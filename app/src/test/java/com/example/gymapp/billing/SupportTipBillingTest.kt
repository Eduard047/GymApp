package com.example.gymapp.billing

import com.android.billingclient.api.BillingClient.BillingResponseCode
import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class SupportTipBillingTest {
    private fun fixture(): JSONObject {
        val direct = File("shared/support-tips-v1.json")
        val file = if (direct.isFile) direct else File("../shared/support-tips-v1.json")
        return JSONObject(file.readText())
    }

    @Test
    fun productIdsMatchSharedFixtureInOrder() {
        val tips = fixture().getJSONArray("tips")
        val ids = (0 until tips.length()).map { tips.getJSONObject(it).getString("android") }
        assertEquals(ids, SupportTipProducts.ids)
        assertEquals(6, SupportTipProducts.ids.size)
    }

    @Test
    fun responseCodesMapToOutcomes() {
        val table = listOf(
            BillingResponseCode.OK to SupportTipOutcome.Proceed,
            BillingResponseCode.USER_CANCELED to SupportTipOutcome.Cancelled,
            BillingResponseCode.SERVICE_UNAVAILABLE to SupportTipOutcome.NoNetwork,
            BillingResponseCode.NETWORK_ERROR to SupportTipOutcome.NoNetwork,
            BillingResponseCode.BILLING_UNAVAILABLE to SupportTipOutcome.Unavailable,
            BillingResponseCode.FEATURE_NOT_SUPPORTED to SupportTipOutcome.Unavailable,
            BillingResponseCode.ITEM_UNAVAILABLE to SupportTipOutcome.Unavailable,
            BillingResponseCode.DEVELOPER_ERROR to SupportTipOutcome.Unavailable,
            BillingResponseCode.SERVICE_DISCONNECTED to SupportTipOutcome.Unavailable,
            BillingResponseCode.ITEM_ALREADY_OWNED to SupportTipOutcome.AlreadyOwned,
            BillingResponseCode.ERROR to SupportTipOutcome.Generic,
            BillingResponseCode.ITEM_NOT_OWNED to SupportTipOutcome.Generic,
            BillingResponseCode.SERVICE_TIMEOUT to SupportTipOutcome.Generic,
            12345 to SupportTipOutcome.Generic
        )
        table.forEach { (code, expected) ->
            assertEquals("code $code", expected, mapSupportTipResponse(code))
        }
    }

    @Test
    fun defaultChipIsTheThirdOrTheLastWhenFewer() {
        assertEquals(2, defaultSupportTipIndex(6))
        assertEquals(2, defaultSupportTipIndex(3))
        assertEquals(1, defaultSupportTipIndex(2))
        assertEquals(0, defaultSupportTipIndex(1))
        assertEquals(0, defaultSupportTipIndex(0))
    }
}
