package com.example.gymapp.billing

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * Owns the Play [BillingClient] for the optional tip screen. Tips are consumable and unlock nothing:
 * there is no server validation, and purchase tokens are used only to consume and never logged.
 * The connection opens lazily with [open] when the screen appears and ends with [close]. All
 * callbacks arrive on the main thread, so [state] is only written from there.
 */
class SupportTipBilling(context: Context) {
    private val appContext = context.applicationContext
    private val _state = MutableStateFlow(SupportTipUiState())
    val state: StateFlow<SupportTipUiState> = _state.asStateFlow()

    private var client: BillingClient? = null
    private var details: Map<String, ProductDetails> = emptyMap()

    private val purchasesListener = PurchasesUpdatedListener { result, purchases ->
        when (mapSupportTipResponse(result.responseCode)) {
            SupportTipOutcome.Proceed -> {
                val tips = purchases.orEmpty().filter(::isTip)
                if (tips.isEmpty()) endPurchase(null) else tips.forEach { handle(it, userInitiated = true) }
            }
            SupportTipOutcome.Cancelled -> endPurchase(null)
            SupportTipOutcome.AlreadyOwned -> {
                // A tip that was never consumed blocks a new one: clear it, then the button works again.
                consumeLeftovers()
                endPurchase(null)
            }
            SupportTipOutcome.NoNetwork -> endPurchase(SupportTipMessage.NoNetwork)
            SupportTipOutcome.Unavailable -> {
                _state.update { it.copy(phase = SupportTipPhase.Unavailable, purchaseInFlight = false) }
            }
            SupportTipOutcome.Generic -> endPurchase(SupportTipMessage.Generic)
        }
    }

    /** Connects (if needed) and loads the six products; also consumes any tip left unconsumed by a crash. */
    fun open() {
        if (client != null) return
        _state.value = SupportTipUiState()
        val built = BillingClient.newBuilder(appContext)
            .setListener(purchasesListener)
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .build()
        client = built
        built.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (client !== built) return
                when (mapSupportTipResponse(result.responseCode)) {
                    SupportTipOutcome.Proceed -> {
                        loadProducts(built)
                        consumeLeftovers()
                    }
                    SupportTipOutcome.NoNetwork -> failLoad(SupportTipPhase.Offline)
                    else -> failLoad(SupportTipPhase.Unavailable)
                }
            }

            override fun onBillingServiceDisconnected() {
                if (client !== built) return
                if (_state.value.phase == SupportTipPhase.Loading) failLoad(SupportTipPhase.Unavailable)
            }
        })
    }

    /** Ends the connection; call when the screen leaves. */
    fun close() {
        client?.endConnection()
        client = null
        details = emptyMap()
        _state.value = SupportTipUiState()
    }

    fun select(index: Int) {
        _state.update { if (index in it.chips.indices) it.copy(selectedIndex = index, message = null) else it }
    }

    fun dismissThanks() {
        _state.update { it.copy(showThanks = false) }
    }

    /** Opens the Play purchase sheet for the selected amount. */
    fun purchase(activity: Activity) {
        val current = _state.value
        val chip = current.selectedChip ?: return
        val product = details[chip.productId] ?: return
        val active = client ?: return
        if (current.purchaseInFlight || current.phase != SupportTipPhase.Ready) return
        _state.update { it.copy(purchaseInFlight = true, message = null) }
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(product)
                        .build()
                )
            )
            .build()
        val result = active.launchBillingFlow(activity, params)
        // OK means the sheet is up; its outcome arrives on the purchases listener.
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            when (mapSupportTipResponse(result.responseCode)) {
                SupportTipOutcome.Cancelled -> endPurchase(null)
                SupportTipOutcome.NoNetwork -> endPurchase(SupportTipMessage.NoNetwork)
                SupportTipOutcome.Unavailable ->
                    _state.update { it.copy(phase = SupportTipPhase.Unavailable, purchaseInFlight = false) }
                SupportTipOutcome.AlreadyOwned -> {
                    consumeLeftovers()
                    endPurchase(null)
                }
                else -> endPurchase(SupportTipMessage.Generic)
            }
        }
    }

    private fun loadProducts(active: BillingClient) {
        val products = SupportTipProducts.ids.map {
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(it)
                .setProductType(BillingClient.ProductType.INAPP)
                .build()
        }
        active.queryProductDetailsAsync(
            QueryProductDetailsParams.newBuilder().setProductList(products).build()
        ) { result, queryResult ->
            if (client !== active) return@queryProductDetailsAsync
            when (mapSupportTipResponse(result.responseCode)) {
                SupportTipOutcome.Proceed -> {
                    val byId = queryResult.productDetailsList.associateBy { it.productId }
                    val chips = SupportTipProducts.ids.mapNotNull { id ->
                        val price = byId[id]?.oneTimePurchaseOfferDetails?.formattedPrice
                        if (price.isNullOrBlank()) null else SupportTipChip(id, price)
                    }
                    details = byId
                    if (chips.isEmpty()) {
                        // Not configured in the store yet: same as purchases being unavailable.
                        failLoad(SupportTipPhase.Unavailable)
                    } else {
                        _state.update {
                            it.copy(
                                phase = SupportTipPhase.Ready,
                                chips = chips,
                                selectedIndex = defaultSupportTipIndex(chips.size)
                            )
                        }
                    }
                }
                SupportTipOutcome.NoNetwork -> failLoad(SupportTipPhase.Offline)
                else -> failLoad(SupportTipPhase.Unavailable)
            }
        }
    }

    private fun consumeLeftovers() {
        val active = client ?: return
        active.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()
        ) { result, purchases ->
            if (result.responseCode != BillingClient.BillingResponseCode.OK) return@queryPurchasesAsync
            purchases.filter(::isTip).forEach { handle(it, userInitiated = false) }
        }
    }

    private fun handle(purchase: Purchase, userInitiated: Boolean) {
        when (purchase.purchaseState) {
            Purchase.PurchaseState.PURCHASED -> consume(purchase, userInitiated)
            Purchase.PurchaseState.PENDING -> if (userInitiated) endPurchase(SupportTipMessage.Pending)
            else -> if (userInitiated) endPurchase(null)
        }
    }

    private fun consume(purchase: Purchase, userInitiated: Boolean) {
        val active = client ?: return
        val params = ConsumeParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
        active.consumeAsync(params) { _, _ ->
            if (!userInitiated) return@consumeAsync
            // The payment went through either way. A failed consume only delays reuse of this amount;
            // the next screen open consumes it again, so never tell the user the purchase failed.
            _state.update { it.copy(purchaseInFlight = false, showThanks = true, message = null) }
        }
    }

    private fun isTip(purchase: Purchase): Boolean = purchase.products.any { it in SupportTipProducts.ids }

    private fun endPurchase(message: SupportTipMessage?) {
        _state.update { it.copy(purchaseInFlight = false, message = message) }
    }

    private fun failLoad(phase: SupportTipPhase) {
        _state.update { it.copy(phase = phase, chips = emptyList(), purchaseInFlight = false) }
    }
}
