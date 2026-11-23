import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = path => readFile(path, "utf8");

test("iOS offers no Garmin token creation, rotation or paste sheet", async () => {
  const account = await read("ios/GymApp-iOS/GymApp/UI/Screens/AccountSettingsView.swift");
  for (const removed of [
    "GarminTokenView",
    "GarminTokenPresentation",
    "GarminSettingsCard",
    "createNewDevice",
    "rotateToken",
    "Pair a brand-new watch",
    "Rotate token",
    "Paste this token"
  ]) {
    assert.equal(account.includes(removed), false, removed);
  }
});

test("iOS cloud-linked watch card is removal-only and gated on an existing cloud device", async () => {
  const account = await read("ios/GymApp-iOS/GymApp/UI/Screens/AccountSettingsView.swift");
  assert.match(account, /enum GarminLegacyCloudCardPolicy[\s\S]*isCloudAccount && cloudDeviceCount > 0/);
  assert.match(account, /GarminLegacyCloudSection\(\s*garminCloud: appState\.garminCloud,\s*isCloudAccount: isCloudAccount/);
  assert.match(account, /Cloud-linked watches/);
  assert.match(account, /New watches connect over Bluetooth\./);
  assert.match(account, /garminCloud\.revokeDevice\(device\)/);
  assert.equal(account.includes("createDevice("), false);
  assert.equal(account.includes("rotateSelectedDeviceToken("), false);
});

test("iOS Profile is the single Garmin connect action with Android-matching states", async () => {
  const profile = await read("ios/GymApp-iOS/GymApp/UI/Screens/ProfileView.swift");
  const phone = await read("ios/GymApp-iOS/GymApp/Services/GarminPhoneSyncService.swift");
  assert.match(profile, /garminPhoneSync\.selectDevices\(\)/);
  assert.match(profile, /"Connecting…", "Підключення…", "Подключение…"/);
  assert.match(profile, /"Connected now", "Зараз підключено", "Сейчас подключено"/);
  assert.match(profile, /"Paired", "Прив’язано", "Привязано"/);
  assert.match(phone, /Couldn't connect\. Open the app on the watch and try again\./);
  assert.match(phone, /Не вдалося підключити\. Відкрийте застосунок на годиннику й повторіть\./);
  assert.match(phone, /Не удалось подключить\. Откройте приложение на часах и повторите\./);
  // Returning from Garmin Connect sends the pairing sync at once.
  assert.match(
    phone,
    /registerDevices\(\)[\s\S]*?synchronizeConnectedDevices\(\)\s*beginConnectingIfNeeded\(\)/
  );
});
