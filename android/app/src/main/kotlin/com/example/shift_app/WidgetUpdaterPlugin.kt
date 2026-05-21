package com.example.shift_app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONArray
import org.json.JSONObject

class WidgetUpdaterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.example.shift_app/widget")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        if (call.method == "updateWidgetData") {
            val team = call.argument<String>("team") ?: "A"
            val todayShift = call.argument<String>("todayShift") ?: ""
            val shiftName = call.argument<String>("shiftName") ?: ""
            val shiftTime = call.argument<String>("shiftTime") ?: ""
            val leaveCount = call.argument<Int>("leaveCount") ?: 0
            val leaversList = call.argument<List<String>>("leavers") ?: emptyList()
            val nextShift1 = call.argument<String>("nextShift1") ?: ""
            val nextLeavers1List = call.argument<List<String>>("nextShiftLeavers1") ?: emptyList()
            val nextShift2 = call.argument<String>("nextShift2") ?: ""
            val nextLeavers2List = call.argument<List<String>>("nextShiftLeavers2") ?: emptyList()

            saveWidgetDataToPrefs(team, todayShift, shiftName, shiftTime, leaveCount, leaversList,
                nextShift1, nextLeavers1List, nextShift2, nextLeavers2List)
            updateWidgetFromPrefs(team)

            result.success(null)
        } else {
            result.notImplemented()
        }
    }

    private fun saveWidgetDataToPrefs(
        team: String, todayShift: String, shiftName: String, shiftTime: String,
        leaveCount: Int, leavers: List<String>, nextShift1: String, nextLeavers1: List<String>,
        nextShift2: String, nextLeavers2: List<String>
    ) {
        val prefs: SharedPreferences = context.getSharedPreferences("widget_data", Context.MODE_PRIVATE)
        val json = JSONObject().apply {
            put("todayShift", todayShift)
            put("shiftName", shiftName)
            put("shiftTime", shiftTime)
            put("leaveCount", leaveCount)
            put("leavers", JSONArray(leavers))
            put("nextShift1", nextShift1)
            put("nextShiftLeavers1", JSONArray(nextLeavers1))
            put("nextShift2", nextShift2)
            put("nextShiftLeavers2", JSONArray(nextLeavers2))
            put("lastUpdated", System.currentTimeMillis())
        }
        prefs.edit().putString("widget_${team}_data", json.toString()).apply()
        android.util.Log.d("WidgetUpdater", "已儲存 $team 隊三日數據到 SharedPreferences")
    }

    fun updateWidgetFromPrefs(team: String) {
        val prefs: SharedPreferences = context.getSharedPreferences("widget_data", Context.MODE_PRIVATE)
        val jsonStr = prefs.getString("widget_${team}_data", null) ?: return

        try {
            val json = JSONObject(jsonStr)
            val todayShift = json.getString("todayShift")
            val shiftName = json.getString("shiftName")
            val shiftTime = json.getString("shiftTime")
            val leaveCount = json.getInt("leaveCount")
            val leavers = json.getJSONArray("leavers").let { arr ->
                (0 until arr.length()).map { arr.getString(it) }
            }
            val nextShift1 = json.getString("nextShift1")
            val nextLeavers1 = json.getJSONArray("nextShiftLeavers1").let { arr ->
                (0 until arr.length()).map { arr.getString(it) }
            }
            val nextShift2 = json.optString("nextShift2", "")
            val nextLeavers2 = json.optJSONArray("nextShiftLeavers2")?.let { arr ->
                (0 until arr.length()).map { arr.getString(it) }
            } ?: emptyList()

            // 修正點：加上 "D" 嘅 case
            val providerClass = when (team) {
                "A" -> MyAppWidgetProviderA::class.java
                "B" -> MyAppWidgetProviderB::class.java
                "C" -> MyAppWidgetProviderC::class.java
                "D" -> MyAppWidgetProviderD::class.java
                else -> return
            }
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, providerClass)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            if (appWidgetIds.isEmpty()) return

            for (appWidgetId in appWidgetIds) {
                val views = RemoteViews(context.packageName, R.layout.my_app_widget_layout)
                views.setTextViewText(R.id.tv_team, "${team}隊")
                views.setTextViewText(R.id.tv_today_shift, if (todayShift.isNotEmpty()) todayShift else shiftName)
                views.setTextViewText(R.id.tv_today_time, shiftTime)
                views.setTextViewText(R.id.tv_leave_count, if (leaveCount == 0) "請假：0人" else "請假：${leaveCount}人")
                views.setTextViewText(R.id.tv_leavers, leavers.joinToString("  "))

                if (nextShift1.isEmpty()) {
                    views.setViewVisibility(R.id.tv_tomorrow_label_container, android.view.View.GONE)
                } else {
                    views.setViewVisibility(R.id.tv_tomorrow_label_container, android.view.View.VISIBLE)
                    views.setTextViewText(R.id.tv_tomorrow_shift, nextShift1)
                    views.setTextViewText(R.id.tv_tomorrow_leavers, nextLeavers1.joinToString(", "))
                }

                if (nextShift2.isEmpty()) {
                    views.setViewVisibility(R.id.tv_dayafter_label_container, android.view.View.GONE)
                } else {
                    views.setViewVisibility(R.id.tv_dayafter_label_container, android.view.View.VISIBLE)
                    views.setTextViewText(R.id.tv_dayafter_shift, nextShift2)
                    views.setTextViewText(R.id.tv_dayafter_leavers, nextLeavers2.joinToString(", "))
                }

                val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                val pendingIntent = android.app.PendingIntent.getActivity(context, 0, intent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
                views.setOnClickPendingIntent(R.id.layout_root, pendingIntent)

                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
            android.util.Log.d("WidgetUpdater", "從 SharedPreferences 更新 $team 隊 Widget 成功")
        } catch (e: Exception) {
            android.util.Log.e("WidgetUpdater", "讀取快照失敗: ${e.message}")
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}