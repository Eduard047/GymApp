import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const placeholderPattern = /%(?:\d+\$)?(?:[-+#0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?)?[a-zA-Z@]/g;

function androidStrings(source) {
  return new Map([...source.matchAll(/<string\s+name="([^"]+)"[^>]*>(.*?)<\/string>/gs)]
    .map(([, name, value]) => [name, value]));
}

function placeholders(value) {
  return [...String(value).matchAll(placeholderPattern)].map(match => match[0]).sort();
}

test("Android Russian resources cover every English string with compatible placeholders", async () => {
  const [englishSource, ukrainianSource, russianSource, manager, navigation, dynamic, workoutDetail, addWorkout, activeWorkout] = await Promise.all([
    readFile("app/src/main/res/values/strings.xml", "utf8"),
    readFile("app/src/main/res/values-uk/strings.xml", "utf8"),
    readFile("app/src/main/res/values-ru/strings.xml", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/util/LanguageManager.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/navigation/GymNavGraph.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/util/RussianText.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/ui/screens/WorkoutDetailScreen.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/ui/screens/AddWorkoutScreen.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/ui/screens/ActiveWorkoutScreen.kt", "utf8")
  ]);
  const english = androidStrings(englishSource);
  const ukrainian = androidStrings(ukrainianSource);
  const russian = androidStrings(russianSource);
  assert.deepEqual([...russian.keys()].sort(), [...english.keys()].sort());
  for (const [name, value] of english) {
    assert.deepEqual(placeholders(russian.get(name)), placeholders(value), name);
  }
  assert.doesNotMatch([...russian.values()].join("\n"), /[іїєґІЇЄҐ]/);
  assert.match(manager, /RU\("ru"\)/);
  assert.match(navigation, /onLanguageSelected\(AppLanguage\.RU\)/);
  assert.match(dynamic, /"Barbell Row" to "Тяга штанги в наклоне"/);
  assert.match(
    workoutDetail,
    /parseGarminWorkoutPresentation\([\s\S]*note = details\.session\.note\.orEmpty\(\),[\s\S]*hasGarminReceipt = uiState\.hasGarminReceipt/
  );
  assert.doesNotMatch(workoutDetail, /parseTrustedGarminWorkoutMetrics/);
  assert.match(workoutDetail, /garminPresentation\?\.hasVerifiedGarminOrigin == true/);
  assert.match(workoutDetail, /GarminSetHeartRateOverview\(points = heartRatePoints\)/);
  assert.equal(russian.get("action_add_set"), "Добавить подход");
  assert.equal(english.get("action_add_planned_set"), "Add planned set");
  assert.equal(ukrainian.get("action_add_planned_set"), "Додати запланований підхід");
  assert.equal(russian.get("action_add_planned_set"), "Добавить запланированный подход");
  assert.equal(english.get("action_start_workout"), "Start workout");
  assert.equal(russian.get("action_start_workout"), "Начать тренировку");
  assert.match(english.get("add_workout_plan_mode_hint"), /targets sent to Garmin/);
  assert.match(english.get("add_workout_active_mode_hint"), /durable local plan/);
  assert.match(
    english.get("active_workout_supporting"),
    /saved before a movement-aware rest timer starts/
  );
  assert.match(addWorkout, /R\.string\.action_add_planned_set/);
  assert.match(addWorkout, /R\.string\.action_start_workout/);
  assert.match(addWorkout, /R\.string\.add_workout_plan_mode_hint/);
  assert.match(addWorkout, /R\.string\.add_workout_active_mode_hint/);
  assert.match(activeWorkout, /R\.string\.action_log_set_and_rest/);
  assert.match(activeWorkout, /R\.string\.active_workout_finish_supporting/);
  assert.equal(english.get("garmin_set_intervals_title"), "Chronological watch sets");
  assert.equal(ukrainian.get("garmin_watch_set_label"), "Підхід з годинника S%1$d");
  assert.equal(russian.get("garmin_watch_set_label"), "Подход с часов S%1$d");
  assert.match(english.get("garmin_note_derived_sets_hint"), /do not prove watch origin/);
  assert.match(russian.get("garmin_set_hr_overview_supporting"), /не непрерывный график пульса/);
});

test("iOS String Catalog has Russian values for every key and preserves format placeholders", async () => {
  const [catalogSource, languageSource, menuSource, projectSource, workoutEditor, addWorkout] = await Promise.all([
    readFile("ios/GymApp-iOS/GymApp/Resources/Localizable.xcstrings", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/App/AppLanguage.swift", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/UI/Components/AppLanguageMenu.swift", "utf8"),
    readFile("ios/GymApp-iOS/GymApp.xcodeproj/project.pbxproj", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/UI/Components/WorkoutEditorComponents.swift", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/UI/Screens/AddWorkoutView.swift", "utf8")
  ]);
  const catalog = JSON.parse(catalogSource);
  assert.ok(Object.keys(catalog.strings).length >= 650);
  for (const [key, entry] of Object.entries(catalog.strings)) {
    const english = entry.localizations?.en?.stringUnit?.value ?? key;
    const russian = entry.localizations?.ru?.stringUnit?.value;
    assert.equal(typeof russian, "string", key);
    assert.deepEqual(placeholders(russian), placeholders(english), key);
    if (key !== "Українська") assert.doesNotMatch(russian, /[іїєґІЇЄҐ]/, key);
  }
  assert.match(languageSource, /case russian = "ru"/);
  assert.match(menuSource, /Label\("Русский"/);
  assert.match(projectSource, /knownRegions = \([\s\S]*\bru,/);
  assert.equal(
    catalog.strings["Add planned set"].localizations.uk.stringUnit.value,
    "Додати запланований підхід"
  );
  assert.equal(
    catalog.strings["Add planned set"].localizations.ru.stringUnit.value,
    "Добавить запланированный подход"
  );
  assert.match(workoutEditor, /Label\("Add planned set"/);
  const draftCard = workoutEditor.match(/struct WorkoutDraftExerciseCard:[\s\S]*?private func binding/)[0];
  assert.doesNotMatch(draftCard, /restTimers\.start|WorkoutRestTimerControls/);
  assert.equal(
    catalog.strings["Save as completed workout"].localizations.ru.stringUnit.value,
    "Сохранить как выполненную тренировку"
  );
  assert.match(addWorkout, /Label\("Save as completed workout"/);
  assert.match(addWorkout, /Planned rows are targets\. They do not start rest timers/);
  assert.match(addWorkout, /Garmin plan mode: after saving, every planned row is sent/);
  assert.match(addWorkout, /Completed mode remains available for workouts you already finished/);
  assert.match(addWorkout, /Adds every planned row to history and summaries as completed/);
});

test("PWA accepts Russian state and renders Russian runtime text before app startup", async () => {
  const [contractSource, russianSource, appSource, indexSource, workerSource] = await Promise.all([
    readFile("pwa/state-contract.js", "utf8"),
    readFile("pwa/russian-text.js", "utf8"),
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/index.html", "utf8"),
    readFile("pwa/sw.js", "utf8")
  ]);
  const window = {};
  vm.runInNewContext(russianSource, { Map, Object, RegExp, String, window });
  assert.equal(window.GymRussianText.translate("Add Set"), "Добавить подход");
  assert.equal(window.GymRussianText.translate("Log set · rest 90 s"), "Записать подход · отдых 90 с");
  assert.equal(window.GymRussianText.translate("Add planned set"), "Добавить запланированный подход");
  assert.equal(window.GymRussianText.translate("Save as completed workout"), "Сохранить как выполненную тренировку");
  assert.equal(window.GymRussianText.translate("Chronological watch set metrics"), "Хронологические показатели подходов на часах");
  assert.equal(window.GymRussianText.translate("Barbell Row"), "Тяга штанги в наклоне");
  assert.equal(window.GymRussianText.translate("Deadlift"), "Становая тяга");
  assert.equal(window.GymRussianText.translate("4-workout week"), "4 тренировок за неделю");
  const auditedRussian = new Map([
    ["Add workouts to unlock daily, weekly, and monthly goals.", "Добавь тренировки, чтобы открыть ежедневные, недельные и месячные цели."],
    ["All saved exercises are already in this workout.", "Все сохранённые упражнения уже добавлены в эту тренировку."],
    ["An account with this email already exists. Log in or resend the confirmation email.", "Аккаунт с этим адресом электронной почты уже существует. Войди или повторно отправь письмо для подтверждения."],
    ["Based on muscle load and recent training gaps.", "На основе нагрузки на мышцы и недавних перерывов в тренировках."],
    ["Build plan: hold weight and add reps before the next jump.", "План набора: сохраняй вес и добавляй повторы перед следующим увеличением веса."],
    ["Cloud sync conflicted. Reload before saving again.", "Возник конфликт облачной синхронизации. Обнови данные перед повторным сохранением."],
    ["Confirm your email first, then log in.", "Сначала подтверди адрес электронной почты, затем войди."],
    ["Consistency milestone reached.", "Достигнута веха стабильности."],
    ["Generate Smart Workout", "Сгенерировать тренировку"],
    ["Monthly", "Месячные"],
    ["Next suggested workout: pull", "Следующая рекомендованная тренировка: тяга"],
    ["Next suggested workout: push", "Следующая рекомендованная тренировка: жим"],
    ["Wait for the account operation to finish.", "Дождись завершения операции с аккаунтом."],
    ["A previous Garmin device creation is still awaiting revocation. Keep this page open and retry before pairing again.", "Предыдущее создание устройства Garmin всё ещё ожидает отзыва. Не закрывай эту страницу и повтори попытку перед новым сопряжением."],
    ["Aesthetic goal: the plan favors clean volume and technique.", "Цель сушки: план делает упор на качественный объём и технику."],
    ["Achievements", "Достижения"],
    ["Back", "Сзади"],
    ["Back to workouts", "К тренировкам"],
    ["Backup JSON ready", "Резервная копия JSON готова"],
    ["Backup imported.", "Резервная копия импортирована."],
    ["Auto mapping", "Автосопоставление"],
    ["Auto mapping works first, manual choices override it.", "Сначала применяется автосопоставление, а ручной выбор имеет приоритет."],
    ["Avg / Set", "Сред. / подход"],
    ["By name", "По названию"],
    ["Built-in", "Встроенное"],
    ["Copy Last +2.5 kg", "Копировать последний +2,5 кг"],
    ["Copy Previous Workout", "Скопировать предыдущую тренировку"],
    ["Completed missions and new badges from this finish.", "Выполненные миссии и новые значки после завершения тренировки."],
    ["Deload", "Разгрузка"],
    ["Garmin sync failed. Check your connection and try again.", "Не удалось синхронизировать Garmin. Проверь подключение и попробуй снова."],
    ["Import backup", "Импорт резервной копии"],
    ["Invalid backup.", "Некорректная резервная копия."],
    ["Latest max", "Последний максимум"],
    ["Least frequent", "Реже всего"],
    ["Load", "Нагрузка"],
    ["Local mode. Sign in to protect and synchronize your progress.", "Локальный режим. Войди, чтобы защитить и синхронизировать прогресс."],
    ["Log in instead", "Войти вместо регистрации"],
    ["Log your plan fast and keep momentum with smart set shortcuts.", "Быстро запиши план и сохраняй темп с помощью удобных действий для подходов."],
    ["Momentum", "Темп"],
    ["Name in English, Ukrainian, or Russian", "Название на английском, украинском или русском"],
    ["Next", "Далее"],
    ["No synced progress yet.", "Синхронизированного прогресса пока нет."],
    ["This backup belongs to another account.", "Эта резервная копия принадлежит другому аккаунту."],
    ["This full backup contains private workout history and account metadata. Copy it to the system clipboard? Other apps may be able to read it.", "Полная резервная копия содержит личную историю тренировок и данные аккаунта. Скопировать её в системный буфер обмена? Другие приложения могут получить к ней доступ."],
    ["This report will include the full private backup. Continue to the print dialog?", "Отчёт будет содержать полную личную резервную копию. Перейти к диалогу печати?"],
    ["Garmin-format strength workout", "Силовая тренировка в формате Garmin"],
    ["metrics parsed from the saved note", "показатели прочитаны из сохранённой заметки"],
    ["Set metrics", "Показатели подхода"],
    ["Rest before", "Отдых перед подходом"],
    ["2 / week", "2 раза в неделю"],
    ["3 / week", "3 раза в неделю"],
    ["4 / week", "4 раза в неделю"],
    ["5 / week", "5 раз в неделю"],
    ["6 / week", "6 раз в неделю"],
    ["Copy Last Set", "Копировать последний подход"],
    ["Copy a previous workout", "Скопировать предыдущую тренировку"],
    ["Copy this Garmin pairing token into Connect IQ settings now. Treat it as a password. It will not be stored or shown again. Choose Cancel to revoke it.", "Сейчас скопируй этот токен сопряжения Garmin в настройки Connect IQ. Относись к нему как к паролю. Он не будет сохранён или показан повторно. Нажми «Отмена», чтобы отозвать его."],
    ["Existing Garmin recovery was cancelled. No new device identity was created.", "Восстановление существующего сопряжения Garmin отменено. Новый идентификатор устройства не создан."],
    ["First download the untouched private JSON for offline recovery. Replacing it with an empty valid state is permanent and uses the exact server revision so another device's newer update cannot be overwritten.", "Сначала скачай неизменённый приватный JSON для офлайн-восстановления. Замена на пустое корректное состояние необратима и использует точную ревизию сервера, поэтому новые изменения с другого устройства не будут перезаписаны."],
    ["Front", "Спереди"],
    ["Garmin unpair failed.", "Не удалось отсоединить Garmin."],
    ["Last", "Последний вес"],
    ["Maintenance", "Поддержание"],
    ["Maximum weight and session volume over time.", "Максимальный вес и объём тренировки в динамике."],
    ["No exercise data yet", "По этому упражнению пока нет данных"],
    ["No logged exercises for this muscle in the selected period.", "Для этой группы мышц в выбранном периоде нет записанных упражнений."],
    ["Open the full rank list and check the next unlocks.", "Открой полный список рангов и посмотри, что откроется дальше."],
    ["Paste exported GymApp JSON here", "Вставь сюда экспортированный JSON GymApp"],
    ["Plateau plan: change the rep target to break the flat trend.", "План выхода с плато: измени цель по повторам, чтобы преодолеть застой."],
    ["Recent reps or volume dipped, so the plan stays conservative.", "Повторы или объём снизились, поэтому план остаётся консервативным."],
    ["Recent volume dropped compared with the previous session.", "Объём последней тренировки ниже объёма предыдущей."],
    ["Repeat Last Workout", "Повторить последнюю тренировку"],
    ["Share PDF report", "Поделиться PDF-отчётом"],
    ["Sign in to sync workouts across devices.", "Войди, чтобы синхронизировать тренировки между устройствами."],
    ["Smart Coach", "Умный тренер"],
    ["Smart Coach uses this to match your plan, goal and recovery.", "Умный тренер использует эти данные, чтобы подобрать план с учётом цели и восстановления."],
    ["Solo Progress", "Личный прогресс"],
    ["Suggested from your recent exercise pattern and training profile.", "Подобрано с учётом недавних упражнений и профиля тренировок."],
    ["Switch", "Сменить аккаунт"],
    ["The increase is intentionally conservative.", "Увеличение намеренно небольшое."],
    ["The pending Garmin device is no longer active. Run Sync Watch again to choose or create a pairing.", "Ожидающее сопряжения устройство Garmin больше не активно. Снова нажми «Синхронизировать с часами», чтобы выбрать или создать сопряжение."],
    ["This legacy local account name is ambiguous. Its stored data was left untouched; rename/recover it before signing in.", "Название старого локального аккаунта неоднозначно. Его данные не изменены; восстанови или переименуй аккаунт перед входом."],
    ["Use Last Weight", "Использовать последний вес"],
    ["View workout", "Открыть тренировку"],
    ["Your authenticated cloud row uses a legacy or invalid format. It was not loaded into the app and cannot sync until you choose a recovery action.", "Твоя аутентифицированная облачная запись имеет устаревший или некорректный формат. Она не загружена в приложение, и синхронизация заблокирована до выбора способа восстановления."],
    ["Your latest result and the direction of recent sessions.", "Последний результат и динамика недавних тренировок."],
    ["into this level", "на этом уровне"],
    ["A one-time Garmin token will be shown. It works like a password: paste it only into this watch's Connect IQ settings. GymApp will not store or show it again. Continue?", "Будет показан одноразовый токен Garmin. Он работает как пароль: вставь его только в настройки Connect IQ этих часов. GymApp не сохранит и больше не покажет его. Продолжить?"],
    ["Last session was stable across the sets.", "Результаты последней тренировки были стабильными во всех подходах."],
    ["Use at least 12 characters (up to 72 UTF-8 bytes) with lowercase and uppercase Latin letters, a number, and a supported symbol such as !, @, #, or $.", "Используй не менее 12 символов (до 72 байт UTF-8): строчную и заглавную латинские буквы, цифру и поддерживаемый спецсимвол, например !, @, # или $."],
    ["Password must contain at least 12 characters, fit within 72 UTF-8 bytes, and include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol.", "Пароль должен содержать не менее 12 символов, занимать не более 72 байт в UTF-8 и включать строчную и заглавную латинские буквы, цифру и поддерживаемый спецсимвол."],
    ["Repeat email", "Повтори адрес электронной почты"],
    ["Resend confirmation email", "Повторно отправить письмо для подтверждения"],
    ["The unseen Garmin token could not be persisted or revoked. Keep this page open and retry Garmin sync or sign-out to revoke it.", "Непоказанный токен Garmin не удалось ни сохранить, ни отозвать. Не закрывай эту страницу: повтори синхронизацию с Garmin или выйди из аккаунта, чтобы отозвать токен."],
    ["Workout summary unavailable.", "Сводка по тренировке недоступна."],
    ["Your training history and next best move.", "Твоя история тренировок и рекомендация, что делать дальше."],
    ["Your active workout was left untouched. Finish or discard it before using this shared plan; the plan will stay ready here.", "Активная тренировка не изменена. Завершите или отмените её перед использованием общего плана; план останется здесь."],
    ["Your current draft is still intact. Replacing it with this shared plan requires a separate confirmation.", "Текущий черновик не изменён. Для его замены общим планом требуется отдельное подтверждение."],
    ["Use this workout plan", "Использовать этот план"],
    ["Replace the current draft?", "Заменить текущий черновик?"],
    ["Replace with shared plan", "Заменить общим планом"]
  ]);
  for (const [english, russian] of auditedRussian) {
    assert.equal(window.GymRussianText.translate(english), russian, english);
  }
  assert.doesNotMatch([...auditedRussian.values()].join("\n"), /погруз|лунн|прыжком|\b(?:pull|push)\b|Sync Watch|Garmin sync/i);
  assert.match(contractSource, /\["en", "uk", "ru"\]\.includes/);
  assert.match(appSource, /data-language="ru">Русский/);
  assert.match(appSource, /\^Garmin\(\?: Fenix 8\)\?\(\?: ·\|\$\)/);
  assert.match(appSource, /tx\("metrics parsed from the saved note", "показники прочитано зі збереженої нотатки"\)/);
  assert.match(appSource, /txAttr\("Name in English, Ukrainian, or Russian", "Назва англійською, українською або російською"\)/);
  assert.doesNotMatch(appSource, /Name in English, Ukrainian or Russian/);
  assert.ok(indexSource.indexOf("russian-text.v76.js") < indexSource.indexOf("exercise-search-vocabulary.v1.js"));
  assert.ok(indexSource.indexOf("exercise-search-vocabulary.v1.js") < indexSource.indexOf("app.v84.js"));
  assert.match(workerSource, /"\.\/russian-text\.v76\.js"/);
});

test("runtime language switches invalidate cached labels on every client", async () => {
  const [androidRoot, iosRoot, pwaApp] = await Promise.all([
    readFile("app/src/main/java/com/example/gymapp/navigation/GymNavGraph.kt", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/App/AppRootView.swift", "utf8"),
    readFile("pwa/app.js", "utf8")
  ]);
  assert.match(androidRoot, /key\(uiIsolationKey, selectedLanguage\) \{ rememberNavController\(\) \}/);
  assert.match(androidRoot, /key\(uiIsolationKey, selectedLanguage\) \{[\s\S]*GymBackground/);
  assert.match(iosRoot, /@AppStorage\("app-language"\)[\s\S]*\.environment\(\\\.locale/);
  assert.doesNotMatch(iosRoot, /\.id\(languageCode\)/);
  assert.match(
    pwaApp,
    /if \(action === "set-language"\)[\s\S]*authNotice = null;[\s\S]*resetGarminProfileContext\(\);[\s\S]*saveState\(\);[\s\S]*return render\(\);/
  );
});

test("Garmin accepts Russian language sync and uses direct touch hit targets", async () => {
  const [manifest, store, view, russianResources, ukrainianResources, buildScript, exerciseLabelsSource] = await Promise.all([
    readFile("garmin/manifest.xml", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/resources-rus/strings.xml", "utf8"),
    readFile("garmin/resources-ukr/strings.xml", "utf8"),
    readFile("scripts/build-garmin.sh", "utf8"),
    readFile("garmin/resources/exercise-labels.json", "utf8")
  ]);
  const exerciseLabels = JSON.parse(exerciseLabelsSource);
  assert.match(manifest, /<iq:language>rus<\/iq:language>/);
  assert.match(store, /language\.equals\("ru"\)/);
  assert.match(store, /static function tr\(en, uk, ru\)/);
  assert.match(store, /System\.LANGUAGE_RUS/);
  assert.match(store, /System\.LANGUAGE_UKR/);
  assert.match(store, /return "Exercise";/);
  assert.match(store, /static function currentExerciseLabel\(\)/);
  assert.match(store, /App\.loadResource\(Rez\.JsonData\.ExerciseLabels\) as Lang\.Dictionary/);
  assert.deepEqual(exerciseLabels["Bench Press"], ["Жим штанги лежачи", "Жим штанги лежа"]);
  assert.deepEqual(exerciseLabels.Squat, ["Присідання зі штангою", "Приседания со штангой"]);
  assert.deepEqual(exerciseLabels.Deadlift, ["Станова тяга", "Становая тяга"]);
  assert.deepEqual(exerciseLabels["Overhead Press"], ["Жим над головою", "Жим над головой"]);
  assert.deepEqual(exerciseLabels.Curl, ["Згинання рук", "Сгибание рук"]);
  assert.match(store, /"exerciseName" => currentExercise\(\)/);
  assert.match(view, /evt\.getCoordinates\(\)/);
  assert.match(view, /function rowAt\(/);
  assert.match(view, /activate\(x < \(view\.screenWidth \/ 2\) \? -1 : 1\)/);
  assert.match(view, /handleSettings\(x < \(view\.screenWidth \/ 2\) \? -1 : 1\)/);
  assert.match(view, /function onMenu\(\)/);
  assert.match(view, /function onNextMode\(\)/);
  assert.match(view, /function onPreviousMode\(\)/);
  assert.match(view, /function drawDiscardConfirmation\(/);
  assert.match(view, /GymStore\.tr\("KEEP WORKOUT", "ЗАЛИШИТИ", "ОСТАВИТЬ"\)/);
  assert.match(view, /GymStore\.tr\("YES, DISCARD", "ТАК, СКАСУВАТИ", "ДА, СБРОСИТЬ"\)/);
  assert.match(view, /GymStore\.currentExerciseLabel\(\)/);
  assert.match(view, /function localizedDecimal\(value\)/);
  assert.match(view, /GymStore\.tr\("kg x ", " кг × ", " кг × "\)/);
  assert.match(view, /GymStore\.tr\("s", "с", "с"\)/);
  assert.match(view, /GymStore\.tr\("DETECT", "ЧУТЛ", "ЧУВСТ"\)/);
  assert.match(view, /function statusLabel\(value\)/);
  assert.match(russianResources, /Облачный токен/);
  assert.match(ukrainianResources, /Хмарний токен/);
  assert.match(buildScript, /-r -e/);
  assert.equal([...manifest.matchAll(/<iq:product id=/g)].length, 108);
});
