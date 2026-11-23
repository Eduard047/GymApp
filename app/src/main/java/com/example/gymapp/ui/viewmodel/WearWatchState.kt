package com.example.gymapp.ui.viewmodel

/**
 * State of the Wear OS card on the Watches screen. The default (nothing looked up yet, or the
 * Google Play services Wearable API is missing) hides the card.
 */
data class WearWatchUiState(
    val apiAvailable: Boolean = false,
    val linked: Boolean = false,
    /** The Data Layer display name of the linked watch while it is connected; null otherwise. */
    val displayName: String? = null,
    val connected: Boolean = false
)

enum class WearWatchCardMode { HIDDEN, NOT_LINKED, LINKED }

fun wearWatchCardMode(state: WearWatchUiState?): WearWatchCardMode = when {
    state == null || !state.apiAvailable -> WearWatchCardMode.HIDDEN
    state.linked -> WearWatchCardMode.LINKED
    else -> WearWatchCardMode.NOT_LINKED
}

/**
 * Builds the card state from one Data Layer lookup: [pinnedNodeId] is the watch the phone has
 * linked (pinned) and [connectedNodes] maps each connected node id to its display name.
 */
fun wearWatchUiState(
    apiAvailable: Boolean,
    pinnedNodeId: String?,
    connectedNodes: Map<String, String?>
): WearWatchUiState {
    if (!apiAvailable) return WearWatchUiState()
    if (pinnedNodeId.isNullOrBlank()) return WearWatchUiState(apiAvailable = true)
    val connected = pinnedNodeId in connectedNodes
    return WearWatchUiState(
        apiAvailable = true,
        linked = true,
        displayName = if (connected) sanitizeWearWatchName(connectedNodes[pinnedNodeId]) else null,
        connected = connected
    )
}

/** The name shown for the linked watch: its Data Layer name, else [fallback] ("Wear OS watch"). */
fun wearWatchDisplayName(state: WearWatchUiState, fallback: String): String =
    sanitizeWearWatchName(state.displayName) ?: fallback

private const val MAX_WEAR_WATCH_NAME_LENGTH = 64

/** Node names come from another device: strip control characters, trim, and bound the length. */
internal fun sanitizeWearWatchName(raw: String?): String? = raw
    ?.filterNot(Char::isISOControl)
    ?.trim()
    ?.take(MAX_WEAR_WATCH_NAME_LENGTH)
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
