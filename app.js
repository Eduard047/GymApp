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
    note: "Нотатка", trainingProfile: "Профіль тренувань", smartCoach: "Smart Coach", generateSmart: "Згенерувати тренування",
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
  return new Intl.DateTimeFormat(state.language === "uk" ? "uk-UA" : undefined, options).format(new Date(value));
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
  return Math.round(totalVolume(sessions) / 35) + allSets(sessions).length * 8 + sessions.length * 35;
}

function totalXp() {
  return xpForSessions(state.sessions) + completedMissions().reduce((sum, mission) => sum + mission.reward, 0);
}

function levelFromXp(value = totalXp()) {
  return Math.max(1, Math.floor(value / 500) + 1);
}

function rankTitle(value = totalXp()) {
  return rankLadder().filter(rank => value >= rank.xp).at(-1)?.title || "Rookie";
}

function rankLadder() {
  return [
    ["Rookie", 1, 0], ["Regular", 2, 500], ["Iron Builder", 4, 1500], ["Strength Adept", 7, 3200],
    ["Barbell Veteran", 10, 5600], ["Peak Chaser", 14, 9000], ["Elite Lifter", 18, 13500], ["Legend", 24, 21000]
  ].map(([title, level, xp], id) => ({ id, title, level, xp }));
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
  return `
    ${monthSwitcher()}
    <section class="segmented panel compact">
      <button class="${overviewMode === "overview" ? "selected" : ""}" data-action="overview-mode" data-mode="overview"><strong>${t("overview")}</strong><span>Progress, goals, achievements</span></button>
      <button class="${overviewMode === "list" ? "selected" : ""}" data-action="overview-mode" data-mode="list"><strong>${t("workoutList")}</strong><span>${sessions.length} saved sessions</span></button>
    </section>
    ${overviewMode === "overview" ? overviewCards(sessions) : ""}
    <div class="section-title"><div><h2>${t("workoutList")}</h2><p>${sessions.length ? `${sessions.length} saved sessions` : "New sessions will appear here as soon as you log them."}</p></div><button class="button" data-action="open-add">${svg("add", "small-icon")}${t("addWorkout")}</button></div>
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
  const level = levelFromXp(xp);
  const into = xp % 500;
  const next = rankLadder().find(rank => rank.xp > xp)?.title || "Max title";
  return `<section class="hero-panel">
    <div class="eyebrow">${t("soloProgress")}</div>
    <div class="hero-split"><div><span class="pill hero-pill">LEVEL ${level}</span><h2>${rankTitle(xp)}</h2><p>${into} / 500 XP to next level</p></div><div class="hero-stat"><span>TOTAL XP</span><strong>${xp}</strong><small>earned</small></div></div>
    <div class="progress"><span style="width:${into / 5}%"></span></div>
    <div class="metric-grid three"><div><span>Month XP</span><strong>${xpForSessions(selectedMonthSessions())} XP</strong></div><div><span>Next title</span><strong>${next}</strong></div><div><span>Week streak</span><strong>${weeklyStreak()} wk</strong></div></div>
  </section>`;
}

function dashboardCard(sessions) {
  const sets = allSets(sessions);
  const avg = sets.length ? totalVolume(sessions) / sets.length : 0;
  return `<section class="hero-panel">
    <h2>${t("monthlySnapshot")}</h2><p>Track consistency, output and intensity at a glance.</p>
    <div class="metric-grid"><div><span>Workouts</span><strong>${sessions.length}</strong></div><div><span>Streak</span><strong>${weeklyStreak()} wk</strong></div><div><span>Total Volume</span><strong>${Math.round(totalVolume(sessions))}</strong></div><div><span>Avg / Set</span><strong>${avg.toFixed(1)}</strong></div></div>
  </section>`;
}

function workoutItem(session) {
  const summary = sessionSummary(session);
  return `<article class="workout-item clickable" data-action="open-detail" data-id="${session.id}">
    <div class="workout-head"><div><h3 class="workout-title">Workout ${fmtDate(session.startedAt)}</h3><span class="muted">${session.note ? `Note: ${escapeHtml(session.note)}` : "No note"}</span></div><span class="chip">Sets: ${summary.sets}</span></div>
    <div class="chip-row"><span class="chip">Exercises: ${summary.exercises}</span><span class="chip">Volume: ${Math.round(summary.volume)}</span>${[...new Set(session.sets.map(set => set.exerciseName))].slice(0, 5).map(name => `<span class="chip">${escapeHtml(name)}</span>`).join("")}</div>
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
  return `<section class="panel"><div class="section-title"><div><h2>${t("heatmap")}</h2><p>${fmtDate(d.getTime(), { month: "long", year: "numeric" })}</p></div><span class="pill">${byDay.size} active days</span></div>
    <div class="metric-grid"><div><span>Sessions</span><strong>${monthSessions.length}</strong></div><div><span>Volume</span><strong>${Math.round(totalVolume(monthSessions))}</strong></div></div>
    <div class="heatmap-grid">${cells.map(day => `<button class="heat-cell ${day ? "" : "outside"}" style="${day ? `--i:${(byDay.get(day) || 0) / max}` : ""}" title="${day || ""}">${day || ""}</button>`).join("")}</div>
    <div class="legend"><span>Less</span><i></i><i></i><i></i><i></i><span>More</span></div>
  </section>`;
}

function muscleMapCard() {
  const data = muscleStats();
  const max = Math.max(1, ...data.map(item => item.load));
  const top = data.filter(item => item.load > 0).sort((a, b) => b.load - a.load);
  const selected = selectedMuscle ? top.find(item => item.id === selectedMuscle) : null;
  const unmapped = groupedExercises().filter(ex => !mappingFor(ex.name).length);
  return `<section class="panel">
    <div class="section-title"><div><h2>${t("muscleMap")}</h2><p>Colors show which muscle groups carried the most load.</p></div><span class="pill">${musclePeriod}</span></div>
    <div class="period-tabs">${["all", "month", "week"].map(period => `<button class="${musclePeriod === period ? "selected" : ""}" data-action="muscle-period" data-period="${period}">${period === "all" ? "All time" : titleCase(period)}</button>`).join("")}</div>
    <div class="metric-grid three"><div><span>Sets</span><strong>${allSets(periodSessions()).length}</strong></div><div><span>Load</span><strong>${Math.round(totalVolume(periodSessions()))}</strong></div><div><span>Mapped</span><strong>${mappedCount()}/${state.exercises.length}</strong></div></div>
    <div class="body-map">${muscles.map(([id, label]) => {
      const item = data.find(x => x.id === id) || { load: 0 };
      return `<button class="muscle-tile ${selectedMuscle === id ? "selected" : ""}" data-action="select-muscle" data-id="${id}" style="--i:${item.load / max}"><span>${label}</span><small>${Math.round(item.load)}</small></button>`;
    }).join("")}</div>
    ${selected ? `<div class="subpanel"><h3>${selected.label} loaded by</h3>${selected.exercises.map(ex => `<div class="row-line"><span>${escapeHtml(ex.name)}</span><button class="button ghost mini" data-action="map-exercise" data-name="${escapeAttr(ex.name)}">Map</button></div>`).join("")}</div>` : ""}
    ${unmapped.length ? `<div class="subpanel"><h3>Unmapped / new exercises</h3>${unmapped.map(ex => `<div class="row-line"><span>${escapeHtml(ex.name)} · ${ex.sets} sets</span><button class="button secondary mini" data-action="map-exercise" data-name="${escapeAttr(ex.name)}">Map</button></div>`).join("")}</div>` : ""}
    <h3>Top muscle groups</h3><div class="bars">${top.length ? top.slice(0, 8).map(item => barRow(item.label, item.load, max, `${item.sets} sets · ${item.sessions.size} sessions`)).join("") : `<div class="empty">Log sets to light up the body map.</div>`}</div>
  </section>`;
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
  return state.mappings[name.trim().toLowerCase()] || [];
}

function muscleStats(sessions = periodSessions()) {
  const map = new Map(muscles.map(([id, label]) => [id, { id, label, load: 0, sets: 0, sessions: new Set(), exercises: [] }]));
  allSets(sessions).forEach(set => {
    const ids = mappingFor(set.exerciseName);
    ids.forEach(id => {
      const item = map.get(id);
      if (!item) return;
      const load = Number(set.weight || 0) * Number(set.reps || 0);
      item.load += load / ids.length;
      item.sets += 1;
      item.sessions.add(set.session.id);
      if (!item.exercises.some(ex => ex.name === set.exerciseName)) item.exercises.push({ name: set.exerciseName });
    });
  });
  return [...map.values()];
}

function recommendationsCard() {
  const recs = trainingRecommendations();
  return `<section class="panel highlighted"><h2>${t("recommendations")}</h2><p class="muted">Based on muscle load and recent training gaps.</p>
    <div class="list-gap">${recs.map(rec => `<div class="subpanel row-line"><div><strong>${rec.title}</strong><p>${rec.supporting}</p></div><span class="pill">${rec.priority}</span></div>`).join("")}</div>
  </section>`;
}

function trainingRecommendations() {
  const stats = muscleStats(state.sessions).sort((a, b) => a.load - b.load);
  const stale = stats.filter(item => item.load > 0).slice(0, 3);
  const last = [...state.sessions].sort((a, b) => b.startedAt - a.startedAt)[0];
  return [
    stale[0] ? { title: `Bring up ${stale[0].label}`, supporting: "This muscle group is behind your current total load.", priority: "High" } : { title: "Starter plan", supporting: "Add your first workout to unlock smarter recommendations.", priority: "New" },
    { title: nextWorkoutType(last), supporting: "Suggested from your recent exercise pattern and training profile.", priority: "Next" }
  ];
}

function nextWorkoutType(last) {
  const note = last?.note?.toLowerCase() || "";
  if (note.includes("push")) return "Next suggested workout: pull";
  if (note.includes("pull")) return "Next suggested workout: legs";
  if (note.includes("leg")) return "Next suggested workout: push";
  return `Next suggested workout: ${state.profile.split}`;
}

function achievementsCard() {
  const achievements = [
    achievement("First Baseline", "Save your first workout.", state.sessions.length, 1),
    achievement("Volume Builder", "Reach 10,000 total volume.", totalVolume(), 10000),
    achievement("Set Collector", "Log 100 total sets.", allSets().length, 100),
    achievement("Consistency", "Build a 7 day streak.", streakDays(), 7)
  ];
  return `<section class="panel highlighted"><h2>${t("achievements")}</h2><p class="muted">Recent unlocks and the next solo milestones.</p>
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
      <h2>Build todays session</h2><p>Log your plan fast and keep momentum with smart set shortcuts.</p>
      <div class="metric-grid"><div><span>Date</span><strong>${fmtDate(draft.startedAt)}</strong></div><div><span>Exercises</span><strong>${selectedCount}</strong></div><div><span>Sets</span><strong>${setCount}</strong></div></div>
      <button class="button hero-button" data-action="repeat-latest" ${state.sessions.length ? "" : "disabled"}>${svg("copy", "small-icon")}${t("repeatLast")}</button>
      <button class="button ghost hero-button" data-action="template-picker" ${state.sessions.length ? "" : "disabled"}>${svg("copy", "small-icon")}${t("copyWorkout")}</button>
    </section>
    <section class="panel"><h2>${t("note")}</h2><textarea data-draft="note" placeholder="Push day, pull day, deload...">${escapeHtml(draft.note)}</textarea><div class="chip-row">${["Push day", "Pull day", "Leg day", "Upper body", "Lower body", "Deload"].map(note => `<button class="chip buttonlike" data-action="note-template" data-note="${note}">${note}</button>`).join("")}</div></section>
    ${trainingProfilePanel()}
    <section class="draft-list">${draft.blocks.map((block, index) => draftBlock(block, index)).join("")}</section>
    <button class="button secondary full" data-action="add-block">${svg("add", "small-icon")}${t("addExercise")}</button>
    <section class="panel"><p class="muted">Check your sets, then save to move straight into workout details.</p><button class="button ghost full" data-action="sync-watch">${t("syncWatch")}</button><button class="button full" data-action="save-workout">${svg("save", "small-icon")}${t("saveWorkout")}</button></section>`;
}

function trainingProfilePanel() {
  const p = state.profile;
  return `<section class="panel highlighted"><div class="section-title"><div><h2>${t("trainingProfile")}</h2><p>Smart Coach uses this to match your plan, goal and recovery.</p></div>${svg("auto", "small-icon")}</div>
    ${chipSelect("split", ["Upper / Lower", "Full Body", "Push Pull Legs", "Custom"], p.split)}
    ${chipSelect("days", [2, 3, 4, 5, 6].map(v => `${v} / week`), `${p.days} / week`)}
    ${chipSelect("goal", ["Aesthetic Cut", "Muscle Gain", "Strength", "Balanced"], p.goal)}
    ${chipSelect("calories", ["Deficit", "Maintenance", "Surplus"], p.calories)}
    <button class="button full" data-action="generate-smart">${svg("auto", "small-icon")}${t("generateSmart")}</button>
  </section>`;
}

function chipSelect(field, options, selected) {
  return `<div class="chip-row">${options.map(option => `<button class="chip buttonlike ${option === selected ? "selected" : ""}" data-action="profile" data-field="${field}" data-value="${option}">${option}</button>`).join("")}</div>`;
}

function draftBlock(block, blockIndex) {
  const lastWeight = lastWeightFor(block.exerciseName);
  const rec = block.exerciseName ? smartRecommendation(block.exerciseName) : null;
  return `<section class="draft-exercise panel highlighted"><div class="row-head"><h2>Exercise ${blockIndex + 1}</h2><button class="icon-button" data-action="remove-block" data-block="${blockIndex}">${svg("delete")}</button></div>
    <label>Exercise<input list="exercise-options" data-block="${blockIndex}" data-field="exerciseName" value="${escapeAttr(block.exerciseName)}" placeholder="Select exercise"></label>
    <datalist id="exercise-options">${state.exercises.map(ex => `<option value="${escapeAttr(ex.name)}"></option>`).join("")}</datalist>
    ${lastWeight != null ? `<div class="row-line"><strong>Last: ${lastWeight.toFixed(1)} kg</strong><button class="button ghost mini" data-action="apply-last" data-block="${blockIndex}">${t("useLast")}</button></div>` : ""}
    ${rec ? smartPanel(rec, blockIndex) : ""}
    <div class="actions"><button class="button ghost" data-action="add-set" data-block="${blockIndex}">${t("addSet")}</button><button class="button ghost" data-action="copy-set" data-block="${blockIndex}">${t("copyLast")}</button><button class="button ghost" data-action="plus-set" data-block="${blockIndex}">${t("copyPlus")}</button></div>
    ${block.sets.map((set, setIndex) => `<div class="set-row"><span>Set ${setIndex + 1}</span><input inputmode="decimal" aria-label="Weight" data-block="${blockIndex}" data-set="${setIndex}" data-field="weight" value="${escapeAttr(set.weight)}" placeholder="kg"><input inputmode="numeric" aria-label="Reps" data-block="${blockIndex}" data-set="${setIndex}" data-field="reps" value="${escapeAttr(set.reps)}"><button class="icon-button" data-action="remove-set" data-block="${blockIndex}" data-set="${setIndex}">${svg("delete")}</button></div>`).join("")}
  </section>`;
}

function smartPanel(rec, blockIndex) {
  return `<div class="subpanel smart"><div class="row-head"><div><strong>${t("smartCoach")}</strong><p>${rec.kind}</p></div>${svg("auto", "small-icon")}</div><p>${rec.sets.map(s => `${s.weight.toFixed(1)} kg x ${s.reps}`).join(" | ")}</p><div class="progress"><span style="width:${rec.confidence * 100}%"></span></div><small>Confidence ${Math.round(rec.confidence * 100)}%</small><p class="muted">${rec.reason}</p><button class="button full" data-action="apply-smart" data-block="${blockIndex}">${t("applySmart")}</button></div>`;
}

function createDraft(source) {
  const blocks = source ? [...new Set(source.sets.map(s => s.exerciseName))].map(name => ({ exerciseName: name, sets: source.sets.filter(s => s.exerciseName === name).map(s => ({ weight: s.weight, reps: s.reps })) })) : [{ exerciseName: "", sets: [{ weight: "", reps: 8 }] }];
  return { startedAt: Date.now(), note: source?.note || "", blocks };
}

function smartRecommendation(name) {
  const history = allSets().filter(set => set.exerciseName.toLowerCase() === name.toLowerCase()).sort((a, b) => b.session.startedAt - a.session.startedAt);
  if (!history.length) return { kind: "Starter plan: build clean reps and save the first baseline.", sets: [{ weight: 20, reps: 10 }, { weight: 20, reps: 10 }, { weight: 20, reps: 10 }], confidence: 0.62, reason: "No saved history yet, so this starts with a clean baseline." };
  const best = Math.max(...history.map(s => s.weight));
  const recent = history.slice(0, 3);
  const avgReps = recent.reduce((sum, s) => sum + s.reps, 0) / recent.length;
  const weight = avgReps >= 8 ? best + 2.5 : Math.max(0, best - 2.5);
  return { kind: avgReps >= 8 ? "Progression plan: small load increase with controlled reps." : "Recovery plan: reduce load because the last result looked strained.", sets: [{ weight, reps: 8 }, { weight, reps: 8 }, { weight, reps: 8 }], confidence: 0.78, reason: avgReps >= 8 ? "Last session was stable across the sets." : "Recent reps dipped, so the plan stays conservative." };
}

function lastWeightFor(name) {
  if (!name) return null;
  const set = allSets().filter(s => s.exerciseName.toLowerCase() === name.toLowerCase()).sort((a, b) => b.session.startedAt - a.session.startedAt)[0];
  return set ? Number(set.weight) : null;
}

function detailScreen(id) {
  const session = state.sessions.find(s => s.id === id);
  if (!session) return `<div class="empty">Workout not found.</div>`;
  const grouped = [...new Set(session.sets.map(s => s.exerciseName))].map(name => ({ name, sets: session.sets.filter(s => s.exerciseName === name) }));
  const available = state.exercises.filter(ex => !grouped.some(g => g.name === ex.name));
  return `<section class="panel"><h2>${fmtDate(session.startedAt)}</h2><p>${session.note || "No note"}</p></section>
    <section class="panel"><div class="section-title"><h2>Add Exercise to This Workout</h2></div>${available.length ? `<select id="quick-add">${available.map(ex => `<option value="${ex.id}">${escapeHtml(ex.name)}</option>`).join("")}</select><button class="button full" data-action="quick-add-exercise">Add to Workout</button>` : `<p class="muted">All saved exercises are already in this workout.</p>`}</section>
    ${grouped.map(group => exerciseDetailCard(session, group)).join("")}
    <button class="fab" data-action="finish-workout" data-id="${session.id}">${svg("check", "small-icon")}${t("finishWorkout")}</button>`;
}

function exerciseDetailCard(session, group) {
  const key = `${session.id}:${group.name}`;
  const remaining = timerRemaining(key);
  return `<section class="panel highlighted"><div class="row-head"><h2>${escapeHtml(group.name)}</h2>${isPr(session, group.name) ? `<span class="pill">${svg("trophy", "small-icon")}New PR</span>` : ""}</div>
    <div class="timer-row"><div><strong>Exercise Rest</strong><span>${remaining > 0 ? formatTimer(remaining) : "Ready"}</span></div><div class="actions"><button class="button ghost mini" data-action="timer" data-key="${key}" data-seconds="60">60s</button><button class="button ghost mini" data-action="timer" data-key="${key}" data-seconds="90">90s</button><button class="button ghost mini" data-action="timer" data-key="${key}" data-seconds="180">180s</button><button class="button ghost mini" data-action="timer-stop" data-key="${key}" ${remaining ? "" : "disabled"}>Stop</button></div></div>
    <div class="table"><div class="table-head"><span>Set</span><span>Weight (kg)</span><span>Reps</span><span></span></div>${group.sets.map((set, i) => `<div class="table-row"><span>Set ${i + 1}</span><span>${Number(set.weight).toFixed(1)}</span><span>${set.reps}</span><span><button class="icon-button" data-action="edit-set" data-id="${set.id}">${svg("edit")}</button><button class="icon-button" data-action="delete-set" data-id="${set.id}">${svg("delete")}</button></span></div>`).join("")}</div>
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
  if (!session) return `<div class="empty">Workout summary unavailable.</div>`;
  const before = state.sessions.filter(s => s.startedAt < session.startedAt);
  const summary = sessionSummary(session);
  const xpGain = xpForSessions([session]);
  const xpTotal = totalXp();
  const records = [...new Set(session.sets.map(s => s.exerciseName))].map(name => {
    const prev = Math.max(0, ...allSets(before).filter(s => s.exerciseName === name).map(s => s.weight));
    const now = Math.max(0, ...session.sets.filter(s => s.exerciseName === name).map(s => s.weight));
    return now > prev ? { name, prev, now } : null;
  }).filter(Boolean);
  const mStats = muscleStats([session]).filter(m => m.load > 0).sort((a, b) => b.load - a.load);
  return `<section class="hero-panel"><h2>${t("workoutComplete")}</h2><p>${fmtDate(session.startedAt)}</p><div class="metric-grid"><div><span>XP gained</span><strong>+${xpGain} XP</strong></div><div><span>Level</span><strong>${levelFromXp(xpTotal)}</strong></div></div></section>
    <section class="metric-grid post"><div><span>Current title</span><strong>${rankTitle(xpTotal)}</strong></div><div><span>Streak</span><strong>${streakDays()} d</strong></div><div><span>Exercises</span><strong>${summary.exercises}</strong></div><div><span>Sets</span><strong>${summary.sets}</strong></div><div><span>Volume</span><strong>${Math.round(summary.volume)}</strong></div></section>
    <section class="panel"><h2>${t("impact")}</h2><p class="muted">${mStats[0] ? `Most loaded today: ${mStats[0].label}` : "Mapped muscle load will appear after sets are saved."}</p>${mStats.slice(0, 5).map(m => barRow(m.label, m.load, mStats[0]?.load || 1, `${Math.round(m.load)} load · ${m.sets} sets`)).join("")}</section>
    ${records.length ? `<section class="panel highlighted"><h2>${t("personalRecords")}</h2>${records.map(r => `<div class="row-line"><div><strong>${escapeHtml(r.name)}</strong><p>${r.prev ? `Previous best ${r.prev.toFixed(1)} kg` : "First logged best"}</p></div><span class="pill">${r.now.toFixed(1)} kg</span></div>`).join("")}</section>` : ""}
    <section class="panel"><h2>${t("levelProgress")}</h2><p>Level ${levelFromXp(xpTotal)} - ${rankTitle(xpTotal)}</p><div class="progress"><span style="width:${xpTotal % 500 / 5}%"></span></div><div class="row-line"><span>${xpTotal % 500} XP into this level</span><strong>${500 - xpTotal % 500} XP to next</strong></div></section>
    <section class="panel"><h2>${t("momentum")}</h2><p>${streakDays() > 1 ? `Streak extended to ${streakDays()} days.` : "A fresh streak has started."}</p><div class="chip-row"><span class="chip">Logged today</span><span class="chip">Best ${streakDays()} d</span></div></section>
    <div class="actions vertical"><button class="button full" data-action="summary-view" data-id="${session.id}">View workout</button><button class="button ghost full" data-action="summary-done">Back to workouts</button></div>`;
}

function exercisesScreen() {
  return `<section class="panel"><div class="field-row"><input id="new-exercise-name" placeholder="e.g. Bench Press"><button class="button" data-action="save-exercise">${t("addExercise")}</button></div></section>
    <section class="panel"><h2>${t("backup")}</h2><div class="actions"><button class="button ghost" data-action="export-json">${t("exportJson")}</button><button class="button ghost" data-action="import-json">${t("importJson")}</button><button class="button ghost full" data-action="export-diagnostics">${t("diagnostics")}</button></div></section>
    <section class="exercise-list">${state.exercises.length ? state.exercises.map(exerciseRow).join("") : `<div class="empty">No exercises yet.</div>`}</section>`;
}

function exerciseRow(exercise) {
  const stats = groupedExercises().find(g => g.name === exercise.name) || { sets: 0, volume: 0, best: 0, sessions: new Set() };
  return `<article class="exercise-row clickable" data-action="exercise-history" data-id="${exercise.id}"><div><h3>${escapeHtml(exercise.name)}</h3><span class="muted">Sessions: ${stats.sessions.size} · Sets: ${stats.sets} · Volume: ${Math.round(stats.volume)}</span></div><div class="actions"><button class="icon-button" data-action="rename-exercise" data-id="${exercise.id}">${svg("edit")}</button><button class="icon-button" data-action="delete-exercise" data-id="${exercise.id}">${svg("delete")}</button></div></article>`;
}

function progressScreen() {
  const selectedId = state.progressExerciseId || state.exercises[0]?.id;
  const selected = state.exercises.find(ex => ex.id === selectedId);
  if (!selected) return `<div class="empty">No exercises yet.</div>`;
  const history = allSets(selectedMonthSessions()).filter(set => set.exerciseName === selected.name).sort((a, b) => b.session.startedAt - a.session.startedAt);
  const grouped = Object.values(history.reduce((acc, set) => {
    acc[set.session.id] ||= { session: set.session, sets: [] };
    acc[set.session.id].sets.push(set);
    return acc;
  }, {}));
  const best = Math.max(0, ...history.map(s => s.weight));
  const avg = grouped.length ? grouped.reduce((sum, g) => sum + Math.max(...g.sets.map(s => s.weight)), 0) / grouped.length : 0;
  const vol = history.reduce((sum, s) => sum + s.weight * s.reps, 0);
  return `${monthSwitcher()}<section class="panel"><label>Exercise<select id="progress-select" data-action="progress-select">${state.exercises.map(ex => `<option value="${ex.id}" ${ex.id === selectedId ? "selected" : ""}>${escapeHtml(ex.name)}</option>`).join("")}</select></label></section>
    <section class="panel"><h2>Progress Summary</h2><p class="muted">Volume = weight x reps across all completed sets.</p><div class="metric-grid three"><div><span>Sessions</span><strong>${grouped.length}</strong></div><div><span>Total Sets</span><strong>${history.length}</strong></div><div><span>Total Reps</span><strong>${history.reduce((s, x) => s + x.reps, 0)}</strong></div><div><span>Best Weight</span><strong>${best.toFixed(1)} kg</strong></div><div><span>Average Max</span><strong>${avg.toFixed(1)} kg</strong></div><div><span>Total Volume</span><strong>${Math.round(vol)}</strong></div></div></section>
    <section class="panel">${spotlight(selected.name, grouped, best, vol)}</section>
    <section class="panel"><h2>Visual Trends</h2><div class="bars">${grouped.length ? grouped.slice().reverse().map(g => barRow(fmtDate(g.session.startedAt, { day: "numeric", month: "short" }), Math.max(...g.sets.map(s => s.weight)), best || 1, `Vol ${Math.round(g.sets.reduce((sum, s) => sum + s.weight * s.reps, 0))}`)).join("") : `<div class="empty">Add sets to see chart.</div>`}</div></section>
    <section class="workout-list"><h2>Workout History</h2>${grouped.length ? grouped.map(g => progressHistoryCard(g)).join("") : `<div class="empty">No history in this month.</div>`}</section>`;
}

function spotlight(name, grouped, best, vol) {
  return `<h2>${escapeHtml(name)}</h2><div class="metric-grid"><div><span>All-time best</span><strong>${best.toFixed(1)} kg</strong></div><div><span>Consistency</span><strong>${grouped.length} sessions</strong></div><div><span>Peak weight</span><strong>${best.toFixed(1)} kg</strong></div><div><span>Avg volume</span><strong>${grouped.length ? Math.round(vol / grouped.length) : 0}</strong></div></div>`;
}

function progressHistoryCard(group) {
  const volume = group.sets.reduce((sum, s) => sum + s.weight * s.reps, 0);
  return `<article class="workout-item"><h3>${fmtDate(group.session.startedAt)}</h3><div class="chip-row"><span class="chip">Sets: ${group.sets.length}</span><span class="chip">Reps: ${group.sets.reduce((s, x) => s + x.reps, 0)}</span><span class="chip">Volume: ${Math.round(volume)}</span></div><div class="table">${group.sets.map((set, i) => `<div class="table-row"><span>Set ${i + 1}</span><span>${set.weight.toFixed(1)}</span><span>${set.reps}</span><button class="icon-button" data-action="delete-set" data-id="${set.id}">${svg("delete")}</button></div>`).join("")}</div></article>`;
}

function missionsScreen() {
  const missions = missionGroups();
  const all = [...missions.daily, ...missions.weekly, ...missions.monthly];
  const done = all.filter(m => m.done);
  return `<section class="hero-panel"><h2>${t("missions")}</h2><p>Active daily, weekly, and monthly missions rotate from a huge challenge pool.</p><div class="metric-grid"><div><span>Total</span><strong>${all.length}</strong></div><div><span>Completed</span><strong>${done.length}</strong></div><div><span>Open</span><strong>${all.length - done.length}</strong></div><div><span>Progress</span><strong>${done.length}/${all.length}</strong></div></div><p>Mission XP from completed goals: ${done.reduce((s, m) => s + m.reward, 0)}</p></section>
    <section class="panel highlighted clickable" data-action="open-ranks"><div class="section-title"><div><h2>Rank ladder</h2><p>Open the full rank list and check the next unlocks.</p></div><span class="pill">${t("viewRanks")}</span></div><div class="metric-grid"><div><span>Current level</span><strong>${levelFromXp()}</strong></div><div><span>Current title</span><strong>${rankTitle()}</strong></div></div></section>
    ${missionSection(t("daily"), missions.daily)}${missionSection(t("weekly"), missions.weekly)}${missionSection(t("monthly"), missions.monthly)}`;
}

function missionGroups() {
  const month = selectedMonthSessions();
  return {
    daily: [mission("daily_workout", "Log a workout today", hasWorkoutToday(), 1, 120), mission("daily_sets", "Complete 10 sets today", setsToday(), 10, 90)],
    weekly: [mission("weekly_workouts", "Complete 3 workouts this week", workoutsThisWeek(), 3, 300), mission("weekly_volume", "Reach 8,000 weekly volume", volumeThisWeek(), 8000, 260)],
    monthly: [mission("monthly_volume", "Reach 20,000 volume this month", totalVolume(month), 20000, 500), mission("monthly_sets", "Log 80 sets this month", allSets(month).length, 80, 350)]
  };
}

function completedMissions() {
  return Object.values(missionGroups()).flat().filter(m => m.done);
}

function mission(id, title, progress, target, reward) {
  return { id, title, summary: `${Math.round(progress)} / ${target}`, progress, target, reward, done: progress >= target };
}

function missionSection(title, missions) {
  return `<section class="mission-list"><div class="section-title panel compact"><div><h2>${title}</h2><p>Consistency goals for the current period.</p></div><span class="pill">${missions.filter(m => m.done).length}/${missions.length} done</span></div>${missions.map(missionCard).join("")}</section>`;
}

function missionCard(m) {
  return `<article class="mission-row ${m.done ? "highlighted" : ""}"><div class="row-head"><div><h3>${m.title}</h3><p>${m.summary}</p></div><span class="pill">${m.done ? "Completed" : "In progress"}</span></div><div class="chip-row"><span class="chip">+${m.reward} XP</span><span class="chip">${m.summary}</span></div><div class="progress"><span style="width:${Math.min(100, m.progress / m.target * 100)}%"></span></div></article>`;
}

function ranksScreen() {
  const xp = totalXp();
  return `<section class="hero-panel"><h2>${t("ranks")}</h2><p>See every title, its level gate, and the XP needed to unlock it.</p><div class="metric-grid"><div><span>TOTAL XP</span><strong>${xp}</strong></div><div><span>Current level</span><strong>${levelFromXp(xp)}</strong></div></div><p>Current title: ${rankTitle(xp)}</p></section>
    ${rankLadder().map(rank => {
      const unlocked = xp >= rank.xp;
      const current = rank.title === rankTitle(xp);
      return `<section class="panel ${current ? "highlighted" : ""}"><div class="row-head"><div><h2>${rank.title}</h2><p>${current ? "Current" : unlocked ? "Unlocked" : "Locked"}</p></div><span class="pill">${current ? "Current" : unlocked ? "Unlocked" : "Locked"}</span></div><div class="metric-grid"><div><span>Required level</span><strong>${rank.level}</strong></div><div><span>Required total XP</span><strong>${rank.xp}</strong></div></div><div class="progress"><span style="width:${unlocked ? 100 : Math.min(100, xp / rank.xp * 100)}%"></span></div><div class="row-line"><span>${Math.min(xp, rank.xp)} / ${rank.xp} XP</span>${!unlocked ? `<strong>${rank.xp - xp} XP left</strong>` : ""}</div></section>`;
    }).join("")}`;
}

function modalMarkup() {
  if (modal.type === "template") return bottomSheet(`<h2>${t("templatePicker")}</h2>${state.sessions.length ? [...state.sessions].sort((a, b) => b.startedAt - a.startedAt).map(session => `<article class="workout-item"><h3>${fmtDate(session.startedAt)}</h3><p>${sessionSummary(session).exercises} exercises · ${sessionSummary(session).sets} sets · ${Math.round(sessionSummary(session).volume)} volume</p><button class="button full" data-action="copy-template" data-id="${session.id}">${t("copyWorkout")}</button></article>`).join("") : `<p>No previous workouts yet.</p>`}`);
  if (modal.type === "import") return bottomSheet(`<h2>Import backup</h2><textarea id="import-json" placeholder="Paste exported GymApp JSON here"></textarea><button class="button full" data-action="apply-import">Import</button>`);
  if (modal.type === "backup-json") return bottomSheet(`<h2>Backup JSON ready</h2><textarea readonly>${escapeHtml(modal.json)}</textarea><div class="actions"><button class="button" data-action="copy-json">Copy JSON</button><button class="button ghost" data-action="download-json">Download</button></div><button class="button ghost full" data-action="pdf-report">${t("sharePdf")}</button>`);
  if (modal.type === "rename") return bottomSheet(`<h2>${t("rename")}</h2><input id="rename-name" value="${escapeAttr(modal.exercise.name)}"><button class="button full" data-action="apply-rename" data-id="${modal.exercise.id}">Save</button>`);
  if (modal.type === "history") return bottomSheet(exerciseHistoryMarkup(modal.exercise));
  if (modal.type === "map") return bottomSheet(mappingEditor(modal.name));
  if (modal.type === "edit-set") return bottomSheet(`<h2>Edit Set</h2><label>Weight (kg)<input id="edit-weight" value="${modal.set.weight || ""}" inputmode="decimal"></label><label>Reps<input id="edit-reps" value="${modal.set.reps || ""}" inputmode="numeric"></label><button class="button full" data-action="apply-edit-set" data-id="${modal.set.id}">Save</button>`);
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
  return `<h2>${escapeHtml(exercise.name)}</h2><div class="metric-grid three"><div><span>Sessions</span><strong>${groups.length}</strong></div><div><span>Sets</span><strong>${history.length}</strong></div><div><span>Volume</span><strong>${Math.round(history.reduce((s, x) => s + x.weight * x.reps, 0))}</strong></div></div>${groups.length ? groups.map(progressHistoryCard).join("") : `<div class="empty">No history for this exercise yet.</div>`}`;
}

function mappingEditor(name) {
  const current = new Set(mappingFor(name));
  return `<h2>Map "${escapeHtml(name)}"</h2><div class="mapping-grid">${muscles.map(([id, label]) => `<button class="chip buttonlike ${current.has(id) ? "selected" : ""}" data-action="toggle-map" data-id="${id}">${label}</button>`).join("")}</div><button class="button full" data-action="save-map" data-name="${escapeAttr(name)}">Save</button>`;
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
  if (action === "copy-json") return navigator.clipboard?.writeText(modal.json).then(() => showToast("JSON copied."));
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
  const groups = groupedExercises();
  const names = groups.length ? groups.slice(0, 4).map(g => g.name) : ["Bench Press", "Barbell Row", "Squat"];
  modal.draft.blocks = names.map(name => ({ exerciseName: name, sets: smartRecommendation(name).sets.map(s => ({ weight: s.weight, reps: s.reps })) }));
  showToast("Smart workout generated.");
  render();
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
  block.sets = smartRecommendation(block.exerciseName).sets.map(set => ({ weight: set.weight, reps: set.reps }));
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
  if (!sets.length) return showToast("Please fill all selected exercises and sets.");
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
  if (!Number.isFinite(weight) || weight < 0 || reps <= 0) return showToast("Enter valid reps and optional weight.");
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
      showToast("Set deleted.");
      return render();
    }
  }
}

function findSet(id) {
  return state.sessions.flatMap(s => s.sets).find(s => s.id === id);
}

function saveExercise() {
  const name = document.querySelector("#new-exercise-name")?.value.trim();
  if (!name) return showToast("Enter exercise name.");
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
    showToast("Backup imported.");
  } catch {
    showToast("Invalid JSON.");
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
