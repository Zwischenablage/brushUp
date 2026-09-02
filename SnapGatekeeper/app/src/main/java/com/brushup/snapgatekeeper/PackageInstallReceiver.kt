package com.brushup.snapgatekeeper

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Without Device Owner there's no "suspended" state to lose, but a fresh
 * (re)install of the target app can auto-launch (e.g. a "set up now"
 * first-run flow triggered by the Play Store) before the accessibility
 * service or the polling loop notices it. Reacting to the install
 * broadcast directly closes most of that gap.
 *
 * PACKAGE_ADDED / PACKAGE_REPLACED are among the broadcasts explicitly
 * exempted from Android 8+'s implicit-broadcast restrictions, so this
 * manifest-registered receiver fires even if the app has no running
 * process and nothing else is on screen.
 */
class PackageInstallReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_PACKAGE_ADDED, Intent.ACTION_PACKAGE_REPLACED -> {
                val installedPackage = intent.data?.schemeSpecificPart ?: return
                val target = GatekeeperConfig.targetPackage(context)
                if (installedPackage != target) return

                Log.i(TAG, "$target was (re)installed; killing any background process")
                PackageBlocker.killBackgroundProcess(context, target)

                // Make sure the redundant polling/watchdog path is running too,
                // in case it was previously stopped for any reason.
                if (GatekeeperConfig.isServiceEnabled(context)) {
                    BlockerForegroundService.start(context)
                }
            }
        }
    }

    companion object {
        private const val TAG = "PackageInstallReceiver"
    }
}
