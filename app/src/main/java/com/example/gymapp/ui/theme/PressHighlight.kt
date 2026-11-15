package com.example.gymapp.ui.theme

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.interaction.FocusInteraction
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import kotlinx.coroutines.launch

/** Peak alpha of the press tint over the control (on the content colour). */
internal const val PressHighlightAlpha = 0.08f

/** Alpha of the steady focus tint (keyboard / TalkBack / switch focus), so focus never disappears. */
internal const val FocusHighlightAlpha = 0.06f

/**
 * App-wide indication that replaces the Material ripple: a flat [color] tint appears the instant a
 * press starts and fades out softly on release or cancel (a scroll cancels the press, so the tint
 * drops as soon as a list starts moving). A focused control keeps a steady, fainter tint.
 */
internal class PressHighlight(private val color: Color) : IndicationNodeFactory {
    override fun create(interactionSource: InteractionSource): DelegatableNode = Node(interactionSource, color)

    override fun equals(other: Any?): Boolean = other is PressHighlight && other.color == color

    override fun hashCode(): Int = color.hashCode()

    private class Node(
        private val source: InteractionSource,
        private val color: Color
    ) : Modifier.Node(), DrawModifierNode {
        private val pressLevel = Animatable(0f)
        private val focusLevel = Animatable(0f)

        override fun onAttach() {
            coroutineScope.launch {
                source.interactions.collect { interaction ->
                    when (interaction) {
                        is PressInteraction.Press -> launch { pressLevel.snapTo(1f) }
                        is PressInteraction.Release, is PressInteraction.Cancel ->
                            launch { pressLevel.animateTo(0f, tween(durationMillis = 250)) }
                        is FocusInteraction.Focus -> launch { focusLevel.snapTo(1f) }
                        is FocusInteraction.Unfocus -> launch { focusLevel.animateTo(0f, tween(durationMillis = 150)) }
                    }
                }
            }
        }

        override fun ContentDrawScope.draw() {
            drawContent()
            val alpha = maxOf(pressLevel.value * PressHighlightAlpha, focusLevel.value * FocusHighlightAlpha)
            if (alpha > 0f) drawRect(color.copy(alpha = alpha))
        }
    }
}
