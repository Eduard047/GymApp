import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const appSource = readFileSync(new URL("../pwa/app.v60.js", import.meta.url), "utf8");
const stylesSource = readFileSync(new URL("../pwa/styles.v58.css", import.meta.url), "utf8");
const russianSource = readFileSync(new URL("../pwa/russian-text.v59.js", import.meta.url), "utf8");

test("pending email confirmation uses a persistent account screen", () => {
  assert.match(appSource, /let pendingEmailConfirmation = null;/);
  assert.match(appSource, /function emailConfirmationPanel\(\)/);
  assert.match(appSource, /data-action="remote-resend-confirmation"/);
  assert.match(appSource, /data-action="confirmation-change-address"/);
  assert.match(appSource, /data-action="confirmation-back-to-login"/);
  assert.match(appSource, /pendingEmail\.textContent = pendingEmailConfirmation\.email;/);
  assert.match(appSource, /normalizeAuthEmail\(pendingEmailConfirmation\?\.email\)/);
  assert.doesNotMatch(
    appSource,
    /function resendRemoteConfirmation\(\)[\s\S]{0,500}querySelector\("#signup-email"\)/
  );
});

test("confirmation screen has themed styling and Russian copy", () => {
  assert.match(stylesSource, /\.email-confirmation-panel\s*\{/);
  assert.match(stylesSource, /var\(--primary-container\)/);
  assert.match(stylesSource, /\.email-confirmation-status\.error\s*\{/);
  assert.match(russianSource, /\["Check your email", "Проверьте электронную почту"\]/);
  assert.match(russianSource, /\["Send email again", "Отправить письмо ещё раз"\]/);
  assert.match(russianSource, /\["Use a different address", "Использовать другой адрес"\]/);
});
