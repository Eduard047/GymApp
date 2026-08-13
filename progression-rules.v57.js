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

  function mondayStart(timestamp) {
    const date = new Date(Number(timestamp));
    if (!Number.isFinite(date.getTime())) return null;
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() - ((date.getDay() + 6) % 7));
    return date.getTime();
  }

  function localDayKey(timestamp) {
    const date = new Date(Number(timestamp));
    if (!Number.isFinite(date.getTime())) return null;
    return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
  }

  function weeklyTrainingDays(sessions, maximumTimestamp = Number.POSITIVE_INFINITY) {
    const maximum = Number(maximumTimestamp);
    if (!Number.isFinite(maximum) && maximum !== Number.POSITIVE_INFINITY) return new Map();
    const weeks = new Map();
    for (const session of Array.isArray(sessions) ? sessions : []) {
      const timestamp = Number(session?.startedAt ?? session?.date);
      if (!Number.isFinite(timestamp) || timestamp > maximum) continue;
      const week = mondayStart(timestamp);
      const day = localDayKey(timestamp);
      if (week === null || day === null) continue;
      const days = weeks.get(week) || new Set();
      days.add(day);
      weeks.set(week, days);
    }
    return weeks;
  }

  function weeklyTarget(value) {
    const target = Number(value);
    return Number.isInteger(target) && target >= 2 && target <= 6 ? target : 3;
  }

  function currentWeeklyStreak(sessions, now = Date.now(), target = 3) {
    const nowTimestamp = Number(now);
    if (!Number.isFinite(nowTimestamp)) return 0;
    const weeks = weeklyTrainingDays(sessions, nowTimestamp);
    if (!weeks.size) return 0;
    const required = weeklyTarget(target);

    let cursor = mondayStart(now);
    if (cursor === null) return 0;
    if ((weeks.get(cursor)?.size || 0) < required) {
      const previous = new Date(cursor);
      previous.setDate(previous.getDate() - 7);
      cursor = previous.getTime();
    }

    let streak = 0;
    while ((weeks.get(cursor)?.size || 0) >= required) {
      streak++;
      const previous = new Date(cursor);
      previous.setDate(previous.getDate() - 7);
      cursor = previous.getTime();
    }
    return streak;
  }

  function bestWeeklyStreakDuring(sessions, periodStart, periodEnd, target = 3) {
    const start = Number(periodStart);
    const end = Number(periodEnd);
    if (!Number.isFinite(start) || !Number.isFinite(end) || end < start) return 0;
    const required = weeklyTarget(target);
    const successfulWeeks = [...weeklyTrainingDays(sessions, end)]
      .filter(([, days]) => days.size >= required)
      .map(([week]) => week)
      .sort((left, right) => left - right);
    let previousWeek = null;
    let running = 0;
    let best = 0;
    for (const week of successfulWeeks) {
      if (previousWeek === null) {
        running = 1;
      } else {
        const expected = new Date(previousWeek);
        expected.setDate(expected.getDate() + 7);
        running = expected.getTime() === week ? running + 1 : 1;
      }
      const weekEnd = new Date(week);
      weekEnd.setDate(weekEnd.getDate() + 7);
      if (week <= end && weekEnd.getTime() > start) best = Math.max(best, running);
      previousWeek = week;
    }
    return best;
  }

  return Object.freeze({
    RULES_VERSION,
    MAX_SUPPORTED_XP,
    MAX_SESSION_XP,
    sessionXP,
    requirementForLevel,
    cumulativeXPForLevel,
    levelProgress,
    mondayStart,
    localDayKey,
    weeklyTrainingDays,
    currentWeeklyStreak,
    bestWeeklyStreakDuring
  });
});
