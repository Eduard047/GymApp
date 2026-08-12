(function (root, factory) {
  const codec = root.GymSharedWorkout ||
    (typeof module !== "undefined" && module.exports && typeof require === "function"
      ? require("../shared-workout.js")
      : null);
  const api = factory(codec);
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  root.GymSharedWorkoutLanding = api;
  if (root.document && root.location) {
    const render = () => api.mount(root.document, root.location.href, root.navigator);
    const start = () => {
      render();
      if (typeof root.addEventListener === "function") {
        root.addEventListener("hashchange", render);
      }
    };
    if (root.document.readyState === "loading") {
      root.document.addEventListener("DOMContentLoaded", start, { once: true });
    } else {
      start();
    }
  }
})(typeof globalThis !== "undefined" ? globalThis : window, function buildSharedWorkoutLanding(codec) {
  "use strict";

  const CANONICAL_SITE = "https://gymapptracker.com/";
  const CANONICAL_WORKOUT_PATH = "/workout/";
  const ANDROID_SCHEME = "com.setforge.gymapp";
  const IOS_SCHEME = "com.setforge.gymapp.ios";
  const GOOGLE_PLAY_URL = "https://play.google.com/store/apps/details?id=com.setforge.gymapp";
  const CREDENTIAL_KEYS = new Set(["access_token", "refresh_token", "token", "code", "apikey", "api_key"]);

  const COPY = Object.freeze({
    en: Object.freeze({
      title: "Shared GymApp workout",
      brand: "Workout plan",
      heading: "Choose where to open this plan",
      subtitle: "Review the exercises, then open an editable copy in GymApp.",
      invalidTitle: "This workout link is invalid",
      invalidCopy: "Ask the sender to create and send the link again.",
      home: "Open GymApp website",
      previewTitle: "Workout preview",
      exercises: "Exercises",
      sets: "Sets",
      volume: "Volume",
      actionTitle: "Open in GymApp",
      android: "Open Android app",
      ios: "Open iPhone app",
      googlePlay: "Get GymApp on Google Play",
      downloads: "GymApp downloads",
      privacy: "Only exercises, weights, and reps are included. Nothing is added to your history until you confirm it.",
      set: "Set",
      kg: "kg"
    }),
    uk: Object.freeze({
      title: "Спільне тренування GymApp",
      brand: "План тренування",
      heading: "Обери, де відкрити цей план",
      subtitle: "Переглянь вправи, а потім відкрий редаговану копію у GymApp.",
      invalidTitle: "Це посилання на тренування некоректне",
      invalidCopy: "Попроси відправника створити й надіслати посилання ще раз.",
      home: "Відкрити сайт GymApp",
      previewTitle: "Перегляд тренування",
      exercises: "Вправи",
      sets: "Підходи",
      volume: "Обсяг",
      actionTitle: "Відкрити у GymApp",
      android: "Відкрити Android-застосунок",
      ios: "Відкрити iPhone-застосунок",
      googlePlay: "Завантажити GymApp у Google Play",
      downloads: "Завантаження GymApp",
      privacy: "Посилання містить лише вправи, вагу й повтори. Нічого не потрапить в історію без твого підтвердження.",
      set: "Підхід",
      kg: "кг"
    }),
    ru: Object.freeze({
      title: "Общая тренировка GymApp",
      brand: "План тренировки",
      heading: "Выберите, где открыть этот план",
      subtitle: "Проверьте упражнения, затем откройте редактируемую копию в GymApp.",
      invalidTitle: "Эта ссылка на тренировку некорректна",
      invalidCopy: "Попросите отправителя создать и отправить ссылку ещё раз.",
      home: "Открыть сайт GymApp",
      previewTitle: "Просмотр тренировки",
      exercises: "Упражнения",
      sets: "Подходы",
      volume: "Объём",
      actionTitle: "Открыть в GymApp",
      android: "Открыть Android-приложение",
      ios: "Открыть приложение на iPhone",
      googlePlay: "Скачать GymApp в Google Play",
      downloads: "Загрузки GymApp",
      privacy: "Ссылка содержит только упражнения, веса и повторы. Ничего не попадёт в историю без вашего подтверждения.",
      set: "Подход",
      kg: "кг"
    })
  });

  function fail(message) {
    throw new TypeError(message);
  }

  function languageFor(navigatorLike) {
    const language = String(navigatorLike?.language || "").toLowerCase();
    if (language.startsWith("uk")) return "uk";
    if (language.startsWith("ru")) return "ru";
    return "en";
  }

  function destinations(encoded) {
    if (typeof encoded !== "string" || !/^[A-Za-z0-9_-]+$/.test(encoded) ||
        encoded.length > codec.LIMITS.encodedLength) {
      fail("Shared workout encoding is invalid.");
    }
    const hash = `workout=${encoded}`;
    return Object.freeze({
      android: `${ANDROID_SCHEME}://workout/#${hash}`,
      ios: `${IOS_SCHEME}://workout/#${hash}`,
      googlePlay: GOOGLE_PLAY_URL,
      downloads: CANONICAL_SITE
    });
  }

  function parse(rawUrl) {
    if (!codec?.fromHash || !codec?.encode) fail("Shared workout codec is unavailable.");
    const url = new URL(rawUrl);
    const canonicalOrigin = new URL(CANONICAL_SITE).origin;
    const isCanonicalUrl = url.origin === canonicalOrigin &&
      url.protocol === "https:" && url.pathname === CANONICAL_WORKOUT_PATH;
    const isLoopbackPreview = (url.protocol === "http:" || url.protocol === "https:") &&
      ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname) &&
      url.pathname === CANONICAL_WORKOUT_PATH;
    if ((!isCanonicalUrl && !isLoopbackPreview) || url.username || url.password || url.search) {
      fail("Shared workout URL is invalid.");
    }
    const hash = new URLSearchParams(url.hash.replace(/^#/, ""));
    const keys = [...hash.keys()];
    if (keys.length !== 1 || keys[0] !== codec.HASH_KEY || hash.getAll(codec.HASH_KEY).length !== 1 ||
        keys.some(key => CREDENTIAL_KEYS.has(key.toLowerCase()) || key.toLowerCase().includes("token"))) {
      fail("Shared workout URL is invalid.");
    }
    const plan = codec.fromHash(url.hash);
    if (!plan) fail("Shared workout is missing.");
    const encoded = codec.encode(plan);
    const setCount = plan.exercises.reduce((sum, exercise) => sum + exercise.sets.length, 0);
    const volume = plan.exercises.reduce((sum, exercise) => sum +
      exercise.sets.reduce((setSum, set) => setSum + set.weight * set.reps, 0), 0);
    return Object.freeze({
      plan,
      encoded,
      links: destinations(encoded),
      summary: Object.freeze({ exerciseCount: plan.exercises.length, setCount, volume })
    });
  }

  function setText(document, id, value) {
    const node = document.getElementById(id);
    if (node) node.textContent = value;
  }

  function resetView(document) {
    for (const id of ["invalid-panel", "preview-panel", "action-panel"]) {
      document.getElementById(id)?.setAttribute("hidden", "");
    }
    document.getElementById("exercise-list")?.replaceChildren();
    setText(document, "exercise-count", "0");
    setText(document, "set-count", "0");
    setText(document, "volume-count", "0");
    for (const id of ["open-android", "open-ios"]) {
      const link = document.getElementById(id);
      if (!link) continue;
      link.removeAttribute("href");
      link.classList.remove("recommended");
    }
  }

  function renderPreview(document, result, copy, locale) {
    const list = document.getElementById("exercise-list");
    if (!list) return;
    list.replaceChildren();
    const number = new Intl.NumberFormat(locale, { maximumFractionDigits: 2 });
    result.plan.exercises.forEach((exercise, exerciseIndex) => {
      const article = document.createElement("article");
      article.className = "exercise-card";
      const heading = document.createElement("div");
      heading.className = "exercise-heading";
      const index = document.createElement("span");
      index.textContent = String(exerciseIndex + 1);
      const name = document.createElement("h3");
      name.textContent = exercise.name;
      heading.append(index, name);
      const sets = document.createElement("div");
      sets.className = "set-list";
      exercise.sets.forEach((set, setIndex) => {
        const row = document.createElement("div");
        const label = document.createElement("span");
        label.textContent = `${copy.set} ${setIndex + 1}`;
        const value = document.createElement("strong");
        value.textContent = `${number.format(set.weight)} ${copy.kg} × ${set.reps}`;
        row.append(label, value);
        sets.append(row);
      });
      article.append(heading, sets);
      list.append(article);
    });
  }

  function mount(document, rawUrl, navigatorLike = {}) {
    resetView(document);
    const language = languageFor(navigatorLike);
    const copy = COPY[language];
    const locale = language === "uk" ? "uk-UA" : language === "ru" ? "ru-RU" : "en-US";
    document.documentElement.lang = language;
    document.title = copy.title;
    const text = {
      "brand-caption": copy.brand, "share-title": copy.heading,
      "share-subtitle": copy.subtitle, "invalid-title": copy.invalidTitle,
      "invalid-copy": copy.invalidCopy, "invalid-home": copy.home,
      "preview-title": copy.previewTitle, "exercise-label": copy.exercises,
      "set-label": copy.sets, "volume-label": copy.volume,
      "action-title": copy.actionTitle,
      "privacy-copy": copy.privacy
    };
    Object.entries(text).forEach(([id, value]) => setText(document, id, value));
    const androidLabel = document.querySelector("#open-android strong");
    const iosLabel = document.querySelector("#open-ios strong");
    if (androidLabel) androidLabel.textContent = copy.android;
    if (iosLabel) iosLabel.textContent = copy.ios;
    setText(document, "get-android", copy.googlePlay);
    setText(document, "downloads-home", copy.downloads);

    try {
      const result = parse(rawUrl);
      const formatter = new Intl.NumberFormat(locale, { maximumFractionDigits: 1 });
      setText(document, "exercise-count", result.summary.exerciseCount);
      setText(document, "set-count", result.summary.setCount);
      setText(document, "volume-count", formatter.format(result.summary.volume));
      const android = document.getElementById("open-android");
      const ios = document.getElementById("open-ios");
      if (android) android.href = result.links.android;
      if (ios) ios.href = result.links.ios;
      renderPreview(document, result, copy, locale);
      document.getElementById("preview-panel")?.removeAttribute("hidden");
      document.getElementById("action-panel")?.removeAttribute("hidden");
      const ua = String(navigatorLike?.userAgent || "").toLowerCase();
      if (ua.includes("android")) android?.classList.add("recommended");
      if (/iphone|ipad|ipod/.test(ua)) ios?.classList.add("recommended");
      return result;
    } catch {
      document.getElementById("invalid-panel")?.removeAttribute("hidden");
      return null;
    }
  }

  return Object.freeze({
    CANONICAL_SITE,
    CANONICAL_WORKOUT_PATH,
    ANDROID_SCHEME,
    IOS_SCHEME,
    GOOGLE_PLAY_URL,
    COPY,
    languageFor,
    destinations,
    parse,
    resetView,
    mount
  });
});
