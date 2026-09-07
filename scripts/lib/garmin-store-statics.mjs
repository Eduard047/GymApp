import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import plugin from "@markw65/prettier-plugin-monkeyc";

const checks = new Set([
  "sameOptionalText", "sameOptionalBoolean", "sameTextArray", "sameNumericArray",
  "utf8Bytes", "isBoundedText", "counterToLong", "isValidWeight", "isValidReps",
  "isValidSetInterval", "isValidSetIntervalsList", "areSetIntervalsConsistent",
  "isValidPlannedSetCount", "isValidExactPlannedProgress", "isBoundedNumber",
  "isOptionalBoundedNumber", "isBoundedInteger", "isOptionalBoundedInteger",
  "isNumeric", "containsName"
]);

function walk(node, visit, parent = null, owner = null) {
  if (!node?.type) return;
  if (node.type === "ClassDeclaration") owner = node.id.name;
  visit(node, parent, owner);
  for (const [key, value] of Object.entries(node)) {
    if (key === "loc" || key === "attrs") continue;
    for (const child of Array.isArray(value) ? value : [value]) {
      if (child && typeof child === "object") walk(child, visit, node, owner);
    }
  }
}

async function files(root) {
  const result = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    const file = path.join(root, entry.name);
    if (entry.isDirectory()) result.push(...await files(file));
    else if (entry.name.endsWith(".mc")) result.push(file);
  }
  return result;
}

function replace(source, edits) {
  let previous = source.length;
  for (const [start, end, text] of edits.sort((a, b) => b[0] - a[0])) {
    if (end > previous) throw new Error("Overlapping storage relocation");
    source = source.slice(0, start) + text + source.slice(end);
    previous = start;
  }
  return source;
}

// Run after annotation selection and source optimization. Only oversized full
// profiles move these stateless methods; compact binaries remain byte-identical.
// This satisfies the older SDK's 254-static-member limit without removing checks.
export async function splitGarminStoreStatics(root) {
  let movedGroups = 0;
  for (const group of await readdir(root, { withFileTypes: true })) {
    if (!group.isDirectory()) continue;
    const sources = await Promise.all((await files(path.join(root, group.name))).map(async file => {
      const source = await readFile(file, "utf8");
      return { file, source, ast: plugin.parsers.monkeyc.parse(source) };
    }));
    const store = sources.find(item => item.ast.body.some(node => node.type === "ClassDeclaration" && node.id.name === "GymStore"));
    if (!store) continue;
    const declaration = store.ast.body.find(node => node.type === "ClassDeclaration" && node.id.name === "GymStore");
    const members = declaration.body.body.map(node => node.item);
    const count = members.filter(node => node.attrs?.access?.includes("static"))
      .reduce((sum, node) => sum + (node.declarations?.length ?? 1), 0);
    if (count <= 254) continue;
    const selected = members.filter(node => node.type === "FunctionDeclaration" && checks.has(node.id.name));
    if (selected.length !== checks.size || count - selected.length > 254) {
      throw new Error("Unexpected oversized GymStore layout");
    }
    if (sources.some(item => /\bGymStoreValues\b/.test(item.source))) {
      throw new Error("Storage value module already exists");
    }
    for (const item of sources) {
      const edits = [];
      walk(item.ast, (node, parent, owner) => {
        if (node.type === "Identifier" && node.name === "GymStore" &&
            parent?.type !== "MemberExpression" &&
            !(parent?.type === "ClassDeclaration" && parent.id === node)) {
          throw new Error("Ambiguous storage class reference cannot be relocated");
        }
        if ((node.type === "Literal" && checks.has(node.value)) ||
            (node.type === "UnaryExpression" && node.operator === ":" && checks.has(node.argument?.name))) {
          throw new Error("Reflective storage check cannot be relocated");
        }
        if (node.type === "MemberExpression" && node.object.name === "GymStore" && checks.has(node.property.name)) {
          if (node.computed) throw new Error("Computed storage check cannot be relocated");
          edits.push([node.object.start, node.object.end, "GymStoreValues"]);
        } else if (owner === "GymStore" && node.type === "Identifier" && checks.has(node.name) &&
            parent?.type !== "MemberExpression" && !(parent?.type === "FunctionDeclaration" && parent.id === node)) {
          if (parent?.type !== "CallExpression" || parent.callee !== node) {
            throw new Error("Shadowed storage check cannot be relocated");
          }
          edits.push([node.start, node.end, `GymStoreValues.${node.name}`]);
        }
      });
      item.source = replace(item.source, edits);
    }
    const updated = plugin.parsers.monkeyc.parse(store.source).body.find(node => node.type === "ClassDeclaration" && node.id.name === "GymStore");
    const functions = updated.body.body.map(node => node.item).filter(node => node.type === "FunctionDeclaration" && checks.has(node.id.name));
    const bounds = new Set(["maxWeight", "maxReps", "maxWorkoutSets", "maxPlanSets"]);
    const bodies = functions.map(fn => {
      const edits = [];
      walk(fn, (node, parent) => {
        if (node.type !== "Identifier" || !bounds.has(node.name) || parent?.type === "MemberExpression") return;
        if (parent?.type === "VariableDeclarator" || fn.params.some(p => p.start <= node.start && p.end >= node.end)) {
          throw new Error("Shadowed storage bound cannot be relocated");
        }
        edits.push([node.start - fn.start, node.end - fn.start, `GymStore.${node.name}`]);
      });
      return replace(store.source.slice(fn.start, fn.end), edits).replace(/\bstatic\s+function\b/, "function");
    });
    store.source = replace(store.source, functions.map(node => [node.start, node.end, ""]));
    // Keep the optimized source's imports, which may have qualified SDK aliases.
    const imports = store.source.slice(0, updated.start);
    await writeFile(path.join(path.dirname(store.file), "GymStoreValues.mc"),
      `${imports}\nmodule GymStoreValues {\n${bodies.join("\n")}\n}\n`);
    for (const item of sources) await writeFile(item.file, item.source);
    movedGroups++;
  }
  return movedGroups;
}
