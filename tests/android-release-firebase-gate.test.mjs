import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { chmod, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const projectRoot = process.cwd();
const helperPath = path.join(projectRoot, "scripts/android-release-firebase-gate.ps1");
const [playScript, phoneScript, firebaseGate, phoneBuild, gitignore] = await Promise.all([
  readFile("scripts/build-play-release-aab.ps1", "utf8"),
  readFile("scripts/build-phone-release-apk.ps1", "utf8"),
  readFile(helperPath, "utf8"),
  readFile("app/build.gradle.kts", "utf8"),
  readFile(".gitignore", "utf8"),
]);

const syntheticFirebaseConfig = Object.freeze({
  project_info: {
    project_number: "123456789012",
    project_id: "gymapp-release-test",
  },
  client: [
    {
      client_info: {
        mobilesdk_app_id: "1:123456789012:android:0123456789abcdef",
        android_client_info: { package_name: "com.setforge.gymapp" },
      },
      api_key: [{ current_key: ["A", "Iza", "A".repeat(32)].join("") }],
    },
  ],
});

async function fileIntegrityDigest(configPath) {
  const { stdout } = await execFileAsync(
    "pwsh",
    [
      "-NoProfile",
      "-Command",
      "(Get-FileHash -Algorithm SHA256 -LiteralPath $env:GYMAPP_TEST_HASH_PATH).Hash.ToLowerInvariant()",
    ],
    {
      env: {
        ...process.env,
        GYMAPP_TEST_HASH_PATH: configPath,
      },
    }
  );
  const digest = stdout.trim();
  assert.match(digest, /^[a-f0-9]{64}$/);
  return digest;
}

async function writeConfig(directory, name, value, mode = 0o600) {
  const configPath = path.join(directory, name);
  const bytes = Buffer.from(JSON.stringify(value), "utf8");
  await writeFile(configPath, bytes, { mode });
  await chmod(configPath, mode);
  return { configPath, digest: await fileIntegrityDigest(configPath) };
}

async function runGate(configPath, expectedSha256, root = projectRoot) {
  const command = [
    ". $env:GYMAPP_TEST_FIREBASE_HELPER",
    "$isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT",
    "Resolve-ReviewedReleaseFirebaseConfig -ProjectRoot $env:GYMAPP_TEST_PROJECT_ROOT -ConfigPath $env:GYMAPP_TEST_FIREBASE_CONFIG -ExpectedSha256 $env:GYMAPP_TEST_FIREBASE_SHA -ExpectedPackageId 'com.setforge.gymapp' -IsWindowsPlatform $isWindowsPlatform | Out-Null",
  ].join("; ");
  return execFileAsync("pwsh", ["-NoProfile", "-Command", command], {
    env: {
      ...process.env,
      GYMAPP_TEST_FIREBASE_HELPER: helperPath,
      GYMAPP_TEST_PROJECT_ROOT: root,
      GYMAPP_TEST_FIREBASE_CONFIG: configPath,
      GYMAPP_TEST_FIREBASE_SHA: expectedSha256,
    },
  });
}

async function createZip(sourceDirectory, archivePath) {
  await execFileAsync(
    "pwsh",
    [
      "-NoProfile",
      "-Command",
      "Compress-Archive -Path (Join-Path $env:GYMAPP_TEST_ZIP_SOURCE '*') -DestinationPath $env:GYMAPP_TEST_ZIP_DESTINATION -Force",
    ],
    {
      env: {
        ...process.env,
        GYMAPP_TEST_ZIP_SOURCE: sourceDirectory,
        GYMAPP_TEST_ZIP_DESTINATION: archivePath,
      },
    }
  );
}

async function runArtifactGate(configPath, expectedSha256, archivePath) {
  const command = [
    ". $env:GYMAPP_TEST_FIREBASE_HELPER",
    "$isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT",
    "$config = Resolve-ReviewedReleaseFirebaseConfig -ProjectRoot $env:GYMAPP_TEST_PROJECT_ROOT -ConfigPath $env:GYMAPP_TEST_FIREBASE_CONFIG -ExpectedSha256 $env:GYMAPP_TEST_FIREBASE_SHA -ExpectedPackageId 'com.setforge.gymapp' -IsWindowsPlatform $isWindowsPlatform",
    "Assert-ReleaseFirebaseArtifact $env:GYMAPP_TEST_ARCHIVE 'APK' $config",
  ].join("; ");
  return execFileAsync("pwsh", ["-NoProfile", "-Command", command], {
    env: {
      ...process.env,
      GYMAPP_TEST_FIREBASE_HELPER: helperPath,
      GYMAPP_TEST_PROJECT_ROOT: projectRoot,
      GYMAPP_TEST_FIREBASE_CONFIG: configPath,
      GYMAPP_TEST_FIREBASE_SHA: expectedSha256,
      GYMAPP_TEST_ARCHIVE: archivePath,
    },
  });
}

test("both production Android release scripts fail closed around reviewed Firebase input", () => {
  for (const [label, script, task, source, kind] of [
    ["Play AAB", playScript, ":app:bundleRelease", "$bundleSource", "AAB"],
    ["phone APK", phoneScript, ":app:assembleRelease", "$phoneApkSource", "APK"],
  ]) {
    assert.match(script, /FirebaseConfigFile\s*=\s*\$env:ORG_GRADLE_PROJECT_gymappFirebaseConfigFile/);
    assert.match(script, /FirebaseConfigSha256\s*=\s*\$env:GYMAPP_FIREBASE_CONFIG_SHA256/);
    assert.match(script, /android-release-firebase-gate\.ps1/);
    const inputGate = script.indexOf("Resolve-ReviewedReleaseFirebaseConfig");
    const build = script.indexOf(task);
    const artifactGate = script.indexOf(`Assert-ReleaseFirebaseArtifact ${source} '${kind}'`);
    const copy = script.indexOf(`Copy-Item -Path ${source}`);
    assert.ok(inputGate >= 0 && inputGate < build, `${label} must validate Firebase before Gradle`);
    assert.ok(artifactGate > build && artifactGate < copy, `${label} must verify Firebase before copy`);
    assert.match(script, /-PgymappFirebaseConfigFile=\$\(\$firebaseConfig\.Path\)/);
    assert.match(script, /-PgymappRequireReviewedFirebaseConfig=true/);
    assert.match(script, /-PgymappFirebaseConfigSha256=\$\(\$firebaseConfig\.Sha256\)/);
    assert.match(script, /Assert-ReleaseFirebaseBuildConfig/);
  }
  assert.match(phoneBuild, /gymappRequireReviewedFirebaseConfig/);
  assert.match(phoneBuild, /gymappFirebaseConfigSha256/);
  assert.match(phoneBuild, /firebaseSha256\(configBytes\) == expectedSha256/);
  assert.match(phoneBuild, /containsFirebaseServerCredential\(root\)/);
});

test("both production release entry points reject missing Firebase path and hash before Gradle", async () => {
  const cleanEnvironment = { ...process.env };
  delete cleanEnvironment.ORG_GRADLE_PROJECT_gymappFirebaseConfigFile;
  delete cleanEnvironment.GYMAPP_FIREBASE_CONFIG_SHA256;
  for (const script of [
    "scripts/build-play-release-aab.ps1",
    "scripts/build-phone-release-apk.ps1",
  ]) {
    await assert.rejects(
      execFileAsync(
        "pwsh",
        ["-NoProfile", "-File", script, "-VersionName", "3.1.1", "-VersionCode", "2000320892"],
        { env: cleanEnvironment }
      ),
      (error) => {
        assert.doesNotMatch(`${error.stdout ?? ""}\n${error.stderr ?? ""}`, /Building (?:Play|phone) release/);
        return true;
      }
    );
  }
});

test("Firebase release gate validates exact external owner-only client config", async (t) => {
  const externalDirectory = await mkdtemp(path.join(tmpdir(), "gymapp-firebase-gate-"));
  t.after(() => rm(externalDirectory, { recursive: true, force: true }));
  const reviewed = await writeConfig(
    externalDirectory,
    "google-services.json",
    syntheticFirebaseConfig
  );
  await runGate(reviewed.configPath, reviewed.digest);

  await assert.rejects(runGate(reviewed.configPath, ""), "missing SHA must fail");
  await assert.rejects(
    runGate(path.join(externalDirectory, "missing.json"), reviewed.digest),
    "missing path must fail"
  );
  await assert.rejects(runGate(reviewed.configPath, "0".repeat(64)), "wrong SHA must fail");

  const wrongPackage = structuredClone(syntheticFirebaseConfig);
  wrongPackage.client[0].client_info.android_client_info.package_name = "com.attacker.app";
  const wrongPackageFile = await writeConfig(
    externalDirectory,
    "wrong-package.json",
    wrongPackage
  );
  await assert.rejects(
    runGate(wrongPackageFile.configPath, wrongPackageFile.digest),
    "wrong package must fail"
  );

  const inconsistentSender = structuredClone(syntheticFirebaseConfig);
  inconsistentSender.client[0].client_info.mobilesdk_app_id =
    "1:999999999999:android:0123456789abcdef";
  const inconsistentSenderFile = await writeConfig(
    externalDirectory,
    "inconsistent-sender.json",
    inconsistentSender
  );
  await assert.rejects(
    runGate(inconsistentSenderFile.configPath, inconsistentSenderFile.digest),
    "application ID sender must match project_info.project_number"
  );

  const clientObject = structuredClone(syntheticFirebaseConfig);
  clientObject.client = clientObject.client[0];
  const clientObjectFile = await writeConfig(
    externalDirectory,
    "client-object.json",
    clientObject
  );
  await assert.rejects(
    runGate(clientObjectFile.configPath, clientObjectFile.digest),
    "client must remain an array"
  );

  const apiKeyObject = structuredClone(syntheticFirebaseConfig);
  apiKeyObject.client[0].api_key = apiKeyObject.client[0].api_key[0];
  const apiKeyObjectFile = await writeConfig(
    externalDirectory,
    "api-key-object.json",
    apiKeyObject
  );
  await assert.rejects(
    runGate(apiKeyObjectFile.configPath, apiKeyObjectFile.digest),
    "api_key must remain an array"
  );

  const projectInfoArray = structuredClone(syntheticFirebaseConfig);
  projectInfoArray.project_info = [projectInfoArray.project_info];
  const projectInfoArrayFile = await writeConfig(
    externalDirectory,
    "project-info-array.json",
    projectInfoArray
  );
  await assert.rejects(
    runGate(projectInfoArrayFile.configPath, projectInfoArrayFile.digest),
    "project_info must remain an object"
  );

  const serviceAccountFile = await writeConfig(externalDirectory, "service-account.json", {
    type: "service_account",
    private_key: "synthetic-test-only",
  });
  await assert.rejects(
    runGate(serviceAccountFile.configPath, serviceAccountFile.digest),
    "server credential JSON must fail"
  );

  if (process.platform !== "win32") {
    const broadMode = await writeConfig(
      externalDirectory,
      "broad-mode.json",
      syntheticFirebaseConfig,
      0o644
    );
    await assert.rejects(
      runGate(broadMode.configPath, broadMode.digest),
      "group/world-readable config must fail"
    );
  }
});

test("artifact gate rejects packaged Firebase JSON and missing reviewed identity", async (t) => {
  const externalDirectory = await mkdtemp(path.join(tmpdir(), "gymapp-firebase-artifact-"));
  t.after(() => rm(externalDirectory, { recursive: true, force: true }));
  const reviewed = await writeConfig(
    externalDirectory,
    "google-services.json",
    syntheticFirebaseConfig
  );
  const identities = [
    syntheticFirebaseConfig.project_info.project_id,
    syntheticFirebaseConfig.project_info.project_number,
    syntheticFirebaseConfig.client[0].client_info.mobilesdk_app_id,
    syntheticFirebaseConfig.client[0].api_key[0].current_key,
  ];

  const packagedDirectory = path.join(externalDirectory, "packaged-json");
  await mkdir(packagedDirectory);
  await writeFile(path.join(packagedDirectory, "classes.dex"), identities.join("\n"));
  await writeFile(path.join(packagedDirectory, "google-services (1).json"), "{}");
  const packagedArchive = path.join(externalDirectory, "packaged-json.zip");
  await createZip(packagedDirectory, packagedArchive);
  await assert.rejects(
    runArtifactGate(reviewed.configPath, reviewed.digest, packagedArchive),
    "packaged Firebase JSON must fail"
  );

  const missingIdentityDirectory = path.join(externalDirectory, "missing-identity");
  await mkdir(missingIdentityDirectory);
  await writeFile(path.join(missingIdentityDirectory, "classes.dex"), identities.slice(0, 3).join("\n"));
  const missingIdentityArchive = path.join(externalDirectory, "missing-identity.zip");
  await createZip(missingIdentityDirectory, missingIdentityArchive);
  await assert.rejects(
    runArtifactGate(reviewed.configPath, reviewed.digest, missingIdentityArchive),
    "missing reviewed Firebase identity must fail"
  );

  const renamedConfigDirectory = path.join(externalDirectory, "renamed-config");
  await mkdir(renamedConfigDirectory);
  await writeFile(path.join(renamedConfigDirectory, "classes.dex"), identities.join("\n"));
  await writeFile(
    path.join(renamedConfigDirectory, "client-settings.json"),
    await readFile(reviewed.configPath)
  );
  const renamedConfigArchive = path.join(externalDirectory, "renamed-config.zip");
  await createZip(renamedConfigDirectory, renamedConfigArchive);
  await assert.rejects(
    runArtifactGate(reviewed.configPath, reviewed.digest, renamedConfigArchive),
    "renamed reviewed Firebase config must fail"
  );
});

test("Firebase release gate rejects a config stored inside the repository", async (t) => {
  const ignoredRoot = path.join(projectRoot, "tmp");
  await mkdir(ignoredRoot, { recursive: true });
  const internalDirectory = await mkdtemp(path.join(ignoredRoot, "firebase-gate-test-"));
  t.after(() => rm(internalDirectory, { recursive: true, force: true }));
  const internal = await writeConfig(
    internalDirectory,
    "google-services.json",
    syntheticFirebaseConfig
  );
  await assert.rejects(
    runGate(internal.configPath, internal.digest),
    "repository-local config must fail"
  );

  if (process.platform !== "win32") {
    const externalDirectory = await mkdtemp(path.join(tmpdir(), "gymapp-firebase-link-target-"));
    t.after(() => rm(externalDirectory, { recursive: true, force: true }));
    const external = await writeConfig(
      externalDirectory,
      "external-client.json",
      syntheticFirebaseConfig
    );
    const internalLink = path.join(internalDirectory, "linked-client.json");
    await symlink(external.configPath, internalLink);
    await assert.rejects(
      runGate(internalLink, external.digest),
      "repository-local symlink entry point must fail"
    );
  }
});

test("Firebase gate checks bounded shape, permissions, artifact identity, and JSON exclusion", () => {
  assert.match(firebaseGate, /ReleaseFirebaseMaxConfigBytes\s*=\s*1MB/);
  assert.match(firebaseGate, /GetUnixFileMode/);
  assert.match(firebaseGate, /owner-only mode 0600/);
  assert.match(firebaseGate, /Windows ACL validation is not implemented/);
  assert.match(firebaseGate, /service_account/);
  assert.match(firebaseGate, /private_key/);
  assert.match(firebaseGate, /clients\.Count -ne 1/);
  assert.match(firebaseGate, /packageId -cne \$ExpectedPackageId/);
  assert.match(firebaseGate, /Groups\['sender'\]\.Value -cne \$senderId/);
  assert.match(firebaseGate, /FIREBASE_CONFIGURED = true/);
  assert.match(firebaseGate, /base\/dex\/classes/);
  assert.match(firebaseGate, /\^google-services\.\*\\\.json\$/);
  assert.doesNotMatch(firebaseGate, /Write-(?:Host|Output|Warning)/i);
});

test("repository ignores only the supported local Firebase config locations", () => {
  assert.match(gitignore, /^google-services\*\.json$/m);
});
