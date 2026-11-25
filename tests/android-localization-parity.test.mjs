import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const placeholderPattern = /%(?:\d+\$)?(?:[-+#0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?)?[a-zA-Z@]/g;

function placeholders(value) {
  return [...String(value).matchAll(placeholderPattern)].map(match => match[0]).sort();
}

function uniquePlaceholders(value) {
  return [...new Set(placeholders(value))].sort();
}

/** Parses strings, plurals and string-arrays of an Android values XML file. */
function androidResources(source) {
  const strings = new Map(
    [...source.matchAll(/<string\s+name="([^"]+)"[^>]*>(.*?)<\/string>/gs)].map(([, name, value]) => [name, value])
  );
  const plurals = new Map(
    [...source.matchAll(/<plurals\s+name="([^"]+)"[^>]*>(.*?)<\/plurals>/gs)].map(([, name, body]) => [
      name,
      new Map([...body.matchAll(/<item\s+quantity="([^"]+)"[^>]*>(.*?)<\/item>/gs)].map(([, quantity, value]) => [quantity, value]))
    ])
  );
  const arrays = new Map(
    [...source.matchAll(/<string-array\s+name="([^"]+)"[^>]*>(.*?)<\/string-array>/gs)].map(([, name, body]) => [
      name,
      [...body.matchAll(/<item[^>]*>(.*?)<\/item>/gs)].map(([, value]) => value)
    ])
  );
  return { strings, plurals, arrays };
}

async function loadModule(module) {
  const read = locale => readFile(`${module}/src/main/res/values${locale}/strings.xml`, "utf8").then(androidResources);
  const [english, ukrainian, russian] = await Promise.all([read(""), read("-uk"), read("-ru")]);
  return { english, ukrainian, russian };
}

function assertLocaleParity(module, localeName, english, localized) {
  const sorted = map => [...map.keys()].sort();
  assert.deepEqual(sorted(localized.strings), sorted(english.strings), `${module} ${localeName} string keys`);
  assert.deepEqual(sorted(localized.plurals), sorted(english.plurals), `${module} ${localeName} plurals keys`);
  assert.deepEqual(sorted(localized.arrays), sorted(english.arrays), `${module} ${localeName} array keys`);

  for (const [name, value] of english.strings) {
    assert.deepEqual(placeholders(localized.strings.get(name)), placeholders(value), `${module} ${localeName} ${name}`);
  }
  for (const [name, items] of english.plurals) {
    assert.deepEqual([...items.keys()].sort(), ["one", "other"], `${module} en plural quantities ${name}`);
    const expected = uniquePlaceholders(items.get("other"));
    for (const quantity of ["one", "other"]) {
      assert.deepEqual(uniquePlaceholders(items.get(quantity)), expected, `${module} en ${name}[${quantity}] placeholders`);
    }
    const localizedItems = localized.plurals.get(name);
    assert.deepEqual(
      [...localizedItems.keys()].sort(),
      ["few", "many", "one", "other"],
      `${module} ${localeName} plural quantities ${name}`
    );
    for (const [quantity, value] of localizedItems) {
      assert.deepEqual(uniquePlaceholders(value), expected, `${module} ${localeName} ${name}[${quantity}] placeholders`);
    }
  }
  for (const [name, items] of english.arrays) {
    const localizedItems = localized.arrays.get(name);
    assert.equal(localizedItems.length, items.length, `${module} ${localeName} array length ${name}`);
    items.forEach((value, index) => {
      assert.deepEqual(placeholders(localizedItems[index]), placeholders(value), `${module} ${localeName} ${name}[${index}]`);
    });
  }
}

test("Android app Ukrainian and Russian resources match English keys, plural quantities and placeholders", async () => {
  const { english, ukrainian, russian } = await loadModule("app");
  assert.ok(english.strings.size >= 1500);
  assert.ok(english.plurals.size >= 50);
  assertLocaleParity("app", "uk", english, ukrainian);
  assertLocaleParity("app", "ru", english, russian);
  // The offline-profile placeholder and default name is translated.
  assert.equal(ukrainian.strings.get("auth_local_default_name"), "Локальний");
  assert.equal(russian.strings.get("auth_local_default_name"), "Локальный");
});

test("Android Wear OS Ukrainian and Russian resources match English keys, plural quantities and placeholders", async () => {
  const { english, ukrainian, russian } = await loadModule("wear");
  assert.ok(english.strings.size >= 50);
  assertLocaleParity("wear", "uk", english, ukrainian);
  assertLocaleParity("wear", "ru", english, russian);
  assert.doesNotMatch([...russian.strings.values()].join("\n"), /[іїєґІЇЄҐ]/);
});

test("Android counts after a number use plurals, not fixed noun forms", async () => {
  const { english, ukrainian, russian } = await loadModule("app");
  const converted = [
    "leaderboard_row_detail", "friend_stats_summary", "friend_metric_workouts", "friend_record_meta",
    "workout_invites_pending_count", "friends_confirmed_count", "missions_xp_reward", "smart_reason_recent_break",
    "garmin_metric_sets_value", "garmin_metric_exercises_value", "garmin_set_intervals_omitted",
    "training_rep_comparison", "shared_workout_more_exercises", "progress_reps_value", "activity_heatmap_day_a11y",
    "garmin_sets_with_evidence", "garmin_recovery_median_sets", "exercise_search_result_count",
    "exercise_load_option_count", "garmin_set_hr_overview_accessibility", "exercise_workout_count_compact",
    "live_workout_plan_exercises", "live_workout_plan_sets"
  ];
  for (const name of converted) {
    for (const [localeName, resources] of [["en", english], ["uk", ukrainian], ["ru", russian]]) {
      assert.ok(resources.plurals.has(name), `${localeName} ${name} is a plurals resource`);
      assert.ok(!resources.strings.has(name), `${localeName} ${name} is not also a fixed string`);
    }
  }
  // Two-count summaries compose one plural per number.
  assert.equal(english.strings.get("smart_alternative_prescription"), "%1$s · %2$s · RIR %3$d–%4$d");
  assert.equal(english.strings.get("live_workout_plan_summary"), "%1$s · %2$s");

  const sources = new Map();
  async function source(file) {
    if (!sources.has(file)) sources.set(file, await readFile(`app/src/main/java/com/example/gymapp/${file}`, "utf8"));
    return sources.get(file);
  }
  const allMain = await kotlinSources("app/src/main/java");
  for (const name of converted) {
    assert.doesNotMatch(allMain, new RegExp(`R\\.string\\.${name}\\b`), `${name} is read as a plurals resource`);
  }
  assert.match(
    await source("ui/screens/AddWorkoutScreen.kt"),
    /R\.string\.smart_alternative_prescription,\s*formattedPluralStringResource\(\s*R\.plurals\.saved_workout_set_count,[\s\S]*?R\.plurals\.saved_workout_rep_count/
  );
  assert.match(
    await source("ui/screens/FriendsScreen.kt"),
    /R\.string\.live_workout_plan_summary,\s*formattedPluralStringResource\(\s*R\.plurals\.live_workout_plan_exercises,[\s\S]*?R\.plurals\.live_workout_plan_sets/
  );
});

async function kotlinFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map(entry => {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) return kotlinFiles(full);
    return entry.name.endsWith(".kt") ? [full] : [];
  }));
  return files.flat();
}

async function kotlinSources(directory) {
  const files = await kotlinFiles(directory);
  return (await Promise.all(files.map(file => readFile(file, "utf8")))).join("\n");
}

function kotlinStringLiteral(literal) {
  // Kotlin "\$" is a literal dollar; the remaining escapes match JSON.
  return JSON.parse(`"${literal.replace(/\\\$/g, "$")}"`);
}

/** Mirrors RussianText.translate: the exact table first, then the dynamic patterns. */
async function russianTranslator() {
  const source = await readFile("app/src/main/java/com/example/gymapp/util/RussianText.kt", "utf8");
  const exactBlock = source.match(/private val exact = mapOf\(([\s\S]*?)\n {4}\)/)[1];
  const dynamicBlock = source.match(/private val dynamic = listOf\(([\s\S]*?)\n {4}\)/)[1];
  const literal = String.raw`"((?:[^"\\]|\\.)*)"`;
  const exact = new Map(
    [...exactBlock.matchAll(new RegExp(`${literal}\\s+to\\s+${literal}`, "g"))].map(([, en, ru]) => [
      kotlinStringLiteral(en),
      kotlinStringLiteral(ru)
    ])
  );
  const dynamic = [...dynamicBlock.matchAll(new RegExp(`Regex\\(${literal}\\)\\s+to`, "g"))].map(
    ([, pattern]) => new RegExp(kotlinStringLiteral(pattern))
  );
  assert.ok(exact.size >= 100, "RussianText exact table parsed");
  assert.ok(dynamic.length >= 20, "RussianText dynamic patterns parsed");
  return english => exact.has(english) || dynamic.some(pattern => pattern.test(english));
}

test("every Android two-argument t(en, uk) English literal has a Russian translation", async () => {
  const translates = await russianTranslator();
  const files = await kotlinFiles("app/src/main/java");
  const literal = String.raw`"((?:[^"\\]|\\.)*)"`;
  const call = new RegExp(String.raw`\b(?:t|localizedText)\(\s*en\s*=\s*${literal}\s*,\s*uk\s*=\s*${literal}\s*\)`, "g");
  const missing = [];
  let checked = 0;
  for (const file of files) {
    const source = await readFile(file, "utf8");
    for (const [, en] of source.matchAll(call)) {
      checked += 1;
      const english = kotlinStringLiteral(en);
      // Interpolated values (`$names`, `${group.titleEn}`) become sample text before matching.
      const candidates = /\$/.test(english)
        ? ["Chest", "3"].map(sample => english.replace(/\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*/g, sample))
        : [english];
      if (!candidates.some(translates)) missing.push(`${path.relative(".", file)}: ${english}`);
    }
  }
  assert.ok(checked >= 30, `expected at least 30 two-argument literals, found ${checked}`);
  assert.deepEqual(missing, []);
});
