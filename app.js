"use strict";

const STORAGE_KEY = "gym-pwa-state-v2";
const LEGACY_KEY = "gym-pwa-state-v1";
const app = document.querySelector("#app");

const icons = {
  add: "M12 5v14M5 12h14",
  auto: "M12 3l1.7 5.3L19 10l-5.3 1.7L12 17l-1.7-5.3L5 10l5.3-1.7zM19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z",
  back: "M15 18l-6-6 6-6",
  chart: "M4 19V5M8 17v-5M13 17V8M18 17v-9M3 19h18",
  check: "M20 6 9 17l-5-5",
  close: "M18 6 6 18M6 6l12 12",
  copy: "M8 8h11v11H8zM5 16H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h11a1 1 0 0 1 1 1v1",
  delete: "M3 6h18M8 6V4h8v2M6 6l1 15h10l1-15",
  download: "M12 3v12m0 0 5-5m-5 5-5-5M4 21h16",
  edit: "M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z",
  fire: "M12 22c4 0 7-3 7-7 0-4-3-7-5-10 0 4-2 5-4 7-1-2-1-4 0-6-3 2-5 5-5 9 0 4 3 6 7 6z",
  home: "M3 11l9-8 9 8v10H5V11",
  lang: "M4 5h16M9 3v2m4 0c-1 5-4 8-8 10m3-7c2 3 5 6 9 7m-4 4 3-7 3 7m-5-2h4",
  list: "M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01",
  medal: "M8 21l4-7 4 7M8 3h8l2 5-6 6-6-6z",
  save: "M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2zM7 21v-8h10v8M7 3v5h8",
  timer: "M10 2h4M12 14l4-4M5 5l2 2m10-2-2 2M12 22a8 8 0 1 0 0-16 8 8 0 0 0 0 16z",
  trophy: "M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0zM5 5H3v2a4 4 0 0 0 4 4M19 5h2v2a4 4 0 0 1-4 4",
  upload: "M12 21V9m0 0 5 5m-5-5-5 5M4 3h16",
  weight: "M6 7h12l2 14H4zM9 7a3 3 0 0 1 6 0"
};

const text = {
  en: {
    workouts: "Workouts", missions: "Missions", exercises: "Exercises", progress: "Progress", ranks: "Rank Titles",
    addWorkout: "Add Workout", finishWorkout: "Finish Workout", saveWorkout: "Save Workout", repeatLast: "Repeat Last Workout",
    copyWorkout: "Copy Previous Workout", overview: "Overview", workoutList: "Workout list", current: "Current",
    soloProgress: "Solo Progress", monthlySnapshot: "Monthly Snapshot", heatmap: "Activity Heatmap", muscleMap: "Muscle Map",
    recommendations: "Recommendations", achievements: "Achievements", noWorkouts: "No workouts in this month.",
    note: "Note", trainingProfile: "Training Profile", smartCoach: "Smart Coach", generateSmart: "Generate Smart Workout",
    syncWatch: "Sync Plan to Watch", addExercise: "Add Exercise", addSet: "Add Set", copyLast: "Copy Last Set",
    copyPlus: "Copy Last +2.5 kg", useLast: "Use Last Weight", applySmart: "Apply Smart Plan", templatePicker: "Copy a previous workout",
    exerciseName: "Exercise name", backup: "Backup and diagnostics", exportJson: "Export JSON", importJson: "Import JSON",
    diagnostics: "Send diagnostics / DB snapshot", sharePdf: "Share PDF report", rename: "Rename Exercise", history: "History",
    workoutComplete: "Workout complete", impact: "Workout impact", personalRecords: "Personal records", levelProgress: "Level progress",
    momentum: "Momentum", daily: "Daily Missions", weekly: "Weekly Missions", monthly: "Monthly Missions", viewRanks: "View ranks"
  },
  uk: {
    workouts: "Тренування", missions: "Місії", exercises: "Вправи", progress: "Прогрес", ranks: "Ранги",
    addWorkout: "Додати тренування", finishWorkout: "Завершити", saveWorkout: "Зберегти тренування", repeatLast: "Повторити останнє",
    copyWorkout: "Скопіювати день", overview: "Огляд", workoutList: "Список тренувань", current: "Поточний",
    soloProgress: "Соло прогрес", monthlySnapshot: "Підсумок місяця", heatmap: "Карта активності", muscleMap: "Карта м'язів",
    recommendations: "Рекомендації", achievements: "Досягнення", noWorkouts: "Немає тренувань у цьому місяці.",
    note: "Нотатка", trainingProfile: "Профіль тренувань", smartCoach: "Розумний коуч", generateSmart: "Згенерувати тренування",
    syncWatch: "Синхронізувати з годинником", addExercise: "Додати вправу", addSet: "Додати підхід", copyLast: "Копіювати підхід",
    copyPlus: "Копіювати +2.5 кг", useLast: "Остання вага", applySmart: "Застосувати план", templatePicker: "Скопіювати попереднє",
    exerciseName: "Назва вправи", backup: "Бекап і діагностика", exportJson: "Експорт JSON", importJson: "Імпорт JSON",
    diagnostics: "Діагностика / знімок БД", sharePdf: "PDF звіт", rename: "Перейменувати", history: "Історія",
    workoutComplete: "Тренування завершено", impact: "Вплив тренування", personalRecords: "Особисті рекорди", levelProgress: "Прогрес рівня",
    momentum: "Імпульс", daily: "Щоденні місії", weekly: "Тижневі місії", monthly: "Місячні місії", viewRanks: "Дивитись ранги"
  }
};

const muscles = [
  ["chest", "Chest"], ["shoulders", "Shoulders"], ["biceps", "Biceps"], ["triceps", "Triceps"],
  ["forearms", "Forearms"], ["abs", "Abs"], ["obliques", "Obliques"], ["upperBack", "Upper Back"],
  ["lats", "Lats"], ["lowerBack", "Lower Back"], ["glutes", "Glutes"], ["quads", "Quads"],
  ["hamstrings", "Hamstrings"], ["adductors", "Adductors"], ["calves", "Calves"]
];

const defaultMappings = {
  "bench press": ["chest", "triceps", "shoulders"], "incline dumbbell press": ["chest", "shoulders", "triceps"],
  "pull up": ["lats", "biceps", "upperBack"], "lat pulldown": ["lats", "biceps"], "barbell row": ["upperBack", "lats", "biceps"],
  "squat": ["quads", "glutes", "adductors"], "leg press": ["quads", "glutes"], "romanian deadlift": ["hamstrings", "glutes", "lowerBack"],
  "deadlift": ["hamstrings", "glutes", "lowerBack", "upperBack"], "shoulder press": ["shoulders", "triceps"],
  "lateral raise": ["shoulders"], "biceps curl": ["biceps", "forearms"], "triceps pushdown": ["triceps"],
  "calf raise": ["calves"], "plank": ["abs", "obliques"]
};

const defaultExercises = Object.keys(defaultMappings).map(name => titleCase(name));

const rankDefinitions = [
  ["rookie", 1, "Rookie", "Новачок"], ["starter", 3, "Starter", "Стартовий"],
  ["steady", 5, "Steady", "Стабільний"], ["driven", 7, "Driven", "Вмотивований"],
  ["striker", 9, "Striker", "Ударний"], ["ironclad", 11, "Ironclad", "Незламний"],
  ["vanguard", 13, "Vanguard", "Авангард"], ["challenger", 15, "Challenger", "Претендент"],
  ["dominator", 17, "Dominator", "Домінатор"], ["elite", 19, "Elite", "Еліта"],
  ["titan", 21, "Titan", "Титан"], ["colossus", 23, "Colossus", "Колос"],
  ["warborn", 25, "Warborn", "Воїн"], ["apex", 27, "Apex", "Апекс"],
  ["mythic", 29, "Mythic", "Міфічний"], ["legend", 31, "Legend", "Легенда"],
  ["eternal", 33, "Eternal", "Вічний"], ["immortal", 35, "Immortal", "Безсмертний"],
  ["paragon", 37, "Paragon", "Парагон"], ["overlord", 39, "Overlord", "Володар"],
  ["ascendant", 41, "Ascendant", "Вознесений"], ["conqueror", 43, "Conqueror", "Завойовник"],
  ["sovereign", 45, "Sovereign", "Суверен"], ["prime", 47, "Prime", "Прайм"],
  ["omni", 49, "Omni", "Омні"], ["galactic", 51, "Galactic", "Галактичний"],
  ["nova", 53, "Nova", "Нова"], ["singularity", 55, "Singularity", "Сингулярність"],
  ["omega", 57, "Omega", "Омега"], ["transcendent", 60, "Transcendent", "Трансцендентний"],
  ["celestial", 64, "Celestial", "Небесний"], ["empyrean", 68, "Empyrean", "Емпірей"],
  ["infinite", 72, "Infinite", "Нескінченний"], ["beyond", 76, "Beyond", "Понадмежний"],
  ["cosmic-warlord", 80, "Cosmic Warlord", "Космічний воєвода"]
].map(([id, level, titleEn, titleUk]) => ({ id, level, titleEn, titleUk }));

let state = loadState();
let nav = [{ name: "workouts" }];
let modal = null;
let toastTimer = null;
let selectedMonthOffset = 0;
let overviewMode = "overview";
let musclePeriod = "month";
let selectedMuscle = null;
let timerInterval = null;

function t(key) {
  return (text[state.language] || text.en)[key] || text.en[key] || key;
}

function tx(en, uk) {
  return state.language === "uk" ? uk : en;
}

function n(count, enOne, enMany, ukOne, ukFew, ukMany) {
  if (state.language !== "uk") return `${count} ${count === 1 ? enOne : enMany}`;
  const mod10 = count % 10;
  const mod100 = count % 100;
  const word = mod10 === 1 && mod100 !== 11 ? ukOne : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) ? ukFew : ukMany;
  return `${count} ${word}`;
}

function loadState() {
  const fallback = {
    language: "en",
    exercises: defaultExercises.map((name, index) => ({ id: index + 1, name })),
    sessions: [],
    mappings: { ...defaultMappings },
    profile: { split: "Push Pull Legs", days: 4, goal: "Balanced", calories: "Maintenance" }
  };
  try {
    const raw = localStorage.getItem(STORAGE_KEY) || localStorage.getItem(LEGACY_KEY);
    if (!raw) return fallback;
    const parsed = JSON.parse(raw);
    return {
      ...fallback,
      ...parsed,
      exercises: Array.isArray(parsed.exercises) ? parsed.exercises : fallback.exercises,
      sessions: Array.isArray(parsed.sessions) ? normalizeSessions(parsed.sessions) : [],
      mappings: { ...fallback.mappings, ...(parsed.mappings || {}) },
      profile: { ...fallback.profile, ...(parsed.profile || {}) }
    };
  } catch {
    return fallback;
  }
}

function normalizeSessions(sessions) {
  return sessions.map(session => ({
    id: Number(session.id || uid()),
    startedAt: Number(session.startedAt || session.date || Date.now()),
    note: session.note || "",
    sets: (session.sets || []).flatMap((set, index) => {
      if (set.exerciseName) return [{ id: Number(set.id || uid()), exerciseName: set.exerciseName, weight: Number(set.weight || 0), reps: Number(set.reps || 0), orderIndex: set.orderIndex ?? index }];
      return [];
    })
  }));
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function uid() {
  return Date.now() + Math.floor(Math.random() * 100000);
}

function route() {
  return nav[nav.length - 1];
}

function push(name, params = {}) {
  nav.push({ name, ...params });
  modal = null;
  render();
}

function goRoot(name) {
  nav = [{ name }];
  modal = null;
  render();
}

function back() {
  if (modal) modal = null;
  else if (nav.length > 1) nav.pop();
  render();
}

function svg(name, cls = "") {
  return `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[name] || ""}"></path></svg>`;
}

function fmtDate(value, options = { month: "short", day: "numeric", year: "numeric" }) {
  return new Intl.DateTimeFormat(state.language === "uk" ? "uk-UA" : "en-US", options).format(new Date(value));
}

function monthDate() {
  const d = new Date();
  d.setDate(1);
  d.setMonth(d.getMonth() + selectedMonthOffset);
  return d;
}

function monthKey(value) {
  const d = new Date(value);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function selectedMonthKey() {
  return monthKey(monthDate().getTime());
}

function selectedMonthSessions() {
  const key = selectedMonthKey();
  return state.sessions.filter(session => monthKey(session.startedAt) === key);
}

function allSets(sessions = state.sessions) {
  return sessions.flatMap(session => session.sets.map(set => ({ ...set, session })));
}

function totalVolume(sessions = state.sessions) {
  return allSets(sessions).reduce((sum, set) => sum + Number(set.weight || 0) * Number(set.reps || 0), 0);
}

function groupedExercises(sets = allSets()) {
  const map = new Map();
  sets.forEach(set => {
    const item = map.get(set.exerciseName) || { name: set.exerciseName, sets: 0, reps: 0, volume: 0, best: 0, sessions: new Set() };
    item.sets += 1;
    item.reps += Number(set.reps || 0);
    item.volume += Number(set.weight || 0) * Number(set.reps || 0);
    item.best = Math.max(item.best, Number(set.weight || 0));
    item.sessions.add(set.session.id);
    map.set(set.exerciseName, item);
  });
  return [...map.values()].sort((a, b) => b.volume - a.volume);
}

function sessionSummary(session) {
  return {
    exercises: new Set(session.sets.map(set => set.exerciseName)).size,
    sets: session.sets.length,
    volume: totalVolume([session])
  };
}

function xpForSessions(sessions) {
  return sessions.reduce((sum, session) => sum + sessionXp(session), 0);
}

function totalXp() {
  return xpForSessions(state.sessions) + completedMissions().reduce((sum, mission) => sum + mission.reward, 0);
}

function levelFromXp(value = totalXp()) {
  return levelProgress(value).level;
}

function rankTitle(value = totalXp()) {
  const level = levelFromXp(value);
  const rank = rankDefinitions.filter(item => level >= item.level).at(-1) || rankDefinitions[0];
  return state.language === "uk" ? rank.titleUk : rank.titleEn;
}

function rankLadder() {
  const xp = totalXp();
  const current = rankDefinitions.filter(item => xp >= cumulativeXpForLevel(item.level)).at(-1)?.id;
  return rankDefinitions.map((rank, index) => {
    const requiredXp = cumulativeXpForLevel(rank.level);
    const previousXp = index === 0 ? 0 : cumulativeXpForLevel(rankDefinitions[index - 1].level);
    const segment = Math.max(1, requiredXp - previousXp);
    return {
      id: rank.id,
      title: state.language === "uk" ? rank.titleUk : rank.titleEn,
      level: rank.level,
      xp: requiredXp,
      xpRemaining: Math.max(0, requiredXp - xp),
      progressFraction: Math.min(1, Math.max(0, (xp - previousXp) / segment)),
      isCurrent: rank.id === current,
      isUnlocked: xp >= requiredXp
    };
  });
}

function sessionXp(session) {
  const summary = sessionSummary(session);
  return 90 + summary.exercises * 16 + summary.sets * 8 + Math.round(summary.volume / 80);
}

function xpRequirementForLevel(level) {
  const stage = Math.max(0, level - 1);
  return 200 + stage * 85 + stage * stage * 8;
}

function cumulativeXpForLevel(level) {
  let total = 0;
  for (let current = 1; current < level; current++) total += xpRequirementForLevel(current);
  return total;
}

function levelProgress(value = totalXp()) {
  let level = 1;
  let remaining = value;
  let next = xpRequirementForLevel(level);
  while (remaining >= next) {
    remaining -= next;
    level += 1;
    next = xpRequirementForLevel(level);
  }
  return { level, currentLevelXp: remaining, xpForNextLevel: next, progressFraction: Math.min(1, remaining / next) };
}

function streakDays() {
  const days = [...new Set(state.sessions.map(session => new Date(session.startedAt).setHours(0, 0, 0, 0)))].sort((a, b) => b - a);
  if (!days.length) return 0;
  let expected = new Date().setHours(0, 0, 0, 0);
  if (days[0] < expected) expected -= 86400000;
  let streak = 0;
  for (const day of days) {
    if (day === expected) {
      streak++;
      expected -= 86400000;
    }
  }
  return streak;
}

function weeklyStreak() {
  return Math.ceil(streakDays() / 7);
}

function render() {
  const current = route();
  app.innerHTML = `
    <header class="topbar">
      ${nav.length > 1 ? `<button class="icon-button" data-action="back" aria-label="Back">${svg("back")}</button>` : `<button class="icon-button" data-action="backup" aria-label="Backup">${svg("download")}</button>`}
      <h1>${titleForRoute(current)}</h1>
      <button class="icon-button" data-action="language" aria-label="Language">${svg("lang")}</button>
    </header>
    <main class="screen">${screenMarkup(current)}</main>
    ${isRootRoute(current.name) ? bottomNav() : ""}
    ${modal ? modalMarkup() : ""}
    <div id="toast" class="toast hidden"></div>
  `;
  bindEvents();
  startTimerTicker();
}

function isRootRoute(name) {
  return ["workouts", "missions", "exercises", "progress"].includes(name);
}

function titleForRoute(current) {
  return {
    workouts: t("workouts"), missions: t("missions"), exercises: t("exercises"), progress: t("progress"),
    add: t("addWorkout"), detail: "Workout Details", summary: "Workout Summary", ranks: t("ranks")
  }[current.name] || "Gym Workout Tracker";
}

function bottomNav() {
  const tabs = [["workouts", "list", t("workouts")], ["missions", "medal", t("missions")], ["exercises", "weight", t("exercises")], ["progress", "chart", t("progress")]];
  return `<nav class="bottom-nav">${tabs.map(([id, icon, label]) => `
    <button class="tab-button ${route().name === id ? "active" : ""}" data-route="${id}">${svg(icon)}<span>${label}</span></button>`).join("")}</nav>`;
}

function screenMarkup(current) {
  if (current.name === "missions") return missionsScreen();
  if (current.name === "exercises") return exercisesScreen();
  if (current.name === "progress") return progressScreen();
  if (current.name === "add") return addWorkoutScreen();
  if (current.name === "detail") return detailScreen(current.id);
  if (current.name === "summary") return summaryScreen(current.id);
  if (current.name === "ranks") return ranksScreen();
  return workoutsScreen();
}

function monthSwitcher() {
  return `<section class="month-switcher panel compact">
    <button class="icon-button" data-action="month-prev" aria-label="Previous month">${svg("back")}</button>
    <strong>${fmtDate(monthDate().getTime(), { month: "long", year: "numeric" })}</strong>
    <button class="button ghost" data-action="month-current">${t("current")}</button>
    <button class="icon-button rotate-180" data-action="month-next" aria-label="Next month">${svg("back")}</button>
  </section>`;
}

function workoutsScreen() {
  const sessions = [...selectedMonthSessions()].sort((a, b) => b.startedAt - a.startedAt);
  const savedSessions = n(sessions.length, "saved session", "saved sessions", "збережене тренування", "збережені тренування", "збережених тренувань");
  return `
    ${monthSwitcher()}
    <section class="segmented panel compact">
      <button class="${overviewMode === "overview" ? "selected" : ""}" data-action="overview-mode" data-mode="overview"><strong>${t("overview")}</strong><span>${tx("Progress, goals, achievements", "Прогрес, цілі, досягнення")}</span></button>
      <button class="${overviewMode === "list" ? "selected" : ""}" data-action="overview-mode" data-mode="list"><strong>${t("workoutList")}</strong><span>${savedSessions}</span></button>
    </section>
    ${overviewMode === "overview" ? overviewCards(sessions) : ""}
    <div class="section-title"><div><h2>${t("workoutList")}</h2><p>${sessions.length ? savedSessions : tx("New sessions will appear here as soon as you log them.", "Нові тренування з'являться тут одразу після збереження.")}</p></div><button class="button" data-action="open-add">${svg("add", "small-icon")}${t("addWorkout")}</button></div>
    <section class="workout-list">${sessions.length ? sessions.map(workoutItem).join("") : `<div class="empty">${t("noWorkouts")}</div>`}</section>
    <button class="fab" data-action="open-add">${svg("add", "small-icon")}${t("addWorkout")}</button>
  `;
}

function overviewCards(sessions) {
  return `
    ${soloProgressHero()}
    ${dashboardCard(sessions)}
    ${activityHeatmapCard()}
    ${muscleMapCard()}
    ${recommendationsCard()}
    ${achievementsCard()}
  `;
}

function soloProgressHero() {
  const xp = totalXp();
  const progress = levelProgress(xp);
  const level = progress.level;
  const next = rankDefinitions.find(rank => level < rank.level);
  const nextTitle = next ? (state.language === "uk" ? next.titleUk : next.titleEn) : rankTitle(xp);
  return `<section class="hero-panel">
    <div class="eyebrow">${t("soloProgress")}</div>
    <div class="hero-split"><div><span class="pill hero-pill">${tx("LEVEL", "РІВЕНЬ")} ${level}</span><h2>${rankTitle(xp)}</h2><p>${progress.currentLevelXp} / ${progress.xpForNextLevel} XP ${tx("to next level", "до наступного рівня")}</p></div><div class="hero-stat"><span>${tx("TOTAL XP", "УСЬОГО XP")}</span><strong>${xp}</strong><small>${tx("earned", "зароблено")}</small></div></div>
    <div class="progress"><span style="width:${progress.progressFraction * 100}%"></span></div>
    <div class="metric-grid three"><div><span>${tx("Month XP", "XP за місяць")}</span><strong>${xpForSessions(selectedMonthSessions())} XP</strong></div><div><span>${tx("Next title", "Наступний ранг")}</span><strong>${nextTitle}</strong></div><div><span>${tx("Week streak", "Серія тижнів")}</span><strong>${weeklyStreak()} ${tx("wk", "тж")}</strong></div></div>
  </section>`;
}

function dashboardCard(sessions) {
  const sets = allSets(sessions);
  const avg = sets.length ? totalVolume(sessions) / sets.length : 0;
  return `<section class="hero-panel">
    <h2>${t("monthlySnapshot")}</h2><p>${tx("Track consistency, output and intensity at a glance.", "Відстежуй стабільність, обсяг і інтенсивність одним поглядом.")}</p>
    <div class="metric-grid"><div><span>${tx("Workouts", "Тренування")}</span><strong>${sessions.length}</strong></div><div><span>${tx("Streak", "Серія")}</span><strong>${weeklyStreak()} ${tx("wk", "тж")}</strong></div><div><span>${tx("Total Volume", "Загальний обсяг")}</span><strong>${Math.round(totalVolume(sessions))}</strong></div><div><span>${tx("Avg / Set", "Сер. / підхід")}</span><strong>${avg.toFixed(1)}</strong></div></div>
  </section>`;
}

function workoutItem(session) {
  const summary = sessionSummary(session);
  return `<article class="workout-item clickable" data-action="open-detail" data-id="${session.id}">
    <div class="workout-head"><div><h3 class="workout-title">${tx("Workout", "Тренування")} ${fmtDate(session.startedAt)}</h3><span class="muted">${session.note ? `${t("note")}: ${escapeHtml(session.note)}` : tx("No note", "Без нотатки")}</span></div><span class="chip">${tx("Sets", "Підходи")}: ${summary.sets}</span></div>
    <div class="chip-row"><span class="chip">${tx("Exercises", "Вправи")}: ${summary.exercises}</span><span class="chip">${tx("Volume", "Обсяг")}: ${Math.round(summary.volume)}</span>${[...new Set(session.sets.map(set => set.exerciseName))].slice(0, 5).map(name => `<span class="chip">${escapeHtml(name)}</span>`).join("")}</div>
  </article>`;
}

function activityHeatmapCard() {
  const d = monthDate();
  const days = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  const first = new Date(d.getFullYear(), d.getMonth(), 1).getDay();
  const blanks = (first + 6) % 7;
  const cells = Array.from({ length: blanks }, () => null).concat(Array.from({ length: days }, (_, i) => i + 1));
  while (cells.length % 7) cells.push(null);
  const monthSessions = selectedMonthSessions();
  const byDay = new Map();
  monthSessions.forEach(session => {
    const day = new Date(session.startedAt).getDate();
    byDay.set(day, (byDay.get(day) || 0) + totalVolume([session]));
  });
  const max = Math.max(1, ...byDay.values());
  return `<section class="panel"><div class="section-title"><div><h2>${t("heatmap")}</h2><p>${fmtDate(d.getTime(), { month: "long", year: "numeric" })}</p></div><span class="pill">${n(byDay.size, "active day", "active days", "активний день", "активні дні", "активних днів")}</span></div>
    <div class="metric-grid"><div><span>${tx("Sessions", "Сесії")}</span><strong>${monthSessions.length}</strong></div><div><span>${tx("Volume", "Обсяг")}</span><strong>${Math.round(totalVolume(monthSessions))}</strong></div></div>
    <div class="heatmap-grid">${cells.map(day => `<button class="heat-cell ${day ? "" : "outside"}" style="${day ? `--i:${(byDay.get(day) || 0) / max}` : ""}" title="${day || ""}">${day || ""}</button>`).join("")}</div>
    <div class="legend"><span>${tx("Less", "Менше")}</span><i></i><i></i><i></i><i></i><span>${tx("More", "Більше")}</span></div>
  </section>`;
}

function muscleMapCard() {
  const data = muscleStats();
  const max = Math.max(1, ...data.map(item => item.load));
  const top = data.filter(item => item.load > 0).sort((a, b) => b.load - a.load);
  const selected = selectedMuscle ? top.find(item => item.id === selectedMuscle) : null;
  const unmapped = groupedExercises().filter(ex => !mappingFor(ex.name).length);
  return `<section class="panel">
    <div class="section-title"><div><h2>${t("muscleMap")}</h2><p>${tx("Colors show which muscle groups carried the most load.", "Кольори показують, які групи м'язів отримали найбільше навантаження.")}</p></div><span class="pill">${musclePeriodLabel(musclePeriod)}</span></div>
    <div class="period-tabs">${["all", "month", "week"].map(period => `<button class="${musclePeriod === period ? "selected" : ""}" data-action="muscle-period" data-period="${period}">${musclePeriodLabel(period)}</button>`).join("")}</div>
    <div class="metric-grid three"><div><span>${tx("Sets", "Підходи")}</span><strong>${allSets(periodSessions()).length}</strong></div><div><span>${tx("Load", "Навантаження")}</span><strong>${Math.round(totalVolume(periodSessions()))}</strong></div><div><span>${tx("Mapped", "Зіставлено")}</span><strong>${mappedCount()}/${state.exercises.length}</strong></div></div>
    ${sourceBodyMapSvg(data, max)}
    ${selected ? `<div class="subpanel"><h3>${selected.label} ${tx("loaded by", "навантажено через")}</h3>${selected.exercises.map(ex => `<div class="row-line"><span>${escapeHtml(ex.name)}</span><button class="button ghost mini" data-action="map-exercise" data-name="${escapeAttr(ex.name)}">${tx("Map", "Карта")}</button></div>`).join("")}</div>` : ""}
    ${unmapped.length ? `<div class="subpanel"><h3>${tx("Unmapped / new exercises", "Нові вправи без мапінгу")}</h3>${unmapped.map(ex => `<div class="row-line"><span>${escapeHtml(ex.name)} - ${n(ex.sets, "set", "sets", "підхід", "підходи", "підходів")}</span><button class="button secondary mini" data-action="map-exercise" data-name="${escapeAttr(ex.name)}">${tx("Map", "Мапити")}</button></div>`).join("")}</div>` : ""}
    <h3>${tx("Top muscle groups", "Топ груп м'язів")}</h3><div class="bars">${top.length ? top.slice(0, 8).map(item => barRow(item.label, item.load, max, `${n(item.sets, "set", "sets", "підхід", "підходи", "підходів")} - ${n(item.sessions.size, "session", "sessions", "сесія", "сесії", "сесій")}`)).join("") : `<div class="empty">${tx("Log sets to light up the body map.", "Запиши підходи, щоб підсвітити карту тіла.")}</div>`}</div>
  </section>`;
}

function musclePeriodLabel(period) {
  return {
    all: tx("All time", "Весь час"),
    month: tx("Month", "Місяць"),
    week: tx("Week", "Тиждень")
  }[period] || period;
}

function periodSessions() {
  if (musclePeriod === "all") return state.sessions;
  const now = Date.now();
  if (musclePeriod === "week") return state.sessions.filter(s => now - s.startedAt <= 7 * 86400000);
  return selectedMonthSessions();
}

function mappedCount() {
  return state.exercises.filter(ex => mappingFor(ex.name).length).length;
}

function mappingFor(name) {
  const normalized = normalizeExerciseName(name);
  const manual = state.mappings[normalized];
  if (manual?.length) return manual;
  return inferMuscleContributions(name).map(item => item.muscleId);
}

function contributionFor(name) {
  const normalized = normalizeExerciseName(name);
  const manual = state.mappings[normalized];
  if (manual?.length) return manual.map(muscleId => ({ muscleId, weight: 1 }));
  return inferMuscleContributions(name);
}

function normalizeExerciseName(name) {
  return String(name || "").toLowerCase().replace(/[ʼ’]/g, "'").replace(/\s+/g, " ").trim();
}

function inferMuscleContributions(name) {
  const normalized = normalizeExerciseName(name);
  const inferred = new Map();
  const add = (muscleId, weight) => inferred.set(muscleId, Math.max(inferred.get(muscleId) || 0, clamp(weight, 0, 1)));
  const has = (...tokens) => tokens.some(token => normalized.includes(token));
  (defaultMappings[normalized] || []).forEach(id => add(id, 1));
  if (has("біцепс", "бицепс", "bicep", "curl", "сгибание рук", "згинання рук")) { add("biceps", 1); add("forearms", 0.25); }
  if (has("трицепс", "tricep", "француз", "розгинання рук", "разгибание рук", "pushdown")) add("triceps", 1);
  if (has("жим ног", "жим ногами", "leg press")) { add("quads", 1); add("glutes", 0.55); add("hamstrings", 0.35); }
  if (has("жим", "press", "bench") && !has("ног", "leg press")) { add("chest", 0.85); add("triceps", 0.55); add("shoulders", 0.45); }
  if (has("плеч", "дельт", "махи", "розведення", "разведение", "підйом гантелей", "подъем гантелей", "shoulder", "lateral raise", "rear delt", "face pull", "overhead press")) add("shoulders", 1);
  if (has("підтяг", "подтяг", "pull up", "pullup", "pulldown", "тяга верхнього блока", "тяга верхнего блока", "верхній блок", "верхний блок")) { add("lats", 1); add("upperBack", 0.65); add("biceps", 0.55); add("forearms", 0.3); }
  if (has("тяга", "deadlift", "row") && has("румун", "станов", "становая", "deadlift")) { add("hamstrings", 0.9); add("glutes", 0.85); add("lowerBack", 0.75); add("upperBack", 0.3); add("forearms", 0.25); }
  if (has("тяга", "row") && !has("румун", "станов", "становая", "deadlift", "підборід", "подбород")) { add("lats", 0.9); add("upperBack", 0.85); add("biceps", 0.45); add("forearms", 0.25); }
  if (has("прис", "присед", "squat", "випади", "выпады", "lunge")) { add("quads", 1); add("glutes", 0.7); add("hamstrings", 0.45); add("lowerBack", 0.25); }
  if (has("розгинання ніг", "разгибание ног", "leg extension")) add("quads", 1);
  if (has("згинання ніг", "згибання ніг", "сгибание ног", "leg curl")) add("hamstrings", 1);
  if (has("підйом на носки", "підйоми на носки", "подъем на носки", "икры", "calf")) add("calves", 1);
  if (has("прес", "скруч", "планка", "crunch", "sit up", "leg raise", "plank")) add("abs", 1);
  if (has("нахил", "наклон", "сторони", "стороны", "поворот корпус", "rotation", "side bend", "russian twist")) add("obliques", 0.85);
  if (has("гіперекстензі", "гиперэкстенз", "hyperextension")) { add("lowerBack", 1); add("glutes", 0.55); add("hamstrings", 0.45); }
  if (has("сідниц", "ягодиц", "glute", "hip thrust", "місток", "мостик")) { add("glutes", 1); add("hamstrings", 0.35); }
  if (has("зведення ніг", "сведение ног", "adductor")) add("adductors", 1);
  if (has("метелик", "pec deck", "зведення рук", "сведение рук", "fly", "flies")) { add("chest", 1); add("shoulders", 0.25); }
  return [...inferred].filter(([muscleId]) => muscles.some(([id]) => id === muscleId)).map(([muscleId, weight]) => ({ muscleId, weight }));
}

function muscleStats(sessions = periodSessions()) {
  const map = new Map(muscles.map(([id, label]) => [id, { id, label, load: 0, sets: 0, sessions: new Set(), exercises: [] }]));
  allSets(sessions).forEach(set => {
    const contributions = contributionFor(set.exerciseName);
    contributions.forEach(contribution => {
      const item = map.get(contribution.muscleId);
      if (!item) return;
      const trackedLoad = Math.max(0, Number(set.weight || 0)) * Math.max(0, Number(set.reps || 0));
      const load = (trackedLoad > 0 ? trackedLoad : 72 * Math.max(0, Number(set.reps || 0))) + 35;
      item.load += load * contribution.weight;
      item.sets += 1;
      item.sessions.add(set.session.id);
      if (!item.exercises.some(ex => ex.name === set.exerciseName)) item.exercises.push({ name: set.exerciseName });
    });
  });
  return [...map.values()];
}

function sourceBodyMapSvg(data, maxLoad) {
  const byId = new Map(data.map(item => [item.id, item]));
  const front = window.SOURCE_FRONT_MUSCLE_REGIONS || [];
  const back = window.SOURCE_BACK_MUSCLE_REGIONS || [];
  const regionMarkup = [...front, ...back].map(region => {
    const muscleId = muscleIdForSourceRegion(region.id);
    const item = muscleId ? byId.get(muscleId) : null;
    const intensity = item && maxLoad > 0 ? Math.min(1, item.load / maxLoad) : 0;
    const selected = muscleId && selectedMuscle === muscleId;
    return `<path class="body-region ${selected ? "selected" : ""}" d="${escapeAttr(region.pathData)}" fill="${heatColor(intensity)}" data-action="${muscleId ? "select-muscle" : ""}" data-id="${muscleId || ""}"><title>${escapeHtml(region.name)}${item ? ` - ${Math.round(item.load)} ${tx("load", "навантаження")}` : ""}</title></path>`;
  }).join("");
  return `<div class="body-map-svg-wrap">
    <svg class="body-map-svg" viewBox="0 0 72 93" role="img" aria-label="${tx("Muscle load map", "Карта навантаження м'язів")}">
      ${regionMarkup}
    </svg>
    <div class="body-labels"><span>${tx("Front", "Спереду")}</span><span>${tx("Back", "Ззаду")}</span></div>
  </div>`;
}

function muscleIdForSourceRegion(regionId) {
  if (!regionId) return null;
  if (regionId.includes("chest")) return "chest";
  if (regionId.includes("shoulder") || regionId.includes("deltoid")) return "shoulders";
  if (regionId.includes("biceps")) return "biceps";
  if (regionId.includes("triceps")) return "triceps";
  if (regionId.includes("forearm")) return "forearms";
  if (regionId.includes("obliques") || regionId.includes("serratus")) return "obliques";
  if (regionId.includes("abs")) return "abs";
  if (regionId.includes("traps")) return "upperBack";
  if (regionId.includes("lats")) return "lats";
  if (regionId === "spine" || regionId.includes("lower-back")) return "lowerBack";
  if (regionId.includes("gluteus")) return "glutes";
  if (regionId.includes("quads")) return "quads";
  if (regionId.includes("adductors") || regionId.includes("hip-flexor")) return "adductors";
  if (regionId.includes("hamstrings")) return "hamstrings";
  if (regionId.includes("calves") || regionId.includes("tibialis")) return "calves";
  return null;
}

function heatColor(intensity) {
  const value = Math.min(1, Math.max(0, intensity));
  if (value <= 0) return "rgba(180,195,207,0.22)";
  if (value < 0.28) return `rgba(59,130,246,${0.42 + value / 0.28 * 0.58})`;
  if (value < 0.58) return mixHex("#3b82f6", "#8b5cf6", (value - 0.28) / 0.3);
  if (value < 0.86) return mixHex("#8b5cf6", "#e11d48", (value - 0.58) / 0.28);
  return mixHex("#e11d48", "#f59e0b", (value - 0.86) / 0.14);
}

function mixHex(a, b, t) {
  const av = a.match(/\w\w/g).map(x => parseInt(x, 16));
  const bv = b.match(/\w\w/g).map(x => parseInt(x, 16));
  const cv = av.map((v, i) => Math.round(v + (bv[i] - v) * Math.min(1, Math.max(0, t))));
  return `rgb(${cv[0]},${cv[1]},${cv[2]})`;
}

function recommendationsCard() {
  const recs = trainingRecommendations();
  return `<section class="panel highlighted"><h2>${t("recommendations")}</h2><p class="muted">${tx("Based on muscle load and recent training gaps.", "На основі навантаження м'язів і останніх пауз у тренуваннях.")}</p>
    <div class="list-gap">${recs.map(rec => `<div class="subpanel row-line"><div><strong>${rec.title}</strong><p>${rec.supporting}</p></div><span class="pill">${rec.priority}</span></div>`).join("")}</div>
  </section>`;
}

function trainingRecommendations() {
  const stats = muscleStats(state.sessions).sort((a, b) => a.load - b.load);
  const stale = stats.filter(item => item.load > 0).slice(0, 3);
  const last = [...state.sessions].sort((a, b) => b.startedAt - a.startedAt)[0];
  return [
    stale[0] ? { title: `${tx("Bring up", "Підтягни")} ${stale[0].label}`, supporting: tx("This muscle group is behind your current total load.", "Ця група м'язів відстає за поточним загальним навантаженням."), priority: tx("High", "Високий") } : { title: tx("Starter plan", "Стартовий план"), supporting: tx("Add your first workout to unlock smarter recommendations.", "Додай перше тренування, щоб відкрити розумніші рекомендації."), priority: tx("New", "Нове") },
    { title: nextWorkoutType(last), supporting: tx("Suggested from your recent exercise pattern and training profile.", "Підібрано за останнім патерном вправ і профілем тренувань."), priority: tx("Next", "Далі") }
  ];
}

function nextWorkoutType(last) {
  const note = last?.note?.toLowerCase() || "";
  if (note.includes("push")) return tx("Next suggested workout: pull", "Наступне рекомендоване тренування: pull");
  if (note.includes("pull")) return tx("Next suggested workout: legs", "Наступне рекомендоване тренування: ноги");
  if (note.includes("leg")) return tx("Next suggested workout: push", "Наступне рекомендоване тренування: push");
  return `${tx("Next suggested workout", "Наступне рекомендоване тренування")}: ${profileValueLabel(state.profile.split)}`;
}

function achievementsCard() {
  const achievements = [
    achievement(tx("First session", "Перша сесія"), tx("Log your first workout.", "Запиши перше тренування."), state.sessions.length, 1),
    achievement(tx("Ten sessions", "Десять сесій"), tx("Reach ten logged workouts.", "Дійди до десяти збережених тренувань."), state.sessions.length, 10),
    achievement(tx("Streak keeper", "Тримай серію"), tx("Hold a 7-day streak.", "Втримай серію 7 днів."), streakDays(), 7),
    achievement(tx("Set century", "Сотня підходів"), tx("Finish 100 total sets.", "Заверши 100 підходів загалом."), allSets().length, 100),
    achievement(tx("Volume builder", "Будівник обсягу"), tx("Accumulate 10000 total volume.", "Набери 10000 загального обсягу."), Math.round(totalVolume()), 10000)
  ].sort((a, b) => Number(b.progress >= b.target) - Number(a.progress >= a.target) || (b.progress / b.target) - (a.progress / a.target) || a.target - b.target).slice(0, 4);
  return `<section class="panel highlighted"><h2>${t("achievements")}</h2><p class="muted">${tx("Recent unlocks and the next solo milestones.", "Останні відкриття й наступні особисті віхи.")}</p>
    ${achievements.map(a => `<div class="achievement"><div class="percent">${Math.min(100, Math.round(a.progress / a.target * 100))}%</div><div><strong>${a.title}</strong><p>${a.description}</p><div class="progress"><span style="width:${Math.min(100, a.progress / a.target * 100)}%"></span></div><small>${Math.round(a.progress)} / ${a.target}</small></div></div>`).join("")}
  </section>`;
}

function achievement(title, description, progress, target) {
  return { title, description, progress, target };
}

function addWorkoutScreen() {
  if (!modal?.draft) modal = { type: "draft", draft: createDraft() };
  const draft = modal.draft;
  const selectedCount = draft.blocks.filter(b => b.exerciseName).length;
  const setCount = draft.blocks.reduce((sum, block) => sum + block.sets.length, 0);
  return `<section class="hero-panel">
      <h2>${tx("Build today's session", "Збери сьогоднішнє тренування")}</h2><p>${tx("Log your plan fast and keep momentum with smart set shortcuts.", "Швидко запиши план і тримай темп розумними діями для підходів.")}</p>
      <div class="metric-grid"><div><span>${tx("Date", "Дата")}</span><strong>${fmtDate(draft.startedAt)}</strong></div><div><span>${tx("Exercises", "Вправи")}</span><strong>${selectedCount}</strong></div><div><span>${tx("Sets", "Підходи")}</span><strong>${setCount}</strong></div></div>
      <button class="button hero-button" data-action="repeat-latest" ${state.sessions.length ? "" : "disabled"}>${svg("copy", "small-icon")}${t("repeatLast")}</button>
      <button class="button ghost hero-button" data-action="template-picker" ${state.sessions.length ? "" : "disabled"}>${svg("copy", "small-icon")}${t("copyWorkout")}</button>
    </section>
    <section class="panel"><h2>${t("note")}</h2><textarea data-draft="note" placeholder="${tx("Push day, pull day, deload...", "Push день, pull день, делoad...")}">${escapeHtml(draft.note)}</textarea><div class="chip-row">${noteTemplates().map(note => `<button class="chip buttonlike" data-action="note-template" data-note="${note.value}">${note.label}</button>`).join("")}</div></section>
    ${trainingProfilePanel()}
    <section class="draft-list">${draft.blocks.map((block, index) => draftBlock(block, index)).join("")}</section>
    <button class="button secondary full" data-action="add-block">${svg("add", "small-icon")}${t("addExercise")}</button>
    <section class="panel"><p class="muted">${tx("Check your sets, then save to move straight into workout details.", "Перевір підходи й збережи, щоб перейти до деталей тренування.")}</p><button class="button ghost full" data-action="sync-watch">${t("syncWatch")}</button><button class="button full" data-action="save-workout">${svg("save", "small-icon")}${t("saveWorkout")}</button></section>`;
}

function trainingProfilePanel() {
  const p = state.profile;
  return `<section class="panel highlighted"><div class="section-title"><div><h2>${t("trainingProfile")}</h2><p>${tx("Smart Coach uses this to match your plan, goal and recovery.", "Розумний коуч використовує це, щоб підібрати план, ціль і відновлення.")}</p></div>${svg("auto", "small-icon")}</div>
    ${chipSelect("split", ["Upper / Lower", "Full Body", "Push Pull Legs", "Custom"], p.split)}
    ${chipSelect("days", [2, 3, 4, 5, 6].map(v => `${v} / week`), `${p.days} / week`)}
    ${chipSelect("goal", ["Aesthetic Cut", "Muscle Gain", "Strength", "Balanced"], p.goal)}
    ${chipSelect("calories", ["Deficit", "Maintenance", "Surplus"], p.calories)}
    <button class="button full" data-action="generate-smart">${svg("auto", "small-icon")}${t("generateSmart")}</button>
  </section>`;
}

function chipSelect(field, options, selected) {
  return `<div class="chip-row">${options.map(option => `<button class="chip buttonlike ${option === selected ? "selected" : ""}" data-action="profile" data-field="${field}" data-value="${option}">${profileValueLabel(option)}</button>`).join("")}</div>`;
}

function draftBlock(block, blockIndex) {
  const lastWeight = lastWeightFor(block.exerciseName);
  const rec = block.exerciseName ? smartRecommendation(block.exerciseName) : null;
  return `<section class="draft-exercise panel highlighted"><div class="row-head"><h2>${tx("Exercise", "Вправа")} ${blockIndex + 1}</h2><button class="icon-button" data-action="remove-block" data-block="${blockIndex}">${svg("delete")}</button></div>
    <label>${tx("Exercise", "Вправа")}<input list="exercise-options" data-block="${blockIndex}" data-field="exerciseName" value="${escapeAttr(block.exerciseName)}" placeholder="${tx("Select exercise", "Обери вправу")}"></label>
    <datalist id="exercise-options">${state.exercises.map(ex => `<option value="${escapeAttr(ex.name)}"></option>`).join("")}</datalist>
    ${lastWeight != null ? `<div class="row-line"><strong>${tx("Last", "Остання")}: ${lastWeight.toFixed(1)} kg</strong><button class="button ghost mini" data-action="apply-last" data-block="${blockIndex}">${t("useLast")}</button></div>` : ""}
    ${rec ? smartPanel(rec, blockIndex) : ""}
    <div class="actions"><button class="button ghost" data-action="add-set" data-block="${blockIndex}">${t("addSet")}</button><button class="button ghost" data-action="copy-set" data-block="${blockIndex}">${t("copyLast")}</button><button class="button ghost" data-action="plus-set" data-block="${blockIndex}">${t("copyPlus")}</button></div>
    ${block.sets.map((set, setIndex) => `<div class="set-row"><span>${tx("Set", "Підхід")} ${setIndex + 1}</span><input inputmode="decimal" aria-label="${tx("Weight", "Вага")}" data-block="${blockIndex}" data-set="${setIndex}" data-field="weight" value="${escapeAttr(set.weight)}" placeholder="kg"><input inputmode="numeric" aria-label="${tx("Reps", "Повтори")}" data-block="${blockIndex}" data-set="${setIndex}" data-field="reps" value="${escapeAttr(set.reps)}"><button class="icon-button" data-action="remove-set" data-block="${blockIndex}" data-set="${setIndex}">${svg("delete")}</button></div>`).join("")}
  </section>`;
}

function smartPanel(rec, blockIndex) {
  return `<div class="subpanel smart"><div class="row-head"><div><strong>${t("smartCoach")}</strong><p>${rec.kind}</p></div>${svg("auto", "small-icon")}</div><p>${rec.sets.map(s => `${s.weight == null ? tx("light", "легко") : `${s.weight.toFixed(1)} kg`} x ${s.reps}`).join(" | ")}</p><div class="progress"><span style="width:${rec.confidence * 100}%"></span></div><small>${tx("Confidence", "Впевненість")} ${Math.round(rec.confidence * 100)}%</small>${rec.reasons.map(reason => `<p class="muted">${escapeHtml(reason)}</p>`).join("")}<button class="button full" data-action="apply-smart" data-block="${blockIndex}">${t("applySmart")}</button></div>`;
}

function noteTemplates() {
  return [
    ["Push day", tx("Push day", "Push день")],
    ["Pull day", tx("Pull day", "Pull день")],
    ["Leg day", tx("Leg day", "День ніг")],
    ["Upper body", tx("Upper body", "Верх тіла")],
    ["Lower body", tx("Lower body", "Низ тіла")],
    ["Deload", tx("Deload", "Делоад")]
  ].map(([value, label]) => ({ value, label }));
}

function profileValueLabel(value) {
  return {
    "Upper / Lower": tx("Upper / Lower", "Верх / Низ"),
    "Full Body": tx("Full Body", "Все тіло"),
    "Push Pull Legs": tx("Push Pull Legs", "Push Pull Legs"),
    Custom: tx("Custom", "Власний"),
    "2 / week": tx("2 / week", "2 / тиждень"),
    "3 / week": tx("3 / week", "3 / тиждень"),
    "4 / week": tx("4 / week", "4 / тиждень"),
    "5 / week": tx("5 / week", "5 / тиждень"),
    "6 / week": tx("6 / week", "6 / тиждень"),
    "Aesthetic Cut": tx("Aesthetic Cut", "Сушка"),
    "Muscle Gain": tx("Muscle Gain", "Набір м'язів"),
    Strength: tx("Strength", "Сила"),
    Balanced: tx("Balanced", "Баланс"),
    Deficit: tx("Deficit", "Дефіцит"),
    Maintenance: tx("Maintenance", "Підтримка"),
    Surplus: tx("Surplus", "Профіцит")
  }[value] || value;
}

function createDraft(source) {
  const blocks = source ? [...new Set(source.sets.map(s => s.exerciseName))].map(name => ({ exerciseName: name, sets: source.sets.filter(s => s.exerciseName === name).map(s => ({ weight: s.weight, reps: s.reps })) })) : [{ exerciseName: "", sets: [{ weight: "", reps: 8 }] }];
  return { startedAt: Date.now(), note: source?.note || "", blocks };
}

function smartRecommendation(name) {
  const history = allSets()
    .filter(set => set.exerciseName.toLowerCase() === name.toLowerCase())
    .sort((a, b) => b.session.startedAt - a.session.startedAt || a.orderIndex - b.orderIndex)
    .slice(0, 120);
  if (!history.length) {
    const baseline = tx("No saved history yet, so this starts with a clean baseline.", "Історії ще немає, тому план починається з чистої бази.");
    return {
      kindId: "NewExercise",
      kind: smartKindLabel("NewExercise"),
      sets: Array.from({ length: 3 }, () => ({ weight: null, reps: 10 })),
      confidence: 0.35,
      estimatedVolume: 0,
      daysSinceLastSession: null,
      reasons: [baseline],
      reason: baseline
    };
  }

  const sessions = Object.values(history.reduce((acc, set) => {
    acc[set.session.id] ||= { id: set.session.id, date: set.session.startedAt, sets: [] };
    acc[set.session.id].sets.push(set);
    return acc;
  }, {})).sort((a, b) => b.date - a.date).map(snapshotForExerciseSession);
  const latest = sessions[0];
  const previous = sessions[1];
  const daysSinceLastSession = daysBetween(latest.date, Date.now());
  const recentSessions = sessions.slice(0, 5);
  const bestEstimatedMax = Math.max(...sessions.map(s => s.estimatedMax));
  const recentMaxWeights = recentSessions.map(s => s.maxWeight);
  const plateauDetected = recentMaxWeights.length >= 4 && Math.max(...recentMaxWeights) - Math.min(...recentMaxWeights) <= 1.25;
  const latestNearBest = latest.estimatedMax >= bestEstimatedMax * 0.97;
  const previousVolume = previous?.volume || latest.volume;
  const volumeRatio = previousVolume <= 0 ? 1 : latest.volume / previousVolume;
  const latestStable = latest.minReps >= 8 && latest.sets.length >= 3;
  const latestStrained = latest.minReps <= 5 || volumeRatio < 0.88;
  const isFatLossDeficit = state.profile.goal === "Aesthetic Cut" && state.profile.calories === "Deficit";

  let kindId;
  if (daysSinceLastSession >= 10) kindId = "Comeback";
  else if (latestStrained || (isFatLossDeficit && volumeRatio < 0.96)) kindId = "Deload";
  else if (plateauDetected) kindId = "PlateauBreak";
  else if (latestStable && volumeRatio >= 0.95 && !isFatLossDeficit) kindId = "ProgressiveOverload";
  else kindId = "HoldAndBuild";

  const targetSetCount = state.profile.goal === "Strength"
    ? clamp(latest.sets.length, 3, 5)
    : isFatLossDeficit
      ? clamp(latest.sets.length, 3, 4)
      : clamp(latest.sets.length, 2, 5);
  const targetWeight = (() => {
    if (kindId === "ProgressiveOverload") return latest.maxWeight + chooseWeightStep(latest.maxWeight);
    if (kindId === "HoldAndBuild" || kindId === "PlateauBreak") return latest.maxWeight;
    if (kindId === "Deload") return latest.maxWeight * (isFatLossDeficit ? 0.9 : 0.92);
    if (kindId === "Comeback") return latest.maxWeight * comebackMultiplier(daysSinceLastSession);
    return null;
  })();
  const roundedWeight = targetWeight == null ? null : roundToNearestHalf(targetWeight);
  const avgReps = Math.round(latest.averageReps);
  const targetReps = (() => {
    if (kindId === "ProgressiveOverload") return clamp(avgReps, 6, goalMaxReps());
    if (kindId === "HoldAndBuild") return clamp(avgReps + 1, 8, goalMaxReps());
    if (kindId === "Deload") return clamp(avgReps + 1, 8, 12);
    if (kindId === "Comeback") return clamp(avgReps, 8, 12);
    if (kindId === "PlateauBreak") return latest.averageReps >= 9 && !isFatLossDeficit ? 6 : 11;
    return 10;
  })();
  const sets = Array.from({ length: targetSetCount }, (_, index) => ({
    weight: roundedWeight,
    reps: kindId === "PlateauBreak" && targetReps <= 6
      ? Math.max(4, targetReps - Math.floor(index / 2))
      : index >= 3
        ? Math.max(5, targetReps - 1)
        : targetReps
  }));
  const reasons = [];
  if (latestStable) reasons.push(tx("Last session was stable across the sets.", "Остання сесія була стабільною по підходах."));
  if (latestStrained) reasons.push(tx("Recent reps or volume dipped, so the plan stays conservative.", "Повтори або обсяг просіли, тому план обережний."));
  if (daysSinceLastSession >= 10) reasons.push(tx(`${daysSinceLastSession} days since this exercise, so the load is adjusted down.`, `${daysSinceLastSession} днів без цієї вправи, тому навантаження знижено.`));
  if (volumeRatio >= 1.08) reasons.push(tx("Recent volume is trending up.", "Останній обсяг зростає."));
  if (volumeRatio < 0.9) reasons.push(tx("Recent volume dropped compared with the previous session.", "Останній обсяг нижчий за попередню сесію."));
  if (plateauDetected) reasons.push(tx("Several sessions stayed near the same top weight.", "Кілька сесій трималися біля тієї самої максимальної ваги."));
  if (latestNearBest) reasons.push(tx("This is close to your best estimated strength for the exercise.", "Це близько до найкращої оцінки сили в цій вправі."));
  if (state.profile.goal === "Aesthetic Cut") reasons.push(tx("Aesthetic goal: the plan favors clean volume and technique.", "Ціль сушки: план тримає чистий обсяг і техніку."));
  if (state.profile.calories === "Deficit") reasons.push(tx("Calorie deficit: progression is more conservative to protect recovery.", "Дефіцит калорій: прогресія обережніша для відновлення."));
  if (state.profile.days === 4 && state.profile.split === "Upper / Lower") reasons.push(tx("Upper/lower 4-day plan: the load leaves room for the next session.", "План верх/низ 4 дні: навантаження лишає запас для наступної сесії."));
  if (kindId === "ProgressiveOverload") reasons.push(tx("The increase is intentionally conservative.", "Збільшення спеціально обережне."));
  const uniqueReasons = [...new Set(reasons)].slice(0, 3);
  return {
    kindId,
    kind: smartKindLabel(kindId),
    sets,
    confidence: confidenceFor(sessions.length, latest.sets.length, daysSinceLastSession),
    estimatedVolume: sets.reduce((sum, set) => sum + (set.weight || 0) * set.reps, 0),
    daysSinceLastSession,
    reasons: uniqueReasons.length ? uniqueReasons : [tx("The increase is intentionally conservative.", "Збільшення спеціально обережне.")],
    reason: (uniqueReasons[0] || tx("The increase is intentionally conservative.", "Збільшення спеціально обережне."))
  };
}

function snapshotForExerciseSession(session) {
  const weights = session.sets.map(set => Number(set.weight || 0));
  const reps = session.sets.map(set => Number(set.reps || 0));
  return {
    ...session,
    maxWeight: Math.max(...weights),
    minReps: Math.min(...reps),
    averageReps: reps.reduce((sum, value) => sum + value, 0) / reps.length,
    volume: session.sets.reduce((sum, set) => sum + set.weight * set.reps, 0),
    estimatedMax: Math.max(...session.sets.map(set => set.weight * (1 + set.reps / 30)))
  };
}

function chooseWeightStep(weight) {
  const baseStep = weight < 20 ? 1 : weight < 60 ? 2.5 : weight < 120 ? 5 : 7.5;
  return state.profile.goal === "Aesthetic Cut" || state.profile.calories === "Deficit" ? baseStep * 0.5 : baseStep;
}

function goalMaxReps() {
  if (state.profile.goal === "Strength") return 8;
  if (state.profile.goal === "Aesthetic Cut") return 14;
  return 12;
}

function comebackMultiplier(days) {
  if (days >= 45) return 0.82;
  if (days >= 30) return 0.86;
  return 0.9;
}

function confidenceFor(sessionCount, lastSetCount, daysSinceLastSession) {
  const historyScore = Math.min(sessionCount, 6) * 0.09;
  const setScore = Math.min(lastSetCount, 4) * 0.05;
  const profileScore = state.profile.days > 0 ? 0.06 : 0;
  const recencyPenalty = daysSinceLastSession >= 30 ? 0.18 : daysSinceLastSession >= 14 ? 0.08 : 0;
  return clamp(0.35 + historyScore + setScore + profileScore - recencyPenalty, 0.25, 0.94);
}

function smartKindLabel(kindId) {
  return {
    NewExercise: tx("Starter plan: build clean reps and save the first baseline.", "Стартовий план: зроби чисті повтори й збережи першу базу."),
    ProgressiveOverload: tx("Progression plan: small load increase with controlled reps.", "План прогресії: невелике збільшення ваги з контрольованими повторами."),
    HoldAndBuild: tx("Build plan: hold weight and add reps before the next jump.", "План набору: тримай вагу й додай повтори перед наступним стрибком."),
    Deload: tx("Recovery plan: reduce load because the last result looked strained.", "План відновлення: знизь навантаження, бо останній результат був важким."),
    Comeback: tx("Comeback plan: restart below the last weight after a training gap.", "План повернення: почни нижче останньої ваги після паузи."),
    PlateauBreak: tx("Plateau plan: change the rep target to break the flat trend.", "План плато: зміни ціль повторів, щоб зрушити прогрес.")
  }[kindId] || tx("Build plan: hold weight and add reps before the next jump.", "План набору: тримай вагу й додай повтори перед наступним стрибком.");
}

function lastWeightFor(name) {
  if (!name) return null;
  const set = allSets().filter(s => s.exerciseName.toLowerCase() === name.toLowerCase()).sort((a, b) => b.session.startedAt - a.session.startedAt)[0];
  return set ? Number(set.weight) : null;
}

function detailScreen(id) {
  const session = state.sessions.find(s => s.id === id);
  if (!session) return `<div class="empty">${tx("Workout not found.", "Тренування не знайдено.")}</div>`;
  const grouped = [...new Set(session.sets.map(s => s.exerciseName))].map(name => ({ name, sets: session.sets.filter(s => s.exerciseName === name) }));
  const available = state.exercises.filter(ex => !grouped.some(g => g.name === ex.name));
  return `<section class="panel"><h2>${fmtDate(session.startedAt)}</h2><p>${session.note || tx("No note", "Без нотатки")}</p></section>
    <section class="panel"><div class="section-title"><h2>${tx("Add Exercise to This Workout", "Додати вправу в це тренування")}</h2></div>${available.length ? `<select id="quick-add">${available.map(ex => `<option value="${ex.id}">${escapeHtml(ex.name)}</option>`).join("")}</select><button class="button full" data-action="quick-add-exercise">${tx("Add to Workout", "Додати до тренування")}</button>` : `<p class="muted">${tx("All saved exercises are already in this workout.", "Усі збережені вправи вже є в цьому тренуванні.")}</p>`}</section>
    ${grouped.map(group => exerciseDetailCard(session, group)).join("")}
    <button class="fab" data-action="finish-workout" data-id="${session.id}">${svg("check", "small-icon")}${t("finishWorkout")}</button>`;
}

function exerciseDetailCard(session, group) {
  const key = `${session.id}:${group.name}`;
  const remaining = timerRemaining(key);
  return `<section class="panel highlighted"><div class="row-head"><h2>${escapeHtml(group.name)}</h2>${isPr(session, group.name) ? `<span class="pill">${svg("trophy", "small-icon")}${tx("New PR", "Новий PR")}</span>` : ""}</div>
    <div class="timer-row"><div><strong>${tx("Exercise Rest", "Відпочинок")}</strong><span>${remaining > 0 ? formatTimer(remaining) : tx("Ready", "Готово")}</span></div><div class="actions"><button class="button ghost mini" data-action="timer" data-key="${key}" data-seconds="60">60s</button><button class="button ghost mini" data-action="timer" data-key="${key}" data-seconds="90">90s</button><button class="button ghost mini" data-action="timer" data-key="${key}" data-seconds="180">180s</button><button class="button ghost mini" data-action="timer-stop" data-key="${key}" ${remaining ? "" : "disabled"}>${tx("Stop", "Стоп")}</button></div></div>
    <div class="table"><div class="table-head"><span>${tx("Set", "Підхід")}</span><span>${tx("Weight (kg)", "Вага (кг)")}</span><span>${tx("Reps", "Повтори")}</span><span></span></div>${group.sets.map((set, i) => `<div class="table-row"><span>${tx("Set", "Підхід")} ${i + 1}</span><span>${Number(set.weight).toFixed(1)}</span><span>${set.reps}</span><span><button class="icon-button" data-action="edit-set" data-id="${set.id}">${svg("edit")}</button><button class="icon-button" data-action="delete-set" data-id="${set.id}">${svg("delete")}</button></span></div>`).join("")}</div>
    <button class="button ghost full" data-action="detail-add-set" data-session="${session.id}" data-name="${escapeAttr(group.name)}">${t("addSet")}</button>
  </section>`;
}

function isPr(session, name) {
  const previous = allSets(state.sessions.filter(s => s.startedAt < session.startedAt)).filter(s => s.exerciseName === name).map(s => s.weight);
  const current = session.sets.filter(s => s.exerciseName === name).map(s => s.weight);
  return current.length && Math.max(...current) > Math.max(0, ...previous);
}

function summaryScreen(id) {
  const session = state.sessions.find(s => s.id === id);
  if (!session) return `<div class="empty">${tx("Workout summary unavailable.", "Підсумок тренування недоступний.")}</div>`;
  const before = state.sessions.filter(s => s.startedAt < session.startedAt);
  const summary = sessionSummary(session);
  const xpGain = xpForSessions([session]);
  const xpTotal = totalXp();
  const progress = levelProgress(xpTotal);
  const records = [...new Set(session.sets.map(s => s.exerciseName))].map(name => {
    const prev = Math.max(0, ...allSets(before).filter(s => s.exerciseName === name).map(s => s.weight));
    const now = Math.max(0, ...session.sets.filter(s => s.exerciseName === name).map(s => s.weight));
    return now > prev ? { name, prev, now } : null;
  }).filter(Boolean);
  const mStats = muscleStats([session]).filter(m => m.load > 0).sort((a, b) => b.load - a.load);
  return `<section class="hero-panel"><h2>${t("workoutComplete")}</h2><p>${fmtDate(session.startedAt)}</p><div class="metric-grid"><div><span>${tx("XP gained", "Отримано XP")}</span><strong>+${xpGain} XP</strong></div><div><span>${tx("Level", "Рівень")}</span><strong>${levelFromXp(xpTotal)}</strong></div></div></section>
    <section class="metric-grid post"><div><span>${tx("Current title", "Поточний ранг")}</span><strong>${rankTitle(xpTotal)}</strong></div><div><span>${tx("Streak", "Серія")}</span><strong>${streakDays()} ${tx("d", "д")}</strong></div><div><span>${tx("Exercises", "Вправи")}</span><strong>${summary.exercises}</strong></div><div><span>${tx("Sets", "Підходи")}</span><strong>${summary.sets}</strong></div><div><span>${tx("Volume", "Обсяг")}</span><strong>${Math.round(summary.volume)}</strong></div></section>
    <section class="panel"><h2>${t("impact")}</h2><p class="muted">${mStats[0] ? `${tx("Most loaded today", "Найбільше навантажено сьогодні")}: ${mStats[0].label}` : tx("Mapped muscle load will appear after sets are saved.", "Навантаження м'язів з'явиться після збереження підходів.")}</p>${mStats.slice(0, 5).map(m => barRow(m.label, m.load, mStats[0]?.load || 1, `${Math.round(m.load)} ${tx("load", "навантаження")} - ${n(m.sets, "set", "sets", "підхід", "підходи", "підходів")}`)).join("")}</section>
    ${records.length ? `<section class="panel highlighted"><h2>${t("personalRecords")}</h2>${records.map(r => `<div class="row-line"><div><strong>${escapeHtml(r.name)}</strong><p>${r.prev ? `${tx("Previous best", "Попередній рекорд")} ${r.prev.toFixed(1)} kg` : tx("First logged best", "Перший зафіксований рекорд")}</p></div><span class="pill">${r.now.toFixed(1)} kg</span></div>`).join("")}</section>` : ""}
    <section class="panel"><h2>${t("levelProgress")}</h2><p>${tx("Level", "Рівень")} ${levelFromXp(xpTotal)} - ${rankTitle(xpTotal)}</p><div class="progress"><span style="width:${progress.progressFraction * 100}%"></span></div><div class="row-line"><span>${progress.currentLevelXp} XP ${tx("into this level", "у цьому рівні")}</span><strong>${progress.xpForNextLevel - progress.currentLevelXp} XP ${tx("to next", "до наступного")}</strong></div></section>
    <section class="panel"><h2>${t("momentum")}</h2><p>${streakDays() > 1 ? `${tx("Streak extended to", "Серію продовжено до")} ${streakDays()} ${tx("days.", "днів.")}` : tx("A fresh streak has started.", "Нова серія почалася.")}</p><div class="chip-row"><span class="chip">${tx("Logged today", "Записано сьогодні")}</span><span class="chip">${tx("Best", "Найкраще")} ${streakDays()} ${tx("d", "д")}</span></div></section>
    <div class="actions vertical"><button class="button full" data-action="summary-view" data-id="${session.id}">${tx("View workout", "Переглянути тренування")}</button><button class="button ghost full" data-action="summary-done">${tx("Back to workouts", "Назад до тренувань")}</button></div>`;
}

function exercisesScreen() {
  return `<section class="panel"><div class="field-row"><input id="new-exercise-name" placeholder="e.g. Bench Press"><button class="button" data-action="save-exercise">${t("addExercise")}</button></div></section>
    <section class="panel"><h2>${t("backup")}</h2><div class="actions"><button class="button ghost" data-action="export-json">${t("exportJson")}</button><button class="button ghost" data-action="import-json">${t("importJson")}</button><button class="button ghost full" data-action="export-diagnostics">${t("diagnostics")}</button></div></section>
    <section class="exercise-list">${state.exercises.length ? state.exercises.map(exerciseRow).join("") : `<div class="empty">${tx("No exercises yet.", "Вправ ще немає.")}</div>`}</section>`;
}

function exerciseRow(exercise) {
  const stats = groupedExercises().find(g => g.name === exercise.name) || { sets: 0, volume: 0, best: 0, sessions: new Set() };
  return `<article class="exercise-row clickable" data-action="exercise-history" data-id="${exercise.id}"><div><h3>${escapeHtml(exercise.name)}</h3><span class="muted">${tx("Sessions", "Сесії")}: ${stats.sessions.size} - ${tx("Sets", "Підходи")}: ${stats.sets} - ${tx("Volume", "Обсяг")}: ${Math.round(stats.volume)}</span></div><div class="actions"><button class="icon-button" data-action="rename-exercise" data-id="${exercise.id}">${svg("edit")}</button><button class="icon-button" data-action="delete-exercise" data-id="${exercise.id}">${svg("delete")}</button></div></article>`;
}

function progressScreen() {
  const selectedId = state.progressExerciseId || state.exercises[0]?.id;
  const selected = state.exercises.find(ex => ex.id === selectedId);
  if (!selected) return `<div class="empty">${tx("No exercises yet.", "Вправ ще немає.")}</div>`;
  const history = allSets(selectedMonthSessions()).filter(set => set.exerciseName === selected.name).sort((a, b) => b.session.startedAt - a.session.startedAt);
  const grouped = Object.values(history.reduce((acc, set) => {
    acc[set.session.id] ||= { session: set.session, sets: [] };
    acc[set.session.id].sets.push(set);
    return acc;
  }, {}));
  const best = Math.max(0, ...history.map(s => s.weight));
  const avg = grouped.length ? grouped.reduce((sum, g) => sum + Math.max(...g.sets.map(s => s.weight)), 0) / grouped.length : 0;
  const vol = history.reduce((sum, s) => sum + s.weight * s.reps, 0);
  return `${monthSwitcher()}<section class="panel"><label>${tx("Exercise", "Вправа")}<select id="progress-select" data-action="progress-select">${state.exercises.map(ex => `<option value="${ex.id}" ${ex.id === selectedId ? "selected" : ""}>${escapeHtml(ex.name)}</option>`).join("")}</select></label></section>
    <section class="panel"><h2>${tx("Progress Summary", "Підсумок прогресу")}</h2><p class="muted">${tx("Volume = weight x reps across all completed sets.", "Обсяг = вага x повтори по всіх завершених підходах.")}</p><div class="metric-grid three"><div><span>${tx("Sessions", "Сесії")}</span><strong>${grouped.length}</strong></div><div><span>${tx("Total Sets", "Усього підходів")}</span><strong>${history.length}</strong></div><div><span>${tx("Total Reps", "Усього повторів")}</span><strong>${history.reduce((s, x) => s + x.reps, 0)}</strong></div><div><span>${tx("Best Weight", "Найкраща вага")}</span><strong>${best.toFixed(1)} kg</strong></div><div><span>${tx("Average Max", "Середній максимум")}</span><strong>${avg.toFixed(1)} kg</strong></div><div><span>${tx("Total Volume", "Загальний обсяг")}</span><strong>${Math.round(vol)}</strong></div></div></section>
    <section class="panel">${spotlight(selected.name, grouped, best, vol)}</section>
    <section class="panel"><h2>${tx("Visual Trends", "Візуальні тренди")}</h2><div class="bars">${grouped.length ? grouped.slice().reverse().map(g => barRow(fmtDate(g.session.startedAt, { day: "numeric", month: "short" }), Math.max(...g.sets.map(s => s.weight)), best || 1, `${tx("Vol", "Обсяг")} ${Math.round(g.sets.reduce((sum, s) => sum + s.weight * s.reps, 0))}`)).join("") : `<div class="empty">${tx("Add sets to see chart.", "Додай підходи, щоб побачити графік.")}</div>`}</div></section>
    <section class="workout-list"><h2>${tx("Workout History", "Історія тренувань")}</h2>${grouped.length ? grouped.map(g => progressHistoryCard(g)).join("") : `<div class="empty">${tx("No history in this month.", "Немає історії за цей місяць.")}</div>`}</section>`;
}

function spotlight(name, grouped, best, vol) {
  return `<h2>${escapeHtml(name)}</h2><div class="metric-grid"><div><span>${tx("All-time best", "Найкраще за весь час")}</span><strong>${best.toFixed(1)} kg</strong></div><div><span>${tx("Consistency", "Стабільність")}</span><strong>${n(grouped.length, "session", "sessions", "сесія", "сесії", "сесій")}</strong></div><div><span>${tx("Peak weight", "Пікова вага")}</span><strong>${best.toFixed(1)} kg</strong></div><div><span>${tx("Avg volume", "Сер. обсяг")}</span><strong>${grouped.length ? Math.round(vol / grouped.length) : 0}</strong></div></div>`;
}

function progressHistoryCard(group) {
  const volume = group.sets.reduce((sum, s) => sum + s.weight * s.reps, 0);
  return `<article class="workout-item"><h3>${fmtDate(group.session.startedAt)}</h3><div class="chip-row"><span class="chip">${tx("Sets", "Підходи")}: ${group.sets.length}</span><span class="chip">${tx("Reps", "Повтори")}: ${group.sets.reduce((s, x) => s + x.reps, 0)}</span><span class="chip">${tx("Volume", "Обсяг")}: ${Math.round(volume)}</span></div><div class="table">${group.sets.map((set, i) => `<div class="table-row"><span>${tx("Set", "Підхід")} ${i + 1}</span><span>${set.weight.toFixed(1)}</span><span>${set.reps}</span><button class="icon-button" data-action="delete-set" data-id="${set.id}">${svg("delete")}</button></div>`).join("")}</div></article>`;
}

function missionsScreen() {
  const missions = missionGroups();
  const all = [...missions.daily, ...missions.weekly, ...missions.monthly];
  const done = all.filter(m => m.done);
  return `<section class="hero-panel"><h2>${t("missions")}</h2><p>${tx("Active daily, weekly, and monthly missions rotate from a huge challenge pool.", "Активні щоденні, тижневі й місячні місії обираються з великого пулу викликів.")}</p><div class="metric-grid"><div><span>${tx("Total", "Усього")}</span><strong>${all.length}</strong></div><div><span>${tx("Completed", "Виконано")}</span><strong>${done.length}</strong></div><div><span>${tx("Open", "Відкрито")}</span><strong>${all.length - done.length}</strong></div><div><span>${tx("Progress", "Прогрес")}</span><strong>${done.length}/${all.length}</strong></div></div><p>${tx("Mission XP from completed goals", "XP місій за виконані цілі")}: ${done.reduce((s, m) => s + m.reward, 0)}</p></section>
    <section class="panel highlighted clickable" data-action="open-ranks"><div class="section-title"><div><h2>${tx("Rank ladder", "Драбина рангів")}</h2><p>${tx("Open the full rank list and check the next unlocks.", "Відкрий повний список рангів і перевір наступні відкриття.")}</p></div><span class="pill">${t("viewRanks")}</span></div><div class="metric-grid"><div><span>${tx("Current level", "Поточний рівень")}</span><strong>${levelFromXp()}</strong></div><div><span>${tx("Current title", "Поточний ранг")}</span><strong>${rankTitle()}</strong></div></div></section>
    ${missionSection(t("daily"), missions.daily)}${missionSection(t("weekly"), missions.weekly)}${missionSection(t("monthly"), missions.monthly)}`;
}

function missionGroups() {
  const month = selectedMonthSessions();
  const weekSessions = state.sessions.filter(s => s.startedAt >= startOfWeek());
  const todaySessions = state.sessions.filter(s => new Date(s.startedAt).toDateString() === new Date().toDateString());
  const todaySets = allSets(todaySessions);
  const weekSets = allSets(weekSessions);
  const monthSets = allSets(month);
  const todayExerciseCount = new Set(todaySets.map(s => s.exerciseName)).size;
  const weekExerciseCount = new Set(weekSets.map(s => s.exerciseName)).size;
  const monthExerciseCount = new Set(monthSets.map(s => s.exerciseName)).size;
  const weekActiveDays = new Set(weekSessions.map(s => new Date(s.startedAt).toDateString())).size;
  const monthActiveDays = new Set(month.map(s => new Date(s.startedAt).toDateString())).size;
  return {
    daily: [
      mission("daily-check-in", tx("Complete a workout", "Заверши тренування"), todaySessions.length, 1, 30),
      mission("daily-sets-8", tx("Log 8 sets", "Запиши 8 підходів"), todaySets.length, 8, 25),
      mission("daily-exercises-3", tx("Train 3 exercises", "Зроби 3 вправи"), todayExerciseCount, 3, 35),
      mission("daily-volume-1000", tx("Move 1,000 volume", "Набери 1 000 обсягу"), totalVolume(todaySessions), 1000, 40),
      mission("daily-session-density", tx("Finish a dense session", "Заверши щільну сесію"), Math.max(0, ...todaySessions.map(s => s.sets.length)), 10, 45)
    ],
    weekly: [
      mission("weekly-days-3", tx("Train on 3 days", "Тренуйся 3 дні"), weekActiveDays, 3, 60),
      mission("weekly-workouts-4", tx("Complete 4 workouts", "Заверши 4 тренування"), weekSessions.length, 4, 70),
      mission("weekly-sets-30", tx("Log 30 sets", "Запиши 30 підходів"), weekSets.length, 30, 80),
      mission("weekly-volume-5000", tx("Move 5,000 volume", "Набери 5 000 обсягу"), totalVolume(weekSessions), 5000, 100),
      mission("weekly-exercises-10", tx("Touch 10 exercises", "Зачепи 10 вправ"), weekExerciseCount, 10, 85),
      mission("weekly-big-session", tx("Hit 12 sets in one session", "Зроби 12 підходів за сесію"), Math.max(0, ...weekSessions.map(s => s.sets.length)), 12, 75),
      mission("weekly-heavy-day", tx("Move 2,000 volume in one session", "Набери 2 000 обсягу за сесію"), Math.max(0, ...weekSessions.map(s => totalVolume([s]))), 2000, 90),
      mission("weekly-frequency", tx("Complete 5 workouts", "Заверши 5 тренувань"), weekSessions.length, 5, 110),
      mission("weekly-set-stack", tx("Log 45 sets", "Запиши 45 підходів"), weekSets.length, 45, 120),
      mission("weekly-volume-push", tx("Move 8,000 volume", "Набери 8 000 обсягу"), totalVolume(weekSessions), 8000, 140)
    ],
    monthly: [
      mission("monthly-days-10", tx("Train on 10 days", "Тренуйся 10 днів"), monthActiveDays, 10, 180),
      mission("monthly-workouts-14", tx("Complete 14 workouts", "Заверши 14 тренувань"), month.length, 14, 220),
      mission("monthly-sets-120", tx("Log 120 sets", "Запиши 120 підходів"), monthSets.length, 120, 240),
      mission("monthly-volume-20000", tx("Move 20,000 volume", "Набери 20 000 обсягу"), totalVolume(month), 20000, 280),
      mission("monthly-exercises-18", tx("Touch 18 exercises", "Зачепи 18 вправ"), monthExerciseCount, 18, 230),
      mission("monthly-big-session", tx("Hit 16 sets in one session", "Зроби 16 підходів за сесію"), Math.max(0, ...month.map(s => s.sets.length)), 16, 180),
      mission("monthly-heavy-day", tx("Move 3,500 volume in one session", "Набери 3 500 обсягу за сесію"), Math.max(0, ...month.map(s => totalVolume([s]))), 3500, 210),
      mission("monthly-consistency", tx("Train on 16 days", "Тренуйся 16 днів"), monthActiveDays, 16, 300),
      mission("monthly-set-stack", tx("Log 180 sets", "Запиши 180 підходів"), monthSets.length, 180, 340),
      mission("monthly-volume-push", tx("Move 35,000 volume", "Набери 35 000 обсягу"), totalVolume(month), 35000, 380)
    ]
  };
}

function completedMissions() {
  return Object.values(missionGroups()).flat().filter(m => m.done);
}

function mission(id, title, progress, target, reward) {
  return { id, title, summary: `${Math.round(progress)} / ${target}`, progress, target, reward, done: progress >= target };
}

function missionSection(title, missions) {
  return `<section class="mission-list"><div class="section-title panel compact"><div><h2>${title}</h2><p>${tx("Consistency goals for the current period.", "Цілі стабільності на поточний період.")}</p></div><span class="pill">${missions.filter(m => m.done).length}/${missions.length} ${tx("done", "виконано")}</span></div>${missions.map(missionCard).join("")}</section>`;
}

function missionCard(m) {
  return `<article class="mission-row ${m.done ? "highlighted" : ""}"><div class="row-head"><div><h3>${m.title}</h3><p>${m.summary}</p></div><span class="pill">${m.done ? tx("Completed", "Виконано") : tx("In progress", "У процесі")}</span></div><div class="chip-row"><span class="chip">+${m.reward} XP</span><span class="chip">${m.summary}</span></div><div class="progress"><span style="width:${Math.min(100, m.progress / m.target * 100)}%"></span></div></article>`;
}

function ranksScreen() {
  const xp = totalXp();
  return `<section class="hero-panel"><h2>${t("ranks")}</h2><p>${tx("See every title, its level gate, and the XP needed to unlock it.", "Переглянь усі ранги, потрібний рівень і XP для відкриття.")}</p><div class="metric-grid"><div><span>${tx("TOTAL XP", "УСЬОГО XP")}</span><strong>${xp}</strong></div><div><span>${tx("Current level", "Поточний рівень")}</span><strong>${levelFromXp(xp)}</strong></div></div><p>${tx("Current title", "Поточний ранг")}: ${rankTitle(xp)}</p></section>
    ${rankLadder().map(rank => {
      const unlocked = rank.isUnlocked;
      const current = rank.isCurrent;
      const status = current ? tx("Current", "Поточний") : unlocked ? tx("Unlocked", "Відкрито") : tx("Locked", "Закрито");
      return `<section class="panel ${current ? "highlighted" : ""}"><div class="row-head"><div><h2>${rank.title}</h2><p>${status}</p></div><span class="pill">${status}</span></div><div class="metric-grid"><div><span>${tx("Required level", "Потрібний рівень")}</span><strong>${rank.level}</strong></div><div><span>${tx("Required total XP", "Потрібно XP")}</span><strong>${rank.xp}</strong></div></div><div class="progress"><span style="width:${rank.progressFraction * 100}%"></span></div><div class="row-line"><span>${Math.min(xp, rank.xp)} / ${rank.xp} XP</span>${!unlocked ? `<strong>${rank.xpRemaining} XP ${tx("left", "лишилось")}</strong>` : ""}</div></section>`;
    }).join("")}`;
}

function modalMarkup() {
  if (modal.type === "template") return bottomSheet(`<h2>${t("templatePicker")}</h2>${state.sessions.length ? [...state.sessions].sort((a, b) => b.startedAt - a.startedAt).map(session => `<article class="workout-item"><h3>${fmtDate(session.startedAt)}</h3><p>${sessionSummary(session).exercises} ${tx("exercises", "вправ")} - ${sessionSummary(session).sets} ${tx("sets", "підходів")} - ${Math.round(sessionSummary(session).volume)} ${tx("volume", "обсяг")}</p><button class="button full" data-action="copy-template" data-id="${session.id}">${t("copyWorkout")}</button></article>`).join("") : `<p>${tx("No previous workouts yet.", "Попередніх тренувань ще немає.")}</p>`}`);
  if (modal.type === "import") return bottomSheet(`<h2>${tx("Import backup", "Імпорт бекапу")}</h2><textarea id="import-json" placeholder="${tx("Paste exported GymApp JSON here", "Встав сюди експортований JSON GymApp")}"></textarea><button class="button full" data-action="apply-import">${tx("Import", "Імпорт")}</button>`);
  if (modal.type === "backup-json") return bottomSheet(`<h2>${tx("Backup JSON ready", "JSON бекапу готовий")}</h2><textarea readonly>${escapeHtml(modal.json)}</textarea><div class="actions"><button class="button" data-action="copy-json">${tx("Copy JSON", "Копіювати JSON")}</button><button class="button ghost" data-action="download-json">${tx("Download", "Завантажити")}</button></div><button class="button ghost full" data-action="pdf-report">${t("sharePdf")}</button>`);
  if (modal.type === "rename") return bottomSheet(`<h2>${t("rename")}</h2><input id="rename-name" value="${escapeAttr(modal.exercise.name)}"><button class="button full" data-action="apply-rename" data-id="${modal.exercise.id}">${tx("Save", "Зберегти")}</button>`);
  if (modal.type === "history") return bottomSheet(exerciseHistoryMarkup(modal.exercise));
  if (modal.type === "map") return bottomSheet(mappingEditor(modal.name));
  if (modal.type === "edit-set") return bottomSheet(`<h2>${tx("Edit Set", "Редагувати підхід")}</h2><label>${tx("Weight (kg)", "Вага (кг)")}<input id="edit-weight" value="${modal.set.weight || ""}" inputmode="decimal"></label><label>${tx("Reps", "Повтори")}<input id="edit-reps" value="${modal.set.reps || ""}" inputmode="numeric"></label><button class="button full" data-action="apply-edit-set" data-id="${modal.set.id}">${tx("Save", "Зберегти")}</button>`);
  return "";
}

function bottomSheet(content) {
  return `<div class="modal" role="dialog" aria-modal="true"><section class="modal-panel"><div class="sheet-handle"></div><button class="icon-button sheet-close" data-action="close-modal">${svg("close")}</button>${content}</section></div>`;
}

function exerciseHistoryMarkup(exercise) {
  const history = allSets().filter(set => set.exerciseName === exercise.name).sort((a, b) => b.session.startedAt - a.session.startedAt);
  const groups = Object.values(history.reduce((acc, set) => {
    acc[set.session.id] ||= { session: set.session, sets: [] };
    acc[set.session.id].sets.push(set);
    return acc;
  }, {}));
  return `<h2>${escapeHtml(exercise.name)}</h2><div class="metric-grid three"><div><span>${tx("Sessions", "Сесії")}</span><strong>${groups.length}</strong></div><div><span>${tx("Sets", "Підходи")}</span><strong>${history.length}</strong></div><div><span>${tx("Volume", "Обсяг")}</span><strong>${Math.round(history.reduce((s, x) => s + x.weight * x.reps, 0))}</strong></div></div>${groups.length ? groups.map(progressHistoryCard).join("") : `<div class="empty">${tx("No history for this exercise yet.", "Історії для цієї вправи ще немає.")}</div>`}`;
}

function mappingEditor(name) {
  const current = new Set(mappingFor(name));
  return `<h2>${tx("Map", "Мапінг")} "${escapeHtml(name)}"</h2><div class="mapping-grid">${muscles.map(([id, label]) => `<button class="chip buttonlike ${current.has(id) ? "selected" : ""}" data-action="toggle-map" data-id="${id}">${label}</button>`).join("")}</div><button class="button full" data-action="save-map" data-name="${escapeAttr(name)}">${tx("Save", "Зберегти")}</button>`;
}

function bindEvents() {
  app.querySelectorAll("[data-route]").forEach(el => el.addEventListener("click", () => goRoot(el.dataset.route)));
  app.querySelectorAll("[data-action]").forEach(el => el.addEventListener("click", ev => {
    ev.stopPropagation();
    handleAction(el.dataset.action, el);
  }));
  app.querySelectorAll("[data-block][data-field]").forEach(input => input.addEventListener("input", () => updateDraftInput(input)));
  app.querySelectorAll("[data-draft]").forEach(input => input.addEventListener("input", () => {
    if (modal?.draft) modal.draft[input.dataset.draft] = input.value;
  }));
  const progressSelect = app.querySelector("#progress-select");
  if (progressSelect) progressSelect.addEventListener("change", () => {
    state.progressExerciseId = Number(progressSelect.value);
    saveState();
    render();
  });
}

function handleAction(action, el) {
  if (action === "back") return back();
  if (action === "language") { state.language = state.language === "en" ? "uk" : "en"; saveState(); return render(); }
  if (action === "backup") { modal = { type: "backup-json", json: exportPayload(false) }; return render(); }
  if (action === "open-add") return push("add");
  if (action === "open-detail") return push("detail", { id: Number(el.dataset.id) });
  if (action === "finish-workout") return push("summary", { id: Number(el.dataset.id) });
  if (action === "summary-view") { nav = [{ name: "workouts" }, { name: "detail", id: Number(el.dataset.id) }]; return render(); }
  if (action === "summary-done") return goRoot("workouts");
  if (action === "open-ranks") return push("ranks");
  if (action === "month-prev") { selectedMonthOffset--; return render(); }
  if (action === "month-next") { selectedMonthOffset++; return render(); }
  if (action === "month-current") { selectedMonthOffset = 0; return render(); }
  if (action === "overview-mode") { overviewMode = el.dataset.mode; return render(); }
  if (action === "muscle-period") { musclePeriod = el.dataset.period; return render(); }
  if (action === "select-muscle") { selectedMuscle = el.dataset.id; return render(); }
  if (action === "map-exercise") { modal = { type: "map", name: el.dataset.name }; return render(); }
  if (action === "toggle-map") { el.classList.toggle("selected"); return; }
  if (action === "save-map") return saveMapping(el.dataset.name);
  if (action === "profile") return updateProfile(el);
  if (action === "note-template") return applyNoteTemplate(el.dataset.note);
  if (action === "generate-smart") return generateSmartWorkout();
  if (action === "repeat-latest") { modal.draft = createDraft([...state.sessions].sort((a, b) => b.startedAt - a.startedAt)[0]); return render(); }
  if (action === "template-picker") { modal = { type: "template" }; return render(); }
  if (action === "copy-template") { modal = { type: "draft", draft: createDraft(state.sessions.find(s => s.id === Number(el.dataset.id))) }; nav = [{ name: "workouts" }, { name: "add" }]; return render(); }
  if (action === "add-block") { modal.draft.blocks.push({ exerciseName: "", sets: [{ weight: "", reps: 8 }] }); return render(); }
  if (action === "remove-block") { modal.draft.blocks.splice(Number(el.dataset.block), 1); return render(); }
  if (action === "add-set") { modal.draft.blocks[Number(el.dataset.block)].sets.push({ weight: "", reps: 8 }); return render(); }
  if (action === "copy-set" || action === "plus-set") { copyDraftSet(Number(el.dataset.block), action === "plus-set"); return render(); }
  if (action === "remove-set") { modal.draft.blocks[Number(el.dataset.block)].sets.splice(Number(el.dataset.set), 1); return render(); }
  if (action === "apply-last") return applyLast(Number(el.dataset.block));
  if (action === "apply-smart") return applySmart(Number(el.dataset.block));
  if (action === "sync-watch") return showToast("Plan sync is unavailable on iPhone PWA, but the plan is ready locally.");
  if (action === "save-workout") return saveWorkout();
  if (action === "quick-add-exercise") return quickAddExercise();
  if (action === "detail-add-set") return detailAddSet(Number(el.dataset.session), el.dataset.name);
  if (action === "edit-set") return openEditSet(Number(el.dataset.id));
  if (action === "apply-edit-set") return applyEditSet(Number(el.dataset.id));
  if (action === "delete-set") return deleteSet(Number(el.dataset.id));
  if (action === "timer") { state.timers ||= {}; state.timers[el.dataset.key] = Date.now() + Number(el.dataset.seconds) * 1000; saveState(); return render(); }
  if (action === "timer-stop") { delete state.timers?.[el.dataset.key]; saveState(); return render(); }
  if (action === "save-exercise") return saveExercise();
  if (action === "rename-exercise") { modal = { type: "rename", exercise: state.exercises.find(ex => ex.id === Number(el.dataset.id)) }; return render(); }
  if (action === "apply-rename") return applyRename(Number(el.dataset.id));
  if (action === "delete-exercise") return deleteExercise(Number(el.dataset.id));
  if (action === "exercise-history") { modal = { type: "history", exercise: state.exercises.find(ex => ex.id === Number(el.dataset.id)) }; return render(); }
  if (action === "export-json") { modal = { type: "backup-json", json: exportPayload(false) }; return render(); }
  if (action === "export-diagnostics") { modal = { type: "backup-json", json: exportPayload(true) }; return render(); }
  if (action === "import-json") { modal = { type: "import" }; return render(); }
  if (action === "apply-import") return applyImport();
  if (action === "copy-json") return navigator.clipboard?.writeText(modal.json).then(() => showToast(tx("JSON copied.", "JSON скопійовано.")));
  if (action === "download-json") return downloadJson(modal.json);
  if (action === "pdf-report") return printReport();
  if (action === "close-modal") { modal = null; return render(); }
}

function updateDraftInput(input) {
  const block = modal?.draft?.blocks[Number(input.dataset.block)];
  if (!block) return;
  if (input.dataset.set === undefined) block[input.dataset.field] = input.value;
  else block.sets[Number(input.dataset.set)][input.dataset.field] = input.value;
}

function updateProfile(el) {
  const field = el.dataset.field;
  const value = el.dataset.value;
  if (field === "days") state.profile.days = Number.parseInt(value, 10);
  else state.profile[field] = value;
  saveState();
  render();
}

function applyNoteTemplate(note) {
  const current = modal.draft.note.trim();
  modal.draft.note = current ? current.includes(note) ? current : `${current} | ${note}` : note;
  render();
}

function generateSmartWorkout() {
  const plan = buildSmartWorkoutPlan();
  modal.draft.blocks = plan.exercises.map(({ name, recommendation }) => ({
    exerciseName: name,
    sets: recommendation.sets.map(set => ({ weight: set.weight ?? "", reps: set.reps }))
  }));
  showToast(`${tx("Smart workout generated", "Розумне тренування згенеровано")}: ${plan.focus}.`);
  render();
}

function buildSmartWorkoutPlan() {
  const focus = chooseWorkoutFocus();
  const targetExerciseCount = focus === "FullBody" ? 6 : 5;
  const candidates = state.exercises.map(exercise => {
    const exerciseHistory = allSets().filter(set => set.exerciseName === exercise.name);
    const bodyGroup = classifyExercise(exercise.name);
    const latest = exerciseHistory.reduce((max, set) => Math.max(max, set.session.startedAt), 0);
    const daysSince = latest ? daysBetween(latest, Date.now()) : 90;
    const sessionCount = new Set(exerciseHistory.map(set => set.session.id)).size;
    const focusScore = focus === "FullBody" ? 24 : isCandidateForFocus(bodyGroup, focus) && bodyGroup !== "FullBody" ? 80 : bodyGroup === "FullBody" ? 34 : -35;
    const noveltyScore = sessionCount === 0 ? 18 : 0;
    const dueScore = Math.min(daysSince, 45) * 1.6;
    const confidenceScore = Math.min(sessionCount, 6) * 3;
    return { exercise, bodyGroup, score: focusScore + noveltyScore + dueScore + confidenceScore };
  }).sort((a, b) => b.score - a.score || a.exercise.name.localeCompare(b.exercise.name));
  const primary = candidates.filter(candidate => isCandidateForFocus(candidate.bodyGroup, focus)).slice(0, targetExerciseCount);
  const fallback = primary.length >= targetExerciseCount ? [] : candidates.filter(candidate => !primary.some(item => item.exercise.id === candidate.exercise.id)).slice(0, targetExerciseCount - primary.length);
  return {
    focus,
    exercises: [...primary, ...fallback].slice(0, targetExerciseCount).map(candidate => ({
      name: candidate.exercise.name,
      recommendation: smartRecommendation(candidate.exercise.name)
    }))
  };
}

function chooseWorkoutFocus() {
  const history = allSets();
  if (!history.length) {
    if (state.profile.split === "Upper / Lower") return "Upper";
    if (state.profile.split === "Push Pull Legs") return "Push";
    return "FullBody";
  }
  const latestSessionId = history.reduce((best, set) => set.session.startedAt > best.date ? { id: set.session.id, date: set.session.startedAt } : best, { id: null, date: 0 }).id;
  const latest = history.filter(set => set.session.id === latestSessionId);
  if (state.profile.split === "Upper / Lower") {
    const lowerCount = latest.filter(set => ["Lower", "Legs"].includes(classifyExercise(set.exerciseName))).length;
    const upperCount = latest.filter(set => ["Upper", "Push", "Pull"].includes(classifyExercise(set.exerciseName))).length;
    return lowerCount > upperCount ? "Upper" : "Lower";
  }
  if (state.profile.split === "Push Pull Legs") {
    const push = latest.filter(set => classifyExercise(set.exerciseName) === "Push").length;
    const pull = latest.filter(set => classifyExercise(set.exerciseName) === "Pull").length;
    const legs = latest.filter(set => ["Lower", "Legs"].includes(classifyExercise(set.exerciseName))).length;
    if (legs >= push && legs >= pull) return "Push";
    return push >= pull ? "Pull" : "Legs";
  }
  if (state.profile.split === "Custom") return chooseMostNeglectedFocus(history);
  return "FullBody";
}

function classifyExercise(name) {
  const normalized = name.toLowerCase().replace(/\s+/g, " ").trim();
  const has = (...tokens) => tokens.some(token => normalized.includes(token));
  if (has("нога", "ноги", "прис", "squat", "leg", "квад", "стег", "ікр", "икр", "calf", "румун", "станов", "deadlift", "glute")) return "Legs";
  if (has("спин", "тяга", "row", "pull", "підтяг", "подтяг", "біцеп", "бицеп", "curl")) return "Pull";
  if (has("жим", "груд", "chest", "плеч", "shoulder", "tricep", "трицеп", "брусь", "dips", "press")) return "Push";
  if (has("прес", "abs", "crunch", "oblique", "гіперекстензі", "hyperextension")) return "FullBody";
  return "FullBody";
}

function isCandidateForFocus(candidateFocus, workoutFocus) {
  if (workoutFocus === "Upper") return ["Upper", "Push", "Pull", "FullBody"].includes(candidateFocus);
  if (workoutFocus === "Lower" || workoutFocus === "Legs") return ["Lower", "Legs", "FullBody"].includes(candidateFocus);
  if (workoutFocus === "Push") return candidateFocus === "Push" || candidateFocus === "FullBody";
  if (workoutFocus === "Pull") return candidateFocus === "Pull" || candidateFocus === "FullBody";
  return true;
}

function chooseMostNeglectedFocus(history) {
  const focuses = ["Push", "Pull", "Legs", "FullBody"];
  const latestByFocus = Object.fromEntries(focuses.map(focus => [focus, 0]));
  history.forEach(set => {
    const focus = classifyExercise(set.exerciseName);
    latestByFocus[focus] = Math.max(latestByFocus[focus] || 0, set.session.startedAt);
  });
  return focuses.sort((a, b) => latestByFocus[a] - latestByFocus[b])[0] || "FullBody";
}

function copyDraftSet(blockIndex, plus) {
  const block = modal.draft.blocks[blockIndex];
  const last = block.sets.at(-1) || { weight: "", reps: 8 };
  const weight = Number(String(last.weight).replace(",", "."));
  block.sets.push({ weight: Number.isFinite(weight) ? weight + (plus ? 2.5 : 0) : last.weight, reps: last.reps });
}

function applyLast(blockIndex) {
  const block = modal.draft.blocks[blockIndex];
  const weight = lastWeightFor(block.exerciseName);
  if (weight == null) return;
  block.sets = block.sets.map(set => ({ ...set, weight }));
  render();
}

function applySmart(blockIndex) {
  const block = modal.draft.blocks[blockIndex];
  block.sets = smartRecommendation(block.exerciseName).sets.map(set => ({ weight: set.weight ?? "", reps: set.reps }));
  render();
}

function saveWorkout() {
  const draft = modal?.draft;
  if (!draft) return;
  const sets = [];
  draft.blocks.forEach(block => {
    const exerciseName = block.exerciseName.trim();
    if (!exerciseName) return;
    ensureExercise(exerciseName);
    block.sets.forEach((set, index) => {
      const weight = Number(String(set.weight).replace(",", "."));
      const reps = Number.parseInt(set.reps, 10);
      if (Number.isFinite(weight) && weight >= 0 && reps > 0) sets.push({ id: uid(), exerciseName, weight, reps, orderIndex: index });
    });
  });
  if (!sets.length) return showToast(tx("Please fill all selected exercises and sets.", "Заповни всі вибрані вправи й підходи."));
  const id = uid();
  state.sessions.push({ id, startedAt: draft.startedAt || Date.now(), note: draft.note || "", sets });
  saveState();
  modal = null;
  nav = [{ name: "workouts" }, { name: "summary", id }];
  render();
}

function quickAddExercise() {
  const session = state.sessions.find(s => s.id === route().id);
  const ex = state.exercises.find(e => e.id === Number(document.querySelector("#quick-add")?.value));
  if (!session || !ex) return;
  session.sets.push({ id: uid(), exerciseName: ex.name, weight: 0, reps: 8, orderIndex: 0 });
  saveState();
  render();
}

function detailAddSet(sessionId, name) {
  const session = state.sessions.find(s => s.id === sessionId);
  if (!session) return;
  const last = session.sets.filter(s => s.exerciseName === name).at(-1) || allSets().filter(s => s.exerciseName === name).at(-1);
  session.sets.push({ id: uid(), exerciseName: name, weight: last?.weight || 0, reps: last?.reps || 8, orderIndex: session.sets.filter(s => s.exerciseName === name).length });
  state.timers ||= {};
  state.timers[`${sessionId}:${name}`] = Date.now() + 90000;
  saveState();
  render();
}

function openEditSet(id) {
  const set = findSet(id);
  if (set) {
    modal = { type: "edit-set", set };
    render();
  }
}

function applyEditSet(id) {
  const set = findSet(id);
  if (!set) return;
  const weight = Number(String(document.querySelector("#edit-weight").value).replace(",", "."));
  const reps = Number.parseInt(document.querySelector("#edit-reps").value, 10);
  if (!Number.isFinite(weight) || weight < 0 || reps <= 0) return showToast(tx("Enter valid reps and optional weight.", "Введи коректні повтори й вагу."));
  set.weight = weight;
  set.reps = reps;
  saveState();
  modal = null;
  render();
}

function deleteSet(id) {
  for (const session of state.sessions) {
    const index = session.sets.findIndex(s => s.id === id);
    if (index >= 0) {
      session.sets.splice(index, 1);
      saveState();
      showToast(tx("Set deleted.", "Підхід видалено."));
      return render();
    }
  }
}

function findSet(id) {
  return state.sessions.flatMap(s => s.sets).find(s => s.id === id);
}

function saveExercise() {
  const name = document.querySelector("#new-exercise-name")?.value.trim();
  if (!name) return showToast(tx("Enter exercise name.", "Введи назву вправи."));
  ensureExercise(name);
  saveState();
  render();
}

function ensureExercise(name) {
  if (!state.exercises.some(e => e.name.toLowerCase() === name.toLowerCase())) {
    state.exercises.push({ id: uid(), name });
    state.exercises.sort((a, b) => a.name.localeCompare(b.name));
  }
}

function applyRename(id) {
  const exercise = state.exercises.find(ex => ex.id === id);
  const next = document.querySelector("#rename-name")?.value.trim();
  if (!exercise || !next) return;
  const old = exercise.name;
  exercise.name = next;
  state.sessions.forEach(session => session.sets.forEach(set => { if (set.exerciseName === old) set.exerciseName = next; }));
  state.mappings[next.toLowerCase()] = state.mappings[old.toLowerCase()] || [];
  delete state.mappings[old.toLowerCase()];
  saveState();
  modal = null;
  render();
}

function deleteExercise(id) {
  const exercise = state.exercises.find(ex => ex.id === id);
  if (!exercise) return;
  if (state.sessions.some(session => session.sets.some(set => set.exerciseName === exercise.name))) return showToast("Exercise is used in workouts.");
  state.exercises = state.exercises.filter(ex => ex.id !== id);
  saveState();
  render();
}

function saveMapping(name) {
  const ids = [...document.querySelectorAll(".mapping-grid .selected")].map(el => el.dataset.id);
  state.mappings[name.toLowerCase()] = ids;
  saveState();
  modal = null;
  render();
}

function exportPayload(diagnostics) {
  const payload = {
    schemaVersion: 2,
    exportedAt: Date.now(),
    source: diagnostics ? "gym-pwa-diagnostics" : "gym-pwa",
    exercises: state.exercises,
    sessions: state.sessions.map(session => ({
      id: session.id,
      date: session.startedAt,
      startedAt: session.startedAt,
      note: session.note,
      exercises: [...new Set(session.sets.map(s => s.exerciseName))].map(name => ({ name, sets: session.sets.filter(s => s.exerciseName === name) })),
      sets: session.sets
    })),
    exerciseCatalog: state.exercises.map(ex => ex.name),
    mappings: state.mappings,
    profile: state.profile
  };
  if (diagnostics) payload.summary = { exerciseCount: state.exercises.length, sessionCount: state.sessions.length, setCount: allSets().length, totalVolume: totalVolume() };
  return JSON.stringify(payload, null, 2);
}

function applyImport() {
  try {
    const parsed = JSON.parse(document.querySelector("#import-json").value);
    state.exercises = parsed.exercises || (parsed.exerciseCatalog || []).map((name, index) => ({ id: index + 1, name }));
    state.sessions = normalizeSessions(parsed.sessions || []);
    state.mappings = { ...defaultMappings, ...(parsed.mappings || {}) };
    state.profile = { ...state.profile, ...(parsed.profile || {}) };
    saveState();
    modal = null;
    goRoot("workouts");
    showToast(tx("Backup imported.", "Бекап імпортовано."));
  } catch {
    showToast(tx("Invalid JSON.", "Некоректний JSON."));
  }
}

function downloadJson(json) {
  const blob = new Blob([json], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `gym-backup-${new Date().toISOString().slice(0, 10)}.json`;
  a.click();
  URL.revokeObjectURL(url);
}

function printReport() {
  const win = window.open("", "_blank");
  const data = JSON.parse(modal.json);
  win.document.write(`<title>GymApp diagnostics</title><style>body{font-family:system-ui;padding:32px;color:#14202c}h1{margin-bottom:4px}pre{white-space:pre-wrap;background:#f4f1ec;padding:16px}</style><h1>GymApp diagnostics report</h1><p>Exported: ${new Date(data.exportedAt).toLocaleString()}</p><h2>Summary</h2><p>Exercises: ${data.summary?.exerciseCount ?? data.exercises.length}</p><p>Workouts: ${data.summary?.sessionCount ?? data.sessions.length}</p><p>Sets: ${data.summary?.setCount ?? allSets().length}</p><h2>Raw JSON</h2><pre>${escapeHtml(modal.json)}</pre>`);
  win.document.close();
  win.print();
}

function hasWorkoutToday() {
  const today = new Date().toDateString();
  return state.sessions.some(s => new Date(s.startedAt).toDateString() === today) ? 1 : 0;
}

function setsToday() {
  const today = new Date().toDateString();
  return allSets(state.sessions.filter(s => new Date(s.startedAt).toDateString() === today)).length;
}

function workoutsThisWeek() {
  const start = startOfWeek();
  return state.sessions.filter(s => s.startedAt >= start).length;
}

function volumeThisWeek() {
  const start = startOfWeek();
  return totalVolume(state.sessions.filter(s => s.startedAt >= start));
}

function startOfWeek() {
  const now = new Date();
  const start = new Date(now);
  start.setDate(now.getDate() - ((now.getDay() + 6) % 7));
  start.setHours(0, 0, 0, 0);
  return start.getTime();
}

function daysBetween(fromMillis, toMillis) {
  const from = new Date(fromMillis);
  const to = new Date(toMillis);
  from.setHours(0, 0, 0, 0);
  to.setHours(0, 0, 0, 0);
  return Math.max(0, Math.round((to - from) / 86400000));
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function roundToNearestHalf(value) {
  return Math.round(value * 2) / 2;
}

function timerRemaining(key) {
  const target = state.timers?.[key];
  if (!target) return 0;
  return Math.max(0, Math.ceil((target - Date.now()) / 1000));
}

function startTimerTicker() {
  clearInterval(timerInterval);
  if (Object.values(state.timers || {}).some(target => target > Date.now())) {
    timerInterval = setInterval(render, 1000);
  }
}

function formatTimer(seconds) {
  return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
}

function barRow(label, value, max, detail) {
  return `<div class="bar-row"><span>${escapeHtml(label)}</span><div class="bar-track"><div class="bar-fill" style="width:${Math.min(100, value / max * 100)}%"></div></div><span class="muted">${escapeHtml(detail)}</span></div>`;
}

function titleCase(value) {
  return String(value).replace(/\w\S*/g, word => word[0].toUpperCase() + word.slice(1).toLowerCase());
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#039;" }[char]));
}

function escapeAttr(value) {
  return escapeHtml(value).replace(/`/g, "&#096;");
}

function showToast(message) {
  clearTimeout(toastTimer);
  requestAnimationFrame(() => {
    const toast = document.querySelector("#toast");
    if (!toast) return;
    toast.textContent = message;
    toast.classList.remove("hidden");
    toastTimer = setTimeout(() => toast.classList.add("hidden"), 2400);
  });
}

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => navigator.serviceWorker.register("./sw.js").catch(() => {}));
}

render();
