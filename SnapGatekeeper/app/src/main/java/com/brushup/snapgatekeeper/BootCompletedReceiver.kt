package com.brushup.snapgatekeeper

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-arms suspension and restarts the gateway service after a reboot, so
 * the block survives a restart without needing the app opened by hand.
 */
class BootCompletedReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        PackageBlocker.applySuspension(context)

        if (GatekeeperConfig.isServiceEnabled(context)) {
            BlockerForegroundService.start(context)
        }
    }
}
