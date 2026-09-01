import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, stylesSource] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/styles.css", "utf8")
]);

function sourceBetween(startMarker, endMarker) {
  const start = appSource.indexOf(startMarker);
  const end = appSource.indexOf(endMarker, start + startMarker.length);
  assert.ok(start >= 0, `${startMarker} must exist`);
  assert.ok(end > start, `${endMarker} must follow ${startMarker}`);
  return appSource.slice(start, end);
}

test("compact auth header uses the deployed app icon and exposes the language control", () => {
  const auth = sourceBetween("function loginScreen()", "function offlineAccountSheetMarkup()");

  assert.match(auth, /class="auth-brand-mark" src="\.\/icon-192\.png"/);
  assert.doesNotMatch(auth, /\.\/icons\//);
  assert.match(auth, /\$\{languageSelectorMarkup\(\)\}/);
  assert.match(appSource, /data-action="language-menu"/);
  assert.match(auth, /data-action="open-offline-account"/);
});

test("profile hub defaults to social training and keeps account controls in a compact second segment", () => {
  const screen = sourceBetween("function friendsProfileScreen()", "function parseSocialGenericSubmission");

  assert.match(appSource, /let profileHubSection = "training";/);
  assert.match(appSource, /accountEpoch \+= 1;\s+profileHubSection = "training";/);
  assert.match(screen, /role="tablist"/);
  assert.match(screen, /id="profile-training-tab"[^>]*aria-controls="profile-training-panel"/);
  assert.match(screen, /id="profile-settings-tab"[^>]*aria-controls="profile-settings-panel"/);
  assert.match(screen, /id="profile-training-panel"[^>]*aria-labelledby="profile-training-tab"/);
  assert.match(screen, /id="profile-settings-panel"[^>]*aria-labelledby="profile-settings-tab"/);
  assert.match(screen, /data-action="profile-hub-section" data-section="training"/);
  assert.match(screen, /data-action="profile-hub-section" data-section="settings"/);
  assert.ok(screen.indexOf("friendsPanel()") < screen.indexOf("themePreferencePanel()"));
  assert.match(stylesSource, /\.profile-hub-passport\s*\{/);
  assert.match(stylesSource, /\.profile-spotter-rail\s*\{/);
  assert.match(stylesSource, /\.profile-hub-panel\[hidden\]\s*\{\s*display:\s*none;\s*\}/);
  assert.match(stylesSource, /@media \(max-width: 460px\)[\s\S]*\.profile-hub-passport/);
});

test("profile hub tabs support automatic WAI-ARIA keyboard activation with wrapped focus", () => {
  const binding = sourceBetween("function bindEvents(", "function activateProfileHubTabFromKeyboard");
  const handlerSource = sourceBetween(
    "function activateProfileHubTabFromKeyboard",
    "function activateDataActionFromKeyboard"
  );
  const context = vm.createContext({});
  vm.runInContext(`${handlerSource}\nglobalThis.profileHubTabHandler = activateProfileHubTabFromKeyboard;`, context);

  assert.match(binding, /\.profile-hub-switch \[role="tab"\]\[data-action="profile-hub-section"\]/);
  assert.match(binding, /addEventListener\("keydown", activateProfileHubTabFromKeyboard\)/);

  function press(startSection, key) {
    let selectedSection = startSection;
    let clickedSection = null;
    let focusedSection = null;
    let focusPreventedScroll = false;
    let prevented = false;
    let tablist;
    const tabs = ["training", "settings"].map(section => ({
      dataset: { section },
      closest: selector => selector === '[role="tablist"]' ? tablist : null,
      click() {
        clickedSection = section;
        selectedSection = section;
      },
      focus(options) {
        focusedSection = section;
        focusPreventedScroll = options?.preventScroll === true;
      },
      getAttribute(name) {
        return name === "aria-selected" && selectedSection === section ? "true" : null;
      }
    }));
    tablist = {
      querySelectorAll: selector => {
        assert.equal(selector, '[role="tab"][data-action="profile-hub-section"]');
        return tabs;
      }
    };
    context.app = {
      querySelector: selector => {
        const section = selector.match(/data-section="(training|settings)"/)?.[1];
        return tabs.find(tab =>
          tab.dataset.section === section && tab.getAttribute("aria-selected") === "true"
        ) || null;
      }
    };
    context.requestAnimationFrame = callback => callback();
    const handled = context.profileHubTabHandler({
      key,
      currentTarget: tabs.find(tab => tab.dataset.section === startSection),
      preventDefault() { prevented = true; }
    });
    return { handled, prevented, clickedSection, focusedSection, focusPreventedScroll };
  }

  const expected = { handled: true, prevented: true, focusPreventedScroll: true };
  for (const [start, key, destination] of [
    ["training", "ArrowRight", "settings"],
    ["training", "ArrowLeft", "settings"],
    ["settings", "ArrowRight", "training"],
    ["settings", "ArrowLeft", "training"],
    ["settings", "Home", "training"],
    ["training", "End", "settings"]
  ]) {
    assert.deepEqual(press(start, key), {
      ...expected,
      clickedSection: destination,
      focusedSection: destination
    });
  }
  assert.deepEqual(press("training", "Tab"), {
    handled: false,
    prevented: false,
    clickedSection: null,
    focusedSection: null,
    focusPreventedScroll: false
  });
});

test("urgent live, workout, and friend requests render before the friend list and settings", () => {
  const panel = sourceBetween("function friendsPanel()", "function friendsProfileScreen()");
  const urgentStart = panel.indexOf("const urgent =");
  const circleStart = panel.indexOf("friends-circle-card");
  const listStart = panel.indexOf("friend-circle-list");
  const codeStart = panel.indexOf("social-code-card");
  const privacyStart = panel.indexOf('data-action="save-social-privacy"', codeStart);

  assert.ok(urgentStart >= 0);
  assert.ok(panel.indexOf("liveWorkoutInboxMarkup()", urgentStart) < circleStart);
  assert.ok(panel.indexOf("socialWorkoutInviteRows()", urgentStart) < circleStart);
  assert.ok(panel.indexOf("socialRequestCards()", urgentStart) < circleStart);
  assert.ok(urgentStart < circleStart && circleStart < listStart && listStart < codeStart && codeStart < privacyStart);
});

test("friend workout preference is explicit, account-fenced, escaped, and cleared with its modal", () => {
  const intent = sourceBetween("function preferredFriendShareIntent", "function openFriendWorkoutPicker");
  const picker = sourceBetween("function openFriendWorkoutPicker", "function socialWorkoutInviteBanner");
  const reset = sourceBetween("function resetRemoteSyncContext", "const CLOUD_SYNC_UI_STATUSES");

  assert.match(intent, /value\.expectedEpoch !== accountEpoch/);
  assert.match(intent, /activeAccount\.userId !== value\.expectedUserId/);
  assert.match(intent, /loadRemoteSession\(\)\?\.user\?\.id !== value\.expectedUserId/);
  assert.match(intent, /SOCIAL_PROFILE_ID_PATTERN\.test\(value\.preferredProfileId/);
  assert.match(intent, /socialState\.dashboard\?\.friends\.some/);
  assert.match(picker, /type: "friend-workout-picker"/);
  assert.match(picker, /expectedEpoch: accountEpoch/);
  assert.match(picker, /escapeHtml\(friend\.displayName\)/);
  assert.match(picker, /escapeAttr\(session\.id\)/);
  assert.match(reset, /modal = null;/);
  assert.match(appSource, /function closeModal\(\) \{[\s\S]*modal = null;/);
  assert.match(appSource, /data-action="create-live-workout-for-friend"/);
  assert.match(appSource, /function createLiveWorkoutForFriend\([\s\S]*friendshipId: friend\.friendshipId[\s\S]*friendshipRevision: friend\.friendshipRevision/);
  assert.doesNotMatch(appSource, /data-action="open-friend-workout-picker" data-share-mode="live"/);
  assert.match(appSource, /data-action="open-friend-workout-picker" data-share-mode="copy"/);
  assert.match(appSource, /social-share-friend-card \$\{isPreferred \? "preferred" : ""\}/);
});

test("signed-out friends state offers a direct, route-fenced cloud sign-in path", () => {
  const panel = sourceBetween("function friendsPanel()", "function friendsProfileScreen()");
  const action = sourceBetween('if (action === "profile-cloud-sign-in")', 'if (action === "refresh-social")');

  assert.match(panel, /empty-state-panel friends-sign-in-card/);
  assert.match(panel, /data-action="profile-cloud-sign-in"/);
  assert.match(panel, /Sign in to connect/);
  assert.match(action, /route\(\)\.name !== "leaderboard"/);
  assert.match(action, /profileHubSection = "settings";\s+render\(\);\s+return logoutAccount\(\);/);
});

test("Fluid Focus interaction contract keeps choices, navigation, and touch targets legible", () => {
  assert.match(stylesSource, /\.chip\.selected\s*\{[\s\S]*?color:\s*var\(--on-accent\);[\s\S]*?background:\s*var\(--sage\);/);
  assert.match(stylesSource, /\.button\.mini\s*\{[\s\S]*?min-height:\s*44px;/);
  assert.match(stylesSource, /\.buttonlike\s*\{[\s\S]*?min-height:\s*44px;/);
  assert.match(stylesSource, /\.period-tabs button\s*\{[\s\S]*?min-height:\s*44px;/);
  assert.match(stylesSource, /html\[lang="ru"\] \.tab-button > span:last-child\s*\{[\s\S]*?text-overflow:\s*clip;/);
  assert.match(stylesSource, /@media \(max-width: 460px\)[\s\S]*?\.profile-hub-switch button strong\s*\{[\s\S]*?text-overflow:\s*clip;[\s\S]*?white-space:\s*normal;/);
  assert.match(stylesSource, /\.active-live-participant-panel:not\(\[hidden\]\)\s*\{[\s\S]*animation:\s*active-live-panel-enter 180ms/);
  assert.match(stylesSource, /\.onboarding-coach\s*\{[\s\S]*max-height:\s*calc\(100dvh[\s\S]*overflow-y:\s*auto;/);
  assert.match(stylesSource, /\.onboarding-actions\s*\{[\s\S]*position:\s*sticky;[\s\S]*bottom:\s*-18px;/);
  assert.match(stylesSource, /@media \(prefers-reduced-motion: reduce\)\s*\{[\s\S]*?\*::after\s*\{[\s\S]*?transition-duration:\s*0\.01ms !important;/);
  assert.match(stylesSource, /@media \(prefers-reduced-motion: reduce\)[\s\S]*?\.active-live-participant-panel\s*\{\s*animation:\s*none;/);
});

test("main empty states explain the next action instead of ending the flow", () => {
  const workouts = sourceBetween("function workoutsScreen()", "function overviewCards");
  const activation = sourceBetween("function activationCard()", "function workoutItem");
  const exercises = sourceBetween("function exercisesScreen()", "function exerciseFilterControls");
  const spotlight = sourceBetween("function spotlight(", "function progressChartPoints");
  const missions = sourceBetween("function missionsScreen()", "function missionGroups");

  assert.match(workouts, /activationCard\(\)/);
  assert.match(activation, /data-action="activation-start"[\s\S]*data-action="activation-manual"/);
  assert.match(exercises, /empty-state-panel[\s\S]*data-action="reset-exercise-filters"/);
  assert.match(appSource, /if \(action === "reset-exercise-filters"\)[\s\S]*?exerciseSortMode = "name";[\s\S]*?render\(\);\s+restoreStableActionFocus\(focusTarget\);\s+return true;/);
  assert.match(spotlight, /data-action="open-add"/);
  assert.match(missions, /empty-state-panel[\s\S]*data-action="open-add"/);
});

test("root navigation has four parity tabs and Progress exposes the shared Goals subtab", () => {
  const nav = sourceBetween("function bottomNav()", "function screenMarkup");
  const workouts = sourceBetween("function workoutsScreen()", "function overviewCards");
  const progress = sourceBetween("function progressScreen()", "function exerciseProgressPanel");

  assert.match(nav, /\[\["workouts"[\s\S]*\["exercises"[\s\S]*\["progress"[\s\S]*\["leaderboard"/);
  assert.doesNotMatch(nav, /\["missions"/);
  assert.match(stylesSource, /\.bottom-nav\s*\{[\s\S]*grid-template-columns:\s*repeat\(4,/);
  assert.doesNotMatch(workouts, /overviewCards\(/);
  assert.match(workouts, /focusOverview\(sessions\)[\s\S]*trainingHistoryMarkup\(\)/);
  assert.match(appSource, /function trainingHistoryMarkup\(\)[\s\S]*id="workout-list-section"[\s\S]*data-action="history-period" data-period="week"[\s\S]*data-action="history-period" data-period="month"/);
  assert.match(progress, /overviewCards\(selectedMonthSessions\(\)\)/);
  assert.match(progress, /exerciseProgressPanel\(\)/);
  assert.match(progress, /missionsScreen\(\)/);
  assert.match(progress, /role="tablist"/);
  assert.match(progress, /data-action="progress-hub-section"/);
  assert.match(progress, /goals:\s*\{[\s\S]*tx\("Goals", "Цілі"\)/);
  assert.match(progress, /selectedSection === "goals"/);
  assert.doesNotMatch(progress, /missions:\s*\{[\s\S]*label:/);
  assert.match(appSource, /current\.name === "missions"[\s\S]*progressHubSection = "goals"/);
});

test("first-entry app tour is account-bound, accessible, deferrable, and replayable from Help", () => {
  const storage = sourceBetween("function onboardingTourAccountDescriptor", "function emptyTrainingGuidance");
  const tour = sourceBetween("function onboardingTourSteps()", "function render()");
  const finish = sourceBetween("function finishOnboardingTour", "function render()");
  const profileData = sourceBetween("function profileDataPanel()", "function garminProfilePanel");
  const deletion = sourceBetween("async function deleteLocalAccount()", "async function logoutAccount");

  assert.match(storage, /ONBOARDING_TOUR_PREFIX/);
  assert.match(storage, /owner:\s*normalized\.remote === "supabase"/);
  assert.match(storage, /schemaVersion:\s*1/);
  assert.match(storage, /tourVersion:\s*ONBOARDING_TOUR_VERSION/);
  assert.match(storage, /\["completed", "skipped"\]/);
  assert.match(tour, /role="dialog" aria-modal="true"/);
  assert.match(tour, /data-action="onboarding-back"/);
  assert.match(tour, /"onboarding-done"\s*:\s*"onboarding-next"/);
  assert.match(tour, /data-action="onboarding-skip"/);
  assert.match(tour, /"onboarding-done"\s*:\s*"onboarding-next"/);
  assert.match(tour, /pendingSharedWorkout/);
  assert.match(tour, /activeWorkout/);
  assert.match(tour, /session\?\.activation_pending/);
  assert.match(tour, /element\.inert = true/);
  assert.match(tour, /event\.key === "Escape"/);
  assert.match(tour, /const candidates = \[/);
  assert.match(tour, /candidate\.top >= bottom \+ gap/);
  assert.match(tour, /candidates\.find\(candidate => fitsViewport\(candidate\) && avoidsSpotlight\(candidate\)\)/);
  assert.match(tour, /const aboveTop = top - gap - coachRect\.height/);
  assert.match(tour, /belowTop \+ coachRect\.height <= viewportHeight - margin/);
  assert.doesNotMatch(finish, /nav\s*=/);
  assert.match(profileData, /data-action="replay-onboarding"/);
  assert.match(profileData, /Show tutorial/);
  assert.match(profileData, /Показати навчання/);
  assert.match(deletion, /onboardingDescriptor\.storageKey/);
  assert.match(stylesSource, /\.onboarding-spotlight[\s\S]*box-shadow:\s*0 0 0 9999px/);
  assert.match(stylesSource, /@media \(prefers-reduced-motion: reduce\)[\s\S]*\.onboarding-spotlight\s*\{\s*transition:\s*none;/);
});

test("social push routing retains opaque type and object ID and authorizes it after refresh", () => {
  const parser = sourceBetween("function parseAppPushData", "async function openLiveWorkoutPushRoom");
  const resolver = sourceBetween("function authoritativeSocialPushObject", "async function openLiveWorkoutPushRoom");
  const opener = sourceBetween("async function openBoundAppPushTarget", "function captureAppPushTargetFromLocation");
  const capture = sourceBetween("function captureAppPushTargetFromLocation", "function showToast");

  assert.match(parser, /socialType/);
  assert.match(parser, /objectId/);
  assert.match(parser, /objectRevision/);
  assert.match(resolver, /await refreshSocialData\(true\)/);
  assert.match(resolver, /expectedEpoch !== accountEpoch/);
  assert.match(resolver, /loadRemoteSession\(\)\?\.user\?\.id !== expectedUserId/);
  assert.match(resolver, /authoritativeSocialPushObject\(target\)/);
  assert.match(resolver, /Notification opened\. Current account data was refreshed\./);
  assert.match(opener, /readStoredWebPushBinding\(\)/);
  assert.match(opener, /stored\.bindingId !== target\.bindingId/);
  assert.match(opener, /stored\.ownerId !== expectedUserId/);
  assert.match(opener, /profileHubSection = "training"/);
  assert.match(capture, /searchParams\.delete\("binding"\)/);
  assert.match(capture, /searchParams\.delete\("social_type"\)/);
  assert.match(capture, /searchParams\.delete\("object"\)/);
  assert.match(capture, /searchParams\.delete\("revision"\)/);
});
