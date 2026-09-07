import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import plugin from "@markw65/prettier-plugin-monkeyc";

// Run after device annotation selection. The compact renderer does not read
// these optional diagnostics. A read anywhere (including tests or reflection)
// keeps the field; this pass never touches recording, detection or stored state.
const candidates = new Set([
  "activityHr", "hrSource", "gyroAvailable", "gyroScore", "motionNoiseFloor",
  "currentSetLastMotionZoneSeconds"
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

export async function pruneUnusedGarminDiagnostics(root) {
  // An export contains several independent device groups. Analyze each group
  // separately so a larger device retains its actual diagnostics and gyro UI.
  let removed = 0;
  for (const group of await readdir(root, { withFileTypes: true })) {
    if (!group.isDirectory()) continue;
    const sources = await Promise.all((await sourceFiles(path.join(root, group.name))).map(async file => {
      const source = await readFile(file, "utf8");
      return { file, source, ast: plugin.parsers.monkeyc.parse(source), edits: [] };
    }));
    let shadowedClass = false;
    for (const source of sources) walk(source.ast, (node, ancestors) => {
      if (node.type === "Identifier" && node.name === "GymSession" &&
          ancestors.some(value => value.type === "FunctionDeclaration") &&
          (ancestors.at(-1)?.type === "VariableDeclarator" ||
            ancestors.some(value => value.type === "FunctionDeclaration" &&
              value.params.some(parameter => parameter.start <= node.start && parameter.end >= node.end)))) {
        shadowedClass = true;
      }
    });
    if (shadowedClass) continue;
    for (const field of candidates) {
      let declaration = null;
      let read = false;
      const writes = [];
      for (const source of sources) walk(source.ast, (node, ancestors, owner) => {
        const parent = ancestors.at(-1);
        if (node.type === "Literal" && node.value === field) read = true;
        if (node.type !== "Identifier" || node.name !== field) return;
        if (parent?.type === "VariableDeclarator" && parent.id === node &&
            owner === "GymSession" && !ancestors.some(value => value.type === "FunctionDeclaration")) {
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
          if (parent.property !== node || parent.computed || parent.object.name !== "GymSession") {
            read = true; return;
          }
          target = parent;
          assignment = ancestors.at(-2);
          statement = ancestors.at(-3);
        } else if (owner !== "GymSession") { read = true; return; }
        if (assignment?.type !== "AssignmentExpression" || assignment.operator !== "=" ||
            assignment.left !== target || statement?.type !== "ExpressionStatement") {
          read = true; return;
        }
        writes.push([source, statement, assignment.right]);
      });
      if (read || !declaration || writes.some(([, , rhs]) =>
          rhs.type !== "Literal" && rhs.type !== "Identifier")) continue;
      declaration[0].edits.push([declaration[1].start, declaration[1].end, ""]);
      for (const [source, statement] of writes) {
        // Only literal/identifier writes qualify. Calls, getters and potentially
        // throwing conversions keep both the field and its original evaluation.
        source.edits.push([statement.start, statement.end, ""]);
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
