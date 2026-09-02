package com.brushup.snapgatekeeper

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Persistent foreground "gateway" service. It doesn't do the actual
 * blocking by itself (that's [PackageBlocker] and the accessibility
 * service) - its job is to:
 *  - keep re-asserting Device Owner suspension in case anything clears it
 *  - poll [UsageStatsManager] for the current foreground app as a second,
 *    independent detection path in case the accessibility service is ever
 *    disabled by the user
 *  - show a visible notification so it's obvious the gatekeeper is running
 */
class BlockerForegroundService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var lastSeenForeground: String? = null

    private val pollTask = object : Runnable {
        override fun run() {
            poll()
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        GatekeeperConfig.setServiceEnabled(this, true)
        PackageBlocker.applySuspension(this)
        handler.removeCallbacks(pollTask)
        handler.post(pollTask)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(pollTask)
        GatekeeperConfig.setServiceEnabled(this, false)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun poll() {
        val target = GatekeeperConfig.targetPackage(this)

        // Re-assert suspension periodically; cheap and idempotent.
        PackageBlocker.applySuspension(this)

        val foreground = currentForegroundPackage()
        if (foreground != null && foreground != lastSeenForeground) {
            lastSeenForeground = foreground
            if (foreground == target) {
                Log.i(TAG, "Usage-stats poll caught $target in foreground; killing it")
                PackageBlocker.killBackgroundProcess(this, target)
            }
        }
    }

    private fun currentForegroundPackage(): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return null
        val end = System.currentTimeMillis()
        val begin = end - USAGE_WINDOW_MS
        val events = usm.queryEvents(begin, end)
        var lastPackage: String? = null
        val event = android.app.usage.UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND) {
                lastPackage = event.packageName
            }
        }
        return lastPackage
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_name),
                NotificationManager.IMPORTANCE_MIN
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val target = GatekeeperConfig.targetPackage(this)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(getString(R.string.notification_text, target))
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
    }

    companion object {
        private const val TAG = "BlockerService"
        private const val CHANNEL_ID = "gatekeeper_channel"
        private const val NOTIFICATION_ID = 1001
        private const val POLL_INTERVAL_MS = 2_000L
        private const val USAGE_WINDOW_MS = 10_000L

        fun start(context: Context) {
            val intent = Intent(context, BlockerForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, BlockerForegroundService::class.java))
        }
    }
}
