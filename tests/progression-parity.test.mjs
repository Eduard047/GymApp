import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import test from "node:test";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const rules = require(path.join(root, "pwa", "progression-rules.js"));
const fixturePath = path.join(root, "app", "src", "test", "resources", "progression-v1.tsv");

function goldenRows() {
  return fs.readFileSync(fixturePath, "utf8")
    .split(/\r?\n/)
    .filter(line => line && !line.startsWith("#") && !line.startsWith("case_id"))
    .map(line => {
      const [id, encodedSessions, totalXP, level, levelStartXP, nextLevelXP] = line.split("\t");
      return {
        id,
        sessions: encodedSessions.split(";").map(encoded => {
          const [exercises, sets, volume] = encoded.split(",").map(Number);
          return { exercises, sets, volume };
        }),
        totalXP: Number(totalXP),
        level: Number(level),
        levelStartXP: Number(levelStartXP),
        nextLevelXP: Number(nextLevelXP)
      };
    });
}

test("PWA progression rules match the Android/iOS golden fixture", () => {
  assert.equal(rules.RULES_VERSION, 1);
  for (const row of goldenRows()) {
    const totalXP = row.sessions.reduce((sum, session) => sum + rules.sessionXP(session), 0);
    const progress = rules.levelProgress(totalXP);
    assert.equal(totalXP, row.totalXP, row.id);
    assert.equal(progress.level, row.level, row.id);
    assert.equal(progress.levelStartXp, row.levelStartXP, row.id);
    assert.equal(progress.nextLevelXp, row.nextLevelXP, row.id);
  }
});

test("PWA permanent total excludes rotating mission rewards", () => {
  const source = fs.readFileSync(path.join(root, "pwa", "app.js"), "utf8");
  assert.match(source, /function totalXp\(\)\s*{\s*return xpForSessions\(state\.sessions\);\s*}/);
  assert.match(source, /window\.GymProgressionRules\.sessionXP\(summary\)/);

  const index = fs.readFileSync(path.join(root, "pwa", "index.html"), "utf8");
  assert.ok(index.indexOf("progression-rules.v57.js") < index.indexOf("app.v98.js"));
});

test("empty workouts earn no progression and extreme XP is bounded without a linear loop", () => {
  assert.equal(rules.sessionXP({ exercises: 12, sets: 0, volume: 0 }), 0);
  assert.equal(rules.sessionXP({ exercises: 100, sets: 10000, volume: 1e15 }), rules.MAX_SESSION_XP);
  assert.equal(rules.MAX_SESSION_XP, 5000);
  const started = performance.now();
  const progress = rules.levelProgress(1e307);
  const elapsed = performance.now() - started;

  assert.equal(rules.MAX_SUPPORTED_XP, 2147483647);
  assert.ok(progress.level > 1);
  assert.ok(progress.nextLevelXp <= rules.MAX_SUPPORTED_XP);
  assert.ok(elapsed < 100, `extreme XP calculation took ${elapsed}ms`);

  const source = fs.readFileSync(path.join(root, "pwa", "progression-rules.js"), "utf8");
  assert.match(source, /const squares = stages \* \(stages - 1\)/);
  assert.doesNotMatch(source, /while \(remaining >= next\)/);
});

test("historical months preserve the best three-workout weekly streak reached in that month", () => {
  const localTimestamp = (year, month, day) => new Date(year, month - 1, day, 12).getTime();
  const sessions = [
    [1, 6], [2, 6], [4, 6],
    [9, 6], [11, 6], [12, 6],
    [15, 6], [16, 6]
  ].map(([day, month]) => ({ startedAt: localTimestamp(2026, month, day) }));

  assert.equal(
    rules.bestWeeklyStreakDuring(
      sessions,
      new Date(2026, 5, 1).getTime(),
      new Date(2026, 6, 1).getTime() - 1
    ),
    2
  );
  assert.equal(rules.currentWeeklyStreak(sessions, localTimestamp(2026, 7, 23)), 0);
  assert.equal(
    rules.bestWeeklyStreakDuring(
      [{ startedAt: localTimestamp(2026, 6, 1) }, { startedAt: localTimestamp(2026, 6, 9) }],
      new Date(2026, 5, 1).getTime(),
      new Date(2026, 6, 1).getTime() - 1
    ),
    0
  );
});
