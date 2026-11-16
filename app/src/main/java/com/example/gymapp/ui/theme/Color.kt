package com.example.gymapp.ui.theme

import androidx.compose.ui.graphics.Color

// Apple neutral system palette (spec 2026-11-15), same values on iOS. Neutrals are R=G=B (or at most
// +2 on blue): no navy or blue-tinted greys, no gradients. Text and small icons are >= 4.5:1 on every
// surface they sit on; filled-button labels and non-text marks are >= 3:1.

// ---- Light ----
/** Tint for fills, icons and marks (brand fill, accent mark, hero progress). */
val SystemBlue = Color(0xFF007AFF)
/** Accent text and `colorScheme.primary`: SystemBlue darkened to >= 4.6:1 on every light surface. */
val SystemBlueText = Color(0xFF0062CC)
val BlueSoft = Color(0xFFE5F0FF)
val Amber = Color(0xFFFF9500)
val AmberText = Color(0xFFBD3100)
val Paper = Color(0xFFFFFFFF)
val Canvas = Color(0xFFF2F2F7)
val Mist = Color(0xFFE5E5EA)
val Ink = Color(0xFF000000)
/** Secondary label: 4.69:1 on Canvas, 4.56:1 on Mist (the search / chip fill). */
val InkMuted = Color(0xFF666669)
val SeparatorLight = Color(0xFFC6C6C8)
/** Success / recovery as text; the system fill green #34C759 is only 2.0:1 on Canvas. */
val RecoveryGreen = Color(0xFF1C7430)
val MomentumViolet = Color(0xFF5856D6)
val DestructiveLight = Color(0xFFD70015)
val EffortCoral = Color(0xFFFF6961)

// ---- Dark ----
val Night = Color(0xFF000000)
val NightSurface = Color(0xFF1C1C1E)
val NightRaised = Color(0xFF2C2C2E)
val NightFill = Color(0xFF3A3A3C)
/** Raised pill of the segmented control on dark (iOS `GymTheme.segmentPill`): white label is 6.0:1. */
val NightSegmentPill = Color(0xFF636366)
val NightSeparator = Color(0xFF38383A)
val NightOutline = Color(0xFF545458)
val Frost = Color(0xFFFFFFFF)
/** Secondary label: 7.33:1 on Night, 5.94:1 on NightSurface, 4.86:1 on NightRaised. */
val FrostMuted = Color(0xFF98989F)
/** Tint for fills, icons and marks (brand fill, accent mark, hero progress). */
val SystemBlueNight = Color(0xFF0A84FF)
/** Accent text and `colorScheme.primary`: 4.92:1 on NightRaised (SystemBlueNight is 3.82:1 there). */
val SystemBlueTextNight = Color(0xFF409CFF)
/**
 * Opaque tinted accent fill (`primaryContainer`, iOS `GymTheme.primarySoft`): SystemBlueNight at 20%
 * over NightSurface. Accent text (SystemBlueTextNight) is 4.69:1 on it; the former #183554 was 4.43:1.
 */
val BlueSoftNight = Color(0xFF18314B)
val RecoveryGreenNight = Color(0xFF30D158)
val MomentumVioletFill = Color(0xFF5E5CE6)
/** Violet as text and icon on dark: 5.95:1 on NightSurface, 4.87:1 on NightRaised (#7D7AFF was 4.06:1 there). */
val MomentumVioletNight = Color(0xFF8E8CFF)
val AmberNight = Color(0xFFFF9F0A)
/** Error as text and icon on dark surfaces (the system red #FF453A is 4.09:1 on NightRaised). */
val DestructiveNight = Color(0xFFFF6961)
val OnDestructiveNight = Color(0xFF000000)
// `accent-mark` (dark): chart lines, rings and progress fills. `accent-mark` light is SystemBlue;
// `accent-text` per appearance is colorScheme.primary.
val AccentMarkNight = SystemBlueNight

// Brand fill shared with iOS: the solid primary-action blue per appearance, white label
// (4.02:1 light, 3.65:1 dark; both are filled-button labels, >= 3:1).
val BrandFill = SystemBlue
val BrandFillNight = SystemBlueNight

// Flat tonal hero surface shared with iOS (`GymTheme.heroSurface`) and the PWA (`--hero-surface`).
// Every hero or brand card is one solid fill with a hairline outline; the primary action inside is a
// solid brand-blue capsule. Text pairs: title >= 17:1, supporting >= 4.86:1 on the surface and tile,
// accent text >= 4.9:1 on the surface and tile.
val HeroSurface = Paper
val HeroSurfaceNight = NightSurface
val HeroOutline = Mist
val HeroOutlineNight = NightSeparator
val HeroTitle = Ink
val HeroTitleNight = Frost
val HeroSupporting = InkMuted
val HeroSupportingNight = FrostMuted
// Inner tiles sit inside the hero surface: Canvas inside the white card, NightRaised inside NightSurface.
val HeroTile = Canvas
val HeroTileNight = NightRaised
val HeroAccent = SystemBlue
val HeroActionLabel = SystemBlueText
val HeroAccentText = SystemBlueText
val HeroAccentNight = SystemBlueNight
// Emphasised value and action labels on the dark hero are the text-safe blue.
val HeroAccentTextNight = SystemBlueTextNight
val HeroActionLabelNight = SystemBlueTextNight
