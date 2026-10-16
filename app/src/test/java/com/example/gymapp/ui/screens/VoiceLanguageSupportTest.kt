package com.example.gymapp.ui.screens

import android.os.Build
import android.speech.SpeechRecognizer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceLanguageSupportTest {
    @Test
    fun matchTagPrefersExactThenFallsBackToSameLanguage() {
        assertEquals("ru-RU", VoiceLanguageSupport.matchTag("ru-RU", listOf("en-US", "ru-RU")))
        assertEquals("ru-UA", VoiceLanguageSupport.matchTag("ru-RU", listOf("en-US", "ru-UA")))
        assertEquals("ru", VoiceLanguageSupport.matchTag("ru-RU", listOf("ru")))
        assertEquals("ru-RU", VoiceLanguageSupport.matchTag("ru", listOf("ru-RU")))
        assertEquals("ru-RU", VoiceLanguageSupport.matchTag("ru-RU", listOf("ru-UA", "ru-RU")))
        assertEquals("uk_UA", VoiceLanguageSupport.matchTag("uk-UA", listOf("uk_UA")))
        assertEquals("EN-us", VoiceLanguageSupport.matchTag("en-US", listOf("EN-us")))
    }

    @Test
    fun matchTagRejectsOtherLanguagesAndBlankInput() {
        assertNull(VoiceLanguageSupport.matchTag("ru-RU", listOf("uk-UA", "en-US")))
        assertNull(VoiceLanguageSupport.matchTag("ru-RU", emptyList()))
        assertNull(VoiceLanguageSupport.matchTag("", listOf("ru-RU")))
        assertNull(VoiceLanguageSupport.matchTag("ru-RU", listOf("rus-RU")))
    }

    @Test
    fun installedLanguageStartsWithTheReportedTag() {
        val decision = VoiceLanguageSupport.decide("ru-RU", listOf("ru-UA"), listOf("ru-RU"), emptyList())
        assertEquals(VoiceLanguageDecision.Start("ru-UA"), decision)
    }

    @Test
    fun supportedButNotInstalledLanguageTriggersDownload() {
        val decision = VoiceLanguageSupport.decide("ru-RU", listOf("en-US"), listOf("ru-RU", "uk-UA"), emptyList())
        assertEquals(VoiceLanguageDecision.Download("ru-RU"), decision)
    }

    @Test
    fun pendingLanguageTriggersDownloadWithPrefixMatch() {
        val decision = VoiceLanguageSupport.decide("uk-UA", listOf("en-US"), emptyList(), listOf("uk"))
        assertEquals(VoiceLanguageDecision.Download("uk"), decision)
    }

    @Test
    fun languageMissingFromEveryListIsUnsupported() {
        val decision = VoiceLanguageSupport.decide("ru-RU", listOf("en-US"), listOf("uk-UA"), listOf("de-DE"))
        assertEquals(VoiceLanguageDecision.Unsupported, decision)
    }

    @Test
    fun emptyReportKeepsThePlainStartPath() {
        val decision = VoiceLanguageSupport.decide("ru-RU", emptyList(), emptyList(), emptyList())
        assertEquals(VoiceLanguageDecision.Unchecked, decision)
    }

    @Test
    fun installedWinsOverSupportedAndPending() {
        val decision = VoiceLanguageSupport.decide("en-US", listOf("en-US"), listOf("en-US"), listOf("en-US"))
        assertEquals(VoiceLanguageDecision.Start("en-US"), decision)
    }

    @Test
    fun apiGatingMatchesPlatformReleases() {
        assertFalse(VoiceLanguageSupport.supportsLanguageCheck(Build.VERSION_CODES.S))
        assertFalse(VoiceLanguageSupport.supportsLanguageCheck(Build.VERSION_CODES.S_V2))
        assertTrue(VoiceLanguageSupport.supportsLanguageCheck(Build.VERSION_CODES.TIRAMISU))
    }

    @Test
    fun errorTwelveIsAlwaysUnsupported() {
        for (sdk in listOf(Build.VERSION_CODES.S, Build.VERSION_CODES.TIRAMISU, 36)) {
            assertEquals(
                VoiceErrorAction.Unsupported,
                VoiceLanguageSupport.errorAction(SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED, sdk)
            )
        }
    }

    @Test
    fun errorThirteenDownloadsOnApi33AndUp() {
        assertEquals(
            VoiceErrorAction.Unsupported,
            VoiceLanguageSupport.errorAction(SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE, Build.VERSION_CODES.S)
        )
        assertEquals(
            VoiceErrorAction.Unsupported,
            VoiceLanguageSupport.errorAction(SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE, Build.VERSION_CODES.S_V2)
        )
        assertEquals(
            VoiceErrorAction.DownloadThenWait,
            VoiceLanguageSupport.errorAction(SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE, Build.VERSION_CODES.TIRAMISU)
        )
        assertEquals(
            VoiceErrorAction.DownloadThenWait,
            VoiceLanguageSupport.errorAction(SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE, 36)
        )
    }

    @Test
    fun otherErrorMappingsAreUnchanged() {
        val sdk = Build.VERSION_CODES.UPSIDE_DOWN_CAKE
        assertEquals(VoiceErrorAction.PermissionDenied, VoiceLanguageSupport.errorAction(SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS, sdk))
        assertEquals(VoiceErrorAction.AudioFailure, VoiceLanguageSupport.errorAction(SpeechRecognizer.ERROR_AUDIO, sdk))
        assertEquals(VoiceErrorAction.Ignore, VoiceLanguageSupport.errorAction(SpeechRecognizer.ERROR_CLIENT, sdk))
        assertEquals(VoiceErrorAction.RecognitionFailure, VoiceLanguageSupport.errorAction(SpeechRecognizer.ERROR_NETWORK, sdk))
        assertEquals(VoiceErrorAction.RecognitionFailure, VoiceLanguageSupport.errorAction(SpeechRecognizer.ERROR_NO_MATCH, sdk))
        assertEquals(VoiceErrorAction.RecognitionFailure, VoiceLanguageSupport.errorAction(SpeechRecognizer.ERROR_SERVER, sdk))
        assertEquals(VoiceErrorAction.RecognitionFailure, VoiceLanguageSupport.errorAction(SpeechRecognizer.ERROR_SPEECH_TIMEOUT, sdk))
    }

    @Test
    fun errorActionsMapToTranscriptionErrors() {
        assertEquals(VoiceTranscriptionError.UnsupportedLanguage, VoiceLanguageSupport.errorFor(VoiceErrorAction.Unsupported))
        assertEquals(VoiceTranscriptionError.LanguageDownloading, VoiceLanguageSupport.errorFor(VoiceErrorAction.DownloadThenWait))
        assertEquals(VoiceTranscriptionError.PermissionDenied, VoiceLanguageSupport.errorFor(VoiceErrorAction.PermissionDenied))
        assertEquals(VoiceTranscriptionError.AudioFailure, VoiceLanguageSupport.errorFor(VoiceErrorAction.AudioFailure))
        assertNull(VoiceLanguageSupport.errorFor(VoiceErrorAction.Ignore))
        assertEquals(VoiceTranscriptionError.RecognitionFailure, VoiceLanguageSupport.errorFor(VoiceErrorAction.RecognitionFailure))
    }

    @Test
    fun diagnosticLineCarriesOnlyCodeDeviceAndLanguageTags() {
        val line = VoiceLanguageSupport.diagnosticLine(
            event = "recognizer error",
            errorCode = 13,
            sdkInt = 34,
            manufacturer = "Samsung",
            model = "SM-S911B",
            requestedTag = "ru-RU",
            installed = listOf("en-US"),
            supported = listOf("ru-RU", "uk-UA"),
            pending = emptyList()
        )
        assertEquals(
            "recognizer error code=13 sdk=34 device=Samsung/SM-S911B lang=ru-RU " +
                "installed=[en-US] supported=[ru-RU,uk-UA] pending=[]",
            line
        )
    }

    @Test
    fun diagnosticLineMarksMissingListsAndStripsUnsafeCharacters() {
        val line = VoiceLanguageSupport.diagnosticLine(
            event = "language check error",
            errorCode = null,
            sdkInt = 33,
            manufacturer = "Acme\nCorp",
            model = "X<1>",
            requestedTag = "ru-RU",
            installed = null,
            supported = listOf("ru\nRU"),
            pending = null
        )
        assertFalse(line.contains('\n'))
        assertFalse(line.contains("code="))
        assertTrue(line.contains("device=AcmeCorp/X1"))
        assertTrue(line.contains("installed=n/a"))
        assertTrue(line.contains("supported=[ruRU]"))
        assertTrue(line.contains("pending=n/a"))
    }

    @Test
    fun diagnosticLineBoundsTheLanguageLists() {
        val many = (1..200).map { "l$it-XX" }
        val line = VoiceLanguageSupport.diagnosticLine("e", 1, 34, "m", "d", "en-US", many, null, null)
        assertTrue(line.contains("l40-XX"))
        assertFalse(line.contains("l41-XX"))
    }
}
