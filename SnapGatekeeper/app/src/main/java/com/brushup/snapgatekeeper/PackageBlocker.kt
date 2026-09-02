package com.brushup.snapgatekeeper

import android.app.ActivityManager
import android.content.Context
import android.util.Log

/**
 * Deliberately non-invasive: this app is a normal, sideloaded app with no
 * Device Owner / Device Admin privileges, so it never touches accounts,
 * other apps, or device policy. It cannot call the real (signature-only)
 * "force stop" API, so it relies on two ordinary permissions instead:
 *
 *  - performGlobalAction(GLOBAL_ACTION_HOME) from the accessibility
 *    service, which boots the target app out of the foreground the
 *    instant its window appears.
 *  - ActivityManager#killBackgroundProcesses, which then kills its now-
 *    backgrounded process. This call is a no-op while a process is still
 *    in the foreground, which is why it's only useful right after the
 *    "go home" step above (or when the target starts silently in the
 *    background, e.g. from a push notification).
 *
 * Nothing here can survive a factory reset requirement, root, or system
 * privileges - it's the same class of technique other app-blocker apps
 * (Digital Wellbeing focus mode, Freedom, etc.) use.
 */
object PackageBlocker {

    private const val TAG = "PackageBlocker"

    fun killBackgroundProcess(context: Context, packageName: String) {
        try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.killBackgroundProcesses(packageName)
        } catch (e: SecurityException) {
            Log.w(TAG, "killBackgroundProcesses denied for $packageName", e)
        }
    }
}
