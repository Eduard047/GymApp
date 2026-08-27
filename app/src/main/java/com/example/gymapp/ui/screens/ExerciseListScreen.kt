package com.example.gymapp.ui.screens

import android.content.Intent
import android.content.Context
import android.content.ClipData
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.format.DateFormat as AndroidDateFormat
import androidx.compose.foundation.clickable
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.data.repository.ExerciseLoadDirection
import com.example.gymapp.data.repository.MUSCLE_DEFINITIONS
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.ExerciseMuscleBreakdownCard
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.LoadingStatePanel
import com.example.gymapp.ui.components.ScreenHeader
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.util.localizedMuscleName
import com.example.gymapp.ui.util.SensitiveClipboard
import com.example.gymapp.ui.viewmodel.ExerciseListUiState
import com.example.gymapp.ui.viewmodel.ExerciseMuscleOptionUiModel
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.asString
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.text.DateFormat
import java.text.Normalizer
import java.security.MessageDigest
import java.util.Date
import java.util.Locale
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

private const val BACKUP_PREVIEW_CHARS = 4_000
private const val MAX_PDF_PAGES = 24
private const val MAX_PDF_REPORT_LINES = 480
private const val MAX_PDF_EXERCISES = 120
private const val MAX_PDF_SESSIONS = 60
private const val MAX_PDF_EXERCISES_PER_SESSION = 24
private const val MAX_PDF_SETS_PER_EXERCISE = 20
private const val MAX_PDF_TEXT_CHARS = 320
internal const val EXERCISE_SEARCH_QUERY_MAX_CHARS = 256
internal const val EXERCISE_SEARCH_QUERY_MAX_TOKENS = 16
private const val EXERCISE_SEARCH_TERM_MAX_CHARS = 128
private const val EXERCISE_SEARCH_TERMS_PER_SOURCE_MAX = 96
private const val EXERCISE_SEARCH_TYPO_TOKEN_MIN_CHARS = 5
private const val EXERCISE_SEARCH_TYPO_TOKEN_MAX_CHARS = 48
private val EXERCISE_SEARCH_AMBIGUOUS_TOKENS = setOf("bb", "db")
private val EXERCISE_SEARCH_TRANSLITERATED_CONNECTOR_TOKENS by lazy(
    LazyThreadSafetyMode.PUBLICATION
) {
    BuiltInExerciseCatalog.searchConnectorTokens()
        .map(::transliterateExerciseSearchToken)
        .toSet()
}
private const val PRIVATE_SHARE_RETENTION_MILLIS = 24 * 60 * 60 * 1_000L
private const val MAX_RETAINED_PRIVATE_SHARE_FILES = 32
private const val MAX_PRIVATE_SHARE_DIRECTORY_ENTRIES = 128
private val PRIVATE_SHARE_FILE_LOCK = Any()
private val PRIVATE_SHARE_OWNER_DIRECTORY_PATTERN = Regex("^[a-f0-9]{64}$")

internal enum class ExerciseBodyFilter(val muscleIds: Set<String>) {
    All(emptySet()),
    Upper(setOf("chest", "shoulders", "biceps", "triceps", "forearms", "lats", "upperBack")),
    Lower(setOf("lowerBack", "glutes", "quads", "hamstrings", "adductors", "calves")),
    Core(setOf("abs", "obliques"))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AccountBackupSheets(
    uiState: ExerciseListUiState,
    backupShareOwnerKey: String,
    onClearBackup: () -> Unit,
    onCloseImport: () -> Unit,
    onImportJsonChange: (String) -> Unit,
    onImportBackup: () -> Unit
) {
    val backupJson = uiState.backupJson
    if (backupJson != null) {
        ModalBottomSheet(
            onDismissRequest = onClearBackup,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            BackupJsonBottomSheetContent(
                json = backupJson,
                diagnosticsOnly = uiState.backupIsDiagnostics,
                backupShareOwnerKey = backupShareOwnerKey,
                onDismiss = onClearBackup
            )
        }
    }

    if (uiState.isImportOpen) {
        ModalBottomSheet(
            onDismissRequest = onCloseImport,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            ImportBackupBottomSheetContent(
                importJson = uiState.importJson,
                importMessage = uiState.importMessage,
                onImportJsonChange = onImportJsonChange,
                onImportBackup = onImportBackup,
                onDismiss = onCloseImport
            )
        }
    }
}

internal enum class ExerciseSortMode {
    Name,
    MostFrequent,
    LeastFrequent
}

private data class ExerciseHistorySessionGroup(
    val sessionId: Long,
    val sessionDate: Long,
    val sets: List<ExerciseHistoryEntry>
)

internal enum class ExerciseSearchMatchReasonKind {
    Alias,
    Approximate,
    Muscle,
    Equipment,
    MuscleAndEquipment
}

internal data class ExerciseSearchMatchReason(
    val kind: ExerciseSearchMatchReasonKind,
    val value: String
)

internal data class ExerciseSearchMatch(
    val relevance: Int,
    val reason: ExerciseSearchMatchReason?
)

private enum class ExerciseSearchSource(val priority: Int) {
    Canonical(4),
    Alias(3),
    Muscle(2),
    Equipment(1)
}

private enum class ExerciseSearchTokenMatchMode(val points: Int) {
    Exact(50),
    Partial(40),
    Stem(35),
    Transliteration(30),
    Typo(20)
}

private data class ExerciseSearchPhrase(
    val tokens: List<String>,
    val compact: String = tokens.joinToString(separator = ""),
    val transliteratedTokens: List<String> = tokens.map(::transliterateExerciseSearchToken),
    val transliteratedCompact: String = transliteratedTokens.joinToString(separator = "")
)

private data class ExerciseSearchCandidate(
    val source: ExerciseSearchSource,
    val value: String,
    val phrase: ExerciseSearchPhrase
)

private data class ExerciseSearchCandidateConcept(
    val id: String,
    val candidates: List<ExerciseSearchCandidate>
)

private data class ExerciseSearchTokenEvidence(
    val candidate: ExerciseSearchCandidate,
    val mode: ExerciseSearchTokenMatchMode
)

internal fun exerciseSearchTokens(value: String): List<String> {
    val normalized = Normalizer.normalize(value, Normalizer.Form.NFC)
        .lowercase(Locale.ROOT)
        .replace('ё', 'е')
    val connectors = BuiltInExerciseCatalog.searchConnectorTokens()
    val tokens = mutableListOf<String>()
    val token = StringBuilder()

    fun finishToken() {
        if (token.isEmpty()) return
        val valueToken = token.toString()
        token.setLength(0)
        if (
            valueToken !in connectors &&
            transliterateExerciseSearchToken(valueToken) !in
            EXERCISE_SEARCH_TRANSLITERATED_CONNECTOR_TOKENS
        ) {
            tokens += valueToken
        }
    }

    var index = 0
    while (index < normalized.length) {
        val codePoint = Character.codePointAt(normalized, index)
        if (Character.isLetterOrDigit(codePoint)) {
            token.appendCodePoint(codePoint)
        } else {
            finishToken()
        }
        index += Character.charCount(codePoint)
    }
    finishToken()
    return tokens
}

private fun exerciseSearchPhrase(value: String, maxChars: Int): ExerciseSearchPhrase? {
    if (value.isBlank() || value.length > maxChars) return null
    val tokens = exerciseSearchTokens(value)
    if (
        tokens.isEmpty() ||
        tokens.size > EXERCISE_SEARCH_QUERY_MAX_TOKENS
    ) {
        return null
    }
    return ExerciseSearchPhrase(tokens)
}

private fun transliterateExerciseSearchToken(value: String): String {
    return buildString(value.length) {
        value.forEach { character ->
            append(
                when (character) {
                    'а' -> "a"
                    'б' -> "b"
                    'в' -> "v"
                    'г', 'ґ' -> "g"
                    'д' -> "d"
                    'е', 'ё', 'э' -> "e"
                    'є' -> "ye"
                    'ж' -> "zh"
                    'з' -> "z"
                    'и', 'і' -> "i"
                    'ї' -> "yi"
                    'й' -> "y"
                    'к' -> "k"
                    'л' -> "l"
                    'м' -> "m"
                    'н' -> "n"
                    'о' -> "o"
                    'п' -> "p"
                    'р' -> "r"
                    'с' -> "s"
                    'т' -> "t"
                    'у' -> "u"
                    'ф' -> "f"
                    'х' -> "h"
                    'ц' -> "ts"
                    'ч' -> "ch"
                    'ш' -> "sh"
                    'щ' -> "shch"
                    'ы' -> "y"
                    'ю' -> "yu"
                    'я' -> "ya"
                    'ь', 'ъ' -> ""
                    else -> character.toString()
                }
            )
        }
    }
}

private fun commonSearchPrefixLength(first: String, second: String): Int {
    val sharedLength = minOf(first.length, second.length)
    var index = 0
    while (index < sharedLength && first[index] == second[index]) {
        index += 1
    }
    return index
}

private fun hasUsefulExerciseSearchStem(first: String, second: String): Boolean {
    val prefixLength = commonSearchPrefixLength(first, second)
    return prefixLength >= 5 &&
        first.length - prefixLength <= 3 &&
        second.length - prefixLength <= 3
}

private fun isSafeDamerauDistanceAtMostOne(first: String, second: String): Boolean {
    if (
        minOf(first.length, second.length) < EXERCISE_SEARCH_TYPO_TOKEN_MIN_CHARS ||
        maxOf(first.length, second.length) > EXERCISE_SEARCH_TYPO_TOKEN_MAX_CHARS ||
        kotlin.math.abs(first.length - second.length) > 1
    ) {
        return false
    }
    if (first == second) return true
    if (first.length == second.length) {
        val mismatches = first.indices.filter { index -> first[index] != second[index] }
        return when (mismatches.size) {
            1 -> true
            2 -> {
                val firstMismatch = mismatches[0]
                val secondMismatch = mismatches[1]
                secondMismatch == firstMismatch + 1 &&
                    first[firstMismatch] == second[secondMismatch] &&
                    first[secondMismatch] == second[firstMismatch]
            }
            else -> false
        }
    }

    val shorter = if (first.length < second.length) first else second
    val longer = if (first.length < second.length) second else first
    var shorterIndex = 0
    var longerIndex = 0
    var skipped = false
    while (shorterIndex < shorter.length && longerIndex < longer.length) {
        if (shorter[shorterIndex] == longer[longerIndex]) {
            shorterIndex += 1
            longerIndex += 1
        } else {
            if (skipped) return false
            skipped = true
            longerIndex += 1
        }
    }
    return true
}

private fun exerciseSearchTokenMatchMode(
    candidateToken: String,
    queryToken: String
): ExerciseSearchTokenMatchMode? {
    if (candidateToken == queryToken) return ExerciseSearchTokenMatchMode.Exact
    if (
        minOf(candidateToken.length, queryToken.length) >= 3 &&
        (candidateToken.contains(queryToken) || queryToken.contains(candidateToken))
    ) {
        return ExerciseSearchTokenMatchMode.Partial
    }
    if (hasUsefulExerciseSearchStem(candidateToken, queryToken)) {
        return ExerciseSearchTokenMatchMode.Stem
    }

    val transliteratedCandidate = transliterateExerciseSearchToken(candidateToken)
    val transliteratedQuery = transliterateExerciseSearchToken(queryToken)
    val usedTransliteration =
        transliteratedCandidate != candidateToken || transliteratedQuery != queryToken
    if (usedTransliteration) {
        if (transliteratedCandidate == transliteratedQuery) {
            return ExerciseSearchTokenMatchMode.Transliteration
        }
        if (
            minOf(candidateToken.length, queryToken.length) >= 3 &&
            minOf(transliteratedCandidate.length, transliteratedQuery.length) >= 3 &&
            (
                transliteratedCandidate.contains(transliteratedQuery) ||
                    transliteratedQuery.contains(transliteratedCandidate)
                )
        ) {
            return ExerciseSearchTokenMatchMode.Transliteration
        }
        if (hasUsefulExerciseSearchStem(transliteratedCandidate, transliteratedQuery)) {
            return ExerciseSearchTokenMatchMode.Transliteration
        }
    }
    if (isSafeDamerauDistanceAtMostOne(candidateToken, queryToken)) {
        return ExerciseSearchTokenMatchMode.Typo
    }
    if (
        usedTransliteration &&
        isSafeDamerauDistanceAtMostOne(transliteratedCandidate, transliteratedQuery)
    ) {
        return ExerciseSearchTokenMatchMode.Typo
    }
    return null
}

private fun exerciseSearchCandidates(
    source: ExerciseSearchSource,
    values: Iterable<String>
): List<ExerciseSearchCandidate> {
    return values.asSequence()
        .filter { value -> value.isNotBlank() && value.length <= EXERCISE_SEARCH_TERM_MAX_CHARS }
        .mapNotNull { value ->
            exerciseSearchPhrase(value, EXERCISE_SEARCH_TERM_MAX_CHARS)?.let { phrase ->
                ExerciseSearchCandidate(source = source, value = value, phrase = phrase)
            }
        }
        .distinctBy { candidate -> candidate.phrase.tokens.joinToString(separator = "\u0000") }
        .take(EXERCISE_SEARCH_TERMS_PER_SOURCE_MAX)
        .toList()
}

private fun bestExerciseSearchEvidence(
    queryToken: String,
    candidates: List<ExerciseSearchCandidate>,
    preferSemanticSource: Boolean = false
): ExerciseSearchTokenEvidence? {
    return candidates.asSequence()
        .flatMap { candidate ->
            candidate.phrase.tokens.asSequence().mapNotNull { candidateToken ->
                exerciseSearchTokenMatchMode(candidateToken, queryToken)?.let { mode ->
                    ExerciseSearchTokenEvidence(candidate = candidate, mode = mode)
                }
            }
        }
        .maxWithOrNull(
            compareBy<ExerciseSearchTokenEvidence> { evidence -> evidence.mode.points }
                .thenBy { evidence ->
                    val source = evidence.candidate.source
                    if (
                        preferSemanticSource &&
                        (source == ExerciseSearchSource.Muscle ||
                            source == ExerciseSearchSource.Equipment)
                    ) {
                        source.priority + 10
                    } else {
                        source.priority
                    }
                }
        )
}

private fun exactExerciseSearchMatch(
    query: ExerciseSearchPhrase,
    candidates: List<ExerciseSearchCandidate>,
    source: ExerciseSearchSource,
    relevance: Int
): ExerciseSearchMatch? {
    val candidate = candidates.firstOrNull { item ->
        item.source == source && item.phrase.tokens == query.tokens
    } ?: return null
    val reason = if (source == ExerciseSearchSource.Alias) {
        ExerciseSearchMatchReason(ExerciseSearchMatchReasonKind.Alias, candidate.value)
    } else {
        null
    }
    return ExerciseSearchMatch(relevance = relevance, reason = reason)
}

private fun compactExerciseSearchMatch(
    query: ExerciseSearchPhrase,
    candidates: List<ExerciseSearchCandidate>
): ExerciseSearchMatch? {
    if (query.compact.length < 4) return null
    val candidateAndMode = candidates.asSequence()
        .mapNotNull { candidate ->
            val mode = when {
                candidate.phrase.compact == query.compact ->
                    ExerciseSearchTokenMatchMode.Partial
                candidate.phrase.transliteratedCompact == query.transliteratedCompact &&
                    (
                        candidate.phrase.transliteratedCompact != candidate.phrase.compact ||
                            query.transliteratedCompact != query.compact
                        ) -> ExerciseSearchTokenMatchMode.Transliteration
                isSafeDamerauDistanceAtMostOne(candidate.phrase.compact, query.compact) ->
                    ExerciseSearchTokenMatchMode.Typo
                (
                    candidate.phrase.transliteratedCompact != candidate.phrase.compact ||
                        query.transliteratedCompact != query.compact
                    ) && isSafeDamerauDistanceAtMostOne(
                    candidate.phrase.transliteratedCompact,
                    query.transliteratedCompact
                ) -> ExerciseSearchTokenMatchMode.Typo
                else -> null
            }
            mode?.let { candidate to it }
        }
        .maxWithOrNull(
            compareBy<Pair<ExerciseSearchCandidate, ExerciseSearchTokenMatchMode>> {
                (_, mode) -> mode.points
            }.thenBy { (candidate, _) -> candidate.source.priority }
        )
        ?: return null
    val (candidate, mode) = candidateAndMode
    val reasonKind = if (candidate.source == ExerciseSearchSource.Alias) {
        ExerciseSearchMatchReasonKind.Alias
    } else {
        ExerciseSearchMatchReasonKind.Approximate
    }
    return ExerciseSearchMatch(
        relevance = 20_800 + mode.points + candidate.source.priority,
        reason = ExerciseSearchMatchReason(reasonKind, candidate.value)
    )
}

private fun lexicalExerciseSearchMatch(
    query: ExerciseSearchPhrase,
    candidates: List<ExerciseSearchCandidate>
): ExerciseSearchMatch? {
    return candidates.asSequence().mapNotNull { candidate ->
        val evidence = query.tokens.map { queryToken ->
            bestExerciseSearchEvidence(queryToken, listOf(candidate)) ?: return@mapNotNull null
        }
        val approximate = evidence.any { item ->
            item.mode == ExerciseSearchTokenMatchMode.Transliteration ||
                item.mode == ExerciseSearchTokenMatchMode.Typo
        }
        val reason = when {
            candidate.source == ExerciseSearchSource.Alias -> ExerciseSearchMatchReason(
                ExerciseSearchMatchReasonKind.Alias,
                candidate.value
            )
            approximate -> ExerciseSearchMatchReason(
                ExerciseSearchMatchReasonKind.Approximate,
                candidate.value
            )
            else -> null
        }
        ExerciseSearchMatch(
            relevance = 20_000 + evidence.sumOf { item -> item.mode.points },
            reason = reason
        )
    }.maxByOrNull(ExerciseSearchMatch::relevance)
}

private fun candidateHasExactSearchToken(
    candidate: ExerciseSearchCandidate,
    queryToken: String
): Boolean {
    val transliteratedQuery = transliterateExerciseSearchToken(queryToken)
    return candidate.phrase.tokens.any { candidateToken ->
        candidateToken == queryToken ||
            (
                transliterateExerciseSearchToken(candidateToken) != candidateToken &&
                    transliterateExerciseSearchToken(candidateToken) == transliteratedQuery
                )
    }
}

private fun bridgedCanonicalAliasSearchMatch(
    query: ExerciseSearchPhrase,
    canonicalCandidates: List<ExerciseSearchCandidate>,
    aliasCandidates: List<ExerciseSearchCandidate>
): ExerciseSearchMatch? {
    return canonicalCandidates.asSequence().flatMap { canonicalCandidate ->
        aliasCandidates.asSequence().mapNotNull { aliasCandidate ->
            val canonicalEvidence = query.tokens.map { queryToken ->
                bestExerciseSearchEvidence(queryToken, listOf(canonicalCandidate))
            }
            val aliasEvidence = query.tokens.map { queryToken ->
                bestExerciseSearchEvidence(queryToken, listOf(aliasCandidate))
            }
            val canonicalOnlyExact = query.tokens.indices.any { index ->
                aliasEvidence[index] == null &&
                    candidateHasExactSearchToken(canonicalCandidate, query.tokens[index])
            }
            val aliasContributes = query.tokens.indices.any { index ->
                aliasEvidence[index] != null && canonicalEvidence[index] == null
            }
            if (!canonicalOnlyExact || !aliasContributes) return@mapNotNull null

            val combinedEvidence = query.tokens.indices.map { index ->
                listOfNotNull(canonicalEvidence[index], aliasEvidence[index])
                    .maxWithOrNull(
                        compareBy<ExerciseSearchTokenEvidence> { evidence ->
                            evidence.mode.points
                        }.thenBy { evidence -> evidence.candidate.source.priority }
                    )
                    ?: return@mapNotNull null
            }
            ExerciseSearchMatch(
                relevance = 20_000 + combinedEvidence.sumOf { evidence ->
                    evidence.mode.points
                },
                reason = ExerciseSearchMatchReason(
                    ExerciseSearchMatchReasonKind.Alias,
                    aliasCandidate.value
                )
            )
        }
    }.maxByOrNull(ExerciseSearchMatch::relevance)
}

private fun semanticExerciseSearchMatchForCandidates(
    query: ExerciseSearchPhrase,
    candidates: List<ExerciseSearchCandidate>
): ExerciseSearchMatch? {
    val evidence = query.tokens.map { queryToken ->
        bestExerciseSearchEvidence(
            queryToken,
            candidates,
            preferSemanticSource = true
        ) ?: return null
    }
    val muscleEvidence = evidence.filter { item ->
        item.candidate.source == ExerciseSearchSource.Muscle
    }
    val equipmentEvidence = evidence.filter { item ->
        item.candidate.source == ExerciseSearchSource.Equipment
    }
    if (muscleEvidence.isEmpty() && equipmentEvidence.isEmpty()) return null
    val reasonKind = when {
        muscleEvidence.isNotEmpty() && equipmentEvidence.isNotEmpty() ->
            ExerciseSearchMatchReasonKind.MuscleAndEquipment
        muscleEvidence.isNotEmpty() -> ExerciseSearchMatchReasonKind.Muscle
        else -> ExerciseSearchMatchReasonKind.Equipment
    }
    val reasonValue = (muscleEvidence + equipmentEvidence)
        .map { item -> item.candidate.value }
        .distinct()
        .joinToString(separator = " · ")
    return ExerciseSearchMatch(
        relevance = 10_000 +
            evidence.sumOf { item -> item.mode.points } +
            (if (muscleEvidence.isNotEmpty() && equipmentEvidence.isNotEmpty()) 20 else 10),
        reason = ExerciseSearchMatchReason(reasonKind, reasonValue)
    )
}

private fun semanticExerciseSearchMatch(
    query: ExerciseSearchPhrase,
    muscleConcepts: List<ExerciseSearchCandidateConcept>,
    equipmentConcepts: List<ExerciseSearchCandidateConcept>
): ExerciseSearchMatch? {
    val allowedSemanticCandidates = sequence {
        muscleConcepts.forEach { muscleConcept ->
            yield(muscleConcept.candidates)
        }
        equipmentConcepts.forEach { equipmentConcept ->
            yield(equipmentConcept.candidates)
        }
        muscleConcepts.forEach { muscleConcept ->
            equipmentConcepts.forEach { equipmentConcept ->
                yield(muscleConcept.candidates + equipmentConcept.candidates)
            }
        }
    }
    return allowedSemanticCandidates.mapNotNull { semanticCandidates ->
        semanticExerciseSearchMatchForCandidates(
            query = query,
            candidates = semanticCandidates
        )
    }.maxByOrNull(ExerciseSearchMatch::relevance)
}

internal fun exerciseSearchMatch(
    exerciseName: String,
    query: String
): ExerciseSearchMatch? {
    if (query.length > EXERCISE_SEARCH_QUERY_MAX_CHARS) return null
    val rawQuery = query.trim()
    if (rawQuery.isEmpty()) return ExerciseSearchMatch(relevance = 0, reason = null)
    val queryPhrase = exerciseSearchPhrase(
        rawQuery,
        EXERCISE_SEARCH_QUERY_MAX_CHARS
    ) ?: return null
    val definition = BuiltInExerciseCatalog.definitionForName(exerciseName)
    val canonicalValues = if (definition == null) {
        listOf(exerciseName)
    } else {
        listOf(
            definition.nameEn,
            definition.nameUk,
            BuiltInExerciseCatalog.displayName(definition.nameEn, "ru")
        )
    }
    val canonicalCandidates = exerciseSearchCandidates(
        ExerciseSearchSource.Canonical,
        canonicalValues
    )
    val legacyAliasCandidates = if (definition == null) {
        emptyList()
    } else {
        exerciseSearchCandidates(
            ExerciseSearchSource.Alias,
            definition.legacyAliases.filter { alias ->
                BuiltInExerciseCatalog.isIdentityNameSearchable(definition, alias)
            }
        )
    }
    val generatedAliasCandidates = if (definition == null) {
        emptyList()
    } else {
        exerciseSearchCandidates(
            ExerciseSearchSource.Alias,
            BuiltInExerciseCatalog.searchAliasesForDefinition(definition)
        )
    }
    val aliasCandidates = legacyAliasCandidates + generatedAliasCandidates
    val lexicalCandidates = canonicalCandidates + aliasCandidates

    exactExerciseSearchMatch(
        queryPhrase,
        canonicalCandidates,
        ExerciseSearchSource.Canonical,
        relevance = 40_000
    )?.let { return it }
    exactExerciseSearchMatch(
        queryPhrase,
        aliasCandidates,
        ExerciseSearchSource.Alias,
        relevance = 30_000
    )?.let { return it }
    if (
        queryPhrase.tokens.all { queryToken ->
            transliterateExerciseSearchToken(queryToken) in
                EXERCISE_SEARCH_AMBIGUOUS_TOKENS
        }
    ) {
        return null
    }
    compactExerciseSearchMatch(
        queryPhrase,
        canonicalCandidates + aliasCandidates
    )?.let { return it }
    lexicalExerciseSearchMatch(queryPhrase, lexicalCandidates)?.let { return it }
    bridgedCanonicalAliasSearchMatch(
        query = queryPhrase,
        canonicalCandidates = canonicalCandidates,
        aliasCandidates = generatedAliasCandidates
    )?.let { return it }

    if (definition == null) return null
    val muscleConcepts = BuiltInExerciseCatalog
        .searchMuscleTermConceptsForDefinition(definition)
        .mapNotNull { concept ->
            exerciseSearchCandidates(ExerciseSearchSource.Muscle, concept.terms)
                .takeIf { candidates -> candidates.isNotEmpty() }
                ?.let { candidates -> ExerciseSearchCandidateConcept(concept.id, candidates) }
        }
        .distinctBy(ExerciseSearchCandidateConcept::id)
    val equipmentConcepts = BuiltInExerciseCatalog
        .searchEquipmentTermConceptsForDefinition(definition)
        .mapNotNull { concept ->
            exerciseSearchCandidates(ExerciseSearchSource.Equipment, concept.terms)
                .takeIf { candidates -> candidates.isNotEmpty() }
                ?.let { candidates -> ExerciseSearchCandidateConcept(concept.id, candidates) }
        }
        .distinctBy(ExerciseSearchCandidateConcept::id)
    return semanticExerciseSearchMatch(
        query = queryPhrase,
        muscleConcepts = muscleConcepts,
        equipmentConcepts = equipmentConcepts
    )
}

internal fun exerciseNameMatchesLocalizedQuery(exerciseName: String, query: String): Boolean {
    return exerciseSearchMatch(exerciseName, query) != null
}

internal fun filterAndSortExercises(
    exercises: List<ExerciseEntity>,
    exerciseWorkoutCounts: Map<Long, Int>,
    muscleIdsByExerciseName: Map<String, Set<String>>,
    query: String,
    bodyFilter: ExerciseBodyFilter,
    muscleFilter: String?,
    sortMode: ExerciseSortMode,
    favoritesOnly: Boolean,
    languageTag: String
): List<ExerciseEntity> {
    data class RankedExercise(
        val exercise: ExerciseEntity,
        val searchMatch: ExerciseSearchMatch
    )

    val filtered = exercises.mapNotNull { exercise ->
        val muscleIds = muscleIdsByExerciseName[exercise.name].orEmpty()
        val matchesBody = bodyFilter == ExerciseBodyFilter.All ||
            muscleIds.any(bodyFilter.muscleIds::contains)
        val searchMatch = exerciseSearchMatch(exercise.name, query)
        if (
            searchMatch != null &&
            matchesBody &&
            (muscleFilter == null || muscleFilter in muscleIds) &&
            (!favoritesOnly || exercise.isFavorite)
        ) {
            RankedExercise(exercise = exercise, searchMatch = searchMatch)
        } else {
            null
        }
    }
    val byName = compareBy<RankedExercise> {
        BuiltInExerciseCatalog.displayName(it.exercise.name, languageTag).lowercase(Locale.ROOT)
    }.thenBy { it.exercise.id }
    val existingSort = when (sortMode) {
        ExerciseSortMode.Name -> filtered.sortedWith(byName)
        ExerciseSortMode.MostFrequent -> filtered.sortedWith(
            compareByDescending<RankedExercise> {
                exerciseWorkoutCounts[it.exercise.id] ?: 0
            }
                .then(byName)
        )
        ExerciseSortMode.LeastFrequent -> filtered.sortedWith(
            compareBy<RankedExercise> { exerciseWorkoutCounts[it.exercise.id] ?: 0 }
                .then(byName)
        )
    }
    if (query.isBlank()) return existingSort.map(RankedExercise::exercise)

    val tieBreakComparator = when (sortMode) {
        ExerciseSortMode.Name -> byName
        ExerciseSortMode.MostFrequent ->
            compareByDescending<RankedExercise> { exerciseWorkoutCounts[it.exercise.id] ?: 0 }
                .then(byName)
        ExerciseSortMode.LeastFrequent ->
            compareBy<RankedExercise> { exerciseWorkoutCounts[it.exercise.id] ?: 0 }
                .then(byName)
    }
    return filtered.sortedWith(
        compareByDescending<RankedExercise> { ranked -> ranked.searchMatch.relevance }
            .then(tieBreakComparator)
    ).map(RankedExercise::exercise)
}

@Composable
internal fun localizedExerciseSearchMatchReason(
    reason: ExerciseSearchMatchReason
): String {
    return when (reason.kind) {
        ExerciseSearchMatchReasonKind.Alias -> stringResource(
            R.string.exercise_search_match_alias,
            reason.value
        )
        ExerciseSearchMatchReasonKind.Approximate -> stringResource(
            R.string.exercise_search_match_approximate,
            reason.value
        )
        ExerciseSearchMatchReasonKind.Muscle -> stringResource(
            R.string.exercise_search_match_muscle,
            reason.value
        )
        ExerciseSearchMatchReasonKind.Equipment -> stringResource(
            R.string.exercise_search_match_equipment,
            reason.value
        )
        ExerciseSearchMatchReasonKind.MuscleAndEquipment -> stringResource(
            R.string.exercise_search_match_muscle_and_equipment,
            reason.value
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExerciseListScreen(
    uiState: ExerciseListUiState,
    exerciseMediaOwnerKey: String,
    onNameChange: (String) -> Unit,
    onAddExercise: () -> Unit,
    onExerciseClick: (Long) -> Unit,
    onStartRenameExercise: (ExerciseEntity) -> Unit,
    onRenameExerciseNameChange: (String) -> Unit,
    onSaveRenameExercise: () -> Unit,
    onDismissRenameExercise: () -> Unit,
    onDeleteExercise: (ExerciseEntity) -> Unit,
    onConfirmDeleteExercise: () -> Unit,
    onDismissDeleteExercise: () -> Unit,
    onEditExerciseMapping: (String) -> Unit,
    onToggleExerciseMappingMuscle: (String) -> Unit,
    onSaveExerciseMapping: () -> Unit,
    onDismissExerciseMapping: () -> Unit,
    onEditExerciseLoadProfile: (ExerciseEntity) -> Unit,
    onExerciseLoadDirectionChange: (ExerciseLoadDirection) -> Unit,
    onExerciseLoadWeightsChange: (String) -> Unit,
    onApplyExerciseLoadPreset: (Double) -> Unit,
    onSaveExerciseLoadProfile: () -> Unit,
    onClearExerciseLoadProfile: () -> Unit,
    onDismissExerciseLoadProfile: () -> Unit,
    onDismissHistory: () -> Unit,
    onToggleFavorite: (ExerciseEntity) -> Unit,
    onRetryLoad: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    var isAddExerciseOpen by rememberSaveable { mutableStateOf(false) }
    var pendingAddedName by rememberSaveable { mutableStateOf<String?>(null) }
    var searchQuery by rememberSaveable { mutableStateOf("") }
    var bodyFilter by rememberSaveable { mutableStateOf(ExerciseBodyFilter.All) }
    var muscleFilter by rememberSaveable { mutableStateOf<String?>(null) }
    var sortMode by rememberSaveable { mutableStateOf(ExerciseSortMode.Name) }
    var favoritesOnly by rememberSaveable { mutableStateOf(false) }
    val languageTag = currentAppLanguageTag()
    val musclesByExercise = remember(uiState.muscleMappings) {
        uiState.muscleMappings.associate { mapping -> mapping.exerciseName to mapping.muscleIds.toSet() }
    }
    val filteredExercises = remember(
        uiState.exercises,
        uiState.exerciseWorkoutCounts,
        musclesByExercise,
        searchQuery,
        bodyFilter,
        muscleFilter,
        sortMode,
        favoritesOnly,
        languageTag
    ) {
        filterAndSortExercises(
            exercises = uiState.exercises,
            exerciseWorkoutCounts = uiState.exerciseWorkoutCounts,
            muscleIdsByExerciseName = musclesByExercise,
            query = searchQuery,
            bodyFilter = bodyFilter,
            muscleFilter = muscleFilter,
            sortMode = sortMode,
            favoritesOnly = favoritesOnly,
            languageTag = languageTag
        )
    }
    LaunchedEffect(uiState.newExerciseName, uiState.hasInputError, pendingAddedName) {
        if (
            pendingAddedName != null &&
            uiState.newExerciseName.isBlank() &&
            !uiState.hasInputError
        ) {
            isAddExerciseOpen = false
            pendingAddedName = null
        } else if (uiState.hasInputError) {
            pendingAddedName = null
        }
    }

    if (uiState.isLoading) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .padding(horizontal = screenHorizontalPadding),
            contentAlignment = Alignment.Center
        ) {
            LoadingStatePanel(label = stringResource(R.string.exercises_loading))
        }
        return
    }
    uiState.loadError?.let { error ->
        Box(
            modifier = modifier
                .fillMaxSize()
                .padding(horizontal = screenHorizontalPadding),
            contentAlignment = Alignment.Center
        ) {
            EmptyStatePanel(
                title = error.asString(),
                actionLabel = stringResource(R.string.action_retry),
                onAction = onRetryLoad
            )
        }
        return
    }

    LazyColumn(
        modifier = modifier
            .fillMaxSize(),
        contentPadding = PaddingValues(
            start = screenHorizontalPadding,
            top = GymSpacing.ScreenTop,
            end = screenHorizontalPadding,
            bottom = GymSpacing.ScreenBottom
        ),
        verticalArrangement = Arrangement.spacedBy(GymSpacing.Large)
    ) {
        item {
            ScreenHeader(
                title = stringResource(R.string.title_exercises)
            )
        }

        item {
            Button(
                onClick = { isAddExerciseOpen = true },
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 52.dp),
                shape = MaterialTheme.shapes.small
            ) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = null
                )
                Text(
                    text = stringResource(R.string.action_add_exercise),
                    modifier = Modifier.padding(start = 8.dp),
                    maxLines = 1
                )
            }
        }

        if (
            uiState.exerciseDeletionError != null &&
            uiState.pendingExerciseDeletion == null
        ) {
            item {
                AppPanel(
                    modifier = Modifier.fillMaxWidth(),
                    containerColor = MaterialTheme.colorScheme.errorContainer
                ) {
                    Text(
                        text = uiState.exerciseDeletionError.asString(),
                        modifier = Modifier.padding(14.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        }

        item {
            ExerciseSearchAndFilters(
                query = searchQuery,
                onQueryChange = { searchQuery = it.take(EXERCISE_SEARCH_QUERY_MAX_CHARS) },
                bodyFilter = bodyFilter,
                onBodyFilterChange = { bodyFilter = it },
                muscleFilter = muscleFilter,
                onMuscleFilterChange = { muscleFilter = it },
                sortMode = sortMode,
                onSortModeChange = { sortMode = it },
                favoritesOnly = favoritesOnly,
                onFavoritesOnlyChange = { favoritesOnly = it },
                resultCount = filteredExercises.size
            )
        }

        if (filteredExercises.isEmpty()) {
            item {
                EmptyStatePanel(
                    title = if (uiState.exercises.isEmpty()) {
                        stringResource(R.string.empty_exercises)
                    } else {
                        stringResource(R.string.exercise_search_no_results)
                    },
                    supporting = if (uiState.exercises.isEmpty()) {
                        stringResource(R.string.exercise_library_empty_supporting)
                    } else {
                        stringResource(R.string.exercise_search_no_results_supporting)
                    },
                    actionLabel = if (uiState.exercises.isEmpty()) {
                        stringResource(R.string.action_add_exercise)
                    } else {
                        null
                    },
                    onAction = { isAddExerciseOpen = true }
                )
            }
        } else {
            items(
                items = filteredExercises,
                key = { it.id }
            ) { exercise ->
                var menuExpanded by remember(exercise.id) { mutableStateOf(false) }
                val isBuiltIn = BuiltInExerciseCatalog.definitionForName(exercise.name) != null
                val displayExerciseName = localizedExerciseName(exercise.name)
                val searchMatchReason = exerciseSearchMatch(exercise.name, searchQuery)?.reason
                AppPanel(
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(13.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            ExerciseMediaPreview(
                                exerciseId = exercise.id,
                                exerciseName = exercise.name,
                                ownerKey = exerciseMediaOwnerKey,
                            width = 76.dp,
                            height = 64.dp
                            )
                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(2.dp)
                            ) {
                                Text(
                                    text = displayExerciseName,
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                                if (searchMatchReason != null) {
                                    Text(
                                        text = localizedExerciseSearchMatchReason(searchMatchReason),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                            IconButton(onClick = { onToggleFavorite(exercise) }) {
                                Icon(
                                    imageVector = if (exercise.isFavorite) {
                                        Icons.Default.Favorite
                                    } else {
                                        Icons.Default.FavoriteBorder
                                    },
                                    contentDescription = stringResource(
                                        if (exercise.isFavorite) {
                                            R.string.exercise_favorite_remove
                                        } else {
                                            R.string.exercise_favorite_add
                                        }
                                    ),
                                    tint = if (exercise.isFavorite) {
                                        MaterialTheme.colorScheme.primary
                                    } else {
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                    }
                                )
                            }
                            androidx.compose.foundation.layout.Box {
                            IconButton(onClick = { menuExpanded = true }) {
                                Icon(
                                    imageVector = Icons.Default.MoreVert,
                                    contentDescription = stringResource(R.string.cd_more_actions)
                                )
                            }
                            DropdownMenu(
                                expanded = menuExpanded,
                                onDismissRequest = { menuExpanded = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.exercise_card_history)) },
                                    onClick = {
                                        menuExpanded = false
                                        onExerciseClick(exercise.id)
                                    },
                                    leadingIcon = { Icon(Icons.Default.History, contentDescription = null) }
                                )
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.exercise_card_muscle_groups)) },
                                    onClick = {
                                        menuExpanded = false
                                        onEditExerciseMapping(exercise.name)
                                    },
                                    leadingIcon = { Icon(Icons.Default.FitnessCenter, contentDescription = null) }
                                )
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.exercise_load_profile_action)) },
                                    onClick = {
                                        menuExpanded = false
                                        onEditExerciseLoadProfile(exercise)
                                    },
                                    leadingIcon = { Icon(Icons.Default.FormatListNumbered, contentDescription = null) }
                                )
                                if (!isBuiltIn) {
                                    DropdownMenuItem(
                                        text = { Text(stringResource(R.string.cd_edit)) },
                                        onClick = {
                                            menuExpanded = false
                                            onStartRenameExercise(exercise)
                                        },
                                        leadingIcon = { Icon(Icons.Default.Edit, contentDescription = null) }
                                    )
                                }
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.action_delete)) },
                                    onClick = {
                                        menuExpanded = false
                                        onDeleteExercise(exercise)
                                    },
                                    leadingIcon = {
                                        Icon(
                                            Icons.Default.Delete,
                                            contentDescription = stringResource(
                                                R.string.cd_delete_exercise_named,
                                                displayExerciseName
                                            ),
                                            tint = MaterialTheme.colorScheme.error
                                        )
                                    }
                                )
                            }
                            }
                        }
                    }
                }
            }
        }
    }

    uiState.pendingExerciseDeletion?.let { snapshot ->
        ExerciseDeleteConfirmationDialog(
            snapshot = snapshot,
            isDeleting = uiState.isExerciseDeletionInProgress,
            error = uiState.exerciseDeletionError,
            onDismiss = onDismissDeleteExercise,
            onConfirm = onConfirmDeleteExercise
        )
    }

    if (isAddExerciseOpen) {
        ModalBottomSheet(
            onDismissRequest = {
                isAddExerciseOpen = false
                pendingAddedName = null
            },
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            AddExerciseBottomSheetContent(
                exerciseName = uiState.newExerciseName,
                hasInputError = uiState.hasInputError,
                onExerciseNameChange = onNameChange,
                onAdd = {
                    pendingAddedName = uiState.newExerciseName.trim().takeIf { it.isNotEmpty() }
                    onAddExercise()
                }
            )
        }
    }

    val editingExercise = uiState.editingExercise
    if (editingExercise != null) {
        ModalBottomSheet(
            onDismissRequest = onDismissRenameExercise,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            RenameExerciseBottomSheetContent(
                exerciseName = uiState.editingExerciseName,
                rawExerciseName = editingExercise.name,
                hasInputError = uiState.hasInputError,
                onExerciseNameChange = onRenameExerciseNameChange,
                onSave = onSaveRenameExercise,
                onDismiss = onDismissRenameExercise
            )
        }
    }

    val selectedExerciseId = uiState.selectedExerciseId
    val selectedExerciseName = uiState.selectedExerciseName
    if (selectedExerciseId != null && selectedExerciseName != null) {
        ModalBottomSheet(
            onDismissRequest = onDismissHistory,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            ExerciseHistoryBottomSheetContent(
                exerciseId = selectedExerciseId,
                exerciseName = selectedExerciseName,
                exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                history = uiState.selectedExerciseHistory,
                onEditExerciseMapping = {
                    onDismissHistory()
                    onEditExerciseMapping(selectedExerciseName)
                }
            )
        }
    }

    val mappingExerciseName = uiState.mappingEditorExerciseName
    if (mappingExerciseName != null) {
        ModalBottomSheet(
            onDismissRequest = onDismissExerciseMapping,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            ExerciseMappingBottomSheetContent(
                exerciseName = mappingExerciseName,
                muscles = uiState.mappingEditorMuscles,
                onToggleMuscle = onToggleExerciseMappingMuscle,
                onSave = onSaveExerciseMapping,
                onDismiss = onDismissExerciseMapping
            )
        }
    }

    val loadEditorExercise = uiState.loadEditorExercise
    if (loadEditorExercise != null) {
        ModalBottomSheet(
            onDismissRequest = onDismissExerciseLoadProfile,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            ExerciseLoadProfileBottomSheetContent(
                exerciseName = loadEditorExercise.name,
                direction = uiState.loadEditorDirection,
                weights = uiState.loadEditorWeights,
                hasError = uiState.loadEditorHasError,
                hasExistingProfile = uiState.loadProfiles.containsKey(loadEditorExercise.id),
                onDirectionChange = onExerciseLoadDirectionChange,
                onWeightsChange = onExerciseLoadWeightsChange,
                onApplyPreset = onApplyExerciseLoadPreset,
                onSave = onSaveExerciseLoadProfile,
                onClear = onClearExerciseLoadProfile,
                onDismiss = onDismissExerciseLoadProfile
            )
        }
    }

}

@Composable
private fun ExerciseLoadProfileBottomSheetContent(
    exerciseName: String,
    direction: ExerciseLoadDirection,
    weights: String,
    hasError: Boolean,
    hasExistingProfile: Boolean,
    onDirectionChange: (ExerciseLoadDirection) -> Unit,
    onWeightsChange: (String) -> Unit,
    onApplyPreset: (Double) -> Unit,
    onSave: () -> Unit,
    onClear: () -> Unit,
    onDismiss: () -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            SectionTitle(
                eyebrow = stringResource(R.string.exercise_load_profile_eyebrow),
                title = localizedExerciseName(exerciseName),
                supporting = stringResource(R.string.exercise_load_profile_supporting)
            )
        }
        item {
            Text(
                text = stringResource(R.string.exercise_load_direction_title),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
        }
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ExerciseLoadDirection.entries.forEach { option ->
                    FilterChip(
                        selected = direction == option,
                        onClick = { onDirectionChange(option) },
                        label = {
                            Text(
                                stringResource(
                                    if (option == ExerciseLoadDirection.HigherIsHarder) {
                                        R.string.exercise_load_higher_is_harder
                                    } else {
                                        R.string.exercise_load_lower_is_harder
                                    }
                                )
                            )
                        }
                    )
                }
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = { onApplyPreset(2.5) },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.exercise_load_preset_2_5))
                }
                OutlinedButton(
                    onClick = { onApplyPreset(5.0) },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.exercise_load_preset_5))
                }
            }
        }
        item {
            OutlinedTextField(
                value = weights,
                onValueChange = onWeightsChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.exercise_load_weights_label)) },
                supportingText = {
                    Text(stringResource(R.string.exercise_load_weights_hint))
                },
                isError = hasError,
                minLines = 5,
                maxLines = 10
            )
        }
        if (hasError) {
            item {
                Text(
                    text = stringResource(R.string.exercise_load_profile_error),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
        item {
            Button(
                onClick = onSave,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 52.dp)
            ) {
                Text(stringResource(R.string.exercise_load_profile_save))
            }
        }
        if (hasExistingProfile) {
            item {
                OutlinedButton(
                    onClick = onClear,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.exercise_load_profile_clear))
                }
            }
        }
        item {
            OutlinedButton(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    }
}

@Composable
private fun ExerciseMetricPill(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String
) {
    val accent = MaterialTheme.colorScheme.primary
    Surface(
        color = accent.copy(alpha = 0.10f),
        contentColor = accent,
        shape = CircleShape,
        border = BorderStroke(1.dp, accent.copy(alpha = 0.22f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 11.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Icon(imageVector = icon, contentDescription = null, modifier = Modifier.size(17.dp))
            Text(
                text = text,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1
            )
        }
    }
}

@Composable
internal fun ExerciseSearchAndFilters(
    query: String,
    onQueryChange: (String) -> Unit,
    bodyFilter: ExerciseBodyFilter,
    onBodyFilterChange: (ExerciseBodyFilter) -> Unit,
    muscleFilter: String?,
    onMuscleFilterChange: (String?) -> Unit,
    sortMode: ExerciseSortMode,
    onSortModeChange: (ExerciseSortMode) -> Unit,
    favoritesOnly: Boolean,
    onFavoritesOnlyChange: (Boolean) -> Unit,
    resultCount: Int
) {
    val languageTag = currentAppLanguageTag()
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            OutlinedTextField(
                value = query,
                onValueChange = onQueryChange,
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                leadingIcon = {
                    Icon(Icons.Default.Search, contentDescription = null)
                },
                trailingIcon = if (query.isNotEmpty()) {
                    {
                        IconButton(onClick = { onQueryChange("") }) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = stringResource(R.string.exercise_search_clear)
                            )
                        }
                    }
                } else {
                    null
                },
                label = { Text(stringResource(R.string.exercise_search_label)) },
                placeholder = { Text(stringResource(R.string.exercise_search_placeholder)) }
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FilterChip(
                    selected = favoritesOnly,
                    onClick = { onFavoritesOnlyChange(!favoritesOnly) },
                    leadingIcon = {
                        Icon(
                            imageVector = if (favoritesOnly) {
                                Icons.Default.Favorite
                            } else {
                                Icons.Default.FavoriteBorder
                            },
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                    },
                    label = { Text(stringResource(R.string.exercise_filter_favorites)) }
                )
                ExerciseBodyFilter.entries.forEach { filter ->
                    val label = when (filter) {
                        ExerciseBodyFilter.All -> R.string.exercise_filter_all
                        ExerciseBodyFilter.Upper -> R.string.exercise_filter_upper
                        ExerciseBodyFilter.Lower -> R.string.exercise_filter_lower
                        ExerciseBodyFilter.Core -> R.string.exercise_filter_core
                    }
                    FilterChip(
                        selected = bodyFilter == filter,
                        onClick = { onBodyFilterChange(filter) },
                        label = { Text(stringResource(label)) }
                    )
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ExerciseSortMode.entries.forEach { mode ->
                    val label = when (mode) {
                        ExerciseSortMode.Name -> R.string.exercise_sort_name
                        ExerciseSortMode.MostFrequent -> R.string.exercise_sort_most_frequent
                        ExerciseSortMode.LeastFrequent -> R.string.exercise_sort_least_frequent
                    }
                    FilterChip(
                        selected = sortMode == mode,
                        onClick = { onSortModeChange(mode) },
                        label = { Text(stringResource(label)) }
                    )
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FilterChip(
                    selected = muscleFilter == null,
                    onClick = { onMuscleFilterChange(null) },
                    label = { Text(stringResource(R.string.exercise_filter_all_muscles)) }
                )
                MUSCLE_DEFINITIONS.forEach { muscle ->
                    FilterChip(
                        selected = muscleFilter == muscle.id,
                        onClick = {
                            onMuscleFilterChange(if (muscleFilter == muscle.id) null else muscle.id)
                        },
                        label = { Text(localizedMuscleName(muscle.id, languageTag)) }
                    )
                }
            }

        }
    }
}

@Composable
private fun AddExerciseBottomSheetContent(
    exerciseName: String,
    hasInputError: Boolean,
    onExerciseNameChange: (String) -> Unit,
    onAdd: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        SectionTitle(
            eyebrow = stringResource(R.string.exercise_library_eyebrow),
            title = stringResource(R.string.action_add_exercise),
            supporting = stringResource(R.string.exercise_library_supporting)
        )
        OutlinedTextField(
            value = exerciseName,
            onValueChange = onExerciseNameChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text(stringResource(R.string.label_exercise_name)) },
            placeholder = { Text(stringResource(R.string.hint_exercise_name)) },
            singleLine = true
        )
        if (hasInputError) {
            Text(
                text = stringResource(R.string.message_exercise_error),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        Button(
            onClick = onAdd,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 52.dp),
            shape = MaterialTheme.shapes.small
        ) {
            Icon(
                imageVector = Icons.Default.Add,
                contentDescription = null
            )
            Text(
                text = stringResource(R.string.action_add_exercise),
                modifier = Modifier.padding(start = 8.dp)
            )
        }
    }
}

@Composable
private fun ExerciseMappingBottomSheetContent(
    exerciseName: String,
    muscles: List<ExerciseMuscleOptionUiModel>,
    onToggleMuscle: (String) -> Unit,
    onSave: () -> Unit,
    onDismiss: () -> Unit
) {
    val languageTag = currentAppLanguageTag()
    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text(
                text = stringResource(
                    R.string.exercise_mappings_editor_title,
                    localizedExerciseName(exerciseName)
                ),
                style = MaterialTheme.typography.headlineSmall
            )
        }
        items(
            items = muscles,
            key = { it.id }
        ) { muscle ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onToggleMuscle(muscle.id) }
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Checkbox(
                    checked = muscle.isSelected,
                    onCheckedChange = { onToggleMuscle(muscle.id) }
                )
                Text(
                    text = localizedMuscleName(muscle.id, languageTag),
                    style = MaterialTheme.typography.bodyLarge
                )
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = onDismiss,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.action_cancel))
                }
                Button(
                    onClick = onSave,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.action_save))
                }
            }
        }
    }
}

@Composable
internal fun AccountStatusCard(
    label: String,
    supporting: String,
    isCloudAccount: Boolean,
    canLogout: Boolean,
    logoutEnabled: Boolean,
    onLogout: () -> Unit,
    onOpenGarminApp: () -> Unit,
    onResetGarminPairing: () -> Unit
) {
    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = supporting,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                InfoPill(
                    text = stringResource(
                        if (isCloudAccount) {
                            R.string.account_mode_cloud
                        } else {
                            R.string.account_mode_local
                        }
                    )
                )
            }
            if (canLogout) {
                OutlinedButton(
                    onClick = onLogout,
                    enabled = logoutEnabled,
                    modifier = Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.small
                ) {
                    Text(stringResource(R.string.auth_switch_account))
                }
            }
            OutlinedButton(
                onClick = onOpenGarminApp,
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.small
            ) {
                Text(stringResource(R.string.garmin_open_app))
            }
            OutlinedButton(
                onClick = onResetGarminPairing,
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.small
            ) {
                Text(stringResource(R.string.garmin_reset_pairing_action))
            }
        }
    }
}

@Composable
private fun RenameExerciseBottomSheetContent(
    exerciseName: String,
    rawExerciseName: String,
    hasInputError: Boolean,
    onExerciseNameChange: (String) -> Unit,
    onSave: () -> Unit,
    onDismiss: () -> Unit
) {
    val displayedExerciseName = if (exerciseName == rawExerciseName) {
        localizedExerciseName(rawExerciseName)
    } else {
        exerciseName
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            text = stringResource(R.string.exercise_rename_title),
            style = MaterialTheme.typography.headlineSmall
        )
        OutlinedTextField(
            value = displayedExerciseName,
            onValueChange = onExerciseNameChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text(stringResource(R.string.label_exercise_name)) },
            singleLine = true
        )
        if (hasInputError) {
            Text(
                text = stringResource(R.string.message_exercise_error),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(
                onClick = onDismiss,
                modifier = Modifier.weight(1f)
            ) {
                Text(stringResource(R.string.action_cancel))
            }
            Button(
                onClick = onSave,
                modifier = Modifier.weight(1f)
            ) {
                Text(stringResource(R.string.action_save))
            }
        }
    }
}

@Composable
internal fun BackupToolsCard(
    message: LocalizedText?,
    onExportBackup: () -> Unit,
    onExportDiagnostics: () -> Unit,
    onOpenImport: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.backup_tools_eyebrow),
                title = stringResource(R.string.backup_tools_title),
                supporting = stringResource(R.string.backup_tools_supporting)
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = onExportBackup,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        text = stringResource(R.string.backup_export_json),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                OutlinedButton(
                    onClick = onOpenImport,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        text = stringResource(R.string.backup_import_json),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            OutlinedButton(
                onClick = onExportDiagnostics,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.backup_export_diagnostics))
            }
            if (message != null) {
                Text(
                    text = message.asString(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
internal fun BackupJsonBottomSheetContent(
    json: String,
    diagnosticsOnly: Boolean,
    backupShareOwnerKey: String,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showClipboardWarning by rememberSaveable { mutableStateOf(false) }
    var shareError by remember { mutableStateOf<LocalizedText?>(null) }
    val previewTruncatedMessage = stringResource(R.string.backup_preview_truncated)
    val preview = remember(json, previewTruncatedMessage) {
        if (json.length <= BACKUP_PREVIEW_CHARS) json else {
            json.take(BACKUP_PREVIEW_CHARS) +
                "\n… $previewTruncatedMessage"
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text(
                text = stringResource(
                    if (diagnosticsOnly) {
                        R.string.backup_diagnostics_ready
                    } else {
                        R.string.backup_export_ready
                    }
                ),
                style = MaterialTheme.typography.headlineSmall
            )
        }
        item {
            // A read-only text field remains selectable and would expose an unguarded Copy menu.
            // Plain Text outside SelectionContainer keeps the warned action as the only copy path.
            Text(
                text = preview,
                modifier = Modifier.fillMaxWidth(),
                style = MaterialTheme.typography.bodySmall,
                maxLines = 12,
                overflow = TextOverflow.Ellipsis
            )
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(
                    onClick = { showClipboardWarning = true },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.backup_copy_json))
                }
                OutlinedButton(
                    onClick = {
                        shareError = null
                        scope.launch {
                            runCatching {
                                val file = withContext(Dispatchers.IO) {
                                    createBackupJsonFile(context, backupShareOwnerKey, json)
                                }
                                sharePrivateBackupFile(
                                    context = context,
                                    file = file,
                                    mimeType = "application/json",
                                    chooserTitle = context.getString(R.string.backup_share_json)
                                )
                            }.onFailure { error ->
                                if (error is CancellationException) throw error
                                shareError = LocalizedText(R.string.backup_share_json_failed)
                            }
                        }
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.backup_share_json))
                }
            }
        }
        item {
            OutlinedButton(
                onClick = {
                    shareError = null
                    scope.launch {
                        runCatching {
                            val file = withContext(Dispatchers.IO) {
                                createBackupPdfFile(context, backupShareOwnerKey, json)
                            }
                            sharePrivateBackupFile(
                                context = context,
                                file = file,
                                mimeType = "application/pdf",
                                chooserTitle = context.getString(R.string.backup_share_pdf)
                            )
                        }.onFailure { error ->
                            if (error is CancellationException) throw error
                            shareError = LocalizedText(R.string.backup_share_pdf_failed)
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.backup_share_pdf))
            }
        }
        if (shareError != null) {
            item {
                Text(
                    text = checkNotNull(shareError).asString(),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
        item {
            OutlinedButton(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.action_close))
            }
        }
    }

    if (showClipboardWarning) {
        AlertDialog(
            onDismissRequest = { showClipboardWarning = false },
            title = { Text(stringResource(R.string.backup_copy_warning_title)) },
            text = { Text(stringResource(R.string.backup_copy_warning_message)) },
            confirmButton = {
                Button(
                    onClick = {
                        if (!SensitiveClipboard.copyBackup(context, json)) {
                            shareError = LocalizedText(R.string.backup_clipboard_too_large)
                        }
                        showClipboardWarning = false
                    }
                ) {
                    Text(stringResource(R.string.backup_copy_confirm))
                }
            },
            dismissButton = {
                OutlinedButton(onClick = { showClipboardWarning = false }) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }
}

@Composable
internal fun ImportBackupBottomSheetContent(
    importJson: String,
    importMessage: LocalizedText?,
    onImportJsonChange: (String) -> Unit,
    onImportBackup: () -> Unit,
    onDismiss: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            text = stringResource(R.string.backup_import_title),
            style = MaterialTheme.typography.headlineSmall
        )
        OutlinedTextField(
            value = importJson,
            onValueChange = onImportJsonChange,
            modifier = Modifier.fillMaxWidth(),
            minLines = 6,
            maxLines = 12,
            placeholder = { Text(stringResource(R.string.backup_import_placeholder)) }
        )
        if (importMessage != null) {
            Text(
                text = importMessage.asString(),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(
                onClick = onDismiss,
                modifier = Modifier.weight(1f)
            ) {
                Text(stringResource(R.string.action_cancel))
            }
            Button(
                onClick = onImportBackup,
                modifier = Modifier.weight(1f)
            ) {
                Text(stringResource(R.string.backup_import_action))
            }
        }
    }
}

private fun sharePrivateBackupFile(
    context: Context,
    file: File,
    mimeType: String,
    chooserTitle: String
) {
    val uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file
    )
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = mimeType
        putExtra(Intent.EXTRA_STREAM, uri)
        clipData = ClipData.newRawUri(file.name, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(
        Intent.createChooser(
            sendIntent,
            chooserTitle
        )
    )
}

private fun createBackupJsonFile(context: Context, ownerKey: String, json: String): File {
    val bytes = json.toByteArray(Charsets.UTF_8)
    check(bytes.size <= WorkoutDataLimits.MAX_BACKUP_BYTES) {
        "Backup exceeds the private share size limit."
    }
    val outputFile = createPrivateBackupShareFile(
        context,
        ownerKey,
        "gymapp-backup-",
        ".json"
    )
    try {
        outputFile.outputStream().buffered().use { output ->
            output.write(bytes)
        }
        return outputFile
    } catch (error: Throwable) {
        outputFile.delete()
        throw error
    }
}

private fun createBackupPdfFile(context: Context, ownerKey: String, json: String): File {
    // Parse and bound attacker-controlled backup content before allocating a native PDF.
    val reportLines = backupReportLines(context, json)
    val document = PdfDocument()
    return try {
        val pageWidth = 595
        val pageHeight = 842
        val left = 42f
        val top = 48f
        val bottom = 800f
        val lineHeight = 16f
        var pageNumber = 1
        var y = top
        var page = document.startPage(
            PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pageNumber).create()
        )

        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.rgb(20, 32, 44)
            textSize = 18f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val headingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.rgb(20, 32, 44)
            textSize = 12f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.rgb(45, 56, 70)
            textSize = 10f
        }

        var pageLimitReached = false

        fun newPage(): Boolean {
            if (pageNumber >= MAX_PDF_PAGES) {
                pageLimitReached = true
                return false
            }
            document.finishPage(page)
            pageNumber += 1
            page = document.startPage(
                PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pageNumber).create()
            )
            y = top
            return true
        }

        fun drawWrapped(text: String, paint: Paint = bodyPaint, maxChars: Int = 92) {
            if (pageLimitReached) return
            wrapPdfLine(text, maxChars).forEach { line ->
                if (y > bottom && !newPage()) {
                    return
                }
                page.canvas.drawText(line, left, y, paint)
                y += lineHeight
            }
        }

        reportLines.forEachIndexed { index, line ->
            when {
                index == 0 -> {
                    drawWrapped(line, titlePaint, maxChars = 58)
                    y += 8f
                }
                line.startsWith("## ") -> {
                    y += 6f
                    drawWrapped(line.removePrefix("## "), headingPaint, maxChars = 76)
                    y += 2f
                }
                else -> drawWrapped(line)
            }
        }

        document.finishPage(page)
        val outputFile = createPrivateBackupShareFile(
            context,
            ownerKey,
            "gymapp-report-",
            ".pdf"
        )
        try {
            outputFile.outputStream().use(document::writeTo)
            outputFile
        } catch (error: Throwable) {
            outputFile.delete()
            throw error
        }
    } finally {
        document.close()
    }
}

private fun createPrivateBackupShareFile(
    context: Context,
    ownerKey: String,
    prefix: String,
    suffix: String
): File = synchronized(PRIVATE_SHARE_FILE_LOCK) {
    require(prefix in setOf("gymapp-backup-", "gymapp-report-"))
    require(suffix in setOf(".json", ".pdf"))
    val nowMillis = System.currentTimeMillis()
    val shareRoot = File(context.cacheDir, "backup-share").apply {
        check(isDirectory || mkdirs()) { "Could not prepare the private share directory" }
    }
    val artifacts = checkNotNull(privateBackupShareArtifacts(shareRoot)) {
        "Could not inspect the private share directory"
    }

    // A chooser may retain the granted URI after returning to GymApp. Delete
    // only expired artifacts across owner directories; never invalidate a fresh
    // grant from another signed-in account to make room.
    artifacts.filter { file ->
        val age = nowMillis - file.lastModified()
        age >= PRIVATE_SHARE_RETENTION_MILLIS
    }.forEach(File::delete)
    val retainedCount = checkNotNull(privateBackupShareArtifacts(shareRoot)) {
        "Could not recheck the private share directory"
    }.size
    check(retainedCount < MAX_RETAINED_PRIVATE_SHARE_FILES) {
        "Too many recent private share files. Try again after older shares expire."
    }
    val ownerDirectory = privateBackupShareOwnerDirectory(shareRoot, ownerKey).apply {
        check(isDirectory || mkdirs()) { "Could not prepare the account share directory" }
    }
    File.createTempFile(prefix, suffix, ownerDirectory)
}

private fun isPrivateBackupShareArtifact(file: File): Boolean =
    file.isFile &&
        (file.name.startsWith("gymapp-backup-") || file.name.startsWith("gymapp-report-")) &&
        file.extension in setOf("pdf", "json")

internal fun privateBackupShareOwnerDirectory(shareRoot: File, ownerKey: String): File {
    val ownerBytes = ownerKey.toByteArray(Charsets.UTF_8)
    require(ownerBytes.isNotEmpty() && ownerBytes.size <= 512)
    require(ownerKey.none(Char::isISOControl))
    val ownerHash = MessageDigest.getInstance("SHA-256")
        .digest("GymAppPrivateBackupShareV1:".toByteArray(Charsets.UTF_8) + ownerBytes)
        .joinToString(separator = "") { byte -> "%02x".format(byte) }
    return File(shareRoot, ownerHash)
}

private fun privateBackupShareArtifacts(shareRoot: File): List<File>? {
    if (!shareRoot.isDirectory) return null
    val rootEntries = shareRoot.listFiles() ?: return null
    if (rootEntries.size > MAX_PRIVATE_SHARE_DIRECTORY_ENTRIES) return null
    val artifacts = mutableListOf<File>()
    rootEntries.forEach { entry ->
        when {
            isPrivateBackupShareArtifact(entry) -> artifacts += entry
            entry.isDirectory && PRIVATE_SHARE_OWNER_DIRECTORY_PATTERN.matches(entry.name) -> {
                val ownerEntries = entry.listFiles() ?: return null
                if (ownerEntries.size > MAX_PRIVATE_SHARE_DIRECTORY_ENTRIES) return null
                artifacts += ownerEntries.filter(::isPrivateBackupShareArtifact)
            }
        }
    }
    return artifacts
}

internal fun clearPrivateBackupShareArtifacts(shareRoot: File, ownerKey: String): Boolean =
    synchronized(PRIVATE_SHARE_FILE_LOCK) {
        if (!shareRoot.exists()) return@synchronized true
        if (!shareRoot.isDirectory) return@synchronized false
        val ownerDirectory = privateBackupShareOwnerDirectory(shareRoot, ownerKey)
        if (!ownerDirectory.exists()) return@synchronized true
        if (!ownerDirectory.isDirectory) return@synchronized false
        val artifacts = ownerDirectory.listFiles()
            ?.filter(::isPrivateBackupShareArtifact)
            ?: return@synchronized false
        var cleared = true
        artifacts.forEach { artifact ->
            if (!artifact.delete()) cleared = false
        }
        val ownedArtifactsRemain = ownerDirectory.listFiles()
            ?.any(::isPrivateBackupShareArtifact)
            ?: true
        if (ownerDirectory.listFiles()?.isEmpty() == true) ownerDirectory.delete()
        if (shareRoot.listFiles()?.isEmpty() == true) shareRoot.delete()
        cleared && !ownedArtifactsRemain
    }

private fun backupReportLines(context: Context, json: String): List<String> {
    val root = JSONObject(json)
    val diagnosticsOnly = root.optBoolean("diagnostics", false)
    val locale = context.resources.configuration.locales[0]
    val exportedAt = DateFormat.getDateTimeInstance(
        DateFormat.MEDIUM,
        DateFormat.SHORT,
        locale
    )
        .format(Date(root.optLong("exportedAt", System.currentTimeMillis())))
    val exercises = root.optJSONArray("exercises")
    val sessions = root.optJSONArray("sessions")
    val summary = root.optJSONObject("summary")
    val lines = mutableListOf<String>()

    lines += if (diagnosticsOnly) {
        context.getString(R.string.backup_report_diagnostics_title)
    } else {
        context.getString(R.string.backup_report_private_title)
    }
    lines += context.getString(R.string.backup_report_exported, exportedAt)
    lines += context.getString(
        R.string.backup_report_schema,
        root.optInt("schemaVersion", 1)
    )
    if (!diagnosticsOnly) {
        lines += context.getString(R.string.backup_report_private_notice)
    }
    lines += ""
    lines += "## ${context.getString(R.string.backup_report_summary_heading)}"
    lines += context.getString(
        R.string.backup_report_exercises_count,
        summary?.optInt("exerciseCount") ?: (exercises?.length() ?: 0)
    )
    lines += context.getString(
        R.string.backup_report_workouts_count,
        summary?.optInt("sessionCount") ?: (sessions?.length() ?: 0)
    )
    summary?.let {
        lines += context.getString(R.string.backup_report_sets_count, it.optInt("setCount"))
    }

    if (diagnosticsOnly) {
        lines += ""
        lines += context.getString(R.string.backup_report_diagnostics_notice)
        lines += context.getString(R.string.backup_report_diagnostics_exclusions)
        return lines.take(MAX_PDF_REPORT_LINES)
    }

    lines += ""
    lines += "## ${context.getString(R.string.backup_report_exercises_heading)}"
    if (exercises == null || exercises.length() == 0) {
        lines += context.getString(R.string.backup_report_no_exercises)
    } else {
        val exerciseLimit = exercises.length().coerceAtMost(MAX_PDF_EXERCISES)
        for (index in 0 until exerciseLimit) {
            val name = boundedPdfText(
                exercises.optJSONObject(index)?.optString("name").orEmpty()
            )
            if (name.isNotBlank()) {
                lines += "- $name"
            }
        }
        if (exercises.length() > exerciseLimit) {
            lines += context.getString(
                R.string.backup_report_more_exercises,
                exercises.length() - exerciseLimit
            )
        }
    }

    lines += ""
    lines += "## ${context.getString(R.string.backup_report_workouts_heading)}"
    if (sessions == null || sessions.length() == 0) {
        lines += context.getString(R.string.backup_report_no_workouts)
    } else {
        val sessionLimit = sessions.length().coerceAtMost(MAX_PDF_SESSIONS)
        for (sessionIndex in 0 until sessionLimit) {
            if (lines.size >= MAX_PDF_REPORT_LINES) break
            val session = sessions.optJSONObject(sessionIndex) ?: continue
            val sessionTimestamp = session.optLong("date", 0L)
            val date = DateTimeUtils.formatDate(sessionTimestamp, locale) + " · " +
                DateFormat.getTimeInstance(DateFormat.SHORT, locale)
                    .format(Date(sessionTimestamp))
            val note = boundedPdfText(session.optString("note")).takeIf { it.isNotBlank() }
            lines += "$date${note?.let { " - $it" }.orEmpty()}"
            val sessionExercises = session.optJSONArray("exercises")
            val sessionExerciseCount = sessionExercises?.length() ?: 0
            val sessionExerciseLimit = sessionExerciseCount.coerceAtMost(
                MAX_PDF_EXERCISES_PER_SESSION
            )
            for (exerciseIndex in 0 until sessionExerciseLimit) {
                if (lines.size >= MAX_PDF_REPORT_LINES) break
                val exercise = sessionExercises?.optJSONObject(exerciseIndex) ?: continue
                val sets = exercise.optJSONArray("sets")
                val setCount = sets?.length() ?: 0
                val setLimit = setCount.coerceAtMost(MAX_PDF_SETS_PER_EXERCISE)
                val setParts = buildList {
                    for (setIndex in 0 until setLimit) {
                        val set = sets?.optJSONObject(setIndex) ?: continue
                        val weight = set.optDouble("weight", 0.0)
                            .toString()
                            .trimEnd('0')
                            .trimEnd('.')
                        add(
                            context.getString(
                                R.string.backup_report_set_value,
                                weight,
                                set.optInt("reps", 0)
                            )
                        )
                    }
                }
                val moreSets = if (setCount > setLimit) {
                    ", … ${context.getString(
                        R.string.backup_report_more_sets,
                        setCount - setLimit
                    )}"
                } else {
                    ""
                }
                lines += "  - ${boundedPdfText(exercise.optString("name"))}: " +
                    setParts.joinToString(", ") + moreSets
            }
            if (sessionExerciseCount > sessionExerciseLimit) {
                lines += "  … ${context.getString(
                    R.string.backup_report_more_exercises,
                    sessionExerciseCount - sessionExerciseLimit
                )}"
            }
            lines += ""
        }
        if (sessions.length() > sessionLimit) {
            lines += context.getString(
                R.string.backup_report_more_workouts,
                sessions.length() - sessionLimit
            )
        }
    }

    if (lines.size >= MAX_PDF_REPORT_LINES) {
        lines[MAX_PDF_REPORT_LINES - 1] =
            context.getString(R.string.backup_report_truncated)
    }
    return lines.take(MAX_PDF_REPORT_LINES)
}

private fun boundedPdfText(value: String): String = buildString {
    for (character in value) {
        if (length >= MAX_PDF_TEXT_CHARS) break
        append(
            if (character.isISOControl() || character == '\n' || character == '\r') ' '
            else character
        )
    }
}.trim()

private fun wrapPdfLine(text: String, maxChars: Int): List<String> {
    require(maxChars > 0)
    val bounded = text.take(MAX_PDF_TEXT_CHARS)
    if (bounded.length <= maxChars) return listOf(bounded)
    val words = bounded.split(" ")
    val lines = mutableListOf<String>()
    var current = ""
    words.forEach { word ->
        val chunks = if (word.length <= maxChars) listOf(word) else word.chunked(maxChars)
        chunks.forEach { chunk ->
            if (current.isBlank()) {
                current = chunk
            } else if (current.length + chunk.length + 1 <= maxChars) {
                current += " $chunk"
            } else {
                lines += current
                current = chunk
            }
        }
    }
    if (current.isNotBlank()) lines += current
    return lines
}

@Composable
private fun ExerciseHistoryBottomSheetContent(
    exerciseId: Long,
    exerciseName: String,
    history: List<ExerciseHistoryEntry>,
    exerciseMediaOwnerKey: String,
    onEditExerciseMapping: () -> Unit
) {
    val context = LocalContext.current
    val languageTag = currentAppLanguageTag()
    val locale = remember(languageTag) { Locale.forLanguageTag(languageTag) }
    val zoneId = ZoneId.systemDefault()
    val monthFormatter = remember(locale) { DateTimeFormatter.ofPattern("LLLL yyyy", locale) }
    val dayFormatter = remember(locale) { DateTimeFormatter.ofPattern("EEEE, d MMMM", locale) }
    val systemTimeFormatter = remember(context) { AndroidDateFormat.getTimeFormat(context) }

    val sessionGroups = remember(history) {
        history
            .groupBy { it.sessionId }
            .values
            .map { entries ->
                ExerciseHistorySessionGroup(
                    sessionId = entries.first().sessionId,
                    sessionDate = entries.first().sessionDate,
                    sets = entries.sortedBy { it.setOrderIndex }
                )
            }
            .sortedByDescending { it.sessionDate }
    }

    val sessionsByMonth = remember(sessionGroups, zoneId) {
        sessionGroups.groupBy { group ->
            YearMonth.from(Instant.ofEpochMilli(group.sessionDate).atZone(zoneId).toLocalDate())
        }.toSortedMap(compareByDescending { it })
    }

    val totalVolume = remember(history) { history.sumOf { it.weight * it.reps } }
    val muscleIntensities = remember(exerciseName) {
        defaultContributionsForExercise(exerciseName)
            .associate { contribution -> contribution.muscleId to contribution.weight.toFloat() }
    }

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ExerciseMediaPreview(
                    exerciseId = exerciseId,
                    exerciseName = exerciseName,
                    ownerKey = exerciseMediaOwnerKey,
                    width = 84.dp,
                    height = 70.dp
                )
                Text(
                    text = localizedExerciseName(exerciseName),
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.weight(1f)
                )
            }
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    HistoryStat(
                        label = stringResource(R.string.exercise_history_sessions),
                        value = sessionGroups.size.toString(),
                        modifier = Modifier.weight(1f)
                    )
                    HistoryStat(
                        label = stringResource(R.string.exercise_history_sets),
                        value = history.size.toString(),
                        modifier = Modifier.weight(1f)
                    )
                    HistoryStat(
                        label = stringResource(R.string.exercise_history_volume),
                        value = String.format(locale, "%.0f", totalVolume),
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }

        if (muscleIntensities.isNotEmpty()) {
            item {
                ExerciseMuscleBreakdownCard(
                    exerciseName = exerciseName,
                    muscleIntensities = muscleIntensities,
                    onEditMapping = onEditExerciseMapping
                )
            }
        }

        if (history.isEmpty()) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.exercise_history_empty),
                    supporting = stringResource(R.string.exercise_library_empty_supporting)
                )
            }
            return@LazyColumn
        }

        sessionsByMonth.forEach { (month, monthSessions) ->
            item(key = "month_$month") {
                Text(
                    text = month.format(monthFormatter).replaceFirstChar {
                        if (it.isLowerCase()) it.titlecase(locale) else it.toString()
                    },
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }

            val sessionsByDay = monthSessions.groupBy { group ->
                Instant.ofEpochMilli(group.sessionDate).atZone(zoneId).toLocalDate()
            }.toSortedMap(compareByDescending { it })

            sessionsByDay.forEach { (day, daySessions) ->
                item(key = "day_${month}_$day") {
                    Text(
                        text = day.format(dayFormatter).replaceFirstChar {
                            if (it.isLowerCase()) it.titlecase(locale) else it.toString()
                        },
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                items(
                    items = daySessions,
                    key = { group -> group.sessionId }
                ) { sessionGroup ->
                    val timeText = systemTimeFormatter.format(Date(sessionGroup.sessionDate))
                    ExerciseHistorySessionCard(
                        sessionGroup = sessionGroup,
                        timeText = timeText
                    )
                }
            }
        }
    }
}

@Composable
private fun HistoryStat(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = value,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun ExerciseHistorySessionCard(
    sessionGroup: ExerciseHistorySessionGroup,
    timeText: String
) {
    val locale = Locale.getDefault()
    val totalVolume = sessionGroup.sets.sumOf { it.weight * it.reps }
    val maxWeight = sessionGroup.sets.maxOfOrNull { it.weight } ?: 0.0

    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.session_item_title, timeText),
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = stringResource(R.string.progress_weight_value, maxWeight),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.exercise_history_sets_inline, sessionGroup.sets.size),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = stringResource(R.string.exercise_history_volume_inline, String.format(locale, "%.0f", totalVolume)),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            HorizontalDivider()

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.label_set_short),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelLarge
                )
                Text(
                    text = stringResource(R.string.label_weight_kg),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelLarge
                )
                Text(
                    text = stringResource(R.string.label_reps),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelLarge
                )
            }

            sessionGroup.sets.forEachIndexed { index, set ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = stringResource(R.string.label_set, index + 1),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = formatWeightShort(set.weight),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = set.reps.toString(),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        }
    }
}

private fun formatWeightShort(weight: Double): String {
    return if (weight % 1.0 == 0.0) {
        weight.toInt().toString()
    } else {
        String.format(Locale.getDefault(), "%.1f", weight)
    }
}
