import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { TextEncoder } from "node:util";
import test from "node:test";
import vm from "node:vm";

const appSources = await Promise.all(
  ["app.js", "app.v59.js"].map(async filename => ({
    filename,
    source: await readFile(new URL(`../pwa/${filename}`, import.meta.url), "utf8")
  }))
);

function loadPasswordPolicy(source) {
  const start = source.indexOf("function normalizeAuthEmail");
  const end = source.indexOf("function validateConfirmationEmail", start);
  assert.ok(start >= 0 && end > start, "password validation source must remain extractable");

  const context = vm.createContext({ tx: english => english, TextEncoder });
  vm.runInContext(
    `${source.slice(start, end)}\nthis.passwordPolicy = { validNewPassword, validateAuthInput };`,
    context
  );
  return context.passwordPolicy;
}

for (const { filename, source } of appSources) {
  test(`${filename} enforces the new policy only for account creation`, () => {
    const { validNewPassword, validateAuthInput } = loadPasswordPolicy(source);
    const email = "athlete@example.com";
    const policyError = "Password must contain at least 12 characters, fit within 72 UTF-8 bytes, and include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol.";

    assert.equal(validateAuthInput(email, "legacy1", "", false), "");
    assert.equal(validateAuthInput(email, "", "", false), "Enter your password.");
    assert.equal(validateAuthInput(email, "legacy1", "Athlete", true), policyError);
    assert.equal(validateAuthInput(email, "SecurePass9!", "Athlete", true), "");

    assert.equal(validNewPassword("SecurePass9!"), true);
    assert.equal(validNewPassword(`Aa1!${"x".repeat(68)}`), true);
    assert.equal(validNewPassword("Short1!Aa"), false);
    assert.equal(validNewPassword(`Aa1!${"x".repeat(69)}`), false);
    assert.equal(validNewPassword("SECUREPASS9!"), false);
    assert.equal(validNewPassword("securepass9!"), false);
    assert.equal(validNewPassword("SecurePass!!"), false);
    assert.equal(validNewPassword("SecurePass9🙂"), false);

    for (const symbol of "!@#$%^&*()_+-=[]{};'\\:\"|<>?,./`~") {
      assert.equal(validNewPassword(`SecurePass9${symbol}`), true, symbol);
    }
  });

  test(`${filename} uses a code-point minimum, UTF-8 byte ceiling, and unrestricted login fields`, () => {
    const { validNewPassword } = loadPasswordPolicy(source);
    assert.equal(validNewPassword(`Aa1!${"x".repeat(8)}${"🙂".repeat(15)}`), true);
    assert.equal(validNewPassword(`Aa1!${"x".repeat(8)}${"🙂".repeat(16)}`), false);
    assert.match(source, /validateAuthInput\(email, password, createAccount \? displayName : "", createAccount\)/);
    assert.match(source, /id="signup-password"[^>]*minlength="12"[^>]*maxlength="72"/);
    assert.match(source, /id="signup-password-confirm"[^>]*minlength="12"[^>]*maxlength="72"/);
    assert.doesNotMatch(source, /id="login-password"[^>]*(?:minlength|maxlength)=/);
  });
}

test("mobile password policies use the same scalar and UTF-8 byte metrics and preserve recovery API shape", async () => {
  const [androidPolicy, androidAuth, iosAuth] = await Promise.all([
    readFile(new URL("../app/src/main/java/com/example/gymapp/auth/PasswordPolicy.kt", import.meta.url), "utf8"),
    readFile(new URL("../app/src/main/java/com/example/gymapp/auth/CloudAuthManager.kt", import.meta.url), "utf8"),
    readFile(new URL("../ios/GymApp-iOS/GymApp/Services/AuthService.swift", import.meta.url), "utf8")
  ]);

  assert.match(androidPolicy, /codePointCount\(0, password\.length\)/);
  assert.match(androidPolicy, /toByteArray\(Charsets\.UTF_8\)\.size <= 72/);
  assert.match(iosAuth, /password\.unicodeScalars/);
  assert.match(iosAuth, /password\.utf8\.count <= 72/);

  const androidLogin = androidAuth.slice(
    androidAuth.indexOf("suspend fun login"),
    androidAuth.indexOf("suspend fun signUp")
  );
  assert.doesNotMatch(androidLogin, /validateNewPassword|isValidNewPassword/);
  assert.match(androidLogin, /require\(password\.isNotEmpty\(\)\)/);

  const iosLogin = iosAuth.slice(
    iosAuth.indexOf("func signIn"),
    iosAuth.indexOf("func signUp")
  );
  assert.doesNotMatch(iosLogin, /validatePassword|GymPasswordPolicy\.accepts/);

  const androidUpdate = androidAuth.slice(
    androidAuth.indexOf("suspend fun updatePassword"),
    androidAuth.indexOf("suspend fun changePassword")
  );
  assert.match(androidUpdate, /passwordUpdateBody\(newPassword = password\)/);
  assert.doesNotMatch(androidUpdate, /current_password/);

  const androidPasswordBody = androidAuth.slice(
    androidAuth.indexOf("internal fun passwordUpdateBody"),
    androidAuth.indexOf("internal fun isTerminalRefreshFailure")
  );
  assert.match(androidPasswordBody, /put\("password", newPassword\)/);
  assert.match(androidPasswordBody, /put\("current_password", currentPassword\)/);

  const androidChange = androidAuth.slice(
    androidAuth.indexOf("suspend fun changePassword"),
    androidAuth.indexOf("suspend fun deleteCloudAccount")
  );
  assert.match(androidChange, /currentPassword = currentPassword/);

  const iosUpdate = iosAuth.slice(
    iosAuth.indexOf("func updatePassword"),
    iosAuth.indexOf("func continueOffline")
  );
  assert.match(iosUpdate, /var body: \[String: Any\] = \["password": password\]/);
  assert.match(iosUpdate, /body\["current_password"\] = currentPassword/);
  assert.match(iosUpdate, /if let currentPassword/);
});
