// Plain-text parsers for the Kotlin and Swift exercise tables, shared by the parity tests.
import { readFileSync } from "node:fs";

const ANDROID_CATALOG = "app/src/main/java/com/example/gymapp/data/catalog/BuiltInExerciseCatalog.kt";
const IOS_CATALOG = "ios/GymApp-iOS/GymApp/Domain/BuiltInExerciseCatalog.swift";
const ANDROID_ENGINE = "app/src/main/java/com/example/gymapp/data/repository/WorkoutRecommendationEngine.kt";
const IOS_ENGINE = "ios/GymApp-iOS/GymApp/Domain/RecommendationEngine.swift";
const ANDROID_MUSCLES = "app/src/main/java/com/example/gymapp/data/repository/MuscleMappingEngine.kt";
const IOS_MUSCLES = "ios/GymApp-iOS/GymApp/Domain/MuscleMappingEngine.swift";

const read = path => readFileSync(path, "utf8");

/** Text between the parenthesis opening at `open` and its match, skipping string literals. */
function balanced(source, open) {
  let depth = 0;
  for (let i = open; i < source.length; i += 1) {
    const ch = source[i];
    if (ch === '"') {
      i += 1;
      while (source[i] !== '"') i += source[i] === "\\" ? 2 : 1;
    } else if (ch === "(") {
      depth += 1;
    } else if (ch === ")") {
      depth -= 1;
      if (depth === 0) return source.slice(open + 1, i);
    }
  }
  throw new Error("unbalanced parenthesis");
}

/** Splits at top-level commas, ignoring commas inside strings, parentheses and brackets. */
function splitTopLevel(text) {
  const parts = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (ch === '"') {
      i += 1;
      while (text[i] !== '"') i += text[i] === "\\" ? 2 : 1;
    } else if (ch === "(" || ch === "[") {
      depth += 1;
    } else if (ch === ")" || ch === "]") {
      depth -= 1;
    } else if (ch === "," && depth === 0) {
      parts.push(text.slice(start, i).trim());
      start = i + 1;
    }
  }
  const tail = text.slice(start).trim();
  if (tail) parts.push(tail);
  return parts;
}

const strings = text => [...text.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(match => match[1]);

function definitionCalls(source, callPattern) {
  const calls = [];
  for (const match of source.matchAll(callPattern)) {
    calls.push(splitTopLevel(balanced(source, match.index + match[0].length - 1)));
  }
  return calls;
}

export function parseAndroidCatalog() {
  const source = read(ANDROID_CATALOG);
  const result = {};
  for (const args of definitionCalls(source, /^ {8}definition\(/gm)) {
    const entry = { key: null, nameEn: null, nameUk: null, muscleIds: [], aliases: [], introducedInSeedVersion: 1 };
    const positional = [];
    for (const arg of args) {
      if (arg.startsWith("aliases =")) entry.aliases = strings(arg);
      else if (arg.startsWith("introducedInSeedVersion =")) entry.introducedInSeedVersion = Number(arg.split("=")[1]);
      else positional.push(strings(arg)[0]);
    }
    [entry.key, entry.nameEn, entry.nameUk, ...entry.muscleIds] = positional;
    result[entry.key] = entry;
  }
  return result;
}

export function parseIosCatalog() {
  const source = read(IOS_CATALOG);
  const result = {};
  for (const args of definitionCalls(source, /^ {8}definition\(/gm)) {
    const entry = { key: null, nameEn: null, nameUk: null, muscleIds: [], aliases: [], introducedInSeedVersion: 1 };
    const positional = [];
    for (const arg of args) {
      if (arg.startsWith("aliases:")) entry.aliases = strings(arg);
      else if (arg.startsWith("introducedInSeedVersion:")) entry.introducedInSeedVersion = Number(arg.split(":")[1]);
      else positional.push(arg);
    }
    entry.key = strings(positional[0])[0];
    entry.nameEn = strings(positional[1])[0];
    entry.nameUk = strings(positional[2])[0];
    entry.muscleIds = strings(positional[4]);
    result[entry.key] = entry;
  }
  return result;
}

const lowerFirst = text => text[0].toLowerCase() + text.slice(1);

export function parseAndroidProgramming() {
  const source = read(ANDROID_ENGINE);
  const result = {};
  for (const match of source.matchAll(/^\s*"([a-z0-9_]+)" to programming\(/gm)) {
    const args = balanced(source, match.index + match[0].length - 1);
    result[match[1]] = {
      category: lowerFirst(args.match(/SmartWorkoutFocus\.(\w+)/)[1]),
      role: lowerFirst(args.match(/ExerciseRole\.(\w+)/)[1]),
      loadMode: lowerFirst((args.match(/ExerciseLoadMode\.(\w+)/) || [, "Standard"])[1]),
      patterns: [...args.matchAll(/MovementPattern\.(\w+)/g)].map(m => lowerFirst(m[1]))
    };
  }
  return result;
}

export function parseIosProgramming() {
  const source = read(IOS_ENGINE);
  const result = {};
  for (const match of source.matchAll(/^\s*"([a-z0-9_]+)": \.init\(/gm)) {
    const args = balanced(source, match.index + match[0].length - 1);
    result[match[1]] = {
      category: args.match(/category: \.(\w+)/)[1],
      role: args.match(/role: \.(\w+)/)[1],
      loadMode: (args.match(/loadMode: \.(\w+)/) || [, "standard"])[1],
      patterns: (args.match(/patterns: \[([^\]]*)\]/) || [, ""])[1]
        .split(",").map(item => item.trim().replace(/^\./, "")).filter(Boolean)
    };
  }
  return result;
}

export function parseAndroidExactMuscleMap() {
  const source = read(ANDROID_MUSCLES);
  const result = {};
  for (const match of source.matchAll(/^\s*"([^"]+)" to muscles\((.*)\),?$/gm)) {
    result[match[1]] = Object.fromEntries(
      [...match[2].matchAll(/"(\w+)" to ([\d.]+)/g)].map(item => [item[1], Number(item[2])])
    );
  }
  return result;
}

export function parseIosExactMuscleMap() {
  const source = read(IOS_MUSCLES);
  const result = {};
  for (const match of source.matchAll(/^\s*"([^"]+)": muscles\((.*)\),?$/gm)) {
    result[match[1]] = Object.fromEntries(
      [...match[2].matchAll(/\("(\w+)", ([\d.]+)\)/g)].map(item => [item[1], Number(item[2])])
    );
  }
  return result;
}
