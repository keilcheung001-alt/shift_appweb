package com.example.shift_app

import java.time.LocalDate
import java.time.temporal.ChronoUnit

object ShiftEngine {
    private val CYCLE_START_DATE = LocalDate.parse("2025-12-13")

    private val TEAM_CYCLES = mapOf(
        "A" to listOf("", "", "M", "M", "A", "A", "N", "LN", "LN", "", "", "M", "M", "A", "", "", "N", "N", "", "", "M", "LM", "LM", "A", "A", "N", "N", ""),
        "B" to listOf("LM", "LM", "A", "A", "N", "N", "", "", "", "M", "M", "A", "A", "N", "LN", "LN", "", "", "M", "M", "A", "", "", "N", "N", "", "", "M"),
        "C" to listOf("", "", "N", "N", "", "", "M", "LM", "LM", "A", "A", "N", "N", "", "", "", "M", "M", "A", "A", "N", "LN", "LN", "", "", "M", "M", "A"),
        "D" to listOf("LN", "LN", "", "", "M", "M", "A", "", "", "N", "N", "", "", "M", "LM", "LM", "A", "A", "N", "N", "", "", "", "M", "M", "A", "A", "N")
    )

    private val SHIFT_DISPLAY = mapOf(
        "M" to "早班", "LM" to "L早班", "A" to "中班", "N" to "夜班", "LN" to "L夜班", "REST" to "休息", "" to ""
    )

    private val SHIFT_TIME = mapOf(
        "M" to "08:00-16:00", "LM" to "08:00-20:00", "A" to "16:00-23:00", "N" to "23:00-08:00", "LN" to "20:00-08:00", "REST" to "休息", "" to ""
    )

    fun getShiftCode(team: String, date: LocalDate): String {
        val daysDiff = ChronoUnit.DAYS.between(CYCLE_START_DATE, date).toInt()
        if (daysDiff < 0) return ""
        val cycle = TEAM_CYCLES[team] ?: return ""
        return cycle[daysDiff % cycle.size]
    }

    fun getShiftDisplay(team: String, date: LocalDate): String {
        val code = getShiftCode(team, date)
        return SHIFT_DISPLAY[code] ?: code
    }

    fun getShiftTime(team: String, date: LocalDate): String {
        val code = getShiftCode(team, date)
        return SHIFT_TIME[code] ?: ""
    }
}