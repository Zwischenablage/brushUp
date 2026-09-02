# Snap Gatekeeper

An Android app + background "gateway" service that stops Snapchat
(`com.snapchat.android` by default) from starting, on a device connected
over adb.

**This build is deliberately non-invasive**: it does not use Device Owner,
does not require a factory reset or removing accounts, and does not touch
anything else on the phone. Everything else on the device — calls, other
apps, existing accounts — keeps working exactly as before. Setup is three
adb commands and installing the app; nothing is permanent or hard to
reverse (see "Undo everything" below).

## Why not Device Owner?

The strongest way to stop an app from launching (`DevicePolicyManager
.setPackagesSuspended`) requires this app to be **Device Owner**, which
Android only allows on a device with **no accounts configured** — in
practice that means a factory reset first. That's off the table for a
phone that's in daily use, so this build doesn't use it at all.

## What it actually does instead

A normal, sideloaded app can't call the real (signature-only) "force
stop" API either way. Instead this uses two ordinary, revocable
permissions:

1. **Accessibility watchdog** (`GatekeeperAccessibilityService`) — the
   primary mechanism. It watches for the target app's window appearing
   and, the instant it does, sends the device back to the home screen
   (`GLOBAL_ACTION_HOME`) and kills its now-backgrounded process. This is
   the same technique used by mainstream app-blocker/parental-control
   apps (Digital Wellbeing focus mode, Freedom, etc.) — no root needed.
2. **Polling gateway service** (`BlockerForegroundService`) — a
   foreground service with a visible notification that, every 2 seconds,
   independently checks `UsageStatsManager` for the target app and kills
   its process if it ever starts in the background. Pure redundancy in
   case the accessibility service is ever turned off.

A **boot receiver** restarts the polling service after every reboot
(Android restarts the accessibility service on its own), and a
**package-install receiver** reacts immediately if Snapchat is
uninstalled and reinstalled, so that cycle can't slip a launch past the
block either.

### Honest limitation

Without Device Owner or root, there is a small window — typically well
under a second — between the target app's window appearing and the
accessibility event firing where it may flash on screen before getting
kicked home. This is inherent to any non-privileged Android app blocker,
not specific to this one.

## Build & install

```bash
# from this directory, with an Android SDK / Android Studio available
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

(No committed Gradle wrapper jar — open the project in Android Studio once
and let it regenerate `gradle/wrapper/gradle-wrapper.jar`, or run
`gradle wrapper` with a local Gradle install.)

## One-time device setup (all via adb, nothing else on the phone is touched)

1. **Install the app** (see above).

2. **Enable the accessibility watchdog.** Sideloaded apps can't grant this
   through the Settings UI on Android 13+ without an extra "allow
   restricted settings" tap, so it's simplest to grant it directly via the
   underlying setting instead:

   ```bash
   adb shell settings put secure enabled_accessibility_services \
     com.brushup.snapgatekeeper/com.brushup.snapgatekeeper.GatekeeperAccessibilityService
   adb shell settings put secure accessibility_enabled 1
   ```

   (Or open the app and tap "Enable accessibility watchdog", which opens
   the system settings screen directly, if you'd rather do it by hand.)

3. **Grant usage access** (for the polling fallback):

   ```bash
   adb shell appops set com.brushup.snapgatekeeper android:get_usage_stats allow
   ```

   (Or tap "Grant usage access" in the app.)

4. **Start the gateway service**:

   ```bash
   adb shell am start-foreground-service -n com.brushup.snapgatekeeper/.BlockerForegroundService
   ```

   (Or open the app and tap "Start gateway service".)

After this, opening the app shows live status for all three pieces
(accessibility watchdog, usage access, gateway service) — green means
active. Nothing here needs the phone attached to adb afterwards; all of
it keeps running normally on the phone by itself.

## Undo everything

Every step above is a single reverse command, none of it requires a
reset:

```bash
adb shell am stopservice -n com.brushup.snapgatekeeper/.BlockerForegroundService
adb shell settings put secure enabled_accessibility_services ""
adb shell settings put secure accessibility_enabled 0
adb shell appops set com.brushup.snapgatekeeper android:get_usage_stats deny
adb uninstall com.brushup.snapgatekeeper
```

## Changing the blocked package

Defaults to `com.snapchat.android`. To block a different package, set it
via the shared prefs key before/while the app is installed, e.g. from a
custom build, or extend `MainActivity` with an input field bound to
`GatekeeperConfig.setTargetPackage(context, packageName)`.
