package com.brushup.snapgatekeeper

import android.content.Context

/**
 * Small persisted config: which package(s) to block, and whether the
 * gateway service should be running. Kept separate from the individual
 * components so the accessibility service, the polling service, and the
 * boot receiver all agree on the same target without depending on each
 * other.
 */
object GatekeeperConfig {

    const val DEFAULT_TARGET_PACKAGE = "com.snapchat.android"

    private const val PREFS_NAME = "gatekeeper_prefs"
    private const val KEY_TARGET_PACKAGE = "target_package"
    private const val KEY_SERVICE_ENABLED = "service_enabled"

    fun targetPackage(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_TARGET_PACKAGE, DEFAULT_TARGET_PACKAGE) ?: DEFAULT_TARGET_PACKAGE
    }

    fun setTargetPackage(context: Context, packageName: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TARGET_PACKAGE, packageName)
            .apply()
    }

    fun isServiceEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_SERVICE_ENABLED, false)
    }

    fun setServiceEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_SERVICE_ENABLED, enabled)
            .apply()
    }
}
