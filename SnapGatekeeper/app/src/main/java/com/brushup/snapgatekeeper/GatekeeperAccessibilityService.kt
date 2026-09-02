package com.brushup.snapgatekeeper

import android.accessibilityservice.AccessibilityService
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * Primary blocking mechanism (no Device Owner needed). Watches every
 * window-state change and, if the blocked package's window ever appears,
 * immediately performs the "go home" global action - so the blocked app
 * gets bumped out of the foreground before the user can interact with it -
 * then kills its now-backgrounded process.
 */
class GatekeeperAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        val target = GatekeeperConfig.targetPackage(applicationContext)
        if (pkg != target) return

        Log.i(TAG, "Blocked package's window detected ($pkg); sending device home")
        performGlobalAction(GLOBAL_ACTION_HOME)
        PackageBlocker.killBackgroundProcess(applicationContext, pkg)
    }

    override fun onInterrupt() {
        Log.w(TAG, "Accessibility service interrupted")
    }

    companion object {
        private const val TAG = "GatekeeperA11y"
    }
}
