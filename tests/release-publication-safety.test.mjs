import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);

const [script, gitignore, dependabot] = await Promise.all([
  readFile("scripts/publish-debug-release.ps1", "utf8"),
  readFile(".gitignore", "utf8"),
  readFile(".github/dependabot.yml", "utf8"),
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

  assert.equal(ecosystems.length, 3, "only the three maintained ecosystems belong here");

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
    routinePullRequestLimit <= 4,
    "routine dependency updates must not flood the branch and pull-request lists"
  );
});
