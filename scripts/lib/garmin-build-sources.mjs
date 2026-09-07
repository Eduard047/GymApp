import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import plugin from "@markw65/prettier-plugin-monkeyc";

// Dictionary indexing uses smaller native instructions than a method call.
// Keep polymorphic live-set reads intact: GymRecordedSet is not a Dictionary.
const dictionaryReceivers = new Set([
  "phoneFence", "cloudFence", "message", "safeMessage", "postCommitPlanItem",
  "stage", "snapshot", "value", "left", "right", "statistics", "queuedItem",
  "preparedItem"
]);
const dictionaryFunctions = new Set([
  "planItemForExerciseAfterCompleted", "applyPlanItem", "remainingPlannedSetsForExercise",
  "plannedSetsForExercise", "selectNextPlanSlotInGlobalOrder", "syncPlanMatchesCurrentState",
  "copyOptionalAccountBinding", "removePendingByRequestId", "rotatePairingGenerationForPending",
  "recoverQueuedWorkout", "pendingMatchesStagedPairing", "isValidPendingList",
  "isValidLegacyPendingList", "copyOptionalLegacyMetric", "canQueueWorkout"
]);

function walk(node, visit, parent = null, fn = null) {
  if (!node?.type) return;
  if (node.type === "FunctionDeclaration") fn = node.id.name;
  visit(node, parent, fn);
  for (const [key, value] of Object.entries(node)) {
    if (key === "loc" || key === "attrs") continue;
    if (Array.isArray(value)) value.forEach(child => walk(child, visit, node, fn));
    else if (value && typeof value === "object") walk(value, visit, node, fn);
  }
}

function replaceRanges(source, edits) {
  edits.sort((a, b) => b[0] - a[0]);
  let previous = source.length;
  for (const [start, end, replacement] of edits) {
    if (end > previous) throw new Error("Overlapping Garmin source replacements");
    source = source.slice(0, start) + replacement + source.slice(end);
    previous = start;
  }
  return source;
}

const escapeXml = value => value.replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;").replaceAll(">", "&gt;");

export async function prepareGarminSources(root) {
  const sourceRoot = path.join(root, "source");
  const stringsPath = path.join(root, "resources", "strings.xml");
  let originalStrings = null;
  try { originalStrings = await readFile(stringsPath, "utf8"); }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  const bucketCount = 16;
  const exerciseRows = Array.from({ length: bucketCount }, () => []);
  const seenExerciseShards = new Set();
  let exerciseChunks = 0;
  const decodeXml = value => value.replace(/&(#x[0-9a-f]+|#[0-9]+|amp|lt|gt|quot|apos);/gi,
    (_, key) => key[0] === "#" ? String.fromCodePoint(key[1].toLowerCase() === "x" ?
      parseInt(key.slice(2), 16) : parseInt(key.slice(1), 10)) :
      ({ amp: "&", lt: "<", gt: ">", quot: '\"', apos: "'" })[key.toLowerCase()]);
  const withoutExerciseStrings = originalStrings?.replace(
    /<string id="ExerciseLabels([0-9]{2})">([\s\S]*?)<\/string>/g,
    (_, suffix, encoded) => {
      const index = Number(suffix);
      const decoded = decodeXml(encoded);
      if (index >= 16 || seenExerciseShards.has(index) || !decoded.startsWith("~")) {
        throw new Error("Invalid exercise resource shard");
      }
      seenExerciseShards.add(index);
      for (const row of decoded.slice(1).split("~")) {
        const values = row.split("|");
        if (values.length !== 3) throw new Error("Invalid exercise resource row");
        const bucket = [...Buffer.from(values[0])].reduce((sum, value) =>
          (sum + value) % bucketCount, 0);
        exerciseRows[bucket].push("e" + row);
      }
      exerciseChunks += 1;
      return "";
    });
  if (exerciseChunks !== 0 && exerciseChunks !== 16) {
    throw new Error("Incomplete exercise resource pool");
  }
  const mergedExercises = exerciseChunks === 16;

  const files = (await readdir(sourceRoot)).filter(name =>
    name.endsWith(".mc") && !name.endsWith("Tests.mc")).sort();
  const sources = new Map();
  const phrases = new Map();
  // The recording render path loads only one locale, keeping its transient
  // text allocation below the merged catalog/translation shards.
  const hotFunctions = new Set(["onUpdate", "drawTinyDashboard", "dashboardStatusText", "confidenceLabel", "workoutErrorText", "effortLabel", "setSummaryText", "drawEntry", "drawSettings", "drawDebug", "drawSetSavedOverlay", "statusLabel"]);
  for (const file of files) {
    const source = await readFile(path.join(sourceRoot, file), "utf8");
    const ast = plugin.parsers.monkeyc.parse(source);
    const calls = [];
    const edits = [];
    const localNames = new Map();
    walk(ast, (node, parent, fn) => {
      if (!fn) return;
      if (!localNames.has(fn)) localNames.set(fn, new Set());
      if (node.type === "VariableDeclarator") localNames.get(fn).add(node.id.name);
      if (node.type === "FunctionDeclaration") {
        for (const parameter of node.params ?? []) {
          walk(parameter, part => {
            if (part.type === "Identifier") localNames.get(fn).add(part.name);
          });
        }
      }
    });
    walk(ast, (node, parent, fn) => {
      if (mergedExercises && file === "GymStore.mc" && fn === "exerciseLabelShard" &&
          node.type === "Literal" && node.value === 16 && parent?.operator === "%") {
        edits.push([node.start, node.end, String(bucketCount)]);
      }
      if (mergedExercises && file === "GymStore.mc" && fn === "localizedExerciseName") {
        if (node.type === "VariableDeclarator" && node.id.name === "shards") {
          if (parent.type !== "VariableDeclaration" || parent.declarations.length !== 1) {
            throw new Error("Unexpected exercise resource declaration");
          }
          edits.push([parent.start, parent.end, ""]);
        } else if (node.type === "AssignmentExpression" && node.left.name === "shards" &&
            parent.type === "ExpressionStatement") {
          edits.push([parent.start, parent.end, ""]);
        } else if (node.type === "CallExpression" && node.callee.property?.name === "loadResource") {
          edits.push([node.start, node.end, "GymText.resource(shard)"]);
        } else if (node.type === "BinaryExpression" && node.operator === "+" &&
            node.left.type === "Literal" && node.left.value === "~" && node.right.name === "name") {
          edits.push([node.left.start, node.left.end, '\"~e\"']);
        }
      }
      if (node.type !== "CallExpression") return;
      const member = node.callee.type === "MemberExpression";
      const name = member ? node.callee.property.name : node.callee.name;
      const receiver = member ? node.callee.object : null;
      // These state fields are null or validated Strings. All consuming paths
      // retain their binding/type guards; String.toString() adds no conversion.
      if (name === "toString" && node.arguments.length === 0 &&
          ((file === "GymStore.mc" && receiver?.type === "Identifier" &&
              !localNames.get(fn)?.has(receiver.name)) ||
            (receiver?.type === "MemberExpression" && receiver.object.name === "GymStore" &&
              !localNames.get(fn)?.has("GymStore"))) &&
          ["accountBinding", "stateOwnerBinding", "deviceBinding", "pairingGeneration"]
            .includes(receiver.type === "Identifier" ? receiver.name : receiver.property.name)) {
        edits.push([receiver.end, node.end, ""]);
      } else if (name === "tr" && node.arguments.length === 3 &&
          node.arguments.every(arg => arg.type === "Literal" && typeof arg.value === "string")) {
        const values = node.arguments.map(arg => arg.value);
        // Delimiters are never interpreted when the original UI copy contains them.
        if (values.some(value => /[~|]/.test(value))) return;
        const key = JSON.stringify(values);
        if (!phrases.has(key)) phrases.set(key, { values });
        if (file === "WorkoutView.mc" && hotFunctions.has(fn)) phrases.get(key).hot = true;
        calls.push([node.start, node.end, key]);
      } else if (member && name === "get" && node.arguments.length === 1) {
        const object = node.callee.object;
        const dictionary = dictionaryReceivers.has(object.name) ||
          (file === "GymStore.mc" && dictionaryFunctions.has(fn)) ||
          file === "GymComm.mc" || file === "GymWorkoutMode.mc";
        if (dictionary) {
          edits.push([object.end, node.arguments[0].start, "["],
            [node.arguments[0].end, node.end, "]"]);
        } else if (file === "GymStore.mc" && fn === "migrateFullLegacyQuarantineToCompact") {
          // The whole legacy set list was validated as Dictionaries before this read.
          // Make that type explicit for the SDK's overloaded container analysis.
          edits.push([object.start, object.start, "("],
            [object.end, node.arguments[0].start, " as Lang.Dictionary)["],
            [node.arguments[0].end, node.end, "]"]);
        }
      } else if (member && name === "put" && node.arguments.length === 2 &&
          parent.type === "ExpressionStatement") {
        edits.push([node.callee.object.end, node.arguments[0].start, "["],
          [node.arguments[0].end, node.arguments[1].start, "] = "],
          [node.arguments[1].end, node.end, ""]);
      }
    });
    sources.set(file, { source, calls, edits });
  }

  // Share resource handles between UI text and exercise labels. The separate
  // row prefixes prevent a custom exercise name from matching a UI phrase.
  // Bound decoded-string peaks on legacy VMs instead of loading whole catalogs.
  // Framing preserves leading and trailing whitespace in native resources.
  const buckets = exerciseRows.map(rows => ({ rows: [...rows], uiCount: 0,
    bytes: rows.reduce((sum, row) => sum + Buffer.byteLength(row) + 1, 0) }));
  const hotPhrases = [...phrases.values()].filter(phrase => phrase.hot);
  const hotGroups = [{ phrases: [], bytes: [2, 2, 2] }];
  for (const phrase of hotPhrases) {
    let group = hotGroups.at(-1);
    const costs = phrase.values.map(value => 8 + Buffer.byteLength(value));
    if (costs.some(cost => cost >= 96)) throw new Error("Garmin live label exceeds 96 bytes");
    if (costs.some((cost, language) => group.bytes[language] + cost > 600)) {
      group = { phrases: [], bytes: [2, 2, 2] };
      hotGroups.push(group);
    }
    phrase.id = 2048 + (hotGroups.length - 1) * 256 + group.phrases.length;
    group.phrases.push(phrase);
    costs.forEach((cost, language) => { group.bytes[language] += cost; });
  }
  for (const phrase of [...phrases.values()].filter(phrase => !phrase.hot).sort((a, b) =>
    Buffer.byteLength(b.values.join("|")) - Buffer.byteLength(a.values.join("|")))) {
    const bucket = buckets.reduce((left, right) => left.bytes <= right.bytes ? left : right);
    phrase.id = buckets.indexOf(bucket) + bucket.uiCount++ * bucketCount;
    const row = `u${phrase.id}|${phrase.values.join("|")}`;
    bucket.rows.push(row);
    bucket.bytes += Buffer.byteLength(row) + 1;
  }
  if (buckets.some(bucket => bucket.bytes + 1 > 800)) {
    throw new Error("Garmin UI resource bucket exceeds the verified 800-byte bound: " + buckets.map(bucket => bucket.bytes + 1).join(", "));
  }
  if (buckets.some(bucket => bucket.rows.some(row => Buffer.byteLength(row) >= 192))) {
    throw new Error("Garmin translation row exceeds the 192-byte extraction window");
  }
  if (mergedExercises) await writeFile(stringsPath, withoutExerciseStrings);
  for (const [file, { source, calls, edits }] of sources) {
    for (const [start, end, key] of calls) {
      edits.push([start, end, `GymText.get(${phrases.get(key).id})`]);
    }
    await writeFile(path.join(sourceRoot, file), replaceRanges(source, edits));
  }
  const resources = buckets.map((bucket, index) =>
    `    <string id="UiText${index}">${escapeXml(`~${bucket.rows.join("~")}~`)}</string>`);
  const hotRefs = [];
  for (const [groupIndex, group] of hotGroups.entries()) {
    for (let language = 0; language < 3; language += 1) {
      const index = groupIndex * 3 + language;
      const packed = `~${group.phrases.map(phrase => `u${phrase.id}|${phrase.values[language]}`).join("~")}~`;
      if (Buffer.byteLength(packed) > 600) throw new Error("Garmin live resource exceeds 600 bytes");
      hotRefs.push(`Rez.Strings.UiHot${index}`);
      resources.push(`    <string id="UiHot${index}">${escapeXml(packed)}</string>`);
    }
  }
  await writeFile(path.join(root, "resources", "ui-text.xml"),
    `<strings>\n${resources.join("\n")}\n</strings>\n`);
  await writeFile(path.join(sourceRoot, "GymText.mc"), `using Toybox.Application;
class GymText {
    static function resource(bucket) {
        if (bucket >= ${bucketCount}) {
            var hotRefs = [${hotRefs.join(", ")}];
            return Application.loadResource(hotRefs[bucket - ${bucketCount}]);
        }
        var refs = [${buckets.map((_, index) => `Rez.Strings.UiText${index}`).join(", ")}];
        var packed = Application.loadResource(refs[bucket]);
        refs = null;
        return packed;
    }
    static function get(id) {
        var marker = "~u" + id.toString() + "|";
        var packed = resource(id >= 2048 ? ${bucketCount} + ((id - 2048) / 256).toNumber() * 3 + (GymStore.isUk() ? 1 : (GymStore.isRu() ? 2 : 0)) : id % ${bucketCount});
        var start = packed.find(marker);
        if (start == null) { return ""; }
        start += marker.length();
        var end = start + (id >= 2048 ? 96 : 192);
        if (end > packed.length()) { end = packed.length(); }
        var row = packed.substring(start, end);
        packed = null;
        if (row == null) { return ""; }
        row = row.substring(0, row.find("~"));
        if (id >= 2048) { return row; }
        var first = row.find("|");
        if (!GymStore.isUk() && !GymStore.isRu()) { return row.substring(0, first); }
        var tail = row.substring(first + 1, null);
        row = null;
        var second = tail.find("|");
        return GymStore.isRu() ? tail.substring(second + 1, null) : tail.substring(0, second);
    }
}
`);
  return [...phrases.values()];
}
