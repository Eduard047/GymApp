package com.example.gymapp.ui.screens

import android.content.Intent
import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.ui.components.ExerciseMuscleBreakdownCard
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.util.localizedMuscleName
import com.example.gymapp.ui.viewmodel.ExerciseListUiState
import com.example.gymapp.ui.viewmodel.ExerciseMuscleMappingUiModel
import com.example.gymapp.ui.viewmodel.ExerciseMuscleOptionUiModel
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.text.DateFormat
import java.util.Date
import java.util.Locale
import java.io.File
import org.json.JSONObject

private data class ExerciseHistorySessionGroup(
    val sessionId: Long,
    val sessionDate: Long,
    val sets: List<ExerciseHistoryEntry>
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExerciseListScreen(
    uiState: ExerciseListUiState,
    onNameChange: (String) -> Unit,
    onAddExercise: () -> Unit,
    onExerciseClick: (Long) -> Unit,
    onStartRenameExercise: (ExerciseEntity) -> Unit,
    onRenameExerciseNameChange: (String) -> Unit,
    onSaveRenameExercise: () -> Unit,
    onDismissRenameExercise: () -> Unit,
    onDeleteExercise: (ExerciseEntity) -> Unit,
    onEditExerciseMapping: (String) -> Unit,
    onToggleExerciseMappingMuscle: (String) -> Unit,
    onSaveExerciseMapping: () -> Unit,
    onDismissExerciseMapping: () -> Unit,
    onDismissHistory: () -> Unit,
    onExportBackup: () -> Unit,
    onExportDiagnostics: () -> Unit,
    onClearBackup: () -> Unit,
    onOpenImport: () -> Unit,
    onCloseImport: () -> Unit,
    onImportJsonChange: (String) -> Unit,
    onImportBackup: () -> Unit,
    onLogout: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        AccountStatusCard(
            label = uiState.accountLabel,
            supporting = uiState.accountSupporting,
            canLogout = uiState.canLogout,
            onLogout = onLogout
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedTextField(
                value = uiState.newExerciseName,
                onValueChange = onNameChange,
                modifier = Modifier.weight(1f),
                label = { Text(stringResource(R.string.label_exercise_name)) },
                placeholder = { Text(stringResource(R.string.hint_exercise_name)) },
                singleLine = true
            )
            OutlinedButton(onClick = onAddExercise) {
                Text(text = stringResource(R.string.action_add_exercise))
            }
        }

        if (uiState.hasInputError) {
            Text(
                text = stringResource(R.string.message_exercise_error),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium
            )
        }

        BackupToolsCard(
            message = uiState.backupMessage,
            onExportBackup = onExportBackup,
            onExportDiagnostics = onExportDiagnostics,
            onOpenImport = onOpenImport
        )

        if (uiState.exercises.isEmpty()) {
            Text(
                text = stringResource(R.string.empty_exercises),
                style = MaterialTheme.typography.bodyLarge
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (uiState.muscleMappings.isNotEmpty()) {
                    item {
                        ExerciseMuscleMappingsCard(
                            mappings = uiState.muscleMappings,
                            onEditExerciseMapping = onEditExerciseMapping
                        )
                    }
                }
                items(
                    items = uiState.exercises,
                    key = { it.id }
                ) { exercise ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onExerciseClick(exercise.id) }
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text(
                                text = localizedExerciseName(exercise.name),
                                modifier = Modifier.weight(1f),
                                style = MaterialTheme.typography.bodyLarge
                            )
                            IconButton(onClick = { onStartRenameExercise(exercise) }) {
                                Icon(
                                    imageVector = Icons.Default.Edit,
                                    contentDescription = stringResource(R.string.cd_edit)
                                )
                            }
                            IconButton(onClick = { onDeleteExercise(exercise) }) {
                                Icon(
                                    imageVector = Icons.Default.Delete,
                                    contentDescription = stringResource(R.string.cd_delete)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    val editingExercise = uiState.editingExercise
    if (editingExercise != null) {
        ModalBottomSheet(onDismissRequest = onDismissRenameExercise) {
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
        ModalBottomSheet(onDismissRequest = onDismissHistory) {
            ExerciseHistoryBottomSheetContent(
                exerciseName = selectedExerciseName,
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
        ModalBottomSheet(onDismissRequest = onDismissExerciseMapping) {
            ExerciseMappingBottomSheetContent(
                exerciseName = mappingExerciseName,
                muscles = uiState.mappingEditorMuscles,
                onToggleMuscle = onToggleExerciseMappingMuscle,
                onSave = onSaveExerciseMapping,
                onDismiss = onDismissExerciseMapping
            )
        }
    }

    val backupJson = uiState.backupJson
    if (backupJson != null) {
        ModalBottomSheet(onDismissRequest = onClearBackup) {
            BackupJsonBottomSheetContent(
                json = backupJson,
                onDismiss = onClearBackup
            )
        }
    }

    if (uiState.isImportOpen) {
        ModalBottomSheet(onDismissRequest = onCloseImport) {
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

@Composable
private fun ExerciseMuscleMappingsCard(
    mappings: List<ExerciseMuscleMappingUiModel>,
    onEditExerciseMapping: (String) -> Unit
) {
    val languageTag = currentAppLanguageTag()
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.exercise_mappings_title),
                style = MaterialTheme.typography.titleSmall
            )
            mappings.forEach { mapping ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = localizedExerciseName(mapping.exerciseName),
                            style = MaterialTheme.typography.bodyMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = if (mapping.isMapped) {
                                mapping.muscleIds.joinToString(", ") { muscleId ->
                                    localizedMuscleName(muscleId, languageTag)
                                }
                            } else {
                                stringResource(R.string.exercise_mappings_unmapped)
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    OutlinedButton(onClick = { onEditExerciseMapping(mapping.exerciseName) }) {
                        Text(stringResource(R.string.exercise_mappings_edit))
                    }
                }
            }
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
private fun AccountStatusCard(
    label: String,
    supporting: String,
    canLogout: Boolean,
    onLogout: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = label,
                    style = MaterialTheme.typography.titleSmall
                )
                Text(
                    text = supporting,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (canLogout) {
                OutlinedButton(onClick = onLogout) {
                    Text(stringResource(R.string.auth_switch_account))
                }
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
private fun BackupToolsCard(
    message: String?,
    onExportBackup: () -> Unit,
    onExportDiagnostics: () -> Unit,
    onOpenImport: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.backup_tools_title),
                style = MaterialTheme.typography.titleSmall
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
            if (!message.isNullOrBlank()) {
                Text(
                    text = message,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun BackupJsonBottomSheetContent(
    json: String,
    onDismiss: () -> Unit
) {
    val clipboardManager = LocalClipboardManager.current
    val context = LocalContext.current

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text(
                text = stringResource(R.string.backup_export_ready),
                style = MaterialTheme.typography.headlineSmall
            )
        }
        item {
            OutlinedTextField(
                value = json,
                onValueChange = {},
                modifier = Modifier.fillMaxWidth(),
                readOnly = true,
                minLines = 6,
                maxLines = 12
            )
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(
                    onClick = {
                        clipboardManager.setText(AnnotatedString(json))
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.backup_copy_json))
                }
                OutlinedButton(
                    onClick = {
                        val sendIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "application/json"
                            putExtra(Intent.EXTRA_TEXT, json)
                        }
                        context.startActivity(
                            Intent.createChooser(
                                sendIntent,
                                context.getString(R.string.backup_share_json)
                            )
                        )
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.backup_share_json))
                }
            }
        }
        item {
            OutlinedButton(
                onClick = { shareBackupPdf(context, json) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.backup_share_pdf))
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
}

@Composable
private fun ImportBackupBottomSheetContent(
    importJson: String,
    importMessage: String?,
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
        if (!importMessage.isNullOrBlank()) {
            Text(
                text = importMessage,
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

private fun shareBackupPdf(context: Context, json: String) {
    val file = createBackupPdfFile(context, json)
    val uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file
    )
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = "application/pdf"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(
        Intent.createChooser(
            sendIntent,
            context.getString(R.string.backup_share_pdf)
        )
    )
}

private fun createBackupPdfFile(context: Context, json: String): File {
    val document = PdfDocument()
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

    fun newPage() {
        document.finishPage(page)
        pageNumber += 1
        page = document.startPage(
            PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pageNumber).create()
        )
        y = top
    }

    fun drawWrapped(text: String, paint: Paint = bodyPaint, maxChars: Int = 92) {
        wrapPdfLine(text, maxChars).forEach { line ->
            if (y > bottom) {
                newPage()
            }
            page.canvas.drawText(line, left, y, paint)
            y += lineHeight
        }
    }

    backupReportLines(json).forEachIndexed { index, line ->
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
    val outputFile = File(context.cacheDir, "gymapp-diagnostics-${System.currentTimeMillis()}.pdf")
    outputFile.outputStream().use(document::writeTo)
    document.close()
    return outputFile
}

private fun backupReportLines(json: String): List<String> {
    val root = JSONObject(json)
    val exportedAt = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
        .format(Date(root.optLong("exportedAt", System.currentTimeMillis())))
    val exercises = root.optJSONArray("exercises")
    val sessions = root.optJSONArray("sessions")
    val summary = root.optJSONObject("summary")
    val lines = mutableListOf<String>()

    lines += "GymApp diagnostics report"
    lines += "Exported: $exportedAt"
    lines += "Schema: ${root.optInt("schemaVersion", 1)}"
    lines += ""
    lines += "## Summary"
    lines += "Exercises: ${summary?.optInt("exerciseCount") ?: (exercises?.length() ?: 0)}"
    lines += "Workouts: ${summary?.optInt("sessionCount") ?: (sessions?.length() ?: 0)}"
    summary?.let {
        lines += "Sets: ${it.optInt("setCount")}"
    }

    lines += ""
    lines += "## Exercises"
    if (exercises == null || exercises.length() == 0) {
        lines += "No exercises exported."
    } else {
        repeat(exercises.length().coerceAtMost(120)) { index ->
            val name = exercises.optJSONObject(index)?.optString("name").orEmpty()
            if (name.isNotBlank()) {
                lines += "- $name"
            }
        }
        if (exercises.length() > 120) {
            lines += "... ${exercises.length() - 120} more exercises"
        }
    }

    lines += ""
    lines += "## Workouts"
    if (sessions == null || sessions.length() == 0) {
        lines += "No workouts exported."
    } else {
        repeat(sessions.length().coerceAtMost(80)) { sessionIndex ->
            val session = sessions.optJSONObject(sessionIndex) ?: return@repeat
            val date = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
                .format(Date(session.optLong("date", 0L)))
            val note = session.optString("note").takeIf { it.isNotBlank() }
            lines += "$date${note?.let { " - $it" }.orEmpty()}"
            val sessionExercises = session.optJSONArray("exercises")
            repeat(sessionExercises?.length() ?: 0) { exerciseIndex ->
                val exercise = sessionExercises?.optJSONObject(exerciseIndex) ?: return@repeat
                val sets = exercise.optJSONArray("sets")
                val setText = buildString {
                    repeat(sets?.length() ?: 0) { setIndex ->
                        val set = sets?.optJSONObject(setIndex) ?: return@repeat
                        if (isNotEmpty()) append(", ")
                        append(set.optDouble("weight", 0.0).toString().trimEnd('0').trimEnd('.'))
                        append("kg x ")
                        append(set.optInt("reps", 0))
                    }
                }
                lines += "  - ${exercise.optString("name")}: $setText"
            }
            lines += ""
        }
        if (sessions.length() > 80) {
            lines += "... ${sessions.length() - 80} more workouts"
        }
    }

    return lines
}

private fun wrapPdfLine(text: String, maxChars: Int): List<String> {
    if (text.length <= maxChars) return listOf(text)
    val words = text.split(" ")
    val lines = mutableListOf<String>()
    var current = ""
    words.forEach { word ->
        if (current.isBlank()) {
            current = word
        } else if (current.length + word.length + 1 <= maxChars) {
            current += " $word"
        } else {
            lines += current
            current = word
        }
    }
    if (current.isNotBlank()) lines += current
    return lines
}

@Composable
private fun ExerciseHistoryBottomSheetContent(
    exerciseName: String,
    history: List<ExerciseHistoryEntry>,
    onEditExerciseMapping: () -> Unit
) {
    val locale = Locale.getDefault()
    val zoneId = ZoneId.systemDefault()
    val monthFormatter = remember(locale) { DateTimeFormatter.ofPattern("LLLL yyyy", locale) }
    val dayFormatter = remember(locale) { DateTimeFormatter.ofPattern("EEEE, d MMMM", locale) }
    val timeFormatter = remember(locale) { DateTimeFormatter.ofPattern("HH:mm", locale) }

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
            Text(
                text = localizedExerciseName(exerciseName),
                style = MaterialTheme.typography.headlineSmall
            )
        }

        item {
            Card(modifier = Modifier.fillMaxWidth()) {
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
                Card(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = stringResource(R.string.exercise_history_empty),
                        modifier = Modifier.padding(14.dp),
                        style = MaterialTheme.typography.bodyLarge
                    )
                }
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
                    val timeText = Instant.ofEpochMilli(sessionGroup.sessionDate)
                        .atZone(zoneId)
                        .toLocalTime()
                        .format(timeFormatter)
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

    Card(modifier = Modifier.fillMaxWidth()) {
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
