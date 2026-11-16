package com.example.gymapp.billing

import com.android.billingclient.api.BillingClient.BillingResponseCode

/** The six optional tip products, in display order. Mirrors `shared/support-tips-v1.json` (`android` ids). */
object SupportTipProducts {
    val ids: List<String> = listOf(
        "support_tip_1",
        "support_tip_2",
        "support_tip_3",
        "support_tip_5",
        "support_tip_10",
        "support_tip_20"
    )

    /** The chip selected first: the third amount (about 3 USD). */
    const val DEFAULT_SELECTED_INDEX = 2
}

/** What a Play Billing response code means for the tip screen. */
enum class SupportTipOutcome { Proceed, Cancelled, NoNetwork, Unavailable, AlreadyOwned, Generic }

/** Maps a [BillingResponseCode] to the screen outcome. Pure and table-tested. */
fun mapSupportTipResponse(code: Int): SupportTipOutcome = when (code) {
    BillingResponseCode.OK -> SupportTipOutcome.Proceed
    BillingResponseCode.USER_CANCELED -> SupportTipOutcome.Cancelled
    BillingResponseCode.SERVICE_UNAVAILABLE,
    BillingResponseCode.NETWORK_ERROR -> SupportTipOutcome.NoNetwork
    BillingResponseCode.BILLING_UNAVAILABLE,
    BillingResponseCode.FEATURE_NOT_SUPPORTED,
    BillingResponseCode.ITEM_UNAVAILABLE,
    BillingResponseCode.DEVELOPER_ERROR,
    BillingResponseCode.SERVICE_DISCONNECTED -> SupportTipOutcome.Unavailable
    BillingResponseCode.ITEM_ALREADY_OWNED -> SupportTipOutcome.AlreadyOwned
    else -> SupportTipOutcome.Generic
}

/** The chip index to preselect for [count] loaded products (the third, or the last when fewer). */
fun defaultSupportTipIndex(count: Int): Int =
    if (count <= 0) 0 else minOf(SupportTipProducts.DEFAULT_SELECTED_INDEX, count - 1)

enum class SupportTipPhase { Loading, Ready, Unavailable, Offline }

/** A short inline note under the button; cancel has none. */
enum class SupportTipMessage { NoNetwork, Pending, Generic }

/** One loaded tip: the store product id and its localized price string. */
data class SupportTipChip(val productId: String, val formattedPrice: String)

data class SupportTipUiState(
    val phase: SupportTipPhase = SupportTipPhase.Loading,
    val chips: List<SupportTipChip> = emptyList(),
    val selectedIndex: Int = 0,
    val purchaseInFlight: Boolean = false,
    val showThanks: Boolean = false,
    val message: SupportTipMessage? = null
) {
    val selectedChip: SupportTipChip? get() = chips.getOrNull(selectedIndex)
}
