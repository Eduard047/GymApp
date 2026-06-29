(function (root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  root.GymGarminCloud = api;
})(typeof globalThis !== "undefined" ? globalThis : window, function () {
  function draftToGarminPlan(draft, options = {}) {
    if (!draft) return null;
    const exercises = [];
    (draft.blocks || []).forEach(block => {
      const name = String(block.exerciseName || "").trim();
      if (!name) return;
      const sets = [];
      (block.sets || []).forEach((set, index) => {
        const weight = Number(String(set.weight).replace(",", "."));
        const reps = Number.parseInt(set.reps, 10);
        if (Number.isFinite(weight) && weight >= 0 && reps > 0) {
          sets.push({ weight, reps, orderIndex: index });
        }
      });
      if (sets.length) exercises.push({ name, sets });
    });
    if (!exercises.length) return null;
    const now = options.now || (() => new Date());
    return {
      source: "pwa",
      version: 1,
      title: options.title || "Workout plan",
      createdAt: now().toISOString(),
      startedAt: new Date(draft.startedAt || Date.now()).toISOString(),
      note: draft.note || "",
      exercises
    };
  }

  function cloudPlanResponseToSyncMessage(response, fallbackReps = 8) {
    if (!response || response.status !== "ok" || !response.plan || !Array.isArray(response.plan.exercises)) {
      return null;
    }
    const planNames = [];
    const planWeights = [];
    const planReps = [];
    response.plan.exercises.forEach(exercise => {
      const name = String(exercise?.name || "").trim();
      if (!name || !Array.isArray(exercise.sets)) return;
      exercise.sets.forEach(set => {
        if (!set) return;
        planNames.push(name);
        planWeights.push(Number.isFinite(Number(set.weight)) ? Number(set.weight) : 0);
        const reps = Number.parseInt(set.reps, 10);
        planReps.push(reps > 0 ? reps : fallbackReps);
      });
    });
    if (!planNames.length) return null;
    return {
      type: "sync",
      syncId: response.planId ? String(response.planId) : "cloud",
      resetWorkout: false,
      planNames,
      planWeights,
      planReps
    };
  }

  return { draftToGarminPlan, cloudPlanResponseToSyncMessage };
});
