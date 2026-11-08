package com.example.gymapp.ui.screens

/** One set of the active workout, by position: [exerciseIndex], [setIndex] and whether it is recorded. */
internal data class NextSetFocusSet(val exerciseIndex: Int, val setIndex: Int, val completed: Boolean)

internal data class NextSetPosition(val exerciseIndex: Int, val setIndex: Int)

/**
 * Where the active workout moves its current-set focus after the user records one set. Runs the same
 * cases as iOS from shared/next-set-focus-v1.json.
 */
internal object NextSetFocus {
    /**
     * The first incomplete set after [recorded] in workout order (rest of its exercise, then the following
     * exercises); when none is left, the first incomplete set before it; null when every set is complete
     * (no focus change). Fully completed exercises hold no incomplete set, so they are skipped on their own.
     */
    fun next(sets: List<NextSetFocusSet>, recorded: NextSetPosition): NextSetPosition? {
        val ordered = sets.sortedWith(compareBy({ it.exerciseIndex }, { it.setIndex }))
        fun isBefore(set: NextSetFocusSet): Boolean =
            set.exerciseIndex < recorded.exerciseIndex ||
                (set.exerciseIndex == recorded.exerciseIndex && set.setIndex < recorded.setIndex)
        fun isAfter(set: NextSetFocusSet): Boolean =
            set.exerciseIndex > recorded.exerciseIndex ||
                (set.exerciseIndex == recorded.exerciseIndex && set.setIndex > recorded.setIndex)
        val target = ordered.firstOrNull { !it.completed && isAfter(it) }
            ?: ordered.firstOrNull { !it.completed && isBefore(it) }
            ?: return null
        return NextSetPosition(target.exerciseIndex, target.setIndex)
    }

    /**
     * Pixels to scroll the list by (positive = content moves up) so a row spanning [rowTop]..[rowBottom] is
     * fully inside [viewportTop]..[viewportBottom]; 0f when it already is. A row taller than the viewport
     * aligns its top edge.
     */
    fun scrollDelta(rowTop: Float, rowBottom: Float, viewportTop: Float, viewportBottom: Float): Float = when {
        rowTop >= viewportTop && rowBottom <= viewportBottom -> 0f
        rowBottom - rowTop > viewportBottom - viewportTop -> rowTop - viewportTop
        rowTop < viewportTop -> rowTop - viewportTop
        else -> rowBottom - viewportBottom
    }
}
