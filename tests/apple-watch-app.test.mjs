import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const iosRoot = "ios/GymApp-iOS";
const project = await readFile(`${iosRoot}/GymApp.xcodeproj/project.pbxproj`, "utf8");
const infoPlist = await readFile(`${iosRoot}/GymAppWatch/Info.plist`, "utf8");
const entitlements = await readFile(`${iosRoot}/GymAppWatch/GymAppWatch.entitlements`, "utf8");
const infoStrings = JSON.parse(await readFile(`${iosRoot}/GymAppWatch/InfoPlist.xcstrings`, "utf8"));

async function swiftFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) return swiftFiles(entryPath);
    return entry.name.endsWith(".swift") ? [entryPath] : [];
  }));
  return nested.flat().sort();
}

function configBlocks(bundleId) {
  const escaped = bundleId.replaceAll(".", "\\.");
  return [...project.matchAll(new RegExp(`buildSettings = \\{[^}]*PRODUCT_BUNDLE_IDENTIFIER = ${escaped};[^}]*\\}`, "g"))]
    .map((match) => match[0]);
}

function setting(block, key) {
  const match = block.match(new RegExp(`^\\s*${key} = ("[^"]*"|[^;]+);$`, "m"));
  return match?.[1];
}

test("GymAppWatch target exists with the watch bundle id, companion id and watchOS 11 deployment", () => {
  assert.match(project, /A00000000000000000000029 \/\* GymAppWatch \*\/ = \{\s*isa = PBXNativeTarget;/);
  assert.match(project, /productType = "com\.apple\.product-type\.application";[\s\S]*?/);
  const blocks = configBlocks("com.setforge.gymapp.ios.watchkitapp");
  assert.equal(blocks.length, 2, "Debug and Release configurations");
  for (const block of blocks) {
    assert.equal(setting(block, "SDKROOT"), "watchos");
    assert.equal(setting(block, "WATCHOS_DEPLOYMENT_TARGET"), "11.0");
    assert.equal(setting(block, "TARGETED_DEVICE_FAMILY"), "4");
    assert.equal(setting(block, "INFOPLIST_KEY_WKCompanionAppBundleIdentifier"), "com.setforge.gymapp.ios");
    assert.equal(setting(block, "CODE_SIGN_ENTITLEMENTS"), "GymAppWatch/GymAppWatch.entitlements");
    assert.equal(setting(block, "INFOPLIST_FILE"), "GymAppWatch/Info.plist");
    assert.ok(setting(block, "INFOPLIST_KEY_NSHealthShareUsageDescription"));
    assert.ok(setting(block, "INFOPLIST_KEY_NSHealthUpdateUsageDescription"));
  }
  const release = blocks.find((block) => /CODE_SIGN_IDENTITY/.test(block));
  assert.ok(release, "Release configuration");
  assert.match(release, /OTHER_SWIFT_FLAGS = "\$\(inherited\) -debug-prefix-map \$\(SRCROOT\)=GymAppSource\/ios\/GymApp-iOS -file-prefix-map \$\(SRCROOT\)=GymAppSource\/ios\/GymApp-iOS";/);
});

test("watch versions equal the iPhone app's versions", () => {
  const app = configBlocks("com.setforge.gymapp.ios");
  const watch = configBlocks("com.setforge.gymapp.ios.watchkitapp");
  assert.equal(app.length, 2);
  const marketing = new Set(app.map((block) => setting(block, "MARKETING_VERSION")));
  const build = new Set(app.map((block) => setting(block, "CURRENT_PROJECT_VERSION")));
  assert.equal(marketing.size, 1);
  assert.equal(build.size, 1);
  for (const block of watch) {
    assert.ok(marketing.has(setting(block, "MARKETING_VERSION")), "MARKETING_VERSION parity");
    assert.ok(build.has(setting(block, "CURRENT_PROJECT_VERSION")), "CURRENT_PROJECT_VERSION parity");
  }
});

test("the iPhone app embeds the watch app in Contents/Watch and depends on it", () => {
  assert.match(
    project,
    /A00000000000000000000022 \/\* Embed Watch Content \*\/ = \{\s*isa = PBXCopyFilesBuildPhase;\s*buildActionMask = 2147483647;\s*dstPath = "\$\(CONTENTS_FOLDER_PATH\)\/Watch";\s*dstSubfolderSpec = 16;\s*files = \(\s*A00000000000000000000021 \/\* GymAppWatch\.app in Embed Watch Content \*\/,/
  );
  const appTarget = project.match(/A00000000000000000000010 \/\* GymApp \*\/ = \{[\s\S]*?productType[^;]*;/)[0];
  assert.match(appTarget, /A00000000000000000000022 \/\* Embed Watch Content \*\//);
  assert.match(appTarget, /A0000000000000000000002E \/\* PBXTargetDependency \*\//);
  assert.match(project, /A0000000000000000000002E \/\* PBXTargetDependency \*\/ = \{\s*isa = PBXTargetDependency;\s*target = A00000000000000000000029 \/\* GymAppWatch \*\/;/);
  const watchTarget = project.match(/A00000000000000000000029 \/\* GymAppWatch \*\/ = \{[\s\S]*?productType[^;]*;/)[0];
  assert.match(watchTarget, /A00000000000000000000025 \/\* GymAppWatchShared \*\//, "watch compiles the shared codec");
});

test("watch Info.plist, entitlements and HealthKit usage strings in EN/UK/RU", () => {
  assert.match(infoPlist, /<key>WKApplication<\/key>\s*<true\/>/);
  assert.match(infoPlist, /<key>WKBackgroundModes<\/key>\s*<array>\s*<string>workout-processing<\/string>/);
  assert.match(entitlements, /<key>com\.apple\.developer\.healthkit<\/key>\s*<true\/>/);
  for (const key of ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"]) {
    const localizations = infoStrings.strings[key]?.localizations ?? {};
    for (const language of ["en", "uk", "ru"]) {
      const value = localizations[language]?.stringUnit?.value ?? "";
      assert.ok(value.includes("Apple Watch"), `${key} ${language}`);
    }
    assert.doesNotMatch(localizations.ru.stringUnit.value, /[іїєґІЇЄҐ]/);
  }
});

test("watch sources stay flat: no gradients, no all-caps, no emoji", async () => {
  const files = [
    ...(await swiftFiles(`${iosRoot}/GymAppWatch`)),
    ...(await swiftFiles(`${iosRoot}/GymAppWatchShared`)),
  ];
  assert.ok(files.length >= 10);
  for (const file of files) {
    const source = await readFile(file, "utf8");
    assert.doesNotMatch(source, /Gradient|\.shadow\(|textCase\(\.uppercase\)|\.uppercased\(\)/, file);
    assert.doesNotMatch(source, /\p{Extended_Pictographic}/u, file);
  }
});

test("watch uses the shared codec and the crash-safe finish order", async () => {
  const model = await readFile(`${iosRoot}/GymAppWatch/WatchAppModel.swift`, "utf8");
  const save = model.slice(model.indexOf("func saveWorkout()"));
  // The message is validated before the Health session is ended, so a workout that
  // cannot be encoded stays open on Summary with a message and a working Save.
  const order = ["guard let preflight = encoded(", "health.end(", "outboxStore.save(item)", "health.finishWorkout()", "activeStore.clear()", "flushOutbox()"]
    .map((needle) => save.indexOf(needle));
  assert.ok(order.every((index) => index >= 0), "all finish steps present");
  assert.deepEqual([...order].sort((a, b) => a - b), order, "outbox item is written before the Health save");
  const saveBody = save.slice(0, save.indexOf("func closeResult()"));
  assert.equal(saveBody.match(/saveFailed\(current\)/g)?.length, 2, "both early exits report the failure");
  assert.doesNotMatch(saveBody, /phase = \.summary/, "no silent return to Summary");
  // A failed save of an owner deleted on the phone mid-save discards the workout instead of keeping Save.
  assert.match(model, /private func saveFailed\(_ current: WatchActiveWorkout\) \{\s+let ownerDeleted = WatchOutboxPolicy\.discardsAfterFailedSave\(current, deletedWhileSaving: deletedWhileSaving\)\s+deletedWhileSaving\.removeAll\(\)\s+if ownerDeleted \{\s+discardDeletedOwnersWorkout\(current\)\s+return\s+\}\s+phase = \.summary\s+summaryStatus = text\(\.saveFailed\)/);
  assert.match(model, /WatchSyncCodec\.decodeContext\(bytes\)/);
  // A context or reply of another protocol version is not dropped whole, and an
  // unsupported-version hold follows the phone's context version.
  assert.match(model, /WatchSyncCodec\.decodeContextHeader\(bytes\)/);
  assert.match(model, /WatchSyncCodec\.decodeReplyTolerant\(bytes\)/);
  assert.match(model, /WatchOutboxPolicy\.apply\(reply, to: item, nowMillis: now, contextProtocolVersion: phoneProtocolVersion\)/);
  assert.match(model, /WatchOutboxPolicy\.applyContext\(merged, to: item, nowMillis: now, protocolVersion: header\.protocolVersion\)/);
  // A permanent rejection is not shown as "will send later"; a lost Health session is "failed".
  assert.match(model, /next\.status == \.failed \{\s+phase = \.result\(\.failed\)/);
  assert.match(model, /WatchWorkoutModel\.markHealthLost\(/);
  assert.match(model, /WatchWorkoutModel\.healthKitStatus\(current\)/);
  // The item being finished is never flushed or rewritten after a send, and a snapshot
  // of an already finished workout is not restored.
  assert.match(model, /outstanding\.insert\(savingRequestId\)/);
  assert.match(model, /WatchOutboxPolicy\.rewriting\(live, envelope: failed\.envelope\)/);
  assert.match(model, /WatchOutboxPolicy\.isAlreadyFinished\(requestId: restored\.requestId, outbox: outbox\)/);
  // Debug seeds never reach Release.
  const debugExtension = model.indexOf("#if DEBUG\nextension WatchAppModel {");
  assert.ok(debugExtension > 0 && model.indexOf("func debugDeliver(") > debugExtension, "debug seeds are DEBUG-only");
});

test("watch debug seeds are compiled out of Release", async () => {
  const { readdir } = await import("node:fs/promises");
  const root = `${iosRoot}/GymAppWatch`;
  const names = (await readdir(root, { recursive: true })).filter((name) => name.endsWith(".swift"));
  let mentions = 0;
  for (const name of names) {
    const source = await readFile(`${root}/${name}`, "utf8");
    const stack = [];
    source.split("\n").forEach((line, index) => {
      const trimmed = line.trim();
      if (trimmed.startsWith("#if ")) stack.push(trimmed === "#if DEBUG");
      else if (trimmed === "#else" || trimmed.startsWith("#elseif")) stack[stack.length - 1] = false;
      else if (trimmed === "#endif") stack.pop();
      else if (/WatchDebugSeed|AWDebugSeed|applyDebugSeed|debugSeedApplied|debugDeliver|debugShowScreen/.test(line)) {
        mentions += 1;
        assert.ok(stack.includes(true), `${name}:${index + 1} debug seed code outside #if DEBUG`);
      }
    });
  }
  assert.ok(mentions > 10, "debug seed hooks found");
  const seed = await readFile(`${root}/WatchDebugSeed.swift`, "utf8");
  assert.match(seed.trim(), /^#if DEBUG[\s\S]*#endif$/);
});
