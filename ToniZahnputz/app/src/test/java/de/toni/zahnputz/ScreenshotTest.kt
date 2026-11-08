package de.toni.zahnputz

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.io.FileOutputStream

/**
 * Renders the main screens at Echo Show 5 resolution (960x480) into PNGs under
 * app/build/screenshots, and checks the timeline covers the whole song.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w960dp-h480dp-land-mdpi")
class ScreenshotTest {

    private class FakeHost : GameView.Host {
        var t = 0.0
        override fun startSong() {}
        override fun stopSong() {}
        override fun songPositionSec() = t
        override fun songDurationSec() = 122.7
    }

    private val ctx get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    private fun render(v: View, name: String) {
        val bmp = Bitmap.createBitmap(960, 480, Bitmap.Config.ARGB_8888)
        v.draw(Canvas(bmp))
        val dir = File("build/screenshots").apply { mkdirs() }
        FileOutputStream(File(dir, "$name.png")).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun newView(host: FakeHost): GameView {
        val v = GameView(ctx, host, Timeline.load(ctx), ProgressStore(ctx))
        v.measure(View.MeasureSpec.makeMeasureSpec(960, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(480, View.MeasureSpec.EXACTLY))
        v.layout(0, 0, 960, 480)
        return v
    }

    @Test
    fun timelineIsContiguousAndCoversSong() {
        val tl = Timeline.load(ctx)
        assertEquals(12, tl.zoneSegments.size)
        assertEquals(Zone.entries.toSet(), tl.zoneSegments.map { it.zone }.toSet())
        for (i in 1 until tl.segments.size) assertEquals(tl.segments[i - 1].end, tl.segments[i].start, 0.001)
        assertTrue(tl.segments.last().end > 122.7)
    }

    @Test
    fun screenshots() {
        val host = FakeHost()
        val v = newView(host)
        render(v, "01_home")
        GameView::class.java.getDeclaredMethod("startSession").apply { isAccessible = true }.invoke(v)
        for ((name, t) in listOf(
            "02_intro" to 3.0, "03_countdown" to 6.5, "04_kau_oben_links" to 11.0,
            "05_kau_unten_links_end" to 39.0, "06_aussen_vorne" to 52.0,
            "07_innen_oben_rechts" to 69.0, "08_innen_vorne" to 101.0,
            "09_finale" to 110.0, "10_outro" to 117.0
        )) {
            host.t = t
            render(v, name)
        }
        v.onSongFinished()
        render(v, "11_done")
    }
}
