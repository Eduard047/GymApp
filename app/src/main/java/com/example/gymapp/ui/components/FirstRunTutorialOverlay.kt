package com.example.gymapp.ui.components

import androidx.annotation.StringRes
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.dialog
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.theme.GymSpacing

internal const val FIRST_RUN_TUTORIAL_VERSION = 1

internal enum class TutorialTarget {
    TodayFocus,
    TodayPrimaryAction,
    NavigationExercises,
    NavigationProgress,
    NavigationProfile
}

internal data class FirstRunTutorialStep(
    val id: String,
    val target: TutorialTarget,
    @param:StringRes val titleRes: Int,
    @param:StringRes val bodyRes: Int
)

internal val FIRST_RUN_TUTORIAL_STEPS = listOf(
    FirstRunTutorialStep(
        id = "todayFocus",
        target = TutorialTarget.TodayFocus,
        titleRes = R.string.tutorial_today_focus_title,
        bodyRes = R.string.tutorial_today_focus_body
    ),
    FirstRunTutorialStep(
        id = "todayPrimaryAction",
        target = TutorialTarget.TodayPrimaryAction,
        titleRes = R.string.tutorial_today_primary_title,
        bodyRes = R.string.tutorial_today_primary_body
    ),
    FirstRunTutorialStep(
        id = "exercises",
        target = TutorialTarget.NavigationExercises,
        titleRes = R.string.tutorial_exercises_title,
        bodyRes = R.string.tutorial_exercises_body
    ),
    FirstRunTutorialStep(
        id = "progress",
        target = TutorialTarget.NavigationProgress,
        titleRes = R.string.tutorial_progress_title,
        bodyRes = R.string.tutorial_progress_body
    ),
    FirstRunTutorialStep(
        id = "profile",
        target = TutorialTarget.NavigationProfile,
        titleRes = R.string.tutorial_profile_title,
        bodyRes = R.string.tutorial_profile_body
    )
)

@Stable
class TutorialAnchorRegistry {
    private val anchors = mutableStateMapOf<TutorialTarget, Rect>()

    internal operator fun get(target: TutorialTarget): Rect? = anchors[target]

    internal fun update(target: TutorialTarget, bounds: Rect) {
        if (bounds.width > 0f && bounds.height > 0f) anchors[target] = bounds
    }

    internal fun remove(target: TutorialTarget) {
        anchors.remove(target)
    }
}

internal fun Modifier.tutorialAnchor(
    registry: TutorialAnchorRegistry,
    target: TutorialTarget
): Modifier = composed {
    DisposableEffect(registry, target) {
        onDispose { registry.remove(target) }
    }
    onGloballyPositioned { coordinates ->
        registry.update(target, coordinates.boundsInRoot())
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
internal fun FirstRunTutorialOverlay(
    stepIndex: Int,
    registry: TutorialAnchorRegistry,
    showCompletionSaveError: Boolean = false,
    onBack: () -> Unit,
    onNext: () -> Unit,
    onSkip: () -> Unit,
    onDone: () -> Unit,
    modifier: Modifier = Modifier
) {
    val safeIndex = stepIndex.coerceIn(FIRST_RUN_TUTORIAL_STEPS.indices)
    val step = FIRST_RUN_TUTORIAL_STEPS[safeIndex]
    val target = registry[step.target]
    val title = stringResource(step.titleRes)
    val body = stringResource(step.bodyRes)
    val stepCount = stringResource(
        R.string.tutorial_step_count,
        safeIndex + 1,
        FIRST_RUN_TUTORIAL_STEPS.size
    )
    val focusRequester = remember { FocusRequester() }
    val blockingInteraction = remember { MutableInteractionSource() }
    val haloColor = MaterialTheme.colorScheme.primary
    val density = LocalDensity.current

    LaunchedEffect(step.id) {
        focusRequester.requestFocus()
    }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .testTag("first_run_tutorial_overlay")
    ) {
        val haloPaddingPx = with(density) { 9.dp.toPx() }
        val haloRadiusPx = with(density) { 24.dp.toPx() }
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .clickable(
                    interactionSource = blockingInteraction,
                    indication = null,
                    onClick = {}
                )
        ) {
            val safeTarget = target?.let { bounds ->
                Rect(
                    left = (bounds.left - haloPaddingPx).coerceAtLeast(0f),
                    top = (bounds.top - haloPaddingPx).coerceAtLeast(0f),
                    right = (bounds.right + haloPaddingPx).coerceAtMost(size.width),
                    bottom = (bounds.bottom + haloPaddingPx).coerceAtMost(size.height)
                )
            }
            val scrim = Path().apply {
                fillType = PathFillType.EvenOdd
                addRect(Rect(Offset.Zero, size))
                safeTarget?.let { bounds ->
                    addRoundRect(
                        RoundRect(bounds, CornerRadius(haloRadiusPx, haloRadiusPx))
                    )
                }
            }
            drawPath(scrim, Color.Black.copy(alpha = 0.72f))
            safeTarget?.let { bounds ->
                drawRoundRect(
                    color = haloColor,
                    topLeft = bounds.topLeft,
                    size = Size(bounds.width, bounds.height),
                    cornerRadius = CornerRadius(haloRadiusPx, haloRadiusPx),
                    style = Stroke(width = with(density) { 3.dp.toPx() })
                )
            }
        }

        val targetIsInTopHalf = target?.center?.y?.let { centerY ->
            centerY < constraints.maxHeight / 2f
        } ?: false
        val cardAlignment = when {
            target == null -> Alignment.Center
            targetIsInTopHalf -> Alignment.BottomCenter
            else -> Alignment.TopCenter
        }
        Surface(
            modifier = Modifier
                .align(cardAlignment)
                .padding(
                    horizontal = GymSpacing.Large,
                    vertical = GymSpacing.XXLarge
                )
                .widthIn(max = 520.dp)
                .fillMaxWidth()
                .heightIn(max = maxHeight * 0.58f)
                .focusRequester(focusRequester)
                .focusProperties {
                    exit = { FocusRequester.Cancel }
                }
                .focusGroup()
                .focusable()
                .semantics(mergeDescendants = false) {
                    dialog()
                    paneTitle = title
                    liveRegion = LiveRegionMode.Assertive
                    contentDescription = "$stepCount. $title. $body"
                }
                .testTag("first_run_tutorial_card"),
            shape = RoundedCornerShape(28.dp),
            color = MaterialTheme.colorScheme.surface,
            contentColor = MaterialTheme.colorScheme.onSurface,
            tonalElevation = 6.dp,
            shadowElevation = 10.dp
        ) {
            Column(
                modifier = Modifier
                    .verticalScroll(rememberScrollState())
                    .padding(GymSpacing.XLarge),
                verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
            ) {
                Text(
                    text = stepCount,
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary
                )
                Text(
                    text = title,
                    modifier = Modifier.semantics { heading() },
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = body,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (showCompletionSaveError) {
                    Text(
                        text = stringResource(R.string.tutorial_completion_save_failed),
                        modifier = Modifier.semantics {
                            liveRegion = LiveRegionMode.Assertive
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(GymSpacing.Small),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(
                        onClick = onSkip,
                        modifier = Modifier.heightIn(min = GymSpacing.MinimumTouch)
                    ) {
                        Text(stringResource(R.string.tutorial_skip))
                    }
                    OutlinedButton(
                        onClick = onBack,
                        enabled = safeIndex > 0,
                        modifier = Modifier
                            .weight(1f)
                            .heightIn(min = GymSpacing.MinimumTouch)
                    ) {
                        Text(stringResource(R.string.tutorial_back))
                    }
                    Button(
                        onClick = if (safeIndex == FIRST_RUN_TUTORIAL_STEPS.lastIndex) {
                            onDone
                        } else {
                            onNext
                        },
                        modifier = Modifier
                            .weight(1f)
                            .heightIn(min = GymSpacing.MinimumTouch)
                    ) {
                        Text(
                            stringResource(
                                if (safeIndex == FIRST_RUN_TUTORIAL_STEPS.lastIndex) {
                                    R.string.tutorial_done
                                } else {
                                    R.string.tutorial_next
                                }
                            )
                        )
                    }
                }
            }
        }
    }
}
