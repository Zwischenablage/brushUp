package de.toni.zahnputz

import android.app.Activity
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Bundle
import android.view.View
import android.view.WindowManager

class MainActivity : Activity(), GameView.Host {

    private lateinit var game: GameView
    private var player: MediaPlayer? = null
    private var sessionActive = false

    // Smooth song clock: MediaPlayer.currentPosition updates in coarse steps on some devices.
    private var lastRawMs = -1
    private var lastRawNanos = 0L
    private var lastReturned = 0.0
    private var fallbackStartNanos = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or WindowManager.LayoutParams.FLAG_FULLSCREEN)
        volumeControlStream = AudioManager.STREAM_MUSIC
        game = GameView(this, this, Timeline.load(this), ProgressStore(this))
        setContentView(game)
        hideSystemUi()
    }

    @Suppress("DEPRECATION")
    private fun hideSystemUi() {
        window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUi()
    }

    // ---- GameView.Host ----

    override fun startSong() {
        releasePlayer()
        sessionActive = true
        lastRawMs = -1
        lastReturned = 0.0
        fallbackStartNanos = System.nanoTime()
        player = try {
            MediaPlayer.create(this, R.raw.zwei_minuten_party)
        } catch (e: Exception) {
            null
        }
        player?.apply {
            setOnCompletionListener { game.onSongFinished() }
            start()
        }
    }

    override fun stopSong() {
        sessionActive = false
        releasePlayer()
    }

    override fun songPositionSec(): Double {
        val p = player
        if (p == null) {
            // No audio available: run on a plain clock so the session still works.
            val t = (System.nanoTime() - fallbackStartNanos) / 1e9
            if (t >= songDurationSec()) game.post { game.onSongFinished() }
            return t
        }
        return try {
            val raw = p.currentPosition
            val now = System.nanoTime()
            if (raw != lastRawMs) {
                lastRawMs = raw
                lastRawNanos = now
            }
            var t = raw / 1000.0
            if (p.isPlaying) t += ((now - lastRawNanos) / 1e9).coerceAtMost(0.3)
            if (t < lastReturned && t > lastReturned - 0.3) t = lastReturned // no tiny jumps back
            lastReturned = t
            t
        } catch (e: IllegalStateException) {
            lastReturned
        }
    }

    override fun songDurationSec(): Double {
        val d = try { player?.duration ?: -1 } catch (e: IllegalStateException) { -1 }
        return if (d > 0) d / 1000.0 else 122.7
    }

    private fun releasePlayer() {
        player?.let {
            try { it.stop() } catch (_: IllegalStateException) {}
            it.release()
        }
        player = null
    }

    override fun onPause() {
        super.onPause()
        try { player?.pause() } catch (_: IllegalStateException) {}
    }

    override fun onResume() {
        super.onResume()
        hideSystemUi()
        if (sessionActive) try { player?.start() } catch (_: IllegalStateException) {}
    }

    override fun onDestroy() {
        releasePlayer()
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Back during a session must not end it accidentally; GameView decides.
        if (!game.onBack()) {
            @Suppress("DEPRECATION")
            super.onBackPressed()
        }
    }
}
