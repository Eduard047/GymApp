import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [androidBoard, androidScreen, androidRussian, iosEngine] = await Promise.all([
  readFile("app/src/main/java/com/example/gymapp/ui/viewmodel/AdaptiveMissionBoard.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/screens/MissionsScreen.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/util/RussianText.kt", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Domain/GamificationEngine.swift", "utf8")
]);

const canonicalCopy = [
  {
    enTitle: "Show up",
    ukTitle: "Прийди на тренування",
    ruTitle: "Приди на тренировку",
    enDescription: "Complete one workout today.",
    ukDescription: "Заверши одне тренування сьогодні.",
    ruDescription: "Заверши одну тренировку сегодня."
  },
  {
    enTitle: "Quality sets",
    ukTitle: "Якісні підходи",
    ruTitle: "Качественные подходы",
    enDescription: "Complete a sustainable number of working sets today.",
    ukDescription: "Виконай реалістичну кількість робочих підходів сьогодні.",
    ruDescription: "Выполни реалистичное количество рабочих подходов сегодня."
  },
  {
    enTitle: "Balanced session",
    ukTitle: "Збалансована сесія",
    ruTitle: "Сбалансированная сессия",
    enDescription: "Train a realistic number of exercises today.",
    ukDescription: "Виконай реалістичну кількість вправ сьогодні.",
    ruDescription: "Выполни реалистичное количество упражнений сегодня."
  },
  {
    enTitle: "Weekly rhythm",
    ukTitle: "Ритм тижня",
    ruTitle: "Ритм недели",
    enDescription: "Match a sustainable recent workout rhythm this week.",
    ukDescription: "Підтримай цього тижня сталий ритм недавніх тренувань.",
    ruDescription: "Поддержи на этой неделе стабильный ритм недавних тренировок."
  },
  {
    enTitle: "Active days",
    ukTitle: "Активні дні",
    ruTitle: "Активные дни",
    enDescription: "Train on a realistic number of separate days this week.",
    ukDescription: "Тренуйся реалістичну кількість окремих днів цього тижня.",
    ruDescription: "Тренируйся реалистичное количество отдельных дней на этой неделе."
  },
  {
    enTitle: "Steady sets",
    ukTitle: "Сталі підходи",
    ruTitle: "Стабильные подходы",
    enDescription: "Build a typical recent week's number of working sets.",
    ukDescription: "Виконай типову для недавнього тижня кількість робочих підходів.",
    ruDescription: "Выполни типичное для недавней недели количество рабочих подходов."
  },
  {
    enTitle: "Monthly base",
    ukTitle: "Основа місяця",
    ruTitle: "Основа месяца",
    enDescription: "Build on a sustainable recent month of workouts.",
    ukDescription: "Спирайся на сталий ритм тренувань недавнього місяця.",
    ruDescription: "Опирайся на стабильный ритм тренировок недавнего месяца."
  },
  {
    enTitle: "Sustainable sets",
    ukTitle: "Сталий обсяг підходів",
    ruTitle: "Стабильный объём подходов",
    enDescription: "Accumulate a realistic number of working sets this month.",
    ukDescription: "Набери реалістичну кількість робочих підходів цього місяця.",
    ruDescription: "Набери реалистичное количество рабочих подходов в этом месяце."
  }
];

test("native mission boards retain the same concise hierarchy and copy", () => {
  assert.match(androidBoard, /linkedSetOf\("workouts", "sets", "exercises"\)/);
  assert.match(androidBoard, /linkedSetOf\("workouts", "active-days", "sets"\)/);
  assert.match(androidBoard, /linkedSetOf\("workouts", "sets"\)/);
  for (const copy of canonicalCopy) {
    for (const value of [copy.enTitle, copy.ukTitle, copy.enDescription, copy.ukDescription]) {
      assert.ok(androidBoard.includes(`"${value}"`), `Android is missing ${value}`);
      assert.ok(iosEngine.includes(`"${value}"`), `iOS is missing ${value}`);
    }
    for (const value of [copy.ruTitle, copy.ruDescription]) {
      assert.ok(androidRussian.includes(`"${value}"`), `Android Russian is missing ${value}`);
      assert.ok(iosEngine.includes(`"${value}"`), `iOS Russian is missing ${value}`);
    }
  }
});

test("Android mission hero is the compact iOS level row that opens ranks", async () => {
  const hero = androidScreen.slice(0, androidScreen.indexOf("private fun MissionCard"));
  assert.match(hero, /R\.string\.missions_level_summary/);
  assert.match(hero, /formatXp\(uiState\.soloProgress\.totalXp/);
  assert.match(hero, /onClickLabel = openRanks/);
  assert.match(hero, /heightIn\(min = 48\.dp\)/);
  assert.match(hero, /maxLines = 1/);
  assert.match(hero, /Icons\.Default\.EmojiEvents/);
  assert.match(hero, /KeyboardArrowRight/);
  assert.doesNotMatch(hero, /HeroPanel|MetricTile|solo_weekly_rhythm_value|solo_streak_weekly_value/);
  for (const [file, level] of [
    ["values", "Level %1$d \u00b7 %2$s \u00b7 %3$s XP"],
    ["values-uk", "\u0420\u0456\u0432\u0435\u043d\u044c %1$d \u00b7 %2$s \u00b7 %3$s XP"],
    ["values-ru", "\u0423\u0440\u043e\u0432\u0435\u043d\u044c %1$d \u00b7 %2$s \u00b7 %3$s XP"]
  ]) {
    const xml = await readFile(`app/src/main/res/${file}/strings.xml`, "utf8");
    assert.ok(xml.includes(`<string name="missions_level_summary">${level}</string>`), file);
  }
});

test("Android mission card matches the iOS counter, pill, and tint hierarchy", () => {
  const card = androidScreen.slice(androidScreen.indexOf("private fun MissionCard"));
  assert.match(card, /R\.string\.missions_progress_value,\s*mission\.progress,\s*mission\.goal/);
  assert.match(card, /InfoPill\(\s*text = stringResource\(R\.string\.missions_status_completed\)/);
  assert.match(card, /tint = MaterialTheme\.colorScheme\.primary/);
  assert.match(card, /vertical = 13\.dp/);
  assert.match(card, /spacedBy\(9\.dp\)/);
  assert.doesNotMatch(card, /mission\.progressLabel/);
});

test("Android mission cards retain the same semantic icon roles as iOS", () => {
  assert.match(androidScreen, /missionId == "daily-check-in" -> Icons\.Default\.FitnessCenter/);
  assert.match(androidScreen, /"active-days" in missionId -> Icons\.Default\.EventAvailable/);
  assert.match(androidScreen, /"workouts" in missionId -> Icons\.Default\.CalendarMonth/);
  assert.match(androidScreen, /"sets" in missionId -> Icons\.Default\.FormatListNumbered/);
  assert.match(androidScreen, /"exercises" in missionId -> Icons\.Default\.Dashboard/);
});
