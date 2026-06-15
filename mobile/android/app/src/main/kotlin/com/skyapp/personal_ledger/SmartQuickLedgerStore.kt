package com.skyapp.personal_ledger

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object SmartQuickLedgerStore {
    private const val PREFS_NAME = "smart_quick_ledger"
    private const val DRAFTS_KEY = "drafts"
    private const val SOURCES_KEY = "enabled_sources"
    private const val MAX_DRAFTS = 50

    private val defaultSources = setOf("wechat", "alipay", "bank")

    fun getDrafts(context: Context): JSONArray {
        val raw = prefs(context).getString(DRAFTS_KEY, "[]") ?: "[]"
        return runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
    }

    fun addDraft(context: Context, draft: JSONObject) {
        val hash = draft.optString("notification_hash")
        if (hash.isBlank()) {
            return
        }
        val current = getDrafts(context)
        val next = JSONArray()
        next.put(draft)
        for (index in 0 until current.length()) {
            val item = current.optJSONObject(index) ?: continue
            if (item.optString("notification_hash") == hash) {
                continue
            }
            if (next.length() < MAX_DRAFTS) {
                next.put(item)
            }
        }
        prefs(context).edit().putString(DRAFTS_KEY, next.toString()).apply()
    }

    fun dismissDraft(context: Context, id: String) {
        val current = getDrafts(context)
        val next = JSONArray()
        for (index in 0 until current.length()) {
            val item = current.optJSONObject(index) ?: continue
            if (item.optString("id") != id) {
                next.put(item)
            }
        }
        prefs(context).edit().putString(DRAFTS_KEY, next.toString()).apply()
    }

    fun getEnabledSources(context: Context): Set<String> {
        return prefs(context).getStringSet(SOURCES_KEY, defaultSources) ?: defaultSources
    }

    fun setEnabledSources(context: Context, sources: Set<String>) {
        prefs(context).edit().putStringSet(SOURCES_KEY, sources).apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
