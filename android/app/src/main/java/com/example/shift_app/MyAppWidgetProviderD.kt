package com.example.shift_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import android.util.Log
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

class MyAppWidgetProviderD : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val team = "D"
        val views = RemoteViews(context.packageName, R.layout.my_app_widget_layout)

        val monthJson = prefs.getString("full_month_leaves_$team", null)
        val today = LocalDate.now()
        val todayKey = today.format(DateTimeFormatter.ISO_LOCAL_DATE)
        val tomorrowKey = today.plusDays(1).format(DateTimeFormatter.ISO_LOCAL_DATE)

        var todayLeavers = emptyList<String>()
        var tomorrowLeavers = emptyList<String>()

        if (monthJson != null) {
            try {
                val json = JSONObject(monthJson)
                todayLeavers = json.optJSONArray(todayKey)?.let { arr ->
                    (0 until arr.length()).map { arr.getString(it) }
                } ?: emptyList()
                tomorrowLeavers = json.optJSONArray(tomorrowKey)?.let { arr ->
                    (0 until arr.length()).map { arr.getString(it) }
                } ?: emptyList()
            } catch(e: Exception) {
                Log.e("WidgetD", "解析一個月數據失敗", e)
            }
        }

        val todayShift = getShiftForDate(today, team)
        val tomorrowShift = getShiftForDate(today.plusDays(1), team)

        views.setTextViewText(R.id.tv_team, "${team}隊")
        views.setTextViewText(R.id.tv_today_shift, getShiftDisplay(todayShift))
        views.setTextViewText(R.id.tv_today_time, getShiftTime(todayShift))
        views.setTextViewText(R.id.tv_leave_count, if (todayLeavers.isEmpty()) "請假：0人" else "請假：${todayLeavers.size}人")
        views.setTextViewText(R.id.tv_leavers, todayLeavers.joinToString("  "))
        views.setTextViewText(R.id.tv_tomorrow_shift, getShiftDisplay(tomorrowShift))
        views.setTextViewText(R.id.tv_tomorrow_leavers, tomorrowLeavers.joinToString(", "))
        views.setViewVisibility(R.id.tv_tomorrow_label_container, android.view.View.VISIBLE)
        views.setViewVisibility(R.id.tv_dayafter_label_container, android.view.View.GONE)

        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = android.app.PendingIntent.getActivity(context, 0, intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.layout_root, pendingIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    // ----- 班次計算邏輯 -----
    private val CYCLE_START_DATE = "2025-12-13"
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

    private fun getShiftForDate(date: LocalDate, team: String): String {
        val cycleStart = LocalDate.parse(CYCLE_START_DATE)
        val daysDiff = ChronoUnit.DAYS.between(cycleStart, date).toInt()
        if (daysDiff < 0) return ""
        val cycle = TEAM_CYCLES[team] ?: return ""
        return cycle[daysDiff % cycle.size]
    }

    private fun getShiftDisplay(shift: String): String = SHIFT_DISPLAY[shift] ?: shift
    private fun getShiftTime(shift: String): String = SHIFT_TIME[shift] ?: ""
}