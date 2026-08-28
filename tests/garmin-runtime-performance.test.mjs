import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const section = (source, start, end) => {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notEqual(startIndex, -1, `Missing start anchor: ${start}`);
  assert.notEqual(endIndex, -1, `Missing end anchor: ${end}`);
  return source.slice(startIndex, endIndex);
};

test("Garmin full-profile motion callbacks validate each adjacent sample once", async () => {
  const source = await readFile("garmin/source/GymSession.mc", "utf8");
  const full = section(
    source,
    "(:fullLegacyState)\n    static function onSensorData(data)",
    "(:fullLegacyState)\n    static function axisDeltaScore"
  );
  const gyro = section(
    source,
    "(:fullLegacyState)\n    static function axisDeltaScore(sensorData)",
    "(:compactLegacyState)\n    static function onSensorData(data)"
  );
  const compact = section(
    source,
    "(:compactLegacyState)\n    static function onSensorData(data)",
    "static function isFiniteSensorNumber"
  );

  for (const callback of [full, gyro]) {
    assert.match(callback, /var previousSampleValid = isFiniteSensorNumber\(previousX\)/);
    assert.match(callback, /var currentSampleValid = isFiniteSensorNumber\(currentX\)/);
    assert.match(callback, /previousSampleValid = currentSampleValid/);
    assert.doesNotMatch(callback, /isFiniteSensorNumber\([xyz]s\[i - 1\]\)/);
  }
  assert.match(compact, /if \(count > 40\) \{\s*count = 40/);
  assert.doesNotMatch(compact, /Storage|GymComm|setValue/);
  assert.match(full, /var previousValid = isFiniteSensorNumber\(previous\)/);
  assert.match(full, /var currentValid = isFiniteSensorNumber\(current\)/);
  assert.match(full, /previousValid = currentValid/);

  const samplesPerBatch = 25;
  const oldFullValidationCalls = 14 * (samplesPerBatch - 1);
  const newFullValidationCalls = 7 * samplesPerBatch;
  assert.ok(newFullValidationCalls < oldFullValidationCalls / 1.9);
});

test("Garmin full profile throttles static redraws and caches plan progress", async () => {
  const view = await readFile("garmin/source/WorkoutView.mc", "utf8");
  const tick = section(view, "function tick()", "function requestSyncNow()");
  const badge = section(
    view,
    "function dashboardSetBadgeText()",
    "function drawDashboardSetRow("
  );

  assert.match(tick, /if \(page == 7 \|\| !GymSession\.recording\) \{[\s\S]*staticRefreshTicks \+= 1/);
  assert.ok(
    tick.indexOf("if (GymSession.paused)") < tick.indexOf("GymSession.tick()"),
    "paused menus should not execute or redraw the live dashboard tick"
  );
  assert.match(
    tick,
    /if \(GymSession\.paused\) \{\s*if \(staticSurfaceChanged\) \{\s*Ui\.requestUpdate\(\);\s*\}\s*return;/,
    "sync timeout state changes must refresh the paused surface without restoring periodic redraws"
  );
  assert.match(tick, /staticSurfaceChanged \|\| staticRefreshTicks >= 60/);
  assert.match(tick, /page == 0 \|\| page == 4 \|\| overlayActive/);
  assert.match(badge, /dashboardProgressSetCount != setCount/);
  assert.match(badge, /dashboardProgressPlanCount != planCount/);
  assert.equal((badge.match(/completedPlannedSetCount\(\)/g) || []).length, 1);
});

test("Garmin full-profile text fitting preserves the longest prefix logarithmically", async () => {
  const view = await readFile("garmin/source/WorkoutView.mc", "utf8");
  const fit = section(
    view,
    "(:fullLegacyState)\n    function fitTextWidth(",
    "(:compactLegacyState)\n    function fitTextWidth("
  );
  assert.match(fit, /var low = 3/);
  assert.match(fit, /var high = value\.length\(\) - 1/);
  assert.match(fit, /while \(low <= high\)/);
  assert.match(fit, /low = middle \+ 1/);
  assert.match(fit, /high = middle - 1/);
  assert.doesNotMatch(fit, /value = value\.substring\(0, value\.length\(\) - 1\)/);

  const linear = (length, maxWidth) => {
    if (length * 7 <= maxWidth) return length;
    let prefix = length;
    while (prefix > 3) {
      prefix -= 1;
      if ((prefix * 7) + 9 <= maxWidth) return prefix;
    }
    return -1;
  };
  const binary = (length, maxWidth) => {
    if (length * 7 <= maxWidth) return length;
    let low = 3;
    let high = length - 1;
    let fitted = -1;
    while (low <= high) {
      const middle = Math.floor((low + high) / 2);
      if ((middle * 7) + 9 <= maxWidth) {
        fitted = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return fitted;
  };

  for (let length = 0; length <= 160; length += 1) {
    for (let maxWidth = 0; maxWidth <= 1200; maxWidth += 13) {
      assert.equal(binary(length, maxWidth), linear(length, maxWidth));
    }
  }
});
