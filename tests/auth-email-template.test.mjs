import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const config = await readFile("supabase/config.toml", "utf8");
const template = await readFile("supabase/templates/confirmation.html", "utf8");

test("Supabase local config points at the source-controlled confirmation template", () => {
  assert.match(config, /\[auth\.email\.template\.confirmation\]/);
  assert.match(config, /content_path\s*=\s*"\.\/supabase\/templates\/confirmation\.html"/);
  assert.match(config, /subject\s*=\s*"Confirm your GymApp email"/);
});

test("confirmation email uses the exact server-issued URL and never renders its token as text", () => {
  const expectedHref = 'href="{{ .ConfirmationURL }}"';
  assert.equal(template.split(expectedHref).length - 1, 2);
  assert.doesNotMatch(template, />\s*{{\s*\.ConfirmationURL\s*}}\s*</);
  assert.doesNotMatch(template, /{{\s*\.(?:SiteURL|Token|TokenHash|Email|Data)\b/);
  assert.doesNotMatch(template, /(?:access_token|refresh_token|service_role|sb_secret_)/i);
});

test("confirmation email stays portable, private, and accessible across mail clients", () => {
  assert.match(template, /display:none; max-height:0; overflow:hidden/);
  assert.match(template, /<table role="presentation"/);
  assert.match(template, /min-height:48px/);
  assert.match(template, /line-height:48px/);
  assert.match(template, /@media only screen and \(max-width: 620px\)/);
  assert.match(template, /@media \(prefers-color-scheme: dark\)/);
  assert.match(template, /<table role="presentation" class="email-body"[^>]+background-color:#f3f0e8/);
  assert.match(template, /\.email-title, \.email-copy, \.email-brand \{ color: #f5f2ea !important; \}/);
  assert.match(template, /<td class="email-brand"/);
  assert.doesNotMatch(template, /<(?:script|form|iframe|video|audio)\b/i);
  assert.doesNotMatch(template, /<(?:img|link)\b/i);
  assert.doesNotMatch(template, /url\s*\(|@import|https?:\/\/[^"']+\.(?:woff2?|ttf|otf)|utm_|pixel|analytics/i);
});
