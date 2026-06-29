"use strict";

const STORAGE_KEY = "gym-pwa-state-v2";
const LEGACY_KEY = "gym-pwa-state-v1";
const AUTH_KEY = "gym-pwa-active-account-v1";
const ACCOUNT_LIST_KEY = "gym-pwa-account-list-v1";
const ACCOUNT_PREFIX = "gym-pwa-account:";
const REMOTE_SESSION_KEY = "gym-pwa-supabase-session-v1";
const GARMIN_DEVICE_TOKEN_KEY = "gym-pwa-garmin-device-token-v1";
const AUTH_REDIRECT_URL = "https://eduard047.github.io/GymApp/";
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
  ["chest", "Chest", "Груди"], ["shoulders", "Shoulders", "Плечі"], ["biceps", "Biceps", "Біцепс"], ["triceps", "Triceps", "Трицепс"],
  ["forearms", "Forearms", "Передпліччя"], ["abs", "Abs", "Прес"], ["obliques", "Obliques", "Косі м'язи"], ["upperBack", "Upper Back", "Верх спини"],
  ["lats", "Lats", "Широчайші"], ["lowerBack", "Lower Back", "Поперек"], ["glutes", "Glutes", "Сідниці"], ["quads", "Quads", "Квадрицепси"],
  ["hamstrings", "Hamstrings", "Біцепс стегна"], ["adductors", "Adductors", "Привідні"], ["calves", "Calves", "Ікри"]
];

const defaultMappings = {
  "bench press": ["chest", "triceps", "shoulders"], "incline dumbbell press": ["chest", "shoulders", "triceps"],
  "pull up": ["lats", "biceps", "upperBack"], "lat pulldown": ["lats", "biceps"], "barbell row": ["upperBack", "lats", "biceps"],
  "squat": ["quads", "glutes", "adductors"], "leg press": ["quads", "glutes"], "romanian deadlift": ["hamstrings", "glutes", "lowerBack"],
  "deadlift": ["hamstrings", "glutes", "lowerBack", "upperBack"], "shoulder press": ["shoulders", "triceps"],
  "lateral raise": ["shoulders"], "biceps curl": ["biceps", "forearms"], "triceps pushdown": ["triceps"],
  "calf raise": ["calves"], "plank": ["abs", "obliques"]
};

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

let activeAccount = loadActiveAccount();
let state = loadState();
let nav = [{ name: "workouts" }];
let modal = null;
let toastTimer = null;
let selectedMonthOffset = 0;
let overviewMode = "overview";
let musclePeriod = "month";
let selectedMuscle = null;
let leaderboardState = { status: "idle", rows: [], error: "" };
let leaderboardRequestController = null;
let leaderboardRequestId = 0;
let timerInterval = null;

function t(key) {
  return (text[state.language] || text.en)[key] || text.en[key] || key;
}

function tx(en, uk) {
  return state.language === "uk" ? uk : en;
}

function muscleLabel(id) {
  const row = muscles.find(([muscleId]) => muscleId === id);
  return row ? (state.language === "uk" ? row[2] : row[1]) : id;
}

function normalizeExerciseKey(name) {
  return String(name || "").toLowerCase().replace(/[\u02bc\u2019]/g, "'").replace(/\s+/g, " ").trim();
}

function n(count, enOne, enMany, ukOne, ukFew, ukMany) {
  if (state.language !== "uk") return `${count} ${count === 1 ? enOne : enMany}`;
  const mod10 = count % 10;
  const mod100 = count % 100;
  const word = mod10 === 1 && mod100 !== 11 ? ukOne : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) ? ukFew : ukMany;
  return `${count} ${word}`;
}

function defaultAppState() {
  return {
    language: "en",
    exercises: defaultExercises.map((name, index) => ({ id: index + 1, name })),
    sessions: [],
    mappings: { ...defaultMappings },
    profile: { split: "Push Pull Legs", days: 4, goal: "Balanced", calories: "Maintenance" }
  };
}

function normalizeAccountId(name) {
  return String(name || "").toLowerCase().replace(/[^a-z0-9а-яіїєґ_-]+/gi, "-").replace(/^-+|-+$/g, "").slice(0, 48);
}

function loadActiveAccount() {
  try {
    const parsed = JSON.parse(localStorage.getItem(AUTH_KEY) || "null");
    return parsed?.id && parsed?.name && parsed?.remote ? parsed : null;
  } catch {
    return null;
  }
}

function activeStorageKey(account = activeAccount) {
  return account?.id ? ACCOUNT_PREFIX + account.id : STORAGE_KEY;
}

function accountList() {
  try {
    const parsed = JSON.parse(localStorage.getItem(ACCOUNT_LIST_KEY) || "[]");
    return Array.isArray(parsed) ? parsed.filter(item => item?.id && item?.name) : [];
  } catch {
    return [];
  }
}

function saveAccountList(accounts) {
  const unique = [];
  accounts.forEach(account => {
    if (account?.id && !unique.some(item => item.id === account.id)) unique.push(account);
  });
  localStorage.setItem(ACCOUNT_LIST_KEY, JSON.stringify(unique));
}

function supabaseConfig() {
  const config = window.GYM_SUPABASE || {};
  return {
    url: String(config.url || "").replace(/\/+$/, ""),
    anonKey: String(config.anonKey || "")
  };
}

function remoteAuthEnabled() {
  const config = supabaseConfig();
  return Boolean(config.url && config.anonKey);
}

function loadRemoteSession() {
  try {
    const parsed = JSON.parse(localStorage.getItem(REMOTE_SESSION_KEY) || "null");
    return parsed?.access_token && parsed?.user?.id ? parsed : null;
  } catch {
    return null;
  }
}

function saveRemoteSession(session) {
  localStorage.setItem(REMOTE_SESSION_KEY, JSON.stringify(session));
}

function accessTokenExpirationSeconds(session) {
  try {
    const payload = String(session?.access_token || "").split(".")[1];
    if (!payload) return null;
    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    const decoded = JSON.parse(atob(padded));
    return Number(decoded.exp) || null;
  } catch {
    return null;
  }
}

function remoteSessionNeedsRefresh(session) {
  const expiresAt = accessTokenExpirationSeconds(session);
  return Boolean(expiresAt && expiresAt - Math.floor(Date.now() / 1000) <= 60);
}

async function refreshRemoteSession(session = loadRemoteSession()) {
  if (!session?.refresh_token) return session;
  const config = supabaseConfig();
  const response = await fetch(`${config.url}/auth/v1/token?grant_type=refresh_token`, {
    method: "POST",
    headers: {
      apikey: config.anonKey,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ refresh_token: session.refresh_token })
  });
  if (!response.ok) {
    localStorage.removeItem(REMOTE_SESSION_KEY);
    throw new Error(await response.text().catch(() => "") || `Session refresh failed: ${response.status}`);
  }
  const refreshed = await response.json();
  const nextSession = {
    ...session,
    ...refreshed,
    user: refreshed.user || session.user,
    refresh_token: refreshed.refresh_token || session.refresh_token
  };
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
  const { timeoutMs = 12000, ...fetchOptions } = options;
  const isAuthRequest = path.startsWith("/auth/v1/");
  let requestSession = fetchOptions.session || loadRemoteSession();
  if (!isAuthRequest && requestSession?.access_token && remoteSessionNeedsRefresh(requestSession)) {
    requestSession = await refreshRemoteSession(requestSession);
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  if (fetchOptions.signal) {
    fetchOptions.signal.addEventListener("abort", () => controller.abort(), { once: true });
  }
  const request = () => fetch(`${config.url}${path}`, {
      ...fetchOptions,
      signal: controller.signal,
      headers: { ...remoteHeaders(requestSession), ...(fetchOptions.headers || {}) }
    });
  let response;
  try {
    response = await request();
    if (response.status === 401 && !isAuthRequest && requestSession?.refresh_token) {
      requestSession = await refreshRemoteSession(requestSession);
      response = await request();
    }
  } finally {
    clearTimeout(timeout);
  }
  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error(text || `Request failed: ${response.status}`);
  }
  if (response.status === 204) return null;
  const body = await response.text();
  return body ? JSON.parse(body) : null;
}

function remoteAccountFromSession(session) {
  const email = session?.user?.email || "";
  return {
    id: `remote-${session.user.id}`,
    name: session.user.user_metadata?.display_name || email.split("@")[0] || "Supabase",
    email,
    userId: session.user.id,
    remote: "supabase"
  };
}

async function loadRemoteState(session) {
  const rows = await supabaseRequest(`/rest/v1/user_states?user_id=eq.${encodeURIComponent(session.user.id)}&select=state`, { session });
  return Array.isArray(rows) && rows[0]?.state ? rows[0].state : null;
}

async function pullRemoteState() {
  if (!activeAccount?.remote || !remoteAuthEnabled()) return false;
  const session = loadRemoteSession();
  if (!session?.user?.id) return false;
  const cloudState = await loadRemoteState(session);
  if (!cloudState) return false;
  state = normalizeImportedState(cloudState, defaultAppState());
  saveState();
  return true;
}

function remoteStatePayload() {
  return JSON.parse(JSON.stringify({
    language: state.language,
    exercises: state.exercises,
    sessions: state.sessions,
    mappings: state.mappings,
    profile: state.profile
  }));
}

let remoteSaveTimer = null;

function queueRemoteSave() {
  if (!activeAccount?.remote || !remoteAuthEnabled()) return;
  clearTimeout(remoteSaveTimer);
  remoteSaveTimer = setTimeout(() => saveRemoteState().catch(() => showToast(tx("Cloud sync failed.", "Синхронізація не вдалася."))), 700);
}

async function saveRemoteState() {
  const session = loadRemoteSession();
  if (!session?.user?.id) return;
  const payload = remoteStatePayload();
  await supabaseRequest("/rest/v1/user_states?on_conflict=user_id", {
    method: "POST",
    session,
    headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({ user_id: session.user.id, state: payload, updated_at: new Date().toISOString() })
  });
  await supabaseRequest("/rest/v1/profiles?on_conflict=user_id", {
    method: "POST",
    session,
    headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({
      user_id: session.user.id,
      display_name: activeAccount.name,
      xp: totalXp(),
      level: levelFromXp(totalXp()),
      workouts: state.sessions.length,
      updated_at: new Date().toISOString()
    })
  });
}

function draftToGarminPlan(draft = modal?.draft) {
  if (!draft) return null;
  const exercises = [];
  draft.blocks.forEach(block => {
    const name = String(block.exerciseName || "").trim();
    if (!name) return;
    const sets = [];
    block.sets.forEach((set, index) => {
      const weight = Number(String(set.weight).replace(",", "."));
      const reps = Number.parseInt(set.reps, 10);
      if (Number.isFinite(weight) && weight >= 0 && reps > 0) {
        sets.push({ weight, reps, orderIndex: index });
      }
    });
    if (sets.length) exercises.push({ name, sets });
  });
  if (!exercises.length) return null;
  return {
    source: "pwa",
    version: 1,
    title: tx("Workout plan", "Workout plan"),
    createdAt: new Date().toISOString(),
    startedAt: new Date(draft.startedAt || Date.now()).toISOString(),
    note: draft.note || "",
    exercises
  };
}

async function ensureGarminDeviceToken(session) {
  const current = localStorage.getItem(GARMIN_DEVICE_TOKEN_KEY);
  if (current) return current;
  const response = await supabaseRequest("/functions/v1/garmin-sync", {
    method: "POST",
    session,
    body: JSON.stringify({ action: "createDevice", displayName: "Garmin watch" })
  });
  const token = response?.device?.device_token;
  if (!token) throw new Error("Garmin device token was not created.");
  localStorage.setItem(GARMIN_DEVICE_TOKEN_KEY, token);
  try {
    await navigator.clipboard?.writeText(token);
  } catch (_) {
  }
  return token;
}

async function queueGarminPlanFromDraft() {
  if (!remoteAuthEnabled()) return showToast(tx("Cloud login is not configured.", "Cloud login is not configured."));
  const session = loadRemoteSession();
  if (!session?.user?.id) return showToast(tx("Log in to cloud first.", "Log in to cloud first."));
  const plan = draftToGarminPlan();
  if (!plan) return showToast(tx("Please fill exercises and sets first.", "Please fill exercises and sets first."));

  let tokenWasCreated = false;
  let token = localStorage.getItem(GARMIN_DEVICE_TOKEN_KEY);
  if (!token) {
    token = await ensureGarminDeviceToken(session);
    tokenWasCreated = true;
  }

  await supabaseRequest("/rest/v1/garmin_plans", {
    method: "POST",
    session,
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify({ user_id: session.user.id, status: "pending", plan })
  });

  if (tokenWasCreated) {
    showToast(tx("Garmin token copied. Paste it once in Connect IQ settings, then sync on watch.", "Garmin token copied. Paste it once in Connect IQ settings, then sync on watch."));
  } else {
    showToast(tx("Plan queued for Garmin. Open the watch app and run Cloud sync.", "Plan queued for Garmin. Open the watch app and run Cloud sync."));
  }
}

function loadState() {
  const fallback = defaultAppState();
  try {
    const currentRaw = localStorage.getItem(activeStorageKey());
    const legacyRaw = localStorage.getItem(LEGACY_KEY);
    const raw = currentRaw || (!activeAccount ? legacyRaw : null);
    if (!raw) return fallback;
    const parsed = JSON.parse(raw);
    const normalizedSessions = Array.isArray(parsed.sessions) ? normalizeSessions(parsed.sessions) : [];
    const legacySessions = legacyRaw ? normalizeSessions(JSON.parse(legacyRaw).sessions || []) : [];
    const sessions = normalizedSessions.length && !allSetsFromSessions(normalizedSessions).length && allSetsFromSessions(legacySessions).length ? legacySessions : normalizedSessions;
    return {
      ...fallback,
      ...parsed,
      exercises: normalizeExerciseCatalog(parsed.exercises || parsed.exerciseCatalog, fallback.exercises),
      sessions,
      mappings: { ...fallback.mappings, ...(parsed.mappings || {}) },
      profile: { ...fallback.profile, ...(parsed.profile || {}) }
    };
  } catch {
    return fallback;
  }
}

function normalizeImportedState(parsed, fallback = defaultAppState()) {
  const normalizedSessions = Array.isArray(parsed.sessions) ? normalizeSessions(parsed.sessions) : [];
  return {
    ...fallback,
    ...parsed,
    exercises: normalizeExerciseCatalog(parsed.exercises || parsed.exerciseCatalog, fallback.exercises),
    sessions: normalizedSessions,
    mappings: { ...fallback.mappings, ...(parsed.mappings || {}) },
    profile: { ...fallback.profile, ...(parsed.profile || {}) }
  };
}

function normalizeSessions(sessions) {
  return sessions.map(session => ({
    id: Number(session.id || uid()),
    startedAt: Number(session.startedAt || session.date || Date.now()),
    note: session.note || "",
    exerciseNames: normalizeSessionExerciseNames(session),
    sets: normalizeSessionSets(session)
  }));
}

function normalizeSessionSets(session) {
  const flatSets = Array.isArray(session.sets) ? session.sets : [];
  const sessionExercises = nestedSessionExercises(session);
  const nestedSets = sessionExercises
    .flatMap(exercise => nestedExerciseSets(exercise).map(set => ({
      ...set,
      exerciseName: set.exerciseName || exerciseNameFromImport(exercise)
    })));
  return [...flatSets, ...nestedSets].flatMap((set, index) => {
    const exerciseName = set.exerciseName || set.name || set.exercise || set.title;
    if (!exerciseName) return [];
    return [{
      id: Number(set.id || uid() + index),
      exerciseName: String(exerciseName),
      weight: Number(set.weight ?? set.weightKg ?? set.kg ?? 0),
      reps: Number(set.reps ?? set.repeatCount ?? set.count ?? 0),
      orderIndex: set.orderIndex ?? set.index ?? index
    }];
  }).filter(set => set.reps > 0);
}

function normalizeSessionExerciseNames(session) {
  const names = [
    ...nestedSessionExercises(session).map(exerciseNameFromImport),
    ...(Array.isArray(session.sets) ? session.sets.map(set => set.exerciseName || set.name || set.exercise || set.title) : [])
  ].map(name => String(name || "").trim()).filter(Boolean);
  return [...new Set(names)];
}

function nestedSessionExercises(session) {
  return [session.exercises, session.workoutExercises, session.exerciseDetails, session.items]
    .find(Array.isArray) || [];
}

function nestedExerciseSets(exercise) {
  return [exercise.sets, exercise.setEntries, exercise.entries, exercise.history]
    .find(Array.isArray) || [];
}

function exerciseNameFromImport(exercise) {
  if (typeof exercise === "string") return exercise;
  if (exercise.exercise && typeof exercise.exercise === "object") return exercise.exercise.name || exercise.exercise.title;
  return exercise.name || exercise.exerciseName || exercise.title;
}

function normalizeExerciseCatalog(input, fallback = []) {
  const items = Array.isArray(input) ? input : [];
  const normalized = items.map((item, index) => ({
    id: Number(item?.id || index + 1),
    name: String(typeof item === "string" ? item : item?.name || item?.exerciseName || item?.title || "").trim()
  })).filter(item => item.name);
  return normalized.length ? normalized : fallback;
}

function saveState() {
  localStorage.setItem(activeStorageKey(), JSON.stringify(state));
  queueRemoteSave();
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
  if (route().name === "add" && nav.length > 1) {
    modal = null;
    nav.pop();
  } else if (modal) modal = null;
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
  const names = exerciseNamesForSession(session);
  return {
    exercises: names.length,
    sets: session.sets.length,
    volume: totalVolume([session])
  };
}

function exerciseNamesForSession(session) {
  return [...new Set([...(session.exerciseNames || []), ...((session.sets || []).map(set => set.exerciseName))].filter(Boolean))];
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

function loginScreen() {
  const accounts = accountList().filter(account => !account.remote);
  const remoteEnabled = remoteAuthEnabled();
  return `<div class="app-shell auth-shell">
    <header class="topbar"><span></span><h1>${tx("Login", "Вхід")}</h1><button class="icon-button" data-action="language" aria-label="Language">${svg("lang")}</button></header>
    <main class="screen auth-screen">
      <section class="hero-panel auth-hero"><p class="eyebrow">${tx("Training log", "Журнал тренувань")}</p><h2>GymApp</h2><p>${remoteEnabled ? tx("Sign in to sync workouts across devices.", "Увійди, щоб синхронізувати тренування між пристроями.") : tx("Cloud login is ready after Supabase keys are added.", "Хмарний вхід запрацює після додавання ключів Supabase.")}</p></section>
      ${remoteEnabled ? `<section class="panel auth-panel"><h2>${tx("Cloud account", "Хмарний акаунт")}</h2><div class="field-stack"><input id="login-email" autocomplete="email" inputmode="email" placeholder="email@example.com"><input id="login-password" autocomplete="current-password" type="password" placeholder="${tx("Password", "Пароль")}"></div><div class="actions login-actions"><button class="button" data-action="remote-login">${tx("Log in", "Увійти")}</button></div><details class="signup-details" open><summary>${tx("Create account", "Створити акаунт")}</summary><div class="field-stack"><input id="signup-name" autocomplete="name" placeholder="${tx("Display name", "Ім'я в рейтингу")}"><input id="signup-email" autocomplete="email" inputmode="email" placeholder="email@example.com"><input id="signup-password" autocomplete="new-password" type="password" placeholder="${tx("Password", "Пароль")}"><input id="signup-password-confirm" autocomplete="new-password" type="password" placeholder="${tx("Repeat password", "Повтори пароль")}"><p class="muted">${tx("Use 8+ characters with letters and numbers.", "Використай 8+ символів з літерами й цифрами.")}</p><button class="button ghost" data-action="remote-signup">${tx("Create account", "Створити акаунт")}</button></div></details></section>` : ""}
      <section class="panel auth-panel"><h2>${tx("Local account", "Локальний акаунт")}</h2><p class="muted">${remoteEnabled ? tx("Offline fallback for this browser only.", "Запасний режим лише для цього браузера.") : tx("Paste Supabase keys into supabase-config.js to enable real network login.", "Встав ключі Supabase у supabase-config.js, щоб увімкнути справжній мережевий вхід.")}</p><div class="field-row login-row"><input id="local-login-name" autocomplete="username" placeholder="${tx("Name", "Ім'я")}"><button class="button" data-action="login-account">${tx("Enter", "Увійти")}</button></div></section>
      ${accounts.length ? `<section class="panel"><h2>${tx("Saved accounts", "Збережені акаунти")}</h2><div class="chip-row">${accounts.map(account => `<button class="chip buttonlike" data-action="login-account" data-name="${escapeAttr(account.name)}">${escapeHtml(account.name)}</button>`).join("")}</div></section>` : ""}
      <div id="toast" class="toast hidden"></div>
    </main>
  </div>`;
}

function render() {
  if (!activeAccount) {
    app.innerHTML = loginScreen();
    bindEvents();
    return;
  }
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
  if (current.name === "leaderboard") refreshLeaderboard();
}

function isRootRoute(name) {
  return ["workouts", "missions", "exercises", "progress", "leaderboard"].includes(name);
}

function titleForRoute(current) {
  return {
    workouts: t("workouts"), missions: t("missions"), exercises: t("exercises"), progress: t("progress"), leaderboard: tx("Rating", "Рейтинг"),
    add: t("addWorkout"), detail: tx("Workout Details", "Деталі тренування"), summary: tx("Workout Summary", "Підсумок тренування"), ranks: t("ranks")
  }[current.name] || "Gym Workout Tracker";
}

function bottomNav() {
  const tabs = [["workouts", "list", t("workouts")], ["missions", "medal", t("missions")], ["exercises", "weight", t("exercises")], ["progress", "chart", t("progress")], ["leaderboard", "trophy", tx("Rating", "Рейтинг")]];
  return `<nav class="bottom-nav">${tabs.map(([id, icon, label]) => `
    <button class="tab-button ${route().name === id ? "active" : ""}" data-route="${id}">${svg(icon)}<span>${label}</span></button>`).join("")}</nav>`;
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
    <div class="workout-head"><div><h3 class="workout-title">${tx("Workout", "Тренування")} ${fmtDate(session.startedAt)}</h3><span class="muted">${session.note ? `${t("note")}: ${escapeHtml(session.note)}` : tx("No note", "Без нотатки")}</span></div><div class="actions"><span class="chip">${tx("Sets", "Підходи")}: ${summary.sets}</span><button class="icon-button" data-action="delete-session" data-id="${session.id}" aria-label="${tx("Delete workout", "Видалити тренування")}">${svg("delete")}</button></div></div>
    <div class="chip-row"><span class="chip">${tx("Exercises", "Вправи")}: ${summary.exercises}</span><span class="chip">${tx("Sets", "Підходи")}: ${summary.sets}</span><span class="chip">${tx("Volume", "Обсяг")}: ${Math.round(summary.volume)}</span>${exerciseNamesForSession(session).slice(0, 5).map(name => `<span class="chip">${escapeHtml(name)}</span>`).join("")}</div>
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
    <div class="heatmap-grid">${cells.map(day => `<button class="heat-cell ${day ? "" : "outside"}" style="${day ? `--i:${(byDay.get(day) || 0) / max}` : ""}" title="${day || ""}">${day || ""}</button>`).join("")}</div>
    <div class="legend"><span>${tx("Less", "Менше")}</span><i></i><i></i><i></i><i></i><span>${tx("More", "Більше")}</span></div>
  </section>`;
}

function mappingOverviewCard() {
  const rows = groupedExercises().sort((a, b) => Number(!mappingFor(a.name).length) - Number(!mappingFor(b.name).length) || a.name.localeCompare(b.name));
  return `<div class="subpanel"><div class="row-head"><div><h3>${tx("Exercise mapping", "Мапінг вправ")}</h3><p>${tx("Auto mapping works first, manual choices override it.", "Автомапінг працює базово, ручний вибір перекриває його.")}</p></div><span class="pill">${mappedCount()}/${state.exercises.length}</span></div>${rows.length ? rows.map(ex => {
    const ids = mappingFor(ex.name);
    const labels = ids.length ? ids.map(muscleLabel).join(", ") : tx("Not mapped", "Не зіставлено");
    return `<div class="row-line mapping-row"><span>${escapeHtml(ex.name)}<small>${escapeHtml(labels)}</small></span><button class="button secondary mini" data-action="map-exercise" data-name="${escapeAttr(ex.name)}">${tx("Map", "Мапити")}</button></div>`;
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
    ${selected ? `<div class="subpanel"><h3>${tx("Exercises for", "Вправи для")}: ${selected.label}</h3>${selectedExercises.length ? selectedExercises.map(ex => `<div class="row-line"><span>${escapeHtml(ex.name)}</span><span class="muted">${n(ex.sets, "set", "sets", "підхід", "підходи", "підходів")} - ${n(ex.sessions.size, "session", "sessions", "сесія", "сесії", "сесій")} - ${Math.round(ex.load)} ${tx("load", "навантаження")}</span><button class="button ghost mini" data-action="map-exercise" data-name="${escapeAttr(ex.name)}">${tx("Map", "Мапити")}</button></div>`).join("") : `<div class="empty">${tx("No logged exercises for this muscle in the selected period.", "У вибраному періоді для цієї групи ще немає вправ.")}</div>`}</div>` : ""}
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
  return state.exercises.filter(ex => contributionFor(ex.name).length).length;
}

function mappingFor(name) {
  const manual = state.mappings[normalizeExerciseName(name)];
  if (manual?.length) return manual;
  return contributionFor(name).map(item => item.muscleId);
}

function contributionFor(name) {
  const normalized = normalizeExerciseName(name);
  const manual = state.mappings[normalized];
  if (manual?.length) return manual.map(muscleId => ({ muscleId, weight: 1 }));
  if (exactMuscleMap[normalized]?.length) return exactMuscleMap[normalized];
  return inferMuscleContributions(name);
}

function normalizeExerciseName(name) {
  return normalizeExerciseKey(name);
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
  const map = new Map(muscles.map(([id]) => [id, { id, label: muscleLabel(id), load: 0, sets: 0, sessions: new Set(), exercises: [] }]));
  allSets(sessions).forEach(set => {
    const contributions = contributionFor(set.exerciseName);
    contributions.forEach(contribution => {
      const item = map.get(contribution.muscleId);
      if (!item) return;
      const trackedLoad = Math.max(0, Number(set.weight || 0)) * Math.max(0, Number(set.reps || 0));
      const load = (trackedLoad > 0 ? trackedLoad : 72 * Math.max(0, Number(set.reps || 0))) + 35;
      const weightedLoad = load * contribution.weight;
      item.load += weightedLoad;
      item.sets += 1;
      item.sessions.add(set.session.id);
      let exercise = item.exercises.find(ex => ex.name === set.exerciseName);
      if (!exercise) {
        exercise = { name: set.exerciseName, load: 0, sets: 0, sessions: new Set() };
        item.exercises.push(exercise);
      }
      exercise.load += weightedLoad;
      exercise.sets += 1;
      exercise.sessions.add(set.session.id);
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
  const title = block.exerciseName || `${tx("Exercise", "Вправа")} ${blockIndex + 1}`;
  return `<section class="draft-exercise panel highlighted"><details open><summary class="detail-summary"><div><h2>${escapeHtml(title)}</h2><p class="muted">${escapeHtml(draftSetSummary(block))}</p></div><button class="icon-button" data-action="remove-block" data-block="${blockIndex}" aria-label="${tx("Remove exercise", "Прибрати вправу")}">${svg("delete")}</button></summary>
    <label>${tx("Exercise", "Вправа")}<input list="exercise-options" data-block="${blockIndex}" data-field="exerciseName" value="${escapeAttr(block.exerciseName)}" placeholder="${tx("Select exercise", "Обери вправу")}"></label>
    <datalist id="exercise-options">${state.exercises.map(ex => `<option value="${escapeAttr(ex.name)}"></option>`).join("")}</datalist>
    ${block.exerciseName ? muscleContributionPanel(block.exerciseName, false) : ""}
    ${lastWeight != null ? `<div class="row-line"><strong>${tx("Last", "Остання")}: ${lastWeight.toFixed(1)} kg</strong><button class="button ghost mini" data-action="apply-last" data-block="${blockIndex}">${t("useLast")}</button></div>` : ""}
    ${rec ? smartPanel(rec, blockIndex) : ""}
    <div class="actions"><button class="button ghost" data-action="add-set" data-block="${blockIndex}">${t("addSet")}</button><button class="button ghost" data-action="copy-set" data-block="${blockIndex}">${t("copyLast")}</button><button class="button ghost" data-action="plus-set" data-block="${blockIndex}">${t("copyPlus")}</button></div>
    ${block.sets.map((set, setIndex) => `<div class="set-row"><span>${tx("Set", "Підхід")} ${setIndex + 1}</span><input inputmode="decimal" aria-label="${tx("Weight", "Вага")}" data-block="${blockIndex}" data-set="${setIndex}" data-field="weight" value="${escapeAttr(set.weight)}" placeholder="kg"><input inputmode="numeric" aria-label="${tx("Reps", "Повтори")}" data-block="${blockIndex}" data-set="${setIndex}" data-field="reps" value="${escapeAttr(set.reps)}"><button class="icon-button" data-action="remove-set" data-block="${blockIndex}" data-set="${setIndex}">${svg("delete")}</button></div>`).join("")}
  </details></section>`;
}

function smartPanel(rec, blockIndex) {
  return `<div class="subpanel smart"><div class="row-head"><div><strong>${t("smartCoach")}</strong><p>${rec.kind}</p></div>${svg("auto", "small-icon")}</div><p>${rec.sets.map(s => `${s.weight == null ? tx("light", "легко") : `${s.weight.toFixed(1)} kg`} x ${s.reps}`).join(" | ")}</p><div class="progress"><span style="width:${rec.confidence * 100}%"></span></div><small>${tx("Confidence", "Впевненість")} ${Math.round(rec.confidence * 100)}%</small>${rec.reasons.slice(0, 3).map(reason => `<p class="muted">${escapeHtml(reason)}</p>`).join("")}<button class="button full" data-action="apply-smart" data-block="${blockIndex}">${svg("auto", "small-icon")}${t("applySmart")}</button></div>`;
}

function draftSetSummary(block) {
  const setLabel = `${block.sets.length} ${tx("sets", "підходів")}`;
  const details = block.sets.map(set => `${set.weight === "" ? "—" : formatSetWeight(set.weight)} kg x ${set.reps || "—"}`).join(" · ");
  return details ? `${setLabel} · ${details}` : setLabel;
}

function muscleContributionPanel(name, compact = false) {
  const contributions = contributionFor(name).slice(0, compact ? 3 : 6);
  if (!contributions.length) return "";
  return `<div class="chip-row">${contributions.map(item => `<span class="chip">${muscleLabel(item.muscleId)} ${Math.round(item.weight * 100)}%</span>`).join("")}</div>`;
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

function legacyDetailScreenOld(id) {
  const session = state.sessions.find(s => s.id === id);
  if (!session) return `<div class="empty">${tx("Workout not found.", "Тренування не знайдено.")}</div>`;
  const grouped = exerciseNamesForSession(session).map(name => ({ name, sets: session.sets.filter(s => s.exerciseName === name) }));
  const available = state.exercises.filter(ex => !grouped.some(g => g.name === ex.name));
  const garmin = parseGarminWorkoutMetrics(session.note || "");
  return `<section class="panel"><h2>${fmtDate(session.startedAt)}</h2><p>${session.note || tx("No note", "Без нотатки")}</p></section>
    ${!session.sets.length && grouped.length ? `<section class="panel warning"><h2>${tx("No set data", "Немає даних підходів")}</h2><p>${tx("This imported workout contains exercise names, but no weights or reps. Export a full Backup JSON from the Android app and import it again.", "У цьому імпортованому тренуванні є назви вправ, але немає ваги й повторів. Експортуй повний Backup JSON з Android-додатка й імпортуй ще раз.")}</p></section>` : ""}
    <section class="panel"><div class="section-title"><h2>${tx("Add Exercise to This Workout", "Додати вправу в це тренування")}</h2></div>${available.length ? `<select id="quick-add">${available.map(ex => `<option value="${ex.id}">${escapeHtml(ex.name)}</option>`).join("")}</select><button class="button full" data-action="quick-add-exercise">${tx("Add to Workout", "Додати до тренування")}</button>` : `<p class="muted">${tx("All saved exercises are already in this workout.", "Усі збережені вправи вже є в цьому тренуванні.")}</p>`}</section>
    ${garmin ? garminWorkoutMetricsCard(session, garmin, grouped) : ""}
    ${grouped.map(group => exerciseDetailCard(session, group, Boolean(garmin))).join("")}
    <button class="fab" data-action="finish-workout" data-id="${session.id}">${svg("check", "small-icon")}${t("finishWorkout")}</button>`;
}

function legacyExerciseDetailCard(session, group) {
  const key = `${session.id}:${group.name}`;
  const remaining = timerRemaining(key);
  return `<section class="panel highlighted"><div class="row-head"><h2>${escapeHtml(group.name)}</h2>${isPr(session, group.name) ? `<span class="pill">${svg("trophy", "small-icon")}${tx("New PR", "Новий PR")}</span>` : ""}</div>
    ${group.sets.length ? `<div class="timer-row"><div><strong>${tx("Exercise Rest", "Відпочинок")}</strong><span>${remaining > 0 ? formatTimer(remaining) : tx("Ready", "Готово")}</span></div><div class="actions"><button class="button ghost mini" data-action="timer" data-key="${key}" data-seconds="60">60s</button><button class="button ghost mini" data-action="timer" data-key="${key}" data-seconds="90">90s</button><button class="button ghost mini" data-action="timer" data-key="${key}" data-seconds="180">180s</button><button class="button ghost mini" data-action="timer-stop" data-key="${key}" ${remaining ? "" : "disabled"}>${tx("Stop", "Стоп")}</button></div></div>
    <div class="table"><div class="table-head"><span>${tx("Set", "Підхід")}</span><span>${tx("Weight (kg)", "Вага (кг)")}</span><span>${tx("Reps", "Повтори")}</span><span></span></div>${group.sets.map((set, i) => `<div class="table-row"><span>${tx("Set", "Підхід")} ${i + 1}</span><span>${Number(set.weight).toFixed(1)}</span><span>${set.reps}</span><span><button class="icon-button" data-action="edit-set" data-id="${set.id}">${svg("edit")}</button><button class="icon-button" data-action="delete-set" data-id="${set.id}">${svg("delete")}</button></span></div>`).join("")}</div>` : `<div class="empty">${tx("No sets were imported for this exercise.", "Для цієї вправи не імпортовано підходи.")}</div>`}
    <button class="button ghost full" data-action="detail-add-set" data-session="${session.id}" data-name="${escapeAttr(group.name)}">${t("addSet")}</button>
  </section>`;
}

function detailScreen(id) {
  const session = state.sessions.find(s => s.id === id);
  if (!session) return `<div class="empty">${tx("Workout not found.", "Workout not found.")}</div>`;
  const grouped = exerciseNamesForSession(session).map(name => ({ name, sets: session.sets.filter(s => s.exerciseName === name) }));
  const available = state.exercises.filter(ex => !grouped.some(g => g.name === ex.name));
  const garmin = parseGarminWorkoutMetrics(session.note || "");
  return `${garmin ? garminWorkoutHeader(session, garmin, grouped) : workoutHeader(session)}
    ${garmin ? garminWorkoutMetricsCard(garmin) : ""}
    ${!session.sets.length && grouped.length ? `<section class="panel warning"><h2>${tx("No set data", "No set data")}</h2><p>${tx("This imported workout contains exercise names, but no weights or reps. Export a full Backup JSON from the Android app and import it again.", "This imported workout contains exercise names, but no weights or reps. Export a full Backup JSON from the Android app and import it again.")}</p></section>` : ""}
    <section class="panel"><div class="section-title"><div><h2>${tx("Add Exercise to This Workout", "Add Exercise to This Workout")}</h2></div>${svg("add", "small-icon")}</div>${available.length ? `<select id="quick-add">${available.map(ex => `<option value="${ex.id}">${escapeHtml(ex.name)}</option>`).join("")}</select><button class="button full" data-action="quick-add-exercise">${tx("Add to Workout", "Add to Workout")}</button>` : `<p class="muted">${tx("All saved exercises are already in this workout.", "All saved exercises are already in this workout.")}</p>`}</section>
    ${grouped.map(group => exerciseDetailCard(session, group, Boolean(garmin))).join("")}
    <button class="fab" data-action="finish-workout" data-id="${session.id}">${svg("check", "small-icon")}${t("finishWorkout")}</button>`;
}

function workoutHeader(session) {
  return `<section class="panel"><div class="row-head"><div><h2>${fmtDate(session.startedAt)}</h2><p>${session.note ? `${t("note")}: ${escapeHtml(session.note)}` : tx("No note", "No note")}</p></div><button class="icon-button" data-action="delete-session" data-id="${session.id}" aria-label="${tx("Delete workout", "Delete workout")}">${svg("delete")}</button></div></section>`;
}

function garminWorkoutHeader(session, metrics, grouped) {
  const setCount = grouped.reduce((sum, group) => sum + group.sets.length, 0);
  return `<section class="panel highlighted garmin-header"><div class="row-head"><div><h2>${tx("Garmin strength workout", "Garmin strength workout")}</h2><p class="muted">${fmtDate(session.startedAt)} · ${tx("synced from Fenix 8", "synced from Fenix 8")}</p></div><button class="icon-button" data-action="delete-session" data-id="${session.id}" aria-label="${tx("Delete workout", "Delete workout")}">${svg("delete")}</button></div>
    <div class="metric-grid"><div><span>${tx("Duration", "Duration")}</span><strong>${metrics.duration || "—"}</strong><small>${tx("watch session", "watch session")}</small></div><div><span>${tx("Logged", "Logged")}</span><strong>${setCount} ${tx("sets", "sets")}</strong><small>${grouped.length} ${tx("exercises", "exercises")}</small></div></div>
    <p class="muted">${tx("Synced sets are grouped below. Expand an exercise to edit weight, reps, add a missed set, or delete a wrong one.", "Synced sets are grouped below. Expand an exercise to edit weight, reps, add a missed set, or delete a wrong one.")}</p>
  </section>`;
}

function garminWorkoutMetricsCard(metrics) {
  return `<section class="panel garmin-metrics"><h2>${tx("Garmin strength metrics", "Garmin strength metrics")}</h2>
    <div class="metric-grid">
      <div><span>${tx("Gym kcal", "Gym kcal")}</span><strong>${metrics.gymCalories ?? "—"}</strong><small>${tx("our formula", "our formula")}</small></div>
      <div><span>${tx("Garmin kcal", "Garmin kcal")}</span><strong>${metrics.garminCalories ?? "—"}</strong><small>${tx("system", "system")}</small></div>
      <div><span>${tx("Avg HR", "Avg HR")}</span><strong>${metrics.avgHeartRate ? `${metrics.avgHeartRate} bpm` : "—"}</strong><small>${metrics.duration || tx("duration", "duration")}</small></div>
      <div><span>${tx("Max HR", "Max HR")}</span><strong>${metrics.maxHeartRate ? `${metrics.maxHeartRate} bpm` : "—"}</strong><small>${metrics.heartRateZone || tx("peak", "peak")}</small></div>
    </div>
    <p class="muted">${tx("Gym kcal is saved from the Garmin app strength formula. Garmin kcal is the system value Garmin Connect uses for daily calories.", "Gym kcal is saved from the Garmin app strength formula. Garmin kcal is the system value Garmin Connect uses for daily calories.")}</p>
  </section>`;
}

function parseGarminWorkoutMetrics(note) {
  if (!/Garmin Fenix 8/i.test(note || "")) return null;
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
    ? `${group.sets.length} ${tx("sets", "sets")} · ${group.sets.map(set => `${formatSetWeight(set.weight)} kg x ${set.reps}`).join(" · ")}`
    : tx("No sets", "No sets");
  const restTimer = isGarminWorkout ? "" : `<div class="timer-row"><div><strong>${tx("Exercise Rest", "Exercise Rest")}</strong><span>${remaining > 0 ? formatTimer(remaining) : tx("Ready", "Ready")}</span></div><div class="actions"><button class="button ghost mini" data-action="timer" data-key="${key}" data-seconds="60">60s</button><button class="button ghost mini" data-action="timer" data-key="${key}" data-seconds="90">90s</button><button class="button ghost mini" data-action="timer" data-key="${key}" data-seconds="180">180s</button><button class="button ghost mini" data-action="timer-stop" data-key="${key}" ${remaining ? "" : "disabled"}>${tx("Stop", "Stop")}</button></div></div>`;
  return `<section class="panel highlighted workout-exercise-card"><details ${isGarminWorkout ? "" : "open"}><summary class="detail-summary"><div><h2>${escapeHtml(group.name)}</h2><p class="muted">${escapeHtml(setSummary)}</p></div>${isPr(session, group.name) ? `<span class="pill">${svg("trophy", "small-icon")}${tx("New PR", "New PR")}</span>` : ""}</summary>
    ${!isGarminWorkout ? muscleContributionPanel(group.name) : ""}
    ${group.sets.length ? `${restTimer}<div class="table"><div class="table-head"><span>${tx("Set", "Set")}</span><span>${tx("Weight (kg)", "Weight (kg)")}</span><span>${tx("Reps", "Reps")}</span><span></span></div>${group.sets.map((set, i) => `<div class="table-row"><span>${tx("Set", "Set")} ${i + 1}</span><span>${Number(set.weight).toFixed(1)}</span><span>${set.reps}</span><span><button class="icon-button" data-action="edit-set" data-id="${set.id}">${svg("edit")}</button><button class="icon-button" data-action="delete-set" data-id="${set.id}">${svg("delete")}</button></span></div>`).join("")}</div>` : `<div class="empty">${tx("No sets were imported for this exercise.", "No sets were imported for this exercise.")}</div>`}
    <button class="button ghost full" data-action="detail-add-set" data-session="${session.id}" data-name="${escapeAttr(group.name)}">${t("addSet")}</button>
  </details></section>`;
}

function formatSetWeight(weight) {
  const value = Number(weight);
  if (!Number.isFinite(value)) return "0";
  return value % 1 === 0 ? String(value.toFixed(0)) : value.toFixed(1);
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
  const rewards = summaryRewards(session, records);
  return `<section class="hero-panel"><h2>${t("workoutComplete")}</h2><p>${fmtDate(session.startedAt)}</p><div class="metric-grid"><div><span>${tx("XP gained", "Отримано XP")}</span><strong>+${xpGain} XP</strong></div><div><span>${tx("Level", "Рівень")}</span><strong>${levelFromXp(xpTotal)}</strong></div></div></section>
    <section class="metric-grid post"><div><span>${tx("Current title", "Поточний ранг")}</span><strong>${rankTitle(xpTotal)}</strong></div><div><span>${tx("Streak", "Серія")}</span><strong>${streakDays()} ${tx("d", "д")}</strong></div><div><span>${tx("Exercises", "Вправи")}</span><strong>${summary.exercises}</strong></div><div><span>${tx("Sets", "Підходи")}</span><strong>${summary.sets}</strong></div><div><span>${tx("Volume", "Обсяг")}</span><strong>${Math.round(summary.volume)}</strong></div></section>
    <section class="panel"><h2>${t("impact")}</h2><p class="muted">${mStats[0] ? `${tx("Most loaded today", "Найбільше навантажено сьогодні")}: ${mStats[0].label}` : tx("Mapped muscle load will appear after sets are saved.", "Навантаження м'язів з'явиться після збереження підходів.")}</p>${mStats.slice(0, 5).map(m => barRow(m.label, m.load, mStats[0]?.load || 1, `${Math.round(m.load)} ${tx("load", "навантаження")} - ${n(m.sets, "set", "sets", "підхід", "підходи", "підходів")}`)).join("")}</section>
    ${records.length ? `<section class="panel highlighted"><h2>${t("personalRecords")}</h2>${records.map(r => `<div class="row-line"><div><strong>${escapeHtml(r.name)}</strong><p>${r.prev ? `${tx("Previous best", "Попередній рекорд")} ${r.prev.toFixed(1)} kg` : tx("First logged best", "Перший зафіксований рекорд")}</p></div><span class="pill">${r.now.toFixed(1)} kg</span></div>`).join("")}</section>` : ""}
    <section class="panel"><h2>${t("levelProgress")}</h2><p>${tx("Level", "Рівень")} ${levelFromXp(xpTotal)} - ${rankTitle(xpTotal)}</p><div class="progress"><span style="width:${progress.progressFraction * 100}%"></span></div><div class="row-line"><span>${progress.currentLevelXp} XP ${tx("into this level", "у цьому рівні")}</span><strong>${progress.xpForNextLevel - progress.currentLevelXp} XP ${tx("to next", "до наступного")}</strong></div></section>
    <section class="panel"><h2>${t("momentum")}</h2><p>${streakDays() > 1 ? `${tx("Streak extended to", "Серію продовжено до")} ${streakDays()} ${tx("days.", "днів.")}` : tx("A fresh streak has started.", "Нова серія почалася.")}</p><div class="chip-row"><span class="chip">${tx("Logged today", "Записано сьогодні")}</span><span class="chip">${tx("Best", "Найкраще")} ${streakDays()} ${tx("d", "д")}</span></div></section>
    ${summaryRewardsSection(rewards)}
    <div class="actions vertical"><button class="button full" data-action="summary-view" data-id="${session.id}">${tx("View workout", "Переглянути тренування")}</button><button class="button ghost full" data-action="summary-done">${tx("Back to workouts", "Назад до тренувань")}</button></div>`;
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
  return `<section class="panel highlighted"><h2>${tx("Rewards", "Нагороди")}</h2><p class="muted">${tx("Completed missions and new badges from this finish.", "Завершені місії та нові бейджі після фінішу.")}</p>${hasRewards ? "" : `<div class="empty">${tx("No new unlocks this time. Keep logging to unlock more.", "Цього разу нових відкриттів немає. Продовжуй записувати тренування.")}</div>`}${rewards.missions.map(item => rewardRow(item)).join("")}${rewards.badges.map(item => rewardRow(item)).join("")}</section>`;
}

function rewardRow(item) {
  return `<div class="row-line"><div><strong>${escapeHtml(item.title)}</strong><p>${escapeHtml(item.supporting)}</p></div><div class="actions"><span class="chip">${escapeHtml(item.badge)}</span>${item.reward ? `<span class="pill">+${item.reward} XP</span>` : ""}</div></div>`;
}

function loginAccount(rawName) {
  const name = String(rawName || "").trim();
  if (!name) return showToast(tx("Enter account name.", "Введи назву акаунта."));
  const id = normalizeAccountId(name);
  if (!id) return showToast(tx("Use letters or numbers for account name.", "Використай літери або цифри для назви акаунта."));
  const account = { id, name };
  const key = activeStorageKey(account);
  saveAccountList([...accountList().filter(item => item.id !== id), account]);
  localStorage.setItem(AUTH_KEY, JSON.stringify(account));
  if (!localStorage.getItem(key)) localStorage.setItem(key, JSON.stringify(state));
  activeAccount = account;
  state = loadState();
  nav = [{ name: "workouts" }];
  modal = null;
  render();
}

function sanitizeDisplayName(value) {
  return String(value || "").replace(/[^\p{L}\p{N} ._-]/gu, "").replace(/\s+/g, " ").trim().slice(0, 32);
}

function validateAuthInput(email, password, displayName = "") {
  const cleanEmail = String(email || "").trim();
  const cleanPassword = String(password || "");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(cleanEmail) || cleanEmail.length > 254) {
    return tx("Enter a valid email address.", "Enter a valid email address.");
  }
  if (cleanPassword.length < 8 || cleanPassword.length > 72 || !/[A-Za-z]/.test(cleanPassword) || !/\d/.test(cleanPassword)) {
    return tx("Password must be 8-72 characters and include letters and numbers.", "Password must be 8-72 characters and include letters and numbers.");
  }
  if (displayName && !/^[\p{L}\p{N} ._-]{2,32}$/u.test(displayName)) {
    return tx("Display name can use letters, numbers, spaces, dot, dash and underscore.", "Display name can use letters, numbers, spaces, dot, dash and underscore.");
  }
  return "";
}

async function remoteLogin(createAccount) {
  if (!remoteAuthEnabled()) return showToast(tx("Supabase is not configured.", "Supabase is not configured."));
  const email = createAccount
    ? document.querySelector("#signup-email")?.value.trim()
    : document.querySelector("#login-email")?.value.trim();
  const password = createAccount
    ? document.querySelector("#signup-password")?.value
    : document.querySelector("#login-password")?.value;
  const passwordConfirm = document.querySelector("#signup-password-confirm")?.value;
  const displayName = sanitizeDisplayName(document.querySelector("#signup-name")?.value.trim() || "");
  const validationError = validateAuthInput(email, password, createAccount ? displayName : "");
  if (validationError) return showToast(validationError);
  if (createAccount && password !== passwordConfirm) {
    return showToast(tx("Passwords do not match.", "Паролі не збігаються."));
  }
  try {
    const path = createAccount
      ? `/auth/v1/signup?redirect_to=${encodeURIComponent(AUTH_REDIRECT_URL)}`
      : "/auth/v1/token?grant_type=password";
    const session = await supabaseRequest(path, {
      method: "POST",
      body: JSON.stringify(createAccount ? { email, password, data: { display_name: displayName || email.split("@")[0] } } : { email, password })
    });
    if (!session?.access_token || !session?.user?.id) {
      showToast(tx("Check email to confirm account, then log in.", "Check email to confirm account, then log in."));
      return;
    }
    saveRemoteSession(session);
    const account = remoteAccountFromSession(session);
    if (displayName) account.name = displayName;
    localStorage.setItem(AUTH_KEY, JSON.stringify(account));
    saveAccountList([...accountList().filter(item => item.id !== account.id), account]);
    activeAccount = account;
    const cloudState = await loadRemoteState(session);
    state = cloudState ? normalizeImportedState(cloudState, defaultAppState()) : defaultAppState();
    saveState();
    nav = [{ name: "workouts" }];
    modal = null;
    render();
    showToast(tx("Cloud login complete.", "Cloud login complete."));
  } catch {
    showToast(tx("Login failed. Check email, password, and email confirmation.", "Login failed. Check email, password, and email confirmation."));
  }
}

function logoutAccount() {
  saveState();
  localStorage.removeItem(AUTH_KEY);
  localStorage.removeItem(REMOTE_SESSION_KEY);
  activeAccount = null;
  state = loadState();
  nav = [{ name: "workouts" }];
  modal = null;
  render();
}

function accountPanel() {
  const label = activeAccount?.name || tx("Local", "Локальний");
  return `<section class="panel"><div class="row-head"><div><h2>${tx("Account", "Акаунт")}</h2><p>${escapeHtml(label)}</p></div><button class="button ghost" data-action="logout-account">${tx("Switch", "Змінити")}</button></div></section>`;
}

function localLeaderboardRow() {
  return {
    display_name: activeAccount?.name || tx("Local", "Локальний"),
    xp: totalXp(),
    level: levelFromXp(),
    workouts: state.sessions.length,
    updated_at: new Date().toISOString(),
    isCurrent: true
  };
}

async function refreshLeaderboard(force = false) {
  if (leaderboardState.status === "loading" && !force) return;
  if (leaderboardState.status === "loading" && force) {
    leaderboardRequestController?.abort();
  }
  if (!force && leaderboardState.status === "loaded") return;
  if (!remoteAuthEnabled()) {
    leaderboardState = { status: "loaded", rows: [localLeaderboardRow()], error: "" };
    return render();
  }
  const requestId = ++leaderboardRequestId;
  leaderboardRequestController = new AbortController();
  leaderboardState = { ...leaderboardState, status: "loading", error: "" };
  render();
  try {
    const session = loadRemoteSession();
    if (session?.user?.id && activeAccount?.remote) {
      saveRemoteState().catch(() => {});
    }
    const rows = await supabaseRequest(
      "/rest/v1/profiles?select=user_id,display_name,xp,level,workouts,updated_at&order=xp.desc,workouts.desc,updated_at.asc&limit=50",
      { session: null, signal: leaderboardRequestController.signal, timeoutMs: 10000 }
    );
    if (requestId !== leaderboardRequestId) return;
    leaderboardState = {
      status: "loaded",
      rows: (Array.isArray(rows) ? rows : []).map(row => ({ ...row, isCurrent: session?.user?.id && row.user_id === session.user.id })),
      error: ""
    };
  } catch (error) {
    if (requestId !== leaderboardRequestId) return;
    leaderboardState = {
      status: "error",
      rows: [localLeaderboardRow()],
      error: tx("Could not load cloud rating. Try refresh again.", "Не вдалося завантажити хмарний рейтинг. Спробуй оновити ще раз.")
    };
  } finally {
    if (requestId === leaderboardRequestId) leaderboardRequestController = null;
  }
  render();
}

function leaderboardScreen() {
  const rows = leaderboardState.rows.length ? leaderboardState.rows : [localLeaderboardRow()];
  const loading = leaderboardState.status === "loading";
  const supporting = loading
    ? tx("Loading the latest cloud standings.", "Завантажуємо останній хмарний рейтинг.")
    : remoteAuthEnabled()
      ? tx("Synced through Supabase.", "Синхронізовано через Supabase.")
      : tx("Cloud rating is disabled until Supabase is configured.", "Хмарний рейтинг вимкнений, доки Supabase не налаштований.");
  return `<section class="hero-panel"><div class="hero-split"><div><h2>${tx("Rating", "Рейтинг")}</h2><p>${tx("Top users by XP, level and saved workouts.", "Топ користувачів за XP, рівнем і тренуваннями.")}</p></div><div class="hero-stat"><span>${tx("Your XP", "Твої XP")}</span><strong>${totalXp()}</strong><small>${rankTitle()}</small></div></div></section>
    <section class="panel highlighted"><div class="row-head"><div><h2>${tx("Leaderboard", "Таблиця рейтингу")}</h2><p>${supporting}</p></div><button class="button" data-action="refresh-leaderboard" ${loading ? "disabled" : ""}>${loading ? tx("Loading", "Завантаження") : tx("Refresh", "Оновити")}</button></div>${leaderboardState.error ? `<p class="muted">${escapeHtml(leaderboardState.error)}</p>` : ""}${!rows.length && !loading ? `<div class="empty">${tx("No leaderboard rows yet.", "Рядків рейтингу ще немає.")}</div>` : ""}</section>
    <section class="leaderboard-list">${rows.map(leaderboardRow).join("")}</section>`;
}

function leaderboardRow(row, index) {
  const name = row.display_name || tx("Anonymous", "Без імені");
  const xp = Number(row.xp || 0);
  const level = Number(row.level || 1);
  const workouts = Number(row.workouts || 0);
  return `<article class="leaderboard-row ${row.isCurrent ? "highlighted" : ""}"><div class="rank-place">${index + 1}</div><div><h3>${escapeHtml(name)}</h3><p>${tx("Level", "Рівень")} ${level} - ${n(workouts, "workout", "workouts", "тренування", "тренування", "тренувань")}</p></div><strong>${xp} XP</strong></article>`;
}

function exercisesScreen() {
  const mappingRows = state.exercises;
  return `${accountPanel()}<section class="panel"><div class="field-row"><input id="new-exercise-name" placeholder="${tx("Exercise name", "Назва вправи")}"><button class="button" data-action="save-exercise">${t("addExercise")}</button></div></section>
    <section class="panel"><h2>${t("backup")}</h2><div class="actions"><button class="button ghost" data-action="export-json">${t("exportJson")}</button><button class="button ghost" data-action="import-json">${t("importJson")}</button><button class="button ghost full" data-action="export-diagnostics">${t("diagnostics")}</button></div></section>
    ${mappingRows.length ? exerciseMappingsPanel(mappingRows) : ""}
    <section class="exercise-list">${state.exercises.length ? state.exercises.map(exerciseRow).join("") : `<div class="empty">${tx("No exercises yet.", "Вправ ще немає.")}</div>`}</section>`;
}

function exerciseMappingsPanel(exercises) {
  return `<section class="panel"><h2>${tx("Exercise mapping", "Мапінг вправ")}</h2>${exercises.map(exercise => {
    const labels = mappingFor(exercise.name).map(muscleLabel).join(", ") || tx("Not mapped", "Не зіставлено");
    return `<div class="row-line mapping-row"><span>${escapeHtml(exercise.name)}<small>${escapeHtml(labels)}</small></span><button class="button secondary mini" data-action="map-exercise" data-name="${escapeAttr(exercise.name)}">${tx("Map", "Мапити")}</button></div>`;
  }).join("")}</section>`;
}

function exerciseRow(exercise) {
  const stats = groupedExercises().find(g => g.name === exercise.name) || { sets: 0, volume: 0, best: 0, sessions: new Set() };
  const mapped = mappingFor(exercise.name).map(muscleLabel).join(", ") || tx("Not mapped", "Не зіставлено");
  return `<article class="exercise-row clickable" data-action="exercise-history" data-id="${exercise.id}"><div><h3>${escapeHtml(exercise.name)}</h3><span class="muted">${tx("Sessions", "Сесії")}: ${stats.sessions.size} - ${tx("Sets", "Підходи")}: ${stats.sets} - ${tx("Volume", "Обсяг")}: ${Math.round(stats.volume)}</span><small>${escapeHtml(mapped)}</small></div><div class="actions"><button class="icon-button" data-action="map-exercise" data-name="${escapeAttr(exercise.name)}">${svg("chart")}</button><button class="icon-button" data-action="rename-exercise" data-id="${exercise.id}">${svg("edit")}</button><button class="icon-button" data-action="delete-exercise" data-id="${exercise.id}">${svg("delete")}</button></div></article>`;
}

function progressScreen() {
  const selectedId = Number(state.progressExerciseId || state.exercises[0]?.id || 0);
  const selected = state.exercises.find(ex => Number(ex.id) === selectedId);
  if (!selected) return `<section class="panel"><div class="empty">${tx("No exercises yet.", "Вправ ще немає.")}</div></section>`;
  const history = allSets(selectedMonthSessions()).filter(set => set.exerciseName === selected.name).sort((a, b) => b.session.startedAt - a.session.startedAt);
  const grouped = progressHistoryGroups(history);
  const best = Math.max(0, ...history.map(s => Number(s.weight || 0)));
  const avg = grouped.length ? grouped.reduce((sum, g) => sum + Math.max(...g.sets.map(s => Number(s.weight || 0))), 0) / grouped.length : 0;
  const vol = history.reduce((sum, s) => sum + Number(s.weight || 0) * Number(s.reps || 0), 0);
  const reps = history.reduce((sum, x) => sum + Number(x.reps || 0), 0);
  return `${monthSwitcher()}<section class="panel"><label>${tx("Exercise", "Вправа")}<select id="progress-select" data-action="progress-select">${state.exercises.map(ex => `<option value="${ex.id}" ${Number(ex.id) === selectedId ? "selected" : ""}>${escapeHtml(ex.name)}</option>`).join("")}</select></label></section>
    <section class="panel"><h2>${tx("Progress Summary", "Підсумок прогресу")}</h2><p class="muted">${tx("Volume = weight x reps across all completed sets.", "Обсяг = вага x повтори по всіх завершених підходах.")}</p><div class="metric-grid three"><div><span>${tx("Sessions", "Сесії")}</span><strong>${grouped.length}</strong></div><div><span>${tx("Total Sets", "Усього підходів")}</span><strong>${history.length}</strong></div><div><span>${tx("Total Reps", "Усього повторів")}</span><strong>${reps}</strong></div><div><span>${tx("Best Weight", "Найкраща вага")}</span><strong>${history.length ? `${best.toFixed(1)} kg` : tx("No data", "Немає даних")}</strong></div><div><span>${tx("Average Max", "Середній максимум")}</span><strong>${history.length ? `${avg.toFixed(1)} kg` : tx("No data", "Немає даних")}</strong></div><div><span>${tx("Total Volume", "Загальний обсяг")}</span><strong>${Math.round(vol)}</strong></div></div></section>
    <section class="panel">${spotlight(selected.name, grouped, best, vol)}</section>
    <section class="panel"><h2>${tx("Visual Trends", "Візуальні тренди")}</h2><div class="bars">${grouped.length ? grouped.slice().reverse().map(g => barRow(fmtDate(g.session.startedAt, { day: "numeric", month: "short" }), Math.max(...g.sets.map(s => Number(s.weight || 0))), best || 1, `${tx("Vol", "Обсяг")} ${Math.round(g.sets.reduce((sum, s) => sum + Number(s.weight || 0) * Number(s.reps || 0), 0))}`)).join("") : `<div class="empty">${tx("Add sets to see chart.", "Додай підходи, щоб побачити графік.")}</div>`}</div></section>
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
function spotlight(name, grouped, best, vol) {
  return `<h2>${escapeHtml(name)}</h2><div class="metric-grid"><div><span>${tx("All-time best", "Найкраще за весь час")}</span><strong>${best.toFixed(1)} kg</strong></div><div><span>${tx("Consistency", "Стабільність")}</span><strong>${n(grouped.length, "session", "sessions", "сесія", "сесії", "сесій")}</strong></div><div><span>${tx("Peak weight", "Пікова вага")}</span><strong>${best.toFixed(1)} kg</strong></div><div><span>${tx("Avg volume", "Сер. обсяг")}</span><strong>${grouped.length ? Math.round(vol / grouped.length) : 0}</strong></div></div>`;
}

function progressHistoryCard(group) {
  const volume = group.sets.reduce((sum, s) => sum + Number(s.weight || 0) * Number(s.reps || 0), 0);
  const reps = group.sets.reduce((sum, x) => sum + Number(x.reps || 0), 0);
  return `<article class="workout-item"><h3>${fmtDate(group.session.startedAt)}</h3><div class="chip-row"><span class="chip">${tx("Sets", "Підходи")}: ${group.sets.length}</span><span class="chip">${tx("Reps", "Повтори")}: ${reps}</span><span class="chip">${tx("Volume", "Обсяг")}: ${Math.round(volume)}</span></div><div class="table"><div class="table-row"><strong>${tx("Set", "Підхід")}</strong><strong>${tx("Weight", "Вага")}</strong><strong>${tx("Reps", "Повтори")}</strong><span></span></div>${group.sets.map((set, i) => `<div class="table-row"><span>${tx("Set", "Підхід")} ${i + 1}</span><span>${Number(set.weight || 0).toFixed(1)}</span><span>${Number(set.reps || 0)}</span><button class="icon-button" data-action="delete-set" data-id="${set.id}">${svg("delete")}</button></div>`).join("")}</div></article>`;
}

function missionsScreen() {
  const missions = missionGroups();
  const all = [...missions.daily, ...missions.weekly, ...missions.monthly];
  const done = all.filter(m => m.done);
  const dailyDone = missions.daily.filter(m => m.done).length;
  const weeklyDone = missions.weekly.filter(m => m.done).length;
  const monthlyDone = missions.monthly.filter(m => m.done).length;
  const sections = all.length
    ? `${missionSection(t("daily"), tx("Daily consistency goals reset at midnight.", "Щоденні цілі стабільності оновлюються опівночі."), missions.daily)}${missionSection(t("weekly"), tx("Weekly goals track this training week.", "Тижневі цілі рахують поточний тренувальний тиждень."), missions.weekly)}${missionSection(t("monthly"), tx("Monthly goals measure the whole calendar month.", "Місячні цілі рахують увесь календарний місяць."), missions.monthly)}`
    : `<section class="panel"><div class="empty"><h2>${tx("No missions yet", "Місій ще немає")}</h2><p>${tx("Add workouts to unlock daily, weekly, and monthly goals.", "Додай тренування, щоб відкрити щоденні, тижневі й місячні цілі.")}</p></div></section>`;
  return `<section class="hero-panel"><h2>${t("missions")}</h2><p>${tx("Active daily, weekly, and monthly missions rotate from a huge challenge pool.", "Активні щоденні, тижневі й місячні місії обираються з великого пулу викликів.")}</p><div class="metric-grid"><div><span>${tx("Total", "Усього")}</span><strong>${all.length}</strong></div><div><span>${tx("Completed", "Виконано")}</span><strong>${done.length}</strong></div><div><span>${tx("Open", "Відкрито")}</span><strong>${all.length - done.length}</strong></div><div><span>${tx("Progress", "Прогрес")}</span><strong>${done.length}/${all.length}</strong></div></div><p>${tx("Daily", "Щоденні")}: ${dailyDone}/${missions.daily.length} - ${tx("Weekly", "Тижневі")}: ${weeklyDone}/${missions.weekly.length} - ${tx("Monthly", "Місячні")}: ${monthlyDone}/${missions.monthly.length}</p><p>${tx("Mission XP from completed goals", "XP місій за виконані цілі")}: ${done.reduce((s, m) => s + m.reward, 0)}</p></section>
    <section class="panel highlighted clickable" data-action="open-ranks"><div class="section-title"><div><h2>${tx("Rank ladder", "Драбина рангів")}</h2><p>${tx("Open the full rank list and check the next unlocks.", "Відкрий повний список рангів і перевір наступні відкриття.")}</p></div><span class="pill">${t("viewRanks")}</span></div><div class="metric-grid"><div><span>${tx("Current level", "Поточний рівень")}</span><strong>${levelFromXp()}</strong></div><div><span>${tx("Current title", "Поточний ранг")}</span><strong>${rankTitle()}</strong></div></div></section>
    ${sections}`;
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
  return `<section class="mission-list"><div class="section-title panel highlighted compact"><div><h2>${title}</h2><p>${supporting}</p></div><span class="pill">${missions.filter(m => m.done).length}/${missions.length} ${tx("done", "виконано")}</span></div>${missions.map(missionCard).join("")}</section>`;
}

function missionCard(m) {
  const status = m.done ? tx("Completed", "Виконано") : tx("In progress", "У процесі");
  return `<article class="mission-row ${m.done ? "highlighted" : ""}"><div class="row-head"><div><h3>${m.title}</h3><p>${m.summary}</p></div><span class="pill">${status}</span></div><div class="chip-row"><span class="chip">${m.cadenceLabel}</span><span class="chip">+${m.reward} XP</span><span class="muted">${m.progressLabel}</span></div><div class="progress"><span style="width:${Math.min(100, m.progress / Math.max(1, m.target) * 100)}%"></span></div></article>`;
}

function ranksScreen() {
  const xp = totalXp();
  const ranks = rankLadder().sort((a, b) => a.xp - b.xp || a.level - b.level);
  const cards = ranks.length ? ranks.map(rank => {
    const unlocked = rank.isUnlocked;
    const current = rank.isCurrent;
    const status = current ? tx("Current", "Поточний") : unlocked ? tx("Unlocked", "Відкрито") : tx("Locked", "Закрито");
    const progressValue = unlocked ? 100 : rank.progressFraction * 100;
    return `<section class="panel ${current ? "highlighted" : ""}"><div class="row-head"><div><h2>${rank.title}</h2><p>${status}</p></div><span class="pill">${status}</span></div><div class="metric-grid"><div><span>${tx("Required level", "Потрібний рівень")}</span><strong>${rank.level}</strong></div><div><span>${tx("Required total XP", "Потрібно XP")}</span><strong>${rank.xp}</strong></div></div><div class="progress"><span style="width:${progressValue}%"></span></div><div class="row-line"><span>${Math.min(xp, rank.xp)} / ${rank.xp} XP</span>${!unlocked ? `<strong>${rank.xpRemaining} XP ${tx("left", "лишилось")}</strong>` : ""}</div></section>`;
  }).join("") : `<section class="panel"><div class="empty"><h2>${tx("No ranks yet", "Рангів ще немає")}</h2><p>${tx("Earn XP to unlock rank titles.", "Заробляй XP, щоб відкривати ранги.")}</p></div></section>`;
  return `<section class="hero-panel"><h2>${t("ranks")}</h2><p>${tx("See every title, its level gate, and the XP needed to unlock it.", "Переглянь усі ранги, потрібний рівень і XP для відкриття.")}</p><div class="metric-grid"><div><span>${tx("TOTAL XP", "УСЬОГО XP")}</span><strong>${xp}</strong></div><div><span>${tx("Current level", "Поточний рівень")}</span><strong>${levelFromXp(xp)}</strong></div></div><p>${tx("Current title", "Поточний ранг")}: ${rankTitle(xp)}</p></section>
    ${cards}`;
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
  const groups = progressHistoryGroups(history);
  const total = history.reduce((s, x) => s + Number(x.weight || 0) * Number(x.reps || 0), 0);
  return `<h2>${escapeHtml(exercise.name)}</h2><div class="metric-grid three"><div><span>${tx("Sessions", "Сесії")}</span><strong>${groups.length}</strong></div><div><span>${tx("Sets", "Підходи")}</span><strong>${history.length}</strong></div><div><span>${tx("Volume", "Обсяг")}</span><strong>${Math.round(total)}</strong></div></div>${groups.length ? groupedExerciseHistory(groups) : `<div class="empty">${tx("No history for this exercise yet.", "Історії для цієї вправи ще немає.")}</div>`}`;
}

function mappingEditor(name) {
  const current = new Set(mappingFor(name));
  return `<h2>${tx("Map", "Мапінг")} "${escapeHtml(name)}"</h2><div class="mapping-grid">${muscles.map(([id]) => `<button class="chip buttonlike ${current.has(id) ? "selected" : ""}" data-action="toggle-map" data-id="${id}">${muscleLabel(id)}</button>`).join("")}</div><button class="button full" data-action="save-map" data-name="${escapeAttr(name)}">${tx("Save", "Зберегти")}</button>`;
}

function bindEvents() {
  app.querySelectorAll("[data-route]").forEach(el => el.addEventListener("click", () => goRoot(el.dataset.route)));
  app.querySelectorAll("[data-action]").forEach(el => el.addEventListener("click", ev => {
    ev.stopPropagation();
    handleAction(el.dataset.action, el);
  }));
  const loginName = app.querySelector("#local-login-name");
  if (loginName) loginName.addEventListener("keydown", ev => {
    if (ev.key === "Enter") loginAccount(loginName.value);
  });
  const loginPassword = app.querySelector("#login-password");
  if (loginPassword) loginPassword.addEventListener("keydown", ev => {
    if (ev.key === "Enter") remoteLogin(false);
  });
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
  if (action === "remote-login") return remoteLogin(false);
  if (action === "remote-signup") return remoteLogin(true);
  if (action === "login-account") return showToast(tx("Local login has been removed.", "Local login has been removed."));
  if (action === "logout-account") return logoutAccount();
  if (action === "refresh-leaderboard") return refreshLeaderboard(true);
  if (action === "back") return back();
  if (action === "language") { state.language = state.language === "en" ? "uk" : "en"; saveState(); return render(); }
  if (action === "backup") { modal = { type: "backup-json", json: exportPayload(false) }; return render(); }
  if (action === "open-add") return push("add");
  if (action === "open-detail") return push("detail", { id: Number(el.dataset.id) });
  if (action === "delete-session") return deleteSession(Number(el.dataset.id));
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
  if (action === "sync-watch") return queueGarminPlanFromDraft().catch(err => showToast(err.message || "Garmin sync failed."));
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

function deleteSession(id) {
  const session = state.sessions.find(s => s.id === id);
  if (!session) return;
  if (!window.confirm(tx(`Delete workout from ${fmtDate(session.startedAt)}?`, `Видалити тренування від ${fmtDate(session.startedAt)}?`))) return;
  state.sessions = state.sessions.filter(item => item.id !== id);
  saveState();
  modal = null;
  if (route().name === "detail" || route().name === "summary") nav = [{ name: "workouts" }];
  showToast(tx("Workout deleted.", "Тренування видалено."));
  render();
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
  state.mappings[normalizeExerciseName(name)] = ids;
  saveState();
  modal = null;
  render();
}

function exportPayload(diagnostics) {
  const payload = {
    schemaVersion: 2,
    exportedAt: Date.now(),
    source: diagnostics ? "gym-pwa-diagnostics" : "gym-pwa",
    owner: {
      accountId: activeAccount?.id || null,
      userId: activeAccount?.userId || null,
      email: activeAccount?.email || null,
      remote: activeAccount?.remote || null
    },
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

function importAllowed(parsed) {
  if (!activeAccount?.remote) {
    return !parsed.owner?.accountId || parsed.owner.accountId === activeAccount?.id;
  }
  return Boolean(parsed.owner?.userId && parsed.owner.userId === activeAccount.userId);
}

function applyImport() {
  try {
    const parsed = JSON.parse(document.querySelector("#import-json").value);
    if (!importAllowed(parsed)) {
      showToast(tx("This backup belongs to another account.", "Цей бекап належить іншому акаунту."));
      return;
    }
    const imported = normalizeImportedState(parsed, state);
    state.exercises = imported.exercises;
    state.sessions = imported.sessions;
    state.mappings = imported.mappings;
    state.profile = imported.profile;
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
pullRemoteState()
  .then(updated => {
    if (updated) render();
  })
  .catch(() => showToast(tx("Cloud sync failed.", "Синхронізація не вдалася.")));
