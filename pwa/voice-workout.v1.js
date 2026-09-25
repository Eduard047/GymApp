(function voiceWorkoutModule(root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.GymVoiceWorkout = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function buildVoiceWorkout() {
  "use strict";

  // Mirrors shared/voice-workout-v1.json. Android and iOS implement the same
  // tables and algorithm; tests/voice-workout-parity.test.mjs keeps them aligned.
  const LIMITS = Object.freeze({
    maxTranscriptBytes: 8192,
    maxBlocks: 100,
    maxSetsPerBlock: 100,
    maxWeight: 1000000,
    maxReps: 10000
  });
  const LOCALES = Object.freeze({ en: "en-US", uk: "uk-UA", ru: "ru-RU" });
  const CONTAINS_MATCH_MINIMUM_LENGTH = 8;

  const SEPARATOR_PHRASES = Object.freeze([
    "и потом", "а потом", "после этого", "потом", "затем", "далее", "дальше",
    "після цього", "потім", "далі",
    "and then", "after that", "then", "next"
  ]);
  const SET_WORDS = Object.freeze([
    "подход", "подхода", "подходов", "подходы",
    "підхід", "підходи", "підходів", "підхода",
    "set", "sets"
  ]);
  const REP_WORDS = Object.freeze([
    "повтор", "повтора", "повторов", "повторы", "повторение", "повторения", "повторений", "раз", "раза",
    "повтори", "повторів", "повторення", "повторень", "рази", "разів",
    "rep", "reps", "repetition", "repetitions", "times"
  ]);
  const WEIGHT_WORDS = Object.freeze([
    "кг", "кило", "килограмм", "килограмма", "килограммов", "килограм",
    "кілограм", "кілограми", "кілограмів", "кілограма", "кіло",
    "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms", "kilogramme", "kilogrammes"
  ]);
  const WEIGHT_PREFIX_WORDS = Object.freeze(["вес", "весом", "веса", "вага", "вагою", "ваги", "weight", "weighing"]);
  const CONNECTOR_WORDS = Object.freeze([
    "по", "на", "x", "х", "×", "с", "со", "з", "зі", "із", "и", "і", "й", "та", "а", "без", "каждый", "кожен",
    "for", "of", "by", "with", "at", "and", "each", "bodyweight"
  ]);
  const NUMBER_WORDS = Object.freeze({
    units: Object.freeze({
      "ноль": 0, "один": 1, "одна": 1, "одно": 1, "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5,
      "шесть": 6, "семь": 7, "восемь": 8, "девять": 9,
      "нуль": 0, "одне": 1, "дві": 2, "чотири": 4, "п'ять": 5, "шість": 6, "сім": 7, "вісім": 8, "дев'ять": 9,
      "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9
    }),
    teens: Object.freeze({
      "десять": 10, "одиннадцать": 11, "двенадцать": 12, "тринадцать": 13, "четырнадцать": 14,
      "пятнадцать": 15, "шестнадцать": 16, "семнадцать": 17, "восемнадцать": 18, "девятнадцать": 19,
      "одинадцять": 11, "дванадцять": 12, "тринадцять": 13, "чотирнадцять": 14, "п'ятнадцять": 15,
      "шістнадцять": 16, "сімнадцять": 17, "вісімнадцять": 18, "дев'ятнадцять": 19,
      "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
      "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19
    }),
    tens: Object.freeze({
      "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50, "шестьдесят": 60,
      "семьдесят": 70, "восемьдесят": 80, "девяносто": 90,
      "двадцять": 20, "тридцять": 30, "п'ятдесят": 50, "шістдесят": 60, "сімдесят": 70,
      "вісімдесят": 80, "дев'яносто": 90,
      "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    }),
    hundreds: Object.freeze({
      "сто": 100, "двести": 200, "триста": 300, "четыреста": 400, "пятьсот": 500,
      "двісті": 200, "чотириста": 400, "п'ятсот": 500
    }),
    hundredMultipliers: Object.freeze(["hundred"])
  });
  const VOICE_ALIASES = Object.freeze({
    bench_press: ["жим лежа", "жим лежачи", "жим штанги лежа", "жим штанги лежачи", "bench"],
    squat: ["присед", "присед со штангой", "приседания", "приседания со штангой", "присідання", "присідання зі штангою", "присід", "barbell squat", "back squat", "squats"],
    pull_up: ["подтягивания", "подтягивание", "підтягування", "pull ups", "pullups", "chin ups"],
    push_up: ["отжимания", "отжимания от пола", "віджимання", "віджимання від підлоги", "push ups", "pushups"],
    dips: ["брусья", "отжимания на брусьях", "бруси", "віджимання на брусах"],
    deadlift: ["становая", "становая тяга", "станова", "станова тяга"],
    romanian_deadlift: ["румынская тяга", "румунська тяга", "rdl"],
    leg_press: ["жим ногами", "жим ногами в тренажере", "жим ногами у тренажері"],
    lat_pulldown: ["тяга верхнего блока", "тяга верхнього блока", "вертикальная тяга"],
    barbell_row: ["тяга штанги в наклоне", "тяга штанги в нахилі"],
    shoulder_press: ["жим над головой", "армейский жим", "жим над головою", "армійський жим", "overhead press"],
    biceps_curl: ["подъем на бицепс", "бицепс", "біцепс", "curls"],
    lunge: ["выпады", "випади", "lunges"],
    plank: ["планка"],
    calf_raise: ["подъем на носки", "підйом на носки", "calf raises"],
    lateral_raise: ["махи в стороны", "махи гантелями в стороны", "розведення в сторони", "lateral raises"]
  });

  const setWordSet = new Set(SET_WORDS);
  const repWordSet = new Set(REP_WORDS);
  const weightWordSet = new Set(WEIGHT_WORDS);
  const weightPrefixSet = new Set(WEIGHT_PREFIX_WORDS);
  const connectorSet = new Set(CONNECTOR_WORDS);
  const separatorTokens = SEPARATOR_PHRASES
    .map((phrase) => phrase.split(" "))
    .sort((left, right) => right.length - left.length);

  const LETTER = /\p{L}/u;
  const DIGIT = /[0-9]/;

  function normalizeWord(value) {
    return String(value)
      .toLowerCase()
      .replace(/ё/g, "е")
      .replace(/[’ʼ`]/g, "'");
  }

  // Name identity used for matching: lower-case, ё→е, unified apostrophes,
  // every other non letter/digit/apostrophe becomes one separating space.
  function normalizeName(value) {
    const lowered = normalizeWord(String(value).normalize("NFC"));
    let result = "";
    let pendingSpace = false;
    for (const character of lowered) {
      if (LETTER.test(character) || DIGIT.test(character) || character === "'") {
        if (pendingSpace && result) result += " ";
        pendingSpace = false;
        result += character;
      } else {
        pendingSpace = true;
      }
    }
    return result;
  }

  function utf8Length(value) {
    let bytes = 0;
    for (const character of String(value)) {
      const code = character.codePointAt(0);
      bytes += code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
    }
    return bytes;
  }

  function truncateUtf8(value, maxBytes = LIMITS.maxTranscriptBytes) {
    let bytes = 0;
    let result = "";
    for (const character of String(value)) {
      const code = character.codePointAt(0);
      const size = code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
      if (bytes + size > maxBytes) break;
      bytes += size;
      result += character;
    }
    return result;
  }

  // Tokens: {type:"word", raw, norm} | {type:"number", value} | {type:"break"}.
  function tokenize(transcript) {
    const characters = Array.from(String(transcript).normalize("NFC"));
    const tokens = [];
    let index = 0;
    const isWordChar = (character) => character !== undefined &&
      (LETTER.test(character) || character === "'" || character === "’" || character === "ʼ" || character === "`");
    while (index < characters.length) {
      const character = characters[index];
      const previous = characters[index - 1];
      const next = characters[index + 1];
      if (DIGIT.test(character) || (character === "-" && DIGIT.test(next ?? "") && !DIGIT.test(previous ?? ""))) {
        let text = character;
        index += 1;
        while (index < characters.length && DIGIT.test(characters[index])) text += characters[index++];
        if ((characters[index] === "." || characters[index] === ",") && DIGIT.test(characters[index + 1] ?? "")) {
          text += ".";
          index += 1;
          while (index < characters.length && DIGIT.test(characters[index])) text += characters[index++];
        }
        tokens.push({ type: "number", value: Number(text) });
        continue;
      }
      if (character === "×") {
        tokens.push({ type: "word", raw: character, norm: character });
        index += 1;
        continue;
      }
      if (LETTER.test(character)) {
        let raw = character;
        index += 1;
        while (index < characters.length && isWordChar(characters[index])) raw += characters[index++];
        const trimmed = raw.replace(/['’ʼ`]+$/u, "");
        tokens.push({ type: "word", raw: trimmed, norm: normalizeWord(trimmed) });
        continue;
      }
      if (character === ";" || character === "\n" || character === "\r" || character === "." ||
          character === "!" || character === "?") {
        tokens.push({ type: "break" });
      }
      index += 1;
    }
    return combineNumberWords(tokens);
  }

  function numberWordClass(norm) {
    if (Object.prototype.hasOwnProperty.call(NUMBER_WORDS.hundreds, norm)) return ["h", NUMBER_WORDS.hundreds[norm]];
    if (Object.prototype.hasOwnProperty.call(NUMBER_WORDS.tens, norm)) return ["t", NUMBER_WORDS.tens[norm]];
    if (Object.prototype.hasOwnProperty.call(NUMBER_WORDS.teens, norm)) return ["e", NUMBER_WORDS.teens[norm]];
    if (Object.prototype.hasOwnProperty.call(NUMBER_WORDS.units, norm)) return ["u", NUMBER_WORDS.units[norm]];
    if (NUMBER_WORDS.hundredMultipliers.includes(norm)) return ["m", 100];
    return null;
  }

  // Spoken compound numbers: [hundreds] [tens] [unit|teen]; English
  // "<unit> hundred" multiplies. Anything that does not continue the
  // current number starts a new one.
  function combineNumberWords(tokens) {
    const result = [];
    let total = null;
    let allowed = null;
    const flush = () => {
      if (total !== null) result.push({ type: "number", value: total });
      total = null;
      allowed = null;
    };
    for (const token of tokens) {
      const info = token.type === "word" ? numberWordClass(token.norm) : null;
      if (!info) {
        flush();
        result.push(token);
        continue;
      }
      const [kind, value] = info;
      if (total !== null && allowed.includes(kind)) {
        if (kind === "m") {
          total *= 100;
          allowed = ["t", "e", "u"];
        } else {
          total += value;
          allowed = kind === "h" ? ["t", "e", "u"] : kind === "t" ? ["u"] : kind === "u" && total < 10 ? ["m"] : [];
        }
        continue;
      }
      flush();
      if (kind === "m") {
        result.push(token);
        continue;
      }
      total = value;
      allowed = kind === "h" ? ["t", "e", "u"] : kind === "t" ? ["u"] : kind === "u" ? ["m"] : [];
    }
    flush();
    return result;
  }

  function isMetadataWord(norm) {
    return connectorSet.has(norm) || setWordSet.has(norm) || repWordSet.has(norm) ||
      weightWordSet.has(norm) || weightPrefixSet.has(norm);
  }

  function separatorLength(tokens, index) {
    for (const phrase of separatorTokens) {
      let matches = true;
      for (let offset = 0; offset < phrase.length; offset += 1) {
        const token = tokens[index + offset];
        if (!token || token.type !== "word" || token.norm !== phrase[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) return phrase.length;
    }
    return 0;
  }

  function segment(tokens) {
    const segments = [];
    let current = [];
    let seenNumber = false;
    const close = () => {
      if (current.some((token) => token.type === "number" || (token.type === "word" && !isMetadataWord(token.norm)))) {
        segments.push(current);
      }
      current = [];
      seenNumber = false;
    };
    for (let index = 0; index < tokens.length; index += 1) {
      const token = tokens[index];
      if (token.type === "break") {
        close();
        continue;
      }
      const separator = separatorLength(tokens, index);
      if (separator > 0) {
        close();
        index += separator - 1;
        continue;
      }
      if (token.type === "word" && seenNumber && !isMetadataWord(token.norm)) close();
      if (token.type === "number") seenNumber = true;
      current.push(token);
    }
    close();
    return segments;
  }

  function spokenName(tokens) {
    const firstNumber = tokens.findIndex((token) => token.type === "number");
    let words = (firstNumber === -1 ? tokens : tokens.slice(0, firstNumber)).filter((token) => token.type === "word");
    while (words.length && isMetadataWord(words[0].norm)) words = words.slice(1);
    while (words.length && isMetadataWord(words[words.length - 1].norm)) words = words.slice(0, -1);
    return words.map((token) => token.raw).join(" ");
  }

  function candidateAliases(exercise) {
    const aliases = [exercise.name, ...(Array.isArray(exercise.aliases) ? exercise.aliases : [])];
    const key = exercise.catalogKey;
    if (key && Object.prototype.hasOwnProperty.call(VOICE_ALIASES, key)) aliases.push(...VOICE_ALIASES[key]);
    return aliases.map(normalizeName).filter(Boolean);
  }

  function matchExercise(name, candidates) {
    const normalized = normalizeName(name);
    if (!normalized) return { match: "unresolved", candidates: [] };
    const padded = ` ${normalized} `;
    const exact = [];
    const contained = [];
    let bestScore = 0;
    for (const candidate of candidates) {
      if (candidate.aliases.includes(normalized)) {
        exact.push(candidate);
        continue;
      }
      let score = 0;
      for (const alias of candidate.aliases) {
        if (alias.length >= CONTAINS_MATCH_MINIMUM_LENGTH && padded.includes(` ${alias} `)) {
          score = Math.max(score, alias.length);
        }
      }
      if (score > 0) {
        contained.push({ candidate, score });
        bestScore = Math.max(bestScore, score);
      }
    }
    const chosen = exact.length ? exact : contained.filter((entry) => entry.score === bestScore).map((entry) => entry.candidate);
    const seen = new Set();
    const unique = chosen.filter((candidate) => !seen.has(candidate.id) && seen.add(candidate.id));
    if (unique.length === 1) return { match: "resolved", candidates: unique };
    if (unique.length > 1) return { match: "ambiguous", candidates: unique };
    return { match: "unresolved", candidates: [] };
  }

  function validWeight(value) {
    return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= LIMITS.maxWeight;
  }

  function validReps(value) {
    return Number.isInteger(value) && value >= 1 && value <= LIMITS.maxReps;
  }

  function isValidSet(set) {
    return validWeight(set.weight) && validReps(set.reps);
  }

  function repsValue(raw, flags) {
    if (raw === null) return null;
    if (!Number.isInteger(raw)) {
      flags.invalid = true;
      return null;
    }
    return raw;
  }

  function parseValues(tokens) {
    const flags = { invalid: false };
    const numbers = [];
    for (let index = 0; index < tokens.length; index += 1) {
      const token = tokens[index];
      if (token.type !== "number") continue;
      const next = tokens[index + 1];
      const previous = tokens[index - 1];
      let tag = null;
      if (next && next.type === "word") {
        if (setWordSet.has(next.norm)) tag = "set";
        else if (repWordSet.has(next.norm)) tag = "rep";
        else if (weightWordSet.has(next.norm)) tag = "weight";
      }
      if (!tag && previous && previous.type === "word" && weightPrefixSet.has(previous.norm)) tag = "weight";
      numbers.push({ value: token.value, tag });
    }
    if (!numbers.length) return { sets: [{ weight: null, reps: null }], flags };

    const setEntry = numbers.find((entry) => entry.tag === "set");
    if (setEntry) {
      let reps = numbers.find((entry) => entry.tag === "rep")?.value ?? null;
      let weight = numbers.find((entry) => entry.tag === "weight")?.value ?? null;
      for (const entry of numbers) {
        if (entry.tag !== null) continue;
        if (reps === null) reps = entry.value;
        else if (weight === null) weight = entry.value;
      }
      const repsInteger = repsValue(reps, flags);
      if (reps === null && weight === null) return { sets: [{ weight: null, reps: null }], flags };
      if (weight === null && repsInteger !== null) weight = 0;
      const count = setEntry.value;
      if (!Number.isInteger(count) || count < 1) {
        flags.invalid = true;
        return { sets: [{ weight, reps: repsInteger }], flags };
      }
      const bounded = Math.min(count, LIMITS.maxSetsPerBlock + 1);
      return { sets: Array.from({ length: bounded }, () => ({ weight, reps: repsInteger })), flags };
    }

    const sets = [];
    let current = { weight: null, reps: null, hasReps: false };
    const push = () => {
      if (current.weight !== null || current.hasReps) sets.push({ weight: current.weight, reps: current.reps });
      current = { weight: null, reps: null, hasReps: false };
    };
    for (const entry of numbers) {
      if (entry.tag === "rep") {
        if (current.hasReps) push();
        current.reps = repsValue(entry.value, flags);
        current.hasReps = true;
      } else if (entry.tag === "weight") {
        if (current.weight !== null) push();
        current.weight = entry.value;
      } else if (current.weight === null && !current.hasReps) {
        current.weight = entry.value;
      } else if (current.weight !== null && !current.hasReps) {
        current.reps = repsValue(entry.value, flags);
        current.hasReps = true;
      } else if (current.weight === null) {
        current.weight = entry.value;
      } else {
        push();
        current.weight = entry.value;
      }
      if (current.weight !== null && current.hasReps) push();
    }
    push();
    return { sets, flags };
  }

  let idCounter = 0;
  function defaultId() {
    if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") return crypto.randomUUID();
    idCounter += 1;
    return `voice-${Date.now().toString(36)}-${idCounter}`;
  }

  // exercises: [{id, name, catalogKey, aliases?: string[]}] where aliases are the
  // caller's localized display names and exercise-search aliases.
  function parse(transcript, exercises, options = {}) {
    const makeId = typeof options.makeId === "function" ? options.makeId : defaultId;
    const text = String(transcript ?? "");
    if (!text.trim()) return { blocks: [], diagnostics: [{ kind: "empty", blockId: null }] };
    if (utf8Length(text) > LIMITS.maxTranscriptBytes) {
      return { blocks: [], diagnostics: [{ kind: "transcriptTooLong", blockId: null }] };
    }
    const candidates = (Array.isArray(exercises) ? exercises : []).map((exercise) => ({
      id: exercise.id,
      name: exercise.name,
      catalogKey: exercise.catalogKey ?? null,
      aliases: candidateAliases(exercise)
    }));

    const parsed = [];
    for (const tokens of segment(tokenize(text))) {
      const name = spokenName(tokens);
      const match = matchExercise(name, candidates);
      const values = parseValues(tokens);
      const resolved = match.match === "resolved" ? match.candidates[0] : null;
      const existing = resolved ? parsed.find((entry) => entry.block.exerciseId === resolved.id) : null;
      if (existing) {
        existing.block.sets.push(...values.sets.map((set) => ({ id: makeId(), ...set })));
        existing.invalid = existing.invalid || values.flags.invalid;
        continue;
      }
      parsed.push({
        hasName: Boolean(name),
        invalid: values.flags.invalid,
        block: {
          id: makeId(),
          spokenName: name,
          exerciseId: resolved ? resolved.id : null,
          catalogKey: resolved ? resolved.catalogKey : null,
          match: match.match,
          candidates: match.match === "ambiguous"
            ? match.candidates.map((candidate) => ({ id: candidate.id, name: candidate.name, catalogKey: candidate.catalogKey }))
            : [],
          sets: values.sets.map((set) => ({ id: makeId(), ...set }))
        }
      });
    }

    const diagnostics = [];
    let entries = parsed;
    const tooManyBlocks = entries.length > LIMITS.maxBlocks;
    if (tooManyBlocks) entries = entries.slice(0, LIMITS.maxBlocks);
    for (const entry of entries) {
      const block = entry.block;
      const push = (kind) => diagnostics.push({ kind, blockId: block.id });
      if (!entry.hasName) push("missingExercise");
      else if (block.match === "ambiguous") push("ambiguousExercise");
      else if (block.match !== "resolved") push("unknownExercise");
      const truncated = block.sets.length > LIMITS.maxSetsPerBlock;
      if (truncated) block.sets = block.sets.slice(0, LIMITS.maxSetsPerBlock);
      const hasInvalid = entry.invalid || block.sets.some((set) =>
        (set.weight !== null && !validWeight(set.weight)) || (set.reps !== null && !validReps(set.reps)));
      if (hasInvalid) push("invalidNumber");
      else if (block.sets.some((set) => set.weight === null || set.reps === null)) push("missingSets");
      if (truncated) push("limitsExceeded");
    }
    if (tooManyBlocks) diagnostics.push({ kind: "limitsExceeded", blockId: null });
    return { blocks: entries.map((entry) => entry.block), diagnostics };
  }

  // Live readiness used by every client's sheet; stored diagnostics only
  // describe what the transcript contained.
  function isBlockReady(block) {
    return Boolean(block && block.exerciseId) && Array.isArray(block.sets) && block.sets.length > 0 &&
      block.sets.length <= LIMITS.maxSetsPerBlock && block.sets.every(isValidSet);
  }

  function blockIssue(block) {
    if (!block.exerciseId) return "chooseExercise";
    if (!block.sets.length || !block.sets.every(isValidSet) || block.sets.length > LIMITS.maxSetsPerBlock) return "fixSets";
    return null;
  }

  function formatWeight(value) {
    if (typeof value !== "number" || !Number.isFinite(value)) return "";
    return String(Math.round(value * 1000) / 1000);
  }

  function parseWeightInput(value) {
    const text = String(value ?? "").trim().replace(",", ".");
    if (!text) return null;
    if (!/^-?\d+(?:\.\d+)?$/.test(text)) return Number.NaN;
    return Number(text);
  }

  function parseRepsInput(value) {
    const text = String(value ?? "").trim();
    if (!text) return null;
    if (!/^\d+$/.test(text)) return Number.NaN;
    return Number(text);
  }

  return Object.freeze({
    VERSION: 1,
    LIMITS,
    LOCALES,
    CONTAINS_MATCH_MINIMUM_LENGTH,
    SEPARATOR_PHRASES,
    SET_WORDS,
    REP_WORDS,
    WEIGHT_WORDS,
    WEIGHT_PREFIX_WORDS,
    CONNECTOR_WORDS,
    NUMBER_WORDS,
    VOICE_ALIASES,
    normalizeName,
    utf8Length,
    truncateUtf8,
    parse,
    isValidSet,
    isBlockReady,
    blockIssue,
    formatWeight,
    parseWeightInput,
    parseRepsInput
  });
});
