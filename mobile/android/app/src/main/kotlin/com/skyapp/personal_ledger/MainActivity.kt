package com.skyapp.personal_ledger

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preferHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        preferHighestRefreshRate()
    }

    private fun preferHighestRefreshRate() {
        val modes = windowManager.defaultDisplay.supportedModes
        val preferredMode = modes.maxByOrNull { it.refreshRate } ?: return
        val params = window.attributes
        if (params.preferredDisplayModeId == preferredMode.modeId) {
            return
        }
        params.preferredDisplayModeId = preferredMode.modeId
        window.attributes = params
    }
}
