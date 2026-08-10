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
const CLOUD_ACCOUNT_DELETION_JOURNAL_KEY = "gym-pwa-cloud-account-deletion-v1";
const SYNC_BASELINE_PREFIX = "gym-pwa-sync-baseline-v1:";
const EXERCISE_REST_TIMER_PREFIX = "gym-pwa-exercise-rest-timers-v1:";
const ACTIVE_WORKOUT_PREFIX = "gym-pwa-active-workout-v1:";
const ACTIVE_WORKOUT_RECOVERY_PREFIX = "gym-pwa-active-workout-recovery-v1:";
const ACTIVE_WORKOUT_COMMIT_PREFIX = "gym-pwa-active-workout-commits-v1:";
const ACTIVE_WORKOUT_UNDO_PREFIX = "gym-pwa-active-workout-undo-v1:";
const ACTIVE_WORKOUT_TIMING_PREFIX = "gym-pwa-active-workout-timing-v1:";
const ACTIVE_WORKOUT_REST_TRANSITION_PREFIX = "gym-pwa-active-workout-rest-transition-v1:";
const ACTIVE_WORKOUT_BULK_CLEANUP_PREFIX = "gym-pwa-active-workout-bulk-cleanup-v1:";
const ACTIVE_WORKOUT_LOCK_PREFIX = "gym-pwa-active-workout-lock-v1:";
const LIVE_WORKOUT_BINDING_PREFIX = "gym-pwa-live-workout-v1:";
const WEB_PUSH_INSTALLATION_KEY = "gym-pwa-web-push-installation-v1";
const WEB_PUSH_ENABLED_KEY = "gym-pwa-web-push-enabled-v1";
const WEB_PUSH_BINDING_DB_NAME = "gymapp-push-binding-v1";
const WEB_PUSH_BINDING_DB_VERSION = 1;
const WEB_PUSH_BINDING_STORE_NAME = "current-bindings";
const WEB_PUSH_BINDING_RECORD_KEY = "current";
const WEB_PUSH_BINDING_TRANSITION_KEY = "transition";
const LEGACY_GARMIN_DEVICE_TOKEN_KEY = "gym-pwa-garmin-device-token-v1";
const GARMIN_DEVICE_BINDINGS_KEY = "gym-pwa-garmin-device-bindings-v2";
const GARMIN_CREATE_REQUESTS_KEY = "gym-pwa-garmin-create-requests-v1";
const GARMIN_PENDING_REVOCATIONS_KEY = "gym-pwa-garmin-pending-revocations-v1";
const GARMIN_ENQUEUE_REQUESTS_KEY = "gym-pwa-garmin-enqueue-requests-v1";
const PUBLIC_SITE_URL = "https://gymapptracker.com/";
const SHARED_WORKOUT_URL = `${PUBLIC_SITE_URL}workout/`;
const SHARED_WORKOUT_PENDING_KEY = "gym-pwa-pending-shared-workout-v1";
const SUPPORT_URL = "https://gymapptracker.com/support.html";
const PRIVACY_URL = "https://gymapptracker.com/privacy-policy.html";
const AUTH_REDIRECT_URL = "https://gymapptracker.com/confirmed.html?platform=web";
const ANDROID_APP_PACKAGE = "com.setforge.gymapp";
const GOOGLE_PLAY_APP_URL = `https://play.google.com/store/apps/details?id=${ANDROID_APP_PACKAGE}`;
const GARMIN_STORE_APP_URL = "https://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f";
const CONNECT_IQ_ANDROID_PACKAGE = "com.garmin.connectiq";
const CONNECT_IQ_GOOGLE_PLAY_URL = `https://play.google.com/store/apps/details?id=${CONNECT_IQ_ANDROID_PACKAGE}`;
const GARMIN_STORE_ANDROID_INTENT_URL = `intent://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f#Intent;scheme=https;package=${CONNECT_IQ_ANDROID_PACKAGE};S.browser_fallback_url=${encodeURIComponent(CONNECT_IQ_GOOGLE_PLAY_URL)};end`;
const MAX_REMOTE_RESPONSE_BYTES = 8 * 1024 * 1024;
const MAX_REMOTE_AUTH_RESPONSE_BYTES = 64 * 1024;
const MAX_REMOTE_ERROR_RESPONSE_BYTES = 8 * 1024;
const MAX_SOCIAL_RESPONSE_BYTES = 256 * 1024;
const MAX_LIVE_RESPONSE_BYTES = 256 * 1024;
const MAX_PENDING_SOCIAL_WORKOUT_REQUESTS = 25;
const MAX_PENDING_LIVE_REQUESTS = 25;
const SOCIAL_REFRESH_MIN_INTERVAL_MS = 30 * 1000;
const LIVE_POLL_ACTIVE_MS = 3000;
const LIVE_POLL_LOBBY_MS = 10000;
const LIVE_POLL_REALTIME_FALLBACK_MS = 30000;
const LIVE_LOCAL_INTENT_RECOVERY_MS = 5 * 60 * 1000;
const MAX_REMOTE_RESPONSE_CHUNKS = 4096;
const MAX_LOCAL_ACCOUNT_STORAGE_BYTES = 64 * 1024;
const MAX_AUTH_TRANSACTION_STORAGE_BYTES = 4 * 1024;
const MAX_CLOUD_ACCOUNT_DELETION_JOURNAL_BYTES = 2 * 1024;
const AUTH_TRANSACTION_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const MAX_SYNC_BASELINE_STORAGE_BYTES = 2 * 1024;
const MAX_CLOUD_EXTENSION_NAMESPACES = 32;
const MAX_CLOUD_EXTENSION_NAMESPACE_LENGTH = 64;
const MAX_EXERCISE_REST_TIMER_STORAGE_BYTES = 64 * 1024;
const MAX_EXERCISE_REST_TIMERS = 100;
const MAX_EXERCISE_REST_TIMER_MS = 24 * 60 * 60 * 1000;
const MAX_ACTIVE_WORKOUT_STORAGE_BYTES = 2 * 1024 * 1024;
const MAX_ACTIVE_WORKOUT_COMMIT_STORAGE_BYTES = 8 * 1024 * 1024;
const MAX_ACTIVE_WORKOUT_UNDO_STORAGE_BYTES = 1024;
const MAX_ACTIVE_WORKOUT_TIMING_STORAGE_BYTES = 1024;
const MAX_ACTIVE_WORKOUT_REST_TRANSITION_STORAGE_BYTES = 2048;
const MAX_ACTIVE_WORKOUT_BULK_CLEANUP_STORAGE_BYTES = MAX_ACTIVE_WORKOUT_STORAGE_BYTES * 2 + 4096;
const MAX_ACTIVE_WORKOUT_REST_MS = 30 * 60 * 1000;
const ACTIVE_WORKOUT_LOCK_WAIT_MS = 1500;
const MAX_ACTIVE_WORKOUT_NOTE_LENGTH = 2000;
const MAX_ACTIVE_WORKOUT_NOTE_BYTES = 8000;
const ACTIVE_WORKOUT_VERSION = 1;
const MAX_LOCAL_ACCOUNTS = 20;
const MAX_ACCOUNT_NAME_LENGTH = 64;
const LOCAL_ACCOUNT_ID_VERSION = 2;
const LOCAL_ACCOUNT_ID_PATTERN = /^local-v2-[a-f0-9]{32}$/;
const MAX_GARMIN_BINDING_STORAGE_BYTES = 64 * 1024;
const MAX_GARMIN_BINDINGS = 20;
const MAX_GARMIN_CREATE_STORAGE_BYTES = 16 * 1024;
const MAX_GARMIN_CREATE_REQUESTS = 4;
const GARMIN_CREATE_REQUEST_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const MAX_GARMIN_PENDING_REVOCATION_STORAGE_BYTES = 8 * 1024;
const MAX_GARMIN_PENDING_REVOCATIONS = 4;
const MAX_GARMIN_ENQUEUE_STORAGE_BYTES = 512 * 1024;
const MAX_GARMIN_ENQUEUE_REQUESTS = 4;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SOCIAL_PROFILE_ID_PATTERN = /^p_[0-9a-f]{32}$/;
const SOCIAL_FRIENDSHIP_ID_PATTERN = /^f_[0-9a-f]{32}$/;
const SOCIAL_WORKOUT_INVITE_ID_PATTERN = /^wi_[0-9a-f]{32}$/;
const SOCIAL_DAY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
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
  send: "M2 3l20 9-20 9 4-9-4-9zm4.8 8h8.7L5.2 6.4 6.8 11zm0 2-1.6 4.6L15.5 13H6.8z",
  share: "M18 16c-.8 0-1.5.3-2 .8L8.9 12.7c.1-.2.1-.5.1-.7s0-.5-.1-.7l7-4.1c.6.5 1.3.8 2.1.8 1.7 0 3-1.3 3-3s-1.3-3-3-3-3 1.3-3 3c0 .2 0 .5.1.7l-7 4.1C7.5 9.3 6.8 9 6 9c-1.7 0-3 1.3-3 3s1.3 3 3 3c.8 0 1.5-.3 2-.8l7.1 4.1c-.1.2-.1.4-.1.7 0 1.7 1.3 3 3 3s3-1.3 3-3-1.3-3-3-3z",
  save: "M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2zM7 21v-8h10v8M7 3v5h8",
  search: "M21 21l-4.35-4.35M19 11a8 8 0 1 1-16 0 8 8 0 0 1 16 0z",
  showChart: "M3.5 18.49l6-6.01 4 4L22 6.92l-1.41-1.41-7.09 7.97-4-4L2 16.99z",
  timer: "M10 2h4M12 14l4-4M5 5l2 2m10-2-2 2M12 22a8 8 0 1 0 0-16 8 8 0 0 0 0 16z",
  trophy: "M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0zM5 5H3v2a4 4 0 0 0 4 4M19 5h2v2a4 4 0 0 1-4 4",
  upload: "M12 21V9m0 0 5 5m-5-5-5 5M4 3h16",
  watch: "M9 2h6l1 3h2v14h-2l-1 3H9l-1-3H6V5h2l1-3zm-1 5v10h8V7H8zm4 2a3 3 0 1 1 0 6 3 3 0 0 1 0-6z",
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
    addWorkout: "Add Workout", finishWorkout: "Finish Workout", saveWorkout: "Save Workout", saveCompletedWorkout: "Save as completed workout", repeatLast: "Repeat Last Workout",
    copyWorkout: "Copy Previous Workout", overview: "Overview", workoutList: "Workout list", current: "Current",
    soloProgress: "Solo Progress", monthlySnapshot: "Monthly Snapshot", heatmap: "Activity Heatmap", muscleMap: "Muscle Map",
    recommendations: "Recommendations", achievements: "Achievements", noWorkouts: "No workouts in this month.",
    note: "Note", trainingProfile: "Training Profile", smartCoach: "Smart Coach", generateSmart: "Generate Smart Workout",
    syncWatch: "Sync Plan to Watch", addExercise: "Add Exercise", addSet: "Add Set", addPlannedSet: "Add planned set", logSetAndRest: "Log set · rest 90 s", copyLast: "Copy Last Set",
    copyPlus: "Copy Last +2.5 kg", useLast: "Use Last Weight", applySmart: "Apply Smart Plan", templatePicker: "Copy a previous workout",
    exerciseName: "Exercise name", backup: "Backup and diagnostics", exportJson: "Export JSON", importJson: "Import JSON",
    diagnostics: "Export redacted diagnostics", sharePdf: "Share PDF report", rename: "Rename Exercise", history: "History",
    workoutComplete: "Workout complete", impact: "Workout impact", personalRecords: "Personal records", levelProgress: "Level progress",
    momentum: "Momentum", daily: "Daily Missions", weekly: "Weekly Missions", monthly: "Monthly Missions", viewRanks: "View ranks"
  },
  uk: {
    workouts: "Тренування", missions: "Місії", exercises: "Вправи", progress: "Прогрес", ranks: "Ранги",
    addWorkout: "Додати тренування", finishWorkout: "Завершити", saveWorkout: "Зберегти тренування", saveCompletedWorkout: "Зберегти як виконане тренування", repeatLast: "Повторити останнє тренування",
    copyWorkout: "Скопіювати попереднє тренування", overview: "Огляд", workoutList: "Список тренувань", current: "Поточний",
    soloProgress: "Особистий прогрес", monthlySnapshot: "Підсумок місяця", heatmap: "Карта активності", muscleMap: "Карта м'язів",
    recommendations: "Рекомендації", achievements: "Досягнення", noWorkouts: "Немає тренувань у цьому місяці.",
    note: "Нотатка", trainingProfile: "Профіль тренувань", smartCoach: "Розумний тренер", generateSmart: "Згенерувати тренування",
    syncWatch: "Синхронізувати з годинником", addExercise: "Додати вправу", addSet: "Додати підхід", addPlannedSet: "Додати запланований підхід", logSetAndRest: "Записати підхід · відпочинок 90 с", copyLast: "Копіювати останній підхід",
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
  { key: "assisted_dip", names: { en: "Assisted Dip", uk: "Віджимання на брусах у гравітроні" }, aliases: ["підтягування з брусьями", "підтягування з брусами", "підтягування с брусьями", "підтягування с брусами", "подтягивания с брусьями", "подтягивание с брусьями", "пидтягування с брусьями", "пидтягування с брусями"], muscleIds: ["triceps", "chest", "shoulders"], introducedInSeedVersion: 3 },
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

const CATALOG_SEED_VERSION = 3;
const builtInExerciseByKey = new Map(builtInExerciseCatalog.map(exercise => [exercise.key, exercise]));
// Generated search vocabulary is loaded before the app and stays search-only: it never
// participates in catalog identity, persistence, imports, history, or sync.
const exerciseSearchVocabulary = globalThis.GymExerciseSearchVocabulary &&
  typeof globalThis.GymExerciseSearchVocabulary === "object"
  ? globalThis.GymExerciseSearchVocabulary
  : Object.freeze({ connectorTokens: [], aliasesByKey: {}, muscleTermsById: {}, equipmentTermsById: {}, equipmentIdsByKey: {} });
const builtInExerciseSearchAliasesByKey = new Map(Object.entries(
  exerciseSearchVocabulary.aliasesByKey && typeof exerciseSearchVocabulary.aliasesByKey === "object"
    ? exerciseSearchVocabulary.aliasesByKey
    : {}
));
const excludedLegacySearchAliasesByKey = new Map([
  ["upright_row", new Set([normalizeExerciseKey("вертикальна тяга")])]
]);
for (const catalogKey of builtInExerciseSearchAliasesByKey.keys()) {
  if (!builtInExerciseByKey.has(catalogKey)) throw new Error(`Unknown exercise search alias key: ${catalogKey}`);
}
const bundledExerciseMediaKeys = new Set([
  "bench_press", "dumbbell_bench_press", "incline_dumbbell_press", "incline_bench_press",
  "chest_fly_machine", "push_up", "dips", "pull_up", "assisted_pull_up", "assisted_dip", "band_assisted_pull_up",
  "lat_pulldown", "straight_arm_pulldown", "barbell_row", "seated_cable_row", "plate_loaded_row", "face_pull",
  "squat", "leg_press", "romanian_deadlift", "deadlift", "hip_thrust", "bulgarian_split_squat", "lunge", "leg_extension",
  "lying_leg_curl", "seated_leg_curl", "hip_adduction", "hip_abduction", "calf_raise",
  "shoulder_press", "lateral_raise", "machine_lateral_raise", "rear_delt_fly", "upright_row", "biceps_curl",
  "barbell_curl", "seated_dumbbell_curl", "hammer_curl", "cable_curl", "preacher_curl",
  "triceps_pushdown", "v_bar_pushdown", "overhead_dumbbell_triceps_extension",
  "french_press", "hyperextension", "side_hyperextension", "plank", "weighted_crunch",
  "hanging_leg_raise", "plate_twist", "weighted_side_bend", "warm_up"
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

window.GymSharedWorkout?.configureBuiltInIdentityResolver?.(catalogKeyRecognizedFromName);

let volatileRemoteSessionRaw = null;
discardLegacyGarminToken();
const startupCloudAccountDeletionRecovery = loadCloudAccountDeletionJournal();
let activeAccount = loadActiveAccount();
activeAccount = suppressPendingCloudDeletionAtStartup(
  activeAccount,
  startupCloudAccountDeletionRecovery
);
let state = loadState();
const initialActiveWorkoutRecord = loadActiveWorkoutRecord(activeAccount);
let activeWorkout = initialActiveWorkoutRecord.workout;
let activeWorkoutStorageRaw = initialActiveWorkoutRecord.raw;
const initialActiveWorkoutUndoRecord = loadActiveWorkoutUndoRecord(activeWorkout, activeAccount);
let activeWorkoutUndoMarker = initialActiveWorkoutUndoRecord.marker;
let activeWorkoutUndoStorageRaw = initialActiveWorkoutUndoRecord.raw;
let activeWorkoutUi = { status: "idle", message: "" };
let exerciseRestTimerLedger = null;
let activeWorkoutControlReconciliationPromise = null;
let nav = [{ name: "workouts" }];
let modal = null;
let workoutDraft = null;
let smartWorkoutEffort = "Auto";
let smartGeneratedPlan = null;
let smartPlanStale = false;
let toastTimer = null;
const monthOffsets = { workouts: 0, progress: 0 };
let overviewMode = "overview";
let musclePeriod = "month";
let missionPeriod = "daily";
let selectedMuscle = null;
let socialState = { status: "idle", source: null, dashboard: null, inbox: null, error: "" };
let socialRequestController = null;
let socialRequestId = 0;
let socialDetailState = { status: "idle", source: null, profileId: null, value: null, error: "" };
let socialDetailRequestController = null;
let socialDetailRequestId = 0;
let socialMutationInProgress = false;
let socialLastLoadedAt = 0;
let socialWorkoutInviteRequests = new Map();
let liveWorkoutState = { status: "idle", source: null, inbox: null, snapshot: null, error: "" };
let liveWorkoutRequestController = null;
let liveWorkoutRequestId = 0;
let liveWorkoutMutationInProgress = false;
let liveWorkoutOperationDrain = null;
let liveWorkoutContextGeneration = 0;
let liveWorkoutPollTimer = null;
let liveRealtimeRefreshTimer = null;
let liveRealtimeGeneration = 0;
let liveRealtime = {
  status: "idle", source: null, client: null, channel: null, accessToken: null
};
let webPushState = { status: "idle", source: null, error: "" };
let webPushMutationInProgress = false;
let webPushGeneration = 0;
let webPushLifecycleTail = Promise.resolve();
let liveWorkoutInviteRequests = new Map();
let liveWorkoutActionRequests = new Map();
let liveWorkoutBinding = loadLiveWorkoutBinding();
let garminProfileState = { status: "idle", userId: null, devices: [], error: "" };
let garminProfileRequestController = null;
let garminProfileRequestId = 0;
let timerInterval = null;
let languageMenuOpen = false;
let exerciseSearchQuery = "";
let progressExerciseSearchQuery = "";
let workoutDetailEditSessionId = null;
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
let cloudStateRecovery = null;
let cloudSyncConflict = null;
let cloudExtensions = { userId: null, value: {} };
let cloudRecoveryInProgress = false;
let cloudSyncUi = { userId: null, status: "idle", error: "" };
let pendingSharedWorkout = loadStoredSharedWorkout();
let pendingSharedWorkoutOrigin = pendingSharedWorkout ? { type: "link" } : null;
let sharedWorkoutStartupError = false;
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
  const sharedNormalizer = window.GymStateContract?.portableExerciseNameKey;
  if (typeof sharedNormalizer === "function") return sharedNormalizer(name);
  return String(name || "")
    .normalize("NFC")
    .replace(/[\u02bc\u2019]/g, "'")
    .replace(/[\p{White_Space}\u001c-\u001f]+/gu, " ")
    .trim()
    .toLowerCase()
    .replace(/ё/g, "е");
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

function exerciseMediaThumbnail(exercise, { blockIndex = null, className = "" } = {}) {
  const media = exerciseMedia(exercise);
  const label = txAttr("Open exercise demonstration", "Відкрити демонстрацію вправи");
  const storedExercise = state.exercises.find(item => exercisesMatch(item, exercise));
  const idAttribute = storedExercise && Number.isSafeInteger(Number(storedExercise.id)) && Number(storedExercise.id) > 0
    ? ` data-exercise-id="${escapeAttr(String(storedExercise.id))}"`
    : "";
  const blockAttribute = Number.isInteger(blockIndex) && blockIndex >= 0
    ? ` data-block="${blockIndex}"`
    : "";
  if (!idAttribute && !blockAttribute) return "";
  const classes = `exercise-media-thumb${className ? ` ${escapeAttr(className)}` : ""}`;
  if (!media) {
    return `<button class="${classes} empty" type="button" data-action="open-exercise-media"${idAttribute}${blockAttribute} aria-label="${label}">${svg("image", "exercise-media-placeholder-icon")}<span>${tx("Add image", "Додати фото")}</span></button>`;
  }
  return `<button class="${classes}" type="button" data-action="open-exercise-media"${idAttribute}${blockAttribute} aria-label="${label}"><img src="${escapeAttr(media.preview)}" alt="" loading="lazy"><span class="exercise-media-play">${media.frames.length > 1 ? "▶" : svg("image", "small-icon")}</span></button>`;
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

const EXERCISE_SEARCH_QUERY_MAX_CHARS = 256;
const EXERCISE_SEARCH_QUERY_MAX_TOKENS = 16;
const PROGRESS_EXERCISE_PICKER_LIMIT = 80;
const EXERCISE_SEARCH_MAX_CANDIDATES = 192;
const EXERCISE_SEARCH_MAX_CANDIDATE_CHARS = 128;
const exerciseSearchConnectorTokens = new Set(
  Array.isArray(exerciseSearchVocabulary.connectorTokens)
    ? exerciseSearchVocabulary.connectorTokens.filter(token => typeof token === "string" && token.length <= 16).slice(0, 96).map(normalizeExerciseKey)
    : []
);
const exerciseSearchSourcePriority = Object.freeze({
  canonical: 5000,
  legacy: 4500,
  alias: 4000,
  muscle: 2500,
  equipment: 2400
});
const exerciseSearchCyrillicToLatin = Object.freeze({
  а: "a", б: "b", в: "v", г: "g", ґ: "g", д: "d", е: "e", є: "ye", ж: "zh", з: "z",
  и: "i", і: "i", ї: "yi", й: "i", к: "k", л: "l", м: "m", н: "n", о: "o", п: "p",
  р: "r", с: "s", т: "t", у: "u", ф: "f", х: "h", ц: "ts", ч: "ch", ш: "sh",
  щ: "sch", ъ: "", ы: "y", ь: "", э: "e", ю: "yu", я: "ya"
});

function exerciseSearchVocabularyList(collection, key) {
  if (!collection || typeof collection !== "object") return [];
  const values = collection[key];
  return Array.isArray(values)
    ? values.filter(value => typeof value === "string" && value.trim() && value.length <= EXERCISE_SEARCH_MAX_CANDIDATE_CHARS).slice(0, 64)
    : [];
}

function exerciseSearchPhrase(value, maxChars = EXERCISE_SEARCH_MAX_CANDIDATE_CHARS) {
  return normalizeExerciseKey(String(value || "").slice(0, maxChars))
    .normalize("NFKD")
    .replace(/\p{M}+/gu, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

function exerciseSearchTokens(
  value,
  maxChars = EXERCISE_SEARCH_MAX_CANDIDATE_CHARS,
  allowTransliteratedConnectors = false
) {
  const tokens = exerciseSearchPhrase(value, maxChars)
    .split(" ")
    .filter(Boolean);
  const canDropTransliteratedConnectors = allowTransliteratedConnectors && tokens.length >= 3;
  return tokens.filter(token =>
    !exerciseSearchConnectorTokens.has(token) &&
    !(canDropTransliteratedConnectors && exerciseSearchTransliteratedConnectorTokens.has(token))
  );
}

function transliterateExerciseSearchToken(value) {
  return Array.from(value).map(character => exerciseSearchCyrillicToLatin[character] ?? character).join("");
}

const exerciseSearchTransliteratedConnectorTokens = new Set(
  [...exerciseSearchConnectorTokens].map(transliterateExerciseSearchToken)
);

function exerciseSearchWithinOneEdit(leftValue, rightValue) {
  if (leftValue === rightValue) return true;
  const left = Array.from(leftValue);
  const right = Array.from(rightValue);
  if (Math.abs(left.length - right.length) > 1) return false;
  if (left.length === right.length) {
    const differences = [];
    for (let index = 0; index < left.length; index += 1) {
      if (left[index] !== right[index]) differences.push(index);
      if (differences.length > 2) return false;
    }
    if (differences.length === 1) return true;
    return differences.length === 2 && differences[1] === differences[0] + 1 &&
      left[differences[0]] === right[differences[1]] && left[differences[1]] === right[differences[0]];
  }
  const shorter = left.length < right.length ? left : right;
  const longer = left.length < right.length ? right : left;
  let shortIndex = 0;
  let longIndex = 0;
  let skipped = false;
  while (shortIndex < shorter.length && longIndex < longer.length) {
    if (shorter[shortIndex] === longer[longIndex]) {
      shortIndex += 1;
      longIndex += 1;
    } else if (!skipped) {
      skipped = true;
      longIndex += 1;
    } else {
      return false;
    }
  }
  return true;
}

function exerciseSearchTokenQuality(candidateToken, queryToken) {
  if (candidateToken === queryToken) return 500;
  const candidateLatin = transliterateExerciseSearchToken(candidateToken);
  const queryLatin = transliterateExerciseSearchToken(queryToken);
  if (candidateLatin === queryLatin) return 460;
  const shortest = Math.min(candidateToken.length, queryToken.length);
  if (shortest >= 3 && (candidateToken.startsWith(queryToken) || queryToken.startsWith(candidateToken))) return 390;
  if (shortest >= 4 && (candidateToken.includes(queryToken) || queryToken.includes(candidateToken))) return 360;
  const latinShortest = Math.min(candidateLatin.length, queryLatin.length);
  if (latinShortest >= 3 && (candidateLatin.startsWith(queryLatin) || queryLatin.startsWith(candidateLatin))) return 350;
  if (latinShortest >= 4 && (candidateLatin.includes(queryLatin) || queryLatin.includes(candidateLatin))) return 330;
  let prefixLength = 0;
  while (prefixLength < shortest && candidateToken[prefixLength] === queryToken[prefixLength]) prefixLength += 1;
  if (prefixLength >= 5) return 310;
  const fuzzyLength = Math.min(candidateToken.length, queryToken.length);
  if (fuzzyLength >= 5 && exerciseSearchWithinOneEdit(candidateToken, queryToken)) return 270;
  if (latinShortest >= 5 && exerciseSearchWithinOneEdit(candidateLatin, queryLatin)) return 240;
  return 0;
}

function exerciseSearchCandidateEntries(value, language = state.language) {
  const builtIn = builtInExerciseFor(value);
  if (!builtIn) {
    const customName = exerciseRawName(value);
    if (!customName || customName.length > EXERCISE_SEARCH_MAX_CANDIDATE_CHARS) return [];
    return [{ source: "canonical", concept: "canonical", label: customName }];
  }
  const russianName = ru(builtIn.names.en);
  const localizedName = language === "uk" ? builtIn.names.uk : language === "ru" ? russianName : builtIn.names.en;
  const excludedLegacyAliases = excludedLegacySearchAliasesByKey.get(builtIn.key) || new Set();
  const entries = [localizedName, builtIn.names.en, builtIn.names.uk, russianName]
    .map(label => ({ source: "canonical", concept: "canonical", label }));
  entries.push(...builtIn.aliases
    .filter(alias => !excludedLegacyAliases.has(normalizeExerciseKey(alias)))
    .map(label => ({ source: "legacy", concept: `legacy:${normalizeExerciseKey(label)}`, label })));
  entries.push(...exerciseSearchVocabularyList(exerciseSearchVocabulary.aliasesByKey, builtIn.key)
    .map(label => ({ source: "alias", concept: `alias:${normalizeExerciseKey(label)}`, label })));
  const muscleIds = Array.isArray(builtIn.muscleIds) ? builtIn.muscleIds.slice(0, 16) : [];
  for (const muscleId of muscleIds) {
    entries.push(...exerciseSearchVocabularyList(exerciseSearchVocabulary.muscleTermsById, muscleId)
      .map(label => ({ source: "muscle", concept: `muscle:${muscleId}`, label })));
  }
  for (const equipmentId of exerciseSearchVocabularyList(exerciseSearchVocabulary.equipmentIdsByKey, builtIn.key).slice(0, 12)) {
    entries.push(...exerciseSearchVocabularyList(exerciseSearchVocabulary.equipmentTermsById, equipmentId)
      .map(label => ({ source: "equipment", concept: `equipment:${equipmentId}`, label })));
  }
  const seen = new Set();
  return entries.filter(entry => {
    const phrase = exerciseSearchPhrase(entry.label);
    const identity = `${entry.source}:${phrase}`;
    if (!phrase || seen.has(identity) || entry.label.length > EXERCISE_SEARCH_MAX_CANDIDATE_CHARS) return false;
    seen.add(identity);
    return true;
  }).slice(0, EXERCISE_SEARCH_MAX_CANDIDATES);
}

function exerciseSearchEntryData(entry) {
  const phrase = exerciseSearchPhrase(entry.label);
  const tokens = exerciseSearchTokens(entry.label);
  const compact = tokens.length > 1 ? tokens.join("") : "";
  return { ...entry, phrase, significantPhrase: tokens.join(" "), tokens, compact };
}

function exerciseSearchBestTokenMatch(queryToken, entries) {
  let bestTokenMatch = null;
  for (const entry of entries) {
    const candidateTokens = entry.compact ? [...entry.tokens, entry.compact] : entry.tokens;
    for (const candidateToken of candidateTokens) {
      const quality = exerciseSearchTokenQuality(candidateToken, queryToken);
      const rank = quality + Math.floor((exerciseSearchSourcePriority[entry.source] || 0) / 100);
      if (quality && (!bestTokenMatch || rank > bestTokenMatch.rank)) {
        bestTokenMatch = { entry, quality, rank };
      }
    }
  }
  return bestTokenMatch;
}

function exerciseSearchTokenMatchResult(selectedMatches) {
  const strongestPriority = Math.max(...selectedMatches.map(match =>
    exerciseSearchSourcePriority[match.entry.source] || 0
  ));
  const averageQuality = Math.round(
    selectedMatches.reduce((sum, match) => sum + match.quality, 0) / selectedMatches.length
  );
  const reasonEntries = [];
  const seenReasons = new Set();
  for (const match of selectedMatches) {
    const reasonKey = `${match.entry.source}:${match.entry.phrase}`;
    if (!seenReasons.has(reasonKey)) {
      seenReasons.add(reasonKey);
      reasonEntries.push(match.entry);
    }
  }
  const reason = reasonEntries.slice(0, 2).map(entry => entry.label).join(" · ");
  const source = reasonEntries.length === 1 ? reasonEntries[0].source : "combined";
  return { matched: true, score: strongestPriority + 1000 + averageQuality, reason, source };
}

function exerciseSearchCoherentMatch(queryTokens, candidateGroups, { lexical = false } = {}) {
  let bestMatch = null;
  for (const candidates of candidateGroups) {
    const selectedMatches = queryTokens.map(queryToken =>
      exerciseSearchBestTokenMatch(queryToken, candidates)
    );
    if (selectedMatches.some(match => !match)) continue;
    // For a multi-word lexical phrase, a weak fuzzy-only interpretation must be
    // anchored by at least one exact or exact-transliterated word. This keeps useful
    // one-word typo recovery while preventing "верх груди" from becoming the
    // pulldown phrase "верхнього блока до грудей" through two loose inflections.
    if (lexical && queryTokens.length > 1 &&
        selectedMatches.some(match => match.quality < 300) &&
        !selectedMatches.some(match => match.quality >= 460)) {
      continue;
    }
    const match = exerciseSearchTokenMatchResult(selectedMatches);
    if (!bestMatch || match.score > bestMatch.score) bestMatch = match;
  }
  return bestMatch;
}

function exerciseSearchMatch(value, query, language = state.language) {
  const queryValue = String(query || "");
  if (queryValue.length > EXERCISE_SEARCH_QUERY_MAX_CHARS) {
    return { matched: false, score: 0, reason: null, source: null };
  }
  const rawQuery = queryValue.trim();
  if (!rawQuery) return { matched: true, score: 0, reason: null, source: "canonical" };
  const queryPhrase = exerciseSearchPhrase(rawQuery, EXERCISE_SEARCH_QUERY_MAX_CHARS);
  const queryTokens = exerciseSearchTokens(rawQuery, EXERCISE_SEARCH_QUERY_MAX_CHARS, true);
  const queryDistinctTokens = [...new Set(queryTokens)];
  if (!queryTokens.length || queryTokens.length > EXERCISE_SEARCH_QUERY_MAX_TOKENS ||
      (queryDistinctTokens.length === 1 && queryDistinctTokens[0].length < 3)) {
    return { matched: false, score: 0, reason: null, source: null };
  }
  const querySignificantPhrase = queryTokens.join(" ");
  const queryCompact = queryTokens.join("");
  const entries = exerciseSearchCandidateEntries(value, language).map(exerciseSearchEntryData);
  let bestPhraseMatch = null;
  for (const entry of entries) {
    const priority = exerciseSearchSourcePriority[entry.source] || 0;
    let score = 0;
    if (entry.phrase === queryPhrase || entry.significantPhrase === querySignificantPhrase) score = priority + 3000;
    else if (entry.compact && entry.compact === queryCompact) score = priority + 2600;
    else if (entry.compact && queryCompact.length >= 5 && exerciseSearchWithinOneEdit(entry.compact, queryCompact)) score = priority + 1500;
    if (score && (!bestPhraseMatch || score > bestPhraseMatch.score)) {
      bestPhraseMatch = { matched: true, score, reason: entry.label, source: entry.source };
    }
  }
  if (bestPhraseMatch) return bestPhraseMatch;

  const lexicalEntries = entries.filter(entry =>
    entry.source === "canonical" || entry.source === "legacy" || entry.source === "alias"
  );
  const lexicalMatch = exerciseSearchCoherentMatch(
    queryTokens,
    lexicalEntries.map(entry => [entry]),
    { lexical: true }
  );
  if (lexicalMatch) return lexicalMatch;

  const groupsForSource = source => {
    const grouped = new Map();
    entries.filter(entry => entry.source === source).forEach(entry => {
      if (!grouped.has(entry.concept)) grouped.set(entry.concept, []);
      grouped.get(entry.concept).push(entry);
    });
    return [...grouped.values()];
  };
  const muscleGroups = groupsForSource("muscle");
  const equipmentGroups = groupsForSource("equipment");
  const semanticGroups = [
    ...muscleGroups,
    ...equipmentGroups,
    ...muscleGroups.flatMap(muscleGroup =>
      equipmentGroups.map(equipmentGroup => [...muscleGroup, ...equipmentGroup])
    )
  ];
  return exerciseSearchCoherentMatch(queryTokens, semanticGroups) ||
    { matched: false, score: 0, reason: null, source: null };
}

function exerciseMatchesSearch(value, query, language = state.language) {
  return exerciseSearchMatch(value, query, language).matched;
}

function exerciseSearchReason(value, query = exerciseSearchQuery, language = state.language) {
  if (!String(query || "").trim()) return null;
  const match = exerciseSearchMatch(value, query, language);
  if (!match.matched || !match.reason) return null;
  const displayedName = exerciseDisplayName(value, language);
  if (match.source === "canonical" && normalizeExerciseKey(match.reason) === normalizeExerciseKey(displayedName)) return null;
  return match.reason;
}

function exerciseSearchReasonMarkup(value, query = exerciseSearchQuery) {
  const reason = exerciseSearchReason(value, query);
  if (!reason) return "";
  const prefix = state.language === "ru" ? "Найдено по" : state.language === "uk" ? "Знайдено за запитом" : "Found by";
  return `<small class="exercise-search-reason">${escapeHtml(`${prefix}: ${reason}`)}</small>`;
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
  rep: ["повтор", "повтора", "повторов"],
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
  if (!targetState || !Array.isArray(targetState.exercises)) return false;
  let changed = false;
  const assistedDipMatches = targetState.exercises.filter(
    exercise => catalogKeyRecognizedFromName(exercise) === "assisted_dip"
  );
  if (assistedDipMatches.length) {
    const legacyMatch = assistedDipMatches.find(
      exercise => normalizeExerciseKey(exerciseRawName(exercise)) !== normalizeExerciseKey("Assisted Dip")
    );
    const survivor = legacyMatch || assistedDipMatches[0];
    const mergedFavorite = assistedDipMatches.some(exercise => exercise.favorite === true);
    const mergedLoadProfile = survivor.loadProfile || assistedDipMatches.find(exercise => exercise.loadProfile)?.loadProfile;
    survivor.name = "Assisted Dip";
    survivor.catalogKey = "assisted_dip";
    if (mergedFavorite) survivor.favorite = true;
    if (mergedLoadProfile) survivor.loadProfile = mergedLoadProfile;
    if (assistedDipMatches.length > 1) {
      const duplicates = new Set(assistedDipMatches.filter(exercise => exercise !== survivor));
      targetState.exercises = targetState.exercises.filter(exercise => !duplicates.has(exercise));
    }
    changed = legacyMatch != null || assistedDipMatches.length > 1;
  }
  if (targetState.catalogSeedVersion >= CATALOG_SEED_VERSION) return changed;
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
  return changed || inserted > 0;
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

function activeWorkoutAccountDescriptor(account = activeAccount) {
  const normalized = normalizeStoredAccount(account);
  if (!normalized) return null;
  return {
    owner: normalized.remote === "supabase"
      ? `supabase:${normalized.userId}`
      : `local:${normalized.id}`,
    storageKey: `${ACTIVE_WORKOUT_PREFIX}${normalized.id}`,
    recoveryKey: `${ACTIVE_WORKOUT_RECOVERY_PREFIX}${normalized.id}`,
    commitKey: `${ACTIVE_WORKOUT_COMMIT_PREFIX}${normalized.id}`,
    undoKey: `${ACTIVE_WORKOUT_UNDO_PREFIX}${normalized.id}`,
    timingKey: `${ACTIVE_WORKOUT_TIMING_PREFIX}${normalized.id}`,
    restTransitionKey: `${ACTIVE_WORKOUT_REST_TRANSITION_PREFIX}${normalized.id}`,
    bulkCleanupKey: `${ACTIVE_WORKOUT_BULK_CLEANUP_PREFIX}${normalized.id}`,
    lockName: `${ACTIVE_WORKOUT_LOCK_PREFIX}${normalized.id}`,
  };
}

function activeWorkoutExactObject(value, path, required, optional = []) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${path} must be an object.`);
  }
  const allowed = new Set([...required, ...optional]);
  const keys = Object.keys(value);
  if (required.some(key => !Object.hasOwn(value, key)) || keys.some(key => !allowed.has(key))) {
    throw new Error(`${path} has unsupported fields.`);
  }
  return value;
}

function activeWorkoutPositiveId(value, path) {
  if (!Number.isSafeInteger(value) || value <= 0 || String(value).length > 16) {
    throw new Error(`${path} must be a positive stable ID.`);
  }
  return value;
}

function activeWorkoutTimestamp(value, path) {
  const limits = window.GymStateContract.LIMITS;
  if (!Number.isSafeInteger(value) || value < limits.timestampMin || value > limits.timestampMax) {
    throw new Error(`${path} is outside the supported timestamp range.`);
  }
  return value;
}

function activeWorkoutStorageByteLength(value) {
  try {
    return new TextEncoder().encode(value).byteLength;
  } catch {
    return Number.POSITIVE_INFINITY;
  }
}

function persistLocalExerciseNameMigration(storageKey, expectedRaw, encoded, maxBytes) {
  if (typeof storageKey !== "string" || typeof expectedRaw !== "string" ||
      typeof encoded !== "string" || activeWorkoutStorageByteLength(encoded) > maxBytes) {
    return expectedRaw;
  }
  try {
    if (localStorage.getItem(storageKey) !== expectedRaw) return expectedRaw;
    localStorage.setItem(storageKey, encoded);
    return localStorage.getItem(storageKey) === encoded ? encoded : expectedRaw;
  } catch {
    // Keep the normalized value usable in memory. A normal mutation can retry
    // persistence without deleting or quarantining the bounded legacy value.
    return expectedRaw;
  }
}

function preserveActiveWorkoutRecoveryRaw(raw, descriptor) {
  if (typeof raw !== "string" || !descriptor ||
      activeWorkoutStorageByteLength(raw) > MAX_ACTIVE_WORKOUT_STORAGE_BYTES) {
    return false;
  }
  try {
    const existing = localStorage.getItem(descriptor.recoveryKey);
    if (existing !== null && existing !== raw) return false;
    if (existing === null) localStorage.setItem(descriptor.recoveryKey, raw);
    return localStorage.getItem(descriptor.recoveryKey) === raw;
  } catch {
    return false;
  }
}

function scheduleActiveWorkoutRecoveryRaw(raw, descriptor) {
  if (typeof raw !== "string" || !descriptor ||
      activeWorkoutStorageByteLength(raw) > MAX_ACTIVE_WORKOUT_STORAGE_BYTES ||
      !navigator?.locks || typeof navigator.locks.request !== "function" ||
      typeof AbortController !== "function") return;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), ACTIVE_WORKOUT_LOCK_WAIT_MS);
  try {
    void navigator.locks.request(
      descriptor.lockName,
      { mode: "exclusive", signal: controller.signal },
      () => {
        try {
          const marker = normalizeStoredAccount(JSON.parse(localStorage.getItem(AUTH_KEY) || "null"));
          const markerDescriptor = activeWorkoutAccountDescriptor(marker);
          if (markerDescriptor?.owner === descriptor.owner &&
              markerDescriptor.storageKey === descriptor.storageKey) {
            preserveActiveWorkoutRecoveryRaw(raw, descriptor);
          }
        } catch {
          // The source draft remains untouched when a recovery copy cannot be made.
        }
      }
    ).catch(() => {}).finally(() => clearTimeout(timeout));
  } catch {
    clearTimeout(timeout);
  }
}

function removeActiveWorkoutRecoveryStorage(account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) return false;
  try {
    localStorage.removeItem(descriptor.recoveryKey);
    return localStorage.getItem(descriptor.recoveryKey) === null;
  } catch {
    return false;
  }
}

async function withActiveWorkoutMutationLock(descriptor, operation) {
  if (!descriptor || typeof operation !== "function") return { acquired: false, value: null };
  if (navigator?.locks && typeof navigator.locks.request === "function" &&
      typeof AbortController === "function") {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), ACTIVE_WORKOUT_LOCK_WAIT_MS);
    try {
      return await navigator.locks.request(
        descriptor.lockName,
        { mode: "exclusive", signal: controller.signal },
        async () => ({ acquired: true, value: await operation() })
      );
    } catch {
      return { acquired: false, value: null };
    } finally {
      clearTimeout(timeout);
    }
  }
  // A localStorage lease cannot fence a tab that is suspended after its last
  // ownership check. Browsers without Web Locks therefore fail closed instead
  // of risking two successful writers or a stale post-expiry write.
  return { acquired: false, value: null };
}

async function withActiveWorkoutDeletionLock(descriptor, operation) {
  if (navigator?.locks && typeof navigator.locks.request === "function" &&
      typeof AbortController === "function") {
    return withActiveWorkoutMutationLock(descriptor, operation);
  }
  // In this runtime active-workout mutations use the fail-closed path above,
  // so synchronous marker invalidation plus cleanup cannot race one of them.
  try {
    return { acquired: true, value: await operation() };
  } catch {
    return { acquired: true, value: false };
  }
}

function activeWorkoutMutationContext(account = activeAccount) {
  const normalized = normalizeStoredAccount(account);
  const descriptor = activeWorkoutAccountDescriptor(normalized);
  if (!normalized || !descriptor) return null;
  try {
    const authMarkerRaw = localStorage.getItem(AUTH_KEY);
    if (typeof authMarkerRaw !== "string" ||
        activeWorkoutStorageByteLength(authMarkerRaw) > MAX_LOCAL_ACCOUNT_STORAGE_BYTES) return null;
    const marker = normalizeStoredAccount(JSON.parse(authMarkerRaw));
    const markerDescriptor = activeWorkoutAccountDescriptor(marker);
    if (!markerDescriptor || markerDescriptor.owner !== descriptor.owner ||
        markerDescriptor.storageKey !== descriptor.storageKey) return null;
    return {
      account: normalized,
      descriptor,
      epoch: accountEpoch,
      authMarkerRaw
    };
  } catch {
    return null;
  }
}

function activeWorkoutMutationContextIsCurrent(context) {
  if (!context || context.epoch !== accountEpoch ||
      activeWorkoutAccountDescriptor()?.owner !== context.descriptor.owner) return false;
  try {
    return localStorage.getItem(AUTH_KEY) === context.authMarkerRaw;
  } catch {
    return false;
  }
}

function parseActiveWorkoutEnvelope(input, account = activeAccount, options = {}) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) throw new Error("Active workout has no valid account owner.");
  let value = input;
  if (typeof input === "string") {
    if (new TextEncoder().encode(input).byteLength > MAX_ACTIVE_WORKOUT_STORAGE_BYTES) {
      throw new Error("Active workout storage is oversized.");
    }
    value = JSON.parse(input);
  }
  let migratedLegacyExerciseNameControls = false;
  if (options.migrateLegacyExerciseNameControls === true &&
      value && typeof value === "object" && !Array.isArray(value) && Array.isArray(value.blocks)) {
    value.blocks.forEach(block => {
      if (!block || typeof block !== "object" || Array.isArray(block) ||
          typeof block.exerciseName !== "string") return;
      const migratedName = window.GymStateContract.migrateLegacyExerciseNameControls(block.exerciseName);
      if (migratedName === block.exerciseName) return;
      block.exerciseName = migratedName;
      delete block.catalogKey;
      delete block.exerciseCatalogKey;
      migratedLegacyExerciseNameControls = true;
    });
  }
  const root = activeWorkoutExactObject(value, "active workout", [
    "version", "owner", "id", "startedAt", "createdAt", "updatedAt", "revision", "note", "blocks"
  ]);
  if (root.version !== ACTIVE_WORKOUT_VERSION || root.owner !== descriptor.owner) {
    throw new Error("Active workout owner or version is invalid.");
  }
  const id = activeWorkoutPositiveId(root.id, "active workout.id");
  const startedAt = activeWorkoutTimestamp(root.startedAt, "active workout.startedAt");
  const createdAt = activeWorkoutTimestamp(root.createdAt, "active workout.createdAt");
  const updatedAt = activeWorkoutTimestamp(root.updatedAt, "active workout.updatedAt");
  if (startedAt > createdAt || updatedAt < createdAt) {
    throw new Error("Active workout timestamps are out of order.");
  }
  if (!Number.isSafeInteger(root.revision) || root.revision < 1) {
    throw new Error("Active workout revision is invalid.");
  }
  if (typeof root.note !== "string" || root.note.length > MAX_ACTIVE_WORKOUT_NOTE_LENGTH ||
      new TextEncoder().encode(root.note).byteLength > MAX_ACTIVE_WORKOUT_NOTE_BYTES) {
    throw new Error("Active workout note exceeds the supported limit.");
  }
  const limits = window.GymStateContract.LIMITS;
  if (!Array.isArray(root.blocks) || root.blocks.length < 1 ||
      root.blocks.length > limits.exercisesPerSession) {
    throw new Error("Active workout exercise list is invalid.");
  }
  const usedIds = new Set([id]);
  let totalSets = 0;
  const blocks = root.blocks.map((rawBlock, blockIndex) => {
    const block = activeWorkoutExactObject(
      rawBlock,
      `active workout.blocks[${blockIndex}]`,
      ["id", "exerciseName", "sets"],
      ["catalogKey"]
    );
    const blockId = activeWorkoutPositiveId(block.id, `active workout.blocks[${blockIndex}].id`);
    if (usedIds.has(blockId)) throw new Error("Active workout contains duplicate IDs.");
    usedIds.add(blockId);
    if (typeof block.exerciseName !== "string" || block.exerciseName !== block.exerciseName.trim() ||
        !isSupportedExerciseName(block.exerciseName)) {
      throw new Error("Active workout contains an invalid exercise name.");
    }
    let catalogKey = null;
    if (Object.hasOwn(block, "catalogKey")) {
      if (typeof block.catalogKey !== "string" ||
          persistedExerciseCatalogKey({ name: block.exerciseName, catalogKey: block.catalogKey }) !== block.catalogKey) {
        throw new Error("Active workout contains an invalid exercise identity.");
      }
      catalogKey = block.catalogKey;
    }
    if (!Array.isArray(block.sets) || block.sets.length < 1 || block.sets.length > limits.setsPerExercise) {
      throw new Error("Active workout contains an invalid set list.");
    }
    totalSets += block.sets.length;
    if (totalSets > limits.exercisesPerSession * limits.setsPerExercise) {
      throw new Error("Active workout exceeds the total set limit.");
    }
    const sets = block.sets.map((rawSet, setIndex) => {
      const set = activeWorkoutExactObject(
        rawSet,
        `active workout.blocks[${blockIndex}].sets[${setIndex}]`,
        ["id", "weight", "reps", "completed", "completedAt"]
      );
      const setId = activeWorkoutPositiveId(
        set.id,
        `active workout.blocks[${blockIndex}].sets[${setIndex}].id`
      );
      if (usedIds.has(setId)) throw new Error("Active workout contains duplicate IDs.");
      usedIds.add(setId);
      const weight = Number(set.weight);
      if (typeof set.weight !== "number" || !Number.isFinite(weight) || weight < 0 ||
          weight > limits.weightMax) {
        throw new Error("Active workout contains an invalid weight.");
      }
      if (!Number.isInteger(set.reps) || set.reps < 1 || set.reps > limits.repsMax) {
        throw new Error("Active workout contains invalid reps.");
      }
      if (typeof set.completed !== "boolean") {
        throw new Error("Active workout contains an invalid completion state.");
      }
      let completedAt = null;
      if (set.completed) {
        completedAt = activeWorkoutTimestamp(
          set.completedAt,
          `active workout.blocks[${blockIndex}].sets[${setIndex}].completedAt`
        );
        if (completedAt < createdAt || completedAt > updatedAt) {
          throw new Error("Active workout completion timestamp is out of order.");
        }
      } else if (set.completedAt !== null) {
        throw new Error("An unfinished active set cannot have a completion timestamp.");
      }
      return {
        id: setId,
        weight: Object.is(weight, -0) ? 0 : weight,
        reps: set.reps,
        completed: set.completed,
        completedAt
      };
    });
    return {
      id: blockId,
      exerciseName: block.exerciseName,
      ...(catalogKey ? { catalogKey } : {}),
      sets
    };
  });
  const workout = {
    version: ACTIVE_WORKOUT_VERSION,
    owner: descriptor.owner,
    id,
    startedAt,
    createdAt,
    updatedAt,
    revision: root.revision,
    note: root.note,
    blocks
  };
  return options.includeMigrationMetadata === true
    ? { workout, migratedLegacyExerciseNameControls }
    : workout;
}

function parseActiveWorkoutUndoEnvelope(input, workout, account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor || !workout) throw new Error("Active workout undo state has no owner or workout.");
  let value = input;
  if (typeof input === "string") {
    if (activeWorkoutStorageByteLength(input) > MAX_ACTIVE_WORKOUT_UNDO_STORAGE_BYTES) {
      throw new Error("Active workout undo state is oversized.");
    }
    value = JSON.parse(input);
  }
  const root = activeWorkoutExactObject(value, "active workout undo state", [
    "version", "owner", "workoutId", "workoutRevision", "setId"
  ]);
  const workoutId = activeWorkoutPositiveId(root.workoutId, "active workout undo state.workoutId");
  if (root.version !== 1 || root.owner !== descriptor.owner || workout.owner !== descriptor.owner ||
      workoutId !== workout.id || !Number.isSafeInteger(root.workoutRevision) ||
      root.workoutRevision < 1 || root.workoutRevision !== workout.revision) {
    throw new Error("Active workout undo state does not match the current workout.");
  }
  let setId = null;
  if (root.setId !== null) {
    setId = activeWorkoutPositiveId(root.setId, "active workout undo state.setId");
    if (latestActiveCompletedEntry(workout)?.set.id !== setId) {
      throw new Error("Active workout undo state does not identify the latest completed set.");
    }
  }
  return {
    version: 1,
    owner: descriptor.owner,
    workoutId,
    workoutRevision: root.workoutRevision,
    setId
  };
}

function loadActiveWorkoutUndoRecord(workout, account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) return { marker: null, raw: null };
  let raw = null;
  try {
    raw = localStorage.getItem(descriptor.undoKey);
    if (raw === null || !workout ||
        activeWorkoutStorageByteLength(raw) > MAX_ACTIVE_WORKOUT_UNDO_STORAGE_BYTES) {
      return { marker: null, raw };
    }
    return { marker: parseActiveWorkoutUndoEnvelope(raw, workout, account), raw };
  } catch {
    return { marker: null, raw };
  }
}

function persistActiveWorkoutUndoRecord(workout, setId, account = activeAccount, expectedRaw = undefined) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor || !workout || (setId !== null && (!Number.isSafeInteger(setId) || setId <= 0))) return null;
  try {
    const marker = parseActiveWorkoutUndoEnvelope({
      version: 1,
      owner: descriptor.owner,
      workoutId: workout.id,
      workoutRevision: workout.revision,
      setId
    }, workout, account);
    const encoded = JSON.stringify(marker);
    if (activeWorkoutStorageByteLength(encoded) > MAX_ACTIVE_WORKOUT_UNDO_STORAGE_BYTES) return null;
    const current = localStorage.getItem(descriptor.undoKey);
    if (expectedRaw !== undefined && current !== expectedRaw) return null;
    localStorage.setItem(descriptor.undoKey, encoded);
    if (localStorage.getItem(descriptor.undoKey) !== encoded) return null;
    return { marker, raw: encoded };
  } catch {
    return null;
  }
}

function removeActiveWorkoutUndoStorage(account = activeAccount, expectedRaw = undefined) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) return false;
  try {
    const current = localStorage.getItem(descriptor.undoKey);
    if (expectedRaw !== undefined && current !== expectedRaw) return false;
    localStorage.removeItem(descriptor.undoKey);
    return localStorage.getItem(descriptor.undoKey) === null;
  } catch {
    return false;
  }
}

function parseActiveWorkoutTimingEnvelope(input, workout, account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor || !workout) throw new Error("Active workout timing has no owner or workout.");
  let value = input;
  if (typeof input === "string") {
    if (activeWorkoutStorageByteLength(input) > MAX_ACTIVE_WORKOUT_TIMING_STORAGE_BYTES) {
      throw new Error("Active workout timing is oversized.");
    }
    value = JSON.parse(input);
  }
  const root = activeWorkoutExactObject(value, "active workout timing", [
    "version", "owner", "workoutId", "accumulatedActiveMillis", "activeSince", "restingUntil"
  ]);
  const workoutId = activeWorkoutPositiveId(root.workoutId, "active workout timing.workoutId");
  if (root.version !== 1 || root.owner !== descriptor.owner || workout.owner !== descriptor.owner ||
      workoutId !== workout.id || !Number.isSafeInteger(root.accumulatedActiveMillis) ||
      root.accumulatedActiveMillis < 0) {
    throw new Error("Active workout timing does not match the current workout.");
  }
  const hasActiveSince = root.activeSince !== null;
  const hasRestingUntil = root.restingUntil !== null;
  if (hasActiveSince === hasRestingUntil) {
    throw new Error("Active workout timing must be either active or resting.");
  }
  const activeSince = hasActiveSince
    ? activeWorkoutTimestamp(root.activeSince, "active workout timing.activeSince")
    : null;
  const restingUntil = hasRestingUntil
    ? activeWorkoutTimestamp(root.restingUntil, "active workout timing.restingUntil")
    : null;
  if (restingUntil !== null && restingUntil > Date.now() + MAX_ACTIVE_WORKOUT_REST_MS) {
    throw new Error("Active workout rest is too far in the future.");
  }
  const boundary = activeSince ?? restingUntil;
  if (boundary < workout.createdAt ||
      root.accumulatedActiveMillis > Math.max(0, boundary - workout.createdAt)) {
    throw new Error("Active workout timing is outside the workout lifetime.");
  }
  return {
    version: 1,
    owner: descriptor.owner,
    workoutId,
    accumulatedActiveMillis: root.accumulatedActiveMillis,
    activeSince,
    restingUntil
  };
}

function defaultActiveWorkoutTiming(workout, account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor || !workout || workout.owner !== descriptor.owner) return null;
  return {
    version: 1,
    owner: descriptor.owner,
    workoutId: workout.id,
    accumulatedActiveMillis: 0,
    activeSince: workout.createdAt,
    restingUntil: null
  };
}

function loadActiveWorkoutTimingRecord(workout = activeWorkout, account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor || !workout) return { timing: null, raw: null };
  let raw = null;
  try {
    raw = localStorage.getItem(descriptor.timingKey);
    if (raw === null) return { timing: defaultActiveWorkoutTiming(workout, account), raw: null };
    return { timing: parseActiveWorkoutTimingEnvelope(raw, workout, account), raw };
  } catch {
    try {
      localStorage.removeItem(descriptor.timingKey);
    } catch {
      // A malformed sidecar is ignored; the strict active-workout envelope stays intact.
    }
    return { timing: defaultActiveWorkoutTiming(workout, account), raw: null };
  }
}

function persistActiveWorkoutTiming(timing, workout = activeWorkout, account = activeAccount, expectedRaw = undefined) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor || !workout) return null;
  try {
    const parsed = parseActiveWorkoutTimingEnvelope(timing, workout, account);
    const encoded = JSON.stringify(parsed);
    if (activeWorkoutStorageByteLength(encoded) > MAX_ACTIVE_WORKOUT_TIMING_STORAGE_BYTES) return null;
    const current = localStorage.getItem(descriptor.timingKey);
    if (expectedRaw !== undefined && current !== expectedRaw) return null;
    localStorage.setItem(descriptor.timingKey, encoded);
    if (localStorage.getItem(descriptor.timingKey) !== encoded) return null;
    return { timing: parsed, raw: encoded };
  } catch {
    return null;
  }
}

function removeActiveWorkoutTimingStorage(account = activeAccount, expectedRaw = undefined) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) return false;
  try {
    const current = localStorage.getItem(descriptor.timingKey);
    if (expectedRaw !== undefined && current !== expectedRaw) return false;
    localStorage.removeItem(descriptor.timingKey);
    return localStorage.getItem(descriptor.timingKey) === null;
  } catch {
    return false;
  }
}

function normalizedActiveWorkoutTiming(timing, workout = activeWorkout, now = Date.now(), account = activeAccount) {
  if (!timing || !workout || !Number.isSafeInteger(now)) return null;
  const parsed = parseActiveWorkoutTimingEnvelope(timing, workout, account);
  if (parsed.restingUntil !== null && now >= parsed.restingUntil) {
    return { ...parsed, activeSince: parsed.restingUntil, restingUntil: null };
  }
  return parsed;
}

function activeWorkoutElapsedMillis(workout = activeWorkout, now = Date.now()) {
  if (!workout || !Number.isSafeInteger(now)) return 0;
  return Math.max(0, now - workout.createdAt);
}

function transitionActiveWorkoutTimingToRest(workout, restingUntil, now = Date.now(), account = activeAccount) {
  if (!workout || !Number.isSafeInteger(restingUntil) || !Number.isSafeInteger(now) ||
      restingUntil <= now) return false;
  const loaded = loadActiveWorkoutTimingRecord(workout, account);
  let timing = normalizedActiveWorkoutTiming(loaded.timing, workout, now, account);
  if (!timing) return false;
  if (timing.activeSince !== null) {
    const interval = Math.max(0, now - timing.activeSince);
    if (!Number.isSafeInteger(interval) ||
        !Number.isSafeInteger(timing.accumulatedActiveMillis + interval)) return false;
    timing = {
      ...timing,
      accumulatedActiveMillis: timing.accumulatedActiveMillis + interval,
      activeSince: null
    };
  }
  timing.restingUntil = restingUntil;
  return Boolean(persistActiveWorkoutTiming(timing, workout, account, loaded.raw));
}

function transitionActiveWorkoutTimingToActive(workout, now = Date.now(), account = activeAccount) {
  if (!workout || !Number.isSafeInteger(now)) return false;
  const loaded = loadActiveWorkoutTimingRecord(workout, account);
  let timing = normalizedActiveWorkoutTiming(loaded.timing, workout, now, account);
  if (!timing) return false;
  if (timing.restingUntil !== null) {
    timing = { ...timing, activeSince: now, restingUntil: null };
  }
  return Boolean(persistActiveWorkoutTiming(timing, workout, account, loaded.raw));
}

function activeWorkoutTimingAfterRestTransition(workout, restingUntil, transitionAt, account = activeAccount) {
  if (!workout || !Number.isSafeInteger(restingUntil) || !Number.isSafeInteger(transitionAt) ||
      restingUntil <= transitionAt || restingUntil > transitionAt + MAX_ACTIVE_WORKOUT_REST_MS) return null;
  const loaded = loadActiveWorkoutTimingRecord(workout, account);
  let timing = normalizedActiveWorkoutTiming(loaded.timing, workout, transitionAt, account);
  if (!timing) return null;
  if (timing.activeSince !== null) {
    const interval = Math.max(0, transitionAt - timing.activeSince);
    const accumulatedActiveMillis = timing.accumulatedActiveMillis + interval;
    if (!Number.isSafeInteger(interval) || !Number.isSafeInteger(accumulatedActiveMillis)) return null;
    timing = { ...timing, accumulatedActiveMillis, activeSince: null };
  }
  timing.restingUntil = restingUntil;
  try {
    return { timing: parseActiveWorkoutTimingEnvelope(timing, workout, account), raw: loaded.raw };
  } catch {
    return null;
  }
}

function activeWorkoutTimingAfterStopTransition(workout, transitionAt, account = activeAccount) {
  if (!workout || !Number.isSafeInteger(transitionAt)) return null;
  const loaded = loadActiveWorkoutTimingRecord(workout, account);
  let timing = normalizedActiveWorkoutTiming(loaded.timing, workout, transitionAt, account);
  if (!timing) return null;
  if (timing.activeSince !== null) {
    const interval = Math.max(0, transitionAt - timing.activeSince);
    const accumulatedActiveMillis = timing.accumulatedActiveMillis + interval;
    if (!Number.isSafeInteger(interval) || !Number.isSafeInteger(accumulatedActiveMillis)) return null;
    timing = { ...timing, accumulatedActiveMillis };
  }
  timing = { ...timing, activeSince: transitionAt, restingUntil: null };
  try {
    return { timing: parseActiveWorkoutTimingEnvelope(timing, workout, account), raw: loaded.raw };
  } catch {
    return null;
  }
}

function parseActiveWorkoutRestTransitionEnvelope(input, workout, account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor || !workout) throw new Error("Active workout rest transition has no owner or workout.");
  let value = input;
  if (typeof input === "string") {
    if (activeWorkoutStorageByteLength(input) > MAX_ACTIVE_WORKOUT_REST_TRANSITION_STORAGE_BYTES) {
      throw new Error("Active workout rest transition is oversized.");
    }
    value = JSON.parse(input);
  }
  const root = activeWorkoutExactObject(value, "active workout rest transition", [
    "version", "owner", "workoutId", "workoutRevision", "timerKey", "transition",
    "transitionAt", "deadlineMillis", "timing"
  ]);
  const workoutId = activeWorkoutPositiveId(root.workoutId, "active workout rest transition.workoutId");
  const timer = parseExerciseRestTimerKey(root.timerKey);
  if (root.version !== 1 || root.owner !== descriptor.owner || workout.owner !== descriptor.owner ||
      workoutId !== workout.id || !Number.isSafeInteger(root.workoutRevision) ||
      root.workoutRevision !== workout.revision || !timer || timer.sessionId !== workout.id ||
      !workout.blocks.some(block => block.exerciseName === timer.exerciseName) ||
      !["rest", "active"].includes(root.transition)) {
    throw new Error("Active workout rest transition does not match the current workout.");
  }
  const transitionAt = activeWorkoutTimestamp(
    root.transitionAt,
    "active workout rest transition.transitionAt"
  );
  if (transitionAt < workout.createdAt) {
    throw new Error("Active workout rest transition predates the workout.");
  }
  const timing = parseActiveWorkoutTimingEnvelope(root.timing, workout, account);
  let deadlineMillis = null;
  if (root.transition === "rest") {
    deadlineMillis = activeWorkoutTimestamp(
      root.deadlineMillis,
      "active workout rest transition.deadlineMillis"
    );
    if (deadlineMillis <= transitionAt || deadlineMillis > transitionAt + MAX_ACTIVE_WORKOUT_REST_MS ||
        timing.activeSince !== null || timing.restingUntil !== deadlineMillis ||
        timing.accumulatedActiveMillis > transitionAt - workout.createdAt) {
      throw new Error("Active workout rest transition target is invalid.");
    }
  } else if (root.deadlineMillis !== null || timing.activeSince !== transitionAt ||
      timing.restingUntil !== null || timing.accumulatedActiveMillis > transitionAt - workout.createdAt) {
    throw new Error("Active workout stop transition target is invalid.");
  }
  return {
    version: 1,
    owner: descriptor.owner,
    workoutId,
    workoutRevision: root.workoutRevision,
    timerKey: timer.key,
    transition: root.transition,
    transitionAt,
    deadlineMillis,
    timing
  };
}

function persistActiveWorkoutRestTransitionMarker(marker, workout, account = activeAccount, expectedRaw = null) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor || !workout) return null;
  try {
    const parsed = parseActiveWorkoutRestTransitionEnvelope(marker, workout, account);
    const encoded = JSON.stringify(parsed);
    if (activeWorkoutStorageByteLength(encoded) > MAX_ACTIVE_WORKOUT_REST_TRANSITION_STORAGE_BYTES ||
        localStorage.getItem(descriptor.restTransitionKey) !== expectedRaw) return null;
    localStorage.setItem(descriptor.restTransitionKey, encoded);
    return localStorage.getItem(descriptor.restTransitionKey) === encoded
      ? { marker: parsed, raw: encoded }
      : null;
  } catch {
    return null;
  }
}

function removeActiveWorkoutRestTransitionStorage(account = activeAccount, expectedRaw = undefined) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) return false;
  try {
    const current = localStorage.getItem(descriptor.restTransitionKey);
    if (expectedRaw !== undefined && current !== expectedRaw) return false;
    localStorage.removeItem(descriptor.restTransitionKey);
    return localStorage.getItem(descriptor.restTransitionKey) === null;
  } catch {
    return false;
  }
}

function reconcileActiveWorkoutRestTransition(workout = activeWorkout, account = activeAccount, now = Date.now()) {
  const activeDescriptor = activeWorkoutAccountDescriptor(account);
  const timerDescriptor = exerciseRestTimerAccountDescriptor(account);
  if (!activeDescriptor || !timerDescriptor || !workout || !Number.isSafeInteger(now)) return false;
  let raw;
  let marker;
  try {
    raw = localStorage.getItem(activeDescriptor.restTransitionKey);
    if (raw === null) return true;
    marker = parseActiveWorkoutRestTransitionEnvelope(raw, workout, account);
  } catch {
    let removed = false;
    try {
      if (raw !== undefined && localStorage.getItem(activeDescriptor.restTransitionKey) === raw) {
        localStorage.removeItem(activeDescriptor.restTransitionKey);
        removed = localStorage.getItem(activeDescriptor.restTransitionKey) === null;
      }
    } catch {
      // An invalid marker is never applied to either account-bound state key.
    }
    return removed;
  }

  const restStillRunning = marker.transition === "rest" && now < marker.deadlineMillis;
  const targetTiming = restStillRunning
    ? marker.timing
    : marker.transition === "rest"
      ? { ...marker.timing, activeSince: marker.deadlineMillis, restingUntil: null }
      : marker.timing;
  if (localStorage.getItem(activeDescriptor.restTransitionKey) !== raw ||
      !persistActiveWorkoutTiming(targetTiming, workout, account)) return false;

  const loadedTimers = loadExerciseRestTimerLedger(account, now);
  const targetTimers = Object.assign(Object.create(null), loadedTimers.timers);
  if (restStillRunning) {
    for (const key of Object.keys(targetTimers)) delete targetTimers[key];
    targetTimers[marker.timerKey] = marker.deadlineMillis;
  } else {
    delete targetTimers[marker.timerKey];
  }
  if (localStorage.getItem(activeDescriptor.restTransitionKey) !== raw ||
      !persistExerciseRestTimers(targetTimers, account, now)) return false;
  exerciseRestTimerLedger = { owner: timerDescriptor.owner, timers: targetTimers };
  return removeActiveWorkoutRestTransitionStorage(account, raw);
}

function commitActiveWorkoutRestTransition(
  workout,
  timerKey,
  transition,
  transitionAt,
  deadlineMillis = null,
  account = activeAccount
) {
  const activeDescriptor = activeWorkoutAccountDescriptor(account);
  if (!activeDescriptor || !workout || workout.owner !== activeDescriptor.owner ||
      !reconcileActiveWorkoutRestTransition(workout, account, transitionAt)) return false;
  const target = transition === "rest"
    ? activeWorkoutTimingAfterRestTransition(workout, deadlineMillis, transitionAt, account)
    : transition === "active"
      ? activeWorkoutTimingAfterStopTransition(workout, transitionAt, account)
      : null;
  if (!target) return false;
  const stored = persistActiveWorkoutRestTransitionMarker({
    version: 1,
    owner: activeDescriptor.owner,
    workoutId: workout.id,
    workoutRevision: workout.revision,
    timerKey,
    transition,
    transitionAt,
    deadlineMillis,
    timing: target.timing
  }, workout, account, null);
  if (!stored) return false;
  return reconcileActiveWorkoutRestTransition(workout, account, transitionAt);
}

function parseActiveWorkoutBulkCleanupEnvelope(input, account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) throw new Error("Active workout bulk cleanup has no owner.");
  let value = input;
  if (typeof input === "string") {
    if (activeWorkoutStorageByteLength(input) > MAX_ACTIVE_WORKOUT_BULK_CLEANUP_STORAGE_BYTES) {
      throw new Error("Active workout bulk cleanup is oversized.");
    }
    value = JSON.parse(input);
  }
  const root = activeWorkoutExactObject(value, "active workout bulk cleanup", [
    "version", "owner", "workoutId", "fromRevision", "toRevision", "transitionAt", "targetRaw"
  ]);
  const workoutId = activeWorkoutPositiveId(root.workoutId, "active workout bulk cleanup.workoutId");
  if (root.version !== 1 || root.owner !== descriptor.owner ||
      !Number.isSafeInteger(root.fromRevision) || root.fromRevision < 1 ||
      !Number.isSafeInteger(root.toRevision) || root.toRevision !== root.fromRevision + 1) {
    throw new Error("Active workout bulk cleanup owner or revision is invalid.");
  }
  const transitionAt = activeWorkoutTimestamp(
    root.transitionAt,
    "active workout bulk cleanup.transitionAt"
  );
  if (typeof root.targetRaw !== "string" ||
      activeWorkoutStorageByteLength(root.targetRaw) > MAX_ACTIVE_WORKOUT_STORAGE_BYTES) {
    throw new Error("Active workout bulk cleanup target is oversized.");
  }
  const target = parseActiveWorkoutEnvelope(root.targetRaw, account);
  if (JSON.stringify(target) !== root.targetRaw || target.id !== workoutId ||
      target.revision !== root.toRevision || target.updatedAt !== transitionAt ||
      target.blocks.some(block => block.sets.some(set => !set.completed))) {
    throw new Error("Active workout bulk cleanup target is invalid.");
  }
  return {
    version: 1,
    owner: descriptor.owner,
    workoutId,
    fromRevision: root.fromRevision,
    toRevision: root.toRevision,
    transitionAt,
    targetRaw: root.targetRaw
  };
}

function persistActiveWorkoutBulkCleanupIntent(
  previousWorkout,
  nextWorkout,
  transitionAt,
  account = activeAccount,
  expectedRaw = null
) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor || !previousWorkout || !nextWorkout || previousWorkout.owner !== descriptor.owner ||
      nextWorkout.owner !== descriptor.owner || previousWorkout.id !== nextWorkout.id ||
      nextWorkout.revision !== previousWorkout.revision + 1 ||
      transitionAt !== nextWorkout.updatedAt || transitionAt < nextWorkout.createdAt ||
      nextWorkout.blocks.some(block => block.sets.some(set => !set.completed))) return null;
  try {
    const targetRaw = JSON.stringify(parseActiveWorkoutEnvelope(nextWorkout, account));
    const marker = parseActiveWorkoutBulkCleanupEnvelope({
      version: 1,
      owner: descriptor.owner,
      workoutId: nextWorkout.id,
      fromRevision: previousWorkout.revision,
      toRevision: nextWorkout.revision,
      transitionAt,
      targetRaw
    }, account);
    const encoded = JSON.stringify(marker);
    if (activeWorkoutStorageByteLength(encoded) > MAX_ACTIVE_WORKOUT_BULK_CLEANUP_STORAGE_BYTES ||
        localStorage.getItem(descriptor.bulkCleanupKey) !== expectedRaw) return null;
    localStorage.setItem(descriptor.bulkCleanupKey, encoded);
    return localStorage.getItem(descriptor.bulkCleanupKey) === encoded
      ? { marker, raw: encoded }
      : null;
  } catch {
    return null;
  }
}

function removeActiveWorkoutBulkCleanupStorage(account = activeAccount, expectedRaw = undefined) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) return false;
  try {
    const current = localStorage.getItem(descriptor.bulkCleanupKey);
    if (expectedRaw !== undefined && current !== expectedRaw) return false;
    localStorage.removeItem(descriptor.bulkCleanupKey);
    return localStorage.getItem(descriptor.bulkCleanupKey) === null;
  } catch {
    return false;
  }
}

function reconcileActiveWorkoutBulkCleanupIntent(workout, account = activeAccount, now = Date.now()) {
  const activeDescriptor = activeWorkoutAccountDescriptor(account);
  if (!activeDescriptor || !workout || !Number.isSafeInteger(now)) return false;
  let raw;
  let marker;
  try {
    raw = localStorage.getItem(activeDescriptor.bulkCleanupKey);
    if (raw === null) return true;
    marker = parseActiveWorkoutBulkCleanupEnvelope(raw, account);
  } catch {
    try {
      if (raw !== undefined && localStorage.getItem(activeDescriptor.bulkCleanupKey) === raw) {
        localStorage.removeItem(activeDescriptor.bulkCleanupKey);
        return localStorage.getItem(activeDescriptor.bulkCleanupKey) === null;
      }
    } catch {
      // An invalid cleanup intent never changes the active workout or its sidecars.
    }
    return false;
  }
  if (marker.workoutId !== workout.id || marker.owner !== workout.owner) {
    return removeActiveWorkoutBulkCleanupStorage(account, raw);
  }
  let currentWorkoutRaw;
  try {
    currentWorkoutRaw = localStorage.getItem(activeDescriptor.storageKey);
  } catch {
    return false;
  }
  if (currentWorkoutRaw !== marker.targetRaw) {
    return removeActiveWorkoutBulkCleanupStorage(account, raw);
  }
  if (workout.revision !== marker.toRevision || marker.transitionAt !== workout.updatedAt ||
      marker.transitionAt < workout.createdAt ||
      workout.blocks.some(block => block.sets.some(set => !set.completed))) return false;

  const undoLoaded = loadActiveWorkoutUndoRecord(workout, account);
  const undoCleared = removeActiveWorkoutUndoStorage(account, undoLoaded.raw);
  const timerLedger = loadExerciseRestTimerLedger(account, now);
  const workoutTimerKeys = Object.keys(timerLedger.timers).filter(key =>
    parseExerciseRestTimerKey(key)?.sessionId === workout.id
  );
  let timingResumed = true;
  if (workoutTimerKeys.length) {
    timingResumed = commitActiveWorkoutRestTransition(
      workout,
      workoutTimerKeys[0],
      "active",
      marker.transitionAt,
      null,
      account
    );
  } else {
    timingResumed = transitionActiveWorkoutTimingToActive(workout, marker.transitionAt, account);
  }
  const timersCleared = timingResumed && clearActiveWorkoutRestTimers(workout.id, account, now);
  if (!undoCleared || !timingResumed || !timersCleared) return false;
  const verifiedTiming = loadActiveWorkoutTimingRecord(workout, account).timing;
  const verifiedTimers = loadExerciseRestTimerLedger(account, now).timers;
  if (!verifiedTiming || verifiedTiming.restingUntil !== null ||
      Object.keys(verifiedTimers).some(key => parseExerciseRestTimerKey(key)?.sessionId === workout.id)) {
    return false;
  }
  if (activeWorkout?.id === workout.id && activeWorkout?.owner === workout.owner) {
    activeWorkoutUndoMarker = null;
    activeWorkoutUndoStorageRaw = null;
  }
  return removeActiveWorkoutBulkCleanupStorage(account, raw);
}

function activeWorkoutCompletedSnapshot(workout, account = activeAccount) {
  const parsed = parseActiveWorkoutEnvelope(workout, account);
  const blocks = parsed.blocks.flatMap(block => {
    const sets = block.sets.filter(set => set.completed);
    return sets.length ? [{ ...block, sets }] : [];
  });
  if (!blocks.length) return null;
  return parseActiveWorkoutEnvelope({ ...parsed, blocks }, account);
}

function loadActiveWorkoutCommitLedger(account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) return null;
  let raw;
  try {
    raw = localStorage.getItem(descriptor.commitKey);
    if (raw === null) {
      return { ledger: { version: 1, owner: descriptor.owner, workouts: [] }, raw: null };
    }
    if (activeWorkoutStorageByteLength(raw) > MAX_ACTIVE_WORKOUT_COMMIT_STORAGE_BYTES) return null;
    const value = activeWorkoutExactObject(JSON.parse(raw), "active workout commit ledger", [
      "version", "owner", "workouts"
    ]);
    const limits = window.GymStateContract.LIMITS;
    if (value.version !== 1 || value.owner !== descriptor.owner || !Array.isArray(value.workouts) ||
        value.workouts.length > limits.sessions) return null;
    const sessionIds = new Set();
    const setIds = new Set();
    let totalSets = 0;
    let migratedLegacyExerciseNameControls = false;
    const workouts = value.workouts.map((candidate, index) => {
      const parsed = parseActiveWorkoutEnvelope(candidate, account, {
        migrateLegacyExerciseNameControls: true,
        includeMigrationMetadata: true
      });
      const workout = parsed.workout;
      migratedLegacyExerciseNameControls = parsed.migratedLegacyExerciseNameControls ||
        migratedLegacyExerciseNameControls;
      if (sessionIds.has(workout.id)) throw new Error(`Duplicate commit session at ${index}.`);
      sessionIds.add(workout.id);
      for (const block of workout.blocks) {
        for (const set of block.sets) {
          if (!set.completed || setIds.has(set.id)) {
            throw new Error(`Invalid committed set at ${index}.`);
          }
          setIds.add(set.id);
          totalSets += 1;
          if (totalSets > limits.totalSets) throw new Error("Commit ledger exceeds the set limit.");
        }
      }
      return workout;
    });
    const ledger = { version: 1, owner: descriptor.owner, workouts };
    const effectiveRaw = migratedLegacyExerciseNameControls
      ? persistLocalExerciseNameMigration(
          descriptor.commitKey,
          raw,
          JSON.stringify(ledger),
          MAX_ACTIVE_WORKOUT_COMMIT_STORAGE_BYTES
        )
      : raw;
    return { ledger, raw: effectiveRaw };
  } catch {
    return null;
  }
}

function activeWorkoutCommitExercise(targetState, block) {
  const existing = targetState.exercises.find(exercise => exercisesMatch(exercise, block));
  if (existing) return existing;
  const limits = window.GymStateContract.LIMITS;
  if (targetState.exercises.length >= limits.exercises) return null;
  const catalogKey = persistedExerciseCatalogKey(block);
  const name = catalogKey && builtInExerciseByKey.has(catalogKey)
    ? builtInExerciseByKey.get(catalogKey).names.en
    : block.exerciseName;
  if (!isSupportedExerciseName(name)) return null;
  const usedIds = new Set(targetState.exercises.map(exercise => exercise.id));
  let id = block.id;
  for (let attempt = 0; attempt <= limits.exercises; attempt += 1) {
    if (Number.isSafeInteger(id) && id > 0 && !usedIds.has(id)) break;
    id = id >= Number.MAX_SAFE_INTEGER ? 1 : id + 1;
  }
  if (!Number.isSafeInteger(id) || id <= 0 || usedIds.has(id)) return null;
  const created = { id, name, ...(catalogKey ? { catalogKey } : {}) };
  targetState.exercises.push(created);
  targetState.exercises.sort((left, right) =>
    exerciseDisplayName(left, targetState.language)
      .localeCompare(exerciseDisplayName(right, targetState.language), targetState.language));
  return created;
}

function mergeActiveWorkoutCommitLedger(baseState, ledger, account = activeAccount) {
  if (!baseState || !ledger) return null;
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor || ledger.version !== 1 || ledger.owner !== descriptor.owner) return null;
  try {
    const merged = {
      ...baseState,
      exercises: baseState.exercises.map(exercise => ({ ...exercise })),
      sessions: baseState.sessions.map(session => ({
        ...session,
        sets: session.sets.map(set => ({ ...set }))
      }))
    };
    const limits = window.GymStateContract.LIMITS;
    for (const workout of ledger.workouts) {
      const completed = activeCompletedEntries(workout);
      if (!completed.length) return null;
      const matchingSessions = merged.sessions.filter(session => session.id === workout.id);
      if (matchingSessions.length > 1) return null;
      let session = matchingSessions[0] || null;
      if (session && (session.startedAt !== workout.startedAt || session.note !== workout.note)) return null;
      const otherSetIds = new Set(merged.sessions
        .filter(candidate => candidate.id !== workout.id)
        .flatMap(candidate => candidate.sets.map(set => set.id)));
      if (completed.some(entry => otherSetIds.has(entry.set.id))) return null;
      if (!session) {
        if (merged.sessions.length >= limits.sessions) return null;
        session = { id: workout.id, startedAt: workout.startedAt, note: workout.note, sets: [] };
        merged.sessions.push(session);
      }
      const existingSetIds = new Set(session.sets.map(set => set.id));
      for (const entry of completed) {
        if (existingSetIds.has(entry.set.id)) continue;
        if (session.sets.length >= limits.exercisesPerSession * limits.setsPerExercise) return null;
        const exercise = activeWorkoutCommitExercise(merged, entry.block);
        if (!exercise) return null;
        const catalogKey = persistedExerciseCatalogKey(exercise);
        session.sets.push({
          id: entry.set.id,
          exerciseName: exercise.name,
          ...(catalogKey ? { catalogKey } : {}),
          weight: entry.set.weight,
          reps: entry.set.reps,
          orderIndex: entry.setIndex
        });
        existingSetIds.add(entry.set.id);
      }
    }
    const normalized = validateImportedEnvelope({ schemaVersion: 2, ...merged }, defaultAppState()).state;
    if (normalized.sessions.length !== merged.sessions.length ||
        allSetsFromSessions(normalized.sessions).length !== allSetsFromSessions(merged.sessions).length) return null;
    return normalized;
  } catch {
    return null;
  }
}

function activeWorkoutCommitCanReplace(previous, next) {
  if (previous.id !== next.id || previous.startedAt !== next.startedAt || previous.note !== next.note) return false;
  const nextEntries = new Map(activeCompletedEntries(next).map(entry => [entry.set.id, entry]));
  return activeCompletedEntries(previous).every(entry => {
    const candidate = nextEntries.get(entry.set.id);
    return candidate && historySetMatchesActiveEntry({
      id: candidate.set.id,
      exerciseName: candidate.block.exerciseName,
      ...(candidate.block.catalogKey ? { catalogKey: candidate.block.catalogKey } : {}),
      weight: candidate.set.weight,
      reps: candidate.set.reps
    }, entry);
  });
}

function persistActiveWorkoutCommit(workout, account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  const loaded = loadActiveWorkoutCommitLedger(account);
  const completed = activeWorkoutCompletedSnapshot(workout, account);
  if (!descriptor || !loaded || !completed) return null;
  const existingIndex = loaded.ledger.workouts.findIndex(candidate => candidate.id === completed.id);
  const workouts = [...loaded.ledger.workouts];
  if (existingIndex >= 0) {
    if (!activeWorkoutCommitCanReplace(workouts[existingIndex], completed)) return null;
    workouts[existingIndex] = completed;
  } else {
    workouts.push(completed);
  }
  const ledger = { version: 1, owner: descriptor.owner, workouts };
  const baseState = loadStoredStateBase(account);
  const mergedState = mergeActiveWorkoutCommitLedger(baseState, ledger, account);
  if (!mergedState) return null;
  try {
    const encoded = JSON.stringify(ledger);
    if (activeWorkoutStorageByteLength(encoded) > MAX_ACTIVE_WORKOUT_COMMIT_STORAGE_BYTES ||
        localStorage.getItem(descriptor.commitKey) !== loaded.raw) return null;
    localStorage.setItem(descriptor.commitKey, encoded);
    if (localStorage.getItem(descriptor.commitKey) !== encoded) return null;
    return { state: mergedState, raw: encoded };
  } catch {
    return null;
  }
}

function removeActiveWorkoutCommitStorage(account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) return false;
  try {
    localStorage.removeItem(descriptor.commitKey);
    return localStorage.getItem(descriptor.commitKey) === null;
  } catch {
    return false;
  }
}

function rewriteActiveWorkoutCommitLedger(transform, account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  const loaded = loadActiveWorkoutCommitLedger(account);
  if (!descriptor || !loaded || typeof transform !== "function") return null;
  try {
    const workouts = transform(loaded.ledger.workouts.map(workout => ({
      ...workout,
      blocks: workout.blocks.map(block => ({
        ...block,
        sets: block.sets.map(set => ({ ...set }))
      }))
    })));
    if (!Array.isArray(workouts)) return null;
    const nextLedger = { version: 1, owner: descriptor.owner, workouts };
    const parsed = workouts.length
      ? (() => {
          const encoded = JSON.stringify(nextLedger);
          if (activeWorkoutStorageByteLength(encoded) > MAX_ACTIVE_WORKOUT_COMMIT_STORAGE_BYTES) return null;
          const candidate = { ledger: nextLedger, raw: encoded };
          // Reuse the strict parser by temporarily validating the encoded value
          // before any storage mutation.
          if (nextLedger.workouts.some(workout => !activeWorkoutCompletedSnapshot(workout, account))) return null;
          return candidate;
        })()
      : { ledger: nextLedger, raw: null };
    if (!parsed || localStorage.getItem(descriptor.commitKey) !== loaded.raw) return null;
    if (parsed.raw === null) localStorage.removeItem(descriptor.commitKey);
    else localStorage.setItem(descriptor.commitKey, parsed.raw);
    if (localStorage.getItem(descriptor.commitKey) !== parsed.raw) return null;
    return { previousRaw: loaded.raw, raw: parsed.raw };
  } catch {
    return null;
  }
}

function restoreActiveWorkoutCommitLedger(raw, account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) return false;
  try {
    restoreStorageValue(descriptor.commitKey, raw);
    return localStorage.getItem(descriptor.commitKey) === raw;
  } catch {
    return false;
  }
}

function loadActiveWorkoutRecord(account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) return { workout: null, raw: null };
  let raw = null;
  try {
    raw = localStorage.getItem(descriptor.storageKey);
    if (raw === null) return { workout: null, raw: null };
    const parsed = parseActiveWorkoutEnvelope(raw, account, {
      migrateLegacyExerciseNameControls: true,
      includeMigrationMetadata: true
    });
    const effectiveRaw = parsed.migratedLegacyExerciseNameControls
      ? persistLocalExerciseNameMigration(
          descriptor.storageKey,
          raw,
          JSON.stringify(parsed.workout),
          MAX_ACTIVE_WORKOUT_STORAGE_BYTES
        )
      : raw;
    return { workout: parsed.workout, raw: effectiveRaw };
  } catch {
    // Never delete an unreadable or future-version draft. A bounded, account-scoped
    // recovery copy makes rollback/forward incompatibility recoverable, while the
    // original key remains fail-closed until a compatible client can read it.
    if (raw !== null) scheduleActiveWorkoutRecoveryRaw(raw, descriptor);
    return { workout: null, raw: null };
  }
}

function persistActiveWorkoutRecord(value, account = activeAccount, expectedRaw = undefined) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) return null;
  try {
    const workout = parseActiveWorkoutEnvelope(value, account);
    const encoded = JSON.stringify(workout);
    if (new TextEncoder().encode(encoded).byteLength > MAX_ACTIVE_WORKOUT_STORAGE_BYTES) return null;
    const current = localStorage.getItem(descriptor.storageKey);
    if (expectedRaw !== undefined && current !== expectedRaw) return null;
    localStorage.setItem(descriptor.storageKey, encoded);
    if (localStorage.getItem(descriptor.storageKey) !== encoded) return null;
    return { workout, raw: encoded };
  } catch {
    return null;
  }
}

function removeActiveWorkoutStorage(account = activeAccount, expectedRaw = undefined) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor) return false;
  try {
    const current = localStorage.getItem(descriptor.storageKey);
    if (expectedRaw !== undefined && current !== expectedRaw) return false;
    localStorage.removeItem(descriptor.storageKey);
    return localStorage.getItem(descriptor.storageKey) === null;
  } catch {
    return false;
  }
}

function reloadActiveWorkoutContext(account = activeAccount) {
  const loaded = loadActiveWorkoutRecord(account);
  const undoLoaded = loadActiveWorkoutUndoRecord(loaded.workout, account);
  activeWorkout = loaded.workout;
  activeWorkoutStorageRaw = loaded.raw;
  activeWorkoutUndoMarker = undoLoaded.marker;
  activeWorkoutUndoStorageRaw = undoLoaded.raw;
  exerciseRestTimerLedger = null;
  if (activeWorkout) scheduleActiveWorkoutControlReconciliation(activeWorkout, account);
  return activeWorkout;
}

function clearActiveWorkoutMemory() {
  activeWorkout = null;
  activeWorkoutStorageRaw = null;
  activeWorkoutUndoMarker = null;
  activeWorkoutUndoStorageRaw = null;
  activeWorkoutControlReconciliationPromise = null;
  activeWorkoutUi = { status: "idle", message: "" };
}

function scheduleActiveWorkoutControlReconciliation(workout = activeWorkout, account = activeAccount) {
  const descriptor = activeWorkoutAccountDescriptor(account);
  if (!descriptor || !workout) return Promise.resolve(false);
  if (activeWorkoutControlReconciliationPromise) return activeWorkoutControlReconciliationPromise;
  try {
    if (localStorage.getItem(descriptor.restTransitionKey) === null &&
        localStorage.getItem(descriptor.bulkCleanupKey) === null) return Promise.resolve(true);
  } catch {
    return Promise.resolve(false);
  }
  const mutationContext = activeWorkoutMutationContext(account);
  if (!mutationContext) return Promise.resolve(false);
  const pending = withActiveWorkoutMutationLock(descriptor, () => {
    if (!activeWorkoutMutationContextIsCurrent(mutationContext)) return false;
    const loaded = loadActiveWorkoutRecord(mutationContext.account);
    if (!loaded.workout) return false;
    const restReconciled = reconcileActiveWorkoutRestTransition(
      loaded.workout,
      mutationContext.account
    );
    const bulkReconciled = restReconciled && reconcileActiveWorkoutBulkCleanupIntent(
      loaded.workout,
      mutationContext.account
    );
    if (!bulkReconciled || !activeWorkoutMutationContextIsCurrent(mutationContext)) return false;
    const refreshed = loadActiveWorkoutRecord(mutationContext.account);
    const undoLoaded = loadActiveWorkoutUndoRecord(refreshed.workout, mutationContext.account);
    if (activeWorkoutAccountDescriptor()?.owner === descriptor.owner) {
      activeWorkout = refreshed.workout;
      activeWorkoutStorageRaw = refreshed.raw;
      activeWorkoutUndoMarker = undoLoaded.marker;
      activeWorkoutUndoStorageRaw = undoLoaded.raw;
      exerciseRestTimerLedger = null;
    }
    return true;
  }).then(result => {
    if (result.acquired && result.value === true &&
        activeWorkoutAccountDescriptor()?.owner === descriptor.owner) render();
    return result.acquired && result.value === true;
  }).catch(() => false).finally(() => {
    if (activeWorkoutControlReconciliationPromise === pending) {
      activeWorkoutControlReconciliationPromise = null;
    }
  });
  activeWorkoutControlReconciliationPromise = pending;
  return pending;
}

function exerciseRestTimerAccountDescriptor(account = activeAccount) {
  if (account == null) {
    return { owner: "guest", storageKey: `${EXERCISE_REST_TIMER_PREFIX}guest` };
  }
  const normalized = normalizeStoredAccount(account);
  if (!normalized) return null;
  return {
    owner: normalized.remote === "supabase"
      ? `supabase:${normalized.userId}`
      : `local:${normalized.id}`,
    storageKey: `${EXERCISE_REST_TIMER_PREFIX}${normalized.id}`
  };
}

function parseExerciseRestTimerKey(value) {
  if (typeof value !== "string" || value.length > 700) return null;
  const separator = value.indexOf(":");
  if (separator < 1) return null;
  const rawSessionId = value.slice(0, separator);
  const exerciseName = value.slice(separator + 1);
  if (!/^\d{1,16}$/.test(rawSessionId) || !isSupportedExerciseName(exerciseName) ||
      exerciseName !== exerciseName.trim()) return null;
  const sessionId = Number(rawSessionId);
  if (!Number.isSafeInteger(sessionId) || sessionId <= 0) return null;
  return { key: `${sessionId}:${exerciseName}`, sessionId, exerciseName };
}

function exerciseRestTimerTarget(value) {
  const parsed = parseExerciseRestTimerKey(value);
  if (!parsed) return null;
  const session = state.sessions.find(item => item.id === parsed.sessionId);
  const activeMatch = activeWorkout?.id === parsed.sessionId && activeWorkout.blocks.some(
    block => block.exerciseName === parsed.exerciseName
  );
  if ((!session || !session.sets.some(set => set.exerciseName === parsed.exerciseName)) && !activeMatch) {
    return null;
  }
  return parsed;
}

function persistExerciseRestTimers(timers, account = activeAccount, now = Date.now()) {
  const descriptor = exerciseRestTimerAccountDescriptor(account);
  if (!descriptor || !Number.isSafeInteger(now) || now < 0 ||
      now > Number.MAX_SAFE_INTEGER - MAX_EXERCISE_REST_TIMER_MS ||
      !timers || typeof timers !== "object" || Array.isArray(timers)) return false;
  const entries = [];
  const seen = new Set();
  for (const [rawKey, deadlineMillis] of Object.entries(timers)) {
    const parsed = parseExerciseRestTimerKey(rawKey);
    if (!parsed || parsed.key !== rawKey || seen.has(rawKey) ||
        !Number.isSafeInteger(deadlineMillis) || deadlineMillis <= now ||
        deadlineMillis > now + MAX_EXERCISE_REST_TIMER_MS) return false;
    seen.add(rawKey);
    entries.push({
      sessionId: parsed.sessionId,
      exerciseName: parsed.exerciseName,
      deadlineMillis
    });
  }
  if (entries.length > MAX_EXERCISE_REST_TIMERS) return false;
  entries.sort((left, right) => left.sessionId - right.sessionId ||
    left.exerciseName.localeCompare(right.exerciseName, "en"));
  try {
    if (!entries.length) {
      localStorage.removeItem(descriptor.storageKey);
      return localStorage.getItem(descriptor.storageKey) === null;
    }
    const encoded = JSON.stringify({ version: 1, owner: descriptor.owner, entries });
    if (new TextEncoder().encode(encoded).byteLength > MAX_EXERCISE_REST_TIMER_STORAGE_BYTES) {
      return false;
    }
    localStorage.setItem(descriptor.storageKey, encoded);
    return localStorage.getItem(descriptor.storageKey) === encoded;
  } catch {
    return false;
  }
}

function loadExerciseRestTimerLedger(account = activeAccount, now = Date.now()) {
  const descriptor = exerciseRestTimerAccountDescriptor(account);
  const empty = { owner: descriptor?.owner || null, timers: Object.create(null) };
  if (!descriptor || !Number.isSafeInteger(now) || now < 0 ||
      now > Number.MAX_SAFE_INTEGER - MAX_EXERCISE_REST_TIMER_MS) return empty;
  let raw;
  try {
    raw = localStorage.getItem(descriptor.storageKey);
    if (!raw) return empty;
    if (new TextEncoder().encode(raw).byteLength > MAX_EXERCISE_REST_TIMER_STORAGE_BYTES) {
      throw new Error("Exercise rest timer storage is oversized.");
    }
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) ||
        Object.keys(parsed).sort().join(",") !== "entries,owner,version" ||
        parsed.version !== 1 || parsed.owner !== descriptor.owner ||
        !Array.isArray(parsed.entries) || parsed.entries.length > MAX_EXERCISE_REST_TIMERS) {
      throw new Error("Exercise rest timer storage is malformed.");
    }
    const timers = Object.create(null);
    for (const entry of parsed.entries) {
      if (!entry || typeof entry !== "object" || Array.isArray(entry) ||
          Object.keys(entry).sort().join(",") !== "deadlineMillis,exerciseName,sessionId") {
        throw new Error("Exercise rest timer entry is malformed.");
      }
      const key = `${entry.sessionId}:${entry.exerciseName}`;
      const normalizedKey = parseExerciseRestTimerKey(key);
      if (!normalizedKey || normalizedKey.sessionId !== entry.sessionId ||
          normalizedKey.exerciseName !== entry.exerciseName ||
          !Number.isSafeInteger(entry.deadlineMillis) ||
          entry.deadlineMillis > now + MAX_EXERCISE_REST_TIMER_MS ||
          Object.hasOwn(timers, normalizedKey.key)) {
        throw new Error("Exercise rest timer entry is outside supported limits.");
      }
      if (entry.deadlineMillis <= now) {
        continue;
      }
      timers[normalizedKey.key] = entry.deadlineMillis;
    }
    return { owner: descriptor.owner, timers };
  } catch {
    // Reads quarantine malformed or stale values in memory only. Durable pruning
    // here could race a newer tab and overwrite a freshly committed timer.
    return empty;
  }
}

function currentExerciseRestTimers(now = Date.now()) {
  const descriptor = exerciseRestTimerAccountDescriptor();
  if (!descriptor) return Object.create(null);
  if (activeWorkout) scheduleActiveWorkoutControlReconciliation(activeWorkout, activeAccount);
  if (!exerciseRestTimerLedger || exerciseRestTimerLedger.owner !== descriptor.owner) {
    exerciseRestTimerLedger = loadExerciseRestTimerLedger(activeAccount, now);
  }
  const current = exerciseRestTimerLedger.timers;
  const filtered = Object.create(null);
  let changed = false;
  for (const [key, deadline] of Object.entries(current)) {
    if (deadline > now && deadline <= now + MAX_EXERCISE_REST_TIMER_MS &&
        exerciseRestTimerTarget(key)) {
      filtered[key] = deadline;
    } else {
      changed = true;
    }
  }
  if (changed) {
    exerciseRestTimerLedger = { owner: descriptor.owner, timers: filtered };
  }
  return changed ? filtered : current;
}

function startExerciseRestTimerLocked(key, seconds, now = Date.now()) {
  const target = exerciseRestTimerTarget(key);
  if (!target || !Number.isInteger(seconds) || seconds < 1 ||
      seconds * 1000 > MAX_EXERCISE_REST_TIMER_MS ||
      !Number.isSafeInteger(now) || now < 0 ||
      now > Number.MAX_SAFE_INTEGER - seconds * 1000) return false;
  const descriptor = exerciseRestTimerAccountDescriptor();
  if (!descriptor) return false;
  if (activeWorkout?.id === target.sessionId && now >= activeWorkout.createdAt) {
    return commitActiveWorkoutRestTransition(
      activeWorkout,
      target.key,
      "rest",
      now,
      now + seconds * 1000
    );
  }
  // A person can only be in one current rest interval. Replacing the ledger also
  // prevents stale per-exercise countdowns from surviving a superset/navigation change.
  const next = Object.create(null);
  next[target.key] = now + seconds * 1000;
  if (!persistExerciseRestTimers(next, activeAccount, now)) return false;
  exerciseRestTimerLedger = { owner: descriptor.owner, timers: next };
  return true;
}

function adjustExerciseRestTimerLocked(key, deltaSeconds, now = Date.now()) {
  const target = exerciseRestTimerTarget(key);
  if (!target || !Number.isInteger(deltaSeconds) || Math.abs(deltaSeconds) > 300) return false;
  const deadline = currentExerciseRestTimers(now)[target.key];
  if (!Number.isSafeInteger(deadline) || deadline <= now) return false;
  const currentSeconds = Math.max(1, Math.ceil((deadline - now) / 1000));
  const adjustedSeconds = currentSeconds + deltaSeconds;
  if (adjustedSeconds <= 0) return stopExerciseRestTimerLocked(target.key, now);
  const nextSeconds = clamp(adjustedSeconds, 1, 30 * 60);
  return startExerciseRestTimerLocked(target.key, nextSeconds, now);
}

function stopExerciseRestTimerLocked(key, now = Date.now()) {
  const target = exerciseRestTimerTarget(key);
  if (!target) return false;
  const descriptor = exerciseRestTimerAccountDescriptor();
  if (!descriptor) return false;
  const previous = Object.assign(Object.create(null), currentExerciseRestTimers(now));
  const next = Object.assign(Object.create(null), previous);
  if (!Object.hasOwn(next, target.key)) {
    return activeWorkout?.id === target.sessionId && now >= activeWorkout.createdAt
      ? transitionActiveWorkoutTimingToActive(activeWorkout, now)
      : true;
  }
  if (activeWorkout?.id === target.sessionId && now >= activeWorkout.createdAt) {
    return commitActiveWorkoutRestTransition(activeWorkout, target.key, "active", now);
  }
  delete next[target.key];
  if (!persistExerciseRestTimers(next, activeAccount, now)) return false;
  exerciseRestTimerLedger = { owner: descriptor.owner, timers: next };
  return true;
}

function mutateExerciseRestTimer(operation, key, value, now = Date.now()) {
  const parsed = parseExerciseRestTimerKey(key);
  if (!parsed || !Number.isSafeInteger(now)) return false;
  const lockedMutation = () => operation === "start"
    ? startExerciseRestTimerLocked(parsed.key, value, now)
    : operation === "adjust"
      ? adjustExerciseRestTimerLocked(parsed.key, value, now)
      : operation === "stop"
        ? stopExerciseRestTimerLocked(parsed.key, now)
        : false;
  if (activeWorkout?.id !== parsed.sessionId) return lockedMutation();

  const mutationContext = activeWorkoutMutationContext();
  const expectedWorkoutId = activeWorkout?.id;
  const expectedRevision = activeWorkout?.revision;
  const expectedRaw = activeWorkoutStorageRaw;
  if (!mutationContext || !Number.isSafeInteger(expectedWorkoutId) ||
      !Number.isSafeInteger(expectedRevision) || typeof expectedRaw !== "string") return false;
  return withActiveWorkoutMutationLock(mutationContext.descriptor, () => {
    if (!activeWorkoutMutationContextIsCurrent(mutationContext)) return false;
    const loaded = loadActiveWorkoutRecord(mutationContext.account);
    if (!loaded.workout || loaded.raw !== expectedRaw || loaded.workout.id !== expectedWorkoutId ||
        loaded.workout.revision !== expectedRevision) {
      reloadActiveWorkoutContext(mutationContext.account);
      return false;
    }
    // Complete any write-ahead transition before reading the ledger used by this
    // mutation. Otherwise a crash after timing-but-before-ledger could let the next
    // adjustment calculate from the older durable deadline and lose its own delta.
    if (!reconcileActiveWorkoutRestTransition(loaded.workout, mutationContext.account, now)) {
      reloadActiveWorkoutContext(mutationContext.account);
      return false;
    }
    let hasBulkCleanupIntent = false;
    try {
      hasBulkCleanupIntent = localStorage.getItem(mutationContext.descriptor.bulkCleanupKey) !== null;
    } catch {
      return false;
    }
    if (hasBulkCleanupIntent) {
      reconcileActiveWorkoutBulkCleanupIntent(loaded.workout, mutationContext.account, now);
      reloadActiveWorkoutContext(mutationContext.account);
      return false;
    }
    const undoLoaded = loadActiveWorkoutUndoRecord(loaded.workout, mutationContext.account);
    activeWorkout = loaded.workout;
    activeWorkoutStorageRaw = loaded.raw;
    activeWorkoutUndoMarker = undoLoaded.marker;
    activeWorkoutUndoStorageRaw = undoLoaded.raw;
    // The Web Lock serializes durable writes, but each tab still owns an in-memory
    // projection. Refresh it only after acquiring the lock so an adjustment cannot
    // be calculated from a deadline cached before another tab's committed change.
    exerciseRestTimerLedger = loadExerciseRestTimerLedger(mutationContext.account, now);
    const changed = lockedMutation();
    return changed && activeWorkoutMutationContextIsCurrent(mutationContext);
  }).then(result => {
    if (!result.acquired) return activeWorkoutMutationUnavailable(mutationContext);
    return result.value === true;
  });
}

function startExerciseRestTimer(key, seconds, now = Date.now()) {
  return mutateExerciseRestTimer("start", key, seconds, now);
}

function adjustExerciseRestTimer(key, deltaSeconds, now = Date.now()) {
  return mutateExerciseRestTimer("adjust", key, deltaSeconds, now);
}

function stopExerciseRestTimer(key, now = Date.now()) {
  return mutateExerciseRestTimer("stop", key, null, now);
}

function removeExerciseRestTimerStorage(account) {
  const descriptor = exerciseRestTimerAccountDescriptor(account);
  if (!descriptor) return false;
  try {
    localStorage.removeItem(descriptor.storageKey);
    const removed = localStorage.getItem(descriptor.storageKey) === null;
    if (removed && exerciseRestTimerLedger?.owner === descriptor.owner) {
      exerciseRestTimerLedger = { owner: descriptor.owner, timers: Object.create(null) };
    }
    return removed;
  } catch {
    return false;
  }
}

function clearActiveWorkoutRestTimers(workoutId, account = activeAccount, now = Date.now()) {
  if (!Number.isSafeInteger(workoutId) || workoutId <= 0) return false;
  const descriptor = exerciseRestTimerAccountDescriptor(account);
  if (!descriptor) return false;
  if (activeWorkout?.id === workoutId && !reconcileActiveWorkoutRestTransition(activeWorkout, account, now)) {
    return false;
  }
  const loaded = loadExerciseRestTimerLedger(account, now);
  const next = Object.assign(Object.create(null), loaded.timers);
  let changed = false;
  for (const key of Object.keys(next)) {
    const parsed = parseExerciseRestTimerKey(key);
    if (parsed?.sessionId !== workoutId) continue;
    delete next[key];
    changed = true;
  }
  if (!changed) return true;
  if (!persistExerciseRestTimers(next, account, now)) return false;
  if (exerciseRestTimerLedger?.owner === descriptor.owner) {
    exerciseRestTimerLedger = { owner: descriptor.owner, timers: next };
  }
  return true;
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
  const webPushVapidPublicKey = String(config.webPushVapidPublicKey || "").trim();
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
    anonKey: anonKey.length >= 8 && anonKey.length <= 4096 && !/\s/.test(anonKey) ? anonKey : "",
    webPushVapidPublicKey: /^B[A-Za-z0-9_-]{86}$/.test(webPushVapidPublicKey)
      ? webPushVapidPublicKey
      : ""
  };
}

function remoteAuthEnabled() {
  const config = supabaseConfig();
  return Boolean(config.url && config.anonKey);
}

function webPushSupported() {
  return Boolean(
    navigator.serviceWorker &&
    typeof window.PushManager === "function" &&
    window.Notification &&
    typeof window.Notification.requestPermission === "function"
  );
}

function sharedActiveAccountMatches(account = activeAccount) {
  const expected = normalizeStoredAccount(account);
  if (!expected) return false;
  try {
    const raw = localStorage.getItem(AUTH_KEY);
    if (!raw || new TextEncoder().encode(raw).byteLength > MAX_LOCAL_ACCOUNT_STORAGE_BYTES) {
      return false;
    }
    const shared = normalizeStoredAccount(JSON.parse(raw));
    return expected.remote === "supabase"
      ? shared?.remote === "supabase" && shared.userId === expected.userId && shared.id === expected.id
      : !shared?.remote && shared?.id === expected.id && shared?.name === expected.name;
  } catch {
    return false;
  }
}

function webPushSource(session = loadRemoteSession()) {
  const identity = liveSessionIdentity(session);
  return identity && activeAccount?.remote === "supabase" && activeAccount.userId === identity.userId &&
      sharedActiveAccountMatches(activeAccount)
    ? `${identity.userId}:${identity.sessionId}`
    : null;
}

function webPushContextIsCurrent(source, expectedEpoch, expectedUserId, session = loadRemoteSession()) {
  return !accountTransitionInProgress && expectedEpoch === accountEpoch &&
    activeAccount?.userId === expectedUserId && sharedActiveAccountMatches(activeAccount) &&
    webPushSource(session) === source;
}

function webPushPreferenceEnabled() {
  try {
    return localStorage.getItem(WEB_PUSH_ENABLED_KEY) === "1";
  } catch {
    return false;
  }
}

function setWebPushPreference(enabled) {
  try {
    if (enabled) localStorage.setItem(WEB_PUSH_ENABLED_KEY, "1");
    else localStorage.removeItem(WEB_PUSH_ENABLED_KEY);
    return enabled ? localStorage.getItem(WEB_PUSH_ENABLED_KEY) === "1" :
      localStorage.getItem(WEB_PUSH_ENABLED_KEY) === null;
  } catch {
    return false;
  }
}

function storedWebPushInstallationId() {
  try {
    const stored = localStorage.getItem(WEB_PUSH_INSTALLATION_KEY);
    return UUID_V4_PATTERN.test(stored || "") ? stored.toLowerCase() : null;
  } catch {
    return null;
  }
}

function webPushInstallationId() {
  try {
    const stored = storedWebPushInstallationId();
    if (stored) return stored;
    const installationId = newUuidV4();
    localStorage.setItem(WEB_PUSH_INSTALLATION_KEY, installationId);
    return localStorage.getItem(WEB_PUSH_INSTALLATION_KEY) === installationId
      ? installationId
      : null;
  } catch {
    return null;
  }
}

function webPushPublicKeyBytes() {
  const value = supabaseConfig().webPushVapidPublicKey;
  if (!value) return null;
  try {
    const padded = value.replaceAll("-", "+").replaceAll("_", "/") +
      "=".repeat((4 - value.length % 4) % 4);
    const bytes = Uint8Array.from(atob(padded), character => character.charCodeAt(0));
    return bytes.byteLength === 65 && bytes[0] === 4 ? bytes : null;
  } catch {
    return null;
  }
}

function webPushEndpointAllowed(rawEndpoint) {
  if (typeof rawEndpoint !== "string" || rawEndpoint.length < 32 || rawEndpoint.length > 2048) {
    return false;
  }
  try {
    const endpoint = new URL(rawEndpoint);
    const host = endpoint.hostname.toLowerCase();
    return endpoint.protocol === "https:" && !endpoint.username && !endpoint.password &&
      !endpoint.hash && endpoint.port === "" && (
        ["fcm.googleapis.com", "updates.push.services.mozilla.com", "web.push.apple.com"].includes(host) ||
        /^[a-z0-9-]+\.notify\.windows\.com$/.test(host)
      );
  } catch {
    return false;
  }
}

function webPushSubscriptionMaterial(subscription) {
  const value = subscription?.toJSON?.();
  const endpoint = value?.endpoint;
  const p256dh = value?.keys?.p256dh;
  const auth = value?.keys?.auth;
  if (!webPushEndpointAllowed(endpoint) || typeof p256dh !== "string" ||
      !/^[A-Za-z0-9_-]{80,120}$/.test(p256dh) || typeof auth !== "string" ||
      !/^[A-Za-z0-9_-]{20,64}$/.test(auth) ||
      Object.keys(value).some(key => !["endpoint", "expirationTime", "keys"].includes(key)) ||
      Object.keys(value.keys || {}).sort().join(",") !== "auth,p256dh") {
    throw new TypeError("Web Push subscription is invalid.");
  }
  return { endpoint, p256dh, auth };
}

function parseWebPushRegistration(value, expectedInstallationId) {
  const row = socialExactObject(value, [
    "version", "installationId", "provider", "environment", "bindingId",
    "registrationRevision", "registeredAt"
  ]);
  if (row.version !== 1 || row.installationId !== expectedInstallationId ||
      row.provider !== "web_push" || row.environment !== "production" ||
      !UUID_V4_PATTERN.test(row.bindingId || "")) {
    throw new TypeError("Web Push registration acknowledgement is invalid.");
  }
  return {
    ...row,
    bindingId: row.bindingId.toLowerCase(),
    registrationRevision: socialInteger(row.registrationRevision, 1, 2147483647),
    registeredAt: socialTimestamp(row.registeredAt)
  };
}

function parseWebPushRevocation(value, expectedInstallationId) {
  const row = socialExactObject(value, ["version", "installationId", "revoked"]);
  if (row.version !== 1 || row.installationId !== expectedInstallationId ||
      typeof row.revoked !== "boolean") {
    throw new TypeError("Web Push revocation acknowledgement is invalid.");
  }
  return row;
}

function parseStoredWebPushBinding(value) {
  const row = socialExactObject(value, ["version", "bindingId", "ownerId"]);
  if (row.version !== 1 || !UUID_V4_PATTERN.test(row.bindingId || "") ||
      !UUID_V4_PATTERN.test(row.ownerId || "")) {
    throw new TypeError("Stored Web Push binding is invalid.");
  }
  return {
    version: 1,
    bindingId: row.bindingId.toLowerCase(),
    ownerId: row.ownerId.toLowerCase()
  };
}

function parseStoredWebPushTransition(value) {
  const row = socialExactObject(value, ["version", "nextOwnerId"]);
  if (row.version !== 1 || (row.nextOwnerId !== null &&
      !UUID_V4_PATTERN.test(row.nextOwnerId || ""))) {
    throw new TypeError("Stored Web Push transition is invalid.");
  }
  return {
    version: 1,
    nextOwnerId: row.nextOwnerId === null ? null : row.nextOwnerId.toLowerCase()
  };
}

function openWebPushBindingDatabase() {
  return new Promise((resolve, reject) => {
    if (!window.indexedDB) {
      reject(new Error("Web Push binding storage is unavailable."));
      return;
    }
    const request = window.indexedDB.open(WEB_PUSH_BINDING_DB_NAME, WEB_PUSH_BINDING_DB_VERSION);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(WEB_PUSH_BINDING_STORE_NAME)) {
        database.createObjectStore(WEB_PUSH_BINDING_STORE_NAME);
      }
    };
    request.onerror = () => reject(request.error || new Error("Web Push binding storage failed."));
    request.onblocked = () => reject(new Error("Web Push binding storage is blocked."));
    request.onsuccess = () => resolve(request.result);
  });
}

async function readStoredWebPushBinding() {
  const database = await openWebPushBindingDatabase();
  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(WEB_PUSH_BINDING_STORE_NAME, "readonly");
      const store = transaction.objectStore(WEB_PUSH_BINDING_STORE_NAME);
      const request = store.get(WEB_PUSH_BINDING_RECORD_KEY);
      const transitionRequest = store.get(WEB_PUSH_BINDING_TRANSITION_KEY);
      let stored = null;
      let transitionBlocked = false;
      request.onsuccess = () => {
        try {
          stored = request.result === undefined ? null : parseStoredWebPushBinding(request.result);
        } catch {
          stored = null;
        }
      };
      transitionRequest.onsuccess = () => {
        if (transitionRequest.result === undefined) return;
        transitionBlocked = true;
      };
      request.onerror = () => reject(request.error || new Error("Web Push binding read failed."));
      transitionRequest.onerror = () => reject(
        transitionRequest.error || new Error("Web Push transition read failed.")
      );
      transaction.onabort = () => reject(transaction.error || new Error("Web Push binding read aborted."));
      transaction.onerror = () => {};
      transaction.oncomplete = () => resolve(transitionBlocked ? null : stored);
    });
  } finally {
    database.close();
  }
}

async function mutateStoredWebPushBinding(decide) {
  const database = await openWebPushBindingDatabase();
  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(WEB_PUSH_BINDING_STORE_NAME, "readwrite");
      const store = transaction.objectStore(WEB_PUSH_BINDING_STORE_NAME);
      const request = store.get(WEB_PUSH_BINDING_RECORD_KEY);
      const transitionRequest = store.get(WEB_PUSH_BINDING_TRANSITION_KEY);
      let result = false;
      let current = null;
      let malformed = false;
      let transition = null;
      let malformedTransition = false;
      let completedReads = 0;
      const applyDecision = () => {
        completedReads += 1;
        if (completedReads !== 2) return;
        const action = decide(current, malformed, transition, malformedTransition) || {};
        if (action.current === "put") {
          store.put(parseStoredWebPushBinding(action.value), WEB_PUSH_BINDING_RECORD_KEY);
        } else if (action.current === "delete") {
          store.delete(WEB_PUSH_BINDING_RECORD_KEY);
        }
        if (action.transition === "put") {
          store.put(
            parseStoredWebPushTransition(action.transitionValue),
            WEB_PUSH_BINDING_TRANSITION_KEY
          );
        } else if (action.transition === "delete") {
          store.delete(WEB_PUSH_BINDING_TRANSITION_KEY);
        }
        result = action.result !== false;
      };
      request.onsuccess = () => {
        if (request.result !== undefined) {
          try {
            current = parseStoredWebPushBinding(request.result);
          } catch {
            malformed = true;
          }
        }
        applyDecision();
      };
      transitionRequest.onsuccess = () => {
        if (transitionRequest.result !== undefined) {
          try {
            transition = parseStoredWebPushTransition(transitionRequest.result);
          } catch {
            malformedTransition = true;
          }
        }
        applyDecision();
      };
      request.onerror = () => reject(request.error || new Error("Web Push binding mutation failed."));
      transitionRequest.onerror = () => reject(
        transitionRequest.error || new Error("Web Push transition mutation failed.")
      );
      transaction.onabort = () => reject(transaction.error || new Error("Web Push binding mutation aborted."));
      transaction.onerror = () => {};
      transaction.oncomplete = () => resolve(result);
    });
  } finally {
    database.close();
  }
}

async function prepareStoredWebPushBinding(ownerId) {
  const normalizedOwnerId = UUID_V4_PATTERN.test(ownerId || "") ? ownerId.toLowerCase() : null;
  if (!normalizedOwnerId) return false;
  return mutateStoredWebPushBinding((current, malformed, transition, malformedTransition) => {
    if (malformedTransition || (transition && transition.nextOwnerId !== normalizedOwnerId)) {
      return { result: false };
    }
    return {
      current: malformed || (current && current.ownerId !== normalizedOwnerId)
        ? "delete"
        : "keep",
      transition: transition ? "delete" : "keep",
      result: true
    };
  });
}

async function storeWebPushBinding(ownerId, bindingId) {
  const record = parseStoredWebPushBinding({ version: 1, ownerId, bindingId });
  if (!await mutateStoredWebPushBinding((_current, _malformed, transition, malformedTransition) => (
    transition || malformedTransition
      ? { result: false }
      : { current: "put", value: record, result: true }
  ))) {
    return false;
  }
  const stored = await readStoredWebPushBinding();
  return stored?.ownerId === record.ownerId && stored.bindingId === record.bindingId;
}

async function clearStoredWebPushBinding({ ownerId = null, bindingId = null } = {}) {
  const normalizedOwnerId = ownerId == null ? null
    : UUID_V4_PATTERN.test(ownerId) ? ownerId.toLowerCase() : false;
  const normalizedBindingId = bindingId == null ? null
    : UUID_V4_PATTERN.test(bindingId) ? bindingId.toLowerCase() : false;
  if (normalizedOwnerId === false || normalizedBindingId === false) return false;
  return mutateStoredWebPushBinding((current, malformed) => {
    if (malformed) return { current: "delete", result: true };
    if (!current || (normalizedOwnerId && current.ownerId !== normalizedOwnerId) ||
        (normalizedBindingId && current.bindingId !== normalizedBindingId)) {
      return { result: true };
    }
    return { current: "delete", result: true };
  });
}

async function beginStoredWebPushTransition(nextOwnerId = null) {
  const normalizedOwnerId = nextOwnerId == null ? null
    : UUID_V4_PATTERN.test(nextOwnerId) ? nextOwnerId.toLowerCase() : false;
  if (normalizedOwnerId === false) return false;
  const transitionValue = { version: 1, nextOwnerId: normalizedOwnerId };
  return mutateStoredWebPushBinding(() => ({
    current: "delete",
    transition: "put",
    transitionValue,
    result: true
  }));
}

async function currentServiceWorkerRegistration() {
  const registration = await navigator.serviceWorker.getRegistration?.("./");
  return registration || await navigator.serviceWorker.ready;
}

async function closeDisplayedWebPushNotifications() {
  if (!webPushSupported()) return true;
  const registration = await navigator.serviceWorker.getRegistration?.("./");
  if (!registration) return true;
  if (typeof registration.getNotifications !== "function") return false;
  const notifications = await registration.getNotifications();
  if (!Array.isArray(notifications) || notifications.length > 256) return false;
  for (const notification of notifications) {
    if (!notification || typeof notification.close !== "function") return false;
    notification.close();
  }
  return true;
}

async function disableWebPushWithoutBindingStorage() {
  const registration = await navigator.serviceWorker?.getRegistration?.("./");
  if (registration) {
    if (!await closeDisplayedWebPushNotifications()) return false;
    const pushManager = registration.pushManager;
    if (pushManager && typeof pushManager.getSubscription === "function") {
      const subscription = await pushManager.getSubscription();
      if (subscription && await subscription.unsubscribe() === false) return false;
    } else if (webPushSupported()) {
      return false;
    }
  }
  setWebPushPreference(false);
  return true;
}

async function invalidateWebPushUiBeforeAccountChange({ ownerId = null } = {}) {
  if (window.indexedDB && !await clearStoredWebPushBinding({ ownerId })) return false;
  return closeDisplayedWebPushNotifications();
}

function runWebPushLifecycle(task) {
  const run = webPushLifecycleTail.catch(() => {}).then(task);
  webPushLifecycleTail = run.catch(() => {});
  return run;
}

async function fenceWebPushBeforeAccountChange(nextOwnerId = null) {
  const fenceGeneration = ++webPushGeneration;
  webPushMutationInProgress = true;
  try {
    let bindingStorageReady = false;
    if (window.indexedDB) {
      bindingStorageReady = await beginStoredWebPushTransition(nextOwnerId).catch(() => false);
    }
    return await runWebPushLifecycle(
      bindingStorageReady
        ? closeDisplayedWebPushNotifications
        : disableWebPushWithoutBindingStorage
    );
  } finally {
    if (fenceGeneration === webPushGeneration) webPushMutationInProgress = false;
  }
}

async function registerWebPush({ prompt = false } = {}) {
  if (webPushMutationInProgress || accountTransitionInProgress) return false;
  const session = loadRemoteSession();
  const source = webPushSource(session);
  const expectedEpoch = accountEpoch;
  const expectedUserId = activeAccount?.userId;
  const applicationServerKey = webPushPublicKeyBytes();
  if (!source || !webPushSupported() || !applicationServerKey) {
    webPushState = {
      status: "unavailable", source, error: tx(
        "System notifications are not supported in this browser.",
        "Системні сповіщення не підтримуються в цьому браузері."
      )
    };
    render();
    return false;
  }
  if (window.Notification.permission === "default") {
    if (!prompt) return false;
    const permission = await window.Notification.requestPermission();
    if (permission !== "granted") {
      setWebPushPreference(false);
      webPushState = { status: permission === "denied" ? "denied" : "idle", source, error: "" };
      render();
      return false;
    }
  }
  if (window.Notification.permission !== "granted") {
    setWebPushPreference(false);
    webPushState = { status: "denied", source, error: "" };
    render();
    return false;
  }

  // The browser permission sheet may stay open while another tab or action
  // signs out. Never subscribe or bind an installation to a superseded
  // account/session after that user-controlled await.
  if (!webPushContextIsCurrent(source, expectedEpoch, expectedUserId)) {
    return false;
  }

  const requestGeneration = ++webPushGeneration;
  webPushMutationInProgress = true;
  webPushState = { status: "registering", source, error: "" };
  render();
  return runWebPushLifecycle(async () => {
    let subscription = null;
    let installationId = null;
    let bindingId = null;
    try {
      installationId = webPushInstallationId();
      if (!installationId) throw new Error("Browser storage is unavailable.");
      if (!await prepareStoredWebPushBinding(expectedUserId)) {
        throw new Error("Notification account binding could not be prepared.");
      }
      if (!webPushContextIsCurrent(source, expectedEpoch, expectedUserId)) {
        throw new Error("Notification account changed.");
      }
      const registration = await currentServiceWorkerRegistration();
      if (!webPushContextIsCurrent(source, expectedEpoch, expectedUserId)) {
        throw new Error("Notification account changed.");
      }
      subscription = await registration.pushManager.getSubscription();
      if (!webPushContextIsCurrent(source, expectedEpoch, expectedUserId)) {
        throw new Error("Notification account changed.");
      }
      const currentKey = subscription?.options?.applicationServerKey
        ? new Uint8Array(subscription.options.applicationServerKey)
        : null;
      if (subscription && currentKey &&
          (currentKey.byteLength !== applicationServerKey.byteLength ||
            currentKey.some((byte, index) => byte !== applicationServerKey[index]))) {
        await subscription.unsubscribe();
        subscription = null;
      }
      if (!subscription) {
        subscription = await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey
        });
        if (!webPushContextIsCurrent(source, expectedEpoch, expectedUserId)) {
          throw new Error("Notification account changed.");
        }
      }
      const material = webPushSubscriptionMaterial(subscription);
      const response = await supabaseRequest("/rest/v1/rpc/notification_register_installation", {
        method: "POST",
        session,
        timeoutMs: 12000,
        maxResponseBytes: 32 * 1024,
        body: JSON.stringify({
          p_installation_id: installationId,
          p_platform: "web",
          p_provider: "web_push",
          p_environment: "production",
          p_provider_token: material.endpoint,
          p_web_push_p256dh: material.p256dh,
          p_web_push_auth: material.auth,
          p_locale: state.language === "uk" ? "uk-UA" : state.language === "ru" ? "ru-RU" : "en-US",
          p_app_version: null
        })
      });
      const acknowledgement = parseWebPushRegistration(response, installationId);
      bindingId = acknowledgement.bindingId;
      if (requestGeneration !== webPushGeneration ||
          !webPushContextIsCurrent(source, expectedEpoch, expectedUserId)) {
        throw new Error("Stale notification registration was rejected.");
      }
      if (!await storeWebPushBinding(expectedUserId, bindingId) ||
          requestGeneration !== webPushGeneration ||
          !webPushContextIsCurrent(source, expectedEpoch, expectedUserId)) {
        throw new Error("Notification account binding could not be committed.");
      }
      if (!setWebPushPreference(true)) throw new Error("Notification preference could not be saved.");
      webPushState = { status: "registered", source, error: "" };
      render();
      return true;
    } catch (error) {
      if (installationId && source) {
        await supabaseRequest("/rest/v1/rpc/notification_revoke_installation", {
          method: "POST",
          session,
          timeoutMs: 5000,
          maxResponseBytes: 16 * 1024,
          body: JSON.stringify({ p_installation_id: installationId })
        }).catch(() => null);
      }
      if (sharedActiveAccountMatches(activeAccount) && activeAccount?.userId === expectedUserId) {
        await subscription?.unsubscribe?.().catch(() => {});
      }
      await clearStoredWebPushBinding({ ownerId: expectedUserId, bindingId }).catch(() => false);
      if (requestGeneration === webPushGeneration && expectedEpoch === accountEpoch &&
          activeAccount?.userId === expectedUserId) {
        webPushState = {
          status: "error",
          source,
          error: tx(
            "Notifications could not be registered safely. Try again.",
            "Не вдалося безпечно зареєструвати сповіщення. Спробуй ще раз."
          )
        };
        render();
      }
      return false;
    } finally {
      if (requestGeneration === webPushGeneration) {
        webPushMutationInProgress = false;
        render();
      }
    }
  });
}

async function revokeWebPush({ session = loadRemoteSession(), preservePreference = false } = {}) {
  const requestGeneration = ++webPushGeneration;
  webPushMutationInProgress = true;
  const installationId = storedWebPushInstallationId();
  const source = webPushSource(session);
  const expectedUserId = activeAccount?.userId;
  if (!preservePreference) setWebPushPreference(false);
  webPushState = { status: "revoking", source, error: "" };
  return runWebPushLifecycle(async () => {
    let serverRevoked = false;
    const localBindingCleared = await (
      source
        ? invalidateWebPushUiBeforeAccountChange({ ownerId: expectedUserId })
        : clearStoredWebPushBinding({ ownerId: expectedUserId })
    ).catch(() => false);
    if (installationId && source) {
      for (let attempt = 0; attempt < 2 && !serverRevoked; attempt += 1) {
        try {
          const response = await supabaseRequest("/rest/v1/rpc/notification_revoke_installation", {
            method: "POST",
            session,
            timeoutMs: 5000,
            maxResponseBytes: 16 * 1024,
            body: JSON.stringify({ p_installation_id: installationId })
          });
          parseWebPushRevocation(response, installationId);
          serverRevoked = true;
        } catch {
          serverRevoked = false;
        }
      }
    }
    try {
      const registration = webPushSupported() ? await currentServiceWorkerRegistration() : null;
      const subscription = await registration?.pushManager?.getSubscription?.();
      if (subscription && activeAccount?.userId === expectedUserId &&
          sharedActiveAccountMatches(activeAccount)) await subscription.unsubscribe();
    } catch {
      // The server binding is still scrubbed when available; a dead browser
      // endpoint is also revoked by the bounded dispatcher on its first 404/410.
    }
    const cleanupConfirmed = localBindingCleared && (serverRevoked || !installationId || !source);
    if (requestGeneration === webPushGeneration) {
      webPushMutationInProgress = false;
      webPushState = {
        status: cleanupConfirmed ? "idle" : "error",
        source: null,
        error: cleanupConfirmed ? "" : tx(
          "Notifications were disabled here, but server cleanup could not be confirmed yet.",
          "Сповіщення тут вимкнено, але очищення на сервері поки не підтверджено."
        )
      };
      render();
    }
    return serverRevoked;
  });
}

function resetWebPushContext() {
  const expectedAccount = normalizeStoredAccount(activeAccount);
  webPushGeneration += 1;
  webPushMutationInProgress = false;
  webPushState = { status: "idle", source: null, error: "" };
  if (webPushSupported() && expectedAccount) {
    void runWebPushLifecycle(async () => {
      const expectedOwnerId = expectedAccount.remote === "supabase"
        ? expectedAccount.userId
        : null;
      if (expectedOwnerId &&
          !await clearStoredWebPushBinding({ ownerId: expectedOwnerId })) return false;
      if (!sharedActiveAccountMatches(expectedAccount)) return false;
      if (!await closeDisplayedWebPushNotifications()) return false;
      const registration = await currentServiceWorkerRegistration();
      const subscription = await registration.pushManager.getSubscription();
      if (!sharedActiveAccountMatches(expectedAccount)) return false;
      await subscription?.unsubscribe?.();
      return true;
    }).catch(() => {});
  }
}

function syncWebPushIfEnabled() {
  const source = webPushSource();
  if (!source || !webPushPreferenceEnabled() || !webPushSupported() ||
      window.Notification.permission !== "granted" || webPushMutationInProgress ||
      (webPushState.status === "registered" && webPushState.source === source) ||
      (webPushState.status === "registering" && webPushState.source === source)) return false;
  void registerWebPush({ prompt: false });
  return true;
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
      validRemoteRefreshToken(session.refresh_token)) &&
    (session.password_update_required === undefined ||
      typeof session.password_update_required === "boolean") &&
    (session.activation_pending === undefined ||
      ["login", "signup", "recovery"].includes(session.activation_pending))
  );
}

function validRemoteRefreshToken(refreshToken) {
  return typeof refreshToken === "string" &&
    refreshToken.length > 0 &&
    refreshToken.length <= 8192;
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
       !validRemoteRefreshToken(refreshed.refresh_token)) ||
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
  clearActiveWorkoutMemory();
  activeAccount = null;
  exerciseRestTimerLedger = null;
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
  const expectedUserId = activeAccount.userId;
  setCloudSyncUi("checking", "", expectedUserId);
  try {
    const session = loadRemoteSession();
    if (!session?.user?.id) return false;
    const cloudState = await loadRemoteState(session);
    if (activeAccount?.userId !== cloudState.userId || loadRemoteSession()?.user?.id !== cloudState.userId) {
      throw new Error("Cloud state was loaded for a stale account session.");
    }
    const result = await reconcileLoadedRemoteState(
      cloudState,
      state,
      storedAccountStateExists(activeAccount)
    );
    const baseline = loadSyncBaseline(expectedUserId);
    setCloudSyncUi(baseline?.dirty || baseline?.pending ? "pending" : "synced", "", expectedUserId);
    return result;
  } catch (error) {
    if (activeAccount?.userId === expectedUserId) {
      setCloudSyncUi("error", friendlySyncError(error), expectedUserId);
    }
    throw error;
  }
}

function storedAccountStateExists(account = activeAccount) {
  try {
    return Boolean(account?.id && localStorage.getItem(activeStorageKey(account)) !== null);
  } catch {
    return false;
  }
}

function nativeCloudEnvelopeCandidate(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  if (Object.hasOwn(value, "summary")) return true;
  const pwaOnly = ["language", "mappings", "profile"];
  if (pwaOnly.some(key => Object.hasOwn(value, key)) || !Object.hasOwn(value, "schemaVersion")) return false;
  const nativeMetadataSignals = ["exportedAt", "app", "diagnostics", "owner"]
    .filter(key => Object.hasOwn(value, key)).length;
  return nativeMetadataSignals >= 3 ||
    (nativeMetadataSignals >= 2 && ["exercises", "sessions"].some(key => Object.hasOwn(value, key)));
}

function nativeCloudRecord(value, path) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${path} must be an object.`);
  }
  return value;
}

function nativeCloudAssertJsonBudget(value) {
  const limits = window.GymStateContract.LIMITS;
  let encoded;
  try {
    encoded = JSON.stringify(value);
  } catch {
    throw new Error("Cloud state cannot be encoded as JSON.");
  }
  if (typeof encoded !== "string" || new TextEncoder().encode(encoded).byteLength > limits.rawBytes) {
    throw new Error("Cloud state exceeds the supported byte limit.");
  }
  const stack = [{ value, depth: 0 }];
  let nodes = 0;
  while (stack.length) {
    const current = stack.pop();
    nodes += 1;
    if (nodes > limits.maxNodes || current.depth > limits.maxDepth) {
      throw new Error("Cloud state exceeds the supported complexity limit.");
    }
    if (typeof current.value === "string") {
      if (new TextEncoder().encode(current.value).byteLength > limits.jsonStringBytes) {
        throw new Error("Cloud state contains an oversized string.");
      }
      continue;
    }
    if (current.value === null || typeof current.value === "boolean") continue;
    if (typeof current.value === "number") {
      if (!Number.isFinite(current.value)) throw new Error("Cloud state contains a non-finite number.");
      continue;
    }
    if (!current.value || typeof current.value !== "object") {
      throw new Error("Cloud state contains a non-JSON value.");
    }
    if (Array.isArray(current.value)) {
      for (let index = current.value.length - 1; index >= 0; index -= 1) {
        stack.push({ value: current.value[index], depth: current.depth + 1 });
      }
      continue;
    }
    for (const [key, child] of Object.entries(current.value)) {
      if (["__proto__", "prototype", "constructor"].includes(key) ||
          new TextEncoder().encode(key).byteLength > limits.jsonStringBytes) {
        throw new Error("Cloud state contains an unsupported object key.");
      }
      stack.push({ value: child, depth: current.depth + 1 });
    }
  }
}

function nativeCloudExactKeys(value, path, required, optional = []) {
  const record = nativeCloudRecord(value, path);
  const allowed = new Set([...required, ...optional]);
  const keys = Object.keys(record);
  if (!required.every(key => Object.hasOwn(record, key)) || keys.some(key => !allowed.has(key))) {
    throw new Error(`${path} has unsupported or missing fields.`);
  }
  return record;
}

function nativeCloudExactInteger(value, path, minimum, maximum) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${path} must be a supported integer.`);
  }
  return value;
}

function nativeCloudFiniteNumber(value, path, minimum, maximum) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    throw new Error(`${path} must be a supported finite number.`);
  }
  return value === 0 ? 0 : value;
}

function nativeCloudBoundedText(value, path, maximumCharacters, maximumBytes, { allowEmpty = false } = {}) {
  if (typeof value !== "string") throw new Error(`${path} must be a string.`);
  if ((!allowEmpty && !value) || Array.from(value).length > maximumCharacters ||
      new TextEncoder().encode(value).byteLength > maximumBytes) {
    throw new Error(`${path} is outside the supported length.`);
  }
  return value;
}

function nativeCloudClone(value, path = "cloud state") {
  nativeCloudAssertJsonBudget(value);
  try {
    return JSON.parse(JSON.stringify(value));
  } catch {
    throw new Error(`${path} cannot be represented as JSON.`);
  }
}

function nativeCloudOwner(value, expectedUserId, path = "cloud state.owner") {
  const owner = nativeCloudExactKeys(value, path, ["accountId", "userId", "remote"], ["email"]);
  const ownerUserId = nativeCloudBoundedText(owner.userId, `${path}.userId`, 64, 64);
  const ownerAccountId = nativeCloudBoundedText(owner.accountId, `${path}.accountId`, 64, 64);
  const recognizedAccountIds = new Set([expectedUserId, `remote-${expectedUserId}`, `cloud_${expectedUserId}`]);
  if (ownerUserId !== expectedUserId || !recognizedAccountIds.has(ownerAccountId) || owner.remote !== true) {
    throw new Error("Cloud state owner does not match the authenticated account.");
  }
  if (Object.hasOwn(owner, "email") && owner.email !== null) {
    nativeCloudBoundedText(owner.email, `${path}.email`, 320, 512, { allowEmpty: true });
  }
  return { accountId: expectedUserId, userId: expectedUserId, remote: true };
}

function nativeCloudPwaExtension(value, path = "cloud state.extensions.pwa") {
  const extension = nativeCloudExactKeys(value, path, ["version", "language", "mappings", "profile"]);
  nativeCloudExactInteger(extension.version, `${path}.version`, 1, 1);
  if (!["en", "uk", "ru"].includes(extension.language)) {
    throw new Error(`${path}.language is unsupported.`);
  }
  const profile = nativeCloudExactKeys(
    extension.profile,
    `${path}.profile`,
    ["split", "days", "goal", "calories"]
  );
  const profileEnums = window.GymStateContract.PROFILE_ENUMS;
  if (!profileEnums.split.includes(profile.split) ||
      !profileEnums.goal.includes(profile.goal) ||
      !profileEnums.calories.includes(profile.calories) ||
      !Number.isSafeInteger(profile.days) || profile.days < 2 || profile.days > 6) {
    throw new Error(`${path}.profile is invalid.`);
  }
  const normalized = window.GymStateContract.validateAndNormalize({
    schemaVersion: 2,
    language: extension.language,
    exercises: [],
    sessions: [],
    mappings: extension.mappings,
    profile
  }).state;
  if (canonicalValueFingerprint(extension.mappings) !== canonicalValueFingerprint(normalized.mappings)) {
    throw new Error(`${path}.mappings is not canonical.`);
  }
  return nativeCloudClone({
    version: 1,
    language: extension.language,
    mappings: normalized.mappings,
    profile: normalized.profile
  }, path);
}

function nativeCloudExtensions(value, path = "cloud state.extensions") {
  if (value == null) return {};
  const extensions = nativeCloudRecord(value, path);
  const names = Object.keys(extensions);
  if (names.length > MAX_CLOUD_EXTENSION_NAMESPACES) {
    throw new Error(`${path} contains too many namespaces.`);
  }
  const normalized = {};
  for (const name of names) {
    nativeCloudBoundedText(
      name,
      `${path} namespace`,
      MAX_CLOUD_EXTENSION_NAMESPACE_LENGTH,
      MAX_CLOUD_EXTENSION_NAMESPACE_LENGTH
    );
    if (!/^[a-z][a-z0-9_.-]*$/.test(name)) {
      throw new Error(`${path} contains an invalid namespace.`);
    }
    nativeCloudRecord(extensions[name], `${path}.${name}`);
    normalized[name] = name === "pwa"
      ? nativeCloudPwaExtension(extensions[name], `${path}.pwa`)
      : nativeCloudClone(extensions[name], `${path}.${name}`);
  }
  nativeCloudAssertJsonBudget(normalized);
  return normalized;
}

function bindCloudExtensions(userId, extensions) {
  if (!UUID_PATTERN.test(userId || "")) throw new Error("Cloud extension owner is invalid.");
  cloudExtensions = { userId, value: nativeCloudExtensions(extensions) };
  return cloudExtensions.value;
}

function pwaCloudExtension(sourceState = state) {
  const normalized = window.GymStateContract.validateAndNormalize({
    schemaVersion: 2,
    language: sourceState.language,
    exercises: [],
    sessions: [],
    mappings: sourceState.mappings,
    profile: sourceState.profile
  }).state;
  return nativeCloudPwaExtension({
    version: 1,
    language: normalized.language,
    mappings: normalized.mappings,
    profile: normalized.profile
  }, "PWA cloud extension");
}

function nativeCloudLoadProfile(value, path) {
  const limits = window.GymStateContract.LIMITS;
  const profile = nativeCloudExactKeys(value, path, ["direction", "allowedWeightsKg"]);
  if (!['higherIsHarder', 'lowerIsHarder'].includes(profile.direction) ||
      !Array.isArray(profile.allowedWeightsKg) || profile.allowedWeightsKg.length < 1 ||
      profile.allowedWeightsKg.length > limits.loadProfileWeights) {
    throw new Error(`${path} is invalid.`);
  }
  const allowedWeightsKg = profile.allowedWeightsKg.map((weight, index) =>
    nativeCloudFiniteNumber(weight, `${path}.allowedWeightsKg[${index}]`, 0, limits.weightMax)
  );
  if (allowedWeightsKg.some((weight, index) => index > 0 && weight <= allowedWeightsKg[index - 1])) {
    throw new Error(`${path}.allowedWeightsKg must be strictly increasing.`);
  }
  return { direction: profile.direction, allowedWeightsKg };
}

function nativeCloudExerciseWire(value, path, { block = false } = {}) {
  const required = block ? ["name", "sets"] : ["name"];
  const optional = ["catalogKey", "loadProfile"];
  const exercise = nativeCloudExactKeys(value, path, required, optional);
  const limits = window.GymStateContract.LIMITS;
  const name = nativeCloudBoundedText(
    exercise.name,
    `${path}.name`,
    limits.exerciseName,
    limits.exerciseNameBytes
  );
  if (name.trim() !== name || /[\u0000-\u001f\u007f-\u009f]/.test(name)) {
    throw new Error(`${path}.name is not canonical.`);
  }
  let catalogKey = null;
  if (Object.hasOwn(exercise, "catalogKey")) {
    catalogKey = nativeCloudBoundedText(exercise.catalogKey, `${path}.catalogKey`, 80, 80);
    if (!/^[a-z0-9_-]+$/.test(catalogKey)) throw new Error(`${path}.catalogKey is invalid.`);
  }
  const recognizedCatalogKey = catalogKeyRecognizedFromName(name);
  if ((recognizedCatalogKey || null) !== catalogKey) {
    throw new Error(`${path}.catalogKey does not match its name.`);
  }
  const identity = recognizedCatalogKey
    ? `catalog:${recognizedCatalogKey}`
    : `custom:${normalizeExerciseKey(name)}`;
  if (!identity.slice(identity.indexOf(":") + 1)) throw new Error(`${path}.name is invalid.`);
  const loadProfile = Object.hasOwn(exercise, "loadProfile")
    ? nativeCloudLoadProfile(exercise.loadProfile, `${path}.loadProfile`)
    : null;
  return { exercise, identity, name, catalogKey, loadProfile };
}

function nativeCloudCompareBytes(left, right) {
  const sharedLength = Math.min(left.length, right.length);
  for (let index = 0; index < sharedLength; index += 1) {
    if (left[index] !== right[index]) return left[index] - right[index];
  }
  return left.length - right.length;
}

function nativeCloudWireBytes(value, foldAscii = false) {
  const bytes = new TextEncoder().encode(value);
  if (!foldAscii) return bytes;
  return Uint8Array.from(bytes, byte => byte >= 0x41 && byte <= 0x5a ? byte + 0x20 : byte);
}

function nativeCloudCompareWireText(left, right) {
  return nativeCloudCompareBytes(nativeCloudWireBytes(left, true), nativeCloudWireBytes(right, true)) ||
    nativeCloudCompareBytes(nativeCloudWireBytes(left), nativeCloudWireBytes(right));
}

function nativeCloudCompareOptionalText(left, right) {
  if (left === null || right === null) {
    if (left === right) return 0;
    return left === null ? -1 : 1;
  }
  return nativeCloudCompareBytes(nativeCloudWireBytes(left), nativeCloudWireBytes(right));
}

function nativeCloudCompareLoadProfiles(left, right) {
  if (left === null || right === null) {
    if (left === right) return 0;
    return left === null ? -1 : 1;
  }
  const directionOrder = nativeCloudCompareBytes(
    nativeCloudWireBytes(left.direction),
    nativeCloudWireBytes(right.direction)
  );
  if (directionOrder) return directionOrder;
  const sharedLength = Math.min(left.allowedWeightsKg.length, right.allowedWeightsKg.length);
  for (let index = 0; index < sharedLength; index += 1) {
    const difference = left.allowedWeightsKg[index] - right.allowedWeightsKg[index];
    if (difference) return difference;
  }
  return left.allowedWeightsKg.length - right.allowedWeightsKg.length;
}

function nativeCloudCatalogComparator(left, right) {
  return nativeCloudCompareWireText(left.name, right.name) ||
    nativeCloudCompareOptionalText(left.catalogKey, right.catalogKey) ||
    nativeCloudCompareLoadProfiles(left.loadProfile, right.loadProfile);
}

function nativeCloudProfilesMatch(left, right) {
  return nativeCloudCompareLoadProfiles(left, right) === 0;
}

function prepareNativeCloudEnvelope(value, expectedUserId) {
  const limits = window.GymStateContract.LIMITS;
  // Budget the raw envelope without passing it through the generic PWA normalizer: generated
  // IDs or compatibility fallbacks must never participate in native cloud identity.
  nativeCloudAssertJsonBudget(value);
  const root = nativeCloudExactKeys(value, "cloud state", [
    "schemaVersion", "exportedAt", "app", "diagnostics", "owner", "exercises", "sessions", "summary"
  ], ["catalogSeedVersion", "extensions"]);
  nativeCloudExactInteger(root.schemaVersion, "cloud state.schemaVersion", 2, 2);
  nativeCloudExactInteger(root.exportedAt, "cloud state.exportedAt", limits.timestampMin, limits.timestampMax);
  if (root.app !== "GymApp" || root.diagnostics !== false) {
    throw new Error("Cloud state metadata is not a canonical native envelope.");
  }
  if (Object.hasOwn(root, "catalogSeedVersion")) {
    nativeCloudExactInteger(
      root.catalogSeedVersion,
      "cloud state.catalogSeedVersion",
      0,
      defaultAppState().catalogSeedVersion
    );
  }
  const owner = nativeCloudOwner(root.owner, expectedUserId);
  const extensions = nativeCloudExtensions(root.extensions);
  if (!Array.isArray(root.exercises) || root.exercises.length > limits.exercises) {
    throw new Error("Cloud exercise catalog exceeds the supported limit.");
  }
  const catalogProfiles = new Map();
  const catalog = root.exercises.map((rawExercise, index) => {
    const wire = nativeCloudExerciseWire(rawExercise, `cloud state.exercises[${index}]`);
    if (catalogProfiles.has(wire.identity)) {
      throw new Error("Cloud exercise catalog contains a duplicate portable identity.");
    }
    catalogProfiles.set(wire.identity, wire.loadProfile);
    return { name: wire.name, catalogKey: wire.catalogKey, loadProfile: wire.loadProfile };
  });
  if (!Array.isArray(root.sessions) || root.sessions.length > limits.sessions) {
    throw new Error("Cloud workout history exceeds the supported limit.");
  }
  let totalSetCount = 0;
  let totalVolume = 0;
  let previousSessionDate = null;
  const sessions = root.sessions.map((rawSession, sessionIndex) => {
    const path = `cloud state.sessions[${sessionIndex}]`;
    const session = nativeCloudExactKeys(rawSession, path, ["date", "exercises"], ["note"]);
    const date = nativeCloudExactInteger(session.date, `${path}.date`, limits.timestampMin, limits.timestampMax);
    if (previousSessionDate !== null && date < previousSessionDate) {
      throw new Error("Cloud workout history must be sorted by date.");
    }
    previousSessionDate = date;
    let note = null;
    if (Object.hasOwn(session, "note") && session.note !== null) {
      const rawNote = nativeCloudBoundedText(
        session.note,
        `${path}.note`,
        limits.note,
        limits.noteBytes,
        { allowEmpty: true }
      );
      note = rawNote.trim() || null;
    }
    if (!Array.isArray(session.exercises) || session.exercises.length < 1 ||
        session.exercises.length > limits.exercisesPerSession) {
      throw new Error(`${path}.exercises is outside the supported limit.`);
    }
    const blockIdentities = new Set();
    const setsByIdentity = new Map();
    const blocks = session.exercises.map((rawBlock, blockIndex) => {
      const blockPath = `${path}.exercises[${blockIndex}]`;
      const wire = nativeCloudExerciseWire(rawBlock, blockPath, { block: true });
      if (!catalogProfiles.has(wire.identity)) {
        throw new Error(`${blockPath} is absent from the authoritative exercise catalog.`);
      }
      if (blockIdentities.has(wire.identity)) {
        throw new Error(`${path}.exercises contains repeated portable identity blocks that cannot be represented losslessly.`);
      }
      blockIdentities.add(wire.identity);
      if (wire.loadProfile !== null && !nativeCloudProfilesMatch(wire.loadProfile, catalogProfiles.get(wire.identity))) {
        throw new Error(`${blockPath}.loadProfile does not match the authoritative catalog.`);
      }
      if (!Array.isArray(wire.exercise.sets) || wire.exercise.sets.length < 1 ||
          wire.exercise.sets.length > limits.setsPerExercise) {
        throw new Error(`${blockPath}.sets is outside the supported limit.`);
      }
      const nextIdentitySetCount = (setsByIdentity.get(wire.identity) || 0) + wire.exercise.sets.length;
      if (nextIdentitySetCount > limits.setsPerExercise) {
        throw new Error(`${blockPath} exceeds the per-exercise set limit.`);
      }
      setsByIdentity.set(wire.identity, nextIdentitySetCount);
      const sets = wire.exercise.sets.map((rawSet, setIndex) => {
        const setPath = `${blockPath}.sets[${setIndex}]`;
        const set = nativeCloudExactKeys(rawSet, setPath, ["weight", "reps"]);
        const weight = nativeCloudFiniteNumber(set.weight, `${setPath}.weight`, 0, limits.weightMax);
        const reps = nativeCloudExactInteger(set.reps, `${setPath}.reps`, 1, limits.repsMax);
        totalSetCount += 1;
        if (totalSetCount > limits.totalSets) throw new Error("Cloud history exceeds the total set limit.");
        totalVolume += weight * reps;
        if (!Number.isFinite(totalVolume)) throw new Error("Cloud workout volume is invalid.");
        return { weight, reps };
      });
      // A matching nested load profile is compatibility-only duplication. The top catalog
      // remains authoritative and the duplicate is intentionally absent from this identity.
      return { name: wire.name, catalogKey: wire.catalogKey, sets };
    });
    return { date, note, blocks };
  });
  const summary = nativeCloudExactKeys(root.summary, "cloud state.summary", [
    "exerciseCount", "sessionCount", "setCount", "totalVolume"
  ]);
  const normalizedSummary = {
    exerciseCount: nativeCloudExactInteger(
      summary.exerciseCount,
      "cloud state.summary.exerciseCount",
      0,
      limits.exercises
    ),
    sessionCount: nativeCloudExactInteger(
      summary.sessionCount,
      "cloud state.summary.sessionCount",
      0,
      limits.sessions
    ),
    setCount: nativeCloudExactInteger(summary.setCount, "cloud state.summary.setCount", 0, limits.totalSets),
    totalVolume: nativeCloudFiniteNumber(
      summary.totalVolume,
      "cloud state.summary.totalVolume",
      0,
      Number.MAX_VALUE
    )
  };
  if (normalizedSummary.exerciseCount !== catalog.length ||
      normalizedSummary.sessionCount !== sessions.length ||
      normalizedSummary.setCount !== totalSetCount ||
      normalizedSummary.totalVolume !== (totalVolume === 0 ? 0 : totalVolume)) {
    throw new Error("Cloud state summary does not match its workout data.");
  }
  const canonicalCatalog = [...catalog]
    .sort(nativeCloudCatalogComparator)
    .map(exercise => ({
      name: exercise.name,
      ...(exercise.catalogKey ? { catalogKey: exercise.catalogKey } : {}),
      ...(exercise.loadProfile ? { loadProfile: exercise.loadProfile } : {})
    }));
  const canonicalSessions = sessions.map(session => ({
    date: session.date,
    ...(session.note ? { note: session.note } : {}),
    exercises: session.blocks.map(block => ({
      name: block.name,
      ...(block.catalogKey ? { catalogKey: block.catalogKey } : {}),
      sets: block.sets
    }))
  }));
  // Synchronization deliberately uses the workout-only envelope understood by the
  // released 2.2.9 native clients. Newer load profiles and client namespaces stay
  // device-local: an older client rewrites the whole user_states row and cannot
  // preserve those fields losslessly.
  const compatibilityCatalog = canonicalCatalog.map(exercise => ({
    name: exercise.name,
    ...(exercise.catalogKey ? { catalogKey: exercise.catalogKey } : {})
  }));
  const identityProjection = {
    schemaVersion: 2,
    app: "GymApp",
    diagnostics: false,
    owner,
    exercises: compatibilityCatalog,
    sessions: canonicalSessions,
    summary: normalizedSummary
  };
  const readableProjection = {
    ...identityProjection,
    exercises: canonicalCatalog,
    ...(Object.keys(extensions).length ? { extensions } : {})
  };
  const appStateInput = {
    ...nativeCloudClone(readableProjection),
    exportedAt: root.exportedAt,
    ...(extensions.pwa ? {
      language: extensions.pwa.language,
      mappings: extensions.pwa.mappings,
      profile: extensions.pwa.profile
    } : {})
  };
  // The native cloud format intentionally omits this local migration marker. Mark the local
  // projection current without seeding: a deleted built-in must not be resurrected and uploaded.
  appStateInput.catalogSeedVersion = defaultAppState().catalogSeedVersion;
  return {
    appStateInput,
    fingerprint: canonicalValueFingerprint(identityProjection),
    identityProjection,
    extensions
  };
}

function prepareLegacyPwaCloudEnvelope(value, expectedUserId) {
  const limits = window.GymStateContract.LIMITS;
  nativeCloudAssertJsonBudget(value);
  const ownerlessKeys = ["language", "exercises", "sessions", "mappings", "profile"];
  const record = nativeCloudRecord(value, "legacy PWA cloud state");
  // The earliest browser row had no embedded owner. This exact shape is accepted only here,
  // after loadRemoteState has selected the authenticated user's RLS-protected user_states row.
  // Manual backup import never calls this cloud preparation path.
  const isOwnerlessLegacy = Object.keys(record).length === ownerlessKeys.length &&
    ownerlessKeys.every(key => Object.hasOwn(record, key));
  const root = isOwnerlessLegacy
    ? nativeCloudExactKeys(record, "legacy PWA cloud state", ownerlessKeys)
    : nativeCloudExactKeys(record, "legacy PWA cloud state", [
        "schemaVersion", "exportedAt", "app", "diagnostics", "owner",
        "language", "exercises", "sessions", "mappings", "profile"
      ]);
  if (!isOwnerlessLegacy) {
    nativeCloudExactInteger(root.schemaVersion, "legacy PWA cloud state.schemaVersion", 2, 2);
    nativeCloudExactInteger(
      root.exportedAt,
      "legacy PWA cloud state.exportedAt",
      limits.timestampMin,
      limits.timestampMax
    );
    if (root.app !== "GymApp" || root.diagnostics !== false) {
      throw new Error("Legacy PWA cloud metadata is invalid.");
    }
    nativeCloudOwner(root.owner, expectedUserId, "legacy PWA cloud state.owner");
  }
  const normalized = validateImportedEnvelope(root, defaultAppState()).state;
  const extensions = {
    pwa: pwaCloudExtension(normalized)
  };
  return {
    state: normalized,
    extensions: nativeCloudExtensions(extensions)
  };
}

async function reconcileLoadedRemoteState(cloudState, cachedState, cachedStateExists = true) {
  const userId = activeAccount?.userId;
  if (!UUID_PATTERN.test(userId || "") || cloudState?.userId !== userId) {
    throw new Error("Cloud state reconciliation owner is invalid.");
  }
  let remoteState = defaultAppState();
  let remoteFingerprint = null;
  let catalogChanged = false;
  let remoteFormat = "empty";
  try {
    if (cloudState.exists) {
      if (nativeCloudEnvelopeCandidate(cloudState.state)) {
        remoteFormat = "canonical";
        const prepared = prepareNativeCloudEnvelope(cloudState.state, userId);
        bindCloudExtensions(userId, prepared.extensions);
        remoteState = normalizeImportedState(
          prepared.appStateInput,
          cachedState || defaultAppState()
        );
        if (!prepared.extensions.pwa) {
          remoteState.language = cachedState?.language || defaultAppState().language;
        }
        remoteState.catalogSeedVersion = defaultAppState().catalogSeedVersion;
        preserveExerciseFavorites(remoteState, cachedState, {
          preferPrevious: true,
          preserveMissingLoadProfiles: true
        });
        preserveLocalProgressExerciseSelection(remoteState, cachedState);
        remoteFingerprint = prepared.fingerprint;
        catalogChanged = remoteStateFingerprint(remoteState, userId) !== prepared.fingerprint;
      } else {
        remoteFormat = "legacy-pwa";
        const prepared = prepareLegacyPwaCloudEnvelope(cloudState.state, userId);
        bindCloudExtensions(userId, prepared.extensions);
        remoteState = prepared.state;
        remoteFingerprint = remoteStateFingerprint(remoteState, userId);
        preserveExerciseFavorites(remoteState, cachedState, {
          preferPrevious: true,
          preserveMissingLoadProfiles: true
        });
        ensureBuiltInExerciseCatalog(remoteState);
        preserveLocalProgressExerciseSelection(remoteState, cachedState);
        // The semantic state is safe, but the row must be rewritten once into the
        // workout-only native core that released 2.2.9 clients can preserve.
        catalogChanged = true;
      }
    } else {
      bindCloudExtensions(userId, {});
    }
    cloudStateRecovery = null;
  } catch {
    state = cachedState;
    bindRemoteStateRevision(cloudState);
    bindCloudExtensions(userId, {});
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
  if (cloudState.exists && baseline && !baseline.dirty && baseline.pending === null &&
      baseline.revision === cloudState.revision &&
      baseline.syncedFingerprint !== remoteFingerprint) {
    // Fingerprint v1 represented the old per-platform wire format. An unchanged
    // server revision proves the cached copy still descends from this exact row,
    // so upgrade the baseline without inventing a cross-device conflict.
    baseline = saveSyncBaseline({
      version: 1,
      userId,
      remoteExists: true,
      revision: cloudState.revision,
      syncedFingerprint: remoteFingerprint,
      localFingerprint,
      dirty: localFingerprint !== remoteFingerprint || remoteFormat === "legacy-pwa" || catalogChanged,
      pending: null,
      lastSyncedAt: baseline.lastSyncedAt ?? null,
      updatedAt: Date.now()
    });
  }
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
      lastSyncedAt: dirty ? (baseline?.lastSyncedAt ?? null) : Date.now(),
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
      lastSyncedAt: catalogChanged ? (baseline?.lastSyncedAt ?? null) : Date.now(),
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
        lastSyncedAt: null,
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
      lastSyncedAt: null,
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

function pwaExerciseForNativeCloud(value) {
  const catalogKey = persistedExerciseCatalogKey(value);
  const name = catalogKey ? canonicalExerciseName(value) : exerciseRawName(value);
  const loadProfile = normalizeExerciseLoadProfile(value?.loadProfile);
  return {
    identity: catalogKey ? `catalog:${catalogKey}` : `custom:${normalizeExerciseKey(name)}`,
    name,
    catalogKey,
    loadProfile
  };
}

function remoteStateCore(sourceState = state, expectedUserId = activeAccount?.userId) {
  if (!UUID_PATTERN.test(expectedUserId || "")) throw new Error("Cloud state owner is missing or invalid.");
  const catalogByIdentity = new Map();
  const registerExercise = value => {
    const candidate = pwaExerciseForNativeCloud(value);
    if (!candidate.name || !candidate.identity.slice(candidate.identity.indexOf(":") + 1)) {
      throw new Error("Cloud exercise identity is invalid.");
    }
    const existing = catalogByIdentity.get(candidate.identity);
    if (!existing) {
      catalogByIdentity.set(candidate.identity, candidate);
      return candidate;
    }
    if (!existing.loadProfile && candidate.loadProfile) existing.loadProfile = candidate.loadProfile;
    return existing;
  };
  const sourceCatalogIdentities = new Set();
  sourceState.exercises.forEach(exercise => {
    const candidate = pwaExerciseForNativeCloud(exercise);
    if (sourceCatalogIdentities.has(candidate.identity)) {
      throw new Error("Local exercise catalog contains a duplicate portable identity and cannot be uploaded losslessly.");
    }
    sourceCatalogIdentities.add(candidate.identity);
    registerExercise(exercise);
  });

  let setCount = 0;
  let totalVolume = 0;
  const sessions = sourceState.sessions
    .map((session, originalIndex) => ({ session, originalIndex }))
    .sort((left, right) =>
      Number(left.session.startedAt) - Number(right.session.startedAt) ||
      left.originalIndex - right.originalIndex
    )
    .map(({ session }, sessionIndex) => {
      const indexedSets = (session.sets || []).map((set, index) => ({ set, index }));
      const orderIndexes = indexedSets.map(({ set, index }) => Number(set.orderIndex ?? index));
      // Older nested imports numbered sets from zero inside every exercise block. Sorting those
      // duplicate indexes globally interleaves otherwise contiguous blocks, so preserve their
      // validated array order. A unique orderIndex sequence remains authoritative.
      const orderedSets = new Set(orderIndexes).size === orderIndexes.length
        ? indexedSets.sort((left, right) =>
            Number(left.set.orderIndex ?? left.index) - Number(right.set.orderIndex ?? right.index) ||
            left.index - right.index
          )
        : indexedSets;
      if (!orderedSets.length) {
        throw new Error(`Cloud workout ${sessionIndex + 1} has no completed sets.`);
      }
      const blocksByIdentity = new Map();
      const closedBlockIdentities = new Set();
      let previousBlockIdentity = null;
      for (const { set } of orderedSets) {
        const reference = {
          name: set.exerciseName,
          ...(set.catalogKey ? { catalogKey: set.catalogKey } : {})
        };
        const catalogExercise = registerExercise(reference);
        if (previousBlockIdentity !== null && catalogExercise.identity !== previousBlockIdentity) {
          closedBlockIdentities.add(previousBlockIdentity);
          if (closedBlockIdentities.has(catalogExercise.identity)) {
            throw new Error("Local workout contains repeated non-contiguous portable identity blocks and cannot be uploaded losslessly.");
          }
        }
        previousBlockIdentity = catalogExercise.identity;
        let block = blocksByIdentity.get(catalogExercise.identity);
        if (!block) {
          block = { exercise: catalogExercise, sets: [] };
          blocksByIdentity.set(catalogExercise.identity, block);
        }
        const weight = Number(set.weight);
        const reps = Number(set.reps);
        if (!Number.isFinite(weight) || weight < 0 || !Number.isSafeInteger(reps) || reps < 1) {
          throw new Error("Cloud workout contains an invalid set.");
        }
        block.sets.push({ weight: weight === 0 ? 0 : weight, reps });
        setCount += 1;
        totalVolume += weight * reps;
        if (!Number.isFinite(totalVolume)) throw new Error("Cloud workout volume is invalid.");
      }
      const note = String(session.note || "").trim();
      return {
        date: Number(session.startedAt),
        ...(note ? { note } : {}),
        exercises: [...blocksByIdentity.values()].map(block => ({
          name: block.exercise.name,
          ...(block.exercise.catalogKey ? { catalogKey: block.exercise.catalogKey } : {}),
          sets: block.sets
        }))
      };
    });
  const exercises = [...catalogByIdentity.values()]
    .sort(nativeCloudCatalogComparator)
    .map(exercise => ({
      name: exercise.name,
      ...(exercise.catalogKey ? { catalogKey: exercise.catalogKey } : {})
    }));
  return {
    schemaVersion: 2,
    app: "GymApp",
    diagnostics: false,
    owner: { accountId: expectedUserId, userId: expectedUserId, remote: true },
    exercises,
    sessions,
    summary: {
      exerciseCount: exercises.length,
      sessionCount: sessions.length,
      setCount,
      totalVolume: totalVolume === 0 ? 0 : totalVolume
    }
  };
}

function remoteStatePayload(expectedUserId = activeAccount?.userId, sourceState = state) {
  const core = remoteStateCore(sourceState, expectedUserId);
  const payload = nativeCloudClone({
    schemaVersion: core.schemaVersion,
    exportedAt: Date.now(),
    app: core.app,
    diagnostics: core.diagnostics,
    owner: core.owner,
    exercises: core.exercises,
    sessions: core.sessions,
    summary: core.summary
  });
  const prepared = prepareNativeCloudEnvelope(payload, expectedUserId);
  if (prepared.fingerprint !== canonicalValueFingerprint(core)) {
    throw new Error("Cloud payload failed canonical round-trip validation.");
  }
  return payload;
}

let remoteSaveTimer = null;
let remoteSaveInFlight = null;
let accountEpoch = 0;
let remoteStateSync = { userId: null, exists: false, revision: null };

function resetRemoteSyncContext({ eraseLiveBinding = false } = {}) {
  accountEpoch += 1;
  exerciseSearchQuery = "";
  progressExerciseSearchQuery = "";
  workoutDetailEditSessionId = null;
  // Every unsaved editor/share surface is account-bound. A shared link may stay
  // waiting across account changes, but a draft or modal must never cross them.
  workoutDraft = null;
  smartGeneratedPlan = null;
  smartPlanStale = false;
  modal = null;
  routeScrollPositions.delete("add:root");
  if (pendingSharedWorkoutOrigin?.type === "social") {
    pendingSharedWorkout = null;
    pendingSharedWorkoutOrigin = null;
    clearStoredSharedWorkout();
  }
  socialWorkoutInviteRequests.clear();
  resetSocialContext();
  resetLiveWorkoutContext({ eraseBinding: eraseLiveBinding });
  resetWebPushContext();
  resetGarminProfileContext();
  clearTimeout(remoteSaveTimer);
  remoteSaveTimer = null;
  remoteStateSync = { userId: null, exists: false, revision: null };
  cloudStateRecovery = null;
  cloudSyncConflict = null;
  cloudExtensions = { userId: null, value: {} };
  cloudRecoveryInProgress = false;
  cloudSyncUi = { userId: null, status: "idle", error: "" };
}

const CLOUD_SYNC_UI_STATUSES = new Set(["idle", "checking", "pending", "saving", "synced", "error"]);

function setCloudSyncUi(status, error = "", userId = activeAccount?.userId) {
  if (!CLOUD_SYNC_UI_STATUSES.has(status) ||
      (userId != null && !UUID_PATTERN.test(userId)) ||
      typeof error !== "string") return false;
  cloudSyncUi = { userId: userId || null, status, error: error.slice(0, 512) };
  return true;
}

function friendlySyncError(error) {
  const message = String(error?.message || "");
  if (/changed on another client|revision|conflict/i.test(message)) {
    return tx(
      "Cloud data changed elsewhere. Review the conflict before syncing.",
      "Хмарні дані змінилися на іншому пристрої. Перевір конфлікт перед синхронізацією."
    );
  }
  return tx(
    "Sync failed. Your latest workout changes remain saved in this browser.",
    "Синхронізація не вдалася. Останні зміни тренувань збережено в цьому браузері."
  );
}

function resetGarminProfileContext() {
  garminProfileRequestId += 1;
  garminProfileRequestController?.abort();
  garminProfileRequestController = null;
  garminProfileState = { status: "idle", userId: null, devices: [], error: "" };
}

function resetSocialReadContext() {
  socialRequestId += 1;
  socialRequestController?.abort();
  socialRequestController = null;
  socialDetailRequestId += 1;
  socialDetailRequestController?.abort();
  socialDetailRequestController = null;
  socialState = { status: "idle", source: null, dashboard: null, inbox: null, error: "" };
  socialDetailState = { status: "idle", source: null, profileId: null, value: null, error: "" };
  socialLastLoadedAt = 0;
}

function resetSocialContext() {
  resetSocialReadContext();
  socialMutationInProgress = false;
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

function canonicalValueFingerprint(value) {
  const canonicalJson = value => {
    if (value === null || typeof value !== "object") return JSON.stringify(value);
    if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
    return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  };
  const bytes = new TextEncoder().encode(canonicalJson(value));
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

function remoteStateFingerprint(sourceState = state, userId = activeAccount?.userId) {
  return canonicalValueFingerprint(remoteStateCore(sourceState, userId));
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
      !Number.isSafeInteger(value.updatedAt) || value.updatedAt < 0 ||
      (value.lastSyncedAt !== undefined && value.lastSyncedAt !== null &&
        (!Number.isSafeInteger(value.lastSyncedAt) || value.lastSyncedAt < 0))) {
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
    lastSyncedAt: value.lastSyncedAt == null
      ? (value.dirty === false && value.pending == null ? value.updatedAt : null)
      : value.lastSyncedAt,
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
  const now = Date.now();
  return {
    version: 1,
    userId,
    remoteExists: Boolean(cloudState.exists),
    revision: cloudState.exists ? cloudState.revision : null,
    syncedFingerprint: fingerprint,
    localFingerprint: fingerprint,
    dirty: false,
    pending: null,
    lastSyncedAt: now,
    updatedAt: now
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
    lastSyncedAt: baseline?.lastSyncedAt ?? null,
    updatedAt: Date.now()
  };
  return saveSyncBaseline(next);
}

function queueRemoteSave() {
  if (!activeAccount?.remote || !remoteAuthEnabled() || cloudStateRecovery || cloudSyncConflict) return;
  clearTimeout(remoteSaveTimer);
  const expectedEpoch = accountEpoch;
  const expectedUserId = activeAccount.userId;
  setCloudSyncUi("pending", "", expectedUserId);
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
      setCloudSyncUi("saving", "", expectedUserId);
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
    () => {
      if (remoteSaveInFlight === operation) remoteSaveInFlight = null;
      const expectedUserId = options.expectedUserId ?? activeAccount?.userId;
      if (expectedUserId && activeAccount?.userId === expectedUserId) {
        const baseline = loadSyncBaseline(expectedUserId);
        setCloudSyncUi(baseline?.dirty || baseline?.pending ? "pending" : "synced", "", expectedUserId);
      }
    },
    error => {
      if (remoteSaveInFlight === operation) remoteSaveInFlight = null;
      const expectedUserId = options.expectedUserId ?? activeAccount?.userId;
      if (expectedUserId && activeAccount?.userId === expectedUserId) {
        setCloudSyncUi("error", friendlySyncError(error), expectedUserId);
      }
    }
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
  if (activeAccount?.remote) {
    setCloudSyncUi("error", friendlySyncError(error), activeAccount.userId);
  }
  const conflict = /changed on another client|revision|stale account session/i.test(String(error?.message || ""));
  showToast(conflict
    ? tx("Cloud sync conflicted. Reload before saving again.", "Хмарні зміни конфліктують. Онови дані перед повторним збереженням.")
    : tx("Cloud sync failed. Your latest changes remain saved in this browser.", "Хмарна синхронізація не вдалася. Останні зміни збережено в цьому браузері."));
}

async function saveRemoteState({ expectedEpoch = accountEpoch, expectedUserId = activeAccount?.userId } = {}) {
  if (cloudStateRecovery?.userId === expectedUserId) {
    throw new Error("Cloud state recovery must be resolved before saving.");
  }
  if (cloudSyncConflict?.userId === expectedUserId) {
    throw new Error("Cloud sync conflicted and needs an explicit version choice.");
  }
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
    lastSyncedAt: baseline?.lastSyncedAt ?? null,
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
  const confirmedAt = Date.now();
  saveSyncBaseline({
    version: 1,
    userId: expectedUserId,
    remoteExists: true,
    revision: confirmedState.revision,
    syncedFingerprint: attemptFingerprint,
    localFingerprint: currentFingerprint,
    dirty: currentFingerprint !== attemptFingerprint,
    pending: null,
    lastSyncedAt: confirmedAt,
    updatedAt: confirmedAt
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
  resetGarminProfileContext();
}

function removeGarminBinding(userId) {
  if (!userId) return;
  const bindings = loadGarminBindings();
  delete bindings[userId];
  if (Object.keys(bindings).length) localStorage.setItem(GARMIN_DEVICE_BINDINGS_KEY, JSON.stringify(bindings));
  else localStorage.removeItem(GARMIN_DEVICE_BINDINGS_KEY);
  resetGarminProfileContext();
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

async function listGarminDevices(session, { signal } = {}) {
  const response = await supabaseRequest("/functions/v1/garmin-sync", {
    method: "POST",
    session,
    signal,
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

async function refreshGarminProfileDevices() {
  const session = loadRemoteSession();
  const userId = activeAccount?.remote && session?.user?.id;
  if (!UUID_PATTERN.test(userId || "")) {
    resetGarminProfileContext();
    return;
  }
  if (garminProfileState.userId === userId && garminProfileState.status !== "idle") return;

  const requestId = ++garminProfileRequestId;
  const expectedEpoch = accountEpoch;
  garminProfileRequestController?.abort();
  const controller = new AbortController();
  garminProfileRequestController = controller;
  garminProfileState = { status: "loading", userId, devices: [], error: "" };
  if (route().name === "leaderboard") render();
  try {
    const devices = await listGarminDevices(session, { signal: controller.signal });
    if (requestId !== garminProfileRequestId || expectedEpoch !== accountEpoch ||
        activeAccount?.userId !== userId || loadRemoteSession()?.user?.id !== userId) return;
    garminProfileState = { status: "loaded", userId, devices, error: "" };
  } catch (error) {
    if (error?.name === "AbortError" || requestId !== garminProfileRequestId) return;
    if (expectedEpoch !== accountEpoch || activeAccount?.userId !== userId) return;
    garminProfileState = {
      status: "error",
      userId,
      devices: [],
      error: friendlyOperationError(
        error,
        "Garmin watch status is temporarily unavailable.",
        "Статус годинника Garmin тимчасово недоступний."
      )
    };
  } finally {
    if (requestId === garminProfileRequestId) garminProfileRequestController = null;
  }
  if (route().name === "leaderboard") render();
}

function newGarminReplacementToken() {
  if (!window.crypto || typeof window.crypto.getRandomValues !== "function") {
    throw new Error("Secure Garmin token generation is unavailable in this browser.");
  }
  const bytes = new Uint8Array(32);
  window.crypto.getRandomValues(bytes);
  return [...bytes].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

function validGarminDisplayName(value) {
  return typeof value === "string" && value === value.trim() && value.length > 0 &&
    value.length <= 80 && !/[\u0000-\u001f\u007f]/.test(value) &&
    new TextEncoder().encode(value).byteLength <= 320;
}

function loadGarminPendingRevocations() {
  const raw = localStorage.getItem(GARMIN_PENDING_REVOCATIONS_KEY) || "{}";
  if (new TextEncoder().encode(raw).byteLength > MAX_GARMIN_PENDING_REVOCATION_STORAGE_BYTES) {
    throw new Error("Garmin revocation recovery storage exceeds its limit.");
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("Garmin revocation recovery storage is invalid.");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) ||
      Object.keys(parsed).length > MAX_GARMIN_PENDING_REVOCATIONS) {
    throw new Error("Garmin revocation recovery storage is invalid.");
  }
  const safe = Object.create(null);
  const now = Date.now();
  const expectedKeys = new Set([
    "version", "userId", "deviceId", "cleanupKind", "createdAt"
  ]);
  for (const [userId, value] of Object.entries(parsed)) {
    const keys = value && typeof value === "object" && !Array.isArray(value)
      ? Object.keys(value)
      : [];
    const createdAt = Number(value?.createdAt);
    if (!UUID_PATTERN.test(userId) || value?.version !== 1 || value.userId !== userId ||
        !UUID_V4_PATTERN.test(value.deviceId || "") ||
        !["revoke", "legacy-recovery"].includes(value.cleanupKind) ||
        keys.length !== expectedKeys.size || !keys.every(key => expectedKeys.has(key)) ||
        !Number.isSafeInteger(createdAt) || createdAt < 0 || createdAt > now + 5 * 60 * 1000) {
      // Do not trust a malformed local record enough to issue a server
      // revocation, and do not silently discard another possibly-live cleanup.
      throw new Error("Garmin revocation recovery storage is invalid.");
    }
    safe[userId] = {
      version: 1,
      userId,
      deviceId: value.deviceId.toLowerCase(),
      cleanupKind: value.cleanupKind,
      createdAt
    };
  }
  return safe;
}

function saveGarminPendingRevocations(records) {
  const entries = Object.entries(records || {});
  if (entries.length > MAX_GARMIN_PENDING_REVOCATIONS) {
    throw new Error("Garmin revocation recovery storage is full.");
  }
  if (!entries.length) {
    localStorage.removeItem(GARMIN_PENDING_REVOCATIONS_KEY);
    return;
  }
  const encoded = JSON.stringify(Object.fromEntries(entries));
  if (new TextEncoder().encode(encoded).byteLength > MAX_GARMIN_PENDING_REVOCATION_STORAGE_BYTES) {
    throw new Error("Garmin revocation recovery storage exceeds its limit.");
  }
  localStorage.setItem(GARMIN_PENDING_REVOCATIONS_KEY, encoded);
}

function pendingGarminRevocationForUser(userId) {
  if (!UUID_PATTERN.test(userId || "")) return null;
  return loadGarminPendingRevocations()[userId] || null;
}

function rememberGarminPendingRevocation(userId, deviceId, cleanupKind = "revoke") {
  if (!UUID_PATTERN.test(userId || "") || !UUID_V4_PATTERN.test(deviceId || "") ||
      !["revoke", "legacy-recovery"].includes(cleanupKind)) {
    throw new Error("Garmin revocation recovery record is invalid.");
  }
  const records = loadGarminPendingRevocations();
  const existing = records[userId];
  if (existing && (existing.deviceId !== deviceId.toLowerCase() ||
      existing.cleanupKind !== cleanupKind)) {
    throw new Error("A different Garmin cleanup is already pending for this account.");
  }
  if (!existing) {
    records[userId] = {
      version: 1,
      userId,
      deviceId: deviceId.toLowerCase(),
      cleanupKind,
      createdAt: Date.now()
    };
    saveGarminPendingRevocations(records);
  }
  return records[userId];
}

function forgetGarminPendingRevocation(userId, deviceId = null) {
  if (!UUID_PATTERN.test(userId || "")) return;
  const records = loadGarminPendingRevocations();
  const existing = records[userId];
  if (!existing || (deviceId !== null && existing.deviceId !== deviceId)) return;
  delete records[userId];
  saveGarminPendingRevocations(records);
}

function loadGarminCreateRequests() {
  const raw = localStorage.getItem(GARMIN_CREATE_REQUESTS_KEY) || "{}";
  if (new TextEncoder().encode(raw).byteLength > MAX_GARMIN_CREATE_STORAGE_BYTES) {
    localStorage.removeItem(GARMIN_CREATE_REQUESTS_KEY);
    throw new Error("Garmin creation recovery storage exceeds its limit.");
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    localStorage.removeItem(GARMIN_CREATE_REQUESTS_KEY);
    throw new Error("Garmin creation recovery storage is invalid.");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) ||
      Object.keys(parsed).length > MAX_GARMIN_CREATE_REQUESTS) {
    localStorage.removeItem(GARMIN_CREATE_REQUESTS_KEY);
    throw new Error("Garmin creation recovery storage is invalid.");
  }
  const now = Date.now();
  const safe = Object.create(null);
  let rewrite = false;
  let malformed = false;
  for (const [userId, value] of Object.entries(parsed)) {
    const createdAt = Number(value?.createdAt);
    const structurallyValid = UUID_PATTERN.test(userId) && value?.version === 1 &&
      value.userId === userId && UUID_V4_PATTERN.test(value.requestId || "") &&
      UUID_V4_PATTERN.test(value.deviceId || "") &&
      GARMIN_LEGACY_CAPABILITY_PATTERN.test(value.deviceNonce || "") &&
      validGarminDisplayName(value.displayName) &&
      typeof value.legacyFallbackAttempted === "boolean" &&
      Number.isSafeInteger(createdAt) && createdAt >= 0 &&
      createdAt <= now + 5 * 60 * 1000;
    if (!structurallyValid) {
      rewrite = true;
      malformed = true;
      continue;
    }
    if (now - createdAt > GARMIN_CREATE_REQUEST_MAX_AGE_MS) {
      // The server may have committed after the last client response. Persist
      // a nonsecret cleanup obligation before dropping the bearer retry data.
      rememberGarminPendingRevocation(
        userId,
        value.deviceId.toLowerCase(),
        value.legacyFallbackAttempted ? "legacy-recovery" : "revoke"
      );
      rewrite = true;
      continue;
    }
    safe[userId] = {
      version: 1,
      userId,
      requestId: value.requestId.toLowerCase(),
      deviceId: value.deviceId.toLowerCase(),
      deviceNonce: value.deviceNonce,
      displayName: value.displayName,
      createdAt,
      legacyFallbackAttempted: value.legacyFallbackAttempted
    };
  }
  if (rewrite) saveGarminCreateRequests(safe);
  if (malformed) throw new Error("Garmin creation recovery storage was invalid and was removed.");
  return safe;
}

function saveGarminCreateRequests(requests) {
  const entries = Object.entries(requests || {});
  if (entries.length > MAX_GARMIN_CREATE_REQUESTS) {
    throw new Error("Garmin creation recovery storage is full.");
  }
  if (!entries.length) {
    localStorage.removeItem(GARMIN_CREATE_REQUESTS_KEY);
    return;
  }
  const encoded = JSON.stringify(Object.fromEntries(entries));
  if (new TextEncoder().encode(encoded).byteLength > MAX_GARMIN_CREATE_STORAGE_BYTES) {
    throw new Error("Garmin creation recovery storage exceeds its limit.");
  }
  localStorage.setItem(GARMIN_CREATE_REQUESTS_KEY, encoded);
}

function removeGarminCreateRequestForUser(userId, requestId = null) {
  if (!UUID_PATTERN.test(userId || "")) return;
  const requests = loadGarminCreateRequests();
  if (!Object.hasOwn(requests, userId) ||
      (requestId !== null && requests[userId].requestId !== requestId)) return;
  delete requests[userId];
  saveGarminCreateRequests(requests);
}

function removeGarminCreateRequestMatchingCleanup(userId, deviceId, cleanupKind = null) {
  if (!UUID_PATTERN.test(userId || "") || !UUID_V4_PATTERN.test(deviceId || "") ||
      (cleanupKind !== null && !["revoke", "legacy-recovery"].includes(cleanupKind))) {
    throw new Error("Garmin cleanup identity is invalid.");
  }
  const requests = loadGarminCreateRequests();
  const creation = requests[userId];
  if (!creation) return;
  const creationKind = creation.legacyFallbackAttempted ? "legacy-recovery" : "revoke";
  if (creation.deviceId !== deviceId.toLowerCase() ||
      (cleanupKind !== null && creationKind !== cleanupKind)) {
    throw new Error("Garmin cleanup does not match the pending creation.");
  }
  delete requests[userId];
  saveGarminCreateRequests(requests);
}

function promoteGarminCreateRequestToCleanup(userId) {
  if (!UUID_PATTERN.test(userId || "")) {
    throw new Error("Garmin creation recovery belongs to an invalid account.");
  }
  const requests = loadGarminCreateRequests();
  const creation = requests[userId];
  if (!creation) return pendingGarminRevocationForUser(userId);
  const cleanup = rememberGarminPendingRevocation(
    userId,
    creation.deviceId,
    creation.legacyFallbackAttempted ? "legacy-recovery" : "revoke"
  );
  delete requests[userId];
  // Persist the secret removal only after the nonsecret cleanup marker. If
  // this write fails, sign-out is aborted rather than retaining a bearer in a
  // completed signed-out browser lifecycle.
  saveGarminCreateRequests(requests);
  return cleanup;
}

function prepareGarminCreateRequest(userId, displayName) {
  if (!UUID_PATTERN.test(userId || "") || !validGarminDisplayName(displayName)) {
    throw new Error("Garmin device creation belongs to an invalid account.");
  }
  const requests = loadGarminCreateRequests();
  const existing = requests[userId];
  if (existing) {
    if (existing.displayName !== displayName) {
      throw new Error("A different Garmin device creation is still awaiting recovery.");
    }
    return existing;
  }
  const record = {
    version: 1,
    userId,
    requestId: newUuidV4(),
    deviceId: newUuidV4(),
    deviceNonce: newGarminReplacementToken(),
    displayName,
    createdAt: Date.now(),
    legacyFallbackAttempted: false
  };
  requests[userId] = record;
  saveGarminCreateRequests(requests);
  return record;
}

function exactGarminCreateFallback(error) {
  if (!((error?.status === 400) || (error?.status === 501)) ||
      typeof error.message !== "string" || error.message.length > 512) return false;
  try {
    const value = JSON.parse(error.message);
    return value && typeof value === "object" && !Array.isArray(value) &&
      Object.keys(value).length === 1 &&
      ((error.status === 400 && value.error === "Unknown action") ||
       (error.status === 501 && value.error === "Idempotent device creation unavailable"));
  } catch {
    return false;
  }
}

async function requestGarminDeviceCreation(session, record) {
  if (session?.user?.id !== record.userId) {
    throw new Error("Garmin device creation belongs to another account.");
  }
  const idempotentBody = JSON.stringify({
    action: "createDeviceIdempotent",
    capabilityVersion: GARMIN_CAPABILITY_VERSION,
    requestId: record.requestId,
    deviceId: record.deviceId,
    deviceNonce: record.deviceNonce,
    displayName: record.displayName
  });
  const requestIdempotently = () => supabaseRequest("/functions/v1/garmin-sync", {
    method: "POST",
    session,
    body: idempotentBody
  });
  let response;
  try {
    response = await requestIdempotently();
  } catch (error) {
    if (exactGarminCreateFallback(error)) {
      if (record.legacyFallbackAttempted) {
        throw userVisibleError(
          "An older Garmin server may already have created this watch, but its token response was lost. Refresh and recover the existing watch instead of creating another one.",
          "Старіша версія сервера Garmin могла вже створити цей годинник, але відповідь із токеном було втрачено. Онови список і віднови наявний годинник замість створення ще одного."
        );
      }
      // Old Edge or migration-first/Edge-first rollout only. This legacy call
      // is never retried after an outcome-unknown result.
      const requests = loadGarminCreateRequests();
      const current = requests[record.userId];
      if (!current || current.requestId !== record.requestId ||
          current.deviceId !== record.deviceId || current.deviceNonce !== record.deviceNonce ||
          current.displayName !== record.displayName) {
        throw new Error("Garmin creation recovery state changed before fallback.");
      }
      const legacyRecord = { ...current, legacyFallbackAttempted: true };
      requests[record.userId] = legacyRecord;
      saveGarminCreateRequests(requests);
      try {
        return {
          response: await supabaseRequest("/functions/v1/garmin-sync", {
            method: "POST",
            session,
            body: JSON.stringify({
              action: "createDevice",
              capabilityVersion: GARMIN_CAPABILITY_VERSION,
              displayName: record.displayName
            })
          }),
          idempotent: false
        };
      } catch (legacyError) {
        if (legacyError?.status === 401 || legacyError?.status === 403) {
          // Authentication is checked before the old creator mutates state;
          // permit the normal sign-in/refresh path to retry that definitive
          // denial without treating it as an unknown outcome.
          const latest = loadGarminCreateRequests();
          if (latest[record.userId]?.requestId === record.requestId) {
            latest[record.userId] = { ...legacyRecord, legacyFallbackAttempted: false };
            saveGarminCreateRequests(latest);
          }
        }
        throw legacyError;
      }
    }
    if (error?.status !== undefined && error.status < 500) throw error;
    // Only the exact new body is safe after a lost response or server failure.
    response = await requestIdempotently();
  }
  return { response, idempotent: true };
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
  const pendingCleanup = pendingGarminRevocationForUser(userId);
  if (pendingCleanup?.cleanupKind === "legacy-recovery") {
    const recoveryDevices = await listGarminDevices(session);
    assertCurrentAccount();
    if (!recoveryDevices.length) {
      // The authoritative owner list proves that the outcome-unknown legacy
      // call left no active device, so a new idempotent creation is safe.
      removeGarminCreateRequestMatchingCleanup(
        userId,
        pendingCleanup.deviceId,
        pendingCleanup.cleanupKind
      );
      forgetGarminPendingRevocation(userId, pendingCleanup.deviceId);
    } else {
      const selectedDevice = chooseGarminDeviceForRecovery(recoveryDevices);
      if (!selectedDevice) {
        throw userVisibleError(
          "An older Garmin creation still needs recovery. Select the existing watch before creating another one.",
          "Старіше створення Garmin ще потребує відновлення. Вибери наявний годинник перед створенням нового."
        );
      }
      const binding = await recoverGarminDeviceBinding(session, selectedDevice);
      removeGarminCreateRequestMatchingCleanup(
        userId,
        pendingCleanup.deviceId,
        pendingCleanup.cleanupKind
      );
      forgetGarminPendingRevocation(userId, pendingCleanup.deviceId);
      return { binding, created: false, rotated: true };
    }
  } else if (pendingCleanup) {
    try {
      await revokeGarminDeviceById(session, pendingCleanup.deviceId);
      removeGarminCreateRequestMatchingCleanup(
        userId,
        pendingCleanup.deviceId,
        pendingCleanup.cleanupKind
      );
      forgetGarminPendingRevocation(userId, pendingCleanup.deviceId);
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
      // A prior binding write may have succeeded while raw-create deletion
      // failed. The authoritative absence now lets us scrub that exact retry
      // record before dropping its cleanup marker or binding.
      removeGarminCreateRequestMatchingCleanup(userId, current.deviceId);
      const pendingAfterAbsence = pendingGarminRevocationForUser(userId);
      if (pendingAfterAbsence?.deviceId === current.deviceId) {
        forgetGarminPendingRevocation(userId, current.deviceId);
      }
      removeGarminBinding(userId);
      throw userVisibleError(
        "The pending Garmin device is no longer active. Run Sync Watch again to choose or create a pairing.",
        "Пристрій Garmin, що очікував на сполучення, більше не активний. Знову натисни «Синхронізувати з годинником», щоб вибрати або створити сполучення."
      );
    }
    removeGarminCreateRequestForUser(userId);
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
  if (current) {
    removeGarminCreateRequestForUser(userId);
    return { binding: current, created: false };
  }
  const existingDevices = await listGarminDevices(session);
  assertCurrentAccount();
  if (existingDevices.length) {
    // A response-lost legacy create is recovered through the server list and
    // token rotation, so its temporary client secret must not be retained.
    removeGarminCreateRequestForUser(userId);
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
  const pendingCreationAfterEmptyList = loadGarminCreateRequests()[userId];
  if (pendingCreationAfterEmptyList?.legacyFallbackAttempted) {
    // The owner-authoritative empty list proves that the one-shot legacy call
    // created no active device. Remove only that exact spent transition; a
    // non-legacy idempotent request must retain its replay material.
    removeGarminCreateRequestMatchingCleanup(
      userId,
      pendingCreationAfterEmptyList.deviceId,
      "legacy-recovery"
    );
  }
  const pairingWarning = tx(
    "A one-time Garmin token will be shown. It works like a password: paste it only into this watch's Connect IQ settings. GymApp temporarily keeps account-bound retry material in this browser until pairing is recovered, then removes it. Continue?",
    "Буде показано одноразовий токен Garmin. Він працює як пароль: встав його лише в налаштування Connect IQ цього годинника. GymApp тимчасово зберігає в цьому браузері прив’язані до акаунта дані повтору до відновлення сполучення, а потім видаляє їх. Продовжити?"
  );
  if (typeof window.confirm !== "function" || !window.confirm(pairingWarning)) {
    throw userVisibleError("Garmin pairing was cancelled.", "Сполучення Garmin скасовано.");
  }
  const creation = prepareGarminCreateRequest(userId, "Garmin watch");
  const { response, idempotent } = await requestGarminDeviceCreation(session, creation);
  const device = response?.device;
  const normalizedDevice = normalizedGarminDevice(device, { requireToken: true });
  if (!normalizedDevice || normalizedDevice.tokenRevision !== 1 ||
      (idempotent && (
        !["created", "already_created"].includes(response?.status) ||
        response?.requestId !== creation.requestId ||
        normalizedDevice.id !== creation.deviceId ||
        normalizedDevice.displayName !== creation.displayName ||
        (GARMIN_CAPABILITY_VERSION === 2
          ? normalizedDevice.deviceToken !== creation.deviceNonce
          : GARMIN_CAPABILITY_PATTERN.exec(normalizedDevice.deviceToken)?.[3] !== creation.deviceNonce)
      ))) {
    throw new Error("Garmin device binding was not created.");
  }
  const binding = { version: GARMIN_CAPABILITY_VERSION, userId, deviceId: device.id };
  try {
    rememberGarminPendingRevocation(userId, device.id);
  } catch {
    if (await revokeGarminDeviceById(session, device.id).then(() => true, () => false)) {
      removeGarminCreateRequestForUser(userId, creation.requestId);
    }
    throw userVisibleError(
      "The unseen Garmin token could not be recorded for durable cleanup. It was not revealed; retry after restoring browser storage.",
      "Не вдалося записати невидимий токен Garmin для надійного очищення. Його не було показано; віднови сховище браузера й повтори."
    );
  }
  if (expectedEpoch !== accountEpoch || activeAccount?.userId !== userId || loadRemoteSession()?.user?.id !== userId) {
    try {
      await revokeGarminDeviceById(session, device.id);
      removeGarminCreateRequestForUser(userId, creation.requestId);
      forgetGarminPendingRevocation(userId, device.id);
    } catch {
      // Keep the nonsecret device ID durably for the next same-owner session.
    }
    throw new Error("Garmin pairing completed for a stale account session.");
  }
  try {
    // Persist the nonsecret device ID before the raw one-time token is revealed.
    // If storage fails, no user-visible capability has escaped this function.
    saveGarminBinding({ ...binding, recoveryPending: true });
    removeGarminCreateRequestForUser(userId, creation.requestId);
    forgetGarminPendingRevocation(userId, device.id);
  } catch {
    let revoked = false;
    try {
      await revokeGarminDeviceById(session, device.id);
      revoked = true;
    } catch {
      // Retain the nonsecret device ID for retry while this page remains open.
    }
    if (revoked) {
      removeGarminCreateRequestForUser(userId, creation.requestId);
      forgetGarminPendingRevocation(userId, device.id);
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
    "Copy this Garmin pairing token into Connect IQ settings now. Treat it as a password. Temporary retry material has been removed and the token will not be shown again. Choose Cancel to revoke it.",
    "Зараз скопіюй цей токен сполучення Garmin у налаштування Connect IQ. Стався до нього як до пароля. Тимчасові дані повтору вже видалені, і токен більше не буде показано. Натисни «Скасувати», щоб відкликати його."
  );
  const acknowledged = typeof window.prompt === "function"
    ? window.prompt(tokenPrompt, device.device_token)
    : null;
  if (acknowledged === null) {
    try {
      await revokeGarminDeviceById(session, device.id);
      removeGarminBinding(userId);
      removeGarminCreateRequestForUser(userId, creation.requestId);
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

function loadStoredStateBase(account = activeAccount) {
  const fallback = defaultAppState();
  try {
    const storageKey = activeStorageKey(account);
    const currentRaw = localStorage.getItem(storageKey);
    const legacyRaw = localStorage.getItem(LEGACY_KEY);
    const raw = currentRaw !== null ? currentRaw : (!account ? legacyRaw : null);
    const sourceKey = currentRaw !== null ? storageKey : (!account && legacyRaw !== null ? LEGACY_KEY : null);
    if (raw === null || sourceKey === null) return fallback;
    const validated = validateImportedEnvelope(raw, fallback, {
      migrateLegacyExerciseNameControls: true
    });
    if (validated.migratedLegacyExerciseNameControls) {
      persistLocalExerciseNameMigration(
        sourceKey,
        raw,
        JSON.stringify(validated.state),
        window.GymStateContract.LIMITS.rawBytes
      );
    }
    return validated.state;
  } catch {
    return fallback;
  }
}

function loadState(account = activeAccount) {
  const base = loadStoredStateBase(account);
  try {
    const commit = loadActiveWorkoutCommitLedger(account);
    const loaded = commit ? mergeActiveWorkoutCommitLedger(base, commit.ledger, account) : base;
    if (!loaded) return base;
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
    return base;
  }
}

function normalizeImportedState(parsed, fallback = defaultAppState()) {
  return validateImportedEnvelope(parsed, fallback).state;
}

function validateImportedEnvelope(input, fallback = defaultAppState(), options = {}) {
  const validated = window.GymStateContract.validateAndNormalize(input, {
    fallback,
    migrateLegacyExerciseNameControls: options.migrateLegacyExerciseNameControls === true
  });
  const safe = validated.state;
  return {
    owner: validated.owner,
    diagnostics: validated.diagnostics,
    migratedLegacyExerciseNameControls: validated.migratedLegacyExerciseNameControls === true,
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
    const loadProfile = normalizeExerciseLoadProfile(record?.loadProfile);
    if (!rawName) return [];
    return [{
      id: Number(typeof item === "object" && item?.id || index + 1),
      name: rawName,
      ...(catalogKey ? { catalogKey } : {}),
      ...(hasFavorite || hasLegacyFavorite ? { favorite: favorite === true } : {}),
      ...(loadProfile ? { loadProfile } : {})
    }];
  });
  return normalized;
}

function normalizeExerciseLoadProfile(value) {
  const limits = window.GymStateContract.LIMITS;
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      !["higherIsHarder", "lowerIsHarder"].includes(value.direction) ||
      !Array.isArray(value.allowedWeightsKg) || value.allowedWeightsKg.length < 1 ||
      value.allowedWeightsKg.length > limits.loadProfileWeights) return null;
  const allowedWeightsKg = value.allowedWeightsKg.map(Number);
  if (allowedWeightsKg.some(weight => !Number.isFinite(weight) || weight < 0 || weight > limits.weightMax)) return null;
  if (allowedWeightsKg.some((weight, index) => index > 0 && weight <= allowedWeightsKg[index - 1])) return null;
  return { direction: value.direction, allowedWeightsKg };
}

function preserveExerciseFavorites(nextState, previousState, {
  preferPrevious = false,
  preserveMissingLoadProfiles = false
} = {}) {
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
    if (preserveMissingLoadProfiles && !normalizeExerciseLoadProfile(exercise.loadProfile)) {
      const previousLoadProfile = normalizeExerciseLoadProfile(previous?.loadProfile);
      if (previousLoadProfile) merged.loadProfile = previousLoadProfile;
    }
    return merged;
  });
  return nextState;
}

function preserveLocalProgressExerciseSelection(nextState, previousState) {
  if (!nextState || !Array.isArray(nextState.exercises) ||
      !Array.isArray(previousState?.exercises)) return nextState;
  const previousID = Number(previousState.progressExerciseId);
  if (!Number.isSafeInteger(previousID) || previousID <= 0) return nextState;
  const previous = previousState.exercises.find(exercise => Number(exercise?.id) === previousID);
  if (!previous) return nextState;
  const identity = exerciseMatchKey(previous);
  const matches = nextState.exercises.filter(exercise => exerciseMatchKey(exercise) === identity);
  if (matches.length === 1 && Number.isSafeInteger(Number(matches[0].id)) && Number(matches[0].id) > 0) {
    nextState.progressExerciseId = Number(matches[0].id);
  }
  return nextState;
}

function saveState({ queueRemote = true, markDirty = true } = {}) {
  // Treat every mutation as a security boundary, including values produced by
  // UI event handlers. This prevents a missed range/count check from reaching
  // local storage or the cloud queue.
  const { timers: _legacyTimers, ...persistedState } = state;
  window.GymStateContract.validateAndNormalize({ schemaVersion: 2, ...persistedState }, {
    fallback: defaultAppState()
  });
  if (markDirty) markRemoteStateDirtyBeforeWrite(state);
  localStorage.setItem(activeStorageKey(), JSON.stringify(persistedState));
  if (queueRemote) queueRemoteSave();
}

function uid() {
  const secureCrypto = window.crypto;
  if (!secureCrypto || typeof secureCrypto.getRandomValues !== "function") {
    throw new Error("Secure numeric ID generation is unavailable in this browser.");
  }
  const words = new Uint32Array(2);
  for (let attempt = 0; attempt < 8; attempt += 1) {
    secureCrypto.getRandomValues(words);
    const value = (words[0] & 0x1fffff) * 0x100000000 + words[1];
    if (Number.isSafeInteger(value) && value > 0) return value;
  }
  throw new Error("Secure numeric ID generation failed.");
}

function route() {
  return nav[nav.length - 1];
}

function isSavedWorkoutEditMode(sessionId = route().id) {
  const id = Number(sessionId);
  return route().name === "detail" && Number.isSafeInteger(id) && id > 0 &&
    workoutDetailEditSessionId === id && state.sessions.some(session => session.id === id);
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
  const childNames = new Set(["add", "active", "detail", "summary", "ranks"]);
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
  if (name === "detail" || name === "summary") workoutDetailEditSessionId = null;
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
  workoutDetailEditSessionId = null;
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
  // Starting a workout replaces the Add route in-place. The preceding browser
  // history entry can therefore still point at Add, which render() immediately
  // redirects back to Active while a draft exists. Return straight to Home so
  // the header Back action cannot become a navigation loop.
  if (route().name === "active") return goRoot("workouts");
  if (nav.length <= 1) return;
  if (route().name === "detail") workoutDetailEditSessionId = null;
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

function localDateInputValue(timestamp = Date.now()) {
  const date = new Date(timestamp);
  if (!Number.isFinite(date.getTime())) return "";
  const year = String(date.getFullYear()).padStart(4, "0");
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function workoutTimestampForLocalDateInput(value, referenceTimestamp = Date.now(), nowTimestamp = Date.now()) {
  const textValue = String(value || "");
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(textValue);
  if (!match || textValue > localDateInputValue(nowTimestamp)) return null;
  const [year, month, day] = match.slice(1).map(Number);
  const reference = new Date(referenceTimestamp);
  const safeReference = Number.isFinite(reference.getTime()) ? reference : new Date(nowTimestamp);
  const candidate = new Date(0);
  candidate.setFullYear(year, month - 1, day);
  candidate.setHours(
    safeReference.getHours(),
    safeReference.getMinutes(),
    safeReference.getSeconds(),
    safeReference.getMilliseconds()
  );
  if (candidate.getFullYear() !== year || candidate.getMonth() !== month - 1 || candidate.getDate() !== day) {
    candidate.setHours(12, 0, 0, 0);
    candidate.setFullYear(year, month - 1, day);
  }
  if (candidate.getFullYear() !== year || candidate.getMonth() !== month - 1 || candidate.getDate() !== day) return null;
  const timestamp = candidate.getTime();
  return isWorkoutTimestampAllowed(timestamp, nowTimestamp) ? timestamp : null;
}

function isWorkoutTimestampAllowed(timestamp, nowTimestamp = Date.now()) {
  const limits = window.GymStateContract.LIMITS;
  return Number.isSafeInteger(timestamp) && timestamp >= limits.timestampMin && timestamp <= limits.timestampMax &&
    Number.isSafeInteger(nowTimestamp) && timestamp <= nowTimestamp &&
    localDateInputValue(timestamp) !== "" && localDateInputValue(timestamp) <= localDateInputValue(nowTimestamp);
}

function updateWorkoutDraftDate(value) {
  if (!workoutDraft) return false;
  const timestamp = workoutTimestampForLocalDateInput(value, workoutDraft.startedAt);
  if (timestamp === null) {
    showToast(tx(
      "Choose today or an earlier valid workout date.",
      "Обери сьогоднішню або ранішу коректну дату тренування."
    ));
    return false;
  }
  workoutDraft.startedAt = timestamp;
  render();
  return true;
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

function streakDays(nowTimestamp = Date.now()) {
  const days = [...new Set(state.sessions.map(session => new Date(session.startedAt).setHours(0, 0, 0, 0)))].sort((a, b) => b - a);
  if (!days.length) return 0;
  const expected = new Date(nowTimestamp);
  if (!Number.isFinite(expected.getTime())) return 0;
  expected.setHours(0, 0, 0, 0);
  if (days[0] < expected.getTime()) expected.setDate(expected.getDate() - 1);
  let streak = 0;
  for (const day of days) {
    if (day === expected.getTime()) {
      streak++;
      expected.setDate(expected.getDate() - 1);
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
      ${pendingSharedWorkout ? `<section class="panel highlighted shared-workout-pending"><h2>${tx("Shared workout ready", "Спільне тренування готове")}</h2><p>${tx("Sign in or enter offline mode to review the plan. It will not replace or save anything automatically.", "Увійди або відкрий офлайн-режим, щоб переглянути план. Він нічого не замінить і не збереже автоматично.")}</p>${sharedWorkoutPreviewMarkup(pendingSharedWorkout)}</section>` : ""}
      ${storeDownloadPanel()}
      ${remotePanel}
      ${themePreferencePanel("auth")}
      <details class="local-account-details" ${remoteEnabled ? "" : "open"}><summary>${tx("Offline local account", "Офлайн-акаунт")}</summary><section class="panel auth-panel"><p class="muted">${remoteEnabled ? tx("Fallback for this browser only.", "Запасний режим лише для цього браузера.") : tx("Paste Supabase keys into supabase-config.js to enable real network login.", "Встав ключі Supabase у supabase-config.js, щоб увімкнути справжній мережевий вхід.")}</p><div class="field-row login-row"><input id="local-login-name" autocomplete="username" maxlength="64" aria-label="${txAttr("Name", "Ім'я")}" placeholder="${txAttr("Name", "Ім'я")}"><button class="button" data-action="login-account">${tx("Enter", "Увійти")}</button></div>${accounts.length ? `<div class="saved-accounts"><span class="field-caption">${tx("Saved accounts", "Збережені акаунти")}</span><div class="chip-row">${accounts.map(account => `<button class="chip buttonlike" data-action="login-account" data-name="${escapeAttr(account.name)}">${escapeHtml(account.name)}</button>`).join("")}</div></div>` : ""}</section></details>
      <nav class="auth-links" aria-label="${txAttr("GymApp links", "Посилання GymApp")}"><a href="${PUBLIC_SITE_URL}" target="_blank" rel="noopener noreferrer">${tx("Website", "Сайт")}</a><a href="${SUPPORT_URL}" target="_blank" rel="noopener noreferrer">${tx("Support", "Підтримка")}</a><a href="${PRIVACY_URL}" target="_blank" rel="noopener noreferrer">${tx("Privacy", "Конфіденційність")}</a></nav>
      <div id="toast" class="toast hidden" role="status" aria-live="polite"></div>
    </main>
  </div>`;
}

function storeDownloadPanel() {
  return `<section class="panel store-download-card" aria-labelledby="store-download-title">
    <div class="store-download-copy">
      <span class="eyebrow">${tx("Official apps", "Офіційні застосунки")}</span>
      <h2 id="store-download-title">${tx("Get GymApp", "Завантажити GymApp")}</h2>
      <p class="muted">${tx("Install the Android app or add the companion app to your Garmin watch.", "Встанови застосунок для Android або додай супутній застосунок на годинник Garmin.")}</p>
    </div>
    <div class="store-download-actions">
      <a class="store-download-link" href="${escapeAttr(GOOGLE_PLAY_APP_URL)}" target="_blank" rel="noopener noreferrer">${svg("fitness", "store-download-icon")}<span><small>${tx("GET IT ON", "ЗАВАНТАЖИТИ В")}</small><strong>Google Play</strong></span></a>
      <a class="store-download-link" href="${escapeAttr(garminStoreAppLink())}" target="_blank" rel="noopener noreferrer">${svg("watch", "store-download-icon")}<span><small>${tx("AVAILABLE ON", "ДОСТУПНО В")}</small><strong>Garmin Connect IQ</strong></span></a>
    </div>
  </section>`;
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
  let current = route();
  if (activeWorkout && current.name === "add") {
    nav[nav.length - 1] = { name: "active" };
    replaceNavigationHistory();
    workoutDraft = null;
    current = route();
  } else if (!activeWorkout && current.name === "active") {
    nav = [{ name: "workouts" }];
    replaceNavigationHistory();
    current = route();
  }
  app.innerHTML = `
    <header class="topbar">
      ${nav.length > 1 ? `<button class="icon-button topbar-action" data-action="back" aria-label="${txAttr("Go back", "Назад")}">${svg("back")}</button>` : `<span class="topbar-slot" aria-hidden="true"></span>`}
      <h1>${titleForRoute(current)}</h1>
      ${languageSelectorMarkup()}
    </header>
    <main class="screen screen-${escapeAttr(current.name)}" data-scroll-key="${escapeAttr(routeScrollKey(current))}">${liveWorkoutBanner()}${socialWorkoutInviteBanner()}${pendingSharedWorkoutCard()}${screenMarkup(current)}</main>
    ${isRootRoute(current.name) ? bottomNav() : ""}
    ${modal ? modalMarkup() : ""}
    <div id="toast" class="toast hidden" role="status" aria-live="polite"></div>
  `;
  hydrateRecommendationText();
  bindEvents();
  requestAnimationFrame(restoreVisibleScroll);
  startTimerTicker();
  if (current.name === "leaderboard" ||
      (socialState.status === "idle" && activeAccount?.remote === "supabase")) {
    void refreshSocialData();
  }
  if (current.name === "leaderboard" ||
      (liveWorkoutState.status === "idle" && activeAccount?.remote === "supabase")) {
    void refreshLiveWorkoutData();
  }
  if (current.name === "leaderboard" && activeAccount?.remote === "supabase") {
    void refreshGarminProfileDevices();
  }
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
    add: t("addWorkout"), active: tx("Active Workout", "Активне тренування"), detail: tx("Workout Details", "Деталі тренування"), summary: tx("Workout Summary", "Підсумок тренування"), ranks: t("ranks")
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
  if (current.name === "leaderboard") return friendsProfileScreen();
  if (current.name === "add") return addWorkoutScreen();
  if (current.name === "active") return activeWorkoutScreen();
  if (current.name === "detail") return detailScreen(current.id);
  if (current.name === "summary") return summaryScreen(current.id);
  if (current.name === "ranks") return ranksScreen();
  return workoutsScreen();
}

function monthSwitcher() {
  const isCurrentMonth = (monthOffsets[activeMonthScope()] || 0) === 0;
  return `<section class="month-switcher panel compact">
    <button class="icon-button" data-action="month-prev" aria-label="${txAttr("Previous month", "Попередній місяць")}">${svg("back")}</button>
    <button class="month-current-button" data-action="month-current" ${isCurrentMonth ? "disabled" : ""}><strong>${fmtDate(monthDate().getTime(), { month: "long", year: "numeric" })}</strong><span>${isCurrentMonth ? tx("Current month", "Поточний місяць") : tx("Return to current month", "Повернутися до поточного місяця")}</span></button>
    <button class="icon-button rotate-180" data-action="month-next" aria-label="${txAttr("Next month", "Наступний місяць")}" ${isCurrentMonth ? "disabled" : ""}>${svg("back")}</button>
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
          <button class="${overviewMode === "overview" ? "selected" : ""}" data-action="overview-mode" data-mode="overview" aria-pressed="${overviewMode === "overview"}"><strong>${t("overview")}</strong></button>
          <button class="${overviewMode === "list" ? "selected" : ""}" data-action="overview-mode" data-mode="list" aria-pressed="${overviewMode === "list"}"><strong>${tx("List", "Список")} (${sessions.length})</strong></button>
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
  return `<div class="focus-overview">${focusLensCard(sessions)}</div>`;
}

function focusLensCard(sessions) {
  if (activeWorkout) {
    const counts = activeWorkoutSetCounts(activeWorkout);
    return `<section class="focus-lens active" aria-labelledby="focus-lens-title">
      <div class="focus-lens-copy">
        <span class="focus-lens-eyebrow">${tx("WORKOUT IN PROGRESS", "ТРЕНУВАННЯ ТРИВАЄ")}</span>
        <h2 id="focus-lens-title">${tx("Continue where you stopped", "Продовжуй із місця зупинки")}</h2>
        <p>${tx("Completed sets are already saved in this browser for this account.", "Виконані підходи вже збережено в цьому браузері для цього акаунта.")}</p>
      </div>
      <div class="focus-lens-metrics" aria-label="${txAttr("Active workout progress", "Прогрес активного тренування")}">
        <div><strong>${activeWorkout.blocks.length}</strong><span>${tx("exercises", "вправ")}</span></div>
        <div><strong>${counts.completed}</strong><span>${tx("completed", "виконано")}</span></div>
        <div><strong>${counts.total}</strong><span>${tx("planned sets", "підходів у плані")}</span></div>
      </div>
      <div class="focus-lens-actions"><button class="focus-lens-action" data-action="continue-active-workout">${svg("fitness", "small-icon")}<span>${tx("Continue workout", "Продовжити тренування")}</span></button><button class="focus-lens-discard" data-action="discard-active-workout">${tx("Discard", "Відкинути")}</button></div>
    </section>`;
  }
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
    <button class="focus-lens-action" data-action="open-add">${svg("add", "small-icon")}<span>${tx("Start workout", "Почати тренування")}</span></button>
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
  return `<article class="workout-item clickable" role="button" tabindex="0" data-action="open-detail" data-id="${session.id}">
    <div class="workout-head"><div><h3 class="workout-title">${tx("Workout", "Тренування")} ${fmtDate(session.startedAt)}</h3><span class="muted">${session.note ? `${t("note")}: ${escapeHtml(session.note)}` : tx("No note", "Без нотатки")}</span></div><div class="actions"><span class="chip">${tx("Sets", "Підходи")}: ${summary.sets}</span></div></div>
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
  const cellMarkup = cells.map(day => {
    if (!day) {
      return `<button type="button" class="heat-cell outside" tabindex="-1" aria-hidden="true"></button>`;
    }
    const load = Math.round(byDay.get(day) || 0);
    const date = new Date(d.getFullYear(), d.getMonth(), day);
    const label = `${fmtDate(date.getTime())}: ${load} ${tx("load", "навантаження")}`;
    return `<button type="button" class="heat-cell ${heatLevelClass(load / max)}" tabindex="-1" aria-disabled="true" aria-label="${escapeAttr(label)}" title="${escapeAttr(label)}">${day}</button>`;
  }).join("");
  return `<section class="panel"><div class="section-title"><div><h2>${t("heatmap")}</h2><p>${fmtDate(d.getTime(), { month: "long", year: "numeric" })}</p></div><span class="pill">${n(byDay.size, "active day", "active days", "активний день", "активні дні", "активних днів")}</span></div>
    <div class="metric-grid"><div><span>${tx("Sessions", "Сесії")}</span><strong>${monthSessions.length}</strong></div><div><span>${tx("Load", "Навантаження")}</span><strong>${Math.round(trainingLoad(monthSessions))}</strong></div></div>
    <div class="heatmap-grid">${cellMarkup}</div>
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

function exerciseMuscleBreakdownCard(exercise, framed = false) {
  const active = contributionFor(exercise)
    .filter(item => muscles.some(([id]) => id === item.muscleId) && item.weight > 0)
    .map(item => ({
      ...item,
      label: muscleLabel(item.muscleId),
      weight: clamp(Number(item.weight) || 0, 0, 1)
    }))
    .sort((left, right) => right.weight - left.weight || left.label.localeCompare(right.label, displayLocale()));
  if (!active.length) return "";
  const className = framed
    ? "panel highlighted exercise-muscle-breakdown"
    : "exercise-muscle-breakdown";
  return `<section class="${className}">
    <div class="exercise-muscle-breakdown-heading"><h3>${tx("Top muscle groups", "Топ груп м'язів")}</h3><p>${escapeHtml(exerciseDisplayName(exercise))}</p></div>
    <div class="exercise-muscle-breakdown-bars">${active.map(item => {
      const percent = Math.round(item.weight * 100);
      return `<div class="exercise-muscle-breakdown-row"><div><span>${escapeHtml(item.label)}</span><strong>${percent}%</strong></div><div class="bar-track"><div class="bar-fill ${percentageClass(percent)}"></div></div></div>`;
    }).join("")}</div>
  </section>`;
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
      <div class="hero-info-row"><span class="hero-info-pill">${tx("Exercises", "Вправи")}: ${selectedCount}</span><span class="hero-info-pill">${tx("Sets", "Підходи")}: ${setCount}</span></div>
    </section>
    <section class="panel note-panel"><div class="section-title"><div><span class="eyebrow">${tx("Workout details", "Деталі тренування")}</span><h2>${t("note")}</h2></div></div><label><span class="field-caption">${tx("Workout date", "Дата тренування")}</span><div class="actions"><input type="date" data-workout-date value="${escapeAttr(localDateInputValue(draft.startedAt))}" max="${escapeAttr(localDateInputValue())}" aria-label="${txAttr("Workout date", "Дата тренування")}"><button type="button" class="button ghost" data-action="workout-date-today">${tx("Today", "Сьогодні")}</button></div><span class="muted">${tx("Choose today or an earlier local date.", "Обери сьогоднішню або ранішу дату за місцевим часом.")}</span></label><textarea data-draft="note" maxlength="2000" aria-label="${tAttr("note")}" placeholder="${txAttr("Push day, pull day, deload...", "Push день, pull день, делoad...")}">${escapeHtml(draft.note)}</textarea><span class="field-caption">${tx("Plan templates", "Шаблони плану")}</span><div class="chip-row">${noteTemplates().map(note => `<button class="chip buttonlike" data-action="note-template" data-note="${escapeAttr(note.value)}">${escapeHtml(note.label)}</button>`).join("")}</div></section>
    <section class="panel highlighted workout-template-panel"><div class="section-title"><div><span class="eyebrow">${tx("Plan templates", "Шаблони плану")}</span><h2>${t("templatePicker")}</h2></div>${svg("copy", "small-icon")}</div><button class="button ghost full" data-action="repeat-latest" ${state.sessions.length ? "" : "disabled"}>${svg("copy", "small-icon")}${t("repeatLast")}</button><button class="button ghost full" data-action="template-picker" ${state.sessions.length ? "" : "disabled"}>${svg("copy", "small-icon")}${t("copyWorkout")}</button></section>
    ${trainingProfilePanel()}
    ${smartCoachPanel()}
    <section class="exercise-builder-heading"><div><span class="eyebrow">${t("addWorkout")}</span><h2>${tx("Exercises in this workout", "Вправи в цьому тренуванні")}</h2><p>${tx("Choose movements and log the working sets you plan to complete.", "Обери вправи та запиши робочі підходи, які плануєш виконати.")}</p></div><button class="button exercise-builder-add" data-action="open-workout-exercise-picker" data-picker-target="draft-new" aria-label="${tAttr("addExercise")}">${svg("add", "small-icon")}</button></section>
    <section class="draft-list">${draft.blocks.map((block, index) => draftBlock(block, index)).join("")}</section>
    <section class="panel highlighted"><div class="section-title"><div><span class="eyebrow">${tx("Workout template", "Шаблон тренування")}</span><h2>${tx("Share with a friend", "Поділитися з другом")}</h2><p>${tx("Choose a regular link or send a private GymApp invitation to a confirmed friend. Only exercises, weights, and reps are shared.", "Обери звичайне посилання або надішли особисте запрошення GymApp підтвердженому другу. Передаються лише вправи, вага й повтори.")}</p></div>${svg("share", "small-icon")}</div><button class="button ghost full" data-action="share-draft">${svg("share", "small-icon")}${tx("Share workout plan", "Поділитися планом тренування")}</button></section>
    <section class="panel watch-plan-panel"><div><span class="eyebrow">${t("addWorkout")}</span><h2>${t("syncWatch")}</h2><p class="muted">${tx("Sync sends these planned targets to the watch. Starting here keeps the active workout only in this browser until you finish it.", "Синхронізація надсилає ці заплановані цілі на годинник. Після старту активне тренування зберігається лише в цьому браузері, доки ти його не завершиш.")}</p></div><button class="button ghost full" data-action="sync-watch">${t("syncWatch")}</button></section>
    <section class="panel highlighted"><div><h2>${tx("Complete the whole plan now", "Виконати весь план зараз")}</h2><p class="muted">${tx("All unfinished set fields are checked first and then saved together. No rest timer starts.", "Спочатку перевіряються всі незавершені підходи, після чого вони зберігаються разом. Таймер відпочинку не запускається.")}</p></div><button class="button secondary full" data-action="save-workout">${svg("checkCircle", "small-icon")}${t("saveCompletedWorkout")}</button></section>
    <button class="button full save-workout-button" data-action="start-workout">${svg("fitness", "small-icon")}${tx("Start workout", "Почати тренування")}</button>`;
}

function activeWorkoutSetCounts(workout = activeWorkout) {
  const sets = Array.isArray(workout?.blocks)
    ? workout.blocks.flatMap(block => Array.isArray(block.sets) ? block.sets : [])
    : [];
  return {
    total: sets.length,
    completed: sets.filter(set => set.completed === true).length
  };
}

function latestActiveCompletedEntry(workout = activeWorkout) {
  if (!workout) return null;
  return workout.blocks.flatMap((block, blockIndex) => block.sets.flatMap((set, setIndex) =>
    set.completed === true && Number.isSafeInteger(set.completedAt)
      ? [{ block, blockIndex, set, setIndex }]
      : []
  )).sort((left, right) => right.set.completedAt - left.set.completedAt ||
    right.set.id - left.set.id)[0] || null;
}

function smartRestSecondsForBlock(block) {
  const analysis = analyzeSmartExercise(block);
  if (analysis.role === "Primary") return 180;
  if (analysis.role === "Secondary") return 120;
  if (analysis.role === "Core") return 60;
  return 75;
}

function activeWorkoutScreen() {
  const workout = activeWorkout;
  if (!workout) {
    return `<section class="panel highlighted empty-state-panel"><h2>${tx("No active workout", "Немає активного тренування")}</h2><p>${tx("Build a plan to start a workout.", "Створи план, щоб почати тренування.")}</p><button class="button full" data-action="open-add">${tx("Build workout", "Створити тренування")}</button></section>`;
  }
  const counts = activeWorkoutSetCounts(workout);
  const progress = counts.total ? counts.completed / counts.total * 100 : 0;
  const latestCompleted = latestActiveCompletedEntry(workout);
  const latestCompletedId = latestCompleted && latestCompleted.set.id === activeWorkoutUndoMarker?.setId
    ? latestCompleted.set.id
    : null;
  return `<section class="hero-panel active-workout-hero">
      <div><span class="eyebrow">${tx("ACTIVE WORKOUT", "АКТИВНЕ ТРЕНУВАННЯ")}</span><h2>${tx("Record each completed set", "Записуй кожен виконаний підхід")}</h2><p>${tx("A set is saved locally before Smart Coach starts an exercise-specific rest timer.", "Підхід спочатку зберігається локально, а потім Smart Coach запускає відпочинок відповідно до вправи.")}</p></div>
      <div class="metric-grid active-workout-metrics"><div><span>${tx("Workout time", "Загальний час тренування")}</span><strong data-active-workout-elapsed aria-live="off">${formatActiveWorkoutElapsed(activeWorkoutElapsedMillis(workout))}</strong><small>${tx("includes rest", "разом із відпочинком")}</small></div><div><span>${tx("Exercises", "Вправи")}</span><strong>${workout.blocks.length}</strong></div><div><span>${tx("Completed", "Виконано")}</span><strong>${counts.completed}</strong></div><div><span>${tx("Planned", "Заплановано")}</span><strong>${counts.total}</strong></div></div>
      <div class="progress" role="progressbar" aria-label="${txAttr(`Completed ${counts.completed} of ${counts.total} sets`, `Виконано ${counts.completed} із ${counts.total} підходів`)}" aria-valuemin="0" aria-valuemax="${counts.total}" aria-valuenow="${counts.completed}"><span class="${percentageClass(progress)}"></span></div>
      ${workout.note ? `<p class="active-workout-note"><strong>${t("note")}:</strong> ${escapeHtml(workout.note)}</p>` : ""}
    </section>
    ${activeLiveWorkoutMarkup(workout)}
    ${activeWorkoutUi.message ? `<div class="inline-status ${escapeAttr(activeWorkoutUi.status)}" role="${activeWorkoutUi.status === "error" ? "alert" : "status"}" aria-live="polite">${escapeHtml(activeWorkoutUi.message)}</div>` : ""}
    <section class="active-workout-list">${workout.blocks.map((block, index) => activeWorkoutBlockMarkup(block, index, latestCompletedId)).join("")}</section>
    <section class="panel active-workout-finish"><div><h2>${tx("Finish when you are done", "Заверши, коли закінчиш")}</h2><p class="muted">${tx("Save all validates every unfinished set first and commits them together without starting rest. Finish adds recorded sets to history.", "«Зберегти всі» спочатку перевіряє кожен незавершений підхід і записує їх разом без запуску відпочинку. Завершення додає записані підходи до історії.")}</p></div><div class="actions vertical"><button class="button secondary full" data-action="record-all-active-sets" ${counts.completed < counts.total ? "" : "disabled"}>${svg("checkCircle", "small-icon")}${tx("Save all sets", "Зберегти всі підходи")}</button><button class="button full" data-action="finish-active-workout" ${counts.completed ? "" : "disabled"}>${svg("checkCircle", "small-icon")}${tx("Finish workout", "Завершити тренування")}</button><button class="button danger full" data-action="discard-active-workout">${tx("Discard active workout", "Відкинути активне тренування")}</button></div></section>`;
}

function activeLiveWorkoutMarkup(workout = activeWorkout) {
  if (!workout || liveWorkoutBinding?.localWorkoutId !== workout.id) return "";
  const snapshot = liveWorkoutState.snapshot?.room?.roomId === liveWorkoutBinding.roomId
    ? liveWorkoutState.snapshot
    : null;
  const peer = snapshot?.participants?.find(row => !row.isSelf);
  const total = snapshot?.room?.summary?.setCount || Object.keys(liveWorkoutBinding.serverToLocalSetIds).length;
  const completed = peer?.progress?.completedSets?.length || 0;
  const waiting = liveWorkoutBinding.pendingOperations.length;
  const connection = liveRealtime.status === "subscribed"
    ? tx("Realtime connected", "Realtime підключено")
    : tx("Reconnecting · safe polling active", "Відновлення · працює безпечне опитування");
  return `<section class="panel highlighted"><div class="row-head"><div><span class="eyebrow">LIVE</span><h2>${tx("Training with", "Тренування з")} ${escapeHtml(peer?.profile?.displayName || liveWorkoutBinding.peerDisplayName)}</h2><p>${peer ? `${completed} / ${total} ${tx("friend sets completed", "підходів друга виконано")}` : tx("Refreshing your friend’s progress…", "Оновлюємо прогрес друга…")}</p><small class="muted">${escapeHtml(connection)}</small></div><span class="pill">${waiting ? `${waiting} ${tx("queued", "у черзі")}` : tx("Synced", "Синхронізовано")}</span></div><div class="progress"><span class="${percentageClass(total ? completed / total * 100 : 0)}"></span></div>${liveWorkoutState.error ? `<p class="muted">${escapeHtml(liveWorkoutState.error)}</p>` : ""}<button class="button ghost full" data-action="open-live-room" data-room-id="${escapeAttr(liveWorkoutBinding.roomId)}">${tx("Open both progress lanes", "Відкрити обидві шкали прогресу")}</button></section>`;
}

function activeWorkoutBlockMarkup(block, blockIndex, latestCompletedId = null) {
  const timerKey = `${activeWorkout.id}:${block.exerciseName}`;
  const remaining = timerRemaining(timerKey);
  const completed = block.sets.filter(set => set.completed).length;
  const fullyCompleted = completed === block.sets.length;
  return `<section class="panel highlighted active-workout-exercise ${fullyCompleted ? "completed" : ""}"><details ${fullyCompleted ? "" : "open"}><summary class="detail-summary active-workout-exercise-summary"><div><span class="eyebrow">${tx("Exercise", "Вправа")} ${blockIndex + 1}</span><h2>${escapeHtml(exerciseDisplayName(block))}</h2><p>${completed} / ${block.sets.length} ${tx("sets recorded", "підходів записано")}</p></div>${exerciseMediaThumbnail(block, { className: "compact" })}${fullyCompleted ? `<span class="pill completed-exercise-badge">${svg("checkCircle", "small-icon")}${tx("Completed", "Виконано")}</span>` : ""}</summary>
    <div class="timer-row active-workout-timer"><div><strong>${tx("Rest", "Відпочинок")}</strong><span data-timer-display="${escapeAttr(timerKey)}" aria-live="polite">${remaining > 0 ? formatTimer(remaining) : tx("Ready", "Готово")}</span></div><div class="timer-actions"><button class="button ghost mini" data-action="timer-adjust" data-timer-control="${escapeAttr(timerKey)}" data-seconds="-15" data-key="${escapeAttr(timerKey)}" ${remaining ? "" : "disabled"} aria-label="${txAttr("Subtract 15 seconds", "Відняти 15 секунд")}">−15</button><button class="button ghost mini" data-action="timer-adjust" data-timer-control="${escapeAttr(timerKey)}" data-seconds="15" data-key="${escapeAttr(timerKey)}" ${remaining ? "" : "disabled"} aria-label="${txAttr("Add 15 seconds", "Додати 15 секунд")}">+15</button><button class="button ghost mini" data-action="timer-stop" data-timer-control="${escapeAttr(timerKey)}" data-timer-stop="${escapeAttr(timerKey)}" data-key="${escapeAttr(timerKey)}" ${remaining ? "" : "disabled"}>${tx("Stop", "Стоп")}</button></div></div>
    <div class="active-set-list">${block.sets.map((set, setIndex) => activeWorkoutSetMarkup(set, setIndex, latestCompletedId)).join("")}</div>
  </details></section>`;
}

function activeWorkoutSetMarkup(set, setIndex, latestCompletedId = null) {
  const completedLabel = set.completed
    ? tx("Recorded", "Записано")
    : tx("Record set", "Записати підхід");
  const weightControl = set.completed
    ? `<div class="active-set-value"><span>${tx("Weight (kg)", "Вага (кг)")}</span><strong>${escapeHtml(String(set.weight))}</strong></div>`
    : `<label><span>${tx("Weight (kg)", "Вага (кг)")}</span><input data-active-set-id="${set.id}" data-active-field="weight" inputmode="decimal" value="${escapeAttr(String(set.weight))}"></label>`;
  const repsControl = set.completed
    ? `<div class="active-set-value"><span>${tx("Reps", "Повтори")}</span><strong>${set.reps}</strong></div>`
    : `<label><span>${tx("Reps", "Повтори")}</span><input data-active-set-id="${set.id}" data-active-field="reps" inputmode="numeric" value="${set.reps}"></label>`;
  const action = set.completed
    ? (set.id === latestCompletedId
      ? `<button class="button ghost" data-action="undo-active-set" data-id="${set.id}">${tx("Undo last set", "Скасувати останній підхід")}</button>`
      : `<span class="recorded-set-badge">${completedLabel}</span>`)
    : `<button class="button" data-action="record-active-set" data-id="${set.id}">${completedLabel}</button>`;
  return `<div class="active-set-row ${set.completed ? "completed" : ""}" data-active-set-row="${set.id}"><div class="active-set-label"><strong>${tx("Set", "Підхід")} ${setIndex + 1}</strong><span>${set.completed ? svg("checkCircle", "small-icon") + completedLabel : tx("Planned", "Заплановано")}</span></div>${weightControl}${repsControl}${action}</div>`;
}

function trainingProfilePanel() {
  const p = state.profile;
  return `<section class="panel training-profile-panel"><div class="section-title"><div><span class="eyebrow">${t("addWorkout")}</span><h2>${t("trainingProfile")}</h2><p>${tx("Smart Coach uses this to match your plan, goal and recovery.", "Розумний тренер використовує ці дані, щоб підібрати план з урахуванням цілі та відновлення.")}</p></div></div>
    <span class="field-caption">${tx("Training split", "Спліт тренувань")}</span>
    ${chipSelect("split", ["Upper / Lower", "Full Body", "Push Pull Legs", "Custom"], p.split)}
    <span class="field-caption">${tx("Workouts per week", "Тренувань на тиждень")}</span>
    ${chipSelect("days", [2, 3, 4, 5, 6].map(v => `${v} / week`), `${p.days} / week`)}
    <span class="field-caption">${tx("Training goal", "Ціль тренувань")}</span>
    ${chipSelect("goal", ["Aesthetic Cut", "Muscle Gain", "Strength", "Balanced"], p.goal)}
    <span class="field-caption">${tx("Calorie mode", "Режим калорій")}</span>
    ${chipSelect("calories", ["Deficit", "Maintenance", "Surplus"], p.calories)}
  </section>`;
}

function smartCoachPanel() {
  const effortOptions = ["Auto", "Recovery", "Standard", "Hard"];
  const planStatus = smartPlanStale
    ? `<div class="inline-status warning" role="status"><strong>${tx("Plan needs refresh", "План потрібно оновити")}</strong><span>${tx("Your profile or effort changed. Generate again to recalculate the Smart Coach rows; manual edits were not overwritten.", "Профіль або навантаження змінилися. Згенеруй план ще раз, щоб перерахувати рядки Smart Coach; ручні зміни не перезаписано.")}</span></div>`
    : smartGeneratedPlan
    ? `<div class="smart-plan-status"><div class="metric-grid three"><div><span>${tx("Focus", "Фокус")}</span><strong>${escapeHtml(smartFocusLabel(smartGeneratedPlan.focus))}</strong></div><div><span>${tx("Requested", "Запитано")}</span><strong>${escapeHtml(smartWorkoutEffortLabel(smartGeneratedPlan.requestedEffort))}</strong></div><div><span>${tx("Applied", "Застосовано")}</span><strong>${escapeHtml(smartWorkoutEffortLabel(smartGeneratedPlan.appliedEffort))}</strong></div></div><p class="muted">${escapeHtml(smartGeneratedPlan.adjustment)}</p><p class="smart-rir-guidance">${escapeHtml(smartWorkoutEffortGuidance(smartGeneratedPlan.appliedEffort))}</p></div>`
    : `<p class="smart-rir-guidance">${escapeHtml(smartWorkoutEffortGuidance(smartWorkoutEffort))}</p>`;
  return `<section class="panel highlighted smart-coach-panel"><div class="section-title"><div><span class="eyebrow">${t("smartCoach")}</span><h2>${t("generateSmart")}</h2><p>${tx("Smart Coach balances weekly muscle work, movement patterns, recovery, and your saved history.", "Розумний тренер балансує тижневе навантаження на м’язи, рухові патерни, відновлення та збережену історію.")}</p></div>${svg("auto", "small-icon")}</div><span class="field-caption">${tx("Today's effort", "Навантаження сьогодні")}</span><div class="chip-row smart-effort-chips">${effortOptions.map(effort => `<button class="chip buttonlike ${smartWorkoutEffort === effort ? "selected" : ""}" data-action="smart-effort" data-effort="${effort}" aria-pressed="${smartWorkoutEffort === effort}">${escapeHtml(smartWorkoutEffortLabel(effort))}</button>`).join("")}</div>${planStatus}<button class="button full" data-action="generate-smart">${svg("auto", "small-icon")}${t("generateSmart")}</button></section>`;
}

function smartWorkoutEffortLabel(effort) {
  return ({
    Auto: tx("Auto", "Авто"),
    Recovery: tx("Recovery", "Відновлювальне"),
    Standard: tx("Standard", "Звичайне"),
    Hard: tx("Hard", "Важке")
  })[effort] || tx("Auto", "Авто");
}

function smartWorkoutEffortGuidance(effort) {
  return ({
    Auto: tx("Auto checks recent target-muscle recovery and never promotes the day to Hard on its own.", "Авто перевіряє недавнє відновлення цільових м’язів і ніколи самостійно не підвищує день до важкого."),
    Recovery: tx("Recovery: keep about 3–4 reps in reserve and use an easier, controlled load.", "Відновлювальне: залишай приблизно 3–4 повтори в запасі та використовуй легше контрольоване навантаження."),
    Standard: tx("Standard: keep about 2–3 reps in reserve with clean technique.", "Звичайне: залишай приблизно 2–3 повтори в запасі та зберігай чисту техніку."),
    Hard: tx("Hard: only the first one or two compound lifts use 1–2 reps in reserve; accessories stay controlled.", "Важке: лише перші одна-дві базові вправи виконуються з 1–2 повторами в запасі; допоміжні вправи залишаються контрольованими.")
  })[effort] || tx("Keep about 2–3 reps in reserve with clean technique.", "Залишай приблизно 2–3 повтори в запасі та зберігай чисту техніку.");
}

function smartFocusLabel(focus) {
  return ({
    FullBody: tx("Full body", "Усе тіло"),
    Upper: tx("Upper body", "Верх тіла"),
    Lower: tx("Lower body", "Низ тіла"),
    Push: tx("Push", "Жимові"),
    Pull: tx("Pull", "Тягові"),
    Legs: tx("Legs", "Ноги")
  })[focus] || tx("Balanced", "Збалансовано");
}

function smartMovementLabel(analysis) {
  const labels = {
    Squat: tx("Squat pattern", "Присідальний патерн"),
    LegPress: tx("Leg press pattern", "Патерн жиму ногами"),
    Hinge: tx("Hip hinge", "Тазовий нахил"),
    KneeFlexion: tx("Knee flexion", "Згинання коліна"),
    KneeExtension: tx("Knee extension", "Розгинання коліна"),
    HorizontalPress: tx("Horizontal press", "Горизонтальний жим"),
    VerticalPress: tx("Vertical press", "Вертикальний жим"),
    HorizontalPull: tx("Horizontal pull", "Горизонтальна тяга"),
    VerticalPull: tx("Vertical pull", "Вертикальна тяга"),
    Core: tx("Core", "Кор"),
    Calf: tx("Calves", "Ікри"),
    Accessory: tx("Accessory", "Допоміжна")
  };
  const pattern = [...(analysis?.patterns || [])][0];
  return labels[pattern] || tx("Similar movement", "Схожий рух");
}

function smartRoleLabel(role) {
  return ({
    Primary: tx("Primary", "Основна"),
    Secondary: tx("Compound", "Базова"),
    Isolation: tx("Isolation", "Ізоляційна"),
    Core: tx("Trunk", "Корпус")
  })[role] || tx("Accessory", "Допоміжна");
}

function chipSelect(field, options, selected) {
  return `<div class="chip-row">${options.map(option => `<button class="chip buttonlike ${option === selected ? "selected" : ""}" data-action="profile" data-field="${field}" data-value="${option}">${profileValueLabel(option)}</button>`).join("")}</div>`;
}

function draftBlock(block, blockIndex) {
  const lastWeight = lastWeightFor(block.exerciseName);
  const rec = block.exerciseName ? smartRecommendationForBlock(block) : null;
  const storedExercise = block.exerciseName ? state.exercises.find(exercise => exercisesMatch(exercise, block)) : null;
  const loadProfile = storedExercise ? normalizeExerciseLoadProfile(storedExercise.loadProfile) : null;
  const title = block.exerciseName ? exerciseDisplayName(block) : `${tx("Exercise", "Вправа")} ${blockIndex + 1}`;
  return `<section class="draft-exercise panel highlighted"><details open><summary class="detail-summary"><div class="draft-exercise-title"><h2>${escapeHtml(title)}</h2><p class="muted">${escapeHtml(draftSetSummary(block))}</p></div>${block.exerciseName ? exerciseMediaThumbnail(block, { blockIndex }) : ""}${block.exerciseName ? exerciseDetailBodyMap(block, "collapsed") : ""}<button class="icon-button" data-action="remove-block" data-block="${blockIndex}" aria-label="${txAttr("Remove exercise", "Прибрати вправу")}">${svg("delete")}</button></summary>
    <div class="workout-exercise-choice"><button class="button ghost full" data-action="open-workout-exercise-picker" data-picker-target="draft-replace" data-block="${blockIndex}">${svg("list", "small-icon")}${block.exerciseName ? tx("Change exercise", "Змінити вправу") : tx("Choose exercise", "Обрати вправу")}</button></div>
    ${block.exerciseName ? exerciseMuscleBreakdownCard(block) : ""}
    ${storedExercise ? `<div class="row-line"><span class="muted">${loadProfile ? `${tx("Configured machine weights", "Налаштовані ваги тренажера")}: ${loadProfile.allowedWeightsKg.length}` : tx("Use the exact weights available on this machine.", "Вкажи точні ваги, доступні на цьому тренажері.")}</span><button class="button ghost mini" data-action="configure-load-profile" data-id="${escapeAttr(String(storedExercise.id))}">${tx("Machine weights", "Ваги тренажера")}</button></div>` : ""}
    ${lastWeight != null ? `<div class="row-line"><strong>${tx("Last", "Остання вага")}: ${lastWeight.toFixed(1)} kg</strong><button class="button ghost mini" data-action="apply-last" data-block="${blockIndex}">${t("useLast")}</button></div>` : ""}
    ${rec ? smartPanel(rec, blockIndex) : ""}
    ${block.smartGenerated === true && storedExercise ? `<button class="button ghost full smart-alternatives-button" data-action="smart-alternatives" data-block="${blockIndex}" data-exercise-id="${escapeAttr(String(storedExercise.id))}">${svg("copy", "small-icon")}${tx("Replace with a similar exercise", "Замінити схожою вправою")}</button>` : ""}
    <div class="set-shortcuts"><button class="button ghost" data-action="add-set" data-block="${blockIndex}">${t("addPlannedSet")}</button><button class="button ghost" data-action="copy-set" data-block="${blockIndex}">${t("copyLast")}</button><button class="button ghost full" data-action="plus-set" data-block="${blockIndex}">${t("copyPlus")}</button></div>
    ${block.sets.map((set, setIndex) => `<div class="set-entry"><span>${tx("Set", "Підхід")} ${setIndex + 1}</span><div class="set-row"><input inputmode="decimal" aria-label="${txAttr("Weight", "Вага")}" data-block="${blockIndex}" data-set="${setIndex}" data-field="weight" value="${escapeAttr(set.weight)}" placeholder="kg"><input inputmode="numeric" aria-label="${txAttr("Reps", "Повтори")}" data-block="${blockIndex}" data-set="${setIndex}" data-field="reps" value="${escapeAttr(set.reps)}" placeholder="${txAttr("Reps", "Повтори")}"><button class="icon-button" data-action="remove-set" data-block="${blockIndex}" data-set="${setIndex}" aria-label="${txAttr("Remove set", "Видалити підхід")}">${svg("delete")}</button></div></div>`).join("")}
  </details></section>`;
}

function draftExerciseOptions(block) {
  const options = [...state.exercises].sort((left, right) =>
    exerciseDisplayName(left).localeCompare(exerciseDisplayName(right), state.language) ||
      Number(left.id) - Number(right.id)
  );
  if (block.exerciseName && !options.some(exercise => exercisesMatch(exercise, block))) {
    options.unshift({
      name: block.exerciseName,
      ...(persistedExerciseCatalogKey(block) ? { catalogKey: persistedExerciseCatalogKey(block) } : {})
    });
  }
  return options.map(exercise => `<option value="${escapeAttr(exercise.name)}" ${exercisesMatch(exercise, block) ? "selected" : ""}>${escapeHtml(exerciseDisplayName(exercise))}</option>`).join("");
}

function smartPanel(rec, blockIndex) {
  const setLabel = set => {
    if (set.weight == null) return tx("choose weight", "обери вагу");
    if (rec.loadMode === "Bodyweight" && set.weight === 0) return tx("bodyweight", "власна вага");
    return `${set.weight.toFixed(1)} kg`;
  };
  return `<div class="subpanel smart"><div class="row-head"><div><strong>${t("smartCoach")}</strong><p>${rec.kind}</p></div>${svg("auto", "small-icon")}</div><p>${rec.sets.map(s => `${setLabel(s)} x ${s.reps}`).join(" | ")}</p>${rec.rirGuidance ? `<p class="smart-rir-guidance">${escapeHtml(rec.rirGuidance)}</p>` : ""}<div class="progress"><span class="${percentageClass(rec.confidence * 100)}"></span></div><small>${tx("Confidence", "Впевненість")} ${Math.round(rec.confidence * 100)}%</small>${rec.reasons.slice(0, 3).map(reason => `<p class="muted">${escapeHtml(reason)}</p>`).join("")}<button class="button full" data-action="apply-smart" data-block="${blockIndex}">${svg("auto", "small-icon")}${t("applySmart")}</button></div>`;
}

function smartRecommendationForBlock(block) {
  const recommendation = smartRecommendation(block, {
    appliedEffort: block?.smartEffort,
    hardSlot: block?.smartHardSlot === true,
    recoverySteps: block?.smartRecoverySteps
  });
  const cap = Number(block?.smartSetCap);
  if (block?.smartGenerated !== true || !Number.isInteger(cap) || cap < 1 ||
      cap > window.GymStateContract.LIMITS.setsPerExercise ||
      recommendation.sets.length <= cap) return recommendation;
  return { ...recommendation, sets: recommendation.sets.slice(0, cap) };
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

function clearStoredSharedWorkout() {
  try {
    sessionStorage.removeItem(SHARED_WORKOUT_PENDING_KEY);
  } catch {
    // The in-memory draft still works when private browsing blocks storage.
  }
}

function loadStoredSharedWorkout() {
  if (!window.GymSharedWorkout?.decode) return null;
  try {
    const encoded = sessionStorage.getItem(SHARED_WORKOUT_PENDING_KEY);
    if (!encoded) return null;
    return window.GymSharedWorkout.decode(encoded);
  } catch {
    clearStoredSharedWorkout();
    return null;
  }
}

function captureSharedWorkoutFromLocation() {
  if (!window.GymSharedWorkout?.fromHash || !window.GymSharedWorkout?.removeFromHash) return;
  const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  if (!hash.has(window.GymSharedWorkout.HASH_KEY)) return;
  const containsAuthCredential = ["access_token", "refresh_token", "token", "code"].some(key => hash.has(key));
  if (containsAuthCredential) return;
  try {
    const parsed = window.GymSharedWorkout.fromHash(window.location.hash);
    if (!parsed) throw new TypeError("Shared workout is missing or duplicated.");
    pendingSharedWorkout = parsed;
    pendingSharedWorkoutOrigin = { type: "link" };
    try {
      sessionStorage.setItem(SHARED_WORKOUT_PENDING_KEY, window.GymSharedWorkout.encode(parsed));
    } catch {
      // Keep the validated plan in memory when session storage is unavailable.
    }
  } catch {
    // A malformed or oversized incoming link must not clear an already validated
    // pending plan. The user can still review or dismiss that earlier plan.
    sharedWorkoutStartupError = true;
  } finally {
    const safeHash = window.GymSharedWorkout.removeFromHash(window.location.hash);
    history.replaceState(history.state, "", `${window.location.pathname}${window.location.search}${safeHash}`);
  }
}

function sharedWorkoutPreviewMarkup(plan) {
  if (!plan?.exercises?.length) return "";
  const setCount = plan.exercises.reduce((sum, exercise) => sum + exercise.sets.length, 0);
  const volume = plan.exercises.reduce((sum, exercise) => sum + exercise.sets.reduce(
    (exerciseSum, set) => exerciseSum + set.weight * set.reps,
    0
  ), 0);
  return `<div class="metric-grid three shared-workout-metrics"><div><span>${tx("Exercises", "Вправи")}</span><strong>${plan.exercises.length}</strong></div><div><span>${tx("Sets", "Підходи")}</span><strong>${setCount}</strong></div><div><span>${tx("Volume", "Обсяг")}</span><strong>${escapeHtml(formatSetWeight(volume))}</strong></div></div><div class="shared-workout-preview-list">${plan.exercises.map((exercise, index) => {
    const sets = exercise.sets.map(set => `${formatSetWeight(set.weight)} kg × ${set.reps}`).join(" · ");
    return `<article><span>${index + 1}</span><div><strong>${escapeHtml(exerciseDisplayName(exercise))}</strong><small>${escapeHtml(sets)}</small></div></article>`;
  }).join("")}</div>`;
}

function pendingSharedWorkoutCard() {
  if (!pendingSharedWorkout) return "";
  const stateCopy = activeWorkout
    ? tx(
      "Your active workout was left untouched. Finish or discard it before using this shared plan; the plan will stay ready here.",
      "Активне тренування не змінено. Заверши або відкинь його перед використанням спільного плану; план залишиться тут."
    )
    : workoutDraft
    ? tx(
      "Your current draft is still intact. Replacing it with this shared plan requires a separate confirmation.",
      "Поточна чернетка не змінена. Для заміни її спільним планом потрібне окреме підтвердження."
    )
    : tx(
      "Review the exercises below. The plan becomes an editable draft only after you confirm.",
      "Переглянь вправи нижче. План стане редагованою чернеткою лише після твого підтвердження."
    );
  const primaryAction = activeWorkout
    ? `<button class="button full" data-action="continue-active-workout">${tx("Continue active workout", "Продовжити активне тренування")}</button>`
    : `<button class="button full" data-action="accept-shared-workout">${workoutDraft ? tx("Review draft replacement", "Перевірити заміну чернетки") : tx("Use this workout plan", "Використати цей план")}</button>`;
  return `<section class="panel highlighted shared-workout-pending" aria-labelledby="shared-workout-pending-title"><div class="section-title"><div><span class="eyebrow">${tx("SHARED WORKOUT", "СПІЛЬНЕ ТРЕНУВАННЯ")}</span><h2 id="shared-workout-pending-title">${tx("Shared workout ready", "Спільне тренування готове")}</h2><p>${escapeHtml(stateCopy)}</p></div>${svg("copy", "small-icon")}</div>${sharedWorkoutPreviewMarkup(pendingSharedWorkout)}<div class="actions vertical">${primaryAction}<button class="button ghost full" data-action="dismiss-shared-workout">${tx("Discard shared plan", "Відхилити спільний план")}</button></div></section>`;
}

function applyPendingSharedWorkout(allowDraftReplacement = false) {
  if (!pendingSharedWorkout || !window.GymSharedWorkoutFlow?.prepareImport) return false;
  let decision;
  try {
    decision = window.GymSharedWorkoutFlow.prepareImport(pendingSharedWorkout, {
      hasActiveWorkout: Boolean(activeWorkout),
      hasDraft: Boolean(workoutDraft),
      allowDraftReplacement,
      now: Date.now()
    });
  } catch {
    pendingSharedWorkout = null;
    pendingSharedWorkoutOrigin = null;
    clearStoredSharedWorkout();
    modal = null;
    render();
    showToast(tx(
      "This shared plan cannot be imported safely.",
      "Цей спільний план неможливо безпечно імпортувати."
    ));
    return false;
  }
  if (decision.status === "blocked-active") {
    modal = null;
    render();
    showToast(tx(
      "The shared plan is still waiting. Finish or discard the active workout first.",
      "Спільний план усе ще очікує. Спочатку заверши або відкинь активне тренування."
    ));
    return false;
  }
  if (decision.status === "confirm-replace") {
    modal = { type: "confirm-shared-workout-replace" };
    render();
    return false;
  }
  if (decision.status !== "ready" || !decision.draft) return false;

  // The validated incoming plan stays separate until this explicit commit point.
  // No history, active workout, account state, or cloud row is mutated here.
  workoutDraft = decision.draft;
  pendingSharedWorkout = null;
  pendingSharedWorkoutOrigin = null;
  clearStoredSharedWorkout();
  smartGeneratedPlan = null;
  smartPlanStale = false;
  modal = null;
  nav = [{ name: "workouts" }, { name: "add" }];
  routeScrollPositions.delete("add:root");
  replaceNavigationHistory();
  render();
  showToast(tx("Shared workout opened as a draft.", "Спільне тренування відкрито як чернетку."));
  return true;
}

function dismissPendingSharedWorkout() {
  if (!pendingSharedWorkout) return false;
  pendingSharedWorkout = null;
  pendingSharedWorkoutOrigin = null;
  clearStoredSharedWorkout();
  modal = null;
  render();
  showToast(tx("Shared workout discarded.", "Спільне тренування відхилено."));
  return true;
}

function sharedWorkoutPlanFromDraft(draft) {
  if (!draft || !Array.isArray(draft.blocks)) throw new TypeError("Workout draft is unavailable.");
  return window.GymSharedWorkout.normalize({
    exercises: draft.blocks.map(block => ({
      name: String(block?.exerciseName || "").trim(),
      ...(persistedExerciseCatalogKey(block) ? { catalogKey: persistedExerciseCatalogKey(block) } : {}),
      sets: Array.isArray(block?.sets) ? block.sets.map(set => ({
        weight: Number(String(set?.weight ?? "").replace(",", ".")),
        reps: Number(String(set?.reps ?? ""))
      })) : []
    }))
  });
}

function sharedWorkoutPlanFromSession(session) {
  if (!session) throw new TypeError("Workout is unavailable.");
  return window.GymSharedWorkout.normalize({
    exercises: exerciseReferencesForSession(session).map(exercise => ({
      name: exercise.name,
      ...(persistedExerciseCatalogKey(exercise) ? { catalogKey: persistedExerciseCatalogKey(exercise) } : {}),
      sets: session.sets
        .filter(set => exercisesMatch(set, exercise))
        .map(set => ({ weight: Number(set.weight), reps: Number(set.reps) }))
    })).filter(exercise => exercise.sets.length)
  });
}

async function shareWorkoutPlan(plan) {
  let url;
  try {
    plan = normalizeSocialWorkoutPlan(plan);
    url = window.GymSharedWorkout.buildUrl(SHARED_WORKOUT_URL, plan);
  } catch {
    return showToast(tx(
      "Fill every exercise and set before sharing this workout.",
      "Заповни кожну вправу й підхід перед поширенням тренування."
    ));
  }
  modal = { type: "workout-share", plan, url };
  render();
  if (activeAccount?.remote === "supabase" && !socialState.dashboard && socialState.status !== "loading") {
    void refreshSocialData();
  }
  if (activeAccount?.remote === "supabase" && liveWorkoutState.status === "idle") {
    void refreshLiveWorkoutData();
  }
}

async function shareWorkoutLink(url) {
  if (typeof url !== "string" || !url.startsWith(SHARED_WORKOUT_URL) || url.length > 64 * 1024) {
    return showToast(tx("Workout link is unavailable.", "Посилання на тренування недоступне."));
  }
  const shareData = {
    title: tx("GymApp workout", "Тренування GymApp"),
    text: tx("Open this editable workout plan in GymApp.", "Відкрий цей редагований план тренування у GymApp."),
    url
  };
  if (typeof navigator.share === "function") {
    try {
      await navigator.share(shareData);
      modal = null;
      render();
      return;
    } catch (error) {
      if (error?.name === "AbortError") return;
    }
  }
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(url);
      modal = null;
      render();
      return showToast(tx("Workout link copied.", "Посилання на тренування скопійовано."));
    } catch {
      // Fall through to a selectable, read-only link.
    }
  }
  modal = { type: "shared-workout-link", url };
  render();
}

const SMART_HISTORY_SESSION_LIMIT = 24;
const SMART_FUTURE_CLOCK_SKEW_MS = 24 * 60 * 60 * 1000;
const SMART_COMEBACK_BREAK_DAYS = 10;
const SMART_WORKOUT_EFFORTS = new Set(["Auto", "Recovery", "Standard", "Hard"]);

function smartNormalizeWorkoutEffort(value, fallback = "Standard") {
  return SMART_WORKOUT_EFFORTS.has(value) ? value : fallback;
}

function smartExerciseLoadProfile(exercise) {
  const requested = typeof exercise === "string" ? { name: exercise } : exercise;
  const stored = state.exercises.find(candidate => exercisesMatch(candidate, requested));
  return normalizeExerciseLoadProfile(stored?.loadProfile);
}

function smartLoadDirection(analysis, loadProfile) {
  return loadProfile?.direction || (analysis.loadMode === "Assistance" ? "lowerIsHarder" : "higherIsHarder");
}

function smartSnapAllowedWeight(weight, movement, allowedWeightsKg, direction, targetWeight = null) {
  const current = smartBoundedWeight(weight);
  if (movement === "hold") {
    return allowedWeightsKg.reduce((best, candidate) =>
      Math.abs(candidate - current) < Math.abs(best - current) ? candidate : best
    );
  }
  const increasing = (movement === "harder") === (direction === "higherIsHarder");
  const directional = allowedWeightsKg.filter(value => increasing ? value > current : value < current);
  if (!directional.length) return increasing ? allowedWeightsKg.at(-1) : allowedWeightsKg[0];
  if (targetWeight == null) return increasing ? directional[0] : directional.at(-1);
  const numericTarget = Number(targetWeight);
  const target = Number.isFinite(numericTarget)
    ? clamp(numericTarget, 0, window.GymStateContract.LIMITS.weightMax)
    : current;
  if (increasing) return directional.find(value => value >= target) ?? directional.at(-1);
  return [...directional].reverse().find(value => value <= target) ?? directional[0];
}

function smartSnapGridWeight(weight, movement, direction, targetWeight = null) {
  const current = smartBoundedWeight(weight);
  const step = 2.5;
  const numericTarget = Number(targetWeight);
  const boundedTarget = Number.isFinite(numericTarget)
    ? clamp(numericTarget, 0, window.GymStateContract.LIMITS.weightMax)
    : current;
  if (movement === "hold") return smartBoundedWeight(Math.round(current / step) * step);
  const increasing = (movement === "harder") === (direction === "higherIsHarder");
  if (increasing) {
    const adjacent = (Math.floor(current / step) + 1) * step;
    const directionalTarget = targetWeight == null
      ? adjacent
      : Math.ceil(boundedTarget / step) * step;
    return smartBoundedWeight(Math.max(adjacent, directionalTarget));
  }
  const adjacent = (Math.ceil(current / step) - 1) * step;
  const directionalTarget = targetWeight == null
    ? adjacent
    : Math.floor(boundedTarget / step) * step;
  return smartBoundedWeight(Math.min(adjacent, directionalTarget));
}

function smartAdjustedWeight(weight, movement, analysis, loadProfile, targetWeight = null) {
  const direction = smartLoadDirection(analysis, loadProfile);
  if (loadProfile) {
    return smartBoundedWeight(smartSnapAllowedWeight(
      weight,
      movement,
      loadProfile.allowedWeightsKg,
      direction,
      targetWeight
    ));
  }
  if (["Standard", "Assistance"].includes(analysis.loadMode)) {
    return smartSnapGridWeight(weight, movement, direction, targetWeight);
  }
  if (movement === "hold") return smartBoundedWeight(weight);
  const increasing = (movement === "harder") === (direction === "higherIsHarder");
  const step = chooseWeightStep(weight);
  return smartBoundedWeight(increasing ? Number(weight) + step : Math.max(0, Number(weight) - step));
}

function smartEasierWeight(weight, retainedIntensity, analysis, loadProfile) {
  const current = smartBoundedWeight(weight);
  if (current <= 0 || ["Bodyweight", "None"].includes(analysis.loadMode)) return current;
  const safeIntensity = clamp(Number(retainedIntensity) || 0.9, 0.5, 1);
  const direction = smartLoadDirection(analysis, loadProfile);
  const targetWeight = direction === "lowerIsHarder"
    ? current / safeIntensity
    : current * safeIntensity;
  if (loadProfile) {
    const easierOptions = loadProfile.allowedWeightsKg.filter(value =>
      direction === "lowerIsHarder" ? value > current : value < current
    );
    if (!easierOptions.length) return current;
    return direction === "lowerIsHarder"
      ? (easierOptions.find(value => value >= targetWeight) ?? easierOptions.at(-1))
      : ([...easierOptions].reverse().find(value => value <= targetWeight) ?? easierOptions[0]);
  }
  return smartAdjustedWeight(current, "easier", analysis, loadProfile, targetWeight);
}

function smartRecommendation(exercise, options = {}) {
  const sessions = smartExerciseSessionHistory(exercise);
  const analysis = analyzeSmartExercise(
    typeof exercise === "string" ? { name: exercise } : exercise
  );
  const requestedEffort = smartNormalizeWorkoutEffort(options.appliedEffort, "Standard");
  const appliedEffort = requestedEffort === "Auto" ? "Standard" : requestedEffort;
  const hardSlot = options.hardSlot === true && smartIsCompound(analysis) && sessions.length >= 2;
  const repRange = smartRepRange(analysis);
  const targetSetCount = smartTargetSetCount(analysis, { appliedEffort, hardSlot });
  const loadMode = analysis.loadMode || "Standard";
  const rirGuidance = smartRecommendationRirGuidance(appliedEffort, hardSlot);
  if (!sessions.length) {
    const baseline = tx("No saved history yet, so this starts with a clean baseline.", "Історії ще немає, тому план починається з чистої бази.");
    const defaultReps = smartDefaultTargetReps(analysis, repRange);
    const zeroLoadMode = loadMode === "Bodyweight" || loadMode === "None";
    return {
      kindId: "NewExercise",
      kind: smartKindLabel("NewExercise"),
      sets: Array.from({ length: targetSetCount }, () => ({
        weight: zeroLoadMode ? 0 : null,
        reps: appliedEffort === "Recovery" && loadMode === "Bodyweight"
          ? Math.max(repRange.min, defaultReps - 1)
          : defaultReps
      })),
      loadMode,
      appliedEffort,
      rirGuidance,
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
  const loadProfile = smartExerciseLoadProfile(exercise);
  const loadDirection = smartLoadDirection(analysis, loadProfile);
  const bestEstimatedMax = Math.max(...sessions.map(s => s.estimatedMax));
  const isAssistanceDirection = loadDirection === "lowerIsHarder";
  const canAssessPlateau = !isAssistanceDirection && latest.maxWeight > 0;
  const canAssessRegression = latest.maxWeight > 0 || loadMode === "Bodyweight";
  const plateauDetected = canAssessPlateau && smartPlateauDetected(sessions);
  const repeatedRegression = canAssessRegression && sessions.length >= 3 &&
    smartSessionRegressed(latest, previous, loadDirection) &&
    smartSessionRegressed(previous, sessions[2], loadDirection);
  const completedRepCeiling = smartCompletedAtRepCeiling(latest, targetSetCount, repRange.max) &&
    smartCompletedAtRepCeiling(previous, targetSetCount, repRange.max) &&
    smartPerformanceDidNotDecline(latest, previous, targetSetCount, loadDirection);
  const needsHarderBodyweight = completedRepCeiling && loadMode === "Bodyweight" && latest.maxWeight <= 0;
  const harderWeightAvailable = smartHarderWeightAvailable(
    latest.sets,
    targetSetCount,
    analysis,
    loadProfile
  );
  const earnedProgression = completedRepCeiling && !needsHarderBodyweight && harderWeightAvailable;
  const latestNearBest = !isAssistanceDirection && latest.estimatedMax >= bestEstimatedMax * 0.97;
  const previousVolume = previous?.averageVolumePerSet || latest.averageVolumePerSet;
  const volumeRatio = previousVolume <= 0 ? 1 : latest.averageVolumePerSet / previousVolume;
  const latestStable = latest.sets.length >= 2 && latest.sets.every(set => smartBoundedReps(set.reps, repRange.min) >= repRange.min);
  const latestStrained = latest.minReps < repRange.min || (!isAssistanceDirection && volumeRatio < 0.9);
  const isFatLossDeficit = state.profile.goal === "Aesthetic Cut" && state.profile.calories === "Deficit";

  let kindId;
  if (daysSinceLastSession >= SMART_COMEBACK_BREAK_DAYS) kindId = "Comeback";
  else if (repeatedRegression) kindId = "Deload";
  else if (earnedProgression) kindId = "ProgressiveOverload";
  else if (plateauDetected) kindId = "PlateauBreak";
  else kindId = "HoldAndBuild";
  if (appliedEffort === "Recovery" && !["Deload", "Comeback"].includes(kindId)) {
    kindId = "HoldAndBuild";
  }

  const finalSetCount = ["Deload", "Comeback"].includes(kindId) ? 3 : targetSetCount;
  const baselineSets = smartBaselineSets(latest.sets, finalSetCount, repRange);
  const plateauUsesLowerRange = latest.averageReps >= (repRange.min + repRange.max) / 2;
  const sets = baselineSets.map(set => {
    const weight = smartBoundedWeight(set.weight);
    const reps = smartBoundedReps(set.reps, repRange.min);
    if (kindId === "ProgressiveOverload") {
      return {
        weight: weight > 0 ? smartAdjustedWeight(weight, "harder", analysis, loadProfile) : 0,
        reps: weight > 0 ? repRange.min : repRange.max
      };
    }
    if (kindId === "Deload") {
      return {
        weight: smartEasierWeight(weight, isFatLossDeficit ? 0.9 : 0.92, analysis, loadProfile),
        reps: clamp(reps, repRange.min, repRange.max)
      };
    }
    if (kindId === "Comeback") {
      return {
        weight: smartEasierWeight(weight, comebackMultiplier(daysSinceLastSession), analysis, loadProfile),
        reps: clamp(reps, repRange.min, repRange.max)
      };
    }
    if (kindId === "PlateauBreak") {
      return {
        weight: smartAdjustedWeight(weight, "hold", analysis, loadProfile),
        reps: plateauUsesLowerRange ? repRange.min : repRange.max
      };
    }
    return {
      weight: smartAdjustedWeight(weight, "hold", analysis, loadProfile),
      reps: clamp(reps + 1, repRange.min, repRange.max)
    };
  });
  if (appliedEffort === "Recovery" && !["Deload", "Comeback"].includes(kindId)) {
    baselineSets.slice(0, 3).forEach((set, index) => {
      const weight = smartBoundedWeight(set.weight);
      sets[index] = {
        weight: weight > 0 ? smartEasierWeight(weight, 0.9, analysis, loadProfile) : weight,
        reps: Math.max(
          repRange.min,
          clamp(smartBoundedReps(set.reps, repRange.min), repRange.min, repRange.max) -
            (loadMode === "Bodyweight" && weight === 0 ? 1 : 0)
        )
      };
    });
    sets.length = 3;
  }
  const reasons = [];
  if (latestStable) reasons.push(tx("Last session was stable across the sets.", "Результати останнього тренування були стабільними в усіх підходах."));
  if (latestStrained && !repeatedRegression) reasons.push(tx("One softer session is held steady; a deload needs two comparable regressions.", "Одне слабше тренування утримує навантаження; для розвантаження потрібні два порівнювані спади."));
  if (repeatedRegression) reasons.push(tx("Two comparable regressions in a row triggered a recovery step.", "Два порівнювані спади поспіль запустили відновлювальний крок."));
  if (daysSinceLastSession >= SMART_COMEBACK_BREAK_DAYS) reasons.push(tx(`${daysSinceLastSession} days since this exercise, so the difficulty is adjusted for the return.`, `${daysSinceLastSession} днів без цієї вправи, тому складність скориговано для повернення.`));
  if (!isAssistanceDirection && volumeRatio >= 1.08) reasons.push(tx("Recent volume is trending up.", "Останній обсяг зростає."));
  if (!isAssistanceDirection && volumeRatio < 0.9) reasons.push(tx("Recent volume dropped compared with the previous session.", "Обсяг останнього тренування нижчий за обсяг попереднього."));
  if (plateauDetected) reasons.push(tx("Four comparable sessions showed no meaningful strength, rep, or per-set volume gain.", "Чотири порівнювані тренування не дали помітного приросту сили, повторів або обсягу на підхід."));
  if (latestNearBest) reasons.push(tx("This is close to your best estimated strength for the exercise.", "Це близько до найкращої оцінки сили в цій вправі."));
  if (state.profile.goal === "Aesthetic Cut") reasons.push(tx("Aesthetic goal: the plan favors clean volume and technique.", "Ціль сушки: план тримає чистий обсяг і техніку."));
  if (state.profile.goal === "Muscle Gain") reasons.push(tx("Muscle-gain goal adds recoverable working volume.", "Ціль набору м'язів додає відновлюваний робочий обсяг."));
  if (state.profile.calories === "Deficit") reasons.push(tx("Calorie deficit trims set volume but still allows earned progression.", "Дефіцит калорій зменшує кількість підходів, але не блокує заслужену прогресію."));
  if (state.profile.calories === "Surplus") reasons.push(tx("Calorie surplus allows progression when the completed sessions support it.", "Профіцит калорій дозволяє прогресію, коли її підтверджують виконані тренування."));
  if (needsHarderBodyweight) reasons.unshift(tx("The rep ceiling is complete; add a small external load or choose a harder variation instead of exceeding 10 reps.", "Верхню межу повторів виконано; додайте невелике обтяження або складніший варіант замість перевищення 10 повторів."));
  if (completedRepCeiling && !needsHarderBodyweight && !harderWeightAvailable) reasons.unshift(tx("The configured machine stack is at its hardest boundary, so the weight is held.", "Налаштований стек тренажера вже на найскладнішій межі, тому вагу залишено без змін."));
  if (state.profile.days === 4 && state.profile.split === "Upper / Lower") reasons.push(tx("Upper/lower 4-day plan: the load leaves room for the next session.", "План верх/низ 4 дні: навантаження лишає запас для наступної сесії."));
  if (kindId === "ProgressiveOverload") reasons.push(tx("Two complete sessions reached the rep ceiling without a performance drop, so difficulty increases conservatively.", "Два повні тренування досягли верхньої межі повторів без спаду, тому складність зростає обережно."));
  if (appliedEffort === "Recovery" && !["Deload", "Comeback"].includes(kindId)) reasons.unshift(tx("Recovery mode reduces the load and keeps three controlled sets today.", "Відновлювальний режим зменшує навантаження й залишає сьогодні три контрольовані підходи."));
  const uniqueReasons = [...new Set(reasons)].slice(0, 3);
  return {
    kindId,
    kind: smartKindLabel(kindId),
    sets,
    loadMode,
    appliedEffort,
    rirGuidance: smartRecommendationRirGuidance(appliedEffort, hardSlot, kindId),
    confidence: confidenceFor(sessions.length, latest.sets.length, daysSinceLastSession),
    estimatedVolume: isAssistanceDirection ? 0 : sets.reduce((sum, set) => sum + (set.weight || 0) * set.reps, 0),
    daysSinceLastSession,
    reasons: uniqueReasons.length ? uniqueReasons : [tx("The increase is intentionally conservative.", "Збільшення навмисно невелике.")],
    reason: (uniqueReasons[0] || tx("The increase is intentionally conservative.", "Збільшення навмисно невелике."))
  };
}

function smartRecommendationRirGuidance(appliedEffort, hardSlot, kindId = "") {
  if (["Deload", "Comeback"].includes(kindId)) {
    return tx("Target: 3–4 reps in reserve.", "Ціль: 3–4 повтори в запасі.");
  }
  if (appliedEffort === "Recovery") {
    return tx("Target: 3–4 reps in reserve.", "Ціль: 3–4 повтори в запасі.");
  }
  if (appliedEffort === "Hard" && hardSlot) {
    return tx("Target: 1–2 reps in reserve on this compound lift.", "Ціль: 1–2 повтори в запасі в цій базовій вправі.");
  }
  return tx("Target: 2–3 reps in reserve.", "Ціль: 2–3 повтори в запасі.");
}

function smartHarderWeightAvailable(sets, targetSetCount, analysis, loadProfile) {
  const direction = smartLoadDirection(analysis, loadProfile);
  return (sets || []).slice(0, targetSetCount).some(set => {
    const current = smartBoundedWeight(set?.weight);
    if (current <= 0) return false;
    const harder = smartAdjustedWeight(current, "harder", analysis, loadProfile);
    return direction === "lowerIsHarder" ? harder < current : harder > current;
  });
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
    minWeight: Math.min(...weights),
    averageWeight: weights.reduce((sum, value) => sum + value, 0) / weights.length,
    minReps: Math.min(...reps),
    averageReps: reps.reduce((sum, value) => sum + value, 0) / reps.length,
    volume,
    averageVolumePerSet: volume / sets.length,
    estimatedMax: Math.max(...sets.map(set => set.weight * (1 + set.reps / 30)))
  };
}

function smartRepRange(analysis) {
  const role = analysis?.role || (smartIsCompound(analysis) ? "Secondary" : "Isolation");
  if (state.profile.goal === "Strength") {
    if (role === "Primary") return { min: 4, max: 6 };
    if (role === "Secondary") return { min: 5, max: 8 };
    return { min: 8, max: 10 };
  }
  if (state.profile.goal === "Muscle Gain") {
    if (role === "Primary") return { min: 6, max: 8 };
    if (role === "Secondary") return { min: 7, max: 10 };
    return { min: 8, max: 10 };
  }
  if (state.profile.goal === "Aesthetic Cut") {
    if (role === "Primary") return { min: 6, max: 8 };
    if (role === "Secondary") return { min: 7, max: 10 };
    return { min: 8, max: 10 };
  }
  if (role === "Primary") return { min: 5, max: 8 };
  if (role === "Secondary") return { min: 6, max: 10 };
  return { min: 8, max: 10 };
}

function smartDefaultTargetReps(analysis, repRange) {
  const role = analysis?.role || (smartIsCompound(analysis) ? "Secondary" : "Isolation");
  const target = state.profile.goal === "Strength"
    ? (role === "Primary" ? 5 : role === "Secondary" ? 6 : 8)
    : state.profile.goal === "Muscle Gain"
      ? (role === "Primary" ? 8 : role === "Secondary" ? 9 : 10)
      : state.profile.goal === "Aesthetic Cut"
        ? (role === "Primary" ? 8 : role === "Secondary" ? 9 : 10)
        : (role === "Primary" ? 7 : role === "Secondary" ? 8 : 10);
  return clamp(target, repRange.min, repRange.max);
}

function smartTargetSetCount(analysis, options = {}) {
  const appliedEffort = smartNormalizeWorkoutEffort(options.appliedEffort, "Standard");
  if (appliedEffort === "Recovery") return 3;
  if (appliedEffort === "Hard") {
    return options.hardSlot === true && smartIsCompound(analysis) ? 4 : 3;
  }
  const days = Number(state.profile.days);
  const highFrequency = days >= 5;
  const recoveryLimited = state.profile.calories === "Deficit";
  return analysis?.role === "Primary" && !highFrequency && !recoveryLimited ? 4 : 3;
}

function smartCompletedAtRepCeiling(session, targetSetCount, repCeiling) {
  return Boolean(session?.sets?.length >= targetSetCount) &&
    session.sets.slice(0, targetSetCount).every(set => smartBoundedReps(set.reps, repCeiling) >= repCeiling);
}

function smartPerformanceDidNotDecline(latest, previous, targetSetCount, loadDirection = "higherIsHarder") {
  if (!latest || !previous) return false;
  const latestSets = latest.sets.slice(0, targetSetCount);
  const previousSets = previous.sets.slice(0, targetSetCount);
  const average = (sets, selector) => sets.reduce((sum, set) => sum + selector(set), 0) / sets.length;
  const latestWeight = average(latestSets, set => smartBoundedWeight(set.weight));
  const previousWeight = average(previousSets, set => smartBoundedWeight(set.weight));
  const latestReps = average(latestSets, set => smartBoundedReps(set.reps, 1));
  const previousReps = average(previousSets, set => smartBoundedReps(set.reps, 1));
  const weightDidNotDecline = loadDirection === "lowerIsHarder"
    ? latestWeight <= previousWeight
    : latestWeight >= previousWeight;
  return weightDidNotDecline && latestReps >= previousReps;
}

function smartBaselineSets(latestSets, targetSetCount, repRange) {
  const source = latestSets.slice(0, window.GymStateContract.LIMITS.setsPerExercise);
  const fallback = source.at(-1) || { weight: 0, reps: repRange.min };
  return Array.from({ length: targetSetCount }, (_, index) => source[index] || fallback);
}

function smartSessionRegressed(current, previous, loadDirection = "higherIsHarder") {
  if (!current || !previous) return false;
  if (loadDirection === "lowerIsHarder") {
    return current.averageWeight > previous.averageWeight * 1.03 &&
      current.averageReps <= previous.averageReps * 1.02;
  }
  if (current.maxWeight <= 0 && previous.maxWeight <= 0) {
    return current.averageReps < previous.averageReps * 0.9;
  }
  if (previous.estimatedMax <= 0 || previous.averageVolumePerSet <= 0) return false;
  return current.estimatedMax < previous.estimatedMax * 0.97 &&
    current.averageVolumePerSet < previous.averageVolumePerSet * 0.92;
}

function smartPlateauDetected(sessions) {
  const recent = sessions.slice(0, 4);
  if (recent.length < 4 || recent.some(session => session.estimatedMax <= 0 || session.averageVolumePerSet <= 0)) return false;
  const oldest = recent.at(-1);
  const latest = recent[0];
  const estimatedMaxImproved = oldest.estimatedMax <= 0
    ? latest.estimatedMax > 0
    : latest.estimatedMax > oldest.estimatedMax * 1.015;
  const repsImproved = latest.averageReps > oldest.averageReps + 0.25;
  const volumeImproved = oldest.averageVolumePerSet <= 0
    ? latest.averageVolumePerSet > 0
    : latest.averageVolumePerSet > oldest.averageVolumePerSet * 1.02;
  const maxWeights = recent.map(session => session.maxWeight);
  const stableLoad = Math.max(...maxWeights) - Math.min(...maxWeights) <=
    Math.max(1.25, oldest.maxWeight * 0.02);
  return stableLoad && !estimatedMaxImproved && !repsImproved && !volumeImproved;
}

function smartBoundedWeight(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return 0;
  return clamp(smartRoundToNearestHalfEven(numeric), 0, window.GymStateContract.LIMITS.weightMax);
}

function smartRoundToNearestHalfEven(value) {
  const scaled = value * 2;
  const lower = Math.floor(scaled);
  const fraction = scaled - lower;
  const rounded = Math.abs(fraction - 0.5) < Number.EPSILON * Math.max(1, Math.abs(scaled))
    ? (lower % 2 === 0 ? lower : lower + 1)
    : Math.round(scaled);
  return rounded / 2;
}

function smartBoundedReps(value, fallback) {
  const numeric = Number(value);
  const safe = Number.isFinite(numeric) ? Math.round(numeric) : fallback;
  return clamp(safe, 1, window.GymStateContract.LIMITS.repsMax);
}

function chooseWeightStep(weight) {
  return weight < 60 ? 2.5 : weight < 120 ? 5 : 7.5;
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

function detailScreen(id) {
  const session = state.sessions.find(s => s.id === id);
  if (!session) return `<div class="empty">${tx("Workout not found.", "Тренування не знайдено.")}</div>`;
  const grouped = exerciseReferencesForSession(session).map(exercise => ({ ...exercise, sets: session.sets.filter(set => exercisesMatch(set, exercise)) }));
  const available = state.exercises.filter(exercise => !grouped.some(group => exercisesMatch(group, exercise)));
  const garmin = parseGarminWorkoutMetrics(session.note || "");
  const editing = isSavedWorkoutEditMode(session.id);
  return `${garmin ? garminWorkoutHeader(session, garmin, grouped, editing) : workoutHeader(session, editing)}
    <section class="panel saved-workout-mode ${editing ? "editing" : "reading"}"><div><span class="eyebrow">${editing ? tx("EDIT MODE", "РЕЖИМ РЕДАГУВАННЯ") : tx("READ MODE", "РЕЖИМ ПЕРЕГЛЯДУ")}</span><h2>${editing ? tx("Edit saved workout", "Редагування збереженого тренування") : tx("Saved workout", "Збережене тренування")}</h2><p class="muted">${editing ? tx("Add an exercise or correct saved sets. Timers and set recording stay in active workouts only.", "Додавай вправу або виправляй збережені підходи. Таймери й запис підходів доступні лише в активному тренуванні.") : tx("Exercises stay collapsed for a compact review. Open one card to inspect its recorded sets.", "Вправи залишаються згорнутими для компактного перегляду. Відкрий одну картку, щоб перевірити записані підходи.")}</p></div><button class="button ${editing ? "secondary" : "ghost"}" data-action="${editing ? "finish-workout-edit" : "edit-workout"}" data-id="${escapeAttr(String(session.id))}">${svg(editing ? "checkCircle" : "edit", "small-icon")}${editing ? tx("Done editing", "Завершити редагування") : tx("Edit workout", "Редагувати тренування")}</button></section>
    <section class="panel highlighted"><div class="row-head"><div><h2>${tx("Train together", "Тренуйтеся разом")}</h2><p class="muted">${tx("Share a link or send a private invitation with an editable copy. Account, notes, heart rate, calories, and Garmin data stay private.", "Поділися посиланням або надішли особисте запрошення з редагованою копією. Акаунт, нотатки, пульс, калорії й дані Garmin залишаються приватними.")}</p></div><button class="button ghost" data-action="share-session" data-id="${escapeAttr(session.id)}">${svg("share", "small-icon")}${tx("Share", "Поділитися")}</button></div></section>
    ${garmin ? garminWorkoutMetricsCard(garmin, session.sets.length) : ""}
    ${workoutComparisonCard(session)}
    ${!session.sets.length && grouped.length ? `<section class="panel warning"><h2>${tx("No set data", "Немає даних підходів")}</h2><p>${tx("This imported workout contains exercise names, but no weights or reps. Export a full Backup JSON from the Android app and import it again.", "У цьому імпортованому тренуванні є назви вправ, але немає ваги й повторів. Експортуй повну резервну копію JSON з Android-застосунку й імпортуй її ще раз.")}</p></section>` : ""}
    ${editing ? `<section class="panel"><div class="section-title"><div><h2>${tx("Add Exercise to This Workout", "Додати вправу в це тренування")}</h2><p class="muted">${tx("Search the same full catalog used when creating a workout. A selected exercise is inserted at the top; existing sets and history stay unchanged.", "Шукай у тому самому повному каталозі, що й під час створення тренування. Обрана вправа додається зверху; наявні підходи та історія не змінюються.")}</p></div>${svg("add", "small-icon")}</div>${available.length ? `<button class="button full" data-action="open-workout-exercise-picker" data-picker-target="session" data-session="${escapeAttr(String(session.id))}">${svg("list", "small-icon")}${tx("Choose from catalog", "Обрати з каталогу")}</button>` : `<p class="muted">${tx("All saved exercises are already in this workout.", "Усі збережені вправи вже додано до цього тренування.")}</p>`}</section>` : ""}
    <section class="saved-workout-exercise-list" aria-label="${txAttr("Recorded exercises", "Записані вправи")}">${grouped.map(group => exerciseDetailCard(session, group, editing)).join("")}</section>`;
}

function workoutHeader(session, editing = false) {
  const summary = sessionSummary(session);
  return `<section class="hero-panel workout-detail-hero"><div class="row-head"><h2>${escapeHtml(fmtDate(session.startedAt))}</h2>${editing ? `<button class="icon-button hero-icon-button" data-action="delete-session" data-id="${escapeAttr(session.id)}" aria-label="${txAttr("Delete workout", "Видалити тренування")}">${svg("delete")}</button>` : ""}</div><p>${session.note ? `${t("note")}: ${escapeHtml(session.note)}` : tx("No note", "Без нотатки")}</p><div class="metric-grid three"><div><span>${tx("Exercises", "Вправи")}</span><strong>${summary.exercises}</strong></div><div><span>${tx("Sets", "Підходи")}</span><strong>${summary.sets}</strong></div><div><span>${tx("Volume", "Обсяг")}</span><strong>${Math.round(summary.volume)}</strong></div></div></section>`;
}

function workoutComparisonForSession(session) {
  const limits = window.GymStateContract.LIMITS;
  if (!Array.isArray(state.sessions) || state.sessions.length > limits.sessions) return null;
  const current = comparableWorkoutSnapshot(session);
  if (!current) return null;
  const previous = state.sessions
    .map(comparableWorkoutSnapshot)
    .filter(candidate =>
      candidate &&
      candidate.id !== current.id &&
      (candidate.startedAt < current.startedAt ||
        (candidate.startedAt === current.startedAt && candidate.id < current.id)) &&
      candidate.exerciseSignature.length === current.exerciseSignature.length &&
      candidate.exerciseSignature.every((key, index) => key === current.exerciseSignature[index])
    )
    .sort((left, right) =>
      right.startedAt - left.startedAt || right.id - left.id
    )[0];
  if (!previous) return null;
  return {
    previousStartedAt: previous.startedAt,
    matchedExerciseCount: current.exerciseSignature.length,
    metrics: [
      {
        label: tx("Sets", "Підходи"),
        current: current.setCount,
        previous: previous.setCount
      },
      {
        label: tx("Reps", "Повтори"),
        current: current.totalReps,
        previous: previous.totalReps
      },
      {
        label: tx("Volume", "Обсяг"),
        current: current.totalVolume,
        previous: previous.totalVolume
      }
    ]
  };
}

function comparableWorkoutSnapshot(session) {
  const limits = window.GymStateContract.LIMITS;
  const id = session?.id;
  const startedAt = session?.startedAt;
  const sets = Array.isArray(session?.sets) ? session.sets : [];
  if (!Number.isSafeInteger(id) || id <= 0 ||
      !Number.isSafeInteger(startedAt) ||
      startedAt < limits.timestampMin ||
      startedAt > limits.timestampMax ||
      !sets.length ||
      sets.length > limits.exercisesPerSession * limits.setsPerExercise) {
    return null;
  }
  const exerciseSignature = exerciseReferencesForSession(session)
    .map(exerciseMatchKey)
    .filter(Boolean)
    .sort();
  if (!exerciseSignature.length || exerciseSignature.length > limits.exercisesPerSession) return null;
  let totalReps = 0;
  let totalVolume = 0;
  for (const set of sets) {
    const weight = set?.weight;
    const reps = set?.reps;
    if (typeof weight !== "number" ||
        !Number.isFinite(weight) ||
        weight < 0 ||
        weight > limits.weightMax ||
        !Number.isInteger(reps) ||
        reps < 0 ||
        reps > limits.repsMax) {
      return null;
    }
    totalReps += reps;
    totalVolume += weight * reps;
  }
  return {
    id,
    startedAt,
    exerciseSignature,
    setCount: sets.length,
    totalReps,
    totalVolume
  };
}

function workoutComparisonCard(session) {
  const comparison = workoutComparisonForSession(session);
  if (!comparison) return "";
  return `<section class="panel workout-comparison-card"><div class="section-title"><div><span class="eyebrow">${tx("Previous session", "Попереднє тренування")}</span><h2>${tx("Workout comparison", "Порівняння тренувань")}</h2><p>${comparison.matchedExerciseCount} ${tx("matching exercises", "спільних вправ")} · ${escapeHtml(fmtDate(comparison.previousStartedAt))}</p></div></div><div class="metric-grid">${comparison.metrics.map(metric => {
    const current = Math.round(metric.current);
    const previous = Math.round(metric.previous);
    const difference = current - previous;
    const delta = difference === 0
      ? tx("No change", "Без змін")
      : `${difference > 0 ? "+" : "−"}${Math.abs(difference)}`;
    return `<div><span>${escapeHtml(metric.label)}</span><strong>${current}</strong><small>${tx("Previous", "Раніше")} ${previous} · ${escapeHtml(delta)}</small></div>`;
  }).join("")}</div></section>`;
}

function garminWorkoutHeader(session, metrics, grouped, editing = false) {
  const setCount = grouped.reduce((sum, group) => sum + group.sets.length, 0);
  const completion = n(setCount, "set", "sets", "підхід", "підходи", "підходів");
  const exerciseCount = n(grouped.length, "exercise", "exercises", "вправа", "вправи", "вправ");
  return `<section class="hero-panel garmin-header"><div class="row-head"><div><h2>${tx("Garmin-format strength workout", "Силове тренування у форматі Garmin")}</h2><p>${escapeHtml(fmtDate(session.startedAt))} · ${tx("metrics parsed from the saved note", "показники прочитано зі збереженої нотатки")}</p></div>${editing ? `<button class="icon-button hero-icon-button" data-action="delete-session" data-id="${escapeAttr(session.id)}" aria-label="${txAttr("Delete workout", "Видалити тренування")}">${svg("delete")}</button>` : ""}</div>
    <div class="metric-grid"><div><span>${tx("Duration", "Тривалість")}</span><strong>${escapeHtml(metrics.duration || "—")}</strong><small>${tx("saved session", "збережене тренування")}</small></div><div><span>${tx("Logged", "Записано")}</span><strong>${escapeHtml(completion)}</strong><small>${escapeHtml(exerciseCount)}</small></div></div>
    <p>${editing ? tx("Workout sets are grouped below. Expand an exercise to correct weight or reps, add a missed set, or delete a wrong one.", "Підходи тренування згруповано нижче. Розгорни вправу, щоб виправити вагу чи повтори, додати пропущений підхід або видалити помилковий.") : tx("Workout sets are grouped below in read-only cards. Expand one exercise at a time to review its recorded sets.", "Підходи тренування згруповано нижче в картках лише для перегляду. Розгортай по одній вправі, щоб перевірити записані підходи.")}</p>
  </section>`;
}

function garminWorkoutMetricsCard(metrics, _actualSetCount) {
  const metricSets = Array.isArray(metrics.sets)
    ? metrics.sets.filter(item => item && Number.isInteger(item.index)).slice(0, 60)
    : [];
  const intervalSets = metricSets.filter(item => item.interval);
  const boundedNumber = (value, minimum, maximum) =>
    typeof value === "number" && Number.isFinite(value) && value >= minimum && value <= maximum
      ? value
      : null;
  const zoneClass = zone => `zone-${Math.max(0, Math.min(5, zone))}`;
  const intervalTimelineEnd = intervalSets.reduce((maximum, item) => {
    const end = boundedNumber(item?.interval?.endSeconds, 0, 604800);
    return end === null ? maximum : Math.max(maximum, end);
  }, 0);
  const durationParts = typeof metrics.duration === "string"
    ? /^(\d+):([0-5]\d)(?::([0-5]\d))?$/.exec(metrics.duration)
    : null;
  let durationTimelineEnd = 0;
  if (durationParts) {
    const first = Number(durationParts[1]);
    const second = Number(durationParts[2]);
    const third = durationParts[3] === undefined ? null : Number(durationParts[3]);
    const seconds = third === null ? first * 60 + second : first * 3600 + second * 60 + third;
    durationTimelineEnd = Number.isSafeInteger(seconds) && seconds >= 0 && seconds <= 604800
      ? seconds
      : 0;
  }
  const timelineEnd = Math.max(intervalTimelineEnd, durationTimelineEnd);
  const omittedSetIntervalCount = Number.isInteger(metrics.omittedSetIntervalCount) &&
      metrics.omittedSetIntervalCount >= 1 && metrics.omittedSetIntervalCount <= 60
    ? metrics.omittedSetIntervalCount
    : null;
  const completion = Number.isInteger(metrics.completion?.completedSets) &&
      Number.isInteger(metrics.completion?.plannedSets) &&
      metrics.completion.completedSets >= 0 &&
      metrics.completion.plannedSets > metrics.completion.completedSets
    ? `<p class="muted">${escapeHtml(tx(
        `Original Garmin result: completed ${metrics.completion.completedSets} of ${metrics.completion.plannedSets} planned sets.`,
        `Початковий результат Garmin: виконано ${metrics.completion.completedSets} із ${metrics.completion.plannedSets} запланованих підходів.`
      ))}</p>`
    : "";
  const noteProvenance = tx(
    "Read from the workout note; imported or manually edited notes are not proof of watch origin.",
    "Прочитано з нотатки тренування; імпортована або вручну змінена нотатка не підтверджує походження з годинника."
  );
  const intervalOrderNote = tx(
    "Watch S1, S2, … follow completion order and may differ from the exercise grouping below.",
    "Підходи годинника S1, S2, … ідуть у порядку виконання й можуть відрізнятися від групування за вправами нижче."
  );
  const omittedNotice = omittedSetIntervalCount === null
    ? ""
    : `<p class="muted">${escapeHtml(tx(
        `Set metric rows omitted from the bounded workout note: ${omittedSetIntervalCount}.`,
        `Рядків показників підходів, що не вмістилися в обмежену нотатку тренування: ${omittedSetIntervalCount}.`
      ))}</p>`;
  const timeline = intervalSets.length && timelineEnd > 0
    ? `<svg class="garmin-workout-timeline" role="img" aria-label="${txAttr("Workout timeline with detected active sets", "Хронологія тренування з визначеними активними підходами")}" viewBox="0 0 1000 18" preserveAspectRatio="none">${intervalSets.map(item => {
        const start = boundedNumber(item.interval.startSeconds, 0, timelineEnd) ?? 0;
        const end = boundedNumber(item.interval.endSeconds, start, timelineEnd) ?? start;
        const left = Math.max(0, Math.min(100, start / timelineEnd * 100));
        const rawWidth = Math.max(0.8, (end - start) / timelineEnd * 100);
        const width = Math.max(0, Math.min(100 - left, rawWidth));
        const confidence = boundedNumber(item.statistics?.detectionConfidence, 0, 100);
        const confidenceClass = confidence === null ? "confidence-unknown" :
          (confidence >= 70 ? "confidence-high" : (confidence >= 40 ? "confidence-medium" : "confidence-low"));
        const label = `${tx("Set", "Підхід")} ${item.index}: ${start}–${end}s`;
        return `<rect class="garmin-timeline-set ${confidenceClass}" x="${(left * 10).toFixed(2)}" y="2" width="${(width * 10).toFixed(2)}" height="14" rx="7"><title>${escapeHtml(label)}</title></rect>`;
      }).join("")}</svg>`
    : "";
  const intervalSection = metricSets.length || omittedSetIntervalCount !== null
    ? `<div class="garmin-set-intervals"><div class="section-title"><div><span class="eyebrow">${tx("Workout timeline", "Хронологія тренування")}</span><h3>${tx("Chronological watch set metrics", "Хронологічні показники підходів годинника")}</h3></div></div>${timeline}<p class="muted">${escapeHtml(intervalOrderNote)}</p><p class="muted">${escapeHtml(noteProvenance)}</p>${metricSets.map(item => {
        const interval = item.interval || null;
        const statistics = item.statistics || {};
        const start = interval ? boundedNumber(interval.startSeconds, 0, 604800) : null;
        const end = interval && start !== null
          ? boundedNumber(interval.endSeconds, start, 604800)
          : null;
        const intervalActiveSeconds = start !== null && end !== null ? end - start : null;
        const activeSeconds = intervalActiveSeconds ?? boundedNumber(statistics.activeSeconds, 0, 7200);
        const zoneSeconds = Array.isArray(interval?.zoneSeconds)
          ? interval.zoneSeconds.slice(0, 6).map(value => boundedNumber(value, 0, 7200) ?? 0)
          : [0, 0, 0, 0, 0, 0];
        const measuredZoneSeconds = zoneSeconds.reduce((sum, value) => sum + value, 0);
        let zoneOffsetSeconds = 0;
        const zoneRects = measuredZoneSeconds > 0
          ? zoneSeconds.map((seconds, zone) => {
              if (seconds <= 0) return "";
              const x = zoneOffsetSeconds / measuredZoneSeconds * 1000;
              const width = seconds / measuredZoneSeconds * 1000;
              zoneOffsetSeconds += seconds;
              return `<rect class="${zoneClass(zone)}" x="${x.toFixed(2)}" y="0" width="${width.toFixed(2)}" height="12"><title>Z${zone} ${seconds}s</title></rect>`;
            }).join("")
          : "";
        const zoneBar = measuredZoneSeconds > 0
          ? `<svg class="garmin-zone-stack" role="img" aria-label="${txAttr("Time in heart-rate zones", "Час у пульсових зонах")}" viewBox="0 0 1000 12" preserveAspectRatio="none">${zoneRects}</svg><div class="garmin-zone-legend">${zoneSeconds.map((seconds, zone) => seconds > 0
              ? `<span><i class="${zoneClass(zone)}"></i>Z${zone} ${seconds}s</span>`
              : "").join("")}</div>`
          : (interval ? `<p class="muted garmin-no-zone">${tx("No timed HR zone", "Немає виміряної зони пульсу")}</p>` : "");
        const heartRates = [
          [tx("Start", "Початок"), boundedNumber(statistics.startHeartRate, 0, 240)],
          [tx("Peak", "Пік"), boundedNumber(statistics.peakHeartRate, 0, 240)],
          [tx("Finish", "Завершення"), boundedNumber(statistics.endHeartRate, 0, 240)]
        ];
        const hasHeartRate = heartRates.some(([, value]) => value !== null);
        const heartRateStrip = hasHeartRate
          ? `<div class="garmin-hr-strip" aria-label="${txAttr("Heart rate during this set", "Пульс під час цього підходу")}">${heartRates.map(([label, value]) => `<div><span>${escapeHtml(label)}</span><strong>${value === null ? "—" : value}</strong><small>${value === null ? "" : "bpm"}</small></div>`).join("")}</div>`
          : "";
        const recovery = boundedNumber(statistics.recoveryHeartRateDrop, 0, 240);
        const confidence = boundedNumber(statistics.detectionConfidence, 0, 100);
        const restBefore = boundedNumber(statistics.restBeforeSeconds, 0, 86400);
        const gymCalories = interval ? boundedNumber(interval.gymCalories, 0, 100000) : null;
        const garminCalories = interval ? boundedNumber(interval.garminCalories, 0, 100000) : null;
        const confidenceLabel = confidence === null ? "" : (confidence >= 70
          ? tx("High sensor confidence", "Висока впевненість сенсорів")
          : (confidence >= 40
              ? tx("Medium sensor confidence", "Середня впевненість сенсорів")
              : tx("Low sensor confidence", "Низька впевненість сенсорів")));
        const facts = [
          restBefore === null ? "" : `${tx("Rest before", "Відпочинок перед підходом")} ${formatTimer(restBefore)}`,
          recovery === null ? "" : `${tx("Recovery", "Відновлення")} ↓${recovery} bpm`,
          confidence === null ? "" : `${confidenceLabel} · ${confidence}%`,
          gymCalories === null ? "" : (garminCalories === null
            ? `Gym ${gymCalories} kcal`
            : `Gym ${gymCalories} kcal · Garmin ${garminCalories} kcal`)
        ].filter(Boolean);
        const activeLabel = activeSeconds === null
          ? tx("Set metrics", "Показники підходу")
          : `${activeSeconds}s ${tx("active", "активності")}`;
        const intervalLabel = start === null || end === null ? "" : `<strong>${start}–${end}s</strong>`;
        return `<article class="garmin-set-card"><div class="row-head"><div><span class="eyebrow">${tx("Watch set", "Підхід годинника")} S${item.index}</span><h4>${activeLabel}</h4></div>${intervalLabel}</div>${heartRateStrip}${zoneBar}<div class="garmin-set-facts">${facts.map(value => `<span>${escapeHtml(value)}</span>`).join("")}</div></article>`;
      }).join("")}${omittedNotice}</div>`
    : "";
  return `<details class="panel garmin-metrics garmin-metrics-disclosure"><summary class="garmin-metrics-summary"><div><span class="eyebrow">GARMIN</span><h2>${tx("Watch metrics", "Показники годинника")}</h2><p class="muted">${tx("Heart rate, calories, detected intervals, and sensor insights", "Пульс, калорії, визначені інтервали та дані сенсорів")}</p></div><div class="garmin-metrics-peek"><span>${boundedNumber(metrics.avgHeartRate, 0, 240) === null ? "—" : `${boundedNumber(metrics.avgHeartRate, 0, 240)} bpm`}</span><span>${boundedNumber(metrics.garminCalories, 0, 100000) === null ? "—" : `${boundedNumber(metrics.garminCalories, 0, 100000)} kcal`}</span></div></summary><div class="garmin-metrics-content"><h3>${tx("Garmin strength metrics", "Показники силового тренування Garmin")}</h3>
    <div class="metric-grid">
      <div><span>${tx("Gym kcal", "Gym ккал")}</span><strong>${boundedNumber(metrics.gymCalories, 0, 100000) ?? "—"}</strong><small>${tx("our formula", "наша формула")}</small></div>
      <div><span>${tx("Garmin kcal", "Garmin ккал")}</span><strong>${boundedNumber(metrics.garminCalories, 0, 100000) ?? "—"}</strong><small>${tx("system", "система")}</small></div>
      <div><span>${tx("Avg HR", "Середній пульс")}</span><strong>${boundedNumber(metrics.avgHeartRate, 0, 240) === null ? "—" : `${boundedNumber(metrics.avgHeartRate, 0, 240)} bpm`}</strong><small>${escapeHtml(typeof metrics.duration === "string" ? metrics.duration : tx("duration", "тривалість"))}</small></div>
      <div><span>${tx("Max HR", "Максимальний пульс")}</span><strong>${boundedNumber(metrics.maxHeartRate, 0, 240) === null ? "—" : `${boundedNumber(metrics.maxHeartRate, 0, 240)} bpm`}</strong><small>${escapeHtml(typeof metrics.heartRateZone === "string" ? metrics.heartRateZone : tx("peak", "максимум"))}</small></div>
    </div>
    <p class="muted">${tx("Gym kcal is saved from the Garmin app strength formula. Garmin kcal is the system value Garmin Connect uses for daily calories.", "Gym ккал збережено за силовою формулою застосунку Garmin. Garmin ккал — системне значення, яке Garmin Connect враховує в добових калоріях.")}</p><p class="muted">${tx("Sensor confidence describes the detected set boundary, not proof of exercise identity or technique quality.", "Впевненість сенсорів описує визначення меж підходу, а не підтверджує вправу чи якість техніки.")}</p>${completion}${intervalSection}
  </div></details>`;
}

function parseGarminWorkoutMetrics(note) {
  const sharedParser = window.GymGarminCloud?.parseGarminWorkoutMetrics;
  if (typeof sharedParser === "function") return sharedParser(note);
  if (!/^Garmin(?: Fenix 8)?(?: ·|$)/i.test(String(note || "").trim())) return null;
  const findText = regex => (regex.exec(note || "") || [])[1] || "";
  const findNumber = regex => {
    const value = Number.parseInt(findText(regex), 10);
    return Number.isFinite(value) ? value : null;
  };
  return {
    duration: findText(/(?:Duration|Тривалість|Длительность)\s+([0-9]+:[0-9]{2}(?::[0-9]{2})?)/i),
    gymCalories: findNumber(/Gym\s+(?:kcal|ккал)\s+([0-9]+)/i),
    garminCalories: findNumber(/Garmin\s+(?:kcal|ккал)\s+([0-9]+)/i),
    avgHeartRate: findNumber(/(?:Avg HR|Сер пульс|Средний пульс)\s+([0-9]+)/i),
    maxHeartRate: findNumber(/(?:Max HR|Макс\.? пульс)\s+([0-9]+)/i),
    heartRateZone: findText(/(?:Ending HR zone|HR zone|Кінцева зона пульсу|Зона пульсу|Конечная зона пульса)\s+(Z[0-5])/i),
    completion: null,
    omittedSetIntervalCount: null,
    sets: []
  };
}

function exerciseDetailCard(session, group, editing = false) {
  const reps = group.sets.reduce((sum, set) => sum + safeChartValue(set.reps), 0);
  const volume = group.sets.reduce((sum, set) =>
    sum + safeChartValue(set.weight) * safeChartValue(set.reps), 0);
  const formattedVolume = new Intl.NumberFormat(displayLocale(), { maximumFractionDigits: 0 }).format(volume);
  const setSummary = group.sets.length
    ? `${n(group.sets.length, "set", "sets", "підхід", "підходи", "підходів")} · ${n(reps, "rep", "reps", "повторення", "повторення", "повторень")} · ${formattedVolume} ${tx("kg volume", "кг обсягу")}`
    : tx("No sets", "Немає підходів");
  const actionHeader = editing ? `<span>${tx("Actions", "Дії")}</span>` : "";
  return `<section class="panel highlighted workout-exercise-card saved-workout-exercise-card"><details data-saved-workout-exercise><summary class="detail-summary saved-workout-exercise-summary" aria-expanded="false">${exerciseMediaThumbnail(group, { className: "compact" })}<div class="saved-workout-exercise-copy"><h2>${escapeHtml(exerciseDisplayName(group))}</h2><p class="muted">${escapeHtml(setSummary)}</p></div>${isPr(session, group) ? `<span class="pill saved-workout-pr">${svg("trophy", "small-icon")}${tx("New PR", "Новий рекорд")}</span>` : ""}${exerciseDetailBodyMap(group, "collapsed")}</summary>
    ${exerciseDetailBodyMap(group, "expanded")}
    ${group.sets.length ? `<div class="table saved-workout-table ${editing ? "editing" : "read-only"}"><div class="table-head"><span>${tx("Set", "Підхід")}</span><span>${tx("Weight (kg)", "Вага (кг)")}</span><span>${tx("Reps", "Повтори")}</span>${actionHeader}</div>${group.sets.map((set, i) => `<div class="table-row"><span>${tx("Set", "Підхід")} ${i + 1}</span><span>${formatSetWeight(set.weight)}</span><span>${set.reps}</span>${editing ? `<span class="saved-set-actions"><button class="icon-button" data-action="edit-set" data-id="${set.id}" data-session="${escapeAttr(session.id)}" aria-label="${txAttr("Edit set", "Редагувати підхід")}">${svg("edit")}</button><button class="icon-button" data-action="delete-set" data-id="${set.id}" data-session="${escapeAttr(session.id)}" aria-label="${txAttr("Delete set", "Видалити підхід")}">${svg("delete")}</button></span>` : ""}</div>`).join("")}</div>` : `<div class="empty">${tx("No sets were imported for this exercise.", "Для цієї вправи не імпортовано жодного підходу.")}</div>`}${editing ? `<button class="button ghost full saved-workout-add-set" data-action="add-saved-workout-set" data-session="${escapeAttr(String(session.id))}" data-name="${escapeAttr(group.name)}">${svg("add", "small-icon")}${tx("Add set", "Додати підхід")}</button>` : ""}
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
  return `<section class="hero-panel summary-hero"><div class="summary-hero-title">${svg("checkCircle")}<div><h2>${t("workoutComplete")}</h2><p>${escapeHtml(fmtDate(session.startedAt))}</p></div></div><div class="metric-grid"><div><span>${tx("XP gained", "Отримано XP")}</span><strong>+${xpGain} XP</strong></div><div><span>${tx("Level progress", "Прогрес рівня")}</span><strong>${tx("Level", "Рівень")} ${levelFromXp(xpTotal)}</strong></div><div><span>${tx("Current title", "Поточний ранг")}</span><strong>${rankTitle(xpTotal)}</strong></div><div><span>${tx("Streak", "Серія")}</span><strong>${streakDays()} ${tx("d", "д")}</strong></div></div></section>
    <section class="panel summary-metrics"><div class="section-title"><div><span class="eyebrow">${tx("Workout summary", "Підсумок тренування")}</span><h2>${tx("Progress Summary", "Підсумок прогресу")}</h2><p>${mStats[0] ? `${tx("Most loaded today", "Найбільше навантажено сьогодні")}: ${escapeHtml(mStats[0].label)}` : tx("Mapped muscle load will appear after sets are saved.", "Навантаження м'язів з'явиться після збереження підходів.")}</p></div></div><div class="metric-grid"><div><span>${tx("Exercises", "Вправи")}</span><strong>${summary.exercises}</strong></div><div><span>${tx("Sets", "Підходи")}</span><strong>${summary.sets}</strong></div><div><span>${tx("Volume", "Обсяг")}</span><strong>${Math.round(summary.volume)}</strong></div><div><span>${t("muscleMap")}</span><strong>${escapeHtml(mStats[0]?.label || "—")}</strong></div></div></section>
    ${workoutComparisonCard(session)}
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
  return `<section class="summary-rewards-heading"><span class="eyebrow">${tx("Progress", "Прогрес")}</span><h2>${tx("Missions", "Місії")}</h2><p>${tx("Completed missions and new badges from this finish.", "Завершені місії та нові бейджі після фінішу.")}</p></section>${hasRewards ? [...rewards.missions, ...rewards.badges].map(item => `<section class="panel highlighted reward-card">${rewardRow(item)}</section>`).join("") : `<section class="panel highlighted empty-state-panel"><h3>${tx("No new unlocks", "Нових відкриттів немає")}</h3><p>${tx("Keep logging to unlock more.", "Продовжуй записувати тренування, щоб відкрити більше.")}</p></section>`}`;
}

function rewardRow(item) {
  return `<div class="row-line"><div><strong>${escapeHtml(item.title)}</strong><p>${escapeHtml(item.supporting)}</p></div><div class="actions"><span class="chip">${escapeHtml(item.badge)}</span>${item.reward ? `<span class="pill">+${item.reward} XP</span>` : ""}</div></div>`;
}

async function loginAccount(rawName) {
  if (accountTransitionInProgress) return;
  if (liveWorkoutOperationDrain || liveWorkoutBinding?.pendingOperations?.length) {
    return showToast(tx(
      "Wait for the pending live workout update before switching accounts.",
      "Дочекайся синхронізації live-тренування перед зміною акаунта."
    ));
  }
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
  accountTransitionInProgress = true;
  try {
    const previousAccountList = localStorage.getItem(ACCOUNT_LIST_KEY);
    const previousAuth = localStorage.getItem(AUTH_KEY);
    if (!await fenceWebPushBeforeAccountChange().catch(() => false)) {
      return showToast(tx(
        "Account switch was stopped because old notifications could not be closed safely.",
        "Перемикання акаунта зупинено, бо старі сповіщення не вдалося безпечно закрити."
      ));
    }
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
    exerciseRestTimerLedger = null;
    clearAuthDrafts();
    state = loadState();
    reloadActiveWorkoutContext();
    nav = [{ name: "workouts" }];
    replaceNavigationHistory();
    modal = null;
    render();
  } finally {
    accountTransitionInProgress = false;
  }
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

async function beginRemoteActivation(session, {
  displayName = "",
  requirePasswordUpdate = false,
  activationPurpose = "login"
} = {}) {
  if (liveWorkoutOperationDrain || liveWorkoutBinding?.pendingOperations?.length) {
    throw userVisibleError(
      "Account switch was stopped until the pending live workout update is synchronized.",
      "Перемикання акаунта зупинено, доки не синхронізовано live-тренування."
    );
  }
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
  if (!await fenceWebPushBeforeAccountChange(account.userId).catch(() => false)) {
    throw userVisibleError(
      "Cloud activation was stopped because old notifications could not be closed safely.",
      "Активацію хмарного акаунта зупинено, бо старі сповіщення не вдалося безпечно закрити."
    );
  }
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
  exerciseRestTimerLedger = null;
  liveWorkoutBinding = loadLiveWorkoutBinding();
  state = loadState(account);
  reloadActiveWorkoutContext(account);
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
  const handoff = await beginRemoteActivation(session, options);
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
    activationHandoff = await beginRemoteActivation(session, {
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
      lastSyncedAt: loadSyncBaseline(conflict.userId)?.lastSyncedAt ?? null,
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

async function resolveSyncConflictWithCloud() {
  const conflict = cloudSyncConflict;
  if (!conflict || conflict.userId !== activeAccount?.userId ||
      loadRemoteSession()?.user?.id !== conflict.userId) return;
  const warning = tx(
    "Discard this browser's conflicting changes and use the cloud version? Download a browser backup first. This cannot be undone in GymApp.",
    "Відкинути конфліктні зміни цього браузера й використати хмарну версію? Спочатку завантаж резервну копію браузера. У GymApp це неможливо скасувати."
  );
  if (typeof window.confirm !== "function" || !window.confirm(warning)) return;
  const mutationContext = activeWorkoutMutationContext();
  if (!mutationContext) return showDestructiveSaveFailure();
  const result = await withActiveWorkoutDeletionLock(mutationContext.descriptor, () => {
    if (!activeWorkoutMutationContextIsCurrent(mutationContext) || cloudSyncConflict !== conflict) return false;
    const previousState = state;
    const rollbackRecords = destructivePersistenceRollbackRecords();
    let previousLedgerRaw;
    try {
      previousLedgerRaw = localStorage.getItem(mutationContext.descriptor.commitKey);
    } catch {
      return false;
    }
    if (!rollbackRecords) return false;
    state = conflict.remoteState;
    try {
      saveState({ queueRemote: false, markDirty: false });
      if (!rewriteActiveWorkoutCommitLedger(() => [], mutationContext.account)) {
        throw new Error("Commit ledger could not be cleared for the cloud version.");
      }
      return true;
    } catch {
      state = previousState;
      restoreDestructivePersistenceRecords(rollbackRecords);
      restoreActiveWorkoutCommitLedger(previousLedgerRaw, mutationContext.account);
      return false;
    }
  });
  if (!result.acquired || result.value !== true) return showDestructiveSaveFailure();
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
    lastSyncedAt: Date.now(),
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
  const mutationContext = activeWorkoutMutationContext();
  if (!mutationContext) return showDestructiveSaveFailure();
  cloudRecoveryInProgress = true;
  cloudStateRecovery = null;
  state = defaultAppState();
  try {
    const result = await saveRemoteState({ expectedEpoch, expectedUserId });
    const localReset = await withActiveWorkoutDeletionLock(mutationContext.descriptor, () => {
      if (!activeWorkoutMutationContextIsCurrent(mutationContext)) return false;
      const rollbackRecords = destructivePersistenceRollbackRecords();
      let previousLedgerRaw;
      try {
        previousLedgerRaw = localStorage.getItem(mutationContext.descriptor.commitKey);
      } catch {
        return false;
      }
      if (!rollbackRecords) return false;
      try {
        saveState({ queueRemote: false, markDirty: false });
        if (!rewriteActiveWorkoutCommitLedger(() => [], mutationContext.account)) {
          throw new Error("Commit ledger could not be cleared for cloud recovery.");
        }
        return true;
      } catch {
        restoreDestructivePersistenceRecords(rollbackRecords);
        restoreActiveWorkoutCommitLedger(previousLedgerRaw, mutationContext.account);
        return false;
      }
    });
    if (!localReset.acquired || localReset.value !== true) {
      throw new Error("Recovered cloud state could not replace the browser commit ledger.");
    }
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

function parseCloudAccountDeletionJournal(raw) {
  if (typeof raw !== "string" ||
      new TextEncoder().encode(raw).byteLength > MAX_CLOUD_ACCOUNT_DELETION_JOURNAL_BYTES) {
    return null;
  }
  try {
    const value = JSON.parse(raw);
    if (!value || typeof value !== "object" || Array.isArray(value) ||
        Object.keys(value).sort().join(",") !== "account,createdAt,owner,version" ||
        value.version !== 1 || typeof value.owner !== "string" ||
        !Number.isSafeInteger(value.createdAt) || value.createdAt < 0 ||
        value.createdAt > Date.now() + 60_000 || !value.account ||
        typeof value.account !== "object" || Array.isArray(value.account) ||
        Object.keys(value.account).sort().join(",") !== "email,id,name,remote,userId") {
      return null;
    }
    const account = normalizeStoredAccount(value.account);
    if (account?.remote !== "supabase" || value.owner !== `supabase:${account.userId}`) return null;
    return {
      journal: { version: 1, owner: value.owner, account, createdAt: value.createdAt },
      account,
      raw
    };
  } catch {
    return null;
  }
}

function loadCloudAccountDeletionJournal() {
  try {
    const raw = localStorage.getItem(CLOUD_ACCOUNT_DELETION_JOURNAL_KEY);
    if (raw === null) return null;
    return parseCloudAccountDeletionJournal(raw) || { unreadable: true, raw };
  } catch {
    return { unreadable: true, raw: null };
  }
}

function saveCloudAccountDeletionJournal(account) {
  const normalized = normalizeStoredAccount(account);
  if (normalized?.remote !== "supabase") return null;
  try {
    const existingRaw = localStorage.getItem(CLOUD_ACCOUNT_DELETION_JOURNAL_KEY);
    if (existingRaw !== null) {
      const existing = parseCloudAccountDeletionJournal(existingRaw);
      return existing?.account.userId === normalized.userId ? existing : null;
    }
    const journal = {
      version: 1,
      owner: `supabase:${normalized.userId}`,
      account: normalized,
      createdAt: Date.now()
    };
    const raw = JSON.stringify(journal);
    if (new TextEncoder().encode(raw).byteLength > MAX_CLOUD_ACCOUNT_DELETION_JOURNAL_BYTES) {
      return null;
    }
    localStorage.setItem(CLOUD_ACCOUNT_DELETION_JOURNAL_KEY, raw);
    return localStorage.getItem(CLOUD_ACCOUNT_DELETION_JOURNAL_KEY) === raw
      ? { journal, account: normalized, raw }
      : null;
  } catch {
    return null;
  }
}

function clearCloudAccountDeletionJournal(record) {
  if (!record || typeof record.raw !== "string") return false;
  try {
    const current = localStorage.getItem(CLOUD_ACCOUNT_DELETION_JOURNAL_KEY);
    if (current === null) return true;
    if (current !== record.raw) return false;
    localStorage.removeItem(CLOUD_ACCOUNT_DELETION_JOURNAL_KEY);
    return localStorage.getItem(CLOUD_ACCOUNT_DELETION_JOURNAL_KEY) === null;
  } catch {
    return false;
  }
}

function cloudDeletionTargetsAccount(record, account) {
  const normalized = normalizeStoredAccount(account);
  return Boolean(record?.account?.remote === "supabase" && normalized?.remote === "supabase" &&
    record.account.userId === normalized.userId && record.account.id === normalized.id);
}

function suppressPendingCloudDeletionAtStartup(account, record) {
  if (!record) return account;
  if (record.unreadable === true) {
    // An unreadable durable delete intent has no trustworthy owner to purge.
    // Hide every remote account/session until the journal can be recovered or
    // site data is cleared, while preserving a current local-only account.
    if (account?.remote === "supabase") removeActiveAccountMarkerForDeletion(account);
    clearRemoteSession();
    return account?.remote === "supabase" ? null : account;
  }
  const deletedAccount = record.account;
  // The marker and transient credential are removed only when they still belong
  // to the journal owner. A stale journal must never sign out a different user.
  removeActiveAccountMarkerForDeletion(deletedAccount);
  const session = loadRemoteSession();
  if (session?.user?.id === deletedAccount.userId) clearRemoteSession();
  return cloudDeletionTargetsAccount(record, account) ? null : account;
}

function finishRemovedAccountTransition() {
  resetRemoteSyncContext({ eraseLiveBinding: true });
  clearAuthDrafts();
  clearActiveWorkoutMemory();
  activeAccount = null;
  exerciseRestTimerLedger = null;
  state = loadState();
  nav = [{ name: "workouts" }];
  modal = null;
  replaceNavigationHistory();
  render();
}

function suppressPendingCloudDeletionInCurrentTab(record) {
  if (!record) return;
  removeActiveAccountMarkerForDeletion(record.account);
  const session = loadRemoteSession();
  if (session?.user?.id === record.account.userId) clearRemoteSession();
  if (cloudDeletionTargetsAccount(record, activeAccount)) finishRemovedAccountTransition();
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
  // Invalidate the account before removing account-bound data. A mutation that
  // was queued behind this lock will then fail its exact auth-marker check.
  attempt(() => removeActiveAccountMarkerForDeletion(account));
  attempt(() => {
    localStorage.removeItem(activeStorageKey(account));
    return localStorage.getItem(activeStorageKey(account)) === null;
  });
  attempt(() => removeExerciseRestTimerStorage(account));
  attempt(() => removeActiveWorkoutStorage(account));
  attempt(() => removeActiveWorkoutRecoveryStorage(account));
  attempt(() => removeActiveWorkoutCommitStorage(account));
  attempt(() => removeActiveWorkoutUndoStorage(account));
  attempt(() => removeActiveWorkoutTimingStorage(account));
  attempt(() => removeActiveWorkoutRestTransitionStorage(account));
  attempt(() => removeActiveWorkoutBulkCleanupStorage(account));
  attempt(() => {
    saveAccountList(accountList().filter(item => item.id !== account.id));
    return !accountList().some(item => item.id === account.id);
  });
  attempt(() => { removeGarminBinding(account.userId); return true; });
  attempt(() => { removeGarminCreateRequestForUser(account.userId); return true; });
  attempt(() => { removeGarminEnqueueRequestsForUser(account.userId); return true; });
  attempt(() => { forgetGarminPendingRevocation(account.userId); return true; });
  const pendingAuth = loadAuthTransaction();
  if (pendingAuth?.email === normalizeAuthEmail(account.email)) {
    attempt(() => clearAuthTransaction(pendingAuth.state, pendingAuth.purpose));
  }
  attempt(() => {
    const key = syncBaselineKey(account.userId);
    localStorage.removeItem(key);
    return localStorage.getItem(key) === null;
  });
  attempt(() => {
    const session = loadRemoteSession();
    return session?.user?.id === account.userId ? clearRemoteSession() : true;
  });
  if (activeAccount?.remote === "supabase" && activeAccount.userId === account.userId) {
    finishRemovedAccountTransition();
  }
  return complete;
}

async function completeCloudAccountDeletionCleanup(record) {
  if (!record?.account) return false;
  if (record.account.remote === "supabase") {
    const notificationFenceComplete = sharedActiveAccountMatches(record.account)
      ? await fenceWebPushBeforeAccountChange().catch(() => false)
      : await (
          window.indexedDB
            ? invalidateWebPushUiBeforeAccountChange({ ownerId: record.account.userId })
            : disableWebPushWithoutBindingStorage()
        ).catch(() => false);
    if (!notificationFenceComplete) return false;
  }
  const descriptor = activeWorkoutAccountDescriptor(record.account);
  const cleanupResult = descriptor
    ? await withActiveWorkoutDeletionLock(
        descriptor,
        () => purgeDeletedCloudAccountFromBrowser(record.account)
      )
    : { acquired: false, value: false };
  const complete = cleanupResult.acquired && cleanupResult.value === true;
  if (!complete) {
    // The journal remains durable for the next startup. Still close the exact
    // deleted/unknown account in this tab without touching another account.
    suppressPendingCloudDeletionInCurrentTab(record);
    return false;
  }
  return clearCloudAccountDeletionJournal(record);
}

async function resumeCloudAccountDeletionRecovery(record = loadCloudAccountDeletionJournal()) {
  if (!record) return true;
  if (record.unreadable === true) return false;
  return completeCloudAccountDeletionCleanup(record);
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
  let journalRecord = null;
  try {
    if (!await fenceWebPushBeforeAccountChange().catch(() => false)) {
      throw new Error("Cloud account notifications could not be invalidated safely.");
    }
    journalRecord = saveCloudAccountDeletionJournal(account);
    if (!journalRecord) {
      throw new Error("Cloud account deletion could not be journaled; no request was sent.");
    }
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
    const cleanupComplete = await completeCloudAccountDeletionCleanup(journalRecord);
    showToast(cleanupComplete
      ? tx("Cloud account permanently deleted.", "Хмарний акаунт назавжди видалено.")
      : tx(
        "Cloud account was deleted, but some browser data could not be cleared. Clear site data before using this device again.",
        "Хмарний акаунт видалено, але деякі дані браузера не вдалося очистити. Очисть дані сайту перед повторним використанням цього пристрою."
      ));
  } catch (error) {
    const deterministicFailure = deterministicAuthRequestFailure(error);
    const journalCleared = journalRecord && deterministicFailure
      ? clearCloudAccountDeletionJournal(journalRecord)
      : false;
    if (!journalRecord || (deterministicFailure && journalCleared)) {
      if (hadPendingSave && activeAccount?.userId === account.userId) queueRemoteSave();
      if (!transitionToReauthentication(error)) {
        showToast(friendlyOperationError(
          error,
          "Cloud account deletion failed. Nothing was deleted from this browser.",
          "Не вдалося видалити хмарний акаунт. У цьому браузері нічого не видалено."
        ));
      }
    } else {
      const cleanupComplete = await completeCloudAccountDeletionCleanup(journalRecord);
      showToast(cleanupComplete
        ? tx(
          "The server result could not be confirmed. This browser signed out and cleared the account's local data.",
          "Не вдалося підтвердити результат сервера. Цей браузер вийшов з акаунта й очистив його локальні дані."
        )
        : tx(
          "The server result could not be confirmed and some browser data remains. Clear site data before using this device again.",
          "Не вдалося підтвердити результат сервера, і частина даних браузера залишилася. Очисть дані сайту перед повторним використанням цього пристрою."
        ));
    }
  } finally {
    accountTransitionInProgress = false;
  }
}

async function deleteLocalAccount() {
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
  const timerDescriptor = exerciseRestTimerAccountDescriptor(account);
  const activeWorkoutDescriptor = activeWorkoutAccountDescriptor(account);
  if (!timerDescriptor || !activeWorkoutDescriptor) {
    return showToast(tx(
      "Local account deletion failed. The account remains open; restore browser storage access and try again.",
      "Не вдалося видалити локальний акаунт. Він залишається відкритим; віднови доступ до сховища браузера й спробуй ще раз."
    ));
  }
  accountTransitionInProgress = true;
  try {
    const result = await withActiveWorkoutDeletionLock(activeWorkoutDescriptor, async () => {
      if (!await fenceWebPushBeforeAccountChange().catch(() => false)) return false;
      let snapshots;
      try {
        snapshots = {
          state: localStorage.getItem(stateKey),
          timers: localStorage.getItem(timerDescriptor.storageKey),
          activeWorkout: localStorage.getItem(activeWorkoutDescriptor.storageKey),
          activeWorkoutRecovery: localStorage.getItem(activeWorkoutDescriptor.recoveryKey),
          activeWorkoutCommits: localStorage.getItem(activeWorkoutDescriptor.commitKey),
          activeWorkoutUndo: localStorage.getItem(activeWorkoutDescriptor.undoKey),
          activeWorkoutTiming: localStorage.getItem(activeWorkoutDescriptor.timingKey),
          activeWorkoutRestTransition: localStorage.getItem(activeWorkoutDescriptor.restTransitionKey),
          activeWorkoutBulkCleanup: localStorage.getItem(activeWorkoutDescriptor.bulkCleanupKey),
          accounts: localStorage.getItem(ACCOUNT_LIST_KEY),
          auth: localStorage.getItem(AUTH_KEY)
        };
        if (!removeActiveAccountMarkerForDeletion(account)) {
          throw new Error("Local account marker could not be invalidated.");
        }
        localStorage.removeItem(stateKey);
        localStorage.removeItem(timerDescriptor.storageKey);
        localStorage.removeItem(activeWorkoutDescriptor.storageKey);
        localStorage.removeItem(activeWorkoutDescriptor.recoveryKey);
        localStorage.removeItem(activeWorkoutDescriptor.commitKey);
        localStorage.removeItem(activeWorkoutDescriptor.undoKey);
        localStorage.removeItem(activeWorkoutDescriptor.timingKey);
        localStorage.removeItem(activeWorkoutDescriptor.restTransitionKey);
        localStorage.removeItem(activeWorkoutDescriptor.bulkCleanupKey);
        saveAccountList(accountList().filter(item => item.id !== account.id));
        if (localStorage.getItem(stateKey) !== null ||
            localStorage.getItem(timerDescriptor.storageKey) !== null ||
            localStorage.getItem(activeWorkoutDescriptor.storageKey) !== null ||
            localStorage.getItem(activeWorkoutDescriptor.recoveryKey) !== null ||
            localStorage.getItem(activeWorkoutDescriptor.commitKey) !== null ||
            localStorage.getItem(activeWorkoutDescriptor.undoKey) !== null ||
            localStorage.getItem(activeWorkoutDescriptor.timingKey) !== null ||
            localStorage.getItem(activeWorkoutDescriptor.restTransitionKey) !== null ||
            localStorage.getItem(activeWorkoutDescriptor.bulkCleanupKey) !== null ||
            accountList().some(item => item.id === account.id)) {
          throw new Error("Local account cleanup was not confirmed.");
        }
        return true;
      } catch {
        if (snapshots) {
          try {
            restoreStorageValue(stateKey, snapshots.state);
            restoreStorageValue(timerDescriptor.storageKey, snapshots.timers);
            restoreStorageValue(activeWorkoutDescriptor.storageKey, snapshots.activeWorkout);
            restoreStorageValue(activeWorkoutDescriptor.recoveryKey, snapshots.activeWorkoutRecovery);
            restoreStorageValue(activeWorkoutDescriptor.commitKey, snapshots.activeWorkoutCommits);
            restoreStorageValue(activeWorkoutDescriptor.undoKey, snapshots.activeWorkoutUndo);
            restoreStorageValue(activeWorkoutDescriptor.timingKey, snapshots.activeWorkoutTiming);
            restoreStorageValue(
              activeWorkoutDescriptor.restTransitionKey,
              snapshots.activeWorkoutRestTransition
            );
            restoreStorageValue(
              activeWorkoutDescriptor.bulkCleanupKey,
              snapshots.activeWorkoutBulkCleanup
            );
            restoreStorageValue(ACCOUNT_LIST_KEY, snapshots.accounts);
            restoreStorageValue(AUTH_KEY, snapshots.auth);
          } catch {
            // Keep the account open and report the failed cleanup below.
          }
        }
        return false;
      }
    });
    if (!result.acquired || result.value !== true) throw new Error("Local account deletion lock failed.");
    if (exerciseRestTimerLedger?.owner === timerDescriptor.owner) exerciseRestTimerLedger = null;
    clearRemoteSession();
    finishRemovedAccountTransition();
    showToast(tx("Local account permanently deleted from this browser.", "Локальний акаунт назавжди видалено з цього браузера."));
  } catch {
    showToast(tx(
      "Local account deletion failed. The account remains open; restore browser storage access and try again.",
      "Не вдалося видалити локальний акаунт. Він залишається відкритим; віднови доступ до сховища браузера й спробуй ще раз."
    ));
  } finally {
    accountTransitionInProgress = false;
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
    if (!activationPending && !await flushPendingLiveWorkoutOperationsForTransition()) {
      throw userVisibleError(
        "Account switch was cancelled because a live workout update is still waiting for the server. Retry when the connection is available.",
        "Перемикання акаунта скасовано, бо оновлення live-тренування ще очікує сервер. Повтори, коли з’єднання відновиться."
      );
    }
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
    // A create response may have been lost after the server committed. Move
    // its bearer retry material to a durable nonsecret cleanup record before
    // the session can be erased. Storage failure aborts sign-out.
    const pendingGarminCleanup = remoteUserId
      ? promoteGarminCreateRequestToCleanup(remoteUserId)
      : null;
    if (pendingGarminCleanup?.cleanupKind === "legacy-recovery") {
      // The legacy endpoint generated a different device ID, so blindly
      // revoking this client ID would prove nothing. The raw nonce was never
      // sent to that endpoint and has already been removed; retain a durable
      // list/select recovery marker for the next same-owner session.
      signedOutWithPendingGarminRevocation = true;
    } else if (pendingGarminCleanup) {
      try {
        if (!session?.user?.id || session.user.id !== remoteUserId) {
          throw new Error("The active cloud session cannot revoke this incomplete Garmin pairing.");
        }
        await revokeGarminDeviceById(session, pendingGarminCleanup.deviceId);
        removeGarminCreateRequestMatchingCleanup(
          remoteUserId,
          pendingGarminCleanup.deviceId,
          pendingGarminCleanup.cleanupKind
        );
        forgetGarminPendingRevocation(remoteUserId, pendingGarminCleanup.deviceId);
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
      // Revoke the account binding before erasing the bearer. Local
      // unsubscribe still runs when the RPC is unavailable, so a signed-out
      // browser cannot keep receiving private social/live notifications.
      await revokeWebPush({ session, preservePreference: true });
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
    clearActiveWorkoutMemory();
    activeAccount = null;
    exerciseRestTimerLedger = null;
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
    const pendingCleanup = pendingGarminRevocationForUser(userId);
    if (pendingCleanup?.cleanupKind === "legacy-recovery") {
      throw new Error("An older Garmin creation must be recovered before unpairing.");
    }
    if (pendingCleanup && pendingCleanup.deviceId !== binding.deviceId) {
      await revokeGarminDeviceById(session, pendingCleanup.deviceId);
      removeGarminCreateRequestMatchingCleanup(
        userId,
        pendingCleanup.deviceId,
        pendingCleanup.cleanupKind
      );
      forgetGarminPendingRevocation(userId, pendingCleanup.deviceId);
    }
    await revokeGarminBinding(session);
    if (pendingCleanup?.deviceId === binding.deviceId) {
      removeGarminCreateRequestMatchingCleanup(
        userId,
        pendingCleanup.deviceId,
        pendingCleanup.cleanupKind
      );
      forgetGarminPendingRevocation(userId, pendingCleanup.deviceId);
    }
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
  return `<section class="panel highlighted account-card"><div class="row-head"><div><span class="eyebrow">${tx("Account", "Акаунт")}</span><h2>${escapeHtml(label)}</h2><p>${activeAccount?.remote ? tx("Cloud account with protected synchronization.", "Хмарний акаунт із захищеною синхронізацією.") : tx("Local account on this device.", "Локальний акаунт на цьому пристрої.")}</p></div><span class="pill">${activeAccount?.remote ? tx("Cloud", "Хмара") : tx("Local", "Локально")}</span></div><div class="actions account-actions"><a class="button ghost" href="${escapeAttr(GOOGLE_PLAY_APP_URL)}" target="_blank" rel="noopener noreferrer">${tx("Open Google Play", "Відкрити Google Play")}</a><a class="button ghost" href="${escapeAttr(garminStoreAppLink())}" target="_blank" rel="noopener noreferrer">${tx("Open Garmin Connect IQ", "Відкрити Garmin Connect IQ")}</a>${activeAccount?.remote ? `<button class="button ghost" data-action="change-password">${tx("Change password", "Змінити пароль")}</button>` : ""}${hasGarminBinding ? `<button class="button danger" data-action="unpair-garmin">${tx("Unpair Garmin", "Від’єднати Garmin")}</button>` : ""}<button class="button ghost" data-action="logout-account">${tx("Switch", "Змінити акаунт")}</button><button class="button danger" data-action="delete-account">${activeAccount?.remote ? tx("Delete cloud account", "Видалити хмарний акаунт") : tx("Delete local account", "Видалити локальний акаунт")}</button></div></section>`;
}

function cloudSyncStatusSnapshot() {
  if (!activeAccount?.remote || !remoteAuthEnabled()) {
    return { status: "local", lastSyncedAt: null, error: "" };
  }
  const userId = activeAccount.userId;
  const baseline = loadSyncBaseline(userId);
  if (cloudSyncConflict?.userId === userId || cloudStateRecovery?.userId === userId) {
    return { status: "conflict", lastSyncedAt: baseline?.lastSyncedAt ?? null, error: "" };
  }
  if (cloudSyncUi.userId === userId && ["checking", "saving", "error"].includes(cloudSyncUi.status)) {
    return {
      status: cloudSyncUi.status,
      lastSyncedAt: baseline?.lastSyncedAt ?? null,
      error: cloudSyncUi.error
    };
  }
  if (baseline?.pending || baseline?.dirty || remoteSaveTimer !== null) {
    return { status: "pending", lastSyncedAt: baseline?.lastSyncedAt ?? null, error: "" };
  }
  if (baseline && !baseline.dirty) {
    return { status: "synced", lastSyncedAt: baseline.lastSyncedAt ?? baseline.updatedAt, error: "" };
  }
  return { status: "checking", lastSyncedAt: null, error: "" };
}

function cloudSyncPanel() {
  if (!activeAccount?.remote || !remoteAuthEnabled()) return "";
  const snapshot = cloudSyncStatusSnapshot();
  const labels = {
    checking: tx("Checking cloud data", "Перевіряємо хмарні дані"),
    saving: tx("Saving workout changes", "Зберігаємо зміни тренувань"),
    pending: tx("Saved here · waiting to sync", "Збережено тут · очікує синхронізації"),
    synced: tx("Workout history is synced", "Історію тренувань синхронізовано"),
    conflict: tx("Sync needs your choice", "Синхронізація потребує твого вибору"),
    error: tx("Sync needs attention", "Синхронізація потребує уваги")
  };
  const lastSynced = Number.isSafeInteger(snapshot.lastSyncedAt)
    ? `${tx("Last confirmed", "Останнє підтвердження")}: ${new Intl.DateTimeFormat(displayLocale(), {
        dateStyle: "medium",
        timeStyle: "short"
      }).format(new Date(snapshot.lastSyncedAt))}`
    : tx("No confirmed sync yet", "Підтвердженої синхронізації ще немає");
  const busy = snapshot.status === "checking" || snapshot.status === "saving";
  return `<section class="panel highlighted cloud-sync-card" aria-live="polite"><div class="row-head"><div><span class="eyebrow">${tx("Cloud sync", "Хмарна синхронізація")}</span><h2>${escapeHtml(labels[snapshot.status] || labels.checking)}</h2><p>${escapeHtml(lastSynced)}</p></div><span class="sync-state-dot ${escapeAttr(snapshot.status)}" aria-hidden="true"></span></div>${snapshot.error ? `<p class="inline-status error" role="alert">${escapeHtml(snapshot.error)}</p>` : ""}<p class="muted">${tx("Cloud sync stores completed workout history and exercises. Confirmed friends receive only the summaries allowed in Friends settings; active workouts and Smart Coach settings stay on this device.", "Хмарна синхронізація зберігає завершену історію тренувань і вправи. Підтверджені друзі отримують лише підсумки, дозволені в налаштуваннях друзів; активні тренування й налаштування Smart Coach залишаються на цьому пристрої.")}</p><button class="button ghost full" data-action="sync-cloud-now" ${busy ? "disabled" : ""}>${snapshot.status === "error" ? tx("Retry sync", "Повторити синхронізацію") : tx("Sync now", "Синхронізувати зараз")}</button></section>`;
}

function webPushPanel() {
  if (!activeAccount?.remote || !remoteAuthEnabled()) return "";
  const supported = webPushSupported() && Boolean(supabaseConfig().webPushVapidPublicKey);
  const permission = supported ? window.Notification.permission : "unsupported";
  const enabled = webPushPreferenceEnabled() && permission === "granted";
  const registered = enabled && webPushState.status === "registered" &&
    webPushState.source === webPushSource();
  const title = !supported
    ? tx("System notifications unavailable", "Системні сповіщення недоступні")
    : permission === "denied"
      ? tx("Notifications blocked by the browser", "Сповіщення заблоковані браузером")
      : registered
        ? tx("System notifications are on", "Системні сповіщення увімкнено")
        : webPushMutationInProgress
          ? tx("Updating notifications", "Оновлюємо сповіщення")
          : tx("Get live workout alerts", "Отримуй сповіщення live-тренування");
  const action = enabled ? "disable-web-push" : "enable-web-push";
  const actionLabel = enabled
    ? tx("Turn off system notifications", "Вимкнути системні сповіщення")
    : permission === "denied"
      ? tx("Allow in browser settings", "Дозволити в налаштуваннях браузера")
      : tx("Turn on system notifications", "Увімкнути системні сповіщення");
  return `<section class="panel highlighted" aria-live="polite"><div class="row-head"><div><span class="eyebrow">${tx("Notifications", "Сповіщення")}</span><h2>${escapeHtml(title)}</h2><p>${tx("Receive friend requests and important live events even when GymApp is not open: invitation, join, start, finish, or room close.", "Отримуй запити в друзі та важливі live-події, навіть коли GymApp не відкритий: запрошення, приєднання, старт, завершення або закриття кімнати.")}</p></div><span class="pill">${registered ? tx("On", "Увімкнено") : tx("Off", "Вимкнено")}</span></div><p class="muted">${tx("The push service receives only a bounded event type and opaque object ID — never exercise names, weights, reps, notes, email, or profile details.", "Push-сервіс отримує лише обмежений тип події та непрозорий ID об’єкта — без назв вправ, ваги, повторів, нотаток, email чи даних профілю.")}</p>${webPushState.error ? `<p class="inline-status error" role="alert">${escapeHtml(webPushState.error)}</p>` : ""}<button class="button ghost full" data-action="${action}" ${!supported || permission === "denied" || webPushMutationInProgress ? "disabled" : ""}>${escapeHtml(actionLabel)}</button></section>`;
}

async function syncCloudNow() {
  if (!activeAccount?.remote || !remoteAuthEnabled() || accountTransitionInProgress) return false;
  const expectedEpoch = accountEpoch;
  const expectedUserId = activeAccount.userId;
  setCloudSyncUi("checking", "", expectedUserId);
  render();
  try {
    await pullRemoteState();
    if (expectedEpoch !== accountEpoch || activeAccount?.userId !== expectedUserId) return false;
    if (cloudSyncConflict?.userId === expectedUserId || cloudStateRecovery?.userId === expectedUserId) {
      render();
      return false;
    }
    await flushPendingRemoteSave();
    if (expectedEpoch !== accountEpoch || activeAccount?.userId !== expectedUserId) return false;
    setCloudSyncUi("synced", "", expectedUserId);
    render();
    showToast(tx("Workout history synced.", "Історію тренувань синхронізовано."));
    return true;
  } catch (error) {
    if (transitionToReauthentication(error)) return false;
    if (expectedEpoch === accountEpoch && activeAccount?.userId === expectedUserId) {
      setCloudSyncUi("error", friendlySyncError(error), expectedUserId);
      render();
    }
    return false;
  }
}

function profileDataPanel() {
  return `<section class="panel profile-data-card"><div class="section-title"><div><span class="eyebrow">${tx("Your data", "Твої дані")}</span><h2>${t("backup")}</h2></div></div><p class="muted">${tx("A full import replaces this profile. Manual backups include favorite exercises; cloud schema-v2 intentionally keeps favorites local to this account and device.", "Повний імпорт замінює цей профіль. Ручна резервна копія містить улюблені вправи; хмарна schema-v2 навмисно зберігає їх локально для цього акаунта й пристрою.")}</p><div class="actions"><button class="button ghost" data-action="export-json">${t("exportJson")}</button><button class="button ghost" data-action="import-json">${t("importJson")}</button><button class="button ghost full" data-action="export-diagnostics">${t("diagnostics")}</button></div></section>
    <section class="panel profile-links-card"><div><span class="eyebrow">${tx("Help and trust", "Допомога й довіра")}</span><h2>${tx("Support and privacy", "Підтримка та приватність")}</h2><p class="muted">${tx("Find setup help or review how GymApp handles your data.", "Знайди допомогу з налаштуванням або переглянь, як GymApp обробляє твої дані.")}</p></div><div class="profile-links"><a class="button ghost" href="${escapeAttr(SUPPORT_URL)}" target="_blank" rel="noopener noreferrer">${tx("Support", "Підтримка")}</a><a class="button ghost" href="${escapeAttr(PRIVACY_URL)}" target="_blank" rel="noopener noreferrer">${tx("Privacy policy", "Політика конфіденційності")}</a></div></section>`;
}

function garminProfilePanel() {
  const sessionUserId = loadRemoteSession()?.user?.id;
  const binding = UUID_PATTERN.test(sessionUserId || "")
    ? garminBindingForUser(sessionUserId)
    : null;
  const stateMatches = garminProfileState.userId === sessionUserId;
  const devices = stateMatches ? garminProfileState.devices : [];
  const selected = binding
    ? devices.filter(device => device.id.toLowerCase() === binding.deviceId.toLowerCase())
    : devices;
  let body;
  if (!activeAccount?.remote) {
    body = `<p class="muted">${tx("Garmin cloud watches are available after cloud sign-in.", "Годинники Garmin у хмарі доступні після входу в хмарний акаунт.")}</p>`;
  } else if (!stateMatches || garminProfileState.status === "idle" || garminProfileState.status === "loading") {
    body = `<p class="muted">${tx("Loading watch status…", "Завантажуємо статус годинника…")}</p>`;
  } else if (garminProfileState.status === "error") {
    body = `<p class="muted">${escapeHtml(garminProfileState.error)}</p><button class="button ghost full" data-action="refresh-garmin-profile">${tx("Retry", "Повторити")}</button>`;
  } else if (!selected.length) {
    body = `<p class="muted">${tx("No Garmin watch is paired with this account.", "До цього акаунта не прив’язано годинник Garmin.")}</p>`;
  } else {
    body = `<div class="garmin-device-list">${selected.map(garminProfileDeviceRow).join("")}</div>`;
  }
  return `<section class="panel garmin-profile-card"><div class="section-title"><div><span class="eyebrow">Garmin</span><h2>${tx("Your watch", "Твій годинник")}</h2><p>${tx("The browser cannot see live Bluetooth status. This shows the latest protected cloud contact from the watch.", "Браузер не бачить поточний стан Bluetooth. Тут показано останній захищений зв’язок годинника з хмарою.")}</p></div></div>${body}</section>`;
}

function garminProfileDeviceRow(device) {
  const lastSeen = device.lastSeenAt ? Date.parse(device.lastSeenAt) : NaN;
  const recent = Number.isFinite(lastSeen) && Date.now() - lastSeen <= 5 * 60 * 1000;
  const status = !Number.isFinite(lastSeen)
    ? tx("Waiting for the first watch sync", "Очікуємо на першу синхронізацію годинника")
    : recent
      ? tx("Watch synced a moment ago", "Годинник щойно синхронізувався")
      : `${tx("Last watch sync", "Остання синхронізація годинника")}: ${new Intl.DateTimeFormat(displayLocale(), { dateStyle: "medium", timeStyle: "short" }).format(new Date(lastSeen))}`;
  return `<div class="garmin-device-row"><span class="garmin-device-icon ${recent ? "connected" : ""}">${svg("watch")}</span><div><strong>${escapeHtml(device.displayName)}</strong><span>${escapeHtml(status)}</span></div><span class="pill">${tx("Paired", "Прив’язано")}</span></div>`;
}

function socialExactObject(value, requiredKeys, optionalKeys = []) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError("Social response object is invalid.");
  }
  const allowed = new Set([...requiredKeys, ...optionalKeys]);
  if (Object.keys(value).some(key => !allowed.has(key)) ||
      requiredKeys.some(key => !Object.hasOwn(value, key))) {
    throw new TypeError("Social response shape is invalid.");
  }
  return value;
}

function socialInteger(value, minimum, maximum) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new TypeError("Social response number is invalid.");
  }
  return value;
}

function socialNullableInteger(value, minimum, maximum) {
  return value === null ? null : socialInteger(value, minimum, maximum);
}

function socialSafeText(value, maximumCharacters, maximumBytes) {
  if (typeof value !== "string" || value.length === 0 ||
      value.startsWith(" ") || value.endsWith(" ") ||
      [...value].length > maximumCharacters ||
      new TextEncoder().encode(value).byteLength > maximumBytes ||
      /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u.test(value)) {
    throw new TypeError("Social response text is invalid.");
  }
  return value;
}

function socialProfileId(value) {
  if (typeof value !== "string" || !SOCIAL_PROFILE_ID_PATTERN.test(value)) {
    throw new TypeError("Social profile id is invalid.");
  }
  return value;
}

function socialFriendshipId(value) {
  if (typeof value !== "string" || !SOCIAL_FRIENDSHIP_ID_PATTERN.test(value)) {
    throw new TypeError("Friendship id is invalid.");
  }
  return value;
}

function socialTimestamp(value, nullable = false) {
  if (nullable && value === null) return null;
  const match = typeof value === "string" && value.length <= 40
    ? /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|([+-])(\d{2}):(\d{2}))$/.exec(value)
    : null;
  if (!match) throw new TypeError("Social timestamp is invalid.");
  const [, yearText, monthText, dayText, hourText, minuteText, secondText, , offsetHourText, offsetMinuteText] = match;
  const [year, month, day, hour, minute, second] = [
    yearText, monthText, dayText, hourText, minuteText, secondText
  ].map(Number);
  const calendar = new Date(Date.UTC(year, month - 1, day));
  const calendarIsExact = calendar.getUTCFullYear() === year && calendar.getUTCMonth() === month - 1 &&
    calendar.getUTCDate() === day;
  const offsetIsValid = offsetHourText === undefined ||
    (Number(offsetHourText) <= 23 && Number(offsetMinuteText) <= 59);
  if (!calendarIsExact || hour > 23 || minute > 59 || second > 59 || !offsetIsValid ||
      !Number.isFinite(Date.parse(value))) {
    throw new TypeError("Social timestamp is invalid.");
  }
  return value;
}

function socialWorkoutDay(value) {
  if (typeof value !== "string" || !SOCIAL_DAY_PATTERN.test(value) ||
      new Date(`${value}T00:00:00.000Z`).toISOString().slice(0, 10) !== value) {
    throw new TypeError("Social workout day is invalid.");
  }
  return value;
}

function parseSocialPrivacy(value) {
  const object = socialExactObject(value, [
    "allowRequests", "shareProgress", "shareRecentWorkouts", "shareRecords"
  ]);
  for (const key of Object.keys(object)) {
    if (typeof object[key] !== "boolean") throw new TypeError("Social privacy value is invalid.");
  }
  return { ...object };
}

function parseSocialDashboard(value) {
  const root = socialExactObject(value, [
    "version", "self", "friends", "incoming", "outgoing", "blocked", "pendingWorkoutInviteCount"
  ]);
  if (root.version !== 1 || !Array.isArray(root.friends) || root.friends.length > 200 ||
      !Array.isArray(root.incoming) || root.incoming.length > 100 ||
      !Array.isArray(root.outgoing) || root.outgoing.length > 25 ||
      !Array.isArray(root.blocked) || root.blocked.length > 200) {
    throw new TypeError("Social dashboard is invalid.");
  }
  const self = socialExactObject(root.self, [
    "profileId", "friendCode", "displayName", "xp", "level", "workouts", "statsAvailable",
    "progressUpdatedAt", "privacy", "settingsRevision"
  ]);
  const parsedSelf = {
    profileId: socialProfileId(self.profileId),
    friendCode: socialProfileId(self.friendCode),
    displayName: socialSafeText(self.displayName, 40, 160),
    xp: socialNullableInteger(self.xp, 0, 2147483647),
    level: socialNullableInteger(self.level, 1, 1000000),
    workouts: socialNullableInteger(self.workouts, 0, 5000),
    statsAvailable: self.statsAvailable,
    progressUpdatedAt: socialTimestamp(self.progressUpdatedAt, true),
    privacy: parseSocialPrivacy(self.privacy),
    settingsRevision: socialInteger(self.settingsRevision, 1, 2147483647)
  };
  if (typeof parsedSelf.statsAvailable !== "boolean" || parsedSelf.friendCode !== parsedSelf.profileId ||
      (parsedSelf.statsAvailable
        ? [parsedSelf.xp, parsedSelf.level, parsedSelf.workouts, parsedSelf.progressUpdatedAt].some(item => item === null)
        : [parsedSelf.xp, parsedSelf.level, parsedSelf.workouts, parsedSelf.progressUpdatedAt].some(item => item !== null))) {
    throw new TypeError("Social self progress is inconsistent.");
  }
  const friends = root.friends.map(value => {
    const row = socialExactObject(value, [
      "friendshipId", "profileId", "displayName", "xp", "level", "workouts", "progressShared",
      "statsAvailable", "progressUpdatedAt", "friendshipRevision", "status"
    ]);
    const parsed = {
      friendshipId: socialFriendshipId(row.friendshipId),
      profileId: socialProfileId(row.profileId),
      displayName: socialSafeText(row.displayName, 40, 160),
      xp: socialNullableInteger(row.xp, 0, 2147483647),
      level: socialNullableInteger(row.level, 1, 1000000),
      workouts: socialNullableInteger(row.workouts, 0, 5000),
      progressShared: row.progressShared,
      statsAvailable: row.statsAvailable,
      progressUpdatedAt: socialTimestamp(row.progressUpdatedAt, true),
      friendshipRevision: socialInteger(row.friendshipRevision, 1, 2147483647),
      status: row.status
    };
    const progressIsInconsistent = !parsed.progressShared || !parsed.statsAvailable
      ? [parsed.xp, parsed.level, parsed.workouts, parsed.progressUpdatedAt].some(item => item !== null)
      : [parsed.xp, parsed.level, parsed.workouts, parsed.progressUpdatedAt].some(item => item === null);
    if (typeof parsed.progressShared !== "boolean" || typeof parsed.statsAvailable !== "boolean" ||
        parsed.status !== "accepted" || progressIsInconsistent) {
      throw new TypeError("Friend progress is inconsistent.");
    }
    return parsed;
  });
  const parseRequest = value => {
    const row = socialExactObject(value, [
      "friendshipId", "profileId", "displayName", "requestedAt", "friendshipRevision", "status"
    ]);
    if (row.status !== "pending") throw new TypeError("Friend request status is invalid.");
    return {
      friendshipId: socialFriendshipId(row.friendshipId),
      profileId: socialProfileId(row.profileId),
      displayName: socialSafeText(row.displayName, 40, 160),
      requestedAt: socialTimestamp(row.requestedAt),
      friendshipRevision: socialInteger(row.friendshipRevision, 1, 2147483647),
      status: row.status
    };
  };
  const blocked = root.blocked.map(value => {
    const row = socialExactObject(value, ["profileId", "displayName", "blockedAt"]);
    return {
      profileId: socialProfileId(row.profileId),
      displayName: socialSafeText(row.displayName, 40, 160),
      blockedAt: socialTimestamp(row.blockedAt)
    };
  });
  const incoming = root.incoming.map(parseRequest);
  const outgoing = root.outgoing.map(parseRequest);
  const unique = values => new Set(values).size === values.length;
  const friendIds = friends.map(row => row.friendshipId);
  const incomingIds = incoming.map(row => row.friendshipId);
  const outgoingIds = outgoing.map(row => row.friendshipId);
  const friendProfiles = friends.map(row => row.profileId);
  const incomingProfiles = incoming.map(row => row.profileId);
  const outgoingProfiles = outgoing.map(row => row.profileId);
  const blockedProfiles = blocked.map(row => row.profileId);
  const relatedIds = [...friendIds, ...incomingIds, ...outgoingIds];
  const relatedProfiles = [...friendProfiles, ...incomingProfiles, ...outgoingProfiles];
  if (![friendIds, incomingIds, outgoingIds, friendProfiles, incomingProfiles, outgoingProfiles, blockedProfiles]
      .every(unique) || !unique(relatedIds) || !unique(relatedProfiles) ||
      relatedProfiles.includes(parsedSelf.profileId) || blockedProfiles.includes(parsedSelf.profileId) ||
      blockedProfiles.some(profileId => relatedProfiles.includes(profileId))) {
    throw new TypeError("Social dashboard relationships are inconsistent.");
  }
  return {
    version: 1,
    self: parsedSelf,
    friends,
    incoming,
    outgoing,
    blocked,
    pendingWorkoutInviteCount: socialInteger(root.pendingWorkoutInviteCount, 0, 25)
  };
}

function parseSocialExerciseIdentity(value) {
  const row = socialExactObject(value, ["catalogKey", "name"]);
  if (row.catalogKey !== null && (typeof row.catalogKey !== "string" || !/^[a-z0-9_]{1,64}$/.test(row.catalogKey))) {
    throw new TypeError("Social exercise key is invalid.");
  }
  return { catalogKey: row.catalogKey, name: socialSafeText(row.name, 120, 480) };
}

function socialExerciseIdentityKey(exercise) {
  if (exercise.catalogKey) return `key:${exercise.catalogKey}`;
  const portableNameKey = window.GymSharedWorkout?.portableNameKey;
  if (typeof portableNameKey !== "function") {
    throw new TypeError("Friend exercise identity normalizer is unavailable.");
  }
  return `name:${portableNameKey(exercise.name)}`;
}

function parseSocialFriendDetails(value) {
  const root = socialExactObject(value, [
    "version", "friend", "recentWorkouts", "exerciseRecords", "sharing", "activityUpdatedAt", "integrity"
  ]);
  if (root.version !== 1 || root.integrity !== "self_reported" ||
      !Array.isArray(root.recentWorkouts) || root.recentWorkouts.length > 5 ||
      !Array.isArray(root.exerciseRecords) || root.exerciseRecords.length > 100) {
    throw new TypeError("Friend details are invalid.");
  }
  const sharing = socialExactObject(root.sharing, ["progress", "recentWorkouts", "records"]);
  if (Object.values(sharing).some(item => typeof item !== "boolean")) {
    throw new TypeError("Friend sharing flags are invalid.");
  }
  const friend = socialExactObject(root.friend, [
    "profileId", "displayName", "xp", "level", "workouts", "progressShared",
    "statsAvailable", "progressUpdatedAt"
  ]);
  const parsedFriend = {
    profileId: socialProfileId(friend.profileId),
    displayName: socialSafeText(friend.displayName, 40, 160),
    xp: socialNullableInteger(friend.xp, 0, 2147483647),
    level: socialNullableInteger(friend.level, 1, 1000000),
    workouts: socialNullableInteger(friend.workouts, 0, 5000),
    progressShared: friend.progressShared,
    statsAvailable: friend.statsAvailable,
    progressUpdatedAt: socialTimestamp(friend.progressUpdatedAt, true)
  };
  const progressFields = [
    parsedFriend.xp, parsedFriend.level, parsedFriend.workouts, parsedFriend.progressUpdatedAt
  ];
  if (typeof parsedFriend.progressShared !== "boolean" || typeof parsedFriend.statsAvailable !== "boolean" ||
      parsedFriend.progressShared !== sharing.progress ||
      (parsedFriend.statsAvailable
        ? !parsedFriend.progressShared || progressFields.some(item => item === null)
        : progressFields.some(item => item !== null))) {
    throw new TypeError("Friend detail progress is inconsistent.");
  }
  const activityUpdatedAt = socialTimestamp(root.activityUpdatedAt, true);
  const recentWorkouts = root.recentWorkouts.map(value => {
    const row = socialExactObject(value, ["workoutDay", "exerciseCount", "setCount", "exercises"]);
    if (!Array.isArray(row.exercises) || row.exercises.length > 20) throw new TypeError("Friend workout exercises are invalid.");
    const exerciseCount = socialInteger(row.exerciseCount, 1, 100);
    const setCount = socialInteger(row.setCount, 1, 10000);
    const exercises = row.exercises.map(parseSocialExerciseIdentity);
    const exerciseIdentities = exercises.map(socialExerciseIdentityKey);
    if (exercises.length !== Math.min(exerciseCount, 20) ||
        new Set(exerciseIdentities).size !== exerciseIdentities.length) {
      throw new TypeError("Friend workout exercise summary is inconsistent.");
    }
    return {
      workoutDay: socialWorkoutDay(row.workoutDay),
      exerciseCount,
      setCount,
      exercises
    };
  });
  const exerciseRecords = root.exerciseRecords.map(value => {
    const row = socialExactObject(value, [
      "catalogKey", "name", "bestWeightKg", "bestReps", "workoutCount", "lastWorkoutDay"
    ]);
    const identity = parseSocialExerciseIdentity({ catalogKey: row.catalogKey, name: row.name });
    if (typeof row.bestWeightKg !== "number" || !Number.isFinite(row.bestWeightKg) ||
        row.bestWeightKg < 0 || row.bestWeightKg > 1000000) {
      throw new TypeError("Friend record weight is invalid.");
    }
    return {
      ...identity,
      bestWeightKg: row.bestWeightKg,
      bestReps: socialInteger(row.bestReps, 1, 10000),
      workoutCount: socialInteger(row.workoutCount, 1, 5000),
      lastWorkoutDay: socialWorkoutDay(row.lastWorkoutDay)
    };
  });
  const recordIdentities = exerciseRecords.map(socialExerciseIdentityKey);
  if (new Set(recordIdentities).size !== recordIdentities.length) {
    throw new TypeError("Friend exercise records are duplicated.");
  }
  if ((!sharing.recentWorkouts && recentWorkouts.length) || (!sharing.records && exerciseRecords.length) ||
      (activityUpdatedAt === null && (recentWorkouts.length || exerciseRecords.length)) ||
      (activityUpdatedAt !== null && !sharing.recentWorkouts && !sharing.records)) {
    throw new TypeError("Hidden friend activity was returned.");
  }
  return {
    version: 1,
    friend: parsedFriend,
    recentWorkouts,
    exerciseRecords,
    sharing: { ...sharing },
    activityUpdatedAt,
    integrity: root.integrity
  };
}

function normalizeSocialWorkoutPlan(value) {
  const root = socialExactObject(value, ["version", "exercises"]);
  if (root.version !== 1 || !Array.isArray(root.exercises) || root.exercises.length < 1 || root.exercises.length > 20) {
    throw new TypeError("Workout invitation is invalid.");
  }
  let totalSets = 0;
  const portableNameKey = window.GymSharedWorkout?.portableNameKey;
  if (typeof portableNameKey !== "function") {
    throw new TypeError("Workout invitation identity normalizer is unavailable.");
  }
  const nameKeys = new Set();
  const catalogKeys = new Set();
  const normalizedExercises = [];
  for (const exercise of root.exercises) {
    const row = socialExactObject(exercise, ["name", "sets"], ["catalogKey"]);
    socialSafeText(row.name, 120, 480);
    if (row.catalogKey !== undefined && (typeof row.catalogKey !== "string" || !/^[a-z0-9_]{1,64}$/.test(row.catalogKey))) {
      throw new TypeError("Workout invitation exercise key is invalid.");
    }
    if (!Array.isArray(row.sets) || row.sets.length < 1 || row.sets.length > 12) {
      throw new TypeError("Workout invitation sets are invalid.");
    }
    const nameKey = portableNameKey(row.name);
    if (!nameKey || nameKeys.has(nameKey) ||
        (row.catalogKey !== undefined && catalogKeys.has(row.catalogKey))) {
      throw new TypeError("Workout invitation exercise identity is duplicated.");
    }
    nameKeys.add(nameKey);
    if (row.catalogKey !== undefined) catalogKeys.add(row.catalogKey);
    totalSets += row.sets.length;
    const normalizedSets = [];
    for (const set of row.sets) {
      socialExactObject(set, ["weight", "reps"]);
      if (typeof set.weight !== "number" || !Number.isFinite(set.weight) || set.weight < 0 || set.weight > 1000000 ||
          !Number.isInteger(set.reps) || set.reps < 1 || set.reps > 10000) {
        throw new TypeError("Workout invitation set is invalid.");
      }
      normalizedSets.push(Object.freeze({ weight: set.weight, reps: set.reps }));
    }
    normalizedExercises.push(Object.freeze({
      ...(row.catalogKey !== undefined ? { catalogKey: row.catalogKey } : {}),
      name: row.name,
      sets: Object.freeze(normalizedSets)
    }));
  }
  if (totalSets > 120 || new TextEncoder().encode(JSON.stringify(root)).byteLength > 32 * 1024) {
    throw new TypeError("Workout invitation is oversized.");
  }
  return Object.freeze({
    version: 1,
    exercises: Object.freeze(normalizedExercises)
  });
}

function parseSocialWorkoutInbox(value) {
  const root = socialExactObject(value, ["version", "pendingIncomingCount", "incoming", "outgoing"]);
  if (root.version !== 1 || !Array.isArray(root.incoming) || root.incoming.length > 25 ||
      !Array.isArray(root.outgoing) || root.outgoing.length > 25) {
    throw new TypeError("Workout invitation inbox is invalid.");
  }
  const allowedStatuses = new Set(["pending", "accepted", "declined", "cancelled", "expired"]);
  const parseSummary = value => {
    const row = socialExactObject(value, ["exerciseCount", "setCount", "exerciseNames"]);
    if (!Array.isArray(row.exerciseNames) || row.exerciseNames.length > 20) {
      throw new TypeError("Workout invitation summary is invalid.");
    }
    return {
      exerciseCount: socialInteger(row.exerciseCount, 1, 20),
      setCount: socialInteger(row.setCount, 1, 120),
      exerciseNames: row.exerciseNames.map(name => socialSafeText(name, 120, 480))
    };
  };
  const parseInvite = (value, incoming) => {
    const required = [
      "inviteId", "profileId", "displayName", "status", "inviteRevision", "createdAt", "expiresAt",
      "respondedAt", "summary", ...(incoming ? ["workout"] : [])
    ];
    const row = socialExactObject(value, required);
    if (typeof row.inviteId !== "string" || !SOCIAL_WORKOUT_INVITE_ID_PATTERN.test(row.inviteId) ||
        !allowedStatuses.has(row.status) || (incoming && !["pending", "accepted"].includes(row.status))) {
      throw new TypeError("Workout invitation row is invalid.");
    }
    const createdAt = socialTimestamp(row.createdAt);
    const expiresAt = socialTimestamp(row.expiresAt);
    const respondedAt = socialTimestamp(row.respondedAt, true);
    const summary = parseSummary(row.summary);
    const workout = incoming ? normalizeSocialWorkoutPlan(row.workout) : null;
    if ((row.status === "pending") !== (respondedAt === null) ||
        Date.parse(expiresAt) <= Date.parse(createdAt) ||
        (workout && (summary.exerciseCount !== workout.exercises.length ||
          summary.setCount !== workout.exercises.reduce((count, exercise) => count + exercise.sets.length, 0) ||
          summary.exerciseNames.some((name, index) => name !== workout.exercises[index].name)))) {
      throw new TypeError("Workout invitation metadata is inconsistent.");
    }
    return {
      inviteId: row.inviteId,
      profileId: socialProfileId(row.profileId),
      displayName: socialSafeText(row.displayName, 40, 160),
      status: row.status,
      inviteRevision: socialInteger(row.inviteRevision, 1, 2147483647),
      createdAt,
      expiresAt,
      respondedAt,
      summary,
      ...(incoming ? { workout } : {})
    };
  };
  const incoming = root.incoming.map(row => parseInvite(row, true));
  const outgoing = root.outgoing.map(row => parseInvite(row, false));
  const pendingIncomingCount = socialInteger(root.pendingIncomingCount, 0, 25);
  if (pendingIncomingCount !== incoming.filter(row => row.status === "pending").length) {
    throw new TypeError("Workout invitation count is inconsistent.");
  }
  const incomingIds = incoming.map(row => row.inviteId);
  const outgoingIds = outgoing.map(row => row.inviteId);
  if (new Set(incomingIds).size !== incomingIds.length ||
      new Set(outgoingIds).size !== outgoingIds.length ||
      incomingIds.some(inviteId => outgoingIds.includes(inviteId))) {
    throw new TypeError("Workout invitation identities are inconsistent.");
  }
  return { version: 1, pendingIncomingCount, incoming, outgoing };
}

const SOCIAL_RPC_NAMES = new Set([
  "social_dashboard", "social_friend_details", "social_send_friend_request",
  "social_respond_friend_request", "social_cancel_friend_request", "social_remove_friend",
  "social_block_profile", "social_unblock_profile", "social_update_privacy",
  "social_workout_inbox", "social_send_workout_invite", "social_respond_workout_invite",
  "social_cancel_workout_invite"
]);

const LIVE_GATEWAY_ACTIONS = new Set([
  "live_inbox", "live_send_invite", "live_respond_invite", "live_start",
  "live_snapshot", "live_apply", "live_finish", "live_leave", "live_cancel"
]);

function liveSessionIdentity(session = loadRemoteSession()) {
  const accessToken = session?.access_token;
  const userId = session?.user?.id;
  if (!UUID_PATTERN.test(userId || "") || typeof accessToken !== "string" || accessToken.length > 8192) {
    return null;
  }
  try {
    const parts = accessToken.split(".");
    if (parts.length !== 3 || !/^[A-Za-z0-9_-]+$/.test(parts[1])) return null;
    const base64 = parts[1].replaceAll("-", "+").replaceAll("_", "/") +
      "=".repeat((4 - parts[1].length % 4) % 4);
    const bytes = Uint8Array.from(atob(base64), character => character.charCodeAt(0));
    if (bytes.byteLength > 8192) return null;
    const payload = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    return UUID_PATTERN.test(payload?.session_id || "")
      ? { userId, sessionId: payload.session_id.toLowerCase() }
      : null;
  } catch {
    return null;
  }
}

function liveWorkoutBindingKey(userId) {
  return UUID_PATTERN.test(userId || "") ? `${LIVE_WORKOUT_BINDING_PREFIX}${userId}` : null;
}

function loadLiveWorkoutBinding() {
  const identity = liveSessionIdentity();
  const key = liveWorkoutBindingKey(identity?.userId);
  if (!identity || !key || !window.GymLiveWorkoutState?.decode) return null;
  try {
    const raw = localStorage.getItem(key);
    return raw ? window.GymLiveWorkoutState.decode(raw, identity.userId, identity.sessionId) : null;
  } catch {
    try { localStorage.removeItem(key); } catch { /* fail closed in memory */ }
    return null;
  }
}

function persistLiveWorkoutBinding(value) {
  const identity = liveSessionIdentity();
  const key = liveWorkoutBindingKey(identity?.userId);
  if (!identity || !key || !window.GymLiveWorkoutState?.encode) return false;
  try {
    const normalized = window.GymLiveWorkoutState.normalize(value, identity.userId, identity.sessionId);
    const raw = window.GymLiveWorkoutState.encode(normalized);
    localStorage.setItem(key, raw);
    if (localStorage.getItem(key) !== raw) return false;
    liveWorkoutBinding = normalized;
    return true;
  } catch {
    return false;
  }
}

function clearLiveWorkoutBinding({ erase = true } = {}) {
  const identity = liveSessionIdentity();
  const key = liveWorkoutBindingKey(identity?.userId || liveWorkoutBinding?.userId);
  if (erase && key) {
    try { localStorage.removeItem(key); } catch { /* memory is still cleared */ }
  }
  liveWorkoutBinding = null;
}

function restoreLiveWorkoutBindingAfterFailedStart(identity, expectedRaw, previousRaw) {
  const key = liveWorkoutBindingKey(identity?.userId);
  if (!key || typeof expectedRaw !== "string" ||
      (previousRaw !== null && typeof previousRaw !== "string")) return false;
  try {
    if (localStorage.getItem(key) !== expectedRaw) return false;
    if (previousRaw === null) localStorage.removeItem(key);
    else localStorage.setItem(key, previousRaw);
    if (localStorage.getItem(key) !== previousRaw) return false;
    liveWorkoutBinding = previousRaw === null
      ? null
      : window.GymLiveWorkoutState.decode(previousRaw, identity.userId, identity.sessionId);
    return true;
  } catch {
    liveWorkoutBinding = null;
    return false;
  }
}

function prepareLiveWorkoutOperationBatch(requests, { allowFinished = false } = {}) {
  if (!Array.isArray(requests) || requests.length < 1) return { required: false, token: null };
  const identity = liveSessionIdentity();
  const binding = liveWorkoutBinding;
  if (!binding) return { required: false, token: null };
  if (!identity || identity.userId !== binding.userId || identity.sessionId !== binding.sessionId ||
      (!allowFinished && (!activeWorkout || binding.localWorkoutId !== activeWorkout.id))) {
    return { required: true, token: null };
  }
  const key = liveWorkoutBindingKey(identity.userId);
  if (!key) return { required: true, token: null };
  try {
    const previousRaw = localStorage.getItem(key);
    const currentRaw = window.GymLiveWorkoutState.encode(binding);
    if (previousRaw !== currentRaw) return { required: true, token: null };
    let next = binding;
    const pendingSuffix = binding.pendingOperations.slice(-requests.length);
    const alreadyPrepared = pendingSuffix.length === requests.length && requests.every((requested, index) => {
      const pending = pendingSuffix[index];
      return pending.kind === requested.kind && pending.serverSetId === requested.serverSetId &&
        pending.weight === (requested.kind === "complete_set" ? requested.weight : null) &&
        pending.reps === (requested.kind === "complete_set" ? requested.reps : null);
    });
    if (!alreadyPrepared) {
      for (const requested of requests) {
        next = window.GymLiveWorkoutState.enqueue(next, {
          ...requested,
          clientOperationId: newUuidV4()
        });
      }
    }
    const expectedRaw = window.GymLiveWorkoutState.encode(next);
    if (!persistLiveWorkoutBinding(next) || localStorage.getItem(key) !== expectedRaw) {
      restoreLiveWorkoutBindingAfterFailedStart(identity, expectedRaw, previousRaw);
      return { required: true, token: null };
    }
    return {
      required: true,
      token: Object.freeze({ identity, previousRaw, expectedRaw })
    };
  } catch {
    return { required: true, token: null };
  }
}

function prepareLiveSetOperationBatch(requests) {
  if (!liveWorkoutBinding) return { required: false, token: null };
  try {
    const wireRequests = requests.map(requested => {
      const serverSetId = window.GymLiveWorkoutState.localToServer(
        liveWorkoutBinding,
        requested.localSetId
      );
      if (!serverSetId) throw new TypeError("Live set mapping is missing.");
      return {
        kind: requested.kind,
        serverSetId,
        weight: requested.kind === "complete_set" ? requested.weight : null,
        reps: requested.kind === "complete_set" ? requested.reps : null,
        localMutationAt: requested.localMutationAt
      };
    });
    return prepareLiveWorkoutOperationBatch(wireRequests);
  } catch {
    return { required: true, token: null };
  }
}

function rollbackPreparedLiveWorkoutOperations(prepared) {
  if (!prepared?.token) return !prepared?.required;
  return restoreLiveWorkoutBindingAfterFailedStart(
    prepared.token.identity,
    prepared.token.expectedRaw,
    prepared.token.previousRaw
  );
}

function commitPreparedLiveWorkoutOperations(prepared) {
  if (!prepared?.required) return true;
  if (!prepared.token) return false;
  void drainLiveWorkoutOperations();
  return true;
}

function stopLiveWorkoutRealtime() {
  liveRealtimeGeneration += 1;
  clearTimeout(liveRealtimeRefreshTimer);
  liveRealtimeRefreshTimer = null;
  const previous = liveRealtime;
  liveRealtime = {
    status: "idle", source: null, client: null, channel: null, accessToken: null
  };
  if (previous.client && previous.channel) {
    void previous.client.removeChannel(previous.channel)
      .catch(() => {})
      .finally(() => previous.client.disconnect().catch(() => {}));
  } else if (previous.client) {
    void previous.client.disconnect().catch(() => {});
  }
}

function handleLiveWorkoutRealtimeMessage(message, generation, expectedEpoch, identity) {
  if (generation !== liveRealtimeGeneration ||
      !liveIdentityIsCurrent(expectedEpoch, identity)) return false;
  let hint;
  try {
    hint = window.GymLiveWorkout.realtimeEvent(message?.payload);
  } catch {
    return false;
  }
  const visibleRoomIds = new Set([
    liveWorkoutBinding?.roomId,
    liveWorkoutState.snapshot?.room?.roomId,
    ...(liveWorkoutState.inbox?.rooms || []).map(room => room.roomId),
    ...(liveWorkoutState.inbox?.invitations || []).map(invite => invite.roomId)
  ].filter(Boolean));
  if (hint.kind === "invite" || visibleRoomIds.has(hint.roomId)) {
    clearTimeout(liveRealtimeRefreshTimer);
    liveRealtimeRefreshTimer = setTimeout(() => {
      if (generation === liveRealtimeGeneration &&
          liveIdentityIsCurrent(expectedEpoch, identity) &&
          !liveWorkoutMutationInProgress) {
        void refreshLiveWorkoutData(true, visibleRoomIds.has(hint.roomId) ? hint.roomId : undefined);
      }
    }, 80);
  }
  return true;
}

async function ensureLiveWorkoutRealtime(session = loadRemoteSession()) {
  const identity = liveSessionIdentity(session);
  const RealtimeClient = window.GymSupabaseRealtime?.RealtimeClient;
  const config = supabaseConfig();
  if (!identity || activeAccount?.remote !== "supabase" ||
      activeAccount.userId !== identity.userId || typeof RealtimeClient !== "function" ||
      !config.url || !config.anonKey || typeof session?.access_token !== "string") {
    stopLiveWorkoutRealtime();
    return false;
  }
  const source = `${identity.userId}:${identity.sessionId}`;
  if (liveRealtime.client && liveRealtime.source === source) {
    try {
      if (liveRealtime.accessToken !== session.access_token) {
        await liveRealtime.client.setAuth(session.access_token);
        if (liveRealtime.source !== source) return false;
        liveRealtime.accessToken = session.access_token;
      }
      return liveRealtime.status === "subscribed";
    } catch {
      liveRealtime.status = "fallback";
      scheduleLiveWorkoutPoll();
      return false;
    }
  }

  stopLiveWorkoutRealtime();
  const generation = liveRealtimeGeneration;
  const expectedEpoch = accountEpoch;
  let client;
  try {
    client = new RealtimeClient(`${config.url}/realtime/v1`, {
      params: { apikey: config.anonKey },
      timeout: 10000,
      heartbeatIntervalMs: 25000,
      worker: false
    });
    liveRealtime = {
      status: "connecting", source, client, channel: null, accessToken: session.access_token
    };
    await client.setAuth(session.access_token);
    if (generation !== liveRealtimeGeneration ||
        !liveIdentityIsCurrent(expectedEpoch, identity)) {
      void client.disconnect().catch(() => {});
      return false;
    }
    const channel = client.channel(`gymapp:user:${identity.userId}`, {
      config: { private: true, broadcast: { ack: false, self: false } }
    });
    liveRealtime.channel = channel;
    channel.on("broadcast", { event: "gymapp_live_changed" }, message => {
      handleLiveWorkoutRealtimeMessage(message, generation, expectedEpoch, identity);
    });
    channel.subscribe(status => {
      if (generation !== liveRealtimeGeneration ||
          !liveIdentityIsCurrent(expectedEpoch, identity)) return;
      liveRealtime.status = status === "SUBSCRIBED"
        ? "subscribed"
        : status === "CLOSED" ? "closed" : status === "CHANNEL_ERROR" || status === "TIMED_OUT"
          ? "fallback" : "connecting";
      scheduleLiveWorkoutPoll();
      render();
    });
    return true;
  } catch {
    if (generation === liveRealtimeGeneration) {
      liveRealtime.status = "fallback";
      scheduleLiveWorkoutPoll();
    }
    if (client) void client.disconnect().catch(() => {});
    return false;
  }
}

function resetLiveWorkoutContext({ eraseBinding = false } = {}) {
  liveWorkoutContextGeneration += 1;
  liveWorkoutRequestId += 1;
  liveWorkoutRequestController?.abort();
  liveWorkoutRequestController = null;
  liveWorkoutState = { status: "idle", source: null, inbox: null, snapshot: null, error: "" };
  liveWorkoutMutationInProgress = false;
  liveWorkoutInviteRequests.clear();
  liveWorkoutActionRequests.clear();
  clearTimeout(liveWorkoutPollTimer);
  liveWorkoutPollTimer = null;
  stopLiveWorkoutRealtime();
  clearLiveWorkoutBinding({ erase: eraseBinding });
}

function parseLiveGatewayEnvelope(value, parser) {
  const row = socialExactObject(value, ["version", "result"]);
  if (row.version !== 1 || typeof parser !== "function") {
    throw new TypeError("Live workout gateway response is invalid.");
  }
  return parser(row.result);
}

async function liveGateway(action, payload, parser, options = {}) {
  if (!LIVE_GATEWAY_ACTIONS.has(action) || !payload || typeof payload !== "object" ||
      Array.isArray(payload)) throw new TypeError("Live workout gateway action is invalid.");
  const session = options.session || loadRemoteSession();
  const value = await supabaseRequest("/functions/v1/social-live-gateway", {
    method: "POST",
    session,
    signal: options.signal,
    timeoutMs: options.timeoutMs || 12000,
    maxResponseBytes: MAX_LIVE_RESPONSE_BYTES,
    body: JSON.stringify({ version: 1, action, payload })
  });
  return parseLiveGatewayEnvelope(value, parser);
}

function liveSourceKey() {
  const identity = liveSessionIdentity();
  return identity ? `cloud:${identity.userId}:${identity.sessionId}:${accountEpoch}` : `local:${accountEpoch}`;
}

function liveIdentityIsCurrent(expectedEpoch, identity) {
  const current = liveSessionIdentity();
  return expectedEpoch === accountEpoch && current?.userId === identity?.userId &&
    current?.sessionId === identity?.sessionId && activeAccount?.userId === identity?.userId;
}

function liveOperationContextIsCurrent(
  expectedGeneration,
  expectedEpoch,
  identity,
  expectedRoomId,
  expectedLocalWorkoutId
) {
  return expectedGeneration === liveWorkoutContextGeneration &&
    liveIdentityIsCurrent(expectedEpoch, identity) &&
    liveWorkoutBinding?.userId === identity?.userId &&
    liveWorkoutBinding?.sessionId === identity?.sessionId &&
    liveWorkoutBinding?.roomId === expectedRoomId &&
    liveWorkoutBinding?.localWorkoutId === expectedLocalWorkoutId;
}

function prepareLiveRequest(map, keyParts) {
  const key = `${liveSourceKey()}:${canonicalValueFingerprint(keyParts)}`;
  const existing = map.get(key);
  if (existing) return existing;
  if (map.size >= MAX_PENDING_LIVE_REQUESTS) {
    throw new Error("Too many live workout outcomes are unresolved.");
  }
  const request = { key, requestId: newUuidV4() };
  map.set(key, request);
  return request;
}

function clearLiveRequest(map, request) {
  if (request && map.get(request.key)?.requestId === request.requestId) map.delete(request.key);
}

function socialSourceKey() {
  const session = loadRemoteSession();
  const cloudMode = Boolean(remoteAuthEnabled() && activeAccount?.remote && session?.user?.id);
  const identity = cloudMode ? session.user.id : activeAccount?.id || "anonymous";
  return `${cloudMode ? "cloud" : "local"}:${identity}:${accountEpoch}`;
}

function socialIdentityIsCurrent(expectedEpoch, expectedUserId) {
  return expectedEpoch === accountEpoch && activeAccount?.userId === expectedUserId &&
    loadRemoteSession()?.user?.id === expectedUserId;
}

function socialRpc(name, body = {}, options = {}) {
  if (!SOCIAL_RPC_NAMES.has(name)) throw new TypeError("Social RPC is not allowlisted.");
  const session = options.session || loadRemoteSession();
  return supabaseRequest(`/rest/v1/rpc/${name}`, {
    method: "POST",
    session,
    signal: options.signal,
    timeoutMs: options.timeoutMs || 12000,
    maxResponseBytes: MAX_SOCIAL_RESPONSE_BYTES,
    body: JSON.stringify(body)
  });
}

async function refreshSocialData(force = false) {
  const session = loadRemoteSession();
  const cloudMode = Boolean(remoteAuthEnabled() && activeAccount?.remote && session?.user?.id);
  const source = socialSourceKey();
  if (socialState.status === "loading" && !force && socialState.source === source) return;
  if (!force && socialState.status === "loaded" && socialState.source === source) return;
  const openDetailProfileId = modal?.type === "friend-detail" &&
    SOCIAL_PROFILE_ID_PATTERN.test(modal.profileId || "")
    ? modal.profileId
    : null;
  if (openDetailProfileId) {
    socialDetailRequestId += 1;
    socialDetailRequestController?.abort();
    socialDetailRequestController = null;
    socialDetailState = {
      status: "loading",
      source: `${source}:${openDetailProfileId}`,
      profileId: openDetailProfileId,
      value: null,
      error: ""
    };
  }
  if (socialState.status === "loading") socialRequestController?.abort();
  if (!cloudMode) {
    socialRequestId += 1;
    socialRequestController?.abort();
    socialRequestController = null;
    socialState = { status: "loaded", source, dashboard: null, inbox: null, error: "" };
    return render();
  }
  const requestId = ++socialRequestId;
  const requestEpoch = accountEpoch;
  const expectedUserId = session.user.id;
  socialRequestController = new AbortController();
  socialState = { ...socialState, status: "loading", source, error: "" };
  render();
  let workoutSyncError = null;
  try {
    if (remoteStateSync.userId === expectedUserId) {
      try {
        await flushPendingRemoteSave();
      } catch (error) {
        if (isTerminalRemoteAuthError(error)) throw error;
        workoutSyncError = error;
        setCloudSyncUi("error", friendlySyncError(error), expectedUserId);
      }
    }
    const [dashboardValue, inboxValue] = await Promise.all([
      socialRpc("social_dashboard", {}, { session, signal: socialRequestController.signal }),
      socialRpc("social_workout_inbox", {}, { session, signal: socialRequestController.signal })
    ]);
    if (requestId !== socialRequestId || source !== socialSourceKey() ||
        !socialIdentityIsCurrent(requestEpoch, expectedUserId)) return;
    socialState = {
      status: "loaded",
      source,
      dashboard: parseSocialDashboard(dashboardValue),
      inbox: parseSocialWorkoutInbox(inboxValue),
      error: workoutSyncError ? friendlySyncError(workoutSyncError) : ""
    };
    socialLastLoadedAt = Date.now();
    if (openDetailProfileId &&
        socialState.dashboard.friends.some(friend => friend.profileId === openDetailProfileId)) {
      await openFriendDetails(openDetailProfileId);
    }
  } catch (error) {
    if (requestId !== socialRequestId || source !== socialSourceKey() ||
        !socialIdentityIsCurrent(requestEpoch, expectedUserId)) return;
    if (isTerminalRemoteAuthError(error) || error?.status === 403) {
      if (error?.status === 403) {
        error.terminalAuth = true;
        error.status = 401;
      }
      if (transitionToReauthentication(error)) return;
    }
    socialState = {
      status: "error",
      source,
      dashboard: null,
      inbox: null,
      error: tx("Friends could not be loaded safely. Try again.", "Не вдалося безпечно завантажити друзів. Спробуй ще раз.")
    };
    if (openDetailProfileId) {
      socialDetailState = {
        status: "error",
        source: `${source}:${openDetailProfileId}`,
        profileId: openDetailProfileId,
        value: null,
        error: tx("This friend profile could not be refreshed safely.", "Не вдалося безпечно оновити профіль друга.")
      };
    }
  } finally {
    if (requestId === socialRequestId) socialRequestController = null;
  }
  render();
}

function currentLiveRoomId() {
  const modalRoomId = modal?.type === "live-workout-room" ? modal.roomId : null;
  const candidates = [modalRoomId, liveWorkoutBinding?.roomId, liveWorkoutState.snapshot?.room?.roomId];
  return candidates.find(value => window.GymLiveWorkout?.patterns?.ROOM_ID?.test(value || "")) || null;
}

function scheduleLiveWorkoutPoll() {
  clearTimeout(liveWorkoutPollTimer);
  liveWorkoutPollTimer = null;
  if (!liveSessionIdentity() || document.visibilityState === "hidden") return;
  const status = liveWorkoutState.snapshot?.room?.status ||
    liveWorkoutState.inbox?.rooms?.find(room => room.roomId === currentLiveRoomId())?.status;
  const delay = liveRealtime.status === "subscribed"
    ? LIVE_POLL_REALTIME_FALLBACK_MS
    : status === "active" ? LIVE_POLL_ACTIVE_MS : LIVE_POLL_LOBBY_MS;
  liveWorkoutPollTimer = setTimeout(() => {
    if (!liveWorkoutMutationInProgress) void refreshLiveWorkoutData(true);
  }, delay);
}

async function refreshLiveWorkoutData(force = false, requestedRoomId = currentLiveRoomId()) {
  const identity = liveSessionIdentity();
  const source = liveSourceKey();
  if (!identity || activeAccount?.remote !== "supabase" || activeAccount.userId !== identity.userId) {
    liveWorkoutState = { status: "idle", source, inbox: null, snapshot: null, error: "" };
    clearTimeout(liveWorkoutPollTimer);
    liveWorkoutPollTimer = null;
    return false;
  }
  void ensureLiveWorkoutRealtime(loadRemoteSession());
  syncWebPushIfEnabled();
  if (!force && liveWorkoutState.status === "loading" && liveWorkoutState.source === source) return false;
  if (liveWorkoutState.status === "loading") liveWorkoutRequestController?.abort();
  const requestId = ++liveWorkoutRequestId;
  const expectedEpoch = accountEpoch;
  liveWorkoutRequestController = new AbortController();
  liveWorkoutState = { ...liveWorkoutState, status: "loading", source, error: "" };
  render();
  try {
    const session = loadRemoteSession();
    const inboxPromise = liveGateway(
      "live_inbox",
      {},
      window.GymLiveWorkout.inbox,
      { session, signal: liveWorkoutRequestController.signal }
    );
    const snapshotPromise = requestedRoomId && window.GymLiveWorkout.patterns.ROOM_ID.test(requestedRoomId)
      ? liveGateway(
          "live_snapshot",
          { roomId: requestedRoomId },
          window.GymLiveWorkout.snapshot,
          { session, signal: liveWorkoutRequestController.signal }
        ).catch(error => {
          if (error?.status === 404 || error?.status === 400) return null;
          throw error;
        })
      : Promise.resolve(null);
    const [inbox, snapshot] = await Promise.all([inboxPromise, snapshotPromise]);
    if (requestId !== liveWorkoutRequestId || !liveIdentityIsCurrent(expectedEpoch, identity)) return false;
    liveWorkoutState = { status: "loaded", source, inbox, snapshot, error: "" };
    if (liveWorkoutBinding && !inbox.rooms.some(room => room.roomId === liveWorkoutBinding.roomId) &&
        snapshot === null) {
      clearLiveWorkoutBinding();
    }
    if (snapshot?.room?.status === "completed" || snapshot?.room?.status === "cancelled" ||
        snapshot?.room?.status === "expired") {
      if (!liveWorkoutBinding?.pendingOperations?.length) clearLiveWorkoutBinding();
    }
    scheduleLiveWorkoutPoll();
    render();
    if (snapshot?.room?.status === "active") {
      void ensureLiveWorkoutAttached(snapshot);
      recoverFinishedLiveWorkoutIntent(snapshot);
      void drainLiveWorkoutOperations();
    }
    return true;
  } catch (error) {
    if (requestId !== liveWorkoutRequestId || !liveIdentityIsCurrent(expectedEpoch, identity)) return false;
    if (transitionToReauthentication(error)) return false;
    liveWorkoutState = {
      status: "error",
      source,
      inbox: null,
      snapshot: null,
      error: tx(
        "Live workout status could not be refreshed safely. Your local workout is still saved.",
        "Не вдалося безпечно оновити live-тренування. Локальне тренування збережено."
      )
    };
    scheduleLiveWorkoutPoll();
    render();
    return false;
  } finally {
    if (requestId === liveWorkoutRequestId) liveWorkoutRequestController = null;
  }
}

async function executeLiveWorkoutMutation(action, payload, parser) {
  if (liveWorkoutMutationInProgress) return null;
  const identity = liveSessionIdentity();
  if (!identity || activeAccount?.userId !== identity.userId) {
    showToast(tx("Sign in to use live workouts.", "Увійди, щоб користуватися live-тренуваннями."));
    return null;
  }
  const expectedEpoch = accountEpoch;
  liveWorkoutMutationInProgress = true;
  render();
  try {
    const result = await liveGateway(action, payload, parser, { session: loadRemoteSession() });
    return liveIdentityIsCurrent(expectedEpoch, identity) ? result : null;
  } catch (error) {
    if (!liveIdentityIsCurrent(expectedEpoch, identity)) return null;
    if (transitionToReauthentication(error)) return null;
    showToast(error?.status === 409
      ? tx("The live workout changed on another device. Refreshing it now.", "Live-тренування змінилося на іншому пристрої. Оновлюємо стан.")
      : tx("The live workout action could not be completed safely.", "Не вдалося безпечно виконати дію live-тренування."));
    void refreshLiveWorkoutData(true);
    return null;
  } finally {
    if (liveIdentityIsCurrent(expectedEpoch, identity)) {
      liveWorkoutMutationInProgress = false;
      render();
    }
  }
}

function liveWorkoutInboxMarkup() {
  const inbox = liveWorkoutState.inbox;
  if (!inbox) {
    if (activeAccount?.remote !== "supabase") return "";
    return `<section class="panel"><div class="row-head"><div><span class="eyebrow">LIVE</span><h2>${tx("Live workouts", "Live-тренування")}</h2><p class="muted">${escapeHtml(liveWorkoutState.error || tx("Refresh to check live rooms.", "Онови, щоб перевірити live-кімнати."))}</p></div><button class="button ghost" data-action="refresh-live-workouts">${tx("Refresh", "Оновити")}</button></div></section>`;
  }
  const invitations = inbox.invitations.map(invite => `<article class="panel highlighted social-invite-card"><div><span class="eyebrow">${tx("LIVE INVITATION", "LIVE-ЗАПРОШЕННЯ")}</span><h3>${escapeHtml(invite.owner.displayName)}</h3><p>${invite.summary.exerciseCount} ${tx("exercises", "вправ")} · ${invite.summary.setCount} ${tx("sets", "підходів")}</p><p class="muted">${escapeHtml(invite.summary.exerciseNames.join(" · "))}</p></div><div class="actions"><button class="button mini" data-action="respond-live-invite" data-decision="accept" data-room-id="${escapeAttr(invite.roomId)}" data-revision="${invite.roomRevision}">${tx("Join", "Приєднатися")}</button><button class="button ghost mini" data-action="respond-live-invite" data-decision="decline" data-room-id="${escapeAttr(invite.roomId)}" data-revision="${invite.roomRevision}">${tx("Decline", "Відхилити")}</button></div></article>`).join("");
  const rooms = inbox.rooms.map(room => `<button class="leaderboard-row social-friend-row" data-action="open-live-room" data-room-id="${escapeAttr(room.roomId)}"><div>${svg("fitness", "small-icon")}</div><div><strong>${escapeHtml(room.peer.displayName)}</strong><small>${room.status === "waiting" ? tx("Invitation pending", "Запрошення очікує") : room.status === "ready" ? tx("Both joined · waiting for host", "Обидва приєдналися · очікування господаря") : tx("Workout is live", "Тренування наживо")}</small></div><span class="pill">${room.status === "active" ? "LIVE" : escapeHtml(room.status)}</span></button>`).join("");
  if (!invitations && !rooms) return "";
  return `<section class="social-invite-list"><div class="section-title"><div><span class="eyebrow">LIVE</span><h2>${tx("Shared live workouts", "Спільні live-тренування")}</h2></div><button class="button ghost mini" data-action="refresh-live-workouts">${tx("Refresh", "Оновити")}</button></div>${invitations}${rooms}<p class="muted">${tx("Each set is saved locally first and then synchronized. Your friend sees progress, not private notes or account data.", "Кожен підхід спочатку зберігається локально, а потім синхронізується. Друг бачить прогрес, але не приватні нотатки чи дані акаунта.")}</p></section>`;
}

function socialRankingRows() {
  const dashboard = socialState.dashboard;
  if (!dashboard) return [];
  const rows = [
    { ...dashboard.self, isCurrent: true, progressShared: true },
    ...dashboard.friends.map(friend => ({ ...friend, isCurrent: false }))
  ].filter(row => row.statsAvailable && row.xp !== null && row.level !== null && row.workouts !== null);
  return rows.sort((left, right) => right.xp - left.xp || right.workouts - left.workouts ||
    left.profileId.localeCompare(right.profileId));
}

function friendRankingRow(row, index) {
  const content = `<div class="rank-place">${row.isCurrent ? svg("person", "small-icon") : index + 1}</div><div><h3>${escapeHtml(row.displayName)}</h3><p>${tx("Level", "Рівень")} ${row.level} · ${n(row.workouts, "workout", "workouts", "тренування", "тренування", "тренувань")}</p></div><strong>${row.xp} XP</strong>`;
  return row.isCurrent
    ? `<article class="leaderboard-row highlighted">${content}</article>`
    : `<button class="leaderboard-row social-friend-row" data-action="open-friend" data-profile-id="${escapeAttr(row.profileId)}">${content}</button>`;
}

function socialRequestCards() {
  const dashboard = socialState.dashboard;
  if (!dashboard) return "";
  const incoming = dashboard.incoming.map(row => `<article class="panel social-request-card"><div><strong>${escapeHtml(row.displayName)}</strong><p class="muted">${tx("Wants to add you as a friend.", "Хоче додати тебе в друзі.")}</p></div><div class="actions"><button class="button mini" data-action="respond-friend" data-decision="accept" data-friendship-id="${escapeAttr(row.friendshipId)}" data-revision="${row.friendshipRevision}">${tx("Accept", "Прийняти")}</button><button class="button ghost mini" data-action="respond-friend" data-decision="decline" data-friendship-id="${escapeAttr(row.friendshipId)}" data-revision="${row.friendshipRevision}">${tx("Decline", "Відхилити")}</button><button class="button danger mini" data-action="block-friend" data-profile-id="${escapeAttr(row.profileId)}">${tx("Block", "Заблокувати")}</button></div></article>`).join("");
  const outgoing = dashboard.outgoing.map(row => `<article class="panel social-request-card"><div><strong>${escapeHtml(row.displayName)}</strong><p class="muted">${tx("Request pending", "Запит очікує")}</p></div><button class="button ghost mini" data-action="cancel-friend" data-friendship-id="${escapeAttr(row.friendshipId)}" data-revision="${row.friendshipRevision}">${tx("Cancel", "Скасувати")}</button></article>`).join("");
  if (!incoming && !outgoing) return "";
  return `<section class="social-request-list"><h2>${tx("Friend requests", "Запити в друзі")}</h2><p class="muted">${tx("Accepting lets this person see the categories enabled above. You can change them, remove the friend, or block them at any time.", "Після прийняття ця людина бачитиме категорії, увімкнені вище. Їх можна змінити, а друга — видалити чи заблокувати будь-коли.")}</p>${incoming}${outgoing}</section>`;
}

function socialWorkoutInviteRows() {
  const inbox = socialState.inbox;
  if (!inbox) return "";
  const pendingIncoming = inbox.incoming.filter(row => row.status === "pending").map(row => `<article class="panel highlighted social-invite-card"><div><span class="eyebrow">${tx("Workout invitation", "Запрошення на тренування")}</span><h3>${escapeHtml(row.displayName)}</h3><p>${row.summary.exerciseCount} ${tx("exercises", "вправ")} · ${row.summary.setCount} ${tx("sets", "підходів")}</p><p class="muted">${escapeHtml(row.summary.exerciseNames.join(" · "))}</p></div><div class="actions"><button class="button mini" data-action="respond-workout-invite" data-decision="accept" data-invite-id="${escapeAttr(row.inviteId)}" data-revision="${row.inviteRevision}">${tx("Open plan", "Відкрити план")}</button><button class="button ghost mini" data-action="respond-workout-invite" data-decision="decline" data-invite-id="${escapeAttr(row.inviteId)}" data-revision="${row.inviteRevision}">${tx("Decline", "Відхилити")}</button></div></article>`).join("");
  const acceptedIncoming = inbox.incoming.filter(row => row.status === "accepted").map(row => `<article class="panel social-invite-card"><div><span class="eyebrow">${tx("Accepted workout plan", "Прийнятий план тренування")}</span><h3>${escapeHtml(row.displayName)}</h3><p>${row.summary.exerciseCount} ${tx("exercises", "вправ")} · ${row.summary.setCount} ${tx("sets", "підходів")}</p><p class="muted">${tx("Available again for recovery on this device while the server retains it.", "План можна знову відкрити для відновлення, поки сервер його зберігає.")}</p></div><button class="button ghost mini" data-action="open-accepted-workout-invite" data-invite-id="${escapeAttr(row.inviteId)}">${tx("Open copy again", "Знову відкрити копію")}</button></article>`).join("");
  const outgoing = inbox.outgoing.filter(row => row.status === "pending").map(row => `<article class="panel social-invite-card"><div><strong>${escapeHtml(row.displayName)}</strong><p class="muted">${tx("Workout invitation pending", "Запрошення на тренування очікує")}</p></div><button class="button ghost mini" data-action="cancel-workout-invite" data-invite-id="${escapeAttr(row.inviteId)}" data-revision="${row.inviteRevision}">${tx("Cancel", "Скасувати")}</button></article>`).join("");
  if (!pendingIncoming && !acceptedIncoming && !outgoing) return "";
  return `<section class="social-invite-list"><h2>${tx("Workout invitations", "Запрошення на тренування")}</h2>${pendingIncoming}${acceptedIncoming}${outgoing}<p class="muted">${tx("Accepting opens the shared plan as an editable draft. Each person starts an independent local workout; sets are not synchronized live.", "Прийняття відкриває спільний план як редаговану чернетку. Кожен запускає незалежне локальне тренування; підходи не синхронізуються наживо.")}</p></section>`;
}

function friendsPanel() {
  const cloudMode = Boolean(remoteAuthEnabled() && activeAccount?.remote && loadRemoteSession()?.user?.id);
  if (!cloudMode) {
    return `<section class="panel highlighted"><span class="eyebrow">${tx("Friends", "Друзі")}</span><h2>${tx("Cloud sign-in required", "Потрібен вхід у хмарний акаунт")}</h2><p>${tx("Friend requests, private friend progress, and workout invitations are available only in a signed-in cloud account.", "Запити в друзі, приватний прогрес друзів і запрошення на тренування доступні лише після входу в хмарний акаунт.")}</p></section>`;
  }
  const loading = socialState.status === "loading";
  const dashboard = socialState.dashboard;
  if (!dashboard) {
    return `<section class="panel highlighted"><div class="row-head"><div><span class="eyebrow">${tx("Friends", "Друзі")}</span><h2>${loading ? tx("Loading friends", "Завантажуємо друзів") : tx("Friends unavailable", "Друзі недоступні")}</h2><p>${escapeHtml(socialState.error || tx("Your friend list is protected by your signed-in session.", "Список друзів захищено твоєю поточною сесією."))}</p></div><button class="button" data-action="refresh-social" ${loading ? "disabled" : ""}>${tx("Retry", "Повторити")}</button></div></section>`;
  }
  const rows = socialRankingRows();
  const code = dashboard.self.friendCode;
  const privacy = dashboard.self.privacy;
  const blocked = dashboard.blocked.map(row => `<article class="social-request-card"><strong>${escapeHtml(row.displayName)}</strong><button class="button ghost mini" data-action="unblock-friend" data-profile-id="${escapeAttr(row.profileId)}">${tx("Unblock", "Розблокувати")}</button></article>`).join("");
  return `<section class="hero-panel profile-rating-hero"><div class="hero-split"><div><span class="eyebrow">${tx("Friends-only progress", "Прогрес серед друзів")}</span><h2>${tx("Your circle, not a global rating", "Твоє коло, а не загальний рейтинг")}</h2><p>${tx("Only you and confirmed friends appear here. XP comes from synchronized workouts entered by each person; it is not a verified sports ranking.", "Тут є лише ти й підтверджені друзі. XP беруться із синхронізованих тренувань, які кожен вводить сам; це не перевірений спортивний рейтинг.")}</p></div><div class="hero-stat"><span>${tx("Your XP", "Твої XP")}</span><strong>${dashboard.self.xp ?? "—"}</strong><small>${dashboard.self.level === null ? tx("Unavailable", "Недоступно") : `${tx("Level", "Рівень")} ${dashboard.self.level}`}</small></div></div></section>
    <section class="panel highlighted social-code-card"><div class="section-title"><div><span class="eyebrow">${tx("Add friends", "Додати друзів")}</span><h2>${tx("Your friend code", "Твій код друга")}</h2><p>${tx("Share this random code. A person still needs your approval before seeing anything.", "Поділися цим випадковим кодом. Людина все одно потребує твого підтвердження, перш ніж щось побачить.")}</p></div></div><div class="field-row"><input id="social-own-code" readonly value="${escapeAttr(code)}"><button class="button ghost" data-action="copy-friend-code">${tx("Copy", "Копіювати")}</button></div><div class="field-row"><input id="social-friend-code" maxlength="34" autocomplete="off" autocapitalize="none" spellcheck="false" placeholder="p_…"><button class="button" data-action="send-friend-request" ${socialMutationInProgress ? "disabled" : ""}>${tx("Send request", "Надіслати запит")}</button></div></section>
    <section class="panel social-privacy-card"><h2>${tx("What confirmed friends can see", "Що бачать підтверджені друзі")}</h2><label class="toggle-row"><input id="social-allow-requests" type="checkbox" ${privacy.allowRequests ? "checked" : ""}><span>${tx("Allow new friend requests", "Дозволити нові запити в друзі")}</span></label><label class="toggle-row"><input id="social-share-progress" type="checkbox" ${privacy.shareProgress ? "checked" : ""}><span>${tx("XP, level, and workout count", "XP, рівень і кількість тренувань")}</span></label><label class="toggle-row"><input id="social-share-workouts" type="checkbox" ${privacy.shareRecentWorkouts ? "checked" : ""}><span>${tx("Five recent workout summaries", "П’ять останніх підсумків тренувань")}</span></label><label class="toggle-row"><input id="social-share-records" type="checkbox" ${privacy.shareRecords ? "checked" : ""}><span>${tx("Recorded exercise bests", "Записані найкращі результати у вправах")}</span></label><button class="button ghost full" data-action="save-social-privacy" data-revision="${dashboard.self.settingsRevision}" ${socialMutationInProgress ? "disabled" : ""}>${tx("Save visibility", "Зберегти видимість")}</button></section>
    ${socialRequestCards()}
    ${socialWorkoutInviteRows()}
    ${liveWorkoutInboxMarkup()}
    <section class="panel highlighted"><div class="row-head"><div><h2>${tx("Friends progress", "Прогрес друзів")}</h2><p>${socialState.error ? escapeHtml(socialState.error) : tx("Sorted only inside your confirmed friend circle.", "Сортування лише у твоєму підтвердженому колі друзів.")}</p></div><button class="button ghost" data-action="refresh-social" ${loading ? "disabled" : ""}>${loading ? tx("Loading", "Завантаження") : tx("Refresh", "Оновити")}</button></div></section>
    <section class="leaderboard-list">${rows.length ? rows.map(friendRankingRow).join("") : `<div class="empty">${tx("No shared friend progress yet.", "Спільного прогресу друзів ще немає.")}</div>`}</section>
    ${blocked ? `<details class="panel"><summary>${tx("Blocked profiles", "Заблоковані профілі")}</summary>${blocked}</details>` : ""}`;
}

function friendsProfileScreen() {
  return `<section class="screen-copy profile-screen-copy"><span class="eyebrow">${tx("Profile", "Профіль")}</span><h2>${tx("Account, friends and progress", "Акаунт, друзі та прогрес")}</h2><p>${tx("Manage your account, confirmed friends, workout invitations, and protected data in one place.", "Керуй акаунтом, підтвердженими друзями, запрошеннями на тренування та захищеними даними в одному місці.")}</p></section>
    ${themePreferencePanel()}
    ${accountPanel()}
    ${cloudSyncPanel()}
    ${webPushPanel()}
    ${friendsPanel()}
    ${garminProfilePanel()}
    ${profileDataPanel()}`;
}

function parseSocialGenericSubmission(value) {
  const row = socialExactObject(value, ["version", "result"]);
  if (row.version !== 1 || row.result !== "submitted_or_unavailable") {
    throw new TypeError("Social submission acknowledgement is invalid.");
  }
  return { version: 1, result: row.result };
}

function parseSocialFriendshipMutation(value, expectedStatuses) {
  const row = socialExactObject(value, ["version", "friendshipId", "status", "friendshipRevision"]);
  if (row.version !== 1 || !expectedStatuses.includes(row.status)) {
    throw new TypeError("Friendship acknowledgement is invalid.");
  }
  return {
    version: 1,
    friendshipId: socialFriendshipId(row.friendshipId),
    status: row.status,
    friendshipRevision: socialInteger(row.friendshipRevision, 1, 2147483647)
  };
}

function parseSocialBlockMutation(value) {
  const row = socialExactObject(value, ["version", "profileId", "blocked"]);
  if (row.version !== 1 || typeof row.blocked !== "boolean") {
    throw new TypeError("Block acknowledgement is invalid.");
  }
  return { version: 1, profileId: socialProfileId(row.profileId), blocked: row.blocked };
}

function parseSocialPrivacyMutation(value) {
  const row = socialExactObject(value, ["version", "privacy", "settingsRevision"]);
  if (row.version !== 1) throw new TypeError("Privacy acknowledgement is invalid.");
  return {
    version: 1,
    privacy: parseSocialPrivacy(row.privacy),
    settingsRevision: socialInteger(row.settingsRevision, 1, 2147483647)
  };
}

function parseSocialWorkoutInviteMutation(value, allowWorkout) {
  const required = ["version", "inviteId", "status", "inviteRevision"];
  if (allowWorkout) required.push("workout");
  const row = socialExactObject(value, required);
  const allowedStatuses = allowWorkout ? ["accepted", "declined"] : ["cancelled"];
  if (row.version !== 1 || typeof row.inviteId !== "string" ||
      !SOCIAL_WORKOUT_INVITE_ID_PATTERN.test(row.inviteId) || !allowedStatuses.includes(row.status)) {
    throw new TypeError("Workout invitation acknowledgement is invalid.");
  }
  const workout = allowWorkout && row.status === "accepted"
    ? normalizeSocialWorkoutPlan(row.workout)
    : null;
  if (allowWorkout && row.status === "declined" && row.workout !== null) {
    throw new TypeError("Declined workout invitation returned private data.");
  }
  return {
    version: 1,
    inviteId: row.inviteId,
    status: row.status,
    inviteRevision: socialInteger(row.inviteRevision, 1, 2147483647),
    ...(allowWorkout ? { workout } : {})
  };
}

function prepareSocialWorkoutInviteRequest(profileId, workout) {
  const source = socialSourceKey();
  const fingerprint = canonicalValueFingerprint({ profileId, workout });
  const key = `${source}:${fingerprint}`;
  const existing = socialWorkoutInviteRequests.get(key);
  if (existing) return existing;
  if (socialWorkoutInviteRequests.size >= MAX_PENDING_SOCIAL_WORKOUT_REQUESTS) {
    throw new Error("Too many workout invitation outcomes are still unknown.");
  }
  const request = { key, source, fingerprint, requestId: newUuidV4() };
  socialWorkoutInviteRequests.set(key, request);
  return request;
}

function clearSocialWorkoutInviteRequest(request) {
  if (!request || socialWorkoutInviteRequests.get(request.key)?.requestId !== request.requestId) return;
  socialWorkoutInviteRequests.delete(request.key);
}

async function executeSocialMutation(name, body, parser) {
  if (socialMutationInProgress) return null;
  const session = loadRemoteSession();
  const expectedUserId = activeAccount?.remote === "supabase" ? activeAccount.userId : null;
  if (!session?.user?.id || session.user.id !== expectedUserId) {
    showToast(tx("Sign in to use friends.", "Увійди, щоб користуватися друзями."));
    return null;
  }
  const expectedEpoch = accountEpoch;
  socialMutationInProgress = true;
  render();
  try {
    const response = await socialRpc(name, body, { session });
    if (!socialIdentityIsCurrent(expectedEpoch, expectedUserId)) return null;
    return parser(response);
  } catch (error) {
    if (!socialIdentityIsCurrent(expectedEpoch, expectedUserId)) return null;
    if (transitionToReauthentication(error)) return null;
    showToast(tx(
      "The friend action could not be completed safely. Refresh and try again.",
      "Не вдалося безпечно виконати дію з друзями. Онови дані й спробуй ще раз."
    ));
    return null;
  } finally {
    if (socialIdentityIsCurrent(expectedEpoch, expectedUserId)) {
      socialMutationInProgress = false;
      render();
    }
  }
}

async function sendFriendRequest() {
  const input = app.querySelector("#social-friend-code");
  const friendCode = String(input?.value || "").trim().toLowerCase();
  if (!SOCIAL_PROFILE_ID_PATTERN.test(friendCode)) {
    return showToast(tx("Paste a valid GymApp friend code.", "Встав коректний код друга GymApp."));
  }
  const result = await executeSocialMutation(
    "social_send_friend_request",
    { p_friend_code: friendCode },
    parseSocialGenericSubmission
  );
  if (!result) return;
  await refreshSocialData(true);
  showToast(tx(
    "Request submitted. For privacy, GymApp does not reveal whether an unknown code exists.",
    "Запит надіслано. Заради приватності GymApp не повідомляє, чи існує невідомий код."
  ));
}

async function respondFriendRequest(element) {
  const friendshipId = element.dataset.friendshipId;
  const decision = element.dataset.decision;
  const revision = Number(element.dataset.revision);
  if (!SOCIAL_FRIENDSHIP_ID_PATTERN.test(friendshipId || "") ||
      !["accept", "decline"].includes(decision) || !Number.isSafeInteger(revision)) return;
  const expectedStatus = decision === "accept" ? "accepted" : "declined";
  const result = await executeSocialMutation(
    "social_respond_friend_request",
    { p_friendship_id: friendshipId, p_decision: decision, p_expected_revision: revision },
    value => {
      const parsed = parseSocialFriendshipMutation(value, [expectedStatus]);
      if (parsed.friendshipId !== friendshipId || parsed.status !== expectedStatus) {
        throw new TypeError("Friend request acknowledgement changed identity.");
      }
      return parsed;
    }
  );
  if (!result) return;
  await refreshSocialData(true);
  showToast(decision === "accept"
    ? tx("Friend added.", "Друга додано.")
    : tx("Friend request declined.", "Запит у друзі відхилено."));
}

async function cancelFriendRequest(element) {
  const friendshipId = element.dataset.friendshipId;
  const revision = Number(element.dataset.revision);
  if (!SOCIAL_FRIENDSHIP_ID_PATTERN.test(friendshipId || "") || !Number.isSafeInteger(revision)) return;
  const result = await executeSocialMutation(
    "social_cancel_friend_request",
    { p_friendship_id: friendshipId, p_expected_revision: revision },
    value => {
      const parsed = parseSocialFriendshipMutation(value, ["removed"]);
      if (parsed.friendshipId !== friendshipId) {
        throw new TypeError("Friend request acknowledgement changed identity.");
      }
      return parsed;
    }
  );
  if (!result) return;
  await refreshSocialData(true);
  showToast(tx("Friend request cancelled.", "Запит у друзі скасовано."));
}

function failCloseSocialPrivateCache() {
  resetSocialReadContext();
  socialState = {
    status: "error",
    source: socialSourceKey(),
    dashboard: null,
    inbox: null,
    error: tx(
      "Friend data was hidden until the server state is refreshed.",
      "Дані друзів приховано до оновлення стану із сервера."
    )
  };
  modal = null;
}

async function removeFriend(element) {
  if (socialMutationInProgress) return;
  const friendshipId = element.dataset.friendshipId;
  const revision = Number(element.dataset.revision);
  if (!SOCIAL_FRIENDSHIP_ID_PATTERN.test(friendshipId || "") || !Number.isSafeInteger(revision)) return;
  if (typeof window.confirm === "function" && !window.confirm(tx(
    "Remove this friend? Their progress and workout activity will disappear immediately.",
    "Видалити цього друга? Його прогрес і тренування одразу зникнуть."
  ))) return;
  failCloseSocialPrivateCache();
  const result = await executeSocialMutation(
    "social_remove_friend",
    { p_friendship_id: friendshipId, p_expected_revision: revision },
    value => {
      const parsed = parseSocialFriendshipMutation(value, ["removed"]);
      if (parsed.friendshipId !== friendshipId) {
        throw new TypeError("Friend removal acknowledgement changed identity.");
      }
      return parsed;
    }
  );
  if (!result) return;
  modal = null;
  await refreshSocialData(true);
  showToast(tx("Friend removed.", "Друга видалено."));
}

async function changeFriendBlock(profileId, blocked) {
  if (socialMutationInProgress) return;
  if (!SOCIAL_PROFILE_ID_PATTERN.test(profileId || "")) return;
  if (blocked && typeof window.confirm === "function" && !window.confirm(tx(
    "Block this profile? Friendship, pending requests, and workout invitations will be closed.",
    "Заблокувати цей профіль? Дружбу, запити й запрошення на тренування буде закрито."
  ))) return;
  if (blocked) failCloseSocialPrivateCache();
  const result = await executeSocialMutation(
    blocked ? "social_block_profile" : "social_unblock_profile",
    { p_profile_id: profileId },
    value => {
      const parsed = parseSocialBlockMutation(value);
      if (parsed.profileId !== profileId || parsed.blocked !== blocked) {
        throw new TypeError("Block acknowledgement changed identity.");
      }
      return parsed;
    }
  );
  if (!result) return;
  modal = null;
  await refreshSocialData(true);
  showToast(blocked ? tx("Profile blocked.", "Профіль заблоковано.") : tx("Profile unblocked.", "Профіль розблоковано."));
}

async function saveSocialPrivacy(element) {
  const revision = Number(element.dataset.revision);
  if (!Number.isSafeInteger(revision)) return;
  const read = id => Boolean(app.querySelector(id)?.checked);
  const body = {
    p_allow_requests: read("#social-allow-requests"),
    p_share_progress: read("#social-share-progress"),
    p_share_recent_workouts: read("#social-share-workouts"),
    p_share_records: read("#social-share-records"),
    p_expected_revision: revision
  };
  const result = await executeSocialMutation("social_update_privacy", body, value => {
    const parsed = parseSocialPrivacyMutation(value);
    if (parsed.settingsRevision < revision || parsed.settingsRevision > revision + 1 ||
        parsed.privacy.allowRequests !== body.p_allow_requests ||
        parsed.privacy.shareProgress !== body.p_share_progress ||
        parsed.privacy.shareRecentWorkouts !== body.p_share_recent_workouts ||
        parsed.privacy.shareRecords !== body.p_share_records) {
      throw new TypeError("Privacy acknowledgement does not match the requested settings.");
    }
    return parsed;
  });
  if (!result) return;
  await refreshSocialData(true);
  showToast(tx("Friend visibility updated.", "Видимість для друзів оновлено."));
}

async function sendWorkoutInvite(element) {
  const profileId = element.dataset.profileId;
  const friend = socialState.dashboard?.friends.find(row => row.profileId === profileId);
  if (!friend || modal?.type !== "workout-share") return;
  let workout;
  try {
    workout = normalizeSocialWorkoutPlan(modal.plan);
  } catch {
    return showToast(tx("This workout plan is no longer valid.", "Цей план тренування більше не є коректним."));
  }
  let request;
  try {
    request = prepareSocialWorkoutInviteRequest(profileId, workout);
  } catch {
    return showToast(tx(
      "A secure workout invitation ID could not be created.",
      "Не вдалося створити безпечний ідентифікатор запрошення на тренування."
    ));
  }
  const result = await executeSocialMutation(
    "social_send_workout_invite",
    { p_profile_id: profileId, p_client_request_id: request.requestId, p_workout: workout },
    parseSocialGenericSubmission
  );
  if (!result) return;
  clearSocialWorkoutInviteRequest(request);
  modal = null;
  await refreshSocialData(true);
  showToast(tx(
    "Workout invitation submitted. Your friend will see it inside GymApp.",
    "Запрошення на тренування надіслано. Друг побачить його всередині GymApp."
  ));
}

async function respondWorkoutInvite(element) {
  const inviteId = element.dataset.inviteId;
  const decision = element.dataset.decision;
  const revision = Number(element.dataset.revision);
  const invite = socialState.inbox?.incoming.find(row => row.inviteId === inviteId);
  if (!invite || invite.inviteRevision !== revision || invite.status !== "pending" ||
      !["accept", "decline"].includes(decision)) return;
  if (decision === "accept" && activeWorkout) {
    return showToast(tx(
      "Finish or discard the active workout first. The invitation will remain waiting.",
      "Спочатку заверши або відкинь активне тренування. Запрошення залишиться в очікуванні."
    ));
  }
  if (decision === "accept") {
    try {
      window.GymSharedWorkout.normalize(invite.workout);
    } catch {
      return showToast(tx(
        "This shared plan cannot be imported safely.",
        "Цей спільний план неможливо безпечно імпортувати."
      ));
    }
  }
  const result = await executeSocialMutation(
    "social_respond_workout_invite",
    { p_invite_id: inviteId, p_decision: decision, p_expected_revision: revision },
    value => {
      const parsed = parseSocialWorkoutInviteMutation(value, true);
      const expectedStatus = decision === "accept" ? "accepted" : "declined";
      if (parsed.inviteId !== inviteId || parsed.status !== expectedStatus) {
        throw new TypeError("Workout invitation acknowledgement changed identity.");
      }
      return parsed;
    }
  );
  if (!result) return;
  if (decision === "accept") {
    openSocialWorkoutInvitePlan({ inviteId: result.inviteId, workout: result.workout });
  }
  await refreshSocialData(true);
  if (decision === "decline") {
    showToast(tx("Workout invitation declined.", "Запрошення на тренування відхилено."));
  }
}

function openAcceptedWorkoutInvite(element) {
  const inviteId = element.dataset.inviteId;
  const invite = socialState.inbox?.incoming.find(row =>
    row.inviteId === inviteId && row.status === "accepted"
  );
  if (!invite) return false;
  return openSocialWorkoutInvitePlan(invite);
}

function openSocialWorkoutInvitePlan(invite, allowPendingReplacement = false) {
  const sessionUserId = loadRemoteSession()?.user?.id;
  const expectedUserId = activeAccount?.userId;
  if (!UUID_PATTERN.test(expectedUserId || "") || sessionUserId !== expectedUserId ||
      !SOCIAL_WORKOUT_INVITE_ID_PATTERN.test(invite?.inviteId || "")) return false;
  if (activeWorkout) {
    showToast(tx(
      "Finish or discard the active workout first. The accepted plan stays available in Friends.",
      "Спочатку заверши або відкинь активне тренування. Прийнятий план залишиться доступним у Друзях."
    ));
    return false;
  }
  let workout;
  try {
    workout = normalizeSocialWorkoutPlan(invite.workout);
  } catch {
    showToast(tx("This accepted plan is no longer valid.", "Цей прийнятий план більше не є коректним."));
    return false;
  }
  const samePendingPlan = pendingSharedWorkout &&
    JSON.stringify(pendingSharedWorkout) === JSON.stringify(workout);
  if (pendingSharedWorkout && !samePendingPlan && !allowPendingReplacement) {
    modal = {
      type: "confirm-social-workout-replace",
      workout,
      inviteId: invite.inviteId,
      expectedEpoch: accountEpoch,
      expectedUserId
    };
    render();
    return false;
  }
  pendingSharedWorkout = workout;
  pendingSharedWorkoutOrigin = {
    type: "social",
    inviteId: invite.inviteId,
    userId: expectedUserId
  };
  // Direct invitations remain server-recoverable for their bounded retention
  // window. Never persist their private payload in the account-agnostic link key.
  clearStoredSharedWorkout();
  modal = null;
  return applyPendingSharedWorkout(false);
}

function confirmSocialWorkoutReplacement() {
  const intent = modal;
  if (intent?.type !== "confirm-social-workout-replace" ||
      intent.expectedEpoch !== accountEpoch ||
      !socialIdentityIsCurrent(intent.expectedEpoch, intent.expectedUserId)) {
    modal = null;
    render();
    return false;
  }
  return openSocialWorkoutInvitePlan(
    { inviteId: intent.inviteId, workout: intent.workout },
    true
  );
}

async function cancelWorkoutInvite(element) {
  const inviteId = element.dataset.inviteId;
  const revision = Number(element.dataset.revision);
  const invite = socialState.inbox?.outgoing.find(row => row.inviteId === inviteId);
  if (!invite || invite.inviteRevision !== revision || invite.status !== "pending") return;
  const result = await executeSocialMutation(
    "social_cancel_workout_invite",
    { p_invite_id: inviteId, p_expected_revision: revision },
    value => {
      const parsed = parseSocialWorkoutInviteMutation(value, false);
      if (parsed.inviteId !== inviteId || parsed.status !== "cancelled") {
        throw new TypeError("Workout invitation cancellation changed identity.");
      }
      return parsed;
    }
  );
  if (!result) return;
  await refreshSocialData(true);
  showToast(tx("Workout invitation cancelled.", "Запрошення на тренування скасовано."));
}

async function sendLiveWorkoutInvite(element) {
  const profileId = element.dataset.profileId;
  const friend = socialState.dashboard?.friends.find(row => row.profileId === profileId);
  if (!friend || modal?.type !== "workout-share") return false;
  let workout;
  let request;
  try {
    workout = normalizeSocialWorkoutPlan(modal.plan);
    request = prepareLiveRequest(liveWorkoutInviteRequests, { profileId, workout });
  } catch {
    showToast(tx("This workout cannot be sent live safely.", "Це тренування неможливо безпечно надіслати в live."));
    return false;
  }
  const result = await executeLiveWorkoutMutation(
    "live_send_invite",
    { profileId, clientRequestId: request.requestId, workout },
    window.GymLiveWorkout.sendResult
  );
  if (!result) return false;
  clearLiveRequest(liveWorkoutInviteRequests, request);
  modal = null;
  await refreshLiveWorkoutData(true, result.roomId);
  showToast(result.result === "submitted"
    ? tx("Live invitation sent. You can start after your friend joins.", "Live-запрошення надіслано. Запустити тренування можна після приєднання друга.")
    : tx("Invitation submitted or unavailable. GymApp does not reveal private friend status.", "Запрошення надіслано або недоступне. GymApp не розкриває приватний стан друга."));
  return true;
}

function workoutDraftHasContent(draft = workoutDraft) {
  return Boolean(draft?.blocks?.some(block => String(block?.exerciseName || "").trim() ||
    block?.sets?.some(set => String(set?.weight ?? "").trim() || String(set?.reps ?? "").trim())));
}

async function preflightLiveWorkoutInvitation(invite) {
  const identity = liveSessionIdentity();
  const expectedEpoch = accountEpoch;
  if (!identity || !invite || activeAccount?.userId !== identity.userId) return null;
  try {
    const snapshot = liveWorkoutState.snapshot?.room?.roomId === invite.roomId
      ? liveWorkoutState.snapshot
      : await liveGateway(
          "live_snapshot",
          { roomId: invite.roomId },
          window.GymLiveWorkout.snapshot
        );
    const currentInvite = liveWorkoutState.inbox?.invitations.find(row => row.roomId === invite.roomId);
    const self = snapshot?.participants?.find(participant => participant.isSelf);
    if (!liveIdentityIsCurrent(expectedEpoch, identity) ||
        currentInvite?.roomRevision !== invite.roomRevision ||
        snapshot?.room?.roomId !== invite.roomId || snapshot.room.status !== "waiting" ||
        self?.state !== "invited") {
      return null;
    }
    // The server contract deliberately uses portable exercise identities.
    // Before mutating membership, also prove that this particular client can
    // import the frozen plan under its stricter built-in alias rules.
    window.GymSharedWorkout.normalize(window.GymLiveWorkout.sharedPlan(snapshot.plan));
    liveWorkoutState = { ...liveWorkoutState, snapshot, error: "" };
    return snapshot;
  } catch (error) {
    if (liveIdentityIsCurrent(expectedEpoch, identity)) {
      if (!transitionToReauthentication(error)) {
        showToast(tx(
          "This live plan cannot be imported safely. The invitation remains waiting.",
          "Цей live-план неможливо безпечно імпортувати. Запрошення залишається в очікуванні."
        ));
      }
    }
    return null;
  }
}

async function respondLiveWorkoutInvite(element) {
  const roomId = element.dataset.roomId;
  const decision = element.dataset.decision;
  const roomRevision = Number(element.dataset.revision);
  const invite = liveWorkoutState.inbox?.invitations.find(row => row.roomId === roomId);
  if (!invite || invite.roomRevision !== roomRevision || !["accept", "decline"].includes(decision)) return false;
  if (decision === "accept" && activeWorkout) {
    showToast(tx("Finish or discard the active workout first. The live invitation stays waiting.", "Спочатку заверши або відкинь активне тренування. Live-запрошення залишиться в очікуванні."));
    return false;
  }
  if (decision === "accept" && !await preflightLiveWorkoutInvitation(invite)) return false;
  if (decision === "accept" && workoutDraftHasContent() && typeof window.confirm === "function" &&
      !window.confirm(tx(
        "Join this live workout? When the host starts, its frozen plan will replace your current unsaved draft.",
        "Приєднатися до live-тренування? Після запуску господарем зафіксований план замінить поточну незбережену чернетку."
      ))) return false;
  let request;
  try {
    request = prepareLiveRequest(liveWorkoutActionRequests, {
      action: "respond", roomId, decision, roomRevision
    });
  } catch {
    showToast(tx("Too many live actions have an unknown outcome.", "Забагато live-дій мають невідомий результат."));
    return false;
  }
  const result = await executeLiveWorkoutMutation(
    "live_respond_invite",
    {
      roomId,
      decision,
      expectedRoomRevision: roomRevision,
      clientOperationId: request.requestId
    },
    window.GymLiveWorkout.respondResult
  );
  if (!result || result.roomId !== roomId ||
      (decision === "accept" ? result.result !== "joined" : result.result !== "declined")) return false;
  clearLiveRequest(liveWorkoutActionRequests, request);
  await refreshLiveWorkoutData(true, decision === "accept" ? roomId : null);
  if (decision === "accept") {
    modal = { type: "live-workout-room", roomId };
    render();
  } else {
    showToast(tx("Live invitation declined.", "Live-запрошення відхилено."));
  }
  return true;
}

async function openLiveWorkoutRoom(roomId) {
  if (!window.GymLiveWorkout?.patterns?.ROOM_ID?.test(roomId || "")) return false;
  const visible = liveWorkoutState.inbox?.rooms?.some(room => room.roomId === roomId) ||
    liveWorkoutState.inbox?.invitations?.some(room => room.roomId === roomId) ||
    liveWorkoutBinding?.roomId === roomId;
  if (!visible) return false;
  modal = { type: "live-workout-room", roomId };
  render();
  await refreshLiveWorkoutData(true, roomId);
  return true;
}

function liveParticipantProgressMarkup(participant, totalSets) {
  const completed = participant?.progress?.completedSets?.length || 0;
  const percent = totalSets > 0 ? Math.round(completed / totalSets * 100) : 0;
  const stateLabel = participant?.state === "finished"
    ? tx("Finished", "Завершено")
    : `${completed} / ${totalSets}`;
  return `<article class="panel ${participant?.isSelf ? "highlighted" : ""}"><div class="row-head"><div><strong>${escapeHtml(participant?.profile?.displayName || "")}</strong><p class="muted">${participant?.isSelf ? tx("You", "Ти") : tx("Friend", "Друг")} · ${escapeHtml(stateLabel)}</p></div><span class="pill">${participant?.role === "owner" ? tx("Host", "Господар") : tx("Guest", "Учасник")}</span></div><div class="progress"><span class="${percentageClass(percent)}"></span></div></article>`;
}

function liveWorkoutRoomMarkup() {
  const roomId = modal?.roomId;
  const snapshot = liveWorkoutState.snapshot?.room?.roomId === roomId ? liveWorkoutState.snapshot : null;
  const roomRow = liveWorkoutState.inbox?.rooms?.find(room => room.roomId === roomId);
  const invitation = liveWorkoutState.inbox?.invitations?.find(room => room.roomId === roomId);
  if (liveWorkoutState.status === "loading" && !snapshot && !roomRow && !invitation) {
    return `<div><span class="eyebrow">LIVE</span><h2>${tx("Loading room…", "Завантажуємо кімнату…")}</h2></div>`;
  }
  const invitedSelf = snapshot?.participants?.find(participant => participant.isSelf)?.state === "invited";
  if (invitation && (!snapshot || invitedSelf)) {
    return `<div><span class="eyebrow">LIVE</span><h2>${escapeHtml(invitation.owner.displayName)}</h2><p>${invitation.summary.exerciseCount} ${tx("exercises", "вправ")} · ${invitation.summary.setCount} ${tx("sets", "підходів")}</p><div class="actions vertical"><button class="button full" data-action="respond-live-invite" data-decision="accept" data-room-id="${escapeAttr(invitation.roomId)}" data-revision="${invitation.roomRevision}">${tx("Join live workout", "Приєднатися до live-тренування")}</button><button class="button ghost full" data-action="respond-live-invite" data-decision="decline" data-room-id="${escapeAttr(invitation.roomId)}" data-revision="${invitation.roomRevision}">${tx("Decline", "Відхилити")}</button></div></div>`;
  }
  if (!snapshot) {
    if (!roomRow) return `<div><h2>${tx("Room unavailable", "Кімната недоступна")}</h2><p class="muted">${escapeHtml(liveWorkoutState.error || tx("Refresh the room or return to Friends.", "Онови кімнату або повернися до Друзів."))}</p><button class="button full" data-action="refresh-live-workouts">${tx("Refresh", "Оновити")}</button></div>`;
    const canStart = roomRow.role === "owner" && roomRow.status === "ready";
    const terminalAction = roomRow.role === "owner" ? "cancel-live-room" : "leave-live-room";
    return `<div><span class="eyebrow">LIVE · ${escapeHtml(roomRow.status)}</span><h2>${escapeHtml(roomRow.peer.displayName)}</h2><p>${roomRow.summary.exerciseCount} ${tx("exercises", "вправ")} · ${roomRow.summary.setCount} ${tx("sets", "підходів")}</p><p class="muted">${roomRow.status === "waiting" ? tx("Waiting for your friend to accept.", "Очікуємо, поки друг прийме запрошення.") : tx("Both participants joined. The host starts the shared workout.", "Обидва учасники приєдналися. Господар запускає спільне тренування.")}</p><div class="actions vertical">${canStart ? `<button class="button full" data-action="start-live-room" data-room-id="${escapeAttr(roomRow.roomId)}" data-revision="${roomRow.roomRevision}">${tx("Start for both", "Запустити для обох")}</button>` : ""}<button class="button ghost full" data-action="refresh-live-workouts">${tx("Refresh room", "Оновити кімнату")}</button><button class="button danger full" data-action="${terminalAction}" data-room-id="${escapeAttr(roomRow.roomId)}" data-room-revision="${roomRow.roomRevision}" data-membership-revision="${roomRow.membershipRevision}">${roomRow.role === "owner" ? tx("Cancel room", "Скасувати кімнату") : tx("Leave room", "Вийти з кімнати")}</button></div></div>`;
  }
  const totalSets = snapshot.room.summary.setCount;
  const self = snapshot.participants.find(row => row.isSelf);
  const active = snapshot.room.status === "active";
  const attached = activeWorkout && liveWorkoutBinding?.roomId === roomId &&
    liveWorkoutBinding.localWorkoutId === activeWorkout.id;
  const canStart = snapshot.room.status === "ready" && self?.role === "owner";
  const canAttach = active && !attached && !activeWorkout;
  const canTerminate = self?.role === "owner"
    ? ["waiting", "ready", "active"].includes(snapshot.room.status) && ["joined", "finished"].includes(self.state)
    : self?.role === "participant" && ["ready", "active"].includes(snapshot.room.status) && ["joined", "finished"].includes(self.state);
  const terminalAction = self?.role === "owner" ? "cancel-live-room" : "leave-live-room";
  const terminalLabel = self?.role === "owner" ? tx("Cancel room", "Скасувати кімнату") : tx("Leave room", "Вийти з кімнати");
  return `<div><span class="eyebrow">LIVE · ${escapeHtml(snapshot.room.status)}</span><h2>${tx("Workout room", "Кімната тренування")}</h2><p class="muted">${tx("The plan is frozen for this room. Each participant controls only their own set lane.", "План зафіксовано для цієї кімнати. Кожен учасник керує лише власною шкалою підходів.")}</p>${snapshot.participants.map(row => liveParticipantProgressMarkup(row, totalSets)).join("")}<div class="actions vertical">${canStart ? `<button class="button full" data-action="start-live-room" data-room-id="${escapeAttr(roomId)}" data-revision="${snapshot.room.roomRevision}">${tx("Start for both", "Запустити для обох")}</button>` : ""}${attached ? `<button class="button full" data-action="continue-active-workout">${tx("Continue workout", "Продовжити тренування")}</button>` : ""}${canAttach ? `<button class="button full" data-action="attach-live-room" data-room-id="${escapeAttr(roomId)}">${tx("Open synchronized workout", "Відкрити синхронізоване тренування")}</button>` : ""}<button class="button ghost full" data-action="refresh-live-workouts">${tx("Refresh progress", "Оновити прогрес")}</button>${canTerminate ? `<button class="button danger full" data-action="${terminalAction}" data-room-id="${escapeAttr(roomId)}" data-room-revision="${snapshot.room.roomRevision}" data-membership-revision="${self.membershipRevision}">${terminalLabel}</button>` : ""}</div></div>`;
}

async function startLiveWorkoutRoom(element) {
  const roomId = element.dataset.roomId;
  const roomRevision = Number(element.dataset.revision);
  const row = liveWorkoutState.inbox?.rooms?.find(room => room.roomId === roomId) ||
    (liveWorkoutState.snapshot?.room?.roomId === roomId ? liveWorkoutState.snapshot.room : null);
  if (!row || row.status !== "ready" || row.roomRevision !== roomRevision || activeWorkout) return false;
  let request;
  try {
    request = prepareLiveRequest(liveWorkoutActionRequests, { action: "start", roomId, roomRevision });
  } catch {
    return false;
  }
  const result = await executeLiveWorkoutMutation(
    "live_start",
    { roomId, expectedRoomRevision: roomRevision, clientOperationId: request.requestId },
    window.GymLiveWorkout.startResult
  );
  if (!result || result.roomId !== roomId || result.result !== "started") return false;
  clearLiveRequest(liveWorkoutActionRequests, request);
  await refreshLiveWorkoutData(true, roomId);
  return ensureLiveWorkoutAttached(liveWorkoutState.snapshot, true);
}

async function closeLiveWorkoutRoom(element, kind) {
  const roomId = element.dataset.roomId;
  const inboxRow = liveWorkoutState.inbox?.rooms?.find(room => room.roomId === roomId) || null;
  const snapshot = liveWorkoutState.snapshot?.room?.roomId === roomId ? liveWorkoutState.snapshot : null;
  const self = snapshot?.participants?.find(participant => participant.isSelf) || null;
  const role = inboxRow?.role || self?.role;
  const memberState = inboxRow?.memberState || self?.state;
  const status = inboxRow?.status || snapshot?.room?.status;
  const visibleRoomRevision = inboxRow?.roomRevision ?? snapshot?.room?.roomRevision;
  const visibleMembershipRevision = inboxRow?.membershipRevision ?? self?.membershipRevision;
  const allowed = kind === "cancel"
    ? role === "owner" && ["waiting", "ready", "active"].includes(status) && ["joined", "finished"].includes(memberState)
    : kind === "leave" && role === "participant" && ["ready", "active"].includes(status) && ["joined", "finished"].includes(memberState);
  if (!allowed) return false;
  const expectedRevision = kind === "leave"
    ? Number(element.dataset.membershipRevision)
    : Number(element.dataset.roomRevision);
  const visibleRevision = kind === "leave" ? visibleMembershipRevision : visibleRoomRevision;
  if (!Number.isSafeInteger(expectedRevision) || expectedRevision !== visibleRevision) return false;
  let request;
  try {
    request = prepareLiveRequest(liveWorkoutActionRequests, { action: kind, roomId, expectedRevision });
  } catch {
    return false;
  }
  const payload = kind === "leave"
    ? { roomId, clientOperationId: request.requestId, expectedMembershipRevision: expectedRevision }
    : { roomId, clientOperationId: request.requestId, expectedRoomRevision: expectedRevision };
  const parser = kind === "leave" ? window.GymLiveWorkout.leaveResult : window.GymLiveWorkout.cancelResult;
  const result = await executeLiveWorkoutMutation(`live_${kind}`, payload, parser);
  if (!result || result.roomId !== roomId) return false;
  clearLiveRequest(liveWorkoutActionRequests, request);
  if (liveWorkoutBinding?.roomId === roomId) clearLiveWorkoutBinding();
  modal = null;
  await refreshLiveWorkoutData(true, null);
  showToast(kind === "leave" ? tx("You left the live room.", "Ти вийшов із live-кімнати.") : tx("Live room cancelled.", "Live-кімнату скасовано."));
  return true;
}

function liveDraftFromSnapshot(snapshot) {
  const plan = window.GymLiveWorkout.sharedPlan(snapshot.plan);
  const normalized = normalizeSocialWorkoutPlan(plan);
  return {
    startedAt: Date.parse(snapshot.room.startedAt),
    note: "",
    blocks: normalized.exercises.map(exercise => ({
      exerciseName: exercise.name,
      ...(exercise.catalogKey ? { catalogKey: exercise.catalogKey } : {}),
      sets: exercise.sets.map(set => ({ weight: set.weight, reps: set.reps }))
    }))
  };
}

function applyLiveSnapshotProgressToLocal(snapshot, binding) {
  if (!activeWorkout || activeWorkout.id !== binding.localWorkoutId) return false;
  const self = snapshot.participants.find(row => row.isSelf);
  if (!self?.progress) return false;
  if (Number.isSafeInteger(binding.progressRevision) &&
      self.progress.revision < binding.progressRevision) {
    // A queue acknowledgement may have advanced after this snapshot request
    // started. Never let the late response undo a locally committed set.
    return true;
  }
  const completed = new Map(self.progress.completedSets.map(row => [row.setId, {
    weight: row.weight,
    reps: row.reps,
    completedAt: Date.parse(row.completedAt),
    pending: false
  }]));
  for (const operation of binding.pendingOperations) {
    if (operation.kind === "complete_set") {
      completed.set(operation.serverSetId, {
        weight: operation.weight,
        reps: operation.reps,
        completedAt: operation.localMutationAt,
        pending: true
      });
    } else if (operation.kind === "undo_set") {
      completed.delete(operation.serverSetId);
    }
  }
  const localToServer = new Map(Object.entries(binding.serverToLocalSetIds)
    .map(([serverId, localId]) => [localId, serverId]));
  let changed = false;
  const blocks = activeWorkout.blocks.map(block => ({
    ...block,
    sets: block.sets.map(set => {
      const serverSetId = localToServer.get(set.id);
      const remote = completed.get(serverSetId);
      if (!remote) {
        if (!set.completed) return set;
        changed = true;
        return { ...set, completed: false, completedAt: null };
      }
      const completedAt = remote.pending
        ? (Number.isSafeInteger(set.completedAt) ? set.completedAt : remote.completedAt)
        : remote.completedAt;
      if (!Number.isSafeInteger(completedAt)) return set;
      if (set.completed && set.weight === remote.weight && set.reps === remote.reps &&
          set.completedAt === completedAt) return set;
      changed = true;
      return { ...set, weight: remote.weight, reps: remote.reps, completed: true, completedAt };
    })
  }));
  if (!changed) return true;
  const next = {
    ...activeWorkout,
    blocks,
    revision: activeWorkout.revision + 1,
    updatedAt: Math.max(Date.now(), activeWorkout.updatedAt + 1)
  };
  const stored = persistActiveWorkoutRecord(next, activeAccount, activeWorkoutStorageRaw);
  if (!stored) return false;
  activeWorkout = stored.workout;
  activeWorkoutStorageRaw = stored.raw;
  return true;
}

async function ensureLiveWorkoutAttached(snapshot, requestedByUser = false) {
  if (!snapshot || snapshot.room?.status !== "active") return false;
  const identity = liveSessionIdentity();
  const self = snapshot.participants.find(row => row.isSelf);
  if (!identity || !self?.progress) return false;
  if (liveWorkoutBinding?.roomId === snapshot.room.roomId && activeWorkout &&
      liveWorkoutBinding.localWorkoutId === activeWorkout.id) {
    if (self.progress.revision < liveWorkoutBinding.progressRevision) return true;
    const updated = {
      ...liveWorkoutBinding,
      roomRevision: snapshot.room.roomRevision,
      membershipRevision: self.membershipRevision,
      progressRevision: Math.max(liveWorkoutBinding.progressRevision, self.progress.revision)
    };
    if (!persistLiveWorkoutBinding(updated)) return false;
    return applyLiveSnapshotProgressToLocal(snapshot, liveWorkoutBinding);
  }
  if (!requestedByUser) return false;
  if (activeWorkout) {
    showToast(tx("Another active workout is already open. Finish or discard it first.", "Уже відкрито інше активне тренування. Спочатку заверши або відкинь його."));
    return false;
  }
  let draft;
  try {
    draft = liveDraftFromSnapshot(snapshot);
  } catch {
    showToast(tx("The live plan cannot be imported safely.", "Live-план неможливо безпечно імпортувати."));
    return false;
  }
  if (workoutDraftHasContent() && typeof window.confirm === "function") {
    let samePlan = false;
    try {
      samePlan = canonicalValueFingerprint(normalizeSocialWorkoutPlan(sharedWorkoutPlanFromDraft(workoutDraft))) ===
        canonicalValueFingerprint(window.GymLiveWorkout.sharedPlan(snapshot.plan));
    } catch {
      samePlan = false;
    }
    if (!samePlan && !window.confirm(tx(
      "Open the frozen live plan and replace your current unsaved draft?",
      "Відкрити зафіксований live-план і замінити поточну незбережену чернетку?"
    ))) return false;
  }
  workoutDraft = draft;
  smartGeneratedPlan = null;
  smartPlanStale = false;
  const started = await startWorkout({ liveSnapshot: snapshot, liveIdentity: identity });
  if (!started || !activeWorkout) return false;
  if (!liveWorkoutBinding || liveWorkoutBinding.roomId !== snapshot.room.roomId ||
      !applyLiveSnapshotProgressToLocal(snapshot, liveWorkoutBinding)) {
    showToast(tx(
      "Workout opened locally, but live recovery could not be saved. Keep this page open and refresh the room.",
      "Тренування відкрито локально, але не вдалося зберегти live-відновлення. Не закривай сторінку й онови кімнату."
    ));
    return false;
  }
  modal = null;
  nav = [{ name: "workouts" }, { name: "active" }];
  replaceNavigationHistory();
  render();
  void drainLiveWorkoutOperations();
  return true;
}

function enqueueLiveWorkoutOperation(requested) {
  if (!liveWorkoutBinding || (requested?.kind !== "finish" &&
      (!activeWorkout || liveWorkoutBinding.localWorkoutId !== activeWorkout.id))) return false;
  try {
    const next = window.GymLiveWorkoutState.enqueue(liveWorkoutBinding, {
      ...requested,
      clientOperationId: newUuidV4()
    });
    if (!persistLiveWorkoutBinding(next)) throw new Error("binding_not_saved");
    void drainLiveWorkoutOperations();
    return true;
  } catch {
    activeWorkoutUi = {
      status: "error",
      message: tx(
        "The set is saved locally, but live synchronization could not be queued.",
        "Підхід збережено локально, але не вдалося поставити live-синхронізацію в чергу."
      )
    };
    render();
    return false;
  }
}

function enqueueLiveSetOperation(kind, localSetId, weight = null, reps = null) {
  if (!liveWorkoutBinding) return false;
  const serverSetId = window.GymLiveWorkoutState.localToServer(liveWorkoutBinding, localSetId);
  if (!serverSetId) return false;
  return enqueueLiveWorkoutOperation({ kind, serverSetId, weight, reps });
}

function localLiveOperationReflection(binding, operation) {
  if (!binding || !operation || binding.localWorkoutId < 1) return "unknown";
  const localSetId = operation.serverSetId === null
    ? null
    : binding.serverToLocalSetIds?.[operation.serverSetId];
  if (operation.serverSetId !== null && !Number.isSafeInteger(localSetId)) return "unknown";
  const loaded = loadActiveWorkoutRecord(activeAccount);
  const localWorkout = loaded.workout?.id === binding.localWorkoutId ? loaded.workout : null;
  let history;
  try {
    history = loadState(activeAccount).sessions.find(session => session.id === binding.localWorkoutId) || null;
  } catch {
    return "unknown";
  }
  if (operation.kind === "finish") {
    return !localWorkout && Boolean(history) ? "reflected" : "not_reflected";
  }
  const localSet = localWorkout?.blocks.flatMap(block => block.sets)
    .find(set => set.id === localSetId) || null;
  const historySet = history?.sets?.find(set => set.id === localSetId) || null;
  if (!localWorkout && !history) return "not_reflected";
  if (operation.kind === "complete_set") {
    const candidate = localSet?.completed ? localSet : historySet;
    return candidate && candidate.weight === operation.weight && candidate.reps === operation.reps
      ? "reflected"
      : "not_reflected";
  }
  if (operation.kind === "undo_set") {
    if (localSet) return localSet.completed ? "not_reflected" : "reflected";
    return history && !historySet ? "reflected" : "not_reflected";
  }
  return "unknown";
}

function discardUncommittedLiveOperation(operation) {
  if (!liveWorkoutBinding || liveWorkoutBinding.pendingOperations[0]?.clientOperationId !==
      operation?.clientOperationId) return false;
  try {
    const next = window.GymLiveWorkoutState.acknowledge(
      liveWorkoutBinding,
      operation.clientOperationId,
      liveWorkoutBinding.progressRevision
    );
    return persistLiveWorkoutBinding(next);
  } catch {
    return false;
  }
}

function detachLiveWorkoutAfterConflict(message) {
  clearLiveWorkoutBinding();
  liveWorkoutState = { ...liveWorkoutState, error: message };
  activeWorkoutUi = { status: "error", message };
  if (modal?.type === "live-workout-room") modal = null;
  showToast(message);
  render();
  return "detached";
}

function recoverFinishedLiveWorkoutIntent(snapshot) {
  if (!liveWorkoutBinding || snapshot?.room?.status !== "active" ||
      snapshot.room.roomId !== liveWorkoutBinding.roomId ||
      liveWorkoutBinding.pendingOperations.length > 0 ||
      activeWorkout?.id === liveWorkoutBinding.localWorkoutId ||
      !state.sessions.some(session => session.id === liveWorkoutBinding.localWorkoutId)) {
    return false;
  }
  const self = snapshot.participants.find(participant => participant.isSelf);
  if (!self?.progress || self.state !== "joined" || self.progress.finishedAt !== null) return false;
  return enqueueLiveWorkoutOperation({
    kind: "finish",
    serverSetId: null,
    weight: null,
    reps: null
  });
}

async function recoverLiveWorkoutQueue(identity, operation, contextIsCurrent) {
  if (!liveWorkoutBinding || typeof contextIsCurrent !== "function" || !contextIsCurrent()) return false;
  const snapshot = await liveGateway(
    "live_snapshot",
    { roomId: liveWorkoutBinding.roomId },
    window.GymLiveWorkout.snapshot
  );
  if (!contextIsCurrent()) return false;
  const self = snapshot.participants.find(row => row.isSelf);
  if (!self?.progress || snapshot.room.status !== "active") {
    return detachLiveWorkoutAfterConflict(tx(
      "This live room is no longer active. Your local workout remains available separately.",
      "Ця live-кімната більше не активна. Локальне тренування залишилося доступним окремо."
    ));
  }
  const completed = self.progress.completedSets.find(row => row.setId === operation.serverSetId);
  let alreadyApplied = false;
  let mayRebase = false;
  if (operation.kind === "complete_set") {
    alreadyApplied = Boolean(completed && completed.weight === operation.weight &&
      completed.reps === operation.reps);
    mayRebase = !completed && self.state === "joined" && self.progress.finishedAt === null;
  } else if (operation.kind === "undo_set") {
    alreadyApplied = !completed;
    mayRebase = Boolean(completed && self.progress.undoableSetId === operation.serverSetId &&
      self.state === "joined" && self.progress.finishedAt === null);
  } else {
    alreadyApplied = self.state === "finished" && self.progress.finishedAt !== null;
    mayRebase = self.state === "joined" && self.progress.finishedAt === null;
  }
  if (!alreadyApplied && !mayRebase) {
    return detachLiveWorkoutAfterConflict(tx(
      "Live progress changed on another device. This workout was detached to protect your local sets.",
      "Live-прогрес змінився на іншому пристрої. Тренування від'єднано, щоб захистити локальні підходи."
    ));
  }
  const next = alreadyApplied
    ? window.GymLiveWorkoutState.acknowledge(
        liveWorkoutBinding,
        operation.clientOperationId,
        self.progress.revision,
        snapshot.room.roomRevision,
        self.membershipRevision
      )
    : window.GymLiveWorkoutState.rebase(
        liveWorkoutBinding,
        self.progress.revision,
        newUuidV4(),
        snapshot.room.roomRevision,
        self.membershipRevision
      );
  if (!contextIsCurrent()) return false;
  if (!persistLiveWorkoutBinding(next)) return false;
  liveWorkoutState = { ...liveWorkoutState, status: "loaded", snapshot, error: "" };
  if (activeWorkout && next.localWorkoutId === activeWorkout.id) {
    applyLiveSnapshotProgressToLocal(snapshot, next);
  }
  if (alreadyApplied && operation.kind === "finish" && snapshot.room.status === "completed") {
    clearLiveWorkoutBinding();
  }
  render();
  return alreadyApplied ? "acknowledged" : "rebased";
}

async function drainLiveWorkoutOperations() {
  if (liveWorkoutOperationDrain || !liveWorkoutBinding?.pendingOperations?.length) {
    return liveWorkoutOperationDrain || false;
  }
  const identity = liveSessionIdentity();
  if (!identity || identity.userId !== liveWorkoutBinding.userId ||
      identity.sessionId !== liveWorkoutBinding.sessionId) return false;
  const expectedGeneration = liveWorkoutContextGeneration;
  const expectedEpoch = accountEpoch;
  const expectedRoomId = liveWorkoutBinding.roomId;
  const expectedLocalWorkoutId = liveWorkoutBinding.localWorkoutId;
  const contextIsCurrent = () => liveOperationContextIsCurrent(
    expectedGeneration,
    expectedEpoch,
    identity,
    expectedRoomId,
    expectedLocalWorkoutId
  );
  const drainPromise = (async () => {
    let recoveryAttempts = 0;
    while (liveWorkoutBinding?.pendingOperations?.length && contextIsCurrent()) {
      const operation = liveWorkoutBinding.pendingOperations[0];
      const localReflection = localLiveOperationReflection(liveWorkoutBinding, operation);
      if (localReflection === "not_reflected") {
        const intentAge = Number.isSafeInteger(operation.localMutationAt)
          ? Date.now() - operation.localMutationAt
          : null;
        if (Number.isSafeInteger(intentAge) && intentAge >= 0 &&
            intentAge <= LIVE_LOCAL_INTENT_RECOVERY_MS) {
          scheduleLiveWorkoutPoll();
          break;
        }
        if (!discardUncommittedLiveOperation(operation)) break;
        continue;
      }
      if (localReflection !== "reflected") break;
      try {
        let result;
        if (operation.kind === "finish") {
          result = await liveGateway(
            "live_finish",
            {
              roomId: liveWorkoutBinding.roomId,
              clientOperationId: operation.clientOperationId,
              expectedProgressRevision: operation.expectedProgressRevision
            },
            window.GymLiveWorkout.finishResult
          );
          if (!contextIsCurrent()) break;
          if (result.result === "closed") {
            clearLiveWorkoutBinding();
            break;
          }
          if (result.roomId !== liveWorkoutBinding.roomId || result.result !== "finished") {
            throw new TypeError("Live finish acknowledgement changed identity.");
          }
          const next = window.GymLiveWorkoutState.acknowledge(
            liveWorkoutBinding,
            operation.clientOperationId,
            result.progressRevision,
            result.roomRevision,
            result.membershipRevision
          );
          if (!persistLiveWorkoutBinding(next)) throw new Error("binding_not_saved");
          if (result.status === "completed") {
            clearLiveWorkoutBinding();
            break;
          }
        } else {
          const wireOperation = operation.kind === "complete_set"
            ? {
                kind: operation.kind,
                setId: operation.serverSetId,
                weight: operation.weight,
                reps: operation.reps
              }
            : { kind: operation.kind, setId: operation.serverSetId };
          result = await liveGateway(
            "live_apply",
            {
              roomId: liveWorkoutBinding.roomId,
              clientOperationId: operation.clientOperationId,
              expectedProgressRevision: operation.expectedProgressRevision,
              operation: wireOperation
            },
            window.GymLiveWorkout.applyResult
          );
          if (!contextIsCurrent()) break;
          if (result.result === "closed") {
            clearLiveWorkoutBinding();
            break;
          }
          if (result.roomId !== liveWorkoutBinding.roomId || result.result !== "applied" ||
              result.kind !== operation.kind || result.setId !== operation.serverSetId) {
            throw new TypeError("Live operation acknowledgement changed identity.");
          }
          const next = window.GymLiveWorkoutState.acknowledge(
            liveWorkoutBinding,
            operation.clientOperationId,
            result.progressRevision,
            result.roomRevision
          );
          if (!persistLiveWorkoutBinding(next)) throw new Error("binding_not_saved");
        }
      } catch (error) {
        if (!contextIsCurrent()) break;
        if (transitionToReauthentication(error)) break;
        if (error?.status === 404) {
          detachLiveWorkoutAfterConflict(tx(
            "This live room is no longer available. Your local workout remains saved separately.",
            "Ця live-кімната більше недоступна. Локальне тренування збережено окремо."
          ));
          break;
        }
        if (recoveryAttempts < 1) {
          try {
            const recovery = await recoverLiveWorkoutQueue(identity, operation, contextIsCurrent);
            if (recovery === "acknowledged") continue;
            if (recovery === "rebased") {
              recoveryAttempts += 1;
              continue;
            }
            if (recovery === "detached") break;
          } catch {
            // Keep the original durable operation and retry after the next snapshot.
          }
        }
        liveWorkoutState = {
          ...liveWorkoutState,
          error: tx(
            "A local set is waiting for live synchronization. It will retry after refresh.",
            "Локальний підхід очікує live-синхронізації. Повтор відбудеться після оновлення."
          )
        };
        scheduleLiveWorkoutPoll();
        render();
        break;
      }
    }
    return true;
  })();
  let wrappedDrain = null;
  wrappedDrain = drainPromise.finally(() => {
    if (liveWorkoutOperationDrain === wrappedDrain) {
      liveWorkoutOperationDrain = null;
    }
  });
  liveWorkoutOperationDrain = wrappedDrain;
  return wrappedDrain;
}

async function flushPendingLiveWorkoutOperationsForTransition() {
  if (!liveWorkoutBinding?.pendingOperations?.length && !liveWorkoutOperationDrain) return true;
  const identity = liveSessionIdentity();
  const expectedUserId = liveWorkoutBinding?.userId;
  const expectedSessionId = liveWorkoutBinding?.sessionId;
  if (!identity || identity.userId !== expectedUserId || identity.sessionId !== expectedSessionId) {
    return false;
  }
  await drainLiveWorkoutOperations();
  if (!liveWorkoutBinding) return true;
  return liveWorkoutBinding.userId === expectedUserId &&
    liveWorkoutBinding.sessionId === expectedSessionId &&
    liveWorkoutBinding.pendingOperations.length === 0;
}

async function abandonLiveWorkoutAfterDiscard(binding) {
  if (!binding || liveWorkoutBinding?.roomId !== binding.roomId) return false;
  const kind = binding.role === "owner" ? "cancel" : "leave";
  let request;
  try {
    request = prepareLiveRequest(liveWorkoutActionRequests, {
      action: kind,
      roomId: binding.roomId,
      roomRevision: binding.roomRevision,
      membershipRevision: binding.membershipRevision
    });
  } catch {
    return false;
  }
  const payload = kind === "cancel"
    ? {
        roomId: binding.roomId,
        clientOperationId: request.requestId,
        expectedRoomRevision: binding.roomRevision
      }
    : {
        roomId: binding.roomId,
        clientOperationId: request.requestId,
        expectedMembershipRevision: binding.membershipRevision
      };
  const result = await executeLiveWorkoutMutation(
    `live_${kind}`,
    payload,
    kind === "cancel" ? window.GymLiveWorkout.cancelResult : window.GymLiveWorkout.leaveResult
  );
  if (!result || result.roomId !== binding.roomId) return false;
  clearLiveRequest(liveWorkoutActionRequests, request);
  clearLiveWorkoutBinding();
  await refreshLiveWorkoutData(true, null);
  return true;
}

async function openFriendDetails(profileId) {
  if (!SOCIAL_PROFILE_ID_PATTERN.test(profileId || "") ||
      !socialState.dashboard?.friends.some(friend => friend.profileId === profileId)) return;
  const session = loadRemoteSession();
  const expectedUserId = activeAccount?.userId;
  if (!session?.user?.id || session.user.id !== expectedUserId) return;
  const expectedEpoch = accountEpoch;
  const source = `${socialSourceKey()}:${profileId}`;
  const requestId = ++socialDetailRequestId;
  socialDetailRequestController?.abort();
  socialDetailRequestController = new AbortController();
  socialDetailState = { status: "loading", source, profileId, value: null, error: "" };
  modal = { type: "friend-detail", profileId };
  render();
  try {
    const response = await socialRpc(
      "social_friend_details",
      { p_profile_id: profileId },
      { session, signal: socialDetailRequestController.signal }
    );
    if (requestId !== socialDetailRequestId || source !== `${socialSourceKey()}:${profileId}` ||
        !socialIdentityIsCurrent(expectedEpoch, expectedUserId)) return;
    const value = parseSocialFriendDetails(response);
    if (value.friend.profileId !== profileId) throw new TypeError("Friend detail identity changed.");
    socialDetailState = { status: "loaded", source, profileId, value, error: "" };
  } catch (error) {
    if (requestId !== socialDetailRequestId || !socialIdentityIsCurrent(expectedEpoch, expectedUserId)) return;
    socialDetailState = {
      status: "error",
      source,
      profileId,
      value: null,
      error: tx("This friend profile is no longer available.", "Цей профіль друга більше недоступний.")
    };
  } finally {
    if (requestId === socialDetailRequestId) socialDetailRequestController = null;
  }
  render();
}

function socialDayLabel(day) {
  return new Intl.DateTimeFormat(displayLocale(), { dateStyle: "medium", timeZone: "UTC" })
    .format(new Date(`${day}T12:00:00.000Z`));
}

function friendDetailMarkup() {
  const profileId = modal?.profileId;
  const relation = socialState.dashboard?.friends.find(friend => friend.profileId === profileId);
  if (!relation || socialDetailState.profileId !== profileId) {
    return `<h2>${tx("Friend unavailable", "Друг недоступний")}</h2>`;
  }
  if (socialDetailState.status === "loading") {
    return `<h2>${escapeHtml(relation.displayName)}</h2><p class="muted">${tx("Loading shared activity…", "Завантажуємо спільні дані…")}</p>`;
  }
  if (!socialDetailState.value) {
    return `<h2>${escapeHtml(relation.displayName)}</h2><p class="muted">${escapeHtml(socialDetailState.error)}</p><button class="button full" data-action="open-friend" data-profile-id="${escapeAttr(profileId)}">${tx("Retry", "Повторити")}</button>`;
  }
  const detail = socialDetailState.value;
  const progress = detail.friend.statsAvailable
    ? `<div class="metric-grid three"><div><span>XP</span><strong>${detail.friend.xp}</strong></div><div><span>${tx("Level", "Рівень")}</span><strong>${detail.friend.level}</strong></div><div><span>${tx("Workouts", "Тренування")}</span><strong>${detail.friend.workouts}</strong></div></div>`
    : `<p class="muted">${detail.sharing.progress
      ? tx("This friend's synchronized progress is temporarily unavailable.", "Синхронізований прогрес цього друга тимчасово недоступний.")
      : tx("This friend hides XP and level.", "Цей друг приховав XP і рівень.")}</p>`;
  const workouts = detail.recentWorkouts.length
    ? detail.recentWorkouts.map(workout => `<article class="workout-item"><h3>${escapeHtml(socialDayLabel(workout.workoutDay))}</h3><p>${workout.exerciseCount} ${tx("exercises", "вправ")} · ${workout.setCount} ${tx("sets", "підходів")}</p><p class="muted">${escapeHtml(workout.exercises.map(exerciseDisplayName).join(" · "))}</p></article>`).join("")
    : `<div class="empty">${!detail.sharing.recentWorkouts
      ? tx("Recent workouts are private.", "Останні тренування приховано.")
      : detail.activityUpdatedAt === null
        ? tx("Recent synchronized workouts are temporarily unavailable.", "Останні синхронізовані тренування тимчасово недоступні.")
        : tx("No recent shared workouts.", "Немає нещодавніх спільних тренувань.")}</div>`;
  const records = detail.exerciseRecords.length
    ? detail.exerciseRecords.map(record => `<article class="leaderboard-row"><div>${svg("fitness", "small-icon")}</div><div><h3>${escapeHtml(exerciseDisplayName(record))}</h3><p>${escapeHtml(socialDayLabel(record.lastWorkoutDay))} · ${record.workoutCount} ${tx("workouts", "тренувань")}</p></div><strong>${tx("Max weight", "Макс. вага")} ${escapeHtml(formatSetWeight(record.bestWeightKg))} kg · ${tx("max reps", "макс. повторів")} ${record.bestReps}</strong></article>`).join("")
    : `<div class="empty">${!detail.sharing.records
      ? tx("Exercise records are private.", "Рекорди у вправах приховано.")
      : detail.activityUpdatedAt === null
        ? tx("Synchronized exercise records are temporarily unavailable.", "Синхронізовані рекорди у вправах тимчасово недоступні.")
        : tx("No shared exercise records yet.", "Спільних рекордів у вправах ще немає.")}</div>`;
  return `<div class="friend-detail-sheet"><span class="eyebrow">${tx("Friend profile", "Профіль друга")}</span><h2>${escapeHtml(detail.friend.displayName)}</h2><p class="muted">${tx("Synced data entered by your friend; not independently verified.", "Синхронізовані дані, внесені другом; вони не перевіряються незалежно.")}</p>${progress}<h3>${tx("Recent workouts", "Останні тренування")}</h3>${workouts}<h3>${tx("Recorded exercise bests", "Записані найкращі результати")}</h3>${records}<div class="actions vertical"><button class="button ghost full" data-action="remove-friend" data-friendship-id="${escapeAttr(relation.friendshipId)}" data-revision="${relation.friendshipRevision}">${tx("Remove friend", "Видалити друга")}</button><button class="button danger full" data-action="block-friend" data-profile-id="${escapeAttr(profileId)}">${tx("Block profile", "Заблокувати профіль")}</button></div></div>`;
}

function socialWorkoutInviteBanner() {
  if (route().name === "leaderboard") return "";
  const invite = socialState.inbox?.incoming.find(row => row.status === "pending");
  if (!invite) return "";
  return `<section class="panel highlighted social-invite-banner"><span class="eyebrow">${tx("Workout invitation", "Запрошення на тренування")}</span><h2>${escapeHtml(invite.displayName)}</h2><p>${invite.summary.exerciseCount} ${tx("exercises", "вправ")} · ${invite.summary.setCount} ${tx("sets", "підходів")}</p><div class="actions"><button class="button" data-action="respond-workout-invite" data-decision="accept" data-invite-id="${escapeAttr(invite.inviteId)}" data-revision="${invite.inviteRevision}">${tx("Open plan", "Відкрити план")}</button><button class="button ghost" data-action="respond-workout-invite" data-decision="decline" data-invite-id="${escapeAttr(invite.inviteId)}" data-revision="${invite.inviteRevision}">${tx("Decline", "Відхилити")}</button></div></section>`;
}

function liveWorkoutBanner() {
  if (route().name === "leaderboard") return "";
  const invite = liveWorkoutState.inbox?.invitations?.[0];
  const activeRoom = liveWorkoutState.inbox?.rooms?.find(room => room.status === "active");
  if (invite) {
    return `<section class="panel highlighted social-invite-banner"><span class="eyebrow">LIVE</span><h2>${escapeHtml(invite.owner.displayName)} ${tx("invited you to train together", "запрошує тренуватися разом")}</h2><p>${invite.summary.exerciseCount} ${tx("exercises", "вправ")} · ${invite.summary.setCount} ${tx("sets", "підходів")}</p><div class="actions"><button class="button" data-action="respond-live-invite" data-decision="accept" data-room-id="${escapeAttr(invite.roomId)}" data-revision="${invite.roomRevision}">${tx("Join live", "Приєднатися наживо")}</button><button class="button ghost" data-action="respond-live-invite" data-decision="decline" data-room-id="${escapeAttr(invite.roomId)}" data-revision="${invite.roomRevision}">${tx("Decline", "Відхилити")}</button></div></section>`;
  }
  if (activeRoom && route().name !== "active") {
    return `<section class="panel highlighted social-invite-banner"><span class="eyebrow">LIVE</span><h2>${tx("Workout with", "Тренування з")} ${escapeHtml(activeRoom.peer.displayName)}</h2><p>${tx("Progress is synchronizing. Open the room to see both lanes.", "Прогрес синхронізується. Відкрий кімнату, щоб бачити обидві шкали.")}</p><button class="button" data-action="open-live-room" data-room-id="${escapeAttr(activeRoom.roomId)}">${tx("Open live room", "Відкрити live-кімнату")}</button></section>`;
  }
  return "";
}

function workoutShareSheetMarkup() {
  const friends = socialState.dashboard?.friends || [];
  const cloudMode = Boolean(activeAccount?.remote === "supabase" && loadRemoteSession()?.user?.id);
  const friendOptions = cloudMode
    ? socialState.status === "loading"
      ? `<p class="muted">${tx("Loading friends…", "Завантажуємо друзів…")}</p>`
      : friends.length
        ? `<div class="social-share-friends">${friends.map(friend => `<article class="panel social-request-card"><div><strong>${escapeHtml(friend.displayName)}</strong><p class="muted">${tx("Choose an independent copy or a synchronized room.", "Обери незалежну копію або синхронізовану кімнату.")}</p></div><div class="actions"><button class="button ghost mini" data-action="send-workout-invite" data-profile-id="${escapeAttr(friend.profileId)}">${svg("copy", "small-icon")}${tx("Send copy", "Надіслати копію")}</button><button class="button mini" data-action="send-live-workout-invite" data-profile-id="${escapeAttr(friend.profileId)}">${svg("fitness", "small-icon")}LIVE</button></div></article>`).join("")}</div>`
        : `<p class="muted">${tx("Add and confirm a friend to send the plan directly.", "Додай і підтвердь друга, щоб надіслати план напряму.")}</p>`
    : `<p class="muted">${tx("Sign in to send a private invitation to a friend.", "Увійди, щоб надіслати другу особисте запрошення.")}</p>`;
  return `<div class="workout-share-sheet"><span class="eyebrow">${tx("Share workout", "Поділитися тренуванням")}</span><h2>${tx("Choose how to train together", "Обери, як тренуватися разом")}</h2><p class="muted">${tx("Every option shares only exercises and planned sets. Notes, dates, accounts, and health data stay private.", "Кожен варіант передає лише вправи й заплановані підходи. Нотатки, дати, акаунти та health-дані залишаються приватними.")}</p><button class="button secondary full" data-action="share-workout-link">${svg("share", "small-icon")}${tx("Share a link", "Поділитися посиланням")}</button><div class="section-title"><div><span class="eyebrow">${tx("Friends", "Друзі")}</span><h3>${tx("Send a copy or start live", "Надіслати копію або запустити live")}</h3></div><button class="button ghost mini" data-action="refresh-social">${tx("Refresh", "Оновити")}</button></div>${friendOptions}<p class="muted">${tx("Send copy creates two independent workouts. Live keeps both set-progress lanes synchronized and lets the host start after the friend joins.", "Копія створює два незалежні тренування. Live синхронізує прогрес підходів обох учасників, а господар запускає тренування після приєднання друга.")}</p></div>`;
}

function exercisesScreen() {
  const mappingRows = filteredLibraryExercises();
  return `<section class="screen-copy"><h2>${t("exercises")}</h2><p>${tx("Manage your exercise library, history, and muscle groups.", "Керуй каталогом вправ, історією та групами м’язів.")}</p></section>
    <button class="button full exercise-add-button" data-action="open-exercise-add">${svg("add", "small-icon")}${t("addExercise")}</button>
    <section class="panel exercise-library-heading"><span class="eyebrow">${tx("Your training", "Твої тренування")}</span><h2>${tx("Exercise library", "Каталог вправ")}</h2><p class="muted">${tx("Add a custom movement or open a saved exercise to view its history.", "Додай власну вправу або відкрий збережену, щоб переглянути історію.")}</p></section>
    ${exerciseFilterControls(mappingRows.length)}
    <section class="exercise-list">${mappingRows.length ? mappingRows.map(exerciseRow).join("") : `<div class="empty">${tx("No matching exercises.", "Вправ за цими фільтрами не знайдено.")}</div>`}</section>`;
}

function exerciseFilterControls(resultCount) {
  const regionFilters = [["all", tx("All", "Усі")], ["upper", tx("Upper body", "Верх тіла")], ["lower", tx("Lower body", "Низ тіла")], ["core", tx("Core", "Кор")]];
  const sortFilters = [["name", tx("By name", "За назвою")], ["most", tx("Most frequent", "Найчастіші")], ["least", tx("Least frequent", "Найрідші")]];
  return `<section class="panel highlighted exercise-search-panel"><label for="exercise-search">${tx("Search exercises", "Пошук вправ")}</label><div class="field-row"><input id="exercise-search" type="search" maxlength="${EXERCISE_SEARCH_QUERY_MAX_CHARS}" value="${escapeAttr(exerciseSearchQuery)}" placeholder="${txAttr("Name in English, Ukrainian, or Russian", "Назва англійською, українською або російською")}">${exerciseSearchQuery ? `<button class="icon-button" data-action="clear-exercise-search" aria-label="${txAttr("Clear search", "Очистити пошук")}">${svg("close")}</button>` : ""}</div>
      <div class="filter-scroll"><button class="chip buttonlike favorite-filter ${exerciseFavoritesOnly ? "selected" : ""}" data-action="exercise-favorites-filter" aria-pressed="${exerciseFavoritesOnly}">${svg(exerciseFavoritesOnly ? "heartFilled" : "heart", "small-icon")}${tx("Favorites", "Улюблені")}</button>${regionFilters.map(([id, label]) => `<button class="chip buttonlike ${exerciseBodyFilter === id ? "selected" : ""}" data-action="exercise-body-filter" data-filter="${id}" aria-pressed="${exerciseBodyFilter === id}">${label}</button>`).join("")}</div>
      <div class="filter-scroll">${sortFilters.map(([id, label]) => `<button class="chip buttonlike ${exerciseSortMode === id ? "selected" : ""}" data-action="exercise-sort" data-sort="${id}" aria-pressed="${exerciseSortMode === id}">${label}</button>`).join("")}</div>
      <div class="filter-scroll"><button class="chip buttonlike ${exerciseMuscleFilter === "all" ? "selected" : ""}" data-action="exercise-muscle-filter" data-filter="all">${tx("All muscles", "Усі м’язи")}</button>${muscles.map(([id]) => `<button class="chip buttonlike ${exerciseMuscleFilter === id ? "selected" : ""}" data-action="exercise-muscle-filter" data-filter="${id}">${escapeHtml(muscleLabel(id))}</button>`).join("")}</div><p class="muted">${resultCount} ${tx("exercises", "вправ")}</p></section>`;
}

const exerciseBodyMuscles = {
  upper: new Set(["chest", "shoulders", "biceps", "triceps", "forearms", "lats", "upperBack"]),
  lower: new Set(["lowerBack", "glutes", "quads", "hamstrings", "adductors", "calves"]),
  core: new Set(["abs", "obliques"])
};

function filteredLibraryExercises() {
  const bodyMuscles = exerciseBodyMuscles[exerciseBodyFilter];
  const matching = state.exercises.map(exercise => {
    const ids = new Set(mappingFor(exercise).map(item => typeof item === "string" ? item : item.muscleId));
    const matchesBody = !bodyMuscles || [...ids].some(id => bodyMuscles.has(id));
    const matchesMuscle = exerciseMuscleFilter === "all" || ids.has(exerciseMuscleFilter);
    const matchesFavorite = !exerciseFavoritesOnly || exercise.favorite === true;
    return { exercise, searchMatch: exerciseSearchMatch(exercise, exerciseSearchQuery), matchesBody, matchesMuscle, matchesFavorite };
  }).filter(item => item.searchMatch.matched && item.matchesBody && item.matchesMuscle && item.matchesFavorite);
  return matching.sort((leftItem, rightItem) => {
    const relevanceDifference = rightItem.searchMatch.score - leftItem.searchMatch.score;
    if (relevanceDifference) return relevanceDifference;
    const left = leftItem.exercise;
    const right = rightItem.exercise;
    const nameOrder = exerciseDisplayName(left).localeCompare(exerciseDisplayName(right), state.language);
    if (exerciseSortMode === "name") return nameOrder || Number(left.id) - Number(right.id);
    const difference = exerciseWorkoutCount(left) - exerciseWorkoutCount(right);
    if (difference) return exerciseSortMode === "most" ? -difference : difference;
    return nameOrder || Number(left.id) - Number(right.id);
  }).map(item => item.exercise);
}

function exerciseWorkoutCount(exercise) {
  return state.sessions.reduce((count, session) => count + Number(
    exerciseReferencesForSession(session).some(reference => exercisesMatch(reference, exercise))
  ), 0);
}

function workoutExercisePickerRows(picker = modal) {
  let rows = filteredLibraryExercises();
  if (picker?.target !== "session") return rows;
  const session = state.sessions.find(item => item.id === Number(picker.sessionId));
  if (!session) return [];
  const existing = exerciseReferencesForSession(session);
  return rows.filter(exercise => !existing.some(reference => exercisesMatch(reference, exercise)));
}

function workoutExercisePickerMarkup(picker = modal) {
  const rows = workoutExercisePickerRows(picker);
  const targetLabel = picker?.target === "session"
    ? tx("Add exercise to workout", "Додати вправу до тренування")
    : picker?.target === "draft-replace"
    ? tx("Change exercise", "Змінити вправу")
    : tx("Add exercise to plan", "Додати вправу до плану");
  return `<div class="workout-exercise-picker"><span class="eyebrow">${tx("Exercise catalog", "Каталог вправ")}</span><h2>${targetLabel}</h2><p class="muted">${tx("Search, favorites, body area, muscle, and sorting match the main exercise catalog.", "Пошук, обране, частина тіла, м’яз і сортування такі самі, як в основному каталозі вправ.")}</p>${exerciseFilterControls(rows.length)}<div class="workout-exercise-picker-list">${rows.length ? rows.map(exercise => `<article class="workout-exercise-picker-row">${exerciseMediaThumbnail(exercise, { className: "compact" })}<div><strong>${escapeHtml(exerciseDisplayName(exercise))}</strong>${exerciseSearchReasonMarkup(exercise)}<small>${escapeHtml(mappingFor(exercise).slice(0, 3).map(item => muscleLabel(typeof item === "string" ? item : item.muscleId)).join(" · "))}</small></div><button class="button ghost mini" data-action="select-workout-exercise" data-exercise-id="${escapeAttr(String(exercise.id))}">${tx("Choose", "Обрати")}</button></article>`).join("") : `<div class="empty">${tx("No matching exercises.", "Вправ за цими фільтрами не знайдено.")}</div>`}</div></div>`;
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

function applyLoadProfilePreset(step) {
  if (![2.5, 5].includes(step)) return;
  const input = document.querySelector("#load-profile-weights");
  if (!input) return;
  input.value = Array.from({ length: Math.floor(200 / step) }, (_, index) => (index + 1) * step).join(", ");
  input.focus();
}

function parsedLoadProfileWeights(rawValue) {
  const value = String(rawValue || "").trim();
  if (!value || !/^[\d\s,.;]+$/u.test(value)) return null;
  const tokens = value.split(/[\s,;]+/u).filter(Boolean);
  if (tokens.some(token => !/^\d+(?:\.\d+)?$/u.test(token))) return null;
  const weights = [...new Set(tokens.map(Number))]
    .sort((left, right) => left - right);
  const limits = window.GymStateContract.LIMITS;
  if (!weights.length || weights.length > limits.loadProfileWeights ||
      weights.some(weight => !Number.isFinite(weight) || weight < 0 || weight > limits.weightMax)) return null;
  return weights;
}

function saveExerciseLoadProfile(id) {
  const exercise = state.exercises.find(item => Number(item.id) === id);
  const direction = document.querySelector("#load-profile-direction")?.value;
  const allowedWeightsKg = parsedLoadProfileWeights(document.querySelector("#load-profile-weights")?.value);
  if (!exercise || !["higherIsHarder", "lowerIsHarder"].includes(direction) || !allowedWeightsKg) {
    return showToast(tx("Enter 1 to 128 valid machine weights.", "Введи від 1 до 128 коректних ваг тренажера."));
  }
  const previous = exercise.loadProfile;
  exercise.loadProfile = { direction, allowedWeightsKg };
  try {
    saveState();
  } catch {
    if (previous) exercise.loadProfile = previous;
    else delete exercise.loadProfile;
    return showToast(tx("Machine weights failed the safety checks.", "Ваги тренажера не пройшли перевірку безпеки."));
  }
  modal = null;
  render();
  showToast(tx("Machine weights saved.", "Ваги тренажера збережено."));
}

function removeExerciseLoadProfile(id) {
  const exercise = state.exercises.find(item => Number(item.id) === id);
  if (!exercise) return;
  const previous = exercise.loadProfile;
  delete exercise.loadProfile;
  try {
    saveState();
  } catch {
    if (previous) exercise.loadProfile = previous;
    return showToast(tx("Machine weights could not be removed.", "Не вдалося видалити ваги тренажера."));
  }
  modal = null;
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
  const loadProfile = normalizeExerciseLoadProfile(exercise.loadProfile);
  return `<article class="panel exercise-row"><div class="exercise-card-head"><div class="exercise-card-identity">${exerciseMediaThumbnail(exercise, { className: "compact" })}<div class="exercise-card-title"><h3 class="exercise-name">${escapeHtml(exerciseDisplayName(exercise))}</h3>${exerciseSearchReasonMarkup(exercise)}</div></div><div class="actions"><button class="icon-button favorite-toggle ${favorite ? "selected" : ""}" data-action="toggle-exercise-favorite" data-id="${escapeAttr(String(exercise.id))}" aria-pressed="${favorite}" aria-label="${favorite ? txAttr("Remove from favorites", "Прибрати з улюблених") : txAttr("Add to favorites", "Додати до улюблених")}">${svg(favorite ? "heartFilled" : "heart")}</button>${builtIn ? `<span class="pill">${tx("Built-in", "Вбудована")}</span>` : `<button class="icon-button" data-action="rename-exercise" data-id="${exercise.id}" aria-label="${txAttr("Rename exercise", "Перейменувати вправу")}">${svg("edit")}</button>`}<button class="icon-button" data-action="delete-exercise" data-id="${exercise.id}" aria-label="${txAttr("Delete exercise", "Видалити вправу")}">${svg("delete")}</button></div></div><div class="exercise-metrics"><span class="pill">${n(workoutCount, "workout", "workouts", "тренування", "тренування", "тренувань")}</span><span class="pill">${mappingCount ? tx(`${mappingCount} mapped`, `Зіставлено: ${mappingCount}`) : tx("Auto mapping", "Автоматичне зіставлення")}</span>${loadProfile ? `<span class="pill">${tx("Machine weights", "Ваги тренажера")}: ${loadProfile.allowedWeightsKg.length}</span>` : ""}</div><div class="exercise-card-actions"><button class="button ghost" data-action="exercise-history" data-id="${exercise.id}">${tx("History", "Історія")}</button><button class="button ghost" data-action="map-exercise" data-name="${escapeAttr(exercise.name)}">${tx("Muscle groups", "Групи м’язів")}</button><button class="button ghost" data-action="configure-load-profile" data-id="${exercise.id}">${tx("Machine weights", "Ваги тренажера")}</button></div></article>`;
}

function progressExercisePickerMarkup(selected = null) {
  const selectedCopy = selected
    ? `<div class="progress-picker-selected">${exerciseMediaThumbnail(selected, { className: "progress" })}<div><span class="eyebrow">${tx("SELECTED EXERCISE", "ОБРАНА ВПРАВА")}</span><h2>${escapeHtml(exerciseDisplayName(selected))}</h2><p class="muted">${tx("Trends and saved history for the selected exercise.", "Тренди та збережена історія обраної вправи.")}</p></div></div>`
    : `<div class="progress-picker-selected"><div><span class="eyebrow">${tx("EXERCISE PROGRESS", "ПРОГРЕС ВПРАВИ")}</span><h2>${tx("Choose an exercise", "Обери вправу")}</h2><p class="muted">${tx("Search your exercise library to open its trends and history.", "Знайди вправу в каталозі, щоб відкрити її тренди та історію.")}</p></div></div>`;
  return `<section class="panel highlighted progress-exercise-picker">${selectedCopy}<button class="button full" data-action="open-progress-exercise-picker">${svg("search", "small-icon")}${selected ? tx("Choose or search exercise", "Обрати або знайти вправу") : tx("Choose exercise", "Обрати вправу")}</button></section>`;
}

function progressExercisePickerRows() {
  const query = progressExerciseSearchQuery;
  const selectedId = Number(state.progressExerciseId || 0);
  return state.exercises.map(exercise => ({
    exercise,
    searchMatch: exerciseSearchMatch(exercise, query)
  })).filter(item => item.searchMatch.matched).sort((left, right) => {
    const selectedOrder = Number(Number(right.exercise.id) === selectedId) - Number(Number(left.exercise.id) === selectedId);
    if (selectedOrder) return selectedOrder;
    const relevance = right.searchMatch.score - left.searchMatch.score;
    if (relevance) return relevance;
    return exerciseDisplayName(left.exercise).localeCompare(exerciseDisplayName(right.exercise), displayLocale()) ||
      Number(left.exercise.id) - Number(right.exercise.id);
  });
}

function progressExercisePickerSheetMarkup() {
  const query = progressExerciseSearchQuery;
  const selectedId = Number(state.progressExerciseId || 0);
  const matchingRows = progressExercisePickerRows();
  const rows = matchingRows.slice(0, PROGRESS_EXERCISE_PICKER_LIMIT);
  const omitted = matchingRows.length - rows.length;
  return `<div class="progress-exercise-picker-sheet"><span class="eyebrow">${tx("PROGRESS", "ПРОГРЕС")}</span><h2>${tx("Choose exercise", "Обери вправу")}</h2><p class="muted">${tx("Search uses the same English, Ukrainian, and Russian vocabulary as the exercise library.", "Пошук використовує той самий англійський, український і російський словник, що й каталог вправ.")}</p><label for="progress-exercise-search">${tx("Search exercises", "Пошук вправ")}</label><div class="field-row"><input id="progress-exercise-search" type="search" maxlength="${EXERCISE_SEARCH_QUERY_MAX_CHARS}" value="${escapeAttr(query)}" placeholder="${txAttr("Name in English, Ukrainian, or Russian", "Назва англійською, українською або російською")}" autocomplete="off">${query ? `<button class="icon-button" data-action="clear-progress-exercise-search" aria-label="${txAttr("Clear search", "Очистити пошук")}">${svg("close")}</button>` : ""}</div><div class="progress-exercise-options" role="listbox" aria-label="${txAttr("Exercise progress selection", "Вибір вправи для прогресу")}">${rows.length ? rows.map(({ exercise }) => {
    const isSelected = Number(exercise.id) === selectedId;
    return `<article class="progress-exercise-option ${isSelected ? "selected" : ""}" role="option" aria-selected="${isSelected}">${exerciseMediaThumbnail(exercise, { className: "compact" })}<div class="progress-exercise-option-copy"><strong>${escapeHtml(exerciseDisplayName(exercise))}</strong>${exerciseSearchReasonMarkup(exercise, query)}<small>${n(exerciseWorkoutCount(exercise), "workout", "workouts", "тренування", "тренування", "тренувань")}</small></div><button class="button ghost mini" data-action="select-progress-exercise" data-id="${escapeAttr(String(exercise.id))}" ${isSelected ? "disabled" : ""}>${isSelected ? tx("Selected", "Обрано") : tx("View", "Переглянути")}</button></article>`;
  }).join("") : `<div class="empty">${tx("No matching exercises.", "Вправ за цим запитом не знайдено.")}</div>`}</div>${omitted > 0 ? `<p class="muted">${tx(`${omitted} more matches. Refine the search to see them.`, `Ще ${omitted} збігів. Уточни пошук, щоб побачити їх.`)}</p>` : ""}</div>`;
}

function progressScreen() {
  const selectedId = Number(state.progressExerciseId || state.exercises[0]?.id || 0);
  const selected = state.exercises.find(ex => Number(ex.id) === selectedId);
  if (!selected) return `${monthSwitcher()}${progressExercisePickerMarkup()}
    <section class="panel progress-summary"><h2>${tx("Progress Summary", "Підсумок прогресу")}</h2><p class="muted">${tx("Volume = weight x reps across all completed sets.", "Обсяг = вага x повтори по всіх завершених підходах.")}</p><div class="metric-grid three"><div><span>${tx("Sessions", "Сесії")}</span><strong>0</strong></div><div><span>${tx("Total Sets", "Усього підходів")}</span><strong>0</strong></div><div><span>${tx("Total Reps", "Усього повторів")}</span><strong>0</strong></div><div><span>${tx("Best Weight", "Найкраща вага")}</span><strong>${tx("No data", "Немає даних")}</strong></div><div><span>${tx("Average Max", "Середній максимум")}</span><strong>${tx("No data", "Немає даних")}</strong></div><div><span>${tx("Total Volume", "Загальний обсяг")}</span><strong>0</strong></div></div></section>
    <section class="hero-panel progress-spotlight"><h2>${tx("No exercise data yet", "За цією вправою поки немає даних")}</h2><p>${tx("Pick an exercise to see solo progress.", "Обери вправу, щоб побачити свій прогрес.")}</p></section>
    <section class="panel highlighted trend-panel"><h2>${tx("Visual Trends", "Візуальні тренди")}</h2><p class="muted">${tx("Maximum weight and session volume over time.", "Максимальна вага та обсяг тренування в динаміці.")}</p><div class="empty">${tx("Add sets to see chart.", "Додай підходи, щоб побачити графік.")}</div></section>
    <section class="panel"><div class="empty">${tx("No exercises yet.", "Вправ ще немає.")}</div></section>`;
  const history = allSets(selectedMonthSessions()).filter(set => exercisesMatch(set, selected)).sort((a, b) => b.session.startedAt - a.session.startedAt);
  const grouped = progressHistoryGroups(history);
  const best = Math.max(0, ...history.map(s => safeChartValue(s.weight)));
  const allTimeBest = Math.max(0, ...allSets().filter(set => exercisesMatch(set, selected)).map(set => safeChartValue(set.weight)));
  const avg = grouped.length ? grouped.reduce((sum, g) => sum + Math.max(0, ...g.sets.map(s => safeChartValue(s.weight))), 0) / grouped.length : 0;
  const vol = history.reduce((sum, s) => sum + safeChartValue(s.weight) * safeChartValue(s.reps), 0);
  const reps = history.reduce((sum, x) => sum + safeChartValue(x.reps), 0);
  const hasMuscleMapping = contributionFor(selected).some(item => muscles.some(([id]) => id === item.muscleId));
  return `${monthSwitcher()}${progressExercisePickerMarkup(selected)}
    ${hasMuscleMapping ? exerciseMuscleBreakdownCard(selected, true) : ""}
    <section class="panel progress-summary"><h2>${tx("Progress Summary", "Підсумок прогресу")}</h2><p class="muted">${tx("Volume = weight x reps across all completed sets.", "Обсяг = вага x повтори по всіх завершених підходах.")}</p><div class="metric-grid three"><div><span>${tx("Sessions", "Сесії")}</span><strong>${grouped.length}</strong></div><div><span>${tx("Total Sets", "Усього підходів")}</span><strong>${history.length}</strong></div><div><span>${tx("Total Reps", "Усього повторів")}</span><strong>${reps}</strong></div><div><span>${tx("Best Weight", "Найкраща вага")}</span><strong>${history.length ? `${best.toFixed(1)} kg` : tx("No data", "Немає даних")}</strong></div><div><span>${tx("Average Max", "Середній максимум")}</span><strong>${history.length ? `${avg.toFixed(1)} kg` : tx("No data", "Немає даних")}</strong></div><div><span>${tx("Total Volume", "Загальний обсяг")}</span><strong>${Math.round(vol)}</strong></div></div></section>
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
  return `<article class="workout-item"><h3>${fmtDate(group.session.startedAt)}</h3><div class="chip-row"><span class="chip">${tx("Sets", "Підходи")}: ${group.sets.length}</span><span class="chip">${tx("Reps", "Повтори")}: ${reps}</span><span class="chip">${tx("Volume", "Обсяг")}: ${Math.round(volume)}</span></div><div class="table progress-history-table"><div class="table-row"><strong>${tx("Set", "Підхід")}</strong><strong>${tx("Weight", "Вага")}</strong><strong>${tx("Reps", "Повтори")}</strong></div>${group.sets.map((set, i) => `<div class="table-row"><span>${tx("Set", "Підхід")} ${i + 1}</span><span>${Number(set.weight || 0).toFixed(1)}</span><span>${Number(set.reps || 0)}</span></div>`).join("")}</div></article>`;
}

function missionsScreen() {
  const missions = missionGroups();
  const xp = totalXp();
  const levelState = levelProgress(xp);
  const periods = {
    daily: {
      tabLabel: tx("Daily", "Щоденні"),
      missions: missions.daily
    },
    weekly: {
      tabLabel: tx("Weekly", "Тижневі"),
      missions: missions.weekly
    },
    monthly: {
      tabLabel: tx("Monthly", "Місячні"),
      missions: missions.monthly
    }
  };
  const selected = periods[missionPeriod] || periods.daily;
  const periodTabs = `<section class="segmented mission-period-tabs panel compact" role="tablist" aria-label="${txAttr("Missions", "Місії")}">${Object.entries(periods).map(([period, item]) => {
    const isSelected = period === missionPeriod;
    return `<button type="button" role="tab" id="mission-tab-${period}" aria-controls="mission-panel-${period}" aria-selected="${isSelected}" tabindex="${isSelected ? "0" : "-1"}" class="${isSelected ? "selected" : ""}" data-action="mission-period" data-period="${period}"><strong>${escapeHtml(item.tabLabel)}</strong></button>`;
  }).join("")}</section>`;
  const sections = selected.missions.length
    ? `<section class="mission-list" id="mission-panel-${missionPeriod}" role="tabpanel" aria-labelledby="mission-tab-${missionPeriod}">${selected.missions.map(missionCard).join("")}</section>`
    : `<section class="panel"><div class="empty"><h2>${tx("No missions yet", "Місій ще немає")}</h2><p>${tx("Add workouts to unlock daily, weekly, and monthly goals.", "Додай тренування, щоб відкрити щоденні, тижневі й місячні цілі.")}</p></div></section>`;
  return `<section class="hero-panel missions-rank-hero"><div class="missions-rank-head"><div><h2>${rankTitle(xp)}</h2><p>${tx("Level", "Рівень")} ${levelState.level}</p></div><button class="missions-rank-action" data-action="open-ranks" aria-label="${tAttr("viewRanks")}">${svg("trophy")}</button></div><div class="progress" aria-label="${txAttr("Level progress", "Прогрес рівня")}"><span class="${percentageClass(levelState.progressFraction * 100)}"></span></div><div class="metric-grid"><div><span>${tx("TOTAL XP", "УСЬОГО XP")}</span><strong>${xp}</strong></div><div><span>${tx("Streak", "Серія")}</span><strong>${streakDays()} ${tx("d", "д")}</strong></div></div></section>
    ${periodTabs}
    ${sections}
    ${achievementsGallery()}`;
}

function missionGroups() {
  const history = missionHistoryStats();
  return {
    daily: buildMissionSet("daily", dailyMissionCatalog(), 3, dayNumber(new Date()), ["workouts"], dailyMissionStats(), history),
    weekly: buildMissionSet("weekly", weeklyMissionCatalog(), 3, dayNumber(startOfWeekDate()), ["workouts"], weeklyMissionStats(), history),
    monthly: buildMissionSet("monthly", monthlyMissionCatalog(), 2, dayNumber(new Date(new Date().getFullYear(), new Date().getMonth(), 1)), ["workouts"], monthlyMissionStats(), history)
  };
}

function completedMissions() {
  return Object.values(missionGroups()).flat().filter(m => m.done);
}

function missionLocalizedText(en, uk, ruText) {
  if (state.language === "uk") return uk;
  if (state.language === "ru") return ruText;
  return en;
}

function missionDayCount(goal) {
  return n(goal, "day", "days", "день", "дні", "днів");
}

function missionWorkoutCount(goal) {
  return n(goal, "workout", "workouts", "тренування", "тренування", "тренувань");
}

function missionSetCount(goal) {
  return n(goal, "set", "sets", "підхід", "підходи", "підходів");
}

function missionExerciseCount(goal) {
  return n(goal, "exercise", "exercises", "вправу", "вправи", "вправ");
}

function missionSessionCount(goal) {
  if (state.language === "ru" && goal === 1) return "1 сессию";
  return n(goal, "session", "sessions", "сесію", "сесії", "сесій");
}

function missionUnitLabel(template) {
  const counted = template.unitEn === "workout" || template.unitEn === "workouts"
    ? missionWorkoutCount(template.goal)
    : template.unitEn === "day" || template.unitEn === "days"
      ? missionDayCount(template.goal)
      : template.unitEn === "set" || template.unitEn === "sets"
        ? missionSetCount(template.goal)
        : template.unitEn === "exercise" || template.unitEn === "exercises"
          ? missionExerciseCount(template.goal)
          : template.unitEn === "session" || template.unitEn === "sessions"
            ? n(template.goal, "session", "sessions", "сесія", "сесії", "сесій")
            : null;
  if (!counted) return tx(template.unitEn, template.unitUk);
  return counted.replace(/^\d+\s+/, "");
}

function mission(template, cadence, stats, history) {
  const progress = template.progress(stats);
  const cadenceLabel = cadence === "daily" ? t("daily") : cadence === "weekly" ? t("weekly") : t("monthly");
  return {
    id: template.id,
    cadence,
    cadenceLabel,
    title: tx(template.titleEn, template.titleUk),
    summary: missionSummary(template, cadence),
    progressLabel: `${Math.round(progress)} / ${template.goal} ${missionUnitLabel(template)}`,
    progress,
    target: template.goal,
    done: progress >= template.goal
  };
}

function missionSummary(template, cadence) {
  const goal = template.goal;
  if (cadence === "daily") {
    if (template.family === "workouts") {
      return tx("Complete 1 workout today.", "Заверши 1 тренування сьогодні.");
    }
    if (template.family === "exercises") {
      const exercises = missionExerciseCount(goal);
      return missionLocalizedText(
        `Log ${exercises} today.`,
        `Занеси ${exercises} сьогодні.`,
        `Запиши ${exercises} сегодня.`
      );
    }
    if (template.family === "sets") {
      const sets = missionSetCount(goal);
      return missionLocalizedText(
        `Reach ${sets} today.`,
        `Набери ${sets} за день.`,
        `Выполни ${sets} сегодня.`
      );
    }
    if (template.family === "volume") {
      return tx(`Reach ${goal} total volume today.`, `Набери ${goal} обсягу сьогодні.`);
    }
    if (template.family === "max-session-volume") {
      return tx(`Push one session to ${goal} volume today.`, `Доведи одну сесію до ${goal} обсягу сьогодні.`);
    }
    if (template.family === "max-session-exercises") {
      const exercises = missionExerciseCount(goal);
      return missionLocalizedText(
        `Fit ${exercises} into one session today.`,
        `Збери ${exercises} в одній сесії сьогодні.`,
        `Выполни ${exercises} за одну сессию сегодня.`
      );
    }
    if (template.family === "max-session-sets") {
      const sets = missionSetCount(goal);
      return missionLocalizedText(
        `Build one session to ${sets} today.`,
        `Збери одну сесію до ${sets} сьогодні.`,
        `Выполни ${sets} за одну сессию сегодня.`
      );
    }
  }
  if (cadence === "weekly") {
    if (template.family === "workouts") {
      const workouts = missionWorkoutCount(goal);
      return missionLocalizedText(
        `Complete ${workouts} this week.`,
        `Заверши ${workouts} цього тижня.`,
        `Заверши ${workouts} на этой неделе.`
      );
    }
    if (template.family === "active-days") {
      const days = missionDayCount(goal);
      return missionLocalizedText(
        `Train on ${days} this week.`,
        `Потренуйся у ${days} цього тижня.`,
        `Тренируйся ${days} на этой неделе.`
      );
    }
    if (template.family === "sets") {
      const sets = missionSetCount(goal);
      return missionLocalizedText(
        `Reach ${sets} this week.`,
        `Набери ${sets} цього тижня.`,
        `Выполни ${sets} на этой неделе.`
      );
    }
    if (template.family === "volume") {
      return tx(`Reach ${goal} total volume this week.`, `Набери ${goal} обсягу цього тижня.`);
    }
    if (template.family === "exercises") {
      const exercises = missionExerciseCount(goal);
      return missionLocalizedText(
        `Log ${exercises} this week.`,
        `Занеси ${exercises} цього тижня.`,
        `Запиши ${exercises} на этой неделе.`
      );
    }
    if (template.family === "days-10-sets") {
      const days = missionDayCount(goal);
      return missionLocalizedText(
        `Hit 10 sets on ${days} this week.`,
        `Зроби 10 підходів у ${days} цього тижня.`,
        `Выполни 10 подходов в ${days} на этой неделе.`
      );
    }
    if (template.family === "days-1000-volume") {
      const days = missionDayCount(goal);
      return missionLocalizedText(
        `Reach 1,000 volume on ${days} this week.`,
        `Набери 1 000 обсягу у ${days} цього тижня.`,
        `Набери объём 1 000 в ${days} на этой неделе.`
      );
    }
    if (template.family === "sessions-8-sets") {
      const sessions = missionSessionCount(goal);
      return missionLocalizedText(
        `Finish ${sessions} with eight or more sets this week.`,
        `Заверши ${sessions} з вісьмома або більше підходами цього тижня.`,
        `Заверши ${sessions} с восемью или более подходами на этой неделе.`
      );
    }
    if (template.family === "sessions-3-exercises") {
      const sessions = missionSessionCount(goal);
      return missionLocalizedText(
        `Finish ${sessions} with three or more exercises this week.`,
        `Заверши ${sessions} з трьома або більше вправами цього тижня.`,
        `Заверши ${sessions} с тремя или более упражнениями на этой неделе.`
      );
    }
  }
  if (cadence === "monthly") {
    if (template.family === "workouts") {
      const workouts = missionWorkoutCount(goal);
      return missionLocalizedText(
        `Complete ${workouts} this month.`,
        `Заверши ${workouts} цього місяця.`,
        `Заверши ${workouts} в этом месяце.`
      );
    }
    if (template.family === "active-days") {
      const days = missionDayCount(goal);
      return missionLocalizedText(
        `Train on ${days} this month.`,
        `Потренуйся у ${days} цього місяця.`,
        `Тренируйся ${days} в этом месяце.`
      );
    }
    if (template.family === "sets") {
      const sets = missionSetCount(goal);
      return missionLocalizedText(
        `Reach ${sets} this month.`,
        `Набери ${sets} цього місяця.`,
        `Выполни ${sets} в этом месяце.`
      );
    }
    if (template.family === "volume") {
      return tx(`Reach ${goal} total volume this month.`, `Набери ${goal} обсягу цього місяця.`);
    }
    if (template.family === "exercises") {
      const exercises = missionExerciseCount(goal);
      return missionLocalizedText(
        `Log ${exercises} this month.`,
        `Занеси ${exercises} цього місяця.`,
        `Запиши ${exercises} в этом месяце.`
      );
    }
    if (template.family === "days-10-sets") {
      const days = missionDayCount(goal);
      return missionLocalizedText(
        `Hit 10 sets on ${days} this month.`,
        `Зроби 10 підходів у ${days} цього місяця.`,
        `Выполни 10 подходов в ${days} в этом месяце.`
      );
    }
    if (template.family === "days-1000-volume") {
      const days = missionDayCount(goal);
      return missionLocalizedText(
        `Reach 1,000 volume on ${days} this month.`,
        `Набери 1 000 обсягу у ${days} цього місяця.`,
        `Набери объём 1 000 в ${days} в этом месяце.`
      );
    }
    if (template.family === "sessions-8-sets") {
      const sessions = missionSessionCount(goal);
      return missionLocalizedText(
        `Finish ${sessions} with eight or more sets this month.`,
        `Заверши ${sessions} з вісьмома або більше підходами цього місяця.`,
        `Заверши ${sessions} с восемью или более подходами в этом месяце.`
      );
    }
    if (template.family === "sessions-3-exercises") {
      const sessions = missionSessionCount(goal);
      return missionLocalizedText(
        `Finish ${sessions} with three or more exercises this month.`,
        `Заверши ${sessions} з трьома або більше вправами цього місяця.`,
        `Заверши ${sessions} с тремя или более упражнениями в этом месяце.`
      );
    }
    if (template.family === "max-session-volume") {
      return tx(`Push one session to ${goal} volume this month.`, `Доведи одну сесію до ${goal} обсягу цього місяця.`);
    }
    if (template.family === "max-session-sets") {
      const sets = missionSetCount(goal);
      return missionLocalizedText(
        `Build one session to ${sets} this month.`,
        `Збери одну сесію до ${sets} цього місяця.`,
        `Выполни ${sets} за одну сессию в этом месяце.`
      );
    }
    if (template.family === "max-session-exercises") {
      const exercises = missionExerciseCount(goal);
      return missionLocalizedText(
        `Fit ${exercises} into one session this month.`,
        `Збери ${exercises} в одній сесії цього місяця.`,
        `Выполни ${exercises} за одну сессию в этом месяце.`
      );
    }
  }
  return `${goal} ${tx(template.unitEn, template.unitUk)}`;
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
    if (!selectedFamilies.has(missionSelectionMetric(template.family))) {
      addMissionTemplate(template, selected, selectedIds, selectedFamilies);
    }
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
  selectedFamilies.add(missionSelectionMetric(template.family));
}

function missionSelectionMetric(family) {
  if (family === "active-days") return "workouts";
  if (family === "max-session-volume" || family === "days-1000-volume") return "volume";
  if (family === "max-session-exercises" || family === "sessions-3-exercises") return "exercises";
  if (family === "max-session-sets" || family === "days-10-sets" || family === "sessions-8-sets") return "sets";
  return family;
}

function dailyMissionCatalog() {
  return [
    ...templates("workouts", [1], "daily-check-in", "workout", "тренування", goal => "Daily check-in", goal => "Щоденний чек-ін", s => s.workoutCount),
    ...templates("exercises", intSeries(3, 1, 10), goal => `daily-exercises-${goal}`, "exercises", "вправ", goal => `${goal} exercises today`, goal => `Вправ за день: ${goal}`, s => s.exerciseCount),
    ...templates("sets", intSeries(8, 2, 9), goal => `daily-sets-${goal}`, "sets", "підходів", goal => `${goal}-set target`, goal => `Ціль: ${goal} підходів`, s => s.setCount),
    ...templates("volume", scaledSeries(1800, [0.8, 1, 1.2, 1.4, 1.6, 1.9, 2.2, 2.5, 2.8, 3.1, 3.5, 3.9, 4.3]), goal => `daily-volume-${goal}`, "volume", "обсягу", goal => `Volume target ${goal}`, goal => `Ціль обсягу ${goal}`, s => s.totalVolume),
    ...templates("max-session-volume", scaledSeries(1300, [0.8, 1, 1.2, 1.4, 1.6, 1.9, 2.2, 2.5, 2.8, 3.1, 3.5, 3.9, 4.4, 4.9, 5.5]), goal => `daily-max-session-volume-${goal}`, "volume", "обсягу", goal => `Best session ${goal} volume`, goal => `Краща сесія: ${goal} обсягу`, s => s.maxSessionVolume),
    ...templates("max-session-exercises", intSeries(3, 1, 8), goal => `daily-max-session-exercises-${goal}`, "exercises", "вправ", goal => `Session breadth ${goal}`, goal => `Ширина сесії ${goal}`, s => s.maxSessionExercises),
    ...templates("max-session-sets", intSeries(8, 2, 8), goal => `daily-max-session-sets-${goal}`, "sets", "підходів", goal => `Session sets ${goal}`, goal => `Підходи в сесії: ${goal}`, s => s.maxSessionSets)
  ];
}

function weeklyMissionCatalog() {
  return [
    ...templates("workouts", intSeries(2, 1, 2), goal => `weekly-workouts-${goal}`, "workouts", "тренування", goal => `${goal}-workout week`, goal => `Тренувань за тиждень: ${goal}`, s => s.workoutCount),
    ...templates("active-days", intSeries(2, 1, 2), goal => `weekly-active-days-${goal}`, "days", "днів", goal => `${goal} active days`, goal => `Активних днів: ${goal}`, s => s.activeDays),
    ...templates("sets", intSeries(16, 4, 10), goal => `weekly-sets-${goal}`, "sets", "підходів", goal => `${goal}-set week`, goal => `Тиждень на ${goal} підходів`, s => s.setCount),
    ...templates("volume", scaledSeries(6000, [0.75, 0.9, 1, 1.15, 1.3, 1.5, 1.7, 1.9, 2.2, 2.5, 2.8, 3.2]), goal => `weekly-volume-${goal}`, "volume", "обсягу", goal => `Weekly volume ${goal}`, goal => `Тижневий обсяг ${goal}`, s => s.totalVolume),
    ...templates("exercises", intSeries(8, 2, 12), goal => `weekly-exercises-${goal}`, "exercises", "вправ", goal => `${goal} exercises this week`, goal => `${goal} вправ за тиждень`, s => s.exerciseCount),
    ...templates("days-10-sets", intSeries(1, 1, 3), goal => `weekly-days-10-sets-${goal}`, "days", "днів", goal => `High-output days ${goal}`, goal => `Потужних днів: ${goal}`, s => s.daysWithTenPlusSets),
    ...templates("days-1000-volume", intSeries(1, 1, 3), goal => `weekly-days-1000-volume-${goal}`, "days", "днів", goal => `Volume days ${goal}`, goal => `Днів обсягу: ${goal}`, s => s.daysWithThousandVolume),
    ...templates("sessions-8-sets", intSeries(1, 1, 3), goal => `weekly-sessions-8-sets-${goal}`, "sessions", "сесій", goal => `Strong sessions ${goal}`, goal => `Сильних сесій: ${goal}`, s => s.sessionsWithEightPlusSets),
    ...templates("sessions-3-exercises", intSeries(1, 1, 3), goal => `weekly-sessions-3-exercises-${goal}`, "sessions", "сесій", goal => `Wide sessions ${goal}`, goal => `Широких сесій: ${goal}`, s => s.sessionsWithThreePlusExercises)
  ];
}

function monthlyMissionCatalog() {
  return [
    ...templates("workouts", intSeries(6, 1, 9), goal => `monthly-workouts-${goal}`, "workouts", "тренування", goal => `${goal}-workout month`, goal => `Тренувань за місяць: ${goal}`, s => s.workoutCount),
    ...templates("active-days", intSeries(6, 1, 9), goal => `monthly-active-days-${goal}`, "days", "днів", goal => `${goal} active days`, goal => `Активних днів: ${goal}`, s => s.activeDays),
    ...templates("sets", intSeries(48, 8, 14), goal => `monthly-sets-${goal}`, "sets", "підходів", goal => `${goal}-set month`, goal => `Місяць на ${goal} підходів`, s => s.setCount),
    ...templates("volume", scaledSeries(24000, [0.75, 0.9, 1, 1.15, 1.3, 1.5, 1.7, 1.9, 2.2, 2.5, 2.8, 3.2]), goal => `monthly-volume-${goal}`, "volume", "обсягу", goal => `Monthly volume ${goal}`, goal => `Місячний обсяг ${goal}`, s => s.totalVolume),
    ...templates("exercises", intSeries(24, 4, 16), goal => `monthly-exercises-${goal}`, "exercises", "вправ", goal => `${goal} exercises this month`, goal => `${goal} вправ за місяць`, s => s.exerciseCount),
    ...templates("days-10-sets", intSeries(2, 1, 11), goal => `monthly-days-10-sets-${goal}`, "days", "днів", goal => `High-output days ${goal}`, goal => `Потужних днів: ${goal}`, s => s.daysWithTenPlusSets),
    ...templates("days-1000-volume", intSeries(2, 1, 11), goal => `monthly-days-1000-volume-${goal}`, "days", "днів", goal => `Volume days ${goal}`, goal => `Днів обсягу: ${goal}`, s => s.daysWithThousandVolume),
    ...templates("sessions-8-sets", intSeries(2, 1, 12), goal => `monthly-sessions-8-sets-${goal}`, "sessions", "сесій", goal => `Strong sessions ${goal}`, goal => `Сильних сесій: ${goal}`, s => s.sessionsWithEightPlusSets),
    ...templates("sessions-3-exercises", intSeries(2, 1, 12), goal => `monthly-sessions-3-exercises-${goal}`, "sessions", "сесій", goal => `Wide sessions ${goal}`, goal => `Широких сесій: ${goal}`, s => s.sessionsWithThreePlusExercises),
    ...templates("max-session-volume", scaledSeries(1400, [1, 1.15, 1.3, 1.45, 1.6, 1.8, 2, 2.25, 2.5, 2.8, 3.1, 3.5, 3.9, 4.3, 4.8, 5.3]), goal => `monthly-max-session-volume-${goal}`, "volume", "обсягу", goal => `Best session ${goal} volume`, goal => `Краща сесія: ${goal} обсягу`, s => s.maxSessionVolume),
    ...templates("max-session-sets", intSeries(10, 2, 11), goal => `monthly-max-session-sets-${goal}`, "sets", "підходів", goal => `Best session ${goal} sets`, goal => `Підходів у кращій сесії: ${goal}`, s => s.maxSessionSets),
    ...templates("max-session-exercises", intSeries(4, 1, 9), goal => `monthly-max-session-exercises-${goal}`, "exercises", "вправ", goal => `Best session ${goal} exercises`, goal => `Вправ у кращій сесії: ${goal}`, s => s.maxSessionExercises)
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

function missionHistoryStats(now = Date.now()) {
  if (!state.sessions.length) return {};
  const windows = missionCalendarWindows(now);
  const daySessions = state.sessions.filter(session =>
    session.startedAt >= windows.dayStartInclusive && session.startedAt < windows.currentDayStartExclusive
  );
  const completedWeekSessions = state.sessions.filter(session =>
    session.startedAt >= windows.completedWeekStartInclusive &&
    session.startedAt < windows.currentWeekStartExclusive
  );
  const completedMonthSessions = state.sessions.filter(session =>
    session.startedAt >= windows.completedMonthStartInclusive &&
    session.startedAt < windows.currentMonthStartExclusive
  );
  const recentSessionCandidates = state.sessions.filter(session =>
    session.startedAt >= windows.sessionStartInclusive && session.startedAt < windows.currentDayStartExclusive
  );
  const dayAggregates = recentMissionAggregates(daySessions, session => dayKey(session.startedAt), aggregateSessions);
  const weekAggregates = recentMissionAggregates(
    completedWeekSessions,
    session => dayKey(startOfWeekDate(new Date(session.startedAt))),
    aggregatePeriod
  );
  const monthAggregates = recentMissionAggregates(
    completedMonthSessions,
    session => monthKey(session.startedAt),
    aggregatePeriod
  );
  const summaries = [...recentSessionCandidates]
    .sort((a, b) => b.startedAt - a.startedAt)
    .slice(0, 12)
    .map(sessionSummary);
  return {
    typicalDayWorkouts: typicalMissionValue(dayAggregates, "workoutCount", 1),
    typicalDayExercises: typicalMissionValue(dayAggregates, "exerciseCount", 3),
    typicalDaySets: typicalMissionValue(dayAggregates, "setCount", 8),
    typicalDayVolume: typicalMissionValue(dayAggregates, "totalVolume", 1800),
    typicalWeekWorkouts: typicalMissionValue(weekAggregates, "workoutCount", 3),
    typicalWeekActiveDays: typicalMissionValue(weekAggregates, "activeDays", 2),
    typicalWeekExercises: typicalMissionValue(weekAggregates, "exerciseCount", 12),
    typicalWeekSets: typicalMissionValue(weekAggregates, "setCount", 24),
    typicalWeekVolume: typicalMissionValue(weekAggregates, "totalVolume", 7500),
    typicalWeekDaysWithTenPlusSets: typicalMissionValue(weekAggregates, "daysWithTenPlusSets", 1),
    typicalWeekDaysWithThousandVolume: typicalMissionValue(weekAggregates, "daysWithThousandVolume", 1),
    typicalWeekSessionsWithEightPlusSets: typicalMissionValue(weekAggregates, "sessionsWithEightPlusSets", 2),
    typicalWeekSessionsWithThreePlusExercises: typicalMissionValue(weekAggregates, "sessionsWithThreePlusExercises", 2),
    typicalMonthWorkouts: typicalMissionValue(monthAggregates, "workoutCount", 8),
    typicalMonthActiveDays: typicalMissionValue(monthAggregates, "activeDays", 8),
    typicalMonthExercises: typicalMissionValue(monthAggregates, "exerciseCount", 32),
    typicalMonthSets: typicalMissionValue(monthAggregates, "setCount", 64),
    typicalMonthVolume: typicalMissionValue(monthAggregates, "totalVolume", 24000),
    typicalMonthDaysWithTenPlusSets: typicalMissionValue(monthAggregates, "daysWithTenPlusSets", 4),
    typicalMonthDaysWithThousandVolume: typicalMissionValue(monthAggregates, "daysWithThousandVolume", 4),
    typicalMonthSessionsWithEightPlusSets: typicalMissionValue(monthAggregates, "sessionsWithEightPlusSets", 4),
    typicalMonthSessionsWithThreePlusExercises: typicalMissionValue(monthAggregates, "sessionsWithThreePlusExercises", 4),
    typicalSessionVolume: typicalMissionValue(summaries, "volume", 1800),
    typicalSessionExercises: typicalMissionValue(summaries, "exercises", 4),
    typicalSessionSets: typicalMissionValue(summaries, "sets", 10)
  };
}

function missionCalendarWindows(now) {
  const nowDate = new Date(now);
  const currentDayStart = new Date(nowDate.getFullYear(), nowDate.getMonth(), nowDate.getDate());
  const dayStart = new Date(currentDayStart);
  dayStart.setDate(dayStart.getDate() - 42);
  const currentWeekStart = startOfWeekDate(nowDate);
  const completedWeekStart = new Date(currentWeekStart);
  completedWeekStart.setDate(completedWeekStart.getDate() - 8 * 7);
  const currentMonthStart = new Date(nowDate.getFullYear(), nowDate.getMonth(), 1);
  const completedMonthStart = new Date(nowDate.getFullYear(), nowDate.getMonth() - 6, 1);
  return {
    dayStartInclusive: dayStart.getTime(),
    currentDayStartExclusive: currentDayStart.getTime(),
    completedWeekStartInclusive: completedWeekStart.getTime(),
    currentWeekStartExclusive: currentWeekStart.getTime(),
    completedMonthStartInclusive: completedMonthStart.getTime(),
    currentMonthStartExclusive: currentMonthStart.getTime(),
    sessionStartInclusive: completedMonthStart.getTime()
  };
}

function recentMissionAggregates(sessions, keySelector, aggregate) {
  return Object.values(groupBy(sessions, keySelector))
    .sort((a, b) => Math.max(...b.map(item => item.startedAt)) - Math.max(...a.map(item => item.startedAt)))
    .map(aggregate);
}

function typicalMissionValue(items, key, fallback) {
  const values = items
    .map(item => Math.round(Number(item[key] || 0)))
    .filter(value => Number.isFinite(value) && value > 0)
    .sort((a, b) => a - b);
  if (values.length < 2) return fallback;
  const baseline = values[Math.floor((values.length - 1) / 2)] || 0;
  return baseline;
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
    if (family === "exercises") return boundedTarget(history.typicalDayExercises, 3, 3, 10);
    if (family === "sets") return boundedTarget(history.typicalDaySets, 8, 8, 22);
    if (family === "volume") return boundedTarget(history.typicalDayVolume, 1800, 1200, 7000);
    if (family === "max-session-volume") return boundedTarget(history.typicalSessionVolume, 1800, 1000, 7000);
    if (family === "max-session-exercises") return boundedTarget(history.typicalSessionExercises, 4, 3, 9);
    if (family === "max-session-sets") return boundedTarget(history.typicalSessionSets, 10, 8, 22);
  }
  if (cadence === "weekly") {
    if (family === "workouts") return boundedTarget(history.typicalWeekWorkouts, 3, 2, 3);
    if (family === "active-days") return boundedTarget(history.typicalWeekActiveDays, 2, 2, 3);
    if (family === "exercises") return boundedTarget(history.typicalWeekExercises, 12, 8, 30);
    if (family === "sets") return boundedTarget(history.typicalWeekSets, 24, 16, 48);
    if (family === "volume") return boundedTarget(history.typicalWeekVolume, 7500, 4500, 20000);
    if (family === "days-10-sets") return boundedTarget(history.typicalWeekDaysWithTenPlusSets, 1, 1, 3);
    if (family === "days-1000-volume") return boundedTarget(history.typicalWeekDaysWithThousandVolume, 1, 1, 3);
    if (family === "sessions-8-sets") return boundedTarget(history.typicalWeekSessionsWithEightPlusSets, 2, 1, 3);
    if (family === "sessions-3-exercises") return boundedTarget(history.typicalWeekSessionsWithThreePlusExercises, 2, 1, 3);
  }
  if (cadence === "monthly") {
    if (family === "workouts") return boundedTarget(history.typicalMonthWorkouts, 8, 6, 14);
    if (family === "active-days") return boundedTarget(history.typicalMonthActiveDays, 8, 6, 14);
    if (family === "exercises") return boundedTarget(history.typicalMonthExercises, 32, 24, 96);
    if (family === "sets") return boundedTarget(history.typicalMonthSets, 64, 48, 160);
    if (family === "volume") return boundedTarget(history.typicalMonthVolume, 24000, 18000, 70000);
    if (family === "days-10-sets") return boundedTarget(history.typicalMonthDaysWithTenPlusSets, 4, 2, 12);
    if (family === "days-1000-volume") return boundedTarget(history.typicalMonthDaysWithThousandVolume, 4, 2, 12);
    if (family === "sessions-8-sets") return boundedTarget(history.typicalMonthSessionsWithEightPlusSets, 4, 2, 12);
    if (family === "sessions-3-exercises") return boundedTarget(history.typicalMonthSessionsWithThreePlusExercises, 4, 2, 12);
    if (family === "max-session-volume") return boundedTarget(history.typicalSessionVolume, 2000, 1000, 7000);
    if (family === "max-session-sets") return boundedTarget(history.typicalSessionSets, 10, 8, 26);
    if (family === "max-session-exercises") return boundedTarget(history.typicalSessionExercises, 4, 3, 10);
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

function missionCard(m) {
  const status = m.done ? tx("Completed", "Виконано") : tx("In progress", "У процесі");
  return `<article class="mission-row ${m.done ? "highlighted" : ""}" aria-label="${escapeAttr(`${m.cadenceLabel}. ${status}`)}"><div class="mission-card-head"><span class="mission-card-icon ${m.done ? "complete" : ""}" aria-hidden="true">${svg(m.done ? "checkCircle" : "timer")}</span><div class="mission-card-copy"><h3>${escapeHtml(m.title)}</h3><p>${escapeHtml(m.summary)}</p></div></div><div class="progress"><span class="${percentageClass(m.progress / Math.max(1, m.target) * 100)}"></span></div><small class="mission-progress-label">${escapeHtml(m.progressLabel)}</small></article>`;
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
  if (modal.type === "add-exercise") return bottomSheet(`<h2>${tx("Add exercise", "Додати вправу")}</h2><input id="new-exercise-name" maxlength="320" aria-label="${txAttr("Exercise name", "Назва вправи")}" placeholder="${txAttr("Exercise name", "Назва вправи")}"><button class="button full" data-action="save-exercise">${tx("Add exercise", "Додати вправу")}</button>`);
  if (modal.type === "exercise-media") {
    const media = exerciseMedia(modal.exercise);
    const frames = media?.frames || [];
    const visual = frames.length
      ? `<div class="exercise-media-stage ${frames.length > 1 ? "animated" : ""}" aria-label="${txAttr("Exercise movement reference", "Орієнтир руху вправи")}">${frames.map((frame, index) => `<img class="exercise-media-frame frame-${index}" src="${escapeAttr(frame)}" alt="">`).join("")}<span class="exercise-media-state">${frames.length > 1 ? tx("Start · Finish", "Початок · Кінець") : tx("Your image", "Ваше фото")}</span></div>`
      : `<div class="exercise-media-stage empty">${svg("image", "exercise-media-empty-icon")}<strong>${tx("No demonstration yet", "Демонстрації поки немає")}</strong><p>${tx("Choose a clear image that helps you recognize this exercise.", "Оберіть чітке фото, яке допоможе впізнати цю вправу.")}</p></div>`;
    return bottomSheet(`<div class="exercise-media-sheet"><div><span class="eyebrow">${tx("Movement guide", "Орієнтир руху")}</span><h2>${escapeHtml(exerciseDisplayName(modal.exercise))}</h2><p class="muted">${tx("Tap-friendly reference for exercise selection. This is not medical or coaching advice.", "Зручний орієнтир для вибору вправи. Це не медична чи тренерська рекомендація.")}</p></div>${visual}<label class="button secondary full exercise-media-file-label">${svg("upload", "small-icon")}${tx("Choose your image", "Обрати своє фото")}<input id="exercise-media-file" type="file" accept="image/jpeg,image/png,image/webp" hidden></label>${media?.custom ? `<button class="button ghost full" data-action="remove-exercise-media">${tx("Restore built-in image", "Повернути стандартне зображення")}</button>` : ""}</div>`);
  }
  if (modal.type === "workout-exercise-picker") return bottomSheet(workoutExercisePickerMarkup(modal));
  if (modal.type === "progress-exercise-picker") return bottomSheet(progressExercisePickerSheetMarkup());
  if (modal.type === "workout-share") return bottomSheet(workoutShareSheetMarkup());
  if (modal.type === "live-workout-room") return bottomSheet(liveWorkoutRoomMarkup());
  if (modal.type === "friend-detail") return bottomSheet(friendDetailMarkup());
  if (modal.type === "shared-workout-link") return bottomSheet(`<h2>${tx("Workout link ready", "Посилання на тренування готове")}</h2><p class="muted">${tx("Copy this link and send it to a friend. It opens as an editable draft and is not saved automatically.", "Скопіюй це посилання й надішли другу. Воно відкриється як редагований чернетковий план і не збережеться автоматично.")}</p><input id="shared-workout-link" readonly value="${escapeAttr(modal.url)}"><button class="button full" data-action="copy-shared-workout-link">${tx("Copy link", "Копіювати посилання")}</button>`);
  if (modal.type === "smart-alternatives") {
    const current = state.exercises.find(exercise => Number(exercise.id) === Number(modal.currentExerciseId));
    const alternatives = Array.isArray(modal.allowedExerciseIds)
      ? modal.allowedExerciseIds.slice(0, 6)
        .filter(id => Number.isSafeInteger(id) && id > 0)
        .map(id => state.exercises.find(exercise => Number(exercise.id) === id))
        .filter(Boolean)
      : [];
    if (!current || !alternatives.length) return "";
    return bottomSheet(`<div class="smart-alternatives-sheet"><span class="eyebrow">${t("smartCoach")}</span><h2>${tx("Replace with a similar exercise", "Замінити схожою вправою")}</h2><p class="muted">${tx("Options prioritize the same movement pattern and primary muscles, then role, equipment, and your history. The old weight is never copied.", "Варіанти передусім враховують той самий руховий патерн і головні м’язи, а потім роль, обладнання та твою історію. Стара вага ніколи не копіюється.")}</p><p><strong>${escapeHtml(exerciseDisplayName(current))}</strong></p><div class="smart-alternative-list">${alternatives.map(exercise => {
      const analysis = analyzeSmartExercise(exercise);
      return `<article class="smart-alternative-card">${exerciseMediaThumbnail(exercise, { className: "compact" })}<div><strong>${escapeHtml(exerciseDisplayName(exercise))}</strong><small>${escapeHtml(smartMovementLabel(analysis))} · ${escapeHtml(smartRoleLabel(analysis.role))}</small></div><button class="button ghost mini" data-action="apply-smart-alternative" data-block="${modal.blockIndex}" data-replacement-id="${Number(exercise.id)}">${tx("Choose", "Обрати")}</button></article>`;
    }).join("")}</div></div>`);
  }
  if (modal.type === "backup-json") return bottomSheet(`<h2>${modal.diagnostics ? tx("Redacted diagnostics ready", "Знеособлена діагностика готова") : tx("Backup JSON ready", "Резервна копія JSON готова")}</h2><textarea readonly>${escapeHtml(modal.json)}</textarea><div class="actions"><button class="button" data-action="copy-json">${tx("Copy JSON", "Копіювати JSON")}</button><button class="button ghost" data-action="download-json">${tx("Download", "Завантажити")}</button></div><button class="button ghost full" data-action="pdf-report">${t("sharePdf")}</button>`);
  if (modal.type === "rename") return bottomSheet(`<h2>${t("rename")}</h2><input id="rename-name" maxlength="320" value="${escapeAttr(exerciseDisplayName(modal.exercise))}"><button class="button full" data-action="apply-rename" data-id="${modal.exercise.id}">${tx("Save", "Зберегти")}</button>`);
  if (modal.type === "load-profile") {
    const exercise = state.exercises.find(item => Number(item.id) === Number(modal.exerciseId));
    if (!exercise) return "";
    const profile = normalizeExerciseLoadProfile(exercise.loadProfile);
    const direction = profile?.direction || (analyzeSmartExercise(exercise).loadMode === "Assistance" ? "lowerIsHarder" : "higherIsHarder");
    const weights = profile?.allowedWeightsKg.join(", ") || "";
    return bottomSheet(`<h2>${tx("Machine weights", "Ваги тренажера")}</h2><p><strong>${escapeHtml(exerciseDisplayName(exercise))}</strong></p><p class="muted">${tx("Enter only the weights this machine can actually select. Smart Coach will never invent a value between them; saved history stays unchanged.", "Вкажи лише ті ваги, які реально можна вибрати на цьому тренажері. Розумний тренер не вигадуватиме проміжні значення; збережена історія не зміниться.")}</p><label>${tx("Difficulty direction", "Напрям складності")}<select id="load-profile-direction"><option value="higherIsHarder" ${direction === "higherIsHarder" ? "selected" : ""}>${tx("More kg is harder", "Більше кг — складніше")}</option><option value="lowerIsHarder" ${direction === "lowerIsHarder" ? "selected" : ""}>${tx("Less kg is harder (assistance machine)", "Менше кг — складніше (гравітрон)")}</option></select></label><span class="field-caption">${tx("Quick machine-stack presets", "Швидкі шаблони стека")}</span><div class="chip-row"><button class="chip buttonlike" data-action="load-profile-preset" data-step="2.5">2.5 kg</button><button class="chip buttonlike" data-action="load-profile-preset" data-step="5">5 kg</button></div><label>${tx("Selectable weights in kg", "Доступні ваги в кг")}<textarea id="load-profile-weights" maxlength="2048" placeholder="20, 22.5, 25, 27.5">${escapeHtml(weights)}</textarea></label><p class="muted">${tx("Use spaces, commas, semicolons, or new lines; use a dot for decimals. Up to 128 unique values.", "Використовуй пробіли, коми, крапки з комою або нові рядки; для дробів використовуй крапку. До 128 унікальних значень.")}</p><div class="actions vertical"><button class="button full" data-action="save-load-profile" data-id="${exercise.id}">${tx("Save machine weights", "Зберегти ваги тренажера")}</button>${profile ? `<button class="button ghost full" data-action="remove-load-profile" data-id="${exercise.id}">${tx("Use automatic weight steps", "Використовувати автоматичні кроки ваги")}</button>` : ""}</div>`);
  }
  if (modal.type === "history") return bottomSheet(exerciseHistoryMarkup(modal.exercise));
  if (modal.type === "map") return bottomSheet(mappingEditor(modal.name));
  if (modal.type === "edit-set") return bottomSheet(`<h2>${tx("Edit Set", "Редагувати підхід")}</h2><label>${tx("Weight (kg)", "Вага (кг)")}<input id="edit-weight" value="${modal.set.weight || ""}" inputmode="decimal"></label><label>${tx("Reps", "Повтори")}<input id="edit-reps" value="${modal.set.reps || ""}" inputmode="numeric"></label><button class="button full" data-action="apply-edit-set" data-id="${modal.set.id}">${tx("Save", "Зберегти")}</button>`);
  if (modal.type === "confirm-shared-workout-replace") {
    return bottomSheet(`<h2 id="shared-workout-replace-title">${tx("Replace the current draft?", "Замінити поточну чернетку?")}</h2><p class="muted" id="shared-workout-replace-description">${tx("Your current unsaved workout draft will be replaced by the shared plan. Workout history, the active workout, and cloud data will not be changed.", "Поточну незбережену чернетку тренування буде замінено спільним планом. Історія, активне тренування та хмарні дані не зміняться.")}</p>${sharedWorkoutPreviewMarkup(pendingSharedWorkout)}<div class="actions vertical"><button class="button ghost full" data-action="cancel-destructive" data-modal-initial-focus>${tx("Keep current draft", "Залишити поточну чернетку")}</button><button class="button danger full" data-action="confirm-shared-workout-replace">${tx("Replace with shared plan", "Замінити спільним планом")}</button></div>`, "shared-workout-replace-title", "alertdialog", "shared-workout-replace-description");
  }
  if (modal.type === "confirm-social-workout-replace") {
    return bottomSheet(`<h2 id="social-workout-replace-title">${tx("Replace the waiting shared plan?", "Замінити спільний план, що очікує?")}</h2><p class="muted" id="social-workout-replace-description">${tx("The plan already waiting on this device will be replaced by the accepted friend copy. Your workout draft, history, and active workout will stay unchanged.", "План, що вже очікує на цьому пристрої, буде замінено прийнятою копією від друга. Чернетка, історія й активне тренування не зміняться.")}</p>${sharedWorkoutPreviewMarkup(modal.workout)}<div class="actions vertical"><button class="button ghost full" data-action="cancel-destructive" data-modal-initial-focus>${tx("Keep waiting plan", "Залишити план, що очікує")}</button><button class="button danger full" data-action="confirm-social-workout-replace">${tx("Open accepted copy", "Відкрити прийняту копію")}</button></div>`, "social-workout-replace-title", "alertdialog", "social-workout-replace-description");
  }
  if (modal.type === "confirm-discard-active") {
    const counts = activeWorkoutSetCounts(activeWorkout);
    const isLive = liveWorkoutBinding?.localWorkoutId === activeWorkout?.id;
    const description = isLive
      ? tx("The local active draft will be removed and the shared live room will end for both participants. Saved workout history stays unchanged.", "Локальну активну чернетку буде видалено, а спільну live-кімнату завершено для обох учасників. Збережена історія тренувань не зміниться.")
      : tx("The local active draft and its recorded progress will be removed. Workout history and cloud data will not be changed.", "Локальну активну чернетку та записаний у ній прогрес буде видалено. Історія тренувань і хмарні дані не зміняться.");
    return bottomSheet(`<h2 id="discard-active-confirm-title">${tx("Discard active workout?", "Відкинути активне тренування?")}</h2><p id="discard-active-confirm-target"><strong>${counts.completed} / ${counts.total} ${tx("sets recorded", "підходів записано")}</strong></p><p class="muted" id="discard-active-confirm-description">${description}</p><div class="actions vertical"><button class="button ghost full" data-action="cancel-destructive" data-modal-initial-focus>${tx("Keep workout", "Залишити тренування")}</button><button class="button danger full" data-action="confirm-discard-active">${isLive ? tx("End live workout", "Завершити live-тренування") : tx("Discard workout", "Відкинути тренування")}</button></div>`, "discard-active-confirm-title", "alertdialog", "discard-active-confirm-target discard-active-confirm-description");
  }
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
  return `<div class="exercise-history-heading">${exerciseMediaThumbnail(exercise, { className: "progress" })}<h2>${escapeHtml(exerciseDisplayName(exercise))}</h2></div><div class="metric-grid three"><div><span>${tx("Sessions", "Сесії")}</span><strong>${groups.length}</strong></div><div><span>${tx("Sets", "Підходи")}</span><strong>${history.length}</strong></div><div><span>${tx("Volume", "Обсяг")}</span><strong>${Math.round(total)}</strong></div></div>${exerciseMuscleMapCard(exercise)}${groups.length ? groupedExerciseHistory(groups) : `<div class="empty">${tx("No history for this exercise yet.", "Історії для цієї вправи ще немає.")}</div>`}`;
}

function mappingEditor(name) {
  const current = new Set(mappingFor(name));
  return `<h2>${tx("Map", "Мапінг")} "${escapeHtml(exerciseDisplayName(name))}"</h2><div class="mapping-grid">${muscles.map(([id]) => `<button class="chip buttonlike ${current.has(id) ? "selected" : ""}" data-action="toggle-map" data-id="${id}">${escapeHtml(muscleLabel(id))}</button>`).join("")}</div><button class="button full" data-action="save-map" data-name="${escapeAttr(name)}">${tx("Save", "Зберегти")}</button>`;
}

function bindEvents() {
  app.querySelectorAll("[data-route]").forEach(el => el.addEventListener("click", () => goRoot(el.dataset.route)));
  app.querySelectorAll("[data-action]").forEach(el => el.addEventListener("click", async ev => {
    ev.stopPropagation();
    try {
      await handleAction(el.dataset.action, el);
    } catch {
      showToast(tx(
        "This action could not be completed safely. Try again.",
        "Не вдалося безпечно завершити цю дію. Повтори спробу."
      ));
    }
  }));
  app.querySelectorAll('[data-action][role="button"]').forEach(el => {
    el.addEventListener("keydown", activateDataActionFromKeyboard);
  });
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
  const workoutDateInput = app.querySelector("[data-workout-date]");
  if (workoutDateInput) {
    workoutDateInput.addEventListener("change", () => {
      if (!updateWorkoutDraftDate(workoutDateInput.value) && workoutDraft) {
        workoutDateInput.value = localDateInputValue(workoutDraft.startedAt);
      }
    });
  }
  app.querySelectorAll("[data-draft]").forEach(input => input.addEventListener("input", () => {
    if (workoutDraft) workoutDraft[input.dataset.draft] = input.value;
  }));
  const exerciseSearch = app.querySelector("#exercise-search");
  if (exerciseSearch) exerciseSearch.addEventListener("input", () => {
    exerciseSearchQuery = exerciseSearch.value.slice(0, EXERCISE_SEARCH_QUERY_MAX_CHARS);
    render();
    requestAnimationFrame(() => {
      const next = app.querySelector("#exercise-search");
      if (next) {
        next.focus({ preventScroll: true });
        next.setSelectionRange(next.value.length, next.value.length);
      }
    });
  });
  const progressExerciseSearch = app.querySelector("#progress-exercise-search");
  if (progressExerciseSearch) progressExerciseSearch.addEventListener("input", () => {
    progressExerciseSearchQuery = progressExerciseSearch.value.slice(0, EXERCISE_SEARCH_QUERY_MAX_CHARS);
    render();
    requestAnimationFrame(() => {
      const next = app.querySelector("#progress-exercise-search");
      if (next) {
        next.focus({ preventScroll: true });
        next.setSelectionRange(next.value.length, next.value.length);
      }
    });
  });
  const savedWorkoutDetails = [...app.querySelectorAll("details[data-saved-workout-exercise]")];
  savedWorkoutDetails.forEach(details => {
    const summary = details.querySelector("summary");
    summary?.setAttribute("aria-expanded", String(details.open));
    details.addEventListener("toggle", () => {
      if (details.open) {
        savedWorkoutDetails.forEach(other => {
          if (other !== details && other.open) other.open = false;
        });
      }
      savedWorkoutDetails.forEach(item =>
        item.querySelector("summary")?.setAttribute("aria-expanded", String(item.open))
      );
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

function activateDataActionFromKeyboard(event) {
  if (!event || (event.key !== "Enter" && event.key !== " ")) return false;
  if (typeof event.preventDefault === "function") event.preventDefault();
  if (typeof event.currentTarget?.click !== "function") return false;
  event.currentTarget.click();
  return true;
}

function syncTopbarVisibility() {
  app.classList.toggle("topbar-collapsed", (visibleScrollContainer()?.scrollTop || 0) > 24);
}

function destructiveReturnFocus(action, element = null) {
  if (!["delete-exercise", "delete-set", "import-json", "discard-active-workout"].includes(action)) return null;
  const target = { action };
  const id = Number(element?.dataset?.id);
  const sessionId = Number(element?.dataset?.session);
  if (Number.isSafeInteger(id) && id > 0) target.id = id;
  if (Number.isSafeInteger(sessionId) && sessionId > 0) target.sessionId = sessionId;
  return target;
}

function restoreDestructiveFocus(target) {
  if (!target || !["delete-exercise", "delete-set", "import-json", "discard-active-workout"].includes(target.action)) return;
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

async function handleAction(action, el) {
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
  if (action === "sync-cloud-now") return syncCloudNow();
  if (action === "enable-web-push") {
    const enabled = await registerWebPush({ prompt: true });
    if (enabled) showToast(tx("System notifications enabled.", "Системні сповіщення увімкнено."));
    return enabled;
  }
  if (action === "disable-web-push") {
    const serverRevoked = await revokeWebPush();
    showToast(serverRevoked
      ? tx("System notifications disabled on this browser.", "Системні сповіщення вимкнено в цьому браузері.")
      : tx(
          "Notifications are off in this browser. Server cleanup will be retried when possible.",
          "Сповіщення в цьому браузері вимкнено. Очищення на сервері буде повторено за можливості."
        ));
    return true;
  }
  if (action === "unpair-garmin") return unpairGarmin();
  if (action === "refresh-garmin-profile") {
    garminProfileState = { status: "idle", userId: null, devices: [], error: "" };
    return refreshGarminProfileDevices();
  }
  if (action === "refresh-social") return refreshSocialData(true);
  if (action === "refresh-live-workouts") return refreshLiveWorkoutData(true);
  if (action === "copy-friend-code") {
    const code = socialState.dashboard?.self.friendCode;
    if (!SOCIAL_PROFILE_ID_PATTERN.test(code || "") || !navigator.clipboard?.writeText) {
      return showToast(tx("Clipboard access is unavailable.", "Доступ до буфера обміну недоступний."));
    }
    return navigator.clipboard.writeText(code)
      .then(() => showToast(tx("Friend code copied.", "Код друга скопійовано.")))
      .catch(() => showToast(tx("Clipboard write failed.", "Не вдалося записати в буфер обміну.")));
  }
  if (action === "send-friend-request") return sendFriendRequest();
  if (action === "respond-friend") return respondFriendRequest(el);
  if (action === "cancel-friend") return cancelFriendRequest(el);
  if (action === "open-friend") return openFriendDetails(el.dataset.profileId);
  if (action === "remove-friend") return removeFriend(el);
  if (action === "block-friend") return changeFriendBlock(el.dataset.profileId, true);
  if (action === "unblock-friend") return changeFriendBlock(el.dataset.profileId, false);
  if (action === "save-social-privacy") return saveSocialPrivacy(el);
  if (action === "send-workout-invite") return sendWorkoutInvite(el);
  if (action === "send-live-workout-invite") return sendLiveWorkoutInvite(el);
  if (action === "respond-workout-invite") return respondWorkoutInvite(el);
  if (action === "open-accepted-workout-invite") return openAcceptedWorkoutInvite(el);
  if (action === "cancel-workout-invite") return cancelWorkoutInvite(el);
  if (action === "respond-live-invite") return respondLiveWorkoutInvite(el);
  if (action === "open-live-room") return openLiveWorkoutRoom(el.dataset.roomId);
  if (action === "start-live-room") return startLiveWorkoutRoom(el);
  if (action === "attach-live-room") return ensureLiveWorkoutAttached(liveWorkoutState.snapshot, true);
  if (action === "leave-live-room") return closeLiveWorkoutRoom(el, "leave");
  if (action === "cancel-live-room") return closeLiveWorkoutRoom(el, "cancel");
  if (action === "share-workout-link") {
    return modal?.type === "workout-share" ? shareWorkoutLink(modal.url) : undefined;
  }
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
    authNotice = null;
    if (pendingEmailConfirmation) {
      pendingEmailConfirmation = {
        ...pendingEmailConfirmation,
        status: "",
        statusIsError: false
      };
    }
    resetSocialContext();
    resetGarminProfileContext();
    webPushState = { status: "idle", source: null, error: "" };
    if (toastTimer) window.clearTimeout(toastTimer);
    toastTimer = null;
    saveState();
    syncWebPushIfEnabled();
    return render();
  }
  if (action === "backup") { modal = { type: "backup-json", diagnostics: false, json: exportPayload(false) }; return render(); }
  if (action === "open-add") return activeWorkout ? push("active") : push("add");
  if (action === "continue-active-workout") {
    return route().name === "active" ? undefined : push("active");
  }
  if (action === "open-detail") return push("detail", { id: Number(el.dataset.id) });
  if (action === "edit-workout") {
    const sessionId = Number(el.dataset.id);
    if (route().name !== "detail" || route().id !== sessionId || !state.sessions.some(session => session.id === sessionId)) return false;
    workoutDetailEditSessionId = sessionId;
    modal = null;
    return render();
  }
  if (action === "finish-workout-edit") {
    if (!isSavedWorkoutEditMode(Number(el.dataset.id))) return false;
    workoutDetailEditSessionId = null;
    modal = null;
    return render();
  }
  if (action === "delete-session") {
    const sessionId = Number(el.dataset.id);
    return isSavedWorkoutEditMode(sessionId) ? deleteSession(sessionId) : false;
  }
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
  if (action === "open-progress-exercise-picker") {
    if (route().name !== "progress") return false;
    progressExerciseSearchQuery = "";
    modal = { type: "progress-exercise-picker" };
    return render();
  }
  if (action === "clear-progress-exercise-search") { progressExerciseSearchQuery = ""; return render(); }
  if (action === "select-progress-exercise") {
    if (route().name !== "progress" || modal?.type !== "progress-exercise-picker") return false;
    const exerciseId = Number(el.dataset.id);
    if (!Number.isSafeInteger(exerciseId) || exerciseId <= 0 ||
        !state.exercises.some(exercise => Number(exercise.id) === exerciseId)) return false;
    state.progressExerciseId = exerciseId;
    progressExerciseSearchQuery = "";
    modal = null;
    saveState({ queueRemote: false });
    return render();
  }
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
  if (action === "workout-date-today") {
    if (!workoutDraft) return;
    workoutDraft.startedAt = Date.now();
    return render();
  }
  if (action === "smart-effort") {
    const effort = smartNormalizeWorkoutEffort(el.dataset.effort, "");
    if (!SMART_WORKOUT_EFFORTS.has(effort)) return;
    smartPlanStale = Boolean(workoutDraft?.blocks?.some(block => block.smartGenerated === true));
    smartWorkoutEffort = effort;
    smartGeneratedPlan = null;
    return render();
  }
  if (action === "generate-smart") return generateSmartWorkout();
  if (action === "smart-alternatives") return openSmartAlternatives(
    Number(el.dataset.block),
    Number(el.dataset.exerciseId)
  );
  if (action === "apply-smart-alternative") return applySmartAlternative(
    Number(el.dataset.block),
    Number(el.dataset.replacementId)
  );
  if (action === "repeat-latest") { smartGeneratedPlan = null; workoutDraft = createDraft([...state.sessions].sort((a, b) => b.startedAt - a.startedAt)[0]); return render(); }
  if (action === "template-picker") { modal = { type: "template" }; return render(); }
  if (action === "copy-template") { smartGeneratedPlan = null; workoutDraft = createDraft(state.sessions.find(s => s.id === Number(el.dataset.id))); modal = null; nav = [{ name: "workouts" }, { name: "add" }]; replaceNavigationHistory(); return render(); }
  if (action === "share-draft") {
    try {
      return shareWorkoutPlan(sharedWorkoutPlanFromDraft(workoutDraft));
    } catch {
      return showToast(tx("Fill every exercise and set before sharing this workout.", "Заповни кожну вправу й підхід перед поширенням тренування."));
    }
  }
  if (action === "share-session") {
    try {
      return shareWorkoutPlan(sharedWorkoutPlanFromSession(state.sessions.find(session => session.id === Number(el.dataset.id))));
    } catch {
      return showToast(tx("This workout cannot be shared as a template.", "Це тренування не можна поширити як шаблон."));
    }
  }
  if (action === "copy-shared-workout-link") {
    const url = modal?.type === "shared-workout-link" ? modal.url : "";
    if (!url || !navigator.clipboard?.writeText) return showToast(tx("Clipboard access is unavailable.", "Доступ до буфера обміну недоступний."));
    return navigator.clipboard.writeText(url)
      .then(() => showToast(tx("Workout link copied.", "Посилання на тренування скопійовано.")))
      .catch(() => showToast(tx("Clipboard write failed.", "Не вдалося записати в буфер обміну.")));
  }
  if (action === "accept-shared-workout") return applyPendingSharedWorkout(false);
  if (action === "confirm-social-workout-replace") return confirmSocialWorkoutReplacement();
  if (action === "confirm-shared-workout-replace") return applyPendingSharedWorkout(true);
  if (action === "dismiss-shared-workout") return dismissPendingSharedWorkout();
  if (action === "open-exercise-media") {
    const exerciseId = Number(el.dataset.exerciseId);
    const storedExercise = Number.isSafeInteger(exerciseId) && exerciseId > 0
      ? state.exercises.find(item => Number(item.id) === exerciseId)
      : null;
    const blockIndex = Number(el.dataset.block);
    const block = Number.isInteger(blockIndex) && blockIndex >= 0 ? workoutDraft?.blocks[blockIndex] : null;
    const exercise = storedExercise || (block?.exerciseName ? state.exercises.find(item => exercisesMatch(item, block)) || block : null);
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
  if (action === "open-workout-exercise-picker") {
    const target = el.dataset.pickerTarget;
    const sessionId = Number(el.dataset.session);
    if (target === "session" && !isSavedWorkoutEditMode(sessionId)) return false;
    return openWorkoutExercisePicker(target, Number(el.dataset.block), sessionId);
  }
  if (action === "select-workout-exercise") return selectWorkoutExercise(Number(el.dataset.exerciseId));
  if (action === "add-block") {
    if (!workoutDraft) return;
    if (workoutDraft.blocks.length >= window.GymStateContract.LIMITS.exercisesPerSession) {
      return showToast(tx("This workout has reached the exercise limit.", "Досягнуто ліміт вправ у тренуванні."));
    }
    smartGeneratedPlan = null;
    workoutDraft.blocks.unshift({ exerciseName: "", sets: [{ weight: "", reps: "" }] });
    return render();
  }
  if (action === "remove-block") {
    if (!workoutDraft) return;
    smartGeneratedPlan = null;
    if (workoutDraft.blocks.length > 1) workoutDraft.blocks.splice(Number(el.dataset.block), 1);
    else workoutDraft.blocks[0] = { exerciseName: "", sets: [{ weight: "", reps: "" }] };
    return render();
  }
  if (action === "add-set") {
    const block = workoutDraft?.blocks[Number(el.dataset.block)];
    if (!block?.sets) return;
    if (block.sets.length >= window.GymStateContract.LIMITS.setsPerExercise) {
      return showToast(tx("This exercise has reached the set limit.", "Досягнуто ліміт підходів для вправи."));
    }
    block.sets.push({
      weight: "",
      reps: "",
      ...(block.smartGenerated === true ? { smartManualSet: true } : {})
    });
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
  if (action === "start-workout") return startWorkout();
  if (action === "record-active-set") return recordActiveSet(Number(el.dataset.id));
  if (action === "record-all-active-sets") return recordAllActiveSets();
  if (action === "undo-active-set") return undoLatestActiveSet(Number(el.dataset.id));
  if (action === "finish-active-workout") return finishActiveWorkout();
  if (action === "discard-active-workout") {
    return requestDiscardActiveWorkout(destructiveReturnFocus("discard-active-workout", el));
  }
  if (action === "confirm-discard-active") return confirmDiscardActiveWorkout();
  if (action === "save-workout") return saveWorkout();
  if (action === "add-saved-workout-set") return isSavedWorkoutEditMode(Number(el.dataset.session))
    ? addSavedWorkoutSet(Number(el.dataset.session), el.dataset.name)
    : false;
  if (action === "edit-set") return isSavedWorkoutEditMode(Number(el.dataset.session))
    ? openEditSet(Number(el.dataset.id), Number(el.dataset.session))
    : false;
  if (action === "apply-edit-set") return isSavedWorkoutEditMode(Number(modal?.sessionId))
    ? applyEditSet(Number(el.dataset.id))
    : false;
  if (action === "delete-set") {
    const sessionId = Number(el.dataset.session);
    return isSavedWorkoutEditMode(sessionId) ? deleteSet(
      Number(el.dataset.id),
      sessionId,
      destructiveReturnFocus("delete-set", el)
    ) : false;
  }
  if (action === "confirm-delete-set") return isSavedWorkoutEditMode(Number(modal?.intent?.sessionId))
    ? confirmDeleteSet()
    : false;
  if (action === "timer-stop") {
    if (!await stopExerciseRestTimer(el.dataset.key)) {
      showToast(tx("Rest timer could not be stopped.", "Не вдалося зупинити таймер відпочинку."));
    }
    return render();
  }
  if (action === "timer-adjust") {
    if (!await adjustExerciseRestTimer(el.dataset.key, Number(el.dataset.seconds))) {
      showToast(tx("Rest timer could not be adjusted.", "Не вдалося змінити таймер відпочинку."));
    }
    return render();
  }
  if (action === "save-exercise") return saveExercise();
  if (action === "toggle-exercise-favorite") return toggleExerciseFavorite(Number(el.dataset.id));
  if (action === "rename-exercise") { modal = { type: "rename", exercise: state.exercises.find(ex => ex.id === Number(el.dataset.id)) }; return render(); }
  if (action === "apply-rename") return applyRename(Number(el.dataset.id));
  if (action === "configure-load-profile") {
    const exerciseId = Number(el.dataset.id);
    if (!state.exercises.some(exercise => Number(exercise.id) === exerciseId)) return;
    modal = { type: "load-profile", exerciseId };
    return render();
  }
  if (action === "load-profile-preset") return applyLoadProfilePreset(Number(el.dataset.step));
  if (action === "save-load-profile") return saveExerciseLoadProfile(Number(el.dataset.id));
  if (action === "remove-load-profile") return removeExerciseLoadProfile(Number(el.dataset.id));
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
  return [
    "confirm-delete-exercise",
    "confirm-delete-set",
    "confirm-import",
    "confirm-discard-active",
    "confirm-social-workout-replace",
    "confirm-shared-workout-replace"
  ].includes(value?.type);
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
      delete block.smartGenerated;
      delete block.smartEffort;
      delete block.smartHardSlot;
      delete block.smartRecoverySteps;
      delete block.smartSetCap;
      smartGeneratedPlan = null;
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
  smartPlanStale = Boolean(workoutDraft?.blocks?.some(block => block.smartGenerated === true));
  smartGeneratedPlan = null;
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
  const plan = buildSmartWorkoutPlan(smartWorkoutEffort);
  if (!workoutDraft) return;
  smartGeneratedPlan = plan;
  smartPlanStale = false;
  workoutDraft.blocks = plan.exercises.map(({ name, catalogKey, recommendation, hardSlot }) => ({
    exerciseName: name,
    ...(catalogKey ? { catalogKey } : {}),
    sets: recommendation.sets.map(set => ({ weight: set.weight ?? "", reps: set.reps })),
    smartGenerated: true,
    smartEffort: plan.appliedEffort,
    smartHardSlot: hardSlot === true,
    smartRecoverySteps: plan.recoverySteps,
    smartSetCap: recommendation.sets.length
  }));
  showToast(`${tx("Smart workout generated", "Розумне тренування згенеровано")}: ${smartFocusLabel(plan.focus)} ${plan.variant} · ${smartWorkoutEffortLabel(plan.appliedEffort)}.`);
  render();
}

function buildSmartWorkoutPlan(requestedEffort = smartWorkoutEffort) {
  const nowMillis = Date.now();
  const history = smartUsableHistory(allSets(), nowMillis);
  const focus = chooseWorkoutFocus(history);
  const targetMuscles = targetMusclesForFocus(focus);
  let effort = resolveSmartWorkoutEffort(requestedEffort, history, targetMuscles, nowMillis);
  const variant = smartWorkoutVariant(focus, history);
  let sessionSetBudget = smartSessionSetBudget(effort.appliedEffort);
  let targetExerciseCount = smartTargetExerciseCount(effort.appliedEffort, focus);
  const historyByExercise = new Map();
  history.forEach(set => {
    const key = exerciseMatchKey(set);
    const items = historyByExercise.get(key) || [];
    items.push(set);
    historyByExercise.set(key, items);
  });
  const recentSessionIds = recentWorkoutSessionIds(history, 3);
  const candidates = state.exercises
    .filter(exercise => resolvedExerciseCatalogKey(exercise) !== "warm_up")
    .map(exercise => {
      const analysis = analyzeSmartExercise(exercise);
      const exerciseHistory = historyByExercise.get(analysis.identityKey) || [];
      const latest = exerciseHistory.reduce((max, set) => Math.max(max, set.session.startedAt), 0);
      const daysSince = latest ? daysBetween(latest, Date.now()) : 7;
      const sessionCount = new Set(exerciseHistory.map(set => set.session.id)).size;
      const recentExercisePenalty = new Set(exerciseHistory.filter(set => recentSessionIds.has(set.session.id)).map(set => set.session.id)).size * 8;
      const sameWeekExercisePenalty = exerciseHistory.some(set => daysBetween(set.session.startedAt, Date.now()) <= 6) ? 10 : 0;
      const focusScore = focus === "FullBody" ? 44 : isCandidateForFocus(analysis, focus) ? 86 : analysis.category === "FullBody" ? 32 : -60;
      const muscleMatchScore = analysis.muscles.filter(muscle => targetMuscles.has(muscle)).length * 9;
      const dueScore = Math.min(daysSince, 14);
      const continuityScore = Math.min(sessionCount, 4) * 5;
      const favoriteScore = exercise.favorite === true ? 5 : 0;
      const programmingScore = smartProgrammingPreferenceScore(analysis, sessionCount);
      return {
        exercise,
        analysis,
        sessionCount,
        score: focusScore + muscleMatchScore + dueScore + continuityScore + favoriteScore +
          smartVariantPreferenceScore(analysis, focus, variant) + programmingScore -
          recentExercisePenalty - sameWeekExercisePenalty
      };
    });
  const canonicalCandidates = [...candidates.reduce((groups, candidate) => {
    const current = groups.get(candidate.analysis.identityKey);
    if (!current || candidate.score > current.score ||
        (candidate.score === current.score && candidate.exercise.name.localeCompare(current.exercise.name) < 0)) {
      groups.set(candidate.analysis.identityKey, candidate);
    }
    return groups;
  }, new Map()).values()];
  const weeklyEffectiveSets = smartWeeklyEffectiveSets(history, nowMillis);
  const selectExercises = () => selectBalancedSmartExercises(
      canonicalCandidates,
      focus,
      targetMuscles,
      targetExerciseCount,
      history,
      variant,
      weeklyEffectiveSets,
      state.profile,
      effort.appliedEffort
    );
  let selected = selectExercises();
  const isEligibleHardCandidate = candidate => smartIsCompound(candidate.analysis) &&
    candidate.sessionCount >= 2;
  if (effort.appliedEffort === "Hard" && !selected.some(isEligibleHardCandidate)) {
    effort = {
      ...effort,
      appliedEffort: "Standard",
      adjustment: tx(
        "Hard was adjusted to Standard because no selected compound exercise has two completed exercise-specific sessions.",
        "Важке тренування змінено на звичайне, бо жодна обрана базова вправа ще не має двох завершених тренувань саме з цією вправою."
      )
    };
    sessionSetBudget = smartSessionSetBudget(effort.appliedEffort);
    targetExerciseCount = smartTargetExerciseCount(effort.appliedEffort, focus);
    selected = selectExercises();
  }
  let hardSetSlotsRemaining = Math.min(2, Math.max(0, sessionSetBudget - selected.length * 3));
  let remainingSetBudget = sessionSetBudget;
  const exercises = selected.map((candidate, index) => {
    const hardSlot = effort.appliedEffort === "Hard" && smartIsCompound(candidate.analysis) &&
      candidate.sessionCount >= 2 && hardSetSlotsRemaining > 0;
    if (hardSlot) hardSetSlotsRemaining -= 1;
    const recommendation = smartRecommendation(candidate.exercise, {
      appliedEffort: effort.appliedEffort,
      hardSlot,
      recoverySteps: effort.recoverySteps
    });
    const minimumForRemainingExercises = Math.max(0, selected.length - index - 1) * 3;
    const allowedSets = clamp(
      remainingSetBudget - minimumForRemainingExercises,
      3,
      recommendation.sets.length
    );
    recommendation.sets = recommendation.sets.slice(0, allowedSets);
    remainingSetBudget -= recommendation.sets.length;
    return {
      name: candidate.exercise.name,
      ...(persistedExerciseCatalogKey(candidate.exercise) ? { catalogKey: persistedExerciseCatalogKey(candidate.exercise) } : {}),
      hardSlot,
      recommendation
    };
  });
  return {
    focus,
    variant,
    requestedEffort: effort.requestedEffort,
    appliedEffort: effort.appliedEffort,
    adjustment: effort.adjustment,
    recoverySteps: effort.recoverySteps,
    setBudget: sessionSetBudget,
    exercises
  };
}

function resolveSmartWorkoutEffort(requestedEffort, history, targetMuscles, nowMillis = Date.now()) {
  const requested = smartNormalizeWorkoutEffort(requestedEffort, "Auto");
  const sessions = sessionGroupsByDate(history);
  const targetRecoveryRatio = smartRecentTargetMuscleRatio(history, targetMuscles, nowMillis);
  const longBreak = Boolean(sessions.length && daysBetween(sessions[0].date, nowMillis) >= SMART_COMEBACK_BREAK_DAYS);
  const underExperienced = sessions.length < 2;
  const recoverySteps = targetRecoveryRatio >= 0.75 ? 2 : 1;
  if (requested === "Auto") {
    if (targetRecoveryRatio >= 0.5) {
      return {
        requestedEffort: requested,
        appliedEffort: "Recovery",
        recoverySteps,
        adjustment: tx("Auto selected Recovery because at least half of the target muscles were trained in the last 0–1 day.", "Авто обрав відновлювальне тренування, бо щонайменше половина цільових м’язів працювала протягом останніх 0–1 днів.")
      };
    }
    return {
      requestedEffort: requested,
      appliedEffort: "Standard",
      recoverySteps,
      adjustment: tx("Auto selected Standard after checking recent target-muscle recovery. Auto never promotes a session to Hard.", "Авто обрав звичайне тренування після перевірки відновлення цільових м’язів. Авто ніколи самостійно не підвищує тренування до важкого.")
    };
  }
  if (requested === "Hard" && (underExperienced || longBreak || targetRecoveryRatio >= 0.5)) {
    const adjustment = underExperienced
      ? tx("Hard was adjusted to Standard because fewer than two sessions are completed.", "Важке тренування змінено на звичайне, бо завершено менше двох тренувань.")
      : longBreak
        ? tx("Hard was adjusted to Standard because of a long training break.", "Важке тренування змінено на звичайне через тривалу перерву в тренуваннях.")
        : tx("Hard was adjusted to Standard because target muscles are still recovering.", "Важке тренування змінено на звичайне, бо цільові м’язи ще відновлюються.");
    return {
      requestedEffort: requested,
      appliedEffort: "Standard",
      recoverySteps,
      adjustment
    };
  }
  return {
    requestedEffort: requested,
    appliedEffort: requested,
    recoverySteps,
    adjustment: requested === "Recovery"
      ? tx("Recovery keeps the session controlled and reduces working load.", "Відновлювальне тренування зберігає контроль і зменшує робоче навантаження.")
      : requested === "Hard"
        ? tx("Hard is applied only to the first one or two compound exercises; other work stays controlled.", "Важкий режим застосовано лише до перших однієї-двох базових вправ; решта роботи залишається контрольованою.")
        : tx("Standard balances productive work with recoverability.", "Звичайний режим балансує продуктивну роботу та відновлення.")
  };
}

function smartRecentTargetMuscleRatio(history, targetMuscles, nowMillis = Date.now()) {
  const targets = [...targetMuscles].filter(muscle => smartKnownMuscleIds.has(muscle));
  if (!targets.length) return 0;
  const lastTrained = lastTrainedBySmartMuscle(history);
  const recentlyTrained = targets.filter(muscle => {
    const trainedAt = Number(lastTrained.get(muscle));
    return Number.isFinite(trainedAt) && trainedAt > 0 && daysBetween(trainedAt, nowMillis) <= 1;
  }).length;
  return recentlyTrained / targets.length;
}

function smartTargetExerciseCount(appliedEffort = "Standard", focus = null) {
  const reservedHardSets = appliedEffort === "Hard" ? 1 : 0;
  return clamp(Math.floor((smartSessionSetBudget(appliedEffort) - reservedHardSets) / 3), 4, 8);
}

function smartSessionSetBudget(appliedEffort = "Standard", profile = state.profile) {
  const days = clamp(Number(profile?.days) || 3, 2, 6);
  const frequencyBase = days === 2 ? 20 : days === 3 ? 18 : days === 4 ? 16 : days === 5 ? 15 : 14;
  const goalAdjustment = profile?.goal === "Muscle Gain" ? 2
    : profile?.goal === "Aesthetic Cut" ? -2
      : profile?.goal === "Strength" ? -1 : 0;
  const calorieAdjustment = profile?.calories === "Deficit" ? -2
    : profile?.calories === "Surplus" ? 2 : 0;
  const effortAdjustment = appliedEffort === "Recovery" ? -3 : appliedEffort === "Hard" ? 1 : 0;
  return clamp(
    frequencyBase + goalAdjustment + calorieAdjustment + effortAdjustment,
    appliedEffort === "Hard" ? 13 : 12,
    24
  );
}

function smartPrimaryMuscles(exercise) {
  const contributions = smartKnownMuscleContributions(exercise);
  const peak = Math.max(0, ...contributions.map(item => item.weight));
  return new Set(contributions
    .filter(item => item.weight >= Math.max(0.5, peak * 0.8))
    .map(item => item.muscleId));
}

function smartEquipmentFamily(exercise, analysis = analyzeSmartExercise(exercise)) {
  if (analysis.loadMode === "Assistance") return "assistance";
  if (analysis.loadMode === "Bodyweight") return "bodyweight";
  const key = resolvedExerciseCatalogKey(exercise) || "";
  const reviewedFamily = ({
    machine_lateral_raise: "machine",
    plate_loaded_row: "machine",
    bulgarian_split_squat: "dumbbell",
    assisted_pull_up: "assistance",
    assisted_dip: "assistance",
    band_assisted_pull_up: "band",
    chest_fly_machine: "machine",
    leg_press: "machine",
    leg_extension: "machine",
    lying_leg_curl: "machine",
    seated_leg_curl: "machine",
    hip_adduction: "machine",
    hip_abduction: "machine"
  })[key];
  if (reviewedFamily) return reviewedFamily;
  if (/(machine|leg_press|leg_extension|leg_curl|hip_adduction|hip_abduction|plate_loaded|preacher)/.test(key)) return "machine";
  if (/(dumbbell|lateral_raise|hammer_curl|weighted_side_bend)/.test(key)) return "dumbbell";
  if (/(barbell|bench_press|squat|deadlift|french_press)/.test(key)) return "barbell";
  if (/(cable|pulldown|pushdown|face_pull|straight_arm)/.test(key)) return "cable";
  return "other";
}

function smartExerciseAlternatives(currentExercise, selectedExercises = [], limit = 6) {
  const current = state.exercises.find(exercise => exercisesMatch(exercise, currentExercise));
  if (!current) return [];
  const currentAnalysis = analyzeSmartExercise(current);
  const currentPrimary = smartPrimaryMuscles(current);
  const currentEquipment = smartEquipmentFamily(current, currentAnalysis);
  const currentIsTrunk = smartIsTrunkCandidate({ exercise: current, analysis: currentAnalysis });
  const excludedKeys = new Set(selectedExercises.map(exercise => exerciseMatchKey(exercise)));
  excludedKeys.add(exerciseMatchKey(current));
  const history = smartUsableHistory();
  const sessionCounts = new Map();
  history.forEach(set => {
    const key = exerciseMatchKey(set);
    const sessions = sessionCounts.get(key) || new Set();
    sessions.add(set.session.id);
    sessionCounts.set(key, sessions);
  });
  const scoreCandidate = exercise => {
    const analysis = analyzeSmartExercise(exercise);
    const sharedPatterns = [...analysis.patterns].filter(pattern => currentAnalysis.patterns.has(pattern)).length;
    const primary = smartPrimaryMuscles(exercise);
    const primaryOverlap = [...primary].filter(muscle => currentPrimary.has(muscle)).length;
    const primaryUnion = new Set([...primary, ...currentPrimary]).size || 1;
    const sameRole = analysis.role === currentAnalysis.role;
    const sameEquipment = smartEquipmentFamily(exercise, analysis) === currentEquipment;
    const familiarity = Math.min(sessionCounts.get(exerciseMatchKey(exercise))?.size || 0, 4) * 3;
    return {
      exercise,
      analysis,
      sharedPatterns,
      primaryOverlap,
      score: sharedPatterns * 100 + primaryOverlap / primaryUnion * 80 +
        (sameRole ? 30 : 0) + (sameEquipment ? 12 : 0) + familiarity +
        (exercise.favorite === true ? 5 : 0)
    };
  };
  const canonical = [...state.exercises.reduce((groups, exercise) => {
    const key = exerciseMatchKey(exercise);
    if (!key || groups.has(key)) return groups;
    groups.set(key, exercise);
    return groups;
  }, new Map()).values()];
  return canonical
    .filter(exercise => !excludedKeys.has(exerciseMatchKey(exercise)) &&
      resolvedExerciseCatalogKey(exercise) !== "warm_up")
    .map(scoreCandidate)
    .filter(candidate => candidate.sharedPatterns > 0 && candidate.primaryOverlap > 0 &&
      smartIsTrunkCandidate(candidate) === currentIsTrunk)
    .sort((left, right) => right.score - left.score ||
      left.exercise.name.localeCompare(right.exercise.name))
    .slice(0, clamp(Number.parseInt(limit, 10) || 6, 1, 6));
}

function openSmartAlternatives(blockIndex, exerciseId) {
  if (!Number.isInteger(blockIndex) || blockIndex < 0 || !Number.isSafeInteger(exerciseId) || exerciseId <= 0) return;
  const block = workoutDraft?.blocks?.[blockIndex];
  const current = state.exercises.find(exercise => Number(exercise.id) === exerciseId);
  if (!block || !current || block.smartGenerated !== true || !exercisesMatch(block, current)) return;
  const selected = workoutDraft.blocks
    .filter((_, index) => index !== blockIndex)
    .map(item => state.exercises.find(exercise => exercisesMatch(exercise, item)) || item);
  const alternatives = smartExerciseAlternatives(current, selected, 6);
  if (!alternatives.length) {
    return showToast(tx("No safe similar exercise is available in your library yet.", "У твоєму каталозі поки немає безпечної схожої вправи."));
  }
  modal = {
    type: "smart-alternatives",
    blockIndex,
    currentExerciseId: Number(current.id),
    currentIdentity: exerciseMatchKey(current),
    draftStartedAt: Number(workoutDraft.startedAt),
    allowedExerciseIds: alternatives.map(candidate => Number(candidate.exercise.id))
  };
  render();
}

function applySmartAlternative(blockIndex, replacementId) {
  if (modal?.type !== "smart-alternatives" || !Number.isInteger(blockIndex) || blockIndex < 0 ||
      !Number.isSafeInteger(replacementId) || replacementId <= 0 || modal.blockIndex !== blockIndex ||
      Number(workoutDraft?.startedAt) !== modal.draftStartedAt || !Array.isArray(modal.allowedExerciseIds) ||
      modal.allowedExerciseIds.length > 6 || !modal.allowedExerciseIds.includes(replacementId)) return;
  const block = workoutDraft?.blocks?.[blockIndex];
  const current = state.exercises.find(exercise => Number(exercise.id) === Number(modal.currentExerciseId));
  const replacement = state.exercises.find(exercise => Number(exercise.id) === replacementId);
  if (!block || !current || !replacement || block.smartGenerated !== true ||
      exerciseMatchKey(block) !== modal.currentIdentity || !exercisesMatch(block, current)) return;
  const selected = workoutDraft.blocks
    .filter((_, index) => index !== blockIndex)
    .map(item => state.exercises.find(exercise => exercisesMatch(exercise, item)) || item);
  const stillAllowed = smartExerciseAlternatives(current, selected, 6)
    .some(candidate => Number(candidate.exercise.id) === replacementId);
  if (!stillAllowed) return;
  const replacementAnalysis = analyzeSmartExercise(replacement);
  block.exerciseName = replacement.name;
  const catalogKey = persistedExerciseCatalogKey(replacement);
  if (catalogKey) block.catalogKey = catalogKey;
  else delete block.catalogKey;
  block.smartHardSlot = block.smartHardSlot === true && smartIsCompound(replacementAnalysis) &&
    smartExerciseSessionHistory(replacement).length >= 2;
  const cappedRecommendation = smartRecommendationForBlock(block);
  block.sets = cappedRecommendation.sets.map(set => ({ weight: set.weight ?? "", reps: set.reps }));
  modal = null;
  showToast(tx("Exercise replaced and its recommendation recalculated.", "Вправу замінено, а рекомендацію перераховано."));
  render();
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
  const value = String(identity || "");
  for (let index = 0; index < value.length; index += 1) {
    hash = (Math.imul(hash, 31) + value.charCodeAt(index)) >>> 0;
  }
  return modulus > 0 ? hash % modulus : 0;
}

function chooseWorkoutFocus(history = smartUsableHistory()) {
  if (Number(state.profile.days) <= 2) return "FullBody";
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
    const latestRecognizedFocus = sessions
      .map(session => dominantSmartFocus(session.sets))
      .find(sessionFocus => isUpperFocus(sessionFocus) || isLowerFocus(sessionFocus));
    if (isLowerFocus(latestRecognizedFocus)) return "Upper";
    if (isUpperFocus(latestRecognizedFocus)) return "Lower";
    const upperCount = thisWeekSessions.filter(session => isUpperFocus(dominantSmartFocus(session.sets))).length;
    const lowerCount = thisWeekSessions.filter(session => isLowerFocus(dominantSmartFocus(session.sets))).length;
    return lowerCount < upperCount ? "Lower" : "Upper";
  }
  if (state.profile.split === "Push Pull Legs") {
    const latestKnownFocus = sessions
      .map(session => dominantSmartFocus(session.sets))
      .find(sessionFocus => ["Push", "Pull", "Legs", "Lower"].includes(sessionFocus));
    if (latestKnownFocus === "Push") return "Pull";
    if (latestKnownFocus === "Pull") return "Legs";
    if (latestKnownFocus === "Legs" || latestKnownFocus === "Lower") return "Push";
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
const smartKnownMuscleIds = new Set(muscles.map(([id]) => id));
const smartMajorWeeklyMuscles = new Set(["chest", "shoulders", "lats", "upperBack", "quads", "hamstrings", "glutes"]);
const smartSecondaryWeeklyMuscles = new Set(["biceps", "triceps", "calves", "abs"]);
const smartCompoundPatterns = new Set([
  "Squat", "LegPress", "Hinge", "HorizontalPress", "VerticalPress", "HorizontalPull", "VerticalPull"
]);

// Programming metadata is deliberately keyed by the reviewed built-in catalog identity.
// Imported/custom exercise names never get to supply these trusted flags themselves.
const smartBuiltInProgramming = new Map([
  ["bench_press", { category: "Push", role: "Primary", loadMode: "Standard", patterns: ["HorizontalPress"] }],
  ["dumbbell_bench_press", { category: "Push", role: "Secondary", loadMode: "Standard", patterns: ["HorizontalPress"] }],
  ["incline_dumbbell_press", { category: "Push", role: "Secondary", loadMode: "Standard", patterns: ["HorizontalPress"] }],
  ["incline_bench_press", { category: "Push", role: "Secondary", loadMode: "Standard", patterns: ["HorizontalPress"] }],
  ["chest_fly_machine", { category: "Push", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["push_up", { category: "Push", role: "Secondary", loadMode: "Bodyweight", patterns: ["HorizontalPress"] }],
  ["dips", { category: "Push", role: "Secondary", loadMode: "Bodyweight", patterns: ["HorizontalPress"] }],
  ["assisted_dip", { category: "Push", role: "Secondary", loadMode: "Assistance", patterns: ["HorizontalPress"] }],
  ["pull_up", { category: "Pull", role: "Secondary", loadMode: "Bodyweight", patterns: ["VerticalPull"] }],
  ["assisted_pull_up", { category: "Pull", role: "Secondary", loadMode: "Assistance", patterns: ["VerticalPull"] }],
  ["band_assisted_pull_up", { category: "Pull", role: "Secondary", loadMode: "Bodyweight", patterns: ["VerticalPull"] }],
  ["lat_pulldown", { category: "Pull", role: "Secondary", loadMode: "Standard", patterns: ["VerticalPull"] }],
  ["straight_arm_pulldown", { category: "Pull", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["barbell_row", { category: "Pull", role: "Primary", loadMode: "Standard", patterns: ["HorizontalPull"] }],
  ["seated_cable_row", { category: "Pull", role: "Secondary", loadMode: "Standard", patterns: ["HorizontalPull"] }],
  ["plate_loaded_row", { category: "Pull", role: "Secondary", loadMode: "Standard", patterns: ["HorizontalPull"] }],
  ["face_pull", { category: "Pull", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["squat", { category: "Legs", role: "Primary", loadMode: "Standard", patterns: ["Squat"] }],
  ["leg_press", { category: "Legs", role: "Secondary", loadMode: "Standard", patterns: ["LegPress"] }],
  ["bulgarian_split_squat", { category: "Legs", role: "Secondary", loadMode: "Standard", patterns: ["Squat"] }],
  ["lunge", { category: "Legs", role: "Secondary", loadMode: "Standard", patterns: ["Squat"] }],
  ["romanian_deadlift", { category: "Legs", role: "Primary", loadMode: "Standard", patterns: ["Hinge"] }],
  ["deadlift", { category: "Legs", role: "Primary", loadMode: "Standard", patterns: ["Hinge"] }],
  ["hip_thrust", { category: "Legs", role: "Secondary", loadMode: "Standard", patterns: ["Hinge"] }],
  ["leg_extension", { category: "Legs", role: "Isolation", loadMode: "Standard", patterns: ["KneeExtension"] }],
  ["lying_leg_curl", { category: "Legs", role: "Isolation", loadMode: "Standard", patterns: ["KneeFlexion"] }],
  ["seated_leg_curl", { category: "Legs", role: "Isolation", loadMode: "Standard", patterns: ["KneeFlexion"] }],
  ["hip_adduction", { category: "Legs", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["hip_abduction", { category: "Legs", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["calf_raise", { category: "Legs", role: "Isolation", loadMode: "Standard", patterns: ["Calf"] }],
  ["shoulder_press", { category: "Push", role: "Primary", loadMode: "Standard", patterns: ["VerticalPress"] }],
  ["lateral_raise", { category: "Push", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["machine_lateral_raise", { category: "Push", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["rear_delt_fly", { category: "Pull", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["upright_row", { category: "Pull", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["biceps_curl", { category: "Pull", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["barbell_curl", { category: "Pull", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["seated_dumbbell_curl", { category: "Pull", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["hammer_curl", { category: "Pull", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["cable_curl", { category: "Pull", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["preacher_curl", { category: "Pull", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["triceps_pushdown", { category: "Push", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["v_bar_pushdown", { category: "Push", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["overhead_dumbbell_triceps_extension", { category: "Push", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["french_press", { category: "Push", role: "Isolation", loadMode: "Standard", patterns: ["Accessory"] }],
  ["hyperextension", { category: "Legs", role: "Isolation", loadMode: "Standard", patterns: ["Hinge"] }],
  ["side_hyperextension", { category: "FullBody", role: "Core", loadMode: "Standard", patterns: ["Core"] }],
  ["plank", { category: "FullBody", role: "Core", loadMode: "Bodyweight", patterns: ["Core"] }],
  ["weighted_crunch", { category: "FullBody", role: "Core", loadMode: "Standard", patterns: ["Core"] }],
  ["hanging_leg_raise", { category: "FullBody", role: "Core", loadMode: "Bodyweight", patterns: ["Core"] }],
  ["plate_twist", { category: "FullBody", role: "Core", loadMode: "Standard", patterns: ["Core"] }],
  ["weighted_side_bend", { category: "FullBody", role: "Core", loadMode: "Standard", patterns: ["Core"] }],
  ["warm_up", { category: "FullBody", role: "Warmup", loadMode: "None", patterns: ["Accessory"] }]
]);

function smartIsCompound(analysis) {
  if (analysis?.role) return analysis.role === "Primary" || analysis.role === "Secondary";
  return Boolean(analysis?.patterns && [...analysis.patterns].some(pattern => smartCompoundPatterns.has(pattern)));
}

function smartProgrammingPreferenceScore(analysis, sessionCount) {
  const compound = smartIsCompound(analysis);
  let score = state.profile.goal === "Strength"
    ? (compound ? 24 : -8)
    : state.profile.goal === "Muscle Gain"
      ? (compound ? 14 : 6)
      : state.profile.goal === "Aesthetic Cut"
        ? (compound ? 8 : 2)
        : (compound ? 10 : 4);
  if (state.profile.calories === "Deficit") {
    score += sessionCount > 0 ? 10 : -6;
  } else if (state.profile.calories === "Surplus" && compound) {
    score += 4;
  }
  return score;
}

function analyzeSmartExercise(exercise) {
  const definition = builtInExerciseFor(exercise);
  const analysisName = definition?.names.en || exerciseRawName(exercise);
  const normalized = normalizeExerciseName(analysisName);
  const has = (...tokens) => tokens.some(token => normalized.includes(token));
  const muscles = new Set(contributionFor(exercise).map(item => item.muscleId));
  const builtInProgramming = definition ? smartBuiltInProgramming.get(definition.key) : null;
  if (builtInProgramming) {
    return {
      identityKey: exerciseMatchKey(exercise),
      category: builtInProgramming.category,
      muscles: [...muscles],
      patterns: new Set(builtInProgramming.patterns),
      role: builtInProgramming.role,
      loadMode: builtInProgramming.loadMode
    };
  }
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

  return {
    identityKey: exerciseMatchKey(exercise),
    category,
    muscles: [...muscles],
    patterns,
    role: [...patterns].some(pattern => smartCompoundPatterns.has(pattern)) ? "Secondary" : "Isolation",
    loadMode: "Standard"
  };
}

function smartWeeklyMuscleTarget(muscleId, profile = state.profile) {
  const base = profile?.goal === "Muscle Gain" ? 10 : 8;
  const calorieAdjustment = profile?.calories === "Deficit" ? -1 : profile?.calories === "Surplus" ? 1 : 0;
  const multiplier = smartMajorWeeklyMuscles.has(muscleId) ? 1 : smartSecondaryWeeklyMuscles.has(muscleId) ? 0.75 : 0.5;
  return clamp((base + calorieAdjustment) * multiplier, 4, 12);
}

function smartKnownMuscleContributions(exercise) {
  const bounded = new Map();
  contributionFor(exercise).forEach(item => {
    const weight = Number(item?.weight);
    if (!smartKnownMuscleIds.has(item?.muscleId) || !Number.isFinite(weight)) return;
    bounded.set(item.muscleId, Math.max(bounded.get(item.muscleId) || 0, clamp(weight, 0, 1)));
  });
  return [...bounded].filter(([, weight]) => weight > 0).map(([muscleId, weight]) => ({ muscleId, weight }));
}

function smartWeeklyEffectiveSets(history, nowMillis = Date.now()) {
  const result = new Map(muscles.map(([id]) => [id, 0]));
  const windowStart = nowMillis - 7 * 24 * 60 * 60 * 1000;
  history.forEach(set => {
    const completedAt = Number(set?.session?.startedAt);
    if (!smartSetUsable(set) || !Number.isFinite(completedAt) || completedAt < windowStart || completedAt > nowMillis) return;
    smartKnownMuscleContributions(set).forEach(({ muscleId, weight }) => {
      result.set(muscleId, (result.get(muscleId) || 0) + weight);
    });
  });
  return result;
}

function smartWeeklyCoverageGain(candidate, selected, completedEffectiveSets, profile = state.profile, appliedEffort = "Standard") {
  const projected = new Map(completedEffectiveSets);
  selected.forEach(item => {
    const plannedSets = smartTargetSetCount(item.analysis, { appliedEffort });
    smartKnownMuscleContributions(item.exercise).forEach(({ muscleId, weight }) => {
      projected.set(muscleId, (projected.get(muscleId) || 0) + plannedSets * weight);
    });
  });
  const plannedSets = smartTargetSetCount(candidate.analysis, { appliedEffort });
  const contributions = smartKnownMuscleContributions(candidate.exercise);
  return contributions.reduce((sum, { muscleId, weight }) => {
    const deficit = Math.max(smartWeeklyMuscleTarget(muscleId, profile) - (projected.get(muscleId) || 0), 0);
    return sum + Math.min(deficit, plannedSets * weight);
  }, 0);
}

function smartWeeklyCoverageScore(candidate, selected, completedEffectiveSets, profile = state.profile, appliedEffort = "Standard") {
  const contributions = smartKnownMuscleContributions(candidate.exercise);
  const coverageGain = smartWeeklyCoverageGain(
    candidate,
    selected,
    completedEffectiveSets,
    profile,
    appliedEffort
  );
  const saturatedPenalty = coverageGain === 0
    ? 12 * contributions.reduce((sum, item) => sum + item.weight, 0)
    : 0;
  return coverageGain * 18 - saturatedPenalty;
}

function selectBalancedSmartExercises(candidates, focus, targetMuscles, targetExerciseCount, history, variant, weeklyEffectiveSets = smartWeeklyEffectiveSets(history), profile = state.profile, appliedEffort = "Standard") {
  const selected = [];
  const coveredMuscles = new Set();
  const lastTrained = lastTrainedBySmartMuscle(history);
  const isTrunkCandidate = smartIsTrunkCandidate;
  let remaining = candidates.filter(candidate =>
    candidate.analysis.role !== "Warmup" &&
    resolvedExerciseCatalogKey(candidate.exercise) !== "warm_up" &&
    (isCandidateForFocus(candidate.analysis, focus) || isTrunkCandidate(candidate))
  );
  if (!remaining.length && focus !== "Lower" && focus !== "Legs") remaining = [...candidates];

  const takeBestPattern = patterns => {
    const best = remaining
      .filter(candidate => !isTrunkCandidate(candidate) &&
        [...candidate.analysis.patterns].some(pattern => patterns.has(pattern)))
      .sort((a, b) => {
        const priority = candidate => candidate.analysis.role === "Primary" ? 28 : smartIsCompound(candidate.analysis) ? 14 : 0;
        return (b.score + patternMatchCount(b, patterns) * 35 + priority(b) +
          smartWeeklyCoverageScore(b, selected, weeklyEffectiveSets, profile, appliedEffort)) -
          (a.score + patternMatchCount(a, patterns) * 35 + priority(a) +
          smartWeeklyCoverageScore(a, selected, weeklyEffectiveSets, profile, appliedEffort)) ||
          a.exercise.name.localeCompare(b.exercise.name);
      })[0];
    if (!best) return;
    selected.push(best);
    best.analysis.muscles.forEach(muscle => coveredMuscles.add(muscle));
    remaining = remaining.filter(candidate => candidate.exercise.id !== best.exercise.id);
  };

  if (focus === "Lower" || focus === "Legs") {
    takeBestPattern(smartVariantPatterns(focus, variant));
    takeBestPattern(variant === "A" ? new Set(["Hinge", "KneeFlexion"]) : new Set(["Squat", "LegPress"]));
  }

  if (focus === "Upper") {
    takeBestPattern(new Set(["HorizontalPress"]));
    takeBestPattern(new Set(["VerticalPress"]));
    takeBestPattern(new Set(["HorizontalPull"]));
    takeBestPattern(new Set(["VerticalPull"]));
  } else if (focus === "Push") {
    takeBestPattern(new Set(["HorizontalPress"]));
    takeBestPattern(new Set(["VerticalPress"]));
  } else if (focus === "Pull") {
    takeBestPattern(new Set(["HorizontalPull"]));
    takeBestPattern(new Set(["VerticalPull"]));
  }

  if (focus === "FullBody") {
    ["Push", "Pull", "Legs"].forEach(requiredFocus => {
      const best = remaining
        .filter(candidate => candidate.analysis.category === requiredFocus && smartIsCompound(candidate.analysis))
        .sort((a, b) => {
          const priority = candidate => candidate.analysis.role === "Primary" ? 28 : smartIsCompound(candidate.analysis) ? 14 : 0;
          return (b.score + priority(b) + smartWeeklyCoverageScore(b, selected, weeklyEffectiveSets, profile, appliedEffort)) -
            (a.score + priority(a) + smartWeeklyCoverageScore(a, selected, weeklyEffectiveSets, profile, appliedEffort)) ||
            a.exercise.name.localeCompare(b.exercise.name);
        })[0];
      if (!best) return;
      selected.push(best);
      best.analysis.muscles.forEach(muscle => coveredMuscles.add(muscle));
      remaining = remaining.filter(candidate => candidate.exercise.id !== best.exercise.id);
    });
  }

  const trunkLastTrained = { core: 0, hyper: 0 };
  history.forEach(set => {
    const key = resolvedExerciseCatalogKey(set);
    const kind = ["hyperextension", "side_hyperextension"].includes(key) ? "hyper" :
      analyzeSmartExercise(set).patterns.has("Core") ? "core" : null;
    if (kind) trunkLastTrained[kind] = Math.max(trunkLastTrained[kind], Number(set.session?.startedAt) || 0);
  });
  const preferredTrunkKind = trunkLastTrained.hyper === trunkLastTrained.core
    ? (variant === "B" ? "hyper" : "core")
    : trunkLastTrained.hyper < trunkLastTrained.core ? "hyper" : "core";
  const trunkKind = candidate => ["hyperextension", "side_hyperextension"].includes(
    resolvedExerciseCatalogKey(candidate.exercise)
  ) ? "hyper" : "core";
  const trunkCandidates = selected.some(isTrunkCandidate) ? [] : remaining.filter(isTrunkCandidate);
  const preferredTrunkCandidates = trunkCandidates.filter(candidate =>
    trunkKind(candidate) === preferredTrunkKind
  );
  const trunk = (preferredTrunkCandidates.length ? preferredTrunkCandidates : trunkCandidates)
    .sort((left, right) => (right.score + smartWeeklyCoverageScore(right, selected, weeklyEffectiveSets, profile, appliedEffort)) -
      (left.score + smartWeeklyCoverageScore(left, selected, weeklyEffectiveSets, profile, appliedEffort)) ||
      left.exercise.name.localeCompare(right.exercise.name))[0] || null;
  if (trunk && selected.length < targetExerciseCount) {
    selected.push(trunk);
    trunk.analysis.muscles.forEach(muscle => coveredMuscles.add(muscle));
    remaining = remaining.filter(candidate => candidate.exercise.id !== trunk.exercise.id);
  }
  if (selected.some(isTrunkCandidate)) {
    remaining = remaining.filter(candidate => !isTrunkCandidate(candidate));
  }

  while (selected.length < targetExerciseCount && remaining.length) {
    const ranked = remaining
      .map(candidate => ({
        candidate,
        coverageGain: smartWeeklyCoverageGain(
          candidate,
          selected,
          weeklyEffectiveSets,
          profile,
          appliedEffort
        ),
        score: balancedSmartScore(candidate, selected, coveredMuscles, targetMuscles, lastTrained) +
          smartWeeklyCoverageScore(candidate, selected, weeklyEffectiveSets, profile, appliedEffort)
      }))
      .sort((a, b) => b.score - a.score || a.candidate.exercise.name.localeCompare(b.candidate.exercise.name));
    if (!ranked.length || ranked[0].coverageGain <= 0) break;
    const best = ranked[0].candidate;
    selected.push(best);
    best.analysis.muscles.forEach(muscle => coveredMuscles.add(muscle));
    remaining = remaining.filter(candidate => candidate.exercise.id !== best.exercise.id);
  }

  return smartFinalizeExerciseOrder(selected, candidates, targetExerciseCount, history, variant, focus);
}

function smartIsHyperCandidate(candidate) {
  return ["hyperextension", "side_hyperextension"].includes(
    resolvedExerciseCatalogKey(candidate?.exercise || candidate)
  );
}

function smartIsTrunkCandidate(candidate) {
  return Boolean(candidate?.analysis?.patterns?.has("Core")) || smartIsHyperCandidate(candidate);
}

function smartFinalizeExerciseOrder(selected, candidates, targetExerciseCount, history, variant, focus) {
  const unique = [...selected.reduce((items, candidate) => {
    const key = candidate?.analysis?.identityKey || exerciseMatchKey(candidate?.exercise || {});
    if (key && !items.has(key)) items.set(key, candidate);
    return items;
  }, new Map()).values()];
  const roleRank = candidate => candidate.analysis.role === "Primary" ? 0 :
    candidate.analysis.role === "Secondary" ? 1 : candidate.analysis.role === "Isolation" ? 2 : 3;
  // A four-exercise Upper session needs all four press/pull planes. Other focuses
  // reserve one final trunk slot so the total still fits the session set budget.
  const reserveTrunk = focus !== "Upper" || targetExerciseCount > 4;
  const nonTrunk = unique
    .filter(candidate => !smartIsTrunkCandidate(candidate))
    .sort((left, right) => roleRank(left) - roleRank(right) || right.score - left.score ||
      left.exercise.name.localeCompare(right.exercise.name))
    .slice(0, Math.max(0, targetExerciseCount - (reserveTrunk ? 1 : 0)));
  const selectedKeys = new Set(nonTrunk.map(candidate => candidate.analysis.identityKey));
  const hasHinge = nonTrunk.some(candidate => candidate.analysis.patterns.has("Hinge"));
  const recentHyperSessions = new Set(history
    .filter(set => daysBetween(set.session?.startedAt, Date.now()) <= 6 &&
      ["hyperextension", "side_hyperextension"].includes(resolvedExerciseCatalogKey(set)))
    .map(set => set.session?.id))
    .size;
  const trunkCandidates = reserveTrunk ? candidates
    .filter(candidate => smartIsTrunkCandidate(candidate) &&
      candidate.analysis.role !== "Warmup" &&
      !selectedKeys.has(candidate.analysis.identityKey) &&
      (!smartIsHyperCandidate(candidate) || (!hasHinge && recentHyperSessions < 2))) : [];
  const previousTrunk = unique.find(candidate => smartIsTrunkCandidate(candidate) && trunkCandidates.some(item =>
    item.analysis.identityKey === candidate.analysis.identityKey
  ));
  const trunkLastTrained = { core: 0, hyper: 0 };
  history.forEach(set => {
    const kind = ["hyperextension", "side_hyperextension"].includes(resolvedExerciseCatalogKey(set))
      ? "hyper"
      : analyzeSmartExercise(set).patterns.has("Core") ? "core" : null;
    if (kind) trunkLastTrained[kind] = Math.max(trunkLastTrained[kind], Number(set.session?.startedAt) || 0);
  });
  const preferredKind = trunkLastTrained.hyper === trunkLastTrained.core
    ? (variant === "B" ? "hyper" : "core")
    : trunkLastTrained.hyper < trunkLastTrained.core ? "hyper" : "core";
  const kindOf = candidate => smartIsHyperCandidate(candidate) ? "hyper" : "core";
  const trunk = previousTrunk || trunkCandidates
    .sort((left, right) => (kindOf(right) === preferredKind ? 20 : 0) -
      (kindOf(left) === preferredKind ? 20 : 0) || right.score - left.score ||
      left.exercise.name.localeCompare(right.exercise.name))[0] || null;
  if (trunk) return [...nonTrunk, trunk].slice(0, targetExerciseCount);

  // Trunk work is preferred, but it must not make the plan shorter when the
  // user's current catalog has no eligible core or hyperextension movement.
  const filled = [...nonTrunk];
  const filledKeys = new Set(filled.map(candidate => candidate.analysis.identityKey));
  const backfill = candidates
    .filter(candidate => candidate.analysis.role !== "Warmup" &&
      !smartIsTrunkCandidate(candidate) &&
      !filledKeys.has(candidate.analysis.identityKey))
    .sort((left, right) => roleRank(left) - roleRank(right) || right.score - left.score ||
      left.exercise.name.localeCompare(right.exercise.name));
  for (const candidate of backfill) {
    if (filled.length >= targetExerciseCount) break;
    if (filledKeys.has(candidate.analysis.identityKey)) continue;
    filled.push(candidate);
    filledKeys.add(candidate.analysis.identityKey);
  }
  return filled.slice(0, targetExerciseCount);
}

function patternMatchCount(candidate, patterns) {
  return [...candidate.analysis.patterns].filter(pattern => patterns.has(pattern)).length;
}

function balancedSmartScore(candidate, selected, coveredMuscles, targetMuscles, lastTrained) {
  const newTargetMuscles = candidate.analysis.muscles.filter(muscle => targetMuscles.has(muscle) && !coveredMuscles.has(muscle)).length;
  const targetOverlap = candidate.analysis.muscles.filter(muscle => targetMuscles.has(muscle)).length;
  const fatiguePenalty = candidate.analysis.muscles.reduce((sum, muscle) => {
    const lastDate = lastTrained.get(muscle);
    if (!lastDate) return sum;
    const days = daysBetween(lastDate, Date.now());
    return sum + (days === 0 ? 28 : days === 1 ? 18 : days === 2 ? 8 : 0);
  }, 0);
  const duplicateCoveragePenalty = candidate.analysis.muscles.length && candidate.analysis.muscles.every(muscle => coveredMuscles.has(muscle)) ? 10 : 0;
  const duplicateCompoundPatternPenalty = smartIsCompound(candidate.analysis)
    ? selected.reduce((sum, item) => sum + [...candidate.analysis.patterns]
      .filter(pattern => smartCompoundPatterns.has(pattern) && item.analysis.patterns.has(pattern)).length * 30, 0)
    : 0;
  const sameCategoryPenalty = selected.filter(item => item.analysis.category === candidate.analysis.category).length * 12;
  return candidate.score + newTargetMuscles * 24 + targetOverlap * 4 - fatiguePenalty -
    duplicateCoveragePenalty - duplicateCompoundPatternPenalty - sameCategoryPenalty;
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
    reps: last.reps,
    ...(block.smartGenerated === true ? { smartManualSet: true } : {})
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
  const setLimit = window.GymStateContract.LIMITS.setsPerExercise;
  const explicitExtraSets = block.smartGenerated === true
    ? block.sets.filter(set => set?.smartManualSet === true).slice(0, setLimit)
    : [];
  const recommendedSets = smartRecommendationForBlock(block).sets
    .slice(0, Math.max(0, setLimit - explicitExtraSets.length))
    .map(set => ({ weight: set.weight ?? "", reps: set.reps }));
  block.sets = [
    ...recommendedSets,
    ...explicitExtraSets
  ];
  render();
}

function activeWorkoutEntityId(usedIds) {
  for (let attempt = 0; attempt < 64; attempt += 1) {
    const candidate = uid();
    if (Number.isSafeInteger(candidate) && candidate > 0 && String(candidate).length <= 16 &&
        !usedIds.has(candidate)) {
      usedIds.add(candidate);
      return candidate;
    }
  }
  throw new Error("Unable to allocate a stable active workout ID.");
}

function activeWorkoutFromDraft(draft = workoutDraft, now = Date.now()) {
  if (!draft || !Number.isSafeInteger(now)) throw new Error("Workout draft is unavailable.");
  const descriptor = activeWorkoutAccountDescriptor();
  if (!descriptor) throw new Error("Workout draft has no account owner.");
  const limits = window.GymStateContract.LIMITS;
  if (!Array.isArray(draft.blocks) || draft.blocks.length < 1 ||
      draft.blocks.length > limits.exercisesPerSession) {
    throw new Error("Workout draft exceeds the exercise limit.");
  }
  const startedAt = draft.startedAt ?? now;
  if (!isWorkoutTimestampAllowed(startedAt, now)) throw new Error("Workout date is invalid.");
  const note = String(draft.note || "");
  if (note.length > MAX_ACTIVE_WORKOUT_NOTE_LENGTH ||
      new TextEncoder().encode(note).byteLength > MAX_ACTIVE_WORKOUT_NOTE_BYTES) {
    throw new Error("Workout note exceeds the supported limit.");
  }
  const parsedBlocks = [];
  const perExerciseCounts = new Map();
  for (const block of draft.blocks) {
    const exerciseName = String(block?.exerciseName || "").trim();
    if (!exerciseName) continue;
    if (!isSupportedExerciseName(exerciseName) || !Array.isArray(block.sets) ||
        block.sets.length < 1 || block.sets.length > limits.setsPerExercise) {
      throw new Error("Workout exercise or set list is invalid.");
    }
    const sets = block.sets.map(set => {
      const weightText = String(set?.weight ?? "").replace(",", ".").trim();
      const repsText = String(set?.reps ?? "").trim();
      const weight = Number(weightText);
      const reps = Number(repsText);
      if (!weightText || !repsText || !Number.isFinite(weight) || weight < 0 ||
          weight > limits.weightMax || !Number.isInteger(reps) || reps < 1 || reps > limits.repsMax) {
        throw new Error("Workout set values are invalid.");
      }
      return { weight: Object.is(weight, -0) ? 0 : weight, reps };
    });
    const exerciseKey = normalizeExerciseName(exerciseName);
    const nextCount = (perExerciseCounts.get(exerciseKey) || 0) + sets.length;
    if (nextCount > limits.setsPerExercise) throw new Error("One exercise exceeds the set limit.");
    perExerciseCounts.set(exerciseKey, nextCount);
    const catalogKey = persistedExerciseCatalogKey(block);
    parsedBlocks.push({ exerciseName, ...(catalogKey ? { catalogKey } : {}), sets });
  }
  const totalSets = parsedBlocks.reduce((sum, block) => sum + block.sets.length, 0);
  if (!totalSets || totalSets > limits.exercisesPerSession * limits.setsPerExercise) {
    throw new Error("Workout has no valid planned sets.");
  }
  const usedIds = new Set([
    ...state.sessions.map(session => session.id),
    ...allSets().map(set => set.id)
  ].filter(id => Number.isSafeInteger(id) && id > 0));
  const id = activeWorkoutEntityId(usedIds);
  const blocks = parsedBlocks.map(block => ({
    id: activeWorkoutEntityId(usedIds),
    exerciseName: block.exerciseName,
    ...(block.catalogKey ? { catalogKey: block.catalogKey } : {}),
    sets: block.sets.map(set => ({
      id: activeWorkoutEntityId(usedIds),
      weight: set.weight,
      reps: set.reps,
      completed: false,
      completedAt: null
    }))
  }));
  return parseActiveWorkoutEnvelope({
    version: ACTIVE_WORKOUT_VERSION,
    owner: descriptor.owner,
    id,
    startedAt,
    createdAt: now,
    updatedAt: now,
    revision: 1,
    note,
    blocks
  });
}

function activeWorkoutMutationUnavailable(context) {
  if (context && activeWorkoutAccountDescriptor()?.owner === context.descriptor.owner) {
    reloadActiveWorkoutContext(context.account);
  } else {
    clearActiveWorkoutMemory();
  }
  activeWorkoutUi = {
    status: "error",
    message: tx(
      "The active workout is busy in another tab. Check the latest set and retry.",
      "Активне тренування зайняте в іншій вкладці. Перевір останній підхід і повтори."
    )
  };
  render();
  showToast(tx(
    "The active workout is busy in another tab. Wait a moment and try again.",
    "Активне тренування зайняте в іншій вкладці. Зачекай трохи та повтори спробу."
  ));
  return false;
}

async function startWorkout({ liveSnapshot = null, liveIdentity = null } = {}) {
  if (activeWorkout) {
    nav = [{ name: "workouts" }, { name: "active" }];
    replaceNavigationHistory();
    render();
    showToast(tx("Continue or discard the active workout first.", "Спочатку продовж або відкинь активне тренування."));
    return false;
  }
  const mutationContext = activeWorkoutMutationContext();
  if (!mutationContext) {
    showToast(tx(
      "The active workout could not be saved in this browser.",
      "Не вдалося зберегти активне тренування в цьому браузері."
    ));
    return false;
  }
  let candidate;
  let preparedLiveBinding = null;
  let preparedLiveBindingRaw = null;
  try {
    candidate = activeWorkoutFromDraft();
    if (liveSnapshot !== null || liveIdentity !== null) {
      if (!liveSnapshot || !liveIdentity || !liveIdentityIsCurrent(accountEpoch, liveIdentity)) {
        throw new Error("Live workout identity changed before local start.");
      }
      preparedLiveBinding = window.GymLiveWorkoutState.bindSnapshot({
        userId: liveIdentity.userId,
        sessionId: liveIdentity.sessionId,
        snapshot: liveSnapshot,
        localWorkout: candidate
      });
      preparedLiveBindingRaw = window.GymLiveWorkoutState.encode(preparedLiveBinding);
    }
  } catch {
    showToast(tx(
      "Fill every planned set with a valid finite weight and whole-number reps.",
      "Заповни кожен запланований підхід коректною вагою та цілою кількістю повторів."
    ));
    return false;
  }
  const result = await withActiveWorkoutMutationLock(mutationContext.descriptor, () => {
    if (!activeWorkoutMutationContextIsCurrent(mutationContext)) return false;
    const loaded = loadActiveWorkoutRecord(mutationContext.account);
    if (loaded.workout) {
      reloadActiveWorkoutContext(mutationContext.account);
      nav = [{ name: "workouts" }, { name: "active" }];
      replaceNavigationHistory();
      workoutDraft = null;
      render();
      showToast(tx(
        "Another active workout already exists for this account. Continue it instead.",
        "Для цього акаунта вже є активне тренування. Продовж його."
      ));
      return false;
    }
    let previousLiveBindingRaw = null;
    if (preparedLiveBinding) {
      if (!liveIdentityIsCurrent(accountEpoch, liveIdentity) ||
          (liveWorkoutBinding && liveWorkoutBinding.roomId !== preparedLiveBinding.roomId) ||
          liveWorkoutBinding?.pendingOperations?.length) {
        return false;
      }
      const bindingKey = liveWorkoutBindingKey(liveIdentity.userId);
      try {
        previousLiveBindingRaw = localStorage.getItem(bindingKey);
      } catch {
        return false;
      }
      if (!persistLiveWorkoutBinding(preparedLiveBinding)) {
        restoreLiveWorkoutBindingAfterFailedStart(
          liveIdentity,
          preparedLiveBindingRaw,
          previousLiveBindingRaw
        );
        return false;
      }
    }
    const previousUndo = loadActiveWorkoutUndoRecord(null, mutationContext.account);
    const stored = persistActiveWorkoutRecord(candidate, mutationContext.account, null);
    if (!stored || !activeWorkoutMutationContextIsCurrent(mutationContext)) {
      if (preparedLiveBinding) {
        restoreLiveWorkoutBindingAfterFailedStart(
          liveIdentity,
          preparedLiveBindingRaw,
          previousLiveBindingRaw
        );
      }
      reloadActiveWorkoutContext(mutationContext.account);
      render();
      showToast(tx(
        "The active workout could not be saved in this browser.",
        "Не вдалося зберегти активне тренування в цьому браузері."
      ));
      return false;
    }
    activeWorkout = stored.workout;
    activeWorkoutStorageRaw = stored.raw;
    const initialTiming = loadActiveWorkoutTimingRecord(stored.workout, mutationContext.account);
    const timingStored = persistActiveWorkoutTiming(
      initialTiming.timing,
      stored.workout,
      mutationContext.account,
      initialTiming.raw
    );
    const restTransitionCleared = removeActiveWorkoutRestTransitionStorage(mutationContext.account);
    const bulkCleanupCleared = removeActiveWorkoutBulkCleanupStorage(mutationContext.account);
    if (removeActiveWorkoutUndoStorage(mutationContext.account, previousUndo.raw)) {
      activeWorkoutUndoMarker = null;
      activeWorkoutUndoStorageRaw = null;
    } else {
      const undoLoaded = loadActiveWorkoutUndoRecord(stored.workout, mutationContext.account);
      activeWorkoutUndoMarker = undoLoaded.marker;
      activeWorkoutUndoStorageRaw = undoLoaded.raw;
    }
    workoutDraft = null;
    smartGeneratedPlan = null;
    smartPlanStale = false;
    activeWorkoutUi = timingStored && restTransitionCleared && bulkCleanupCleared
      ? { status: "idle", message: "" }
      : {
          status: "error",
          message: tx(
            "Workout started, but active-time recovery could not be saved.",
            "Тренування почалося, але відновлення активного часу не вдалося зберегти."
          )
        };
    modal = null;
    nav = [{ name: "workouts" }, { name: "active" }];
    replaceNavigationHistory();
    routeScrollPositions.delete("add:root");
    render();
    return true;
  });
  if (!result.acquired) return activeWorkoutMutationUnavailable(mutationContext);
  return result.value === true;
}

function activeSetLocation(setId, workout = activeWorkout) {
  if (!Number.isSafeInteger(setId) || setId <= 0 || !workout) return null;
  for (const [blockIndex, block] of workout.blocks.entries()) {
    const setIndex = block.sets.findIndex(set => set.id === setId);
    if (setIndex >= 0) return { blockIndex, setIndex, block, set: block.sets[setIndex] };
  }
  return null;
}

function collectAllActiveSetInputs(workout = activeWorkout) {
  if (!workout) return null;
  const limits = window.GymStateContract.LIMITS;
  const values = new Map();
  for (const block of workout.blocks) {
    for (const set of block.sets) {
      if (set.completed) continue;
      const weightInput = app.querySelector(`[data-active-set-id="${set.id}"][data-active-field="weight"]`);
      const repsInput = app.querySelector(`[data-active-set-id="${set.id}"][data-active-field="reps"]`);
      const weightText = String(weightInput?.value ?? "").replace(",", ".").trim();
      const repsText = String(repsInput?.value ?? "").trim();
      const weight = Number(weightText);
      const reps = Number(repsText);
      if (!weightText || !repsText || !Number.isFinite(weight) || weight < 0 ||
          weight > limits.weightMax || !Number.isInteger(reps) || reps < 1 || reps > limits.repsMax) {
        return null;
      }
      values.set(set.id, { weight: Object.is(weight, -0) ? 0 : weight, reps });
    }
  }
  return values;
}

async function recordAllActiveSets() {
  if (!activeWorkout) return false;
  const expectedRaw = activeWorkoutStorageRaw;
  const expectedWorkoutId = activeWorkout.id;
  const expectedRevision = activeWorkout.revision;
  const values = collectAllActiveSetInputs(activeWorkout);
  if (!values || values.size === 0) {
    showToast(values
      ? tx("Every set is already saved.", "Усі підходи вже збережено.")
      : tx(
          "Fill every unfinished set with a valid finite weight and whole-number reps. Nothing was saved.",
          "Заповни кожен незавершений підхід коректною кінцевою вагою та цілою кількістю повторів. Нічого не збережено."
        ));
    return false;
  }
  const mutationContext = activeWorkoutMutationContext();
  if (!mutationContext) return activeWorkoutMutationUnavailable(null);
  let preparedLiveBatch = null;
  const result = await withActiveWorkoutMutationLock(mutationContext.descriptor, () => {
    if (!activeWorkoutMutationContextIsCurrent(mutationContext)) return false;
    const loaded = loadActiveWorkoutRecord(mutationContext.account);
    if (!loaded.workout || loaded.raw !== expectedRaw || loaded.workout.id !== expectedWorkoutId ||
        loaded.workout.revision !== expectedRevision) {
      reloadActiveWorkoutContext(mutationContext.account);
      activeWorkoutUi = {
        status: "error",
        message: tx(
          "The workout changed in another tab. Review every set before saving all again.",
          "Тренування змінилося в іншій вкладці. Перевір кожен підхід перед повторним збереженням усіх."
        )
      };
      render();
      return false;
    }
    const unfinishedIds = loaded.workout.blocks.flatMap(block => block.sets)
      .filter(set => !set.completed)
      .map(set => set.id);
    if (unfinishedIds.length !== values.size || unfinishedIds.some(id => !values.has(id))) {
      reloadActiveWorkoutContext(mutationContext.account);
      render();
      return false;
    }
    const now = Math.max(Date.now(), loaded.workout.updatedAt + 1);
    if (!Number.isSafeInteger(now) || loaded.workout.revision >= Number.MAX_SAFE_INTEGER) return false;
    const next = {
      ...loaded.workout,
      updatedAt: now,
      revision: loaded.workout.revision + 1,
      blocks: loaded.workout.blocks.map(block => ({
        ...block,
        sets: block.sets.map(set => set.completed
          ? set
          : {
              ...set,
              ...values.get(set.id),
              completed: true,
              completedAt: now
            })
      }))
    };
    if (!reconcileActiveWorkoutRestTransition(loaded.workout, mutationContext.account, now) ||
        !reconcileActiveWorkoutBulkCleanupIntent(loaded.workout, mutationContext.account, now)) {
      reloadActiveWorkoutContext(mutationContext.account);
      render();
      return false;
    }
    preparedLiveBatch = prepareLiveSetOperationBatch([...values].map(([localSetId, value]) => ({
      kind: "complete_set",
      localSetId,
      weight: value.weight,
      reps: value.reps,
      localMutationAt: now
    })));
    if (preparedLiveBatch.required && !preparedLiveBatch.token) {
      activeWorkoutUi = {
        status: "error",
        message: tx(
          "Live synchronization could not be prepared, so no sets were changed.",
          "Не вдалося підготувати live-синхронізацію, тому жоден підхід не змінено."
        )
      };
      render();
      return false;
    }
    const cleanupIntent = persistActiveWorkoutBulkCleanupIntent(
      loaded.workout,
      next,
      now,
      mutationContext.account,
      null
    );
    if (!cleanupIntent) {
      rollbackPreparedLiveWorkoutOperations(preparedLiveBatch);
      preparedLiveBatch = null;
      return false;
    }
    const stored = persistActiveWorkoutRecord(next, mutationContext.account, loaded.raw);
    if (!stored || !activeWorkoutMutationContextIsCurrent(mutationContext)) {
      rollbackPreparedLiveWorkoutOperations(preparedLiveBatch);
      preparedLiveBatch = null;
      if (!stored) removeActiveWorkoutBulkCleanupStorage(mutationContext.account, cleanupIntent.raw);
      reloadActiveWorkoutContext(mutationContext.account);
      render();
      return false;
    }
    activeWorkout = stored.workout;
    activeWorkoutStorageRaw = stored.raw;
    const cleanupSucceeded = reconcileActiveWorkoutBulkCleanupIntent(
      stored.workout,
      mutationContext.account,
      now
    );
    if (!cleanupSucceeded) {
      const latestUndo = loadActiveWorkoutUndoRecord(stored.workout, mutationContext.account);
      activeWorkoutUndoMarker = latestUndo.marker;
      activeWorkoutUndoStorageRaw = latestUndo.raw;
    }
    activeWorkoutUi = {
      status: cleanupSucceeded ? "success" : "error",
      message: cleanupSucceeded
        ? tx("All unfinished sets were saved together. Rest was stopped.", "Усі незавершені підходи збережено разом. Відпочинок зупинено.")
        : tx("All sets were saved, but the old rest or Undo state could not be fully cleared.", "Усі підходи збережено, але старий стан відпочинку або скасування не вдалося повністю очистити.")
    };
    render();
    return true;
  });
  if (!result.acquired) return activeWorkoutMutationUnavailable(mutationContext);
  if (result.value === true) commitPreparedLiveWorkoutOperations(preparedLiveBatch);
  return result.value === true;
}

async function recordActiveSet(setId) {
  const initialLocation = activeSetLocation(setId);
  if (!initialLocation || initialLocation.set.completed) return false;
  const weightInput = app.querySelector(`[data-active-set-id="${setId}"][data-active-field="weight"]`);
  const repsInput = app.querySelector(`[data-active-set-id="${setId}"][data-active-field="reps"]`);
  const weightText = String(weightInput?.value ?? "").replace(",", ".").trim();
  const repsText = String(repsInput?.value ?? "").trim();
  const weight = Number(weightText);
  const reps = Number(repsText);
  const limits = window.GymStateContract.LIMITS;
  if (!weightText || !repsText || !Number.isFinite(weight) || weight < 0 ||
      weight > limits.weightMax || !Number.isInteger(reps) || reps < 1 || reps > limits.repsMax) {
    showToast(tx(
      "Enter a valid finite weight and whole-number reps before recording this set.",
      "Введи коректну кінцеву вагу та цілу кількість повторів перед записом підходу."
    ));
    return false;
  }
  const mutationContext = activeWorkoutMutationContext();
  if (!mutationContext) return activeWorkoutMutationUnavailable(null);
  let preparedLiveBatch = null;
  const result = await withActiveWorkoutMutationLock(mutationContext.descriptor, () => {
    if (!activeWorkoutMutationContextIsCurrent(mutationContext)) return false;
    const loaded = loadActiveWorkoutRecord(mutationContext.account);
    const reconciliationNow = Math.max(Date.now(), loaded.workout?.updatedAt || 0);
    if (!loaded.workout ||
        !reconcileActiveWorkoutRestTransition(loaded.workout, mutationContext.account, reconciliationNow) ||
        !reconcileActiveWorkoutBulkCleanupIntent(loaded.workout, mutationContext.account, reconciliationNow)) {
      reloadActiveWorkoutContext(mutationContext.account);
      return false;
    }
    const loadedUndo = loadActiveWorkoutUndoRecord(loaded.workout, mutationContext.account);
    activeWorkout = loaded.workout;
    activeWorkoutStorageRaw = loaded.raw;
    activeWorkoutUndoMarker = loadedUndo.marker;
    activeWorkoutUndoStorageRaw = loadedUndo.raw;
    const location = activeSetLocation(setId, loaded.workout);
    if (!location || location.set.completed) {
      render();
      if (location?.set.completed) {
        showToast(tx(
          "This set was already recorded in another tab.",
          "Цей підхід уже записано в іншій вкладці."
        ));
      }
      return false;
    }
    const now = Math.max(Date.now(), loaded.workout.updatedAt + 1);
    if (!Number.isSafeInteger(now) || loaded.workout.revision >= Number.MAX_SAFE_INTEGER) {
      showToast(tx("This active workout cannot be updated safely.", "Це активне тренування неможливо безпечно оновити."));
      return false;
    }
    const next = {
      ...loaded.workout,
      updatedAt: now,
      revision: loaded.workout.revision + 1,
      blocks: loaded.workout.blocks.map((block, blockIndex) => blockIndex === location.blockIndex
        ? {
            ...block,
            sets: block.sets.map((set, setIndex) => setIndex === location.setIndex
              ? {
                  ...set,
                  weight: Object.is(weight, -0) ? 0 : weight,
                  reps,
                  completed: true,
                  completedAt: now
                }
              : set)
          }
        : block)
    };
    preparedLiveBatch = prepareLiveSetOperationBatch([{
      kind: "complete_set",
      localSetId: setId,
      weight: Object.is(weight, -0) ? 0 : weight,
      reps,
      localMutationAt: now
    }]);
    if (preparedLiveBatch.required && !preparedLiveBatch.token) {
      activeWorkoutUi = {
        status: "error",
        message: tx(
          "Live synchronization could not be prepared, so this set was not changed.",
          "Не вдалося підготувати live-синхронізацію, тому цей підхід не змінено."
        )
      };
      render();
      return false;
    }
    const stored = persistActiveWorkoutRecord(next, mutationContext.account, loaded.raw);
    if (!stored || !activeWorkoutMutationContextIsCurrent(mutationContext)) {
      rollbackPreparedLiveWorkoutOperations(preparedLiveBatch);
      preparedLiveBatch = null;
      reloadActiveWorkoutContext(mutationContext.account);
      render();
      showToast(tx(
        "The active workout changed in another tab or could not be saved. Review it before retrying.",
        "Активне тренування змінилося в іншій вкладці або не збереглося. Перевір його перед повторною спробою."
      ));
      return false;
    }
    activeWorkout = stored.workout;
    activeWorkoutStorageRaw = stored.raw;
    const storedUndo = persistActiveWorkoutUndoRecord(
      stored.workout,
      setId,
      mutationContext.account,
      loadedUndo.raw
    );
    if (storedUndo) {
      activeWorkoutUndoMarker = storedUndo.marker;
      activeWorkoutUndoStorageRaw = storedUndo.raw;
    } else {
      const undoLoaded = loadActiveWorkoutUndoRecord(stored.workout, mutationContext.account);
      activeWorkoutUndoMarker = undoLoaded.marker;
      activeWorkoutUndoStorageRaw = undoLoaded.raw;
    }
    const timerKey = `${stored.workout.id}:${location.block.exerciseName}`;
    const restSeconds = smartRestSecondsForBlock(location.block);
    const timerStarted = startExerciseRestTimerLocked(timerKey, restSeconds);
    activeWorkoutUi = timerStarted && storedUndo
      ? {
          status: "success",
          message: tx(
            "Set saved. Smart rest started.",
            "Підхід збережено. Розумний відпочинок запущено."
          )
        }
      : {
          status: "error",
          message: !storedUndo
            ? tx(
                "Set saved, but one-step Undo could not be enabled. Check the set before continuing.",
                "Підхід збережено, але одноразове скасування не вдалося ввімкнути. Перевір підхід перед продовженням."
              )
            : tx(
                "Set saved, but the rest timer could not be saved. Check it before continuing.",
                "Підхід збережено, але таймер відпочинку не вдалося зберегти. Перевір його перед продовженням."
              )
        };
    render();
    if (!storedUndo || !timerStarted) {
      showToast(!storedUndo
        ? tx(
            "Set recorded, but one-step Undo is unavailable.",
            "Підхід записано, але одноразове скасування недоступне."
          )
        : tx(
            "Set recorded, but the rest timer could not be saved.",
            "Підхід записано, але не вдалося зберегти таймер відпочинку."
          ));
    }
    return true;
  });
  if (!result.acquired) return activeWorkoutMutationUnavailable(mutationContext);
  if (result.value === true) commitPreparedLiveWorkoutOperations(preparedLiveBatch);
  return result.value === true;
}

async function undoLatestActiveSet(setId) {
  if (!Number.isSafeInteger(setId) || setId <= 0) return false;
  const mutationContext = activeWorkoutMutationContext();
  if (!mutationContext) return activeWorkoutMutationUnavailable(null);
  let preparedLiveBatch = null;
  const result = await withActiveWorkoutMutationLock(mutationContext.descriptor, () => {
    if (!activeWorkoutMutationContextIsCurrent(mutationContext)) return false;
    const loaded = loadActiveWorkoutRecord(mutationContext.account);
    const reconciliationNow = Math.max(Date.now(), loaded.workout?.updatedAt || 0);
    if (!loaded.workout ||
        !reconcileActiveWorkoutRestTransition(loaded.workout, mutationContext.account, reconciliationNow) ||
        !reconcileActiveWorkoutBulkCleanupIntent(loaded.workout, mutationContext.account, reconciliationNow)) {
      reloadActiveWorkoutContext(mutationContext.account);
      return false;
    }
    const loadedUndo = loadActiveWorkoutUndoRecord(loaded.workout, mutationContext.account);
    activeWorkout = loaded.workout;
    activeWorkoutStorageRaw = loaded.raw;
    activeWorkoutUndoMarker = loadedUndo.marker;
    activeWorkoutUndoStorageRaw = loadedUndo.raw;
    const latest = latestActiveCompletedEntry(loaded.workout);
    if (!latest || latest.set.id !== setId || loadedUndo.marker?.setId !== setId) {
      activeWorkoutUi = {
        status: "error",
        message: tx(
          "Only the most recently recorded set can be undone.",
          "Скасувати можна лише останній записаний підхід."
        )
      };
      render();
      return false;
    }
    const now = Math.max(Date.now(), loaded.workout.updatedAt + 1);
    if (!Number.isSafeInteger(now) || loaded.workout.revision >= Number.MAX_SAFE_INTEGER) return false;
    const next = {
      ...loaded.workout,
      updatedAt: now,
      revision: loaded.workout.revision + 1,
      blocks: loaded.workout.blocks.map((block, blockIndex) => blockIndex === latest.blockIndex
        ? {
            ...block,
            sets: block.sets.map((set, setIndex) => setIndex === latest.setIndex
              ? { ...set, completed: false, completedAt: null }
              : set)
          }
        : block)
    };
    preparedLiveBatch = prepareLiveSetOperationBatch([{
      kind: "undo_set",
      localSetId: setId,
      weight: null,
      reps: null,
      localMutationAt: now
    }]);
    if (preparedLiveBatch.required && !preparedLiveBatch.token) {
      activeWorkoutUi = {
        status: "error",
        message: tx(
          "Live synchronization could not be prepared, so this set stayed recorded.",
          "Не вдалося підготувати live-синхронізацію, тому підхід залишився записаним."
        )
      };
      render();
      return false;
    }
    const stored = persistActiveWorkoutRecord(next, mutationContext.account, loaded.raw);
    if (!stored || !activeWorkoutMutationContextIsCurrent(mutationContext)) {
      rollbackPreparedLiveWorkoutOperations(preparedLiveBatch);
      preparedLiveBatch = null;
      reloadActiveWorkoutContext(mutationContext.account);
      activeWorkoutUi = {
        status: "error",
        message: tx(
          "The latest set changed in another tab. Check it before retrying.",
          "Останній підхід змінився в іншій вкладці. Перевір його перед повтором."
        )
      };
      render();
      return false;
    }
    activeWorkout = stored.workout;
    activeWorkoutStorageRaw = stored.raw;
    const consumedUndo = persistActiveWorkoutUndoRecord(
      stored.workout,
      null,
      mutationContext.account,
      loadedUndo.raw
    );
    if (consumedUndo) {
      activeWorkoutUndoMarker = consumedUndo.marker;
      activeWorkoutUndoStorageRaw = consumedUndo.raw;
    } else {
      const undoLoaded = loadActiveWorkoutUndoRecord(stored.workout, mutationContext.account);
      activeWorkoutUndoMarker = undoLoaded.marker;
      activeWorkoutUndoStorageRaw = undoLoaded.raw;
    }
    const timerKey = `${stored.workout.id}:${latest.block.exerciseName}`;
    const timerStopped = stopExerciseRestTimerLocked(timerKey);
    activeWorkoutUi = {
      status: timerStopped && consumedUndo ? "success" : "error",
      message: !consumedUndo
        ? tx(
            "Last set returned for editing, but Undo state could not be finalized. Check it before continuing.",
            "Останній підхід повернуто для редагування, але стан скасування не вдалося завершити. Перевір його перед продовженням."
          )
        : timerStopped
        ? tx(
            "Last set returned for editing. Its rest timer was stopped.",
            "Останній підхід повернуто для редагування. Його таймер відпочинку зупинено."
          )
        : tx(
            "Last set returned for editing, but the saved rest timer needs checking.",
            "Останній підхід повернуто для редагування, але збережений таймер потрібно перевірити."
          )
    };
    render();
    return true;
  });
  if (!result.acquired) return activeWorkoutMutationUnavailable(mutationContext);
  if (result.value === true) commitPreparedLiveWorkoutOperations(preparedLiveBatch);
  return result.value === true;
}

function activeCompletedEntries(workout = activeWorkout) {
  if (!workout) return [];
  return workout.blocks.flatMap((block, blockIndex) => block.sets.flatMap((set, setIndex) =>
    set.completed ? [{ block, blockIndex, set, setIndex }] : []
  ));
}

function historySetMatchesActiveEntry(historySet, entry) {
  return historySet?.id === entry.set.id && exercisesMatch(historySet, entry.block) &&
    Number(historySet.weight) === entry.set.weight && historySet.reps === entry.set.reps;
}

async function finishActiveWorkout() {
  const mutationContext = activeWorkoutMutationContext();
  if (!mutationContext) return activeWorkoutMutationUnavailable(null);
  let preparedLiveBatch = null;
  const result = await withActiveWorkoutMutationLock(
    mutationContext.descriptor,
    () => finishActiveWorkoutLocked(mutationContext, prepared => {
      preparedLiveBatch = prepared;
    })
  );
  if (!result.acquired) return activeWorkoutMutationUnavailable(mutationContext);
  if (result.value === true) commitPreparedLiveWorkoutOperations(preparedLiveBatch);
  return result.value === true;
}

function finishActiveWorkoutLocked(mutationContext, onLivePrepared = () => {}) {
  if (!activeWorkoutMutationContextIsCurrent(mutationContext)) return false;
  const loaded = loadActiveWorkoutRecord(mutationContext.account);
  const loadedUndo = loadActiveWorkoutUndoRecord(loaded.workout, mutationContext.account);
  activeWorkout = loaded.workout;
  activeWorkoutStorageRaw = loaded.raw;
  activeWorkoutUndoMarker = loadedUndo.marker;
  activeWorkoutUndoStorageRaw = loadedUndo.raw;
  const workout = loaded.workout;
  if (!workout) {
    render();
    showToast(tx(
      "The active workout changed in another tab. Review the latest version before finishing.",
      "Активне тренування змінилося в іншій вкладці. Перевір останню версію перед завершенням."
    ));
    return false;
  }
  if (!isWorkoutTimestampAllowed(workout.startedAt)) {
    return showToast(tx(
      "The active workout date is no longer valid. Keep the draft and correct the device date before finishing.",
      "Дата активного тренування більше не є коректною. Збережи чернетку та виправ дату на пристрої перед завершенням."
    ));
  }
  let currentRaw;
  try {
    currentRaw = localStorage.getItem(mutationContext.descriptor.storageKey);
  } catch {
    currentRaw = null;
  }
  if (!activeWorkoutStorageRaw || currentRaw !== activeWorkoutStorageRaw) {
    reloadActiveWorkoutContext(mutationContext.account);
    render();
    return showToast(tx(
      "The active workout changed in another tab. Review the latest version before finishing.",
      "Активне тренування змінилося в іншій вкладці. Перевір останню версію перед завершенням."
    ));
  }
  // Read the latest base plus any previously committed active workouts while
  // holding the active-workout lock. Finish writes only to the append ledger;
  // it never overwrites the ordinary state key that another tab may mutate.
  state = loadState(mutationContext.account);
  const completed = activeCompletedEntries(workout);
  if (!completed.length) {
    return showToast(tx("Record at least one set or discard this workout.", "Запиши хоча б один підхід або відкинь це тренування."));
  }
  const limits = window.GymStateContract.LIMITS;
  const matchingSessions = state.sessions.filter(session => session.id === workout.id);
  if (matchingSessions.length > 1) {
    return showToast(tx("Workout history contains a conflicting ID.", "Історія тренувань містить конфліктний ідентифікатор."));
  }
  const existing = matchingSessions[0] || null;
  if (existing && (existing.startedAt !== workout.startedAt || existing.note !== workout.note)) {
    return showToast(tx("Workout history conflicts with this active workout.", "Історія тренувань конфліктує з цим активним тренуванням."));
  }
  const completedById = new Map(completed.map(entry => [entry.set.id, entry]));
  const existingById = new Map();
  for (const set of existing?.sets || []) {
    const entry = completedById.get(set.id);
    if (!entry || existingById.has(set.id) || !historySetMatchesActiveEntry(set, entry)) {
      return showToast(tx("Workout history conflicts with this active workout.", "Історія тренувань конфліктує з цим активним тренуванням."));
    }
    existingById.set(set.id, set);
  }
  const otherSetIds = new Set(state.sessions
    .filter(session => session.id !== workout.id)
    .flatMap(session => session.sets.map(set => set.id)));
  if (completed.some(entry => otherSetIds.has(entry.set.id))) {
    return showToast(tx("A completed set ID conflicts with workout history.", "Ідентифікатор виконаного підходу конфліктує з історією."));
  }
  const missing = completed.filter(entry => !existingById.has(entry.set.id));
  if ((!existing && state.sessions.length >= limits.sessions) ||
      allSets().length + missing.length > limits.totalSets) {
    return showToast(tx("Workout history has reached its supported limit.", "Історія тренувань досягла підтримуваного ліміту."));
  }
  const preparedLiveBatch = prepareLiveWorkoutOperationBatch([{
    kind: "finish",
    serverSetId: null,
    weight: null,
    reps: null,
    localMutationAt: Math.max(Date.now(), workout.updatedAt + 1)
  }]);
  if (preparedLiveBatch.required && !preparedLiveBatch.token) {
    return showToast(tx(
      "Live finish could not be prepared, so the local workout was kept active.",
      "Не вдалося підготувати live-завершення, тому локальне тренування залишилося активним."
    ));
  }
  onLivePrepared(preparedLiveBatch);
  const committed = persistActiveWorkoutCommit(workout, mutationContext.account);
  if (!committed) {
    rollbackPreparedLiveWorkoutOperations(preparedLiveBatch);
    onLivePrepared(null);
    state = loadState(mutationContext.account);
    return showToast(tx(
      "Completed sets could not be committed safely. The active workout was kept.",
      "Не вдалося безпечно зберегти виконані підходи. Активне тренування збережено."
    ));
  }
  state = committed.state;
  try {
    markRemoteStateDirtyBeforeWrite(state);
    queueRemoteSave();
  } catch {
    return showToast(tx(
      "Completed sets were committed locally, but sync could not be prepared. The active workout was kept for a safe retry.",
      "Виконані підходи збережено локально, але синхронізацію не вдалося підготувати. Активне тренування залишено для безпечного повтору."
    ));
  }
  if (!removeActiveWorkoutStorage(mutationContext.account, activeWorkoutStorageRaw)) {
    reloadActiveWorkoutContext(mutationContext.account);
    render();
    return showToast(tx(
      "Completed sets were added to history, but the active draft could not be cleared. Retry Finish to complete cleanup without duplicating sets.",
      "Виконані підходи додано до історії, але активну чернетку не вдалося очистити. Повтори завершення — підходи не дублюватимуться."
    ));
  }
  const undoCleared = removeActiveWorkoutUndoStorage(
    mutationContext.account,
    activeWorkoutUndoStorageRaw
  );
  const timingCleared = removeActiveWorkoutTimingStorage(mutationContext.account);
  const restTransitionCleared = removeActiveWorkoutRestTransitionStorage(mutationContext.account);
  const bulkCleanupCleared = removeActiveWorkoutBulkCleanupStorage(mutationContext.account);
  const finishedId = workout.id;
  clearActiveWorkoutMemory();
  const timerCleared = clearActiveWorkoutRestTimers(finishedId);
  modal = null;
  nav = [{ name: "workouts" }, { name: "summary", id: finishedId }];
  replaceNavigationHistory();
  render();
  if (!timerCleared || !undoCleared || !timingCleared || !restTransitionCleared ||
      !bulkCleanupCleared) {
    showToast(tx(
      "Workout finished, but some local workout controls could not be cleared. Clear site data if they reappear.",
      "Тренування завершено, але деякі локальні елементи керування не вдалося очистити. Очисть дані сайту, якщо вони з’являться знову."
    ));
  }
  return true;
}

function requestDiscardActiveWorkout(returnFocus = null) {
  const descriptor = activeWorkoutAccountDescriptor();
  if (!activeWorkout || !descriptor || !activeWorkoutStorageRaw) return;
  let authMarkerFingerprint;
  try {
    authMarkerFingerprint = destructiveImpactFingerprint(localStorage.getItem(AUTH_KEY));
  } catch {
    return showToast(tx(
      "Discard confirmation could not be bound to the active account.",
      "Не вдалося прив’язати підтвердження відкидання до активного акаунта."
    ));
  }
  modal = {
    type: "confirm-discard-active",
    intent: {
      accountEpoch,
      owner: descriptor.owner,
      workoutId: activeWorkout.id,
      storageKey: descriptor.storageKey,
      raw: activeWorkoutStorageRaw,
      authMarkerFingerprint,
      returnFocus
    }
  };
  render();
}

async function confirmDiscardActiveWorkout() {
  const discardedLiveBinding = liveWorkoutBinding?.localWorkoutId === activeWorkout?.id
    ? liveWorkoutBinding
    : null;
  const intent = modal?.type === "confirm-discard-active" ? modal.intent : null;
  const mutationContext = activeWorkoutMutationContext();
  if (!intent || !mutationContext) return false;
  const result = await withActiveWorkoutMutationLock(
    mutationContext.descriptor,
    () => confirmDiscardActiveWorkoutLocked(intent, mutationContext)
  );
  if (!result.acquired) return activeWorkoutMutationUnavailable(mutationContext);
  if (result.value === true && discardedLiveBinding) {
    void abandonLiveWorkoutAfterDiscard(discardedLiveBinding);
  }
  return result.value === true;
}

function confirmDiscardActiveWorkoutLocked(intent, mutationContext) {
  const descriptor = mutationContext.descriptor;
  if (!activeWorkoutMutationContextIsCurrent(mutationContext) ||
      modal?.type !== "confirm-discard-active" || modal.intent !== intent) return false;
  const loaded = loadActiveWorkoutRecord(mutationContext.account);
  const loadedUndo = loadActiveWorkoutUndoRecord(loaded.workout, mutationContext.account);
  activeWorkout = loaded.workout;
  activeWorkoutStorageRaw = loaded.raw;
  activeWorkoutUndoMarker = loadedUndo.marker;
  activeWorkoutUndoStorageRaw = loadedUndo.raw;
  let authMarkerFingerprint = null;
  try {
    authMarkerFingerprint = destructiveImpactFingerprint(localStorage.getItem(AUTH_KEY));
  } catch {
    // The mismatch below fails closed without deleting the active workout.
  }
  if (!intent || !descriptor || intent.accountEpoch !== accountEpoch ||
      intent.owner !== descriptor.owner || intent.storageKey !== descriptor.storageKey ||
      intent.authMarkerFingerprint !== authMarkerFingerprint ||
      activeWorkout?.id !== intent.workoutId || activeWorkoutStorageRaw !== intent.raw) {
    modal = null;
    reloadActiveWorkoutContext(mutationContext.account);
    render();
    showToast(tx(
      "The active workout changed, so discard was cancelled.",
      "Активне тренування змінилося, тому відкидання скасовано."
    ));
    return false;
  }
  let currentRaw;
  try {
    currentRaw = localStorage.getItem(descriptor.storageKey);
  } catch {
    currentRaw = null;
  }
  if (currentRaw !== intent.raw || !removeActiveWorkoutStorage(mutationContext.account, intent.raw)) {
    modal = null;
    reloadActiveWorkoutContext(mutationContext.account);
    render();
    showToast(tx(
      "The active workout changed or could not be removed. Nothing was discarded.",
      "Активне тренування змінилося або його не вдалося видалити. Нічого не відкинуто."
    ));
    return false;
  }
  const undoCleared = removeActiveWorkoutUndoStorage(
    mutationContext.account,
    activeWorkoutUndoStorageRaw
  );
  const timingCleared = removeActiveWorkoutTimingStorage(mutationContext.account);
  const restTransitionCleared = removeActiveWorkoutRestTransitionStorage(mutationContext.account);
  const bulkCleanupCleared = removeActiveWorkoutBulkCleanupStorage(mutationContext.account);
  const discardedId = activeWorkout.id;
  clearActiveWorkoutMemory();
  clearActiveWorkoutRestTimers(discardedId);
  modal = null;
  nav = [{ name: "workouts" }];
  replaceNavigationHistory();
  render();
  showToast(undoCleared && timingCleared && restTransitionCleared && bulkCleanupCleared
    ? tx("Active workout discarded.", "Активне тренування відкинуто.")
    : tx(
        "Active workout discarded, but its local Undo state could not be cleared. Clear site data if it reappears.",
        "Активне тренування відкинуто, але його локальний стан скасування не вдалося очистити. Очисть дані сайту, якщо він з’явиться знову."
      ));
  return true;
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
  if (!isWorkoutTimestampAllowed(startedAt)) {
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
  smartGeneratedPlan = null;
  modal = null;
  nav = [{ name: "workouts" }, { name: "summary", id }];
  replaceNavigationHistory();
  render();
  routeScrollPositions.delete("add:root");
}

function openWorkoutExercisePicker(target, blockIndex = null, sessionId = null) {
  if (!["draft-new", "draft-replace", "session"].includes(target)) return false;
  if (target === "draft-replace" &&
      (!Number.isInteger(blockIndex) || blockIndex < 0 || !workoutDraft?.blocks?.[blockIndex])) return false;
  if (target === "session" &&
      (!Number.isSafeInteger(sessionId) || sessionId <= 0 || !state.sessions.some(item => item.id === sessionId) ||
        !isSavedWorkoutEditMode(sessionId))) return false;
  modal = {
    type: "workout-exercise-picker",
    target,
    ...(target === "draft-replace" ? { blockIndex } : {}),
    ...(target === "session" ? { sessionId } : {})
  };
  render();
  return true;
}

function selectWorkoutExercise(exerciseId) {
  if (modal?.type !== "workout-exercise-picker" ||
      !Number.isSafeInteger(exerciseId) || exerciseId <= 0) return false;
  const picker = modal;
  const exercise = state.exercises.find(item => Number(item.id) === exerciseId);
  if (!exercise) return false;
  if (picker.target === "session") {
    if (!isSavedWorkoutEditMode(picker.sessionId)) return false;
    return quickAddExercise(exerciseId, picker.sessionId);
  }
  if (!workoutDraft) return false;
  const catalogKey = persistedExerciseCatalogKey(exercise);
  const identity = { exerciseName: exercise.name, ...(catalogKey ? { catalogKey } : {}) };
  if (picker.target === "draft-replace") {
    const block = workoutDraft.blocks[picker.blockIndex];
    if (!block) return false;
    block.exerciseName = identity.exerciseName;
    if (identity.catalogKey) block.catalogKey = identity.catalogKey;
    else delete block.catalogKey;
    delete block.smartGenerated;
    delete block.smartEffort;
    delete block.smartHardSlot;
    delete block.smartRecoverySteps;
    delete block.smartSetCap;
  } else if (picker.target === "draft-new") {
    const limits = window.GymStateContract.LIMITS;
    const pristineFirst = workoutDraft.blocks[0] && !workoutDraft.blocks[0].exerciseName &&
      workoutDraft.blocks[0].sets?.length === 1 &&
      String(workoutDraft.blocks[0].sets[0]?.weight ?? "") === "" &&
      String(workoutDraft.blocks[0].sets[0]?.reps ?? "") === "";
    if (!pristineFirst && workoutDraft.blocks.length >= limits.exercisesPerSession) {
      showToast(tx("This workout has reached the exercise limit.", "Досягнуто ліміт вправ у тренуванні."));
      return false;
    }
    const nextBlock = { ...identity, sets: [{ weight: "", reps: "" }] };
    if (pristineFirst) workoutDraft.blocks[0] = nextBlock;
    else workoutDraft.blocks.unshift(nextBlock);
  } else {
    return false;
  }
  smartGeneratedPlan = null;
  smartPlanStale = false;
  modal = null;
  render();
  return true;
}

function quickAddExercise(exerciseId = Number(document.querySelector("#quick-add")?.value), sessionId = route().id) {
  if (!isSavedWorkoutEditMode(sessionId)) return false;
  const session = state.sessions.find(s => s.id === Number(sessionId));
  const ex = state.exercises.find(e => e.id === Number(exerciseId));
  if (!session || !ex) return false;
  const limits = window.GymStateContract.LIMITS;
  const existingCount = session.sets.filter(set => exercisesMatch(set, ex)).length;
  if (existingCount > 0 || session.sets.length >= limits.exercisesPerSession * limits.setsPerExercise ||
      allSets().length >= limits.totalSets) {
    return showToast(tx("This workout has reached its set limit.", "Тренування досягло ліміту підходів."));
  }
  const catalogKey = persistedExerciseCatalogKey(ex);
  const set = { id: uid(), exerciseName: ex.name, ...(catalogKey ? { catalogKey } : {}), weight: 0, reps: 8, orderIndex: 0 };
  session.sets.unshift(set);
  try {
    saveState();
  } catch {
    session.sets.shift();
    return showToast(tx("The exercise could not be added safely.", "Не вдалося безпечно додати вправу."));
  }
  modal = null;
  render();
  return true;
}

function addSavedWorkoutSet(sessionId, name) {
  if (!isSavedWorkoutEditMode(sessionId)) return false;
  const session = state.sessions.find(s => s.id === sessionId);
  if (!session) return false;
  const limits = window.GymStateContract.LIMITS;
  if (!isSupportedExerciseName(name) ||
      session.sets.filter(set => exercisesMatch(set, name)).length >= limits.setsPerExercise ||
      session.sets.length >= limits.exercisesPerSession * limits.setsPerExercise || allSets().length >= limits.totalSets) {
    showToast(tx("This exercise has reached its set limit.", "Вправа досягла ліміту підходів."));
    return false;
  }
  const matchingSessionSets = session.sets.filter(set => exercisesMatch(set, name));
  const last = matchingSessionSets.at(-1) || allSets().filter(set => exercisesMatch(set, name)).at(-1);
  const exercise = last || state.exercises.find(item => item.name === name);
  const catalogKey = persistedExerciseCatalogKey(exercise);
  const set = { id: uid(), exerciseName: name, ...(catalogKey ? { catalogKey } : {}), weight: last?.weight || 0, reps: last?.reps || 8, orderIndex: matchingSessionSets.length };
  const setIndex = session.sets.length;
  session.sets.push(set);
  try {
    saveState();
  } catch {
    session.sets.splice(setIndex, 1);
    showToast(tx("The set could not be added safely.", "Не вдалося безпечно додати підхід."));
    return false;
  }
  render();
  showToast(tx("Set added without starting rest.", "Підхід додано без запуску відпочинку."));
  return true;
}

function openEditSet(id, sessionId = route().id) {
  if (!isSavedWorkoutEditMode(sessionId)) return false;
  const location = setLocation(id, sessionId);
  if (!location) return false;
  modal = { type: "edit-set", set: location.set, sessionId };
  render();
  return true;
}

function applyEditSet(id) {
  const sessionId = Number(modal?.sessionId);
  if (modal?.type !== "edit-set" || !isSavedWorkoutEditMode(sessionId)) return false;
  const location = setLocation(id, sessionId);
  const set = location?.set;
  if (!set) return false;
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
  return true;
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
    const baseState = validateImportedEnvelope(storedState, defaultAppState()).state;
    const descriptor = activeWorkoutAccountDescriptor();
    const commit = descriptor ? loadActiveWorkoutCommitLedger() : null;
    if (descriptor && !commit) return null;
    const normalizedStoredState = commit
      ? mergeActiveWorkoutCommitLedger(baseState, commit.ledger)
      : baseState;
    if (!normalizedStoredState) return null;
    if (destructiveImpactFingerprint(normalizedStoredState) !== stateFingerprint) return null;
    return {
      storageKey,
      storedStateFingerprint: destructiveImpactFingerprint(storedState),
      commitKey: descriptor?.commitKey || null,
      storedCommitFingerprint: descriptor
        ? destructiveImpactFingerprint(localStorage.getItem(descriptor.commitKey))
        : null,
      authMarkerFingerprint: destructiveImpactFingerprint(localStorage.getItem(AUTH_KEY))
    };
  } catch {
    return null;
  }
}

function destructiveStorageSnapshotIsCurrent(snapshot) {
  if (!snapshot || snapshot.storageKey !== activeStorageKey()) return false;
  try {
    const descriptor = activeWorkoutAccountDescriptor();
    return snapshot.commitKey === (descriptor?.commitKey || null) &&
      destructiveImpactFingerprint(localStorage.getItem(snapshot.storageKey)) === snapshot.storedStateFingerprint &&
      (!snapshot.commitKey || destructiveImpactFingerprint(localStorage.getItem(snapshot.commitKey)) ===
        snapshot.storedCommitFingerprint) &&
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

function destructivePersistenceRollbackRecords() {
  const keys = [];
  if (activeAccount?.remote === "supabase" && UUID_PATTERN.test(activeAccount.userId || "")) {
    keys.push(syncBaselineKey(activeAccount.userId));
  }
  keys.push(activeStorageKey());
  const records = keys.map(destructiveStorageRecord);
  return records.some(record => !record) ? null : records;
}

function restoreDestructivePersistenceRecords(records) {
  return Array.isArray(records) &&
    [...records].reverse().map(restoreDestructiveStorageRecord).every(Boolean);
}

function persistDestructiveState(expectedSnapshot) {
  if (!destructiveStorageSnapshotIsCurrent(expectedSnapshot)) {
    throw new Error("Destructive confirmation storage snapshot is stale.");
  }
  const snapshots = destructivePersistenceRollbackRecords();
  if (!snapshots) throw new Error("Destructive persistence could not be prepared.");
  if (!destructiveStorageSnapshotIsCurrent(expectedSnapshot)) {
    throw new Error("Destructive confirmation storage snapshot changed before persistence.");
  }
  try {
    saveState();
  } catch (error) {
    const restored = restoreDestructivePersistenceRecords(snapshots);
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

async function confirmDeleteSet() {
  const intent = modal?.type === "confirm-delete-set" ? modal.intent : null;
  const location = intent ? setLocation(intent.setId, intent.sessionId) : null;
  if (!destructiveIntentIsCurrent(intent) || !location ||
      location.session.id !== intent.sessionId ||
      destructiveImpactFingerprint(location.session) !== intent.impactFingerprint) {
    return rejectStaleDestructiveConfirmation();
  }
  const mutationContext = activeWorkoutMutationContext();
  if (!mutationContext) return showDestructiveSaveFailure();
  const result = await withActiveWorkoutDeletionLock(mutationContext.descriptor, () => {
    if (!activeWorkoutMutationContextIsCurrent(mutationContext) ||
        !destructiveIntentIsCurrent(intent)) return false;
    const currentLocation = setLocation(intent.setId, intent.sessionId);
    if (!currentLocation) return false;
    const previousSets = currentLocation.session.sets;
    const rollbackRecords = destructivePersistenceRollbackRecords();
    let previousLedgerRaw;
    try {
      previousLedgerRaw = localStorage.getItem(mutationContext.descriptor.commitKey);
    } catch {
      return false;
    }
    if (!rollbackRecords) return false;
    currentLocation.session.sets = previousSets.filter(set => set.id !== intent.setId);
    if (currentLocation.session.sets.length !== previousSets.length - 1) {
      currentLocation.session.sets = previousSets;
      return false;
    }
    try {
      persistDestructiveState(intent.storageSnapshot);
      const ledgerChange = rewriteActiveWorkoutCommitLedger(workouts => workouts.flatMap(workout => {
        if (workout.id !== intent.sessionId) return [workout];
        const blocks = workout.blocks.flatMap(block => {
          const sets = block.sets.filter(set => set.id !== intent.setId);
          return sets.length ? [{ ...block, sets }] : [];
        });
        return blocks.length ? [{ ...workout, blocks }] : [];
      }), mutationContext.account);
      if (!ledgerChange) throw new Error("Commit ledger could not record the set deletion.");
      return true;
    } catch {
      currentLocation.session.sets = previousSets;
      restoreDestructivePersistenceRecords(rollbackRecords);
      restoreActiveWorkoutCommitLedger(previousLedgerRaw, mutationContext.account);
      return false;
    }
  });
  if (!result.acquired || result.value !== true) return showDestructiveSaveFailure();
  modal = null;
  render();
  focusStableScreenContext();
  showToast(tx("Set deleted.", "Підхід видалено."));
}

async function deleteSession(id) {
  const matches = state.sessions.filter(session => session.id === id);
  if (matches.length !== 1) return showToast(tx(
    "This confirmation is no longer current. Nothing was changed.",
    "Це підтвердження вже неактуальне. Нічого не змінено."
  ));
  const session = matches[0];
  if (!window.confirm(tx(`Delete workout from ${fmtDate(session.startedAt)}?`, `Видалити тренування від ${fmtDate(session.startedAt)}?`))) return;
  const mutationContext = activeWorkoutMutationContext();
  if (!mutationContext) return showDestructiveSaveFailure();
  const result = await withActiveWorkoutDeletionLock(mutationContext.descriptor, () => {
    if (!activeWorkoutMutationContextIsCurrent(mutationContext)) return false;
    const currentMatches = state.sessions.filter(item => item.id === id);
    if (currentMatches.length !== 1) return false;
    const previousSessions = state.sessions;
    const rollbackRecords = destructivePersistenceRollbackRecords();
    let previousLedgerRaw;
    try {
      previousLedgerRaw = localStorage.getItem(mutationContext.descriptor.commitKey);
    } catch {
      return false;
    }
    if (!rollbackRecords) return false;
    state.sessions = previousSessions.filter(item => item.id !== id);
    try {
      saveState();
      if (!rewriteActiveWorkoutCommitLedger(
        workouts => workouts.filter(workout => workout.id !== id),
        mutationContext.account
      )) {
        throw new Error("Commit ledger could not record the workout deletion.");
      }
      return true;
    } catch {
      state.sessions = previousSessions;
      restoreDestructivePersistenceRecords(rollbackRecords);
      restoreActiveWorkoutCommitLedger(previousLedgerRaw, mutationContext.account);
      return false;
    }
  });
  if (!result.acquired || result.value !== true) return showDestructiveSaveFailure();
  modal = null;
  if (route().name === "detail" || route().name === "summary") {
    nav = [{ name: "workouts" }];
    workoutDetailEditSessionId = null;
    replaceNavigationHistory();
  }
  showToast(tx("Workout deleted.", "Тренування видалено."));
  render();
}

function findSet(id) {
  return state.sessions.flatMap(s => s.sets).find(s => s.id === id);
}

function isSupportedExerciseName(value) {
  const rawName = typeof value === "string" ? value : "";
  const contract = window.GymStateContract;
  if (contract.containsUnsupportedExerciseNameControls(rawName)) return false;
  const name = rawName.trim();
  const limits = contract.LIMITS;
  return Boolean(name && contract.unicodeCodePointLengthAtMost(name, limits.exerciseName) &&
    new TextEncoder().encode(name).byteLength <= limits.exerciseNameBytes);
}

function saveExercise() {
  const submittedName = document.querySelector("#new-exercise-name")?.value ?? "";
  const name = submittedName.trim();
  if (!name) return showToast(tx("Enter exercise name.", "Введи назву вправи."));
  if (!isSupportedExerciseName(submittedName)) return showToast(tx("Exercise name is too long.", "Назва вправи надто довга."));
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
  const rawSubmittedName = document.querySelector("#rename-name")?.value ?? "";
  const submittedName = rawSubmittedName.trim();
  if (!exercise || !submittedName) return;
  if (!isSupportedExerciseName(rawSubmittedName)) return showToast(tx("Exercise name is too long.", "Назва вправи надто довга."));
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

async function confirmImport() {
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
  const mutationContext = activeWorkoutMutationContext();
  if (!mutationContext) return showDestructiveSaveFailure();
  const result = await withActiveWorkoutDeletionLock(mutationContext.descriptor, () => {
    if (!activeWorkoutMutationContextIsCurrent(mutationContext) ||
        !destructiveIntentIsCurrent(intent)) return false;
    const previousState = state;
    const rollbackRecords = destructivePersistenceRollbackRecords();
    let previousLedgerRaw;
    try {
      previousLedgerRaw = localStorage.getItem(mutationContext.descriptor.commitKey);
    } catch {
      return false;
    }
    if (!rollbackRecords) return false;
    state = intent.nextState;
    try {
      persistDestructiveState(intent.storageSnapshot);
      if (!rewriteActiveWorkoutCommitLedger(() => [], mutationContext.account)) {
        throw new Error("Commit ledger could not be cleared for import.");
      }
      return true;
    } catch {
      state = previousState;
      restoreDestructivePersistenceRecords(rollbackRecords);
      restoreActiveWorkoutCommitLedger(previousLedgerRaw, mutationContext.account);
      return false;
    }
  });
  if (!result.acquired || result.value !== true) return showDestructiveSaveFailure();
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
  const target = currentExerciseRestTimers()[key];
  if (!target) return 0;
  return Math.max(0, Math.ceil((target - Date.now()) / 1000));
}

function startTimerTicker() {
  clearInterval(timerInterval);
  if (document.querySelector("[data-active-workout-elapsed]") ||
      Object.values(currentExerciseRestTimers()).some(target => target > Date.now())) {
    timerInterval = setInterval(updateTimerDisplays, 1000);
  }
}

function updateTimerDisplays() {
  const activeElapsed = document.querySelector("[data-active-workout-elapsed]");
  if (activeElapsed && activeWorkout) {
    activeElapsed.textContent = formatActiveWorkoutElapsed(activeWorkoutElapsedMillis(activeWorkout));
  }
  let hasActiveTimer = Boolean(activeElapsed && activeWorkout);
  document.querySelectorAll("[data-timer-display]").forEach(display => {
    const key = display.dataset.timerDisplay;
    const remaining = timerRemaining(key);
    hasActiveTimer ||= remaining > 0;
    display.textContent = remaining > 0 ? formatTimer(remaining) : tx("Ready", "Готово");
    document.querySelectorAll(`[data-timer-control="${CSS.escape(key)}"]`).forEach(control => {
      control.disabled = remaining <= 0;
    });
  });
  if (!hasActiveTimer) clearInterval(timerInterval);
}

function formatTimer(seconds) {
  return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
}

function formatActiveWorkoutElapsed(milliseconds) {
  const totalSeconds = Math.max(0, Math.floor(Number(milliseconds) / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor(totalSeconds % 3600 / 60);
  const seconds = totalSeconds % 60;
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
    : `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
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

function parseAppPushData(value) {
  const row = socialExactObject(value, ["version", "target"]);
  if (row.version !== 1 || !["live", "social"].includes(row.target)) {
    throw new TypeError("Push target is invalid.");
  }
  return { version: 1, target: row.target };
}

function openAppPushTarget(value) {
  let target;
  try {
    target = parseAppPushData(value);
  } catch {
    return false;
  }
  nav = [{ name: "leaderboard" }];
  replaceNavigationHistory();
  modal = null;
  render();
  if (target.target === "live") {
    if (activeAccount?.remote === "supabase") void refreshLiveWorkoutData(true);
  } else {
    if (activeAccount?.remote === "supabase") void refreshSocialData(true);
  }
  return true;
}

function captureAppPushTargetFromLocation() {
  try {
    const url = new URL(window.location.href);
    const kind = url.searchParams.get("notification");
    const target = ["live", "social"].includes(kind)
      ? { version: 1, target: kind }
      : null;
    if (!target) return null;
    url.searchParams.delete("notification");
    url.searchParams.delete("room");
    const clean = `${url.pathname}${url.search}${url.hash}`;
    history.replaceState(history.state, "", clean);
    return target;
  } catch {
    return null;
  }
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
  navigator.serviceWorker.addEventListener?.("message", event => {
    const message = event?.data;
    try {
      socialExactObject(message, ["version", "type", "target"]);
      if (message.version === 1 && message.type === "gymapp_notification_click") {
        openAppPushTarget({ version: 1, target: message.target });
      }
    } catch {
      // Ignore malformed messages from older/unrelated service workers.
    }
  });
}

window.addEventListener("storage", event => {
  if ((event.key === AUTH_KEY || event.key === null) && activeAccount?.remote === "supabase" &&
      !sharedActiveAccountMatches(activeAccount)) {
    // Auth credentials are tab-scoped but the browser Push subscription is
    // origin-wide. A tab that no longer owns the shared account marker must
    // never rebind or unsubscribe another account's installation.
    webPushGeneration += 1;
    webPushMutationInProgress = false;
    webPushState = { status: "idle", source: null, error: "" };
    void clearStoredWebPushBinding({ ownerId: activeAccount.userId }).catch(() => false);
    render();
  }
  const liveIdentity = liveSessionIdentity();
  const liveBindingKey = liveWorkoutBindingKey(liveIdentity?.userId);
  if (liveBindingKey && (event.key === liveBindingKey || event.key === null)) {
    liveWorkoutBinding = loadLiveWorkoutBinding();
    if (liveWorkoutBinding) {
      void refreshLiveWorkoutData(true, liveWorkoutBinding.roomId);
      void drainLiveWorkoutOperations();
    }
  }
  const activeDescriptor = activeWorkoutAccountDescriptor();
  if (activeDescriptor && event.key === activeDescriptor.commitKey) {
    state = loadState();
    const destructiveSnapshot = isDestructiveConfirmationModal()
      ? modal?.intent?.storageSnapshot
      : null;
    if (destructiveSnapshot && !destructiveStorageSnapshotIsCurrent(destructiveSnapshot)) {
      rejectStaleDestructiveConfirmation();
      return;
    }
    try {
      if (activeWorkoutMutationContext()) {
        markRemoteStateDirtyBeforeWrite(state);
        queueRemoteSave();
      }
    } catch {
      // The durable commit ledger remains available for the next reload/sync.
    }
    render();
    showToast(tx(
      "Workout history updated from another tab.",
      "Історію тренувань оновлено з іншої вкладки."
    ));
    return;
  }
  if (activeDescriptor && (event.key === activeDescriptor.storageKey ||
      event.key === activeDescriptor.undoKey || event.key === activeDescriptor.timingKey ||
      event.key === activeDescriptor.restTransitionKey ||
      event.key === activeDescriptor.bulkCleanupKey ||
      event.key === null)) {
    const previousRaw = activeWorkoutStorageRaw;
    const previousUndoRaw = activeWorkoutUndoStorageRaw;
    const discardConfirmationWasOpen = modal?.type === "confirm-discard-active";
    reloadActiveWorkoutContext();
    if (discardConfirmationWasOpen && previousRaw !== activeWorkoutStorageRaw) modal = null;
    if (!activeWorkout && route().name === "active") {
      nav = [{ name: "workouts" }];
      replaceNavigationHistory();
    }
    render();
    if (previousRaw !== activeWorkoutStorageRaw || previousUndoRaw !== activeWorkoutUndoStorageRaw) {
      showToast(tx(
        "Active workout updated from another tab.",
        "Активне тренування оновлено з іншої вкладки."
      ));
    }
    return;
  }
  if (modal?.type === "confirm-discard-active" && event.key === AUTH_KEY) {
    modal = null;
    render();
    showToast(tx(
      "The active workout changed, so discard was cancelled.",
      "Активне тренування змінилося, тому відкидання скасовано."
    ));
    return;
  }
  if (!isDestructiveConfirmationModal()) return;
  const snapshot = modal?.intent?.storageSnapshot;
  if (!snapshot || (event.key !== null && event.key !== snapshot.storageKey &&
      event.key !== snapshot.commitKey && event.key !== AUTH_KEY)) return;
  if (!destructiveStorageSnapshotIsCurrent(snapshot)) rejectStaleDestructiveConfirmation();
});

window.addEventListener("popstate", event => {
  const restoredNav = validatedHistoryNav(event.state?.gymAppNav);
  if (!restoredNav) return;
  const leavingAdd = route().name === "add" && restoredNav.at(-1)?.name !== "add";
  const leavingDetail = route().name === "detail" && restoredNav.at(-1)?.name !== "detail";
  if (leavingAdd) workoutDraft = null;
  if (leavingDetail) workoutDetailEditSessionId = null;
  nav = restoredNav;
  modal = null;
  languageMenuOpen = false;
  render();
  if (leavingAdd) routeScrollPositions.delete("add:root");
});

window.addEventListener("focus", () => {
  if (activeAccount?.remote !== "supabase" || document.visibilityState === "hidden") return;
  if (webPushSupported() && webPushPreferenceEnabled() &&
      window.Notification.permission !== "granted" && !webPushMutationInProgress) {
    void revokeWebPush();
  } else {
    syncWebPushIfEnabled();
  }
  if (Date.now() - socialLastLoadedAt >= SOCIAL_REFRESH_MIN_INTERVAL_MS &&
      socialState.status !== "loading" && !socialMutationInProgress) {
    void refreshSocialData(true);
  }
  if (liveWorkoutState.status !== "loading" && !liveWorkoutMutationInProgress) {
    void refreshLiveWorkoutData(true);
  }
});

document.addEventListener?.("visibilitychange", () => {
  if (document.visibilityState === "hidden") {
    clearTimeout(liveWorkoutPollTimer);
    liveWorkoutPollTimer = null;
    return;
  }
  if (activeAccount?.remote === "supabase" && !liveWorkoutMutationInProgress) {
    void refreshLiveWorkoutData(true);
  }
});

void resumeCloudAccountDeletionRecovery(startupCloudAccountDeletionRecovery).catch(() => {});

if (!handleEmailConfirmationRedirect()) {
  const startupPushTarget = captureAppPushTargetFromLocation();
  captureSharedWorkoutFromLocation();
  replaceNavigationHistory();
  if (activeWorkout) scheduleActiveWorkoutControlReconciliation(activeWorkout, activeAccount);
  render();
  if (startupPushTarget) openAppPushTarget(startupPushTarget);
  if (sharedWorkoutStartupError) {
    showToast(tx("This workout link is invalid or too large.", "Це посилання на тренування некоректне або завелике."));
  }
  const startupSync = loadRemoteSession()?.activation_pending
    ? retryPendingRemoteActivation().then(() => false)
    : pullRemoteState();
  startupSync
    .then(updated => {
      if (updated) render();
      if (activeAccount?.remote === "supabase") {
        void refreshSocialData(true);
        void refreshLiveWorkoutData(true);
        syncWebPushIfEnabled();
      }
    })
    .catch(error => {
      if (!transitionToReauthentication(error)) {
        showToast(tx("Cloud sync failed.", "Синхронізація не вдалася."));
      }
    });
}
