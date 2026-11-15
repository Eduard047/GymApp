import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const screen = await readFile(
  "app/src/main/java/com/example/gymapp/ui/screens/PostWorkoutSummaryScreen.kt",
  "utf8"
);
const viewModel = await readFile(
  "app/src/main/java/com/example/gymapp/ui/viewmodel/PostWorkoutSummaryViewModel.kt",
  "utf8"
);
const contract = JSON.parse(await readFile("shared/vs-last-comparable-v1.json", "utf8"));

test("post-workout summary is a result hero plus grouped sections, not a stack of cards", () => {
  assert.match(screen, /GroupedSection\(/);
  assert.match(screen, /GymSegmentedControl</);
  for (const forbidden of [/AppPanel\(/, /HeroPanel\(/, /MetricTile\(/, /InfoPill\(/, /AchievementRingTile\(/, /TrainingMetricsCard/, /post_workout_metrics_title/, /post_workout_xp_to_level/, /post_workout_session_xp/]) {
    assert.doesNotMatch(screen, forbidden);
  }
});

test("Done is pinned outside the scrolling list", () => {
  const list = screen.indexOf("LazyColumn(");
  const bar = screen.indexOf("DoneBar(\n                    onDone = onDone");
  assert.ok(list > 0 && bar > list, "DoneBar must be a sibling after the LazyColumn");
  assert.match(screen, /Alignment\.BottomCenter/);
  assert.equal((screen.match(/R\.string\.post_workout_done/g) ?? []).length, 1);
});

test("hero shows volume, sets and duration, and XP is one footnote line", () => {
  assert.match(screen, /post_workout_metric_volume/);
  assert.match(screen, /post_workout_metric_sets/);
  assert.match(screen, /post_workout_metric_duration/);
  assert.match(screen, /ProgressFootnote/);
  assert.doesNotMatch(screen, /levelProgress|xpToNextLevel/);
});

test("comparison rows are gated by the shared 80% rule and shown in neutral colour when lower", () => {
  assert.match(viewModel, /isVsLastComparable\(/);
  assert.match(viewModel, /previousWorkoutSetCount\(/);
  assert.equal(contract.minimumPercent, 80);
  assert.doesNotMatch(screen, /colorScheme\.error/);
  assert.ok(contract.cases.some(row => row.shown === false && row.currentSetCount > 0));
});
