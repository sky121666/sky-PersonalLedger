package com.skyapp.personal_ledger

import android.content.Context
import org.json.JSONObject

object SmartQuickLedgerDebugTools {
    fun injectNotificationDraft(
        context: Context,
        packageName: String,
        title: String,
        text: String,
        postedAtMillis: Long = System.currentTimeMillis(),
    ): JSONObject? {
        val draft = PaymentNotificationParser.parse(
            packageName = packageName,
            title = title,
            text = text,
            postedAtMillis = postedAtMillis,
        ) ?: return null
        SmartQuickLedgerStore.addDraft(context, draft)
        return draft
    }
}
