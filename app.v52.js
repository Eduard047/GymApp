"use strict";

if (window.__GYMAPP_TOP_LEVEL__ !== true || window.top !== window.self) {
  throw new DOMException("GymApp must run in a top-level browsing context.", "SecurityError");
}

const STORAGE_KEY = "gym-pwa-state-v2";
const LEGACY_KEY = "gym-pwa-state-v1";
const AUTH_KEY = "gym-pwa-active-account-v1";
const ACCOUNT_LIST_KEY = "gym-pwa-account-list-v1";
const ACCOUNT_PREFIX = "gym-pwa-account:";
const REMOTE_SESSION_KEY = "gym-pwa-supabase-session-v1";
const AUTH_TRANSACTION_KEY = "gym-pwa-auth-transaction-v1";
const SYNC_BASELINE_PREFIX = "gym-pwa-sync-baseline-v1:";
const LEGACY_GARMIN_DEVICE_TOKEN_KEY = "gym-pwa-garmin-device-token-v1";
const GARMIN_DEVICE_BINDINGS_KEY = "gym-pwa-garmin-device-bindings-v2";
const GARMIN_ENQUEUE_REQUESTS_KEY = "gym-pwa-garmin-enqueue-requests-v1";
const PUBLIC_SITE_URL = "https://gymapptracker.com/";
const SUPPORT_URL = "https://gymapptracker.com/support.html";
const PRIVACY_URL = "https://gymapptracker.com/privacy-policy.html";
const AUTH_REDIRECT_URL = "https://gymapptracker.com/confirmed.html?platform=web";
const GARMIN_STORE_APP_URL = "https://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f";
const CONNECT_IQ_ANDROID_PACKAGE = "com.garmin.connectiq";
const CONNECT_IQ_GOOGLE_PLAY_URL = `https://play.google.com/store/apps/details?id=${CONNECT_IQ_ANDROID_PACKAGE}`;
const GARMIN_STORE_ANDROID_INTENT_URL = `intent://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f#Intent;scheme=https;package=${CONNECT_IQ_ANDROID_PACKAGE};S.browser_fallback_url=${encodeURIComponent(CONNECT_IQ_GOOGLE_PLAY_URL)};end`;
const MAX_REMOTE_RESPONSE_BYTES = 8 * 1024 * 1024;
const MAX_REMOTE_AUTH_RESPONSE_BYTES = 64 * 1024;
const MAX_REMOTE_ERROR_RESPONSE_BYTES = 8 * 1024;
const MAX_REMOTE_RESPONSE_CHUNKS = 4096;
const MAX_LOCAL_ACCOUNT_STORAGE_BYTES = 64 * 1024;
const MAX_AUTH_TRANSACTION_STORAGE_BYTES = 4 * 1024;
const AUTH_TRANSACTION_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const MAX_SYNC_BASELINE_STORAGE_BYTES = 2 * 1024;
const MAX_LOCAL_ACCOUNTS = 20;
const MAX_ACCOUNT_NAME_LENGTH = 64;
const LOCAL_ACCOUNT_ID_VERSION = 2;
const LOCAL_ACCOUNT_ID_PATTERN = /^local-v2-[a-f0-9]{32}$/;
const MAX_GARMIN_BINDING_STORAGE_BYTES = 64 * 1024;
const MAX_GARMIN_BINDINGS = 20;
const MAX_GARMIN_ENQUEUE_STORAGE_BYTES = 512 * 1024;
const MAX_GARMIN_ENQUEUE_REQUESTS = 4;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
// Keep v2 until a newly signed Connect IQ binary is actually releasable.
// The v3 parser/request path is intentionally dormant for that coordinated cutover.
const GARMIN_CAPABILITY_VERSION = 2;
const GARMIN_LEGACY_CAPABILITY_PATTERN = /^[a-f0-9]{64}$/;
const GARMIN_CAPABILITY_PATTERN = /^g3\.([a-f0-9]{64})\.([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.([a-f0-9]{64})\.([a-f0-9]{64})$/;
const UUID_V4_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const app = document.querySelector("#app");

const icons = {
  add: "M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z",
  auto: "M12 3l1.7 5.3L19 10l-5.3 1.7L12 17l-1.7-5.3L5 10l5.3-1.7zM19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z",
  back: "M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z",
  chart: "M4 19V5M8 17v-5M13 17V8M18 17v-9M3 19h18",
  check: "M20 6 9 17l-5-5",
  checkCircle: "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z",
  close: "M18 6 6 18M6 6l12 12",
  copy: "M8 8h11v11H8zM5 16H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h11a1 1 0 0 1 1 1v1",
  delete: "M3 6h18M8 6V4h8v2M6 6l1 15h10l1-15",
  download: "M12 3v12m0 0 5-5m-5 5-5-5M4 21h16",
  edit: "M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z",
  emojiEvents: "M19 5h-2V3H7v2H5C3.9 5 3 5.9 3 7v1c0 2.55 1.92 4.63 4.39 4.94.63 1.5 1.98 2.63 3.61 2.96V19H7v2h10v-2h-4v-3.1c1.63-.33 2.98-1.46 3.61-2.96C19.08 12.63 21 10.55 21 8V7c0-1.1-.9-2-2-2zM5 8V7h2v3.82C5.84 10.4 5 9.3 5 8zm14 0c0 1.3-.84 2.4-2 2.82V7h2v1z",
  fire: "M12 22c4 0 7-3 7-7 0-4-3-7-5-10 0 4-2 5-4 7-1-2-1-4 0-6-3 2-5 5-5 9 0 4 3 6 7 6z",
  fitness: "M20.57 14.86 22 13.43 20.57 12 17 15.57 8.43 7 12 3.43 10.57 2 9.14 3.43 7.71 2 5.57 4.14 4.14 2.71 2.71 4.14l1.43 1.43L2 7.71l1.43 1.43L2 10.57 3.43 12 7 8.43 15.57 17 12 20.57 13.43 22l1.43-1.43L16.29 22l2.14-2.14 1.43 1.43 1.43-1.43-1.43-1.43L22 16.29z",
  heart: "M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78L12 21.23l8.84-8.84a5.5 5.5 0 0 0 0-7.78z",
  heartFilled: "M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09A6.02 6.02 0 0 1 16.5 3C19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54z",
  home: "M3 11l9-8 9 8v10H5V11",
  lang: "M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zm6.93 6h-2.95c-.32-1.25-.78-2.45-1.38-3.56A8.03 8.03 0 0 1 18.92 8zM12 4.04c.83 1.2 1.48 2.53 1.91 3.96h-3.82A15.7 15.7 0 0 1 12 4.04zM4.26 14A8.1 8.1 0 0 1 4 12c0-.69.1-1.36.26-2h3.38c-.08.66-.14 1.32-.14 2s.06 1.34.14 2H4.26zm.82 2h2.95c.32 1.25.78 2.45 1.38 3.56A8.03 8.03 0 0 1 5.08 16zm2.95-8H5.08a8.03 8.03 0 0 1 4.33-3.56A15.8 15.8 0 0 0 8.03 8zM12 19.96A15.7 15.7 0 0 1 10.09 16h3.82A15.7 15.7 0 0 1 12 19.96zM14.34 14H9.66a15.5 15.5 0 0 1-.16-2c0-.68.07-1.35.16-2h4.68c.09.65.16 1.32.16 2s-.07 1.34-.16 2zm.25 5.56A15.8 15.8 0 0 0 15.97 16h2.95a8.03 8.03 0 0 1-4.33 3.56zM16.36 14c.08-.66.14-1.32.14-2s-.06-1.34-.14-2h3.38c.16.64.26 1.31.26 2s-.1 1.36-.26 2h-3.38z",
  list: "M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01",
  listFilled: "M4 10.5c-.83 0-1.5.67-1.5 1.5s.67 1.5 1.5 1.5 1.5-.67 1.5-1.5-.67-1.5-1.5-1.5zm0-6C3.17 4.5 2.5 5.17 2.5 6S3.17 7.5 4 7.5 5.5 6.83 5.5 6 4.83 4.5 4 4.5zm0 12c-.83 0-1.5.68-1.5 1.5s.68 1.5 1.5 1.5 1.5-.68 1.5-1.5-.67-1.5-1.5-1.5zM7 19h14v-2H7v2zm0-6h14v-2H7v2zm0-8v2h14V5H7z",
  medal: "M8 21l4-7 4 7M8 3h8l2 5-6 6-6-6z",
  image: "M4 4h16v16H4zM7 16l3-3 2 2 3-4 3 5M9 9h.01",
  person: "M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-4.42 0-8 2.01-8 4.5V21h16v-2.5c0-2.49-3.58-4.5-8-4.5z",
  save: "M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2zM7 21v-8h10v8M7 3v5h8",
  showChart: "M3.5 18.49l6-6.01 4 4L22 6.92l-1.41-1.41-7.09 7.97-4-4L2 16.99z",
  timer: "M10 2h4M12 14l4-4M5 5l2 2m10-2-2 2M12 22a8 8 0 1 0 0-16 8 8 0 0 0 0 16z",
  trophy: "M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0zM5 5H3v2a4 4 0 0 0 4 4M19 5h2v2a4 4 0 0 1-4 4",
  upload: "M12 21V9m0 0 5 5m-5-5-5 5M4 3h16",
  weight: "M6 7h12l2 14H4zM9 7a3 3 0 0 1 6 0"
};

const filledIcons = new Set([
  "add", "back", "checkCircle", "emojiEvents", "fitness", "heartFilled", "lang", "listFilled", "person", "showChart"
]);

function handleEmailConfirmationRedirect() {
  const query = new URLSearchParams(window.location.search);
  const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  const isWebAuthCallback = query.getAll("platform").length === 1 &&
    query.get("platform") === "web" &&
    ["purpose", "state", "code", "error", "error_description"].some(key => query.has(key));

  if (isWebAuthCallback) {
    void completeAuthCallback(query);
    return true;
  }
  const hasAuthPayload = query.has("access_token") || query.has("refresh_token") ||
    hash.has("access_token") || hash.has("refresh_token") ||
    query.get("type") === "signup" || hash.get("type") === "signup";

  if (!hasAuthPayload) return false;

  if (!query.has("platform")) query.set("platform", "web");
  // Never forward a reusable bearer credential into another URL. The web
  // confirmation page needs only the flow type; replace() also removes the
  // original token-bearing location from browser history.
  window.location.replace("./confirmed.html?platform=web");
  return true;
}

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
    diagnostics: "Export redacted diagnostics", sharePdf: "Share PDF report", rename: "Rename Exercise", history: "History",
    workoutComplete: "Workout complete", impact: "Workout impact", personalRecords: "Personal records", levelProgress: "Level progress",
    momentum: "Momentum", daily: "Daily Missions", weekly: "Weekly Missions", monthly: "Monthly Missions", viewRanks: "View ranks"
  },
  uk: {
    workouts: "Тренування", missions: "Місії", exercises: "Вправи", progress: "Прогрес", ranks: "Ранги",
    addWorkout: "Додати тренування", finishWorkout: "Завершити", saveWorkout: "Зберегти тренування", repeatLast: "Повторити останнє тренування",
    copyWorkout: "Скопіювати попереднє тренування", overview: "Огляд", workoutList: "Список тренувань", current: "Поточний",
    soloProgress: "Особистий прогрес", monthlySnapshot: "Підсумок місяця", heatmap: "Карта активності", muscleMap: "Карта м'язів",
    recommendations: "Рекомендації", achievements: "Досягнення", noWorkouts: "Немає тренувань у цьому місяці.",
    note: "Нотатка", trainingProfile: "Профіль тренувань", smartCoach: "Розумний тренер", generateSmart: "Згенерувати тренування",
    syncWatch: "Синхронізувати з годинником", addExercise: "Додати вправу", addSet: "Додати підхід", copyLast: "Копіювати останній підхід",
    copyPlus: "Копіювати останній +2,5 кг", useLast: "Використати останню вагу", applySmart: "Застосувати план", templatePicker: "Скопіювати попереднє тренування",
    exerciseName: "Назва вправи", backup: "Резервні копії та діагностика", exportJson: "Експорт JSON", importJson: "Імпорт JSON",
    diagnostics: "Експорт знеособленої діагностики", sharePdf: "Поділитися PDF-звітом", rename: "Перейменувати", history: "Історія",
    workoutComplete: "Тренування завершено", impact: "Вплив тренування", personalRecords: "Особисті рекорди", levelProgress: "Прогрес рівня",
    momentum: "Імпульс", daily: "Щоденні місії", weekly: "Тижневі місії", monthly: "Місячні місії", viewRanks: "Дивитись ранги"
  }
};

const muscles = [
  ["chest", "Chest", "Груди"], ["shoulders", "Shoulders", "Плечі"], ["biceps", "Biceps", "Біцепс"], ["triceps", "Triceps", "Трицепс"],
  ["forearms", "Forearms", "Передпліччя"], ["abs", "Abs", "Прес"], ["obliques", "Obliques", "Косі м'язи"], ["upperBack", "Upper Back", "Верх спини"],
  ["lats", "Lats", "Широчайші"], ["lowerBack", "Lower Back", "Поперек"], ["glutes", "Glutes", "Сідниці"], ["quads", "Quads", "Квадрицепси"],
  ["hamstrings", "Hamstrings", "Біцепс стегна"], ["adductors", "Adductors", "Привідні"], ["calves", "Calves", "Ікри"]
];

const builtInExerciseCatalog = [
  { key: "bench_press", names: { en: "Bench Press", uk: "Жим штанги лежачи" }, aliases: ["жим лежачи"], muscleIds: ["chest", "triceps", "shoulders"] },
  { key: "dumbbell_bench_press", names: { en: "Dumbbell Bench Press", uk: "Жим гантелей лежачи" }, aliases: ["гантелі лежачи"], muscleIds: ["chest", "triceps", "shoulders"] },
  { key: "incline_dumbbell_press", names: { en: "Incline Dumbbell Press", uk: "Жим гантелей на похилій лаві" }, aliases: [], muscleIds: ["chest", "shoulders", "triceps"] },
  { key: "incline_bench_press", names: { en: "Incline Bench Press", uk: "Жим штанги на похилій лаві" }, aliases: [], muscleIds: ["chest", "shoulders", "triceps"] },
  { key: "chest_fly_machine", names: { en: "Machine Chest Fly", uk: "Зведення рук у тренажері" }, aliases: ["метелик в середину"], muscleIds: ["chest", "shoulders"] },
  { key: "push_up", names: { en: "Push Up", uk: "Віджимання від підлоги" }, aliases: ["Push-Up"], muscleIds: ["chest", "triceps", "shoulders"] },
  { key: "dips", names: { en: "Dips", uk: "Віджимання на брусах" }, aliases: ["брусья"], muscleIds: ["triceps", "chest", "shoulders"] },
  { key: "pull_up", names: { en: "Pull Up", uk: "Підтягування" }, aliases: ["Pull-Up"], muscleIds: ["lats", "biceps", "upperBack", "forearms"] },
  { key: "assisted_pull_up", names: { en: "Assisted Pull Up", uk: "Підтягування у гравітроні" }, aliases: ["підтягування в гравітроні"], muscleIds: ["lats", "upperBack", "biceps", "forearms"] },
  { key: "band_assisted_pull_up", names: { en: "Band Assisted Pull Up", uk: "Підтягування з еспандером" }, aliases: ["підтягування з резинкою"], muscleIds: ["lats", "upperBack", "biceps", "forearms"] },
  { key: "lat_pulldown", names: { en: "Lat Pulldown", uk: "Тяга верхнього блока" }, aliases: ["Тяга верхнього блока до грудей", "Фронтальна тяга"], muscleIds: ["lats", "upperBack", "biceps", "forearms"] },
  { key: "straight_arm_pulldown", names: { en: "Straight Arm Pulldown", uk: "Тяга прямих рук на верхньому блоці" }, aliases: ["Журавель", "Тяга верхніх блоків у тренажері"], muscleIds: ["lats", "upperBack"] },
  { key: "barbell_row", names: { en: "Barbell Row", uk: "Тяга штанги в нахилі" }, aliases: [], muscleIds: ["upperBack", "lats", "biceps", "forearms"] },
  { key: "seated_cable_row", names: { en: "Seated Cable Row", uk: "Горизонтальна тяга блока" }, aliases: [], muscleIds: ["upperBack", "lats", "biceps", "forearms"] },
  { key: "plate_loaded_row", names: { en: "Plate Loaded Row", uk: "Горизонтальна тяга у важільному тренажері" }, aliases: ["горизонтальна важільна тяга"], muscleIds: ["upperBack", "lats", "biceps", "forearms"] },
  { key: "face_pull", names: { en: "Face Pull", uk: "Тяга каната до обличчя" }, aliases: [], muscleIds: ["shoulders", "upperBack"] },
  { key: "squat", names: { en: "Squat", uk: "Присідання зі штангою" }, aliases: ["Barbell Squat", "Присід зі штангою"], muscleIds: ["quads", "glutes", "hamstrings", "adductors", "lowerBack"] },
  { key: "leg_press", names: { en: "Leg Press", uk: "Жим ногами у тренажері" }, aliases: ["Жим ногами"], muscleIds: ["quads", "glutes", "hamstrings"] },
  { key: "bulgarian_split_squat", names: { en: "Bulgarian Split Squat", uk: "Болгарські випади" }, aliases: [], muscleIds: ["quads", "glutes", "hamstrings"] },
  { key: "lunge", names: { en: "Lunge", uk: "Випади" }, aliases: [], muscleIds: ["quads", "glutes", "hamstrings"] },
  { key: "romanian_deadlift", names: { en: "Romanian Deadlift", uk: "Румунська тяга" }, aliases: [], muscleIds: ["hamstrings", "glutes", "lowerBack"] },
  { key: "deadlift", names: { en: "Deadlift", uk: "Станова тяга" }, aliases: [], muscleIds: ["hamstrings", "glutes", "lowerBack", "upperBack", "forearms"] },
  { key: "hip_thrust", names: { en: "Hip Thrust", uk: "Ягодичний міст зі штангою" }, aliases: [], muscleIds: ["glutes", "hamstrings"] },
  { key: "leg_extension", names: { en: "Leg Extension", uk: "Розгинання ніг у тренажері" }, aliases: ["розгинання ніг"], muscleIds: ["quads"] },
  { key: "lying_leg_curl", names: { en: "Lying Leg Curl", uk: "Згинання ніг лежачи" }, aliases: ["згибання ніг лежачи"], muscleIds: ["hamstrings", "calves"] },
  { key: "seated_leg_curl", names: { en: "Seated Leg Curl", uk: "Згинання ніг сидячи" }, aliases: ["згибання ніг сидячі", "згибання ніг сидячи"], muscleIds: ["hamstrings", "calves"] },
  { key: "hip_adduction", names: { en: "Hip Adduction", uk: "Зведення ніг у тренажері" }, aliases: ["зведення ніг"], muscleIds: ["adductors"] },
  { key: "hip_abduction", names: { en: "Hip Abduction", uk: "Розведення ніг у тренажері" }, aliases: ["розведення ніг", "разведение ног", "разведение ног в тренажере"], muscleIds: ["glutes"], introducedInSeedVersion: 2 },
  { key: "calf_raise", names: { en: "Calf Raise", uk: "Підйом на носки" }, aliases: ["Підйом на носки стоячи"], muscleIds: ["calves"] },
  { key: "shoulder_press", names: { en: "Shoulder Press", uk: "Жим над головою" }, aliases: ["Overhead Press", "Жим сидячи над головою", "Жим сидячи"], muscleIds: ["shoulders", "triceps"] },
  { key: "lateral_raise", names: { en: "Lateral Raise", uk: "Підйоми гантелей через сторони" }, aliases: ["Махи в сторони", "махи в сторони з гантелями"], muscleIds: ["shoulders"] },
  { key: "machine_lateral_raise", names: { en: "Machine Lateral Raise", uk: "Підйоми рук через сторони у тренажері" }, aliases: ["махи в сторони в тренажері"], muscleIds: ["shoulders"] },
  { key: "rear_delt_fly", names: { en: "Rear Delt Fly", uk: "Зворотні розведення у тренажері" }, aliases: ["метелик в сторони"], muscleIds: ["shoulders", "upperBack"] },
  { key: "upright_row", names: { en: "Upright Row", uk: "Тяга штанги до підборіддя" }, aliases: ["протяжка", "вертикальна тяга"], muscleIds: ["shoulders", "upperBack", "biceps"] },
  { key: "biceps_curl", names: { en: "Biceps Curl", uk: "Згинання рук на біцепс" }, aliases: [], muscleIds: ["biceps", "forearms"] },
  { key: "barbell_curl", names: { en: "Barbell Curl", uk: "Згинання рук зі штангою" }, aliases: ["штанга на біцепс"], muscleIds: ["biceps", "forearms"] },
  { key: "seated_dumbbell_curl", names: { en: "Seated Dumbbell Curl", uk: "Згинання рук з гантелями сидячи" }, aliases: ["біцепс з гантелями сидячи"], muscleIds: ["biceps", "forearms"] },
  { key: "hammer_curl", names: { en: "Hammer Curl", uk: "Молоткові згинання рук" }, aliases: [], muscleIds: ["biceps", "forearms"] },
  { key: "cable_curl", names: { en: "Cable Curl", uk: "Згинання рук на нижньому блоці" }, aliases: ["біцепс в кросовері"], muscleIds: ["biceps", "forearms"] },
  { key: "preacher_curl", names: { en: "Preacher Curl", uk: "Згинання рук на лаві Скотта" }, aliases: ["тренажер скота(біцепс)"], muscleIds: ["biceps", "forearms"] },
  { key: "triceps_pushdown", names: { en: "Triceps Pushdown", uk: "Розгинання рук на блоці" }, aliases: [], muscleIds: ["triceps"] },
  { key: "v_bar_pushdown", names: { en: "V-Bar Triceps Pushdown", uk: "Розгинання рук на блоці з V-рукояттю" }, aliases: ["трицепс трикутник"], muscleIds: ["triceps"] },
  { key: "overhead_dumbbell_triceps_extension", names: { en: "Overhead Dumbbell Triceps Extension", uk: "Розгинання гантелі над головою" }, aliases: ["гантеля над головою"], muscleIds: ["triceps", "shoulders"] },
  { key: "french_press", names: { en: "French Press", uk: "Французький жим" }, aliases: [], muscleIds: ["triceps", "shoulders"] },
  { key: "hyperextension", names: { en: "Hyperextension", uk: "Гіперекстензія" }, aliases: [], muscleIds: ["lowerBack", "glutes", "hamstrings"] },
  { key: "side_hyperextension", names: { en: "Side Hyperextension", uk: "Бокові нахили на гіперекстензії" }, aliases: ["Нахили в сторони на гіперекстензії"], muscleIds: ["obliques", "abs", "lowerBack"] },
  { key: "plank", names: { en: "Plank", uk: "Планка" }, aliases: [], muscleIds: ["abs", "obliques"] },
  { key: "weighted_crunch", names: { en: "Weighted Crunch", uk: "Скручування з диском" }, aliases: ["прес звичайний з диском"], muscleIds: ["abs", "obliques"] },
  { key: "hanging_leg_raise", names: { en: "Hanging Leg Raise", uk: "Підйом ніг у висі" }, aliases: ["прес(підйом ніг)"], muscleIds: ["abs"] },
  { key: "plate_twist", names: { en: "Plate Twist", uk: "Повороти корпусу з диском" }, aliases: ["прес з диском в сторони"], muscleIds: ["obliques", "abs"] },
  { key: "weighted_side_bend", names: { en: "Weighted Side Bend", uk: "Бокові нахили з обтяженням" }, aliases: ["бокові нахили"], muscleIds: ["obliques", "abs"] },
  { key: "warm_up", names: { en: "Warm Up", uk: "Розминка" }, aliases: [], muscleIds: ["shoulders", "chest", "upperBack", "lats", "abs", "glutes", "quads", "hamstrings"] }
];

const CATALOG_SEED_VERSION = 2;
const builtInExerciseByKey = new Map(builtInExerciseCatalog.map(exercise => [exercise.key, exercise]));
const bundledExerciseMediaKeys = new Set([
  "bench_press", "dumbbell_bench_press", "incline_dumbbell_press", "incline_bench_press",
  "chest_fly_machine", "push_up", "dips", "pull_up", "band_assisted_pull_up",
  "lat_pulldown", "straight_arm_pulldown", "barbell_row", "seated_cable_row", "face_pull",
  "squat", "leg_press", "romanian_deadlift", "deadlift", "hip_thrust", "leg_extension",
  "lying_leg_curl", "seated_leg_curl", "hip_adduction", "hip_abduction", "calf_raise",
  "shoulder_press", "lateral_raise", "rear_delt_fly", "upright_row", "biceps_curl",
  "barbell_curl", "seated_dumbbell_curl", "hammer_curl", "cable_curl", "preacher_curl",
  "triceps_pushdown", "v_bar_pushdown", "overhead_dumbbell_triceps_extension",
  "hyperextension", "plank", "weighted_crunch", "hanging_leg_raise", "plate_twist",
  "weighted_side_bend"
]);
const builtInExerciseKeyByAlias = new Map(
  builtInExerciseCatalog.flatMap(exercise =>
    [...new Set([exercise.names.en, exercise.names.uk, ru(exercise.names.en), ...exercise.aliases])]
      .map(alias => [normalizeExerciseKey(alias), exercise.key])
  )
);
const defaultMappings = Object.fromEntries(
  builtInExerciseCatalog.map(exercise => [normalizeExerciseKey(exercise.names.en), exercise.muscleIds])
);

function weightedMuscles(values) {
  return values.map(([muscleId, weight]) => ({ muscleId, weight }));
}

const exactMuscleMap = Object.fromEntries(Object.entries({
  "нахили в сторони на гіперекстензії": [
    [
      "obliques",
      0.9
    ],
    [
      "abs",
      0.35
    ],
    [
      "lowerBack",
      0.25
    ]
  ],
  "бокові нахили на гіперекстензії": [
    [
      "obliques",
      0.9
    ],
    [
      "abs",
      0.35
    ],
    [
      "lowerBack",
      0.25
    ]
  ],
  "присід зі штангою": [
    [
      "quads",
      1
    ],
    [
      "glutes",
      0.7
    ],
    [
      "hamstrings",
      0.45
    ],
    [
      "lowerBack",
      0.25
    ],
    [
      "abs",
      0.2
    ]
  ],
  "присідання зі штангою": [
    [
      "quads",
      1
    ],
    [
      "glutes",
      0.7
    ],
    [
      "hamstrings",
      0.45
    ],
    [
      "lowerBack",
      0.25
    ],
    [
      "abs",
      0.2
    ]
  ],
  "бокові нахили": [
    [
      "obliques",
      0.9
    ],
    [
      "abs",
      0.3
    ]
  ],
  "бокові нахили з обтяженням": [
    [
      "obliques",
      0.9
    ],
    [
      "abs",
      0.3
    ]
  ],
  "брусья": [
    [
      "triceps",
      0.85
    ],
    [
      "chest",
      0.75
    ],
    [
      "shoulders",
      0.35
    ]
  ],
  "віджимання на брусах": [
    [
      "triceps",
      0.85
    ],
    [
      "chest",
      0.75
    ],
    [
      "shoulders",
      0.35
    ]
  ],
  "біцепс з гантелями сидячи": [
    [
      "biceps",
      1
    ],
    [
      "forearms",
      0.25
    ]
  ],
  "згинання рук з гантелями сидячи": [
    [
      "biceps",
      1
    ],
    [
      "forearms",
      0.25
    ]
  ],
  "гантеля над головою": [
    [
      "triceps",
      1
    ],
    [
      "shoulders",
      0.3
    ]
  ],
  "розгинання гантелі над головою": [
    [
      "triceps",
      1
    ],
    [
      "shoulders",
      0.3
    ]
  ],
  "гантелі лежачи": [
    [
      "chest",
      0.9
    ],
    [
      "triceps",
      0.55
    ],
    [
      "shoulders",
      0.45
    ]
  ],
  "жим гантелей лежачи": [
    [
      "chest",
      0.9
    ],
    [
      "triceps",
      0.55
    ],
    [
      "shoulders",
      0.45
    ]
  ],
  "горизонтальна важільна тяга": [
    [
      "upperBack",
      1
    ],
    [
      "lats",
      0.75
    ],
    [
      "biceps",
      0.45
    ],
    [
      "forearms",
      0.25
    ]
  ],
  "горизонтальна тяга у важільному тренажері": [
    [
      "upperBack",
      1
    ],
    [
      "lats",
      0.75
    ],
    [
      "biceps",
      0.45
    ],
    [
      "forearms",
      0.25
    ]
  ],
  "гіперекстензія": [
    [
      "lowerBack",
      1
    ],
    [
      "glutes",
      0.55
    ],
    [
      "hamstrings",
      0.45
    ]
  ],
  "жим лежачи": [
    [
      "chest",
      1
    ],
    [
      "triceps",
      0.6
    ],
    [
      "shoulders",
      0.5
    ]
  ],
  "жим штанги лежачи": [
    [
      "chest",
      1
    ],
    [
      "triceps",
      0.6
    ],
    [
      "shoulders",
      0.5
    ]
  ],
  "жим ногами": [
    [
      "quads",
      1
    ],
    [
      "glutes",
      0.55
    ],
    [
      "hamstrings",
      0.35
    ],
    [
      "calves",
      0.15
    ]
  ],
  "жим ногами у тренажері": [
    [
      "quads",
      1
    ],
    [
      "glutes",
      0.55
    ],
    [
      "hamstrings",
      0.35
    ],
    [
      "calves",
      0.15
    ]
  ],
  "жим сидячи": [
    [
      "shoulders",
      1
    ],
    [
      "triceps",
      0.55
    ],
    [
      "chest",
      0.2
    ]
  ],
  "жим сидячи над головою": [
    [
      "shoulders",
      1
    ],
    [
      "triceps",
      0.55
    ],
    [
      "chest",
      0.2
    ]
  ],
  "журавель": [
    [
      "lats",
      1
    ],
    [
      "upperBack",
      0.75
    ],
    [
      "biceps",
      0.45
    ],
    [
      "forearms",
      0.25
    ]
  ],
  "тяга верхніх блоків у тренажері": [
    [
      "lats",
      1
    ],
    [
      "upperBack",
      0.75
    ],
    [
      "biceps",
      0.45
    ],
    [
      "forearms",
      0.25
    ]
  ],
  "тяга верхних блоков в тренажере": [
    [
      "lats",
      1
    ],
    [
      "upperBack",
      0.75
    ],
    [
      "biceps",
      0.45
    ],
    [
      "forearms",
      0.25
    ]
  ],
  "зведення ніг": [
    [
      "adductors",
      1
    ],
    [
      "quads",
      0.25
    ]
  ],
  "зведення ніг у тренажері": [
    [
      "adductors",
      1
    ],
    [
      "quads",
      0.25
    ]
  ],
  "розведення ніг": [
    [
      "glutes",
      1
    ]
  ],
  "розведення ніг у тренажері": [
    [
      "glutes",
      1
    ]
  ],
  "разведение ног": [
    [
      "glutes",
      1
    ]
  ],
  "разведение ног в тренажере": [
    [
      "glutes",
      1
    ]
  ],
  "згибання ніг": [
    [
      "hamstrings",
      1
    ],
    [
      "calves",
      0.2
    ]
  ],
  "згинання ніг у тренажері": [
    [
      "hamstrings",
      1
    ],
    [
      "calves",
      0.2
    ]
  ],
  "махи в сторони": [
    [
      "shoulders",
      1
    ]
  ],
  "підйоми гантелей через сторони": [
    [
      "shoulders",
      1
    ]
  ],
  "метелик в середину": [
    [
      "chest",
      1
    ],
    [
      "shoulders",
      0.25
    ]
  ],
  "зведення рук у тренажері": [
    [
      "chest",
      1
    ],
    [
      "shoulders",
      0.25
    ]
  ],
  "метелик в сторони": [
    [
      "shoulders",
      0.75
    ],
    [
      "upperBack",
      0.65
    ]
  ],
  "зворотні розведення у тренажері": [
    [
      "shoulders",
      0.75
    ],
    [
      "upperBack",
      0.65
    ]
  ],
  "прес з диском в сторони": [
    [
      "obliques",
      0.85
    ],
    [
      "abs",
      0.45
    ]
  ],
  "повороти корпусу з диском": [
    [
      "obliques",
      0.85
    ],
    [
      "abs",
      0.45
    ]
  ],
  "прес звичайний з диском": [
    [
      "abs",
      1
    ],
    [
      "obliques",
      0.25
    ]
  ],
  "скручування з диском": [
    [
      "abs",
      1
    ],
    [
      "obliques",
      0.25
    ]
  ],
  "прес(підйом ніг)": [
    [
      "abs",
      1
    ]
  ],
  "підйом ніг у висі": [
    [
      "abs",
      1
    ]
  ],
  "протяжка": [
    [
      "shoulders",
      0.85
    ],
    [
      "upperBack",
      0.55
    ],
    [
      "biceps",
      0.25
    ]
  ],
  "тяга штанги до підборіддя": [
    [
      "shoulders",
      0.85
    ],
    [
      "upperBack",
      0.55
    ],
    [
      "biceps",
      0.25
    ]
  ],
  "підйом на носки": [
    [
      "calves",
      1
    ]
  ],
  "підйом на носки стоячи": [
    [
      "calves",
      1
    ]
  ],
  "підтягування в гравітроні": [
    [
      "lats",
      1
    ],
    [
      "upperBack",
      0.65
    ],
    [
      "biceps",
      0.55
    ],
    [
      "forearms",
      0.3
    ]
  ],
  "підтягування у гравітроні": [
    [
      "lats",
      1
    ],
    [
      "upperBack",
      0.65
    ],
    [
      "biceps",
      0.55
    ],
    [
      "forearms",
      0.3
    ]
  ],
  "підтягування з резинкою": [
    [
      "lats",
      1
    ],
    [
      "upperBack",
      0.65
    ],
    [
      "biceps",
      0.55
    ],
    [
      "forearms",
      0.3
    ]
  ],
  "підтягування з еспандером": [
    [
      "lats",
      1
    ],
    [
      "upperBack",
      0.65
    ],
    [
      "biceps",
      0.55
    ],
    [
      "forearms",
      0.3
    ]
  ],
  "розгинання ніг": [
    [
      "quads",
      1
    ]
  ],
  "розгинання ніг у тренажері": [
    [
      "quads",
      1
    ]
  ],
  "румунська тяга": [
    [
      "hamstrings",
      1
    ],
    [
      "glutes",
      0.85
    ],
    [
      "lowerBack",
      0.65
    ],
    [
      "upperBack",
      0.2
    ]
  ],
  "станова тяга": [
    [
      "lowerBack",
      0.9
    ],
    [
      "glutes",
      0.85
    ],
    [
      "hamstrings",
      0.8
    ],
    [
      "upperBack",
      0.45
    ],
    [
      "quads",
      0.35
    ],
    [
      "forearms",
      0.3
    ]
  ],
  "тренажер скота(біцепс)": [
    [
      "biceps",
      1
    ],
    [
      "forearms",
      0.25
    ]
  ],
  "згинання рук на лаві скотта": [
    [
      "biceps",
      1
    ],
    [
      "forearms",
      0.25
    ]
  ],
  "трицепс трикутник": [
    [
      "triceps",
      1
    ]
  ],
  "розгинання рук на блоці з v-рукояттю": [
    [
      "triceps",
      1
    ]
  ],
  "французький жим": [
    [
      "triceps",
      1
    ],
    [
      "shoulders",
      0.15
    ]
  ],
  "фронтальна тяга": [
    [
      "lats",
      1
    ],
    [
      "upperBack",
      0.7
    ],
    [
      "biceps",
      0.5
    ],
    [
      "forearms",
      0.25
    ]
  ],
  "тяга верхнього блока до грудей": [
    [
      "lats",
      1
    ],
    [
      "upperBack",
      0.7
    ],
    [
      "biceps",
      0.5
    ],
    [
      "forearms",
      0.25
    ]
  ],
  "штанга на біцепс": [
    [
      "biceps",
      1
    ],
    [
      "forearms",
      0.35
    ]
  ],
  "згинання рук зі штангою": [
    [
      "biceps",
      1
    ],
    [
      "forearms",
      0.35
    ]
  ]
}).map(([name, entries]) => [normalizeExerciseKey(name), weightedMuscles(entries)]));

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

let volatileRemoteSessionRaw = null;
discardLegacyGarminToken();
let activeAccount = loadActiveAccount();
let state = loadState();
let nav = [{ name: "workouts" }];
let modal = null;
let workoutDraft = null;
let toastTimer = null;
const monthOffsets = { workouts: 0, progress: 0 };
let overviewMode = "overview";
let musclePeriod = "month";
let missionPeriod = "daily";
let selectedMuscle = null;
let leaderboardState = { status: "idle", source: null, rows: [], error: "" };
let leaderboardRequestController = null;
let leaderboardRequestId = 0;
let timerInterval = null;
let languageMenuOpen = false;
let exerciseSearchQuery = "";
let exerciseBodyFilter = "all";
let exerciseMuscleFilter = "all";
let exerciseSortMode = "name";
let exerciseFavoritesOnly = false;
let authMode = "login";
let authNotice = null;
let pendingEmailConfirmation = null;
let authRequestInProgress = false;
let accountTransitionInProgress = false;
let garminSyncInProgress = false;
let pendingRecommendations = [];
const pendingGarminRevocations = new Map();
let cloudStateRecovery = null;
let cloudSyncConflict = null;
let cloudRecoveryInProgress = false;
const authDrafts = {
  login: { email: "", password: "" },
  signup: { email: "", emailConfirm: "", password: "", passwordConfirm: "", name: "" },
  forgot: { email: "" }
};
const routeScrollPositions = new Map();
const USER_VISIBLE_ERROR_MESSAGES = Symbol("GymAppUserVisibleErrorMessages");

function clearAuthDrafts() {
  authMode = "login";
  authNotice = null;
  pendingEmailConfirmation = null;
  authDrafts.login = { email: "", password: "" };
  authDrafts.signup = { email: "", emailConfirm: "", password: "", passwordConfirm: "", name: "" };
  authDrafts.forgot = { email: "" };
}

function t(key) {
  if (state.language === "ru") return ru(text.en[key] || key);
  return (text[state.language] || text.en)[key] || text.en[key] || key;
}

function tx(en, uk) {
  if (state.language === "uk") return uk;
  if (state.language === "ru") return ru(en);
  return en;
}

function userVisibleError(en, uk) {
  const error = new Error(en);
  Object.defineProperty(error, USER_VISIBLE_ERROR_MESSAGES, {
    value: Object.freeze({ en, uk })
  });
  return error;
}

function friendlyOperationError(error, fallbackEn, fallbackUk) {
  const messages = error?.[USER_VISIBLE_ERROR_MESSAGES];
  if (messages && typeof messages.en === "string" && typeof messages.uk === "string" &&
      messages.en.length <= 2048 && messages.uk.length <= 2048) {
    return tx(messages.en, messages.uk);
  }
  return tx(fallbackEn, fallbackUk);
}

function txAttr(en, uk) {
  return escapeAttr(tx(en, uk));
}

function tAttr(key) {
  return escapeAttr(t(key));
}

function muscleLabel(id) {
  const row = muscles.find(([muscleId]) => muscleId === id);
  if (!row) return id;
  if (state.language === "uk") return row[2];
  if (state.language === "ru") return ru(row[1]);
  return row[1];
}

function normalizeExerciseKey(name) {
  return String(name || "").toLowerCase().replace(/[\u02bc\u2019]/g, "'").replace(/\s+/g, " ").trim();
}

function exerciseRawName(value) {
  const rawName = typeof value === "string"
    ? value
    : value?.name || value?.exerciseName || value?.title || "";
  return String(rawName).trim();
}

function catalogKeyRecognizedFromName(value) {
  return builtInExerciseKeyByAlias.get(normalizeExerciseKey(exerciseRawName(value))) || null;
}

function explicitCatalogKey(value) {
  if (!value || typeof value !== "object") return null;
  const key = String(value.catalogKey || "").trim();
  return builtInExerciseByKey.has(key) ? key : null;
}

function resolvedExerciseCatalogKey(value) {
  // A recognized raw name is stronger evidence than untrusted imported metadata.
  // A valid explicit key is only a fallback when the raw name is absent. An unknown custom
  // name must never be reclassified or merged because attacker-controlled metadata names a
  // built-in exercise.
  return exerciseRawName(value) ? catalogKeyRecognizedFromName(value) : explicitCatalogKey(value);
}

function persistedExerciseCatalogKey(value) {
  return resolvedExerciseCatalogKey(value);
}

function builtInExerciseFor(value) {
  const key = resolvedExerciseCatalogKey(value);
  return key ? builtInExerciseByKey.get(key) : null;
}

function customExerciseMediaStorageKey(exercise) {
  const owner = destructiveImpactFingerprint(activeStorageKey()) || "local";
  return `gymapp-exercise-media-v1:${owner}:${exerciseIdentity(exercise)}`;
}

function customExerciseMedia(exercise) {
  try {
    return localStorage.getItem(customExerciseMediaStorageKey(exercise)) || null;
  } catch {
    return null;
  }
}

function bundledExerciseMedia(exercise) {
  const key = resolvedExerciseCatalogKey(exercise);
  if (!key || !bundledExerciseMediaKeys.has(key)) return null;
  return {
    preview: `./exercise-media/${key}_0.jpg`,
    frames: [`./exercise-media/${key}_0.jpg`, `./exercise-media/${key}_1.jpg`]
  };
}

function exerciseMedia(exercise) {
  const custom = customExerciseMedia(exercise);
  return custom ? { preview: custom, frames: [custom], custom: true } : bundledExerciseMedia(exercise);
}

function exerciseMediaThumbnail(exercise, blockIndex) {
  const media = exerciseMedia(exercise);
  const label = txAttr("Open exercise demonstration", "Відкрити демонстрацію вправи");
  if (!media) {
    return `<button class="exercise-media-thumb empty" type="button" data-action="open-exercise-media" data-block="${blockIndex}" aria-label="${label}">${svg("image", "exercise-media-placeholder-icon")}<span>${tx("Add image", "Додати фото")}</span></button>`;
  }
  return `<button class="exercise-media-thumb" type="button" data-action="open-exercise-media" data-block="${blockIndex}" aria-label="${label}"><img src="${escapeAttr(media.preview)}" alt="" loading="lazy"><span class="exercise-media-play">${media.frames.length > 1 ? "▶" : svg("image", "small-icon")}</span></button>`;
}

async function normalizeCustomExerciseImage(file) {
  const allowedTypes = new Set(["image/jpeg", "image/png", "image/webp"]);
  if (!(file instanceof File) || !allowedTypes.has(file.type) || file.size < 1 || file.size > 8 * 1024 * 1024) {
    throw new Error("unsupported-image");
  }
  const bitmap = await createImageBitmap(file);
  try {
    if (bitmap.width < 32 || bitmap.height < 32 || bitmap.width > 8192 || bitmap.height > 8192 ||
        bitmap.width * bitmap.height > 40_000_000) {
      throw new Error("invalid-image-size");
    }
    const maximumSide = 1024;
    const scale = Math.min(1, maximumSide / Math.max(bitmap.width, bitmap.height));
    const width = Math.max(1, Math.round(bitmap.width * scale));
    const height = Math.max(1, Math.round(bitmap.height * scale));
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d", { alpha: false });
    if (!context) throw new Error("image-canvas");
    context.fillStyle = "#f7faff";
    context.fillRect(0, 0, width, height);
    context.drawImage(bitmap, 0, 0, width, height);
    const dataUrl = canvas.toDataURL("image/jpeg", 0.82);
    if (dataUrl.length > 1_600_000) throw new Error("compressed-image-too-large");
    return dataUrl;
  } finally {
    bitmap.close();
  }
}

async function saveCustomExerciseMedia(file) {
  if (!modal?.exercise) return;
  try {
    const dataUrl = await normalizeCustomExerciseImage(file);
    localStorage.setItem(customExerciseMediaStorageKey(modal.exercise), dataUrl);
    render();
  } catch {
    showToast(tx(
      "Choose a JPEG, PNG, or WebP image up to 8 MB.",
      "Оберіть JPEG, PNG або WebP розміром до 8 МБ."
    ));
  }
}

function exerciseCatalogKey(value) {
  return resolvedExerciseCatalogKey(value);
}

function canonicalExerciseName(value) {
  return builtInExerciseFor(value)?.names.en || exerciseRawName(value);
}

function exerciseDisplayName(value, language = state.language) {
  const builtIn = builtInExerciseFor(value);
  if (!builtIn) return exerciseRawName(value);
  if (language === "uk") return builtIn.names.uk;
  if (language === "ru") return ru(builtIn.names.en);
  return builtIn.names.en;
}

function exerciseSearchText(value, language = state.language) {
  const builtIn = builtInExerciseFor(value);
  if (!builtIn) return normalizeExerciseKey(exerciseRawName(value));
  const russianName = ru(builtIn.names.en);
  const localizedName = language === "uk" ? builtIn.names.uk : language === "ru" ? russianName : builtIn.names.en;
  return [...new Set([localizedName, builtIn.names.en, builtIn.names.uk, russianName, ...builtIn.aliases])]
    .map(normalizeExerciseKey)
    .join(" ");
}

function exerciseMatchesSearch(value, query, language = state.language) {
  return exerciseSearchText(value, language).includes(normalizeExerciseKey(query));
}

function exerciseMatchKey(value) {
  const catalogKey = persistedExerciseCatalogKey(value);
  return catalogKey ? `catalog:${catalogKey}` : `custom:${normalizeExerciseKey(exerciseRawName(value))}`;
}

function exercisesMatch(left, right) {
  return exerciseMatchKey(left) === exerciseMatchKey(right);
}

function n(count, enOne, enMany, ukOne, ukFew, ukMany) {
  if (state.language === "ru") {
    const forms = russianNounForms[enOne] || [ru(enOne), ru(enMany), ru(enMany)];
    const mod10 = Math.abs(count) % 10;
    const mod100 = Math.abs(count) % 100;
    const word = mod10 === 1 && mod100 !== 11 ? forms[0] : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) ? forms[1] : forms[2];
    return `${count} ${word}`;
  }
  if (state.language !== "uk") return `${count} ${count === 1 ? enOne : enMany}`;
  const mod10 = count % 10;
  const mod100 = count % 100;
  const word = mod10 === 1 && mod100 !== 11 ? ukOne : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) ? ukFew : ukMany;
  return `${count} ${word}`;
}

const russianNounForms = Object.freeze({
  day: ["день", "дня", "дней"],
  "active day": ["активный день", "активных дня", "активных дней"],
  week: ["неделя", "недели", "недель"],
  workout: ["тренировка", "тренировки", "тренировок"],
  "saved session": ["сохранённая тренировка", "сохранённые тренировки", "сохранённых тренировок"],
  session: ["сессия", "сессии", "сессий"],
  set: ["подход", "подхода", "подходов"],
  exercise: ["упражнение", "упражнения", "упражнений"],
  group: ["группа", "группы", "групп"],
  duplicate: ["дубликат", "дубликата", "дубликатов"],
  "invalid set": ["некорректный подход", "некорректных подхода", "некорректных подходов"]
});

function ru(value) {
  return window.GymRussianText?.translate(value) || String(value);
}

function defaultAppState() {
  return {
    language: "en",
    catalogSeedVersion: CATALOG_SEED_VERSION,
    exercises: builtInExerciseCatalog.map((exercise, index) => ({
      id: index + 1,
      name: exercise.names.en,
      catalogKey: exercise.key
    })),
    sessions: [],
    mappings: Object.assign(Object.create(null), defaultMappings),
    profile: { split: "Push Pull Legs", days: 4, goal: "Balanced", calories: "Maintenance" }
  };
}

function ensureBuiltInExerciseCatalog(targetState) {
  if (!targetState || !Array.isArray(targetState.exercises) ||
      targetState.catalogSeedVersion >= CATALOG_SEED_VERSION) return false;
  const currentSeedVersion = Math.max(0, Number(targetState.catalogSeedVersion) || 0);
  const pendingDefinitions = builtInExerciseCatalog.filter(
    definition => (definition.introducedInSeedVersion || 1) > currentSeedVersion
  );
  const existingKeys = new Set(targetState.exercises.map(exerciseCatalogKey).filter(Boolean));
  const usedIds = new Set(targetState.exercises.map(exercise => Number(exercise.id)).filter(Number.isSafeInteger));
  let candidateId = Math.max(0, ...usedIds) + 1;
  let inserted = 0;
  for (const definition of pendingDefinitions) {
    if (existingKeys.has(definition.key) || targetState.exercises.length >= window.GymStateContract.LIMITS.exercises) continue;
    while (usedIds.has(candidateId)) candidateId++;
    targetState.exercises.push({ id: candidateId, name: definition.names.en, catalogKey: definition.key });
    usedIds.add(candidateId);
    existingKeys.add(definition.key);
    candidateId++;
    inserted++;
  }
  targetState.exercises.sort((left, right) =>
    exerciseDisplayName(left, targetState.language).localeCompare(exerciseDisplayName(right, targetState.language), targetState.language)
  );
  if (pendingDefinitions.every(definition => existingKeys.has(definition.key))) {
    targetState.catalogSeedVersion = CATALOG_SEED_VERSION;
  }
  // Advancing the local seed marker alone does not change the portable cloud
  // payload, so it must not trigger a redundant CAS write on every pull.
  return inserted > 0;
}

function normalizeStoredAccount(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const id = typeof value.id === "string" ? value.id.trim() : "";
  const name = typeof value.name === "string" ? value.name.trim() : "";
  if (!/^[a-z0-9а-яіїєґ_-]{1,64}$/iu.test(id) || !name ||
      name.length > MAX_ACCOUNT_NAME_LENGTH || new TextEncoder().encode(name).byteLength > 256) {
    return null;
  }
  if (value.remote == null || value.remote === false) {
    if (value.localIdVersion == null) return { id, name };
    if (value.localIdVersion !== LOCAL_ACCOUNT_ID_VERSION || !LOCAL_ACCOUNT_ID_PATTERN.test(id)) return null;
    return { id, name, localIdVersion: LOCAL_ACCOUNT_ID_VERSION };
  }
  if (value.remote !== "supabase" || !UUID_PATTERN.test(value.userId || "") ||
      id !== `remote-${value.userId}`) return null;
  const email = value.email == null ? "" : String(value.email).trim();
  if (email.length > 254 || new TextEncoder().encode(email).byteLength > 320) return null;
  return { id, name, email, userId: value.userId, remote: "supabase" };
}

function loadActiveAccount() {
  try {
    const raw = localStorage.getItem(AUTH_KEY) || "null";
    if (new TextEncoder().encode(raw).byteLength > MAX_LOCAL_ACCOUNT_STORAGE_BYTES) {
      localStorage.removeItem(AUTH_KEY);
      clearRemoteSession();
      return null;
    }
    const account = normalizeStoredAccount(JSON.parse(raw));
    if (!account) {
      localStorage.removeItem(AUTH_KEY);
      clearRemoteSession();
      return null;
    }
    if (account.remote && loadRemoteSession()?.user?.id !== account.userId) {
      // A remote session is tab-scoped. An independent tab with no matching
      // session must not delete the shared account marker used by another tab.
      clearRemoteSession();
      return null;
    }
    if (!account.remote) clearRemoteSession();
    return account;
  } catch {
    localStorage.removeItem(AUTH_KEY);
    clearRemoteSession();
    return null;
  }
}

function removeActiveAccountMarkerIfOwned(account) {
  const expected = normalizeStoredAccount(account);
  // Remote credentials are tab-scoped while this marker is origin-scoped.
  // Removing a remote marker here would sign another still-authenticated tab
  // out on its next reload, even when both tabs belong to the same account.
  if (!expected || expected.remote) return false;
  try {
    const raw = localStorage.getItem(AUTH_KEY);
    if (!raw) return true;
    if (new TextEncoder().encode(raw).byteLength > MAX_LOCAL_ACCOUNT_STORAGE_BYTES) return false;
    const current = normalizeStoredAccount(JSON.parse(raw));
    if (!current) return false;
    const sameIdentity = !current?.remote && current?.id === expected.id && current?.name === expected.name &&
      current?.localIdVersion === expected.localIdVersion;
    if (!sameIdentity) return true;
    localStorage.removeItem(AUTH_KEY);
    return localStorage.getItem(AUTH_KEY) === null;
  } catch {
    return false;
  }
}

function removeActiveAccountMarkerForDeletion(account) {
  const expected = normalizeStoredAccount(account);
  if (!expected) return false;
  try {
    const raw = localStorage.getItem(AUTH_KEY);
    if (!raw) return true;
    if (new TextEncoder().encode(raw).byteLength > MAX_LOCAL_ACCOUNT_STORAGE_BYTES) return false;
    const current = normalizeStoredAccount(JSON.parse(raw));
    if (!current) return false;
    const sameIdentity = expected.remote === "supabase"
      ? current.remote === "supabase" && current.userId === expected.userId && current.id === expected.id
      : !current.remote && current.id === expected.id && current.name === expected.name &&
        current.localIdVersion === expected.localIdVersion;
    if (!sameIdentity) return true;
    localStorage.removeItem(AUTH_KEY);
    return localStorage.getItem(AUTH_KEY) === null;
  } catch {
    return false;
  }
}

function activeStorageKey(account = activeAccount) {
  return account?.id ? ACCOUNT_PREFIX + account.id : STORAGE_KEY;
}

function accountList() {
  try {
    const raw = localStorage.getItem(ACCOUNT_LIST_KEY) || "[]";
    if (new TextEncoder().encode(raw).byteLength > MAX_LOCAL_ACCOUNT_STORAGE_BYTES) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed) || parsed.length > MAX_LOCAL_ACCOUNTS) return [];
    const unique = [];
    parsed.forEach(value => {
      const account = normalizeStoredAccount(value);
      if (!account) return;
      const alreadyStored = account.remote
        ? unique.some(item => item.remote && item.id === account.id)
        : unique.some(item => !item.remote && item.id === account.id && item.name === account.name);
      if (!alreadyStored) unique.push(account);
    });
    return unique;
  } catch {
    return [];
  }
}

function saveAccountList(accounts) {
  const unique = [];
  (Array.isArray(accounts) ? accounts : []).forEach(value => {
    const account = normalizeStoredAccount(value);
    if (!account) return;
    const alreadyStored = account.remote
      ? unique.some(item => item.remote && item.id === account.id)
      : unique.some(item => !item.remote && item.id === account.id && item.name === account.name);
    if (!alreadyStored) unique.push(account);
  });
  localStorage.setItem(ACCOUNT_LIST_KEY, JSON.stringify(unique.slice(-MAX_LOCAL_ACCOUNTS)));
}

function supabaseConfig() {
  const config = window.GYM_SUPABASE || {};
  const rawUrl = String(config.url || "").trim();
  const anonKey = String(config.anonKey || "").trim();
  let url = "";
  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol === "https:" && !parsed.username && !parsed.password &&
        !parsed.search && !parsed.hash && (parsed.pathname === "/" || parsed.pathname === "")) {
      url = parsed.origin;
    }
  } catch {
    url = "";
  }
  return {
    url,
    anonKey: anonKey.length >= 8 && anonKey.length <= 4096 && !/\s/.test(anonKey) ? anonKey : ""
  };
}

function remoteAuthEnabled() {
  const config = supabaseConfig();
  return Boolean(config.url && config.anonKey);
}

function removeLegacyRemoteSession() {
  try {
    if (localStorage.getItem(REMOTE_SESSION_KEY) === null) return true;
    localStorage.removeItem(REMOTE_SESSION_KEY);
    return localStorage.getItem(REMOTE_SESSION_KEY) === null;
  } catch {
    return false;
  }
}

function takeLegacyRemoteSessionRaw() {
  let raw = null;
  try {
    raw = localStorage.getItem(REMOTE_SESSION_KEY);
  } catch {
    raw = null;
  }
  removeLegacyRemoteSession();
  return raw;
}

function transientRemoteSessionRaw() {
  try {
    return window.sessionStorage?.getItem(REMOTE_SESSION_KEY) ?? volatileRemoteSessionRaw;
  } catch {
    return volatileRemoteSessionRaw;
  }
}

function writeTransientRemoteSessionRaw(raw) {
  volatileRemoteSessionRaw = raw;
  try {
    window.sessionStorage?.setItem(REMOTE_SESSION_KEY, raw);
  } catch {
    // The in-memory copy keeps the current top-level session usable.
  }
  removeLegacyRemoteSession();
}

function clearRemoteSession() {
  volatileRemoteSessionRaw = null;
  let transientCleared = false;
  try {
    const transientStorage = window.sessionStorage;
    if (transientStorage) {
      transientStorage.removeItem(REMOTE_SESSION_KEY);
      transientCleared = transientStorage.getItem(REMOTE_SESSION_KEY) === null;
    } else {
      transientCleared = true;
    }
  } catch {
    transientCleared = false;
  }
  const legacyCleared = removeLegacyRemoteSession();
  return transientCleared && legacyCleared;
}

function loadRemoteSession() {
  const transientRaw = transientRemoteSessionRaw();
  const legacyRaw = takeLegacyRemoteSessionRaw();
  const raw = transientRaw ?? legacyRaw ?? "null";
  try {
    if (new TextEncoder().encode(raw).byteLength > MAX_REMOTE_AUTH_RESPONSE_BYTES) {
      clearRemoteSession();
      return null;
    }
    const parsed = JSON.parse(raw);
    if (!validRemoteSession(parsed)) {
      clearRemoteSession();
      return null;
    }
    if (transientRaw == null && legacyRaw != null) writeTransientRemoteSessionRaw(raw);
    return parsed;
  } catch {
    clearRemoteSession();
    return null;
  }
}

function saveRemoteSession(session) {
  if (!validRemoteSession(session)) throw new Error("Cloud session is invalid.");
  const encoded = JSON.stringify(session);
  if (new TextEncoder().encode(encoded).byteLength > MAX_REMOTE_AUTH_RESPONSE_BYTES) {
    throw new Error("Cloud session exceeds the browser session limit.");
  }
  writeTransientRemoteSessionRaw(encoded);
}

function saveDurableRemoteSession(session) {
  saveRemoteSession(session);
  try {
    const raw = window.sessionStorage?.getItem(REMOTE_SESSION_KEY);
    if (!raw || new TextEncoder().encode(raw).byteLength > MAX_REMOTE_AUTH_RESPONSE_BYTES) {
      throw new Error("Cloud session handoff is unavailable.");
    }
    const stored = JSON.parse(raw);
    if (!validRemoteSession(stored) || stored.user.id !== session.user.id ||
        stored.access_token !== session.access_token ||
        stored.activation_pending !== session.activation_pending) {
      throw new Error("Cloud session handoff could not be verified.");
    }
    return stored;
  } catch (error) {
    clearRemoteSession();
    throw error;
  }
}

function validRemoteSession(session) {
  const userId = session?.user?.id;
  const email = session?.user?.email;
  return Boolean(
    session && typeof session === "object" && !Array.isArray(session) &&
    session.user && typeof session.user === "object" && !Array.isArray(session.user) &&
    typeof session.access_token === "string" && session.access_token.length >= 16 &&
    session.access_token.length <= 16384 &&
    UUID_PATTERN.test(userId || "") && accessTokenSubject(session.access_token) === userId &&
    (email === undefined || (typeof email === "string" && email.length <= 254 &&
      new TextEncoder().encode(email).byteLength <= 320)) &&
    (session.refresh_token === undefined ||
      (typeof session.refresh_token === "string" && session.refresh_token.length >= 16 &&
       session.refresh_token.length <= 8192)) &&
    (session.password_update_required === undefined ||
      typeof session.password_update_required === "boolean") &&
    (session.activation_pending === undefined ||
      ["login", "signup", "recovery"].includes(session.activation_pending))
  );
}

function accessTokenClaims(accessToken) {
  try {
    const payload = String(accessToken || "").split(".")[1];
    if (!payload || payload.length > 12288) return null;
    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    const decoded = JSON.parse(atob(padded));
    return decoded && typeof decoded === "object" && !Array.isArray(decoded) ? decoded : null;
  } catch {
    return null;
  }
}

function accessTokenSubject(accessToken) {
  const subject = accessTokenClaims(accessToken)?.sub;
  return typeof subject === "string" && UUID_PATTERN.test(subject) ? subject : null;
}

function accessTokenExpirationSeconds(session) {
  return Number(accessTokenClaims(session?.access_token)?.exp) || null;
}

function remoteSessionNeedsRefresh(session) {
  const expiresAt = accessTokenExpirationSeconds(session);
  return Boolean(expiresAt && expiresAt - Math.floor(Date.now() / 1000) <= 60);
}

async function refreshRemoteSession(session = loadRemoteSession()) {
  if (!session?.refresh_token) return session;
  const requestEpoch = accountEpoch;
  const expectedUserId = session.user?.id;
  const expectedRefreshToken = session.refresh_token;
  const config = supabaseConfig();
  if (!config.url || !config.anonKey) throw new Error("Cloud request configuration is invalid.");
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12000);
  let response;
  try {
    response = await fetch(`${config.url}/auth/v1/token?grant_type=refresh_token`, {
      method: "POST",
      credentials: "omit",
      cache: "no-store",
      redirect: "error",
      referrerPolicy: "no-referrer",
      signal: controller.signal,
      headers: {
        apikey: config.anonKey,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ refresh_token: session.refresh_token })
    });
  } finally {
    clearTimeout(timeout);
  }
  if (!response.ok) {
    const errorText = await readBoundedResponseText(response, MAX_REMOTE_ERROR_RESPONSE_BYTES).catch(() => "");
    const error = new Error(errorText || `Session refresh failed: ${response.status}`);
    error.status = response.status;
    error.terminalAuth = response.status === 400 || response.status === 401;
    throw error;
  }
  const responseText = await readBoundedResponseText(response, MAX_REMOTE_AUTH_RESPONSE_BYTES);
  let refreshed;
  try {
    refreshed = JSON.parse(responseText);
  } catch {
    throw new Error("Session refresh returned invalid JSON.");
  }
  if (!refreshed || typeof refreshed !== "object" || Array.isArray(refreshed) ||
      typeof refreshed.access_token !== "string" || refreshed.access_token.length < 16 ||
      refreshed.access_token.length > 16384 ||
      accessTokenSubject(refreshed.access_token) !== expectedUserId ||
      (refreshed.refresh_token !== undefined &&
       (typeof refreshed.refresh_token !== "string" || refreshed.refresh_token.length < 16 ||
        refreshed.refresh_token.length > 8192)) ||
      (refreshed.user?.id !== undefined && refreshed.user.id !== expectedUserId)) {
    throw new Error("Session refresh returned an invalid account response.");
  }
  const nextSession = {
    ...session,
    ...refreshed,
    user: refreshed.user || session.user,
    refresh_token: refreshed.refresh_token || session.refresh_token
  };
  const current = loadRemoteSession();
  if (requestEpoch !== accountEpoch || current?.refresh_token !== expectedRefreshToken ||
      current?.user?.id !== expectedUserId || activeAccount?.userId !== expectedUserId) {
    throw new Error("Stale session refresh was discarded.");
  }
  saveRemoteSession(nextSession);
  return nextSession;
}

function remoteHeaders(session = loadRemoteSession()) {
  const config = supabaseConfig();
  return {
    apikey: config.anonKey,
    Authorization: `Bearer ${session?.access_token || config.anonKey}`,
    "Content-Type": "application/json"
  };
}

async function supabaseRequest(path, options = {}) {
  const config = supabaseConfig();
  if (!config.url || !config.anonKey || typeof path !== "string" ||
      !path.startsWith("/") || path.startsWith("//") || path.includes("\\") || path.length > 4096) {
    throw new Error("Cloud request configuration is invalid.");
  }
  const {
    timeoutMs = 12000,
    maxResponseBytes: requestedResponseBytes = MAX_REMOTE_RESPONSE_BYTES,
    ...fetchOptions
  } = options;
  const { session: providedSession, anonymous = false, ...requestOptions } = fetchOptions;
  const maxResponseBytes = Number.isSafeInteger(requestedResponseBytes) && requestedResponseBytes > 0
    ? Math.min(requestedResponseBytes, MAX_REMOTE_RESPONSE_BYTES)
    : MAX_REMOTE_RESPONSE_BYTES;
  const isAuthRequest = path.startsWith("/auth/v1/");
  const authenticatedAuthRequest = /^\/auth\/v1\/(?:user|reauthenticate)(?:[?]|$)/.test(path);
  const refreshEligible = !anonymous && (!isAuthRequest || authenticatedAuthRequest);
  let requestSession = anonymous ? null : (providedSession || loadRemoteSession());
  if (refreshEligible && requestSession?.access_token && remoteSessionNeedsRefresh(requestSession)) {
    requestSession = await refreshRemoteSession(requestSession);
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  if (fetchOptions.signal) {
    fetchOptions.signal.addEventListener("abort", () => controller.abort(), { once: true });
  }
  const request = () => fetch(`${config.url}${path}`, {
      ...requestOptions,
      credentials: "omit",
      cache: "no-store",
      redirect: "error",
      referrerPolicy: "no-referrer",
      signal: controller.signal,
      headers: { ...remoteHeaders(requestSession), ...(requestOptions.headers || {}) }
    });
  let response;
  try {
    response = await request();
    if (response.status === 401 && refreshEligible && requestSession?.refresh_token) {
      requestSession = await refreshRemoteSession(requestSession);
      response = await request();
    }
  } finally {
    clearTimeout(timeout);
  }
  if (!response.ok) {
    const text = await readBoundedResponseText(
      response,
      Math.min(maxResponseBytes, MAX_REMOTE_ERROR_RESPONSE_BYTES)
    ).catch(() => "");
    const error = new Error(text || `Request failed: ${response.status}`);
    error.status = response.status;
    throw error;
  }
  if (response.status === 204) return null;
  const body = await readBoundedResponseText(response, maxResponseBytes);
  return body ? JSON.parse(body) : null;
}

function isTerminalRemoteAuthError(error) {
  return error?.terminalAuth === true && (error.status === 400 || error.status === 401);
}

function transitionToReauthentication(error) {
  if (!isTerminalRemoteAuthError(error)) return false;
  try {
    if (activeAccount) saveState({ queueRemote: false });
  } catch {
    // The already-stored local copy remains available for the next login.
  }
  clearTimeout(remoteSaveTimer);
  remoteSaveTimer = null;
  clearRemoteSession();
  resetRemoteSyncContext();
  clearAuthDrafts();
  activeAccount = null;
  state = loadState();
  nav = [{ name: "workouts" }];
  modal = null;
  authNotice = {
    text: tx(
      "Your cloud session expired or was revoked. Sign in again; browser-saved workouts were kept.",
      "Хмарна сесія завершилася або була відкликана. Увійди знову; тренування в браузері збережено."
    ),
    isError: true
  };
  replaceNavigationHistory();
  render();
  return true;
}

async function readBoundedResponseText(response, maxBytes) {
  const advertisedLength = response.headers.get("Content-Length");
  if (advertisedLength !== null && /^\d+$/.test(advertisedLength.trim()) &&
      Number(advertisedLength) > maxBytes) {
    await response.body?.cancel().catch(() => {});
    throw new Error(`Cloud response exceeds ${maxBytes} bytes.`);
  }

  if (!response.body || typeof response.body.getReader !== "function") {
    throw new Error("Cloud response streaming is unavailable.");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  const chunks = [];
  let byteLength = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      byteLength += value.byteLength;
      if (byteLength > maxBytes || chunks.length >= MAX_REMOTE_RESPONSE_CHUNKS) {
        await reader.cancel().catch(() => {});
        throw new Error(`Cloud response exceeds ${maxBytes} bytes.`);
      }
      chunks.push(decoder.decode(value, { stream: true }));
    }
  } finally {
    reader.releaseLock();
  }
  chunks.push(decoder.decode());
  return chunks.join("");
}

function remoteAccountFromSession(session) {
  const email = session?.user?.email || "";
  const metadataName = sanitizeDisplayName(session.user.user_metadata?.display_name || "");
  return {
    id: `remote-${session.user.id}`,
    name: metadataName || sanitizeDisplayName(email.split("@")[0]) || "Supabase",
    email,
    userId: session.user.id,
    remote: "supabase"
  };
}

async function loadRemoteState(session) {
  const userId = session?.user?.id;
  if (!userId) throw new Error("Cloud session has no user.");
  const rows = await supabaseRequest(
    `/rest/v1/user_states?user_id=eq.${encodeURIComponent(userId)}&select=state,updated_at&limit=2`,
    { session }
  );
  if (!Array.isArray(rows) || rows.length > 1) throw new Error("Cloud state ownership is ambiguous.");
  if (!rows.length) return { userId, exists: false, revision: null, state: null };
  const revision = typeof rows[0]?.updated_at === "string" ? rows[0].updated_at : "";
  if (!validRemoteStateRevision(revision) || !rows[0]?.state || typeof rows[0].state !== "object" ||
      Array.isArray(rows[0].state)) {
    throw new Error("Cloud state response is invalid.");
  }
  return { userId, exists: true, revision, state: rows[0].state };
}

async function pullRemoteState() {
  if (!activeAccount?.remote || !remoteAuthEnabled()) return false;
  const session = loadRemoteSession();
  if (!session?.user?.id) return false;
  const cloudState = await loadRemoteState(session);
  if (activeAccount?.userId !== cloudState.userId || loadRemoteSession()?.user?.id !== cloudState.userId) {
    throw new Error("Cloud state was loaded for a stale account session.");
  }
  return reconcileLoadedRemoteState(cloudState, state, storedAccountStateExists(activeAccount));
}

function storedAccountStateExists(account = activeAccount) {
  try {
    return Boolean(account?.id && localStorage.getItem(activeStorageKey(account)) !== null);
  } catch {
    return false;
  }
}

async function reconcileLoadedRemoteState(cloudState, cachedState, cachedStateExists = true) {
  const userId = activeAccount?.userId;
  if (!UUID_PATTERN.test(userId || "") || cloudState?.userId !== userId) {
    throw new Error("Cloud state reconciliation owner is invalid.");
  }
  let remoteState = defaultAppState();
  let remoteFingerprint = null;
  let catalogChanged = false;
  try {
    if (cloudState.exists) {
      remoteState = normalizeImportedState(cloudState.state, defaultAppState());
      remoteFingerprint = remoteStateFingerprint(remoteState, userId);
      preserveExerciseFavorites(remoteState, cachedState, { preferPrevious: true });
      catalogChanged = ensureBuiltInExerciseCatalog(remoteState);
    }
    cloudStateRecovery = null;
  } catch {
    state = cachedState;
    bindRemoteStateRevision(cloudState);
    cloudStateRecovery = {
      userId: cloudState.userId,
      revision: cloudState.revision,
      rawState: cloudState.state
    };
    cloudSyncConflict = null;
    return true;
  }

  let baseline = loadSyncBaseline(userId);
  const localFingerprint = remoteStateFingerprint(cachedState, userId);
  const remoteIdentityFingerprint = cloudState.exists ? remoteFingerprint : null;
  const sameIdentity = (leftExists, leftFingerprint, rightExists, rightFingerprint) =>
    leftExists === rightExists && (!leftExists || leftFingerprint === rightFingerprint);
  const localMatches = fingerprint => fingerprint !== null && localFingerprint === fingerprint;
  const remoteMatches = (exists, fingerprint) => sameIdentity(
    Boolean(cloudState.exists),
    remoteIdentityFingerprint,
    Boolean(exists),
    fingerprint
  );
  const persistBase = ({ syncedFingerprint, dirty, pending = null }) => {
    baseline = saveSyncBaseline({
      version: 1,
      userId,
      remoteExists: Boolean(cloudState.exists),
      revision: cloudState.exists ? cloudState.revision : null,
      syncedFingerprint,
      localFingerprint,
      dirty,
      pending,
      updatedAt: Date.now()
    });
    return baseline;
  };
  const keepLocalAndUpload = async baseFingerprint => {
    state = cachedState;
    bindRemoteStateRevision(cloudState);
    cloudStateRecovery = null;
    cloudSyncConflict = null;
    persistBase({ syncedFingerprint: baseFingerprint, dirty: true });
    await saveRemoteState();
    return true;
  };
  const acceptRemote = async () => {
    state = cloudState.exists ? remoteState : defaultAppState();
    bindRemoteStateRevision(cloudState);
    cloudStateRecovery = null;
    cloudSyncConflict = null;
    saveState({ queueRemote: false, markDirty: false });
    const acceptedLocalFingerprint = remoteStateFingerprint(state, userId);
    baseline = saveSyncBaseline({
      version: 1,
      userId,
      remoteExists: Boolean(cloudState.exists),
      revision: cloudState.exists ? cloudState.revision : null,
      syncedFingerprint: remoteIdentityFingerprint,
      localFingerprint: acceptedLocalFingerprint,
      dirty: catalogChanged,
      pending: null,
      updatedAt: Date.now()
    });
    if (catalogChanged) await saveRemoteState();
    return true;
  };
  const blockConflict = pending => {
    state = cachedState;
    bindRemoteStateRevision(cloudState);
    cloudStateRecovery = null;
    if (!baseline) {
      baseline = saveSyncBaseline({
        version: 1,
        userId,
        remoteExists: Boolean(cloudState.exists),
        revision: cloudState.exists ? cloudState.revision : null,
        syncedFingerprint: remoteIdentityFingerprint,
        localFingerprint,
        dirty: true,
        pending: pending ?? null,
        updatedAt: Date.now()
      });
    }
    cloudSyncConflict = {
      userId,
      cloudState,
      remoteState,
      remoteFingerprint: remoteIdentityFingerprint,
      pending: pending ?? baseline?.pending ?? null
    };
    return true;
  };

  if (baseline?.pending) {
    const pending = baseline.pending;
    const remoteMatchesPending = cloudState.exists && remoteIdentityFingerprint === pending.payloadFingerprint;
    const remoteMatchesBase = remoteMatches(pending.baseExists, pending.baseFingerprint);
    if (remoteMatchesPending) {
      persistBase({
        syncedFingerprint: pending.payloadFingerprint,
        dirty: localFingerprint !== pending.payloadFingerprint
      });
      if (localFingerprint !== pending.payloadFingerprint) {
        return keepLocalAndUpload(pending.payloadFingerprint);
      }
      state = cachedState;
      bindRemoteStateRevision(cloudState);
      cloudSyncConflict = null;
      return true;
    }
    if (remoteMatchesBase) {
      persistBase({
        syncedFingerprint: pending.baseFingerprint,
        dirty: !localMatches(pending.baseFingerprint)
      });
      if (!localMatches(pending.baseFingerprint)) {
        return keepLocalAndUpload(pending.baseFingerprint);
      }
      return acceptRemote();
    }
    return blockConflict(pending);
  }

  if (!baseline) {
    if (cloudState.exists && !cachedStateExists) return acceptRemote();
    if (cloudState.exists && localFingerprint === remoteIdentityFingerprint) return acceptRemote();
    if (cloudState.exists) return blockConflict(null);
    state = cachedStateExists ? cachedState : defaultAppState();
    const initialFingerprint = remoteStateFingerprint(state, userId);
    baseline = saveSyncBaseline({
      version: 1,
      userId,
      remoteExists: false,
      revision: null,
      syncedFingerprint: null,
      localFingerprint: initialFingerprint,
      dirty: true,
      pending: null,
      updatedAt: Date.now()
    });
    bindRemoteStateRevision(cloudState);
    await saveRemoteState();
    return true;
  }

  const localMatchesRemote = cloudState.exists && localFingerprint === remoteIdentityFingerprint;
  const remoteMatchesBase = remoteMatches(baseline.remoteExists, baseline.syncedFingerprint);
  const localMatchesBase = baseline.syncedFingerprint !== null
    ? localMatches(baseline.syncedFingerprint)
    : (baseline.remoteExists === false && baseline.dirty === false &&
       localFingerprint === baseline.localFingerprint);
  if (localMatchesRemote) {
    if (catalogChanged) return acceptRemote();
    state = cachedState;
    bindRemoteStateRevision(cloudState);
    cloudSyncConflict = null;
    saveSyncBaseline(syncedBaseline(userId, cloudState, localFingerprint));
    return true;
  }
  if (!cloudState.exists && baseline.remoteExists === false && !baseline.dirty) {
    return acceptRemote();
  }
  if (remoteMatchesBase && !localMatchesBase) {
    return keepLocalAndUpload(baseline.syncedFingerprint);
  }
  if (localMatchesBase && !remoteMatchesBase) return acceptRemote();
  if (remoteMatchesBase && localMatchesBase) return acceptRemote();
  return blockConflict(null);
}

function remoteStateCore(sourceState = state, expectedUserId = activeAccount?.userId) {
  if (!expectedUserId) throw new Error("Cloud state owner is missing.");
  return {
    schemaVersion: 2,
    app: "GymApp",
    diagnostics: false,
    owner: { accountId: expectedUserId, userId: expectedUserId, remote: true },
    language: sourceState.language,
    // Favorites are intentionally device/account-local. Android's strict
    // cloud schema-v2 does not accept the optional PWA backup field.
    exercises: sourceState.exercises.map(exercise => ({
      id: exercise.id,
      name: exercise.name,
      ...(persistedExerciseCatalogKey(exercise) ? { catalogKey: persistedExerciseCatalogKey(exercise) } : {})
    })),
    sessions: sourceState.sessions,
    mappings: sourceState.mappings,
    profile: sourceState.profile
  };
}

function remoteStatePayload(expectedUserId = activeAccount?.userId, sourceState = state) {
  const core = remoteStateCore(sourceState, expectedUserId);
  return JSON.parse(JSON.stringify({
    schemaVersion: core.schemaVersion,
    exportedAt: Date.now(),
    app: core.app,
    diagnostics: core.diagnostics,
    owner: core.owner,
    language: core.language,
    exercises: core.exercises,
    sessions: core.sessions,
    mappings: core.mappings,
    profile: core.profile
  }));
}

let remoteSaveTimer = null;
let remoteSaveInFlight = null;
let accountEpoch = 0;
let remoteStateSync = { userId: null, exists: false, revision: null };

function resetRemoteSyncContext() {
  accountEpoch += 1;
  resetLeaderboardContext();
  clearTimeout(remoteSaveTimer);
  remoteSaveTimer = null;
  remoteStateSync = { userId: null, exists: false, revision: null };
  cloudStateRecovery = null;
  cloudSyncConflict = null;
  cloudRecoveryInProgress = false;
}

function resetLeaderboardContext() {
  leaderboardRequestId += 1;
  leaderboardRequestController?.abort();
  leaderboardRequestController = null;
  leaderboardState = { status: "idle", source: null, rows: [], error: "" };
}

function bindRemoteStateRevision(record) {
  if (!UUID_PATTERN.test(record?.userId || "") ||
      (record.exists && !validRemoteStateRevision(record.revision)) ||
      (!record.exists && record.revision != null)) throw new Error("Cloud revision is invalid.");
  remoteStateSync = { userId: record.userId, exists: Boolean(record.exists), revision: record.revision || null };
}

function validRemoteStateRevision(value) {
  return typeof value === "string" && value.length <= 64 &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
    Number.isFinite(Date.parse(value));
}

function syncBaselineKey(userId) {
  if (!UUID_PATTERN.test(userId || "")) throw new Error("Cloud baseline owner is invalid.");
  return `${SYNC_BASELINE_PREFIX}${userId}`;
}

function remoteStateFingerprint(sourceState = state, userId = activeAccount?.userId) {
  const canonicalJson = value => {
    if (value === null || typeof value !== "object") return JSON.stringify(value);
    if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
    return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  };
  const bytes = new TextEncoder().encode(canonicalJson(remoteStateCore(sourceState, userId)));
  const mask = 0xffffffffffffffffn;
  const prime = 0x100000001b3n;
  let forward = 0xcbf29ce484222325n;
  let reverse = 0x84222325cbf29ce4n;
  for (let index = 0; index < bytes.length; index += 1) {
    forward = ((forward ^ BigInt(bytes[index])) * prime) & mask;
    reverse = ((reverse ^ BigInt(bytes[bytes.length - index - 1])) * prime) & mask;
  }
  return `${bytes.length.toString(16)}:${forward.toString(16).padStart(16, "0")}:${reverse.toString(16).padStart(16, "0")}`;
}

function validStateFingerprint(value) {
  return typeof value === "string" && /^[0-9a-f]{1,8}:[0-9a-f]{16}:[0-9a-f]{16}$/.test(value);
}

function normalizeSyncBaseline(value, userId) {
  if (!value || typeof value !== "object" || Array.isArray(value) || value.version !== 1 ||
      value.userId !== userId || ![true, false, null].includes(value.remoteExists) ||
      (value.remoteExists === true ? !validRemoteStateRevision(value.revision) : value.revision !== null) ||
      (value.syncedFingerprint !== null && !validStateFingerprint(value.syncedFingerprint)) ||
      !validStateFingerprint(value.localFingerprint) || typeof value.dirty !== "boolean" ||
      (value.pending !== undefined && value.pending !== null && (!value.pending || typeof value.pending !== "object" ||
        Array.isArray(value.pending) || !validStateFingerprint(value.pending.payloadFingerprint) ||
        typeof value.pending.baseExists !== "boolean" ||
        (value.pending.baseExists ? !validRemoteStateRevision(value.pending.baseRevision) : value.pending.baseRevision !== null) ||
        (value.pending.baseFingerprint !== null && !validStateFingerprint(value.pending.baseFingerprint)) ||
        !Number.isSafeInteger(value.pending.startedAt) || value.pending.startedAt < 0)) ||
      !Number.isSafeInteger(value.updatedAt) || value.updatedAt < 0) {
    return null;
  }
  return {
    version: 1,
    userId,
    remoteExists: value.remoteExists,
    revision: value.revision,
    syncedFingerprint: value.syncedFingerprint,
    localFingerprint: value.localFingerprint,
    dirty: value.dirty,
    pending: value.pending == null ? null : {
      payloadFingerprint: value.pending.payloadFingerprint,
      baseExists: value.pending.baseExists,
      baseRevision: value.pending.baseRevision,
      baseFingerprint: value.pending.baseFingerprint,
      startedAt: value.pending.startedAt
    },
    updatedAt: value.updatedAt
  };
}

function loadSyncBaseline(userId) {
  try {
    const key = syncBaselineKey(userId);
    const raw = localStorage.getItem(key);
    if (!raw || new TextEncoder().encode(raw).byteLength > MAX_SYNC_BASELINE_STORAGE_BYTES) {
      if (raw) localStorage.removeItem(key);
      return null;
    }
    const baseline = normalizeSyncBaseline(JSON.parse(raw), userId);
    if (!baseline) localStorage.removeItem(key);
    return baseline;
  } catch {
    return null;
  }
}

function saveSyncBaseline(baseline) {
  const normalized = normalizeSyncBaseline(baseline, baseline?.userId);
  if (!normalized) throw new Error("Cloud sync baseline is invalid.");
  const encoded = JSON.stringify(normalized);
  if (new TextEncoder().encode(encoded).byteLength > MAX_SYNC_BASELINE_STORAGE_BYTES) {
    throw new Error("Cloud sync baseline is too large.");
  }
  const key = syncBaselineKey(normalized.userId);
  localStorage.setItem(key, encoded);
  const stored = loadSyncBaseline(normalized.userId);
  if (!stored || stored.localFingerprint !== normalized.localFingerprint ||
      stored.updatedAt !== normalized.updatedAt) {
    throw new Error("Cloud sync baseline could not be saved.");
  }
  return stored;
}

function syncedBaseline(userId, cloudState, fingerprint) {
  return {
    version: 1,
    userId,
    remoteExists: Boolean(cloudState.exists),
    revision: cloudState.exists ? cloudState.revision : null,
    syncedFingerprint: fingerprint,
    localFingerprint: fingerprint,
    dirty: false,
    pending: null,
    updatedAt: Date.now()
  };
}

function markRemoteStateDirtyBeforeWrite(nextState = state) {
  const userId = activeAccount?.remote === "supabase" ? activeAccount.userId : null;
  if (!userId) return null;
  const fingerprint = remoteStateFingerprint(nextState, userId);
  const baseline = loadSyncBaseline(userId);
  if (baseline?.dirty && baseline.localFingerprint === fingerprint) return baseline;
  const next = {
    version: 1,
    userId,
    remoteExists: baseline?.remoteExists ?? null,
    revision: baseline?.revision ?? null,
    syncedFingerprint: baseline?.syncedFingerprint ?? null,
    localFingerprint: fingerprint,
    dirty: baseline?.dirty === true || baseline?.syncedFingerprint !== fingerprint,
    pending: baseline?.pending ?? null,
    updatedAt: Date.now()
  };
  return saveSyncBaseline(next);
}

function queueRemoteSave() {
  if (!activeAccount?.remote || !remoteAuthEnabled() || cloudStateRecovery || cloudSyncConflict) return;
  clearTimeout(remoteSaveTimer);
  const expectedEpoch = accountEpoch;
  const expectedUserId = activeAccount.userId;
  remoteSaveTimer = setTimeout(() => {
    remoteSaveTimer = null;
    startRemoteSave({ expectedEpoch, expectedUserId })
      .then(showRemoteSaveResult)
      .catch(handleRemoteSaveError);
  }, 700);
}

function startRemoteSave(options = {}) {
  const previous = remoteSaveInFlight;
  const operation = (previous ? previous.catch(() => {}) : Promise.resolve())
    .then(async () => {
      const expectedUserId = options.expectedUserId ?? activeAccount?.userId;
      if (!expectedUserId || activeAccount?.userId !== expectedUserId) {
        throw new Error("Cloud save belongs to a stale account session.");
      }
      let baseline = loadSyncBaseline(expectedUserId);
      if (baseline?.pending || (baseline?.dirty && remoteStateSync.userId !== expectedUserId)) {
        await pullRemoteState();
        baseline = loadSyncBaseline(expectedUserId);
      }
      if (cloudStateRecovery?.userId === expectedUserId) {
        throw new Error("Cloud state recovery must be resolved before saving.");
      }
      if (cloudSyncConflict?.userId === expectedUserId) {
        throw new Error("Cloud sync conflicted and needs an explicit version choice.");
      }
      if (baseline?.pending) {
        throw new Error("Cloud write outcome could not be reconciled.");
      }
      if (baseline && !baseline.dirty) {
        return { stateSaved: true, profileUpdated: true, reconciled: true };
      }
      return saveRemoteState(options);
    });
  remoteSaveInFlight = operation;
  operation.then(
    () => { if (remoteSaveInFlight === operation) remoteSaveInFlight = null; },
    () => { if (remoteSaveInFlight === operation) remoteSaveInFlight = null; }
  );
  return operation;
}

async function flushPendingRemoteSave() {
  if (!activeAccount?.remote || !remoteAuthEnabled()) return null;
  const expectedEpoch = accountEpoch;
  const expectedUserId = activeAccount.userId;
  if (cloudStateRecovery?.userId === expectedUserId || cloudSyncConflict?.userId === expectedUserId) {
    throw new Error("Cloud sync needs an explicit recovery or conflict choice.");
  }
  const hadPendingTimer = remoteSaveTimer !== null;
  clearTimeout(remoteSaveTimer);
  remoteSaveTimer = null;
  const inFlight = remoteSaveInFlight;
  let inFlightError = null;
  let result = null;
  if (inFlight) {
    try {
      result = await inFlight;
    } catch (error) {
      if (isTerminalRemoteAuthError(error)) throw error;
      inFlightError = error;
    }
  }
  let baseline = loadSyncBaseline(expectedUserId);
  if (hadPendingTimer || baseline?.pending || baseline?.dirty) {
    result = await startRemoteSave({ expectedEpoch, expectedUserId });
    baseline = loadSyncBaseline(expectedUserId);
  }
  if (cloudStateRecovery?.userId === expectedUserId || cloudSyncConflict?.userId === expectedUserId ||
      baseline?.pending || baseline?.dirty) {
    throw new Error("Cloud sync did not reach a confirmed clean state.");
  }
  if (inFlightError && !result) throw inFlightError;
  return result;
}

function showRemoteSaveResult(result) {
  if (result?.profileUpdated === false) {
    if (transitionToReauthentication(result.profileError)) return;
    showToast(tx(
      "Workouts synced, but the public profile summary could not be updated.",
      "Тренування синхронізовано, але публічний підсумок профілю не вдалося оновити."
    ));
  }
}

function handleRemoteSaveError(error) {
  if (transitionToReauthentication(error)) return;
  const conflict = /changed on another client|revision|stale account session/i.test(String(error?.message || ""));
  showToast(conflict
    ? tx("Cloud sync conflicted. Reload before saving again.", "Хмарні зміни конфліктують. Онови дані перед повторним збереженням.")
    : tx("Cloud sync failed. Your latest changes remain saved in this browser.", "Хмарна синхронізація не вдалася. Останні зміни збережено в цьому браузері."));
}

async function saveRemoteState({ expectedEpoch = accountEpoch, expectedUserId = activeAccount?.userId } = {}) {
  const session = loadRemoteSession();
  if (!session?.user?.id) throw new Error("Cloud session is missing.");
  if (expectedEpoch !== accountEpoch || !expectedUserId || session.user.id !== expectedUserId ||
      activeAccount?.userId !== expectedUserId) {
    throw new Error("Cloud save belongs to a stale account session.");
  }
  if (remoteStateSync.userId !== expectedUserId) {
    throw new Error("Cloud state must be loaded and validated before saving.");
  }
  const attemptState = JSON.parse(JSON.stringify(state));
  const attemptFingerprint = remoteStateFingerprint(attemptState, expectedUserId);
  const baseline = loadSyncBaseline(expectedUserId);
  if (baseline?.pending) {
    throw new Error("Cloud write outcome must be reconciled before another save.");
  }
  const pendingBaseline = {
    version: 1,
    userId: expectedUserId,
    remoteExists: baseline?.remoteExists ?? Boolean(remoteStateSync.exists),
    revision: baseline?.revision ?? (remoteStateSync.exists ? remoteStateSync.revision : null),
    syncedFingerprint: baseline?.syncedFingerprint ?? null,
    localFingerprint: remoteStateFingerprint(state, expectedUserId),
    dirty: true,
    pending: {
      payloadFingerprint: attemptFingerprint,
      baseExists: Boolean(remoteStateSync.exists),
      baseRevision: remoteStateSync.exists ? remoteStateSync.revision : null,
      baseFingerprint: baseline?.syncedFingerprint ?? null,
      startedAt: Date.now()
    },
    updatedAt: Date.now()
  };
  saveSyncBaseline(pendingBaseline);
  const payload = remoteStatePayload(expectedUserId, attemptState);
  const attemptedXp = xpForSessions(attemptState.sessions);
  let rows;
  if (remoteStateSync.exists) {
    const revision = remoteStateSync.revision;
    if (!revision) throw new Error("Cloud state revision is missing.");
    rows = await supabaseRequest(
      `/rest/v1/user_states?user_id=eq.${encodeURIComponent(expectedUserId)}&updated_at=eq.${encodeURIComponent(revision)}&select=updated_at`,
      {
        method: "PATCH",
        session,
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({ state: payload })
      }
    );
  } else {
    rows = await supabaseRequest("/rest/v1/user_states?select=updated_at", {
      method: "POST",
      session,
      headers: { Prefer: "return=representation" },
      body: JSON.stringify({ user_id: expectedUserId, state: payload })
    });
  }
  if (!Array.isArray(rows) || rows.length !== 1 || !validRemoteStateRevision(rows[0]?.updated_at)) {
    throw new Error("Cloud state changed on another client.");
  }
  if (expectedEpoch !== accountEpoch || activeAccount?.userId !== expectedUserId ||
      loadRemoteSession()?.user?.id !== expectedUserId) {
    throw new Error("Cloud save completed for a stale account session.");
  }
  const confirmedState = { userId: expectedUserId, exists: true, revision: rows[0].updated_at };
  const currentFingerprint = remoteStateFingerprint(state, expectedUserId);
  saveSyncBaseline({
    version: 1,
    userId: expectedUserId,
    remoteExists: true,
    revision: confirmedState.revision,
    syncedFingerprint: attemptFingerprint,
    localFingerprint: currentFingerprint,
    dirty: currentFingerprint !== attemptFingerprint,
    pending: null,
    updatedAt: Date.now()
  });
  bindRemoteStateRevision(confirmedState);
  try {
    const currentSession = loadRemoteSession();
    const profileSession = currentSession?.user?.id === expectedUserId
      ? currentSession
      : (session?.user?.id === expectedUserId ? session : null);
    if (!profileSession) throw new Error("Cloud profile update belongs to a stale account session.");
    await supabaseRequest("/rest/v1/profiles?on_conflict=user_id", {
      method: "POST",
      session: profileSession,
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify({
        user_id: expectedUserId,
        display_name: activeAccount.name,
        xp: attemptedXp,
        level: levelFromXp(attemptedXp),
        workouts: attemptState.sessions.length,
        updated_at: new Date().toISOString()
      })
    });
    return { stateSaved: true, profileUpdated: true };
  } catch (profileError) {
    return { stateSaved: true, profileUpdated: false, profileError };
  }
}

function draftToGarminPlan(draft = workoutDraft) {
  return window.GymGarminCloud.draftToGarminPlan(draft, { title: tx("Workout plan", "Workout plan") });
}

function discardLegacyGarminToken() {
  localStorage.removeItem(LEGACY_GARMIN_DEVICE_TOKEN_KEY);
}

function loadGarminBindings() {
  try {
    const raw = localStorage.getItem(GARMIN_DEVICE_BINDINGS_KEY) || "{}";
    if (new TextEncoder().encode(raw).byteLength > MAX_GARMIN_BINDING_STORAGE_BYTES) return Object.create(null);
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return Object.create(null);
    const entries = Object.entries(parsed);
    if (entries.length > MAX_GARMIN_BINDINGS) return Object.create(null);
    const sanitized = Object.create(null);
    let storageNeedsRewrite = false;
    entries.forEach(([userId, value]) => {
      storageNeedsRewrite ||= Boolean(value && typeof value === "object" && Object.hasOwn(value, "deviceToken"));
      const capabilityMigration = value?.version !== GARMIN_CAPABILITY_VERSION;
      if (!UUID_PATTERN.test(userId) || ![2, 3].includes(value?.version) || value.userId !== userId ||
          !UUID_PATTERN.test(value.deviceId || "")) {
        storageNeedsRewrite = true;
        return;
      }
      if (Object.hasOwn(value, "recoveryPending") && value.recoveryPending !== true) {
        storageNeedsRewrite = true;
      }
      storageNeedsRewrite ||= capabilityMigration;
      sanitized[userId] = {
        version: GARMIN_CAPABILITY_VERSION,
        userId,
        deviceId: value.deviceId,
        ...(capabilityMigration || value.recoveryPending === true
          ? { recoveryPending: true }
          : {})
      };
    });
    if (storageNeedsRewrite) {
      if (Object.keys(sanitized).length) {
        localStorage.setItem(GARMIN_DEVICE_BINDINGS_KEY, JSON.stringify(sanitized));
      } else {
        localStorage.removeItem(GARMIN_DEVICE_BINDINGS_KEY);
      }
    }
    return sanitized;
  } catch {
    return Object.create(null);
  }
}

function garminBindingForUser(userId) {
  const bindings = loadGarminBindings();
  const value = Object.hasOwn(bindings, userId) ? bindings[userId] : null;
  if (!value || value.version !== GARMIN_CAPABILITY_VERSION || value.userId !== userId ||
      !UUID_PATTERN.test(value.deviceId || "")) {
    return null;
  }
  return value;
}

function saveGarminBinding(binding) {
  if (!UUID_PATTERN.test(binding?.userId || "") || binding.version !== GARMIN_CAPABILITY_VERSION ||
      !UUID_PATTERN.test(binding.deviceId || "") ||
      (binding.recoveryPending !== undefined && binding.recoveryPending !== true)) {
    throw new Error("Invalid Garmin device binding.");
  }
  const bindings = loadGarminBindings();
  if (!Object.hasOwn(bindings, binding.userId) &&
      Object.keys(bindings).length >= MAX_GARMIN_BINDINGS) {
    throw new Error("Garmin device binding storage is full.");
  }
  bindings[binding.userId] = {
    version: GARMIN_CAPABILITY_VERSION,
    userId: binding.userId,
    deviceId: binding.deviceId,
    ...(binding.recoveryPending === true ? { recoveryPending: true } : {})
  };
  localStorage.setItem(GARMIN_DEVICE_BINDINGS_KEY, JSON.stringify(bindings));
}

function removeGarminBinding(userId) {
  if (!userId) return;
  const bindings = loadGarminBindings();
  delete bindings[userId];
  if (Object.keys(bindings).length) localStorage.setItem(GARMIN_DEVICE_BINDINGS_KEY, JSON.stringify(bindings));
  else localStorage.removeItem(GARMIN_DEVICE_BINDINGS_KEY);
}

function normalizedGarminDevice(value, { requireToken = false } = {}) {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      !UUID_PATTERN.test(value.id || "") || value.binding_version !== 2 ||
      !Number.isInteger(value.token_revision) || value.token_revision < 1 ||
      value.token_revision > 2147483647) {
    return null;
  }
  const displayName = typeof value.display_name === "string" ? value.display_name.trim() : "";
  const createdAt = typeof value.created_at === "string" ? value.created_at : "";
  const lastSeenAt = value.last_seen_at == null ? null : value.last_seen_at;
  if (!displayName || displayName.length > 80 || /[\u0000-\u001f\u007f]/.test(displayName) ||
      new TextEncoder().encode(displayName).byteLength > 320 ||
      !validRemoteStateRevision(createdAt) ||
      (lastSeenAt !== null && !validRemoteStateRevision(lastSeenAt))) {
    return null;
  }
  const token = value.device_token;
  if (requireToken) {
    if (GARMIN_CAPABILITY_VERSION === 2) {
      if (typeof token !== "string" || !GARMIN_LEGACY_CAPABILITY_PATTERN.test(token)) return null;
    } else {
      const capability = typeof token === "string"
        ? GARMIN_CAPABILITY_PATTERN.exec(token)
        : null;
      if (!capability || capability[2] !== value.id.toLowerCase()) return null;
    }
  }
  return {
    id: value.id,
    displayName,
    createdAt,
    lastSeenAt,
    bindingVersion: 2,
    tokenRevision: value.token_revision,
    ...(requireToken ? { deviceToken: token } : {})
  };
}

async function listGarminDevices(session) {
  const response = await supabaseRequest("/functions/v1/garmin-sync", {
    method: "POST",
    session,
    body: JSON.stringify({ action: "listDevices" })
  });
  if (!Array.isArray(response?.devices) || response.devices.length > 5) {
    throw new Error("Garmin device list is invalid.");
  }
  const devices = response.devices.map(value => normalizedGarminDevice(value));
  if (devices.some(value => !value) || new Set(devices.map(value => value.id)).size !== devices.length) {
    throw new Error("Garmin device list is invalid.");
  }
  return devices;
}

function newGarminReplacementToken() {
  if (!window.crypto || typeof window.crypto.getRandomValues !== "function") {
    throw new Error("Secure Garmin token generation is unavailable in this browser.");
  }
  const bytes = new Uint8Array(32);
  window.crypto.getRandomValues(bytes);
  return [...bytes].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

async function throwGarminRotationConflict(session, deviceId) {
  const refreshed = await listGarminDevices(session);
  const current = refreshed.find(device => device.id === deviceId);
  const detail = current ? ` Current token revision is ${current.tokenRevision}.` : " The device is no longer active.";
  throw new Error(`Garmin token rotation conflicted with another request.${detail} Review the watch selection and retry.`);
}

async function rotateGarminDeviceToken(session, device) {
  const deviceId = device?.id;
  const expectedTokenRevision = device?.tokenRevision;
  if (!UUID_PATTERN.test(deviceId || "") || !Number.isInteger(expectedTokenRevision) ||
      expectedTokenRevision < 1 || expectedTokenRevision > 2147483646) {
    throw new Error("Garmin device token revision is invalid or exhausted.");
  }
  const replacementToken = newGarminReplacementToken();
  const requestBody = JSON.stringify({
    action: "rotateDeviceToken",
    capabilityVersion: GARMIN_CAPABILITY_VERSION,
    deviceId,
    ...(GARMIN_CAPABILITY_VERSION === 3
      ? { replacementNonce: replacementToken }
      : { replacementToken }),
    expectedTokenRevision
  });
  const requestRotation = () => supabaseRequest("/functions/v1/garmin-sync", {
    method: "POST",
    session,
    body: requestBody
  });
  let response;
  try {
    response = await requestRotation();
  } catch (error) {
    if (error?.status === 409) return throwGarminRotationConflict(session, deviceId);
    if (error?.status !== undefined && error.status < 500) throw error;
    try {
      // Replaying this exact token and expected revision is idempotent. Never
      // generate a second secret for an outcome-unknown request.
      response = await requestRotation();
    } catch (retryError) {
      if (retryError?.status === 409) return throwGarminRotationConflict(session, deviceId);
      throw retryError;
    }
  }
  const rotated = normalizedGarminDevice(response?.device, { requireToken: true });
  const rotatedCapability = GARMIN_CAPABILITY_VERSION === 3 && rotated
    ? GARMIN_CAPABILITY_PATTERN.exec(rotated.deviceToken)
    : null;
  if (!rotated || !["rotated", "already_rotated"].includes(response?.status) ||
      rotated.id !== deviceId ||
      (GARMIN_CAPABILITY_VERSION === 3
        ? rotatedCapability?.[3] !== replacementToken
        : rotated.deviceToken !== replacementToken) ||
      rotated.tokenRevision !== expectedTokenRevision + 1) {
    throw new Error("Garmin token rotation returned an invalid device.");
  }
  return rotated;
}

function chooseGarminDeviceForRecovery(devices) {
  if (!devices.length) return null;
  if (devices.length === 1) {
    const warning = tx(
      `Restore the existing Garmin pairing “${devices[0].displayName}”? Its old token will stop immediately, and a replacement token for the same watch identity will be shown once. Cancel keeps the current token working.`,
      `Відновити наявне сполучення Garmin «${devices[0].displayName}»? Старий токен одразу перестане працювати, а новий токен для того самого годинника буде показано один раз. «Скасувати» збереже чинний токен.`
    );
    return typeof window.confirm === "function" && window.confirm(warning) ? devices[0] : null;
  }
  if (typeof window.prompt !== "function") return null;
  const options = devices.map((device, index) =>
    `${index + 1}. ${device.displayName.replace(/[\u0000-\u001f\u007f]+/g, " ")} (${device.id.slice(0, 8)})`
  ).join("\n");
  const selected = window.prompt(tx(
    `Choose the existing Garmin watch to restore (1-${devices.length}). Rotating its token preserves the watch identity:\n${options}`,
    `Обери наявний годинник Garmin для відновлення (1-${devices.length}). Ротація токена збереже ідентифікатор годинника:\n${options}`
  ), "1");
  if (selected === null || !/^[1-5]$/.test(selected.trim())) return null;
  return devices[Number(selected.trim()) - 1] || null;
}

async function recoverGarminDeviceBinding(session, device) {
  const userId = session?.user?.id;
  if (!userId || activeAccount?.userId !== userId || !device ||
      !UUID_PATTERN.test(device.id || "") || !Number.isInteger(device.tokenRevision) ||
      device.tokenRevision < 1 || device.tokenRevision > 2147483646) {
    throw new Error("Garmin recovery belongs to another account.");
  }
  const expectedEpoch = accountEpoch;
  const binding = { version: GARMIN_CAPABILITY_VERSION, userId, deviceId: device.id };
  // Persist the stable, nonsecret UUID and incomplete state before invalidating
  // the old bearer token. A lost response or closed prompt can then be retried
  // without inventing a second watch identity.
  saveGarminBinding({ ...binding, recoveryPending: true });
  const rotated = await rotateGarminDeviceToken(session, device);
  if (expectedEpoch !== accountEpoch || activeAccount?.userId !== userId ||
      loadRemoteSession()?.user?.id !== userId) {
    throw userVisibleError(
      "Garmin token rotation completed for a stale account session. Sign back into the same account and run Sync Watch to finish recovery for this watch identity.",
      "Ротацію токена Garmin завершено для застарілої сесії. Увійди в той самий акаунт і натисни «Синхронізувати з годинником», щоб завершити відновлення цього годинника."
    );
  }
  let rawToken = rotated.deviceToken;
  const tokenPrompt = tx(
    "Paste this replacement token into the same watch's Connect IQ settings now. The old token has stopped working. This token will not be stored or shown again.",
    "Встав цей новий токен у налаштування Connect IQ того самого годинника. Старий токен уже не працює. Новий токен не зберігатиметься й більше не показуватиметься."
  );
  const acknowledged = typeof window.prompt === "function"
    ? window.prompt(tokenPrompt, rawToken)
    : null;
  rawToken = null;
  if (acknowledged === null) {
    throw userVisibleError(
      "The replacement Garmin token was not confirmed. Run Sync Watch again to rotate another token for the same watch identity.",
      "Новий токен Garmin не підтверджено. Ще раз натисни «Синхронізувати з годинником», щоб створити інший токен для того самого ідентифікатора годинника."
    );
  }
  saveGarminBinding(binding);
  return binding;
}

async function ensureGarminDeviceBinding(session) {
  const userId = session?.user?.id;
  if (!userId || activeAccount?.userId !== userId) throw new Error("Garmin pairing belongs to another account.");
  const expectedEpoch = accountEpoch;
  const assertCurrentAccount = () => {
    if (expectedEpoch !== accountEpoch || activeAccount?.userId !== userId ||
        loadRemoteSession()?.user?.id !== userId) {
      throw new Error("Garmin pairing was cancelled for a stale account session.");
    }
  };
  const pendingDeviceId = pendingGarminRevocations.get(userId);
  if (pendingDeviceId) {
    try {
      await revokeGarminDeviceById(session, pendingDeviceId);
      pendingGarminRevocations.delete(userId);
    } catch {
      throw userVisibleError(
        "A previous Garmin device creation is still awaiting revocation. Keep this page open and retry before pairing again.",
        "Попереднє створення пристрою Garmin ще очікує відкликання. Не закривай цю сторінку й повтори спробу перед новим сполученням."
      );
    }
    assertCurrentAccount();
  }
  const current = garminBindingForUser(userId);
  if (current?.recoveryPending) {
    const refreshedDevices = await listGarminDevices(session);
    assertCurrentAccount();
    const pendingDevice = refreshedDevices.find(device => device.id === current.deviceId);
    if (!pendingDevice) {
      removeGarminBinding(userId);
      throw userVisibleError(
        "The pending Garmin device is no longer active. Run Sync Watch again to choose or create a pairing.",
        "Пристрій Garmin, що очікував на сполучення, більше не активний. Знову натисни «Синхронізувати з годинником», щоб вибрати або створити сполучення."
      );
    }
    const retryWarning = tx(
      "Finish the pending Garmin recovery? This rotates a replacement token for the same watch identity and shows it once. Cancel leaves the current server token unchanged.",
      "Завершити незакінчене відновлення Garmin? Буде створено новий токен для того самого ідентифікатора годинника й показано один раз. «Скасувати» не змінить чинний серверний токен."
    );
    if (typeof window.confirm !== "function" || !window.confirm(retryWarning)) {
      throw userVisibleError(
        "Pending Garmin recovery was not changed.",
        "Незавершене відновлення Garmin не змінено."
      );
    }
    const binding = await recoverGarminDeviceBinding(session, pendingDevice);
    return { binding, created: false, rotated: true };
  }
  if (current) return { binding: current, created: false };
  const existingDevices = await listGarminDevices(session);
  assertCurrentAccount();
  if (existingDevices.length) {
    const selectedDevice = chooseGarminDeviceForRecovery(existingDevices);
    if (!selectedDevice) {
      throw userVisibleError(
        "Existing Garmin recovery was cancelled. No new device identity was created.",
        "Відновлення наявного сполучення Garmin скасовано. Новий ідентифікатор пристрою не створено."
      );
    }
    const binding = await recoverGarminDeviceBinding(session, selectedDevice);
    return { binding, created: false, rotated: true };
  }
  const pairingWarning = tx(
    "A one-time Garmin token will be shown. It works like a password: paste it only into this watch's Connect IQ settings. GymApp will not store or show it again. Continue?",
    "Буде показано одноразовий токен Garmin. Він працює як пароль: встав його лише в налаштування Connect IQ цього годинника. GymApp не збереже та більше не покаже його. Продовжити?"
  );
  if (typeof window.confirm !== "function" || !window.confirm(pairingWarning)) {
    throw userVisibleError("Garmin pairing was cancelled.", "Сполучення Garmin скасовано.");
  }
  const response = await supabaseRequest("/functions/v1/garmin-sync", {
    method: "POST",
    session,
    body: JSON.stringify({ action: "createDevice", capabilityVersion: GARMIN_CAPABILITY_VERSION, displayName: "Garmin watch" })
  });
  const device = response?.device;
  const normalizedDevice = normalizedGarminDevice(device, { requireToken: true });
  if (!normalizedDevice || normalizedDevice.tokenRevision !== 1) {
    throw new Error("Garmin device binding was not created.");
  }
  const binding = { version: GARMIN_CAPABILITY_VERSION, userId, deviceId: device.id };
  pendingGarminRevocations.set(userId, device.id);
  if (expectedEpoch !== accountEpoch || activeAccount?.userId !== userId || loadRemoteSession()?.user?.id !== userId) {
    try {
      await revokeGarminDeviceById(session, device.id);
      pendingGarminRevocations.delete(userId);
    } catch {
      // Keep the nonsecret device ID in memory for the next in-session retry.
    }
    throw new Error("Garmin pairing completed for a stale account session.");
  }
  try {
    // Persist the nonsecret device ID before the raw one-time token is revealed.
    // If storage fails, no user-visible capability has escaped this function.
    saveGarminBinding({ ...binding, recoveryPending: true });
    pendingGarminRevocations.delete(userId);
  } catch {
    let revoked = false;
    try {
      await revokeGarminDeviceById(session, device.id);
      revoked = true;
    } catch {
      // Retain the nonsecret device ID for retry while this page remains open.
    }
    if (revoked) {
      pendingGarminRevocations.delete(userId);
      throw userVisibleError(
        "The Garmin binding could not be saved, so the unseen token was revoked. Free browser storage and try again.",
        "Не вдалося зберегти прив’язку Garmin, тому непоказаний токен відкликано. Звільни місце в сховищі браузера й спробуй ще раз."
      );
    }
    throw userVisibleError(
      "The unseen Garmin token could not be persisted or revoked. Keep this page open and retry Garmin sync or sign-out to revoke it.",
      "Непоказаний токен Garmin не вдалося ні зберегти, ні відкликати. Не закривай цю сторінку: повтори синхронізацію з Garmin або вийди з акаунта, щоб відкликати токен."
    );
  }
  const tokenPrompt = tx(
    "Copy this Garmin pairing token into Connect IQ settings now. Treat it as a password. It will not be stored or shown again. Choose Cancel to revoke it.",
    "Зараз скопіюй цей токен сполучення Garmin у налаштування Connect IQ. Стався до нього як до пароля. Він не буде збережений або показаний знову. Натисни «Скасувати», щоб відкликати його."
  );
  const acknowledged = typeof window.prompt === "function"
    ? window.prompt(tokenPrompt, device.device_token)
    : null;
  if (acknowledged === null) {
    try {
      await revokeGarminDeviceById(session, device.id);
      removeGarminBinding(userId);
    } catch {
      throw userVisibleError(
        "The Garmin token could not be revoked. Use Unpair Garmin to retry revocation, or run Sync Watch again to rotate a replacement token for the same watch identity.",
        "Не вдалося відкликати токен Garmin. Скористайся «Від’єднати Garmin», щоб повторити відкликання, або ще раз натисни «Синхронізувати з годинником», щоб оновити токен того самого годинника."
      );
    }
    throw userVisibleError("Garmin pairing was cancelled.", "Сполучення Garmin скасовано.");
  }
  saveGarminBinding(binding);
  return { binding, created: true };
}

async function revokeGarminDeviceById(session, deviceId) {
  if (!UUID_PATTERN.test(deviceId || "")) {
    throw new Error("Garmin device binding is invalid.");
  }
  const response = await supabaseRequest("/functions/v1/garmin-sync", {
    method: "POST",
    session,
    body: JSON.stringify({ action: "revokeDevice", deviceId })
  });
  if (!response || !["revoked", "already_revoked"].includes(response.status)) {
    throw new Error("Garmin device revocation was not confirmed.");
  }
}

async function revokeGarminBinding(session) {
  const userId = session?.user?.id;
  if (!userId) throw new Error("Cloud session is missing.");
  const binding = garminBindingForUser(userId);
  if (!binding) return;
  await revokeGarminDeviceById(session, binding.deviceId);
  removeGarminBinding(userId);
}

function garminLogicalPlanJson(plan) {
  const { createdAt: _createdAt, ...logicalPlan } = plan;
  return JSON.stringify(logicalPlan);
}

function loadGarminEnqueueRequests() {
  try {
    const raw = localStorage.getItem(GARMIN_ENQUEUE_REQUESTS_KEY) || "{}";
    if (new TextEncoder().encode(raw).byteLength > MAX_GARMIN_ENQUEUE_STORAGE_BYTES) {
      localStorage.removeItem(GARMIN_ENQUEUE_REQUESTS_KEY);
      return Object.create(null);
    }
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) ||
        Object.keys(parsed).length > MAX_GARMIN_ENQUEUE_REQUESTS) {
      localStorage.removeItem(GARMIN_ENQUEUE_REQUESTS_KEY);
      return Object.create(null);
    }
    const safe = Object.create(null);
    let rewrite = false;
    for (const [userId, value] of Object.entries(parsed)) {
      const planJson = typeof value?.planJson === "string" ? value.planJson : "";
      const logicalPlanJson = typeof value?.logicalPlanJson === "string" ? value.logicalPlanJson : "";
      if (!UUID_PATTERN.test(userId) || value?.version !== 1 || value.userId !== userId ||
          !UUID_PATTERN.test(value.deviceId || "") || !UUID_V4_PATTERN.test(value.requestId || "") ||
          new TextEncoder().encode(planJson).byteLength > 64 * 1024 ||
          new TextEncoder().encode(logicalPlanJson).byteLength > 64 * 1024 ||
          (value.conflict !== undefined && value.conflict !== true)) {
        rewrite = true;
        continue;
      }
      let validation;
      try {
        validation = window.GymGarminCloud.validateGarminPlan(JSON.parse(planJson));
      } catch {
        validation = null;
      }
      if (!validation?.ok || logicalPlanJson !== garminLogicalPlanJson(validation.plan)) {
        rewrite = true;
        continue;
      }
      safe[userId] = {
        version: 1,
        userId,
        deviceId: value.deviceId,
        requestId: value.requestId,
        planJson: JSON.stringify(validation.plan),
        logicalPlanJson,
        ...(value.conflict === true ? { conflict: true } : {})
      };
    }
    if (rewrite) saveGarminEnqueueRequests(safe);
    return safe;
  } catch {
    return Object.create(null);
  }
}

function saveGarminEnqueueRequests(requests) {
  const entries = Object.entries(requests || {});
  if (entries.length > MAX_GARMIN_ENQUEUE_REQUESTS) {
    throw new Error("Garmin enqueue request storage is full.");
  }
  if (!entries.length) {
    localStorage.removeItem(GARMIN_ENQUEUE_REQUESTS_KEY);
    return;
  }
  const encoded = JSON.stringify(Object.fromEntries(entries));
  if (new TextEncoder().encode(encoded).byteLength > MAX_GARMIN_ENQUEUE_STORAGE_BYTES) {
    throw new Error("Garmin enqueue request storage exceeds its limit.");
  }
  localStorage.setItem(GARMIN_ENQUEUE_REQUESTS_KEY, encoded);
}

function removeGarminEnqueueRequestsForUser(userId) {
  if (!UUID_PATTERN.test(userId || "")) return;
  const requests = loadGarminEnqueueRequests();
  if (!Object.hasOwn(requests, userId)) return;
  delete requests[userId];
  saveGarminEnqueueRequests(requests);
}

function newUuidV4() {
  if (!window.crypto || typeof window.crypto.getRandomValues !== "function") {
    throw new Error("Secure request ID generation is unavailable in this browser.");
  }
  const bytes = new Uint8Array(16);
  window.crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map(byte => byte.toString(16).padStart(2, "0"));
  return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`;
}

function clearGarminEnqueueRequest(userId, requestId) {
  const requests = loadGarminEnqueueRequests();
  if (requests[userId]?.requestId !== requestId) return;
  delete requests[userId];
  saveGarminEnqueueRequests(requests);
}

function prepareGarminEnqueueRequest(userId, deviceId, candidatePlan) {
  const validation = window.GymGarminCloud.validateGarminPlan(candidatePlan);
  if (!validation?.ok) throw new Error("Garmin plan is invalid.");
  const candidateLogicalJson = garminLogicalPlanJson(validation.plan);
  const requests = loadGarminEnqueueRequests();
  const existing = requests[userId];
  const sameLogicalRequest = existing?.deviceId === deviceId &&
    existing.logicalPlanJson === candidateLogicalJson;
  if (existing && sameLogicalRequest && existing.conflict !== true) {
    return { record: existing, plan: JSON.parse(existing.planJson) };
  }
  if (existing) {
    const warning = existing.conflict === true
      ? tx(
          "The previous Garmin request ID conflicted with server state. Start a new request ID for this submission? Cancel keeps the conflict for review.",
          "Попередній Garmin request ID конфліктує зі станом сервера. Створити новий request ID для цього надсилання? «Скасувати» збереже конфлікт для перевірки."
        )
      : tx(
          "A previous Garmin queue result is still unknown. Start a different logical submission anyway? It may create a second plan if the earlier request succeeded. Cancel is recommended.",
          "Результат попереднього Garmin-запиту ще невідомий. Усе одно почати інше надсилання? Якщо попередній запит спрацював, може з’явитися другий план. Рекомендовано скасувати."
        );
    if (typeof window.confirm !== "function" || !window.confirm(warning)) {
      throw userVisibleError(
        "Garmin queue retry remains pending review.",
        "Повторне надсилання в чергу Garmin залишається на перевірці."
      );
    }
  }
  const record = {
    version: 1,
    userId,
    deviceId,
    requestId: newUuidV4(),
    planJson: JSON.stringify(validation.plan),
    logicalPlanJson: candidateLogicalJson
  };
  requests[userId] = record;
  saveGarminEnqueueRequests(requests);
  return { record, plan: validation.plan };
}

function markGarminEnqueueConflict(userId, requestId) {
  const requests = loadGarminEnqueueRequests();
  if (requests[userId]?.requestId !== requestId) return;
  requests[userId] = { ...requests[userId], conflict: true };
  saveGarminEnqueueRequests(requests);
}

async function enqueueGarminPlan(session, binding, candidatePlan) {
  const userId = session?.user?.id;
  if (!userId || activeAccount?.userId !== userId || binding?.userId !== userId ||
      !UUID_PATTERN.test(binding.deviceId || "")) {
    throw new Error("Garmin enqueue belongs to another account or device.");
  }
  const { record, plan } = prepareGarminEnqueueRequest(userId, binding.deviceId, candidatePlan);
  const requestBody = JSON.stringify({
    p_device_id: binding.deviceId,
    p_plan: plan,
    p_client_request_id: record.requestId
  });
  const request = () => supabaseRequest("/rest/v1/rpc/garmin_enqueue_plan", {
    method: "POST",
    session,
    body: requestBody
  });
  let response;
  try {
    response = await request();
  } catch (error) {
    if (error?.status !== undefined && error.status < 500) {
      clearGarminEnqueueRequest(userId, record.requestId);
      throw error;
    }
    try {
      response = await request();
    } catch (retryError) {
      if (retryError?.status !== undefined && retryError.status < 500) {
        clearGarminEnqueueRequest(userId, record.requestId);
      }
      throw retryError;
    }
  }
  if (response?.status === "conflict") {
    markGarminEnqueueConflict(userId, record.requestId);
    throw new Error("Garmin enqueue request ID conflicted with different server content.");
  }
  if (typeof response?.error === "string") {
    clearGarminEnqueueRequest(userId, record.requestId);
    const allowedErrors = new Set([
      "Unauthorized",
      "Invalid enqueue request",
      "Invalid Garmin plan",
      "Device not found",
      "Plan creation limit reached"
    ]);
    throw new Error(allowedErrors.has(response.error) ? response.error : "Garmin enqueue failed.");
  }
  const allowedStatuses = new Set(["pending", "downloaded", "completed", "invalid", "superseded"]);
  if (!["queued", "already_queued"].includes(response?.status) ||
      !UUID_PATTERN.test(response.planId || "") ||
      !Number.isInteger(response.planRevision) || response.planRevision < 1 ||
      response.planRevision > 2147483647 || !allowedStatuses.has(response.planStatus) ||
      (response.status === "queued" && response.planStatus !== "pending")) {
    throw new Error("Garmin enqueue returned an invalid response; retry will reuse the same request ID.");
  }
  clearGarminEnqueueRequest(userId, record.requestId);
  return response;
}

async function queueGarminPlanFromDraft() {
  if (accountTransitionInProgress) {
    return showToast(tx("Wait for the account operation to finish.", "Дочекайся завершення операції з акаунтом."));
  }
  if (garminSyncInProgress) {
    return showToast(tx("Garmin sync is already in progress.", "Синхронізація з Garmin уже виконується."));
  }
  if (!remoteAuthEnabled()) return showToast(tx("Cloud login is not configured.", "Вхід у хмарний акаунт не налаштовано."));
  const session = loadRemoteSession();
  if (!session?.user?.id) return showToast(tx("Log in to cloud first.", "Спочатку увійди в хмарний акаунт."));
  const plan = draftToGarminPlan();
  if (!plan) return showToast(tx("Please fill exercises and sets first.", "Спочатку додай вправи й підходи."));
  const expectedEpoch = accountEpoch;
  const expectedUserId = session.user.id;
  const lockManager = navigator?.locks;
  if (!lockManager || typeof lockManager.request !== "function") {
    return showToast(tx(
      "Secure cross-tab Garmin sync is unavailable in this browser. Close other GymApp tabs and use a supported browser before retrying.",
      "Безпечна синхронізація з Garmin між вкладками недоступна в цьому браузері. Закрий інші вкладки GymApp і повтори в підтримуваному браузері."
    ));
  }
  garminSyncInProgress = true;
  try {
    let lockAcquired = false;
    await lockManager.request(`gymapp-garmin-sync:${expectedUserId}`, {
      mode: "exclusive",
      ifAvailable: true
    }, async lock => {
      if (!lock) return;
      lockAcquired = true;
      if (expectedEpoch !== accountEpoch || activeAccount?.userId !== expectedUserId ||
          loadRemoteSession()?.user?.id !== expectedUserId) {
        throw new Error("Garmin sync was cancelled for a stale account session.");
      }
      const { binding, created, rotated } = await ensureGarminDeviceBinding(session);
      if (expectedEpoch !== accountEpoch || activeAccount?.userId !== expectedUserId ||
          loadRemoteSession()?.user?.id !== expectedUserId) {
        throw new Error("Garmin sync was cancelled for a stale account session.");
      }

      await enqueueGarminPlan(session, binding, plan);
      if (expectedEpoch !== accountEpoch || activeAccount?.userId !== expectedUserId ||
          loadRemoteSession()?.user?.id !== expectedUserId) {
        throw new Error("Garmin plan was queued for the previous account; switch back to manage it.");
      }

      if (rotated) {
        showToast(tx("Garmin token rotated for the existing watch. Save it in Connect IQ settings, then sync on the watch.", "Токен Garmin оновлено для наявного годинника. Збережи його в налаштуваннях Connect IQ і запусти синхронізацію на годиннику."));
      } else if (created) {
        showToast(tx("Garmin token shown once. After saving it in Connect IQ settings, sync on the watch.", "Токен Garmin показано один раз. Збережи його в налаштуваннях Connect IQ і запусти синхронізацію на годиннику."));
      } else {
        showToast(tx("Plan queued for Garmin. Open the watch app and run Cloud sync.", "План додано в чергу Garmin. Відкрий застосунок на годиннику й запусти хмарну синхронізацію."));
      }
    });
    if (!lockAcquired) {
      showToast(tx(
        "Garmin sync is already running in another GymApp tab. Finish it there before retrying.",
        "Синхронізація з Garmin уже виконується в іншій вкладці GymApp. Заверши її там перед повторною спробою."
      ));
    }
  } finally {
    garminSyncInProgress = false;
  }
}

function loadState(account = activeAccount) {
  const fallback = defaultAppState();
  try {
    const currentRaw = localStorage.getItem(activeStorageKey(account));
    const legacyRaw = localStorage.getItem(LEGACY_KEY);
    const raw = currentRaw || (!account ? legacyRaw : null);
    if (!raw) return fallback;
    const loaded = validateImportedEnvelope(raw, fallback).state;
    const catalogChanged = ensureBuiltInExerciseCatalog(loaded);
    if (catalogChanged) {
      try {
        localStorage.setItem(activeStorageKey(account), JSON.stringify(loaded));
      } catch {
        // Keep the valid account usable in memory; the next normal mutation retries persistence.
      }
    }
    return loaded;
  } catch {
    return fallback;
  }
}

function normalizeImportedState(parsed, fallback = defaultAppState()) {
  return validateImportedEnvelope(parsed, fallback).state;
}

function validateImportedEnvelope(input, fallback = defaultAppState()) {
  const validated = window.GymStateContract.validateAndNormalize(input, { fallback });
  const safe = validated.state;
  return {
    owner: validated.owner,
    diagnostics: validated.diagnostics,
    state: {
      language: safe.language,
      catalogSeedVersion: safe.catalogSeedVersion,
      exercises: normalizeExerciseCatalog(safe.exercises, fallback.exercises),
      sessions: normalizeSessions(safe.sessions),
      mappings: normalizeExerciseMappings(safe.mappings, fallback.mappings),
      profile: safe.profile,
      ...(safe.progressExerciseId ? { progressExerciseId: safe.progressExerciseId } : {})
    }
  };
}

function exerciseCatalogInput(value) {
  if (Array.isArray(value?.exercises)) return value.exercises;
  if (Array.isArray(value?.exerciseCatalog)) return value.exerciseCatalog;
  return undefined;
}

function normalizeExerciseMappings(input, fallback = {}) {
  const normalized = Object.create(null);
  Object.entries(fallback || {}).forEach(([rawName, muscleIds]) => {
    if (Array.isArray(muscleIds)) normalized[normalizeExerciseName(rawName)] = [...muscleIds];
  });
  Object.entries(input || {}).forEach(([rawName, muscleIds]) => {
    if (!Array.isArray(muscleIds)) return;
    normalized[normalizeExerciseName(rawName)] = muscleIds
      .map(String)
      .filter(muscleId => muscles.some(([id]) => id === muscleId));
  });
  return normalized;
}

function normalizeSessions(sessions) {
  if (!Array.isArray(sessions)) return [];
  return sessions.flatMap(session => {
    if (!session || typeof session !== "object") return [];
    return [{
      id: Number(session.id || uid()),
      startedAt: Number(session.startedAt ?? session.date ?? Date.now()),
      note: session.note ?? "",
      exerciseNames: normalizeSessionExerciseNames(session),
      sets: normalizeSessionSets(session)
    }];
  });
}

function normalizeSessionSets(session) {
  const flatSets = Array.isArray(session.sets) ? session.sets : [];
  const sessionExercises = nestedSessionExercises(session);
  const nestedSets = sessionExercises
    .flatMap(exercise => nestedExerciseSets(exercise).flatMap(set => {
      if (!set || typeof set !== "object") return [];
      const inheritedCatalogKey = persistedExerciseCatalogKey(exercise.exercise && typeof exercise.exercise === "object" ? exercise.exercise : exercise);
      return [{
        ...set,
        exerciseName: set.exerciseName || exerciseNameFromImport(exercise),
        ...(explicitCatalogKey(set) ? {} : inheritedCatalogKey ? { catalogKey: inheritedCatalogKey } : {})
      }];
    }));
  // Our schema-v2 export contains both a flat list and nested presentation
  // blocks. Prefer the flat list so importing our own backup cannot duplicate history.
  const sourceSets = flatSets.length ? flatSets : nestedSets;
  return sourceSets.flatMap((set, index) => {
    if (!set || typeof set !== "object") return [];
    const exerciseName = set.exerciseName || set.name || set.exercise || set.title;
    if (!exerciseName) return [];
    const catalogKey = persistedExerciseCatalogKey(set);
    return [{
      id: Number(set.id || uid() + index),
      exerciseName: String(exerciseName).trim(),
      ...(catalogKey ? { catalogKey } : {}),
      weight: Number(set.weight ?? set.weightKg ?? set.kg ?? 0),
      reps: Number(set.reps ?? set.repeatCount ?? set.count ?? 0),
      orderIndex: set.orderIndex ?? set.index ?? index
    }];
  }).filter(set => set.reps > 0);
}

function normalizeSessionExerciseNames(session) {
  const names = [
    ...(Array.isArray(session.exerciseNames) ? session.exerciseNames.map(exerciseNameFromImport) : []),
    ...nestedSessionExercises(session).map(exerciseNameFromImport),
    ...(Array.isArray(session.sets) ? session.sets.map(exerciseNameFromImport) : [])
  ].map(name => String(name || "").trim()).filter(Boolean);
  return [...new Set(names)];
}

function nestedSessionExercises(session) {
  return [session.exercises, session.workoutExercises, session.exerciseDetails, session.items]
    .find(Array.isArray) || [];
}

function nestedExerciseSets(exercise) {
  if (!exercise || typeof exercise !== "object") return [];
  return [exercise.sets, exercise.setEntries, exercise.entries, exercise.history]
    .find(Array.isArray) || [];
}

function exerciseNameFromImport(exercise) {
  if (typeof exercise === "string") return exercise;
  if (!exercise || typeof exercise !== "object") return "";
  if (exercise.exercise && typeof exercise.exercise === "object") return exercise.exercise.name || exercise.exercise.title;
  return exercise.name || exercise.exerciseName || exercise.title;
}

function normalizeExerciseCatalog(input, fallback = []) {
  const items = Array.isArray(input) ? input : Array.isArray(fallback) ? fallback : [];
  const normalized = items.flatMap((item, index) => {
    const rawName = exerciseRawName(item);
    const catalogKey = persistedExerciseCatalogKey(item);
    const record = item && typeof item === "object" ? item : null;
    const hasFavorite = Boolean(record && Object.hasOwn(record, "favorite"));
    const hasLegacyFavorite = Boolean(record && Object.hasOwn(record, "isFavorite"));
    const favorite = hasFavorite ? record.favorite : record?.isFavorite;
    if (!rawName) return [];
    return [{
      id: Number(typeof item === "object" && item?.id || index + 1),
      name: rawName,
      ...(catalogKey ? { catalogKey } : {}),
      ...(hasFavorite || hasLegacyFavorite ? { favorite: favorite === true } : {})
    }];
  });
  return normalized;
}

function preserveExerciseFavorites(nextState, previousState, { preferPrevious = false } = {}) {
  if (!nextState || !Array.isArray(nextState.exercises) || !Array.isArray(previousState?.exercises)) {
    return nextState;
  }
  const previousByKey = new Map(previousState.exercises.map(exercise => [exerciseMatchKey(exercise), exercise]));
  nextState.exercises = nextState.exercises.map(exercise => {
    const previous = previousByKey.get(exerciseMatchKey(exercise));
    const hasIncomingFavorite = Object.hasOwn(exercise, "favorite");
    if (!preferPrevious && hasIncomingFavorite) return exercise;
    const merged = { ...exercise };
    delete merged.favorite;
    if (previous?.favorite === true) merged.favorite = true;
    return merged;
  });
  return nextState;
}

function saveState({ queueRemote = true, markDirty = true } = {}) {
  // Treat every mutation as a security boundary, including values produced by
  // UI event handlers. This prevents a missed range/count check from reaching
  // local storage or the cloud queue.
  window.GymStateContract.validateAndNormalize({ schemaVersion: 2, ...state }, {
    fallback: defaultAppState()
  });
  if (markDirty) markRemoteStateDirtyBeforeWrite(state);
  localStorage.setItem(activeStorageKey(), JSON.stringify(state));
  if (queueRemote) queueRemoteSave();
}

function uid() {
  return Date.now() + Math.floor(Math.random() * 100000);
}

function route() {
  return nav[nav.length - 1];
}

function routeScrollKey(current = route()) {
  return `${current.name}:${current.id ?? "root"}`;
}

function visibleScrollContainer() {
  const main = app.querySelector("main[data-scroll-key]");
  return main;
}

function rememberVisibleScroll() {
  const main = app.querySelector("main[data-scroll-key]");
  const scroller = main;
  if (main?.dataset.scrollKey && scroller) {
    routeScrollPositions.set(main.dataset.scrollKey, scroller.scrollTop);
  }
}

function restoreVisibleScroll() {
  const main = app.querySelector("main[data-scroll-key]");
  const scroller = main;
  if (!main?.dataset.scrollKey || !scroller) return;
  scroller.scrollTop = routeScrollPositions.get(main.dataset.scrollKey) || 0;
}

function navigationState() {
  return { gymAppNav: nav.map(item => ({ name: item.name, ...(Number.isSafeInteger(item.id) ? { id: item.id } : {}) })) };
}

function replaceNavigationHistory() {
  history.replaceState(navigationState(), "");
}

function pushNavigationHistory() {
  history.pushState(navigationState(), "");
}

function validatedHistoryNav(value) {
  const rootNames = new Set(["workouts", "missions", "exercises", "progress", "leaderboard"]);
  const childNames = new Set(["add", "detail", "summary", "ranks"]);
  if (!Array.isArray(value) || !value.length || value.length > 4) return null;
  const result = [];
  for (const [index, item] of value.entries()) {
    if (!item || typeof item !== "object" || typeof item.name !== "string") return null;
    if (index === 0 && !rootNames.has(item.name)) return null;
    if (index > 0 && !childNames.has(item.name)) return null;
    const routeItem = { name: item.name };
    if (item.name === "detail" || item.name === "summary") {
      const id = Number(item.id);
      if (!Number.isSafeInteger(id) || id <= 0) return null;
      routeItem.id = id;
    }
    result.push(routeItem);
  }
  return result;
}

function push(name, params = {}) {
  if (name === "add" && !workoutDraft) {
    routeScrollPositions.delete("add:root");
    workoutDraft = createDraft();
  }
  nav.push({ name, ...params });
  pushNavigationHistory();
  modal = null;
  languageMenuOpen = false;
  render();
}

function goRoot(name) {
  const leavingAdd = route().name === "add";
  if (leavingAdd) workoutDraft = null;
  nav = [{ name }];
  replaceNavigationHistory();
  modal = null;
  languageMenuOpen = false;
  render();
  if (leavingAdd) routeScrollPositions.delete("add:root");
}

function back() {
  if (modal) {
    if (isDestructiveConfirmationModal()) return closeModal();
    modal = null;
    languageMenuOpen = false;
    return render();
  }
  if (nav.length <= 1) return;
  if (Array.isArray(history.state?.gymAppNav)) return history.back();
  const leavingAdd = route().name === "add";
  if (leavingAdd) workoutDraft = null;
  nav.pop();
  replaceNavigationHistory();
  languageMenuOpen = false;
  render();
  if (leavingAdd) routeScrollPositions.delete("add:root");
}

function svg(name, cls = "") {
  const iconClass = [cls, filledIcons.has(name) ? "filled-icon" : ""].filter(Boolean).join(" ");
  return `<svg class="${iconClass}" viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[name] || ""}"></path></svg>`;
}

function displayLocale() {
  return state.language === "uk" ? "uk-UA" : state.language === "ru" ? "ru-RU" : "en-US";
}

function fmtDate(value, options = { month: "short", day: "numeric", year: "numeric" }) {
  return new Intl.DateTimeFormat(displayLocale(), options).format(new Date(value));
}

function activeMonthScope() {
  return route().name === "progress" ? "progress" : "workouts";
}

function monthDate(scope = activeMonthScope()) {
  const d = new Date();
  d.setDate(1);
  d.setMonth(d.getMonth() + (monthOffsets[scope] || 0));
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
  return allSetsFromSessions(sessions);
}

function allSetsFromSessions(sessions = []) {
  return sessions.flatMap(session => (session.sets || []).map(set => ({ ...set, session })));
}

function totalVolume(sessions = state.sessions) {
  return allSets(sessions).reduce((sum, set) => sum + Number(set.weight || 0) * Number(set.reps || 0), 0);
}

function trainingLoad(sessions = state.sessions) {
  return allSets(sessions).reduce((sum, set) => {
    const weighted = Number(set.weight || 0) * Number(set.reps || 0);
    return sum + (weighted > 0 ? weighted : Number(set.reps || 0) * 72 + 35);
  }, 0);
}

function groupedExercises(sets = allSets()) {
  const map = new Map();
  sets.forEach(set => {
    const identity = exerciseMatchKey(set);
    const catalogKey = persistedExerciseCatalogKey(set);
    const item = map.get(identity) || { name: set.exerciseName, ...(catalogKey ? { catalogKey } : {}), sets: 0, reps: 0, volume: 0, best: 0, sessions: new Set() };
    item.sets += 1;
    item.reps += Number(set.reps || 0);
    item.volume += Number(set.weight || 0) * Number(set.reps || 0);
    item.best = Math.max(item.best, Number(set.weight || 0));
    item.sessions.add(set.session.id);
    map.set(identity, item);
  });
  return [...map.values()].sort((a, b) => b.volume - a.volume);
}

function sessionSummary(session) {
  const exerciseIdentities = new Set(
    (session.sets || [])
      .filter(set => exerciseRawName(set))
      .map(set => exerciseMatchKey(set))
  );
  return {
    exercises: exerciseIdentities.size,
    sets: session.sets.length,
    volume: totalVolume([session])
  };
}

function exerciseReferencesForSession(session) {
  const references = [];
  const identities = new Set();
  const rawNamesWithSets = new Set();
  (session.sets || []).forEach(set => {
    const name = exerciseRawName(set);
    if (!name) return;
    const identity = exerciseMatchKey(set);
    rawNamesWithSets.add(normalizeExerciseKey(name));
    if (identities.has(identity)) return;
    const catalogKey = persistedExerciseCatalogKey(set);
    references.push({ name, ...(catalogKey ? { catalogKey } : {}) });
    identities.add(identity);
  });
  (session.exerciseNames || []).forEach(rawName => {
    const name = exerciseRawName(rawName);
    const identity = exerciseMatchKey(name);
    if (!name || rawNamesWithSets.has(normalizeExerciseKey(name)) || identities.has(identity)) return;
    references.push({ name });
    identities.add(identity);
  });
  return references;
}

function exerciseNamesForSession(session) {
  return exerciseReferencesForSession(session).map(exercise => exercise.name);
}

function xpForSessions(sessions) {
  return Math.min(
    window.GymProgressionRules.MAX_SUPPORTED_XP,
    sessions.reduce((sum, session) => sum + sessionXp(session), 0)
  );
}

function totalXp() {
  return xpForSessions(state.sessions);
}

function levelFromXp(value = totalXp()) {
  return levelProgress(value).level;
}

function rankTitle(value = totalXp()) {
  const level = levelFromXp(value);
  const rank = rankDefinitions.filter(item => level >= item.level).at(-1) || rankDefinitions[0];
  return tx(rank.titleEn, rank.titleUk);
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
      title: tx(rank.titleEn, rank.titleUk),
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
  return window.GymProgressionRules.sessionXP(summary);
}

function xpRequirementForLevel(level) {
  return window.GymProgressionRules.requirementForLevel(level);
}

function cumulativeXpForLevel(level) {
  return window.GymProgressionRules.cumulativeXPForLevel(level);
}

function levelProgress(value = totalXp()) {
  return window.GymProgressionRules.levelProgress(value);
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
  return window.GymProgressionRules.currentWeeklyStreak(state.sessions);
}

function selectedMonthWeeklyStreak() {
  if ((monthOffsets[activeMonthScope()] || 0) === 0) return weeklyStreak();
  const selected = monthDate();
  const start = new Date(selected.getFullYear(), selected.getMonth(), 1).getTime();
  const end = new Date(selected.getFullYear(), selected.getMonth() + 1, 1).getTime() - 1;
  return window.GymProgressionRules.bestWeeklyStreakDuring(state.sessions, start, end);
}

function loginScreen() {
  const accounts = accountList().filter(account => !account.remote);
  const remoteEnabled = remoteAuthEnabled();
  const isSignUp = authMode === "signup";
  const isForgot = authMode === "forgot";
  const authNoticeMarkup = authNotice?.text
    ? `<div class="email-confirmation-status ${authNotice.isError ? "error" : ""}" role="status">${escapeHtml(authNotice.text)}</div>`
    : "";
  let remotePanel = "";
  if (remoteEnabled && pendingEmailConfirmation) {
    remotePanel = emailConfirmationPanel();
  } else if (remoteEnabled && isForgot) {
    remotePanel = `<section class="panel highlighted auth-panel"><h2>${tx("Reset password", "Скинути пароль")}</h2><p class="muted">${tx("Enter the email for your cloud account. The reset link must be opened in this browser.", "Введи адресу хмарного акаунта. Посилання для скидання потрібно відкрити в цьому браузері.")}</p>${authNoticeMarkup}<div class="field-stack"><label>${tx("Email", "Email")}<input id="forgot-email" data-auth-mode="forgot" data-auth-field="email" autocomplete="email" inputmode="email" placeholder="email@example.com" value="${escapeAttr(authDrafts.forgot.email)}"></label></div><div class="auth-actions"><button class="button" data-action="request-password-reset" ${authRequestInProgress ? "disabled" : ""}>${tx("Send reset link", "Надіслати посилання")}</button><button class="button ghost" data-action="auth-mode" data-mode="login" ${authRequestInProgress ? "disabled" : ""}>${tx("Back to sign in", "Повернутися до входу")}</button></div></section>`;
  } else if (remoteEnabled) {
    remotePanel = `<section class="panel highlighted auth-panel"><h2>${isSignUp ? tx("Create account", "Створити акаунт") : tx("Cloud account", "Хмарний акаунт")}</h2>${authNoticeMarkup}<div class="field-stack">
      ${isSignUp ? `<label>${tx("Email", "Email")}<input id="signup-email" data-auth-mode="signup" data-auth-field="email" autocomplete="email" inputmode="email" placeholder="email@example.com" value="${escapeAttr(authDrafts.signup.email)}"></label><label>${tx("Repeat email", "Повтори адресу електронної пошти")}<input id="signup-email-confirm" data-auth-mode="signup" data-auth-field="emailConfirm" autocomplete="email" inputmode="email" value="${escapeAttr(authDrafts.signup.emailConfirm)}"></label><label>${tx("Password", "Пароль")}<input id="signup-password" data-auth-mode="signup" data-auth-field="password" autocomplete="new-password" type="password" minlength="12" maxlength="72" value="${escapeAttr(authDrafts.signup.password)}"></label><label>${tx("Repeat password", "Повтори пароль")}<input id="signup-password-confirm" data-auth-mode="signup" data-auth-field="passwordConfirm" autocomplete="new-password" type="password" minlength="12" maxlength="72" value="${escapeAttr(authDrafts.signup.passwordConfirm)}"></label><label>${tx("Display name", "Ім’я профілю")}<input id="signup-name" data-auth-mode="signup" data-auth-field="name" autocomplete="name" maxlength="32" value="${escapeAttr(authDrafts.signup.name)}"></label>` : `<label>${tx("Email", "Email")}<input id="login-email" data-auth-mode="login" data-auth-field="email" autocomplete="email" inputmode="email" placeholder="email@example.com" value="${escapeAttr(authDrafts.login.email)}"></label><label>${tx("Password", "Пароль")}<input id="login-password" data-auth-mode="login" data-auth-field="password" autocomplete="current-password" type="password" value="${escapeAttr(authDrafts.login.password)}"></label>`}
      </div>${isSignUp ? `<p class="muted">${tx("Use at least 12 characters (up to 72 UTF-8 bytes) with lowercase and uppercase Latin letters, a number, and a supported symbol such as !, @, #, or $.", "Використай щонайменше 12 символів (до 72 байтів UTF-8): малу й велику латинські літери, цифру та підтримуваний спецсимвол, наприклад !, @, # або $.")}</p>` : ""}<div class="auth-actions"><button class="button" data-action="${isSignUp ? "remote-signup" : "remote-login"}" ${authRequestInProgress ? "disabled" : ""}>${isSignUp ? tx("Create account", "Створити акаунт") : tx("Log in", "Увійти")}</button><button class="button ghost" data-action="auth-mode" data-mode="${isSignUp ? "login" : "signup"}" ${authRequestInProgress ? "disabled" : ""}>${isSignUp ? tx("Log in instead", "Увійти натомість") : tx("Create account", "Створити акаунт")}</button>${isSignUp ? "" : `<button class="button ghost" data-action="auth-mode" data-mode="forgot" ${authRequestInProgress ? "disabled" : ""}>${tx("Forgot password?", "Забули пароль?")}</button>`}</div>${isSignUp ? `<p class="muted auth-confirmation-preview">${tx("After creating the account, we will show where the confirmation email was sent.", "Після створення акаунта ми покажемо, на яку адресу надіслано лист для підтвердження.")}</p>` : ""}</section>`;
  }
  return `<div class="app-shell auth-shell">
    <main class="screen auth-screen" data-scroll-key="auth">
      <section class="hero-panel auth-hero"><h2>GymApp</h2><p>${remoteEnabled ? tx("Sign in to sync workouts across devices.", "Увійди, щоб синхронізувати тренування між пристроями.") : tx("Cloud login is ready after Supabase keys are added.", "Хмарний вхід запрацює після додавання ключів Supabase.")}</p></section>
      ${remotePanel}
      ${themePreferencePanel("auth")}
      <details class="local-account-details" ${remoteEnabled ? "" : "open"}><summary>${tx("Offline local account", "Офлайн-акаунт")}</summary><section class="panel auth-panel"><p class="muted">${remoteEnabled ? tx("Fallback for this browser only.", "Запасний режим лише для цього браузера.") : tx("Paste Supabase keys into supabase-config.js to enable real network login.", "Встав ключі Supabase у supabase-config.js, щоб увімкнути справжній мережевий вхід.")}</p><div class="field-row login-row"><input id="local-login-name" autocomplete="username" maxlength="64" aria-label="${txAttr("Name", "Ім'я")}" placeholder="${txAttr("Name", "Ім'я")}"><button class="button" data-action="login-account">${tx("Enter", "Увійти")}</button></div>${accounts.length ? `<div class="saved-accounts"><span class="field-caption">${tx("Saved accounts", "Збережені акаунти")}</span><div class="chip-row">${accounts.map(account => `<button class="chip buttonlike" data-action="login-account" data-name="${escapeAttr(account.name)}">${escapeHtml(account.name)}</button>`).join("")}</div></div>` : ""}</section></details>
      <nav class="auth-links" aria-label="${txAttr("GymApp links", "Посилання GymApp")}"><a href="${PUBLIC_SITE_URL}" target="_blank" rel="noopener noreferrer">${tx("Website", "Сайт")}</a><a href="${SUPPORT_URL}" target="_blank" rel="noopener noreferrer">${tx("Support", "Підтримка")}</a><a href="${PRIVACY_URL}" target="_blank" rel="noopener noreferrer">${tx("Privacy", "Конфіденційність")}</a></nav>
      <div id="toast" class="toast hidden" role="status" aria-live="polite"></div>
    </main>
  </div>`;
}

function themePreferencePanel(context = "profile") {
  const preference = window.GymThemePreference?.getPreference?.();
  const current = ["system", "light", "dark"].includes(preference) ? preference : "system";
  const options = [
    ["system", tx("System", "Системна")],
    ["light", tx("Light", "Світла")],
    ["dark", tx("Dark", "Темна")]
  ];
  const titleId = `theme-preference-${context}`;
  return `<section class="panel theme-preference-card ${context === "auth" ? "auth-theme-card" : ""}" aria-labelledby="${titleId}">
    <div class="theme-preference-copy"><h2 id="${titleId}">${tx("Appearance", "Вигляд")}</h2><p class="muted">${tx("Follow this device or keep GymApp light or dark.", "Використовуй тему пристрою або зафіксуй світлий чи темний вигляд GymApp.")}</p></div>
    <div class="theme-options" role="radiogroup" aria-label="${txAttr("Color theme", "Колірна тема")}">${options.map(([value, label]) => `<button type="button" class="theme-option ${current === value ? "selected" : ""}" role="radio" aria-checked="${current === value}" data-action="set-theme" data-theme="${value}">${label}</button>`).join("")}</div>
  </section>`;
}

function emailConfirmationPanel() {
  const notice = pendingEmailConfirmation;
  if (!notice) return "";
  return `<section class="panel highlighted auth-panel email-confirmation-panel" aria-labelledby="email-confirmation-title">
    <div class="email-confirmation-heading"><span class="email-confirmation-icon" aria-hidden="true">✉</span><div><span>${tx("Confirmation link sent to", "Посилання надіслано на адресу")}</span><strong id="pending-confirmation-email"></strong></div></div>
    <div class="email-confirmation-copy"><h2 id="email-confirmation-title">${tx("Check your email", "Перевірте електронну пошту")}</h2><p>${tx("We sent a confirmation link to the address below. Open the newest email from GymApp and tap “Confirm email”. Then return to GymApp and sign in.", "Ми надіслали посилання для підтвердження на адресу нижче. Відкрийте найновіший лист від GymApp і натисніть «Підтвердити email». Потім поверніться до GymApp та увійдіть.")}</p><p class="muted">${tx("If you cannot find it, check your Spam folder.", "Якщо листа немає, перевірте папку «Спам».")}</p></div>
    ${notice.status ? `<div class="email-confirmation-status ${notice.statusIsError ? "error" : ""}" role="status">${escapeHtml(notice.status)}</div>` : ""}
    <div class="email-confirmation-actions"><button class="button full" data-action="remote-resend-confirmation" ${authRequestInProgress ? "disabled" : ""}>${tx("Send email again", "Надіслати лист ще раз")}</button><button class="button ghost full" data-action="confirmation-change-address" ${authRequestInProgress ? "disabled" : ""}>${tx("Use a different address", "Використати іншу адресу")}</button><button class="button ghost full" data-action="confirmation-back-to-login" ${authRequestInProgress ? "disabled" : ""}>${tx("Back to sign in", "Повернутися до входу")}</button></div>
  </section>`;
}

function languageSelectorMarkup() {
  const currentLanguage = state.language === "uk" ? "Українська" : state.language === "ru" ? "Русский" : "English";
  return `<div class="language-selector">
    <button class="icon-button topbar-action" data-action="language-menu" aria-label="${txAttr("Language", "Мова")}" aria-expanded="${languageMenuOpen}">${svg("lang")}</button>
    ${languageMenuOpen ? `<div class="language-menu" role="menu" aria-label="${txAttr("Language", "Мова")}">
      <button class="language-option ${state.language === "en" ? "selected" : ""}" role="menuitem" data-action="set-language" data-language="en">English</button>
      <button class="language-option ${state.language === "uk" ? "selected" : ""}" role="menuitem" data-action="set-language" data-language="uk">Українська</button>
      <button class="language-option ${state.language === "ru" ? "selected" : ""}" role="menuitem" data-action="set-language" data-language="ru">Русский</button>
      <span class="sr-only">${currentLanguage}</span>
    </div>` : ""}
  </div>`;
}

function render() {
  rememberVisibleScroll();
  pendingRecommendations = [];
  document.documentElement.lang = ["en", "uk", "ru"].includes(state.language) ? state.language : "en";
  if (!activeAccount) {
    app.innerHTML = loginScreen();
    bindEvents();
    requestAnimationFrame(restoreVisibleScroll);
    return;
  }
  if (activeAccount.remote === "supabase" && loadRemoteSession()?.activation_pending) {
    app.innerHTML = pendingActivationScreen();
    bindEvents();
    requestAnimationFrame(restoreVisibleScroll);
    return;
  }
  if (activeAccount.remote === "supabase" && loadRemoteSession()?.password_update_required === true) {
    app.innerHTML = passwordUpdateScreen();
    bindEvents();
    requestAnimationFrame(restoreVisibleScroll);
    return;
  }
  if (activeAccount.remote === "supabase" && cloudSyncConflict?.userId === activeAccount.userId) {
    app.innerHTML = cloudSyncConflictScreen();
    bindEvents();
    requestAnimationFrame(restoreVisibleScroll);
    return;
  }
  if (activeAccount.remote === "supabase" &&
      cloudStateRecovery?.userId === activeAccount.userId) {
    app.innerHTML = cloudRecoveryScreen();
    bindEvents();
    requestAnimationFrame(restoreVisibleScroll);
    return;
  }
  const current = route();
  app.innerHTML = `
    <header class="topbar">
      ${nav.length > 1 ? `<button class="icon-button topbar-action" data-action="back" aria-label="${txAttr("Go back", "Назад")}">${svg("back")}</button>` : `<span class="topbar-slot" aria-hidden="true"></span>`}
      <h1>${titleForRoute(current)}</h1>
      ${languageSelectorMarkup()}
    </header>
    <main class="screen screen-${escapeAttr(current.name)}" data-scroll-key="${escapeAttr(routeScrollKey(current))}">${screenMarkup(current)}</main>
    ${isRootRoute(current.name) ? bottomNav() : ""}
    ${modal ? modalMarkup() : ""}
    <div id="toast" class="toast hidden" role="status" aria-live="polite"></div>
  `;
  hydrateRecommendationText();
  bindEvents();
  requestAnimationFrame(restoreVisibleScroll);
  startTimerTicker();
  if (current.name === "leaderboard") refreshLeaderboard();
}

function pendingActivationScreen() {
  return `<div class="app-shell auth-shell">
    <main class="screen auth-screen" data-scroll-key="cloud-activation">
      <section class="hero-panel auth-hero"><h2>${tx("Finishing cloud sign-in", "Завершуємо хмарний вхід")}</h2><p>${tx("Your email is already verified. GymApp is loading cloud data with the saved session; no new email is needed.", "Електронну пошту вже підтверджено. GymApp завантажує хмарні дані зі збереженою сесією; новий лист не потрібен.")}</p></section>
      <section class="panel highlighted auth-panel"><div class="actions vertical"><button class="button full" data-action="retry-cloud-activation" ${authRequestInProgress ? "disabled" : ""}>${tx("Retry cloud loading", "Повторити завантаження з хмари")}</button><button class="button ghost full" data-action="logout-account" ${authRequestInProgress ? "disabled" : ""}>${tx("Sign out", "Вийти")}</button></div></section>
      <div id="toast" class="toast hidden" role="status" aria-live="polite"></div>
    </main>
  </div>`;
}

function cloudSyncConflictScreen() {
  return `<div class="app-shell auth-shell">
    <main class="screen auth-screen" data-scroll-key="cloud-conflict">
      <section class="hero-panel auth-hero"><h2>${tx("Cloud sync needs your choice", "Хмарна синхронізація потребує твого вибору")}</h2><p>${tx("This browser and the cloud both changed since their last confirmed sync. GymApp kept the browser copy and did not overwrite either version.", "Цей браузер і хмара змінилися після останньої підтвердженої синхронізації. GymApp зберіг копію браузера й не перезаписав жодну версію.")}</p></section>
      <section class="panel highlighted auth-panel"><p>${tx("Download a backup first, then explicitly choose which version should continue.", "Спочатку завантаж резервну копію, а потім явно вибери версію для продовження.")}</p><div class="actions vertical"><button class="button secondary full" data-action="export-sync-conflict-local">${tx("Download browser backup", "Завантажити резервну копію браузера")}</button><button class="button full" data-action="resolve-sync-conflict-local">${tx("Keep browser version", "Зберегти версію браузера")}</button><button class="button danger full" data-action="resolve-sync-conflict-cloud">${tx("Use cloud version", "Використати хмарну версію")}</button><button class="button ghost full" data-action="logout-account">${tx("Sign out without changes", "Вийти без змін")}</button></div></section>
      <div id="toast" class="toast hidden" role="status" aria-live="polite"></div>
    </main>
  </div>`;
}

function passwordUpdateScreen() {
  return `<div class="app-shell auth-shell">
    <main class="screen auth-screen" data-scroll-key="password-update">
      <section class="hero-panel auth-hero"><h2>${tx("Choose a new password", "Вибери новий пароль")}</h2><p>${tx("Your reset link was verified. Set a new password before continuing to your cloud account.", "Посилання для скидання перевірено. Встанови новий пароль, перш ніж продовжити роботу з хмарним акаунтом.")}</p></section>
      <section class="panel highlighted auth-panel"><div class="field-stack"><label>${tx("New password", "Новий пароль")}<input id="recovery-new-password" type="password" autocomplete="new-password" minlength="12" maxlength="72"></label><label>${tx("Repeat new password", "Повтори новий пароль")}<input id="recovery-repeat-password" type="password" autocomplete="new-password" minlength="12" maxlength="72"></label></div><p class="muted">${tx("Use at least 12 characters (up to 72 UTF-8 bytes) with lowercase and uppercase Latin letters, a number, and a supported symbol such as !, @, #, or $.", "Використай щонайменше 12 символів (до 72 байтів UTF-8): малу й велику латинські літери, цифру та підтримуваний спецсимвол, наприклад !, @, # або $.")}</p><div class="actions vertical"><button class="button full" data-action="complete-password-recovery" ${authRequestInProgress ? "disabled" : ""}>${tx("Save new password", "Зберегти новий пароль")}</button><button class="button ghost full" data-action="logout-account" ${authRequestInProgress ? "disabled" : ""}>${tx("Cancel and sign out", "Скасувати й вийти")}</button></div></section>
      <div id="toast" class="toast hidden" role="status" aria-live="polite"></div>
    </main>
  </div>`;
}

function cloudRecoveryScreen() {
  return `<div class="app-shell auth-shell">
    <main class="screen auth-screen" data-scroll-key="cloud-recovery">
      <section class="hero-panel auth-hero"><h2>${tx("Cloud data recovery", "Відновлення хмарних даних")}</h2><p>${tx("Your authenticated cloud row uses a legacy or invalid format. It was not loaded into the app and cannot sync until you choose a recovery action.", "Твій автентифікований хмарний запис має застарілий або некоректний формат. Його не завантажено в застосунок, і синхронізація заблокована, доки не вибереш спосіб відновлення.")}</p></section>
      <section class="panel highlighted auth-panel"><h2>${escapeHtml(activeAccount?.name || tx("Cloud account", "Хмарний акаунт"))}</h2><p>${tx("First download the untouched private JSON for offline recovery. Replacing it with an empty valid state is permanent and uses the exact server revision so another device's newer update cannot be overwritten.", "Спочатку завантаж незмінений приватний JSON для офлайн-відновлення. Заміна на порожній коректний стан незворотна й використовує точну ревізію сервера, тому новіші зміни з іншого пристрою не будуть перезаписані.")}</p><div class="actions vertical"><button class="button secondary full" data-action="export-cloud-recovery">${tx("Download original private JSON", "Завантажити оригінальний приватний JSON")}</button><button class="button full" data-action="reset-cloud-recovery">${tx("Replace cloud data with empty state", "Замінити хмарні дані порожнім станом")}</button><button class="button ghost full" data-action="logout-account">${tx("Sign out without changes", "Вийти без змін")}</button></div></section>
      <div id="toast" class="toast hidden" role="status" aria-live="polite"></div>
    </main>
  </div>`;
}

function isRootRoute(name) {
  return ["workouts", "missions", "exercises", "progress", "leaderboard"].includes(name);
}

function titleForRoute(current) {
  const title = {
    workouts: "", missions: t("missions"), exercises: "", progress: t("progress"), leaderboard: tx("Profile", "Профіль"),
    add: t("addWorkout"), detail: tx("Workout Details", "Деталі тренування"), summary: tx("Workout Summary", "Підсумок тренування"), ranks: t("ranks")
  }[current.name];
  return title ?? "Gym Workout Tracker";
}

function bottomNav() {
  const tabs = [["workouts", "fitness", t("workouts")], ["missions", "checkCircle", t("missions")], ["exercises", "listFilled", t("exercises")], ["progress", "showChart", t("progress")], ["leaderboard", "person", tx("Profile", "Профіль")]];
  return `<nav class="bottom-nav">${tabs.map(([id, icon, label]) => `
    <button class="tab-button ${route().name === id ? "active" : ""}" data-route="${id}" ${route().name === id ? `aria-current="page"` : ""}><span class="tab-icon">${svg(icon)}</span><span>${label}</span></button>`).join("")}</nav>`;
}

function screenMarkup(current) {
  if (current.name === "missions") return missionsScreen();
  if (current.name === "exercises") return exercisesScreen();
  if (current.name === "progress") return progressScreen();
  if (current.name === "leaderboard") return leaderboardScreen();
  if (current.name === "add") return addWorkoutScreen();
  if (current.name === "detail") return detailScreen(current.id);
  if (current.name === "summary") return summaryScreen(current.id);
  if (current.name === "ranks") return ranksScreen();
  return workoutsScreen();
}

function monthSwitcher() {
  return `<section class="month-switcher panel compact">
    <button class="icon-button" data-action="month-prev" aria-label="${txAttr("Previous month", "Попередній місяць")}">${svg("back")}</button>
    <strong>${fmtDate(monthDate().getTime(), { month: "long", year: "numeric" })}</strong>
    <button class="button ghost" data-action="month-current">${t("current")}</button>
    <button class="icon-button rotate-180" data-action="month-next" aria-label="${txAttr("Next month", "Наступний місяць")}">${svg("back")}</button>
  </section>`;
}

function workoutsScreen() {
  const sessions = [...selectedMonthSessions()].sort((a, b) => b.startedAt - a.startedAt);
  const savedSessions = n(sessions.length, "saved session", "saved sessions", "збережене тренування", "збережені тренування", "збережених тренувань");
  return `
    <section class="screen-copy workouts-screen-copy"><div><span class="eyebrow">${tx("TRAINING", "ТРЕНУВАННЯ")}</span><h2>${t("workouts")}</h2></div><p>${tx("Your training history and next best move.", "Твоя історія тренувань і рекомендація, що робити далі.")}</p></section>
    <div class="workouts-scroll">
      ${focusOverview(sessions)}
      <div class="workouts-controls">
        ${monthSwitcher()}
        <section class="segmented panel compact" aria-label="${txAttr("Workout sections", "Розділи тренувань")}">
          <button class="${overviewMode === "overview" ? "selected" : ""}" data-action="overview-mode" data-mode="overview" aria-pressed="${overviewMode === "overview"}"><strong>${t("overview")}</strong><span>${tx("Progress, goals, achievements", "Прогрес, цілі, досягнення")}</span></button>
          <button class="${overviewMode === "list" ? "selected" : ""}" data-action="overview-mode" data-mode="list" aria-pressed="${overviewMode === "list"}"><strong>${t("workoutList")}</strong><span>${savedSessions}</span></button>
        </section>
      </div>
      ${overviewCards(sessions)}
      <section id="workout-list-section" class="panel highlighted workout-section-header">
        <div><h2>${t("workoutList")}</h2><p>${sessions.length ? tx("Tap a workout to open its details.", "Натисни тренування, щоб відкрити деталі.") : tx("New sessions will appear here as soon as you log them.", "Нові тренування з'являться тут одразу після збереження.")}</p></div>
        <span class="pill">${savedSessions}</span>
      </section>
      <section class="workout-list">${sessions.length ? sessions.map(workoutItem).join("") : `<section class="panel highlighted empty-state-panel"><h3>${t("noWorkouts")}</h3><p>${tx("Track consistency, output and intensity at a glance.", "Відстежуй стабільність, обсяг і інтенсивність одним поглядом.")}</p></section>`}</section>
    </div>
  `;
}

function overviewCards(sessions) {
  return `
    ${soloProgressHero()}
    ${activityHeatmapCard()}
    ${muscleMapCard()}
    ${recommendationsCard()}
  `;
}

function focusOverview(sessions) {
  const recent = sessions.slice(0, 4);
  return `<div class="focus-overview">
    ${focusLensCard(sessions)}
    <section class="focus-recent" aria-labelledby="focus-recent-title">
      <div class="focus-recent-head"><div><span class="eyebrow">${tx("HISTORY", "ІСТОРІЯ")}</span><h2 id="focus-recent-title">${tx("Recent sessions", "Останні тренування")}</h2></div><button class="button ghost mini" data-action="overview-mode" data-mode="list">${tx("View all", "Переглянути всі")}</button></div>
      <div class="focus-recent-list">${recent.length ? recent.map(session => {
        const summary = sessionSummary(session);
        const title = session.note?.trim() || tx("Workout", "Тренування");
        return `<article class="focus-recent-row clickable" data-action="open-detail" data-id="${escapeAttr(session.id)}"><div class="focus-recent-icon">${svg("workouts")}</div><div><strong>${escapeHtml(title)}</strong><span>${escapeHtml(fmtDate(session.startedAt))}</span><small>${summary.exercises} ${tx("exercises", "вправ")} · ${summary.sets} ${tx("sets", "підходів")}</small></div><span>${Math.round(summary.volume)}</span></article>`;
      }).join("") : `<div class="focus-recent-empty"><strong>${tx("Your first session will appear here", "Твоє перше тренування з’явиться тут")}</strong><span>${tx("Start when you are ready — there is no schedule to catch up with.", "Починай, коли готовий — тут немає графіка, який треба наздоганяти.")}</span></div>`}</div>
    </section>
  </div>`;
}

function focusLensCard(sessions) {
  const monthLabel = fmtDate(monthDate().getTime(), { month: "long", year: "numeric" });
  const weekStart = new Date();
  weekStart.setHours(0, 0, 0, 0);
  weekStart.setDate(weekStart.getDate() - 6);
  const activeDays = new Set(
    state.sessions
      .filter(session => Number.isFinite(Number(session.startedAt)) && session.startedAt >= weekStart.getTime())
      .map(session => new Date(session.startedAt).toDateString())
  );
  const dayMarkers = Array.from({ length: 7 }, (_, index) => {
    const day = new Date(weekStart);
    day.setDate(weekStart.getDate() + index);
    const isActive = activeDays.has(day.toDateString());
    const isToday = day.toDateString() === new Date().toDateString();
    return `<span class="focus-day ${isActive ? "active" : ""} ${isToday ? "today" : ""}" aria-label="${escapeAttr(fmtDate(day.getTime(), { weekday: "long" }))}"></span>`;
  }).join("");
  return `<section class="focus-lens" aria-labelledby="focus-lens-title">
    <div class="focus-lens-copy">
      <span class="focus-lens-eyebrow">${tx("YOUR NEXT MOVE", "ТВІЙ НАСТУПНИЙ КРОК")}</span>
      <h2 id="focus-lens-title">${tx("Build today’s session", "Склади тренування на сьогодні")}</h2>
      <p>${tx("Ready when you are. Start simple and shape the workout as you go.", "Починай, коли готовий. Складай тренування поступово, у своєму темпі.")}</p>
    </div>
    <div class="focus-lens-metrics" aria-label="${txAttr("Current training facts", "Поточні показники тренувань")}">
      <div><strong>${sessions.length}</strong><span>${tx("workouts", "тренувань")}</span></div>
      <div><strong>${selectedMonthWeeklyStreak()}</strong><span>${tx("week streak", "тижні серії")}</span></div>
      <div><strong>${Math.round(totalVolume(sessions))}</strong><span>${tx("volume", "обсяг")}</span></div>
    </div>
    <div class="focus-lens-foot">
      <div class="focus-rhythm"><span>${escapeHtml(monthLabel)}</span><div class="focus-days">${dayMarkers}</div></div>
      <button class="focus-lens-action" data-action="open-add">${svg("add", "small-icon")}<span>${tx("Start workout", "Почати тренування")}</span></button>
    </div>
  </section>`;
}

function soloProgressHero() {
  const xp = totalXp();
  const progress = levelProgress(xp);
  const level = progress.level;
  const next = rankDefinitions.find(rank => level < rank.level);
  const nextTitle = next ? tx(next.titleEn, next.titleUk) : rankTitle(xp);
  return `<section class="hero-panel solo-progress-hero">
    <div class="eyebrow">${t("soloProgress")}</div>
    <div class="hero-split"><div><span class="pill hero-pill">${tx("LEVEL", "РІВЕНЬ")} ${level}</span><h2>${rankTitle(xp)}</h2><p>${progress.currentLevelXp} / ${progress.xpForNextLevel} XP ${tx("to next level", "до наступного рівня")}</p></div><div class="hero-stat"><span>${tx("TOTAL XP", "УСЬОГО XP")}</span><strong>${xp}</strong><small>${tx("earned", "зароблено")}</small></div></div>
    <div class="progress"><span class="${percentageClass(progress.progressFraction * 100)}"></span></div>
    <div class="metric-grid three"><div><span>${tx("Month XP", "XP за місяць")}</span><strong>${xpForSessions(selectedMonthSessions())} XP</strong></div><div><span>${tx("Next title", "Наступний ранг")}</span><strong>${nextTitle}</strong></div><div><span>${tx("Week streak", "Серія тижнів")}</span><strong>${selectedMonthWeeklyStreak()} ${tx("wk", "тж")}</strong></div></div>
  </section>`;
}

function dashboardCard(sessions) {
  const sets = allSets(sessions);
  const avg = sets.length ? totalVolume(sessions) / sets.length : 0;
  return `<section class="hero-panel">
    <h2>${t("monthlySnapshot")}</h2><p>${tx("Track consistency, output and intensity at a glance.", "Відстежуй стабільність, обсяг і інтенсивність одним поглядом.")}</p>
    <div class="metric-grid"><div><span>${tx("Workouts", "Тренування")}</span><strong>${sessions.length}</strong></div><div><span>${tx("Streak", "Серія")}</span><strong>${selectedMonthWeeklyStreak()} ${tx("wk", "тж")}</strong></div><div><span>${tx("Total Volume", "Загальний обсяг")}</span><strong>${Math.round(totalVolume(sessions))}</strong></div><div><span>${tx("Avg / Set", "Сер. / підхід")}</span><strong>${avg.toFixed(1)}</strong></div></div>
  </section>`;
}

function workoutItem(session) {
  const summary = sessionSummary(session);
  return `<article class="workout-item clickable" data-action="open-detail" data-id="${session.id}">
    <div class="workout-head"><div><h3 class="workout-title">${tx("Workout", "Тренування")} ${fmtDate(session.startedAt)}</h3><span class="muted">${session.note ? `${t("note")}: ${escapeHtml(session.note)}` : tx("No note", "Без нотатки")}</span></div><div class="actions"><span class="chip">${tx("Sets", "Підходи")}: ${summary.sets}</span><button class="icon-button" data-action="delete-session" data-id="${session.id}" aria-label="${txAttr("Delete workout", "Видалити тренування")}">${svg("delete")}</button></div></div>
    <div class="workout-stats"><span>${tx("Exercises", "Вправи")}: ${summary.exercises}</span><span>${tx("Sets", "Підходи")}: ${summary.sets}</span><span>${tx("Volume", "Обсяг")}: ${Math.round(summary.volume)}</span></div>
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
    byDay.set(day, (byDay.get(day) || 0) + trainingLoad([session]));
  });
  const max = Math.max(1, ...byDay.values());
  return `<section class="panel"><div class="section-title"><div><h2>${t("heatmap")}</h2><p>${fmtDate(d.getTime(), { month: "long", year: "numeric" })}</p></div><span class="pill">${n(byDay.size, "active day", "active days", "активний день", "активні дні", "активних днів")}</span></div>
    <div class="metric-grid"><div><span>${tx("Sessions", "Сесії")}</span><strong>${monthSessions.length}</strong></div><div><span>${tx("Load", "Навантаження")}</span><strong>${Math.round(trainingLoad(monthSessions))}</strong></div></div>
    <div class="heatmap-grid">${cells.map(day => `<button class="heat-cell ${day ? heatLevelClass((byDay.get(day) || 0) / max) : "outside"}" title="${day || ""}">${day || ""}</button>`).join("")}</div>
    <div class="legend"><span>${tx("Less", "Менше")}</span><i></i><i></i><i></i><i></i><span>${tx("More", "Більше")}</span></div>
  </section>`;
}

function mappingOverviewCard() {
  const rows = groupedExercises().sort((a, b) => Number(!mappingFor(a).length) - Number(!mappingFor(b).length) || a.name.localeCompare(b.name));
  return `<div class="subpanel"><div class="row-head"><div><h3>${tx("Exercise mapping", "Зіставлення вправ")}</h3><p>${tx("Auto mapping works first, manual choices override it.", "Спочатку застосовується автоматичне зіставлення, а ручний вибір має пріоритет.")}</p></div><span class="pill">${mappedCount()}/${state.exercises.length}</span></div>${rows.length ? rows.map(ex => {
    const ids = mappingFor(ex);
    const labels = ids.length ? ids.map(muscleLabel).join(", ") : tx("Not mapped", "Не зіставлено");
    return `<div class="row-line mapping-row"><span>${escapeHtml(exerciseDisplayName(ex))}<small>${escapeHtml(labels)}</small></span><button class="button secondary mini" data-action="map-exercise" data-name="${escapeAttr(ex.name)}">${tx("Map", "Мапити")}</button></div>`;
  }).join("") : `<div class="empty">${tx("No exercises yet.", "Вправ ще немає.")}</div>`}</div>`;
}

function muscleMapCard() {
  const data = muscleStats();
  const max = Math.max(1, ...data.map(item => item.load));
  const top = data.filter(item => item.load > 0).sort((a, b) => b.load - a.load);
  const selected = selectedMuscle ? data.find(item => item.id === selectedMuscle) : null;
  const selectedExercises = selected ? selected.exercises.slice().sort((a, b) => b.load - a.load) : [];
  return `<section class="panel">
    <div class="section-title"><div><h2>${t("muscleMap")}</h2><p>${tx("Colors show which muscle groups carried the most load.", "Кольори показують, які групи м'язів отримали найбільше навантаження.")}</p></div><span class="pill">${musclePeriodLabel(musclePeriod)}</span></div>
    <div class="period-tabs">${["all", "month", "week"].map(period => `<button class="${musclePeriod === period ? "selected" : ""}" data-action="muscle-period" data-period="${period}">${musclePeriodLabel(period)}</button>`).join("")}</div>
    <div class="metric-grid three"><div><span>${tx("Sets", "Підходи")}</span><strong>${allSets(periodSessions()).length}</strong></div><div><span>${tx("Load", "Навантаження")}</span><strong>${Math.round(trainingLoad(periodSessions()))}</strong></div><div><span>${tx("Mapped", "Зіставлено")}</span><strong>${mappedCount()}/${state.exercises.length}</strong></div></div>
    ${sourceBodyMapSvg(data, max)}
    ${selected ? `<div class="subpanel"><h3>${tx("Exercises for", "Вправи для")}: ${escapeHtml(selected.label)}</h3>${selectedExercises.length ? selectedExercises.map(ex => `<div class="row-line"><span>${escapeHtml(exerciseDisplayName(ex))}</span><span class="muted">${n(ex.sets, "set", "sets", "підхід", "підходи", "підходів")} - ${n(ex.sessions.size, "session", "sessions", "сесія", "сесії", "сесій")} - ${Math.round(ex.load)} ${tx("load", "навантаження")}</span><button class="button ghost mini" data-action="map-exercise" data-name="${escapeAttr(ex.name)}">${tx("Map", "Мапити")}</button></div>`).join("") : `<div class="empty">${tx("No logged exercises for this muscle in the selected period.", "Для цієї групи м'язів у вибраному періоді немає записаних вправ.")}</div>`}</div>` : ""}
    ${mappingOverviewCard()}
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
  return state.exercises.filter(ex => contributionFor(ex).length).length;
}

function mappingFor(exercise) {
  const rawName = exerciseRawName(exercise);
  const key = normalizeExerciseName(rawName);
  const manual = Object.hasOwn(state.mappings, key) ? state.mappings[key] : undefined;
  if (manual?.length) return manual;
  return contributionFor(exercise).map(item => item.muscleId);
}

function contributionFor(exercise) {
  const rawName = exerciseRawName(exercise);
  const normalized = normalizeExerciseName(rawName);
  const manual = Object.hasOwn(state.mappings, normalized) ? state.mappings[normalized] : undefined;
  if (manual?.length) return manual.map(muscleId => ({ muscleId, weight: 1 }));
  const exact = Object.hasOwn(exactMuscleMap, normalized) ? exactMuscleMap[normalized] : undefined;
  if (exact?.length) return exact;
  return inferMuscleContributions(exercise);
}

function normalizeExerciseName(name) {
  return normalizeExerciseKey(name);
}

function inferMuscleContributions(exercise) {
  const normalized = normalizeExerciseName(exerciseRawName(exercise));
  const inferred = new Map();
  const add = (muscleId, weight) => inferred.set(muscleId, Math.max(inferred.get(muscleId) || 0, clamp(weight, 0, 1)));
  const has = (...tokens) => tokens.some(token => normalized.includes(token));
  const defaults = Object.hasOwn(defaultMappings, normalized) ? defaultMappings[normalized] : [];
  (builtInExerciseFor(exercise)?.muscleIds || defaults).forEach(id => add(id, 1));
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
  if (has("розведення ніг", "разведение ног", "hip abduction", "abductor")) add("glutes", 1);
  if (has("метелик", "pec deck", "зведення рук", "сведение рук", "fly", "flies")) { add("chest", 1); add("shoulders", 0.25); }
  return [...inferred].filter(([muscleId]) => muscles.some(([id]) => id === muscleId)).map(([muscleId, weight]) => ({ muscleId, weight }));
}

function muscleStats(sessions = periodSessions()) {
  const map = new Map(muscles.map(([id]) => [id, { id, label: muscleLabel(id), load: 0, sets: 0, sessions: new Set(), exercises: [] }]));
  allSets(sessions).forEach(set => {
    const contributions = contributionFor(set);
    contributions.forEach(contribution => {
      const item = map.get(contribution.muscleId);
      if (!item) return;
      const trackedLoad = Math.max(0, Number(set.weight || 0)) * Math.max(0, Number(set.reps || 0));
      const load = (trackedLoad > 0 ? trackedLoad : 72 * Math.max(0, Number(set.reps || 0))) + 35;
      const weightedLoad = load * contribution.weight;
      item.load += weightedLoad;
      item.sets += 1;
      item.sessions.add(set.session.id);
      const identity = exerciseMatchKey(set);
      let exercise = item.exercises.find(ex => exerciseMatchKey(ex) === identity);
      if (!exercise) {
        const catalogKey = persistedExerciseCatalogKey(set);
        exercise = { name: set.exerciseName, ...(catalogKey ? { catalogKey } : {}), load: 0, sets: 0, sessions: new Set() };
        item.exercises.push(exercise);
      }
      exercise.load += weightedLoad;
      exercise.sets += 1;
      exercise.sessions.add(set.session.id);
    });
  });
  return [...map.values()];
}

function sourceBodyMapSvg(data, maxLoad, { interactive = true, showLabels = true } = {}) {
  const byId = new Map(data.map(item => [item.id, item]));
  const front = window.SOURCE_FRONT_MUSCLE_REGIONS || [];
  const back = window.SOURCE_BACK_MUSCLE_REGIONS || [];
  const regionMarkup = [...front, ...back].map(region => {
    const muscleId = muscleIdForSourceRegion(region.id);
    const item = muscleId ? byId.get(muscleId) : null;
    const intensity = item && maxLoad > 0 ? Math.min(1, item.load / maxLoad) : 0;
    const selected = interactive && muscleId && selectedMuscle === muscleId;
    const interactionAttrs = interactive && muscleId ? ` data-action="select-muscle" data-id="${muscleId}"` : "";
    return `<path class="body-region ${selected ? "selected" : ""}" d="${escapeAttr(region.pathData)}" fill="${heatColor(intensity)}"${interactionAttrs}><title>${escapeHtml(region.name)}${item ? ` - ${Math.round(item.load)} ${tx("load", "навантаження")}` : ""}</title></path>`;
  }).join("");
  return `<div class="body-map-svg-wrap">
    <svg class="body-map-svg" viewBox="0 0 72 93" role="img" aria-label="${txAttr("Muscle load map", "Карта навантаження м'язів")}">
      ${regionMarkup}
    </svg>
    ${showLabels ? `<div class="body-labels"><span>${tx("Front", "Спереду")}</span><span>${tx("Back", "Ззаду")}</span></div>` : ""}
  </div>`;
}

function exerciseMuscleMapCard(exercise, framed = false) {
  const exerciseName = exerciseRawName(exercise);
  const contributions = contributionFor(exercise).filter(item => muscles.some(([id]) => id === item.muscleId));
  const data = muscles.map(([id]) => {
    const contribution = contributions.find(item => item.muscleId === id);
    return {
      id,
      label: muscleLabel(id),
      load: contribution ? Math.max(0.08, contribution.weight) : 0,
      weight: contribution?.weight || 0
    };
  });
  const max = Math.max(1, ...data.map(item => item.load));
  const active = data.filter(item => item.weight > 0).sort((a, b) => b.weight - a.weight);
  const label = active.map(item => `${item.label} ${Math.round(item.weight * 100)}%`).join(" - ") || tx("Not mapped", "Не зіставлено");
  return `<section class="${framed ? "panel highlighted" : "subpanel"} exercise-muscle-map"><div class="row-head"><div><h3>${t("muscleMap")}</h3><p>${escapeHtml(label)}</p></div><button class="button secondary mini" data-action="map-exercise" data-name="${escapeAttr(exerciseName)}">${tx("Map", "Мапити")}</button></div>
    <div class="exercise-muscle-layout">${sourceBodyMapSvg(data, max)}<div class="bars">${active.length ? active.map(item => barRow(item.label, item.weight, 1, `${Math.round(item.weight * 100)}% ${tx("target", "ціль")}`)).join("") : `<div class="empty">${tx("Choose muscles for this exercise.", "Вибери м'язи для цієї вправи.")}</div>`}</div></div></section>`;
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
  pendingRecommendations = trainingRecommendations().map(rec => ({
    title: String(rec.title || ""),
    supporting: String(rec.supporting || ""),
    priority: String(rec.priority || "")
  }));
  return `<section class="panel highlighted"><h2>${t("recommendations")}</h2><p class="muted">${tx("Based on muscle load and recent training gaps.", "На основі навантаження м'язів і останніх пауз у тренуваннях.")}</p>
    <div class="list-gap">${pendingRecommendations.map((_, index) => `<div class="subpanel row-line" data-recommendation="${index}"><div><strong data-recommendation-field="title"></strong><p data-recommendation-field="supporting"></p></div><span class="pill" data-recommendation-field="priority"></span></div>`).join("")}</div>
  </section>`;
}

function hydrateRecommendationText() {
  app.querySelectorAll("[data-recommendation]").forEach(row => {
    const recommendation = pendingRecommendations[Number(row.dataset.recommendation)];
    if (!recommendation) return;
    row.querySelectorAll("[data-recommendation-field]").forEach(field => {
      field.textContent = recommendation[field.dataset.recommendationField] || "";
    });
  });
}

function trainingRecommendations() {
  const stats = muscleStats(state.sessions).sort((a, b) => a.load - b.load);
  const stale = stats.filter(item => item.load > 0).slice(0, 3);
  const last = [...state.sessions].sort((a, b) => b.startedAt - a.startedAt)[0];
  return [
    stale[0] ? { title: `${tx("Bring up", "Підтягни")} ${stale[0].label}`, supporting: tx("This muscle group is behind your current total load.", "Ця група м'язів відстає за поточним загальним навантаженням."), priority: tx("High", "Високий") } : { title: tx("Starter plan", "Стартовий план"), supporting: tx("Add your first workout to unlock smarter recommendations.", "Додай перше тренування, щоб відкрити розумніші рекомендації."), priority: tx("New", "Нове") },
    { title: nextWorkoutType(last), supporting: tx("Suggested from your recent exercise pattern and training profile.", "Підібрано з урахуванням недавніх вправ і профілю тренувань."), priority: tx("Next", "Далі") }
  ];
}

function nextWorkoutType(last) {
  const note = last?.note?.toLowerCase() || "";
  if (note.includes("push")) return tx("Next suggested workout: pull", "Наступне рекомендоване тренування: тяга");
  if (note.includes("pull")) return tx("Next suggested workout: legs", "Наступне рекомендоване тренування: ноги");
  if (note.includes("leg")) return tx("Next suggested workout: push", "Наступне рекомендоване тренування: жим");
  return `${tx("Next suggested workout", "Наступне рекомендоване тренування")}: ${profileValueLabel(state.profile.split)}`;
}

function achievementDefinitions() {
  const workoutCount = state.sessions.length;
  const longestStreak = longestWorkoutStreak();
  const totalLoad = Math.round(totalVolume());
  return [
    achievement("first_workout", "fitness", "common", tx("First Workout", "Перше тренування"), tx("Complete your first workout.", "Заверши своє перше тренування."), workoutCount, 1),
    achievement("workout_5", "medal", "common", tx("Starter Habit", "Початок звички"), tx("Complete five workouts.", "Заверши п'ять тренувань."), workoutCount, 5),
    achievement("workout_10", "checkCircle", "uncommon", tx("Consistency Builder", "Будівник стабільності"), tx("Complete ten workouts.", "Заверши десять тренувань."), workoutCount, 10),
    achievement("workout_25", "weight", "rare", tx("Workhorse", "Трудяга"), tx("Complete twenty-five workouts.", "Заверши двадцять п'ять тренувань."), workoutCount, 25),
    achievement("workout_50", "trophy", "epic", tx("Veteran", "Ветеран"), tx("Complete fifty workouts.", "Заверши п'ятдесят тренувань."), workoutCount, 50),
    achievement("workout_100", "emojiEvents", "legendary", tx("Centurion", "Центуріон"), tx("Complete one hundred workouts.", "Заверши сто тренувань."), workoutCount, 100),
    achievement("streak_7", "fire", "common", tx("Seven-Day Streak", "Серія сім днів"), tx("Keep a seven day streak alive.", "Підтримуй серію протягом семи днів."), longestStreak, 7),
    achievement("streak_14", "fire", "uncommon", tx("Fourteen-Day Streak", "Серія чотирнадцять днів"), tx("Keep a fourteen day streak alive.", "Підтримуй серію протягом чотирнадцяти днів."), longestStreak, 14),
    achievement("streak_30", "fire", "epic", tx("Thirty-Day Streak", "Серія тридцять днів"), tx("Keep a thirty day streak alive.", "Підтримуй серію протягом тридцяти днів."), longestStreak, 30),
    achievement("volume_10k", "weight", "uncommon", tx("Ten Thousand Volume", "Десять тисяч обсягу"), tx("Accumulate ten thousand total volume.", "Набери десять тисяч загального обсягу."), totalLoad, 10_000),
    achievement("volume_50k", "trophy", "rare", tx("Fifty Thousand Volume", "П'ятдесят тисяч обсягу"), tx("Accumulate fifty thousand total volume.", "Набери п'ятдесят тисяч загального обсягу."), totalLoad, 50_000),
    achievement("comeback", "auto", "rare", tx("Comeback", "Повернення"), tx("Return after a seven day break.", "Повернися після семиденної перерви."), maximumWorkoutGapDays(), 7)
  ];
}

function achievementWorkoutEpochDays() {
  return [...new Set(state.sessions.flatMap(session => {
    const date = new Date(Number(session.startedAt));
    if (!Number.isFinite(date.getTime())) return [];
    return [Math.floor(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000)];
  }))].sort((left, right) => left - right);
}

function longestWorkoutStreak() {
  const days = achievementWorkoutEpochDays();
  let longest = 0;
  let current = 0;
  let previous = null;
  days.forEach(day => {
    current = previous != null && day === previous + 1 ? current + 1 : 1;
    longest = Math.max(longest, current);
    previous = day;
  });
  return longest;
}

function maximumWorkoutGapDays() {
  const days = achievementWorkoutEpochDays();
  let maximum = 0;
  for (let index = 1; index < days.length; index++) {
    maximum = Math.max(maximum, days[index] - days[index - 1] - 1);
  }
  return maximum;
}

function achievementsGallery() {
  const achievements = achievementDefinitions();
  const unlocked = achievements.filter(item => item.progress >= item.target).length;
  return `<section class="achievements-section"><div class="section-title achievements-heading"><div><span class="eyebrow">${tx("Collection", "Колекція")}</span><h2>${t("achievements")}</h2><p>${tx("Every badge has a stable milestone and stays visible before and after unlock.", "Кожен значок має сталу ціль і залишається видимим до та після відкриття.")}</p></div><span class="pill">${unlocked}/${achievements.length}</span></div><div class="achievement-gallery">${achievements.map(item => {
    const percent = Math.max(0, Math.min(100, Math.round(item.progress / item.target * 100)));
    const isUnlocked = item.progress >= item.target;
    const rarity = achievementRarityLabel(item.rarity);
    return `<article class="panel achievement-card rarity-${escapeAttr(item.rarity)} ${isUnlocked ? "unlocked" : "locked"}" data-achievement-id="${escapeAttr(item.id)}"><div class="achievement-medallion">${svg(item.icon)}</div><div class="achievement-copy"><div class="row-head"><div><span class="eyebrow">${escapeHtml(rarity)}</span><h3>${escapeHtml(item.title)}</h3></div><strong>${percent}%</strong></div><p>${escapeHtml(item.description)}</p><div class="progress"><span class="${percentageClass(percent)}"></span></div><small>${Math.min(Math.round(item.progress), item.target)} / ${item.target} · ${isUnlocked ? tx("Unlocked", "Відкрито") : tx("In progress", "У процесі")}</small></div></article>`;
  }).join("")}</div></section>`;
}

function achievementRarityLabel(rarity) {
  return ({
    common: tx("Common", "Звичайний"),
    uncommon: tx("Uncommon", "Незвичайний"),
    rare: tx("Rare", "Рідкісний"),
    epic: tx("Epic", "Епічний"),
    legendary: tx("Legendary", "Легендарний")
  })[rarity] || tx("Achievement", "Досягнення");
}

function achievement(id, icon, rarity, title, description, progress, target) {
  return { id, icon, rarity, title, description, progress, target };
}

function addWorkoutScreen() {
  if (!workoutDraft) workoutDraft = createDraft();
  const draft = workoutDraft;
  const selectedCount = draft.blocks.filter(b => b.exerciseName).length;
  const setCount = draft.blocks.reduce((sum, block) => sum + block.sets.length, 0);
  return `<section class="hero-panel add-workout-hero">
      <h2>${tx("Build today's session", "Збери сьогоднішнє тренування")}</h2><p>${tx("Log your plan fast and keep momentum with smart set shortcuts.", "Швидко запиши план і зберігай темп за допомогою зручних дій для підходів.")}</p>
      <div class="hero-info-row date-row"><span class="hero-info-pill">${tx("Workout date", "Дата тренування")}</span><span class="hero-info-pill">${fmtDate(draft.startedAt)}</span></div>
      <div class="hero-info-row"><span class="hero-info-pill">${tx("Exercises", "Вправи")}: ${selectedCount}</span><span class="hero-info-pill">${tx("Sets", "Підходи")}: ${setCount}</span></div>
      <button class="button hero-outline hero-button" data-action="repeat-latest" ${state.sessions.length ? "" : "disabled"}>${svg("copy", "small-icon")}${t("repeatLast")}</button>
      <button class="button hero-outline hero-button" data-action="template-picker" ${state.sessions.length ? "" : "disabled"}>${svg("copy", "small-icon")}${t("copyWorkout")}</button>
    </section>
    <section class="panel highlighted note-panel"><h2>${t("note")}</h2><textarea data-draft="note" maxlength="2000" aria-label="${tAttr("note")}" placeholder="${txAttr("Push day, pull day, deload...", "Push день, pull день, делoad...")}">${escapeHtml(draft.note)}</textarea><span class="field-caption">${tx("Plan templates", "Шаблони плану")}</span><div class="chip-row">${noteTemplates().map(note => `<button class="chip buttonlike" data-action="note-template" data-note="${escapeAttr(note.value)}">${escapeHtml(note.label)}</button>`).join("")}</div></section>
    ${trainingProfilePanel()}
    <section class="draft-list">${draft.blocks.map((block, index) => draftBlock(block, index)).join("")}</section>
    <button class="button secondary full" data-action="add-block">${svg("add", "small-icon")}${t("addExercise")}</button>
    <section class="panel"><p class="muted">${tx("Check your sets, then save to move straight into workout details.", "Перевір підходи й збережи, щоб перейти до деталей тренування.")}</p><button class="button ghost full" data-action="sync-watch">${t("syncWatch")}</button><button class="button full" data-action="save-workout">${svg("save", "small-icon")}${t("saveWorkout")}</button></section>`;
}

function trainingProfilePanel() {
  const p = state.profile;
  return `<section class="panel highlighted"><div class="section-title"><div><h2>${t("trainingProfile")}</h2><p>${tx("Smart Coach uses this to match your plan, goal and recovery.", "Розумний тренер використовує ці дані, щоб підібрати план з урахуванням цілі та відновлення.")}</p></div>${svg("auto", "small-icon")}</div>
    <span class="field-caption">${tx("Training split", "Спліт тренувань")}</span>
    ${chipSelect("split", ["Upper / Lower", "Full Body", "Push Pull Legs", "Custom"], p.split)}
    <span class="field-caption">${tx("Workouts per week", "Тренувань на тиждень")}</span>
    ${chipSelect("days", [2, 3, 4, 5, 6].map(v => `${v} / week`), `${p.days} / week`)}
    <span class="field-caption">${tx("Training goal", "Ціль тренувань")}</span>
    ${chipSelect("goal", ["Aesthetic Cut", "Muscle Gain", "Strength", "Balanced"], p.goal)}
    <span class="field-caption">${tx("Calorie mode", "Режим калорій")}</span>
    ${chipSelect("calories", ["Deficit", "Maintenance", "Surplus"], p.calories)}
    <button class="button full" data-action="generate-smart">${svg("auto", "small-icon")}${t("generateSmart")}</button>
  </section>`;
}

function chipSelect(field, options, selected) {
  return `<div class="chip-row">${options.map(option => `<button class="chip buttonlike ${option === selected ? "selected" : ""}" data-action="profile" data-field="${field}" data-value="${option}">${profileValueLabel(option)}</button>`).join("")}</div>`;
}

function draftBlock(block, blockIndex) {
  const lastWeight = lastWeightFor(block.exerciseName);
  const rec = block.exerciseName ? smartRecommendation(block) : null;
  const title = block.exerciseName ? exerciseDisplayName(block) : `${tx("Exercise", "Вправа")} ${blockIndex + 1}`;
  return `<section class="draft-exercise panel highlighted"><details open><summary class="detail-summary"><div class="draft-exercise-title"><h2>${escapeHtml(title)}</h2><p class="muted">${escapeHtml(draftSetSummary(block))}</p></div>${block.exerciseName ? exerciseMediaThumbnail(block, blockIndex) : ""}<button class="icon-button" data-action="remove-block" data-block="${blockIndex}" aria-label="${txAttr("Remove exercise", "Прибрати вправу")}">${svg("delete")}</button></summary>
    <label>${tx("Exercise", "Вправа")}<select class="exercise-select" data-block="${blockIndex}" data-field="exerciseName"><option value="">${tx("Select exercise", "Обери вправу")}</option>${state.exercises.map(ex => `<option value="${escapeAttr(ex.name)}" ${ex.name === block.exerciseName ? "selected" : ""}>${escapeHtml(exerciseDisplayName(ex))}</option>`).join("")}</select></label>
    ${block.exerciseName ? exerciseMuscleMapCard(block) : ""}
    ${lastWeight != null ? `<div class="row-line"><strong>${tx("Last", "Остання вага")}: ${lastWeight.toFixed(1)} kg</strong><button class="button ghost mini" data-action="apply-last" data-block="${blockIndex}">${t("useLast")}</button></div>` : ""}
    ${rec ? smartPanel(rec, blockIndex) : ""}
    <div class="set-shortcuts"><button class="button ghost" data-action="add-set" data-block="${blockIndex}">${t("addSet")}</button><button class="button ghost" data-action="copy-set" data-block="${blockIndex}">${t("copyLast")}</button><button class="button ghost full" data-action="plus-set" data-block="${blockIndex}">${t("copyPlus")}</button></div>
    ${block.sets.map((set, setIndex) => `<div class="set-entry"><span>${tx("Set", "Підхід")} ${setIndex + 1}</span><div class="set-row"><input inputmode="decimal" aria-label="${txAttr("Weight", "Вага")}" data-block="${blockIndex}" data-set="${setIndex}" data-field="weight" value="${escapeAttr(set.weight)}" placeholder="kg"><input inputmode="numeric" aria-label="${txAttr("Reps", "Повтори")}" data-block="${blockIndex}" data-set="${setIndex}" data-field="reps" value="${escapeAttr(set.reps)}" placeholder="${txAttr("Reps", "Повтори")}"><button class="icon-button" data-action="remove-set" data-block="${blockIndex}" data-set="${setIndex}" aria-label="${txAttr("Remove set", "Видалити підхід")}">${svg("delete")}</button></div></div>`).join("")}
  </details></section>`;
}

function smartPanel(rec, blockIndex) {
  return `<div class="subpanel smart"><div class="row-head"><div><strong>${t("smartCoach")}</strong><p>${rec.kind}</p></div>${svg("auto", "small-icon")}</div><p>${rec.sets.map(s => `${s.weight == null ? tx("light", "легко") : `${s.weight.toFixed(1)} kg`} x ${s.reps}`).join(" | ")}</p><div class="progress"><span class="${percentageClass(rec.confidence * 100)}"></span></div><small>${tx("Confidence", "Впевненість")} ${Math.round(rec.confidence * 100)}%</small>${rec.reasons.slice(0, 3).map(reason => `<p class="muted">${escapeHtml(reason)}</p>`).join("")}<button class="button full" data-action="apply-smart" data-block="${blockIndex}">${svg("auto", "small-icon")}${t("applySmart")}</button></div>`;
}

function draftSetSummary(block) {
  const setLabel = `${block.sets.length} ${tx("sets", "підходів")}`;
  const details = block.sets.map(set => `${set.weight === "" ? "—" : formatSetWeight(set.weight)} kg x ${set.reps || "—"}`).join(" · ");
  return details ? `${setLabel} · ${details}` : setLabel;
}

function muscleContributionPanel(exercise, compact = false) {
  const contributions = contributionFor(exercise).slice(0, compact ? 3 : 6);
  if (!contributions.length) return "";
  return `<div class="chip-row">${contributions.map(item => `<span class="chip">${muscleLabel(item.muscleId)} ${Math.round(item.weight * 100)}%</span>`).join("")}</div>`;
}

function exerciseDetailBodyMap(exercise, mode) {
  const contributions = contributionFor(exercise).filter(item => muscles.some(([id]) => id === item.muscleId));
  if (!contributions.length) return "";
  const data = muscles.map(([id]) => {
    const contribution = contributions.find(item => item.muscleId === id);
    return { id, load: contribution?.weight || 0 };
  });
  const maxLoad = Math.max(1, ...data.map(item => item.load));
  const expanded = mode === "expanded";
  return `<div class="detail-muscle-map detail-${expanded ? "expanded" : "collapsed"}-map">${expanded ? `<span class="field-caption">${tx("Target muscles", "Цільові м'язи")}</span>` : ""}${sourceBodyMapSvg(data, maxLoad, { interactive: false, showLabels: false })}</div>`;
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
    "2 / week": tx("2 / week", "2 рази на тиждень"),
    "3 / week": tx("3 / week", "3 рази на тиждень"),
    "4 / week": tx("4 / week", "4 рази на тиждень"),
    "5 / week": tx("5 / week", "5 разів на тиждень"),
    "6 / week": tx("6 / week", "6 разів на тиждень"),
    "Aesthetic Cut": tx("Aesthetic Cut", "Сушка"),
    "Muscle Gain": tx("Muscle Gain", "Набір м'язів"),
    Strength: tx("Strength", "Сила"),
    Balanced: tx("Balanced", "Баланс"),
    Deficit: tx("Deficit", "Дефіцит"),
    Maintenance: tx("Maintenance", "Підтримання"),
    Surplus: tx("Surplus", "Профіцит")
  }[value] || tx("Unknown", "Невідомо");
}

function createDraft(source) {
  const blocks = source ? exerciseReferencesForSession(source).map(exercise => ({
    exerciseName: exercise.name,
    ...(persistedExerciseCatalogKey(exercise) ? { catalogKey: persistedExerciseCatalogKey(exercise) } : {}),
    sets: source.sets.filter(set => exercisesMatch(set, exercise)).map(set => ({ weight: set.weight, reps: set.reps }))
  })) : [{ exerciseName: "", sets: [{ weight: "", reps: "" }] }];
  return { startedAt: Date.now(), note: source?.note || "", blocks };
}

const SMART_HISTORY_SESSION_LIMIT = 24;
const SMART_DEFAULT_SET_COUNT = 3;
const SMART_FUTURE_CLOCK_SKEW_MS = 24 * 60 * 60 * 1000;

function smartRecommendation(exercise) {
  const sessions = smartExerciseSessionHistory(exercise);
  const repRange = smartRepRange();
  if (!sessions.length) {
    const baseline = tx("No saved history yet, so this starts with a clean baseline.", "Історії ще немає, тому план починається з чистої бази.");
    return {
      kindId: "NewExercise",
      kind: smartKindLabel("NewExercise"),
      sets: Array.from({ length: smartTargetSetCount(SMART_DEFAULT_SET_COUNT) }, () => ({
        weight: null,
        reps: clamp(state.profile.goal === "Strength" ? 5 : 10, repRange.min, repRange.max)
      })),
      confidence: 0.35,
      estimatedVolume: 0,
      daysSinceLastSession: null,
      reasons: [baseline],
      reason: baseline
    };
  }

  const latest = sessions[0];
  const previous = sessions[1];
  const daysSinceLastSession = daysBetween(latest.date, Date.now());
  const bestEstimatedMax = Math.max(...sessions.map(s => s.estimatedMax));
  const plateauDetected = smartPlateauDetected(sessions);
  const repeatedRegression = sessions.length >= 3 &&
    smartSessionRegressed(latest, previous) &&
    smartSessionRegressed(previous, sessions[2]);
  const earnedProgression = latest.sets.length > 0 &&
    latest.sets.every(set => smartBoundedReps(set.reps, repRange.min) >= repRange.max);
  const latestNearBest = latest.estimatedMax >= bestEstimatedMax * 0.97;
  const previousVolume = previous?.averageVolumePerSet || latest.averageVolumePerSet;
  const volumeRatio = previousVolume <= 0 ? 1 : latest.averageVolumePerSet / previousVolume;
  const latestStable = latest.sets.length >= 2 && latest.sets.every(set => smartBoundedReps(set.reps, repRange.min) >= repRange.min);
  const latestStrained = latest.minReps < repRange.min || volumeRatio < 0.88;
  const isFatLossDeficit = state.profile.goal === "Aesthetic Cut" && state.profile.calories === "Deficit";

  let kindId;
  if (daysSinceLastSession >= 10) kindId = "Comeback";
  else if (repeatedRegression) kindId = "Deload";
  else if (earnedProgression) kindId = "ProgressiveOverload";
  else if (plateauDetected) kindId = "PlateauBreak";
  else kindId = "HoldAndBuild";

  const targetSetCount = smartTargetSetCount(latest.sets.length);
  const baselineSets = smartBaselineSets(latest.sets, targetSetCount);
  const plateauUsesLowerRange = latest.averageReps >= (repRange.min + repRange.max) / 2;
  const sets = baselineSets.map((set, index) => {
    const weight = smartBoundedWeight(set.weight);
    const reps = smartBoundedReps(set.reps, repRange.min);
    if (kindId === "ProgressiveOverload") {
      return {
        weight: weight > 0 ? smartBoundedWeight(weight + chooseWeightStep(weight)) : 0,
        reps: weight > 0 ? repRange.min : repRange.max
      };
    }
    if (kindId === "Deload") {
      return {
        weight: smartBoundedWeight(weight * (isFatLossDeficit ? 0.9 : 0.92)),
        reps: clamp(reps, repRange.min, repRange.max)
      };
    }
    if (kindId === "Comeback") {
      return {
        weight: smartBoundedWeight(weight * comebackMultiplier(daysSinceLastSession)),
        reps: clamp(reps, repRange.min, repRange.max)
      };
    }
    if (kindId === "PlateauBreak") {
      return {
        weight,
        reps: plateauUsesLowerRange
          ? clamp(repRange.min + index % 2, repRange.min, repRange.max)
          : clamp(repRange.max - index % 2, repRange.min, repRange.max)
      };
    }
    return { weight, reps: clamp(reps + 1, repRange.min, repRange.max) };
  });
  const reasons = [];
  if (latestStable) reasons.push(tx("Last session was stable across the sets.", "Результати останнього тренування були стабільними в усіх підходах."));
  if (latestStrained && !repeatedRegression) reasons.push(tx("One softer session is held steady; a deload needs two comparable regressions.", "Одне слабше тренування утримує навантаження; для розвантаження потрібні два порівнювані спади."));
  if (repeatedRegression) reasons.push(tx("Two comparable regressions in a row triggered a recovery step.", "Два порівнювані спади поспіль запустили відновлювальний крок."));
  if (daysSinceLastSession >= 10) reasons.push(tx(`${daysSinceLastSession} days since this exercise, so the load is adjusted down.`, `${daysSinceLastSession} днів без цієї вправи, тому навантаження знижено.`));
  if (volumeRatio >= 1.08) reasons.push(tx("Recent volume is trending up.", "Останній обсяг зростає."));
  if (volumeRatio < 0.9) reasons.push(tx("Recent volume dropped compared with the previous session.", "Обсяг останнього тренування нижчий за обсяг попереднього."));
  if (plateauDetected) reasons.push(tx("Four comparable sessions showed no meaningful strength, rep, or per-set volume gain.", "Чотири порівнювані тренування не дали помітного приросту сили, повторів або обсягу на підхід."));
  if (latestNearBest) reasons.push(tx("This is close to your best estimated strength for the exercise.", "Це близько до найкращої оцінки сили в цій вправі."));
  if (state.profile.goal === "Aesthetic Cut") reasons.push(tx("Aesthetic goal: the plan favors clean volume and technique.", "Ціль сушки: план тримає чистий обсяг і техніку."));
  if (state.profile.goal === "Muscle Gain") reasons.push(tx("Muscle-gain goal adds recoverable working volume.", "Ціль набору м'язів додає відновлюваний робочий обсяг."));
  if (state.profile.calories === "Deficit") reasons.push(tx("Calorie deficit trims set volume but still allows earned progression.", "Дефіцит калорій зменшує кількість підходів, але не блокує заслужену прогресію."));
  if (state.profile.calories === "Surplus") reasons.push(tx("Calorie surplus supports an additional recoverable set.", "Профіцит калорій підтримує додатковий відновлюваний підхід."));
  if (state.profile.days === 4 && state.profile.split === "Upper / Lower") reasons.push(tx("Upper/lower 4-day plan: the load leaves room for the next session.", "План верх/низ 4 дні: навантаження лишає запас для наступної сесії."));
  if (kindId === "ProgressiveOverload") reasons.push(tx("Every saved set reached the top of the rep range, so load increases conservatively.", "Кожен збережений підхід досяг верхньої межі повторів, тому вага зростає обережно."));
  const uniqueReasons = [...new Set(reasons)].slice(0, 3);
  return {
    kindId,
    kind: smartKindLabel(kindId),
    sets,
    confidence: confidenceFor(sessions.length, latest.sets.length, daysSinceLastSession),
    estimatedVolume: sets.reduce((sum, set) => sum + (set.weight || 0) * set.reps, 0),
    daysSinceLastSession,
    reasons: uniqueReasons.length ? uniqueReasons : [tx("The increase is intentionally conservative.", "Збільшення навмисно невелике.")],
    reason: (uniqueReasons[0] || tx("The increase is intentionally conservative.", "Збільшення навмисно невелике."))
  };
}

function smartExerciseSessionHistory(exercise) {
  const requested = typeof exercise === "string" ? { name: exercise } : exercise;
  if (!exerciseRawName(requested)) return [];
  const sessionLimit = window.GymStateContract.LIMITS.sessions;
  const setLimit = window.GymStateContract.LIMITS.setsPerExercise;
  const latestAllowedDate = Date.now() + SMART_FUTURE_CLOCK_SKEW_MS;
  return state.sessions
    .slice(0, sessionLimit)
    .map(session => ({
      id: session.id,
      date: Number(session.startedAt),
      sets: (session.sets || [])
        .filter(set => smartSetUsable(set) && exercisesMatch(set, requested))
        .sort((left, right) => left.orderIndex - right.orderIndex || String(left.id).localeCompare(String(right.id)))
        .slice(0, setLimit)
    }))
    .filter(session => Number.isFinite(session.date) && session.date <= latestAllowedDate && session.sets.length)
    .sort((left, right) => right.date - left.date || String(right.id).localeCompare(String(left.id)))
    .slice(0, SMART_HISTORY_SESSION_LIMIT)
    .map(snapshotForExerciseSession);
}

function smartSetUsable(set) {
  const limits = window.GymStateContract.LIMITS;
  const weight = Number(set?.weight);
  const reps = Number(set?.reps);
  const orderIndex = Number(set?.orderIndex);
  return Boolean(exerciseRawName(set)) &&
    Number.isFinite(weight) && weight >= 0 && weight <= limits.weightMax &&
    Number.isInteger(reps) && reps >= 1 && reps <= limits.repsMax &&
    Number.isInteger(orderIndex) && orderIndex >= 0 && orderIndex < limits.setsPerExercise;
}

function smartUsableHistory(history = allSets(), nowMillis = Date.now()) {
  const latestAllowedDate = nowMillis + SMART_FUTURE_CLOCK_SKEW_MS;
  return history
    .slice(0, window.GymStateContract.LIMITS.totalSets)
    .filter(set => {
      const sessionDate = Number(set?.session?.startedAt);
      return Number.isFinite(sessionDate) && sessionDate <= latestAllowedDate && smartSetUsable(set);
    });
}

function snapshotForExerciseSession(session) {
  const sets = session.sets.map(set => ({
    ...set,
    weight: smartBoundedWeight(set.weight),
    reps: smartBoundedReps(set.reps, 1)
  }));
  const weights = sets.map(set => set.weight);
  const reps = sets.map(set => set.reps);
  const volume = sets.reduce((sum, set) => sum + set.weight * set.reps, 0);
  return {
    ...session,
    sets,
    maxWeight: Math.max(...weights),
    minReps: Math.min(...reps),
    averageReps: reps.reduce((sum, value) => sum + value, 0) / reps.length,
    volume,
    averageVolumePerSet: volume / sets.length,
    estimatedMax: Math.max(...sets.map(set => set.weight * (1 + set.reps / 30)))
  };
}

function smartRepRange() {
  if (state.profile.goal === "Strength") return { min: 3, max: 6 };
  if (state.profile.goal === "Muscle Gain") return { min: 8, max: 12 };
  if (state.profile.goal === "Aesthetic Cut") return { min: 8, max: 14 };
  return { min: 6, max: 12 };
}

function smartTargetSetCount(latestSetCount = SMART_DEFAULT_SET_COUNT) {
  const goal = state.profile.goal;
  const calories = state.profile.calories;
  const days = Number(state.profile.days);
  let target = Number.isInteger(latestSetCount) ? latestSetCount : SMART_DEFAULT_SET_COUNT;
  if (goal === "Muscle Gain") target += 1;
  if (calories === "Deficit") target -= 1;
  if (calories === "Surplus") target += 1;
  if (days <= 2) target += 1;
  if (days >= 5) target -= 1;
  const bounds = goal === "Strength"
    ? { min: 3, max: 5 }
    : goal === "Muscle Gain"
      ? { min: 3, max: 6 }
      : goal === "Aesthetic Cut"
        ? { min: 2, max: 4 }
        : { min: 2, max: 5 };
  return clamp(Math.round(target), bounds.min, bounds.max);
}

function smartBaselineSets(latestSets, targetSetCount) {
  const source = latestSets.slice(0, window.GymStateContract.LIMITS.setsPerExercise);
  const fallback = source.at(-1) || { weight: 0, reps: smartRepRange().min };
  return Array.from({ length: targetSetCount }, (_, index) => source[index] || fallback);
}

function smartSessionRegressed(current, previous) {
  if (!current || !previous || previous.estimatedMax <= 0 || previous.averageVolumePerSet <= 0) return false;
  return current.estimatedMax < previous.estimatedMax * 0.97 &&
    current.averageVolumePerSet < previous.averageVolumePerSet * 0.92;
}

function smartPlateauDetected(sessions) {
  const recent = sessions.slice(0, 4);
  if (recent.length < 4 || recent.some(session => session.estimatedMax <= 0 || session.averageVolumePerSet <= 0)) return false;
  const oldest = recent.at(-1);
  const latest = recent[0];
  const estimatedMaxValues = recent.map(session => session.estimatedMax);
  const volumeValues = recent.map(session => session.averageVolumePerSet);
  const estimatedMaxSpread = (Math.max(...estimatedMaxValues) - Math.min(...estimatedMaxValues)) / Math.max(...estimatedMaxValues);
  const volumeSpread = (Math.max(...volumeValues) - Math.min(...volumeValues)) / Math.max(...volumeValues);
  return estimatedMaxSpread <= 0.02 &&
    volumeSpread <= 0.03 &&
    latest.estimatedMax <= oldest.estimatedMax * 1.015 &&
    latest.averageReps <= oldest.averageReps + 0.25 &&
    latest.averageVolumePerSet <= oldest.averageVolumePerSet * 1.02;
}

function smartBoundedWeight(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return 0;
  return clamp(roundToNearestHalf(numeric), 0, window.GymStateContract.LIMITS.weightMax);
}

function smartBoundedReps(value, fallback) {
  const numeric = Number(value);
  const safe = Number.isFinite(numeric) ? Math.round(numeric) : fallback;
  return clamp(safe, 1, window.GymStateContract.LIMITS.repsMax);
}

function chooseWeightStep(weight) {
  const baseStep = weight < 20 ? 1 : weight < 60 ? 2.5 : weight < 120 ? 5 : 7.5;
  return state.profile.goal === "Aesthetic Cut" || state.profile.calories === "Deficit" ? baseStep * 0.5 : baseStep;
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
    PlateauBreak: tx("Plateau plan: change the rep target to break the flat trend.", "План виходу з плато: зміни ціль за повторами, щоб подолати застій.")
  }[kindId] || tx("Build plan: hold weight and add reps before the next jump.", "План набору: тримай вагу й додай повтори перед наступним стрибком.");
}

function lastWeightFor(name) {
  if (!name) return null;
  const set = allSets().filter(s => s.exerciseName.toLowerCase() === name.toLowerCase()).sort((a, b) => b.session.startedAt - a.session.startedAt)[0];
  return set ? Number(set.weight) : null;
}

function legacyDetailScreenOld(id) {
  const session = state.sessions.find(s => s.id === id);
  if (!session) return `<div class="empty">${tx("Workout not found.", "Тренування не знайдено.")}</div>`;
  const grouped = exerciseReferencesForSession(session).map(exercise => ({ ...exercise, sets: session.sets.filter(set => exercisesMatch(set, exercise)) }));
  const available = state.exercises.filter(exercise => !grouped.some(group => exercisesMatch(group, exercise)));
  const garmin = parseGarminWorkoutMetrics(session.note || "");
  return `<section class="panel"><h2>${fmtDate(session.startedAt)}</h2><p>${session.note ? escapeHtml(session.note) : tx("No note", "Без нотатки")}</p></section>
    ${!session.sets.length && grouped.length ? `<section class="panel warning"><h2>${tx("No set data", "Немає даних підходів")}</h2><p>${tx("This imported workout contains exercise names, but no weights or reps. Export a full Backup JSON from the Android app and import it again.", "У цьому імпортованому тренуванні є назви вправ, але немає ваги й повторів. Експортуй повний Backup JSON з Android-додатка й імпортуй ще раз.")}</p></section>` : ""}
    <section class="panel"><div class="section-title"><h2>${tx("Add Exercise to This Workout", "Додати вправу в це тренування")}</h2></div>${available.length ? `<select id="quick-add">${available.map(ex => `<option value="${ex.id}">${escapeHtml(exerciseDisplayName(ex))}</option>`).join("")}</select><button class="button full" data-action="quick-add-exercise">${tx("Add to Workout", "Додати до тренування")}</button>` : `<p class="muted">${tx("All saved exercises are already in this workout.", "Усі збережені вправи вже є в цьому тренуванні.")}</p>`}</section>
    ${garmin ? garminWorkoutMetricsCard(session, garmin, grouped) : ""}
    ${grouped.map(group => exerciseDetailCard(session, group, Boolean(garmin))).join("")}
    <button class="fab finish-fab" data-action="finish-workout" data-id="${session.id}">${svg("check", "small-icon")}${t("finishWorkout")}</button>`;
}

function legacyExerciseDetailCard(session, group) {
  const key = `${session.id}:${group.name}`;
  const remaining = timerRemaining(key);
  return `<section class="panel highlighted"><div class="row-head"><h2>${escapeHtml(exerciseDisplayName(group))}</h2>${isPr(session, group) ? `<span class="pill">${svg("trophy", "small-icon")}${tx("New PR", "Новий PR")}</span>` : ""}</div>
    ${group.sets.length ? `<div class="timer-row"><div><strong>${tx("Exercise Rest", "Відпочинок")}</strong><span data-timer-display="${escapeAttr(key)}" aria-live="polite">${remaining > 0 ? formatTimer(remaining) : tx("Ready", "Готово")}</span></div><div class="actions"><button class="button ghost mini" data-action="timer" data-key="${escapeAttr(key)}" data-seconds="60">60s</button><button class="button ghost mini" data-action="timer" data-key="${escapeAttr(key)}" data-seconds="90">90s</button><button class="button ghost mini" data-action="timer" data-key="${escapeAttr(key)}" data-seconds="180">180s</button><button class="button ghost mini" data-action="timer-stop" data-timer-stop="${escapeAttr(key)}" data-key="${escapeAttr(key)}" ${remaining ? "" : "disabled"}>${tx("Stop", "Стоп")}</button></div></div>
    <div class="table"><div class="table-head"><span>${tx("Set", "Підхід")}</span><span>${tx("Weight (kg)", "Вага (кг)")}</span><span>${tx("Reps", "Повтори")}</span><span></span></div>${group.sets.map((set, i) => `<div class="table-row"><span>${tx("Set", "Підхід")} ${i + 1}</span><span>${Number(set.weight).toFixed(1)}</span><span>${set.reps}</span><span><button class="icon-button" data-action="edit-set" data-id="${set.id}" aria-label="${txAttr("Edit set", "Редагувати підхід")}">${svg("edit")}</button><button class="icon-button" data-action="delete-set" data-id="${set.id}" data-session="${escapeAttr(session.id)}" aria-label="${txAttr("Delete set", "Видалити підхід")}">${svg("delete")}</button></span></div>`).join("")}</div>` : `<div class="empty">${tx("No sets were imported for this exercise.", "Для цієї вправи не імпортовано підходи.")}</div>`}
    <button class="button ghost full" data-action="detail-add-set" data-session="${session.id}" data-name="${escapeAttr(group.name)}">${t("addSet")}</button>
  </section>`;
}

function detailScreen(id) {
  const session = state.sessions.find(s => s.id === id);
  if (!session) return `<div class="empty">${tx("Workout not found.", "Тренування не знайдено.")}</div>`;
  const grouped = exerciseReferencesForSession(session).map(exercise => ({ ...exercise, sets: session.sets.filter(set => exercisesMatch(set, exercise)) }));
  const available = state.exercises.filter(exercise => !grouped.some(group => exercisesMatch(group, exercise)));
  const garmin = parseGarminWorkoutMetrics(session.note || "");
  return `${garmin ? garminWorkoutHeader(session, garmin, grouped) : workoutHeader(session)}
    ${garmin ? garminWorkoutMetricsCard(garmin) : ""}
    ${!session.sets.length && grouped.length ? `<section class="panel warning"><h2>${tx("No set data", "Немає даних підходів")}</h2><p>${tx("This imported workout contains exercise names, but no weights or reps. Export a full Backup JSON from the Android app and import it again.", "У цьому імпортованому тренуванні є назви вправ, але немає ваги й повторів. Експортуй повну резервну копію JSON з Android-застосунку й імпортуй її ще раз.")}</p></section>` : ""}
    <section class="panel"><div class="section-title"><div><h2>${tx("Add Exercise to This Workout", "Додати вправу в це тренування")}</h2></div>${svg("add", "small-icon")}</div>${available.length ? `<select id="quick-add">${available.map(ex => `<option value="${ex.id}">${escapeHtml(exerciseDisplayName(ex))}</option>`).join("")}</select><button class="button full" data-action="quick-add-exercise">${tx("Add to Workout", "Додати до тренування")}</button>` : `<p class="muted">${tx("All saved exercises are already in this workout.", "Усі збережені вправи вже додано до цього тренування.")}</p>`}</section>
    ${grouped.map(group => exerciseDetailCard(session, group, Boolean(garmin))).join("")}
    <button class="fab finish-fab" data-action="finish-workout" data-id="${session.id}">${svg("check", "small-icon")}${t("finishWorkout")}</button>`;
}

function workoutHeader(session) {
  return `<section class="panel"><div class="row-head"><div><h2>${fmtDate(session.startedAt)}</h2><p>${session.note ? `${t("note")}: ${escapeHtml(session.note)}` : tx("No note", "Без нотатки")}</p></div><button class="icon-button" data-action="delete-session" data-id="${session.id}" aria-label="${txAttr("Delete workout", "Видалити тренування")}">${svg("delete")}</button></div></section>`;
}

function garminWorkoutHeader(session, metrics, grouped) {
  const setCount = grouped.reduce((sum, group) => sum + group.sets.length, 0);
  return `<section class="panel highlighted garmin-header"><div class="row-head"><div><h2>${tx("Garmin strength workout", "Силове тренування Garmin")}</h2><p class="muted">${fmtDate(session.startedAt)} · ${tx("synced from Garmin", "синхронізовано з Garmin")}</p></div><button class="icon-button" data-action="delete-session" data-id="${session.id}" aria-label="${txAttr("Delete workout", "Видалити тренування")}">${svg("delete")}</button></div>
    <div class="metric-grid"><div><span>${tx("Duration", "Тривалість")}</span><strong>${metrics.duration || "—"}</strong><small>${tx("watch session", "тренування з годинника")}</small></div><div><span>${tx("Logged", "Записано")}</span><strong>${setCount} ${tx("sets", "підходів")}</strong><small>${grouped.length} ${tx("exercises", "вправ")}</small></div></div>
    <p class="muted">${tx("Synced sets are grouped below. Expand an exercise to edit weight, reps, add a missed set, or delete a wrong one.", "Синхронізовані підходи згруповано нижче. Розгорни вправу, щоб змінити вагу чи повтори, додати пропущений підхід або видалити помилковий.")}</p>
  </section>`;
}

function garminWorkoutMetricsCard(metrics) {
  return `<section class="panel garmin-metrics"><h2>${tx("Garmin strength metrics", "Показники силового тренування Garmin")}</h2>
    <div class="metric-grid">
      <div><span>${tx("Gym kcal", "Gym ккал")}</span><strong>${metrics.gymCalories ?? "—"}</strong><small>${tx("our formula", "наша формула")}</small></div>
      <div><span>${tx("Garmin kcal", "Garmin ккал")}</span><strong>${metrics.garminCalories ?? "—"}</strong><small>${tx("system", "система")}</small></div>
      <div><span>${tx("Avg HR", "Середній пульс")}</span><strong>${metrics.avgHeartRate ? `${metrics.avgHeartRate} bpm` : "—"}</strong><small>${metrics.duration || tx("duration", "тривалість")}</small></div>
      <div><span>${tx("Max HR", "Максимальний пульс")}</span><strong>${metrics.maxHeartRate ? `${metrics.maxHeartRate} bpm` : "—"}</strong><small>${metrics.heartRateZone || tx("peak", "максимум")}</small></div>
    </div>
    <p class="muted">${tx("Gym kcal is saved from the Garmin app strength formula. Garmin kcal is the system value Garmin Connect uses for daily calories.", "Gym ккал збережено за силовою формулою застосунку Garmin. Garmin ккал — системне значення, яке Garmin Connect враховує в добових калоріях.")}</p>
  </section>`;
}

function parseGarminWorkoutMetrics(note) {
  if (!/^Garmin(?: Fenix 8)?(?: ·|$)/i.test(String(note || "").trim())) return null;
  const findText = regex => (regex.exec(note || "") || [])[1] || "";
  const findNumber = regex => {
    const value = Number.parseInt(findText(regex), 10);
    return Number.isFinite(value) ? value : null;
  };
  return {
    duration: findText(/(?:Duration|Тривалість)\s+([0-9]+:[0-9]{2}(?::[0-9]{2})?)/i),
    gymCalories: findNumber(/Gym\s+(?:kcal|ккал)\s+([0-9]+)/i),
    garminCalories: findNumber(/Garmin\s+(?:kcal|ккал)\s+([0-9]+)/i),
    avgHeartRate: findNumber(/(?:Avg HR|Сер пульс)\s+([0-9]+)/i),
    maxHeartRate: findNumber(/(?:Max HR|Макс пульс)\s+([0-9]+)/i),
    heartRateZone: findText(/(?:HR zone|Зона пульсу)\s+(Z[0-9]+)/i)
  };
}

function exerciseDetailCard(session, group, isGarminWorkout = false) {
  const key = `${session.id}:${group.name}`;
  const remaining = timerRemaining(key);
  const setSummary = group.sets.length
    ? `${group.sets.length} ${tx("sets", "підходів")} · ${group.sets.map(set => `${formatSetWeight(set.weight)} kg x ${set.reps}`).join(" · ")}`
    : tx("No sets", "Немає підходів");
  const restTimer = isGarminWorkout ? "" : `<div class="timer-row"><div><strong>${tx("Exercise Rest", "Відпочинок")}</strong><span data-timer-display="${escapeAttr(key)}" aria-live="polite">${remaining > 0 ? formatTimer(remaining) : tx("Ready", "Готово")}</span></div><div class="actions"><button class="button ghost mini" data-action="timer" data-key="${escapeAttr(key)}" data-seconds="60">60s</button><button class="button ghost mini" data-action="timer" data-key="${escapeAttr(key)}" data-seconds="90">90s</button><button class="button ghost mini" data-action="timer" data-key="${escapeAttr(key)}" data-seconds="180">180s</button><button class="button ghost mini" data-action="timer-stop" data-timer-stop="${escapeAttr(key)}" data-key="${escapeAttr(key)}" ${remaining ? "" : "disabled"}>${tx("Stop", "Стоп")}</button></div></div>`;
  return `<section class="panel highlighted workout-exercise-card"><details ${isGarminWorkout ? "" : "open"}><summary class="detail-summary"><div><h2>${escapeHtml(exerciseDisplayName(group))}</h2><p class="muted">${escapeHtml(setSummary)}</p></div>${isPr(session, group) ? `<span class="pill">${svg("trophy", "small-icon")}${tx("New PR", "Новий рекорд")}</span>` : ""}</summary>
    ${exerciseDetailBodyMap(group, "collapsed")}
    ${!isGarminWorkout ? exerciseDetailBodyMap(group, "expanded") : ""}
    ${group.sets.length ? `${restTimer}<div class="table"><div class="table-head"><span>${tx("Set", "Підхід")}</span><span>${tx("Weight (kg)", "Вага (кг)")}</span><span>${tx("Reps", "Повтори")}</span><span></span></div>${group.sets.map((set, i) => `<div class="table-row"><span>${tx("Set", "Підхід")} ${i + 1}</span><span>${Number(set.weight).toFixed(1)}</span><span>${set.reps}</span><span><button class="icon-button" data-action="edit-set" data-id="${set.id}" aria-label="${txAttr("Edit set", "Редагувати підхід")}">${svg("edit")}</button><button class="icon-button" data-action="delete-set" data-id="${set.id}" data-session="${escapeAttr(session.id)}" aria-label="${txAttr("Delete set", "Видалити підхід")}">${svg("delete")}</button></span></div>`).join("")}</div>` : `<div class="empty">${tx("No sets were imported for this exercise.", "Для цієї вправи не імпортовано жодного підходу.")}</div>`}
    <button class="button ghost full" data-action="detail-add-set" data-session="${session.id}" data-name="${escapeAttr(group.name)}">${t("addSet")}</button>
  </details></section>`;
}

function formatSetWeight(weight) {
  const value = Number(weight);
  if (!Number.isFinite(value)) return "0";
  return value % 1 === 0 ? String(value.toFixed(0)) : value.toFixed(1);
}

function formatLocalizedSetWeight(weight) {
  const value = Number(weight);
  const normalized = Number.isFinite(value) ? value : 0;
  const amount = new Intl.NumberFormat(displayLocale(), {
    minimumFractionDigits: 0,
    maximumFractionDigits: 1
  }).format(normalized);
  return `${amount} ${tx("kg", "кг")}`;
}

function isPr(session, exercise) {
  const previous = allSets(state.sessions.filter(s => s.startedAt < session.startedAt)).filter(set => exercisesMatch(set, exercise)).map(set => set.weight);
  const current = session.sets.filter(set => exercisesMatch(set, exercise)).map(set => set.weight);
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
  const records = exerciseReferencesForSession(session).map(exercise => {
    const prev = Math.max(0, ...allSets(before).filter(set => exercisesMatch(set, exercise)).map(set => set.weight));
    const now = Math.max(0, ...session.sets.filter(set => exercisesMatch(set, exercise)).map(set => set.weight));
    return now > prev ? { ...exercise, prev, now } : null;
  }).filter(Boolean);
  const mStats = muscleStats([session]).filter(m => m.load > 0).sort((a, b) => b.load - a.load);
  const rewards = summaryRewards(session, records);
  return `<section class="hero-panel summary-hero"><h2>${t("workoutComplete")}</h2><p>${fmtDate(session.startedAt)}</p><div class="hero-info-row"><span class="hero-info-pill">+${xpGain} XP</span><span class="hero-info-pill">${tx("Level", "Рівень")} ${levelFromXp(xpTotal)}</span></div></section>
    <section class="metric-grid post summary-metrics"><div><span>${tx("XP gained", "Отримано XP")}</span><strong>+${xpGain} XP</strong></div><div><span>${tx("Current title", "Поточний ранг")}</span><strong>${rankTitle(xpTotal)}</strong></div><div><span>${tx("Streak", "Серія")}</span><strong>${streakDays()} ${tx("d", "д")}</strong></div><div><span>${tx("Exercises", "Вправи")}</span><strong>${summary.exercises}</strong></div><div><span>${tx("Sets", "Підходи")}</span><strong>${summary.sets}</strong></div><div><span>${tx("Volume", "Обсяг")}</span><strong>${Math.round(summary.volume)}</strong></div></section>
    <section class="panel ${mStats.length ? "highlighted" : ""}"><h2>${t("impact")}</h2><p class="muted">${mStats[0] ? `${tx("Most loaded today", "Найбільше навантажено сьогодні")}: ${mStats[0].label}` : tx("Mapped muscle load will appear after sets are saved.", "Навантаження м'язів з'явиться після збереження підходів.")}</p>${mStats.slice(0, 5).map(m => barRow(m.label, m.load, mStats[0]?.load || 1, `${Math.round(m.load)} ${tx("load", "навантаження")} - ${n(m.sets, "set", "sets", "підхід", "підходи", "підходів")}`)).join("")}</section>
    ${records.length ? `<section class="panel highlighted"><h2>${t("personalRecords")}</h2>${records.map(r => `<div class="row-line"><div><strong>${escapeHtml(exerciseDisplayName(r))}</strong><p>${r.prev ? `${tx("Previous best", "Попередній рекорд")} ${r.prev.toFixed(1)} kg` : tx("First logged best", "Перший зафіксований рекорд")}</p></div><span class="pill">${r.now.toFixed(1)} kg</span></div>`).join("")}</section>` : ""}
    <section class="panel"><h2>${t("levelProgress")}</h2><p>${tx("Level", "Рівень")} ${levelFromXp(xpTotal)} - ${rankTitle(xpTotal)}</p><div class="progress"><span class="${percentageClass(progress.progressFraction * 100)}"></span></div><div class="row-line"><span>${progress.currentLevelXp} XP ${tx("into this level", "на цьому рівні")}</span><strong>${progress.xpForNextLevel - progress.currentLevelXp} XP ${tx("to next", "до наступного")}</strong></div></section>
    <section class="panel"><h2>${t("momentum")}</h2><p>${streakDays() > 1 ? `${tx("Streak extended to", "Серію продовжено до")} ${streakDays()} ${tx("days.", "днів.")}` : tx("A fresh streak has started.", "Нова серія почалася.")}</p><div class="chip-row"><span class="chip">${tx("Logged today", "Записано сьогодні")}</span><span class="chip">${tx("Best", "Найкраще")} ${streakDays()} ${tx("d", "д")}</span></div></section>
    ${summaryRewardsSection(rewards)}
    <div class="actions vertical"><button class="button full" data-action="summary-view" data-id="${session.id}">${tx("View workout", "Відкрити тренування")}</button><button class="button ghost full" data-action="summary-done">${tx("Back to workouts", "Назад до тренувань")}</button></div>`;
}

function summaryRewards(session, records) {
  const sessionIndex = state.sessions.filter(item => item.startedAt <= session.startedAt).length;
  const missionRewards = completedMissions().slice(0, 5).map(mission => ({
    title: mission.title,
    supporting: mission.summary,
    reward: mission.reward,
    badge: tx("Mission", "Місія")
  }));
  const badgeRewards = [
    sessionIndex === 1 ? { title: tx("First session", "Перша сесія"), supporting: tx("Workout streak started.", "Серію тренувань почато."), reward: 0, badge: tx("Common", "Звичайна") } : null,
    sessionIndex === 10 ? { title: tx("Ten sessions", "Десять сесій"), supporting: tx("Consistency milestone reached.", "Досягнуто віху стабільності."), reward: 0, badge: tx("Uncommon", "Незвичайна") } : null,
    records.length ? { title: tx("Personal record", "Особистий рекорд"), supporting: `${records.length} ${tx("new bests", "нових рекордів")}`, reward: 0, badge: tx("Rare", "Рідкісна") } : null
  ].filter(Boolean);
  return { missions: missionRewards, badges: badgeRewards };
}

function summaryRewardsSection(rewards) {
  const hasRewards = rewards.missions.length || rewards.badges.length;
  return `<section class="summary-rewards-heading"><span class="eyebrow">${tx("Rewards", "Нагороди")}</span><h2>${tx("What you unlocked", "Що відкрито")}</h2><p>${tx("Completed missions and new badges from this finish.", "Завершені місії та нові бейджі після фінішу.")}</p></section>${hasRewards ? [...rewards.missions, ...rewards.badges].map(item => `<section class="panel highlighted reward-card">${rewardRow(item)}</section>`).join("") : `<section class="panel highlighted empty-state-panel"><h3>${tx("No new unlocks", "Нових відкриттів немає")}</h3><p>${tx("Keep logging to unlock more.", "Продовжуй записувати тренування, щоб відкрити більше.")}</p></section>`}`;
}

function rewardRow(item) {
  return `<div class="row-line"><div><strong>${escapeHtml(item.title)}</strong><p>${escapeHtml(item.supporting)}</p></div><div class="actions"><span class="chip">${escapeHtml(item.badge)}</span>${item.reward ? `<span class="pill">+${item.reward} XP</span>` : ""}</div></div>`;
}

function loginAccount(rawName) {
  const name = String(rawName || "").trim();
  if (!name) return showToast(tx("Enter account name.", "Введи назву акаунта."));
  if (name.length > MAX_ACCOUNT_NAME_LENGTH || new TextEncoder().encode(name).byteLength > 256) {
    return showToast(tx("Account name is too long.", "Назва акаунта надто довга."));
  }
  if (/\p{C}/u.test(name) || !/[\p{L}\p{N}]/u.test(name)) {
    return showToast(tx("Use visible letters or numbers for account name.", "Використай видимі літери або цифри для назви акаунта."));
  }
  const accounts = accountList();
  const nameKey = name.normalize("NFKC").toLowerCase();
  const matches = accounts.filter(account => !account.remote &&
    account.name.normalize("NFKC").toLowerCase() === nameKey);
  if (matches.length > 1) {
    return showToast(tx(
      "This legacy local account name is ambiguous. Its stored data was left untouched; rename/recover it before signing in.",
      "Ця назва старого локального акаунта неоднозначна. Збережені дані не змінено; віднови або перейменуй акаунт перед входом."
    ));
  }
  let account = matches[0] || null;
  if (account && accounts.some(item => item.id === account.id &&
      (item.remote || item.name !== account.name))) {
    return showToast(tx(
      "A legacy storage-key collision was detected. Sign-in is blocked so one local account cannot open another account's data.",
      "Виявлено колізію старого ключа сховища. Вхід заблоковано, щоб один локальний акаунт не відкрив дані іншого."
    ));
  }
  const creatingAccount = !account;
  if (creatingAccount) {
    if (accounts.length >= MAX_LOCAL_ACCOUNTS) {
      return showToast(tx("Local account limit reached.", "Досягнуто ліміт локальних акаунтів."));
    }
    try {
      account = {
        id: createLocalAccountId(accounts),
        name,
        localIdVersion: LOCAL_ACCOUNT_ID_VERSION
      };
    } catch {
      return showToast(tx(
        "Secure local account creation is unavailable in this browser.",
        "Безпечне створення локального акаунта недоступне в цьому браузері."
      ));
    }
  }
  const key = activeStorageKey(account);
  if (!creatingAccount && !localStorage.getItem(key)) {
    return showToast(tx(
      "This saved local account is missing its state. Nothing was created or merged automatically.",
      "У цього збереженого локального акаунта відсутній стан. Нічого не створено й не об’єднано автоматично."
    ));
  }
  const previousAccountList = localStorage.getItem(ACCOUNT_LIST_KEY);
  const previousAuth = localStorage.getItem(AUTH_KEY);
  try {
    if (creatingAccount) {
      localStorage.setItem(key, JSON.stringify(defaultAppState()));
      saveAccountList([...accounts, account]);
    }
    localStorage.setItem(AUTH_KEY, JSON.stringify(account));
    clearRemoteSession();
  } catch {
    try {
      if (creatingAccount) {
        localStorage.removeItem(key);
        if (previousAccountList == null) localStorage.removeItem(ACCOUNT_LIST_KEY);
        else localStorage.setItem(ACCOUNT_LIST_KEY, previousAccountList);
      }
      if (previousAuth == null) localStorage.removeItem(AUTH_KEY);
      else localStorage.setItem(AUTH_KEY, previousAuth);
    } catch {
      // Preserve the original error message; storage may be unavailable.
    }
    return showToast(tx("Local account could not be saved.", "Не вдалося зберегти локальний акаунт."));
  }
  resetRemoteSyncContext();
  activeAccount = account;
  clearAuthDrafts();
  state = loadState();
  nav = [{ name: "workouts" }];
  replaceNavigationHistory();
  modal = null;
  render();
}

function createLocalAccountId(accounts = accountList()) {
  const secureCrypto = window.crypto;
  if (!secureCrypto || typeof secureCrypto.getRandomValues !== "function") {
    throw new Error("Secure randomness is unavailable.");
  }
  const existingIds = new Set(accounts.map(account => account.id));
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const bytes = new Uint8Array(16);
    secureCrypto.getRandomValues(bytes);
    const id = `local-v2-${[...bytes].map(byte => byte.toString(16).padStart(2, "0")).join("")}`;
    if (!existingIds.has(id) && !localStorage.getItem(ACCOUNT_PREFIX + id)) return id;
  }
  throw new Error("Unable to allocate a unique local account ID.");
}

function sanitizeDisplayName(value) {
  return String(value || "").replace(/[^\p{L}\p{N} ._-]/gu, "").replace(/\s+/g, " ").trim().slice(0, 32);
}

function normalizeAuthEmail(value) {
  return String(value || "").trim().toLowerCase();
}

const SUPABASE_PASSWORD_SYMBOLS = "!@#$%^&*()_+-=[]{};'\\:\"|<>?,./`~";

function validNewPassword(password) {
  const value = String(password || "");
  const characters = Array.from(value);
  return characters.length >= 12 && new TextEncoder().encode(value).length <= 72 &&
    /[a-z]/.test(value) && /[A-Z]/.test(value) && /[0-9]/.test(value) &&
    characters.some(character => SUPABASE_PASSWORD_SYMBOLS.includes(character));
}

function validateAuthInput(email, password, displayName = "", enforceNewPasswordPolicy = false) {
  const cleanEmail = normalizeAuthEmail(email);
  const cleanPassword = String(password || "");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(cleanEmail) || cleanEmail.length > 254) {
    return tx("Enter a valid email address.", "Введи коректну адресу електронної пошти.");
  }
  if (!cleanPassword) {
    return tx("Enter your password.", "Введи пароль.");
  }
  if (enforceNewPasswordPolicy && !validNewPassword(cleanPassword)) {
    return tx("Password must contain at least 12 characters, fit within 72 UTF-8 bytes, and include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol.", "Пароль має містити щонайменше 12 символів, займати не більше 72 байтів у UTF-8 та включати малу й велику латинські літери, цифру й підтримуваний спецсимвол.");
  }
  if (displayName && !/^[\p{L}\p{N} ._-]{2,32}$/u.test(displayName)) {
    return tx("Display name can use letters, numbers, spaces, dot, dash and underscore.", "В імені можна використовувати літери, цифри, пробіли, крапку, дефіс і підкреслення.");
  }
  return "";
}

function validateConfirmationEmail(email) {
  const cleanEmail = normalizeAuthEmail(email);
  if (!cleanEmail) return tx("Enter your email.", "Введи адресу електронної пошти.");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(cleanEmail) || cleanEmail.length > 254) {
    return tx("Enter a valid email address.", "Введи коректну адресу електронної пошти.");
  }
  return "";
}

function base64UrlEncode(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function createAuthTransaction(email, purpose) {
  if (!["signup", "recovery"].includes(purpose)) {
    throw new Error("Authentication transaction purpose is invalid.");
  }
  const secureCrypto = window.crypto;
  if (!secureCrypto || typeof secureCrypto.getRandomValues !== "function" ||
      typeof secureCrypto.subtle?.digest !== "function") {
    throw userVisibleError(
      "Secure email authentication is unavailable in this browser.",
      "Безпечна автентифікація електронною поштою недоступна в цьому браузері."
    );
  }
  const stateBytes = new Uint8Array(24);
  const verifierBytes = new Uint8Array(32);
  secureCrypto.getRandomValues(stateBytes);
  secureCrypto.getRandomValues(verifierBytes);
  const stateValue = base64UrlEncode(stateBytes);
  const verifier = base64UrlEncode(verifierBytes);
  const challenge = await pkceChallengeForVerifier(verifier);
  if (!/^[A-Za-z0-9_-]{32}$/.test(stateValue) || !/^[A-Za-z0-9_-]{43,128}$/.test(verifier)) {
    throw new Error("Authentication transaction generation failed.");
  }
  return {
    transaction: { version: 1, purpose, state: stateValue, verifier, email, createdAt: Date.now() },
    challenge
  };
}

async function pkceChallengeForVerifier(verifier) {
  if (!/^[A-Za-z0-9_-]{43,128}$/.test(verifier || "") ||
      typeof window.crypto?.subtle?.digest !== "function") {
    throw new Error("PKCE verifier is invalid.");
  }
  const digest = await window.crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return base64UrlEncode(new Uint8Array(digest));
}

async function signupAuthTransaction(email) {
  const existing = loadAuthTransaction("signup");
  if (existing?.email === email) {
    return {
      transaction: existing,
      challenge: await pkceChallengeForVerifier(existing.verifier),
      reused: true
    };
  }
  const generated = await createAuthTransaction(email, "signup");
  return { ...generated, reused: false };
}

function deterministicAuthRequestFailure(error) {
  return Number.isInteger(error?.status) && error.status >= 400 && error.status < 500;
}

function validAuthTransaction(value, expectedPurpose = null) {
  return Boolean(
    value && typeof value === "object" && !Array.isArray(value) && value.version === 1 &&
    ["signup", "recovery"].includes(value.purpose) &&
    (!expectedPurpose || value.purpose === expectedPurpose) &&
    /^[A-Za-z0-9_-]{32}$/.test(value.state || "") &&
    /^[A-Za-z0-9_-]{43,128}$/.test(value.verifier || "") &&
    validateConfirmationEmail(value.email) === "" && Number.isSafeInteger(value.createdAt) &&
    value.createdAt <= Date.now() + 60_000 && Date.now() - value.createdAt <= AUTH_TRANSACTION_MAX_AGE_MS
  );
}

function loadAuthTransaction(expectedPurpose = null) {
  try {
    const raw = localStorage.getItem(AUTH_TRANSACTION_KEY);
    if (!raw || new TextEncoder().encode(raw).byteLength > MAX_AUTH_TRANSACTION_STORAGE_BYTES) {
      localStorage.removeItem(AUTH_TRANSACTION_KEY);
      return null;
    }
    const parsed = JSON.parse(raw);
    if (!validAuthTransaction(parsed)) {
      localStorage.removeItem(AUTH_TRANSACTION_KEY);
      return null;
    }
    return validAuthTransaction(parsed, expectedPurpose) ? parsed : null;
  } catch {
    return null;
  }
}

function saveAuthTransaction(transaction) {
  if (!validAuthTransaction(transaction)) throw new Error("Authentication transaction is invalid.");
  const encoded = JSON.stringify(transaction);
  if (new TextEncoder().encode(encoded).byteLength > MAX_AUTH_TRANSACTION_STORAGE_BYTES) {
    throw new Error("Authentication transaction is too large.");
  }
  localStorage.setItem(AUTH_TRANSACTION_KEY, encoded);
  const stored = loadAuthTransaction(transaction.purpose);
  if (!stored || stored.state !== transaction.state || stored.verifier !== transaction.verifier) {
    throw userVisibleError(
      "Email authentication could not be saved in this browser.",
      "Не вдалося зберегти автентифікацію електронною поштою в цьому браузері."
    );
  }
}

function clearAuthTransaction(expectedState = null, expectedPurpose = null) {
  try {
    const current = loadAuthTransaction();
    if (expectedState && current?.state !== expectedState) return false;
    if (expectedPurpose && current?.purpose !== expectedPurpose) return false;
    localStorage.removeItem(AUTH_TRANSACTION_KEY);
    return localStorage.getItem(AUTH_TRANSACTION_KEY) === null;
  } catch {
    return false;
  }
}

function authRedirectUrl() {
  // Keep this byte-for-byte equal to the production Supabase redirect allowlist.
  // The PKCE verifier, purpose and state stay in same-origin local storage.
  return AUTH_REDIRECT_URL;
}

async function requestPasswordReset(rawEmail = document.querySelector("#forgot-email")?.value) {
  if (authRequestInProgress) return;
  if (!remoteAuthEnabled()) return showToast(tx("Supabase is not configured.", "Supabase не налаштовано."));
  const email = normalizeAuthEmail(rawEmail);
  const validationError = validateConfirmationEmail(email);
  if (validationError) return showToast(validationError);
  authRequestInProgress = true;
  authNotice = null;
  render();
  let transaction = null;
  try {
    const generated = await createAuthTransaction(email, "recovery");
    transaction = generated.transaction;
    saveAuthTransaction(transaction);
    const redirectTo = authRedirectUrl();
    await supabaseRequest(`/auth/v1/recover?redirect_to=${encodeURIComponent(redirectTo)}`, {
      method: "POST",
      anonymous: true,
      maxResponseBytes: MAX_REMOTE_AUTH_RESPONSE_BYTES,
      body: JSON.stringify({
        email,
        code_challenge: generated.challenge,
        code_challenge_method: "s256"
      })
    });
    authMode = "forgot";
    authDrafts.forgot.email = email;
    authNotice = {
      text: tx(
        "If an account exists for this email, a password reset link has been sent. Open the newest email in this browser.",
        "Якщо акаунт із цією адресою існує, посилання для скидання пароля надіслано. Відкрий найновіший лист у цьому браузері."
      ),
      isError: false
    };
  } catch (error) {
    // A network failure or 5xx can happen after Supabase accepted and emailed
    // the request. Retain the verifier so that link remains usable.
    if (transaction && deterministicAuthRequestFailure(error)) {
      clearAuthTransaction(transaction.state, "recovery");
    }
    authNotice = { text: friendlyAuthError(error), isError: true };
  } finally {
    authRequestInProgress = false;
    render();
  }
}

function friendlyAuthError(error) {
  const userMessages = error?.[USER_VISIBLE_ERROR_MESSAGES];
  if (userMessages && typeof userMessages.en === "string" && typeof userMessages.uk === "string") {
    return tx(userMessages.en, userMessages.uk);
  }
  const raw = typeof error?.message === "string"
    ? error.message.slice(0, MAX_REMOTE_ERROR_RESPONSE_BYTES)
    : "";
  let parsed = null;
  try {
    parsed = raw ? JSON.parse(raw) : null;
  } catch {
    parsed = null;
  }
  const messageCandidate = parsed?.msg ?? parsed?.message ?? parsed?.error_description ?? parsed?.error;
  const message = typeof messageCandidate === "string" ? messageCandidate : raw;
  const codeCandidate = parsed?.error_code ?? parsed?.code;
  const code = typeof codeCandidate === "string" ? codeCandidate : "";
  if (/rate limit|too many/i.test(message) ||
      ["over_email_send_rate_limit", "over_request_rate_limit", "rate_limit_exceeded"].includes(code)) {
    return tx(
      "Too many confirmation emails were requested. Supabase may block new emails for up to an hour on the built-in sender. Try again later, or contact support if the email never arrives.",
      "Запитано забагато листів для підтвердження. Вбудований відправник Supabase може призупинити нові листи на строк до години. Спробуй пізніше або звернися до підтримки, якщо лист так і не надійде."
    );
  }
  if (/already registered|already exists|user_already_exists|email_exists/i.test(`${code} ${message}`)) {
    return tx(
      "An account with this email already exists. Log in or resend the confirmation email.",
      "Акаунт із цією адресою електронної пошти вже існує. Увійди або надішли лист підтвердження ще раз."
    );
  }
  if (/email not confirmed/i.test(message) || code === "email_not_confirmed") {
    return tx("Confirm your email first, then log in.", "Спочатку підтвердь адресу електронної пошти, а потім увійди.");
  }
  if (/invalid login/i.test(message) || ["invalid_credentials", "invalid_grant"].includes(code)) {
    return tx("Email or password is incorrect.", "Неправильна адреса електронної пошти або пароль.");
  }
  if (/same password/i.test(message) || code === "same_password") {
    return tx("Choose a password different from the current password.", "Вибери пароль, який відрізняється від поточного.");
  }
  if (/weak password/i.test(message) || code === "weak_password") {
    return tx(
      "The new password does not meet the server password policy.",
      "Новий пароль не відповідає серверним вимогам."
    );
  }
  if (/expired|otp_expired/i.test(`${code} ${message}`)) {
    return tx("This authentication link or code has expired. Request a new one.", "Строк дії посилання або коду минув. Запроси новий.");
  }
  return tx(
    "Cloud request failed. Check your connection and try again.",
    "Не вдалося виконати хмарний запит. Перевір з’єднання та спробуй ще раз."
  );
}

function isEmailConfirmationError(error) {
  const raw = typeof error?.message === "string"
    ? error.message.slice(0, MAX_REMOTE_ERROR_RESPONSE_BYTES)
    : "";
  return /email not confirmed|email_not_confirmed/i.test(raw);
}

function beginRemoteActivation(session, {
  displayName = "",
  requirePasswordUpdate = false,
  activationPurpose = "login"
} = {}) {
  if (!validRemoteSession(session)) throw new Error("Cloud login returned an invalid session.");
  if (!["login", "signup", "recovery"].includes(activationPurpose)) {
    throw new Error("Cloud activation purpose is invalid.");
  }
  const account = remoteAccountFromSession(session);
  if (displayName) account.name = displayName;
  const storedSession = { ...session };
  delete storedSession.password_update_required;
  if (requirePasswordUpdate) storedSession.password_update_required = true;
  storedSession.activation_pending = activationPurpose;
  saveDurableRemoteSession(storedSession);
  try {
    localStorage.setItem(AUTH_KEY, JSON.stringify(account));
    const marker = normalizeStoredAccount(JSON.parse(localStorage.getItem(AUTH_KEY) || "null"));
    if (marker?.remote !== "supabase" || marker.userId !== account.userId) {
      throw new Error("Cloud activation marker could not be verified.");
    }
  } catch (error) {
    clearRemoteSession();
    throw error;
  }
  resetRemoteSyncContext();
  activeAccount = account;
  state = loadState(account);
  try {
    saveAccountList([...accountList().filter(item => item.id !== account.id), account]);
  } catch {
    // AUTH_KEY plus the tab-scoped session are the durable handoff. The list is
    // repaired after cloud reconciliation succeeds.
  }
  render();
  return { account, session: storedSession };
}

async function finishRemoteActivation(session = loadRemoteSession(), account = activeAccount) {
  if (!validRemoteSession(session) || !session.activation_pending ||
      account?.remote !== "supabase" || account.userId !== session.user.id) {
    throw new Error("Pending cloud activation is invalid.");
  }
  const cachedAccountState = loadState(account);
  const cachedStateExists = storedAccountStateExists(account);
  const cloudState = await loadRemoteState(session);
  await reconcileLoadedRemoteState(cloudState, cachedAccountState, cachedStateExists);
  const completedSession = { ...loadRemoteSession() };
  if (!validRemoteSession(completedSession) || completedSession.user.id !== account.userId) {
    throw new Error("Cloud activation session was lost.");
  }
  delete completedSession.activation_pending;
  saveDurableRemoteSession(completedSession);
  saveAccountList([...accountList().filter(item => item.id !== account.id), account]);
  clearAuthDrafts();
  nav = [{ name: "workouts" }];
  replaceNavigationHistory();
  modal = null;
  render();
  return { recovery: cloudStateRecovery, conflict: cloudSyncConflict };
}

async function activateRemoteSession(session, options = {}) {
  const handoff = beginRemoteActivation(session, options);
  return finishRemoteActivation(handoff.session, handoff.account);
}

async function remoteLogin(createAccount) {
  if (authRequestInProgress) return;
  if (!remoteAuthEnabled()) return showToast(tx("Supabase is not configured.", "Supabase не налаштовано."));
  const email = normalizeAuthEmail(createAccount
    ? document.querySelector("#signup-email")?.value
    : document.querySelector("#login-email")?.value);
  const emailConfirm = normalizeAuthEmail(document.querySelector("#signup-email-confirm")?.value);
  const password = createAccount
    ? document.querySelector("#signup-password")?.value
    : document.querySelector("#login-password")?.value;
  const passwordConfirm = document.querySelector("#signup-password-confirm")?.value;
  const displayName = sanitizeDisplayName(document.querySelector("#signup-name")?.value.trim() || "");
  const validationError = validateAuthInput(email, password, createAccount ? displayName : "", createAccount);
  if (validationError) return showToast(validationError);
  if (createAccount && email !== emailConfirm) {
    return showToast(tx("Email does not match.", "Адреси електронної пошти не збігаються."));
  }
  if (createAccount && password !== passwordConfirm) {
    return showToast(tx("Passwords do not match.", "Паролі не збігаються."));
  }
  authRequestInProgress = true;
  let transaction = null;
  let transactionReused = false;
  try {
    let signupPayload = null;
    if (createAccount) {
      const generated = await signupAuthTransaction(email);
      transaction = generated.transaction;
      transactionReused = generated.reused;
      saveAuthTransaction(transaction);
      signupPayload = {
        email,
        password,
        data: { display_name: displayName || email.split("@")[0] },
        code_challenge: generated.challenge,
        code_challenge_method: "s256"
      };
    }
    const path = createAccount
      ? `/auth/v1/signup?redirect_to=${encodeURIComponent(authRedirectUrl())}`
      : "/auth/v1/token?grant_type=password";
    const session = await supabaseRequest(path, {
      method: "POST",
      anonymous: true,
      maxResponseBytes: MAX_REMOTE_AUTH_RESPONSE_BYTES,
      body: JSON.stringify(createAccount ? signupPayload : { email, password })
    });
    if (!session?.access_token || !session?.user?.id) {
      authDrafts.signup.password = "";
      authDrafts.signup.passwordConfirm = "";
      pendingEmailConfirmation = { email, status: "", statusIsError: false };
      render();
      return;
    }
    if (transaction) clearAuthTransaction(transaction.state, "signup");
    const { recovery } = await activateRemoteSession(session, { displayName });
    showToast(recovery
      ? tx("Cloud login complete. Recovery action is required before sync.", "Хмарний вхід виконано. Перед синхронізацією потрібна дія відновлення.")
      : tx("Cloud login complete.", "Вхід у хмарний акаунт виконано."));
  } catch (error) {
    if (transaction && !transactionReused && deterministicAuthRequestFailure(error)) {
      clearAuthTransaction(transaction.state, "signup");
    }
    if (!createAccount && isEmailConfirmationError(error)) {
      authDrafts.login.password = "";
      pendingEmailConfirmation = { email, status: "", statusIsError: false };
      render();
    } else {
      showToast(friendlyAuthError(error));
    }
  } finally {
    authRequestInProgress = false;
    if (pendingEmailConfirmation && !activeAccount) render();
  }
}

function showAuthNotice(textValue, isError = true) {
  authNotice = { text: textValue, isError };
  if (activeAccount) showToast(textValue);
  else render();
}

function retryableRemoteActivationError(error) {
  return error?.name === "AbortError" || error instanceof TypeError ||
    error?.status === 408 || error?.status === 429 || error?.status >= 500;
}

function completePendingActivationMarker(session = loadRemoteSession()) {
  if (!validRemoteSession(session) || !session.activation_pending) return false;
  const completed = { ...session };
  delete completed.activation_pending;
  saveDurableRemoteSession(completed);
  return true;
}

async function retryPendingRemoteActivation() {
  if (authRequestInProgress) return;
  const session = loadRemoteSession();
  if (!session?.activation_pending || activeAccount?.userId !== session.user.id) return;
  authRequestInProgress = true;
  render();
  try {
    await finishRemoteActivation(session, activeAccount);
    showToast(tx("Cloud account is ready.", "Хмарний акаунт готовий."));
  } catch (error) {
    if (!transitionToReauthentication(error)) {
      if (!retryableRemoteActivationError(error)) completePendingActivationMarker();
      render();
      showToast(retryableRemoteActivationError(error)
        ? tx("Cloud data is temporarily unavailable. Reload or retry without requesting a new email.", "Хмарні дані тимчасово недоступні. Онови сторінку або повтори спробу без нового листа.")
        : friendlyAuthError(error));
    }
  } finally {
    authRequestInProgress = false;
    render();
  }
}

async function completeAuthCallback(query) {
  const platforms = query.getAll("platform");
  const purposes = query.getAll("purpose");
  const states = query.getAll("state");
  const codes = query.getAll("code");
  const errors = query.getAll("error");
  const descriptions = query.getAll("error_description");
  const allowedKeys = new Set(["platform", "purpose", "state", "code", "error", "error_description"]);
  const hasUnknownKey = [...query.keys()].some(key => !allowedKeys.has(key) || key.toLowerCase().includes("token"));
  const transaction = loadAuthTransaction();
  const callbackPurpose = purposes[0] || "";
  const stateValue = states[0] || "";
  const code = codes[0] || "";
  const callbackError = errors[0] || "";
  const callbackDescription = descriptions[0] || "";
  const callbackErrorIsSafe = isSafeAuthCallbackValue(callbackError, 128);
  const callbackDescriptionIsSafe = isSafeAuthCallbackValue(callbackDescription, 1024);
  const codePayloadIsValid = codes.length === 1 && errors.length === 0 &&
    descriptions.length === 0 && UUID_PATTERN.test(code);
  const errorPayloadIsValid = codes.length === 0 && errors.length === 1 &&
    callbackErrorIsSafe && (descriptions.length === 0 ||
      (descriptions.length === 1 && callbackDescriptionIsSafe));
  const transactionMatchesCallback = Boolean(transaction &&
    transaction.state === stateValue && transaction.purpose === callbackPurpose);
  const callbackIsValid = [
    platforms.length === 1 && platforms[0] === "web",
    purposes.length === 1 && ["signup", "recovery"].includes(callbackPurpose),
    states.length === 1 && /^[A-Za-z0-9_-]{32}$/.test(stateValue),
    codePayloadIsValid || errorPayloadIsValid,
    !hasUnknownKey,
    window.location.hash.length === 0,
    transactionMatchesCallback
  ].every(Boolean);
  const activationPurpose = transaction?.purpose === "recovery" ? "recovery" : "signup";
  const isRecovery = activationPurpose === "recovery";

  window.history.replaceState(null, "", window.location.pathname || "/");
  authMode = isRecovery ? "forgot" : "login";
  if (!callbackIsValid || callbackError) {
    if (isRecovery) {
      showAuthNotice(callbackError
        ? tx(
          "This password reset link expired or could not be verified. Request a new email.",
          "Строк дії посилання для скидання пароля минув або його не вдалося перевірити. Запроси новий лист."
        )
        : tx(
          "This password reset link is invalid for this browser. Request a new email here.",
          "Це посилання для скидання пароля не підходить для цього браузера. Запроси тут новий лист."
        ));
    } else {
      showAuthNotice(callbackError
        ? tx(
          "This confirmation link expired or could not be verified. Request a new email.",
          "Строк дії посилання для підтвердження минув або його не вдалося перевірити. Запроси новий лист."
        )
        : tx(
          "This confirmation link is invalid for this browser. Start account creation again.",
          "Це посилання для підтвердження не підходить для цього браузера. Почни створення акаунта ще раз."
        ));
    }
    return;
  }

  authRequestInProgress = true;
  let activationHandoff = null;
  let exchangeSucceeded = false;
  showAuthNotice(isRecovery
    ? tx("Verifying password reset…", "Перевіряємо скидання пароля…")
    : tx("Verifying email confirmation…", "Перевіряємо підтвердження електронної пошти…"), false);
  try {
    if (activeAccount) {
      saveState({ queueRemote: false });
      await flushPendingRemoteSave();
    }
    const session = await supabaseRequest("/auth/v1/token?grant_type=pkce", {
      method: "POST",
      anonymous: true,
      maxResponseBytes: MAX_REMOTE_AUTH_RESPONSE_BYTES,
      body: JSON.stringify({ auth_code: code, code_verifier: transaction.verifier })
    });
    if (!validRemoteSession(session) || normalizeAuthEmail(session.user.email) !== transaction.email) {
      const error = new Error("Email authentication returned an invalid account session.");
      error.malformedAuthSession = true;
      throw error;
    }
    exchangeSucceeded = true;
    activationHandoff = beginRemoteActivation(session, {
      requirePasswordUpdate: isRecovery,
      activationPurpose
    });
    clearAuthTransaction(transaction.state, activationPurpose);
    await finishRemoteActivation(activationHandoff.session, activationHandoff.account);
    showToast(isRecovery
      ? tx(
        "Password reset verified. Choose a new password to continue.",
        "Скидання пароля підтверджено. Вибери новий пароль, щоб продовжити."
      )
      : tx(
        "Email confirmed. Your cloud account is ready.",
        "Електронну пошту підтверджено. Твій хмарний акаунт готовий."
      ));
  } catch (error) {
    if (!activationHandoff && (!exchangeSucceeded &&
        (deterministicAuthRequestFailure(error) || error?.malformedAuthSession === true))) {
      clearAuthTransaction(transaction.state, activationPurpose);
    }
    if (!transitionToReauthentication(error)) {
      if (activationHandoff && retryableRemoteActivationError(error)) {
        render();
        showToast(tx(
          "Email verified, but cloud data is temporarily unavailable. Reload or retry without requesting a new email.",
          "Електронну пошту підтверджено, але хмарні дані тимчасово недоступні. Онови сторінку або повтори спробу без нового листа."
        ));
        return;
      }
      if (activationHandoff) completePendingActivationMarker();
      showAuthNotice(isRecovery
        ? tx(
          "Password reset could not be completed. Request a new reset email and try again.",
          "Не вдалося завершити скидання пароля. Запроси новий лист і спробуй ще раз."
        )
        : tx(
          "Email confirmation could not be completed. Request a new confirmation email and try again.",
          "Не вдалося завершити підтвердження електронної пошти. Запроси новий лист і спробуй ще раз."
        ));
    }
  } finally {
    authRequestInProgress = false;
    if (!activeAccount) render();
  }
}

function isSafeAuthCallbackValue(value, maxLength) {
  return typeof value === "string" && value.length > 0 && value.length <= maxLength &&
    !/[\u0000-\u001F\u007F]/.test(value);
}

function passwordReauthenticationRequired(error) {
  return /reauthentication[_ ]needed|reauthenticate|nonce/i.test(String(error?.message || ""));
}

async function updateRemotePassword({ required = false } = {}) {
  if (authRequestInProgress || accountTransitionInProgress) return;
  const currentPassword = required ? "" : (document.querySelector("#change-current-password")?.value || "");
  const password = document.querySelector(required ? "#recovery-new-password" : "#change-new-password")?.value || "";
  const confirmation = document.querySelector(required ? "#recovery-repeat-password" : "#change-repeat-password")?.value || "";
  const nonce = required ? "" : (document.querySelector("#change-password-nonce")?.value || "").trim();
  if (!required && !currentPassword) {
    return showToast(tx("Enter your current password.", "Введи поточний пароль."));
  }
  if (!required && new TextEncoder().encode(currentPassword).byteLength > 1024) {
    return showToast(tx("Current password is too long.", "Поточний пароль задовгий."));
  }
  if (!validNewPassword(password)) {
    return showToast(tx(
      "Password must contain at least 12 characters, fit within 72 UTF-8 bytes, and include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol.",
      "Пароль має містити щонайменше 12 символів, займати не більше 72 байтів у UTF-8 та включати малу й велику латинські літери, цифру й підтримуваний спецсимвол."
    ));
  }
  if (password !== confirmation) return showToast(tx("Passwords do not match.", "Паролі не збігаються."));
  if (!required && currentPassword === password) {
    return showToast(tx("Choose a password different from the current password.", "Вибери пароль, який відрізняється від поточного."));
  }
  if (!required && modal?.reauthRequired && !/^[0-9]{6,8}$/.test(nonce)) {
    return showToast(tx("Enter the verification code from your email.", "Введи код підтвердження з електронної пошти."));
  }
  const session = loadRemoteSession();
  const expectedUserId = activeAccount?.remote === "supabase" ? activeAccount.userId : null;
  if (!expectedUserId || session?.user?.id !== expectedUserId) {
    return showToast(tx("Sign in again before changing your password.", "Увійди знову перед зміною пароля."));
  }
  authRequestInProgress = true;
  render();
  try {
    const response = await supabaseRequest("/auth/v1/user", {
      method: "PUT",
      session,
      maxResponseBytes: MAX_REMOTE_AUTH_RESPONSE_BYTES,
      body: JSON.stringify({
        password,
        ...(!required ? { current_password: currentPassword } : {}),
        ...(nonce ? { nonce } : {})
      })
    });
    const responseUserId = response?.id || response?.user?.id;
    if (responseUserId !== expectedUserId) throw new Error("Password update returned an invalid account response.");
    if (required) {
      const currentSession = loadRemoteSession();
      if (!currentSession || currentSession.user.id !== expectedUserId) throw new Error("Cloud session is missing.");
      const nextSession = { ...currentSession };
      delete nextSession.password_update_required;
      saveRemoteSession(nextSession);
    } else {
      modal = null;
    }
    render();
    showToast(tx("Password changed.", "Пароль змінено."));
  } catch (error) {
    if (!required && !nonce && passwordReauthenticationRequired(error)) {
      try {
        await supabaseRequest("/auth/v1/reauthenticate", {
          method: "GET",
          session: loadRemoteSession() || session,
          maxResponseBytes: MAX_REMOTE_AUTH_RESPONSE_BYTES
        });
        modal = { type: "change-password", reauthRequired: true };
        render();
        showToast(tx("Verification code sent. Re-enter the new password with the code.", "Код підтвердження надіслано. Повторно введи новий пароль разом із кодом."));
      } catch (reauthError) {
        if (!transitionToReauthentication(reauthError)) showToast(friendlyAuthError(reauthError));
      }
    } else if (!transitionToReauthentication(error)) {
      showToast(friendlyAuthError(error));
    }
  } finally {
    authRequestInProgress = false;
    if (activeAccount) render();
  }
}

function exportCloudRecovery() {
  const recovery = cloudStateRecovery;
  if (!recovery || recovery.userId !== activeAccount?.userId) {
    return showToast(tx("No cloud recovery data is available.", "Дані для хмарного відновлення недоступні."));
  }
  try {
    downloadJson(JSON.stringify(recovery.rawState, null, 2), false);
  } catch {
    showToast(tx("Recovery JSON download failed.", "Не вдалося завантажити JSON для відновлення."));
  }
}

function exportSyncConflictLocal() {
  if (cloudSyncConflict?.userId !== activeAccount?.userId) return;
  downloadJson(exportPayload(false), false);
}

async function resolveSyncConflictWithLocal() {
  const conflict = cloudSyncConflict;
  if (!conflict || conflict.userId !== activeAccount?.userId ||
      loadRemoteSession()?.user?.id !== conflict.userId) return;
  const warning = tx(
    "Replace the conflicting cloud version with this browser version? Download a backup first. The revision check will stop if the cloud changes again.",
    "Замінити конфліктну хмарну версію версією з цього браузера? Спочатку завантаж резервну копію. Перевірка ревізії зупинить дію, якщо хмара знову зміниться."
  );
  if (typeof window.confirm !== "function" || !window.confirm(warning)) return;
  authRequestInProgress = true;
  render();
  try {
    saveSyncBaseline({
      version: 1,
      userId: conflict.userId,
      remoteExists: Boolean(conflict.cloudState.exists),
      revision: conflict.cloudState.exists ? conflict.cloudState.revision : null,
      syncedFingerprint: conflict.remoteFingerprint,
      localFingerprint: remoteStateFingerprint(state, conflict.userId),
      dirty: true,
      pending: null,
      updatedAt: Date.now()
    });
    const result = await saveRemoteState();
    cloudSyncConflict = null;
    render();
    showRemoteSaveResult(result);
    showToast(tx("Browser version saved to the cloud.", "Версію браузера збережено в хмарі."));
  } catch (error) {
    if (!transitionToReauthentication(error)) showToast(friendlyAuthError(error));
  } finally {
    authRequestInProgress = false;
    render();
  }
}

function resolveSyncConflictWithCloud() {
  const conflict = cloudSyncConflict;
  if (!conflict || conflict.userId !== activeAccount?.userId ||
      loadRemoteSession()?.user?.id !== conflict.userId) return;
  const warning = tx(
    "Discard this browser's conflicting changes and use the cloud version? Download a browser backup first. This cannot be undone in GymApp.",
    "Відкинути конфліктні зміни цього браузера й використати хмарну версію? Спочатку завантаж резервну копію браузера. У GymApp це неможливо скасувати."
  );
  if (typeof window.confirm !== "function" || !window.confirm(warning)) return;
  state = conflict.remoteState;
  saveState({ queueRemote: false, markDirty: false });
  const acceptedFingerprint = remoteStateFingerprint(state, conflict.userId);
  saveSyncBaseline({
    version: 1,
    userId: conflict.userId,
    remoteExists: Boolean(conflict.cloudState.exists),
    revision: conflict.cloudState.exists ? conflict.cloudState.revision : null,
    syncedFingerprint: conflict.remoteFingerprint,
    localFingerprint: acceptedFingerprint,
    dirty: false,
    pending: null,
    updatedAt: Date.now()
  });
  cloudSyncConflict = null;
  render();
  showToast(tx("Cloud version loaded.", "Хмарну версію завантажено."));
}

async function resetCloudRecovery() {
  if (cloudRecoveryInProgress) return;
  const recovery = cloudStateRecovery;
  const session = loadRemoteSession();
  if (!recovery || recovery.userId !== activeAccount?.userId || session?.user?.id !== recovery.userId ||
      remoteStateSync.userId !== recovery.userId || remoteStateSync.revision !== recovery.revision) {
    return showToast(tx("Cloud recovery session is stale. Sign out and log in again.", "Сесія хмарного відновлення застаріла. Вийди й увійди знову."));
  }
  const warning = tx(
    "Permanently replace the quarantined cloud row with an empty GymApp state? Download the original JSON first if you may need its private workout history. Cancel is the safe default.",
    "Незворотно замінити карантинний хмарний запис порожнім станом GymApp? Спочатку завантаж оригінальний JSON, якщо може знадобитися приватна історія тренувань. «Скасувати» — безпечний вибір за замовчування."
  );
  if (typeof window.confirm !== "function" || !window.confirm(warning)) return;

  const expectedEpoch = accountEpoch;
  const expectedUserId = recovery.userId;
  cloudRecoveryInProgress = true;
  cloudStateRecovery = null;
  state = defaultAppState();
  try {
    const result = await saveRemoteState({ expectedEpoch, expectedUserId });
    saveState({ queueRemote: false, markDirty: false });
    render();
    if (result?.profileUpdated === false && transitionToReauthentication(result.profileError)) return;
    showToast(result?.profileUpdated === false
      ? tx(
        "Cloud state was recovered, but the public profile summary could not be updated. Try again later.",
        "Хмарні дані відновлено, але публічний підсумок профілю не вдалося оновити. Спробуй пізніше."
      )
      : tx("Cloud state recovery completed.", "Відновлення хмарного стану завершено."));
  } catch (error) {
    const stateWasReplaced = remoteStateSync.userId === expectedUserId &&
      remoteStateSync.revision !== recovery.revision;
    const accountIsCurrent = expectedEpoch === accountEpoch && activeAccount?.userId === expectedUserId &&
      loadRemoteSession()?.user?.id === expectedUserId;
    if (stateWasReplaced && accountIsCurrent) {
      saveState({ queueRemote: false, markDirty: false });
      render();
      showToast(tx(
        "Cloud state was recovered, but protected progress could not be refreshed. Try again later.",
        "Хмарні дані відновлено, але захищений прогрес не вдалося оновити. Спробуй пізніше."
      ));
    } else if (accountIsCurrent) {
      state = defaultAppState();
      cloudStateRecovery = recovery;
      render();
      showToast(friendlyOperationError(
        error,
        "Cloud recovery failed.",
        "Не вдалося відновити хмарні дані."
      ));
    }
  } finally {
    cloudRecoveryInProgress = false;
  }
}

async function resendRemoteConfirmation() {
  if (authRequestInProgress) return;
  if (!remoteAuthEnabled()) return showToast(tx("Supabase is not configured.", "Supabase не налаштовано."));
  const email = normalizeAuthEmail(pendingEmailConfirmation?.email);
  const validationError = validateConfirmationEmail(email);
  if (validationError || !pendingEmailConfirmation) return showToast(validationError || tx("Start account creation again.", "Почніть створення акаунта ще раз."));
  authRequestInProgress = true;
  pendingEmailConfirmation = { ...pendingEmailConfirmation, status: "", statusIsError: false };
  render();
  let transaction = null;
  let transactionReused = false;
  try {
    const generated = await signupAuthTransaction(email);
    transaction = generated.transaction;
    transactionReused = generated.reused;
    saveAuthTransaction(transaction);
    await supabaseRequest(`/auth/v1/resend?redirect_to=${encodeURIComponent(authRedirectUrl())}`, {
      method: "POST",
      anonymous: true,
      body: JSON.stringify({
        type: "signup",
        email,
        code_challenge: generated.challenge,
        code_challenge_method: "s256"
      })
    });
    pendingEmailConfirmation = {
      email,
      status: tx("Confirmation email sent. Check your inbox and spam folder.", "Лист для підтвердження надіслано. Перевір вхідні та папку зі спамом."),
      statusIsError: false
    };
  } catch (error) {
    if (transaction && !transactionReused && deterministicAuthRequestFailure(error)) {
      clearAuthTransaction(transaction.state, "signup");
    }
    pendingEmailConfirmation = { email, status: friendlyAuthError(error), statusIsError: true };
  } finally {
    authRequestInProgress = false;
    render();
  }
}

function changePendingConfirmationAddress() {
  if (!pendingEmailConfirmation || authRequestInProgress) return;
  const email = pendingEmailConfirmation.email;
  pendingEmailConfirmation = null;
  authMode = "signup";
  authDrafts.signup = { email, emailConfirm: "", password: "", passwordConfirm: "", name: authDrafts.signup.name || "" };
  render();
  requestAnimationFrame(() => app.querySelector("#signup-email")?.focus());
}

function returnToLoginFromConfirmation() {
  if (!pendingEmailConfirmation || authRequestInProgress) return;
  const email = pendingEmailConfirmation.email;
  pendingEmailConfirmation = null;
  authMode = "login";
  authDrafts.login = { email, password: "" };
  render();
  requestAnimationFrame(() => app.querySelector("#login-email")?.focus());
}

function restoreStorageValue(key, value) {
  if (value === null) localStorage.removeItem(key);
  else localStorage.setItem(key, value);
}

function finishRemovedAccountTransition() {
  resetRemoteSyncContext();
  clearAuthDrafts();
  activeAccount = null;
  state = loadState();
  nav = [{ name: "workouts" }];
  modal = null;
  replaceNavigationHistory();
  render();
}

function purgeDeletedCloudAccountFromBrowser(account) {
  let complete = true;
  const attempt = operation => {
    try {
      if (operation() === false) complete = false;
    } catch {
      complete = false;
    }
  };
  attempt(() => {
    localStorage.removeItem(activeStorageKey(account));
    return localStorage.getItem(activeStorageKey(account)) === null;
  });
  attempt(() => {
    saveAccountList(accountList().filter(item => item.id !== account.id));
    return !accountList().some(item => item.id === account.id);
  });
  attempt(() => removeActiveAccountMarkerForDeletion(account));
  attempt(() => { removeGarminBinding(account.userId); return true; });
  attempt(() => { removeGarminEnqueueRequestsForUser(account.userId); return true; });
  pendingGarminRevocations.delete(account.userId);
  const pendingAuth = loadAuthTransaction();
  if (pendingAuth?.email === normalizeAuthEmail(account.email)) {
    attempt(() => clearAuthTransaction(pendingAuth.state, pendingAuth.purpose));
  }
  attempt(() => {
    const key = syncBaselineKey(account.userId);
    localStorage.removeItem(key);
    return localStorage.getItem(key) === null;
  });
  attempt(() => clearRemoteSession());
  finishRemovedAccountTransition();
  return complete;
}

async function deleteCloudAccount() {
  if (accountTransitionInProgress || authRequestInProgress) return;
  const account = normalizeStoredAccount(activeAccount);
  const session = loadRemoteSession();
  if (account?.remote !== "supabase" || session?.user?.id !== account.userId) {
    return showToast(tx("Sign in again before deleting this cloud account.", "Увійди знову перед видаленням цього хмарного акаунта."));
  }
  const warning = tx(
    "Permanently delete this cloud account, its workouts, profile and connected devices? This cannot be undone. Export a backup first if you need it.",
    "Назавжди видалити цей хмарний акаунт, тренування, профіль і підключені пристрої? Це неможливо скасувати. Спочатку експортуй резервну копію, якщо вона потрібна."
  );
  if (typeof window.confirm !== "function" || !window.confirm(warning)) return;
  const typed = typeof window.prompt === "function"
    ? window.prompt(tx("Type DELETE to permanently delete the cloud account.", "Введи DELETE, щоб назавжди видалити хмарний акаунт."), "")
    : null;
  if (typed !== "DELETE") return showToast(tx("Account deletion cancelled.", "Видалення акаунта скасовано."));

  accountTransitionInProgress = true;
  const hadPendingSave = remoteSaveTimer !== null;
  clearTimeout(remoteSaveTimer);
  remoteSaveTimer = null;
  try {
    if (remoteSaveInFlight) await remoteSaveInFlight.catch(() => {});
    const response = await supabaseRequest("/functions/v1/delete-account", {
      method: "POST",
      session: loadRemoteSession() || session,
      maxResponseBytes: MAX_REMOTE_AUTH_RESPONSE_BYTES,
      body: JSON.stringify({ confirmation: "DELETE" })
    });
    if (!response || typeof response !== "object" || Array.isArray(response) ||
        Object.keys(response).length !== 1 || response.deleted !== true) {
      throw new Error("Cloud account deletion was not confirmed.");
    }
    const cleanupComplete = purgeDeletedCloudAccountFromBrowser(account);
    showToast(cleanupComplete
      ? tx("Cloud account permanently deleted.", "Хмарний акаунт назавжди видалено.")
      : tx(
        "Cloud account was deleted, but some browser data could not be cleared. Clear site data before using this device again.",
        "Хмарний акаунт видалено, але деякі дані браузера не вдалося очистити. Очисть дані сайту перед повторним використанням цього пристрою."
      ));
  } catch (error) {
    if (hadPendingSave && activeAccount?.userId === account.userId) queueRemoteSave();
    if (!transitionToReauthentication(error)) {
      showToast(friendlyOperationError(
        error,
        "Cloud account deletion failed. Nothing was deleted from this browser.",
        "Не вдалося видалити хмарний акаунт. У цьому браузері нічого не видалено."
      ));
    }
  } finally {
    accountTransitionInProgress = false;
  }
}

function deleteLocalAccount() {
  if (accountTransitionInProgress || authRequestInProgress) return;
  const account = normalizeStoredAccount(activeAccount);
  if (!account || account.remote) return;
  const warning = tx(
    "Permanently delete this local account and every workout saved for it in this browser? This cannot be undone. Export a backup first if needed.",
    "Назавжди видалити цей локальний акаунт і всі його тренування в цьому браузері? Це неможливо скасувати. За потреби спочатку експортуй резервну копію."
  );
  if (typeof window.confirm !== "function" || !window.confirm(warning)) return;
  const typed = typeof window.prompt === "function"
    ? window.prompt(tx("Type DELETE to permanently delete the local account.", "Введи DELETE, щоб назавжди видалити локальний акаунт."), "")
    : null;
  if (typed !== "DELETE") return showToast(tx("Account deletion cancelled.", "Видалення акаунта скасовано."));

  const stateKey = activeStorageKey(account);
  let snapshots;
  try {
    snapshots = {
      state: localStorage.getItem(stateKey),
      accounts: localStorage.getItem(ACCOUNT_LIST_KEY),
      auth: localStorage.getItem(AUTH_KEY)
    };
    localStorage.removeItem(stateKey);
    saveAccountList(accountList().filter(item => item.id !== account.id));
    if (!removeActiveAccountMarkerForDeletion(account) || localStorage.getItem(stateKey) !== null ||
        accountList().some(item => item.id === account.id)) {
      throw new Error("Local account cleanup was not confirmed.");
    }
    clearRemoteSession();
    finishRemovedAccountTransition();
    showToast(tx("Local account permanently deleted from this browser.", "Локальний акаунт назавжди видалено з цього браузера."));
  } catch {
    if (snapshots) {
      try {
        restoreStorageValue(stateKey, snapshots.state);
        restoreStorageValue(ACCOUNT_LIST_KEY, snapshots.accounts);
        restoreStorageValue(AUTH_KEY, snapshots.auth);
      } catch {
        // Keep the account open and report the failed cleanup below.
      }
    }
    showToast(tx(
      "Local account deletion failed. The account remains open; restore browser storage access and try again.",
      "Не вдалося видалити локальний акаунт. Він залишається відкритим; віднови доступ до сховища браузера й спробуй ще раз."
    ));
  }
}

async function logoutAccount() {
  if (accountTransitionInProgress) return;
  if (garminSyncInProgress) {
    return showToast(tx("Wait for Garmin sync to finish before switching accounts.", "Дочекайся завершення синхронізації з Garmin перед зміною акаунта."));
  }
  accountTransitionInProgress = true;
  let signedOutWithPendingGarminRevocation = false;
  let remoteSessionRevocationFailed = false;
  const accountBeingLoggedOut = normalizeStoredAccount(activeAccount);
  try {
    const activationSession = loadRemoteSession();
    const activationPending = Boolean(
      activationSession?.activation_pending &&
      activationSession.user?.id === accountBeingLoggedOut?.userId
    );
    if (!activationPending) {
      // Every state mutation persists its dirty marker before writing account
      // data. Sign-out only seals the already-saved snapshot; it must not turn
      // an untouched/migration-era account into a new cloud write.
      saveState({ queueRemote: false, markDirty: false });
      try {
        await flushPendingRemoteSave();
      } catch (error) {
        if (transitionToReauthentication(error)) return;
        if (activeAccount?.remote) queueRemoteSave();
        throw userVisibleError(
          "Account switch was cancelled because the latest browser changes could not be synced. Try again when the connection is available.",
          "Перемикання акаунта скасовано, бо останні зміни з браузера не вдалося синхронізувати. Спробуй ще раз, коли з’єднання відновиться."
        );
      }
    }
    let session = loadRemoteSession();
    const remoteUserId = activeAccount?.remote ? activeAccount.userId : null;
    const pendingGarminDeviceId = remoteUserId ? pendingGarminRevocations.get(remoteUserId) : null;
    if (pendingGarminDeviceId) {
      try {
        if (!session?.user?.id || session.user.id !== remoteUserId) {
          throw new Error("The active cloud session cannot revoke this incomplete Garmin pairing.");
        }
        await revokeGarminDeviceById(session, pendingGarminDeviceId);
        pendingGarminRevocations.delete(remoteUserId);
      } catch {
        const warning = tx(
          "An incomplete Garmin pairing could not be revoked. Cancel to keep this cloud session and retry (recommended). Choose OK only to sign out locally; GymApp will retry cleanup after you sign back into this account.",
          "Не вдалося відкликати незавершене сполучення Garmin. Натисни «Скасувати», щоб зберегти хмарну сесію й повторити спробу (рекомендовано). Натисни OK лише для локального виходу; GymApp повторить очищення після входу в цей акаунт."
        );
        if (typeof window.confirm !== "function" || !window.confirm(warning)) {
          throw userVisibleError(
            "Sign-out was cancelled so Garmin revocation can be retried.",
            "Вихід скасовано, щоб можна було повторити відкликання Garmin."
          );
        }
        signedOutWithPendingGarminRevocation = true;
      }
    }
    if (session?.user?.id && session.user.id === remoteUserId) {
      try {
        session = loadRemoteSession() || session;
        let refreshedForLogout = false;
        if (remoteSessionNeedsRefresh(session) && session.refresh_token) {
          session = await refreshRemoteSession(session);
          refreshedForLogout = true;
        }
        const revokeSession = () => supabaseRequest("/auth/v1/logout?scope=local", {
            method: "POST",
            session,
            timeoutMs: 5000,
            maxResponseBytes: MAX_REMOTE_ERROR_RESPONSE_BYTES
          });
        try {
          await revokeSession();
        } catch (error) {
          if (error?.status !== 401 || refreshedForLogout || !session.refresh_token) throw error;
          session = await refreshRemoteSession(session);
          refreshedForLogout = true;
          await revokeSession();
        }
      } catch {
        // Local cleanup must still complete. The short-lived access JWT may
        // remain valid until expiry, and the erased refresh credential can no
        // longer be used to target this exact server session for a retry.
        remoteSessionRevocationFailed = true;
      }
    }
    const localMarkerCleared = accountBeingLoggedOut?.remote === "supabase"
      ? true
      : removeActiveAccountMarkerIfOwned(accountBeingLoggedOut);
    const remoteSessionCleared = clearRemoteSession();
    if (!localMarkerCleared || !remoteSessionCleared) {
      throw userVisibleError(
        "Sign-out was stopped because browser account data could not be erased. The account remains open in this tab. Restore storage access and retry.",
        "Вихід зупинено, оскільки не вдалося стерти дані акаунта у браузері. Акаунт залишається відкритим у цій вкладці. Віднови доступ до сховища й повтори спробу."
      );
    }
    resetRemoteSyncContext();
    clearAuthDrafts();
    activeAccount = null;
    state = loadState();
    nav = [{ name: "workouts" }];
    replaceNavigationHistory();
    modal = null;
    render();
    if (signedOutWithPendingGarminRevocation) {
      showToast(tx(
        "Signed out locally. An incomplete Garmin pairing still needs cleanup; sign back into the same account to retry.",
        "Локальний вихід виконано. Незавершене сполучення Garmin ще потребує очищення; увійди знову в цей акаунт, щоб повторити."
      ));
    } else if (remoteSessionRevocationFailed) {
      showToast(tx(
        "Signed out locally, but server revocation was not confirmed. That old session may remain valid until server expiry or administrative revocation.",
        "Локальний вихід виконано, але серверне відкликання не підтверджено. Стара сесія може діяти до серверного завершення строку або адміністративного відкликання."
      ));
    }
  } catch (error) {
    showToast(friendlyOperationError(
      error,
      "Account switch was cancelled.",
      "Перемикання акаунта скасовано."
    ));
  } finally {
    accountTransitionInProgress = false;
  }
}

async function unpairGarmin() {
  if (accountTransitionInProgress) return;
  if (garminSyncInProgress) {
    return showToast(tx("Wait for Garmin sync to finish before unpairing.", "Дочекайся завершення синхронізації з Garmin перед від’єднанням."));
  }
  const session = loadRemoteSession();
  const userId = activeAccount?.remote ? activeAccount.userId : null;
  const binding = userId ? garminBindingForUser(userId) : null;
  if (!userId || session?.user?.id !== userId || !binding) {
    return showToast(tx("No active Garmin pairing is available.", "Активне сполучення Garmin відсутнє."));
  }
  const warning = tx(
    "Permanently revoke this Garmin pairing? Cloud sync on the current watch will stop. Before pairing it again, reset or reinstall GymApp on the watch so it forgets the old device identity. Cancel keeps the working pairing.",
    "Назавжди відкликати це сполучення Garmin? Хмарна синхронізація на поточному годиннику припиниться. Перед повторним сполученням скинь або перевстанови GymApp на годиннику, щоб він забув старий ідентифікатор пристрою. «Скасувати» збереже робоче сполучення."
  );
  if (typeof window.confirm !== "function" || !window.confirm(warning)) return;

  accountTransitionInProgress = true;
  try {
    const pendingDeviceId = pendingGarminRevocations.get(userId);
    if (pendingDeviceId && pendingDeviceId !== binding.deviceId) {
      await revokeGarminDeviceById(session, pendingDeviceId);
      pendingGarminRevocations.delete(userId);
    }
    await revokeGarminBinding(session);
    pendingGarminRevocations.delete(userId);
    render();
    showToast(tx(
      "Garmin pairing revoked. Reset the watch app before creating a new pairing.",
      "Сполучення Garmin відкликано. Скинь застосунок на годиннику перед створенням нового сполучення."
    ));
  } catch (error) {
    showToast(friendlyOperationError(
      error,
      "Garmin unpair failed.",
      "Не вдалося від’єднати Garmin."
    ));
  } finally {
    accountTransitionInProgress = false;
  }
}

function garminStoreAppLink() {
  const userAgent = String(navigator.userAgent || "");
  return userAgent.toLowerCase().includes("android") ? GARMIN_STORE_ANDROID_INTENT_URL : GARMIN_STORE_APP_URL;
}

function accountPanel() {
  const label = activeAccount?.name || tx("Local", "Локальний");
  const hasGarminBinding = Boolean(activeAccount?.remote && garminBindingForUser(activeAccount.userId));
  return `<section class="panel highlighted account-card"><div class="row-head"><div><span class="eyebrow">${tx("Account", "Акаунт")}</span><h2>${escapeHtml(label)}</h2><p>${activeAccount?.remote ? tx("Cloud account with protected synchronization.", "Хмарний акаунт із захищеною синхронізацією.") : tx("Local account on this device.", "Локальний акаунт на цьому пристрої.")}</p></div><span class="pill">${activeAccount?.remote ? tx("Cloud", "Хмара") : tx("Local", "Локально")}</span></div><div class="actions account-actions"><a class="button ghost" href="${escapeAttr(garminStoreAppLink())}" target="_blank" rel="noopener noreferrer">${tx("Open Garmin Connect IQ", "Відкрити Garmin Connect IQ")}</a>${activeAccount?.remote ? `<button class="button ghost" data-action="change-password">${tx("Change password", "Змінити пароль")}</button>` : ""}${hasGarminBinding ? `<button class="button danger" data-action="unpair-garmin">${tx("Unpair Garmin", "Від’єднати Garmin")}</button>` : ""}<button class="button ghost" data-action="logout-account">${tx("Switch", "Змінити акаунт")}</button><button class="button danger" data-action="delete-account">${activeAccount?.remote ? tx("Delete cloud account", "Видалити хмарний акаунт") : tx("Delete local account", "Видалити локальний акаунт")}</button></div></section>`;
}

function profileDataPanel() {
  return `<section class="panel profile-data-card"><div class="section-title"><div><span class="eyebrow">${tx("Your data", "Твої дані")}</span><h2>${t("backup")}</h2></div></div><p class="muted">${tx("A full import replaces this profile. Manual backups include favorite exercises; cloud schema-v2 intentionally keeps favorites local to this account and device.", "Повний імпорт замінює цей профіль. Ручна резервна копія містить улюблені вправи; хмарна schema-v2 навмисно зберігає їх локально для цього акаунта й пристрою.")}</p><div class="actions"><button class="button ghost" data-action="export-json">${t("exportJson")}</button><button class="button ghost" data-action="import-json">${t("importJson")}</button><button class="button ghost full" data-action="export-diagnostics">${t("diagnostics")}</button></div></section>
    <section class="panel profile-links-card"><div><span class="eyebrow">${tx("Help and trust", "Допомога й довіра")}</span><h2>${tx("Support and privacy", "Підтримка та приватність")}</h2><p class="muted">${tx("Find setup help or review how GymApp handles your data.", "Знайди допомогу з налаштуванням або переглянь, як GymApp обробляє твої дані.")}</p></div><div class="profile-links"><a class="button ghost" href="${escapeAttr(SUPPORT_URL)}" target="_blank" rel="noopener noreferrer">${tx("Support", "Підтримка")}</a><a class="button ghost" href="${escapeAttr(PRIVACY_URL)}" target="_blank" rel="noopener noreferrer">${tx("Privacy policy", "Політика конфіденційності")}</a></div></section>`;
}

function localLeaderboardRow() {
  return {
    display_name: activeAccount?.name || tx("Local", "Локальний"),
    xp: totalXp(),
    level: levelFromXp(),
    workouts: state.sessions.length,
    isCurrent: true
  };
}

function leaderboardSourceKey() {
  const session = loadRemoteSession();
  const cloudMode = Boolean(remoteAuthEnabled() && activeAccount?.remote && session?.user?.id);
  const identity = cloudMode ? session.user.id : activeAccount?.id || "anonymous";
  return `${cloudMode ? "cloud" : "local"}:${identity}:${accountEpoch}`;
}

async function refreshLeaderboard(force = false) {
  const session = loadRemoteSession();
  const cloudMode = Boolean(remoteAuthEnabled() && activeAccount?.remote && session?.user?.id);
  const source = leaderboardSourceKey();
  if (leaderboardState.status === "loading" && !force && leaderboardState.source === source) return;
  if (leaderboardState.status === "loading") {
    leaderboardRequestController?.abort();
  }
  if (!force && leaderboardState.status === "loaded" && leaderboardState.source === source) return;
  if (!cloudMode) {
    leaderboardRequestId += 1;
    leaderboardRequestController?.abort();
    leaderboardRequestController = null;
    leaderboardState = { status: "loaded", source, rows: [localLeaderboardRow()], error: "" };
    return render();
  }
  const requestId = ++leaderboardRequestId;
  const requestEpoch = accountEpoch;
  const expectedUserId = session.user.id;
  leaderboardRequestController = new AbortController();
  leaderboardState = { ...leaderboardState, status: "loading", source, error: "" };
  render();
  try {
    saveRemoteState().catch(() => {});
    const rows = await supabaseRequest(
      "/rest/v1/leaderboard_public?select=profile_id,display_name,xp,level,workouts,is_current_user&order=xp.desc,workouts.desc,profile_id.asc&limit=50",
      { session, signal: leaderboardRequestController.signal, timeoutMs: 10000 }
    );
    if (requestId !== leaderboardRequestId || requestEpoch !== accountEpoch ||
        source !== leaderboardSourceKey() || activeAccount?.userId !== expectedUserId ||
        loadRemoteSession()?.user?.id !== expectedUserId) return;
    leaderboardState = {
      status: "loaded",
      source,
      rows: (Array.isArray(rows) ? rows : [])
        .filter(row => Boolean(row?.is_current_user))
        .map(row => ({ ...row, isCurrent: true })),
      error: ""
    };
  } catch (error) {
    if (requestId !== leaderboardRequestId || requestEpoch !== accountEpoch ||
        source !== leaderboardSourceKey() || activeAccount?.userId !== expectedUserId ||
        loadRemoteSession()?.user?.id !== expectedUserId) return;
    leaderboardState = {
      status: "error",
      source,
      rows: [localLeaderboardRow()],
      error: tx("Could not load protected cloud progress. Try refresh again.", "Не вдалося завантажити захищений хмарний прогрес. Спробуй оновити ще раз.")
    };
  } finally {
    if (requestId === leaderboardRequestId) leaderboardRequestController = null;
  }
  render();
}

function leaderboardScreen() {
  const rows = leaderboardState.rows.length ? leaderboardState.rows : [localLeaderboardRow()];
  const loading = leaderboardState.status === "loading";
  const cloudMode = Boolean(remoteAuthEnabled() && activeAccount?.remote && loadRemoteSession()?.user?.id);
  const supporting = loading
    ? tx("Loading protected cloud progress.", "Завантажуємо захищений хмарний прогрес.")
    : leaderboardState.status === "error"
      ? tx("Showing local stats while protected cloud progress is unavailable.", "Показуємо локальні дані, поки захищений хмарний прогрес недоступний.")
      : cloudMode
      ? tx("Refresh updates only your own cloud XP. It does not start a rating check.", "Оновлення завантажує лише твої власні XP із хмари. Воно не запускає перевірку рейтингу.")
      : remoteAuthEnabled()
        ? tx("Local mode. Sign in to protect and synchronize your progress.", "Локальний режим. Увійди, щоб захистити й синхронізувати прогрес.")
        : tx("Protected cloud progress is available after Supabase is configured.", "Захищений хмарний прогрес стане доступним після налаштування Supabase.");
  return `<section class="screen-copy profile-screen-copy"><span class="eyebrow">${tx("Profile", "Профіль")}</span><h2>${tx("Account, data and progress", "Акаунт, дані та прогрес")}</h2><p>${tx("Manage your account, connected services and protected progress in one place.", "Керуй акаунтом, підключеними сервісами та захищеним прогресом в одному місці.")}</p></section>
    ${themePreferencePanel()}
    ${accountPanel()}
    ${profileDataPanel()}
    <section class="hero-panel profile-rating-hero"><div class="hero-split"><div><span class="eyebrow">${tx("Rating status", "Статус рейтингу")}</span><h2>${tx("Rating not available yet", "Рейтинг поки недоступний")}</h2><p>${tx("Workouts are currently scored on your device, so public ranking is disabled, not queued for review. It will appear only after a future app and server update adds verified scoring; no release date is set. Your private progress remains available.", "Зараз тренування оцінюються на пристрої, тому публічний рейтинг вимкнено, а не поставлено в чергу на перевірку. Він з’явиться лише після майбутнього оновлення застосунку й сервера з перевіреним підрахунком; дати випуску поки немає. Твій приватний прогрес залишається доступним.")}</p></div><div class="hero-stat"><span>${tx("Your XP", "Твої XP")}</span><strong>${totalXp()}</strong><small>${escapeHtml(rankTitle())}</small></div></div></section>
    <section class="panel highlighted"><div class="row-head"><div><h2>${tx("Your synced progress", "Твій синхронізований прогрес")}</h2><p>${supporting}</p></div><button class="button" data-action="refresh-leaderboard" ${loading ? "disabled" : ""}>${loading ? tx("Loading", "Завантаження") : tx("Refresh progress", "Оновити прогрес")}</button></div>${leaderboardState.error ? `<p class="muted">${escapeHtml(leaderboardState.error)}</p>` : ""}${!rows.length && !loading ? `<div class="empty">${tx("No synced progress yet.", "Синхронізованого прогресу ще немає.")}</div>` : ""}</section>
    <section class="leaderboard-list">${rows.map(leaderboardRow).join("")}</section>`;
}

function leaderboardRow(row, index) {
  const name = row.display_name || tx("Anonymous", "Без імені");
  const xp = Number(row.xp || 0);
  const level = Number(row.level || 1);
  const workouts = Number(row.workouts || 0);
  return `<article class="leaderboard-row ${row.isCurrent ? "highlighted" : ""}"><div class="rank-place">${row.isCurrent ? svg("person", "small-icon") : index + 1}</div><div><h3>${escapeHtml(name)}</h3><p>${tx("Level", "Рівень")} ${level} - ${n(workouts, "workout", "workouts", "тренування", "тренування", "тренувань")}</p></div><strong>${xp} XP</strong></article>`;
}

function exercisesScreen() {
  const mappingRows = filteredLibraryExercises();
  const regionFilters = [["all", tx("All", "Усі")], ["upper", tx("Upper body", "Верх тіла")], ["lower", tx("Lower body", "Низ тіла")], ["core", tx("Core", "Кор")]];
  const sortFilters = [["name", tx("By name", "За назвою")], ["most", tx("Most frequent", "Найчастіші")], ["least", tx("Least frequent", "Найрідші")]];
  return `<section class="screen-copy"><h2>${t("exercises")}</h2><p>${tx("Manage your exercise library, history, and muscle groups.", "Керуй каталогом вправ, історією та групами м’язів.")}</p></section>
    <button class="button full exercise-add-button" data-action="open-exercise-add">${svg("add", "small-icon")}${t("addExercise")}</button>
    <section class="panel exercise-library-heading"><span class="eyebrow">${tx("Your training", "Твої тренування")}</span><h2>${tx("Exercise library", "Каталог вправ")}</h2><p class="muted">${tx("Add a custom movement or open a saved exercise to view its history.", "Додай власну вправу або відкрий збережену, щоб переглянути історію.")}</p></section>
    <section class="panel highlighted exercise-search-panel"><label for="exercise-search">${tx("Search exercises", "Пошук вправ")}</label><div class="field-row"><input id="exercise-search" type="search" maxlength="120" value="${escapeAttr(exerciseSearchQuery)}" placeholder="${txAttr("Name in English, Ukrainian, or Russian", "Назва англійською, українською або російською")}">${exerciseSearchQuery ? `<button class="icon-button" data-action="clear-exercise-search" aria-label="${txAttr("Clear search", "Очистити пошук")}">${svg("close")}</button>` : ""}</div>
      <div class="filter-scroll"><button class="chip buttonlike favorite-filter ${exerciseFavoritesOnly ? "selected" : ""}" data-action="exercise-favorites-filter" aria-pressed="${exerciseFavoritesOnly}">${svg(exerciseFavoritesOnly ? "heartFilled" : "heart", "small-icon")}${tx("Favorites", "Улюблені")}</button>${regionFilters.map(([id, label]) => `<button class="chip buttonlike ${exerciseBodyFilter === id ? "selected" : ""}" data-action="exercise-body-filter" data-filter="${id}" aria-pressed="${exerciseBodyFilter === id}">${label}</button>`).join("")}</div>
      <div class="filter-scroll">${sortFilters.map(([id, label]) => `<button class="chip buttonlike ${exerciseSortMode === id ? "selected" : ""}" data-action="exercise-sort" data-sort="${id}" aria-pressed="${exerciseSortMode === id}">${label}</button>`).join("")}</div>
      <div class="filter-scroll"><button class="chip buttonlike ${exerciseMuscleFilter === "all" ? "selected" : ""}" data-action="exercise-muscle-filter" data-filter="all">${tx("All muscles", "Усі м’язи")}</button>${muscles.map(([id]) => `<button class="chip buttonlike ${exerciseMuscleFilter === id ? "selected" : ""}" data-action="exercise-muscle-filter" data-filter="${id}">${escapeHtml(muscleLabel(id))}</button>`).join("")}</div><p class="muted">${mappingRows.length} ${tx("exercises", "вправ")}</p></section>
    <section class="exercise-list">${mappingRows.length ? mappingRows.map(exerciseRow).join("") : `<div class="empty">${tx("No matching exercises.", "Вправ за цими фільтрами не знайдено.")}</div>`}</section>`;
}

const exerciseBodyMuscles = {
  upper: new Set(["chest", "shoulders", "biceps", "triceps", "forearms", "lats", "upperBack"]),
  lower: new Set(["lowerBack", "glutes", "quads", "hamstrings", "adductors", "calves"]),
  core: new Set(["abs", "obliques"])
};

function filteredLibraryExercises() {
  const bodyMuscles = exerciseBodyMuscles[exerciseBodyFilter];
  const matching = state.exercises.filter(exercise => {
    const ids = new Set(mappingFor(exercise).map(item => typeof item === "string" ? item : item.muscleId));
    const matchesBody = !bodyMuscles || [...ids].some(id => bodyMuscles.has(id));
    const matchesMuscle = exerciseMuscleFilter === "all" || ids.has(exerciseMuscleFilter);
    const matchesFavorite = !exerciseFavoritesOnly || exercise.favorite === true;
    return exerciseMatchesSearch(exercise, exerciseSearchQuery) && matchesBody && matchesMuscle && matchesFavorite;
  });
  return matching.sort((left, right) => {
    const nameOrder = exerciseDisplayName(left).localeCompare(exerciseDisplayName(right), state.language);
    if (exerciseSortMode === "name") return nameOrder || Number(left.id) - Number(right.id);
    const difference = exerciseWorkoutCount(left) - exerciseWorkoutCount(right);
    if (difference) return exerciseSortMode === "most" ? -difference : difference;
    return nameOrder || Number(left.id) - Number(right.id);
  });
}

function exerciseWorkoutCount(exercise) {
  return state.sessions.reduce((count, session) => count + Number(
    exerciseReferencesForSession(session).some(reference => exercisesMatch(reference, exercise))
  ), 0);
}

function toggleExerciseFavorite(id) {
  if (!Number.isSafeInteger(id) || id <= 0) return;
  const exercise = state.exercises.find(item => Number(item.id) === id);
  if (!exercise) return;
  if (exercise.favorite === true) delete exercise.favorite;
  else exercise.favorite = true;
  saveState({ queueRemote: false });
  render();
}

function exerciseMappingsPanel(exercises) {
  return `<section class="material-card mappings-card"><h2>${tx("Exercise mapping", "Мапінг вправ")}</h2>${exercises.map(exercise => {
    const labels = mappingFor(exercise.name).map(muscleLabel).join(", ") || tx("Not mapped", "Не зіставлено");
    return `<div class="row-line mapping-row"><span>${escapeHtml(exerciseDisplayName(exercise))}<small>${escapeHtml(labels)}</small></span><button class="button secondary mini" data-action="map-exercise" data-name="${escapeAttr(exercise.name)}">${tx("Map", "Мапити")}</button></div>`;
  }).join("")}</section>`;
}

function exerciseRow(exercise) {
  const builtIn = Boolean(builtInExerciseFor(exercise));
  const favorite = exercise.favorite === true;
  const workoutCount = exerciseWorkoutCount(exercise);
  const mappingCount = mappingFor(exercise).length;
  return `<article class="panel exercise-row"><div class="exercise-card-head"><h3 class="exercise-name">${escapeHtml(exerciseDisplayName(exercise))}</h3><div class="actions"><button class="icon-button favorite-toggle ${favorite ? "selected" : ""}" data-action="toggle-exercise-favorite" data-id="${escapeAttr(String(exercise.id))}" aria-pressed="${favorite}" aria-label="${favorite ? txAttr("Remove from favorites", "Прибрати з улюблених") : txAttr("Add to favorites", "Додати до улюблених")}">${svg(favorite ? "heartFilled" : "heart")}</button>${builtIn ? `<span class="pill">${tx("Built-in", "Вбудована")}</span>` : `<button class="icon-button" data-action="rename-exercise" data-id="${exercise.id}" aria-label="${txAttr("Rename exercise", "Перейменувати вправу")}">${svg("edit")}</button>`}<button class="icon-button" data-action="delete-exercise" data-id="${exercise.id}" aria-label="${txAttr("Delete exercise", "Видалити вправу")}">${svg("delete")}</button></div></div><div class="exercise-metrics"><span class="pill">${n(workoutCount, "workout", "workouts", "тренування", "тренування", "тренувань")}</span><span class="pill">${mappingCount ? tx(`${mappingCount} mapped`, `Зіставлено: ${mappingCount}`) : tx("Auto mapping", "Автоматичне зіставлення")}</span></div><div class="exercise-card-actions"><button class="button ghost" data-action="exercise-history" data-id="${exercise.id}">${tx("History", "Історія")}</button><button class="button ghost" data-action="map-exercise" data-name="${escapeAttr(exercise.name)}">${tx("Muscle groups", "Групи м’язів")}</button></div></article>`;
}

function progressScreen() {
  const selectedId = Number(state.progressExerciseId || state.exercises[0]?.id || 0);
  const selected = state.exercises.find(ex => Number(ex.id) === selectedId);
  if (!selected) return `${monthSwitcher()}<div class="progress-selector"><label>${tx("Exercise", "Вправа")}</label><button class="button ghost full" type="button">${tx("Select exercise", "Обери вправу")}</button></div>
    <section class="material-card progress-summary"><h2>${tx("Progress Summary", "Підсумок прогресу")}</h2><p class="muted">${tx("Volume = weight x reps across all completed sets.", "Обсяг = вага x повтори по всіх завершених підходах.")}</p><div class="metric-grid three"><div><span>${tx("Sessions", "Сесії")}</span><strong>0</strong></div><div><span>${tx("Total Sets", "Усього підходів")}</span><strong>0</strong></div><div><span>${tx("Total Reps", "Усього повторів")}</span><strong>0</strong></div><div><span>${tx("Best Weight", "Найкраща вага")}</span><strong>${tx("No data", "Немає даних")}</strong></div><div><span>${tx("Average Max", "Середній максимум")}</span><strong>${tx("No data", "Немає даних")}</strong></div><div><span>${tx("Total Volume", "Загальний обсяг")}</span><strong>0</strong></div></div></section>
    <section class="hero-panel progress-spotlight"><h2>${tx("No exercise data yet", "За цією вправою поки немає даних")}</h2><p>${tx("Pick an exercise to see solo progress.", "Обери вправу, щоб побачити свій прогрес.")}</p></section>
    <section class="panel highlighted trend-panel"><h2>${tx("Visual Trends", "Візуальні тренди")}</h2><p class="muted">${tx("Maximum weight and session volume over time.", "Максимальна вага та обсяг тренування в динаміці.")}</p><div class="empty">${tx("Add sets to see chart.", "Додай підходи, щоб побачити графік.")}</div></section>
    <section class="material-card"><div class="empty">${tx("No exercises yet.", "Вправ ще немає.")}</div></section>`;
  const history = allSets(selectedMonthSessions()).filter(set => exercisesMatch(set, selected)).sort((a, b) => b.session.startedAt - a.session.startedAt);
  const grouped = progressHistoryGroups(history);
  const best = Math.max(0, ...history.map(s => safeChartValue(s.weight)));
  const allTimeBest = Math.max(0, ...allSets().filter(set => exercisesMatch(set, selected)).map(set => safeChartValue(set.weight)));
  const avg = grouped.length ? grouped.reduce((sum, g) => sum + Math.max(0, ...g.sets.map(s => safeChartValue(s.weight))), 0) / grouped.length : 0;
  const vol = history.reduce((sum, s) => sum + safeChartValue(s.weight) * safeChartValue(s.reps), 0);
  const reps = history.reduce((sum, x) => sum + safeChartValue(x.reps), 0);
  const hasMuscleMapping = contributionFor(selected).some(item => muscles.some(([id]) => id === item.muscleId));
  return `${monthSwitcher()}<div class="progress-selector"><label for="progress-select">${tx("Exercise", "Вправа")}</label><select id="progress-select" data-action="progress-select">${state.exercises.map(ex => `<option value="${ex.id}" ${Number(ex.id) === selectedId ? "selected" : ""}>${escapeHtml(exerciseDisplayName(ex))}</option>`).join("")}</select></div>
    ${hasMuscleMapping ? exerciseMuscleMapCard(selected, true) : ""}
    <section class="material-card progress-summary"><h2>${tx("Progress Summary", "Підсумок прогресу")}</h2><p class="muted">${tx("Volume = weight x reps across all completed sets.", "Обсяг = вага x повтори по всіх завершених підходах.")}</p><div class="metric-grid three"><div><span>${tx("Sessions", "Сесії")}</span><strong>${grouped.length}</strong></div><div><span>${tx("Total Sets", "Усього підходів")}</span><strong>${history.length}</strong></div><div><span>${tx("Total Reps", "Усього повторів")}</span><strong>${reps}</strong></div><div><span>${tx("Best Weight", "Найкраща вага")}</span><strong>${history.length ? `${best.toFixed(1)} kg` : tx("No data", "Немає даних")}</strong></div><div><span>${tx("Average Max", "Середній максимум")}</span><strong>${history.length ? `${avg.toFixed(1)} kg` : tx("No data", "Немає даних")}</strong></div><div><span>${tx("Total Volume", "Загальний обсяг")}</span><strong>${Math.round(vol)}</strong></div></div></section>
    <section class="hero-panel progress-spotlight">${spotlight(selected, grouped, allTimeBest)}</section>
    ${exerciseTrendCharts(grouped, best)}
    <section class="workout-list"><h2>${tx("Workout History", "Історія тренувань")}</h2>${grouped.length ? grouped.map(g => progressHistoryCard(g)).join("") : `<div class="empty">${tx("No history in this month.", "Немає історії за цей місяць.")}</div>`}</section>`;
}

function progressHistoryGroups(history) {
  const groups = Object.values(history.reduce((acc, set, index) => {
    acc[set.session.id] ||= { session: set.session, sets: [] };
    acc[set.session.id].sets.push({ ...set, orderIndex: set.orderIndex ?? index });
    return acc;
  }, {}));
  return groups.sort((a, b) => b.session.startedAt - a.session.startedAt).map(group => ({
    ...group,
    sets: group.sets.sort((a, b) => Number(a.orderIndex || 0) - Number(b.orderIndex || 0))
  }));
}

function groupedExerciseHistory(groups) {
  let lastMonth = "";
  let lastDay = "";
  return groups.map(group => {
    const month = fmtDate(group.session.startedAt, { month: "long", year: "numeric" });
    const day = fmtDate(group.session.startedAt, { weekday: "long", day: "numeric", month: "long" });
    const headers = `${month !== lastMonth ? `<h3>${escapeHtml(month)}</h3>` : ""}${day !== lastDay ? `<p class="muted">${escapeHtml(day)}</p>` : ""}`;
    lastMonth = month;
    lastDay = day;
    return `${headers}${progressHistoryCard(group)}`;
  }).join("");
}
function spotlight(exercise, grouped, allTimeBest) {
  const displayName = exerciseDisplayName(exercise);
  const points = progressChartPoints(grouped);
  if (!points.length) {
    return `<h2>${escapeHtml(displayName)}</h2><p>${escapeHtml(tx(`Log sets for ${displayName} to unlock trends.`, `Додай підходи для ${displayName}, щоб відкрити тренди.`))}</p>`;
  }
  const latest = points.at(-1) || { maxWeight: 0, volume: 0 };
  const previous = points.at(-2);
  const weightDelta = progressDeltaLabel(latest.maxWeight, previous?.maxWeight, tx("kg", "кг"));
  const volumeDelta = progressDeltaLabel(latest.volume, previous?.volume, tx("volume", "обсягу"));
  return `<h2>${escapeHtml(displayName)}</h2><p>${tx("Your latest result and the direction of recent sessions.", "Останній результат і динаміка недавніх тренувань.")}</p>
    <div class="metric-grid"><div><span>${tx("Latest max", "Останній максимум")}</span><strong>${formatSetWeight(latest.maxWeight)} kg</strong></div><div><span>${tx("Latest volume", "Останній обсяг")}</span><strong>${Math.round(latest.volume)}</strong></div></div>
    <div class="spotlight-deltas"><span class="hero-info-pill">${escapeHtml(weightDelta)}</span>${volumeDelta !== weightDelta ? `<span class="hero-info-pill">${escapeHtml(volumeDelta)}</span>` : ""}</div>
    <div class="metric-grid"><div><span>${tx("All-time best", "Найкраще за весь час")}</span><strong>PR ${formatSetWeight(allTimeBest)} kg</strong></div><div><span>${tx("Consistency", "Стабільність")}</span><strong>${grouped.length} ${tx("this month", "цього місяця")}</strong></div></div>`;
}

function progressChartPoints(grouped) {
  return grouped.slice().reverse().slice(-8).map((group, index, visible) => {
    const values = group.sets.map(set => ({
      weight: safeChartValue(set.weight),
      reps: safeChartValue(set.reps)
    }));
    return {
      label: String(new Date(group.session.startedAt).getDate()),
      maxWeight: Math.max(0, ...values.map(value => value.weight)),
      volume: values.reduce((sum, value) => sum + value.weight * value.reps, 0),
      latest: index === visible.length - 1
    };
  });
}

function exerciseTrendCharts(grouped, monthPeak) {
  const points = progressChartPoints(grouped);
  if (!points.length) {
    return `<section class="panel highlighted trend-panel"><h2>${tx("Visual Trends", "Візуальні тренди")}</h2><p class="muted">${tx("Maximum weight and session volume over time.", "Максимальна вага та обсяг тренування в динаміці.")}</p><div class="empty">${tx("Add sets to see chart.", "Додай підходи, щоб побачити графік.")}</div></section>`;
  }

  const maxWeight = Math.max(1, ...points.map(point => point.maxWeight));
  const maxVolume = Math.max(1, ...points.map(point => point.volume));
  const x = index => points.length === 1 ? 0 : index / (points.length - 1) * 100;
  const y = point => 152 - point.maxWeight / maxWeight * 140;
  const linePath = points.map((point, index) => `${index ? "L" : "M"}${x(index).toFixed(3)} ${y(point).toFixed(3)}`).join(" ");
  const fillPath = `M0 152 ${points.map((point, index) => `L${x(index).toFixed(3)} ${y(point).toFixed(3)}`).join(" ")} L100 152 Z`;
  const dotMarkup = points.map((point, index) =>
    `<circle class="chart-dot ${point.latest ? "latest" : ""}" cx="${x(index).toFixed(3)}" cy="${y(point).toFixed(3)}" r="${point.latest ? "2.8" : "2"}"/>`
  ).join("");
  const barGap = points.length > 1 ? 2 : 0;
  const barWidth = (100 - barGap * (points.length - 1)) / points.length;
  const barMarkup = points.map((point, index) => {
    const ratio = clamp(point.volume / maxVolume, 0, 1);
    const height = Math.max(1, ratio * 152);
    const barX = index * (barWidth + barGap);
    return `<rect class="chart-bar ${point.latest ? "latest" : ""}" x="${barX.toFixed(3)}" y="${(152 - height).toFixed(3)}" width="${barWidth.toFixed(3)}" height="${height.toFixed(3)}" rx="2"/>`;
  }).join("");
  const labels = `<div class="chart-labels">${points.map(point => `<span>${escapeHtml(point.label)}</span>`).join("")}</div>`;
  const first = points[0];
  const latest = points.at(-1);
  const averageVolume = points.reduce((sum, point) => sum + point.volume, 0) / points.length;

  return `<section class="panel highlighted trend-panel"><h2>${tx("Visual Trends", "Візуальні тренди")}</h2><p class="muted">${tx(`${points.length} recent sessions`, `${points.length} останніх тренувань`)}</p>
    <div class="chart-section"><h3>${tx("Maximum weight", "Максимальна вага")}</h3><p class="muted">${escapeHtml(progressDeltaLabel(latest.maxWeight, first.maxWeight, tx("kg vs first session", "кг відносно першої сесії")))}</p><div class="trend-chart-plot"><svg viewBox="0 0 100 180" preserveAspectRatio="none" aria-hidden="true"><path class="chart-guide" d="M0 0 H100 M0 76 H100 M0 152 H100"/><path class="chart-line-fill" d="${fillPath}"/><path class="chart-line" d="${linePath}"/>${dotMarkup}</svg></div>${labels}</div>
    <div class="chart-section"><h3>${tx("Session volume", "Обсяг тренування")}</h3><p class="muted">${escapeHtml(progressDeltaLabel(latest.volume, first.volume, tx("volume vs first session", "обсягу відносно першої сесії")))}</p><div class="trend-chart-plot"><svg viewBox="0 0 100 180" preserveAspectRatio="none" aria-hidden="true"><path class="chart-guide" d="M0 0 H100 M0 76 H100 M0 152 H100"/>${barMarkup}</svg></div>${labels}</div>
    <div class="metric-grid"><div><span>${tx("Peak weight", "Пікова вага")}</span><strong>${formatSetWeight(monthPeak)} kg</strong></div><div><span>${tx("Average volume", "Середній обсяг")}</span><strong>${Math.round(averageVolume)}</strong></div></div></section>`;
}

function progressDeltaLabel(latest, previous, unit) {
  if (previous == null) return tx("First tracked session", "Перше відстежене тренування");
  const delta = safeChartValue(latest) - safeChartValue(previous);
  if (Math.abs(delta) < 0.05) return tx("Holding steady", "Стабільно");
  const value = Math.abs(delta) < 10 ? Math.abs(delta).toFixed(1).replace(/\.0$/, "") : Math.round(Math.abs(delta));
  return `${delta > 0 ? "+" : "-"}${value} ${unit}`;
}

function safeChartValue(value) {
  const numeric = Number(value);
  return Number.isFinite(numeric) && numeric > 0 ? numeric : 0;
}

function progressHistoryCard(group) {
  const volume = group.sets.reduce((sum, s) => sum + Number(s.weight || 0) * Number(s.reps || 0), 0);
  const reps = group.sets.reduce((sum, x) => sum + Number(x.reps || 0), 0);
  return `<article class="workout-item"><h3>${fmtDate(group.session.startedAt)}</h3><div class="chip-row"><span class="chip">${tx("Sets", "Підходи")}: ${group.sets.length}</span><span class="chip">${tx("Reps", "Повтори")}: ${reps}</span><span class="chip">${tx("Volume", "Обсяг")}: ${Math.round(volume)}</span></div><div class="table"><div class="table-row"><strong>${tx("Set", "Підхід")}</strong><strong>${tx("Weight", "Вага")}</strong><strong>${tx("Reps", "Повтори")}</strong><span></span></div>${group.sets.map((set, i) => `<div class="table-row"><span>${tx("Set", "Підхід")} ${i + 1}</span><span>${Number(set.weight || 0).toFixed(1)}</span><span>${Number(set.reps || 0)}</span><button class="icon-button" data-action="delete-set" data-id="${set.id}" data-session="${escapeAttr(group.session.id)}" aria-label="${txAttr("Delete set", "Видалити підхід")}">${svg("delete")}</button></div>`).join("")}</div></article>`;
}

function missionsScreen() {
  const missions = missionGroups();
  const all = [...missions.daily, ...missions.weekly, ...missions.monthly];
  const done = all.filter(m => m.done);
  const dailyDone = missions.daily.filter(m => m.done).length;
  const weeklyDone = missions.weekly.filter(m => m.done).length;
  const monthlyDone = missions.monthly.filter(m => m.done).length;
  const periods = {
    daily: {
      label: t("daily"),
      tabLabel: tx("Daily", "Щоденні"),
      supporting: tx("Daily consistency goals reset at midnight.", "Щоденні цілі стабільності оновлюються опівночі."),
      missions: missions.daily
    },
    weekly: {
      label: t("weekly"),
      tabLabel: tx("Weekly", "Тижневі"),
      supporting: tx("Weekly goals track this training week.", "Тижневі цілі рахують поточний тренувальний тиждень."),
      missions: missions.weekly
    },
    monthly: {
      label: t("monthly"),
      tabLabel: tx("Monthly", "Місячні"),
      supporting: tx("Monthly goals measure the whole calendar month.", "Місячні цілі рахують увесь календарний місяць."),
      missions: missions.monthly
    }
  };
  const selected = periods[missionPeriod] || periods.daily;
  const periodTabs = `<section class="segmented mission-period-tabs panel compact" role="tablist" aria-label="${txAttr("Missions", "Місії")}">${Object.entries(periods).map(([period, item]) => {
    const isSelected = period === missionPeriod;
    return `<button type="button" role="tab" id="mission-tab-${period}" aria-controls="mission-panel-${period}" aria-selected="${isSelected}" tabindex="${isSelected ? "0" : "-1"}" class="${isSelected ? "selected" : ""}" data-action="mission-period" data-period="${period}"><strong>${escapeHtml(item.tabLabel)}</strong><span>${item.missions.filter(m => m.done).length}/${item.missions.length}</span></button>`;
  }).join("")}</section>`;
  const sections = selected.missions.length
    ? `<div id="mission-panel-${missionPeriod}" role="tabpanel" aria-labelledby="mission-tab-${missionPeriod}">${missionSection(selected.label, selected.supporting, selected.missions)}</div>`
    : `<section class="panel"><div class="empty"><h2>${tx("No missions yet", "Місій ще немає")}</h2><p>${tx("Add workouts to unlock daily, weekly, and monthly goals.", "Додай тренування, щоб відкрити щоденні, тижневі й місячні цілі.")}</p></div></section>`;
  return `<section class="hero-panel"><h2>${t("missions")}</h2><p>${tx("Active daily, weekly, and monthly missions rotate from a huge challenge pool.", "Активні щоденні, тижневі й місячні місії обираються з великого пулу викликів.")}</p><div class="metric-grid"><div><span>${tx("Total", "Усього")}</span><strong>${all.length}</strong></div><div><span>${tx("Completed", "Виконано")}</span><strong>${done.length}</strong></div><div><span>${tx("Open", "Відкрито")}</span><strong>${all.length - done.length}</strong></div><div><span>${tx("Progress", "Прогрес")}</span><strong>${done.length}/${all.length}</strong></div></div><p>${tx("Daily", "Щоденні")}: ${dailyDone}/${missions.daily.length} - ${tx("Weekly", "Тижневі")}: ${weeklyDone}/${missions.weekly.length} - ${tx("Monthly", "Місячні")}: ${monthlyDone}/${missions.monthly.length}</p><p>${tx("Mission XP from completed goals", "XP місій за виконані цілі")}: ${done.reduce((s, m) => s + m.reward, 0)}</p></section>
    <section class="panel highlighted clickable" data-action="open-ranks"><div class="section-title"><div><h2>${tx("Rank ladder", "Драбина рангів")}</h2><p>${tx("Open the full rank list and check the next unlocks.", "Відкрий повний список рангів і подивися, що відкриється далі.")}</p></div><span class="pill">${t("viewRanks")}</span></div><div class="metric-grid"><div><span>${tx("Current level", "Поточний рівень")}</span><strong>${levelFromXp()}</strong></div><div><span>${tx("Current title", "Поточний ранг")}</span><strong>${rankTitle()}</strong></div></div></section>
    ${periodTabs}
    ${sections}
    ${achievementsGallery()}`;
}

function missionGroups() {
  const history = missionHistoryStats();
  return {
    daily: buildMissionSet("daily", dailyMissionCatalog(), 5, dayNumber(new Date()), ["workouts"], dailyMissionStats(), history),
    weekly: buildMissionSet("weekly", weeklyMissionCatalog(), 10, dayNumber(startOfWeekDate()), ["workouts"], weeklyMissionStats(), history),
    monthly: buildMissionSet("monthly", monthlyMissionCatalog(), 10, dayNumber(new Date(new Date().getFullYear(), new Date().getMonth(), 1)), ["workouts"], monthlyMissionStats(), history)
  };
}

function completedMissions() {
  return Object.values(missionGroups()).flat().filter(m => m.done);
}

function mission(template, cadence, stats, history) {
  const target = missionTargetForFamily(cadence, template.family, history);
  const progress = template.progress(stats);
  const reward = missionXpReward(cadence, template.goal, target);
  const cadenceLabel = cadence === "daily" ? t("daily") : cadence === "weekly" ? t("weekly") : t("monthly");
  return {
    id: template.id,
    cadence,
    cadenceLabel,
    title: tx(template.titleEn, template.titleUk),
    summary: `${Math.round(progress)} / ${template.goal} ${tx(template.unitEn, template.unitUk)}`,
    progressLabel: `${Math.round(progress)} / ${template.goal} ${tx(template.unitEn, template.unitUk)}`,
    progress,
    target: template.goal,
    reward,
    done: progress >= template.goal
  };
}

function buildMissionSet(cadence, templates, count, seed, requiredFamilies, stats, history) {
  const ranked = [...templates].sort((a, b) => {
    const score = compareBigInt(missionSelectionScore(a.goal, missionTargetForFamily(cadence, a.family, history), seed), missionSelectionScore(b.goal, missionTargetForFamily(cadence, b.family, history), seed));
    return score || compareBigInt(missionOrderScore(a.id, seed), missionOrderScore(b.id, seed));
  });
  const selected = [];
  const selectedIds = new Set();
  const selectedFamilies = new Set();
  for (const family of requiredFamilies) {
    const template = ranked.find(item => item.family === family && !selectedIds.has(item.id));
    if (template) addMissionTemplate(template, selected, selectedIds, selectedFamilies);
  }
  for (const template of ranked) {
    if (selected.length >= count) break;
    if (!selectedFamilies.has(template.family)) addMissionTemplate(template, selected, selectedIds, selectedFamilies);
  }
  for (const template of ranked) {
    if (selected.length >= count) break;
    if (!selectedIds.has(template.id)) addMissionTemplate(template, selected, selectedIds, selectedFamilies);
  }
  return selected.map(template => mission(template, cadence, stats, history));
}

function addMissionTemplate(template, selected, selectedIds, selectedFamilies) {
  selected.push(template);
  selectedIds.add(template.id);
  selectedFamilies.add(template.family);
}

function dailyMissionCatalog() {
  return [
    ...templates("workouts", [1], "daily-check-in", "workout", "тренування", goal => "Daily check-in", goal => "Щоденний чек-ін", s => s.workoutCount),
    ...templates("exercises", intSeries(3, 1, 10), goal => `daily-exercises-${goal}`, "exercises", "вправ", goal => `${goal} exercises today`, goal => `${goal} вправ за день`, s => s.exerciseCount),
    ...templates("sets", intSeries(8, 2, 9), goal => `daily-sets-${goal}`, "sets", "підходів", goal => `${goal}-set target`, goal => `Ціль: ${goal} підходів`, s => s.setCount),
    ...templates("volume", scaledSeries(1800, [0.8, 1, 1.2, 1.4, 1.6, 1.9, 2.2, 2.5, 2.8, 3.1, 3.5, 3.9, 4.3]), goal => `daily-volume-${goal}`, "volume", "обсягу", goal => `Volume target ${goal}`, goal => `Ціль обсягу ${goal}`, s => s.totalVolume),
    ...templates("max-session-volume", scaledSeries(1300, [0.8, 1, 1.2, 1.4, 1.6, 1.9, 2.2, 2.5, 2.8, 3.1, 3.5, 3.9, 4.4, 4.9, 5.5]), goal => `daily-max-session-volume-${goal}`, "volume", "обсягу", goal => `Best session ${goal} volume`, goal => `Краща сесія: ${goal} обсягу`, s => s.maxSessionVolume),
    ...templates("max-session-exercises", intSeries(3, 1, 8), goal => `daily-max-session-exercises-${goal}`, "exercises", "вправ", goal => `Session breadth ${goal}`, goal => `Ширина сесії ${goal}`, s => s.maxSessionExercises),
    ...templates("max-session-sets", intSeries(8, 2, 8), goal => `daily-max-session-sets-${goal}`, "sets", "підходів", goal => `Session sets ${goal}`, goal => `Підходи в сесії: ${goal}`, s => s.maxSessionSets)
  ];
}

function weeklyMissionCatalog() {
  return [
    ...templates("workouts", intSeries(2, 1, 2), goal => `weekly-workouts-${goal}`, "workouts", "тренування", goal => `${goal}-workout week`, goal => `Тиждень на ${goal} тренувань`, s => s.workoutCount),
    ...templates("active-days", intSeries(2, 1, 2), goal => `weekly-active-days-${goal}`, "days", "днів", goal => `${goal} active days`, goal => `${goal} активних днів`, s => s.activeDays),
    ...templates("sets", intSeries(24, 4, 10), goal => `weekly-sets-${goal}`, "sets", "підходів", goal => `${goal}-set week`, goal => `Тиждень на ${goal} підходів`, s => s.setCount),
    ...templates("volume", scaledSeries(8000, [0.8, 0.95, 1.1, 1.25, 1.4, 1.55, 1.75, 1.95, 2.2, 2.5, 2.8, 3.1]), goal => `weekly-volume-${goal}`, "volume", "обсягу", goal => `Weekly volume ${goal}`, goal => `Тижневий обсяг ${goal}`, s => s.totalVolume),
    ...templates("exercises", intSeries(14, 3, 12), goal => `weekly-exercises-${goal}`, "exercises", "вправ", goal => `${goal} exercises this week`, goal => `${goal} вправ за тиждень`, s => s.exerciseCount),
    ...templates("days-10-sets", intSeries(1, 1, 3), goal => `weekly-days-10-sets-${goal}`, "days", "днів", goal => `High-output days ${goal}`, goal => `Потужних днів: ${goal}`, s => s.daysWithTenPlusSets),
    ...templates("days-1000-volume", intSeries(1, 1, 3), goal => `weekly-days-1000-volume-${goal}`, "days", "днів", goal => `Volume days ${goal}`, goal => `Днів обсягу: ${goal}`, s => s.daysWithThousandVolume),
    ...templates("sessions-8-sets", intSeries(1, 1, 3), goal => `weekly-sessions-8-sets-${goal}`, "sessions", "сесій", goal => `Strong sessions ${goal}`, goal => `Сильних сесій: ${goal}`, s => s.sessionsWithEightPlusSets),
    ...templates("sessions-3-exercises", intSeries(1, 1, 3), goal => `weekly-sessions-3-exercises-${goal}`, "sessions", "сесій", goal => `Wide sessions ${goal}`, goal => `Широких сесій: ${goal}`, s => s.sessionsWithThreePlusExercises)
  ];
}

function monthlyMissionCatalog() {
  return [
    ...templates("workouts", intSeries(8, 1, 7), goal => `monthly-workouts-${goal}`, "workouts", "тренування", goal => `${goal}-workout month`, goal => `Місяць на ${goal} тренувань`, s => s.workoutCount),
    ...templates("active-days", intSeries(8, 1, 7), goal => `monthly-active-days-${goal}`, "days", "днів", goal => `${goal} active days`, goal => `${goal} активних днів`, s => s.activeDays),
    ...templates("sets", intSeries(70, 10, 12), goal => `monthly-sets-${goal}`, "sets", "підходів", goal => `${goal}-set month`, goal => `Місяць на ${goal} підходів`, s => s.setCount),
    ...templates("volume", scaledSeries(45000, [0.7, 0.8, 0.9, 1, 1.1, 1.2, 1.3, 1.4, 1.55, 1.7, 1.85, 2]), goal => `monthly-volume-${goal}`, "volume", "обсягу", goal => `Monthly volume ${goal}`, goal => `Місячний обсяг ${goal}`, s => s.totalVolume),
    ...templates("exercises", intSeries(45, 7, 14), goal => `monthly-exercises-${goal}`, "exercises", "вправ", goal => `${goal} exercises this month`, goal => `${goal} вправ за місяць`, s => s.exerciseCount),
    ...templates("days-10-sets", intSeries(4, 1, 9), goal => `monthly-days-10-sets-${goal}`, "days", "днів", goal => `High-output days ${goal}`, goal => `Потужних днів: ${goal}`, s => s.daysWithTenPlusSets),
    ...templates("days-1000-volume", intSeries(4, 1, 9), goal => `monthly-days-1000-volume-${goal}`, "days", "днів", goal => `Volume days ${goal}`, goal => `Днів обсягу: ${goal}`, s => s.daysWithThousandVolume),
    ...templates("sessions-8-sets", intSeries(5, 1, 9), goal => `monthly-sessions-8-sets-${goal}`, "sessions", "сесій", goal => `Strong sessions ${goal}`, goal => `Сильних сесій: ${goal}`, s => s.sessionsWithEightPlusSets),
    ...templates("sessions-3-exercises", intSeries(5, 1, 9), goal => `monthly-sessions-3-exercises-${goal}`, "sessions", "сесій", goal => `Wide sessions ${goal}`, goal => `Широких сесій: ${goal}`, s => s.sessionsWithThreePlusExercises),
    ...templates("max-session-volume", scaledSeries(1400, [1, 1.15, 1.3, 1.45, 1.6, 1.8, 2, 2.25, 2.5, 2.8, 3.1, 3.5, 3.9, 4.3, 4.8, 5.3]), goal => `monthly-max-session-volume-${goal}`, "volume", "обсягу", goal => `Best session ${goal} volume`, goal => `Краща сесія: ${goal} обсягу`, s => s.maxSessionVolume),
    ...templates("max-session-sets", intSeries(10, 2, 11), goal => `monthly-max-session-sets-${goal}`, "sets", "підходів", goal => `Best session ${goal} sets`, goal => `Краща сесія: ${goal} підходів`, s => s.maxSessionSets),
    ...templates("max-session-exercises", intSeries(4, 1, 9), goal => `monthly-max-session-exercises-${goal}`, "exercises", "вправ", goal => `Best session ${goal} exercises`, goal => `Краща сесія: ${goal} вправ`, s => s.maxSessionExercises)
  ];
}

function templates(family, goals, idForGoal, unitEn, unitUk, titleEn, titleUk, progress) {
  return goals.map(goal => ({
    family,
    goal,
    id: typeof idForGoal === "function" ? idForGoal(goal) : idForGoal,
    unitEn,
    unitUk,
    titleEn: titleEn(goal),
    titleUk: titleUk(goal),
    progress
  }));
}

function intSeries(start, step, count) {
  return Array.from({ length: count }, (_, index) => start + index * step);
}

function scaledSeries(base, factors) {
  return [...new Set(factors.map(factor => Math.max(1, Math.round(base * factor))))].sort((a, b) => a - b);
}

function missionXpReward(cadence, goal, target) {
  const base = cadence === "daily" ? 90 : cadence === "weekly" ? 220 : 420;
  const ratio = goal / Math.max(1, target);
  const multiplier = ratio >= 1.35 ? 1.9 : ratio >= 1.2 ? 1.65 : ratio >= 1.05 ? 1.45 : ratio >= 0.9 ? 1.25 : ratio >= 0.75 ? 1.05 : 0.9;
  return Math.max(Math.round(base * 0.8), Math.round(base * multiplier));
}

function dailyMissionStats() {
  return periodStats(state.sessions.filter(session => sameDay(session.startedAt, Date.now())));
}

function weeklyMissionStats() {
  const start = startOfWeek();
  const end = start + 7 * 86400000;
  return periodStats(state.sessions.filter(session => session.startedAt >= start && session.startedAt < end));
}

function monthlyMissionStats() {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), 1).getTime();
  const end = new Date(now.getFullYear(), now.getMonth() + 1, 1).getTime();
  return periodStats(state.sessions.filter(session => session.startedAt >= start && session.startedAt < end));
}

function periodStats(sessions) {
  const summaries = sessions.map(sessionSummary);
  const byDay = groupBy(sessions, session => dayKey(session.startedAt));
  const dayAggregates = Object.values(byDay).map(aggregateSessions);
  return {
    workoutCount: sessions.length,
    activeDays: Object.keys(byDay).length,
    exerciseCount: summaries.reduce((sum, item) => sum + item.exercises, 0),
    setCount: summaries.reduce((sum, item) => sum + item.sets, 0),
    totalVolume: Math.round(summaries.reduce((sum, item) => sum + item.volume, 0)),
    daysWithTenPlusSets: dayAggregates.filter(item => item.setCount >= 10).length,
    daysWithThousandVolume: dayAggregates.filter(item => item.totalVolume >= 1000).length,
    sessionsWithEightPlusSets: summaries.filter(item => item.sets >= 8).length,
    sessionsWithThreePlusExercises: summaries.filter(item => item.exercises >= 3).length,
    maxSessionVolume: Math.round(Math.max(0, ...summaries.map(item => item.volume))),
    maxSessionSets: Math.max(0, ...summaries.map(item => item.sets)),
    maxSessionExercises: Math.max(0, ...summaries.map(item => item.exercises))
  };
}

function missionHistoryStats() {
  if (!state.sessions.length) return {};
  const dayAggregates = Object.values(groupBy(state.sessions, session => dayKey(session.startedAt))).map(aggregateSessions);
  const weekAggregates = Object.values(groupBy(state.sessions, session => dayKey(startOfWeekDate(new Date(session.startedAt))))).map(aggregatePeriod);
  const monthAggregates = Object.values(groupBy(state.sessions, session => monthKey(session.startedAt))).map(aggregatePeriod);
  const summaries = state.sessions.map(sessionSummary);
  return {
    maxDayWorkouts: maxOf(dayAggregates, "workoutCount"),
    maxDayExercises: maxOf(dayAggregates, "exerciseCount"),
    maxDaySets: maxOf(dayAggregates, "setCount"),
    maxDayVolume: maxOf(dayAggregates, "totalVolume"),
    maxWeekWorkouts: maxOf(weekAggregates, "workoutCount"),
    maxWeekActiveDays: maxOf(weekAggregates, "activeDays"),
    maxWeekExercises: maxOf(weekAggregates, "exerciseCount"),
    maxWeekSets: maxOf(weekAggregates, "setCount"),
    maxWeekVolume: maxOf(weekAggregates, "totalVolume"),
    maxWeekDaysWithTenPlusSets: maxOf(weekAggregates, "daysWithTenPlusSets"),
    maxWeekDaysWithThousandVolume: maxOf(weekAggregates, "daysWithThousandVolume"),
    maxWeekSessionsWithEightPlusSets: maxOf(weekAggregates, "sessionsWithEightPlusSets"),
    maxWeekSessionsWithThreePlusExercises: maxOf(weekAggregates, "sessionsWithThreePlusExercises"),
    maxMonthWorkouts: maxOf(monthAggregates, "workoutCount"),
    maxMonthActiveDays: maxOf(monthAggregates, "activeDays"),
    maxMonthExercises: maxOf(monthAggregates, "exerciseCount"),
    maxMonthSets: maxOf(monthAggregates, "setCount"),
    maxMonthVolume: maxOf(monthAggregates, "totalVolume"),
    maxMonthDaysWithTenPlusSets: maxOf(monthAggregates, "daysWithTenPlusSets"),
    maxMonthDaysWithThousandVolume: maxOf(monthAggregates, "daysWithThousandVolume"),
    maxMonthSessionsWithEightPlusSets: maxOf(monthAggregates, "sessionsWithEightPlusSets"),
    maxMonthSessionsWithThreePlusExercises: maxOf(monthAggregates, "sessionsWithThreePlusExercises"),
    maxSessionVolume: Math.round(Math.max(0, ...summaries.map(item => item.volume))),
    maxSessionExercises: Math.max(0, ...summaries.map(item => item.exercises)),
    maxSessionSets: Math.max(0, ...summaries.map(item => item.sets))
  };
}

function aggregatePeriod(sessions) {
  const aggregate = aggregateSessions(sessions);
  const byDay = Object.values(groupBy(sessions, session => dayKey(session.startedAt))).map(aggregateSessions);
  aggregate.activeDays = byDay.length;
  aggregate.daysWithTenPlusSets = byDay.filter(item => item.setCount >= 10).length;
  aggregate.daysWithThousandVolume = byDay.filter(item => item.totalVolume >= 1000).length;
  aggregate.sessionsWithEightPlusSets = sessions.filter(session => sessionSummary(session).sets >= 8).length;
  aggregate.sessionsWithThreePlusExercises = sessions.filter(session => sessionSummary(session).exercises >= 3).length;
  return aggregate;
}

function aggregateSessions(sessions) {
  const summaries = sessions.map(sessionSummary);
  return {
    workoutCount: sessions.length,
    activeDays: new Set(sessions.map(session => dayKey(session.startedAt))).size,
    exerciseCount: summaries.reduce((sum, item) => sum + item.exercises, 0),
    setCount: summaries.reduce((sum, item) => sum + item.sets, 0),
    totalVolume: Math.round(summaries.reduce((sum, item) => sum + item.volume, 0)),
    daysWithTenPlusSets: 0,
    daysWithThousandVolume: 0,
    sessionsWithEightPlusSets: 0,
    sessionsWithThreePlusExercises: 0,
    maxSessionVolume: Math.round(Math.max(0, ...summaries.map(item => item.volume))),
    maxSessionSets: Math.max(0, ...summaries.map(item => item.sets)),
    maxSessionExercises: Math.max(0, ...summaries.map(item => item.exercises))
  };
}

function missionTargetForFamily(cadence, family, history) {
  if (cadence === "daily") {
    if (family === "workouts") return 1;
    if (family === "exercises") return boundedTarget(history.maxDayExercises, 8, 5, 12);
    if (family === "sets") return boundedTarget(history.maxDaySets, 14, 10, 24);
    if (family === "volume") return boundedTarget(history.maxDayVolume, 4800, 3000, 8000);
    if (family === "max-session-volume") return boundedTarget(history.maxSessionVolume, 4000, 2500, 7500);
    if (family === "max-session-exercises") return boundedTarget(history.maxSessionExercises, 6, 4, 10);
    if (family === "max-session-sets") return boundedTarget(history.maxSessionSets, 12, 8, 22);
  }
  if (cadence === "weekly") {
    if (family === "workouts") return boundedTarget(history.maxWeekWorkouts, 3, 2, 3);
    if (family === "active-days") return boundedTarget(history.maxWeekActiveDays, 3, 2, 3);
    if (family === "exercises") return boundedTarget(history.maxWeekExercises, 28, 18, 48);
    if (family === "sets") return boundedTarget(history.maxWeekSets, 40, 24, 64);
    if (family === "volume") return boundedTarget(history.maxWeekVolume, 16000, 9000, 24000);
    if (family === "days-10-sets") return boundedTarget(history.maxWeekDaysWithTenPlusSets, 2, 1, 3);
    if (family === "days-1000-volume") return boundedTarget(history.maxWeekDaysWithThousandVolume, 2, 1, 3);
    if (family === "sessions-8-sets") return boundedTarget(history.maxWeekSessionsWithEightPlusSets, 2, 1, 3);
    if (family === "sessions-3-exercises") return boundedTarget(history.maxWeekSessionsWithThreePlusExercises, 2, 1, 3);
  }
  if (cadence === "monthly") {
    if (family === "workouts") return boundedTarget(history.maxMonthWorkouts, 12, 8, 14);
    if (family === "active-days") return boundedTarget(history.maxMonthActiveDays, 12, 8, 14);
    if (family === "exercises") return boundedTarget(history.maxMonthExercises, 90, 45, 140);
    if (family === "sets") return boundedTarget(history.maxMonthSets, 130, 70, 200);
    if (family === "volume") return boundedTarget(history.maxMonthVolume, 65000, 35000, 95000);
    if (family === "days-10-sets") return boundedTarget(history.maxMonthDaysWithTenPlusSets, 8, 4, 12);
    if (family === "days-1000-volume") return boundedTarget(history.maxMonthDaysWithThousandVolume, 8, 4, 12);
    if (family === "sessions-8-sets") return boundedTarget(history.maxMonthSessionsWithEightPlusSets, 8, 4, 12);
    if (family === "sessions-3-exercises") return boundedTarget(history.maxMonthSessionsWithThreePlusExercises, 8, 4, 12);
    if (family === "max-session-volume") return boundedTarget(history.maxSessionVolume, 5000, 2500, 8000);
    if (family === "max-session-sets") return boundedTarget(history.maxSessionSets, 18, 10, 30);
    if (family === "max-session-exercises") return boundedTarget(history.maxSessionExercises, 8, 4, 12);
  }
  return 1;
}

function boundedTarget(observed, fallback, min, max) {
  return clamp(observed > 0 ? observed : fallback, min, max);
}

function missionSelectionScore(goal, target, seed) {
  const adjustedTarget = Math.max(1, target);
  const distance = Math.abs(goal - adjustedTarget);
  const underTargetDistance = Math.max(0, adjustedTarget - goal);
  const overTargetDistance = Math.max(0, goal - adjustedTarget);
  const jitter = absBigInt(missionOrderScore(String(goal), seed)) % 31n;
  return BigInt(distance * 100 + underTargetDistance * 40 + overTargetDistance * 120) + jitter;
}

function missionOrderScore(id, seed) {
  let mixed = toLong(BigInt(javaStringHash(id))) ^ toLong(BigInt(seed) * 1000003n);
  mixed = toLong(mixed ^ toLong(mixed << 21n));
  mixed = toLong(mixed ^ (toUnsigned(mixed) >> 35n));
  mixed = toLong(mixed ^ toLong(mixed << 4n));
  return toSigned(mixed);
}

function javaStringHash(value) {
  let hash = 0;
  for (let index = 0; index < value.length; index++) hash = ((hash * 31) + value.charCodeAt(index)) | 0;
  return hash;
}

function toLong(value) {
  return value & ((1n << 64n) - 1n);
}

function toUnsigned(value) {
  return value & ((1n << 64n) - 1n);
}

function toSigned(value) {
  const normalized = toLong(value);
  return normalized >= (1n << 63n) ? normalized - (1n << 64n) : normalized;
}

function absBigInt(value) {
  return value < 0n ? -value : value;
}

function compareBigInt(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

function groupBy(items, keySelector) {
  return items.reduce((groups, item) => {
    const key = keySelector(item);
    (groups[key] ||= []).push(item);
    return groups;
  }, {});
}

function maxOf(items, key) {
  return Math.max(0, ...items.map(item => Number(item[key] || 0)));
}

function sameDay(a, b) {
  return dayKey(a) === dayKey(b);
}

function dayKey(value) {
  const date = new Date(value);
  return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
}

function startOfWeekDate(date = new Date()) {
  const start = new Date(date);
  start.setDate(start.getDate() - ((start.getDay() + 6) % 7));
  start.setHours(0, 0, 0, 0);
  return start;
}

function dayNumber(date) {
  return Math.floor(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000);
}

function missionSection(title, supporting, missions) {
  return `<section class="mission-list"><div class="section-title panel highlighted compact"><div><h2>${escapeHtml(title)}</h2><p>${escapeHtml(supporting)}</p></div><span class="pill">${missions.filter(m => m.done).length}/${missions.length} ${tx("done", "виконано")}</span></div>${missions.map(missionCard).join("")}</section>`;
}

function missionCard(m) {
  const status = m.done ? tx("Completed", "Виконано") : tx("In progress", "У процесі");
  return `<article class="mission-row ${m.done ? "highlighted" : ""}"><div class="row-head"><div><h3>${escapeHtml(m.title)}</h3><p>${escapeHtml(m.summary)}</p></div><span class="pill">${escapeHtml(status)}</span></div><div class="chip-row"><span class="chip">${escapeHtml(m.cadenceLabel)}</span><span class="chip">+${m.reward} XP</span><span class="muted">${escapeHtml(m.progressLabel)}</span></div><div class="progress"><span class="${percentageClass(m.progress / Math.max(1, m.target) * 100)}"></span></div></article>`;
}

function ranksScreen() {
  const xp = totalXp();
  const ranks = rankLadder().sort((a, b) => a.xp - b.xp || a.level - b.level);
  const cards = ranks.length ? ranks.map(rank => {
    const unlocked = rank.isUnlocked;
    const current = rank.isCurrent;
    const status = current ? tx("Current", "Поточний") : unlocked ? tx("Unlocked", "Відкрито") : tx("Locked", "Закрито");
    const progressValue = unlocked ? 100 : rank.progressFraction * 100;
    return `<section class="panel ${current ? "highlighted" : ""}"><div class="row-head"><div><h2>${rank.title}</h2><p>${status}</p></div><span class="pill">${status}</span></div><div class="metric-grid"><div><span>${tx("Required level", "Потрібний рівень")}</span><strong>${rank.level}</strong></div><div><span>${tx("Required total XP", "Потрібно XP")}</span><strong>${rank.xp}</strong></div></div><div class="progress"><span class="${percentageClass(progressValue)}"></span></div><div class="row-line"><span>${Math.min(xp, rank.xp)} / ${rank.xp} XP</span>${!unlocked ? `<strong>${rank.xpRemaining} XP ${tx("left", "лишилось")}</strong>` : ""}</div></section>`;
  }).join("") : `<section class="panel"><div class="empty"><h2>${tx("No ranks yet", "Рангів ще немає")}</h2><p>${tx("Earn XP to unlock rank titles.", "Заробляй XP, щоб відкривати ранги.")}</p></div></section>`;
  return `<section class="hero-panel"><h2>${t("ranks")}</h2><p>${tx("See every title, its level gate, and the XP needed to unlock it.", "Переглянь усі ранги, потрібний рівень і XP для відкриття.")}</p><div class="metric-grid"><div><span>${tx("TOTAL XP", "УСЬОГО XP")}</span><strong>${xp}</strong></div><div><span>${tx("Current level", "Поточний рівень")}</span><strong>${levelFromXp(xp)}</strong></div></div><p>${tx("Current title", "Поточний ранг")}: ${rankTitle(xp)}</p></section>
    ${cards}`;
}

function modalMarkup() {
  if (modal.type === "change-password") return bottomSheet(`<h2>${tx("Change password", "Змінити пароль")}</h2>${modal.reauthRequired ? `<p class="muted">${tx("A verification code was sent to your email. Enter it together with the new password.", "Код підтвердження надіслано на твою електронну пошту. Введи його разом із новим паролем.")}</p>` : ""}<div class="field-stack"><label>${tx("Current password", "Поточний пароль")}<input id="change-current-password" type="password" autocomplete="current-password" maxlength="1024"></label>${modal.reauthRequired ? `<label>${tx("Verification code", "Код підтвердження")}<input id="change-password-nonce" autocomplete="one-time-code" inputmode="numeric" maxlength="8"></label>` : ""}<label>${tx("New password", "Новий пароль")}<input id="change-new-password" type="password" autocomplete="new-password" minlength="12" maxlength="72"></label><label>${tx("Repeat new password", "Повтори новий пароль")}<input id="change-repeat-password" type="password" autocomplete="new-password" minlength="12" maxlength="72"></label></div><p class="muted">${tx("Use at least 12 characters (up to 72 UTF-8 bytes) with lowercase and uppercase Latin letters, a number, and a supported symbol such as !, @, #, or $.", "Використай щонайменше 12 символів (до 72 байтів UTF-8): малу й велику латинські літери, цифру та підтримуваний спецсимвол, наприклад !, @, # або $.")}</p><button class="button full" data-action="submit-password-change" ${authRequestInProgress ? "disabled" : ""}>${tx("Change password", "Змінити пароль")}</button>`);
  if (modal.type === "template") return bottomSheet(`<h2>${t("templatePicker")}</h2>${state.sessions.length ? [...state.sessions].sort((a, b) => b.startedAt - a.startedAt).map(session => `<article class="workout-item"><h3>${fmtDate(session.startedAt)}</h3><p>${sessionSummary(session).exercises} ${tx("exercises", "вправ")} - ${sessionSummary(session).sets} ${tx("sets", "підходів")} - ${Math.round(sessionSummary(session).volume)} ${tx("volume", "обсяг")}</p><button class="button full" data-action="copy-template" data-id="${session.id}">${t("copyWorkout")}</button></article>`).join("") : `<p>${tx("No previous workouts yet.", "Попередніх тренувань ще немає.")}</p>`}`);
  if (modal.type === "import") return bottomSheet(`<h2>${tx("Import backup", "Імпорт резервної копії")}</h2><textarea id="import-json" placeholder="${txAttr("Paste exported GymApp JSON here", "Встав сюди експортований JSON GymApp")}"></textarea><button class="button full" data-action="apply-import">${tx("Import", "Імпорт")}</button>`);
  if (modal.type === "add-exercise") return bottomSheet(`<h2>${tx("Add exercise", "Додати вправу")}</h2><input id="new-exercise-name" maxlength="120" aria-label="${txAttr("Exercise name", "Назва вправи")}" placeholder="${txAttr("Exercise name", "Назва вправи")}"><button class="button full" data-action="save-exercise">${tx("Add exercise", "Додати вправу")}</button>`);
  if (modal.type === "exercise-media") {
    const media = exerciseMedia(modal.exercise);
    const frames = media?.frames || [];
    const visual = frames.length
      ? `<div class="exercise-media-stage ${frames.length > 1 ? "animated" : ""}" aria-label="${txAttr("Exercise movement reference", "Орієнтир руху вправи")}">${frames.map((frame, index) => `<img class="exercise-media-frame frame-${index}" src="${escapeAttr(frame)}" alt="">`).join("")}<span class="exercise-media-state">${frames.length > 1 ? tx("Start · Finish", "Початок · Кінець") : tx("Your image", "Ваше фото")}</span></div>`
      : `<div class="exercise-media-stage empty">${svg("image", "exercise-media-empty-icon")}<strong>${tx("No demonstration yet", "Демонстрації поки немає")}</strong><p>${tx("Choose a clear image that helps you recognize this exercise.", "Оберіть чітке фото, яке допоможе впізнати цю вправу.")}</p></div>`;
    return bottomSheet(`<div class="exercise-media-sheet"><div><span class="eyebrow">${tx("Movement guide", "Орієнтир руху")}</span><h2>${escapeHtml(exerciseDisplayName(modal.exercise))}</h2><p class="muted">${tx("Tap-friendly reference for exercise selection. This is not medical or coaching advice.", "Зручний орієнтир для вибору вправи. Це не медична чи тренерська рекомендація.")}</p></div>${visual}<label class="button secondary full exercise-media-file-label">${svg("upload", "small-icon")}${tx("Choose your image", "Обрати своє фото")}<input id="exercise-media-file" type="file" accept="image/jpeg,image/png,image/webp" hidden></label>${media?.custom ? `<button class="button ghost full" data-action="remove-exercise-media">${tx("Restore built-in image", "Повернути стандартне зображення")}</button>` : ""}</div>`);
  }
  if (modal.type === "backup-json") return bottomSheet(`<h2>${modal.diagnostics ? tx("Redacted diagnostics ready", "Знеособлена діагностика готова") : tx("Backup JSON ready", "Резервна копія JSON готова")}</h2><textarea readonly>${escapeHtml(modal.json)}</textarea><div class="actions"><button class="button" data-action="copy-json">${tx("Copy JSON", "Копіювати JSON")}</button><button class="button ghost" data-action="download-json">${tx("Download", "Завантажити")}</button></div><button class="button ghost full" data-action="pdf-report">${t("sharePdf")}</button>`);
  if (modal.type === "rename") return bottomSheet(`<h2>${t("rename")}</h2><input id="rename-name" maxlength="120" value="${escapeAttr(exerciseDisplayName(modal.exercise))}"><button class="button full" data-action="apply-rename" data-id="${modal.exercise.id}">${tx("Save", "Зберегти")}</button>`);
  if (modal.type === "history") return bottomSheet(exerciseHistoryMarkup(modal.exercise));
  if (modal.type === "map") return bottomSheet(mappingEditor(modal.name));
  if (modal.type === "edit-set") return bottomSheet(`<h2>${tx("Edit Set", "Редагувати підхід")}</h2><label>${tx("Weight (kg)", "Вага (кг)")}<input id="edit-weight" value="${modal.set.weight || ""}" inputmode="decimal"></label><label>${tx("Reps", "Повтори")}<input id="edit-reps" value="${modal.set.reps || ""}" inputmode="numeric"></label><button class="button full" data-action="apply-edit-set" data-id="${modal.set.id}">${tx("Save", "Зберегти")}</button>`);
  if (modal.type === "confirm-delete-exercise") {
    const preview = modal.intent?.preview || {};
    return bottomSheet(`<h2 id="delete-exercise-confirm-title">${tx("Delete exercise", "Видалити вправу")}</h2><p id="delete-exercise-confirm-target"><strong>${escapeHtml(preview.name || "")}</strong></p><p class="muted" id="delete-exercise-confirm-description">${tx("Delete this exercise from your library? This cannot be undone in GymApp.", "Видалити цю вправу з каталогу? У GymApp це неможливо скасувати.")}</p><div class="actions vertical"><button class="button ghost full" data-action="cancel-destructive" data-modal-initial-focus>${tx("Cancel", "Скасувати")}</button><button class="button danger full" data-action="confirm-delete-exercise">${tx("Delete exercise", "Видалити вправу")}</button></div>`, "delete-exercise-confirm-title", "alertdialog", "delete-exercise-confirm-target delete-exercise-confirm-description");
  }
  if (modal.type === "confirm-delete-set") {
    const preview = modal.intent?.preview || {};
    return bottomSheet(`<h2 id="delete-set-confirm-title">${tx("Delete set", "Видалити підхід")}</h2><p id="delete-set-confirm-target"><strong>${escapeHtml(preview.exerciseName || "")}</strong></p><p class="muted" id="delete-set-confirm-detail">${escapeHtml(preview.detail || "")}</p><p class="muted" id="delete-set-confirm-description">${tx("Delete this saved set? Workout totals, progress, and recommendations will be updated. This cannot be undone in GymApp.", "Видалити цей збережений підхід? Підсумки тренування, прогрес і рекомендації буде оновлено. У GymApp це неможливо скасувати.")}</p><div class="actions vertical"><button class="button ghost full" data-action="cancel-destructive" data-modal-initial-focus>${tx("Cancel", "Скасувати")}</button><button class="button danger full" data-action="confirm-delete-set">${tx("Delete set", "Видалити підхід")}</button></div>`, "delete-set-confirm-title", "alertdialog", "delete-set-confirm-target delete-set-confirm-detail delete-set-confirm-description");
  }
  if (modal.type === "confirm-import") {
    const preview = modal.intent?.preview || {};
    return bottomSheet(`<h2 id="import-confirm-title">${tx("Replace profile with backup?", "Замінити профіль резервною копією?")}</h2><p class="muted" id="import-confirm-description">${tx("This import will replace workout history, exercises, mappings, and profile settings. This cannot be undone in GymApp.", "Цей імпорт замінить історію тренувань, вправи, зіставлення та налаштування профілю. У GymApp це неможливо скасувати.")}</p><div class="metric-grid three"><div><span>${tx("Exercises", "Вправи")}</span><strong>${Number(preview.exerciseCount) || 0}</strong></div><div><span>${tx("Workouts", "Тренування")}</span><strong>${Number(preview.sessionCount) || 0}</strong></div><div><span>${tx("Sets", "Підходи")}</span><strong>${Number(preview.setCount) || 0}</strong></div></div><div class="actions vertical"><button class="button ghost full" data-action="cancel-destructive" data-modal-initial-focus>${tx("Cancel", "Скасувати")}</button><button class="button danger full" data-action="confirm-import">${tx("Replace with backup", "Замінити резервною копією")}</button></div>`, "import-confirm-title", "alertdialog", "import-confirm-description");
  }
  return "";
}

function bottomSheet(content, labelledBy = "", requestedRole = "dialog", describedBy = "") {
  const accessibleName = labelledBy
    ? `aria-labelledby="${escapeAttr(labelledBy)}"`
    : `aria-label="${txAttr("Dialog", "Діалог")}"`;
  const accessibleDescription = describedBy ? ` aria-describedby="${escapeAttr(describedBy)}"` : "";
  const role = requestedRole === "alertdialog" ? "alertdialog" : "dialog";
  return `<div class="modal" role="${role}" aria-modal="true" ${accessibleName}${accessibleDescription}><section class="modal-panel"><div class="sheet-handle"></div><button class="icon-button sheet-close" data-action="close-modal" aria-label="${txAttr("Close dialog", "Закрити діалог")}">${svg("close")}</button>${content}</section></div>`;
}

function handleDestructiveModalKeydown(modalElement, event) {
  if (event.key === "Escape") {
    event.preventDefault();
    closeModal();
    return;
  }
  if (event.key !== "Tab") return;
  const focusable = [...modalElement.querySelectorAll(
    'button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])'
  )].filter(element => element.getAttribute?.("aria-hidden") !== "true");
  if (!focusable.length) {
    event.preventDefault();
    return;
  }
  const first = focusable[0];
  const last = focusable.at(-1);
  const active = document.activeElement;
  if (event.shiftKey && (active === first || !modalElement.contains(active))) {
    event.preventDefault();
    last.focus({ preventScroll: true });
  } else if (!event.shiftKey && (active === last || !modalElement.contains(active))) {
    event.preventDefault();
    first.focus({ preventScroll: true });
  }
}

function exerciseHistoryMarkup(exercise) {
  const history = allSets().filter(set => exercisesMatch(set, exercise)).sort((a, b) => b.session.startedAt - a.session.startedAt);
  const groups = progressHistoryGroups(history);
  const total = history.reduce((s, x) => s + Number(x.weight || 0) * Number(x.reps || 0), 0);
  return `<h2>${escapeHtml(exerciseDisplayName(exercise))}</h2><div class="metric-grid three"><div><span>${tx("Sessions", "Сесії")}</span><strong>${groups.length}</strong></div><div><span>${tx("Sets", "Підходи")}</span><strong>${history.length}</strong></div><div><span>${tx("Volume", "Обсяг")}</span><strong>${Math.round(total)}</strong></div></div>${exerciseMuscleMapCard(exercise)}${groups.length ? groupedExerciseHistory(groups) : `<div class="empty">${tx("No history for this exercise yet.", "Історії для цієї вправи ще немає.")}</div>`}`;
}

function mappingEditor(name) {
  const current = new Set(mappingFor(name));
  return `<h2>${tx("Map", "Мапінг")} "${escapeHtml(exerciseDisplayName(name))}"</h2><div class="mapping-grid">${muscles.map(([id]) => `<button class="chip buttonlike ${current.has(id) ? "selected" : ""}" data-action="toggle-map" data-id="${id}">${escapeHtml(muscleLabel(id))}</button>`).join("")}</div><button class="button full" data-action="save-map" data-name="${escapeAttr(name)}">${tx("Save", "Зберегти")}</button>`;
}

function bindEvents() {
  app.querySelectorAll("[data-route]").forEach(el => el.addEventListener("click", () => goRoot(el.dataset.route)));
  app.querySelectorAll("[data-action]").forEach(el => el.addEventListener("click", ev => {
    ev.stopPropagation();
    handleAction(el.dataset.action, el);
  }));
  const modalInitialFocus = app.querySelector("[data-modal-initial-focus]");
  if (modalInitialFocus) {
    requestAnimationFrame(() => modalInitialFocus.focus({ preventScroll: true }));
  }
  const modalElement = app.querySelector(".modal");
  if (modalElement && isDestructiveConfirmationModal()) {
    Array.from(app.children || []).forEach(element => {
      if (element !== modalElement) element.inert = true;
    });
    modalElement.addEventListener("click", event => {
      if (event.target === modalElement) closeModal();
    });
    modalElement.addEventListener("keydown", event => handleDestructiveModalKeydown(modalElement, event));
  }
  const loginName = app.querySelector("#local-login-name");
  if (loginName) loginName.addEventListener("keydown", ev => {
    if (ev.key === "Enter") loginAccount(loginName.value);
  });
  const loginPassword = app.querySelector("#login-password");
  if (loginPassword) loginPassword.addEventListener("keydown", ev => {
    if (ev.key === "Enter") remoteLogin(false);
  });
  const forgotEmail = app.querySelector("#forgot-email");
  if (forgotEmail) forgotEmail.addEventListener("keydown", ev => {
    if (ev.key === "Enter") requestPasswordReset();
  });
  const recoveryRepeat = app.querySelector("#recovery-repeat-password");
  if (recoveryRepeat) recoveryRepeat.addEventListener("keydown", ev => {
    if (ev.key === "Enter") updateRemotePassword({ required: true });
  });
  const changeRepeat = app.querySelector("#change-repeat-password");
  if (changeRepeat) changeRepeat.addEventListener("keydown", ev => {
    if (ev.key === "Enter") updateRemotePassword();
  });
  app.querySelectorAll("[data-auth-mode][data-auth-field]").forEach(input => {
    input.addEventListener("input", () => {
      const mode = input.dataset.authMode;
      const field = input.dataset.authField;
      if (authDrafts[mode] && Object.hasOwn(authDrafts[mode], field)) authDrafts[mode][field] = input.value;
    });
  });
  const pendingEmail = app.querySelector("#pending-confirmation-email");
  if (pendingEmail && pendingEmailConfirmation) {
    pendingEmail.textContent = pendingEmailConfirmation.email;
  }
  app.querySelectorAll("[data-block][data-field]").forEach(input => {
    input.addEventListener("input", () => updateDraftInput(input));
    if (input.matches("select")) {
      input.addEventListener("change", () => {
        updateDraftInput(input);
        render();
      });
    }
  });
  app.querySelectorAll("[data-draft]").forEach(input => input.addEventListener("input", () => {
    if (workoutDraft) workoutDraft[input.dataset.draft] = input.value;
  }));
  const progressSelect = app.querySelector("#progress-select");
  if (progressSelect) progressSelect.addEventListener("change", () => {
    state.progressExerciseId = Number(progressSelect.value);
    saveState();
    render();
  });
  const exerciseSearch = app.querySelector("#exercise-search");
  if (exerciseSearch) exerciseSearch.addEventListener("input", () => {
    exerciseSearchQuery = exerciseSearch.value.slice(0, 120);
    render();
    requestAnimationFrame(() => {
      const next = app.querySelector("#exercise-search");
      if (next) {
        next.focus({ preventScroll: true });
        next.setSelectionRange(next.value.length, next.value.length);
      }
    });
  });
  const scrollContainer = visibleScrollContainer();
  if (scrollContainer) {
    scrollContainer.addEventListener("scroll", syncTopbarVisibility, { passive: true });
    syncTopbarVisibility();
  }
  const exerciseMediaFile = app.querySelector("#exercise-media-file");
  if (exerciseMediaFile) {
    exerciseMediaFile.addEventListener("change", () => {
      const file = exerciseMediaFile.files?.[0];
      if (file) saveCustomExerciseMedia(file);
    });
  }
}

function syncTopbarVisibility() {
  app.classList.toggle("topbar-collapsed", (visibleScrollContainer()?.scrollTop || 0) > 24);
}

function destructiveReturnFocus(action, element = null) {
  if (!["delete-exercise", "delete-set", "import-json"].includes(action)) return null;
  const target = { action };
  const id = Number(element?.dataset?.id);
  const sessionId = Number(element?.dataset?.session);
  if (Number.isSafeInteger(id) && id > 0) target.id = id;
  if (Number.isSafeInteger(sessionId) && sessionId > 0) target.sessionId = sessionId;
  return target;
}

function restoreDestructiveFocus(target) {
  if (!target || !["delete-exercise", "delete-set", "import-json"].includes(target.action)) return;
  requestAnimationFrame(() => {
    const candidate = [...app.querySelectorAll(`[data-action="${target.action}"]`)].find(element => {
      const idMatches = target.id == null || Number(element.dataset.id) === target.id;
      const sessionMatches = target.sessionId == null || Number(element.dataset.session) === target.sessionId;
      return idMatches && sessionMatches;
    });
    candidate?.focus({ preventScroll: true });
  });
}

function focusStableScreenContext() {
  requestAnimationFrame(() => {
    const main = visibleScrollContainer() || app.querySelector("main");
    const target = main?.querySelector?.("h2") || main;
    if (!target) return;
    if (!target.hasAttribute?.("tabindex")) target.setAttribute?.("tabindex", "-1");
    target.focus({ preventScroll: true });
  });
}

function handleAction(action, el) {
  if (action === "auth-mode") {
    authMode = ["login", "signup", "forgot"].includes(el.dataset.mode) ? el.dataset.mode : "login";
    authNotice = null;
    return render();
  }
  if (action === "remote-login") return remoteLogin(false);
  if (action === "remote-signup") return remoteLogin(true);
  if (action === "request-password-reset") return requestPasswordReset();
  if (action === "complete-password-recovery") return updateRemotePassword({ required: true });
  if (action === "change-password") { modal = { type: "change-password" }; return render(); }
  if (action === "submit-password-change") return updateRemotePassword();
  if (action === "remote-resend-confirmation") return resendRemoteConfirmation();
  if (action === "confirmation-change-address") return changePendingConfirmationAddress();
  if (action === "confirmation-back-to-login") return returnToLoginFromConfirmation();
  if (action === "retry-cloud-activation") return retryPendingRemoteActivation();
  if (action === "login-account") return loginAccount(el.dataset.name || app.querySelector("#local-login-name")?.value);
  if (action === "export-cloud-recovery") return exportCloudRecovery();
  if (action === "reset-cloud-recovery") return resetCloudRecovery();
  if (action === "export-sync-conflict-local") return exportSyncConflictLocal();
  if (action === "resolve-sync-conflict-local") return resolveSyncConflictWithLocal();
  if (action === "resolve-sync-conflict-cloud") return resolveSyncConflictWithCloud();
  if (action === "logout-account") return logoutAccount();
  if (action === "delete-account") return activeAccount?.remote ? deleteCloudAccount() : deleteLocalAccount();
  if (action === "unpair-garmin") return unpairGarmin();
  if (action === "refresh-leaderboard") return refreshLeaderboard(true);
  if (action === "back") return back();
  if (action === "language-menu") { languageMenuOpen = !languageMenuOpen; return render(); }
  if (action === "set-theme") {
    const theme = el.dataset.theme;
    if (!["system", "light", "dark"].includes(theme)) return;
    window.GymThemePreference?.setPreference?.(theme);
    return render();
  }
  if (action === "set-language") {
    const language = el.dataset.language;
    if (!["en", "uk", "ru"].includes(language)) return;
    state.language = language;
    languageMenuOpen = false;
    saveState();
    return render();
  }
  if (action === "backup") { modal = { type: "backup-json", diagnostics: false, json: exportPayload(false) }; return render(); }
  if (action === "open-add") return push("add");
  if (action === "open-detail") return push("detail", { id: Number(el.dataset.id) });
  if (action === "delete-session") return deleteSession(Number(el.dataset.id));
  if (action === "finish-workout") return push("summary", { id: Number(el.dataset.id) });
  if (action === "summary-view") { nav = [{ name: "workouts" }, { name: "detail", id: Number(el.dataset.id) }]; replaceNavigationHistory(); return render(); }
  if (action === "summary-done") return goRoot("workouts");
  if (action === "open-ranks") return push("ranks");
  if (action === "mission-period") {
    const period = el.dataset.period;
    if (!["daily", "weekly", "monthly"].includes(period)) return;
    missionPeriod = period;
    return render();
  }
  if (action === "month-prev") { monthOffsets[activeMonthScope()]--; return render(); }
  if (action === "month-next") { monthOffsets[activeMonthScope()]++; return render(); }
  if (action === "month-current") { monthOffsets[activeMonthScope()] = 0; return render(); }
  if (action === "clear-exercise-search") { exerciseSearchQuery = ""; return render(); }
  if (action === "exercise-favorites-filter") { exerciseFavoritesOnly = !exerciseFavoritesOnly; return render(); }
  if (action === "exercise-body-filter") { exerciseBodyFilter = ["all", "upper", "lower", "core"].includes(el.dataset.filter) ? el.dataset.filter : "all"; return render(); }
  if (action === "exercise-muscle-filter") { exerciseMuscleFilter = el.dataset.filter === "all" || muscles.some(([id]) => id === el.dataset.filter) ? el.dataset.filter : "all"; return render(); }
  if (action === "exercise-sort") { exerciseSortMode = ["name", "most", "least"].includes(el.dataset.sort) ? el.dataset.sort : "name"; return render(); }
  if (action === "open-exercise-add") { modal = { type: "add-exercise" }; return render(); }
  if (action === "overview-mode") {
    overviewMode = el.dataset.mode === "list" ? "list" : "overview";
    render();
    requestAnimationFrame(() => {
      const scroller = visibleScrollContainer();
      const target = overviewMode === "list" ? document.querySelector("#workout-list-section") : document.querySelector(".solo-progress-hero");
      if (scroller && target) {
        const top = target.getBoundingClientRect().top - scroller.getBoundingClientRect().top + scroller.scrollTop - 10;
        scroller.scrollTo({ top: Math.max(0, top), behavior: "smooth" });
      }
    });
    return;
  }
  if (action === "muscle-period") { musclePeriod = el.dataset.period; return render(); }
  if (action === "select-muscle") { selectedMuscle = el.dataset.id; return render(); }
  if (action === "map-exercise") { modal = { type: "map", name: el.dataset.name }; return render(); }
  if (action === "toggle-map") { el.classList.toggle("selected"); return; }
  if (action === "save-map") return saveMapping(el.dataset.name);
  if (action === "profile") return updateProfile(el);
  if (action === "note-template") return applyNoteTemplate(el.dataset.note);
  if (action === "generate-smart") return generateSmartWorkout();
  if (action === "repeat-latest") { workoutDraft = createDraft([...state.sessions].sort((a, b) => b.startedAt - a.startedAt)[0]); return render(); }
  if (action === "template-picker") { modal = { type: "template" }; return render(); }
  if (action === "copy-template") { workoutDraft = createDraft(state.sessions.find(s => s.id === Number(el.dataset.id))); modal = null; nav = [{ name: "workouts" }, { name: "add" }]; replaceNavigationHistory(); return render(); }
  if (action === "open-exercise-media") {
    const block = workoutDraft?.blocks[Number(el.dataset.block)];
    const exercise = block?.exerciseName ? state.exercises.find(item => exercisesMatch(item, block)) || block : null;
    if (!exercise) return;
    modal = { type: "exercise-media", exercise };
    return render();
  }
  if (action === "remove-exercise-media") {
    if (!modal?.exercise) return;
    try {
      localStorage.removeItem(customExerciseMediaStorageKey(modal.exercise));
    } catch {
      return showToast(tx("The custom image could not be removed.", "Не вдалося видалити власне фото."));
    }
    return render();
  }
  if (action === "add-block") {
    if (!workoutDraft) return;
    if (workoutDraft.blocks.length >= window.GymStateContract.LIMITS.exercisesPerSession) {
      return showToast(tx("This workout has reached the exercise limit.", "Досягнуто ліміт вправ у тренуванні."));
    }
    workoutDraft.blocks.unshift({ exerciseName: "", sets: [{ weight: "", reps: "" }] });
    return render();
  }
  if (action === "remove-block") {
    if (!workoutDraft) return;
    if (workoutDraft.blocks.length > 1) workoutDraft.blocks.splice(Number(el.dataset.block), 1);
    else workoutDraft.blocks[0] = { exerciseName: "", sets: [{ weight: "", reps: "" }] };
    return render();
  }
  if (action === "add-set") {
    const sets = workoutDraft?.blocks[Number(el.dataset.block)]?.sets;
    if (!sets) return;
    if (sets.length >= window.GymStateContract.LIMITS.setsPerExercise) {
      return showToast(tx("This exercise has reached the set limit.", "Досягнуто ліміт підходів для вправи."));
    }
    sets.push({ weight: "", reps: "" });
    return render();
  }
  if (action === "copy-set" || action === "plus-set") { copyDraftSet(Number(el.dataset.block), action === "plus-set"); return render(); }
  if (action === "remove-set") {
    const sets = workoutDraft?.blocks[Number(el.dataset.block)]?.sets;
    if (!sets) return;
    if (sets.length > 1) sets.splice(Number(el.dataset.set), 1);
    else sets[0] = { weight: "", reps: "" };
    return render();
  }
  if (action === "apply-last") return applyLast(Number(el.dataset.block));
  if (action === "apply-smart") return applySmart(Number(el.dataset.block));
  if (action === "sync-watch") {
    return queueGarminPlanFromDraft().catch(error => showToast(friendlyOperationError(
      error,
      "Garmin sync failed. Check your connection and try again.",
      "Не вдалося синхронізувати Garmin. Перевір з’єднання та спробуй ще раз."
    )));
  }
  if (action === "save-workout") return saveWorkout();
  if (action === "quick-add-exercise") return quickAddExercise();
  if (action === "detail-add-set") return detailAddSet(Number(el.dataset.session), el.dataset.name);
  if (action === "edit-set") return openEditSet(Number(el.dataset.id));
  if (action === "apply-edit-set") return applyEditSet(Number(el.dataset.id));
  if (action === "delete-set") return deleteSet(
    Number(el.dataset.id),
    Number(el.dataset.session),
    destructiveReturnFocus("delete-set", el)
  );
  if (action === "confirm-delete-set") return confirmDeleteSet();
  if (action === "timer") { state.timers ||= {}; state.timers[el.dataset.key] = Date.now() + Number(el.dataset.seconds) * 1000; saveState(); return render(); }
  if (action === "timer-stop") { delete state.timers?.[el.dataset.key]; saveState(); return render(); }
  if (action === "save-exercise") return saveExercise();
  if (action === "toggle-exercise-favorite") return toggleExerciseFavorite(Number(el.dataset.id));
  if (action === "rename-exercise") { modal = { type: "rename", exercise: state.exercises.find(ex => ex.id === Number(el.dataset.id)) }; return render(); }
  if (action === "apply-rename") return applyRename(Number(el.dataset.id));
  if (action === "delete-exercise") return deleteExercise(
    Number(el.dataset.id),
    destructiveReturnFocus("delete-exercise", el)
  );
  if (action === "confirm-delete-exercise") return confirmDeleteExercise();
  if (action === "exercise-history") { modal = { type: "history", exercise: state.exercises.find(ex => ex.id === Number(el.dataset.id)) }; return render(); }
  if (action === "export-json") { modal = { type: "backup-json", diagnostics: false, json: exportPayload(false) }; return render(); }
  if (action === "export-diagnostics") { modal = { type: "backup-json", diagnostics: true, json: exportPayload(true) }; return render(); }
  if (action === "import-json") { modal = { type: "import" }; return render(); }
  if (action === "apply-import") return applyImport(destructiveReturnFocus("import-json"));
  if (action === "confirm-import") return confirmImport();
  if (action === "cancel-destructive") return closeModal();
  if (action === "copy-json") return copyExportJson();
  if (action === "download-json") return downloadJson(modal.json, modal.diagnostics);
  if (action === "pdf-report") return printReport();
  if (action === "close-modal") return closeModal();
}

function isDestructiveConfirmationModal(value = modal) {
  return ["confirm-delete-exercise", "confirm-delete-set", "confirm-import"].includes(value?.type);
}

function closeModal() {
  const focusTarget = isDestructiveConfirmationModal() ? modal?.intent?.returnFocus : null;
  modal = null;
  render();
  restoreDestructiveFocus(focusTarget);
}

function updateDraftInput(input) {
  const block = workoutDraft?.blocks[Number(input.dataset.block)];
  if (!block) return;
  if (input.dataset.set === undefined) {
    block[input.dataset.field] = input.value;
    if (input.dataset.field === "exerciseName") {
      const selected = state.exercises.find(exercise => exercise.name === input.value);
      const catalogKey = persistedExerciseCatalogKey(selected);
      if (catalogKey) block.catalogKey = catalogKey;
      else delete block.catalogKey;
    }
  } else block.sets[Number(input.dataset.set)][input.dataset.field] = input.value;
}

function updateProfile(el) {
  const field = el.dataset.field;
  const value = el.dataset.value;
  if (field === "days") {
    const days = Number.parseInt(value, 10);
    if (!Number.isInteger(days) || days < 2 || days > 6) return;
    state.profile.days = days;
  } else {
    const allowed = window.GymStateContract.PROFILE_ENUMS[field];
    if (!allowed?.includes(value)) return;
    state.profile[field] = value;
  }
  saveState();
  render();
}

function applyNoteTemplate(note) {
  if (!workoutDraft) return;
  const current = workoutDraft.note.trim();
  workoutDraft.note = current ? current.includes(note) ? current : `${current} | ${note}` : note;
  render();
}

function generateSmartWorkout() {
  const plan = buildSmartWorkoutPlan();
  if (!workoutDraft) return;
  workoutDraft.blocks = plan.exercises.map(({ name, catalogKey, recommendation }) => ({
    exerciseName: name,
    ...(catalogKey ? { catalogKey } : {}),
    sets: recommendation.sets.map(set => ({ weight: set.weight ?? "", reps: set.reps }))
  }));
  showToast(`${tx("Smart workout generated", "Розумне тренування згенеровано")}: ${plan.focus} ${plan.variant}.`);
  render();
}

function buildSmartWorkoutPlan() {
  const history = smartUsableHistory();
  const focus = chooseWorkoutFocus(history);
  const variant = smartWorkoutVariant(focus, history);
  const targetExerciseCount = smartTargetExerciseCount(focus);
  const historyByExercise = new Map();
  history.forEach(set => {
    const key = exerciseMatchKey(set);
    const items = historyByExercise.get(key) || [];
    items.push(set);
    historyByExercise.set(key, items);
  });
  const recentSessionIds = recentWorkoutSessionIds(history, 3);
  const targetMuscles = targetMusclesForFocus(focus);
  const candidates = state.exercises.map(exercise => {
    const analysis = analyzeSmartExercise(exercise);
    const exerciseHistory = historyByExercise.get(analysis.identityKey) || [];
    const latest = exerciseHistory.reduce((max, set) => Math.max(max, set.session.startedAt), 0);
    const daysSince = latest ? daysBetween(latest, Date.now()) : 90;
    const sessionCount = new Set(exerciseHistory.map(set => set.session.id)).size;
    const recentExercisePenalty = new Set(exerciseHistory.filter(set => recentSessionIds.has(set.session.id)).map(set => set.session.id)).size * 16;
    const sameWeekExercisePenalty = exerciseHistory.some(set => daysBetween(set.session.startedAt, Date.now()) <= 6) ? 55 : 0;
    const focusScore = focus === "FullBody" ? 44 : isCandidateForFocus(analysis, focus) ? 86 : analysis.category === "FullBody" ? 32 : -60;
    const muscleMatchScore = analysis.muscles.filter(muscle => targetMuscles.has(muscle)).length * 9;
    const noveltyScore = sessionCount === 0 ? 12 : 0;
    const dueScore = Math.min(daysSince, 28) * 1.25;
    const confidenceScore = Math.min(sessionCount, 4) * 2;
    return {
      exercise,
      analysis,
      score: focusScore + muscleMatchScore + noveltyScore + dueScore + confidenceScore +
        smartVariantPreferenceScore(analysis, focus, variant) - recentExercisePenalty - sameWeekExercisePenalty
    };
  });
  const selected = selectBalancedSmartExercises(candidates, focus, targetMuscles, targetExerciseCount, history, variant);
  return {
    focus,
    variant,
    exercises: selected.map(candidate => ({
      name: candidate.exercise.name,
      ...(persistedExerciseCatalogKey(candidate.exercise) ? { catalogKey: persistedExerciseCatalogKey(candidate.exercise) } : {}),
      recommendation: smartRecommendation(candidate.exercise)
    }))
  };
}

function smartTargetExerciseCount(focus) {
  const days = Number(state.profile.days);
  let target = focus === "FullBody" ? 6 : 5;
  if (days <= 2) target += 1;
  if (days >= 5) target -= 1;
  return clamp(target, 4, 7);
}

function smartWorkoutVariant(focus, history) {
  const sessions = sessionGroupsByDate(history);
  const relevantCount = focus === "FullBody"
    ? sessions.length
    : sessions.filter(session => smartSessionMatchesFocus(session, focus)).length;
  const variants = focus === "FullBody" ? ["A", "B", "C"] : ["A", "B"];
  return variants[relevantCount % variants.length];
}

function smartSessionMatchesFocus(session, focus) {
  const sessionFocus = dominantSmartFocus(session.sets);
  if (focus === "Upper") return isUpperFocus(sessionFocus);
  if (focus === "Lower" || focus === "Legs") return isLowerFocus(sessionFocus);
  if (focus === "Push") return sessionFocus === "Push";
  if (focus === "Pull") return sessionFocus === "Pull";
  return sessionFocus === focus;
}

function smartVariantPreferenceScore(analysis, focus, variant) {
  const preferredPatterns = smartVariantPatterns(focus, variant);
  const patternBonus = patternMatchCount({ analysis }, preferredPatterns) * 18;
  const variants = focus === "FullBody" ? ["A", "B", "C"] : ["A", "B"];
  const bucketBonus = smartStableBucket(analysis.identityKey, variants.length) === variants.indexOf(variant) ? 10 : 0;
  return patternBonus + bucketBonus;
}

function smartVariantPatterns(focus, variant) {
  if (focus === "FullBody") {
    if (variant === "A") return new Set(["HorizontalPress", "HorizontalPull", "Squat", "LegPress"]);
    if (variant === "B") return new Set(["VerticalPress", "VerticalPull", "Hinge", "KneeFlexion"]);
    return new Set(["Accessory", "Core", "KneeExtension", "Calf"]);
  }
  if (focus === "Lower" || focus === "Legs") {
    return variant === "A" ? new Set(["Squat", "LegPress"]) : new Set(["Hinge", "KneeFlexion"]);
  }
  if (focus === "Push") return variant === "A" ? new Set(["HorizontalPress"]) : new Set(["VerticalPress"]);
  if (focus === "Pull") return variant === "A" ? new Set(["HorizontalPull"]) : new Set(["VerticalPull"]);
  return variant === "A"
    ? new Set(["HorizontalPress", "HorizontalPull"])
    : new Set(["VerticalPress", "VerticalPull"]);
}

function smartStableBucket(identity, modulus) {
  let hash = 0;
  for (const character of String(identity || "")) {
    hash = (Math.imul(hash, 31) + character.codePointAt(0)) >>> 0;
  }
  return modulus > 0 ? hash % modulus : 0;
}

function chooseWorkoutFocus(history = smartUsableHistory()) {
  if (!history.length) {
    if (state.profile.split === "Upper / Lower") return "Upper";
    if (state.profile.split === "Push Pull Legs") return "Push";
    return "FullBody";
  }
  const sessions = sessionGroupsByDate(history);
  const latest = sessions[0]?.sets || [];
  const latestFocus = dominantSmartFocus(latest);
  if (state.profile.split === "Upper / Lower") {
    const thisWeekSessions = sessions.filter(session => daysBetween(session.date, Date.now()) <= 6);
    const latestWeekFocus = thisWeekSessions[0]?.sets ? dominantSmartFocus(thisWeekSessions[0].sets) : latestFocus;
    if (isLowerFocus(latestWeekFocus)) return "Upper";
    if (isUpperFocus(latestWeekFocus)) return "Lower";
    const upperCount = thisWeekSessions.filter(session => isUpperFocus(dominantSmartFocus(session.sets))).length;
    const lowerCount = thisWeekSessions.filter(session => isLowerFocus(dominantSmartFocus(session.sets))).length;
    return lowerCount < upperCount ? "Lower" : "Upper";
  }
  if (state.profile.split === "Push Pull Legs") {
    if (latestFocus === "Push") return "Pull";
    if (latestFocus === "Pull") return "Legs";
    if (latestFocus === "Legs" || latestFocus === "Lower") return "Push";
    return chooseMostNeglectedFocus(history);
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

function isCandidateForFocus(candidate, workoutFocus) {
  const candidateFocus = typeof candidate === "string" ? candidate : candidate.category;
  const muscles = typeof candidate === "string" ? [] : candidate.muscles;
  if (workoutFocus === "Upper") return ["Push", "Pull"].includes(candidateFocus);
  if (workoutFocus === "Lower" || workoutFocus === "Legs") return candidateFocus === "Legs" || muscles.some(muscle => smartCoreMuscles.has(muscle));
  if (workoutFocus === "Push") return candidateFocus === "Push";
  if (workoutFocus === "Pull") return candidateFocus === "Pull";
  return true;
}

function chooseMostNeglectedFocus(history) {
  const focuses = ["Push", "Pull", "Legs", "FullBody"];
  const latestByFocus = Object.fromEntries(focuses.map(focus => [focus, 0]));
  history.forEach(set => {
    const focus = analyzeSmartExercise(set).category;
    latestByFocus[focus] = Math.max(latestByFocus[focus] || 0, set.session.startedAt);
  });
  return focuses.sort((a, b) => latestByFocus[a] - latestByFocus[b])[0] || "FullBody";
}

const smartPushMuscles = new Set(["chest", "shoulders", "triceps"]);
const smartPullMuscles = new Set(["lats", "upperBack", "biceps", "forearms"]);
const smartLowerMuscles = new Set(["quads", "hamstrings", "glutes", "calves", "adductors", "lowerBack"]);
const smartCoreMuscles = new Set(["abs", "obliques"]);

function analyzeSmartExercise(exercise) {
  const definition = builtInExerciseFor(exercise);
  const analysisName = definition?.names.en || exerciseRawName(exercise);
  const normalized = normalizeExerciseName(analysisName);
  const has = (...tokens) => tokens.some(token => normalized.includes(token));
  const muscles = new Set(contributionFor(exercise).map(item => item.muscleId));
  const patterns = new Set();
  const addPattern = (...items) => items.forEach(item => patterns.add(item));

  if (has("жим ног", "жим ногами", "leg press")) addPattern("LegPress");
  if (has("прис", "присед", "squat", "випади", "выпады", "lunge")) addPattern("Squat");
  if (has("румун", "станов", "становая", "deadlift", "hip thrust", "місток", "мостик")) addPattern("Hinge");
  if (has("згинання ніг", "згибання ніг", "сгибание ног", "leg curl")) addPattern("KneeFlexion");
  if (has("розгинання ніг", "разгибание ног", "leg extension")) addPattern("KneeExtension");
  if (has("підйом на носки", "подъем на носки", "икры", "calf")) addPattern("Calf");
  if (has("bench", "жим леж", "віджим", "отжим", "dips")) addPattern("HorizontalPress");
  if (has("shoulder press", "overhead", "над голов", "плеч")) addPattern("VerticalPress");
  if (has("row", "тяга") && !has("румун", "станов", "становая", "deadlift", "підборід", "подбород")) addPattern("HorizontalPull");
  if (has("pull up", "pullup", "pulldown", "підтяг", "подтяг", "верхній блок", "верхний блок")) addPattern("VerticalPull");
  if (has("прес", "abs", "crunch", "планка", "plank", "leg raise")) addPattern("Core");
  if (!patterns.size) addPattern("Accessory");

  const fallback = classifyExercise(analysisName);
  const category = [...muscles].some(muscle => smartLowerMuscles.has(muscle))
    ? "Legs"
    : [...muscles].some(muscle => smartPullMuscles.has(muscle)) && ![...muscles].some(muscle => smartPushMuscles.has(muscle))
      ? "Pull"
      : [...muscles].some(muscle => smartPushMuscles.has(muscle))
        ? "Push"
        : [...muscles].some(muscle => smartCoreMuscles.has(muscle))
          ? "FullBody"
          : fallback;

  return { identityKey: exerciseMatchKey(exercise), category, muscles: [...muscles], patterns };
}

function selectBalancedSmartExercises(candidates, focus, targetMuscles, targetExerciseCount, history, variant) {
  const selected = [];
  const coveredMuscles = new Set();
  const lastTrained = lastTrainedBySmartMuscle(history);
  let remaining = candidates.filter(candidate => isCandidateForFocus(candidate.analysis, focus));
  if (!remaining.length && focus !== "Lower" && focus !== "Legs") remaining = [...candidates];

  const takeBestPattern = patterns => {
    const best = remaining
      .filter(candidate => [...candidate.analysis.patterns].some(pattern => patterns.has(pattern)))
      .sort((a, b) => (b.score + patternMatchCount(b, patterns) * 35) - (a.score + patternMatchCount(a, patterns) * 35) || a.exercise.name.localeCompare(b.exercise.name))[0];
    if (!best) return;
    selected.push(best);
    best.analysis.muscles.forEach(muscle => coveredMuscles.add(muscle));
    remaining = remaining.filter(candidate => candidate.exercise.id !== best.exercise.id);
  };

  if (focus === "Lower" || focus === "Legs") {
    takeBestPattern(smartVariantPatterns(focus, variant));
    takeBestPattern(variant === "A" ? new Set(["Hinge", "KneeFlexion"]) : new Set(["Squat", "LegPress"]));
  }

  if (focus === "Upper" || focus === "Push" || focus === "Pull") {
    takeBestPattern(smartVariantPatterns(focus, variant));
  }

  if (focus === "FullBody") {
    ["Push", "Pull", "Legs"].forEach(requiredFocus => {
      const best = remaining
        .filter(candidate => candidate.analysis.category === requiredFocus)
        .sort((a, b) => b.score - a.score || a.exercise.name.localeCompare(b.exercise.name))[0];
      if (!best) return;
      selected.push(best);
      best.analysis.muscles.forEach(muscle => coveredMuscles.add(muscle));
      remaining = remaining.filter(candidate => candidate.exercise.id !== best.exercise.id);
    });
  }

  while (selected.length < targetExerciseCount && remaining.length) {
    const best = remaining
      .map(candidate => ({
        candidate,
        score: balancedSmartScore(candidate, coveredMuscles, targetMuscles, lastTrained)
      }))
      .sort((a, b) => b.score - a.score || a.candidate.exercise.name.localeCompare(b.candidate.exercise.name))[0].candidate;
    selected.push(best);
    best.analysis.muscles.forEach(muscle => coveredMuscles.add(muscle));
    remaining = remaining.filter(candidate => candidate.exercise.id !== best.exercise.id);
  }

  return selected.slice(0, targetExerciseCount);
}

function patternMatchCount(candidate, patterns) {
  return [...candidate.analysis.patterns].filter(pattern => patterns.has(pattern)).length;
}

function balancedSmartScore(candidate, coveredMuscles, targetMuscles, lastTrained) {
  const newTargetMuscles = candidate.analysis.muscles.filter(muscle => targetMuscles.has(muscle) && !coveredMuscles.has(muscle)).length;
  const targetOverlap = candidate.analysis.muscles.filter(muscle => targetMuscles.has(muscle)).length;
  const fatiguePenalty = candidate.analysis.muscles.reduce((sum, muscle) => {
    const lastDate = lastTrained.get(muscle);
    if (!lastDate) return sum;
    const days = daysBetween(lastDate, Date.now());
    return sum + (days === 0 ? 28 : days === 1 ? 18 : days === 2 ? 8 : 0);
  }, 0);
  const duplicateCoveragePenalty = candidate.analysis.muscles.length && candidate.analysis.muscles.every(muscle => coveredMuscles.has(muscle)) ? 10 : 0;
  return candidate.score + newTargetMuscles * 24 + targetOverlap * 4 - fatiguePenalty - duplicateCoveragePenalty;
}

function targetMusclesForFocus(focus) {
  if (focus === "Upper") return new Set([...smartPushMuscles, ...smartPullMuscles]);
  if (focus === "Lower" || focus === "Legs") return new Set([...smartLowerMuscles, ...smartCoreMuscles]);
  if (focus === "Push") return smartPushMuscles;
  if (focus === "Pull") return smartPullMuscles;
  return new Set([...smartPushMuscles, ...smartPullMuscles, ...smartLowerMuscles, ...smartCoreMuscles]);
}

function recentWorkoutSessionIds(history, limit) {
  return new Set(sessionGroupsByDate(history).slice(0, limit).map(session => session.id));
}

function sessionGroupsByDate(history) {
  const groups = new Map();
  history.forEach(set => {
    const group = groups.get(set.session.id) || { id: set.session.id, date: set.session.startedAt, sets: [] };
    group.date = Math.max(group.date, set.session.startedAt);
    group.sets.push(set);
    groups.set(set.session.id, group);
  });
  return [...groups.values()].sort((a, b) => b.date - a.date);
}

function dominantSmartFocus(sets) {
  const counts = sets.reduce((acc, set) => {
    const focus = analyzeSmartExercise(set).category;
    acc[focus] = (acc[focus] || 0) + 1;
    return acc;
  }, {});
  const lowerCount = (counts.Legs || 0) + (counts.Lower || 0);
  const upperCount = (counts.Push || 0) + (counts.Pull || 0) + (counts.Upper || 0);
  if (lowerCount > upperCount) return "Lower";
  if (upperCount > lowerCount) return (counts.Push || 0) >= (counts.Pull || 0) ? "Push" : "Pull";
  return "FullBody";
}

function isUpperFocus(focus) {
  return ["Upper", "Push", "Pull"].includes(focus);
}

function isLowerFocus(focus) {
  return ["Lower", "Legs"].includes(focus);
}

function lastTrainedBySmartMuscle(history) {
  const result = new Map();
  history.forEach(set => {
    analyzeSmartExercise(set).muscles.forEach(muscle => {
      result.set(muscle, Math.max(result.get(muscle) || 0, set.session.startedAt));
    });
  });
  return result;
}

function shouldPrioritizeHeavyLower(history) {
  const latestLower = sessionGroupsByDate(history).find(session => isLowerFocus(dominantSmartFocus(session.sets)));
  if (!latestLower) return true;
  const patterns = new Set(latestLower.sets.flatMap(set => [...analyzeSmartExercise(set).patterns]));
  return !patterns.has("Squat") && !patterns.has("LegPress") && !patterns.has("Hinge");
}

function copyDraftSet(blockIndex, plus) {
  const block = workoutDraft?.blocks[blockIndex];
  if (!block) return;
  if (block.sets.length >= window.GymStateContract.LIMITS.setsPerExercise) {
    showToast(tx("This exercise has reached the set limit.", "Досягнуто ліміт підходів для вправи."));
    return;
  }
  const last = block.sets.at(-1) || { weight: "", reps: "" };
  const weight = Number(String(last.weight).replace(",", "."));
  const nextWeight = Number.isFinite(weight) ? weight + (plus ? 2.5 : 0) : last.weight;
  block.sets.push({
    weight: typeof nextWeight === "number" && nextWeight <= window.GymStateContract.LIMITS.weightMax
      ? nextWeight
      : last.weight,
    reps: last.reps
  });
}

function applyLast(blockIndex) {
  const block = workoutDraft?.blocks[blockIndex];
  if (!block) return;
  const weight = lastWeightFor(block.exerciseName);
  if (weight == null) return;
  block.sets = block.sets.map(set => ({ ...set, weight }));
  render();
}

function applySmart(blockIndex) {
  const block = workoutDraft?.blocks[blockIndex];
  if (!block) return;
  block.sets = smartRecommendation(block).sets.map(set => ({ weight: set.weight ?? "", reps: set.reps }));
  render();
}

function saveWorkout() {
  const draft = workoutDraft;
  if (!draft) return;
  const limits = window.GymStateContract.LIMITS;
  if (!Array.isArray(draft.blocks) || draft.blocks.length > limits.exercisesPerSession ||
      state.sessions.length >= limits.sessions) {
    return showToast(tx("This workout exceeds the supported size.", "Тренування перевищує допустимий розмір."));
  }
  const parsedBlocks = [];
  const perExerciseCounts = new Map();
  for (const block of draft.blocks) {
    const exerciseName = String(block?.exerciseName || "").trim();
    if (!exerciseName) continue;
    if (!isSupportedExerciseName(exerciseName) || !Array.isArray(block.sets) ||
        block.sets.length < 1 || block.sets.length > limits.setsPerExercise) {
      return showToast(tx("An exercise or its set list is invalid.", "Вправа або список її підходів некоректні."));
    }
    const parsedSets = [];
    for (const set of block.sets) {
      const weightText = String(set?.weight ?? "").replace(",", ".").trim();
      const repsText = String(set?.reps ?? "").trim();
      const weight = Number(weightText);
      const reps = Number(repsText);
      if (!weightText || !repsText || !Number.isFinite(weight) || weight < 0 ||
          weight > limits.weightMax || !Number.isInteger(reps) || reps < 1 || reps > limits.repsMax) {
        return showToast(tx("Enter a valid weight and whole-number reps for every set.", "Введи коректну вагу й цілу кількість повторів для кожного підходу."));
      }
      parsedSets.push({ weight, reps });
    }
    const exerciseKey = normalizeExerciseName(exerciseName);
    const nextCount = (perExerciseCounts.get(exerciseKey) || 0) + parsedSets.length;
    if (nextCount > limits.setsPerExercise) {
      return showToast(tx("One exercise exceeds the set limit.", "Одна вправа перевищує ліміт підходів."));
    }
    perExerciseCounts.set(exerciseKey, nextCount);
    parsedBlocks.push({ block, exerciseName, sets: parsedSets });
  }
  const incomingSetCount = parsedBlocks.reduce((sum, block) => sum + block.sets.length, 0);
  if (!incomingSetCount || incomingSetCount > limits.exercisesPerSession * limits.setsPerExercise ||
      allSets().length + incomingSetCount > limits.totalSets) {
    return showToast(tx("Please fill every selected set within the workout limits.", "Заповни всі вибрані підходи в межах лімітів тренування."));
  }
  const startedAt = draft.startedAt ?? Date.now();
  if (!Number.isSafeInteger(startedAt) || startedAt < limits.timestampMin || startedAt > limits.timestampMax) {
    return showToast(tx("Workout date is invalid.", "Дата тренування некоректна."));
  }
  const note = String(draft.note || "").slice(0, 2000);
  const originalExercises = state.exercises;
  state.exercises = [...state.exercises];
  const sets = [];
  for (const parsedBlock of parsedBlocks) {
    const { block, exerciseName } = parsedBlock;
    const requestedExercise = { name: exerciseName, ...(persistedExerciseCatalogKey(block) ? { catalogKey: persistedExerciseCatalogKey(block) } : {}) };
    const storedExercise = ensureExercise(requestedExercise);
    if (!storedExercise) {
      state.exercises = originalExercises;
      return showToast(tx("The exercise catalog has reached its limit.", "Каталог вправ досяг ліміту."));
    }
    const storedName = storedExercise.name;
    const catalogKey = persistedExerciseCatalogKey(storedExercise);
    parsedBlock.sets.forEach((set, index) => {
      sets.push({
        id: uid(),
        exerciseName: storedName,
        ...(catalogKey ? { catalogKey } : {}),
        weight: set.weight,
        reps: set.reps,
        orderIndex: index
      });
    });
  }
  const id = uid();
  state.sessions.push({ id, startedAt, note, sets });
  try {
    saveState();
  } catch {
    state.sessions.pop();
    state.exercises = originalExercises;
    return showToast(tx("Workout data failed the safety checks.", "Дані тренування не пройшли перевірку безпеки."));
  }
  workoutDraft = null;
  modal = null;
  nav = [{ name: "workouts" }, { name: "summary", id }];
  replaceNavigationHistory();
  render();
  routeScrollPositions.delete("add:root");
}

function quickAddExercise() {
  const session = state.sessions.find(s => s.id === route().id);
  const ex = state.exercises.find(e => e.id === Number(document.querySelector("#quick-add")?.value));
  if (!session || !ex) return;
  const limits = window.GymStateContract.LIMITS;
  const existingCount = session.sets.filter(set => exercisesMatch(set, ex)).length;
  if (existingCount >= limits.setsPerExercise || session.sets.length >= limits.exercisesPerSession * limits.setsPerExercise ||
      allSets().length >= limits.totalSets) {
    return showToast(tx("This workout has reached its set limit.", "Тренування досягло ліміту підходів."));
  }
  const catalogKey = persistedExerciseCatalogKey(ex);
  session.sets.push({ id: uid(), exerciseName: ex.name, ...(catalogKey ? { catalogKey } : {}), weight: 0, reps: 8, orderIndex: 0 });
  saveState();
  render();
}

function detailAddSet(sessionId, name) {
  const session = state.sessions.find(s => s.id === sessionId);
  if (!session) return;
  const limits = window.GymStateContract.LIMITS;
  if (!isSupportedExerciseName(name) ||
      session.sets.filter(set => normalizeExerciseName(set.exerciseName) === normalizeExerciseName(name)).length >= limits.setsPerExercise ||
      session.sets.length >= limits.exercisesPerSession * limits.setsPerExercise || allSets().length >= limits.totalSets) {
    return showToast(tx("This exercise has reached its set limit.", "Вправа досягла ліміту підходів."));
  }
  const last = session.sets.filter(s => s.exerciseName === name).at(-1) || allSets().filter(s => s.exerciseName === name).at(-1);
  const exercise = last || state.exercises.find(item => item.name === name);
  const catalogKey = persistedExerciseCatalogKey(exercise);
  session.sets.push({ id: uid(), exerciseName: name, ...(catalogKey ? { catalogKey } : {}), weight: last?.weight || 0, reps: last?.reps || 8, orderIndex: session.sets.filter(s => s.exerciseName === name).length });
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
  const reps = Number(String(document.querySelector("#edit-reps").value).trim());
  const limits = window.GymStateContract.LIMITS;
  if (!Number.isFinite(weight) || weight < 0 || weight > limits.weightMax ||
      !Number.isInteger(reps) || reps < 1 || reps > limits.repsMax) {
    return showToast(tx("Enter valid reps and optional weight.", "Введи коректні повтори й вагу."));
  }
  set.weight = weight;
  set.reps = reps;
  saveState();
  modal = null;
  render();
}

function destructiveAccountIdentity(account = activeAccount) {
  const normalized = normalizeStoredAccount(account);
  if (!normalized) return null;
  return normalized.remote === "supabase"
    ? `supabase:${normalized.userId}`
    : `local:${normalized.id}`;
}

function destructiveImpactFingerprint(value) {
  try {
    const encoded = JSON.stringify(value);
    if (typeof encoded !== "string") return null;
    const bytes = new TextEncoder().encode(encoded);
    const mask = 0xffffffffffffffffn;
    const prime = 0x100000001b3n;
    let forward = 0xcbf29ce484222325n;
    let reverse = 0x84222325cbf29ce4n;
    for (let index = 0; index < bytes.length; index += 1) {
      forward = ((forward ^ BigInt(bytes[index])) * prime) & mask;
      reverse = ((reverse ^ BigInt(bytes[bytes.length - index - 1])) * prime) & mask;
    }
    return `${bytes.length.toString(16)}:${forward.toString(16).padStart(16, "0")}:${reverse.toString(16).padStart(16, "0")}`;
  } catch {
    return null;
  }
}

function destructiveStateFingerprint(sourceState = state) {
  try {
    const normalized = validateImportedEnvelope({ schemaVersion: 2, ...sourceState }, defaultAppState()).state;
    return destructiveImpactFingerprint(normalized);
  } catch {
    return null;
  }
}

function destructiveStorageSnapshot(stateFingerprint) {
  try {
    const storageKey = activeStorageKey();
    const storedState = localStorage.getItem(storageKey);
    if (storedState == null) return null;
    const normalizedStoredState = validateImportedEnvelope(storedState, defaultAppState()).state;
    if (destructiveImpactFingerprint(normalizedStoredState) !== stateFingerprint) return null;
    return {
      storageKey,
      storedStateFingerprint: destructiveImpactFingerprint(storedState),
      authMarkerFingerprint: destructiveImpactFingerprint(localStorage.getItem(AUTH_KEY))
    };
  } catch {
    return null;
  }
}

function destructiveStorageSnapshotIsCurrent(snapshot) {
  if (!snapshot || snapshot.storageKey !== activeStorageKey()) return false;
  try {
    return destructiveImpactFingerprint(localStorage.getItem(snapshot.storageKey)) === snapshot.storedStateFingerprint &&
      destructiveImpactFingerprint(localStorage.getItem(AUTH_KEY)) === snapshot.authMarkerFingerprint;
  } catch {
    return false;
  }
}

function destructiveIntent(details) {
  const accountIdentity = destructiveAccountIdentity();
  const stateFingerprint = destructiveStateFingerprint();
  const storageSnapshot = stateFingerprint ? destructiveStorageSnapshot(stateFingerprint) : null;
  if (!accountIdentity || !stateFingerprint || !storageSnapshot) return null;
  return { ...details, accountEpoch, accountIdentity, stateFingerprint, storageSnapshot };
}

function destructiveIntentIsCurrent(intent) {
  return Boolean(intent && intent.accountEpoch === accountEpoch &&
    intent.accountIdentity === destructiveAccountIdentity() &&
    intent.stateFingerprint === destructiveStateFingerprint() &&
    destructiveStorageSnapshotIsCurrent(intent.storageSnapshot));
}

function destructiveStorageRecord(key) {
  try {
    return { key, value: localStorage.getItem(key) };
  } catch {
    return null;
  }
}

function restoreDestructiveStorageRecord(record) {
  if (!record) return false;
  try {
    if (record.value == null) localStorage.removeItem(record.key);
    else localStorage.setItem(record.key, record.value);
    return localStorage.getItem(record.key) === record.value;
  } catch {
    return false;
  }
}

function persistDestructiveState(expectedSnapshot) {
  if (!destructiveStorageSnapshotIsCurrent(expectedSnapshot)) {
    throw new Error("Destructive confirmation storage snapshot is stale.");
  }
  const keys = [];
  if (activeAccount?.remote === "supabase" && UUID_PATTERN.test(activeAccount.userId || "")) {
    keys.push(syncBaselineKey(activeAccount.userId));
  }
  keys.push(activeStorageKey());
  const snapshots = keys.map(destructiveStorageRecord);
  if (snapshots.some(snapshot => !snapshot)) throw new Error("Destructive persistence could not be prepared.");
  if (!destructiveStorageSnapshotIsCurrent(expectedSnapshot)) {
    throw new Error("Destructive confirmation storage snapshot changed before persistence.");
  }
  try {
    saveState();
  } catch (error) {
    const restored = [...snapshots].reverse().map(restoreDestructiveStorageRecord).every(Boolean);
    if (!restored) throw new Error("Destructive persistence rollback failed.");
    throw error;
  }
}

function rejectStaleDestructiveConfirmation() {
  closeModal();
  showToast(tx(
    "This confirmation is no longer current. Nothing was changed.",
    "Це підтвердження вже неактуальне. Нічого не змінено."
  ));
}

function showDestructiveSaveFailure() {
  closeModal();
  showToast(tx(
    "The change could not be completed safely. Reload this account before making more changes.",
    "Не вдалося безпечно завершити зміну. Перезавантаж цей акаунт перед подальшими змінами."
  ));
}

function setLocation(id, sessionId) {
  if (!Number.isSafeInteger(id) || id <= 0 || !Number.isSafeInteger(sessionId) || sessionId <= 0) return null;
  const matches = [];
  for (const session of state.sessions) {
    if (session.id !== sessionId) continue;
    session.sets.forEach((set, index) => {
      if (set.id === id) matches.push({ session, set, index });
    });
  }
  return matches.length === 1 ? matches[0] : null;
}

function deleteSet(id, sessionId, returnFocus = null) {
  const location = setLocation(id, sessionId);
  if (!location) return rejectStaleDestructiveConfirmation();
  const impactFingerprint = destructiveImpactFingerprint(location.session);
  const intent = destructiveIntent({
    setId: id,
    sessionId,
    impactFingerprint,
    returnFocus,
    preview: {
      exerciseName: exerciseDisplayName(location.set),
      detail: `${fmtDate(location.session.startedAt)} · ${tx("Set", "Підхід")} ${location.index + 1} · ${formatLocalizedSetWeight(location.set.weight)} × ${location.set.reps}`
    }
  });
  if (!intent || !impactFingerprint) return showDestructiveSaveFailure();
  modal = { type: "confirm-delete-set", intent };
  render();
}

function confirmDeleteSet() {
  const intent = modal?.type === "confirm-delete-set" ? modal.intent : null;
  const location = intent ? setLocation(intent.setId, intent.sessionId) : null;
  if (!destructiveIntentIsCurrent(intent) || !location ||
      location.session.id !== intent.sessionId ||
      destructiveImpactFingerprint(location.session) !== intent.impactFingerprint) {
    return rejectStaleDestructiveConfirmation();
  }
  const previousSets = location.session.sets;
  location.session.sets = previousSets.filter(set => set.id !== intent.setId);
  if (location.session.sets.length !== previousSets.length - 1) {
    location.session.sets = previousSets;
    return rejectStaleDestructiveConfirmation();
  }
  try {
    persistDestructiveState(intent.storageSnapshot);
  } catch {
    location.session.sets = previousSets;
    return showDestructiveSaveFailure();
  }
  try {
    localStorage.removeItem(customExerciseMediaStorageKey(exercise));
  } catch {
    // The catalog deletion is authoritative even when optional device-local media cleanup fails.
  }
  modal = null;
  render();
  focusStableScreenContext();
  showToast(tx("Set deleted.", "Підхід видалено."));
}

function deleteSession(id) {
  const matches = state.sessions.filter(session => session.id === id);
  if (matches.length !== 1) return showToast(tx(
    "This confirmation is no longer current. Nothing was changed.",
    "Це підтвердження вже неактуальне. Нічого не змінено."
  ));
  const session = matches[0];
  if (!window.confirm(tx(`Delete workout from ${fmtDate(session.startedAt)}?`, `Видалити тренування від ${fmtDate(session.startedAt)}?`))) return;
  state.sessions = state.sessions.filter(item => item.id !== id);
  saveState();
  modal = null;
  if (route().name === "detail" || route().name === "summary") {
    nav = [{ name: "workouts" }];
    replaceNavigationHistory();
  }
  showToast(tx("Workout deleted.", "Тренування видалено."));
  render();
}

function findSet(id) {
  return state.sessions.flatMap(s => s.sets).find(s => s.id === id);
}

function isSupportedExerciseName(value) {
  const name = typeof value === "string" ? value.trim() : "";
  const limits = window.GymStateContract.LIMITS;
  return Boolean(name && name.length <= limits.exerciseName &&
    new TextEncoder().encode(name).byteLength <= limits.exerciseNameBytes);
}

function saveExercise() {
  const name = document.querySelector("#new-exercise-name")?.value.trim();
  if (!name) return showToast(tx("Enter exercise name.", "Введи назву вправи."));
  if (!isSupportedExerciseName(name)) return showToast(tx("Exercise name is too long.", "Назва вправи надто довга."));
  if (!ensureExercise(name)) return showToast(tx("The exercise catalog has reached its limit.", "Каталог вправ досяг ліміту."));
  saveState();
  modal = null;
  render();
}

function ensureExercise(name) {
  const rawName = exerciseRawName(name);
  if (!isSupportedExerciseName(rawName)) return null;
  const requestedCatalogKey = persistedExerciseCatalogKey(name);
  const keyedMatch = requestedCatalogKey ? state.exercises.find(exercise => exercisesMatch(exercise, name)) : null;
  if (keyedMatch) return keyedMatch;
  const exact = state.exercises.find(exercise => normalizeExerciseKey(exercise.name) === normalizeExerciseKey(rawName));
  if (exact) return exact;
  const catalogKey = requestedCatalogKey || exerciseCatalogKey(rawName);
  if (catalogKey) {
    const catalogMatch = state.exercises.find(exercise => exerciseCatalogKey(exercise) === catalogKey);
    if (catalogMatch) return catalogMatch;
  }
  const canonicalName = requestedCatalogKey ? rawName : catalogKey ? builtInExerciseByKey.get(catalogKey).names.en : rawName;
  const candidate = { name: canonicalName, ...(catalogKey ? { catalogKey } : {}) };
  const existing = state.exercises.find(exercise => exercisesMatch(exercise, candidate));
  if (existing) return existing;
  if (state.exercises.length >= window.GymStateContract.LIMITS.exercises) return null;
  const created = { id: uid(), ...candidate };
  state.exercises.push(created);
  state.exercises.sort((left, right) => exerciseDisplayName(left).localeCompare(exerciseDisplayName(right), state.language));
  return created;
}

function applyRename(id) {
  const exercise = state.exercises.find(ex => ex.id === id);
  const submittedName = document.querySelector("#rename-name")?.value.trim();
  if (!exercise || !submittedName) return;
  if (!isSupportedExerciseName(submittedName)) return showToast(tx("Exercise name is too long.", "Назва вправи надто довга."));
  const old = exercise.name;
  const oldReference = { name: old, ...(persistedExerciseCatalogKey(exercise) ? { catalogKey: persistedExerciseCatalogKey(exercise) } : {}) };
  const unchangedLocalizedValue = submittedName === exerciseDisplayName(exercise);
  if (unchangedLocalizedValue) {
    modal = null;
    render();
    return;
  }
  const nextCatalogKey = exerciseCatalogKey(submittedName);
  const nextName = nextCatalogKey ? builtInExerciseByKey.get(nextCatalogKey).names.en : submittedName;
  const candidate = { name: nextName, ...(nextCatalogKey ? { catalogKey: nextCatalogKey } : {}) };
  const duplicate = state.exercises.some(item => item.id !== id && (
    exercisesMatch(item, candidate) ||
    normalizeExerciseKey(item.name) === normalizeExerciseKey(nextName) ||
    (nextCatalogKey && exerciseCatalogKey(item) === nextCatalogKey)
  ));
  if (duplicate) return showToast(tx("An exercise with this name already exists.", "Вправа з такою назвою вже існує."));
  exercise.name = nextName;
  if (nextCatalogKey) exercise.catalogKey = nextCatalogKey;
  else delete exercise.catalogKey;
  state.sessions.forEach(session => session.sets.forEach(set => {
    if (!exercisesMatch(set, oldReference)) return;
    set.exerciseName = nextName;
    if (nextCatalogKey) set.catalogKey = nextCatalogKey;
    else delete set.catalogKey;
  }));
  const oldMappingKey = normalizeExerciseName(old);
  const nextMappingKey = normalizeExerciseName(nextName);
  state.mappings[nextMappingKey] = state.mappings[oldMappingKey] || state.mappings[nextMappingKey] || [];
  if (oldMappingKey !== nextMappingKey) delete state.mappings[oldMappingKey];
  saveState();
  modal = null;
  render();
}

function exerciseLocation(id) {
  if (!Number.isSafeInteger(id) || id <= 0) return null;
  const matches = state.exercises.filter(exercise => exercise.id === id);
  return matches.length === 1 ? matches[0] : null;
}

function deleteExercise(id, returnFocus = null) {
  if (!Number.isSafeInteger(id) || id <= 0) return;
  const exercise = exerciseLocation(id);
  if (!exercise) return rejectStaleDestructiveConfirmation();
  if (state.sessions.some(session => session.sets.some(set => exercisesMatch(set, exercise)))) {
    return showToast(tx("Exercise is used in workouts.", "Вправа використовується у тренуваннях."));
  }
  const impactFingerprint = destructiveImpactFingerprint(exercise);
  const intent = destructiveIntent({
    exerciseId: id,
    impactFingerprint,
    returnFocus,
    preview: { name: exerciseDisplayName(exercise) }
  });
  if (!intent || !impactFingerprint) return showDestructiveSaveFailure();
  modal = { type: "confirm-delete-exercise", intent };
  render();
}

function confirmDeleteExercise() {
  const intent = modal?.type === "confirm-delete-exercise" ? modal.intent : null;
  const exercise = intent ? exerciseLocation(intent.exerciseId) : null;
  const isUsed = exercise && state.sessions.some(session =>
    session.sets.some(set => exercisesMatch(set, exercise))
  );
  if (!destructiveIntentIsCurrent(intent) || !exercise || isUsed ||
      destructiveImpactFingerprint(exercise) !== intent.impactFingerprint) {
    return rejectStaleDestructiveConfirmation();
  }
  const previousExercises = state.exercises;
  state.exercises = previousExercises.filter(item => item.id !== intent.exerciseId);
  if (state.exercises.length !== previousExercises.length - 1) {
    state.exercises = previousExercises;
    return rejectStaleDestructiveConfirmation();
  }
  try {
    persistDestructiveState(intent.storageSnapshot);
  } catch {
    state.exercises = previousExercises;
    return showDestructiveSaveFailure();
  }
  modal = null;
  render();
  focusStableScreenContext();
  showToast(tx("Exercise deleted.", "Вправу видалено."));
}

function saveMapping(name) {
  const ids = [...document.querySelectorAll(".mapping-grid .selected")].map(el => el.dataset.id);
  state.mappings[normalizeExerciseName(name)] = ids;
  saveState();
  modal = null;
  render();
}

function exportSessionExercises(session) {
  const groups = [];
  const byIdentity = new Map();
  const rawNamesWithSets = new Set();
  (session.sets || []).forEach(set => {
    const name = exerciseRawName(set);
    if (!name) return;
    rawNamesWithSets.add(normalizeExerciseKey(name));
    const identity = exerciseMatchKey(set);
    let group = byIdentity.get(identity);
    if (!group) {
      const catalogKey = persistedExerciseCatalogKey(set);
      group = { name, ...(catalogKey ? { catalogKey } : {}), sets: [] };
      byIdentity.set(identity, group);
      groups.push(group);
    }
    group.sets.push(set);
  });
  (session.exerciseNames || []).forEach(rawName => {
    const name = exerciseRawName(rawName);
    const identity = exerciseMatchKey(name);
    if (!name || rawNamesWithSets.has(normalizeExerciseKey(name)) || byIdentity.has(identity)) return;
    const group = { name, sets: [] };
    byIdentity.set(identity, group);
    groups.push(group);
  });
  return groups;
}

function exportPayload(diagnostics) {
  if (diagnostics) {
    return JSON.stringify({
      schemaVersion: 2,
      exportedAt: Date.now(),
      app: "GymApp",
      source: "gym-pwa-diagnostics",
      diagnostics: true,
      summary: {
        exerciseCount: state.exercises.length,
        sessionCount: state.sessions.length,
        setCount: allSets().length
      },
      environment: {
        client: "pwa",
        cloudConfigured: remoteAuthEnabled(),
        accountMode: activeAccount?.remote ? "cloud" : "local"
      }
    }, null, 2);
  }
  const payload = {
    schemaVersion: 2,
    exportedAt: Date.now(),
    app: "GymApp",
    source: "gym-pwa",
    diagnostics: false,
    owner: {
      accountId: activeAccount?.id || null,
      userId: activeAccount?.userId || null,
      email: activeAccount?.email || null,
      remote: activeAccount?.remote || null
    },
    catalogSeedVersion: state.catalogSeedVersion,
    exercises: state.exercises,
    sessions: state.sessions.map(session => ({
      id: session.id,
      date: session.startedAt,
      startedAt: session.startedAt,
      note: session.note,
      exercises: exportSessionExercises(session),
      sets: session.sets
    })),
    exerciseCatalog: state.exercises.map(ex => ex.name),
    mappings: state.mappings,
    profile: state.profile
  };
  return JSON.stringify(payload, null, 2);
}

function importAllowed(owner) {
  if (!activeAccount?.remote) {
    return !owner?.accountId || owner.accountId === activeAccount?.id;
  }
  return Boolean(owner?.userId && owner.userId === activeAccount.userId);
}

function importedStateIdsAreUnique(candidate) {
  if (!candidate || !Array.isArray(candidate.exercises) || !Array.isArray(candidate.sessions)) return false;
  const uniquePositiveIds = values => {
    const ids = values.map(Number);
    return ids.every(id => Number.isSafeInteger(id) && id > 0) && new Set(ids).size === ids.length;
  };
  return uniquePositiveIds(candidate.exercises.map(exercise => exercise.id)) &&
    uniquePositiveIds(candidate.sessions.map(session => session.id)) &&
    uniquePositiveIds(candidate.sessions.flatMap(session => session.sets.map(set => set.id)));
}

function applyImport(returnFocus = null) {
  try {
    const raw = document.querySelector("#import-json").value;
    const imported = validateImportedEnvelope(raw, state);
    if (imported.diagnostics) {
      showToast(tx("A redacted diagnostics report is not a restorable backup.", "Знеособлений звіт діагностики не є резервною копією."));
      return;
    }
    if (!importAllowed(imported.owner)) {
      showToast(tx("This backup belongs to another account.", "Ця резервна копія належить іншому акаунту."));
      return;
    }
    const nextState = imported.state;
    ensureBuiltInExerciseCatalog(nextState);
    preserveExerciseFavorites(nextState, state);
    if (!importedStateIdsAreUnique(nextState)) throw new Error("Backup IDs are ambiguous.");
    const currentStateFingerprint = destructiveImpactFingerprint(state);
    const nextStateFingerprint = destructiveImpactFingerprint(nextState);
    const ownerFingerprint = destructiveImpactFingerprint(imported.owner);
    const intent = destructiveIntent({
      currentStateFingerprint,
      nextStateFingerprint,
      ownerFingerprint,
      owner: imported.owner,
      nextState,
      returnFocus,
      preview: {
        exerciseCount: nextState.exercises.length,
        sessionCount: nextState.sessions.length,
        setCount: allSetsFromSessions(nextState.sessions).length
      }
    });
    if (!currentStateFingerprint || !nextStateFingerprint || !ownerFingerprint) {
      throw new Error("Import confirmation could not be prepared.");
    }
    if (!intent) return showDestructiveSaveFailure();
    modal = { type: "confirm-import", intent };
    render();
  } catch {
    showToast(tx("Invalid backup.", "Некоректна резервна копія."));
  }
}

function confirmImport() {
  const intent = modal?.type === "confirm-import" ? modal.intent : null;
  if (!destructiveIntentIsCurrent(intent) ||
      destructiveImpactFingerprint(state) !== intent?.currentStateFingerprint ||
      destructiveImpactFingerprint(intent?.nextState) !== intent?.nextStateFingerprint ||
      destructiveImpactFingerprint(intent?.owner) !== intent?.ownerFingerprint ||
      !importedStateIdsAreUnique(intent?.nextState) ||
      !importAllowed(intent?.owner)) {
    return rejectStaleDestructiveConfirmation();
  }
  try {
    window.GymStateContract.validateAndNormalize({ schemaVersion: 2, ...intent.nextState }, {
      fallback: defaultAppState()
    });
  } catch {
    return rejectStaleDestructiveConfirmation();
  }
  const previousState = state;
  state = intent.nextState;
  try {
    persistDestructiveState(intent.storageSnapshot);
  } catch {
    state = previousState;
    return showDestructiveSaveFailure();
  }
  modal = null;
  goRoot("workouts");
  focusStableScreenContext();
  showToast(tx("Backup imported.", "Резервну копію імпортовано."));
}

async function copyExportJson() {
  if (!modal?.json || !navigator.clipboard?.writeText) {
    return showToast(tx("Clipboard access is unavailable.", "Доступ до буфера обміну недоступний."));
  }
  if (!modal.diagnostics) {
    const warning = tx(
      "This full backup contains private workout history and account metadata. Copy it to the system clipboard? Other apps may be able to read it.",
      "Повна резервна копія містить приватну історію тренувань і дані акаунта. Скопіювати її в системний буфер? Інші програми можуть мати до неї доступ."
    );
    if (typeof window.confirm !== "function" || !window.confirm(warning)) return;
  }
  try {
    await navigator.clipboard.writeText(modal.json);
    showToast(tx("JSON copied.", "JSON скопійовано."));
  } catch {
    showToast(tx("Clipboard write failed.", "Не вдалося записати в буфер обміну."));
  }
}

function downloadJson(json, diagnostics = false) {
  const blob = new Blob([json], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `gym-${diagnostics ? "diagnostics" : "backup"}-${new Date().toISOString().slice(0, 10)}.json`;
  a.click();
  URL.revokeObjectURL(url);
}

function printReport() {
  if (!modal?.json) return;
  if (!modal.diagnostics) {
    const warning = tx(
      "This report will include the full private backup. Continue to the print dialog?",
      "Звіт міститиме повну приватну резервну копію. Перейти до діалогу друку?"
    );
    if (typeof window.confirm !== "function" || !window.confirm(warning)) return;
  }
  const win = window.open("", "_blank");
  if (!win) return showToast(tx("The report window was blocked.", "Вікно звіту заблоковано."));
  win.opener = null;
  const data = JSON.parse(modal.json);
  const document = win.document;
  document.title = "GymApp diagnostics";
  document.head.replaceChildren();
  const add = (tag, text) => {
    const element = document.createElement(tag);
    element.textContent = text;
    document.body.append(element);
  };
  const exerciseCount = data.summary?.exerciseCount ?? (Array.isArray(data.exercises) ? data.exercises.length : 0);
  const sessionCount = data.summary?.sessionCount ?? (Array.isArray(data.sessions) ? data.sessions.length : 0);
  const setCount = data.summary?.setCount ?? allSets().length;
  document.body.replaceChildren();
  add("h1", modal.diagnostics ? "GymApp redacted diagnostics report" : "GymApp private backup report");
  add("p", `Exported: ${new Date(data.exportedAt).toLocaleString()}`);
  add("h2", "Summary");
  add("p", `Exercises: ${exerciseCount}`);
  add("p", `Workouts: ${sessionCount}`);
  add("p", `Sets: ${setCount}`);
  add("h2", "Raw JSON");
  add("pre", modal.json);
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

function percentageClass(value) {
  const numeric = Number(value);
  const bounded = Number.isFinite(numeric) ? clamp(numeric, 0, 100) : 0;
  return `percentage-${Math.round(bounded / 5) * 5}`;
}

function heatLevelClass(value) {
  const numeric = Number(value);
  const bounded = Number.isFinite(numeric) ? clamp(numeric, 0, 1) : 0;
  return `heat-level-${Math.round(bounded * 10)}`;
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
    timerInterval = setInterval(updateTimerDisplays, 1000);
  }
}

function updateTimerDisplays() {
  let hasActiveTimer = false;
  document.querySelectorAll("[data-timer-display]").forEach(display => {
    const key = display.dataset.timerDisplay;
    const remaining = timerRemaining(key);
    hasActiveTimer ||= remaining > 0;
    display.textContent = remaining > 0 ? formatTimer(remaining) : tx("Ready", "Готово");
    const stopButton = document.querySelector(`[data-timer-stop="${CSS.escape(key)}"]`);
    if (stopButton) stopButton.disabled = remaining <= 0;
  });
  if (!hasActiveTimer) clearInterval(timerInterval);
}

function formatTimer(seconds) {
  return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
}

function barRow(label, value, max, detail) {
  return `<div class="bar-row"><span>${escapeHtml(label)}</span><div class="bar-track"><div class="bar-fill ${percentageClass(value / max * 100)}"></div></div><span class="muted">${escapeHtml(detail)}</span></div>`;
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
  window.addEventListener("load", () => navigator.serviceWorker.register("./sw.js", {
    updateViaCache: "none"
  }).catch(() => {}));
}

window.addEventListener("storage", event => {
  if (!isDestructiveConfirmationModal()) return;
  const snapshot = modal?.intent?.storageSnapshot;
  if (!snapshot || (event.key !== null && event.key !== snapshot.storageKey && event.key !== AUTH_KEY)) return;
  if (!destructiveStorageSnapshotIsCurrent(snapshot)) rejectStaleDestructiveConfirmation();
});

window.addEventListener("popstate", event => {
  const restoredNav = validatedHistoryNav(event.state?.gymAppNav);
  if (!restoredNav) return;
  const leavingAdd = route().name === "add" && restoredNav.at(-1)?.name !== "add";
  if (leavingAdd) workoutDraft = null;
  nav = restoredNav;
  modal = null;
  languageMenuOpen = false;
  render();
  if (leavingAdd) routeScrollPositions.delete("add:root");
});

if (!handleEmailConfirmationRedirect()) {
  replaceNavigationHistory();
  render();
  const startupSync = loadRemoteSession()?.activation_pending
    ? retryPendingRemoteActivation().then(() => false)
    : pullRemoteState();
  startupSync
    .then(updated => {
      if (updated) render();
    })
    .catch(error => {
      if (!transitionToReauthentication(error)) {
        showToast(tx("Cloud sync failed.", "Синхронізація не вдалася."));
      }
    });
}
