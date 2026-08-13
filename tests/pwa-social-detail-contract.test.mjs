import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const appSource = await readFile("pwa/app.js", "utf8");

function sourceBetween(startMarker, endMarker) {
  const start = appSource.indexOf(startMarker);
  const end = appSource.indexOf(endMarker, start + startMarker.length);
  assert.ok(start >= 0, `${startMarker} must exist`);
  assert.ok(end > start, `${endMarker} must follow ${startMarker}`);
  return appSource.slice(start, end);
}

function functionSource(name) {
  const start = appSource.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} must exist`);
  const open = appSource.indexOf("{", start);
  let depth = 0;
  for (let index = open; index < appSource.length; index += 1) {
    if (appSource[index] === "{") depth += 1;
    if (appSource[index] === "}") depth -= 1;
    if (depth === 0) return appSource.slice(start, index + 1);
  }
  throw new Error(`${name} is not closed`);
}

function parserContext() {
  const context = vm.createContext({ TextEncoder });
  context.window = {
    GymSharedWorkout: {
      portableNameKey(value) {
        return String(value).normalize("NFKC").trim().toLowerCase();
      }
    }
  };
  vm.runInContext(`
    const SOCIAL_PROFILE_ID_PATTERN = /^p_[0-9a-f]{32}$/;
    const SOCIAL_FRIEND_WORKOUT_ID_PATTERN = /^fw_[0-9a-f]{32}$/;
    const SOCIAL_DAY_PATTERN = /^\\d{4}-\\d{2}-\\d{2}$/;
    ${sourceBetween("function socialExactObject", "function normalizeSocialWorkoutPlan")}
    ${functionSource("parseSocialWorkoutDetailPrivacy")}
    ${functionSource("parseSocialRealtimeInvalidation")}
    globalThis.parsePage = parseSocialFriendWorkoutPage;
    globalThis.parseCapability = parseSocialFriendWorkoutDetailCapability;
    globalThis.parseInvalidation = parseSocialRealtimeInvalidation;
    globalThis.parsePrivacy = parseSocialWorkoutDetailPrivacy;
  `, context);
  return context;
}

function validPage() {
  return {
    version: 1,
    friend: { profileId: `p_${"1".repeat(32)}`, displayName: "Training friend" },
    activityRevision: "2026-08-13T08:30:00.000Z",
    items: [{
      workoutId: `fw_${"2".repeat(32)}`,
      startedAt: "2026-08-12T18:00:00.000Z",
      workoutDay: "2026-08-12",
      exerciseCount: 1,
      setCount: 2,
      truncated: false,
      exercises: [{
        catalogKey: "bench_press",
        name: "Bench Press",
        sets: [{ weightKg: 0, reps: 12 }, { weightKg: 80, reps: 8 }]
      }]
    }],
    nextCursor: null,
    integrity: "self_reported"
  };
}

test("friend workout page accepts only the bounded exact consent projection", () => {
  const context = parserContext();
  const parsed = context.parsePage(validPage());
  assert.equal(parsed.version, 1);
  assert.equal(parsed.items.length, 1);
  assert.equal(parsed.items[0].exercises[0].sets[0].weightKg, 0);
  assert.equal(parsed.nextCursor, null);
  assert.equal(Object.isFrozen(parsed.items[0]), true);

  for (const mutate of [
    page => { page.nextCursor = "1:1"; },
    page => { page.secret = "must fail"; },
    page => { page.activityRevision = null; },
    page => { page.items[0].setCount = 3; },
    page => { page.items[0].exercises[0].sets[0].weightKg = Number.NaN; },
    page => { page.items[0].workoutId = "fw_bad"; },
    page => { page.items[0].exercises.push(structuredClone(page.items[0].exercises[0])); }
  ]) {
    const page = validPage();
    mutate(page);
    assert.throws(() => context.parsePage(page));
  }
});

test("detailed workout privacy uses a separate strict default-off CAS contract", () => {
  const context = parserContext();
  const parsed = context.parsePrivacy({
    version: 1,
    shareWorkoutDetails: false,
    settingsRevision: 7
  });
  assert.equal(parsed.shareWorkoutDetails, false);
  assert.equal(parsed.settingsRevision, 7);
  assert.throws(() => context.parsePrivacy({
    version: 1,
    shareWorkoutDetails: false,
    settingsRevision: 7,
    shareRecentWorkouts: true
  }));
  assert.throws(() => context.parsePrivacy({
    version: 1,
    shareWorkoutDetails: "false",
    settingsRevision: 7
  }));
});

test("friend detail capability and realtime invalidation carry no private payload", () => {
  const context = parserContext();
  assert.equal(context.parseCapability({ version: 1, available: false }).available, false);
  assert.throws(() => context.parseCapability({ version: 1, available: false, profileId: `p_${"1".repeat(32)}` }));
  assert.equal(context.parseInvalidation({ version: 1, kind: "privacy_changed" }), true);
  assert.throws(() => context.parseInvalidation({
    version: 1,
    kind: "privacy_changed",
    activityRevision: "2026-08-13T08:30:00.000Z"
  }));
});

test("PWA requests only the consented latest five and clears private detail on invalidation", () => {
  const load = sourceBetween("async function loadSocialFriendWorkoutPage", "function socialDayLabel");
  const capability = sourceBetween(
    "async function loadSocialFriendWorkoutDetailCapability",
    "async function loadSocialFriendWorkoutPage"
  );
  const refresh = sourceBetween("async function refreshSocialData", "function currentLiveRoomId");
  const realtime = sourceBetween("function handleSocialRealtimeInvalidation", "async function ensureLiveWorkoutRealtime");
  const privacy = sourceBetween("async function saveSocialWorkoutDetailPrivacy", "async function sendWorkoutInvite");

  assert.match(load, /p_cursor: null/);
  assert.match(load, /p_limit: 5/);
  assert.match(load, /p_expected_activity_revision/);
  assert.match(load, /\[403, 404\]\.includes/);
  assert.doesNotMatch(load, /nextCursor[\s\S]*socialRpc/);
  assert.match(capability, /social_friend_workout_detail_capability/);
  assert.match(capability, /if \(!capability\.available\)/);
  assert.doesNotMatch(capability, /social_friend_workout_page/);
  assert.match(refresh, /social_workout_detail_privacy/);
  assert.match(privacy, /social_update_workout_detail_privacy/);
  assert.match(privacy, /p_expected_revision: revision/);
  assert.match(privacy, /clearSocialWorkoutDetailCache/);
  assert.match(realtime, /clearSocialWorkoutDetailCache/);
  assert.match(realtime, /refreshSocialData\(true\)/);
  assert.match(realtime, /parseSocialRealtimeInvalidation\(message\?\.payload\)/);
});

test("active live UI has two nickname tabs, peer actual sets, and no owner start control", () => {
  const tabs = sourceBetween("function activeLiveParticipants", "function activeLiveWorkoutMarkup");
  const room = sourceBetween("function liveWorkoutRoomMarkup", "function liveDraftFromSnapshot");
  const accept = sourceBetween("async function respondLiveWorkoutInvite", "async function openLiveWorkoutRoom");

  assert.match(tabs, /snapshot\.participants\.length === 2/);
  assert.match(tabs, /role="tablist"/);
  assert.equal((tabs.match(/role="tab"/g) || []).length, 2);
  assert.match(tabs, /actual\.weight/);
  assert.match(tabs, /actual\.reps/);
  assert.doesNotMatch(room, /data-action="start-live-room"/);
  assert.match(accept, /refreshAttempts = decision === "accept" \? 3 : 1/);
  assert.match(accept, /snapshot\?\.room\?\.status === "active"/);
});
