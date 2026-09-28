package com.example.gymapp.ui.screens

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.example.gymapp.R
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.repository.VoiceWorkoutBlock
import com.example.gymapp.data.repository.VoiceWorkoutBlockIssue
import com.example.gymapp.data.repository.VoiceWorkoutDiagnosticKind
import com.example.gymapp.data.repository.VoiceWorkoutDraft
import com.example.gymapp.data.repository.VoiceWorkoutDraftParser
import com.example.gymapp.data.repository.VoiceWorkoutMatch
import com.example.gymapp.data.repository.VoiceWorkoutSet
import com.example.gymapp.data.repository.WorkoutExerciseDraft
import com.example.gymapp.data.repository.WorkoutSetDraft
import com.example.gymapp.data.repository.voiceWorkoutExerciseInputs
import com.example.gymapp.ui.util.currentAppLanguageTag
import java.util.UUID
import kotlinx.coroutines.delay

enum class VoiceTranscriptionError {
    Unavailable,
    UnsupportedLanguage,
    PermissionDenied,
    AudioFailure,
    RecognitionFailure
}

/**
 * On-device only: API 31+ `createOnDeviceSpeechRecognizer`. Older Android versions and
 * devices without a local model get manual text entry instead of a network recognizer.
 */
internal fun voiceTranscriptionAvailability(context: Context): VoiceTranscriptionError? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return VoiceTranscriptionError.Unavailable
    return if (SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) null else VoiceTranscriptionError.Unavailable
}

// internal (not private): also reused by ActiveWorkoutScreen's in-workout voice
// command mic, so both entry points share the same on-device-only recognizer.
internal class OnDeviceVoiceTranscriber(
    private val context: Context,
    private val onPartial: (String) -> Unit,
    private val onFinished: (VoiceTranscriptionError?) -> Unit
) {
    private var recognizer: SpeechRecognizer? = null
    private var session = 0L

    fun start(languageTag: String) {
        stop()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            onFinished(VoiceTranscriptionError.Unavailable)
            return
        }
        val current = ++session
        val speech = try {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        } catch (_: RuntimeException) {
            onFinished(VoiceTranscriptionError.Unavailable)
            return
        }
        recognizer = speech
        speech.setRecognitionListener(object : RecognitionListener {
            private fun transcript(results: Bundle?): String? =
                results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()

            override fun onPartialResults(partialResults: Bundle?) {
                if (current == session) transcript(partialResults)?.let(onPartial)
            }

            override fun onResults(results: Bundle?) {
                if (current != session) return
                transcript(results)?.let(onPartial)
                finish(null)
            }

            override fun onError(error: Int) {
                if (current != session) return
                finish(
                    when (error) {
                        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
                        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> VoiceTranscriptionError.UnsupportedLanguage
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> VoiceTranscriptionError.PermissionDenied
                        SpeechRecognizer.ERROR_AUDIO -> VoiceTranscriptionError.AudioFailure
                        SpeechRecognizer.ERROR_CLIENT -> null
                        else -> VoiceTranscriptionError.RecognitionFailure
                    }
                )
            }

            override fun onReadyForSpeech(params: Bundle?) = Unit
            override fun onBeginningOfSpeech() = Unit
            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() = Unit
            override fun onEvent(eventType: Int, params: Bundle?) = Unit
        })
        val locale = VoiceWorkoutDraftParser.LOCALES[languageTag] ?: VoiceWorkoutDraftParser.LOCALES.getValue("en")
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 3_000L)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                putExtra(RecognizerIntent.EXTRA_ENABLE_FORMATTING, RecognizerIntent.FORMATTING_OPTIMIZE_QUALITY)
            }
        }
        try {
            speech.startListening(intent)
        } catch (_: RuntimeException) {
            finish(VoiceTranscriptionError.AudioFailure)
        }
    }

    private fun finish(error: VoiceTranscriptionError?) {
        stop()
        onFinished(error)
    }

    fun stop() {
        session += 1
        recognizer?.let {
            it.cancel()
            it.destroy()
        }
        recognizer = null
    }
}

@Composable
private fun voiceErrorText(error: VoiceTranscriptionError): String = stringResource(
    when (error) {
        VoiceTranscriptionError.Unavailable -> R.string.voice_workout_error_unavailable
        VoiceTranscriptionError.UnsupportedLanguage -> R.string.voice_workout_error_unsupported
        VoiceTranscriptionError.PermissionDenied -> R.string.voice_workout_error_permission
        VoiceTranscriptionError.AudioFailure -> R.string.voice_workout_error_audio
        VoiceTranscriptionError.RecognitionFailure -> R.string.voice_workout_error_recognition
    }
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun VoiceWorkoutDraftSheet(
    exercises: List<ExerciseEntity>,
    existingExerciseCount: Int,
    onApply: (List<WorkoutExerciseDraft>, Boolean) -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val languageTag = currentAppLanguageTag()
    val inputs = remember(exercises) { voiceWorkoutExerciseInputs(exercises) }
    var transcript by rememberSaveable { mutableStateOf("") }
    var draft by remember { mutableStateOf(VoiceWorkoutDraft()) }
    var isListening by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<VoiceTranscriptionError?>(null) }
    var unavailable by remember { mutableStateOf(voiceTranscriptionAvailability(context)) }
    var showReplaceConfirmation by rememberSaveable { mutableStateOf(false) }
    val weightTexts = remember { mutableStateMapOf<String, String>() }
    val repsTexts = remember { mutableStateMapOf<String, String>() }

    fun updateTranscript(value: String) {
        val bounded = VoiceWorkoutDraftParser.truncateUtf8(value)
        transcript = bounded
        weightTexts.clear()
        repsTexts.clear()
        draft = if (bounded.isEmpty()) VoiceWorkoutDraft() else VoiceWorkoutDraftParser.parse(bounded, inputs)
    }

    val transcriber = remember {
        OnDeviceVoiceTranscriber(
            context = context.applicationContext,
            onPartial = { updateTranscript(it) },
            onFinished = { finishedError ->
                isListening = false
                if (finishedError != null) error = finishedError
                if (finishedError == VoiceTranscriptionError.UnsupportedLanguage) unavailable = finishedError
            }
        )
    }
    DisposableEffect(transcriber) { onDispose { transcriber.stop() } }
    LaunchedEffect(isListening) {
        if (isListening) {
            delay(VoiceWorkoutDraftParser.AUTO_STOP_SECONDS * 1_000L)
            transcriber.stop()
            isListening = false
        }
    }

    fun startListening() {
        error = null
        isListening = true
        transcriber.start(languageTag)
    }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) startListening() else error = VoiceTranscriptionError.PermissionDenied
    }

    fun toggleListening() {
        if (isListening) {
            transcriber.stop()
            isListening = false
            return
        }
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            startListening()
        } else {
            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    fun updateBlock(blockId: String, transform: (VoiceWorkoutBlock) -> VoiceWorkoutBlock) {
        draft = draft.copy(blocks = draft.blocks.map { if (it.id == blockId) transform(it) else it })
    }

    fun updateSet(blockId: String, setId: String, transform: (VoiceWorkoutSet) -> VoiceWorkoutSet) {
        updateBlock(blockId) { block -> block.copy(sets = block.sets.map { if (it.id == setId) transform(it) else it }) }
    }

    val canApply = !isListening && draft.blocks.isNotEmpty() && draft.blocks.all { it.isValid }
    val canAdd = existingExerciseCount + draft.blocks.size <= VoiceWorkoutDraftParser.MAX_BLOCKS

    fun apply(replace: Boolean) {
        if (!canApply || (!replace && !canAdd)) return
        val drafts = draft.blocks.mapNotNull { block ->
            val exerciseId = block.exerciseId?.toLongOrNull() ?: return@mapNotNull null
            WorkoutExerciseDraft(
                exerciseId = exerciseId,
                sets = block.sets.mapNotNull { set ->
                    val weight = set.weight ?: return@mapNotNull null
                    val reps = set.reps ?: return@mapNotNull null
                    WorkoutSetDraft(weight = weight, reps = reps)
                }
            )
        }
        if (drafts.size != draft.blocks.size || drafts.isEmpty()) return
        transcriber.stop()
        isListening = false
        onApply(drafts, replace)
    }

    val notices = buildList {
        if (draft.diagnostics.any { it.kind == VoiceWorkoutDiagnosticKind.TranscriptTooLong }) {
            add(stringResource(R.string.voice_workout_notice_too_long))
        }
        if (draft.diagnostics.any { it.kind == VoiceWorkoutDiagnosticKind.LimitsExceeded }) {
            add(stringResource(R.string.voice_workout_notice_limits))
        }
    }

    ModalBottomSheet(
        onDismissRequest = {
            transcriber.stop()
            onDismiss()
        },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        modifier = Modifier.testTag("voice_workout_sheet")
    ) {
        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = stringResource(R.string.voice_workout_title),
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.weight(1f)
                    )
                    TextButton(
                        onClick = {
                            transcriber.stop()
                            onDismiss()
                        },
                        modifier = Modifier.testTag("voice_workout_cancel")
                    ) { Text(stringResource(R.string.voice_workout_cancel)) }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.voice_workout_dictation), style = MaterialTheme.typography.labelLarge)
                    OutlinedTextField(
                        value = transcript,
                        onValueChange = ::updateTranscript,
                        placeholder = { Text(stringResource(R.string.voice_workout_placeholder)) },
                        minLines = 3,
                        maxLines = 8,
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("voice_workout_transcript")
                    )
                    val currentUnavailable = unavailable
                    if (currentUnavailable == null) {
                        val listeningState = stringResource(
                            if (isListening) R.string.voice_workout_state_listening else R.string.voice_workout_state_ready
                        )
                        OutlinedButton(
                            onClick = ::toggleListening,
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("voice_workout_speak")
                                .semantics { stateDescription = listeningState }
                        ) {
                            Icon(if (isListening) Icons.Default.StopCircle else Icons.Default.Mic, contentDescription = null)
                            Spacer(Modifier.size(8.dp))
                            Text(stringResource(if (isListening) R.string.voice_workout_stop else R.string.voice_workout_speak))
                        }
                        if (isListening) {
                            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("voice_workout_listening")) {
                                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                                Spacer(Modifier.size(8.dp))
                                Text(
                                    stringResource(R.string.voice_workout_listening),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    } else {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("voice_workout_unavailable")) {
                            Icon(Icons.Default.MicOff, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.size(8.dp))
                            Text(voiceErrorText(currentUnavailable), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Text(
                        stringResource(R.string.voice_workout_privacy),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.testTag("voice_workout_privacy")
                    )
                }
            }
            val currentError = error
            if (currentError != null && currentError != unavailable) {
                item {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("voice_workout_error")) {
                        Icon(Icons.Default.ErrorOutline, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.size(8.dp))
                        Text(voiceErrorText(currentError), color = MaterialTheme.colorScheme.error)
                    }
                }
            }
            if (draft.blocks.isNotEmpty()) {
                item {
                    Text(stringResource(R.string.voice_workout_preview), style = MaterialTheme.typography.labelLarge)
                }
                items(draft.blocks, key = { it.id }) { block ->
                    VoiceWorkoutBlockEditor(
                        block = block,
                        exercises = exercises,
                        languageTag = languageTag,
                        weightText = { set -> weightTexts[set.id] ?: VoiceWorkoutDraftParser.formatWeight(set.weight) },
                        repsText = { set -> repsTexts[set.id] ?: set.reps?.toString().orEmpty() },
                        onSelectExercise = { exercise ->
                            updateBlock(block.id) { it.copy(exerciseId = exercise?.id?.toString(), catalogKey = null) }
                        },
                        onWeightChange = { set, value ->
                            weightTexts[set.id] = value
                            updateSet(block.id, set.id) { it.copy(weight = VoiceWorkoutDraftParser.parseWeightInput(value)) }
                        },
                        onRepsChange = { set, value ->
                            repsTexts[set.id] = value
                            val trimmed = value.trim()
                            updateSet(block.id, set.id) {
                                it.copy(reps = if (trimmed.isEmpty()) null else trimmed.toIntOrNull() ?: -1)
                            }
                        },
                        onRemoveSet = { set ->
                            weightTexts.remove(set.id)
                            repsTexts.remove(set.id)
                            updateBlock(block.id) { it.copy(sets = it.sets.filterNot { candidate -> candidate.id == set.id }) }
                        },
                        onAddSet = {
                            updateBlock(block.id) {
                                if (it.sets.size >= VoiceWorkoutDraftParser.MAX_SETS_PER_BLOCK) {
                                    it
                                } else {
                                    val last = it.sets.lastOrNull()
                                    it.copy(sets = it.sets + VoiceWorkoutSet(UUID.randomUUID().toString(), last?.weight, last?.reps))
                                }
                            }
                        },
                        onRemoveBlock = { draft = draft.copy(blocks = draft.blocks.filterNot { it.id == block.id }) }
                    )
                }
            }
            if (notices.isNotEmpty()) {
                items(notices) { notice ->
                    Text(notice, color = MaterialTheme.colorScheme.tertiary, style = MaterialTheme.typography.bodyMedium)
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(bottom = 24.dp)) {
                    if (existingExerciseCount > 0) {
                        Text(stringResource(R.string.voice_workout_existing_header), style = MaterialTheme.typography.labelLarge)
                        Button(
                            onClick = { apply(replace = false) },
                            enabled = canApply && canAdd,
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("voice_workout_apply_add")
                        ) { Text(stringResource(R.string.voice_workout_add)) }
                        OutlinedButton(
                            onClick = { showReplaceConfirmation = true },
                            enabled = canApply,
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("voice_workout_apply_replace")
                        ) { Text(stringResource(R.string.voice_workout_replace), color = MaterialTheme.colorScheme.error) }
                        if (!canAdd) {
                            Text(
                                stringResource(R.string.voice_workout_limit_footer),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    } else {
                        Button(
                            onClick = { apply(replace = true) },
                            enabled = canApply,
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("voice_workout_apply_replace")
                        ) { Text(stringResource(R.string.voice_workout_apply)) }
                    }
                }
            }
        }
    }

    if (showReplaceConfirmation) {
        AlertDialog(
            onDismissRequest = { showReplaceConfirmation = false },
            title = { Text(stringResource(R.string.voice_workout_replace_title)) },
            text = { Text(stringResource(R.string.voice_workout_replace_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showReplaceConfirmation = false
                        apply(replace = true)
                    },
                    modifier = Modifier.testTag("voice_workout_replace_confirm")
                ) { Text(stringResource(R.string.voice_workout_replace_confirm), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showReplaceConfirmation = false }) {
                    Text(stringResource(R.string.voice_workout_cancel))
                }
            }
        )
    }
}

@Composable
private fun VoiceWorkoutBlockEditor(
    block: VoiceWorkoutBlock,
    exercises: List<ExerciseEntity>,
    languageTag: String,
    weightText: (VoiceWorkoutSet) -> String,
    repsText: (VoiceWorkoutSet) -> String,
    onSelectExercise: (ExerciseEntity?) -> Unit,
    onWeightChange: (VoiceWorkoutSet, String) -> Unit,
    onRepsChange: (VoiceWorkoutSet, String) -> Unit,
    onRemoveSet: (VoiceWorkoutSet) -> Unit,
    onAddSet: () -> Unit,
    onRemoveBlock: () -> Unit
) {
    var menuOpen by remember { mutableStateOf(false) }
    val selected = exercises.firstOrNull { it.id.toString() == block.exerciseId }
    val candidateIds = block.candidates.map { it.id }.toSet()
    val ordered = exercises.filter { it.id.toString() in candidateIds } + exercises.filterNot { it.id.toString() in candidateIds }
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .testTag("voice_workout_block_${block.id}")
    ) {
        HorizontalDivider()
        if (block.spokenName.isNotEmpty()) {
            Text(
                "“${block.spokenName}”",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Box {
            val chooseLabel = stringResource(R.string.voice_workout_choose_exercise)
            OutlinedButton(
                onClick = { menuOpen = true },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("voice_workout_block_exercise")
            ) {
                Text(
                    selected?.let { BuiltInExerciseCatalog.displayName(it.name, languageTag) } ?: chooseLabel,
                    modifier = Modifier.weight(1f)
                )
                Icon(Icons.Default.KeyboardArrowDown, contentDescription = null)
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                DropdownMenuItem(text = { Text(chooseLabel) }, onClick = {
                    menuOpen = false
                    onSelectExercise(null)
                })
                ordered.forEach { exercise ->
                    DropdownMenuItem(
                        text = { Text(BuiltInExerciseCatalog.displayName(exercise.name, languageTag)) },
                        onClick = {
                            menuOpen = false
                            onSelectExercise(exercise)
                        }
                    )
                }
            }
        }
        val removeSetLabel = stringResource(R.string.voice_workout_remove_set)
        block.sets.forEach { set ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = weightText(set),
                    onValueChange = { onWeightChange(set, it) },
                    label = { Text(stringResource(R.string.voice_workout_weight)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.weight(1f)
                )
                Text(stringResource(R.string.voice_workout_kg_times), color = MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedTextField(
                    value = repsText(set),
                    onValueChange = { onRepsChange(set, it) },
                    label = { Text(stringResource(R.string.voice_workout_reps)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = { onRemoveSet(set) }, modifier = Modifier.semantics { contentDescription = removeSetLabel }) {
                    Icon(Icons.Default.RemoveCircleOutline, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                }
            }
        }
        block.issue?.let { issue ->
            val message = when {
                issue == VoiceWorkoutBlockIssue.ChooseExercise && block.match == VoiceWorkoutMatch.Ambiguous ->
                    stringResource(R.string.voice_workout_issue_ambiguous)
                issue == VoiceWorkoutBlockIssue.ChooseExercise -> stringResource(R.string.voice_workout_issue_choose)
                else -> stringResource(R.string.voice_workout_issue_sets)
            }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("voice_workout_block_issue")) {
                Icon(Icons.Default.ErrorOutline, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(6.dp))
                Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onAddSet, enabled = block.sets.size < VoiceWorkoutDraftParser.MAX_SETS_PER_BLOCK) {
                Icon(Icons.Default.Add, contentDescription = null)
                Spacer(Modifier.size(6.dp))
                Text(stringResource(R.string.voice_workout_add_set))
            }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onRemoveBlock) {
                Icon(Icons.Default.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.size(6.dp))
                Text(stringResource(R.string.voice_workout_remove_exercise), color = MaterialTheme.colorScheme.error)
            }
        }
    }
}
