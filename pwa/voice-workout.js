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

  // In-workout voice commands: shared/voice-workout-command-v1.json. Separate
  // entry point from plan dictation (parseVoiceWorkoutCommand vs parse) with
  // its own result shape; reuses REP_WORDS/WEIGHT_WORDS/CONNECTOR_WORDS/
  // NUMBER_WORDS above instead of redefining vocabulary.
  const COMMAND_LIMITS = Object.freeze({
    maxTranscriptBytes: LIMITS.maxTranscriptBytes,
    minWeightKg: 0,
    maxWeightKg: 1000,
    weightStepKg: 0.25,
    minReps: 1,
    maxReps: 200
  });
  const COMMAND_FILLER_WORDS = Object.freeze([
    "ну", "эм", "окей", "ага",
    "емм", "гаразд",
    "um", "uh", "okay", "ok"
  ]);
  const COMMAND_BODYWEIGHT_PHRASES = Object.freeze([
    "с собственным весом", "собственным весом", "своим весом",
    "власною вагою", "власним вагою", "з власною вагою",
    "bodyweight", "body weight", "own bodyweight"
  ]);
  const COMMAND_REPEAT_PHRASES = Object.freeze([
    "повтори", "ещё раз так же", "то же самое", "повтор",
    "ще раз",
    "repeat", "same again"
  ]);
  const COMMAND_SKIP_PHRASES = Object.freeze([
    "дальше", "пропусти отдых", "готов", "поехали",
    "далі", "пропусти відпочинок", "готовий",
    "next", "skip rest", "ready"
  ]);
  const COMMAND_DIAGNOSTIC_CODES = Object.freeze([
    "empty", "transcriptTooLong",
    "ambiguousNumbers", "weightOutOfRange", "repsOutOfRange", "invalidWeightStep",
    "noMatch"
  ]);

  const setWordSet = new Set(SET_WORDS);
  const repWordSet = new Set(REP_WORDS);
  const weightWordSet = new Set(WEIGHT_WORDS);
  const weightPrefixSet = new Set(WEIGHT_PREFIX_WORDS);
  const connectorSet = new Set(CONNECTOR_WORDS);
  const separatorTokens = SEPARATOR_PHRASES
    .map((phrase) => phrase.split(" "))
    .sort((left, right) => right.length - left.length);

  const commandFillerSet = new Set(COMMAND_FILLER_WORDS);
  const toPhraseWords = (phrase) => phrase.split(" ").map(normalizeWord);
  const commandBodyweightPhraseWords = COMMAND_BODYWEIGHT_PHRASES
    .map(toPhraseWords)
    .sort((left, right) => right.length - left.length);
  const commandRepeatPhraseWords = COMMAND_REPEAT_PHRASES.map(toPhraseWords);
  const commandSkipPhraseWords = COMMAND_SKIP_PHRASES.map(toPhraseWords);

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

  function wordSequenceMatches(tokens, phraseWords) {
    if (tokens.length !== phraseWords.length) return false;
    for (let index = 0; index < tokens.length; index += 1) {
      const token = tokens[index];
      if (token.type !== "word" || token.norm !== phraseWords[index]) return false;
    }
    return true;
  }

  function wordSequenceMatchesAny(tokens, phraseWordsList) {
    return phraseWordsList.some((phraseWords) => wordSequenceMatches(tokens, phraseWords));
  }

  // First contiguous run of word tokens equal to one of phraseWordsList,
  // longest phrase first so a longer bodyweight phrase wins over a shorter
  // one it contains (e.g. "з власною вагою" over "власною вагою").
  function findPhraseRun(tokens, phraseWordsList) {
    for (const phraseWords of phraseWordsList) {
      for (let start = 0; start + phraseWords.length <= tokens.length; start += 1) {
        let matches = true;
        for (let offset = 0; offset < phraseWords.length; offset += 1) {
          const token = tokens[start + offset];
          if (!token || token.type !== "word" || token.norm !== phraseWords[offset]) {
            matches = false;
            break;
          }
        }
        if (matches) return { start, length: phraseWords.length };
      }
    }
    return null;
  }

  function finalizeLogSetCommand(raw, weightKg, reps) {
    if (weightKg !== undefined) {
      if (!(typeof weightKg === "number" && Number.isFinite(weightKg) &&
            weightKg >= COMMAND_LIMITS.minWeightKg && weightKg <= COMMAND_LIMITS.maxWeightKg)) {
        return { intent: "unknown", transcript: raw, code: "weightOutOfRange" };
      }
      const scaled = weightKg / COMMAND_LIMITS.weightStepKg;
      if (Math.abs(scaled - Math.round(scaled)) > 1e-6) {
        return { intent: "unknown", transcript: raw, code: "invalidWeightStep" };
      }
    }
    if (reps !== undefined) {
      if (!(Number.isInteger(reps) && reps >= COMMAND_LIMITS.minReps && reps <= COMMAND_LIMITS.maxReps)) {
        return { intent: "unknown", transcript: raw, code: "repsOutOfRange" };
      }
    }
    const result = { intent: "logSet" };
    if (weightKg !== undefined) result.weightKg = weightKg;
    if (reps !== undefined) result.reps = reps;
    return result;
  }

  // In-workout voice command entry point, separate from parse() (plan
  // dictation). One utterance -> one typed intent; never throws. `locale`
  // and `context` (e.g. the current set being edited) are accepted for
  // callers/future tie-breaking; matching itself is locale-agnostic like
  // parse() above, using the same cross-language tables.
  function parseVoiceWorkoutCommand(transcript, locale, context) {
    try {
      const raw = String(transcript ?? "");
      const trimmed = raw.trim();
      if (!trimmed) return { intent: "unknown", transcript: raw, code: "empty" };
      if (utf8Length(raw) > COMMAND_LIMITS.maxTranscriptBytes) {
        return { intent: "unknown", transcript: truncateUtf8(raw), code: "transcriptTooLong" };
      }

      let tokens = tokenize(raw).filter((token) => token.type !== "break");
      tokens = tokens.filter((token) => !(token.type === "word" && commandFillerSet.has(token.norm)));

      const unknown = (code) => ({ intent: "unknown", transcript: raw, code });
      const hasNumber = tokens.some((token) => token.type === "number");

      if (!hasNumber) {
        if (wordSequenceMatchesAny(tokens, commandRepeatPhraseWords)) return { intent: "repeatPrevious" };
        if (wordSequenceMatchesAny(tokens, commandSkipPhraseWords)) return { intent: "skipRest" };
        return unknown("noMatch");
      }

      let isBodyweight = false;
      const bodyweightRun = findPhraseRun(tokens, commandBodyweightPhraseWords);
      if (bodyweightRun) {
        tokens = tokens.slice(0, bodyweightRun.start).concat(tokens.slice(bodyweightRun.start + bodyweightRun.length));
        isBodyweight = true;
      }

      const numberEntries = [];
      tokens.forEach((token, index) => {
        if (token.type !== "number") return;
        const next = tokens[index + 1];
        let tag = null;
        if (next && next.type === "word") {
          if (weightWordSet.has(next.norm)) tag = "weight";
          else if (repWordSet.has(next.norm)) tag = "rep";
        }
        numberEntries.push({ value: token.value, tag, index });
      });

      if (isBodyweight) {
        if (numberEntries.length !== 1) return unknown("ambiguousNumbers");
        return finalizeLogSetCommand(raw, 0, numberEntries[0].value);
      }

      if (numberEntries.length === 0) return unknown("noMatch");

      if (numberEntries.length === 1) {
        const only = numberEntries[0];
        if (only.tag === "weight") return finalizeLogSetCommand(raw, only.value, undefined);
        if (only.tag === "rep") return finalizeLogSetCommand(raw, undefined, only.value);
        return unknown("ambiguousNumbers");
      }

      if (numberEntries.length === 2) {
        const [first, second] = numberEntries;
        const taggedWeight = numberEntries.filter((entry) => entry.tag === "weight");
        const taggedRep = numberEntries.filter((entry) => entry.tag === "rep");
        const untagged = numberEntries.filter((entry) => entry.tag === null);
        if (taggedWeight.length === 1 && taggedRep.length === 1) {
          return finalizeLogSetCommand(raw, taggedWeight[0].value, taggedRep[0].value);
        }
        if (taggedWeight.length === 1 && untagged.length === 1) {
          return finalizeLogSetCommand(raw, taggedWeight[0].value, untagged[0].value);
        }
        if (taggedRep.length === 1 && untagged.length === 1) {
          return finalizeLogSetCommand(raw, untagged[0].value, taggedRep[0].value);
        }
        if (untagged.length === 2) {
          const between = tokens.slice(first.index + 1, second.index);
          const hasConnector = between.some((token) => token.type === "word" && connectorSet.has(token.norm));
          if (hasConnector) return finalizeLogSetCommand(raw, first.value, second.value);
        }
        return unknown("ambiguousNumbers");
      }

      return unknown("ambiguousNumbers");
    } catch (error) {
      return { intent: "unknown", transcript: String(transcript ?? ""), code: "noMatch" };
    }
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
    COMMAND_LIMITS,
    COMMAND_FILLER_WORDS,
    COMMAND_BODYWEIGHT_PHRASES,
    COMMAND_REPEAT_PHRASES,
    COMMAND_SKIP_PHRASES,
    COMMAND_DIAGNOSTIC_CODES,
    normalizeName,
    utf8Length,
    truncateUtf8,
    parse,
    parseVoiceWorkoutCommand,
    isValidSet,
    isBlockReady,
    blockIssue,
    formatWeight,
    parseWeightInput,
    parseRepsInput
  });
});
