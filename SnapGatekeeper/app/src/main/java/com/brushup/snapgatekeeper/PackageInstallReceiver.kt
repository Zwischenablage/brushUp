package com.brushup.snapgatekeeper

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Suspension is tied to the installed package, so an uninstall wipes it -
 * a freshly (re)installed Snapchat comes back unsuspended and could be
 * opened before the polling loop in [BlockerForegroundService] gets to it.
 *
 * PACKAGE_ADDED / PACKAGE_REPLACED are among the broadcasts explicitly
 * exempted from Android 8+'s implicit-broadcast restrictions, so this
 * manifest-registered receiver fires even if the app has no running
 * process and nothing else is on screen - covering "install/reinstall the
 * blocked app while the gatekeeper app itself was never opened".
 */
class PackageInstallReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_PACKAGE_ADDED, Intent.ACTION_PACKAGE_REPLACED -> {
                val installedPackage = intent.data?.schemeSpecificPart ?: return
                val target = GatekeeperConfig.targetPackage(context)
                if (installedPackage != target) return

                Log.i(TAG, "$target was (re)installed; re-applying suspension")
                PackageBlocker.applySuspension(context)

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
