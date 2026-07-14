import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [script, gitignore] = await Promise.all([
  readFile("scripts/publish-debug-release.ps1", "utf8"),
  readFile(".gitignore", "utf8"),
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
  assert.doesNotMatch(script, /(?:gymapp|app|wear)[^\r\n]*\.(?:apk|aab)\b/i);
});

test("Git ignores local context, secrets, diagnostics, and distributable archives", () => {
  for (const required of [
    /^\/AGENTS\.md$/m,
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
