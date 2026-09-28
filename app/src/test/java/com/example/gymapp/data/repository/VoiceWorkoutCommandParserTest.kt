package com.example.gymapp.data.repository

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceWorkoutCommandParserTest {
    private val contract by lazy { JSONObject(sharedContract().readText()) }

    @Test
    fun kotlinConstantsEqualTheSharedCommandContract() {
        val limits = contract.getJSONObject("limits")
        assertEquals(limits.getInt("maxTranscriptBytes"), VoiceWorkoutCommandParser.MAX_TRANSCRIPT_BYTES)
        assertEquals(limits.getDouble("minWeightKg"), VoiceWorkoutCommandParser.MIN_WEIGHT_KG, 0.0)
        assertEquals(limits.getDouble("maxWeightKg"), VoiceWorkoutCommandParser.MAX_WEIGHT_KG, 0.0)
        assertEquals(limits.getDouble("weightStepKg"), VoiceWorkoutCommandParser.WEIGHT_STEP_KG, 0.0)
        assertEquals(limits.getInt("minReps"), VoiceWorkoutCommandParser.MIN_REPS)
        assertEquals(limits.getInt("maxReps"), VoiceWorkoutCommandParser.MAX_REPS)

        assertEquals(contract.getJSONArray("fillerWords").strings(), VoiceWorkoutCommandParser.COMMAND_FILLER_WORDS)

        val intents = contract.getJSONObject("intents")
        assertEquals(
            intents.getJSONObject("logSet").getJSONArray("bodyweightPhrases").strings(),
            VoiceWorkoutCommandParser.COMMAND_BODYWEIGHT_PHRASES
        )
        assertEquals(
            intents.getJSONObject("repeatPrevious").getJSONArray("phrases").strings(),
            VoiceWorkoutCommandParser.COMMAND_REPEAT_PHRASES
        )
        assertEquals(
            intents.getJSONObject("skipRest").getJSONArray("phrases").strings(),
            VoiceWorkoutCommandParser.COMMAND_SKIP_PHRASES
        )
        assertEquals(
            intents.getJSONObject("unknown").getJSONArray("diagnosticCodes").strings(),
            VoiceWorkoutCommandParser.COMMAND_DIAGNOSTIC_CODES
        )
    }

    @Test
    fun sharedGoldenCasesAllPass() {
        val cases = contract.getJSONArray("cases")
        assertTrue(cases.length() >= 59)
        for (index in 0 until cases.length()) {
            val testCase = cases.getJSONObject(index)
            val caseId = testCase.getString("id")
            val transcript = if (testCase.has("transcriptRepeat")) {
                val repeat = testCase.getJSONObject("transcriptRepeat")
                repeat.getString("text").repeat(repeat.getInt("count"))
            } else {
                testCase.getString("transcript")
            }
            val expected = testCase.getJSONObject("expected")
            val result = VoiceWorkoutCommandParser.parse(transcript, testCase.optString("language", "ru"))
            when (val expectedIntent = expected.getString("intent")) {
                "logSet" -> {
                    val logSet = result as? VoiceWorkoutCommand.LogSet
                    assertTrue("$caseId: expected LogSet but got $result", logSet != null)
                    val expectedWeight = if (expected.has("weightKg")) expected.getDouble("weightKg") else null
                    val expectedReps = if (expected.has("reps")) expected.getInt("reps") else null
                    assertEquals(caseId, expectedWeight, logSet!!.weightKg)
                    assertEquals(caseId, expectedReps, logSet.reps)
                }
                "repeatPrevious" -> assertEquals(caseId, VoiceWorkoutCommand.RepeatPrevious, result)
                "skipRest" -> assertEquals(caseId, VoiceWorkoutCommand.SkipRest, result)
                "unknown" -> {
                    val unknown = result as? VoiceWorkoutCommand.Unknown
                    assertTrue("$caseId: expected Unknown but got $result", unknown != null)
                    val expectedCode = if (expected.has("code")) expected.getString("code") else null
                    assertEquals(caseId, expectedCode, unknown!!.code)
                }
                else -> throw AssertionError("$caseId: unrecognized expected intent $expectedIntent")
            }
        }
    }

    @Test
    fun hostileInputNeverThrows() {
        val hostileInputs = listOf(
            null,
            "",
            "   \n\t  ",
            "x".repeat(50_000),
            "ж".repeat(20_000),
            "\u0000\u0001\u0002 80 на 8",
            "😀🔥💪 80 x 8 🏋️‍♂️",
            "'''''''''''''''''''''",
            "-".repeat(500),
            "80".repeat(2000) + " на 8",
            "NaN Infinity -Infinity 80 на 8",
            "80,,,,,5 на 8",
            "80.5.5.5 на восемь",
            "\uD83D\uD83D 80 x 8",
            "‮80 x 8‬",
            "а".repeat(9000),
            "80 на 8; повтори; дальше; как дела",
            "0".repeat(10) + " x " + "9".repeat(10),
            List(200) { "восемьдесят" }.joinToString(" "),
            "باره فارسی ۸۰ در ۸"
        )
        for (input in hostileInputs) {
            val result = try {
                VoiceWorkoutCommandParser.parse(input, "ru")
            } catch (error: Throwable) {
                throw AssertionError("parse threw for input=$input", error)
            }
            assertTrue(
                "unexpected result type for input=$input",
                result is VoiceWorkoutCommand.LogSet ||
                    result is VoiceWorkoutCommand.RepeatPrevious ||
                    result is VoiceWorkoutCommand.SkipRest ||
                    result is VoiceWorkoutCommand.Unknown
            )
        }
        val nullResult = VoiceWorkoutCommandParser.parse(null, "ru")
        assertEquals(VoiceWorkoutCommand.Unknown("", "empty"), nullResult)
    }

    private fun JSONArray.strings(): List<String> = List(length()) { getString(it) }

    private fun sharedContract(): File {
        val direct = File("shared/voice-workout-command-v1.json")
        if (direct.isFile) return direct
        return File("../shared/voice-workout-command-v1.json").also {
            check(it.isFile) { "Shared voice workout command contract was not found." }
        }
    }
}
