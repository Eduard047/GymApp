import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, russianSource, stateContractSource, progressionRulesSource] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/russian-text.js", "utf8"),
  readFile("pwa/state-contract.js", "utf8"),
  readFile("pwa/progression-rules.js", "utf8")
]);

function createStorage() {
  const values = new Map();
  return {
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: key => values.delete(key)
  };
}

function loadPwaContext() {
  const localStorage = createStorage();
  const sessionStorage = createStorage();
  const context = {
    console,
    Date,
    Map,
    Set,
    TextEncoder,
    URL,
    URLSearchParams,
    window: {
      location: { search: "?access_token=test", hash: "", replace() {} },
      addEventListener() {},
      sessionStorage
    },
    document: {
      documentElement: { lang: "en" },
      querySelector() {
        return { innerHTML: "", querySelectorAll: () => [], querySelector: () => null };
      }
    },
    navigator: {},
    localStorage,
    sessionStorage,
    requestAnimationFrame: callback => callback(),
    clearTimeout,
    setTimeout,
    clearInterval,
    setInterval,
    fetch: () => Promise.reject(new Error("network disabled in tests"))
  };
  context.window.document = context.document;
  context.window.navigator = context.navigator;
  context.window.localStorage = localStorage;
  context.window.self = context.window;
  context.window.top = context.window;
  context.window.__GYMAPP_TOP_LEVEL__ = true;
  vm.createContext(context);
  vm.runInContext(stateContractSource, context);
  context.window.GymStateContract = context.GymStateContract;
  vm.runInContext(progressionRulesSource, context);
  context.window.GymProgressionRules = context.GymProgressionRules;
  vm.runInContext(russianSource, context);
  vm.runInContext(appSource, context);
  vm.runInContext('state.language = "ru"', context);
  return context;
}

function decodeLiteral(literal) {
  return vm.runInNewContext(literal);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function staticRussianCandidates() {
  const values = new Set();
  const literal = /("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/;
  const txPattern = new RegExp(`\\btx\\(\\s*${literal.source}`, "g");
  for (const match of appSource.matchAll(txPattern)) values.add(decodeLiteral(match[1]));

  const englishTextBlock = appSource.match(
    /const text = \{\s*en:\s*\{([\s\S]*?)\n\s*\},\s*\n\s*uk:/
  )?.[1] || "";
  const valuePattern = new RegExp(`:\\s*${literal.source}`, "g");
  for (const match of englishTextBlock.matchAll(valuePattern)) values.add(decodeLiteral(match[1]));

  for (const match of appSource.matchAll(/names:\s*\{\s*en:\s*("(?:\\.|[^"\\])*")/g)) {
    values.add(decodeLiteral(match[1]));
  }
  for (const match of appSource.matchAll(/\["[^"]+",\s*\d+,\s*("(?:\\.|[^"\\])*")/g)) {
    values.add(decodeLiteral(match[1]));
  }
  return values;
}

test("PWA Russian dictionary covers every static runtime label", () => {
  const context = loadPwaContext();
  const missing = [...staticRussianCandidates()].filter(value => {
    if (!/[A-Za-z]/.test(value)) return false;
    const translated = context.window.GymRussianText.translate(value);
    return translated === value;
  });

  assert.deepEqual(missing, []);
  assert.equal(vm.runInContext('n(1, "active day", "active days", "активний день", "активні дні", "активних днів")', context), "1 активный день");
  assert.equal(vm.runInContext('n(3, "active day", "active days", "активний день", "активні дні", "активних днів")', context), "3 активных дня");
  assert.equal(vm.runInContext('n(12, "saved session", "saved sessions", "збережене тренування", "збережені тренування", "збережених тренувань")', context), "12 сохранённых тренировок");
});

test("audited Ukrainian runtime labels keep their intended workout, progress, auth, and Garmin meaning", () => {
  const context = loadPwaContext();
  const topLevelText = JSON.parse(vm.runInContext("JSON.stringify(text)", context));
  const topLevelCases = new Map([
    ["repeatLast", ["Repeat Last Workout", "Повторити останнє тренування"]],
    ["templatePicker", ["Copy a previous workout", "Скопіювати попереднє тренування"]],
    ["copyLast", ["Copy Last Set", "Копіювати останній підхід"]],
    ["sharePdf", ["Share PDF report", "Поділитися PDF-звітом"]],
    ["smartCoach", ["Smart Coach", "Розумний тренер"]],
    ["soloProgress", ["Solo Progress", "Особистий прогрес"]],
    ["useLast", ["Use Last Weight", "Використати останню вагу"]]
  ]);
  for (const [key, [english, ukrainian]] of topLevelCases) {
    assert.equal(topLevelText.en[key], english, `${key} English source`);
    assert.equal(topLevelText.uk[key], ukrainian, `${key} Ukrainian translation`);
  }

  const adjacentLiteralCases = new Map([
    ["2 / week", "2 рази на тиждень"],
    ["3 / week", "3 рази на тиждень"],
    ["4 / week", "4 рази на тиждень"],
    ["5 / week", "5 разів на тиждень"],
    ["6 / week", "6 разів на тиждень"],
    ["Copy this Garmin pairing token into Connect IQ settings now. Treat it as a password. It will not be stored or shown again. Choose Cancel to revoke it.", "Зараз скопіюй цей токен сполучення Garmin у налаштування Connect IQ. Стався до нього як до пароля. Він не буде збережений або показаний знову. Натисни «Скасувати», щоб відкликати його."],
    ["Existing Garmin recovery was cancelled. No new device identity was created.", "Відновлення наявного сполучення Garmin скасовано. Новий ідентифікатор пристрою не створено."],
    ["First download the untouched private JSON for offline recovery. Replacing it with an empty valid state is permanent and uses the exact server revision so another device's newer update cannot be overwritten.", "Спочатку завантаж незмінений приватний JSON для офлайн-відновлення. Заміна на порожній коректний стан незворотна й використовує точну ревізію сервера, тому новіші зміни з іншого пристрою не будуть перезаписані."],
    ["Front", "Спереду"],
    ["Garmin unpair failed.", "Не вдалося від’єднати Garmin."],
    ["Last", "Остання вага"],
    ["Maintenance", "Підтримання"],
    ["Maximum weight and session volume over time.", "Максимальна вага та обсяг тренування в динаміці."],
    ["No exercise data yet", "За цією вправою поки немає даних"],
    ["No logged exercises for this muscle in the selected period.", "Для цієї групи м'язів у вибраному періоді немає записаних вправ."],
    ["Open the full rank list and check the next unlocks.", "Відкрий повний список рангів і подивися, що відкриється далі."],
    ["Paste exported GymApp JSON here", "Встав сюди експортований JSON GymApp"],
    ["Plateau plan: change the rep target to break the flat trend.", "План виходу з плато: зміни ціль за повторами, щоб подолати застій."],
    ["One softer session is held steady; a deload needs two comparable regressions.", "Одне слабше тренування утримує навантаження; для розвантаження потрібні два порівнювані спади."],
    ["Recent volume dropped compared with the previous session.", "Обсяг останнього тренування нижчий за обсяг попереднього."],
    ["Sign in to sync workouts across devices.", "Увійди, щоб синхронізувати тренування між пристроями."],
    ["Smart Coach uses this to match your plan, goal and recovery.", "Розумний тренер використовує ці дані, щоб підібрати план з урахуванням цілі та відновлення."],
    ["Suggested from your recent exercise pattern and training profile.", "Підібрано з урахуванням недавніх вправ і профілю тренувань."],
    ["Switch", "Змінити акаунт"],
    ["The increase is intentionally conservative.", "Збільшення навмисно невелике."],
    ["The pending Garmin device is no longer active. Run Sync Watch again to choose or create a pairing.", "Пристрій Garmin, що очікував на сполучення, більше не активний. Знову натисни «Синхронізувати з годинником», щоб вибрати або створити сполучення."],
    ["This legacy local account name is ambiguous. Its stored data was left untouched; rename/recover it before signing in.", "Ця назва старого локального акаунта неоднозначна. Збережені дані не змінено; віднови або перейменуй акаунт перед входом."],
    ["View workout", "Відкрити тренування"],
    ["Your authenticated cloud row uses a legacy or invalid format. It was not loaded into the app and cannot sync until you choose a recovery action.", "Твій автентифікований хмарний запис має застарілий або некоректний формат. Його не завантажено в застосунок, і синхронізація заблокована, доки не вибереш спосіб відновлення."],
    ["Your latest result and the direction of recent sessions.", "Останній результат і динаміка недавніх тренувань."],
    ["into this level", "на цьому рівні"],
    ["A one-time Garmin token will be shown. It works like a password: paste it only into this watch's Connect IQ settings. GymApp will not store or show it again. Continue?", "Буде показано одноразовий токен Garmin. Він працює як пароль: встав його лише в налаштування Connect IQ цього годинника. GymApp не збереже та більше не покаже його. Продовжити?"],
    ["Last session was stable across the sets.", "Результати останнього тренування були стабільними в усіх підходах."],
    ["Use at least 12 characters (up to 72 UTF-8 bytes) with lowercase and uppercase Latin letters, a number, and a supported symbol such as !, @, #, or $.", "Використай щонайменше 12 символів (до 72 байтів UTF-8): малу й велику латинські літери, цифру та підтримуваний спецсимвол, наприклад !, @, # або $."],
    ["Password must contain at least 12 characters, fit within 72 UTF-8 bytes, and include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol.", "Пароль має містити щонайменше 12 символів, займати не більше 72 байтів у UTF-8 та включати малу й велику латинські літери, цифру й підтримуваний спецсимвол."],
    ["Repeat email", "Повтори адресу електронної пошти"],
    ["Send email again", "Надіслати лист ще раз"],
    ["The unseen Garmin token could not be persisted or revoked. Keep this page open and retry Garmin sync or sign-out to revoke it.", "Непоказаний токен Garmin не вдалося ні зберегти, ні відкликати. Не закривай цю сторінку: повтори синхронізацію з Garmin або вийди з акаунта, щоб відкликати токен."],
    ["Workout summary unavailable.", "Підсумок тренування недоступний."],
    ["Your training history and next best move.", "Твоя історія тренувань і рекомендація, що робити далі."]
  ]);
  for (const [english, ukrainian] of adjacentLiteralCases) {
    const adjacentPair = new RegExp(`${escapeRegExp(JSON.stringify(english))}\\s*,\\s*${escapeRegExp(JSON.stringify(ukrainian))}`);
    assert.match(appSource, adjacentPair, english);
  }
});

test("PWA Russian dynamic Garmin, workout, exercise, and mission text never falls back to English", () => {
  const context = loadPwaContext();
  const cases = new Map([
    [
      "Restore the existing Garmin pairing “Fenix 8”? Its old token will stop immediately, and a replacement token for the same watch identity will be shown once. Cancel keeps the current token working.",
      "Восстановить существующее подключение Garmin «Fenix 8»? Старый токен сразу перестанет работать, а новый токен для тех же часов будет показан один раз. Отмена сохранит текущий токен."
    ],
    [
      "Choose the existing Garmin watch to restore (1-2). Rotating its token preserves the watch identity:\n1. Fenix 8 (abcdef12)",
      "Выберите часы Garmin для восстановления (1–2). Обновление токена сохранит идентификатор часов:\n1. Fenix 8 (abcdef12)"
    ],
    ["12 days since this exercise, so the load is adjusted down.", "12 дней без этого упражнения, поэтому нагрузка снижена."],
    ["3 mapped", "Сопоставлено: 3"],
    ["Log sets for Жим лёжа to unlock trends.", "Добавь подходы для Жим лёжа, чтобы открыть тренды."],
    ["8 recent sessions", "8 недавних тренировок"],
    ["Delete workout from 20 июля 2026 г.?", "Удалить тренировку от 20 июля 2026 г.?"],
    ["High-output days 3", "Дни высокой нагрузки: 3"],
    ["Volume days 4", "Дни объёмных тренировок: 4"],
    ["Strong sessions 5", "Сильные тренировки: 5"],
    ["Wide sessions 6", "Разнообразные тренировки: 6"]
  ]);
  for (const [english, expected] of cases) {
    assert.equal(context.window.GymRussianText.translate(english), expected, english);
  }

  const missionTranslations = JSON.parse(vm.runInContext(`JSON.stringify(
    [...dailyMissionCatalog(), ...weeklyMissionCatalog(), ...monthlyMissionCatalog()].map(template => ({
      titleEn: template.titleEn,
      titleRu: tx(template.titleEn, template.titleUk),
      unitEn: template.unitEn,
      unitRu: tx(template.unitEn, template.unitUk)
    }))
  )`, context));
  assert.equal(missionTranslations.length > 100, true);
  for (const item of missionTranslations) {
    assert.notEqual(item.titleRu, item.titleEn, item.titleEn);
    assert.notEqual(item.unitRu, item.unitEn, item.unitEn);
    assert.doesNotMatch(item.titleRu, /\b(?:check-in|days|sessions)\b/i, item.titleEn);
  }
});

test("destructive confirmations have explicit Russian labels and escaped previews", () => {
  const context = loadPwaContext();
  const cases = new Map([
    ["Cancel", "Отмена"],
    ["Delete set", "Удалить подход"],
    ["Delete this exercise from your library? This cannot be undone in GymApp.", "Удалить это упражнение из каталога? В GymApp это действие нельзя отменить."],
    ["Replace profile with backup?", "Заменить профиль резервной копией?"],
    ["Replace with backup", "Заменить резервной копией"],
    ["This confirmation is no longer current. Nothing was changed.", "Это подтверждение уже неактуально. Ничего не изменено."]
  ]);
  for (const [english, expected] of cases) {
    assert.equal(context.window.GymRussianText.translate(english), expected, english);
  }

  vm.runInContext(`modal = {
    type: "confirm-delete-exercise",
    intent: { preview: { name: '<img src=x onerror="alert(1)">' } }
  }`, context);
  const markup = vm.runInContext("modalMarkup()", context);
  assert.match(markup, /role="alertdialog"/);
  assert.match(markup, />Отмена</);
  assert.match(markup, />Удалить упражнение</);
  assert.doesNotMatch(markup, /<img|onerror="alert/);
  assert.match(markup, /&lt;img src=x onerror=&quot;alert\(1\)&quot;&gt;/);
});

test("missions render one accessible daily, weekly, or monthly panel at a time", () => {
  const context = loadPwaContext();

  for (const period of ["daily", "weekly", "monthly"]) {
    vm.runInContext(`missionPeriod = ${JSON.stringify(period)}`, context);
    const markup = vm.runInContext("missionsScreen()", context);
    assert.match(markup, /role="tablist"/);
    assert.equal((markup.match(/role="tab"/g) || []).length, 3);
    assert.equal((markup.match(/role="tabpanel"/g) || []).length, 1);
    assert.match(markup, new RegExp(`id="mission-panel-${period}"`));
    assert.match(markup, new RegExp(`id="mission-tab-${period}"[^>]+aria-selected="true"`));
  }
});

test("localized attributes and audited generated labels are HTML encoded", () => {
  const context = loadPwaContext();
  const payload = '" autofocus onfocus="alert(1)" <img src=x onerror=alert(2)>';
  context.translationPayload = payload;
  vm.runInContext(`window.GymRussianText = {
    translate(value) {
      return ["Language", "Chest"].includes(String(value)) ? translationPayload : String(value);
    }
  }`, context);

  const encoded = vm.runInContext('txAttr("Language", "Мова")', context);
  assert.equal(encoded, "&quot; autofocus onfocus=&quot;alert(1)&quot; &lt;img src=x onerror=alert(2)&gt;");

  const selector = vm.runInContext("languageSelectorMarkup()", context);
  assert.doesNotMatch(selector, /<img|aria-label="" autofocus/i);
  assert.match(selector, /aria-label="&quot; autofocus/);

  const mapping = vm.runInContext('mappingEditor("Bench Press")', context);
  assert.doesNotMatch(mapping, /<img/);
  assert.match(mapping, /&lt;img src=x/);

  const mission = vm.runInContext(`missionSection(
    translationPayload,
    translationPayload,
    [{ done: false, title: translationPayload, summary: translationPayload,
       cadenceLabel: translationPayload, reward: 10, progressLabel: translationPayload,
       progress: 0, target: 1 }]
  )`, context);
  assert.doesNotMatch(mission, /<img|onfocus="alert/);
  assert.match(mission, /&lt;img src=x/);

  assert.doesNotMatch(appSource, /(?:aria-label|placeholder)="\$\{(?:tx|t)\(/);
});

test("provider and server failures resolve only to stable messages in every PWA locale", () => {
  const context = loadPwaContext();
  const hostile = '<img src=x onerror=alert(1)> bearer-secret user@example.test';
  context.hostile = hostile;
  const expectedGeneric = {
    en: "Cloud request failed. Check your connection and try again.",
    uk: "Не вдалося виконати хмарний запит. Перевір з’єднання та спробуй ще раз.",
    ru: "Не удалось выполнить облачный запрос. Проверь подключение и попробуй снова."
  };
  const expectedGarmin = {
    en: "Garmin sync failed. Check your connection and try again.",
    uk: "Не вдалося синхронізувати Garmin. Перевір з’єднання та спробуй ще раз.",
    ru: "Не удалось синхронизировать Garmin. Проверь подключение и попробуй снова."
  };
  const expectedTrusted = {
    en: "Sign-out was cancelled so Garmin revocation can be retried.",
    uk: "Вихід скасовано, щоб можна було повторити відкликання Garmin.",
    ru: "Выход отменен, чтобы можно было повторить отзыв Garmin."
  };

  for (const locale of ["en", "uk", "ru"]) {
    vm.runInContext(`state.language = ${JSON.stringify(locale)}`, context);
    const unmatched = vm.runInContext(
      "friendlyAuthError(new Error(JSON.stringify({ message: hostile, error_description: hostile })))",
      context
    );
    assert.equal(unmatched, expectedGeneric[locale]);
    assert.doesNotMatch(unmatched, /bearer-secret|example\.test|<img/i);

    const garmin = vm.runInContext(`friendlyOperationError(
      Object.assign(new Error(hostile), { status: 500, USER_VISIBLE_ERROR_MESSAGES: { en: hostile, uk: hostile } }),
      "Garmin sync failed. Check your connection and try again.",
      "Не вдалося синхронізувати Garmin. Перевір з’єднання та спробуй ще раз."
    )`, context);
    assert.equal(garmin, expectedGarmin[locale]);
    assert.doesNotMatch(garmin, /bearer-secret|example\.test|<img/i);

    const trusted = vm.runInContext(`friendlyOperationError(
      userVisibleError(
        "Sign-out was cancelled so Garmin revocation can be retried.",
        "Вихід скасовано, щоб можна було повторити відкликання Garmin."
      ),
      "Account switch was cancelled.",
      "Перемикання акаунта скасовано."
    )`, context);
    assert.equal(trusted, expectedTrusted[locale]);
  }

  const authCases = new Map([
    ['{"error_code":"user_already_exists","message":"hostile detail"}', "An account with this email already exists. Log in or resend the confirmation email."],
    ['{"error_code":"email_not_confirmed","message":"hostile detail"}', "Confirm your email first, then log in."],
    ['{"error_code":"invalid_credentials","message":"hostile detail"}', "Email or password is incorrect."],
    ['{"error_code":"over_email_send_rate_limit","message":"hostile detail"}', "Too many confirmation emails were requested. Supabase may block new emails for up to an hour on the built-in sender. Try again later, or contact support if the email never arrives."]
  ]);
  vm.runInContext('state.language = "en"', context);
  for (const [providerBody, expected] of authCases) {
    context.providerBody = providerBody;
    assert.equal(vm.runInContext("friendlyAuthError(new Error(providerBody))", context), expected);
  }

  assert.doesNotMatch(appSource, /showToast\([^\n]*(?:error|err|retryError)\??\.message/);
  assert.doesNotMatch(appSource, /return\s+message\s*\|\|/);
});
