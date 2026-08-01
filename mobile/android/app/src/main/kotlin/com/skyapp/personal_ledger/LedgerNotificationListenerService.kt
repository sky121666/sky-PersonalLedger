package com.skyapp.personal_ledger

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class LedgerNotificationListenerService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn?.notification ?: return
        val sourceId = PaymentNotificationParser.sourceId(sbn.packageName) ?: return
        if (!SmartQuickLedgerStore.getEnabledSources(this).contains(sourceId)) {
            return
        }

        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = listOf(
            extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty(),
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty(),
            extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().orEmpty(),
        ).filter { it.isNotBlank() }.distinct().joinToString(" ")

        val draft = PaymentNotificationParser.parse(
            packageName = sbn.packageName,
            title = title,
            text = text,
            postedAtMillis = sbn.postTime,
        ) ?: return
        SmartQuickLedgerStore.addDraft(this, draft)
    }
}
