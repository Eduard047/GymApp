package com.example.gymapp.ui.screens

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.speech.SpeechRecognizer
import java.util.Locale

/** What the on-device recognizer should do for the requested dictation language. */
internal sealed interface VoiceLanguageDecision {
    /** The language pack is installed; listen with the tag the service reports. */
    data class Start(val tag: String) : VoiceLanguageDecision

    /** The pack is offered but not installed (or still pending); ask the service to fetch it. */
    data class Download(val tag: String) : VoiceLanguageDecision

    /** The service does not offer this language at all. */
    data object Unsupported : VoiceLanguageDecision

    /** The service reported nothing at all, so keep the plain start path and let it fail on its own. */
    data object Unchecked : VoiceLanguageDecision
}

/** How a recognizer error code is handled. */
internal enum class VoiceErrorAction {
    Unsupported,
    DownloadThenWait,
    PermissionDenied,
    AudioFailure,
    Ignore,
    RecognitionFailure
}

/** Pure decision helpers for on-device language packs; kept free of framework calls so they are unit-testable. */
internal object VoiceLanguageSupport {
    private const val MAX_LOGGED_TAGS = 40
    private const val MAX_TAG_LENGTH = 16

    /** Lower-cased BCP-47 form with `_` normalized to `-`. */
    fun normalizeTag(tag: String): String = tag.trim().replace('_', '-').lowercase(Locale.ROOT)

    private fun primaryLanguage(tag: String): String = normalizeTag(tag).substringBefore('-')

    /** Exact tag first, otherwise the first entry sharing the primary language (for example "ru" and "ru-UA"). */
    fun matchTag(requested: String, candidates: List<String>): String? {
        val wanted = normalizeTag(requested)
        if (wanted.isEmpty()) return null
        candidates.firstOrNull { normalizeTag(it) == wanted }?.let { return it }
        val language = primaryLanguage(requested)
        return candidates.firstOrNull { primaryLanguage(it) == language }
    }

    fun decide(
        requested: String,
        installed: List<String>,
        supported: List<String>,
        pending: List<String>
    ): VoiceLanguageDecision {
        if (installed.isEmpty() && supported.isEmpty() && pending.isEmpty()) return VoiceLanguageDecision.Unchecked
        matchTag(requested, installed)?.let { return VoiceLanguageDecision.Start(it) }
        matchTag(requested, supported)?.let { return VoiceLanguageDecision.Download(it) }
        matchTag(requested, pending)?.let { return VoiceLanguageDecision.Download(it) }
        return VoiceLanguageDecision.Unsupported
    }

    /** The language pack check only exists on API 33+; older versions go straight to listening. */
    fun supportsLanguageCheck(sdkInt: Int): Boolean = sdkInt >= Build.VERSION_CODES.TIRAMISU

    fun errorAction(errorCode: Int, sdkInt: Int): VoiceErrorAction = when (errorCode) {
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> VoiceErrorAction.Unsupported
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
            if (supportsLanguageCheck(sdkInt)) VoiceErrorAction.DownloadThenWait else VoiceErrorAction.Unsupported
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> VoiceErrorAction.PermissionDenied
        SpeechRecognizer.ERROR_AUDIO -> VoiceErrorAction.AudioFailure
        SpeechRecognizer.ERROR_CLIENT -> VoiceErrorAction.Ignore
        else -> VoiceErrorAction.RecognitionFailure
    }

    fun errorFor(action: VoiceErrorAction): VoiceTranscriptionError? = when (action) {
        VoiceErrorAction.Unsupported -> VoiceTranscriptionError.UnsupportedLanguage
        VoiceErrorAction.DownloadThenWait -> VoiceTranscriptionError.LanguageDownloading
        VoiceErrorAction.PermissionDenied -> VoiceTranscriptionError.PermissionDenied
        VoiceErrorAction.AudioFailure -> VoiceTranscriptionError.AudioFailure
        VoiceErrorAction.Ignore -> null
        VoiceErrorAction.RecognitionFailure -> VoiceTranscriptionError.RecognitionFailure
    }

    private fun safeTags(tags: List<String>?): String =
        tags?.take(MAX_LOGGED_TAGS)
            ?.joinToString(",", prefix = "[", postfix = "]") { tag ->
                tag.take(MAX_TAG_LENGTH).filter { it.isLetterOrDigit() || it == '-' || it == '_' }
            }
            ?: "n/a"

    /**
     * One diagnostic line: error code, device model, OS level, the language tag asked for, and the
     * language lists the service reported. Never audio, transcript or any user identifier.
     */
    fun diagnosticLine(
        event: String,
        errorCode: Int?,
        sdkInt: Int,
        manufacturer: String,
        model: String,
        requestedTag: String,
        installed: List<String>?,
        supported: List<String>?,
        pending: List<String>?
    ): String = buildString {
        append(event)
        if (errorCode != null) append(" code=").append(errorCode)
        append(" sdk=").append(sdkInt)
        append(" device=").append(safeText(manufacturer)).append('/').append(safeText(model))
        append(" lang=").append(safeText(requestedTag))
        append(" installed=").append(safeTags(installed))
        append(" supported=").append(safeTags(supported))
        append(" pending=").append(safeTags(pending))
    }

    private fun safeText(value: String): String =
        value.take(40).filter { it.isLetterOrDigit() || it == '-' || it == '_' || it == ' ' || it == '.' }
}

/** Opens the system voice input settings, falling back to the general settings; false when neither opens. */
internal fun openVoiceInputSettings(context: Context): Boolean {
    val candidates = listOf(Settings.ACTION_VOICE_INPUT_SETTINGS, Settings.ACTION_SETTINGS)
    for (action in candidates) {
        try {
            context.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return true
        } catch (_: ActivityNotFoundException) {
            continue
        } catch (_: SecurityException) {
            continue
        }
    }
    return false
}

/** Language name for the pack the app is waiting on, shown in the app's own language. */
internal fun voiceLanguageDisplayName(languageTag: String): String {
    val locale = Locale.forLanguageTag(languageTag)
    return locale.getDisplayLanguage(locale).ifBlank { languageTag }
}
