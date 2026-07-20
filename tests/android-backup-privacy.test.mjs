import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [
  manifest,
  legacyRules,
  extractionRules,
  providerPaths,
  screen,
  viewModel,
  repository,
  clipboardHelper,
  stringsEn,
  stringsUk,
  stringsRu,
] =
  await Promise.all([
    readFile("app/src/main/AndroidManifest.xml", "utf8"),
    readFile("app/src/main/res/xml/backup_rules.xml", "utf8"),
    readFile("app/src/main/res/xml/data_extraction_rules.xml", "utf8"),
    readFile("app/src/main/res/xml/file_paths.xml", "utf8"),
    readFile(
      "app/src/main/java/com/example/gymapp/ui/screens/ExerciseListScreen.kt",
      "utf8"
    ),
    readFile(
      "app/src/main/java/com/example/gymapp/ui/viewmodel/ExerciseListViewModel.kt",
      "utf8"
    ),
    readFile(
      "app/src/main/java/com/example/gymapp/data/repository/GymRepository.kt",
      "utf8"
    ),
    readFile(
      "app/src/main/java/com/example/gymapp/ui/util/SensitiveClipboard.kt",
      "utf8"
    ),
    readFile("app/src/main/res/values/strings.xml", "utf8"),
    readFile("app/src/main/res/values-uk/strings.xml", "utf8"),
    readFile("app/src/main/res/values-ru/strings.xml", "utf8"),
  ]);

function stringResource(xml, name) {
  return xml.match(new RegExp(`<string\\s+name="${name}">([\\s\\S]*?)<\\/string>`))?.[1];
}

const requiredExclusions = [
  /<exclude\s+domain="database"\s+path="\."\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="gym_cloud_auth\.xml"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="gym_cloud_auth\.xml\.bak"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="gym_local_database_bindings\.xml"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="gym_local_database_bindings\.xml\.bak"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="garmin_sync\.xml"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="garmin_sync\.xml\.bak"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="phone_wear_sync\.xml"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="phone_wear_sync\.xml\.bak"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="gym_training_profile\.xml"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="gym_training_profile\.xml\.bak"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="gym_training_profiles\.xml"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="gym_training_profiles\.xml\.bak"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="gym_cloud_sync_baselines\.xml"\s*\/>/,
  /<exclude\s+domain="sharedpref"\s+path="gym_cloud_sync_baselines\.xml\.bak"\s*\/>/,
];

function assertPrivateDataExcluded(rules, label) {
  for (const exclusion of requiredExclusions) {
    assert.match(rules, exclusion, `${label} is missing ${exclusion}`);
  }
}

test("the application wires both Android backup rule formats", () => {
  assert.match(manifest, /android:fullBackupContent="@xml\/backup_rules"/);
  assert.match(manifest, /android:dataExtractionRules="@xml\/data_extraction_rules"/);
});

test("legacy Android backups exclude private databases and device-bound state", () => {
  assertPrivateDataExcluded(legacyRules, "legacy full backup");
});

test("cloud backup and device transfer both exclude private account state", () => {
  const cloud = extractionRules.match(
    /<cloud-backup>([\s\S]*?)<\/cloud-backup>/
  )?.[1];
  const transfer = extractionRules.match(
    /<device-transfer>([\s\S]*?)<\/device-transfer>/
  )?.[1];

  assert.ok(cloud, "cloud-backup rules are missing");
  assert.ok(transfer, "device-transfer rules are missing");
  assertPrivateDataExcluded(cloud, "cloud backup");
  assertPrivateDataExcluded(transfer, "device transfer");
});

test("full backup clipboard export requires confirmation and uses timed sensitive copy", () => {
  assert.match(screen, /showClipboardWarning\s*=\s*true/);
  assert.match(screen, /backup_copy_warning_message/);
  assert.match(screen, /SensitiveClipboard\.copyBackup\(context, json\)/);
  assert.doesNotMatch(screen, /LocalClipboardManager/);

  assert.match(
    clipboardHelper,
    /android\.content\.extra\.IS_SENSITIVE/
  );
  assert.match(clipboardHelper, /BACKUP_CLEAR_DELAY_MILLIS\s*=\s*60_000L/);
  assert.match(
    clipboardHelper,
    /MAX_CLIPBOARD_BACKUP_BYTES\s*=\s*256\s*\*\s*1_024/
  );
  assert.match(clipboardHelper, /utf8ByteLengthAtMost/);
  assert.match(screen, /if \(!SensitiveClipboard\.copyBackup\(context, json\)\)/);
  assert.match(clipboardHelper, /matchesBackupClip\(/);
  assert.match(clipboardHelper, /MessageDigest\.isEqual/);
  assert.match(clipboardHelper, /clearPrimaryClip\(\)/);
  assert.equal(
    [...clipboardHelper.matchAll(/catch \(_:\s*RuntimeException\)/g)].length,
    3,
    "Binder/service failures during clipboard write, read, or cleanup must not crash export"
  );
});

test("private backup preview cannot bypass the guarded clipboard action", () => {
  const sheet = screen.slice(
    screen.indexOf("private fun BackupJsonBottomSheetContent"),
    screen.indexOf("private fun ImportBackupBottomSheetContent")
  );
  assert.match(screen, /BACKUP_PREVIEW_CHARS\s*=\s*4_000/);
  assert.match(screen, /Text\(\s*text\s*=\s*preview,/);
  assert.doesNotMatch(
    screen,
    /OutlinedTextField\([\s\S]{0,240}?value\s*=\s*json,/
  );
  assert.doesNotMatch(sheet, /SelectionContainer\s*\(/);
  assert.match(screen, /R\.string\.backup_preview_truncated/);
  const previews = [stringsEn, stringsUk, stringsRu].map((xml) =>
    stringResource(xml, "backup_preview_truncated")
  );
  assert.ok(previews.every(Boolean), "every supported locale must label a truncated preview");
  assert.equal(new Set(previews).size, 3, "preview warning must be translated in every locale");
});

test("large private backup sharing uses bounded FileProvider streams, never Binder text", () => {
  const sheetStart = screen.indexOf("private fun BackupJsonBottomSheetContent");
  const sheetEnd = screen.indexOf("private fun ImportBackupBottomSheetContent", sheetStart);
  const sheet = screen.slice(sheetStart, sheetEnd);

  assert.ok(sheetStart >= 0 && sheetEnd > sheetStart, "backup sheet is missing");
  assert.doesNotMatch(screen, /Intent\.EXTRA_TEXT/);
  assert.match(
    sheet,
    /withContext\(Dispatchers\.IO\)\s*\{\s*createBackupJsonFile\(context, json\)/
  );
  assert.match(
    sheet,
    /withContext\(Dispatchers\.IO\)\s*\{\s*createBackupPdfFile\(context, json\)/
  );
  assert.match(screen, /putExtra\(Intent\.EXTRA_STREAM, uri\)/);
  assert.match(screen, /clipData\s*=\s*ClipData\.newRawUri\(file\.name, uri\)/);
  assert.match(screen, /Intent\.FLAG_GRANT_READ_URI_PERMISSION/);
  assert.match(screen, /WorkoutDataLimits\.MAX_BACKUP_BYTES/);
  assert.doesNotMatch(screen, /MAX_PRIVATE_BACKUP_BYTES/);
  assert.match(screen, /File\.createTempFile\(prefix, suffix, shareDirectory\)/);
  assert.equal(
    [...screen.matchAll(/outputFile\.delete\(\)/g)].length,
    2,
    "partial JSON/PDF share files must be removed after failed writes"
  );
});

test("private share cleanup preserves fresh granted URIs and fails closed at its cap", () => {
  const helperStart = screen.indexOf("private fun createPrivateBackupShareFile");
  const helperEnd = screen.indexOf("private fun backupReportLines", helperStart);
  const helper = screen.slice(helperStart, helperEnd);

  assert.ok(helperStart >= 0 && helperEnd > helperStart, "share retention helper is missing");
  assert.match(screen, /PRIVATE_SHARE_RETENTION_MILLIS\s*=\s*24\s*\*\s*60\s*\*\s*60\s*\*\s*1_000L/);
  assert.match(screen, /MAX_RETAINED_PRIVATE_SHARE_FILES\s*=\s*32/);
  assert.match(helper, /synchronized\(PRIVATE_SHARE_FILE_LOCK\)/);
  assert.match(helper, /age\s*>=\s*PRIVATE_SHARE_RETENTION_MILLIS/);
  assert.match(
    helper,
    /retainedCount\s*<\s*MAX_RETAINED_PRIVATE_SHARE_FILES/
  );
  assert.match(helper, /File\.createTempFile\(prefix, suffix, shareDirectory\)/);
  assert.doesNotMatch(
    helper,
    /artifacts\.forEach\(File::delete\)/,
    "fresh chooser grants must never be invalidated by blanket cleanup"
  );
});

test("private PDF rendering is off-main, clearly labeled, and resource bounded", () => {
  assert.match(screen, /MAX_PDF_PAGES\s*=\s*24/);
  assert.match(screen, /MAX_PDF_REPORT_LINES\s*=\s*480/);
  assert.match(screen, /MAX_PDF_EXERCISES_PER_SESSION\s*=\s*24/);
  assert.match(screen, /MAX_PDF_SETS_PER_EXERCISE\s*=\s*20/);
  assert.match(screen, /pageNumber\s*>=\s*MAX_PDF_PAGES/);
  assert.match(screen, /lines\.take\(MAX_PDF_REPORT_LINES\)/);
  assert.match(
    screen,
    /coerceAtMost\(\s*MAX_PDF_EXERCISES_PER_SESSION\s*\)/
  );
  assert.match(screen, /coerceAtMost\(\s*MAX_PDF_SETS_PER_EXERCISE\s*\)/);
  assert.match(screen, /boundedPdfText\(/);
  assert.match(screen, /word\.chunked\(maxChars\)/);
  assert.match(screen, /R\.string\.backup_report_diagnostics_title/);
  assert.match(screen, /R\.string\.backup_report_private_title/);
  assert.match(screen, /R\.string\.backup_report_private_notice/);
  for (const xml of [stringsEn, stringsUk, stringsRu]) {
    assert.ok(stringResource(xml, "backup_report_diagnostics_title"));
    assert.ok(stringResource(xml, "backup_report_private_title"));
    assert.ok(stringResource(xml, "backup_report_private_notice"));
  }
  const privateTitles = [stringsEn, stringsUk, stringsRu].map((xml) =>
    stringResource(xml, "backup_report_private_title")
  );
  assert.equal(new Set(privateTitles).size, 3, "private report title must be translated");
  assert.match(screen, /finally\s*\{\s*document\.close\(\)/);

  const pdfStart = screen.indexOf("private fun createBackupPdfFile");
  const pdfEnd = screen.indexOf("private fun createPrivateBackupShareFile", pdfStart);
  const pdfMethod = screen.slice(pdfStart, pdfEnd);
  assert.ok(pdfStart >= 0 && pdfEnd > pdfStart, "PDF generator is missing");
  assert.ok(
    pdfMethod.indexOf("val reportLines = backupReportLines(context, json)") <
      pdfMethod.indexOf("val document = PdfDocument()"),
    "bounded report parsing must finish before the PdfDocument lifecycle starts"
  );
});

test("backup and diagnostics UI labels are carried atomically with generated JSON", () => {
  assert.match(
    viewModel,
    /data class GeneratedExerciseExport\([\s\S]*val json: String,[\s\S]*val diagnosticsOnly: Boolean/
  );
  assert.match(
    viewModel,
    /GeneratedExerciseExport\(\s*json = json,\s*diagnosticsOnly = false/
  );
  assert.match(
    viewModel,
    /GeneratedExerciseExport\(\s*json = json,\s*diagnosticsOnly = true/
  );
  assert.match(screen, /diagnosticsOnly = uiState\.backupIsDiagnostics/);
  assert.match(screen, /R\.string\.backup_diagnostics_ready/);
  assert.match(screen, /R\.string\.backup_export_ready/);
  assert.doesNotMatch(
    screen.slice(
      screen.indexOf("private fun BackupJsonBottomSheetContent"),
      screen.indexOf("private fun ImportBackupBottomSheetContent")
    ),
    /JSONObject\(json\)/,
    "the main-thread sheet must not reparse an up-to-8 MiB export to choose its title"
  );
});

test("FileProvider exposes only the dedicated ephemeral report directory", () => {
  assert.match(providerPaths, /<cache-path[\s\S]*path="backup-share\/"\s*\/>/);
  assert.doesNotMatch(providerPaths, /<cache-path[\s\S]*path="\."\s*\/>/);
  assert.match(screen, /File\(context\.cacheDir, "backup-share"\)/);
  assert.match(screen, /isPrivateBackupShareArtifact/);
  assert.match(screen, /file\.name\.startsWith\("gymapp-backup-"\)/);
  assert.match(screen, /file\.name\.startsWith\("gymapp-report-"\)/);
});

test("diagnostics export is aggregate-only rather than a mislabeled private backup", () => {
  assert.match(viewModel, /repository\.exportDiagnosticsJson\(\)/);
  assert.doesNotMatch(
    viewModel,
    /exportBackupJson\(includeDiagnostics\s*=\s*true/
  );

  const start = repository.indexOf("suspend fun exportDiagnosticsJson");
  const end = repository.indexOf("suspend fun buildBackupJson", start);
  assert.ok(start >= 0 && end > start, "redacted diagnostics method is missing");
  const diagnosticsMethod = repository.slice(start, end);
  assert.match(diagnosticsMethod, /exerciseCount/);
  assert.match(diagnosticsMethod, /sessionCount/);
  assert.match(diagnosticsMethod, /setCount/);
  assert.doesNotMatch(diagnosticsMethod, /owner|email|userId|exercises|sessions|notes?/);
});
