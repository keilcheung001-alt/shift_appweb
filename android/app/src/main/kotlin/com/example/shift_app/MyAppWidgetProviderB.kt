package com.example.shift_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.util.Log
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter

class MyAppWidgetProviderB : AppWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "android.intent.action.DATE_CHANGED" ||
            intent.action == "android.intent.action.TIME_SET") {
            val mgr = AppWidgetManager.getInstance(context)
            val cn = ComponentName(context, MyAppWidgetProviderB::class.java)
            val ids = mgr.getAppWidgetIds(cn)
            onUpdate(context, mgr, ids)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val prefs = context.getSharedPreferences("widget_data", Context.MODE_PRIVATE)
        val team = "B"
        val views = RemoteViews(context.packageName, R.layout.my_app_widget_layout)
        val today = LocalDate.now()
        val tomorrow = today.plusDays(1)
        val dateFormat = DateTimeFormatter.ISO_LOCAL_DATE
        val todayKey = today.format(dateFormat)
        val tomorrowKey = tomorrow.format(dateFormat)

        var todayLeavers = emptyList<String>()
        var tomorrowLeavers = emptyList<String>()
        var isDataLoaded = false

        val monthLeavesJson = prefs.getString("full_month_leaves_$team", null)

        if (monthLeavesJson != null) {
            try {
                isDataLoaded = true
                val json = JSONObject(monthLeavesJson)
                todayLeavers = json.optJSONArray(todayKey)?.let { arr ->
                    (0 until arr.length()).map { arr.getString(it) }
                } ?: emptyList()
                tomorrowLeavers = json.optJSONArray(tomorrowKey)?.let { arr ->
                    (0 until arr.length()).map { arr.getString(it) }
                } ?: emptyList()
            } catch(e: Exception) {
                Log.e("WidgetB", "讀取 full_month_leaves 失敗", e)
                isDataLoaded = false
            }
        }

        if (!isDataLoaded) {
            val jsonStr = prefs.getString("widget_${team}_data", null)
            if (jsonStr != null) {
                try {
                    isDataLoaded = true
                    val json = JSONObject(jsonStr)
                    todayLeavers = json.optJSONArray("leavers")?.let { arr ->
                        (0 until arr.length()).map { arr.getString(it) }
                    } ?: emptyList()
                    tomorrowLeavers = json.optJSONArray("nextShiftLeavers1")?.let { arr ->
                        (0 until arr.length()).map { arr.getString(it) }
                    } ?: emptyList()
                } catch(e: Exception) {
                    Log.e("WidgetB", "讀取 widget_data 失敗", e)
                    isDataLoaded = false
                }
            }
        }

        val todayShift = ShiftEngine.getShiftDisplay(team, today)
        val tomorrowShift = ShiftEngine.getShiftDisplay(team, tomorrow)

        views.setTextViewText(R.id.tv_team, "${team}隊")
        views.setTextViewText(R.id.tv_today_shift, todayShift)
        views.setTextViewText(R.id.tv_today_time, ShiftEngine.getShiftTime(team, today))

        val displayCount = if (!isDataLoaded) "??" else todayLeavers.size.toString()
        views.setTextViewText(R.id.tv_leave_count, "請假：$displayCount 人")
        views.setTextViewText(R.id.tv_leavers, todayLeavers.joinToString("  "))
        views.setTextViewText(R.id.tv_tomorrow_shift, tomorrowShift)
        views.setTextViewText(R.id.tv_tomorrow_leavers, tomorrowLeavers.joinToString(", "))
        views.setViewVisibility(R.id.tv_tomorrow_label_container, android.view.View.VISIBLE)
        views.setViewVisibility(R.id.tv_dayafter_label_container, android.view.View.GONE)

        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = android.app.PendingIntent.getActivity(context, 0, intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.layout_root, pendingIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}