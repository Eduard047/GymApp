#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sourcePath = resolve(repositoryRoot, "shared/exercise-search-vocabulary.json");
const outputPaths = {
  android: resolve(
    repositoryRoot,
    "app/src/main/java/com/example/gymapp/data/catalog/ExerciseSearchVocabulary.generated.kt"
  ),
  ios: resolve(
    repositoryRoot,
    "ios/GymApp-iOS/GymApp/Domain/ExerciseSearchVocabulary.generated.swift"
  ),
  pwa: resolve(repositoryRoot, "pwa/exercise-search-vocabulary.js"),
  pwaVersioned: resolve(repositoryRoot, "pwa/exercise-search-vocabulary.v1.js")
};

const requestedArguments = process.argv.slice(2);
const unknownArguments = requestedArguments.filter(argument => argument !== "--check");
if (unknownArguments.length > 0) {
  throw new Error(`Unknown argument(s): ${unknownArguments.join(", ")}`);
}
const checkOnly = requestedArguments.includes("--check");

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function assertStringArray(value, label, { maximumCount = 128, maximumLength = 128 } = {}) {
  if (!Array.isArray(value) || value.length < 1 || value.length > maximumCount) {
    throw new Error(`${label} must contain between 1 and ${maximumCount} strings`);
  }
  const uniqueValues = new Set();
  for (const entry of value) {
    if (typeof entry !== "string" || entry.trim() !== entry || entry.length < 1 || entry.length > maximumLength) {
      throw new Error(`${label} contains an invalid or unbounded string`);
    }
    if (uniqueValues.has(entry)) {
      throw new Error(`${label} contains duplicate value: ${entry}`);
    }
    uniqueValues.add(entry);
  }
}

function assertVocabularyRecord(value, label, options) {
  if (!isPlainObject(value)) throw new Error(`${label} must be an object`);
  const keys = Object.keys(value);
  if (keys.length < 1 || keys.length > 256) throw new Error(`${label} has an invalid key count`);
  for (const [key, entries] of Object.entries(value)) {
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(key) || key.length > 64) {
      throw new Error(`${label} contains invalid key: ${key}`);
    }
    assertStringArray(entries, `${label}.${key}`, options);
  }
}

function validateVocabulary(value) {
  if (!isPlainObject(value)) throw new Error("Vocabulary root must be an object");
  const expectedFields = [
    "schemaVersion",
    "connectorTokens",
    "aliasesByKey",
    "muscleTermsById",
    "equipmentTermsById",
    "equipmentIdsByKey"
  ];
  const actualFields = Object.keys(value);
  if (actualFields.length !== expectedFields.length || expectedFields.some(field => !actualFields.includes(field))) {
    throw new Error(`Vocabulary must contain exactly: ${expectedFields.join(", ")}`);
  }
  if (value.schemaVersion !== 1) throw new Error("Unsupported exercise-search vocabulary schema version");

  assertStringArray(value.connectorTokens, "connectorTokens", { maximumCount: 64, maximumLength: 16 });
  assertVocabularyRecord(value.aliasesByKey, "aliasesByKey", { maximumCount: 64, maximumLength: 128 });
  assertVocabularyRecord(value.muscleTermsById, "muscleTermsById", { maximumCount: 64, maximumLength: 64 });
  assertVocabularyRecord(value.equipmentTermsById, "equipmentTermsById", { maximumCount: 64, maximumLength: 64 });
  assertVocabularyRecord(value.equipmentIdsByKey, "equipmentIdsByKey", { maximumCount: 8, maximumLength: 64 });

  const knownExerciseKeys = new Set(Object.keys(value.equipmentIdsByKey));
  const knownEquipmentIds = new Set(Object.keys(value.equipmentTermsById));
  for (const key of Object.keys(value.aliasesByKey)) {
    if (!knownExerciseKeys.has(key)) throw new Error(`Alias key has no equipment classification: ${key}`);
  }
  for (const [key, equipmentIds] of Object.entries(value.equipmentIdsByKey)) {
    for (const equipmentId of equipmentIds) {
      if (!knownEquipmentIds.has(equipmentId)) {
        throw new Error(`Unknown equipment ID ${equipmentId} on exercise ${key}`);
      }
    }
  }
}

function sortedEntries(record) {
  return Object.entries(record).sort(([left], [right]) => left.localeCompare(right, "en"));
}

function kotlinString(value) {
  return `"${value
    .replaceAll("\\", "\\\\")
    .replaceAll("\"", "\\\"")
    .replaceAll("\n", "\\n")
    .replaceAll("\r", "\\r")
    .replaceAll("\t", "\\t")
    .replaceAll("$", "\\$")}"`;
}

function swiftString(value) {
  return `"${value
    .replaceAll("\\", "\\\\")
    .replaceAll("\"", "\\\"")
    .replaceAll("\n", "\\n")
    .replaceAll("\r", "\\r")
    .replaceAll("\t", "\\t")}"`;
}

function wrappedItems(values, quote, indent, maximumWidth = 112) {
  const lines = [];
  let current = indent;
  for (const value of values) {
    const item = `${quote(value)},`;
    if (current.trim().length > 0 && current.length + item.length + 1 > maximumWidth) {
      lines.push(current.trimEnd());
      current = indent;
    }
    current += `${item} `;
  }
  if (current.trim().length > 0) lines.push(current.trimEnd());
  return lines.join("\n");
}

function kotlinList(values, indent = "        ") {
  if (values.length <= 3 && values.every(value => kotlinString(value).length < 36)) {
    return `listOf(${values.map(kotlinString).join(", ")})`;
  }
  return `listOf(\n${wrappedItems(values, kotlinString, indent)}\n${indent.slice(0, -4)})`;
}

function kotlinSet(values, indent = "        ") {
  if (values.length <= 3 && values.every(value => kotlinString(value).length < 36)) {
    return `setOf(${values.map(kotlinString).join(", ")})`;
  }
  return `setOf(\n${wrappedItems(values, kotlinString, indent)}\n${indent.slice(0, -4)})`;
}

function kotlinMap(record, collection) {
  return sortedEntries(record).map(([key, values]) => {
    const rendered = collection(values, "            ");
    return `        ${kotlinString(key)} to ${rendered}`;
  }).join(",\n");
}

function renderAndroid(value) {
  return `// GENERATED FILE. DO NOT EDIT.\n// Source: shared/exercise-search-vocabulary.json\npackage com.example.gymapp.data.catalog\n\nobject ExerciseSearchVocabulary {\n    const val schemaVersion: Int = ${value.schemaVersion}\n\n    val connectorTokens: Set<String> = ${kotlinSet(value.connectorTokens, "        ")}\n\n    val aliasesByKey: Map<String, List<String>> = mapOf(\n${kotlinMap(value.aliasesByKey, kotlinList)}\n    )\n\n    val muscleTermsById: Map<String, List<String>> = mapOf(\n${kotlinMap(value.muscleTermsById, kotlinList)}\n    )\n\n    val equipmentTermsById: Map<String, List<String>> = mapOf(\n${kotlinMap(value.equipmentTermsById, kotlinList)}\n    )\n\n    val equipmentIdsByKey: Map<String, Set<String>> = mapOf(\n${kotlinMap(value.equipmentIdsByKey, kotlinSet)}\n    )\n}\n`;
}

function swiftArray(values, indent = "        ") {
  if (values.length <= 3 && values.every(value => swiftString(value).length < 36)) {
    return `[${values.map(swiftString).join(", ")}]`;
  }
  return `[\n${wrappedItems(values, swiftString, indent)}\n${indent.slice(0, -4)}]`;
}

function swiftMap(record) {
  return sortedEntries(record).map(([key, values]) =>
    `        ${swiftString(key)}: ${swiftArray(values, "            ")}`
  ).join(",\n");
}

function renderIos(value) {
  return `// GENERATED FILE. DO NOT EDIT.\n// Source: shared/exercise-search-vocabulary.json\nimport Foundation\n\npublic enum ExerciseSearchVocabulary {\n    public static let schemaVersion = ${value.schemaVersion}\n\n    public static let connectorTokens: Set<String> = Set(${swiftArray(value.connectorTokens, "        ")})\n\n    public static let aliasesByKey: [String: [String]] = [\n${swiftMap(value.aliasesByKey)}\n    ]\n\n    public static let muscleTermsById: [String: [String]] = [\n${swiftMap(value.muscleTermsById)}\n    ]\n\n    public static let equipmentTermsById: [String: [String]] = [\n${swiftMap(value.equipmentTermsById)}\n    ]\n\n    public static let equipmentIdsByKey: [String: [String]] = [\n${swiftMap(value.equipmentIdsByKey)}\n    ]\n}\n`;
}

function sortedRecord(record) {
  return Object.fromEntries(sortedEntries(record));
}

function renderPwa(value) {
  const portableValue = {
    schemaVersion: value.schemaVersion,
    connectorTokens: value.connectorTokens,
    aliasesByKey: sortedRecord(value.aliasesByKey),
    muscleTermsById: sortedRecord(value.muscleTermsById),
    equipmentTermsById: sortedRecord(value.equipmentTermsById),
    equipmentIdsByKey: sortedRecord(value.equipmentIdsByKey)
  };
  return `// GENERATED FILE. DO NOT EDIT.\n// Source: shared/exercise-search-vocabulary.json\n(() => {\n  "use strict";\n\n  const deepFreeze = value => {\n    if (!value || typeof value !== "object" || Object.isFrozen(value)) return value;\n    Object.values(value).forEach(deepFreeze);\n    return Object.freeze(value);\n  };\n\n  globalThis.GymExerciseSearchVocabulary = deepFreeze(${JSON.stringify(portableValue, null, 2)});\n})();\n`;
}

async function writeOrCheck(path, content) {
  if (checkOnly) {
    let current;
    try {
      current = await readFile(path, "utf8");
    } catch {
      throw new Error(`Missing generated file: ${path}`);
    }
    if (current !== content) throw new Error(`Stale generated file: ${path}`);
    return;
  }
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, content, "utf8");
}

const vocabulary = JSON.parse(await readFile(sourcePath, "utf8"));
validateVocabulary(vocabulary);

const androidOutput = renderAndroid(vocabulary);
const iosOutput = renderIos(vocabulary);
const pwaOutput = renderPwa(vocabulary);
await Promise.all([
  writeOrCheck(outputPaths.android, androidOutput),
  writeOrCheck(outputPaths.ios, iosOutput),
  writeOrCheck(outputPaths.pwa, pwaOutput),
  writeOrCheck(outputPaths.pwaVersioned, pwaOutput)
]);

console.log(checkOnly
  ? "Exercise-search vocabulary outputs are up to date."
  : "Generated exercise-search vocabulary for Android, iOS, and PWA.");
