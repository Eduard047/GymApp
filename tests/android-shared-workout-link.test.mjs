import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [manifest, navigation, linkCodec] = await Promise.all([
  readFile("app/src/main/AndroidManifest.xml", "utf8"),
  readFile(
    "app/src/main/java/com/example/gymapp/navigation/GymNavGraph.kt",
    "utf8"
  ),
  readFile(
    "app/src/main/java/com/example/gymapp/data/repository/SharedWorkoutLink.kt",
    "utf8"
  ),
]);

test("Android App Link claims only the canonical shared-workout landing path", () => {
  const appLinkFilter = manifest.match(
    /<intent-filter\s+android:autoVerify="true">[\s\S]*?<\/intent-filter>/
  )?.[0];

  assert.ok(appLinkFilter, "verified shared-workout intent filter is missing");
  assert.match(appLinkFilter, /android:host="gymapptracker\.com"/);
  assert.match(appLinkFilter, /android:path="\/workout\/"/);
  assert.doesNotMatch(appLinkFilter, /android:pathPrefix=/);
});

test("shared-workout consent cannot survive process-local inbox generations", () => {
  const consentStart = navigation.indexOf("var approvedSharedWorkoutId");
  const consentEnd = navigation.indexOf("var preferredShareFriendProfileId", consentStart);
  const consentState = navigation.slice(consentStart, consentEnd);

  assert.ok(
    consentStart >= 0 && consentEnd > consentStart,
    "shared-workout approval state is missing"
  );
  assert.match(consentState, /remember\s*\{\s*mutableStateOf<Long\?>\(null\)\s*}/);
  assert.doesNotMatch(consentState, /rememberSaveable/);
});

test("Android shared-workout validation rejects Unicode control and format categories", () => {
  assert.match(linkCodec, /Character\.CONTROL\.toInt\(\)/);
  assert.match(linkCodec, /Character\.FORMAT\.toInt\(\)/);
  assert.match(linkCodec, /Character\.LINE_SEPARATOR\.toInt\(\)/);
  assert.match(linkCodec, /Character\.PARAGRAPH_SEPARATOR\.toInt\(\)/);
});
