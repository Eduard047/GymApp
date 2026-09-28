import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const appRoot = "ios/GymApp-iOS/GymApp";

async function swiftFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async entry => {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) return swiftFiles(entryPath);
    return entry.name.endsWith(".swift") ? [entryPath] : [];
  }));
  return nested.flat().sort();
}

const identifierCharacter = /[A-Za-z0-9_]/;

// Scans Swift source into code tokens and string literals. String literal
// interpolations are scanned recursively, so a quote inside `\( ... )` never
// ends the outer literal and commas inside literals never count as arguments.
function scanSwift(source) {
  const literals = [];
  const codeMask = source.split("");

  function blank(from, to) {
    for (let index = from; index < to; index += 1) {
      if (codeMask[index] !== "\n") codeMask[index] = " ";
    }
  }

  function scanLiteral(start) {
    let index = start;
    let hashes = 0;
    while (source[index] === "#") {
      hashes += 1;
      index += 1;
    }
    const multiline = source.startsWith('"""', index);
    const quote = multiline ? '"""' : '"';
    index += quote.length;
    const closing = quote + "#".repeat(hashes);
    const escape = "\\" + "#".repeat(hashes);
    let text = "";
    const interpolations = [];
    while (index < source.length) {
      if (source.startsWith(closing, index)) {
        index += closing.length;
        break;
      }
      if (source.startsWith(escape, index)) {
        const next = index + escape.length;
        if (source[next] === "(") {
          const end = scanCode(next + 1, ")");
          interpolations.push([next + 1, end - 1]);
          text += "\u0000";
          index = end;
          continue;
        }
        text += source.slice(index, next + 1);
        index = next + 1;
        continue;
      }
      if (!multiline && source[index] === "\n") break;
      text += source[index];
      index += 1;
    }
    literals.push({ start, end: index, text });
    blank(start, index);
    for (const [from, to] of interpolations) {
      for (let position = from; position < to; position += 1) codeMask[position] = source[position];
    }
    return index;
  }

  // Scans code until the matching terminator at depth zero and returns the
  // index just past it (or the end of the source).
  function scanCode(start, terminator) {
    let index = start;
    let depth = 0;
    while (index < source.length) {
      const character = source[index];
      if (source.startsWith("//", index)) {
        const end = source.indexOf("\n", index);
        const stop = end === -1 ? source.length : end;
        blank(index, stop);
        index = stop;
        continue;
      }
      if (source.startsWith("/*", index)) {
        let nesting = 1;
        let position = index + 2;
        while (position < source.length && nesting > 0) {
          if (source.startsWith("/*", position)) {
            nesting += 1;
            position += 2;
          } else if (source.startsWith("*/", position)) {
            nesting -= 1;
            position += 2;
          } else {
            position += 1;
          }
        }
        blank(index, position);
        index = position;
        continue;
      }
      if (character === '"' || (character === "#" && /^#+"/.test(source.slice(index, index + 8)))) {
        index = scanLiteral(index);
        continue;
      }
      if (character === "(" || character === "[" || character === "{") depth += 1;
      if (character === ")" || character === "]" || character === "}") {
        if (depth === 0 && character === terminator) return index + 1;
        depth -= 1;
      }
      index += 1;
    }
    return index;
  }

  scanCode(0, null);
  return { code: codeMask.join(""), literals };
}

// Returns the top-level argument ranges of the call whose "(" is at `open`.
function callArguments(code, open) {
  const argumentsList = [];
  let depth = 0;
  let segmentStart = open + 1;
  for (let index = open; index < code.length; index += 1) {
    const character = code[index];
    if (character === "(" || character === "[" || character === "{") {
      depth += 1;
    } else if (character === ")" || character === "]" || character === "}") {
      depth -= 1;
      if (depth === 0) {
        if (code.slice(segmentStart, index).trim() !== "" || argumentsList.length > 0) {
          argumentsList.push([segmentStart, index]);
        }
        return { argumentsList, end: index + 1 };
      }
    } else if (character === "," && depth === 1) {
      argumentsList.push([segmentStart, index]);
      segmentStart = index + 1;
    }
  }
  return { argumentsList, end: code.length };
}

function lineOf(source, index) {
  return source.slice(0, index).split("\n").length;
}

function findCalls(code, name) {
  const calls = [];
  const pattern = new RegExp(`${name}\\s*\\(`, "g");
  for (const match of code.matchAll(pattern)) {
    const before = code[match.index - 1] ?? "";
    if (identifierCharacter.test(before)) continue;
    const prefix = code.slice(Math.max(0, match.index - 12), match.index);
    if (/func\s+$/.test(prefix)) continue;
    const open = match.index + match[0].length - 1;
    calls.push({ index: match.index, open, ...callArguments(code, open) });
  }
  return calls;
}

// Localization helpers take the English, Ukrainian, and Russian text either
// positionally (gymText, t, text) or by label (en:/uk:/ru:). A literal belongs
// to the language of the innermost helper argument that contains it.
const localizationCallNames = ["gymText", "t", "text", "gymLocalized", "gymPlural", "localized"];
// Arguments of these calls are identifiers, never visible copy.
const machineCallNames = ["accessibilityIdentifier"];
const positionalLanguages = ["en", "uk", "ru"];
const labelLanguages = {
  en: "en", english: "en",
  uk: "uk", ukrainian: "uk",
  ru: "ru", russian: "ru"
};

function localizedArgumentRanges(code) {
  const ranges = [];
  for (const name of localizationCallNames) {
    for (const call of findCalls(code, name)) {
      let position = 0;
      for (const [from, to] of call.argumentsList) {
        const label = code.slice(from, to).match(/^\s*(\w+)\s*:(?!:)/)?.[1];
        let language = "other";
        if (label) {
          language = labelLanguages[label] ?? "other";
        } else {
          language = name === "gymLocalized" ? "en" : (positionalLanguages[position] ?? "other");
          position += 1;
        }
        ranges.push({ from, to, language });
      }
    }
  }
  for (const name of machineCallNames) {
    for (const call of findCalls(code, name)) {
      ranges.push({ from: call.open + 1, to: call.end - 1, language: "machine" });
    }
  }
  return ranges;
}

function literalLanguage(ranges, literal) {
  let innermost = null;
  for (const range of ranges) {
    if (literal.start < range.from || literal.start >= range.to) continue;
    if (!innermost || range.to - range.from < innermost.to - innermost.from) innermost = range;
  }
  return innermost?.language ?? null;
}

const bareUnitPattern = /(^|[^A-Za-z])(kg|reps)(?![A-Za-z])/;

// Machine values rather than visible copy: persisted unit codes, dictionary
// keys, and identifiers compared against stored data.
function isMachineUnitLiteral(text) {
  return /^(kg|reps)$/.test(text);
}

// A plain literal used as a String Catalog key (Text("..."), Button("...")) is
// localized when the catalog translates it into both Ukrainian and Russian.
function isCatalogTranslated(catalog, text) {
  if (text.includes("\u0000")) return false;
  const localizations = catalog?.strings?.[text.replace(/\\"/g, '"')]?.localizations;
  return ["uk", "ru"].every(language => {
    const value = localizations?.[language]?.stringUnit?.value;
    return typeof value === "string" && value !== "" && !bareUnitPattern.test(value);
  });
}

function unitViolations(code, literals, catalog = null) {
  const ranges = localizedArgumentRanges(code);
  return literals.filter(literal => {
    if (!bareUnitPattern.test(literal.text) || isMachineUnitLiteral(literal.text)) return false;
    const language = literalLanguage(ranges, literal);
    if (language === "uk" || language === "ru") return true;
    if (language !== null) return false;
    return !isCatalogTranslated(catalog, literal.text);
  });
}

// English speech samples for the debug voice fixtures: each language has its
// own utterance, so "reps" here is spoken English rather than a unit label.
const allowedEnglishSpeech = new Map([
  ["ios/GymApp-iOS/GymApp/Services/LocalVoiceTranscriptionService.swift", new Set([
    "Bench press, 3 sets of 10 reps, 80 kilograms",
    "Bench press 3 sets of 10 reps 80 kilograms then squat 60 for 12 80 for 10 100 for 8",
    "Mystery lift, 3 sets of 10 reps, 40 kilograms",
    "Press, 3 sets of 10 reps, 40 kilograms"
  ])]
]);

async function scanApp() {
  const files = await swiftFiles(appRoot);
  return Promise.all(files.map(async file => {
    const source = await readFile(file, "utf8");
    return { file, source, ...scanSwift(source) };
  }));
}

const scanned = await scanApp();
const catalog = JSON.parse(await readFile(`${appRoot}/Resources/Localizable.xcstrings`, "utf8"));

test("the scanner tracks parenthesis depth across lines, literals, and interpolation", () => {
  const sample = [
    'let a = gymText(',
    '    "Sets: \\(values.map { "\\($0), x" }.joined(separator: ", "))",',
    '    "Підходи, (так)",',
    '    languageCode: code',
    ')',
    '// gymText("comment", "ignored", languageCode: code)',
    'let b = t("One, two", "Один, два", "Один, два")',
    'func t(_ english: String, _ ukrainian: String) -> String { english }',
    'let c = gymText(#"Raw "quoted", text"#, """',
    '    multi, line',
    '    """, "Три", languageCode: code)'
  ].join("\n");
  const { code } = scanSwift(sample);
  const gymTextCalls = findCalls(code, "gymText");
  assert.deepEqual(gymTextCalls.map(call => call.argumentsList.length), [3, 4]);
  assert.deepEqual(findCalls(code, "t").map(call => call.argumentsList.length), [3]);
  const unitSample = [
    'let x = "\\(w) kg"',
    'let y = t("\\(w) kg", "\\(w) кг", "\\(w) кг")',
    'let z = unit == "kg"',
    'let u = gymText("\\(w) kg", "\\(w) kg", "\\(w) кг", languageCode: code)',
    'let v = localized(code, en: "reps", uk: "повтори", ru: "8 reps")',
    'let w = gymText("A", "\\(w) \\(gymLocalized("kg"))", "\\(w) \\(gymLocalized("kg"))", languageCode: code)'
  ].join("\n");
  const { code: unitCode, literals } = scanSwift(unitSample);
  assert.deepEqual(
    unitViolations(unitCode, literals).map(literal => [lineOf(unitSample, literal.start), literal.text]),
    [[1, "\u0000 kg"], [4, "\u0000 kg"], [5, "8 reps"]]
  );
});

test("iOS app code never uses the two-language gymText or t helpers", () => {
  const violations = [];
  for (const { file, source, code } of scanned) {
    for (const call of findCalls(code, "gymText")) {
      if (call.argumentsList.length !== 4) {
        violations.push(`${file}:${lineOf(source, call.index)} gymText with ${call.argumentsList.length} arguments`);
      }
    }
    for (const call of findCalls(code, "t")) {
      if (call.argumentsList.length === 2) {
        violations.push(`${file}:${lineOf(source, call.index)} t with 2 arguments`);
      }
    }
    for (const match of code.matchAll(/func\s+(?:t|gymText)\s*\(\s*_\s+\w+\s*:\s*String\s*,\s*_\s+\w+\s*:\s*String\s*(?:,\s*languageCode\s*:\s*String\s*)?\)/g)) {
      violations.push(`${file}:${lineOf(source, match.index)} two-language helper definition`);
    }
  }
  assert.deepEqual(violations, []);
});

test("iOS app code shows no bare kg or reps unit outside localization", () => {
  const violations = [];
  for (const { file, source, code, literals } of scanned) {
    const allowed = allowedEnglishSpeech.get(file) ?? new Set();
    for (const literal of unitViolations(code, literals, catalog)) {
      if (allowed.has(literal.text)) continue;
      violations.push(`${file}:${lineOf(source, literal.start)} ${JSON.stringify(literal.text)}`);
    }
  }
  assert.deepEqual(violations, []);
});

test("iOS number and date formatting uses the in-app language locale", () => {
  const violations = [];
  for (const { file, source, code } of scanned) {
    for (const match of code.matchAll(/\.formatted\s*\(/g)) {
      const open = match.index + match[0].length - 1;
      const { end } = callArguments(code, open);
      const argument = source.slice(open + 1, end - 1).trim();
      // A named style (for example `style`) is built with an explicit locale.
      if (/locale/.test(argument) || /^[A-Za-z_]\w*$/.test(argument)) continue;
      violations.push(`${file}:${lineOf(source, match.index)} .formatted(${argument})`);
    }
  }
  assert.deepEqual(violations, []);
});

test("every literal passed to gymLocalized has Ukrainian and Russian catalog values", () => {
  const violations = [];
  for (const { file, source, code } of scanned) {
    for (const call of findCalls(code, "gymLocalized")) {
      if (call.argumentsList.length === 0) continue;
      const argument = source.slice(...call.argumentsList[0]).trim();
      const literal = argument.match(/^"((?:[^"\\]|\\.)*)"$/)?.[1];
      if (literal === undefined || literal.includes("\\(")) continue;
      const localizations = catalog.strings?.[literal.replace(/\\"/g, '"')]?.localizations;
      if (!localizations?.uk || !localizations?.ru) {
        violations.push(`${file}:${lineOf(source, call.index)} ${argument}`);
      }
    }
  }
  assert.deepEqual(violations, []);
});
