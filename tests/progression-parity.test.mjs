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
  assert.ok(index.indexOf("progression-rules.js") < index.indexOf("app.js"));
});
