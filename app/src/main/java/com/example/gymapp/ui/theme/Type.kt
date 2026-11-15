package com.example.gymapp.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val GymDataTypography = TextStyle(
    fontFeatureSettings = "tnum",
    fontFamily = FontFamily.SansSerif,
    fontWeight = FontWeight.SemiBold,
    fontSize = 14.sp,
    lineHeight = 18.sp,
    letterSpacing = 0.sp
)

/*
 * Apple-like scale on the system face (Roboto), tuned for Cyrillic. Hierarchy comes from size and weight
 * together; sizes sit far apart: 34 / 22 / 20 / 17 / 16 / 15 / 13 / 12. Tracking is 0 from 13 to 17sp;
 * only the 34sp and 22sp titles tighten (-0.02em / -0.01em) and 12sp caption loosens by 0.1sp.
 * Numbers that change in place (timers, set values) opt in to [GymDataTypography]'s `tnum`.
 */
private fun appleStyle(
    weight: FontWeight,
    size: Int,
    line: Int,
    tracking: Float = 0f
) = TextStyle(
    fontFamily = FontFamily.SansSerif,
    fontWeight = weight,
    fontSize = size.sp,
    lineHeight = line.sp,
    letterSpacing = tracking.sp
)

/** Large title: one per screen, the only Bold in the scale. */
private val LargeTitle = appleStyle(FontWeight.Bold, 34, 41, -0.68f)

/** Section and card title. */
private val Title2 = appleStyle(FontWeight.SemiBold, 22, 28, -0.22f)

/** Sheet and large row title. */
private val Title3 = appleStyle(FontWeight.SemiBold, 20, 25)

/** Navigation title, emphasised row title, button label. */
private val Headline = appleStyle(FontWeight.SemiBold, 17, 22)

/** Reading text and row titles. */
private val Body = appleStyle(FontWeight.Normal, 17, 22)

/** Emphasised secondary line (16sp keeps long Russian words from over-wrapping). */
private val CalloutSemibold = appleStyle(FontWeight.SemiBold, 16, 21)

/** Secondary text under a title. */
private val Subhead = appleStyle(FontWeight.Normal, 15, 20)
private val SubheadMedium = appleStyle(FontWeight.Medium, 15, 20)

/** Row labels, section headers and footers. */
private val Footnote = appleStyle(FontWeight.Normal, 13, 18)
private val FootnoteMedium = appleStyle(FontWeight.Medium, 13, 18)

/** Chart axes and timestamps: the minimum size in the app. */
private val CaptionMedium = appleStyle(FontWeight.Medium, 12, 16, 0.1f)

val Typography = Typography(
    displayLarge = LargeTitle,
    displayMedium = LargeTitle,
    displaySmall = Title2,
    headlineLarge = LargeTitle,
    headlineMedium = Title2,
    headlineSmall = Title3,
    titleLarge = Title2,
    titleMedium = Headline,
    titleSmall = CalloutSemibold,
    bodyLarge = Body,
    bodyMedium = Subhead,
    bodySmall = Footnote,
    labelLarge = SubheadMedium,
    labelMedium = FootnoteMedium,
    labelSmall = CaptionMedium
)
