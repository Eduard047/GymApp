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
  const assigned = [];
  const context = {
    DOMException,
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
        pathname: parsed.pathname,
        assign(nextUrl) {
          assigned.push(String(nextUrl));
        }
      },
      history: {
        replaceState(_state, _title, nextUrl) {
          scrubbed.push(nextUrl);
        }
      }
    }
  };
  context.window.self = context.window;
  context.window.top = context.window;
  context.window.__GYMAPP_TOP_LEVEL__ = true;

  vm.runInNewContext(callbackSource, context);
  return {
    button: nodes.get("#open-app"),
    title: nodes.get("#confirmation-title"),
    message: nodes.get("#confirmation-message"),
    scrubbed,
    assigned
  };
}

test("Android rejects legacy implicit bearer signup callbacks", () => {
  const fragment = "#access_token=android-access&refresh_token=android-refresh&type=signup";
  const legacy = runCallback(`https://eduard047.github.io/GymApp/confirmed.html${fragment}`);
  assert.equal(legacy.button.getAttribute("href"), "https://gymapptracker.com/");
  assert.doesNotMatch(legacy.button.getAttribute("href"), /token|auth\/callback/i);
  assert.match(legacy.title.textContent, /unavailable/i);
  assert.deepEqual(legacy.scrubbed, ["/GymApp/confirmed.html"]);
  assert.deepEqual(legacy.assigned, []);

  const explicit = runCallback(`https://gymapptracker.com/confirmed.html?platform=android${fragment}`);
  assert.equal(explicit.button.getAttribute("href"), "https://gymapptracker.com/");
  assert.doesNotMatch(explicit.button.getAttribute("href"), /token|auth\/callback/i);
  assert.match(explicit.title.textContent, /unavailable/i);
  assert.deepEqual(explicit.scrubbed, ["/confirmed.html"]);
  assert.deepEqual(explicit.assigned, []);
});

test("Android signup forwards only a state-bound PKCE code after user action", () => {
  const state = "S".repeat(32);
  const code = "34e770dd-9ff9-416c-87fa-43b31d7ef225";
  const url = `https://gymapptracker.com/confirmed.html?platform=android&state=${state}&purpose=signup&code=${code}`;
  const result = runCallback(url);
  const expected = `com.setforge.gymapp://auth/callback?state=${state}&purpose=signup&code=${code}`;

  assert.equal(result.button.getAttribute("href"), expected);
  assert.doesNotMatch(result.button.getAttribute("href"), /access_token|refresh_token/i);
  assert.equal(result.button.textContent, "Open GymApp");
  assert.match(result.title.textContent, /email confirmed/i);
  assert.match(result.message.textContent, /where registration started/i);
  assert.deepEqual(result.assigned, []);
  assert.deepEqual(result.scrubbed, []);
});

test("Android QA callbacks use only the non-production package scheme", () => {
  const state = "T".repeat(32);
  const code = "dd8af18b-ffb8-4f1e-8552-972ccf840d9f";
  const result = runCallback(
    `https://gymapptracker.com/confirmed.html?platform=android&variant=qa&state=${state}&purpose=signup&code=${code}`
  );

  assert.equal(
    result.button.getAttribute("href"),
    `com.setforge.gymapp.dev://auth/callback?state=${state}&purpose=signup&code=${code}`
  );
  assert.doesNotMatch(result.button.getAttribute("href"), /(?:\?|&)variant=/);
  assert.deepEqual(result.assigned, []);
  assert.deepEqual(result.scrubbed, []);
});

test("authentication bridge rejects duplicate, unknown, and cross-platform variants", () => {
  const state = "V".repeat(32);
  const code = "096032d9-91e5-4ff4-b69a-4c9922fab290";
  const cases = [
    `?platform=android&variant=debug&state=${state}&purpose=signup&code=${code}`,
    `?platform=android&variant=qa&variant=qa&state=${state}&purpose=signup&code=${code}`,
    `?platform=ios&variant=qa&state=${state}&purpose=signup&code=${code}`,
    "?platform=web&variant=qa"
  ];

  for (const suffix of cases) {
    const result = runCallback(`https://gymapptracker.com/confirmed.html${suffix}`);
    assert.equal(result.button.getAttribute("href"), "https://gymapptracker.com/", suffix);
    assert.doesNotMatch(result.button.getAttribute("href"), /auth\/callback/i, suffix);
    assert.match(result.title.textContent, /unavailable/i, suffix);
    assert.deepEqual(result.assigned, [], suffix);
    assert.deepEqual(result.scrubbed, ["/confirmed.html"], suffix);
  }
});

test("Android recovery rejects legacy implicit tokens instead of forwarding them", () => {
  const fragment = "#access_token=android-access&refresh_token=android-refresh&type=recovery";
  const result = runCallback(
    `https://gymapptracker.com/confirmed.html?platform=android${fragment}`
  );

  assert.equal(result.button.getAttribute("href"), "https://gymapptracker.com/");
  assert.doesNotMatch(result.button.getAttribute("href"), /token|auth\/callback/i);
  assert.match(result.title.textContent, /unavailable/i);
  assert.deepEqual(result.scrubbed, ["/confirmed.html"]);
  assert.deepEqual(result.assigned, []);
});

test("Android recovery forwards only a state-bound PKCE code and retains the fallback", () => {
  const state = "A".repeat(32);
  const code = "4be36bc9-5ee4-40f3-a674-5ebf01b53ac8";
  const url = `https://gymapptracker.com/confirmed.html?platform=android&state=${state}&purpose=recovery&code=${code}`;
  const result = runCallback(url);
  const restored = runCallback(url);
  const expected = `com.setforge.gymapp://auth/callback?state=${state}&purpose=recovery&code=${code}`;

  assert.equal(result.button.getAttribute("href"), expected);
  assert.doesNotMatch(result.button.getAttribute("href"), /access_token|refresh_token/i);
  assert.equal(result.button.textContent, "Open GymApp to reset password");
  assert.match(result.title.textContent, /password reset verified/i);
  assert.deepEqual(result.assigned, []);
  assert.deepEqual(result.scrubbed, []);
  assert.equal(restored.button.getAttribute("href"), expected);
  assert.deepEqual(restored.assigned, []);
});

test("Android PKCE recovery fails closed for state mismatch shapes and token injection", () => {
  const state = "B".repeat(32);
  const validCode = "8cb8764c-cb11-44e5-81e6-7ed02ac25101";
  const secondCode = "7e69412b-f558-40a6-9de8-63a324783d24";
  const cases = [
    `?platform=android&state=short&purpose=recovery&code=${validCode}`,
    `?platform=android&state=${state}&state=${state}&purpose=recovery&code=${validCode}`,
    `?platform=android&state=${state}&purpose=recovery&purpose=signup&code=${validCode}`,
    `?platform=android&state=${state}&purpose=recovery&code=${validCode}&code=${secondCode}`,
    `?platform=android&state=${state}&purpose=signup&purpose=recovery&code=${validCode}`,
    `?platform=android&state=${state}&purpose=unknown&code=${validCode}`,
    `?platform=android&state=${state}&purpose=recovery&code=${validCode}&access_token=unsafe`,
    `?platform=android&state=${state}&purpose=recovery&code=${validCode}#refresh_token=unsafe`,
    `?platform=android&state=${state}&purpose=recovery&code=eyJhbGciOiJIUzI1NiJ9.payload.signature`
  ];

  for (const suffix of cases) {
    const result = runCallback(`https://gymapptracker.com/confirmed.html${suffix}`);
    assert.equal(result.button.getAttribute("href"), "https://gymapptracker.com/", suffix);
    assert.doesNotMatch(result.button.getAttribute("href"), /unsafe|auth\/callback/i, suffix);
    assert.deepEqual(result.assigned, [], suffix);
    assert.deepEqual(result.scrubbed, ["/confirmed.html"], suffix);
  }
});

test("web confirmation discards implicit credentials and returns to the canonical site", () => {
  const result = runCallback(
    "https://gymapptracker.com/confirmed.html?platform=web#access_token=secret&refresh_token=secret"
  );

  assert.equal(result.button.getAttribute("href"), "https://gymapptracker.com/");
  assert.doesNotMatch(result.button.getAttribute("href"), /secret|token/i);
  assert.match(result.message.textContent, /log in with your password/i);
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
  assert.deepEqual(result.assigned, [result.button.getAttribute("href")]);
  assert.deepEqual(result.scrubbed, []);
});

test("iOS recovery bridge launches the app, keeps a reload fallback, and uses recovery copy", () => {
  const state = "R".repeat(32);
  const code = "single-use-pkce-code";
  const url = `https://gymapptracker.com/confirmed.html?platform=ios&state=${state}&purpose=recovery&code=${code}`;
  const first = runCallback(url);
  const restored = runCallback(url);
  const expected = `com.setforge.gymapp.ios://auth/callback/${state}?code=${code}`;

  assert.equal(first.button.getAttribute("href"), expected);
  assert.equal(first.button.textContent, "Open GymApp to reset password");
  assert.match(first.title.textContent, /password reset verified/i);
  assert.match(first.message.textContent, /choose a new password/i);
  assert.deepEqual(first.assigned, [expected]);
  assert.deepEqual(first.scrubbed, []);

  assert.equal(restored.button.getAttribute("href"), expected);
  assert.deepEqual(restored.assigned, [expected]);
  assert.deepEqual(restored.scrubbed, []);
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
  assert.deepEqual(result.assigned, [result.button.getAttribute("href")]);
  assert.deepEqual(result.scrubbed, []);
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
    `?platform=ios&state=${state}&purpose=recovery&purpose=signup&code=valid`,
    `?platform=ios&state=${state}&purpose=unknown&code=valid`,
    `?platform=ios&state=too-short&code=valid`,
    `?platform=ios&state=${state}&code=valid&error=access_denied`,
    `?platform=ios&state=${state}&error_description=missing-error`
  ];

  for (const suffix of cases) {
    const result = runCallback(`https://gymapptracker.com/confirmed.html${suffix}`);
    assert.equal(result.button.getAttribute("href"), "https://gymapptracker.com/", suffix);
    assert.doesNotMatch(result.button.getAttribute("href"), /secret|auth\/callback/i, suffix);
    assert.match(result.title.textContent, /unavailable/i, suffix);
    assert.deepEqual(result.assigned, [], suffix);
    assert.deepEqual(result.scrubbed, ["/confirmed.html"], suffix);
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
  const [android, pwa, index, confirmation, cname, operations] = await Promise.all([
    readFile("app/src/main/java/com/example/gymapp/auth/CloudAuthManager.kt", "utf8"),
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/index.html", "utf8"),
    readFile("pwa/confirmed.html", "utf8"),
    readFile("pwa/CNAME", "utf8"),
    readFile("docs/OPERATIONS.md", "utf8")
  ]);
  const signUpSource = android.slice(
    android.indexOf("suspend fun signUp"),
    android.indexOf("suspend fun resendSignUpConfirmation")
  );
  const resendSource = android.slice(
    android.indexOf("suspend fun resendSignUpConfirmation"),
    android.indexOf("suspend fun requestPasswordReset")
  );

  assert.ok(android.includes("https://gymapptracker.com/confirmed.html?platform=android"));
  assert.match(android, /AUTH_BRIDGE_VARIANT_QUERY/);
  assert.match(android, /\/auth\/v1\/resend\?redirect_to=/);
  assert.match(signUpSource, /purpose=signup/);
  assert.match(signUpSource, /\.put\("code_challenge", codeChallenge\(transaction\.codeVerifier\)\)/);
  assert.match(signUpSource, /\.put\("code_challenge_method", "s256"\)/);
  assert.match(resendSource, /WEB_AUTH_REDIRECT_URL/);
  assert.match(resendSource, /clearPendingAuthTransaction\(PENDING_SIGNUP_KEY\)/);
  assert.doesNotMatch(resendSource, /code_challenge|beginAuthTransaction|purpose=signup/);
  assert.ok(pwa.includes("https://gymapptracker.com/confirmed.html?platform=web"));
  assert.match(pwa, /\/auth\/v1\/resend\?redirect_to=/);
  assert.match(pwa, /if \(!query\.has\("platform"\)\) query\.set\("platform", "web"\)/);
  assert.ok(pwa.includes("https://gymapptracker.com/support.html"));
  assert.ok(pwa.includes("https://gymapptracker.com/privacy-policy.html"));
  assert.ok(index.includes('rel="canonical" href="https://gymapptracker.com/"'));
  assert.match(confirmation, /Content-Security-Policy/);
  assert.match(confirmation, /name="referrer" content="no-referrer"/);
  assert.doesNotMatch(confirmation, /<script[^>]+src="https?:\/\//i);
  assert.equal(cname, "gymapptracker.com\n");
  assert.ok(operations.includes("https://eduard047.github.io/GymApp/confirmed.html"));
});
