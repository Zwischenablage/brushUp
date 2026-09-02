package com.brushup.snapgatekeeper

import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.util.Log

/**
 * Central place that actually stops the target package from running.
 *
 * There are two tiers, applied in order of strength:
 *  1. Device Owner suspension (DevicePolicyManager#setPackagesSuspended) -
 *     the real "prevent it from starting at all" switch. The system refuses
 *     to launch a suspended package and shows its own blocked-app dialog.
 *     Requires this app to be Device Owner, set up once via adb.
 *  2. Best-effort process kill (ActivityManager#killBackgroundProcesses) -
 *     works without Device Owner but only reaches background processes;
 *     it cannot stop a package that is already in the foreground, which is
 *     why the accessibility watchdog additionally sends the user home the
 *     instant the target's window appears.
 */
object PackageBlocker {

    private const val TAG = "PackageBlocker"

    fun isDeviceOwner(context: Context): Boolean {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return dpm.isDeviceOwnerApp(context.packageName)
    }

    /** Re-asserts suspension for the configured target package. Safe to call repeatedly. */
    fun applySuspension(context: Context): Boolean {
        val target = GatekeeperConfig.targetPackage(context)
        if (!isDeviceOwner(context)) {
            Log.w(TAG, "Not device owner; cannot suspend $target")
            return false
        }
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(context, GatekeeperDeviceAdminReceiver::class.java)
        return try {
            val failed = dpm.setPackagesSuspended(admin, arrayOf(target), true)
            if (failed.isNotEmpty()) {
                Log.w(TAG, "Package(s) not suspended (not installed?): ${failed.joinToString()}")
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "setPackagesSuspended failed", e)
            false
        }
    }

    fun isSuspended(context: Context): Boolean {
        if (!isDeviceOwner(context)) return false
        val target = GatekeeperConfig.targetPackage(context)
        return try {
            context.packageManager.isPackageSuspended(target)
        } catch (e: Exception) {
            false
        }
    }

    /** Lifts suspension, e.g. if the user disables blocking from the UI. */
    fun clearSuspension(context: Context) {
        if (!isDeviceOwner(context)) return
        val target = GatekeeperConfig.targetPackage(context)
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(context, GatekeeperDeviceAdminReceiver::class.java)
        try {
            dpm.setPackagesSuspended(admin, arrayOf(target), false)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear suspension", e)
        }
    }

    /**
     * Best-effort kill for when this app is not Device Owner. Only affects
     * background processes of [packageName]; Android does not let a normal
     * app force-stop another app's foreground process.
     */
    fun killBackgroundProcess(context: Context, packageName: String) {
        try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.killBackgroundProcesses(packageName)
        } catch (e: SecurityException) {
            Log.w(TAG, "killBackgroundProcesses denied for $packageName", e)
        }
    }
}
