import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);

const [
  script,
  gitignore,
  dependabot,
  securityWorkflow,
  iosArchiveScript,
  iosExportOptions,
] = await Promise.all([
  readFile("scripts/publish-debug-release.ps1", "utf8"),
  readFile(".gitignore", "utf8"),
  readFile(".github/dependabot.yml", "utf8"),
  readFile(".github/workflows/security.yml", "utf8"),
  readFile("ios/GymApp-iOS/Scripts/archive-app-store.sh", "utf8"),
  readFile("ios/GymApp-iOS/AppStore/ExportOptions.plist", "utf8"),
]);

test("debug artifact publication fails closed at the script entry point", () => {
  const policyFailure =
    'throw "Debug APK publication is disabled by repository security policy. Build and inspect artifacts locally; do not upload APK or AAB files to GitHub Releases."';
  const failureIndex = script.indexOf(policyFailure);

  assert.ok(failureIndex >= 0, "the repository publication policy is not enforced");
  assert.equal(
    (script.match(/^\s*throw\s+/gim) ?? []).length,
    1,
    "the script must have one unconditional policy failure"
  );
  assert.doesNotMatch(
    script.slice(0, failureIndex),
    /(?:Get-Command|Resolve-Path|Set-Location|Start-Process|Invoke-Expression|&\s*\()/i,
    "no external command or workspace action may precede the policy failure"
  );
});

test("the disabled script contains no GitHub release mutation", () => {
  assert.doesNotMatch(script, /\bgh\s+release\s+(?:create|upload|delete|edit)\b/i);
  assert.doesNotMatch(script, /\bgh\s+api\b/i);
  assert.doesNotMatch(script, /--clobber\b/i);
});

test("the disabled script contains no local or remote git mutation", () => {
  assert.doesNotMatch(
    script,
    /\bgit\s+(?:fetch|pull|push|switch|checkout|tag|branch|add|commit|reset|clean)\b/i
  );
  assert.doesNotMatch(script, /\bgit\s+ls-remote\b/i);
});

test("the disabled script neither builds nor handles distributable artifacts", () => {
  assert.doesNotMatch(script, /build-update-apk|gradlew(?:\.bat)?/i);
  assert.doesNotMatch(script, /(?:Copy|Move|Remove)-Item\b/i);
  assert.doesNotMatch(script, /(?:gymapp|app)[^\r\n]*\.(?:apk|aab)\b/i);
});

test("iOS export fails closed before publishing personal build paths", () => {
  assert.match(
    iosExportOptions,
    /<key>uploadSymbols<\/key>\s*<false\/>/u,
    "the public IPA must not bundle Xcode symbol metadata with archive paths"
  );
  assert.match(
    iosArchiveScript,
    /DEFAULT_DERIVED_DATA_PATH="\$\{TMPDIR:-\/tmp\/\}GymApp-iOS-\$MARKETING_VERSION-\$BUILD_NUMBER-DerivedData"/u,
    "release dependencies must compile outside the personal workspace by default"
  );
  assert.match(iosArchiveScript, /-derivedDataPath "\$DERIVED_DATA_PATH"/u);
  assert.match(
    iosArchiveScript,
    /unzip -tq "\$IPA_PATH"/u,
    "the exported IPA must pass an independent archive-integrity check"
  );
  assert.match(
    iosArchiveScript,
    /unzip -p "\$IPA_PATH" > "\$IPA_SCAN_DIR\/payload\.bin"/u,
    "the exported IPA must be extracted by a fail-closed command"
  );
  assert.match(
    iosArchiveScript,
    /strings "\$IPA_SCAN_DIR\/payload\.bin" > "\$IPA_SCAN_DIR\/strings\.txt"/u,
    "the privacy scan must fail if string extraction fails"
  );
  assert.match(
    iosArchiveScript,
    /LC_ALL=C grep -Eq '\/Users\/\|\/Volumes\/\|Documents\/GymApp' "\$IPA_SCAN_DIR\/strings\.txt"/u,
    "the exported IPA must be inspected for personal and workspace-local absolute paths"
  );
  assert.doesNotMatch(
    iosArchiveScript,
    /unzip[^\n]*\|[^\n]*strings/u,
    "archive or string extraction failures must not be masked by a pipeline"
  );
  assert.match(
    iosArchiveScript,
    /Export blocked: the IPA contains a personal or workspace-local absolute path/u
  );
  assert.doesNotMatch(
    iosArchiveScript,
    /SWIFT_EXEC|SWIFT_DRIVER_SWIFT_FRONTEND_EXEC/u,
    "release builds must use the standard Xcode Swift driver"
  );
  assert.ok(
    iosArchiveScript.indexOf("-exportArchive") < iosArchiveScript.indexOf('IPA_PATH="$EXPORT_PATH/GymApp.ipa"'),
    "privacy inspection must run against the final exported IPA"
  );
});

test("Git ignores local context, secrets, diagnostics, and distributable archives", () => {
  for (const required of [
    /^\/security-reports\/$/m,
    /^\.env$/m,
    /^\.env\.\*$/m,
    /^\*\.jks$/m,
    /^keystore\.properties$/m,
    /^cookies\.txt$/m,
    /^\*\.har$/m,
    /^\*\.dump$/m,
    /^\*\.zip$/m,
    /^\*\.apk$/m,
    /^\*\.aab$/m,
  ]) {
    assert.match(gitignore, required);
  }
});

test("the local AGENTS context file is not tracked", async () => {
  await assert.rejects(
    execFileAsync("git", ["ls-files", "--error-unmatch", "AGENTS.md"]),
    "AGENTS.md must remain local-only via .git/info/exclude"
  );
});

test("Dependabot stays low-noise without delaying security updates", () => {
  const ecosystems = dependabot
    .split(/\n  - package-ecosystem: /)
    .slice(1);

  const configurations = ecosystems.map((ecosystem) => ({
    ecosystem: ecosystem.match(/^([^\s]+)/u)?.[1],
    directory: ecosystem.match(/\n\s+directory: ([^\s]+)\s*$/mu)?.[1],
  }));
  assert.deepEqual(configurations, [
    { ecosystem: "github-actions", directory: "/" },
    { ecosystem: "gradle", directory: "/" },
    { ecosystem: "deno", directory: "/supabase/functions/garmin-sync" },
    {
      ecosystem: "deno",
      directory: "/supabase/functions/social-live-gateway",
    },
    { ecosystem: "deno", directory: "/supabase/functions/push-dispatch" },
  ]);

  let routinePullRequestLimit = 0;
  for (const ecosystem of ecosystems) {
    assert.match(ecosystem, /\n\s+interval: monthly\s*$/m);
    assert.match(ecosystem, /\n\s+timezone: Europe\/Kyiv\s*$/m);
    assert.match(ecosystem, /\n\s+applies-to: security-updates\s*$/m);
    assert.match(ecosystem, /\n\s+cooldown:\s*\n\s+default-days: 14\s*$/m);

    const limit = Number(ecosystem.match(/\n\s+open-pull-requests-limit: (\d+)\s*$/m)?.[1]);
    assert.ok(Number.isInteger(limit) && limit > 0, "routine update limit must be bounded");
    routinePullRequestLimit += limit;
  }

  assert.ok(
    routinePullRequestLimit <= 6,
    "routine dependency updates must not flood the branch and pull-request lists"
  );
});

test("Security CI checks every independent Edge Function dependency boundary", () => {
  for (const directory of [
    "garmin-sync",
    "social-live-gateway",
    "push-dispatch",
  ]) {
    assert.match(
      securityWorkflow,
      new RegExp(
        `working-directory: supabase/functions/${directory}\\n` +
          "\\s+shell: bash\\n" +
          "\\s+run: deno audit --frozen --level=high",
        "u"
      ),
      `${directory} must audit its own frozen lock at high severity`
    );
    assert.match(
      securityWorkflow,
      new RegExp(
        `working-directory: supabase/functions/${directory}\\n` +
          "\\s+shell: bash\\n" +
          "\\s+run: \\|\\n" +
          "\\s+deno check --frozen --config deno.json",
        "u"
      ),
      `${directory} must type-check with its own frozen config and lock`
    );
  }
  assert.equal(
    (securityWorkflow.match(/deno audit --frozen --level=high/gu) ?? []).length,
    3,
    "exactly the three independently locked Edge Function directories must be audited"
  );

  for (const expected of [
    "../_shared/garmin-capability.ts",
    "../_shared/garmin-plan-contract.ts",
    "../_shared/garmin-telemetry.ts",
    "../_shared/preauth-budget.ts",
    "providers.ts",
    "supabase/functions/delete-account/index.ts",
  ]) {
    assert.ok(
      securityWorkflow.includes(expected),
      `${expected} must remain in the Deno type-check boundary`
    );
  }
  assert.match(
    securityWorkflow,
    /deno check --no-config --no-lock \\\n\s+supabase\/functions\/delete-account\/index\.ts/u,
    "delete-account must be checked without inventing a dependency lock"
  );
  assert.match(
    securityWorkflow,
    /find supabase\/functions -type f -name '\*\.ts' -print0[\s\S]*xargs -0 deno fmt --check/u,
    "all Edge TypeScript sources must be formatting-checked"
  );

  for (const testFile of ["index_test.ts", "providers_test.ts"]) {
    const command = `deno test --frozen --config deno.json ${testFile}`;
    assert.ok(
      securityWorkflow.includes(command),
      `${testFile} must run without broad runtime permission flags`
    );
  }
  assert.doesNotMatch(
    securityWorkflow,
    /deno test[^\n]*(?:--allow-all|-A|--allow-(?:env|ffi|hrtime|net|read|run|sys|write))/u,
    "Edge unit contracts must not receive unnecessary runtime permissions"
  );
});
