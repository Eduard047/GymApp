import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const support = await readFile("ios/GymApp-iOS/AppStore/support.html", "utf8");
const privacy = await readFile("ios/GymApp-iOS/AppStore/privacy-policy.html", "utf8");
const appPrivacy = await readFile("ios/GymApp-iOS/AppStore/APP_PRIVACY.md", "utf8");
const legalCSS = await readFile("ios/GymApp-iOS/AppStore/legal.css", "utf8");
const languageJS = await readFile("ios/GymApp-iOS/AppStore/legal-language.js", "utf8");
const manifest = JSON.parse(await readFile("pwa/manifest.webmanifest", "utf8"));

test("public legal pages share the selected accessible light/dark design system", () => {
  for (const page of [support, privacy]) {
    assert.match(page, /href="\.\/legal\.css"/);
    assert.match(page, /src="\.\/legal-language\.js" defer/);
    assert.match(page, /Content-Security-Policy/);
    assert.match(page, /connect-src 'none'/);
    assert.match(page, /referrer" content="no-referrer/);
    assert.match(page, /data-language="en"[^>]+aria-pressed="true"/);
    assert.match(page, /id="english" class="locale-panel locale-en(?: policy-article)?"/);
    assert.match(page, /id="ukrainian" class="locale-panel locale-uk(?: policy-article)?"[^>]+hidden/);
    assert.match(page, /id="russian" class="locale-panel locale-ru(?: policy-article)?"[^>]+hidden/);
    assert.match(page, /href="\/favicon-32\.png"/);
    assert.match(page, /href="\/apple-touch-icon\.png"/);
    assert.doesNotMatch(page, /<(?:style|iframe|form)\b/i);
    assert.doesNotMatch(page, /\son[a-z]+\s*=/i);
    assert.doesNotMatch(page, /<(?:script|img)[^>]+(?:googletagmanager|facebook\.net|doubleclick|analytics)[^>]*>/i);
  }

  assert.match(legalCSS, /--page: #f3f0e8/);
  assert.match(legalCSS, /--accent: #315bd9/);
  assert.match(legalCSS, /@media \(prefers-color-scheme: dark\)/);
  assert.match(legalCSS, /--page: #080f1b/);
  assert.match(legalCSS, /:focus-visible/);
  assert.match(legalCSS, /@media \(max-width: 560px\)/);
});

test("locale switch is allowlisted, keeps English as the safe fallback, and stores nothing", () => {
  assert.match(languageJS, /\["en", "english"\]/);
  assert.match(languageJS, /\["uk", "ukrainian"\]/);
  assert.match(languageJS, /\["ru", "russian"\]/);
  assert.match(languageJS, /return "en"/);
  assert.match(languageJS, /locales\.has\(locale\) \? locale : "en"/);
  assert.match(languageJS, /panelID === id \|\| id\.startsWith\(`\$\{locale\}-`\)/);
  assert.doesNotMatch(languageJS, /(?:localStorage|sessionStorage|document\.cookie|fetch\s*\(|XMLHttpRequest|sendBeacon)/);
});

function runLanguageSwitch(hash, languages) {
  const buttons = ["en", "uk", "ru"].map(locale => ({
    dataset: { language: locale },
    attributes: new Map(),
    setAttribute(name, value) { this.attributes.set(name, String(value)); },
    addEventListener() {}
  }));
  const panels = new Map([
    ["english", { hidden: false }],
    ["ukrainian", { hidden: true }],
    ["russian", { hidden: true }]
  ]);
  const context = {
    document: {
      documentElement: { lang: "en" },
      querySelectorAll() { return buttons; },
      getElementById(id) { return panels.get(id) || null; }
    },
    navigator: { language: languages[0], languages },
    window: {
      location: { hash },
      history: { replaceState() {} },
      addEventListener() {}
    }
  };

  vm.runInNewContext(languageJS, context);
  return { buttons, panels, lang: context.document.documentElement.lang };
}

test("deep privacy links retain their allowlisted locale and unknown locales fail to English", () => {
  const russian = runLanguageSwitch("#ru-security", ["en-US"]);
  assert.equal(russian.lang, "ru");
  assert.equal(russian.panels.get("russian").hidden, false);
  assert.equal(russian.panels.get("english").hidden, true);

  const ukrainian = runLanguageSwitch("#uk-rights", ["fr-FR"]);
  assert.equal(ukrainian.lang, "uk");
  assert.equal(ukrainian.panels.get("ukrainian").hidden, false);

  const fallback = runLanguageSwitch("#unsupported", ["fr-FR"]);
  assert.equal(fallback.lang, "en");
  assert.equal(fallback.panels.get("english").hidden, false);
});

test("support keeps all localized answers compact and points account data to Profile", () => {
  assert.equal((support.match(/<details class="faq-item"/g) || []).length, 24);
  assert.match(support, /Profile → Account, privacy &amp; deletion → Delete Account/);
  assert.match(support, /Профіль → Обліковий запис, конфіденційність і видалення → Видалити обліковий запис/);
  assert.match(support, /Профиль → Аккаунт, конфиденциальность и удаление → Удалить учётную запись/);
  assert.match(support, /Profile → Backup &amp; diagnostics/);
  assert.match(support, /Профіль → Резервні копії та діагностика/);
  assert.match(support, /Профиль → Резервные копии и диагностика/);
  assert.doesNotMatch(support, /(?:Exercises|Вправи|Упражнения) → (?:Account|Обліковий запис|Учётная запись)/);
});

test("privacy policy has localized summaries, contents, responsive source tables, and current paths", () => {
  assert.equal((privacy.match(/class="summary-grid"/g) || []).length, 3);
  assert.equal((privacy.match(/class="policy-toc"/g) || []).length, 3);
  assert.equal((privacy.match(/<table>/g) || []).length, 3);
  assert.equal((privacy.match(/<h3 id="(?:en|uk|ru)-/g) || []).length, 33);
  assert.match(privacy, /Profile → Account, privacy &amp; deletion → Delete Account/);
  assert.match(privacy, /Профіль → Обліковий запис, конфіденційність і видалення → Видалити обліковий запис/);
  assert.match(privacy, /Профиль → Аккаунт, конфиденциальность и удаление → Удалить учётную запись/);
  assert.doesNotMatch(privacy, /(?:Exercises|Вправи|Упражнения) → (?:Account|Обліковий запис|Учётная запись)/);
});

test("privacy sources disclose bounded default-off read-only friend workout details", () => {
  assert.match(privacy, /separate explicit owner setting that is off by default/);
  assert.match(privacy, /at most those same five recent workouts/);
  assert.match(privacy, /changing the active account closes the view and requires fresh authorization/);
  assert.match(privacy, /окремим явним налаштуванням власника, яке типово вимкнене/);
  assert.match(privacy, /щонайбільше для тих самих п’яти недавніх тренувань/);
  assert.match(privacy, /зміна активного акаунта закриває перегляд і вимагає нової авторизації/);
  assert.match(privacy, /отдельной явной настройке владельца, выключенной по умолчанию/);
  assert.match(privacy, /максимум для тех же пяти недавних тренировок/);
  assert.match(privacy, /смена активной учётной записи закрывает просмотр и требует новой авторизации/);
  assert.match(appPrivacy, /separate explicit owner gesture for `share_workout_details`/);
  assert.match(appPrivacy, /false by default/);
  assert.match(appPrivacy, /changing the active account closes and clears any open exact detail/);
});

function pngSize(buffer) {
  assert.deepEqual([...buffer.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
    colorType: buffer[25]
  };
}

test("PWA manifest exposes dedicated opaque any and maskable launcher sizes", async () => {
  assert.deepEqual(manifest.icons, [
    { src: "./icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
    { src: "./icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
    { src: "./icon-maskable-192.png", sizes: "192x192", type: "image/png", purpose: "maskable" },
    { src: "./icon-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" }
  ]);

  const expected = new Map([
    ["pwa/icon-192.png", 192],
    ["pwa/icon-512.png", 512],
    ["pwa/icon-maskable-192.png", 192],
    ["pwa/icon-maskable-512.png", 512],
    ["pwa/apple-touch-icon.png", 180],
    ["pwa/favicon-32.png", 32]
  ]);

  for (const [path, size] of expected) {
    const dimensions = pngSize(await readFile(path));
    assert.deepEqual(
      { width: dimensions.width, height: dimensions.height },
      { width: size, height: size },
      path
    );
    assert.ok([2, 6].includes(dimensions.colorType), `${path} must be RGB or RGBA`);
  }

  assert.deepEqual(
    await readFile("pwa/icon-192.png"),
    await readFile("pwa/icon-maskable-192.png")
  );
  assert.deepEqual(
    await readFile("pwa/icon-512.png"),
    await readFile("pwa/icon-maskable-512.png")
  );
});

test("pre-Android 8 launcher resources use the current mark at every density", async () => {
  const densities = new Map([
    ["mdpi", 48],
    ["hdpi", 72],
    ["xhdpi", 96],
    ["xxhdpi", 144],
    ["xxxhdpi", 192]
  ]);

  for (const [density, size] of densities) {
    for (const name of ["ic_launcher", "ic_launcher_round"]) {
      const base = `app/src/main/res/mipmap-${density}/${name}`;
      const dimensions = pngSize(await readFile(`${base}.png`));
      assert.deepEqual(
        { width: dimensions.width, height: dimensions.height },
        { width: size, height: size },
        base
      );
      assert.ok([2, 6].includes(dimensions.colorType), `${base} must be RGB or RGBA`);
      await assert.rejects(readFile(`${base}.webp`), error => error?.code === "ENOENT");
    }
  }
});
