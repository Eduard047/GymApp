import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [app, styles] = await Promise.all([readFile("pwa/app.js", "utf8"), readFile("pwa/styles.css", "utf8")]);

test("continue-workout bar reuses the existing continue and discard actions", () => {
  const start = app.indexOf("function continueWorkoutBar(");
  const body = app.slice(start, app.indexOf("function liveWorkoutBanner()", start));
  assert.match(body, /\["active", "workouts", "add"\]\.includes\(current\.name\)/);
  assert.match(body, /liveWorkoutBinding\?\.localWorkoutId === activeWorkout\.id/);
  assert.match(body, /data-action="continue-active-workout"/);
  assert.match(body, /data-action="discard-active-workout"/);
  assert.match(body, /counts\.completed\} \/ \$\{counts\.total/);
  assert.match(app, /\$\{continueWorkoutBar\(current\)\}\$\{liveWorkoutBanner\(\)\}/);
  assert.match(styles, /\.continue-workout-bar-discard\s*\{[^}]*width: 48px;[^}]*height: 48px;/);
});
