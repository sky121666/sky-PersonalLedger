package com.skyapp.personal_ledger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class SmartQuickLedgerDebugReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) {
            return
        }
        if (intent.getBooleanExtra("clear", false)) {
            SmartQuickLedgerStore.clearDrafts(context)
            Log.i(TAG, "Cleared smart quick ledger debug drafts")
            return
        }

        val packageName = intent.getStringExtra("packageName") ?: "com.tencent.mm"
        val title = intent.getStringExtra("title") ?: "微信支付"
        val text = intent.getStringExtra("text") ?: "付款给 瑞幸咖啡 ￥38.90"
        val postedAtMillis = intent.getLongExtra("postedAtMillis", System.currentTimeMillis())
        val draft = SmartQuickLedgerDebugTools.injectNotificationDraft(
            context = context,
            packageName = packageName,
            title = title,
            text = text,
            postedAtMillis = postedAtMillis,
        )
        val draftId = draft?.optString("id") ?: "null"
        Log.i(TAG, "Injected smart quick ledger draft: $draftId")
    }

    private companion object {
        const val ACTION = "com.skyapp.personal_ledger.DEBUG_SMART_QUICK_LEDGER"
        const val TAG = "SmartQuickLedgerDebug"
    }
}
