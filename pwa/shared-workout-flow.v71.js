(function (root, factory) {
  const codec = root.GymSharedWorkout ||
    (typeof module !== "undefined" && module.exports && typeof require === "function"
      ? require("./shared-workout.js")
      : null);
  const api = factory(codec);
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  root.GymSharedWorkoutFlow = api;
})(typeof globalThis !== "undefined" ? globalThis : window, function buildSharedWorkoutFlow(codec) {
  "use strict";

  if (!codec?.normalize) throw new TypeError("Shared workout codec is unavailable.");

  function editableDraft(input, now = Date.now()) {
    const plan = codec.normalize(input);
    if (!Number.isSafeInteger(now) || now <= 0) {
      throw new TypeError("Shared workout draft timestamp is invalid.");
    }
    return {
      startedAt: now,
      note: "",
      blocks: plan.exercises.map(exercise => ({
        exerciseName: exercise.name,
        ...(exercise.catalogKey ? { catalogKey: exercise.catalogKey } : {}),
        sets: exercise.sets.map(set => ({ weight: set.weight, reps: set.reps }))
      }))
    };
  }

  function prepareImport(input, options = {}) {
    const plan = codec.normalize(input);
    if (options.hasActiveWorkout === true) {
      return Object.freeze({ status: "blocked-active", plan });
    }
    if (options.hasDraft === true && options.allowDraftReplacement !== true) {
      return Object.freeze({ status: "confirm-replace", plan });
    }
    return Object.freeze({
      status: "ready",
      plan,
      draft: editableDraft(plan, options.now ?? Date.now())
    });
  }

  return Object.freeze({ editableDraft, prepareImport });
});
