import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [androidSource, iosSource, pwaSource] = await Promise.all([
  readFile("app/src/main/java/com/example/gymapp/data/catalog/BuiltInExerciseCatalog.kt", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Domain/BuiltInExerciseCatalog.swift", "utf8"),
  readFile("pwa/app.js", "utf8")
]);

const expectedCatalog = [
  ["bench_press", "Bench Press", "Жим штанги лежачи"],
  ["incline_dumbbell_press", "Incline Dumbbell Press", "Жим гантелей на похилій лаві"],
  ["pull_up", "Pull Up", "Підтягування"],
  ["lat_pulldown", "Lat Pulldown", "Тяга верхнього блока"],
  ["barbell_row", "Barbell Row", "Тяга штанги в нахилі"],
  ["squat", "Squat", "Присідання зі штангою"],
  ["leg_press", "Leg Press", "Жим ногами у тренажері"],
  ["romanian_deadlift", "Romanian Deadlift", "Румунська тяга"],
  ["deadlift", "Deadlift", "Станова тяга"],
  ["shoulder_press", "Shoulder Press", "Жим над головою"],
  ["lateral_raise", "Lateral Raise", "Підйоми гантелей через сторони"],
  ["biceps_curl", "Biceps Curl", "Згинання рук на біцепс"],
  ["triceps_pushdown", "Triceps Pushdown", "Розгинання рук на блоці"],
  ["calf_raise", "Calf Raise", "Підйом на носки"],
  ["plank", "Plank", "Планка"]
];

test("Android, iOS, and PWA expose the same built-in exercise contract", () => {
  for (const [key, english, ukrainian] of expectedCatalog) {
    for (const [platform, source] of [
      ["Android", androidSource],
      ["iOS", iosSource],
      ["PWA", pwaSource]
    ]) {
      assert.ok(source.includes(`"${key}"`), `${platform} is missing ${key}`);
      assert.ok(source.includes(`"${english}"`), `${platform} is missing ${english}`);
      assert.ok(source.includes(`"${ukrainian}"`), `${platform} is missing ${ukrainian}`);
    }
  }
});
