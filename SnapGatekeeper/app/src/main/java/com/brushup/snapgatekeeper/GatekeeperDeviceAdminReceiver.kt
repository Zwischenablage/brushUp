package com.brushup.snapgatekeeper

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Required receiver for both plain Device Admin and Device Owner mode.
 * Device Owner is what actually unlocks [android.app.admin.DevicePolicyManager.setPackagesSuspended],
 * which is the only reliable, non-root way for a third-party app to stop
 * another app from launching at all. It is granted from a host machine via:
 *
 *   adb shell dpm set-device-owner com.brushup.snapgatekeeper/.GatekeeperDeviceAdminReceiver
 *
 * (only works while the device has no user accounts added yet).
 */
class GatekeeperDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(TAG, "Device admin enabled")
        PackageBlocker.applySuspension(context)
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.i(TAG, "Device admin disabled")
    }

    companion object {
        private const val TAG = "GatekeeperAdmin"
    }
}
