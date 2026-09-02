# Snap Gatekeeper

An Android app + background "gateway" service that stops Snapchat
(`com.snapchat.android` by default) from starting, on a device connected
over adb.

## Why this needs adb, and what "force stop" actually means here

A normal, non-rooted third-party app **cannot** call the hidden
`forceStopPackage` API — that's signature/system-permission only. The
real, supported way to stop another app from launching at all is to make
this app the device's **Device Owner** and use
`DevicePolicyManager.setPackagesSuspended()`. The system then refuses to
launch the target app and shows its own "this app isn't available" UI —
no root required.

Device Owner can only be granted while the device has **no accounts
added** (fresh device, or after a factory reset / removing all accounts),
and only from adb — which lines up with "the phone is attached via adb".

To also work on devices where Device Owner can't be granted (accounts
already present), the app layers two more mechanisms that don't need
Device Owner:

1. **Accessibility watchdog** (`GatekeeperAccessibilityService`) — detects
   the instant Snapchat's window appears and immediately sends the device
   back to the home screen, plus kills its background process.
2. **Polling gateway service** (`BlockerForegroundService`) — a foreground
   service with a persistent notification that, every 2 seconds,
   re-asserts suspension and independently checks `UsageStatsManager` for
   Snapchat in the foreground as a second detection path.

A **boot receiver** re-arms suspension and restarts the gateway service
after every reboot, and a **package-install receiver** re-suspends
Snapchat the instant it's (re)installed — `setPackagesSuspended` is tied
to the installed package, so an uninstall silently clears it; this closes
that gap so uninstall/reinstall cycles of Snapchat don't slip past the
block. `PACKAGE_ADDED`/`PACKAGE_REPLACED` are exempt from Android's
implicit-broadcast restrictions, so this fires even if Snap Gatekeeper's
own process isn't running.

With Device Owner, the block is effectively permanent (survives reboots
and Snapchat reinstalls) without the app needing to be running at all —
the other two layers are pure defense in depth.

## Build & install

```bash
# from this directory, with an Android SDK / Android Studio available
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

(No committed Gradle wrapper jar — open the project in Android Studio once
and let it regenerate `gradle/wrapper/gradle-wrapper.jar`, or run
`gradle wrapper` with a local Gradle install.)

## One-time device setup (all via adb)

1. **Install the app** (see above).

2. **Make it Device Owner** (device must have no accounts configured —
   use a fresh device/profile, or remove all accounts first under
   Settings > Accounts):

   ```bash
   adb shell dpm set-device-owner com.brushup.snapgatekeeper/.GatekeeperDeviceAdminReceiver
   ```

   If this fails with "not allowed to set the device owner because there
   are already some accounts on the device", remove the accounts (or use
   a fresh work profile / test device) and retry.

3. **Enable the accessibility watchdog** (works even without Device
   Owner; useful as a fallback either way):

   ```bash
   adb shell settings put secure enabled_accessibility_services \
     com.brushup.snapgatekeeper/com.brushup.snapgatekeeper.GatekeeperAccessibilityService
   adb shell settings put secure accessibility_enabled 1
   ```

   (Or open the app and tap "Enable accessibility watchdog", which opens
   the system settings screen directly.)

4. **Grant usage access** (for the polling fallback):

   ```bash
   adb shell appops set com.brushup.snapgatekeeper android:get_usage_stats allow
   ```

   (Or tap "Grant usage access" in the app.)

5. **Start the gateway service**:

   ```bash
   adb shell am start-foreground-service -n com.brushup.snapgatekeeper/.BlockerForegroundService
   ```

   (Or open the app and tap "Start gateway service".)

After this, opening the app shows live status for all four pieces
(Device Owner, accessibility watchdog, usage access, gateway service) —
green means active.

## Changing the blocked package

Defaults to `com.snapchat.android`. To block a different package, set it
via the shared prefs key before/while the app is installed, e.g. from a
custom build, or extend `MainActivity` with an input field bound to
`GatekeeperConfig.setTargetPackage(context, packageName)`.

## Removing Device Owner later

```bash
adb shell dpm remove-active-admin com.brushup.snapgatekeeper/.GatekeeperDeviceAdminReceiver
```
