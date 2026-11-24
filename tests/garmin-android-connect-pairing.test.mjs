import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(path, "utf8");

function section(source, start, end) {
  const from = source.indexOf(start);
  assert.notEqual(from, -1, `Missing source marker: ${start}`);
  const to = source.indexOf(end, from + start.length);
  assert.notEqual(to, -1, `Missing source marker: ${end}`);
  return source.slice(from, to);
}

test("Android Watches screen Garmin card offers a one-tap Connect that pairs exactly the tapped watch", async () => {
  const [screen, navGraph, manager, pairing] = await Promise.all([
    read("app/src/main/java/com/example/gymapp/ui/screens/WatchesScreen.kt"),
    read("app/src/main/java/com/example/gymapp/navigation/GymNavGraph.kt"),
    read("app/src/main/java/com/example/gymapp/garmin/GarminSyncManager.kt"),
    read("app/src/main/java/com/example/gymapp/garmin/GarminWatchPairing.kt")
  ]);

  // GarminDeviceCard is the last function in WatchesScreen.kt.
  const card = screen.slice(screen.indexOf("private fun GarminDeviceCard("));
  assert.ok(card.length > 100, "Missing GarminDeviceCard");
  assert.match(card, /garminDeviceOffersConnect\(state, device\)/);
  assert.match(card, /onClick = \{ onConnect\(device\.deviceId\) \}/);
  assert.match(screen, /garminConnectViewModel\.connect\(deviceId, onPairGarminDevice\)/);
  assert.doesNotMatch(card, /remember \{ mutableStateOf<Long\?>/);
  for (const id of ["garmin_connect_action", "garmin_connecting", "garmin_connect_failed", "garmin_connect_reset_pending"]) {
    assert.equal(card.includes(`R.string.${id}`), true, id);
  }
  // The paired tag, the Open-in-Garmin hint and the reset action stay on the card.
  assert.equal(card.includes("R.string.garmin_profile_paired"), true);
  assert.equal(card.includes("R.string.garmin_open_app"), true);
  assert.equal(card.includes("R.string.garmin_reset_pairing_action"), true);
  assert.match(navGraph, /onPairGarminDevice = \{ deviceId ->[\s\S]*garminSyncManager[\s\S]*\.pairWatch\(deviceId\)/);

  const pair = section(manager, "suspend fun pairWatch(deviceId: Long)", "internal fun clearCloudAccountLocalState(");
  // The tap is the choice: no "exactly one connected watch" rule, and a pending reset is never bypassed.
  assert.match(pair, /decideGarminWatchPairing\(/);
  assert.match(pair, /resetPending = resetPending/);
  assert.doesNotMatch(pair, /Connect exactly one Garmin watch/);
  assert.doesNotMatch(pair, /resetWorkout = true/);
  assert.match(pair, /trustDevice\(account, pair\.deviceBinding\)[\s\S]*sendToConnectedDevicesLocked\(/);
  assert.match(pair, /sendLiteBindingSync\(/);
  assert.match(pair, /pairingStateMutex\.withLock[\s\S]*outboundSyncMutex\.withLock/);

  // Inbound messages stay limited to the single pinned watch.
  assert.match(manager, /trustedDeviceBinding\(account\) == sourceBinding/);
  assert.match(manager, /if \(resolution\.binding != deviceBinding\) return false/);
  assert.match(pairing, /AnotherWatchPinned/);
  assert.match(pairing, /ResetPending/);
});

test("Android Garmin Connect strings exist in every locale", async () => {
  for (const dir of ["values", "values-uk", "values-ru"]) {
    const xml = await read(`app/src/main/res/${dir}/strings.xml`);
    for (const id of ["garmin_connect_action", "garmin_connecting", "garmin_connect_failed", "garmin_connect_reset_pending"]) {
      assert.match(xml, new RegExp(`<string name="${id}">[^<]+</string>`), `${dir}/${id}`);
    }
  }
});

test("Android Garmin: Paired means acknowledged; a failed first Connect releases its pin; reset works without the old watch", async () => {
  const [manager, pairing, watchesState] = await Promise.all([
    read("app/src/main/java/com/example/gymapp/garmin/GarminSyncManager.kt"),
    read("app/src/main/java/com/example/gymapp/garmin/GarminWatchPairing.kt"),
    read("app/src/main/java/com/example/gymapp/ui/viewmodel/WatchesState.kt")
  ]);
  assert.match(manager, /trustedForActiveAccount = acknowledged &&\s*trustedBinding == deviceBinding\(device\)/);
  assert.match(manager, /\} finally \{\s*if \(\s*garminPairingRollbackNeeded\(/);
  assert.match(manager, /if \(\(applied \|\| planTooLarge\) && pending\.account != null\) \{\s*markPairingAcknowledged\(/);
  assert.match(manager, /garminResetReleasesLocalPinOnly\(\s*pinnedWatchConnected = connectedPinned != null/);
  // The acknowledgement key must never be scanned as a legacy pin.
  assert.match(manager, /PAIRING_ACK_KEY_PREFIX = "garmin_pairing_ack_v1"/);
  assert.match(pairing, /\(!state\.hasPinnedWatch \|\| device\.pinned\)/);
  assert.match(watchesState, /garmin\.devices\.any \{ it\.trustedForActiveAccount \}/);
});
