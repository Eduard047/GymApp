import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const androidPrompt = await readFile(
  "app/src/main/java/com/example/gymapp/review/ReviewPrompt.kt",
  "utf8",
);
const navGraph = await readFile(
  "app/src/main/java/com/example/gymapp/navigation/GymNavGraph.kt",
  "utf8",
);
const iosPolicy = await readFile(
  "ios/GymApp-iOS/GymApp/Domain/ReviewPromptPolicy.swift",
  "utf8",
);
const iosRoot = await readFile(
  "ios/GymApp-iOS/GymApp/App/AppRootView.swift",
  "utf8",
).catch(() => "");

test("Android and iOS review prompt constants match the approved rule", () => {
  assert.match(androidPrompt, /const val MIN_DAYS_BETWEEN_REQUESTS = 90\b/);
  assert.match(androidPrompt, /const val MAX_REQUESTS = 3\b/);
  assert.match(androidPrompt, /const val MIN_LOGGED_SETS = 1\b/);

  assert.match(iosPolicy, /static let minDaysBetweenRequests = 90\b/);
  assert.match(iosPolicy, /static let maxRequests = 3\b/);
  assert.match(iosPolicy, /static let minLoggedSets = 1\b/);
});

test("Android requests a review only from the post-workout summary Done path", () => {
  const callSites = navGraph.match(/ReviewPromptRequester\.maybeRequest\(/g) ?? [];
  assert.equal(callSites.length, 1);

  const summaryStart = navGraph.indexOf("AppDestination.PostWorkoutSummary.route,");
  const callIndex = navGraph.indexOf("ReviewPromptRequester.maybeRequest(");
  const onDoneIndex = navGraph.indexOf("onDone = {", summaryStart);
  const feedbackIndex = navGraph.indexOf("onFeedbackSelected = viewModel::selectFeedback", onDoneIndex);
  assert.ok(summaryStart > 0 && onDoneIndex > summaryStart);
  assert.ok(callIndex > onDoneIndex && callIndex < feedbackIndex);

  // The Play review API itself is touched in exactly one file, and never reads analytics consent.
  assert.match(androidPrompt, /requestReviewFlow\(\)/);
  assert.doesNotMatch(androidPrompt, /ConversionAnalytics/);
});

test("iOS asks for a review through requestReview in AppRootView", () => {
  assert.match(iosRoot, /requestReview/);
});
