package com.skyapp.personal_ledger

import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : FlutterActivity() {
    private val smartQuickLedgerChannel = "personal_ledger/smart_quick_ledger"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preferHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        preferHighestRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            smartQuickLedgerChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationListenerEnabled" ->
                    result.success(isNotificationListenerEnabled())
                "openNotificationListenerSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "getPendingDrafts" ->
                    result.success(jsonArrayToList(SmartQuickLedgerStore.getDrafts(this)))
                "dismissDraft" -> {
                    val id = call.argument<String>("id").orEmpty()
                    SmartQuickLedgerStore.dismissDraft(this, id)
                    result.success(null)
                }
                "getEnabledSources" ->
                    result.success(SmartQuickLedgerStore.getEnabledSources(this).toList())
                "setEnabledSources" -> {
                    val sources = call.argument<List<String>>("sources") ?: emptyList()
                    SmartQuickLedgerStore.setEnabledSources(this, sources.toSet())
                    result.success(null)
                }
                "debugInjectPaymentNotification" -> {
                    if (!isDebuggable()) {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                    val packageName = call.argument<String>("packageName").orEmpty()
                    val title = call.argument<String>("title").orEmpty()
                    val text = call.argument<String>("text").orEmpty()
                    val postedAtMillis = call.argument<Long>("postedAtMillis")
                        ?: System.currentTimeMillis()
                    val draft = SmartQuickLedgerDebugTools.injectNotificationDraft(
                        context = this,
                        packageName = packageName,
                        title = title,
                        text = text,
                        postedAtMillis = postedAtMillis,
                    )
                    if (draft == null) {
                        result.error("unrecognized_notification", "Notification was not parsed", null)
                    } else {
                        result.success(jsonObjectToMap(draft))
                    }
                }
                "debugClearPaymentNotifications" -> {
                    if (!isDebuggable()) {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                    SmartQuickLedgerStore.clearDrafts(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun preferHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }
        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        } ?: return
        val modes = currentDisplay.supportedModes
        val preferredMode = modes.maxByOrNull { it.refreshRate } ?: return
        val params = window.attributes
        if (params.preferredDisplayModeId == preferredMode.modeId) {
            return
        }
        params.preferredDisplayModeId = preferredMode.modeId
        window.attributes = params
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val enabledListeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val component = ComponentName(this, LedgerNotificationListenerService::class.java)
        val flattened = component.flattenToString()
        val names = TextUtils.split(enabledListeners, ":")
        return names.any { it.equals(flattened, ignoreCase = true) }
    }

    private fun isDebuggable(): Boolean {
        return applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    }

    private fun jsonArrayToList(array: JSONArray): List<Map<String, Any?>> {
        val items = mutableListOf<Map<String, Any?>>()
        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            items.add(jsonObjectToMap(item))
        }
        return items
    }

    private fun jsonObjectToMap(item: org.json.JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = item.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = item.opt(key)
        }
        return map
    }
}
