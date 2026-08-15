import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const assetLinks = JSON.parse(
  await readFile("pwa/.well-known/assetlinks.json", "utf8"),
);
const manifest = await readFile("app/src/main/AndroidManifest.xml", "utf8");
const gradle = await readFile("app/build.gradle.kts", "utf8");

const PLAY_APP_SIGNING_CERT =
  "E6:22:07:94:17:97:9C:65:54:50:25:00:68:80:7E:BD:84:D8:9B:5A:3C:1B:DB:71:E8:10:08:2C:98:DA:4F:87";

test("Digital Asset Links delegates GymApp workout URLs to the Play app signer", () => {
  assert.equal(assetLinks.length, 1);

  const [statement] = assetLinks;
  assert.deepEqual(statement.relation, [
    "delegate_permission/common.handle_all_urls",
  ]);
  assert.equal(statement.target.namespace, "android_app");
  assert.equal(statement.target.package_name, "com.setforge.gymapp");
  assert.deepEqual(
    new Set(statement.target.sha256_cert_fingerprints),
    new Set([PLAY_APP_SIGNING_CERT]),
  );
  assert.equal(
    statement.target.sha256_cert_fingerprints.length,
    new Set(statement.target.sha256_cert_fingerprints).size,
  );
  statement.target.sha256_cert_fingerprints.forEach((fingerprint) => {
    assert.match(fingerprint, /^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$/);
  });
});

test("Android manifest and production package remain coupled to the verified domain", () => {
  assert.match(gradle, /applicationId\s*=\s*"com\.setforge\.gymapp"/);
  assert.match(manifest, /<intent-filter android:autoVerify="true">/);
  assert.match(manifest, /android:scheme="https"/);
  assert.match(manifest, /android:host="gymapptracker\.com"/);
  assert.match(manifest, /android:path="\/workout\/"/);
});
