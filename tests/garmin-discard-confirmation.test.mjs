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

test("Garmin workout discard requires an explicit safe-default confirmation", async () => {
  const [view, store] = await Promise.all([
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8")
  ]);

  assert.match(view, /var discardSelected = 0;/);
  assert.match(view, /page == 6[\s\S]*drawDiscardConfirmation\(dc, w, h\)/);
  assert.match(view, /GymStore\.tr\("DISCARD WORKOUT\?", "СКАСУВАТИ\?", "СБРОСИТЬ\?"\)/);
  assert.match(view, /GymStore\.tr\("CANNOT BE UNDONE", "НЕ МОЖНА СКАСУВАТИ", "НЕЛЬЗЯ ОТМЕНИТЬ"\)/);
  assert.match(view, /GymStore\.tr\("KEEP WORKOUT", "ЗАЛИШИТИ", "ОСТАВИТЬ"\)/);
  assert.match(view, /GymStore\.tr\("YES, DISCARD", "ТАК, СКАСУВАТИ", "ДА, СБРОСИТЬ"\)/);

  const pauseHandler = section(view, "function handlePauseMenu()", "function openDiscardConfirmation()");
  assert.match(pauseHandler, /openDiscardConfirmation\(\)/);
  assert.doesNotMatch(pauseHandler, /clearWorkout\(\)|GymSession\.discard\(\)|System\.exit\(\)/);

  const openConfirmation = section(view, "function openDiscardConfirmation()", "function cancelDiscardConfirmation()");
  assert.match(openConfirmation, /view\.discardSelected = 0;[\s\S]*view\.page = 6;/);

  const cancelConfirmation = section(view, "function cancelDiscardConfirmation()", "function moveDiscardSelection(");
  assert.match(cancelConfirmation, /view\.discardSelected = 0;/);
  assert.match(cancelConfirmation, /view\.pauseSelected = 0;/);
  assert.match(cancelConfirmation, /view\.page = 2;/);

  const confirmHandler = section(view, "function handleDiscardConfirmation()", "function activate(");
  assert.match(confirmHandler, /if \(view\.discardSelected == 0\)[\s\S]*cancelDiscardConfirmation\(\);[\s\S]*return;/);
  assert.match(confirmHandler, /GymStore\.clearWorkout\(\);[\s\S]*GymSession\.discard\(\);[\s\S]*System\.exit\(\);/);

  const backHandler = section(view, "function onBack()", "function onTap(");
  assert.match(backHandler, /if \(view\.page == 6\)[\s\S]*cancelDiscardConfirmation\(\);[\s\S]*return true;/);

  const tapHandler = section(view, "function onTap(evt)", "function rowAt(");
  assert.match(tapHandler, /view\.page == 6[\s\S]*rowAt\(y, 144, 48, 2\)[\s\S]*handleDiscardConfirmation\(\)/);

  for (const handler of ["onNextPage()", "onPreviousPage()", "onNextMode()", "onPreviousMode()"]) {
    const handlerSection = section(view, `function ${handler}`, "function ");
    assert.match(handlerSection, /view\.page == 6[\s\S]*moveDiscardSelection\(/, handler);
  }
  const keyHandler = section(view, "function onKey(evt)", "function handleSelect()");
  assert.match(keyHandler, /view\.page == 6[\s\S]*moveDiscardSelection\(-1\)/);
  assert.match(keyHandler, /view\.page == 6[\s\S]*moveDiscardSelection\(1\)/);

  // Account transitions remain an automatic privacy boundary and never wait on UI state.
  const syncApply = section(store, "static function applySyncFromSource", "static function isValidSyncMessage");
  assert.match(syncApply, /if \(accountChanged \|\| resetWorkout\)[\s\S]*clearAccountScopedState\(\);[\s\S]*GymSession\.resetForAccountTransition\(\);/);
  assert.doesNotMatch(syncApply, /discardSelected|openDiscardConfirmation|page == 6/);
});
