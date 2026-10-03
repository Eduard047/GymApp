import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const section = (source, start, end) => {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notEqual(startIndex, -1, `Missing start anchor: ${start}`);
  assert.notEqual(endIndex, -1, `Missing end anchor: ${end}`);
  return source.slice(startIndex, endIndex);
};

const read = (name) => readFile(`garmin/source/${name}`, "utf8");

test("Clearing unsent workouts needs two confirmations with safe defaults", async () => {
  const view = await read("WorkoutView.mc");

  const open = section(view, "function openClearQueue()", "function cancelDiscardConfirmation()");
  assert.match(open, /if \(!view\.clearQueueAvailable\(\)\) \{ return; \}/);
  assert.match(open, /view\.discardSelected = 0;[\s\S]*view\.clearStage = 1;[\s\S]*view\.page = 6;/);

  const handler = section(view, "function handleClearQueue()", "function moveDiscardSelection(");
  assert.match(handler, /view\.discardSelected == 0 \|\| !view\.clearQueueAvailable\(\)[\s\S]*cancelDiscardConfirmation\(\)/);
  // First confirmation only advances; the second focuses the safe option again.
  assert.match(handler, /view\.clearStage == 1[\s\S]*view\.clearStage = 2;[\s\S]*view\.discardSelected = 0;/);
  assert.equal((handler.match(/discardUnsentQueue\(\)/g) ?? []).length, 1);
  assert.ok(handler.indexOf("clearStage = 2") < handler.indexOf("discardUnsentQueue()"));

  // Page 6 routes both stages, and every cancel path ends on Ready.
  assert.match(
    section(view, "function handleDiscardConfirmation()", "function activate("),
    /if \(view\.clearStage != 0\) \{\s*handleClearQueue\(\);\s*return;/
  );
  const cancel = section(view, "function cancelDiscardConfirmation()", "function handleClearQueue()");
  assert.match(cancel, /view\.clearStage != 0[\s\S]*view\.clearStage = 0;[\s\S]*view\.page = 7;/);
  assert.match(section(view, "function openDiscardConfirmation()", "function openClearQueue()"), /view\.clearStage = 0;/);

  const copy = section(view, "function clearQueueText(part)", "function settingsRows()");
  assert.match(copy, /"DELETE " \+ n \+ " UNSENT\?"/);
  assert.match(copy, /"DELETE " \+ n \+ "\?", "ВИДАЛИТИ " \+ n \+ "\?", "УДАЛИТЬ " \+ n \+ "\?"/);
  assert.match(copy, /"THIS CANNOT BE UNDONE", "ЦЕ НЕ СКАСУВАТИ", "ЭТО НЕЛЬЗЯ ОТМЕНИТЬ"/);
  assert.match(copy, /"WON'T REACH GYMAPP"/);
  assert.match(copy, /"GARMIN KEEPS ACTIVITIES"/);
  assert.match(copy, /"CANCEL", "ВІДМІНИТИ", "ОТМЕНИТЬ"[\s\S]*"KEEP", "ЗАЛИШИТИ", "ОСТАВИТЬ"/);

  // Entry points: Settings row (Instinct profiles; none on fr55) and a Ready row (96 KiB lite).
  assert.match(view, /settingsSelected == 7\) \{\s*openClearQueue\(\);/);
  assert.match(section(view, "function handleReadySelection() {\n        if (view.selected == 2)", "function openReadySettings"), /openClearQueue\(\)/);
  assert.match(view, /function readyActionCount\(\) \{ return clearQueueAvailable\(\) \? 3 : 2; \}/);
  // Page 6 renders the delete confirmation on every profile.
  assert.equal((view.match(/if \(clearStage != 0\) \{ drawClearQueueConfirmation\(dc, w, h\); return; \}/g) ?? []).length, 3);
});

test("Clearing unsent workouts is refused during an active or prepared workout", async () => {
  const [view, store] = await Promise.all([read("WorkoutView.mc"), read("GymStore.mc")]);

  const available = section(view, "function clearQueueAvailable()", "function clearQueueText(part)");
  assert.match(available, /GymStore\.pendingCount\(\) > 0/);
  assert.match(available, /!hasWorkoutToResume\(\)/);
  assert.match(available, /!GymStore\.hasPreparedWorkout\(\)/);

  const discard = section(store, "static function discardUnsentQueue()", "static function removePendingByRequestId(");
  assert.match(discard, /GymSession\.recording \|\| hasUnfinishedWorkout\(\) \|\| hasPreparedWorkout\(\)/);
  assert.match(discard, /!recoverQueuedWorkout\(\)\) \{ return false; \}/);
});

test("Clearing unsent workouts removes only queue storage", async () => {
  const [store, journal, view] = await Promise.all([
    read("GymStore.mc"),
    read("GymPendingJournal.mc"),
    read("WorkoutView.mc")
  ]);

  const discard = section(store, "static function discardUnsentQueue()", "static function removePendingByRequestId(");
  assert.match(discard, /Storage\.setValue\("pending", \[\]\)/);
  assert.match(discard, /pending = \[\]; parkedPending = null; pendingEstimateSource = null;/);
  assert.match(discard, /GymPendingJournal\.discardAll\(\)/);
  assert.match(discard, /Storage\.deleteValue\("queuedActiveRequestId"\)/);
  // The legacy list is committed before the journal; neither touches app state.
  assert.ok(discard.indexOf('"pending"') < discard.indexOf("discardAll()"));
  assert.doesNotMatch(discard, /plan|exercises|binding|Binding|settings|save\(\)|clearWorkout|FIT|Fit/);

  const all = section(journal, "static function discardAll()", "static function origin(");
  // The index delete is the commit and comes before any row cleanup.
  assert.ok(all.indexOf('deleteValue("pendingJournalV1")') < all.indexOf("entryKey(0,"));
  assert.match(all, /deleteValue\("sendProgressV1"\)/);
  assert.match(all, /reset\(\);/);
  assert.match(all, /entryKey\(0, banks\[b\]\)[\s\S]*entryKey\(1, banks\[b\]\)/);
  assert.match(all, /GymActiveJournal\.key\(banks\[b\], n\)[\s\S]*nameKey\(banks\[b\], n\)/);
  assert.match(all, /banks\[b\] == keep\) \{ continue; \}/);
  assert.doesNotMatch(all, /"plan"|"catalog"|Binding|"settings"/);

  // The handler never edits plan, bindings or settings itself.
  const handler = section(view, "function handleClearQueue()", "function moveDiscardSelection(");
  assert.doesNotMatch(handler, /plan|Binding|settings|clearWorkout|GymSession/);
});

test("The open-GymApp hint counts silence from the last transmit or ack", async () => {
  const [view, comm, app] = await Promise.all([read("WorkoutView.mc"), read("GymComm.mc"), read("GymApp.mc")]);
  assert.match(comm, /\(:notFr55Memory\)\s+static var lastActivityAt = null;/);
  assert.match(comm, /\(:notFr55Memory\)\s+static var seenActivityAt = null;/);
  assert.match(comm, /\(:notFr55Memory\)\s+static function noteActivity\(\) \{\s*lastActivityAt = /);
  assert.match(comm, /\(:fr55Memory, :inline\)\s+static function noteActivity\(\) \{\}/);
  // Own transmits mark themselves seen; only a phone ack is new news.
  const ownTransmit = section(comm, "(:notFr55Memory)\n    function onComplete()", "(:fr55Memory)\n    function onComplete()");
  assert.match(ownTransmit, /GymComm\.lastActivityAt = [\s\S]*GymComm\.seenActivityAt = GymComm\.lastActivityAt;/);
  const fr55Complete = section(comm, "(:fr55Memory)\n    function onComplete()", "function onError()");
  assert.doesNotMatch(fr55Complete, /ActivityAt|noteActivity/);
  assert.equal((app.match(/GymComm\.noteActivity\(\);/g) ?? []).length, 2);
  assert.doesNotMatch(app, /lastActivityAt/);
  const retry = section(view, "(:notFr55Memory)\n    function maybeRetryPending()", "(:fr55Memory)\n    function maybeRetryPending()");
  assert.match(retry, /activityAt != GymComm\.seenActivityAt[\s\S]*pendingRetryStartedAt = activityAt;[\s\S]*silentAtCount = 0;/);
  assert.doesNotMatch(view, /\bseenActivityAt\b(?<!GymComm\.seenActivityAt)/);
});

test("The delete-unsent feature is compiled out of Forerunner 55 only", async () => {
  const [view, store, journal] = await Promise.all([
    read("WorkoutView.mc"),
    read("GymStore.mc"),
    read("GymPendingJournal.mc")
  ]);
  // Every feature symbol carries :notFr55Memory (multi-annotation = AND), so the
  // fr55 build (which excludes it) contains none of it.
  const annotated = (source, signature) => {
    const index = source.indexOf(signature);
    assert.notEqual(index, -1, `Missing ${signature}`);
    const before = source.slice(0, index).trimEnd().split("\n").pop();
    return /^\s*\(:[^)]*\bnotFr55Memory\b[^)]*\)\s*$/.test(before);
  };
  for (const signature of [
    "var clearStage = 0;",
    "function clearQueueAvailable()",
    "function clearQueueText(part)",
    "function settingsRows() {\n        var rows",
    "function drawClearQueueConfirmation(dc, w, h) {\n        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);\n        drawCentered",
    "function openClearQueue()",
    "function handleClearQueue()",
    "function openDiscardConfirmation() {\n        // The safe action is always focused first, regardless of how DISCARD was reached.\n        view.discardSelected = 0;\n        view.clearStage",
    "function cancelDiscardConfirmation() {\n        view.discardSelected = 0;\n        if (view.clearStage",
    "function handleDiscardConfirmation() {\n        if (view.clearStage"
  ]) {
    assert.ok(annotated(view, signature), `fr55 must not compile: ${signature}`);
  }
  assert.ok(annotated(store, "static function discardUnsentQueue()"));
  assert.ok(annotated(journal, "static function discardAll()"));

  // The fr55 stand-ins never mention the feature and keep the 4.0.1 behaviour.
  assert.match(view, /\(:fr55Memory\)\s*function settingsRows\(\) \{ return settingsCount; \}/);
  assert.match(view, /\(:compactLegacyState, :richWorkoutMode, :fr55Memory\)\s*function drawDiscardConfirmation\(dc, w, h\) \{\s*drawHeader/);
  assert.match(view, /\(:fr55Memory\)\s*var settingsCount = 3;/);
  const fr55Settings = section(view, "(:fr55Memory)\n    function handleSettings(delta)", "\n}\n");
  assert.doesNotMatch(fr55Settings, /openClearQueue|settingsSelected == 3/);
  // Remaining uses sit only inside :notFr55Memory code or the delete-unsent group.
  const fr55Stubs = [
    section(view, "(:fr55Memory)\n    function openDiscardConfirmation()", "// Delete-unsent reuses"),
    section(view, "(:fr55Memory)\n    function cancelDiscardConfirmation()", "(:notFr55Memory)\n    function handleClearQueue()"),
    section(view, "(:fr55Memory)\n    function handleDiscardConfirmation()", "(:richWorkoutMode)\n    function activate(")
  ].join("\n");
  assert.doesNotMatch(fr55Stubs, /clearStage|clearQueue|ClearQueue|discardUnsent/);
});
