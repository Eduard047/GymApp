import assert from "node:assert/strict";
import {
  chmod,
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { existsSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const TRUSTED_FINGERPRINT =
  "926b106c47125ddc97aef9801ffd4812f54562140122bb30f792493ed92adb47";

function commandExists(command) {
  const versionArguments = command === "openssl" ? ["version"] : ["--version"];
  return spawnSync(command, versionArguments, { stdio: "ignore" }).status === 0;
}

function run(command, args, options = {}) {
  return spawnSync(command, args, {
    encoding: "utf8",
    ...options,
  });
}

function findJavaRuntime() {
  const executable = process.platform === "win32" ? "java.exe" : "java";
  const candidates = [
    process.env.JAVA_HOME && join(process.env.JAVA_HOME, "bin", executable),
    process.platform === "darwin" &&
      "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java",
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (existsSync(candidate) && run(candidate, ["-version"]).status === 0) {
      return candidate;
    }
  }
  return commandExists("java") ? "java" : null;
}

async function findMonkeybrainsJar() {
  const connectIqRoot = process.platform === "win32"
    ? join(process.env.APPDATA || "", "Garmin", "ConnectIQ")
    : join(
      homedir(),
      "Library",
      "Application Support",
      "Garmin",
      "ConnectIQ",
    );
  try {
    const sdk = (await readFile(join(connectIqRoot, "current-sdk.cfg"), "utf8"))
      .trim();
    const jar = join(sdk, "bin", "monkeybrains.jar");
    return existsSync(jar) ? jar : null;
  } catch {
    return null;
  }
}

test("Garmin release scripts pin RSA-4096 and preserve outputs until readback", async () => {
  const [shell, powershell, verifier, readme] = await Promise.all([
    readFile("scripts/build-garmin.sh", "utf8"),
    readFile("scripts/build-garmin.ps1", "utf8"),
    readFile("scripts/VerifyGarminIq.java", "utf8"),
    readFile("garmin/README.md", "utf8"),
  ]);

  for (const script of [shell, powershell]) {
    assert.match(script, new RegExp(TRUSTED_FINGERPRINT));
    assert.doesNotMatch(script, /allow-key-rotation|AllowKeyRotation/i);
    assert.match(script, /RSA-4096|4096/);
    assert.match(script, /trusted public-key fingerprint|pinned Store identity/);
    assert.match(script, /temporary/i);
  }
  const powerShellVersionGate = powershell.indexOf(
    "$PSVersionTable.PSVersion.Major -lt 7",
  );
  assert.ok(powerShellVersionGate >= 0);
  assert.ok(
    powerShellVersionGate < powershell.indexOf("ImportPkcs8PrivateKey"),
    "PowerShell 7 gate must run before .NET 7-only key APIs",
  );
  assert.match(powershell, /PowerShell 7 or newer is required[\s\S]*pwsh -File/);
  assert.match(readme, /pwsh -File \.\\scripts\\build-garmin\.ps1/g);
  assert.match(readme, /Windows PowerShell[\s\S]*5\.1 is not supported/);
  assert.doesNotMatch(readme, /^\.\\scripts\\build-garmin\.ps1/gm);
  assert.match(shell, /mode="compile-only"/);
  assert.match(shell, /--sanitize-debug-paths/);
  assert.match(
    shell,
    /temporary_output="\$raw_release_root\/gymapp-garmin-connect-iq\.iq"/,
  );
  assert.match(
    shell,
    /sanitized_release_output="\$sanitized_release_root\/gymapp-garmin-connect-iq\.iq"/,
  );
  assert.match(shell, /--sanitize-debug-paths[\s\S]*>\/dev\/null 2>&1/);
  assert.match(shell, /--sanitize-debug-paths[\s\S]*"\$project_root"/);
  assert.match(shell, /"\$monkeyc" "\$\{compiler_args\[@\]\}" >\/dev\/null 2>&1/);
  assert.match(shell, /mv -f -- "\$sanitized_release_output" "\$output"/);
  assert.doesNotMatch(shell, /rm -f -- "\$output"/);
  assert.match(powershell, /--sanitize-debug-paths/);
  assert.match(powershell, /\$temporaryOutput = Join-Path \$rawReleaseRoot \$outputName/);
  assert.match(
    powershell,
    /\$sanitizedReleaseOutput = Join-Path \$sanitizedReleaseRoot \$outputName/,
  );
  assert.match(powershell, /--sanitize-debug-paths[^\n]*\*> \$null/);
  assert.match(powershell, /--sanitize-debug-paths[^\n]*\$projectRoot/);
  assert.match(powershell, /& \$monkeycPath @compilerArgs \*> \$null/);
  assert.match(
    powershell,
    /\[System\.IO\.File\]::Move\(\$sanitizedReleaseOutput, \$output, \$true\)/,
  );
  assert.doesNotMatch(
    powershell,
    /Remove-Item -LiteralPath \$output/,
  );

  assert.match(verifier, /name\.equals\("manifest\.sig2"\) && entry\.getSize\(\) == 512/);
  assert.match(verifier, /name\.equals\("dev_key\.pub"\)/);
  assert.match(verifier, /name\.endsWith\("\.prg"\)/);
  assert.match(verifier, /gymapp-garmin-connect-iq\.prg/);
  assert.match(verifier, /non-canonical compiled program name/);
  assert.match(verifier, /while \(\(count = archive\.read\(buffer\)\) != -1\)/);
  assert.match(verifier, /sanitizeDebugPaths/);
  assert.match(verifier, /sourceNonDebugHashes\.equals\(result\.nonDebugHashes\)/);
  assert.match(verifier, /Garmin IQ package contains an unsafe local source path/);
  assert.match(verifier, /MAX_TOTAL_UNCOMPRESSED_BYTES - total/);
  assert.match(verifier, /normalized\.split\("\/", -1\)/);
  assert.match(readme, /equal-byte-length neutral relative/);
  assert.match(readme, /SHA-256[\s\S]*every non-debug entry/);
  assert.match(readme, /does not expose a standalone cryptographic signature/);
  assert.match(readme, /cannot override it/);
});

test("IQ readback rejects directory lookalikes and unsafe path segments", async (t) => {
  const java = findJavaRuntime();
  const monkeybrains = await findMonkeybrainsJar();
  if (!java || !monkeybrains) {
    t.skip("Connect IQ SDK Java package reader is unavailable");
    return;
  }

  const root = await mkdtemp(join(tmpdir(), "gymapp-iq-readback-test-"));
  try {
    const fixtureSource = join(root, "CreateIqFixture.java");
    const inspectSource = join(root, "InspectIqFixture.java");
    await Promise.all([
        writeFile(
          fixtureSource,
          `import java.io.File;\n` +
            `import java.nio.charset.StandardCharsets;\n` +
            `import org.apache.commons.compress.archivers.sevenz.SevenZArchiveEntry;\n` +
            `import org.apache.commons.compress.archivers.sevenz.SevenZOutputFile;\n` +
            `public final class CreateIqFixture {\n` +
            `  private static void add(SevenZOutputFile out, String name, boolean directory, byte[] bytes) throws Exception {\n` +
            `    SevenZArchiveEntry entry = new SevenZArchiveEntry();\n` +
            `    entry.setName(name);\n` +
            `    entry.setDirectory(directory);\n` +
            `    entry.setSize(directory ? 0 : bytes.length);\n` +
            `    out.putArchiveEntry(entry);\n` +
            `    if (!directory) out.write(bytes);\n` +
            `    out.closeArchiveEntry();\n` +
            `  }\n` +
            `  public static void main(String[] args) throws Exception {\n` +
            `    String scenario = args[1];\n` +
            `    try (SevenZOutputFile out = new SevenZOutputFile(new File(args[0]))) {\n` +
            `      boolean lookalikes = scenario.equals("directory-lookalikes");\n` +
            `      add(out, "manifest.xml", lookalikes, new byte[] { 1 });\n` +
            `      add(out, "manifest.sig2", false, new byte[512]);\n` +
            `      add(out, "dev_key.pub", lookalikes, new byte[512]);\n` +
            `      String programName = scenario.equals("nondeterministic-program")\n` +
            `        ? "device/.gymapp-garmin-connect-iq.12345.prg"\n` +
            `        : "device/gymapp-garmin-connect-iq.prg";\n` +
            `      byte[] programBytes;\n` +
            `      if (scenario.equals("binary-drive-lookalike")) {\n` +
            `        programBytes = new byte[] { 2, 3, 4, 0x63, (byte) 0xef, 0x50, 0x3a, 0x2f, 0x3a, 0x49, (byte) 0xa3, 5 };\n` +
            `      } else if (scenario.equals("prg-user-root-boundary")) {\n` +
            `        programBytes = new byte[65600];\n` +
            `        programBytes[0] = 2;\n` +
            `        byte[] leak = "/Users/private/GymStore.mc".getBytes(StandardCharsets.UTF_8);\n` +
            `        System.arraycopy(leak, 0, programBytes, 65533, leak.length);\n` +
            `      } else {\n` +
            `        programBytes = new byte[] { 2, 3, 4 };\n` +
            `      }\n` +
            `      add(out, programName, lookalikes, programBytes);\n` +
            `      if (scenario.equals("debug")) {\n` +
            `        add(out, "device/debug.xml", false, args[2].getBytes(StandardCharsets.UTF_8));\n` +
            `      } else if (scenario.equals("nondebug")) {\n` +
            `        add(out, "device/settings.json", false, args[2].getBytes(StandardCharsets.UTF_8));\n` +
            `      } else if (!lookalikes && !scenario.equals("valid") && !scenario.equals("nondeterministic-program") && !scenario.equals("binary-drive-lookalike") && !scenario.equals("prg-user-root-boundary")) {\n` +
            `        add(out, scenario, false, new byte[] { 5 });\n` +
            `      }\n` +
            `    }\n` +
            `  }\n` +
            `}\n`,
        ),
        writeFile(
          inspectSource,
          `import java.io.ByteArrayOutputStream;\n` +
            `import java.nio.file.Path;\n` +
            `import java.security.MessageDigest;\n` +
            `import java.util.Base64;\n` +
            `import org.apache.commons.compress.archivers.sevenz.SevenZArchiveEntry;\n` +
            `import org.apache.commons.compress.archivers.sevenz.SevenZFile;\n` +
            `public final class InspectIqFixture {\n` +
            `  private static String hex(byte[] bytes) {\n` +
            `    StringBuilder value = new StringBuilder();\n` +
            `    for (byte item : bytes) value.append(String.format("%02x", item & 255));\n` +
            `    return value.toString();\n` +
            `  }\n` +
            `  public static void main(String[] args) throws Exception {\n` +
            `    try (SevenZFile archive = SevenZFile.builder().setFile(Path.of(args[0]).toFile()).get()) {\n` +
            `      SevenZArchiveEntry entry;\n` +
            `      byte[] buffer = new byte[8192];\n` +
            `      while ((entry = archive.getNextEntry()) != null) {\n` +
            `        if (entry.isDirectory()) continue;\n` +
            `        ByteArrayOutputStream bytes = new ByteArrayOutputStream();\n` +
            `        int count;\n` +
            `        while ((count = archive.read(buffer)) != -1) bytes.write(buffer, 0, count);\n` +
            `        byte[] content = bytes.toByteArray();\n` +
            `        if (entry.getName().endsWith("debug.xml")) {\n` +
            `          System.out.println("DEBUG\\t" + Base64.getEncoder().encodeToString(content));\n` +
            `        } else {\n` +
            `          System.out.println("HASH\\t" + entry.getName() + "\\t" + hex(MessageDigest.getInstance("SHA-256").digest(content)));\n` +
            `        }\n` +
            `      }\n` +
            `    }\n` +
            `  }\n` +
            `}\n`,
        ),
    ]);

    const createFixture = (name, scenario, content) => {
      const iq = join(root, name);
      const args = [
        "-cp",
        monkeybrains,
        fixtureSource,
        iq,
        scenario,
      ];
      if (content !== undefined) args.push(content);
      const created = run(java, args);
      assert.equal(created.status, 0, created.stdout + created.stderr);
      return iq;
    };
    const verify = (iq) => run(java, [
      "-cp",
      monkeybrains,
      "scripts/VerifyGarminIq.java",
      iq,
    ]);
    const inspect = (iq) => {
      const inspected = run(java, ["-cp", monkeybrains, inspectSource, iq]);
      assert.equal(inspected.status, 0, inspected.stdout + inspected.stderr);
      const hashes = {};
      const debug = [];
      for (const line of inspected.stdout.trim().split("\n").filter(Boolean)) {
        const [kind, nameOrValue, value] = line.split("\t");
        if (kind === "HASH") hashes[nameOrValue] = value;
        if (kind === "DEBUG") debug.push(Buffer.from(nameOrValue, "base64"));
      }
      return { hashes, debug };
    };

    const valid = verify(createFixture("valid.iq", "valid"));
    assert.equal(valid.status, 0, valid.stdout + valid.stderr);

    const binaryDriveLookalike = createFixture(
      "binary-drive-lookalike.iq",
      "binary-drive-lookalike",
    );
    const binaryDriveVerification = verify(binaryDriveLookalike);
    assert.equal(
      binaryDriveVerification.status,
      0,
      binaryDriveVerification.stdout + binaryDriveVerification.stderr,
    );
    const binaryDriveSanitized = join(root, "binary-drive-lookalike-sanitized.iq");
    const binaryDriveSanitization = run(java, [
      "-cp",
      monkeybrains,
      "scripts/VerifyGarminIq.java",
      "--sanitize-debug-paths",
      binaryDriveLookalike,
      binaryDriveSanitized,
      "/private/tmp/gymapp-binary-lookalike.fixture",
    ]);
    assert.equal(
      binaryDriveSanitization.status,
      0,
      binaryDriveSanitization.stdout + binaryDriveSanitization.stderr,
    );
    assert.deepEqual(
      inspect(binaryDriveSanitized).hashes,
      inspect(binaryDriveLookalike).hashes,
    );

    const boundaryUserRootIq = createFixture(
      "prg-user-root-boundary.iq",
      "prg-user-root-boundary",
    );
    const boundaryUserRootLeak = verify(boundaryUserRootIq);
    assert.notEqual(boundaryUserRootLeak.status, 0);
    assert.match(
      boundaryUserRootLeak.stdout + boundaryUserRootLeak.stderr,
      /unsafe local source path/,
    );
    const boundaryUserRootDestination = join(
      root,
      "prg-user-root-boundary-sanitized.iq",
    );
    const boundaryUserRootSanitization = run(java, [
      "-cp",
      monkeybrains,
      "scripts/VerifyGarminIq.java",
      "--sanitize-debug-paths",
      boundaryUserRootIq,
      boundaryUserRootDestination,
      "/private/tmp/gymapp-prg-boundary.fixture",
    ]);
    assert.notEqual(boundaryUserRootSanitization.status, 0);
    assert.match(
      boundaryUserRootSanitization.stdout + boundaryUserRootSanitization.stderr,
      /outside debug metadata/,
    );
    assert.equal(existsSync(boundaryUserRootDestination), false);

    const nondeterministicProgram = verify(
      createFixture("nondeterministic-program.iq", "nondeterministic-program"),
    );
    assert.notEqual(nondeterministicProgram.status, 0);
    assert.match(
      nondeterministicProgram.stdout + nondeterministicProgram.stderr,
      /non-canonical compiled program name/,
    );

    const lookalikes = verify(
      createFixture("directory-lookalikes.iq", "directory-lookalikes"),
    );
    assert.notEqual(lookalikes.status, 0);
    assert.match(lookalikes.stdout + lookalikes.stderr, /missing its manifest/);

    for (const [index, unsafePath] of [
      ".",
      "..",
      "foo//bar",
      "foo/./bar",
      "foo/../bar",
      "/absolute",
      "C:/absolute",
      "foo\\\\..\\\\bar",
    ].entries()) {
      const invalid = verify(
        createFixture(`unsafe-${index}.iq`, unsafePath),
      );
      assert.notEqual(invalid.status, 0, `accepted unsafe path: ${unsafePath}`);
      assert.match(invalid.stdout + invalid.stderr, /unsafe or duplicate entry/);
    }

    const trustedBuildRoot = "/private/tmp/gymapp-v308-release.fixture";
    const leakyDebug = String.raw`<debug><file path="${trustedBuildRoot}/garmin/source/GymStore.mc"/><file path="/Users/sensitive-user/work/GymApp.mc"/><file path="/home/sensitive-user/work/GymComm.mc"/><file path="C:\Users\sensitive-user\work\GymSession.mc"/><file path="\Users/sensitive-user/work/RootedView.mc"/><file path="D:/work/WorkoutView.mc"/></debug>`;
    const leakyIq = createFixture("leaky.iq", "debug", leakyDebug);
    const rawVerification = verify(leakyIq);
    assert.notEqual(rawVerification.status, 0);
    assert.match(rawVerification.stdout + rawVerification.stderr, /unsafe local source path/);
    assert.doesNotMatch(rawVerification.stdout + rawVerification.stderr, /sensitive-user/);

    const sanitizedIq = join(root, "sanitized.iq");
    const sanitized = run(java, [
      "-cp",
      monkeybrains,
      "scripts/VerifyGarminIq.java",
      "--sanitize-debug-paths",
      leakyIq,
      sanitizedIq,
      trustedBuildRoot,
    ]);
    assert.equal(sanitized.status, 0, sanitized.stdout + sanitized.stderr);
    const sanitizedVerification = verify(sanitizedIq);
    assert.equal(
      sanitizedVerification.status,
      0,
      sanitizedVerification.stdout + sanitizedVerification.stderr,
    );

    const rawContents = inspect(leakyIq);
    const sanitizedContents = inspect(sanitizedIq);
    assert.deepEqual(sanitizedContents.hashes, rawContents.hashes);
    assert.equal(rawContents.debug.length, 1);
    assert.equal(sanitizedContents.debug.length, 1);
    assert.equal(sanitizedContents.debug[0].length, rawContents.debug[0].length);
    const sanitizedDebug = sanitizedContents.debug[0].toString("utf8");
    assert.notEqual(sanitizedDebug, leakyDebug);
    assert.doesNotMatch(
      sanitizedDebug,
      /\/private\/tmp\/|\/Users\/|\/home\/|\\Users\\|(?:^|[^A-Za-z0-9_])[A-Za-z]:[\\/]/,
    );
    assert.match(sanitizedDebug, /GymStore\.mc/);
    assert.match(sanitizedDebug, /GymApp\.mc/);
    assert.match(sanitizedDebug, /GymComm\.mc/);
    assert.match(sanitizedDebug, /GymSession\.mc/);
    assert.match(sanitizedDebug, /RootedView\.mc/);
    assert.match(sanitizedDebug, /WorkoutView\.mc/);

    for (const [name, rejectedPath] of [
      ["source-root-lookalike", `${trustedBuildRoot}-other/garmin/source/GymStore.mc`],
      ["source-root-traversal", `${trustedBuildRoot}/../private/GymStore.mc`],
      ["unrelated-private-temp", "/private/tmp/unrelated/GymStore.mc"],
    ]) {
      const rejectedDebug = createFixture(
        `${name}.iq`,
        "debug",
        `<debug><file path="${rejectedPath}"/></debug>`,
      );
      const rejectedDestination = join(root, `${name}-sanitized.iq`);
      const rejected = run(java, [
        "-cp",
        monkeybrains,
        "scripts/VerifyGarminIq.java",
        "--sanitize-debug-paths",
        rejectedDebug,
        rejectedDestination,
        trustedBuildRoot,
      ]);
      assert.notEqual(rejected.status, 0, `accepted ${name}`);
      assert.equal(existsSync(rejectedDestination), false);
    }

    for (const [index, unsafeRoot] of [
      "/Users/sensitive-user/private/settings.json",
      "/home/sensitive-user/private/settings.json",
      String.raw`\Users\sensitive-user\private\settings.json`,
      String.raw`\Users/sensitive-user/private/settings.json`,
      String.raw`C:\private\settings.json`,
      "D:/private/settings.json",
      "C:/x",
      "C:/é/private",
      "C:/#private",
    ].entries()) {
      const unsafeNonDebug = createFixture(
        `unsafe-nondebug-${index}.iq`,
        "nondebug",
        JSON.stringify({ source: unsafeRoot }),
      );
      const rejectedDestination = join(root, `must-not-exist-${index}.iq`);
      const rejected = run(java, [
        "-cp",
        monkeybrains,
        "scripts/VerifyGarminIq.java",
        "--sanitize-debug-paths",
        unsafeNonDebug,
        rejectedDestination,
        trustedBuildRoot,
      ]);
      assert.notEqual(rejected.status, 0);
      assert.match(rejected.stdout + rejected.stderr, /outside debug metadata/);
      assert.doesNotMatch(rejected.stdout + rejected.stderr, /sensitive-user/);
      assert.equal(existsSync(rejectedDestination), false);
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test(
  "invalid Garmin keys fail before monkeyc and a failed build keeps the prior artifact",
  {
    skip: process.platform === "win32" ||
      !commandExists("openssl") || !commandExists("pwsh"),
  },
  async () => {
    const root = await mkdtemp(join(tmpdir(), "gymapp-garmin-release-test-"));
    try {
      const project = join(root, "project");
      const scripts = join(project, "scripts");
      const garmin = join(project, "garmin");
      const outputRoot = join(garmin, "build");
      const sdk = join(root, "sdk");
      const sdkBin = join(sdk, "bin");
      const home = join(root, "home");
      const connectIq = join(
        home,
        "Library",
        "Application Support",
        "Garmin",
        "ConnectIQ",
      );
      const fakeJdk = join(root, "fake-jdk");
      const marker = join(root, "monkeyc-invoked");
      await Promise.all([
        mkdir(scripts, { recursive: true }),
        mkdir(outputRoot, { recursive: true }),
        mkdir(sdkBin, { recursive: true }),
        mkdir(connectIq, { recursive: true }),
        mkdir(join(fakeJdk, "bin"), { recursive: true }),
      ]);
      await Promise.all([
        copyFile("scripts/build-garmin.sh", join(scripts, "build-garmin.sh")),
        copyFile("scripts/build-garmin.ps1", join(scripts, "build-garmin.ps1")),
        copyFile("scripts/VerifyGarminIq.java", join(scripts, "VerifyGarminIq.java")),
        writeFile(join(garmin, "monkey.jungle"), "# synthetic fixture\n"),
        writeFile(join(connectIq, "current-sdk.cfg"), `${sdk}\n`),
        writeFile(join(sdkBin, "monkeybrains.jar"), "synthetic fixture"),
        writeFile(
          join(fakeJdk, "bin", "java"),
          "#!/usr/bin/env bash\nexit 0\n",
        ),
        writeFile(
          join(sdkBin, "monkeyc"),
          `#!/usr/bin/env bash\n` +
            `output=""\n` +
            `while [[ $# -gt 0 ]]; do\n` +
            `  if [[ "$1" == "-o" ]]; then output="$2"; shift 2; else shift; fi\n` +
            `done\n` +
            `printf '%s' "$output" > "$FAKE_MONKEYC_MARKER"\n` +
            `printf partial > "$output"\n` +
            `printf 'failed %s\\n' "$output" >&2\n` +
            `exit 17\n`,
        ),
      ]);
      await Promise.all([
        chmod(join(scripts, "build-garmin.sh"), 0o755),
        chmod(join(sdkBin, "monkeyc"), 0o755),
        chmod(join(fakeJdk, "bin", "java"), 0o755),
      ]);

      const key2048Pem = join(root, "rsa-2048.pem");
      const key2048Der = join(root, "rsa-2048.der");
      const key4096Pem = join(root, "rsa-4096.pem");
      const key4096Der = join(root, "rsa-4096.der");
      const public4096Der = join(root, "rsa-4096-public.der");
      for (const [bits, pem, der] of [
        [2048, key2048Pem, key2048Der],
        [4096, key4096Pem, key4096Der],
      ]) {
        assert.equal(run("openssl", [
          "genrsa", "-out", pem, String(bits),
        ]).status, 0);
        assert.equal(run("openssl", [
          "rsa", "-in", pem, "-outform", "DER", "-out", der,
        ]).status, 0);
      }
      assert.equal(run("openssl", [
        "pkey", "-in", key4096Der, "-inform", "DER", "-pubout",
        "-outform", "DER", "-out", public4096Der,
      ]).status, 0);
      const digest = run("openssl", ["dgst", "-sha256", public4096Der]);
      assert.equal(digest.status, 0);
      const fixtureFingerprint = digest.stdout.trim().split(/\s+/).at(-1);
      assert.match(fixtureFingerprint, /^[a-f0-9]{64}$/);

      const garbageKey = join(root, "garbage.der");
      await writeFile(garbageKey, "not a private key");
      const shellPath = join(scripts, "build-garmin.sh");
      const powershellPath = join(scripts, "build-garmin.ps1");
      const environment = {
        ...process.env,
        HOME: home,
        JAVA_HOME: fakeJdk,
        PATH: `${sdkBin}:${join(fakeJdk, "bin")}:${process.env.PATH}`,
        FAKE_MONKEYC_MARKER: marker,
      };

      for (const [key, expectedFailure] of [
        [garbageKey, /invalid DER size|valid DER private key/i],
        [key2048Der, /RSA-4096/],
        [key4096Der, /trusted public-key[\s\S]*fingerprint/],
      ]) {
        await rm(marker, { force: true });
        const shellFailure = run(shellPath, ["--release", "--developer-key", key], {
          env: environment,
        });
        assert.notEqual(shellFailure.status, 0, shellFailure.stdout + shellFailure.stderr);
        assert.match(shellFailure.stdout + shellFailure.stderr, expectedFailure);
        assert.equal(existsSync(marker), false, "shell invoked monkeyc before key validation");

        const powershellFailure = run("pwsh", [
          "-NoLogo", "-NoProfile", "-File", powershellPath,
          "-Release", "-DeveloperKey", key,
        ], { env: environment });
        assert.notEqual(
          powershellFailure.status,
          0,
          powershellFailure.stdout + powershellFailure.stderr,
        );
        assert.match(
          powershellFailure.stdout + powershellFailure.stderr,
          expectedFailure,
        );
        assert.equal(existsSync(marker), false, "PowerShell invoked monkeyc before key validation");
      }

      for (const command of [
        [shellPath, [
          "--release", "--developer-key", key4096Der,
          "--expected-public-key-sha256", fixtureFingerprint,
        ]],
        ["pwsh", [
          "-NoLogo", "-NoProfile", "-File", powershellPath,
          "-Release", "-DeveloperKey", key4096Der,
          "-ExpectedPublicKeySha256", fixtureFingerprint,
        ]],
      ]) {
        await rm(marker, { force: true });
        const failure = run(command[0], command[1], { env: environment });
        assert.notEqual(failure.status, 0, failure.stdout + failure.stderr);
        assert.match(failure.stdout + failure.stderr, /pinned Store identity/);
        assert.equal(existsSync(marker), false, "fingerprint override bypassed the Store pin");
      }

      const oldOutput = join(outputRoot, "gymapp-garmin-connect-iq.iq");
      await writeFile(oldOutput, "previous validated artifact");
      const shellSource = await readFile(shellPath, "utf8");
      const powershellSource = await readFile(powershellPath, "utf8");
      await Promise.all([
        writeFile(
          shellPath,
          shellSource.replaceAll(TRUSTED_FINGERPRINT, fixtureFingerprint),
        ),
        writeFile(
          powershellPath,
          powershellSource.replaceAll(TRUSTED_FINGERPRINT, fixtureFingerprint),
        ),
      ]);
      await chmod(shellPath, 0o755);

      for (const command of [
        [shellPath, ["--release", "--developer-key", key4096Der]],
        ["pwsh", [
          "-NoLogo", "-NoProfile", "-File", powershellPath,
          "-Release", "-DeveloperKey", key4096Der,
        ]],
      ]) {
        await rm(marker, { force: true });
        const failedBuild = run(command[0], command[1], { env: environment });
        assert.notEqual(failedBuild.status, 0, failedBuild.stdout + failedBuild.stderr);
        assert.equal(existsSync(marker), true, "fixture compiler was not reached");
        const compilerOutput = await readFile(marker, "utf8");
        assert.equal(
          basename(compilerOutput),
          "gymapp-garmin-connect-iq.iq",
          "release compiler output basename leaked a temporary PID/name into the IQ",
        );
        assert.notEqual(
          dirname(compilerOutput),
          outputRoot,
          "release compiler wrote directly beside the prior final artifact",
        );
        assert.equal(
          await readFile(oldOutput, "utf8"),
          "previous validated artifact",
          "failed build replaced the prior artifact",
        );
        assert.doesNotMatch(
          failedBuild.stdout + failedBuild.stderr,
          new RegExp(root.replaceAll("\\", "\\\\")),
        );
      }

      await Promise.all([
        writeFile(
          join(sdkBin, "monkeyc"),
          `#!/usr/bin/env bash\n` +
            `output=""\n` +
            `while [[ $# -gt 0 ]]; do\n` +
            `  if [[ "$1" == "-o" ]]; then output="$2"; shift 2; else shift; fi\n` +
            `done\n` +
            `printf '%s' "$output" > "$FAKE_MONKEYC_MARKER"\n` +
            `printf synthetic-iq > "$output"\n` +
            `printf 'built %s\\n' "$output" >&2\n`,
        ),
        writeFile(
          join(fakeJdk, "bin", "java"),
          `#!/usr/bin/env bash\n` +
            `last_argument=""\n` +
            `for argument in "$@"; do\n` +
            `  last_argument="$argument"\n` +
            `  if [[ "$argument" == "--sanitize-debug-paths" ]]; then sanitizing=1; fi\n` +
            `done\n` +
            `if [[ "\${sanitizing:-0}" == 1 ]]; then\n` +
            `  printf 'rejected %s\\n' "$last_argument" >&2\n` +
            `  exit 29\n` +
            `fi\n` +
            `exit 0\n`,
        ),
      ]);
      await Promise.all([
        chmod(join(sdkBin, "monkeyc"), 0o755),
        chmod(join(fakeJdk, "bin", "java"), 0o755),
      ]);

      for (const command of [
        [shellPath, ["--release", "--developer-key", key4096Der]],
        ["pwsh", [
          "-NoLogo", "-NoProfile", "-File", powershellPath,
          "-Release", "-DeveloperKey", key4096Der,
        ]],
      ]) {
        await rm(marker, { force: true });
        const failedSanitizer = run(command[0], command[1], { env: environment });
        assert.notEqual(
          failedSanitizer.status,
          0,
          failedSanitizer.stdout + failedSanitizer.stderr,
        );
        assert.match(
          failedSanitizer.stdout + failedSanitizer.stderr,
          /debug-path sanitization failed/i,
        );
        assert.doesNotMatch(
          failedSanitizer.stdout + failedSanitizer.stderr,
          new RegExp(root.replaceAll("\\", "\\\\")),
        );
        assert.equal(existsSync(marker), true, "fixture compiler was not reached");
        assert.equal(
          await readFile(oldOutput, "utf8"),
          "previous validated artifact",
          "failed sanitizer replaced the prior artifact",
        );
      }
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  },
);
