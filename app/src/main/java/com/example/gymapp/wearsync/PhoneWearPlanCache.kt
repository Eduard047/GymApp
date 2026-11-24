package com.example.gymapp.wearsync

import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import org.json.JSONArray
import org.json.JSONObject

/**
 * The last plan the user sent to the watch, kept per account for the pinned watch until one send
 * succeeds. It lives in the same private preference file as the binding and is removed when the
 * watch is unlinked; it is never sent to another owner's binding or to an unpinned node.
 */
internal data class PhoneWearCachedPlan(
    val planId: String,
    val createdAt: Long,
    val sets: List<NamedWorkoutSetDraft>,
    val exerciseCatalog: List<String>,
    val profile: PhoneWearPlanProfile?,
    val planSource: String
)

/** Bounded JSON form of [PhoneWearCachedPlan]; anything out of bounds or too old decodes to null. */
internal object PhoneWearPlanCacheCodec {
    const val MAX_AGE_MS = 7L * 24 * 60 * 60 * 1_000
    private const val MAX_BYTES = 256 * 1024
    private const val MAX_PROFILE_VALUE_LENGTH = 64

    fun encode(plan: PhoneWearCachedPlan): String? {
        if (!isValid(plan)) return null
        val sets = JSONArray()
        plan.sets.forEach { set ->
            sets.put(
                JSONObject()
                    .put("exerciseName", set.exerciseName)
                    .put("weight", set.weight)
                    .put("reps", set.reps)
            )
        }
        val root = JSONObject()
            .put("planId", plan.planId)
            .put("createdAt", plan.createdAt)
            .put("planSource", plan.planSource)
            .put("sets", sets)
            .put("exerciseCatalog", JSONArray(plan.exerciseCatalog))
        plan.profile?.let { profile ->
            root.put(
                "trainingProfile",
                JSONObject()
                    .put("split", profile.split)
                    .put("workoutsPerWeek", profile.workoutsPerWeek)
                    .put("goal", profile.goal)
                    .put("calorieMode", profile.calorieMode)
            )
        }
        return root.toString().takeIf { it.toByteArray(Charsets.UTF_8).size <= MAX_BYTES }
    }

    fun decode(raw: String, now: Long): PhoneWearCachedPlan? = runCatching {
        require(raw.length <= MAX_BYTES)
        val root = JSONObject(raw)
        val setsJson = root.getJSONArray("sets")
        require(setsJson.length() in 1..PhoneWearPaths.MAX_PLAN_SETS)
        val sets = buildList(setsJson.length()) {
            for (index in 0 until setsJson.length()) {
                val item = setsJson.getJSONObject(index)
                add(
                    NamedWorkoutSetDraft(
                        exerciseName = item.getString("exerciseName"),
                        weight = item.getDouble("weight"),
                        reps = item.getInt("reps")
                    )
                )
            }
        }
        val catalogJson = root.getJSONArray("exerciseCatalog")
        require(catalogJson.length() <= PhoneWearPaths.MAX_EXERCISE_CATALOG)
        val catalog = buildList(catalogJson.length()) {
            for (index in 0 until catalogJson.length()) add(catalogJson.getString(index))
        }
        val profile = root.optJSONObject("trainingProfile")?.let { item ->
            PhoneWearPlanProfile(
                split = item.getString("split"),
                workoutsPerWeek = item.getInt("workoutsPerWeek"),
                goal = item.getString("goal"),
                calorieMode = item.getString("calorieMode")
            )
        }
        PhoneWearCachedPlan(
            planId = root.getString("planId"),
            createdAt = root.getLong("createdAt"),
            sets = sets,
            exerciseCatalog = catalog,
            profile = profile,
            planSource = root.getString("planSource")
        ).takeIf { isValid(it) && now - it.createdAt in 0L..MAX_AGE_MS }
    }.getOrNull()

    private fun isValid(plan: PhoneWearCachedPlan): Boolean {
        return plan.planId.length in 1..64 && plan.planId.none(Char::isISOControl) &&
            plan.createdAt > 0L &&
            plan.planSource.length in 1..32 && plan.planSource.none(Char::isISOControl) &&
            plan.sets.size in 1..PhoneWearPaths.MAX_PLAN_SETS &&
            plan.sets.all { set ->
                isValidName(set.exerciseName) &&
                    set.weight.isFinite() && set.weight in 0.0..PhoneWearPaths.MAX_WEIGHT &&
                    set.reps in 1..PhoneWearPaths.MAX_REPS
            } &&
            plan.exerciseCatalog.size <= PhoneWearPaths.MAX_EXERCISE_CATALOG &&
            plan.exerciseCatalog.all { it.length <= PhoneWearPaths.MAX_EXERCISE_NAME_LENGTH } &&
            (plan.profile == null || plan.profile.let { profile ->
                profile.workoutsPerWeek in 1..14 &&
                    profile.split.length <= MAX_PROFILE_VALUE_LENGTH &&
                    profile.goal.length <= MAX_PROFILE_VALUE_LENGTH &&
                    profile.calorieMode.length <= MAX_PROFILE_VALUE_LENGTH
            })
    }

    private fun isValidName(value: String): Boolean {
        val trimmed = value.trim()
        return trimmed.isNotEmpty() &&
            trimmed.length <= PhoneWearPaths.MAX_EXERCISE_NAME_LENGTH &&
            trimmed.none(Char::isISOControl)
    }
}
