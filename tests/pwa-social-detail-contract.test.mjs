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

test("PWA inbox pages metadata and authorizes one exact invite plan at its revision", () => {
  const inbox = sourceBetween("async function loadSocialWorkoutInbox", "async function refreshSocialData");
  const inviteRows = sourceBetween("function socialWorkoutInviteRows", "function friendsPanel");
  const detail = sourceBetween(
    "async function loadSocialWorkoutInvitePlan",
    "function currentShareableFriendCode"
  );
  const accept = sourceBetween("async function respondWorkoutInvite", "async function openAcceptedWorkoutInvite");
  const recovery = sourceBetween("async function openAcceptedWorkoutInvite", "function openSocialWorkoutInvitePlan");

  assert.match(inbox, /social_workout_inbox_page/);
  assert.match(inbox, /p_cursor_created_at/);
  assert.match(inbox, /p_cursor_invite_id/);
  assert.match(inbox, /p_cursor_pending/);
  assert.match(inbox, /p_limit: SOCIAL_WORKOUT_INBOX_PAGE_LIMIT/);
  assert.match(appSource, /const MAX_SOCIAL_WORKOUT_INBOX_ITEMS = 20;/);
  assert.match(appSource, /const SOCIAL_WORKOUT_INBOX_PAGE_LIMIT = 10;/);
  assert.match(
    appSource,
    /const SOCIAL_WORKOUT_INBOX_MAX_PAGES = MAX_SOCIAL_WORKOUT_INBOX_ITEMS;/
  );
  assert.doesNotMatch(appSource, /incoming\.length !== expectedLimit/);
  assert.match(appSource, /if \(!last \|\| last\.createdAt !== nextCursor\.createdAt/);
  assert.match(appSource, /JSON\.stringify\(current\.outgoing\) !== JSON\.stringify\(next\.outgoing\)/);
  assert.match(appSource, /incoming\.length > MAX_SOCIAL_WORKOUT_INBOX_ITEMS/);
  assert.match(inbox, /inboxPageCount < SOCIAL_WORKOUT_INBOX_MAX_PAGES/);
  assert.match(inviteRows, /data-action="load-more-workout-invites"/);
  assert.match(inviteRows, /tx\("Load more", "Завантажити ще"\)/);
  assert.match(inbox, /if \(!isMissingSocialRpc\(error\)\) throw error/);
  assert.match(inbox, /social_workout_inbox/);
  assert.match(detail, /social_workout_invite_plan/);
  assert.match(detail, /p_expected_revision: inviteRevision/);
  assert.match(detail, /socialSessionIsCurrent/);
  assert.match(detail, /Friends changed\. Current account data was refreshed\./);
  assert.match(accept, /await loadSocialWorkoutInvitePlan/);
  assert.match(accept, /parsed\.inviteRevision !== revision \+ 1/);
  assert.match(recovery, /await loadSocialWorkoutInvitePlan/);
});

test("active live UI has two nickname tabs, peer actual sets, and no owner start control", () => {
  const tabs = sourceBetween("function activeLiveParticipants", "function activeLiveWorkoutMarkup");
  const binding = sourceBetween("function bindEvents(", "function activateProfileHubTabFromKeyboard");
  const keyboardHandler = sourceBetween(
    "function activateLiveParticipantTabFromKeyboard",
    "function activateDataActionFromKeyboard"
  );
  const room = sourceBetween("function liveWorkoutRoomMarkup", "function liveDraftFromSnapshot");
  const accept = sourceBetween("async function respondLiveWorkoutInvite", "async function openLiveWorkoutRoom");

  assert.match(tabs, /snapshot\.participants\.length === 2/);
  assert.match(tabs, /role="tablist"/);
  assert.equal((tabs.match(/role="tab"/g) || []).length, 2);
  assert.match(tabs, /id="active-live-tab-self"[^>]*aria-controls="active-live-panel-self"/);
  assert.match(tabs, /id="active-live-tab-peer"[^>]*aria-controls="active-live-panel-peer"/);
  assert.match(tabs, /id="active-live-panel-peer"[^>]*role="tabpanel"[^>]*aria-labelledby="active-live-tab-peer"/);
  assert.match(appSource, /id="active-live-panel-self" role="tabpanel" aria-labelledby="active-live-tab-self"/);
  assert.match(binding, /addEventListener\("keydown", activateLiveParticipantTabFromKeyboard\)/);
  assert.match(keyboardHandler, /\["ArrowLeft", "ArrowRight", "Home", "End"\]/);
  assert.match(tabs, /actual\.weight/);
  assert.match(tabs, /actual\.reps/);
  assert.doesNotMatch(room, /data-action="start-live-room"/);
  assert.match(room, /tx\("Start together", "Почати разом"\)/);
  assert.match(accept, /refreshAttempts = decision === "accept" \? 3 : 1/);
  assert.match(accept, /\["ready", "active"\]\.includes\(result\.status\)/);
  assert.match(accept, /`ready` is a released compatibility response/);
  assert.match(accept, /snapshot\?\.room\?\.status === "active"/);
  assert.equal((appSource.match(/tx\("Start together", "Почати разом"\)/g) || []).length, 3);
});

test("active live participant tabs wrap focus and activate with arrow, Home, and End keys", () => {
  const handlerSource = sourceBetween(
    "function activateLiveParticipantTabFromKeyboard",
    "function activateDataActionFromKeyboard"
  );
  const context = vm.createContext({});
  vm.runInContext(`${handlerSource}\nglobalThis.liveTabHandler = activateLiveParticipantTabFromKeyboard;`, context);

  function press(startParticipant, key) {
    let selectedParticipant = startParticipant;
    let clickedParticipant = null;
    let focusedParticipant = null;
    let prevented = false;
    let tablist;
    const tabs = ["self", "peer"].map(participant => ({
      dataset: { participant },
      closest: selector => selector === '[role="tablist"]' ? tablist : null,
      click() {
        clickedParticipant = participant;
        selectedParticipant = participant;
      },
      focus(options) {
        if (options?.preventScroll === true) focusedParticipant = participant;
      },
      getAttribute(name) {
        return name === "aria-selected" && selectedParticipant === participant ? "true" : null;
      }
    }));
    tablist = {
      querySelectorAll(selector) {
        assert.equal(selector, '[role="tab"][data-action="active-live-participant"]');
        return tabs;
      }
    };
    context.app = {
      querySelector(selector) {
        const participant = selector.match(/data-participant="(self|peer)"/)?.[1];
        return tabs.find(tab => tab.dataset.participant === participant &&
          tab.getAttribute("aria-selected") === "true") || null;
      }
    };
    context.requestAnimationFrame = callback => callback();
    const handled = context.liveTabHandler({
      key,
      currentTarget: tabs.find(tab => tab.dataset.participant === startParticipant),
      preventDefault() { prevented = true; }
    });
    return { handled, prevented, clickedParticipant, focusedParticipant };
  }

  for (const [start, key, destination] of [
    ["self", "ArrowRight", "peer"],
    ["peer", "ArrowRight", "self"],
    ["self", "ArrowLeft", "peer"],
    ["peer", "Home", "self"],
    ["self", "End", "peer"]
  ]) {
    assert.deepEqual(press(start, key), {
      handled: true,
      prevented: true,
      clickedParticipant: destination,
      focusedParticipant: destination
    });
  }
  assert.deepEqual(press("self", "Tab"), {
    handled: false,
    prevented: false,
    clickedParticipant: null,
    focusedParticipant: null
  });
});
