import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { TextEncoder } from "node:util";
import test from "node:test";
import vm from "node:vm";

const appSources = await Promise.all(
  ["app.js", "app.v118.js", "app.v117.js", "app.v116.js", "app.v115.js", "app.v114.js", "app.v113.js", "app.v112.js"].map(async filename => ({
    filename,
    source: await readFile(new URL(`../pwa/${filename}`, import.meta.url), "utf8")
  }))
);

function loadPasswordPolicy(source) {
  const start = source.indexOf("function normalizeAuthEmail");
  const end = source.indexOf("function validateConfirmationEmail", start);
  assert.ok(start >= 0 && end > start, "password validation source must remain extractable");

  const context = vm.createContext({
    MAX_LOGIN_PASSWORD_UTF8_BYTES: 1024,
    tx: english => english,
    TextEncoder
  });
  vm.runInContext(
    `${source.slice(start, end)}\nthis.passwordPolicy = { validNewPassword, validateAuthInput };`,
    context
  );
  return context.passwordPolicy;
}

function loadSensitiveDraftCleaner(source) {
  const start = source.indexOf("const authDrafts =");
  const end = source.indexOf("function clearAuthDrafts", start);
  assert.ok(start >= 0 && end > start, "sensitive auth draft cleanup must remain extractable");
  const inputs = new Map([
    ["#login-password", { value: "login-secret" }],
    ["#signup-password", { value: "signup-secret" }],
    ["#signup-password-confirm", { value: "signup-secret" }],
    ["#recovery-new-password", { value: "recovery-secret" }],
    ["#recovery-repeat-password", { value: "recovery-secret" }],
    ["#change-current-password", { value: "current-secret" }],
    ["#change-password-nonce", { value: "12345678" }],
    ["#change-new-password", { value: "change-secret" }],
    ["#change-repeat-password", { value: "change-secret" }]
  ]);
  const context = vm.createContext({
    document: { querySelector: selector => inputs.get(selector) || null }
  });
  vm.runInContext(
    `${source.slice(start, end)}\n` +
      `authDrafts.login.password = "login-secret";\n` +
      `authDrafts.signup.password = "signup-secret";\n` +
      `authDrafts.signup.passwordConfirm = "signup-secret";\n` +
      `clearSensitiveAuthDrafts();\n` +
      `this.cleanupResult = JSON.stringify(authDrafts);`,
    context
  );
  return { inputs, drafts: JSON.parse(context.cleanupResult) };
}

for (const { filename, source } of appSources) {
  // app.v112.js is the immutable predecessor bundle that still carries the 12-character policy.
  const legacyPolicy = filename === "app.v112.js";
  const policyError = legacyPolicy
    ? "Password must contain at least 12 characters, fit within 72 UTF-8 bytes, and include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol."
    : "Password must contain at least 6 characters and fit within 72 UTF-8 bytes.";

  test(`${filename} preserves legacy login passwords inside the bounded transport contract`, () => {
    const { validNewPassword, validateAuthInput } = loadPasswordPolicy(source);
    const email = "athlete@example.com";

    assert.equal(validateAuthInput(email, "legacy1", "", false), "");
    assert.equal(validateAuthInput(email, "", "", false), "Enter your password.");
    assert.equal(validateAuthInput(email, "x".repeat(1024), "", false), "");
    assert.equal(validateAuthInput(email, "🙂".repeat(256), "", false), "");
    assert.equal(validateAuthInput(email, "x".repeat(1025), "", false), "Password is too long.");
    assert.equal(validateAuthInput(email, "🙂".repeat(257), "", false), "Password is too long.");
    assert.equal(validateAuthInput(email, "SecurePass9!", "Athlete", true), "");

    if (legacyPolicy) {
      assert.equal(validateAuthInput(email, "legacy1", "Athlete", true), policyError);
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
    } else {
      assert.equal(validateAuthInput(email, "abcde", "Athlete", true), policyError);
      assert.equal(validateAuthInput(email, "abcdef", "Athlete", true), "");
      assert.equal(validateAuthInput(email, "x".repeat(73), "Athlete", true), policyError);

      assert.equal(validNewPassword("abcdef"), true);
      assert.equal(validNewPassword("abcde"), false);
      assert.equal(validNewPassword(""), false);
      assert.equal(validNewPassword("lowercaseonly"), true);
      assert.equal(validNewPassword("ALLUPPERCASE"), true);
      assert.equal(validNewPassword("1234567890"), true);
      assert.equal(validNewPassword("x".repeat(72)), true);
      assert.equal(validNewPassword("x".repeat(73)), false);
      assert.equal(validNewPassword("🙂".repeat(6)), true);
      assert.equal(validNewPassword("🙂".repeat(5)), false);
      assert.equal(validNewPassword("🙂".repeat(18)), true);
      assert.equal(validNewPassword("🙂".repeat(19)), false);
      assert.equal(validNewPassword(`${"x".repeat(68)}🙂`), true);
      assert.equal(validNewPassword(`${"x".repeat(69)}🙂`), false);
      assert.doesNotMatch(source, /SUPABASE_PASSWORD_SYMBOLS/);
    }
  });

  test(`${filename} uses UTF-8 byte ceilings for new and existing passwords`, () => {
    const { validNewPassword } = loadPasswordPolicy(source);
    assert.equal(validNewPassword(`Aa1!${"x".repeat(8)}${"🙂".repeat(15)}`), true);
    assert.equal(validNewPassword(`Aa1!${"x".repeat(8)}${"🙂".repeat(16)}`), false);
    const minlength = legacyPolicy ? "12" : "6";
    assert.match(source, /validateAuthInput\(email, password, createAccount \? displayName : "", createAccount\)/);
    assert.match(source, new RegExp(`id="signup-password"[^>]*minlength="${minlength}"[^>]*maxlength="72"`));
    assert.match(source, new RegExp(`id="signup-password-confirm"[^>]*minlength="${minlength}"[^>]*maxlength="72"`));
    for (const id of ["recovery-new-password", "recovery-repeat-password", "change-new-password", "change-repeat-password"]) {
      assert.match(source, new RegExp(`id="${id}"[^>]*minlength="${minlength}"[^>]*maxlength="72"`), id);
    }
    assert.doesNotMatch(source, /id="(?:login-password|change-current-password)"[^>]*minlength=/);
    assert.match(source, /const MAX_LOGIN_PASSWORD_UTF8_BYTES = 1024;/);
    assert.match(source, /id="login-password"[^>]*maxlength="1024"/);
    assert.match(source, /new TextEncoder\(\)\.encode\(cleanPassword\)\.byteLength > MAX_LOGIN_PASSWORD_UTF8_BYTES/);
  });

  test(`${filename} clears password drafts and rendered values on auth transitions`, () => {
    assert.match(source, /function clearSensitiveAuthDrafts\(\)[\s\S]*?authDrafts\.login\.password = "";[\s\S]*?authDrafts\.signup\.password = "";[\s\S]*?authDrafts\.signup\.passwordConfirm = "";/);
    for (const selector of [
      "#login-password", "#signup-password", "#signup-password-confirm",
      "#recovery-new-password", "#recovery-repeat-password",
      "#change-current-password", "#change-password-nonce", "#change-new-password",
      "#change-repeat-password"
    ]) {
      assert.match(source, new RegExp(JSON.stringify(selector)));
    }
    assert.match(source, /for \(const selector of \[[\s\S]*?input\.value = "";/);
    const closeModalStart = source.indexOf("function closeModal()");
    const closeModalEnd = source.indexOf("function dismissModalAfterExternalUpdate", closeModalStart);
    assert.ok(closeModalStart >= 0 && closeModalEnd > closeModalStart, "closeModal must remain extractable");
    assert.match(source.slice(closeModalStart, closeModalEnd), /clearSensitiveAuthDrafts\(\);/);
    assert.match(source, /if \(action === "open-offline-account"\) \{\s*clearSensitiveAuthDrafts\(\);/);
    assert.match(source, /if \(action === "auth-mode"\) \{\s*clearSensitiveAuthDrafts\(\);/);
    assert.match(source, /window\.addEventListener\("pagehide", clearSensitiveAuthDrafts\);/);

    const { inputs, drafts } = loadSensitiveDraftCleaner(source);
    assert.equal(drafts.login.password, "");
    assert.equal(drafts.signup.password, "");
    assert.equal(drafts.signup.passwordConfirm, "");
    assert.deepEqual([...inputs.values()].map(input => input.value), Array(inputs.size).fill(""));
  });
}

test("mobile password policies use the same scalar and UTF-8 byte metrics and preserve recovery API shape", async () => {
  const [androidPolicy, androidAuth, iosAuth] = await Promise.all([
    readFile(new URL("../app/src/main/java/com/example/gymapp/auth/PasswordPolicy.kt", import.meta.url), "utf8"),
    readFile(new URL("../app/src/main/java/com/example/gymapp/auth/CloudAuthManager.kt", import.meta.url), "utf8"),
    readFile(new URL("../ios/GymApp-iOS/GymApp/Services/AuthService.swift", import.meta.url), "utf8")
  ]);

  assert.match(androidPolicy, /codePointCount\(0, password\.length\)/);
  assert.match(androidPolicy, /NEW_PASSWORD_MIN_CODE_POINTS = 6/);
  assert.match(androidPolicy, /NEW_PASSWORD_MAX_UTF8_BYTES = 72/);
  assert.match(androidPolicy, /toByteArray\(Charsets\.UTF_8\)\.size <= NEW_PASSWORD_MAX_UTF8_BYTES/);
  assert.match(iosAuth, /static let minimumCharacters = 6/);
  assert.match(iosAuth, /static let maximumUTF8Bytes = 72/);
  assert.match(iosAuth, /password\.unicodeScalars\.count >= minimumCharacters/);
  assert.match(iosAuth, /password\.utf8\.count <= maximumUTF8Bytes/);

  const androidLogin = androidAuth.slice(
    androidAuth.indexOf("suspend fun login"),
    androidAuth.indexOf("suspend fun signUp")
  );
  assert.doesNotMatch(androidLogin, /validateNewPassword|isValidNewPassword/);
  assert.match(androidLogin, /require\(password\.isNotEmpty\(\)\)/);
  assert.match(androidLogin, /password\.toByteArray\(Charsets\.UTF_8\)\.size <= MAX_LOGIN_PASSWORD_UTF8_BYTES/);

  const iosLogin = iosAuth.slice(
    iosAuth.indexOf("func signIn"),
    iosAuth.indexOf("func signUp")
  );
  assert.doesNotMatch(iosLogin, /validatePassword|GymPasswordPolicy\.accepts/);
  assert.match(iosLogin, /GymLoginPasswordPolicy\.accepts\(password\)/);
  assert.match(iosAuth, /static let maximumUTF8Bytes = 1_024/);
  assert.match(iosAuth, /password\.utf8\.count <= maximumUTF8Bytes/);

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

test("local Supabase Auth config matches the client password policy", async () => {
  const config = await readFile(new URL("../supabase/config.toml", import.meta.url), "utf8");
  const authTable = config.match(/^\[auth\]\s*$([\s\S]*?)(?=^\[|(?![\s\S]))/m);
  assert.ok(authTable, "config.toml must define an [auth] table");
  assert.match(authTable[1], /^minimum_password_length\s*=\s*6\s*$/m);
  assert.doesNotMatch(authTable[1], /^password_requirements\s*=\s*"(?!")/m);
});
