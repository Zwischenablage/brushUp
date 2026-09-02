package com.brushup.snapgatekeeper

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts the gateway service after a reboot, so the block survives a
 * restart without needing the app opened by hand. The accessibility
 * service itself is restarted automatically by the system if it was
 * enabled - this only concerns the polling foreground service.
 */
class BootCompletedReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        if (GatekeeperConfig.isServiceEnabled(context)) {
            BlockerForegroundService.start(context)
        }
    }
}
