package com.example.shift_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import android.util.Log
import org.json.JSONObject

class MyAppWidgetProviderD : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val team = "D"
        var jsonStr = prefs.getString("widget_snapshot_$team", null)
        if (jsonStr == null) {
            jsonStr = prefs.getString("widget_${team}_data", null)
        }
        val views = RemoteViews(context.packageName, R.layout.my_app_widget_layout)

        if (jsonStr.isNullOrEmpty()) {
            views.setTextViewText(R.id.tv_team, "${team}隊")
            views.setTextViewText(R.id.tv_today_shift, "無資料")
            views.setTextViewText(R.id.tv_today_time, "")
            views.setTextViewText(R.id.tv_leave_count, "請假：0人")
            views.setTextViewText(R.id.tv_leavers, "")
            views.setViewVisibility(R.id.tv_tomorrow_label_container, android.view.View.GONE)
            views.setViewVisibility(R.id.tv_dayafter_label_container, android.view.View.GONE)
            appWidgetManager.updateAppWidget(appWidgetId, views)
            return
        }

        try {
            val json = JSONObject(jsonStr)
            val todayShift = json.optString("todayShift", "")
            val shiftTime = json.optString("shiftTime", "")
            val leaveCount = json.optInt("leaveCount", 0)
            val leaversArray = json.optJSONArray("leavers")
            val leavers = if (leaversArray != null) {
                (0 until leaversArray.length()).joinToString("  ") { leaversArray.getString(it) }
            } else ""
            val nextShift1 = json.optString("nextShift1", "")
            val nextLeavers1Array = json.optJSONArray("nextShiftLeavers1")
            val nextLeavers1 = if (nextLeavers1Array != null) {
                (0 until nextLeavers1Array.length()).joinToString(", ") { nextLeavers1Array.getString(it) }
            } else ""

            views.setTextViewText(R.id.tv_team, "${team}隊")
            views.setTextViewText(R.id.tv_today_shift, todayShift)
            views.setTextViewText(R.id.tv_today_time, shiftTime)
            views.setTextViewText(R.id.tv_leave_count, if (leaveCount == 0) "請假：0人" else "請假：${leaveCount}人")
            views.setTextViewText(R.id.tv_leavers, leavers)

            if (nextShift1.isEmpty()) {
                views.setViewVisibility(R.id.tv_tomorrow_label_container, android.view.View.GONE)
            } else {
                views.setViewVisibility(R.id.tv_tomorrow_label_container, android.view.View.VISIBLE)
                views.setTextViewText(R.id.tv_tomorrow_shift, nextShift1)
                views.setTextViewText(R.id.tv_tomorrow_leavers, nextLeavers1)
            }
            views.setViewVisibility(R.id.tv_dayafter_label_container, android.view.View.GONE)

            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pendingIntent = android.app.PendingIntent.getActivity(context, 0, intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.layout_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
            Log.d("WidgetD", "更新成功，請假人數=$leaveCount")
        } catch (e: Exception) {
            Log.e("WidgetD", "JSON解析錯誤", e)
        }
    }
}