import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [
  contractSource,
  migration,
  androidFriend,
  androidFriendsViewModel,
  androidActive,
  androidRepository,
  androidReservation,
  androidLiveCoordinator,
  androidEnglish,
  androidUkrainian,
  androidRussian,
  iosFriends,
  iosActive,
  iosActiveStore,
  iosReservation,
  iosLiveCoordinator,
  iosCloud,
  pwaIndex,
  pwaApp
] = await Promise.all([
  readFile("shared/friends-live-v2.json", "utf8"),
  readFile("supabase/migrations/20260813111115_start_live_on_accept_and_add_friend_workout_pages.sql", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/screens/FriendDetailScreen.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/viewmodel/FriendsViewModel.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/screens/ActiveWorkoutScreen.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/data/repository/GymRepository.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/data/repository/LiveWorkoutSidecarStore.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/viewmodel/LiveWorkoutViewModel.kt", "utf8"),
  readFile("app/src/main/res/values/strings.xml", "utf8"),
  readFile("app/src/main/res/values-uk/strings.xml", "utf8"),
  readFile("app/src/main/res/values-ru/strings.xml", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/UI/Screens/LeaderboardView.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/UI/Screens/ActiveWorkoutView.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Data/ActiveWorkoutStore.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Data/LiveWorkoutSlotReservationStore.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Services/LiveWorkoutCoordinator.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Services/CloudSyncService.swift", "utf8"),
  readFile("pwa/index.html", "utf8"),
  readFile("pwa/app.js", "utf8")
]);

const contract = JSON.parse(contractSource);

function sqlFunction(name) {
  const marker = `function ${name}`;
  const start = migration.indexOf(marker);
  assert.notEqual(start, -1, `Missing SQL function ${name}`);
  const end = migration.indexOf("$function$;", start);
  assert.notEqual(end, -1, `Unterminated SQL function ${name}`);
  return migration.slice(start, end + "$function$;".length);
}

function jsFunction(name) {
  const marker = `function ${name}`;
  const start = pwaApp.indexOf(marker);
  assert.notEqual(start, -1, `Missing PWA function ${name}`);
  const next = pwaApp.indexOf("\nfunction ", start + marker.length);
  return pwaApp.slice(start, next < 0 ? pwaApp.length : next);
}

test("friends/live v2 contract is the same three-client product", () => {
  assert.equal(contract.schemaVersion, 2);
  assert.equal(contract.productVersion, "3.0.9");
  assert.deepEqual(contract.clients, ["android", "ios", "pwa"]);
  assert.equal(contract.friendWorkoutSharing.summaryConsent.mayAuthorizeExactSets, false);
  assert.equal(contract.friendWorkoutSharing.detailConsent.default, false);
  assert.equal(contract.friendWorkoutSharing.detailConsent.requiresSummaryConsent, true);
  assert.equal(contract.friendWorkoutSharing.page.maximumWorkouts, 5);
  assert.equal(contract.friendWorkoutSharing.page.futureSessions, "ignored");
  assert.equal(contract.friendWorkoutSharing.page.maximumRenderedSetsPerWorkout, 100);
  assert.equal(contract.friendWorkoutSharing.page.notesShared, false);
  assert.equal(contract.friendWorkoutSharing.presentation.boldBlueRecordValues, false);
  assert.deepEqual(contract.friendWorkoutSharing.invalidation.payload, ["version", "kind"]);
  assert.equal(contract.liveWorkout.participants, 2);
  assert.equal(contract.liveWorkout.activeScreen.participantTabs, 2);
  assert.equal(contract.liveWorkout.activeScreen.selfTab, "editableLocalInputs");
  assert.equal(contract.liveWorkout.activeScreen.peerTab, "readOnlyCommittedWeightAndReps");
  assert.equal(contract.liveWorkout.localActiveSlotReservation.ownerCommitPoint, "durableBeforeInviteRpc");
  assert.equal(contract.liveWorkout.localActiveSlotReservation.inviteeCommitPoint, "durableBeforeAcceptRpc");
  assert.equal(contract.liveWorkout.localActiveSlotReservation.standaloneStartWhileReserved, "denyWithoutMutation");
  assert.equal(contract.liveWorkout.localActiveSlotReservation.unknownMutationOutcome, "retainUntilAuthoritativeReconciliation");
  assert.equal(contract.liveWorkout.localActiveSlotReservation.activeTransition, "consumeOnlyAfterLocalDraftAndBindingCommit");
  assert.equal(contract.compatibility.legacyDashboardResponseKeysUnchanged, true);
  assert.equal(contract.compatibility.legacyFriendDetailsResponseKeysUnchanged, true);
});

test("all clients durably reserve the local active slot before live publication or acceptance", () => {
  assert.match(androidLiveCoordinator, /sidecarStore\.reserve[\s\S]*sendLiveWorkoutInvite/);
  assert.match(androidLiveCoordinator, /reserveBeforeRespond[\s\S]*respondLiveWorkoutInvite/);
  assert.match(androidRepository, /withOrdinaryStartPermit[\s\S]*startActiveWorkoutLocked/);
  assert.match(androidReservation, /withLiveStartReservation/);
  assert.match(androidLiveCoordinator, /withLiveStartReservation/);
  assert.match(androidReservation, /LIVE_RESERVATION_KEY_PREFIX/);
  assert.match(androidReservation, /sessionGeneration/);

  assert.match(iosLiveCoordinator, /slotReservation\.reserve[\s\S]*gateway\.sendInvite/);
  assert.match(iosLiveCoordinator, /slotReservation\.reserve[\s\S]*gateway\.respondInvite/);
  assert.match(iosActiveStore, /assertOrdinaryStartAllowed/);
  assert.match(iosActiveStore, /assertLiveStartAllowed/);
  assert.match(iosReservation, /sessionID/);
  assert.match(iosReservation, /writeEnvelopeAtomically/);

  const webSend = jsFunction("sendLiveWorkoutInvite");
  const webAccept = jsFunction("respondLiveWorkoutInvite");
  const webStart = jsFunction("startWorkout");
  assert.ok(webSend.indexOf("reserveLiveWorkoutSlot") < webSend.indexOf("live_send_invite"));
  assert.ok(webAccept.indexOf("reserveLiveWorkoutSlot") < webAccept.indexOf("live_respond_invite"));
  assert.match(webStart, /reservationRead\.status !== "absent"/);
  assert.match(webStart, /reservationRead\.reservation\.roomId !== liveSnapshot/);
  assert.match(pwaApp, /LIVE_WORKOUT_RESERVATION_PREFIX/);
  assert.match(pwaApp, /rebindLiveWorkoutSlotToCurrentSession/);
});

test("Supabase separates summary and exact-set consent and exposes no raw-state oracle", () => {
  assert.match(migration, /add column if not exists share_workout_details boolean not null default false/);
  const capability = sqlFunction("public.social_friend_workout_detail_capability");
  const page = sqlFunction("public.social_friend_workout_page");
  const legacyDetails = sqlFunction("public.social_friend_details");
  assert.match(capability, /social_pair_is_accepted/);
  assert.match(capability, /share_recent_workouts/);
  assert.match(capability, /share_workout_details/);
  assert.doesNotMatch(legacyDetails, /shareWorkoutDetails/);
  assert.match(page, /p_limit is distinct from 5/);
  assert.match(page, /p_cursor is not null/);
  assert.match(page, /share_recent_workouts/);
  assert.match(page, /share_workout_details/);
  assert.match(page, /activity_revision::text/);
  assert.doesNotMatch(page, /session_value::text/);
  assert.match(page, /workout_set_position <= 100/);
  assert.match(page, /exercise_set_position <= 20/);
  assert.match(page, /workout_millis <= \(/);
  assert.doesNotMatch(page, /clock_timestamp\(\) \+ interval '24 hours'/);
  assert.match(migration, /grant execute on function public\.social_friend_workout_page[\s\S]*to authenticated/);
  assert.match(migration, /grant execute on function public\.social_friend_workout_detail_capability[\s\S]*to authenticated/);
});

test("privacy invalidation is private, opaque, and forces authoritative detail closure", () => {
  const broadcast = sqlFunction("gymapp_private.broadcast_social_settings_change");
  assert.match(broadcast, /'gymapp_social_changed'/);
  assert.match(broadcast, /'kind', 'privacy_changed'/);
  assert.doesNotMatch(broadcast, /settingsRevision|share_workout_details|share_recent_workouts/);
  assert.match(pwaApp, /event: "gymapp_social_changed"/);
  assert.match(pwaApp, /parseSocialRealtimeInvalidation/);
  assert.match(pwaApp, /closeExactDetail/);
  assert.match(androidFriendsViewModel, /friendWorkoutDetailsAvailable/);
  assert.match(iosFriends, /authorizedSelectedFriendWorkout/);
});

test("friend workout history stays summary-visible and exact detail is read only", () => {
  assert.match(androidFriend, /FriendWorkoutSummaryCard/);
  assert.match(androidFriend, /FriendWorkoutDetail/);
  assert.match(androidFriend, /friend_workout_sets_private/);
  assert.doesNotMatch(androidFriend, /colorScheme\.primary[\s\S]{0,120}friendRecordMetrics/);
  assert.match(iosFriends, /FriendWorkoutReadOnlyDetailView/);
  assert.match(iosFriends, /Sets are private\./);
  assert.match(iosCloud, /socialFriendWorkoutDetailCapability/);
  assert.match(pwaApp, /social_friend_workout_detail_capability/);
  assert.match(pwaApp, /social_friend_workout_page/);
  const webDetail = jsFunction("friendWorkoutDetailMarkup");
  assert.match(webDetail, /exerciseMediaThumbnail/);
  assert.match(webDetail, /Read only/);
  assert.doesNotMatch(webDetail, /data-action="(?:edit|delete|share|copy)/);
});

test("accepting live starts one room and all clients render exactly two participant tabs", () => {
  const accept = sqlFunction("public.social_respond_live_workout_invite");
  assert.match(accept, /set status = 'active'/);
  assert.match(accept, /insert into gymapp_private\.live_workout_progress/);
  assert.match(accept, /'result', 'joined'/);
  assert.match(accept, /'status', 'ready'/);
  assert.match(androidActive, /LiveParticipantTab\.Self/);
  assert.match(androidActive, /LiveParticipantTab\.Peer/);
  assert.match(androidActive, /LivePeerExerciseCard/);
  assert.match(iosActive, /Text\(selfName\)\.tag\(LiveParticipantSelection\.current\)/);
  assert.match(iosActive, /Text\(peerName\)\.tag\(LiveParticipantSelection\.peer\)/);
  assert.match(iosActive, /livePeerExercisePanel/);
  const webTabs = jsFunction("activeLiveParticipantTabsMarkup");
  assert.equal((webTabs.match(/role="tab"/g) || []).length, 2);
  assert.match(webTabs, /data-participant="self"/);
  assert.match(webTabs, /data-participant="peer"/);
  assert.match(pwaApp, /peerTab.*read|Read only|Лише перегляд/s);
});

test("Friends/live critical copy is present in EN, UK, and RU", () => {
  for (const source of [androidEnglish, androidUkrainian, androidRussian]) {
    assert.match(source, /friend_workout_sets_private/);
    assert.match(source, /friend_workout_read_only/);
    assert.match(source, /friends_privacy_share_workout_details/);
    assert.match(source, /live_workout_peer_read_only/);
  }
  assert.match(iosFriends, /Share exercises, weights, and reps/);
  assert.match(iosFriends, /Показувати вправи, вагу й повтори/);
  assert.match(iosFriends, /Показывать упражнения, вес и повторения/);
  assert.match(pwaApp, /Share exercises, weights, and reps/);
  assert.match(pwaApp, /Показувати вправи, вагу й повтори/);
});

test("browser root is the full versioned PWA, not the retirement landing", () => {
  assert.match(pwaIndex, /rel="manifest"/);
  assert.match(pwaIndex, /app\.v\d+\.js/);
  assert.match(pwaIndex, /styles\.v\d+\.css/);
  assert.doesNotMatch(pwaIndex, /retirement\.v\d+\.(?:js|css)/);
});
