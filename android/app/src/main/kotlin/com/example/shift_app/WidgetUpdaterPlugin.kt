package com.example.shift_app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.widget.RemoteViews
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

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
            updateWidget(team, todayShift, shiftName, shiftTime, leaveCount, leaversList, nextShift1, nextLeavers1List)
            result.success(null)
        } else {
            result.notImplemented()
        }
    }

    private fun updateWidget(team: String, todayShift: String, shiftName: String, shiftTime: String, leaveCount: Int, leavers: List<String>, nextShift1: String, nextLeavers1: List<String>) {
        val providerClass = when (team) {
            "A" -> MyAppWidgetProviderA::class.java
            "B" -> MyAppWidgetProviderB::class.java
            "C" -> MyAppWidgetProviderC::class.java
            else -> MyAppWidgetProviderD::class.java
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
            views.setViewVisibility(R.id.tv_dayafter_label_container, android.view.View.GONE)
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pendingIntent = android.app.PendingIntent.getActivity(context, 0, intent, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.layout_root, pendingIntent)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
        android.util.Log.d("WidgetUpdater", "已更新 $team 隊 Widget，請假人數=$leaveCount")
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}