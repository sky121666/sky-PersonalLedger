package com.skyapp.personal_ledger

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentNotificationParserTest {
    @Test
    fun parsesWechatExpenseNotification() {
        val draft = PaymentNotificationParser.parseFields(
            packageName = "com.tencent.mm",
            title = "微信支付",
            text = "付款给 瑞幸咖啡 ￥38.90",
            postedAtMillis = 1_800_000_000_000,
        )

        assertNotNull(draft)
        requireNotNull(draft)
        assertEquals("android_notification", draft.source)
        assertEquals("微信支付", draft.sourceName)
        assertEquals("wechat", draft.sourceId)
        assertEquals("expense", draft.type)
        assertEquals(38.9, draft.amount, 0.001)
        assertTrue(draft.merchant.contains("瑞幸咖啡"))
        assertTrue(draft.confidence >= 0.88)
    }

    @Test
    fun parsesAlipayIncomeNotification() {
        val draft = PaymentNotificationParser.parseFields(
            packageName = "com.eg.android.AlipayGphone",
            title = "支付宝到账",
            text = "你收到 王小明 转账 200.00元",
            postedAtMillis = 1_800_000_000_001,
        )

        assertNotNull(draft)
        requireNotNull(draft)
        assertEquals("支付宝", draft.sourceName)
        assertEquals("alipay", draft.sourceId)
        assertEquals("income", draft.type)
        assertEquals(200.0, draft.amount, 0.001)
    }

    @Test
    fun rejectsUnknownPackageAndUnknownType() {
        assertNull(
            PaymentNotificationParser.parseFields(
                packageName = "com.example.news",
                title = "新闻",
                text = "消费观察 38.90元",
                postedAtMillis = 1_800_000_000_002,
            ),
        )
        assertNull(
            PaymentNotificationParser.parseFields(
                packageName = "com.tencent.mm",
                title = "微信支付",
                text = "余额 38.90元",
                postedAtMillis = 1_800_000_000_003,
            ),
        )
    }

    @Test
    fun lowersConfidenceForNoisyBalanceText() {
        val draft = PaymentNotificationParser.parseFields(
            packageName = "com.cmbchina.ccd.pluto.cmbActivity",
            title = "招商银行",
            text = "消费 19.90元 当前余额 1200.00元",
            postedAtMillis = 1_800_000_000_004,
        )

        assertNotNull(draft)
        requireNotNull(draft)
        assertEquals("bank", draft.sourceId)
        assertEquals("expense", draft.type)
        assertEquals(19.9, draft.amount, 0.001)
        assertTrue(draft.confidence < 0.78)
    }
}
