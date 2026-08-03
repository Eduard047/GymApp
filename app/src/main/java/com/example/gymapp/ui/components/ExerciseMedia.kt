package com.example.gymapp.ui.components

import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.Crossfade
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.media.ExerciseMediaStore
import com.example.gymapp.ui.theme.GymControlShape
import com.example.gymapp.ui.util.localizedExerciseName
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private data class ExerciseMediaFrames(
    val custom: Bitmap?,
    val bundled: List<Bitmap>
)

@Composable
fun ExerciseMediaPreview(
    exerciseId: Long,
    exerciseName: String,
    ownerKey: String,
    modifier: Modifier = Modifier,
    width: Dp = 76.dp,
    height: Dp = 64.dp,
    editable: Boolean = true
) {
    require(ownerKey.isNotBlank()) { "Exercise media must be bound to an active account." }
    var showSheet by remember(exerciseId, ownerKey) { mutableStateOf(false) }
    var revision by remember(exerciseId, ownerKey) { mutableIntStateOf(0) }
    val context = LocalContext.current
    val image by produceState<Bitmap?>(
        initialValue = null,
        exerciseId,
        exerciseName,
        ownerKey,
        revision,
        width,
        height
    ) {
        value = withContext(Dispatchers.IO) {
            runCatching {
                ExerciseMediaStore.loadCustom(context, ownerKey, exerciseId, 256, 192)
            }.getOrNull() ?: ExerciseMediaStore.bundledFramePaths(exerciseName)
                .firstOrNull()
                ?.let { path ->
                    runCatching {
                        ExerciseMediaStore.loadBundledFrame(context, path, 256, 192)
                    }.getOrNull()
                }
        }
    }

    Surface(
        modifier = modifier
            .size(width = width, height = height)
            .clickable { showSheet = true },
        shape = GymControlShape,
        color = MaterialTheme.colorScheme.surfaceVariant
    ) {
        Box(contentAlignment = Alignment.Center) {
            val bitmap = image
            if (bitmap != null) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = stringResource(R.string.exercise_media_hint),
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop
                )
                Surface(
                    modifier = Modifier.align(Alignment.BottomEnd).padding(5.dp),
                    shape = GymControlShape,
                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.9f)
                ) {
                    Icon(
                        Icons.Default.PlayArrow,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onPrimary,
                        modifier = Modifier.padding(3.dp).size(16.dp)
                    )
                }
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.Image, contentDescription = null)
                    Text(
                        stringResource(R.string.exercise_media_add),
                        style = MaterialTheme.typography.labelSmall
                    )
                }
            }
        }
    }

    if (showSheet) {
        ExerciseMediaSheet(
            exerciseId = exerciseId,
            exerciseName = exerciseName,
            ownerKey = ownerKey,
            editable = editable,
            onMediaChanged = { revision += 1 },
            onDismiss = { showSheet = false }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ExerciseMediaSheet(
    exerciseId: Long,
    exerciseName: String,
    ownerKey: String,
    editable: Boolean,
    onMediaChanged: () -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var revision by remember(exerciseId, ownerKey) { mutableIntStateOf(0) }
    var error by remember(exerciseId, ownerKey) { mutableStateOf(false) }
    val frames by produceState(
        initialValue = ExerciseMediaFrames(custom = null, bundled = emptyList()),
        exerciseId,
        exerciseName,
        ownerKey,
        revision
    ) {
        value = withContext(Dispatchers.IO) {
            val custom = runCatching {
                ExerciseMediaStore.loadCustom(context, ownerKey, exerciseId, 1_024, 768)
            }.getOrNull()
            val bundled = ExerciseMediaStore.bundledFramePaths(exerciseName).mapNotNull { path ->
                runCatching {
                    ExerciseMediaStore.loadBundledFrame(context, path, 1_024, 768)
                }.getOrNull()
            }
            ExerciseMediaFrames(custom = custom, bundled = bundled)
        }
    }
    var frameIndex by remember(exerciseId, revision) { mutableIntStateOf(0) }
    LaunchedEffect(frames) {
        frameIndex = 0
        if (frames.custom == null && frames.bundled.size > 1) {
            while (true) {
                delay(1_150)
                frameIndex = (frameIndex + 1) % frames.bundled.size
            }
        }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null && editable) {
            scope.launch {
                error = withContext(Dispatchers.IO) {
                    runCatching {
                        ExerciseMediaStore.saveCustom(context, ownerKey, exerciseId, uri)
                    }.isFailure
                }
                revision += 1
                if (!error) onMediaChanged()
            }
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.padding(start = 18.dp, end = 18.dp, bottom = 28.dp)
        ) {
            Text(stringResource(R.string.exercise_media_title), style = MaterialTheme.typography.titleLarge)
            Text(
                localizedExerciseName(exerciseName),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 8.dp, bottom = 14.dp)
            )
            Surface(
                modifier = Modifier.fillMaxWidth().height(230.dp),
                shape = GymControlShape,
                color = MaterialTheme.colorScheme.surfaceVariant
            ) {
                val image = frames.custom ?: frames.bundled.getOrNull(frameIndex)
                if (image != null) {
                    Crossfade(targetState = image, label = "exercise-media") { bitmap ->
                        Image(
                            bitmap = bitmap.asImageBitmap(),
                            contentDescription = stringResource(R.string.exercise_media_hint),
                            modifier = Modifier.fillMaxSize(),
                            contentScale = ContentScale.Fit
                        )
                    }
                } else {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(Icons.Default.Image, contentDescription = null, modifier = Modifier.size(52.dp))
                    }
                }
            }
            Text(
                stringResource(R.string.exercise_media_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 12.dp)
            )
            if (error) {
                Text(
                    stringResource(R.string.exercise_media_error),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
            if (editable) {
                Button(
                    onClick = { picker.launch("image/*") },
                    modifier = Modifier.fillMaxWidth().padding(top = 14.dp)
                ) {
                    Text(stringResource(R.string.exercise_media_choose))
                }
                if (frames.custom != null && frames.bundled.isNotEmpty()) {
                    OutlinedButton(
                        onClick = {
                            scope.launch {
                                withContext(Dispatchers.IO) {
                                    ExerciseMediaStore.deleteCustom(context, ownerKey, exerciseId)
                                }
                                error = false
                                revision += 1
                                onMediaChanged()
                            }
                        },
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                    ) {
                        Text(stringResource(R.string.exercise_media_restore))
                    }
                }
            }
        }
    }
}
