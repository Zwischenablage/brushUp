package de.toni.zahnputz

import android.content.Context
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** Which side of a tooth is being brushed. */
enum class Surface(val color: Int) {
    KAU(0xFFFFB300.toInt()),     // chewing surfaces – orange
    AUSSEN(0xFF29B6F6.toInt()),  // outer surfaces – blue
    INNEN(0xFFEC407A.toInt())    // inner surfaces – pink
}

/**
 * A brushing zone. Teeth are numbered 0..9 per jaw, from Toni's LEFT (screen left,
 * like looking in a mirror) over the front teeth to his RIGHT.
 */
enum class Zone(val surface: Surface, val upper: IntRange?, val lower: IntRange?) {
    KAU_OL(Surface.KAU, 0..4, null),
    KAU_OR(Surface.KAU, 5..9, null),
    KAU_UR(Surface.KAU, null, 5..9),
    KAU_UL(Surface.KAU, null, 0..4),
    AUSSEN_L(Surface.AUSSEN, 0..2, 0..2),
    AUSSEN_V(Surface.AUSSEN, 3..6, 3..6),
    AUSSEN_R(Surface.AUSSEN, 7..9, 7..9),
    INNEN_OL(Surface.INNEN, 0..3, null),
    INNEN_OR(Surface.INNEN, 6..9, null),
    INNEN_UL(Surface.INNEN, null, 0..3),
    INNEN_UR(Surface.INNEN, null, 6..9),
    INNEN_V(Surface.INNEN, 3..6, 3..6);

    fun covers(upperJaw: Boolean, tooth: Int): Boolean =
        (if (upperJaw) upper else lower)?.contains(tooth) == true
}

class Segment(
    val start: Double,
    val end: Double,
    val type: String,       // intro | zone | finale | outro
    val zone: Zone?,
    val title: String,
    val sub: String,
    val hint: String
) {
    val length get() = end - start
    fun progress(t: Double) = ((t - start) / length).coerceIn(0.0, 1.0)
}

class Timeline(val bpm: Double, val beatOffset: Double, val segments: List<Segment>) {
    val beatLen = 60.0 / bpm
    val zoneSegments = segments.filter { it.zone != null }

    fun indexAt(t: Double): Int {
        for (i in segments.indices) if (t < segments[i].end) return i
        return segments.lastIndex
    }

    /** 0..1 position inside the current beat (0 = on the beat). */
    fun beatPhase(t: Double): Double {
        val b = (t - beatOffset) / beatLen
        return b - Math.floor(b)
    }

    companion object {
        fun load(ctx: Context): Timeline {
            val txt = ctx.assets.open("timeline.json").bufferedReader(Charsets.UTF_8).use { it.readText() }
            val o = JSONObject(txt)
            val arr = o.getJSONArray("segments")
            val list = (0 until arr.length()).map { i ->
                val s = arr.getJSONObject(i)
                Segment(
                    start = s.getDouble("start"),
                    end = s.getDouble("end"),
                    type = s.optString("type", "zone"),
                    zone = s.optString("zone", "").takeIf { it.isNotEmpty() }?.let { Zone.valueOf(it) },
                    title = s.optString("title", ""),
                    sub = s.optString("sub", ""),
                    hint = s.optString("hint", "")
                )
            }
            return Timeline(o.optDouble("bpm", 117.4), o.optDouble("beatOffset", 0.0), list)
        }
    }
}

/** Stores stars, the daily log (morning / evening) and computes the streak. */
class ProgressStore(ctx: Context) {
    private val prefs = ctx.getSharedPreferences("toni_progress", Context.MODE_PRIVATE)
    private val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.GERMANY)

    val stars: Int get() = prefs.getInt("stars", 0)

    private fun log(): Set<String> = prefs.getStringSet("log", emptySet()) ?: emptySet()

    private fun key(cal: Calendar, morning: Boolean) = fmt.format(cal.time) + if (morning) "|M" else "|A"

    fun isMorningNow(): Boolean = Calendar.getInstance().get(Calendar.HOUR_OF_DAY) < 14

    fun recordSession() {
        val newLog = HashSet(log())
        newLog.add(key(Calendar.getInstance(), isMorningNow()))
        // keep the log small: only the last ~60 days
        val cutoff = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -60) }
        val cut = fmt.format(cutoff.time)
        newLog.removeAll { it.substringBefore('|') < cut }
        prefs.edit().putStringSet("log", newLog).putInt("stars", stars + 1).apply()
    }

    fun done(cal: Calendar, morning: Boolean) = log().contains(key(cal, morning))

    fun doneDay(cal: Calendar) = done(cal, true) || done(cal, false)

    /** Days in a row with at least one session, counting back from today (or yesterday). */
    fun streak(): Int {
        val cal = Calendar.getInstance()
        if (!doneDay(cal)) cal.add(Calendar.DAY_OF_YEAR, -1)
        var n = 0
        while (doneDay(cal)) {
            n++
            cal.add(Calendar.DAY_OF_YEAR, -1)
        }
        return n
    }

    /** Monday of the current week. */
    fun weekStart(): Calendar = Calendar.getInstance().apply {
        firstDayOfWeek = Calendar.MONDAY
        val dow = (get(Calendar.DAY_OF_WEEK) + 5) % 7 // Mon=0 .. Sun=6
        add(Calendar.DAY_OF_YEAR, -dow)
    }
}
