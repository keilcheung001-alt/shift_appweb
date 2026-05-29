package com.example.shift_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import android.util.Log
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter

class SevenDayWidgetProviderA : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val prefs = context.getSharedPreferences("widget_data", Context.MODE_PRIVATE)
        val team = "A"
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

        // 读取存储的整月请假数据（key: 日期, value: List<昵称或姓名>）
        val monthLeavesJson = prefs.getString("full_month_leaves_$team", null)
        val leaveMap = mutableMapOf<String, List<String>>()
        var dataLoaded = false

        if (monthLeavesJson != null) {
            try {
                dataLoaded = true
                val json = JSONObject(monthLeavesJson)
                // 预先把未来7天的请假数据读入，缺失的日期不放入 map
                for (i in 0..6) {
                    val date = today.plusDays(i.toLong())
                    val dateKey = date.format(isoFormat)
                    val arr = json.optJSONArray(dateKey)
                    if (arr != null) {
                        val leavers = (0 until arr.length()).map { arr.getString(it) }
                        leaveMap[dateKey] = leavers
                        Log.d("SevenDayWidgetA", "$dateKey -> ${leavers.size}人请假")
                    } else {
                        // 注意：这里不放入 map，表示该日无请假数据记录（不代表0人，可能数据缺失）
                        Log.d("SevenDayWidgetA", "$dateKey 无请假数据记录")
                    }
                }
            } catch (e: Exception) {
                Log.e("SevenDayWidgetA", "读取 full_month_leaves 失败", e)
                dataLoaded = false
            }
        } else {
            Log.e("SevenDayWidgetA", "full_month_leaves_A 为 null")
        }

        // 如果整月数据未加载成功，尝试使用旧的 widget_data 作为后备（但不要混淆）
        if (!dataLoaded) {
            // 使用旧数据（仅用于兼容，尽量不用）
            Log.w("SevenDayWidgetA", "使用旧数据后备方案，可能不准确")
            val oldJson = prefs.getString("widget_${team}_data", null)
            if (oldJson != null) {
                try {
                    val json = JSONObject(oldJson)
                    // 旧数据只含今天和明天，后面几天就用空列表
                    val todayKey = today.format(isoFormat)
                    val tomorrowKey = today.plusDays(1).format(isoFormat)
                    val todayLeavers = json.optJSONArray("leavers")?.let { arr ->
                        (0 until arr.length()).map { arr.getString(it) }
                    } ?: emptyList()
                    val tomorrowLeavers = json.optJSONArray("nextShiftLeavers1")?.let { arr ->
                        (0 until arr.length()).map { arr.getString(it) }
                    } ?: emptyList()
                    leaveMap[todayKey] = todayLeavers
                    leaveMap[tomorrowKey] = tomorrowLeavers
                    // 其他日期不放入 map，后面会显示为数据缺失
                } catch (e: Exception) {
                    Log.e("SevenDayWidgetA", "解析旧数据失败", e)
                }
            }
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

            // 关键修正：区分“数据缺失”和“确实无人请假”
            if (leaveMap.containsKey(dateKey)) {
                val leavers = leaveMap[dateKey] ?: emptyList()
                if (leavers.isNotEmpty()) {
                    card.setTextViewText(R.id.tv_leave, "🔴 請假：${leavers.size}人")
                    card.setTextViewText(R.id.tv_leavers, leavers.joinToString("、"))
                } else {
                    card.setTextViewText(R.id.tv_leave, "✅ 請假：0人")
                    card.setTextViewText(R.id.tv_leavers, "")
                }
            } else {
                // 数据缺失（没有这个日期的记录）
                if (dataLoaded) {
                    // 整月数据已加载但这一条缺失 → 表示确实无人请假？不，可能是该日未记录，但为了不显示假数字，我们显示未知
                    card.setTextViewText(R.id.tv_leave, "❓ 請假：無紀錄")
                    card.setTextViewText(R.id.tv_leavers, "暫無數據")
                } else {
                    card.setTextViewText(R.id.tv_leave, "❌ 請假：讀取失敗")
                    card.setTextViewText(R.id.tv_leavers, "請稍後刷新")
                }
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