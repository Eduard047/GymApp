(function progressionRulesModule(root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.GymProgressionRules = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function buildProgressionRules() {
  "use strict";

  const RULES_VERSION = 1;
  const MAX_SUPPORTED_XP = 2147483647;
  const MAX_SESSION_XP = 5000;

  function nonNegativeInteger(value) {
    const numeric = Number(value);
    return Number.isFinite(numeric) ? Math.max(0, Math.trunc(numeric)) : 0;
  }

  function nonNegativeNumber(value) {
    const numeric = Number(value);
    return Number.isFinite(numeric) ? Math.max(0, numeric) : 0;
  }

  function sessionXP(summary) {
    const exerciseCount = nonNegativeInteger(summary?.exercises ?? summary?.exerciseCount);
    const setCount = nonNegativeInteger(summary?.sets ?? summary?.setCount);
    const volume = nonNegativeNumber(summary?.volume ?? summary?.totalVolume);
    if (setCount === 0) return 0;
    return Math.min(
      MAX_SESSION_XP,
      Math.max(0, 90 + exerciseCount * 16 + setCount * 8 + Math.round(volume / 80))
    );
  }

  function requirementForLevel(level) {
    const stage = Math.max(0, nonNegativeInteger(level) - 1);
    return 200 + stage * 85 + stage * stage * 8;
  }

  function cumulativeXPForLevel(level) {
    const target = Math.max(1, nonNegativeInteger(level));
    const stages = target - 1;
    const linear = stages * (stages - 1) / 2;
    const squares = stages * (stages - 1) * (2 * stages - 1) / 6;
    return 200 * stages + 85 * linear + 8 * squares;
  }

  function levelProgress(totalXP) {
    const total = Math.min(MAX_SUPPORTED_XP, nonNegativeInteger(totalXP));
    let low = 1;
    let high = 2;
    while (high < 65536 && cumulativeXPForLevel(high) <= total) high *= 2;
    while (low + 1 < high) {
      const middle = Math.floor((low + high) / 2);
      if (cumulativeXPForLevel(middle) <= total) low = middle;
      else high = middle;
    }
    const level = low;
    const levelStart = cumulativeXPForLevel(level);
    const remaining = total - levelStart;
    const next = requirementForLevel(level);
    return {
      level,
      currentLevelXp: remaining,
      xpForNextLevel: next,
      levelStartXp: levelStart,
      nextLevelXp: Math.min(MAX_SUPPORTED_XP, levelStart + next),
      progressFraction: Math.min(1, remaining / next)
    };
  }

  return Object.freeze({
    RULES_VERSION,
    MAX_SUPPORTED_XP,
    MAX_SESSION_XP,
    sessionXP,
    requirementForLevel,
    cumulativeXPForLevel,
    levelProgress
  });
});
