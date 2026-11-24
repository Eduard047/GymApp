import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const kotlin = "app/src/main/java/com/example/gymapp";
const read = (path) => readFile(path, "utf8");
const [watches, card, state, viewModel, graph, binding, syncManager] = await Promise.all([
  read(`${kotlin}/ui/screens/WatchesScreen.kt`),
  read(`${kotlin}/ui/screens/WearWatchCard.kt`),
  read(`${kotlin}/ui/viewmodel/WearWatchState.kt`),
  read(`${kotlin}/ui/viewmodel/WearWatchViewModel.kt`),
  read(`${kotlin}/navigation/GymNavGraph.kt`),
  read(`${kotlin}/wearsync/PhoneWearBindingManager.kt`),
  read(`${kotlin}/wearsync/PhoneWearSyncManager.kt`)
]);
const locales = { en: "values", uk: "values-uk", ru: "values-ru" };
const strings = Object.fromEntries(
  await Promise.all(
    Object.entries(locales).map(async ([lang, dir]) => [lang, await read(`app/src/main/res/${dir}/strings.xml`)])
  )
);

const expected = {
  watches_wear_title: { en: "Wear OS", uk: "Wear OS", ru: "Wear OS" },
  watches_wear_caption: {
    // "Wear OS" never breaks across lines: the resource carries a no-break space escape.
    en: "Samsung Galaxy Watch, Pixel Watch and other Wear\\u00A0OS watches",
    uk: "Samsung Galaxy Watch, Pixel Watch та інші годинники Wear\\u00A0OS",
    ru: "Samsung Galaxy Watch, Pixel Watch и другие часы Wear\\u00A0OS"
  },
  watches_wear_not_linked: {
    // First link is automatic; after an unpair the watch links only from its own action.
    en: "Install GymApp on your watch and open it near this phone — it pairs automatically. After unpairing, tap “Link to phone” on the watch.",
    uk: "Встановіть GymApp на годинник і відкрийте його поруч із телефоном — годинник прив’яжеться автоматично. Після відв’язування натисніть на годиннику «Прив’язати до телефона».",
    ru: "Установите GymApp на часы и откройте его рядом с телефоном — часы привяжутся автоматически. После отвязки нажмите на часах «Привязать к телефону»."
  },
  watches_wear_default_name: { en: "Wear\\u00A0OS watch", uk: "Годинник Wear\\u00A0OS", ru: "Часы Wear\\u00A0OS" },
  // One pairing word on the whole Watches screen: the same tag as the Garmin card.
  watches_wear_linked: { en: "Paired", uk: "Прив’язано", ru: "Привязано" },
  watches_wear_link_pending: {
    en: "Open GymApp on the watch to finish pairing.",
    uk: "Відкрийте GymApp на годиннику, щоб завершити прив’язування.",
    ru: "Откройте GymApp на часах, чтобы завершить привязку."
  },
  watches_wear_unlink_action: { en: "Unpair watch", uk: "Відв’язати годинник", ru: "Отвязать часы" },
  watches_wear_unlink_title: { en: "Unpair this watch?", uk: "Відв’язати цей годинник?", ru: "Отвязать эти часы?" },
  watches_wear_unlink_body: {
    en: "Workouts not yet sent from the watch stay on the watch. To pair again, tap “Link to phone” on the watch.",
    uk: "Тренування, ще не надіслані з годинника, залишаться на ньому. Щоб прив’язати знову, натисніть на годиннику «Прив’язати до телефона».",
    ru: "Тренировки, ещё не отправленные с часов, останутся на них. Чтобы привязать снова, нажмите на часах «Привязать к телефону»."
  },
  watches_wear_unlink_confirm: { en: "Unpair", uk: "Відв’язати", ru: "Отвязать" }
};

test("the Wear OS card sits between the Garmin and Health data cards", () => {
  const garmin = watches.indexOf("GarminDeviceCard(");
  const wear = watches.indexOf("WearWatchCard(");
  const health = watches.indexOf("HealthDataCard(");
  assert.ok(garmin > 0 && wear > garmin && health > wear, "Garmin → Wear OS → Health data");
  assert.match(watches, /onUnlink = onUnlinkWearWatch/);
});

test("Wear OS strings exist in en, uk and ru with the agreed copy", () => {
  for (const [key, copy] of Object.entries(expected)) {
    for (const lang of Object.keys(locales)) {
      assert.ok(strings[lang].includes(`<string name="${key}">${copy[lang]}</string>`), `${lang}/${key}`);
    }
  }
  // Ukrainian uses the typographic apostrophe only.
  for (const key of Object.keys(expected)) {
    const line = strings.uk.split("\n").find((l) => l.includes(`name="${key}"`));
    assert.doesNotMatch(line, /\\'|[a-zа-яієїґ]'[a-zа-яієїґ]/i, key);
  }
});

test("the card reuses the Garmin capability line, connection strings and flat style", () => {
  assert.match(card, /title = stringResource\(R\.string\.watches_wear_title\)/);
  assert.match(card, /supporting = stringResource\(R\.string\.watches_garmin_capability\)/);
  assert.match(card, /R\.string\.garmin_profile_connected/);
  assert.match(card, /R\.string\.garmin_profile_offline/);
  assert.match(card, /R\.string\.watches_wear_caption/);
  assert.match(card, /R\.string\.watches_wear_not_linked/);
  // The "Paired" tag needs the watch's proof; a pinned but unconfirmed watch gets the hint instead.
  // Narrow rows move the tag under the status line; both places stay gated on linkConfirmed.
  assert.match(card, /val tagUnderStatus = state\.linkConfirmed &&\s*watchRowIsNarrow\(/);
  assert.match(card, /if \(tagUnderStatus\) WearLinkedTag\(/);
  assert.match(card, /if \(state\.linkConfirmed && !tagUnderStatus\) WearLinkedTag\(\)/);
  assert.equal((card.match(/WearLinkedTag\(/g) || []).length, 3);
  assert.match(card, /fun WearLinkedTag\([^)]*\) \{\s*Text\(\s*text = stringResource\(R\.string\.watches_wear_linked\)/);
  assert.match(card, /if \(!state\.linkConfirmed\) \{\s*Text\(\s*text = stringResource\(R\.string\.watches_wear_link_pending\)/);
  for (const lang of Object.keys(locales)) {
    assert.equal(strings[lang].includes('<string name="garmin_profile_paired">' + expected.watches_wear_linked[lang] + "</string>"), true, lang);
  }
  assert.match(card, /AppPanel\(/);
  assert.match(card, /SectionTitle\(/);
  assert.doesNotMatch(card, /Brush\.(linear|radial|vertical|horizontal)Gradient/);
});

test("unlink is destructive and behind a confirmation dialog", () => {
  assert.match(card, /onClick = \{ showUnlinkConfirmation = true \}/);
  assert.match(
    card,
    /GymAlertDialog\([\s\S]*watches_wear_unlink_title[\s\S]*watches_wear_unlink_body[\s\S]*onUnlink\(\)[\s\S]*GymAlertDialogButtonRole\.Destructive[\s\S]*watches_wear_unlink_confirm[\s\S]*GymAlertDialogButtonRole\.Cancel[\s\S]*R\.string\.action_cancel/
  );
  // Unlink forgets the pin and what is stored for that watch (name, link proof, cached plans) and
  // remembers the node as unlinked; account generations and sync revisions are never removed.
  const clear = binding.slice(binding.indexOf("fun clearPinnedSource"), binding.indexOf("fun isUnlinkedNode"));
  assert.match(clear, /remove\(KEY_SOURCE_NODE_ID\)/);
  assert.match(clear, /remove\(KEY_SOURCE_OWNER_ID\)/);
  assert.match(clear, /remove\(KEY_WATCH_NAME\)/);
  assert.match(clear, /KEY_PLAN_CACHE_PREFIX/);
  assert.match(clear, /putString\(KEY_UNLINKED_NODE_ID, pinned\)/);
  assert.doesNotMatch(clear, /\.clear\(\)|KEY_ACTIVE_GENERATION|KEY_LAST_GENERATION|KEY_FULL_SYNC_REVISION|KEY_AUTHORITY_EPOCH/);
  // The watch is told (binding state "unlinked") and is not pinned again without its explicit link request.
  assert.match(syncManager, /suspend fun unlinkWatch\(\): Boolean/);
  assert.match(syncManager, /buildBindingState\(binding, unlinked = true[,)]/);
  assert.match(binding, /KEY_UNLINKED_NODE_ID, null\) == sourceNodeId && !linkIntent\) return false/);
  // Every released pin (this phone's Unlink or the watch's own notice) re-reads an open card.
  assert.match(syncManager, /val pinReleases: StateFlow<Long>/);
  assert.match(viewModel, /phoneWearSyncManager\.pinReleases\.drop\(1\)\.collect \{ refresh\(\) \}/);
});

test("the card is hidden when the Wearable API is unavailable and lookups stay off the UI thread", () => {
  assert.match(card, /if \(mode == WearWatchCardMode\.HIDDEN\) return/);
  assert.match(state, /state == null \|\| !state\.apiAvailable -> WearWatchCardMode\.HIDDEN/);
  assert.match(viewModel, /GoogleApiAvailability\.getInstance\(\)\.checkApiAvailability\(nodeClient\)/);
  assert.match(viewModel, /withContext\(Dispatchers\.IO\)/);
  assert.match(viewModel, /withTimeoutOrNull\(LOOKUP_TIMEOUT_MS\)/);
  assert.match(viewModel, /catch \(error: CancellationException\) \{\s*throw error\s*\}/);
});

test("the state holder is wired in the navigation graph like the Health data card", () => {
  assert.match(graph, /viewModel<WearWatchViewModel>\(/);
  assert.match(graph, /key = "wear-watch"/);
  assert.match(graph, /wearWatchState = wearWatchState/);
  assert.match(graph, /onRefreshWearWatch = \{ wearWatchViewModel\?\.refresh\(\) \}/);
  assert.match(graph, /onUnlinkWearWatch = \{ wearWatchViewModel\?\.unlink\(\) \}/);
});

test("the Wear OS release script mirrors the phone AAB script and fails closed", async () => {
  const script = await read("scripts/build-wear-release-aab.ps1");
  assert.match(script, /:wear:bundleRelease/);
  assert.match(script, /"-PdevApplicationIdSuffix=false"/);
  assert.match(script, /gymapp-wear-release\.aab/);
  assert.match(script, /throw "Release signing requires all GYMAPP_RELEASE_\* environment variables\."/);
  assert.match(script, /The release keystore must be stored outside the repository\./);
  assert.match(script, /Assert-AabSignature @aabSignatureArguments/);
  assert.match(script, /\$expectedPackageId = "com\.setforge\.gymapp"/);
  // Never touches Git, the working tree index, or GitHub releases.
  assert.doesNotMatch(script, /\bgit\s+(add|commit|push|stash|reset|checkout|clean|tag)\b|\bgh\s+release\b/);
  assert.doesNotMatch(script, /:app:/);
});

test("CI tests, assembles and lints the Wear OS module and Semgrep scans it", async () => {
  const [workflow, semgrep] = await Promise.all([
    read(".github/workflows/security.yml"),
    read(".github/security/semgrep.yml")
  ]);
  for (const task of [":wear:testDebugUnitTest", ":wear:assembleDebug", ":wear:lintDebug"]) {
    assert.ok(workflow.includes(task), task);
  }
  assert.match(workflow, /--exclude wear\/build/);
  assert.ok((semgrep.match(/- \/wear\/src\/main\/\*\*\/\*\.kt/g) ?? []).length >= 4);
});
