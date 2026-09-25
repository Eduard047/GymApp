package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseEntity
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceWorkoutDraftParserTest {
    private val contract by lazy { JSONObject(sharedContract().readText()) }

    @Test
    fun kotlinTablesEqualTheSharedVoiceContract() {
        val limits = contract.getJSONObject("limits")
        assertEquals(limits.getInt("maxTranscriptBytes"), VoiceWorkoutDraftParser.MAX_TRANSCRIPT_BYTES)
        assertEquals(limits.getInt("maxBlocks"), VoiceWorkoutDraftParser.MAX_BLOCKS)
        assertEquals(limits.getInt("maxSetsPerBlock"), VoiceWorkoutDraftParser.MAX_SETS_PER_BLOCK)
        assertEquals(limits.getDouble("maxWeight"), VoiceWorkoutDraftParser.MAX_WEIGHT, 0.0)
        assertEquals(limits.getInt("maxReps"), VoiceWorkoutDraftParser.MAX_REPS)
        assertEquals(contract.getJSONObject("privacy").getInt("autoStopSeconds"), VoiceWorkoutDraftParser.AUTO_STOP_SECONDS)
        assertEquals(contract.getJSONObject("locales").stringMap(), VoiceWorkoutDraftParser.LOCALES)
        val rules = contract.getJSONObject("rules")
        assertEquals(rules.getJSONArray("separatorPhrases").strings(), VoiceWorkoutDraftParser.SEPARATOR_PHRASES)
        assertEquals(rules.getJSONArray("setWords").strings(), VoiceWorkoutDraftParser.SET_WORDS)
        assertEquals(rules.getJSONArray("repWords").strings(), VoiceWorkoutDraftParser.REP_WORDS)
        assertEquals(rules.getJSONArray("weightWords").strings(), VoiceWorkoutDraftParser.WEIGHT_WORDS)
        assertEquals(rules.getJSONArray("weightPrefixWords").strings(), VoiceWorkoutDraftParser.WEIGHT_PREFIX_WORDS)
        assertEquals(rules.getJSONArray("connectorWords").strings(), VoiceWorkoutDraftParser.CONNECTOR_WORDS)
        assertEquals(rules.getInt("containsMatchMinimumLength"), VoiceWorkoutDraftParser.CONTAINS_MATCH_MINIMUM_LENGTH)
        val aliases = rules.getJSONObject("voiceAliases")
        assertEquals(aliases.keys().asSequence().toSet(), VoiceWorkoutDraftParser.VOICE_ALIASES.keys)
        aliases.keys().forEach { key -> assertEquals(aliases.getJSONArray(key).strings(), VoiceWorkoutDraftParser.VOICE_ALIASES[key]) }
        val numbers = rules.getJSONObject("numberWords")
        assertEquals(numbers.getJSONObject("units").intMap(), VoiceWorkoutDraftParser.NUMBER_UNITS)
        assertEquals(numbers.getJSONObject("teens").intMap(), VoiceWorkoutDraftParser.NUMBER_TEENS)
        assertEquals(numbers.getJSONObject("tens").intMap(), VoiceWorkoutDraftParser.NUMBER_TENS)
        assertEquals(numbers.getJSONObject("hundreds").intMap(), VoiceWorkoutDraftParser.NUMBER_HUNDREDS)
        assertEquals(numbers.getJSONArray("hundredMultipliers").strings(), VoiceWorkoutDraftParser.HUNDRED_MULTIPLIERS)
    }

    @Test
    fun sharedGoldenCasesThroughTheProductionExerciseAdapter() {
        val fixtures = contract.getJSONObject("fixtureExercises")
        val fixtureKeys = fixtures.keys().asSequence().toList()
        val defaultFixtures = contract.getJSONArray("defaultFixtures").strings()
        val cases = contract.getJSONArray("cases")
        assertTrue(cases.length() >= 30)
        for (index in 0 until cases.length()) {
            val testCase = cases.getJSONObject(index)
            val caseId = testCase.getString("id")
            val keys = if (testCase.has("fixtures")) testCase.getJSONArray("fixtures").strings() else defaultFixtures
            val entities = keys.map { key ->
                ExerciseEntity(id = (fixtureKeys.indexOf(key) + 1).toLong(), name = fixtures.getJSONObject(key).getString("name"))
            }
            val keyById = keys.associateBy { (fixtureKeys.indexOf(it) + 1).toString() }
            val transcript = if (testCase.has("transcriptRepeat")) {
                val repeat = testCase.getJSONObject("transcriptRepeat")
                repeat.getString("text").repeat(repeat.getInt("count"))
            } else {
                testCase.getString("transcript")
            }
            val result = VoiceWorkoutDraftParser.parse(transcript, voiceWorkoutExerciseInputs(entities))
            val expectedBlocks = testCase.getJSONArray("blocks")
            assertEquals(caseId, expectedBlocks.length(), result.blocks.size)
            for (blockIndex in 0 until expectedBlocks.length()) {
                val expected = expectedBlocks.getJSONObject(blockIndex)
                val block = result.blocks[blockIndex]
                val label = "$caseId block $blockIndex"
                assertEquals(label, if (expected.isNull("exercise")) null else expected.getString("exercise"), block.exerciseId?.let(keyById::get))
                assertEquals(label, expected.getString("match"), block.match.name.lowercase())
                if (expected.has("candidates")) {
                    assertEquals(label, expected.getJSONArray("candidates").strings().toSet(), block.candidates.mapNotNull { keyById[it.id] }.toSet())
                }
                assertEquals(label, expectedSets(expected.get("sets")), block.sets.map { listOf(it.weight, it.reps?.toDouble()) })
            }
            val blockIndexById = result.blocks.withIndex().associate { it.value.id to it.index }
            val diagnostics = result.diagnostics.map { diagnostic ->
                diagnostic.blockId?.let { "${diagnostic.kind.wireName}:${blockIndexById[it]}" } ?: diagnostic.kind.wireName
            }
            assertEquals(caseId, testCase.getJSONArray("diagnostics").strings(), diagnostics)
        }
    }

    @Test
    fun byteTruncationWeightInputAndLiveReadiness() {
        val truncated = VoiceWorkoutDraftParser.truncateUtf8("ж".repeat(5000))
        assertEquals(4096, truncated.length)
        assertEquals("80", VoiceWorkoutDraftParser.formatWeight(80.0))
        assertEquals("82.5", VoiceWorkoutDraftParser.formatWeight(82.5))
        assertEquals(82.5, VoiceWorkoutDraftParser.parseWeightInput("82,5")!!, 0.0)
        assertNull(VoiceWorkoutDraftParser.parseWeightInput(" "))
        assertTrue(VoiceWorkoutDraftParser.parseWeightInput("8a")!!.isNaN())
        val bench = ExerciseEntity(id = 1, name = "Bench Press")
        val tooMany = VoiceWorkoutDraftParser.parse("Bench press: 101 sets of 10 reps, 80 kilograms", voiceWorkoutExerciseInputs(listOf(bench)))
        assertEquals(100, tooMany.blocks.single().sets.size)
        assertTrue(tooMany.blocks.single().isValid)
        val unknown = VoiceWorkoutDraftParser.parse("Mystery lift 40 for 10", voiceWorkoutExerciseInputs(listOf(bench))).blocks.single()
        assertEquals(VoiceWorkoutBlockIssue.ChooseExercise, unknown.issue)
        assertNull(unknown.copy(exerciseId = "1").issue)
    }

    private fun expectedSets(value: Any): List<List<Double?>> {
        fun pair(raw: JSONArray): List<Double?> = List(raw.length()) { if (raw.isNull(it)) null else raw.getDouble(it) }
        if (value is JSONArray) return List(value.length()) { pair(value.getJSONArray(it)) }
        val repeated = value as JSONObject
        return List(repeated.getInt("repeat")) { pair(repeated.getJSONArray("set")) }
    }

    private fun JSONArray.strings(): List<String> = List(length()) { getString(it) }

    private fun JSONObject.stringMap(): Map<String, String> = keys().asSequence().associateWith { getString(it) }

    private fun JSONObject.intMap(): Map<String, Int> = keys().asSequence().associateWith { getInt(it) }

    private fun sharedContract(): File {
        val direct = File("shared/voice-workout-v1.json")
        if (direct.isFile) return direct
        return File("../shared/voice-workout-v1.json").also {
            check(it.isFile) { "Shared voice workout contract was not found." }
        }
    }
}
