import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import plugin from "@markw65/prettier-plugin-monkeyc";

// Analyze each selected device group independently. Only these audited optional
// fields qualify; any read, reflection or ambiguous owner access keeps the field.
// Removing an unused assignment must preserve evaluation of its right-hand side.
const candidates = new Set([
  "activityHr", "hrSource", "gyroAvailable", "gyroScore", "motionNoiseFloor",
  "currentSetStartGarminCalories", "currentSetEndGarminCalories",
  "currentSetLastMotionZoneSeconds", "currentSetLastEvidenceGarminCalories",
  "candidateStartGarminCalories"
]);
const storeCandidates = new Set([
  "lastCloudPlanRevision", "lastCloudPlanId", "stagedCloudPlanRevision",
  "stagedCloudPlanId", "stagedCloudAccountBinding", "stagedCloudSyncMessage"
]);

async function sourceFiles(root) {
  const result = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    const name = path.join(root, entry.name);
    if (entry.isDirectory()) result.push(...await sourceFiles(name));
    else if (entry.name.endsWith(".mc")) result.push(name);
  }
  return result;
}

function walk(node, visit, ancestors = [], owner = null) {
  if (!node?.type) return;
  if (node.type === "ClassDeclaration") owner = node.id.name;
  visit(node, ancestors, owner);
  for (const [key, value] of Object.entries(node)) {
    if (key === "loc" || key === "attrs") continue;
    for (const child of Array.isArray(value) ? value : [value]) {
      if (child && typeof child === "object") walk(child, visit, [...ancestors, node], owner);
    }
  }
}

function isDiscardable(node) {
  if (node.type === "Literal" || node.type === "Identifier") return true;
  if (node.type === "ConditionalExpression") return isDiscardable(node.test) && isDiscardable(node.consequent) && isDiscardable(node.alternate);
  return node.type === "BinaryExpression" && ["==", "!="].includes(node.operator) &&
    isDiscardable(node.left) && isDiscardable(node.right);
}

async function pruneUnusedFields(root, targetOwner, candidates) {
  // An export contains several independent device groups. Analyze each group
  // separately so a larger device retains its actual diagnostics and gyro UI.
  let removed = 0;
  for (const group of await readdir(root, { withFileTypes: true })) {
    if (!group.isDirectory()) continue;
    const sources = await Promise.all((await sourceFiles(path.join(root, group.name))).map(async file => {
      const source = await readFile(file, "utf8");
      return { file, source, ast: plugin.parsers.monkeyc.parse(source), edits: [] };
    }));
    let ambiguousOwner = false;
    let shadowedStorage = false;
    const identifiers = new Set();
    for (const source of sources) walk(source.ast, (node, ancestors, owner) => {
      const parent = ancestors.at(-1);
      if (node.type === "Identifier") identifiers.add(node.name);
      if (["ClassDeclaration", "ModuleDeclaration", "FunctionDeclaration"].includes(node.type) &&
          node.id?.name === "Storage") shadowedStorage = true;
      if (node.type === "Using") {
        const binding = node.as?.name ?? node.id?.property?.name ?? node.id?.name;
        const sdkStorage = node.id?.type === "MemberExpression" && !node.id.computed &&
          node.id.property?.name === "Storage" && node.id.object?.type === "MemberExpression" &&
          !node.id.object.computed && node.id.object.property?.name === "Application" &&
          node.id.object.object?.name === "Toybox";
        if (binding === "Storage" && !sdkStorage) shadowedStorage = true;
      }
      if (node.type === "Identifier" && node.name === "Storage" &&
          (parent?.type === "VariableDeclarator" && parent.id === node ||
           ancestors.some(value => value.type === "FunctionDeclaration" &&
             value.params.some(parameter => parameter.start <= node.start && parameter.end >= node.end)))) {
        shadowedStorage = true;
      }
      if (node.type === "Identifier" && node.name === targetOwner &&
          !(parent?.type === "ClassDeclaration" && parent.id === node) &&
          !(parent?.type === "MemberExpression" && parent.object === node && !parent.computed)) {
        ambiguousOwner = true;
      }
      if (owner === targetOwner && node.type === "Identifier" && node.name === "self" &&
          !(parent?.type === "MemberExpression" && parent.object === node && !parent.computed)) {
        ambiguousOwner = true;
      }
      if (node.type === "MemberExpression" && node.computed &&
          (node.object.name === targetOwner || owner === targetOwner && node.object.name === "self")) {
        ambiguousOwner = true;
      }
    });
    if (ambiguousOwner) continue;
    for (const field of candidates) {
      let declaration = null;
      let read = false;
      const writes = [];
      for (const source of sources) walk(source.ast, (node, ancestors, owner) => {
        const parent = ancestors.at(-1);
        if (node.type === "Literal" && node.value === field) {
          const storageKey = !shadowedStorage && parent?.type === "CallExpression" && parent.arguments[0] === node &&
            parent.callee.type === "MemberExpression" && parent.callee.object.name === "Storage" &&
            ["getValue", "setValue", "deleteValue"].includes(parent.callee.property.name);
          if (!storageKey) read = true;
        }
        if (node.type !== "Identifier" || node.name !== field) return;
        if (parent?.type === "VariableDeclarator" && parent.id === node &&
            owner === targetOwner && !ancestors.some(value => value.type === "FunctionDeclaration")) {
          const statement = ancestors.at(-2);
          if (declaration || statement.declarations.length !== 1 ||
              !statement.attrs?.access?.includes("static") || parent.init?.type !== "Literal") {
            read = true;
          } else declaration = [source, statement];
          return;
        }
        let target = node;
        let assignment = parent;
        let statement = ancestors.at(-2);
        if (parent?.type === "MemberExpression") {
          if (parent.property !== node || parent.computed || parent.object.name !== targetOwner) {
            read = true; return;
          }
          target = parent;
          assignment = ancestors.at(-2);
          statement = ancestors.at(-3);
        } else if (owner !== targetOwner) { read = true; return; }
        if (assignment?.type !== "AssignmentExpression" || assignment.operator !== "=" ||
            assignment.left !== target || statement?.type !== "ExpressionStatement") {
          read = true; return;
        }
        writes.push([source, statement, assignment.right]);
      });
      if (read || !declaration) continue;
      declaration[0].edits.push([declaration[1].start, declaration[1].end, ""]);
      for (const [source, statement, rhs] of writes) {
        // Preserve calls, conversions and their exceptions even when the result
        // is no longer retained in a static field. Avoid user-local name clashes.
        let replacement = "";
        if (!isDiscardable(rhs)) {
          let name = "discardedField_" + statement.start;
          while (identifiers.has(name)) name += "_";
          identifiers.add(name);
          replacement = "var " + name + " = " + source.source.slice(rhs.start, rhs.end) + ";";
        }
        source.edits.push([statement.start, statement.end, replacement]);
      }
      removed += 1;
    }
    for (const { file, source, edits } of sources) {
      if (!edits.length) continue;
      let output = source;
      for (const [start, end, replacement] of edits.sort((a, b) => b[0] - a[0])) {
        output = output.slice(0, start) + replacement + output.slice(end);
      }
      await writeFile(file, output);
    }
  }
  return removed;
}

async function prunePass(root) {
  return await pruneUnusedFields(root, "GymSession", candidates) +
    await pruneUnusedFields(root, "GymStore", storeCandidates);
}

export async function pruneUnusedGarminDiagnostics(root) {
  let total = 0;
  for (;;) {
    const removed = await prunePass(root);
    total += removed;
    if (!removed) return total;
  }
}
