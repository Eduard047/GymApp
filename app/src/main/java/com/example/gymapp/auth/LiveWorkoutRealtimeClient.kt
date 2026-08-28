package com.example.gymapp.auth

import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.realtime.broadcastFlow
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.realtime
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonObject

internal sealed interface LiveRealtimeEvent {
    data class Connection(val connected: Boolean) : LiveRealtimeEvent
    data object ChannelReady : LiveRealtimeEvent
    data class Signal(val value: LiveWorkoutRealtimeSignal) : LiveRealtimeEvent
}

internal class SocialRealtimeClient(
    private val authManager: CloudAuthManager,
    private val session: AccountSession.Cloud
) {
    fun events(): Flow<SocialRealtimeSignal> = channelFlow {
        require(authManager.isLiveSessionActive(session)) { "Cloud session is no longer active." }
        val client = createSupabaseClient(SUPABASE_URL, SUPABASE_KEY) {
            accessToken = {
                if (authManager.isLiveSessionActive(session)) {
                    authManager.freshLiveAccessToken(session)
                } else {
                    null
                }
            }
            install(Realtime) {
                disconnectOnSessionLoss = true
                disconnectOnNoSubscriptions = true
            }
        }
        val channel = client.channel("gymapp:user:${session.userId}") { isPrivate = true }
        val broadcastJob = launch {
            channel.broadcastFlow<JsonObject>("gymapp_social_changed").collectLatest { payload ->
                runCatching { parseSocialRealtimeSignal(payload.toString()) }
                    .getOrNull()
                    ?.let { trySend(it) }
            }
        }
        try {
            withTimeout(10_000L) { channel.subscribe(blockUntilSubscribed = true) }
            awaitCancellation()
        } finally {
            broadcastJob.cancel()
            runCatching { client.realtime.removeChannel(channel) }
            runCatching { client.close() }
        }
    }
}

/**
 * Private personal Realtime channel. Broadcast payloads are invalidation hints only; callers must
 * refetch the authenticated inbox/snapshot before changing durable state.
 */
internal class LiveWorkoutRealtimeClient(
    private val authManager: CloudAuthManager,
    private val session: AccountSession.Cloud
) {
    fun events(): Flow<LiveRealtimeEvent> = channelFlow {
        require(authManager.isLiveSessionActive(session)) { "Cloud session is no longer active." }
        val client = createSupabaseClient(
            supabaseUrl = SUPABASE_URL,
            supabaseKey = SUPABASE_KEY
        ) {
            accessToken = {
                if (authManager.isLiveSessionActive(session)) {
                    authManager.freshLiveAccessToken(session)
                } else {
                    null
                }
            }
            install(Realtime) {
                disconnectOnSessionLoss = true
                disconnectOnNoSubscriptions = true
            }
        }
        val channel = client.channel("gymapp:user:${session.userId}") {
            isPrivate = true
        }
        val broadcastJob = launch {
            channel.broadcastFlow<JsonObject>("gymapp_live_changed").collectLatest { payload ->
                runCatching { parseLiveWorkoutRealtimeSignal(payload.toString()) }
                    .getOrNull()
                    ?.let { trySend(LiveRealtimeEvent.Signal(it)) }
            }
        }
        val connectionJob = launch {
            client.realtime.status.collectLatest { status ->
                trySend(LiveRealtimeEvent.Connection(status == Realtime.Status.CONNECTED))
            }
        }
        try {
            withTimeout(10_000L) { channel.subscribe(blockUntilSubscribed = true) }
            send(LiveRealtimeEvent.ChannelReady)
            awaitCancellation()
        } finally {
            broadcastJob.cancel()
            connectionJob.cancel()
            runCatching { client.realtime.removeChannel(channel) }
            runCatching { client.close() }
        }
    }
}
