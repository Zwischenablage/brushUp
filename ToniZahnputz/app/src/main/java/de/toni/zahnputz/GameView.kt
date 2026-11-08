package de.toni.zahnputz

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.view.MotionEvent
import android.view.View
import java.util.Calendar
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * The whole app is drawn on one canvas: home screen, brushing session and celebration.
 * Everything is scaled from a 960x480 reference layout (Echo Show 5 resolution).
 */
@SuppressLint("ViewConstructor")
class GameView(
    context: Context,
    private val host: Host,
    private val timeline: Timeline,
    private val store: ProgressStore
) : View(context) {

    interface Host {
        fun startSong()
        fun stopSong()
        fun songPositionSec(): Double
        fun songDurationSec(): Double
    }

    private enum class State { HOME, SESSION, DONE }

    private var state = State.HOME
    private val startNanos = System.nanoTime()
    private var a = 0.0                 // animation clock in seconds
    private var doneAt = 0.0
    private var abortPressStart = -1.0
    private var sessionStartedAt = 0.0

    // ---- layout ----
    private var w = 960f
    private var h = 480f
    private var s = 1f
    private val startBtn = RectF()
    private val doneBtn = RectF()
    private val abortBtn = RectF()

    // ---- paints ----
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD) }
    private val bgPaint = Paint()
    private val path = Path()
    private val rect = RectF()

    // ---- teeth geometry ----
    private class Tooth(
        val x: Float, val y: Float, val angle: Float,
        val w: Float, val d: Float, val nx: Float, val ny: Float, val molar: Float
    )

    private var upperTeeth: Array<Tooth> = emptyArray()
    private var lowerTeeth: Array<Tooth> = emptyArray()
    private var base = 40f               // tooth spacing; all mouth sizes derive from it
    private var mouthCx = 0f
    private var mouthCy = 0f
    private val upperArchPts = ArrayList<PointF>()
    private val lowerArchPts = ArrayList<PointF>()

    private val totalGerms = timeline.zoneSegments.sumOf { seg ->
        (if (seg.zone!!.upper != null) 1 else 0) + (if (seg.zone.lower != null) 1 else 0)
    }

    // =====================================================================
    // Lifecycle / input
    // =====================================================================

    override fun onSizeChanged(nw: Int, nh: Int, ow: Int, oh: Int) {
        w = nw.toFloat(); h = nh.toFloat()
        s = min(w / 960f, h / 480f)
        bgPaint.shader = LinearGradient(0f, 0f, 0f, h, 0xFF1A1446.toInt(), 0xFF3B2C8F.toInt(), Shader.TileMode.CLAMP)
        mouthCx = w * 0.28f
        mouthCy = h * 0.5f
        val rx = archRx()
        val ry = h * 0.30f
        upperTeeth = buildArch(true, mouthCx, h * 0.47f, rx, ry, upperArchPts)
        lowerTeeth = buildArch(false, mouthCx, h * 0.53f, rx, ry, lowerArchPts)
    }

    private fun archRx() = min(w * 0.18f, h * 0.36f)

    private fun buildArch(upper: Boolean, cx: Float, by: Float, rx: Float, ry: Float, outPts: ArrayList<PointF>): Array<Tooth> {
        val n = 400
        val phi0 = 0.1 * PI
        val phi1 = 0.9 * PI
        val cum = DoubleArray(n + 1)
        var px = 0.0; var py = 0.0
        outPts.clear()
        for (j in 0..n) {
            val phi = phi0 + (phi1 - phi0) * j / n
            val x = cx - rx * cos(phi)
            val y = if (upper) by - ry * sin(phi) else by + ry * sin(phi)
            if (j > 0) cum[j] = cum[j - 1] + hypot(x - px, y - py)
            if (j % 10 == 0) outPts.add(PointF(x.toFloat(), y.toFloat()))
            px = x; py = y
        }
        val total = cum[n]
        base = (total / 10).toFloat()
        return Array(10) { i ->
            val target = (i + 0.5) / 10 * total
            var j = 0
            while (j < n && cum[j] < target) j++
            val phi = phi0 + (phi1 - phi0) * j / n
            val x = cx - rx * cos(phi)
            val y = if (upper) by - ry * sin(phi) else by + ry * sin(phi)
            val tx = rx * sin(phi)
            val ty = if (upper) -ry * cos(phi) else ry * cos(phi)
            var nx = -ry * cos(phi)
            var ny = if (upper) -rx * sin(phi) else rx * sin(phi)
            val nl = hypot(nx, ny); nx /= nl; ny /= nl
            val molar = abs(cos(phi)).toFloat()
            Tooth(
                x.toFloat(), y.toFloat(), Math.toDegrees(atan2(ty, tx)).toFloat(),
                base * 0.86f, base * (0.9f + 0.45f * molar), nx.toFloat(), ny.toFloat(), molar
            )
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        val x = e.x; val y = e.y
        when (state) {
            State.HOME -> if (e.action == MotionEvent.ACTION_UP && startBtn.contains(x, y)) startSession()
            State.SESSION -> when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> if (abortBtn.contains(x, y)) abortPressStart = a
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> abortPressStart = -1.0
            }
            State.DONE -> if (e.action == MotionEvent.ACTION_UP && a - doneAt > 1.5 && doneBtn.contains(x, y)) state = State.HOME
        }
        return true
    }

    /** @return true if the back press was consumed. */
    fun onBack(): Boolean = when (state) {
        State.SESSION -> true            // only the long-press X ends a session
        State.DONE -> { state = State.HOME; true }
        State.HOME -> false
    }

    private fun startSession() {
        state = State.SESSION
        sessionStartedAt = a
        abortPressStart = -1.0
        host.startSong()
    }

    fun onSongFinished() {
        if (state != State.SESSION) return
        host.stopSong()
        store.recordSession()
        state = State.DONE
        doneAt = a
    }

    private fun abortSession() {
        host.stopSong()
        abortPressStart = -1.0
        state = State.HOME
    }

    // =====================================================================
    // Drawing
    // =====================================================================

    override fun onDraw(c: Canvas) {
        a = (System.nanoTime() - startNanos) / 1e9
        c.drawRect(0f, 0f, w, h, bgPaint)
        drawBubbles(c)
        when (state) {
            State.HOME -> drawHome(c)
            State.SESSION -> drawSession(c)
            State.DONE -> drawDone(c)
        }
        postInvalidateOnAnimation()
    }

    private fun drawBubbles(c: Canvas) {
        stroke.strokeWidth = 2f * s
        for (k in 0 until 16) {
            val speed = 0.6 + (k * 7 % 5) * 0.25
            val span = h + 60 * s
            val y = h + 30 * s - ((a * speed * 30 * s + k * 53 * s) % span).toFloat()
            val x = ((k * 137) % 100) / 100f * w + (sin(a * 0.6 + k) * 18 * s).toFloat()
            val r = (5 + (k * 3 % 9)) * s
            stroke.color = Color.argb(45, 255, 255, 255)
            c.drawCircle(x, y, r, stroke)
        }
    }

    // ------------------------------------------------------------- HOME

    private fun drawHome(c: Canvas) {
        val bounce = (abs(sin(a * 2.4)) * 12 * s).toFloat()
        drawMascot(c, w * 0.2f, h * 0.52f - bounce, h * 0.62f, 1f)
        drawBrush(c, w * 0.2f + h * 0.27f, h * 0.36f - bounce, -60f + (sin(a * 8) * 10).toFloat(), h * 0.07f, false)

        val x0 = w * 0.42f
        val x1 = w * 0.95f
        val cx = (x0 + x1) / 2
        drawText(c, "Hallo Toni!", cx, 84 * s, 58 * s, 0xFFFFD54F.toInt(), Paint.Align.CENTER)
        val greet = if (store.isMorningNow()) "Guten Morgen! Zeit für die Zahnputz-Party." else "Bevor du schläfst: Zahnputz-Party!"
        drawText(c, greet, cx, 122 * s, 22 * s, 0xFFD1C4E9.toInt(), Paint.Align.CENTER)

        // big start button, pulsing
        val p = 1f + (sin(a * 4) * 0.03).toFloat()
        val bw = (x1 - x0) * 0.92f * p
        val bh = 92 * s * p
        val by = 200 * s
        startBtn.set(cx - bw / 2, by - bh / 2, cx + bw / 2, by + bh / 2)
        fill.color = 0x55000000
        rect.set(startBtn); rect.offset(0f, 6 * s)
        c.drawRoundRect(rect, bh / 2, bh / 2, fill)
        fill.color = Color.WHITE
        fill.shader = LinearGradient(0f, startBtn.top, 0f, startBtn.bottom, 0xFFFFCA28.toInt(), 0xFFFF7043.toInt(), Shader.TileMode.CLAMP)
        c.drawRoundRect(startBtn, bh / 2, bh / 2, fill)
        fill.shader = null
        drawText(c, "Zähne putzen!", cx, by + 15 * s, 42 * s * p, Color.WHITE, Paint.Align.CENTER, shadow = true)

        val slotDone = store.done(Calendar.getInstance(), store.isMorningNow())
        if (slotDone) drawText(c, "Schon geputzt – du bist super!", cx, 272 * s, 19 * s, 0xFFA5D6A7.toInt(), Paint.Align.CENTER)

        drawWeek(c, x0, 292 * s, x1, 420 * s)

        // stars + streak
        val sy = 456 * s
        drawStar(c, x0 + 22 * s, sy - 8 * s, 16 * s, 0xFFFFD54F.toInt())
        drawText(c, if (store.stars == 1) "1 Stern" else "${store.stars} Sterne", x0 + 46 * s, sy, 24 * s, Color.WHITE, Paint.Align.LEFT)
        val st = store.streak()
        val streakTxt = when (st) {
            0 -> "Heute geht's los!"
            1 -> "1 Tag geputzt"
            else -> "$st Tage in Folge!"
        }
        drawText(c, streakTxt, x1, sy, 24 * s, 0xFFFFAB91.toInt(), Paint.Align.RIGHT)
    }

    private fun drawWeek(c: Canvas, x0: Float, y0: Float, x1: Float, y1: Float) {
        fill.color = 0x33FFFFFF
        rect.set(x0, y0, x1, y1)
        c.drawRoundRect(rect, 18 * s, 18 * s, fill)
        val days = arrayOf("Mo", "Di", "Mi", "Do", "Fr", "Sa", "So")
        val labelW = 42 * s
        val colW = (x1 - x0 - labelW - 12 * s) / 7
        val cal = store.weekStart()
        val today = Calendar.getInstance()
        val rowM = y0 + 66 * s
        val rowA = y0 + 106 * s
        // row icons: sun + moon
        fill.color = 0xFFFFD54F.toInt()
        c.drawCircle(x0 + 24 * s, rowM - 7 * s, 9 * s, fill)
        fill.color = 0xFFB39DDB.toInt()
        c.drawCircle(x0 + 24 * s, rowA - 7 * s, 9 * s, fill)
        fill.color = 0xFF4A3A9F.toInt()
        c.drawCircle(x0 + 29 * s, rowA - 11 * s, 8 * s, fill)
        for (d in 0 until 7) {
            val cx = x0 + labelW + colW * (d + 0.5f)
            val isToday = cal.get(Calendar.YEAR) == today.get(Calendar.YEAR) &&
                    cal.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR)
            if (isToday) {
                fill.color = 0x40FFD54F
                rect.set(cx - colW / 2 + 3 * s, y0 + 8 * s, cx + colW / 2 - 3 * s, y1 - 8 * s)
                c.drawRoundRect(rect, 12 * s, 12 * s, fill)
            }
            drawText(c, days[d], cx, y0 + 30 * s, 18 * s, if (isToday) 0xFFFFD54F.toInt() else 0xFFD1C4E9.toInt(), Paint.Align.CENTER)
            for ((row, morning) in listOf(rowM to true, rowA to false)) {
                if (store.done(cal, morning)) {
                    drawStar(c, cx, row - 7 * s, 13 * s, 0xFFFFD54F.toInt())
                } else {
                    stroke.color = 0x66FFFFFF; stroke.strokeWidth = 2 * s
                    c.drawCircle(cx, row - 7 * s, 8 * s, stroke)
                }
            }
            cal.add(Calendar.DAY_OF_YEAR, 1)
        }
    }

    // ------------------------------------------------------------- SESSION

    private fun drawSession(c: Canvas) {
        val t = host.songPositionSec()
        val idx = timeline.indexAt(t)
        val seg = timeline.segments[idx]
        val beat = timeline.beatPhase(t)
        val pulse = exp(-beat * 5).toFloat()       // 1 on the beat, decays quickly
        val barLen = timeline.beatLen * 4
        val zones = timeline.zoneSegments

        // ---- mouth ----
        drawGums(c)
        val active = seg.zone
        if (active != null && active.surface == Surface.KAU) drawZoneGlow(c, active, pulse, 1f)
        drawTeeth(c, t, active, pulse)
        if (active != null && active.surface != Surface.KAU) drawZoneGlow(c, active, pulse, 1f)

        // preview of the next zone during the last bar
        val nextZoneSeg = zones.firstOrNull { it.start >= seg.end - 0.01 }
        if (nextZoneSeg != null && seg.end - t < barLen && (a * 4).toInt() % 2 == 0) {
            drawZoneGlow(c, nextZoneSeg.zone!!, 0.2f, 0.45f)
        }

        drawJawLabels(c)

        // brush position (computed before germs so they can look at it)
        var brushPos: PointF? = null
        if (active != null) brushPos = brushPosition(seg, t)
        else if (seg.type == "finale") brushPos = PointF(
            mouthCx + (sin(t * 2.0) * base * 1.4).toFloat(), mouthCy + (sin(t * 12.0) * base * 0.15).toFloat()
        )

        for (zs in zones) drawGermsFor(c, zs, t, brushPos)

        if (seg.type == "finale") drawTongue(c, t)

        if (brushPos != null) {
            val dx = brushPos.x - mouthCx
            val dy = brushPos.y - mouthCy
            val ang = if (seg.type == "finale") 0f else Math.toDegrees(atan2(dy.toDouble(), dx.toDouble())).toFloat()
            drawBrush(c, brushPos.x, brushPos.y, ang, base, true)
        }

        // intro countdown 3-2-1 + "Los!"
        if (seg.type == "intro") {
            val beatsLeft = ceil((seg.end - t) / timeline.beatLen).toInt()
            if (beatsLeft in 1..4) {
                drawBigBadge(c, mouthCx, mouthCy, beatsLeft.toString(), 0xFFFFD54F.toInt(), pulse)
            } else {
                drawMascot(c, mouthCx, mouthCy - (abs(sin(a * 3)) * 8 * s).toFloat(), base * 3.2f, 1f)
            }
        } else if (zones.isNotEmpty() && t - zones[0].start in 0.0..1.0) {
            drawBigBadge(c, mouthCx, mouthCy, "Los!", 0xFF66BB6A.toInt(), 1f - (t - zones[0].start).toFloat())
        }

        // colored flash on every zone change
        if (active != null && t - seg.start < 0.45) {
            stroke.color = active.surface.color
            stroke.alpha = ((1 - (t - seg.start) / 0.45) * 255).toInt().coerceIn(0, 255)
            stroke.strokeWidth = 14 * s
            c.drawRect(0f, 0f, w, h, stroke)
            stroke.alpha = 255
        }

        drawPanel(c, t, seg, idx, pulse, barLen)
        drawAbortButton(c)
    }

    private fun drawGums(c: Canvas) {
        stroke.color = 0xFFE57399.toInt()
        stroke.strokeWidth = base * 1.75f
        for (pts in listOf(upperArchPts, lowerArchPts)) {
            path.reset()
            pts.forEachIndexed { i, p -> if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y) }
            c.drawPath(path, stroke)
        }
        stroke.color = 0xFFF48FB1.toInt()
        stroke.strokeWidth = base * 1.45f
        for (pts in listOf(upperArchPts, lowerArchPts)) {
            path.reset()
            pts.forEachIndexed { i, p -> if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y) }
            c.drawPath(path, stroke)
        }
    }

    /** 0..1 how clean a tooth surface is, from the timeline (zones already finished count fully). */
    private fun cleanliness(t: Double, upper: Boolean, tooth: Int, surface: Surface): Float {
        var best = 0.0
        for (zs in timeline.zoneSegments) {
            val z = zs.zone!!
            if (z.surface == surface && z.covers(upper, tooth)) best = max(best, zs.progress(t))
        }
        return best.toFloat()
    }

    private fun drawTeeth(c: Canvas, t: Double, active: Zone?, pulse: Float) {
        for ((upper, teeth) in listOf(true to upperTeeth, false to lowerTeeth)) {
            teeth.forEachIndexed { i, th ->
                val clean = (cleanliness(t, upper, i, Surface.KAU) +
                        cleanliness(t, upper, i, Surface.AUSSEN) +
                        cleanliness(t, upper, i, Surface.INNEN)) / 3f
                var col = lerpColor(0xFFE6D38A.toInt(), Color.WHITE, clean)
                if (active != null && active.surface == Surface.KAU && active.covers(upper, i)) {
                    col = lerpColor(col, Surface.KAU.color, 0.25f + 0.25f * pulse)
                }
                c.save()
                c.translate(th.x, th.y)
                c.rotate(th.angle)
                rect.set(-th.w / 2, -th.d / 2, th.w / 2, th.d / 2)
                val r = min(th.w, th.d) * 0.32f
                fill.color = col
                c.drawRoundRect(rect, r, r, fill)
                stroke.color = 0xFF7E8BB8.toInt(); stroke.strokeWidth = 1.6f * s
                c.drawRoundRect(rect, r, r, stroke)
                if (th.molar > 0.55f) { // molar fissure
                    stroke.color = 0x55806A3A; stroke.strokeWidth = 1.4f * s
                    c.drawLine(-th.w * 0.22f, 0f, th.w * 0.22f, 0f, stroke)
                    c.drawLine(0f, -th.d * 0.2f, 0f, th.d * 0.2f, stroke)
                }
                // shine
                fill.color = 0x99FFFFFF.toInt()
                c.drawCircle(-th.w * 0.2f, -th.d * 0.2f, th.w * 0.1f, fill)
                c.restore()
                if (clean > 0.99f) drawSparkle(c, th.x + th.w * 0.3f, th.y - th.d * 0.3f, base * 0.16f, i * 0.7 + (if (upper) 0.0 else 3.0))
            }
        }
    }

    private fun surfacePoint(upper: Boolean, i: Int, surface: Surface): PointF {
        val th = (if (upper) upperTeeth else lowerTeeth)[i]
        val off = when (surface) {
            Surface.KAU -> 0f
            Surface.AUSSEN -> th.d / 2 + base * 0.22f
            Surface.INNEN -> -(th.d / 2 + base * 0.22f)
        }
        return PointF(th.x + th.nx * off, th.y + th.ny * off)
    }

    private fun zonePaths(z: Zone): List<List<PointF>> {
        val out = ArrayList<List<PointF>>()
        z.upper?.let { r -> out.add(r.map { surfacePoint(true, it, z.surface) }) }
        z.lower?.let { r -> out.add(r.map { surfacePoint(false, it, z.surface) }) }
        return out
    }

    private fun drawZoneGlow(c: Canvas, z: Zone, pulse: Float, strength: Float) {
        val wide = if (z.surface == Surface.KAU) base * 1.35f else base * 0.5f
        for (pts in zonePaths(z)) {
            path.reset()
            val first = pts.first(); val last = pts.last()
            if (pts.size >= 2) {
                val e0 = extend(pts[1], first, base * 0.3f)
                path.moveTo(e0.x, e0.y)
                pts.forEach { path.lineTo(it.x, it.y) }
                val e1 = extend(pts[pts.size - 2], last, base * 0.3f)
                path.lineTo(e1.x, e1.y)
            } else {
                path.moveTo(first.x, first.y); path.lineTo(first.x + 0.1f, first.y)
            }
            stroke.color = z.surface.color
            stroke.alpha = ((60 + 60 * pulse) * strength).toInt()
            stroke.strokeWidth = wide * 1.7f
            c.drawPath(path, stroke)
            stroke.alpha = ((150 + 100 * pulse) * strength).toInt().coerceAtMost(255)
            stroke.strokeWidth = wide
            c.drawPath(path, stroke)
            stroke.alpha = 255
        }
    }

    private fun extend(from: PointF, to: PointF, by: Float): PointF {
        val dx = to.x - from.x; val dy = to.y - from.y
        val l = max(0.001f, hypot(dx, dy))
        return PointF(to.x + dx / l * by, to.y + dy / l * by)
    }

    private fun brushPosition(seg: Segment, t: Double): PointF {
        val z = seg.zone!!
        val paths = zonePaths(z)
        val barLen = timeline.beatLen * 4
        val local = t - seg.start
        val bar = floor(local / barLen).toInt()
        val pts = paths[bar % paths.size]                      // alternate jaws every bar
        val sweep = (local % (barLen * 2)) / (barLen * 2)      // one slow sweep per 2 bars
        val u = (if (sweep < 0.5) sweep * 2 else 2 - sweep * 2).toFloat()
        val p = pointAlong(pts, u)
        val tan = tangentAlong(pts, u)
        val stroke = sin(2 * PI * t / (timeline.beatLen / 2)).toFloat() // 2 strokes per beat
        return when (z.surface) {
            Surface.KAU -> PointF(p.x + tan.x * stroke * base * 0.25f, p.y + tan.y * stroke * base * 0.25f)
            Surface.AUSSEN -> {
                val ang = 2 * PI * t / timeline.beatLen
                PointF(p.x + (cos(ang) * base * 0.2).toFloat(), p.y + (sin(ang) * base * 0.2).toFloat())
            }
            Surface.INNEN -> PointF(p.x - tan.y * stroke * base * 0.18f, p.y + tan.x * stroke * base * 0.18f)
        }
    }

    private fun pointAlong(pts: List<PointF>, u: Float): PointF {
        if (pts.size == 1) return pts[0]
        val f = u * (pts.size - 1)
        val i = min(pts.size - 2, floor(f).toInt())
        val k = f - i
        return PointF(pts[i].x + (pts[i + 1].x - pts[i].x) * k, pts[i].y + (pts[i + 1].y - pts[i].y) * k)
    }

    private fun tangentAlong(pts: List<PointF>, u: Float): PointF {
        if (pts.size == 1) return PointF(1f, 0f)
        val i = min(pts.size - 2, floor(u * (pts.size - 1)).toInt())
        val dx = pts[i + 1].x - pts[i].x; val dy = pts[i + 1].y - pts[i].y
        val l = max(0.001f, hypot(dx, dy))
        return PointF(dx / l, dy / l)
    }

    private fun drawGermsFor(c: Canvas, zs: Segment, t: Double, look: PointF?) {
        val z = zs.zone!!
        if (t > zs.end + 0.9) return
        zonePaths(z).forEachIndexed { k, pts ->
            var gx = pts.sumOf { it.x.toDouble() }.toFloat() / pts.size
            var gy = pts.sumOf { it.y.toDouble() }.toFloat() / pts.size
            // Push germs a little further out (outer) or in (inner) so they don't hide the glow.
            if (z.surface != Surface.KAU) {
                val dx = gx - mouthCx; val dy = gy - mouthCy
                val l = max(1f, hypot(dx, dy))
                val dir = if (z.surface == Surface.AUSSEN) 1f else -1f
                gx += dx / l * base * 0.25f * dir; gy += dy / l * base * 0.25f * dir
            }
            val seed = z.ordinal * 2 + k
            val r0 = base * 0.42f
            when {
                t >= zs.end -> drawPop(c, gx, gy, r0, ((t - zs.end) / 0.9).toFloat())
                t >= zs.start -> {
                    val hp = 1f - zs.progress(t).toFloat()
                    val shake = ((1 - hp) * 3 * s * sin(a * 45 + seed)).toFloat()
                    drawGerm(c, gx + shake, gy, r0 * (0.35f + 0.65f * hp), hp, seed, look)
                }
                else -> {
                    val bob = (sin(a * 3 + seed) * 2.5 * s).toFloat()
                    drawGerm(c, gx, gy + bob, r0 * 0.8f, 1f, seed, look)
                }
            }
        }
    }

    private fun drawJawLabels(c: Canvas) {
        val col = 0xAAFFFFFF.toInt()
        drawText(c, "oben", mouthCx, h * 0.47f - h * 0.30f * 0.45f, 16 * s, col, Paint.Align.CENTER)
        drawText(c, "unten", mouthCx, h * 0.53f + h * 0.30f * 0.45f + 12 * s, 16 * s, col, Paint.Align.CENTER)
        val rx = archRx()
        drawText(c, "links", mouthCx - rx - base * 0.9f, mouthCy + 6 * s, 16 * s, col, Paint.Align.CENTER)
        drawText(c, "rechts", mouthCx + rx + base * 0.9f, mouthCy + 6 * s, 16 * s, col, Paint.Align.CENTER)
    }

    private fun drawTongue(c: Canvas, t: Double) {
        val wob = (sin(t * 6) * 3 * s).toFloat()
        fill.color = 0xFFEF5350.toInt()
        rect.set(mouthCx - base * 1.3f, mouthCy - base * 0.9f + wob, mouthCx + base * 1.3f, mouthCy + base * 1.2f + wob)
        c.drawOval(rect, fill)
        stroke.color = 0xFFC62828.toInt(); stroke.strokeWidth = 2 * s
        c.drawLine(mouthCx, mouthCy - base * 0.5f + wob, mouthCx, mouthCy + base * 0.7f + wob, stroke)
    }

    private fun drawPanel(c: Canvas, t: Double, seg: Segment, idx: Int, pulse: Float, barLen: Double) {
        val px = w * 0.56f
        val pr = w - 70 * s
        val pw = w * 0.97f - px
        val zones = timeline.zoneSegments

        // progress dots, one per zone
        val gap = (pr - px) / zones.size
        zones.forEachIndexed { k, zs ->
            val cx = px + gap * (k + 0.5f)
            val cy = 34 * s
            val col = zs.zone!!.surface.color
            when {
                t >= zs.end -> { fill.color = col; c.drawCircle(cx, cy, 9 * s, fill) }
                t >= zs.start -> {
                    fill.color = col; c.drawCircle(cx, cy, (10 + 4 * pulse) * s, fill)
                    stroke.color = Color.WHITE; stroke.strokeWidth = 2.5f * s
                    c.drawCircle(cx, cy, (13 + 4 * pulse) * s, stroke)
                }
                else -> { stroke.color = col; stroke.strokeWidth = 2.5f * s; c.drawCircle(cx, cy, 8 * s, stroke) }
            }
        }

        val titleCol = seg.zone?.surface?.color ?: when (seg.type) {
            "intro" -> 0xFFFFD54F.toInt()
            "finale" -> 0xFF66BB6A.toInt()
            else -> Color.WHITE
        }
        val zoneNo = zones.indexOf(seg)
        if (zoneNo >= 0) drawText(c, "Zone ${zoneNo + 1} von ${zones.size}", px, 76 * s, 18 * s, 0xFFB39DDB.toInt(), Paint.Align.LEFT)
        drawText(c, seg.title, px, 128 * s, 50 * s * (1 + 0.05f * pulse), titleCol, Paint.Align.LEFT, shadow = true)
        drawText(c, seg.sub, px, 176 * s, 38 * s, Color.WHITE, Paint.Align.LEFT, shadow = true)
        drawWrapped(c, seg.hint, px, 216 * s, pw, 22 * s, 0xFFD1C4E9.toInt())

        // monster power bar (shrinks while brushing the zone)
        if (seg.zone != null) {
            val by = 312 * s
            drawGerm(c, px + 18 * s, by, 16 * s, 1f - seg.progress(t).toFloat(), 3, null)
            val bx0 = px + 44 * s
            val bx1 = px + pw
            fill.color = 0x40FFFFFF
            rect.set(bx0, by - 11 * s, bx1, by + 11 * s)
            c.drawRoundRect(rect, 11 * s, 11 * s, fill)
            val rem = 1f - seg.progress(t).toFloat()
            fill.color = lerpColor(0xFFFF7043.toInt(), 0xFF7CB342.toInt(), rem)
            rect.set(bx0, by - 11 * s, bx0 + (bx1 - bx0) * rem, by + 11 * s)
            if (rem > 0.02f) c.drawRoundRect(rect, 11 * s, 11 * s, fill)
            drawText(c, "Monster-Power", bx0 + 10 * s, by + 7 * s, 16 * s, Color.WHITE, Paint.Align.LEFT)
        }

        // up next
        val next = timeline.segments.getOrNull(idx + 1)
        if (next != null && seg.end - t < barLen && seg.type != "intro") {
            val blink = (a * 4).toInt() % 2 == 0
            val col = next.zone?.surface?.color ?: Color.WHITE
            if (blink) {
                path.reset()
                val ay = 362 * s
                path.moveTo(px, ay - 12 * s); path.lineTo(px + 18 * s, ay); path.lineTo(px, ay + 12 * s); path.close()
                fill.color = col
                c.drawPath(path, fill)
            }
            drawText(c, "Gleich: ${next.title} ${next.sub}", px + 28 * s, 370 * s, 24 * s, col, Paint.Align.LEFT)
        }

        // whole-song progress
        val dur = host.songDurationSec()
        val prog = (t / dur).coerceIn(0.0, 1.0).toFloat()
        val yb = 430 * s
        fill.color = 0x40FFFFFF
        rect.set(px, yb - 9 * s, px + pw, yb + 9 * s)
        c.drawRoundRect(rect, 9 * s, 9 * s, fill)
        fill.color = 0xFFFFD54F.toInt()
        rect.set(px, yb - 9 * s, px + pw * prog, yb + 9 * s)
        c.drawRoundRect(rect, 9 * s, 9 * s, fill)
        drawMascot(c, px + pw * prog, yb - 4 * s, 34 * s, 1f)
        val left = max(0.0, dur - t).toInt()
        drawText(c, "noch %d:%02d".format(left / 60, left % 60), px + pw, 466 * s, 20 * s, 0xFFD1C4E9.toInt(), Paint.Align.RIGHT)
        drawText(c, "Durchhalten bis zum Ende!", px, 466 * s, 18 * s, 0x99FFFFFF.toInt(), Paint.Align.LEFT)
    }

    private fun drawAbortButton(c: Canvas) {
        val r = 22 * s
        val cx = w - 34 * s
        val cy = 34 * s
        abortBtn.set(cx - r * 1.6f, cy - r * 1.6f, cx + r * 1.6f, cy + r * 1.6f)
        fill.color = 0x33FFFFFF
        c.drawCircle(cx, cy, r, fill)
        stroke.color = 0xAAFFFFFF.toInt(); stroke.strokeWidth = 3 * s
        c.drawLine(cx - r * 0.35f, cy - r * 0.35f, cx + r * 0.35f, cy + r * 0.35f, stroke)
        c.drawLine(cx + r * 0.35f, cy - r * 0.35f, cx - r * 0.35f, cy + r * 0.35f, stroke)
        if (abortPressStart >= 0) {
            val holdSec = 1.5
            val f = ((a - abortPressStart) / holdSec).toFloat()
            stroke.color = 0xFFFF7043.toInt(); stroke.strokeWidth = 5 * s
            rect.set(cx - r - 4 * s, cy - r - 4 * s, cx + r + 4 * s, cy + r + 4 * s)
            c.drawArc(rect, -90f, 360f * min(1f, f), false, stroke)
            drawText(c, "Gedrückt halten…", cx - r - 10 * s, cy + 6 * s, 16 * s, Color.WHITE, Paint.Align.RIGHT)
            if (f >= 1f) abortSession()
        }
    }

    // ------------------------------------------------------------- DONE

    private fun drawDone(c: Canvas) {
        val since = a - doneAt
        drawConfetti(c, since)
        val jump = (abs(sin(a * 4)) * 22 * s).toFloat()
        drawMascot(c, w * 0.22f, h * 0.55f - jump, h * 0.6f, 1f)
        drawSparkle(c, w * 0.22f + h * 0.2f, h * 0.25f - jump, 18 * s, a)
        drawSparkle(c, w * 0.22f - h * 0.22f, h * 0.35f - jump, 12 * s, a + 1.3)

        val x0 = w * 0.44f
        val x1 = w * 0.95f
        val cx = (x0 + x1) / 2
        drawText(c, "Super gemacht, Toni!", cx, 80 * s, 46 * s, 0xFFFFD54F.toInt(), Paint.Align.CENTER, shadow = true)
        drawText(c, "Alle $totalGerms Zuckermonster sind weg!", cx, 122 * s, 24 * s, Color.WHITE, Paint.Align.CENTER)

        val pop = min(1.0, since / 0.6).toFloat()
        val starR = (52 * s) * (0.3f + 0.7f * pop) * (1 + (sin(a * 5) * 0.05).toFloat())
        drawStar(c, cx, 205 * s, starR, 0xFFFFD54F.toInt())
        drawText(c, "+1", cx, 218 * s, 34 * s * pop, 0xFF6D4C41.toInt(), Paint.Align.CENTER)

        val starsTxt = if (store.stars == 1) "deinen ersten Stern" else "schon ${store.stars} Sterne"
        drawText(c, "Du hast $starsTxt gesammelt!", cx, 300 * s, 24 * s, Color.WHITE, Paint.Align.CENTER)
        val st = store.streak()
        if (st >= 2) drawText(c, "$st Tage in Folge – weiter so!", cx, 334 * s, 22 * s, 0xFFFFAB91.toInt(), Paint.Align.CENTER)

        val bw = 220 * s; val bh = 64 * s; val by = 410 * s
        doneBtn.set(cx - bw / 2, by - bh / 2, cx + bw / 2, by + bh / 2)
        fill.color = if (since > 1.5) 0xFF66BB6A.toInt() else 0x8066BB6A.toInt()
        c.drawRoundRect(doneBtn, bh / 2, bh / 2, fill)
        drawText(c, "Fertig!", cx, by + 11 * s, 32 * s, Color.WHITE, Paint.Align.CENTER, shadow = true)

        if (since > 90) state = State.HOME
    }

    private fun drawConfetti(c: Canvas, since: Double) {
        val colors = intArrayOf(0xFFFFD54F.toInt(), 0xFF29B6F6.toInt(), 0xFFEC407A.toInt(), 0xFF66BB6A.toInt(), 0xFFFF7043.toInt(), Color.WHITE)
        for (k in 0 until 70) {
            val rx = ((k * 7919) % 1000) / 1000f
            val ry = ((k * 104729) % 1000) / 1000f
            val speed = 70 + (k * 31 % 90)
            val span = h + 40 * s
            val y = ((-ry * h + since * speed * s) % span).toFloat() - 20 * s
            val x = rx * w + (sin(since * 2 + k) * 20 * s).toFloat()
            c.save()
            c.translate(x, y)
            c.rotate((since * (90 + k * 5) % 360).toFloat())
            fill.color = colors[k % colors.size]
            c.drawRect(-5 * s, -3 * s, 5 * s, 3 * s, fill)
            c.restore()
        }
    }

    // =====================================================================
    // Characters & shapes
    // =====================================================================

    /** "Zahni", the happy tooth mascot. size = height. */
    private fun drawMascot(c: Canvas, cx: Float, cy: Float, size: Float, happy: Float) {
        val k = size / 57f
        c.save()
        c.translate(cx, cy)
        c.scale(k, k)
        path.reset()
        path.moveTo(0f, -24f)
        path.cubicTo(-7f, -28f, -20f, -29f, -22f, -16f)
        path.cubicTo(-24f, -6f, -19f, 2f, -17f, 12f)
        path.cubicTo(-15f, 22f, -13f, 28f, -9f, 28f)
        path.cubicTo(-5f, 28f, -5f, 16f, 0f, 16f)
        path.cubicTo(5f, 16f, 5f, 28f, 9f, 28f)
        path.cubicTo(13f, 28f, 15f, 22f, 17f, 12f)
        path.cubicTo(19f, 2f, 24f, -6f, 22f, -16f)
        path.cubicTo(20f, -29f, 7f, -28f, 0f, -24f)
        path.close()
        fill.color = Color.WHITE
        c.drawPath(path, fill)
        stroke.color = 0xFF90CAF9.toInt(); stroke.strokeWidth = 1.6f
        c.drawPath(path, stroke)
        // eyes (blink every ~4 s)
        val blink = (a % 4.0) < 0.12
        if (blink) {
            stroke.color = 0xFF1A1446.toInt(); stroke.strokeWidth = 1.8f
            c.drawLine(-12f, -10f, -6f, -10f, stroke)
            c.drawLine(6f, -10f, 12f, -10f, stroke)
        } else {
            fill.color = 0xFF1A1446.toInt()
            c.drawCircle(-9f, -10f, 4f, fill)
            c.drawCircle(9f, -10f, 4f, fill)
            fill.color = Color.WHITE
            c.drawCircle(-7.8f, -11.5f, 1.4f, fill)
            c.drawCircle(10.2f, -11.5f, 1.4f, fill)
        }
        fill.color = 0x66F06292
        c.drawCircle(-15f, -1f, 3.5f, fill)
        c.drawCircle(15f, -1f, 3.5f, fill)
        stroke.color = 0xFF1A1446.toInt(); stroke.strokeWidth = 2.2f
        path.reset()
        path.moveTo(-8f, 0f)
        path.quadTo(0f, 7f + 4f * happy, 8f, 0f)
        c.drawPath(path, stroke)
        c.restore()
    }

    private fun drawGerm(c: Canvas, cx: Float, cy: Float, r: Float, hp: Float, seed: Int, look: PointF?) {
        // wobbly blob body
        path.reset()
        val n = 12
        val pts = Array(n) { i ->
            val ang = 2 * PI * i / n
            val rr = r * (1 + 0.1 * sin(a * 5 + i * 1.7 + seed))
            PointF(cx + (cos(ang) * rr).toFloat(), cy + (sin(ang) * rr).toFloat())
        }
        for (i in 0 until n) {
            val p = pts[i]; val q = pts[(i + 1) % n]
            val mx = (p.x + q.x) / 2; val my = (p.y + q.y) / 2
            if (i == 0) path.moveTo(mx, my) else path.quadTo(p.x, p.y, mx, my)
        }
        val p0 = pts[0]; val p1 = pts[1]
        path.quadTo(p0.x, p0.y, (p0.x + p1.x) / 2, (p0.y + p1.y) / 2)
        path.close()
        // little horns
        fill.color = 0xFF8E24AA.toInt()
        c.drawCircle(cx - r * 0.55f, cy - r * 0.95f, r * 0.2f, fill)
        c.drawCircle(cx + r * 0.55f, cy - r * 0.95f, r * 0.2f, fill)
        fill.color = lerpColor(0xFFC0CA33.toInt(), 0xFF7CB342.toInt(), hp)
        c.drawPath(path, fill)
        stroke.color = 0xFF33691E.toInt(); stroke.strokeWidth = max(1f, r * 0.08f)
        c.drawPath(path, stroke)
        fill.color = 0x5533691E
        c.drawCircle(cx + r * 0.45f, cy + r * 0.4f, r * 0.13f, fill)
        c.drawCircle(cx - r * 0.5f, cy + r * 0.3f, r * 0.09f, fill)
        // eyes looking at the brush
        var lx = 0f; var ly = 0f
        if (look != null) {
            val dx = look.x - cx; val dy = look.y - cy
            val l = max(1f, hypot(dx, dy))
            lx = dx / l * r * 0.1f; ly = dy / l * r * 0.1f
        }
        for (sx in floatArrayOf(-1f, 1f)) {
            val ex = cx + sx * r * 0.36f; val ey = cy - r * 0.18f
            fill.color = Color.WHITE
            c.drawCircle(ex, ey, r * 0.27f, fill)
            fill.color = Color.BLACK
            c.drawCircle(ex + lx, ey + ly, r * 0.13f, fill)
            stroke.color = 0xFF33691E.toInt(); stroke.strokeWidth = max(1f, r * 0.1f)
            if (hp > 0.5f) c.drawLine(ex - sx * r * 0.3f, ey - r * 0.42f, ex + sx * r * 0.2f, ey - r * 0.3f, stroke) // angry
            else c.drawLine(ex - sx * r * 0.3f, ey - r * 0.32f, ex + sx * r * 0.2f, ey - r * 0.46f, stroke) // worried
        }
        if (hp > 0.5f) { // cheeky grin with a fang
            stroke.color = 0xFF33691E.toInt(); stroke.strokeWidth = max(1f, r * 0.09f)
            path.reset()
            path.moveTo(cx - r * 0.38f, cy + r * 0.25f)
            path.quadTo(cx, cy + r * 0.62f, cx + r * 0.38f, cy + r * 0.25f)
            c.drawPath(path, stroke)
            fill.color = Color.WHITE
            path.reset()
            path.moveTo(cx + r * 0.08f, cy + r * 0.4f); path.lineTo(cx + r * 0.22f, cy + r * 0.38f); path.lineTo(cx + r * 0.15f, cy + r * 0.55f); path.close()
            c.drawPath(path, fill)
        } else { // "Oh no!"
            fill.color = 0xFF33691E.toInt()
            c.drawOval(cx - r * 0.13f, cy + r * 0.25f, cx + r * 0.13f, cy + r * 0.55f, fill)
            fill.color = 0xAA81D4FA.toInt() // sweat drop
            c.drawCircle(cx + r * 0.85f, cy - r * 0.5f, r * 0.14f, fill)
        }
    }

    private fun drawPop(c: Canvas, cx: Float, cy: Float, r: Float, q: Float) {
        if (q >= 1f) return
        val alpha = ((1 - q) * 255).toInt()
        for (i in 0 until 10) {
            val ang = i * PI / 5 + 0.3
            val d = r * (0.4f + 2.4f * q)
            fill.color = if (i % 2 == 0) 0xFFFFF59D.toInt() else Color.WHITE
            fill.alpha = alpha
            c.drawCircle(cx + (cos(ang) * d).toFloat(), cy + (sin(ang) * d).toFloat(), r * 0.18f * (1 - q * 0.5f), fill)
        }
        fill.alpha = 255
        text.alpha = alpha
        drawText(c, "Plopp!", cx, cy - r * (0.6f + 1.5f * q), r * 0.9f, 0xFFFFF176.toInt(), Paint.Align.CENTER, alpha = alpha)
    }

    private fun drawBrush(c: Canvas, x: Float, y: Float, angleDeg: Float, b: Float, foam: Boolean) {
        if (foam) {
            for (k in 0 until 7) {
                val ang = k * 0.9 + a * 1.3
                val rr = b * (0.4 + 0.25 * sin(a * 2 + k))
                fill.color = Color.argb(210, 255, 255, 255)
                c.drawCircle(x + (cos(ang) * rr).toFloat(), y + (sin(ang) * rr).toFloat(), b * (0.09f + 0.05f * sin(a * 3 + k * 2).toFloat()), fill)
            }
        }
        c.save()
        c.translate(x, y)
        c.rotate(angleDeg)
        // bristles (toward the teeth / mouth center = -x)
        stroke.color = 0xFFE1F5FE.toInt(); stroke.strokeWidth = b * 0.08f
        for (k in 0 until 7) {
            val yy = -0.42f * b + k * 0.14f * b
            c.drawLine(-0.1f * b, yy, -0.48f * b, yy, stroke)
        }
        fill.color = 0xFFFF5252.toInt()
        rect.set(-0.14f * b, -0.55f * b, 0.28f * b, 0.55f * b)
        c.drawRoundRect(rect, 0.15f * b, 0.15f * b, fill)
        rect.set(0.2f * b, -0.15f * b, 2.9f * b, 0.15f * b)
        c.drawRoundRect(rect, 0.15f * b, 0.15f * b, fill)
        fill.color = 0x88FFFFFF.toInt()
        rect.set(1.2f * b, -0.07f * b, 2.6f * b, 0.0f)
        c.drawRoundRect(rect, 0.05f * b, 0.05f * b, fill)
        c.restore()
    }

    private fun drawStar(c: Canvas, cx: Float, cy: Float, r: Float, color: Int) {
        path.reset()
        for (i in 0 until 10) {
            val rr = if (i % 2 == 0) r else r * 0.45f
            val ang = -PI / 2 + i * PI / 5
            val x = cx + (cos(ang) * rr).toFloat(); val y = cy + (sin(ang) * rr).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        fill.color = color
        c.drawPath(path, fill)
        stroke.color = 0xFFFFA000.toInt(); stroke.strokeWidth = max(1f, r * 0.08f)
        c.drawPath(path, stroke)
    }

    private fun drawSparkle(c: Canvas, x: Float, y: Float, r: Float, phase: Double) {
        val k = (0.5 + 0.5 * sin(a * 3 + phase * 2.1)).toFloat()
        if (k < 0.15f) return
        val rr = r * k
        path.reset()
        path.moveTo(x, y - rr); path.lineTo(x + rr * 0.25f, y - rr * 0.25f)
        path.lineTo(x + rr, y); path.lineTo(x + rr * 0.25f, y + rr * 0.25f)
        path.lineTo(x, y + rr); path.lineTo(x - rr * 0.25f, y + rr * 0.25f)
        path.lineTo(x - rr, y); path.lineTo(x - rr * 0.25f, y - rr * 0.25f)
        path.close()
        fill.color = 0xFFFFF59D.toInt()
        c.drawPath(path, fill)
    }

    private fun drawBigBadge(c: Canvas, cx: Float, cy: Float, label: String, color: Int, pulse: Float) {
        val r = base * (1.6f + 0.25f * pulse)
        fill.color = 0x66000000
        c.drawCircle(cx, cy + 5 * s, r, fill)
        fill.color = color
        c.drawCircle(cx, cy, r, fill)
        drawText(c, label, cx, cy + r * 0.32f, r * (if (label.length > 1) 0.7f else 1.0f), 0xFF1A1446.toInt(), Paint.Align.CENTER)
    }

    // =====================================================================
    // Text helpers
    // =====================================================================

    private fun drawText(
        c: Canvas, str: String, x: Float, y: Float, size: Float, color: Int,
        align: Paint.Align, shadow: Boolean = false, alpha: Int = 255
    ) {
        text.textSize = size
        text.textAlign = align
        if (shadow) {
            text.color = 0x66000000
            text.alpha = (0x66 * alpha / 255)
            c.drawText(str, x + size * 0.04f, y + size * 0.06f, text)
        }
        text.color = color
        text.alpha = alpha
        c.drawText(str, x, y, text)
        text.alpha = 255
    }

    private fun drawWrapped(c: Canvas, str: String, x: Float, y: Float, maxW: Float, size: Float, color: Int): Float {
        text.textSize = size
        var line = ""
        var yy = y
        for (word in str.split(' ')) {
            val test = if (line.isEmpty()) word else "$line $word"
            if (text.measureText(test) > maxW && line.isNotEmpty()) {
                drawText(c, line, x, yy, size, color, Paint.Align.LEFT)
                yy += size * 1.3f
                line = word
            } else line = test
        }
        if (line.isNotEmpty()) drawText(c, line, x, yy, size, color, Paint.Align.LEFT)
        return yy + size * 1.3f
    }

    private fun lerpColor(c1: Int, c2: Int, f: Float): Int {
        val k = f.coerceIn(0f, 1f)
        fun ch(shift: Int) = (((c1 shr shift) and 0xFF) + (((c2 shr shift) and 0xFF) - ((c1 shr shift) and 0xFF)) * k).toInt()
        return Color.argb(ch(24), ch(16), ch(8), ch(0))
    }
}
