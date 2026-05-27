package com.example.shift_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import android.util.Log
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter

class SevenDayWidgetProviderC : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val prefs = context.getSharedPreferences("widget_data", Context.MODE_PRIVATE)
        val team = "C"
        val views = RemoteViews(context.packageName, R.layout.widget_seven_day)

        val today = LocalDate.now()
        val dateFormat = DateTimeFormatter.ofPattern("M/d")
        val weekdayFormat = DateTimeFormatter.ofPattern("E")
        val isoFormat = DateTimeFormatter.ISO_LOCAL_DATE

        val chineseWeekday = mapOf(
            "Mon" to "週一", "Tue" to "週二", "Wed" to "週三", "Thu" to "週四",
            "Fri" to "週五", "Sat" to "週六", "Sun" to "週日"
        )

        views.setTextViewText(R.id.tv_title, "${team}隊未來7日")

        val monthLeavesJson = prefs.getString("full_month_leaves_$team", null)
        val leaveMap = mutableMapOf<String, List<String>>()

        if (monthLeavesJson != null) {
            try {
                val json = JSONObject(monthLeavesJson)
                for (i in 0..6) {
                    val date = today.plusDays(i.toLong())
                    val dateKey = date.format(isoFormat)
                    val arr = json.optJSONArray(dateKey)
                    if (arr != null) {
                        val leavers = (0 until arr.length()).map { arr.getString(it) }
                        leaveMap[dateKey] = leavers
                        Log.d("SevenDayWidgetC", "$dateKey -> ${leavers.size}人")
                    } else {
                        leaveMap[dateKey] = emptyList()
                        Log.d("SevenDayWidgetC", "$dateKey -> 0人")
                    }
                }
            } catch (e: Exception) {
                Log.e("SevenDayWidgetC", "讀取失敗", e)
            }
        } else {
            Log.e("SevenDayWidgetC", "full_month_leaves_C 為 null")
        }

        views.removeAllViews(R.id.container)

        for (i in 0..6) {
            val date = today.plusDays(i.toLong())
            val dateKey = date.format(isoFormat)
            val card = RemoteViews(context.packageName, R.layout.widget_seven_day_card)

            val weekday = chineseWeekday[date.format(weekdayFormat)] ?: ""
            val dateStr = if (i == 0) "🔥 今日 ${date.format(dateFormat)} $weekday" else "📅 ${date.format(dateFormat)} $weekday"
            card.setTextViewText(R.id.tv_date, dateStr)
            card.setTextViewText(R.id.tv_shift, ShiftEngine.getShiftDisplay(team, date))
            card.setTextViewText(R.id.tv_time, ShiftEngine.getShiftTime(team, date))

            val leavers = leaveMap[dateKey]
            if (leavers != null) {
                if (leavers.isNotEmpty()) {
                    card.setTextViewText(R.id.tv_leave, "🔴 請假：${leavers.size}人")
                    card.setTextViewText(R.id.tv_leavers, leavers.joinToString("、"))
                } else {
                    card.setTextViewText(R.id.tv_leave, "✅ 請假：0人")
                    card.setTextViewText(R.id.tv_leavers, "")
                }
            } else {
                card.setTextViewText(R.id.tv_leave, "❓ 請假：??")
                card.setTextViewText(R.id.tv_leavers, "讀取失敗")
            }

            if (i == 0) {
                card.setInt(R.id.card_root, "setBackgroundResource", R.drawable.widget_today_bg)
            }

            views.addView(R.id.container, card)
        }

        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = android.app.PendingIntent.getActivity(context, 0, intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}