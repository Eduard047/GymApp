import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const callbackSource = await readFile("pwa/confirmed.js", "utf8");

function element() {
  const attributes = new Map();
  return {
    attributes,
    textContent: "",
    setAttribute(name, value) {
      attributes.set(name, String(value));
    },
    getAttribute(name) {
      return attributes.get(name) ?? null;
    }
  };
}

function runCallback(url) {
  const parsed = new URL(url);
  const nodes = new Map([
    ["#open-app", element()],
    ["#confirmation-title", element()],
    ["#confirmation-message", element()]
  ]);
  const scrubbed = [];
  const context = {
    URL,
    URLSearchParams,
    document: {
      querySelector(selector) {
        return nodes.get(selector) || null;
      }
    },
    window: {
      location: {
        search: parsed.search,
        hash: parsed.hash,
        pathname: parsed.pathname
      },
      history: {
        replaceState(_state, _title, nextUrl) {
          scrubbed.push(nextUrl);
        }
      }
    }
  };

  vm.runInNewContext(callbackSource, context);
  return {
    button: nodes.get("#open-app"),
    title: nodes.get("#confirmation-title"),
    message: nodes.get("#confirmation-message"),
    scrubbed
  };
}

test("legacy and explicit Android confirmation links keep the implicit fragment contract", () => {
  const fragment = "#access_token=android-access&refresh_token=android-refresh&type=signup";
  const legacy = runCallback(`https://eduard047.github.io/GymApp/confirmed.html${fragment}`);
  assert.equal(
    legacy.button.getAttribute("href"),
    `com.setforge.gymapp://auth/callback${fragment}`
  );
  assert.deepEqual(legacy.scrubbed, ["/GymApp/confirmed.html"]);

  const explicit = runCallback(`https://gymapptracker.com/confirmed.html?platform=android${fragment}`);
  assert.equal(
    explicit.button.getAttribute("href"),
    `com.setforge.gymapp://auth/callback?platform=android${fragment}`
  );
  assert.deepEqual(explicit.scrubbed, ["/confirmed.html"]);
});

test("web confirmation discards implicit credentials and returns to the canonical site", () => {
  const result = runCallback(
    "https://gymapptracker.com/confirmed.html?platform=web#access_token=secret&refresh_token=secret"
  );

  assert.equal(result.button.getAttribute("href"), "https://gymapptracker.com/");
  assert.doesNotMatch(result.button.getAttribute("href"), /secret|token/i);
  assert.deepEqual(result.scrubbed, ["/confirmed.html"]);
});

test("iOS bridge forwards only one PKCE code under the exact state-bound callback", () => {
  const state = "AbCdEf0123456789_-AbCdEf01234567";
  const code = "34e770dd-9ff9-416c-87fa-43b31d7ef225";
  const result = runCallback(
    `https://gymapptracker.com/confirmed.html?platform=ios&state=${state}&code=${code}&type=signup`
  );

  assert.equal(
    result.button.getAttribute("href"),
    `com.setforge.gymapp.ios://auth/callback/${state}?code=${code}`
  );
  assert.equal(result.button.textContent, "Open GymApp for iOS");
  assert.deepEqual(result.scrubbed, ["/confirmed.html"]);
});

test("iOS bridge forwards only bounded error fields", () => {
  const state = "Z".repeat(32);
  const result = runCallback(
    `https://gymapptracker.com/confirmed.html?platform=ios&state=${state}&error=access_denied&error_description=User%20cancelled&type=signup`
  );

  assert.equal(
    result.button.getAttribute("href"),
    `com.setforge.gymapp.ios://auth/callback/${state}?error=access_denied&error_description=User+cancelled`
  );
  assert.doesNotMatch(result.button.getAttribute("href"), /type=signup/);
});

test("iOS bridge fails closed for implicit tokens, fragments, duplicates, and invalid state", () => {
  const state = "Q".repeat(32);
  const cases = [
    `?platform=ios&state=${state}&code=valid&access_token=secret`,
    `?platform=ios&state=${state}&code=valid&refresh_token=secret`,
    `?platform=ios&state=${state}&code=valid&provider_token=secret`,
    `?platform=ios&state=${state}&code=valid&id_token=secret`,
    `?platform=ios&state=${state}&code=valid#access_token=secret`,
    `?platform=ios&state=${state}&state=${state}&code=valid`,
    `?platform=ios&platform=web&state=${state}&code=valid`,
    `?platform=ios&state=${state}&code=one&code=two`,
    `?platform=ios&state=too-short&code=valid`,
    `?platform=ios&state=${state}&code=valid&error=access_denied`,
    `?platform=ios&state=${state}&error_description=missing-error`
  ];

  for (const suffix of cases) {
    const result = runCallback(`https://gymapptracker.com/confirmed.html${suffix}`);
    assert.equal(result.button.getAttribute("href"), "https://gymapptracker.com/", suffix);
    assert.doesNotMatch(result.button.getAttribute("href"), /secret|auth\/callback/i, suffix);
    assert.match(result.title.textContent, /unavailable/i, suffix);
  }
});

test("unknown platform never becomes a custom-scheme redirect", () => {
  const result = runCallback(
    "https://gymapptracker.com/confirmed.html?platform=attacker&return_to=evil%3A%2F%2Fcallback"
  );

  assert.equal(result.button.getAttribute("href"), "https://gymapptracker.com/");
  assert.deepEqual(result.scrubbed, ["/confirmed.html"]);
});

test("client auth, public metadata, and compatibility docs use the intended domains", async () => {
  const [android, pwa, index, confirmation, cname, readme] = await Promise.all([
    readFile("app/src/main/java/com/example/gymapp/auth/CloudAuthManager.kt", "utf8"),
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/index.html", "utf8"),
    readFile("pwa/confirmed.html", "utf8"),
    readFile("pwa/CNAME", "utf8"),
    readFile("README.md", "utf8")
  ]);

  assert.match(android, /https:\/\/gymapptracker\.com\/confirmed\.html\?platform=android/);
  assert.match(android, /\/auth\/v1\/resend\?redirect_to=/);
  assert.match(pwa, /https:\/\/gymapptracker\.com\/confirmed\.html\?platform=web/);
  assert.match(pwa, /\/auth\/v1\/resend\?redirect_to=/);
  assert.match(pwa, /if \(!query\.has\("platform"\)\) query\.set\("platform", "web"\)/);
  assert.match(pwa, /https:\/\/gymapptracker\.com\/support\.html/);
  assert.match(pwa, /https:\/\/gymapptracker\.com\/privacy-policy\.html/);
  assert.match(index, /rel="canonical" href="https:\/\/gymapptracker\.com\/"/);
  assert.match(confirmation, /Content-Security-Policy/);
  assert.match(confirmation, /name="referrer" content="no-referrer"/);
  assert.doesNotMatch(confirmation, /<script[^>]+src="https?:\/\//i);
  assert.equal(cname, "gymapptracker.com\n");
  assert.match(readme, /https:\/\/eduard047\.github\.io\/GymApp\/confirmed\.html/);
});
