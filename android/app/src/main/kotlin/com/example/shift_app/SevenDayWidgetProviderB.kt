package com.example.shift_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import android.util.Log
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter

class SevenDayWidgetProviderB : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val prefs = context.getSharedPreferences("widget_data", Context.MODE_PRIVATE)
        val team = "B"
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
        var dataLoaded = false

        if (monthLeavesJson != null) {
            try {
                dataLoaded = true
                val json = JSONObject(monthLeavesJson)
                for (i in 0..6) {
                    val date = today.plusDays(i.toLong())
                    val dateKey = date.format(isoFormat)
                    val arr = json.optJSONArray(dateKey)
                    if (arr != null) {
                        val leavers = (0 until arr.length()).map { arr.getString(it) }
                        leaveMap[dateKey] = leavers
                        Log.d("SevenDayWidgetB", "$dateKey -> ${leavers.size}人请假")
                    } else {
                        Log.d("SevenDayWidgetB", "$dateKey 无请假数据记录")
                    }
                }
            } catch (e: Exception) {
                Log.e("SevenDayWidgetB", "读取失败", e)
                dataLoaded = false
            }
        } else {
            Log.e("SevenDayWidgetB", "full_month_leaves_B 为 null")
        }

        // 后备方案：使用旧数据（仅用于兼容）
        if (!dataLoaded) {
            Log.w("SevenDayWidgetB", "使用旧数据后备方案")
            val oldJson = prefs.getString("widget_${team}_data", null)
            if (oldJson != null) {
                try {
                    val json = JSONObject(oldJson)
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
                } catch (e: Exception) {
                    Log.e("SevenDayWidgetB", "解析旧数据失败", e)
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

            if (leaveMap.containsKey(dateKey)) {
                val leavers = leaveMap[dateKey] ?: emptyList()
                if (leavers.isNotEmpty()) {
                    card.setTextViewText(R.id.tv_leave, "🔴 請假：${leavers.size}人")
                    // 将 "昵称(类型)" 转换为带图标的文本
                    val displayList = leavers.map { leaver ->
                        val pattern = Regex("(.*?)\\((.*?)\\)")
                        val match = pattern.find(leaver)
                        if (match != null) {
                            val name = match.groupValues[1]
                            val type = match.groupValues[2]
                            val icon = when (type) {
                                "AL" -> "📅"
                                "CL" -> "🏢"
                                "SL" -> "🤒"
                                "TR" -> "📚"
                                else -> "📌"
                            }
                            "$icon $name"
                        } else {
                            leaver
                        }
                    }.joinToString("  ")
                    card.setTextViewText(R.id.tv_leavers, displayList)
                } else {
                    card.setTextViewText(R.id.tv_leave, "✅ 請假：0人")
                    card.setTextViewText(R.id.tv_leavers, "")
                }
            } else {
                if (dataLoaded) {
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