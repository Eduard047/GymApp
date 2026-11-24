import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const IOS_STORE_URL = "https://apps.apple.com/app/id6831768175";
const ANDROID_PACKAGE = "com.eduard.healthapp";
const ANDROID_MARKET_URL = "market://details?id=com.eduard.healthapp";
const ANDROID_WEB_URL = "https://play.google.com/store/apps/details?id=com.eduard.healthapp";

const ios = await readFile("ios/GymApp-iOS/GymApp/UI/Screens/ProfileView.swift", "utf8");
const profile = await readFile("app/src/main/java/com/example/gymapp/ui/screens/ProfileScreen.kt", "utf8");
const recommendation = await readFile("app/src/main/java/com/example/gymapp/ui/screens/HealthAppRecommendation.kt", "utf8");
const strings = {
  en: await readFile("app/src/main/res/values/strings.xml", "utf8"),
  uk: await readFile("app/src/main/res/values-uk/strings.xml", "utf8"),
  ru: await readFile("app/src/main/res/values-ru/strings.xml", "utf8")
};

function androidString(locale, name) {
  const match = strings[locale].match(new RegExp(`<string name="${name}">([^<]*)</string>`));
  assert.notEqual(match, null, `${locale} is missing ${name}`);
  return match[1].replaceAll("&amp;", "&");
}

function swiftText(source, english) {
  const start = source.indexOf(`"${english}"`);
  assert.notEqual(start, -1, `iOS is missing "${english}"`);
  const tail = source.slice(start, start + 600);
  const parts = [...tail.matchAll(/"((?:[^"\\\n]|\\.)*)"/g)].map(match => match[1]);
  return { en: parts[0], uk: parts[1], ru: parts[2] };
}

// Owner-approved copy: [iOS English, Android English, uk, ru] per sheet line.
const copy = [
  ["Our apps", "profile_group_our_apps", "Наші застосунки", "Наши приложения"],
  ["Sleep, HRV and recovery from your watch — by the same developer", "health_app_row_subtitle",
    "Сон, HRV і відновлення з вашого годинника — від того ж розробника",
    "Сон, HRV и восстановление с ваших часов — от того же разработчика"],
  ["Your training is only half the story. HealthApp shows how well you recover, so you know when to push and when to rest.",
    "health_app_sheet_lead",
    "Тренування — це лише половина справи. HealthApp показує, як ви відновлюєтеся, щоб ви знали, коли навантажувати себе, а коли відпочити.",
    "Тренировки — это только половина дела. HealthApp показывает, как вы восстанавливаетесь, чтобы вы знали, когда нагружать себя, а когда отдохнуть."],
  ["Sleep and recovery every morning", "health_app_benefit_sleep",
    "Сон і відновлення щоранку", "Сон и восстановление каждое утро"],
  ["HRV, resting heart rate and readiness", "health_app_benefit_hrv",
    "HRV, пульс спокою та готовність", "HRV, пульс покоя и готовность"],
  ["Free · From the developer of GymApp", "health_app_sheet_footnote",
    "Безкоштовно · Від розробника GymApp", "Бесплатно · От разработчика GymApp"],
  ["Not now", "health_app_sheet_not_now", "Не зараз", "Не сейчас"]
];

test("iOS opens exactly the verified App Store listing", () => {
  const match = ios.match(/private let healthAppStoreURL = URL\(string: "([^"]+)"\)!/);
  assert.notEqual(match, null);
  assert.equal(match[1], IOS_STORE_URL);
  // The only store call site is the sheet's primary button.
  assert.equal((ios.match(/open\(healthAppStoreURL\)/g) ?? []).length, 1);
});

test("Android package and store URLs are exact and the row is gated by one constant", () => {
  const constant = (name) => recommendation.match(new RegExp(`const val ${name} =\\s*"([^"]+)"`))?.[1];
  assert.equal(constant("HEALTH_APP_ANDROID_PACKAGE"), ANDROID_PACKAGE);
  assert.equal(constant("HEALTH_APP_MARKET_URL"), ANDROID_MARKET_URL);
  assert.equal(constant("HEALTH_APP_GOOGLE_PLAY_URL"), ANDROID_WEB_URL);
  // The Play app first, then the web listing.
  assert.ok(recommendation.indexOf("HEALTH_APP_MARKET_URL, packageName") < recommendation.indexOf("HEALTH_APP_GOOGLE_PLAY_URL, packageName"));
  assert.match(recommendation, /internal const val HEALTH_APP_PLAY_LISTING_PUBLIC = false/);
  assert.equal((recommendation.match(/HEALTH_APP_PLAY_LISTING_PUBLIC =/g) ?? []).length, 1);
  // Row and sheet are both behind the constant.
  assert.match(profile, /if \(HEALTH_APP_PLAY_LISTING_PUBLIC\) \{\s*item \{[\s\S]*?profile_group_our_apps/);
  assert.match(profile, /showHealthAppSheet && HEALTH_APP_PLAY_LISTING_PUBLIC/);
});

test("the HealthApp row sits right after the header and before the Account group on both clients", () => {
  const iosGroups = ios.slice(ios.indexOf("private var settingsGroups"));
  assert.ok(iosGroups.indexOf("healthAppRow") !== -1);
  assert.ok(iosGroups.indexOf("healthAppRow") < iosGroups.indexOf("settingsGroup\n"));
  const root = profile.slice(profile.indexOf("private fun LazyListScope.profileRootContent"));
  const header = root.indexOf("ProfileIdentityHeader(");
  const apps = root.indexOf("profile_group_our_apps");
  const account = root.indexOf("profile_group_account");
  assert.ok(header !== -1 && header < apps && apps < account);
});

test("the store opens only from the sheet's primary button", () => {
  // iOS: the row only presents the sheet.
  const row = ios.slice(ios.indexOf("private var healthAppRow"), ios.indexOf("/// The help row's one action"));
  assert.match(row, /showsHealthAppSheet = true/);
  assert.equal(row.includes("open("), false);
  // The row opens an in-app sheet, so it carries the default chevron, not an external-link arrow.
  assert.equal(row.includes("arrow.up.right"), false);
  // Android: the row only raises onOpenHealthApp; the launcher is called from the sheet button.
  assert.equal(profile.includes("openHealthAppInGooglePlay"), false);
  assert.equal((recommendation.match(/openHealthAppInGooglePlay\(context\)/g) ?? []).length, 1);
  assert.match(recommendation, /onClick = \{\s*openHealthAppInGooglePlay\(context\)\s*onDismiss\(\)\s*\}/);
  assert.match(recommendation, /catch \(_: ActivityNotFoundException\)/);
});

test("copy exists on both clients in English, Ukrainian and Russian", () => {
  for (const [english, key, uk, ru] of copy) {
    const iosText = swiftText(ios.includes("private struct HealthAppRecommendationSheet") && ios.slice(ios.indexOf("private struct HealthAppRecommendationSheet")).includes(`"${english}"`)
      ? ios.slice(ios.indexOf("private struct HealthAppRecommendationSheet")) : ios, english);
    assert.deepEqual(iosText, { en: english, uk, ru }, `iOS: ${english}`);
    assert.equal(androidString("en", key), english, `Android en: ${key}`);
    assert.equal(androidString("uk", key), uk, `Android uk: ${key}`);
    assert.equal(androidString("ru", key), ru, `Android ru: ${key}`);
  }
  // Sheet title is the same in every language.
  assert.match(ios, /Text\("HealthApp: Recovery & Sleep"\)/);
  for (const locale of ["en", "uk", "ru"]) {
    assert.equal(androidString(locale, "health_app_sheet_title"), "HealthApp: Recovery & Sleep");
    assert.equal(androidString(locale, "health_app_row_title"), "HealthApp");
  }
});

test("platform-specific copy: source list, store button and accessibility labels", () => {
  assert.deepEqual(swiftText(ios, "Garmin, Oura and Apple Health"), {
    en: "Garmin, Oura and Apple Health",
    uk: "Дані з Garmin, Oura та Apple Health",
    ru: "Данные из Garmin, Oura и Apple Health"
  });
  assert.equal(androidString("en", "health_app_benefit_sources"), "Garmin, Oura and Health Connect");
  assert.equal(androidString("uk", "health_app_benefit_sources"), "Дані з Garmin, Oura та Health Connect");
  assert.equal(androidString("ru", "health_app_benefit_sources"), "Данные из Garmin, Oura и Health Connect");

  assert.deepEqual(swiftText(ios, "Open in App Store"), {
    en: "Open in App Store", uk: "Відкрити в App Store", ru: "Открыть в App Store"
  });
  assert.equal(androidString("en", "health_app_sheet_open_store"), "Open in Google Play");
  assert.equal(androidString("uk", "health_app_sheet_open_store"), "Відкрити в Google Play");
  assert.equal(androidString("ru", "health_app_sheet_open_store"), "Открыть в Google Play");

  assert.deepEqual(swiftText(ios, "HealthApp, details"), {
    en: "HealthApp, details",
    uk: "HealthApp, докладніше",
    ru: "HealthApp, подробнее"
  });
  assert.equal(androidString("en", "health_app_row_description"), "Open HealthApp in Google Play");
  assert.equal(androidString("uk", "health_app_row_description"), "Відкрити HealthApp у Google Play");
  assert.equal(androidString("ru", "health_app_row_description"), "Открыть HealthApp в Google Play");
});

test("sheet uses the shared flat sheet and capsule button styles", () => {
  assert.match(ios, /HealthAppRecommendationSheet\(languageCode: languageCode\)\s*\.gymSheetPresentation\(\.standard\)/);
  assert.match(ios, /\.buttonStyle\(GymPrimaryButtonStyle\(\)\)/);
  for (const symbol of ["bed.double", "waveform.path.ecg", "chart.line.uptrend.xyaxis"]) {
    assert.ok(ios.includes(`"${symbol}"`), symbol);
  }
  assert.match(recommendation, /GymModalBottomSheet\(/);
  assert.equal(/Brush|gradient/i.test(recommendation), false);
});
