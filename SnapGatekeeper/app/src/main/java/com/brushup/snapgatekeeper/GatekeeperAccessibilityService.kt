package com.brushup.snapgatekeeper

import android.accessibilityservice.AccessibilityService
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * Fallback / redundancy layer for [PackageBlocker]. Even with Device Owner
 * suspension in place, this watches every window-state change and, if the
 * blocked package's window ever appears (e.g. suspension was cleared, or
 * this runs without Device Owner at all), immediately performs the "go
 * home" global action so the blocked app never stays on screen, and kicks
 * off a background kill + suspension re-assert for good measure.
 */
class GatekeeperAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        val target = GatekeeperConfig.targetPackage(applicationContext)
        if (pkg != target) return

        Log.i(TAG, "Blocked package's window detected ($pkg); sending device home")
        performGlobalAction(GLOBAL_ACTION_HOME)
        PackageBlocker.killBackgroundProcess(applicationContext, pkg)
        PackageBlocker.applySuspension(applicationContext)
    }

    override fun onInterrupt() {
        Log.w(TAG, "Accessibility service interrupted")
    }

    companion object {
        private const val TAG = "GatekeeperA11y"
    }
}
