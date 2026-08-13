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

test("Android mission hero matches the iOS XP and week-streak metrics", () => {
  const hero = androidScreen.slice(0, androidScreen.indexOf("private fun MissionCard"));
  assert.match(hero, /label = "XP"/);
  assert.match(hero, /R\.string\.solo_streak_weekly_value/);
  assert.doesNotMatch(hero, /R\.string\.solo_weekly_rhythm_value/);
});

test("Android mission cards retain the same semantic icon roles as iOS", () => {
  assert.match(androidScreen, /missionId == "daily-check-in" -> Icons\.Default\.FitnessCenter/);
  assert.match(androidScreen, /"active-days" in missionId -> Icons\.Default\.EventAvailable/);
  assert.match(androidScreen, /"workouts" in missionId -> Icons\.Default\.CalendarMonth/);
  assert.match(androidScreen, /"sets" in missionId -> Icons\.Default\.FormatListNumbered/);
  assert.match(androidScreen, /"exercises" in missionId -> Icons\.Default\.Dashboard/);
});
