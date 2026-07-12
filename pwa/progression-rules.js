(function progressionRulesModule(root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.GymProgressionRules = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function buildProgressionRules() {
  "use strict";

  const RULES_VERSION = 1;

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
    return Math.max(0, 90 + exerciseCount * 16 + setCount * 8 + Math.round(volume / 80));
  }

  function requirementForLevel(level) {
    const stage = Math.max(0, nonNegativeInteger(level) - 1);
    return 200 + stage * 85 + stage * stage * 8;
  }

  function cumulativeXPForLevel(level) {
    const target = Math.max(1, nonNegativeInteger(level));
    let total = 0;
    for (let current = 1; current < target; current += 1) {
      total += requirementForLevel(current);
    }
    return total;
  }

  function levelProgress(totalXP) {
    const total = nonNegativeInteger(totalXP);
    let level = 1;
    let remaining = total;
    let next = requirementForLevel(level);
    while (remaining >= next) {
      remaining -= next;
      level += 1;
      next = requirementForLevel(level);
    }
    return {
      level,
      currentLevelXp: remaining,
      xpForNextLevel: next,
      levelStartXp: total - remaining,
      nextLevelXp: total - remaining + next,
      progressFraction: Math.min(1, remaining / next)
    };
  }

  return Object.freeze({
    RULES_VERSION,
    sessionXP,
    requirementForLevel,
    cumulativeXPForLevel,
    levelProgress
  });
});
