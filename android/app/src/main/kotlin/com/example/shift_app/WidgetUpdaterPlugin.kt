package com.example.shift_app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class WidgetUpdaterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.example.shift_app/widget")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "updateWidgetData" -> {
                val team = call.argument<String>("team") ?: "A"
                val fullMonthJson = call.argument<String>("fullMonthJson")

                if (!fullMonthJson.isNullOrEmpty()) {
                    // ✅ 唯一嘅數據源：full_month_leaves_$team
                    val prefs = context.getSharedPreferences("widget_data", Context.MODE_PRIVATE)
                    prefs.edit().putString("full_month_leaves_$team", fullMonthJson).apply()

                    Log.d("WidgetUpdater", "✅ 已寫入 $team 隊一個月請假數據")

                    // 更新所有 Widget
                    updateAllWidgets()
                    result.success(true)
                } else {
                    result.error("NO_DATA", "fullMonthJson 為空", null)
                }
            }
            "forceUpdateWidgets" -> {
                updateAllWidgets()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun updateAllWidgets() {
        val providers = listOf(
            MyAppWidgetProviderA::class.java, MyAppWidgetProviderB::class.java,
            MyAppWidgetProviderC::class.java, MyAppWidgetProviderD::class.java,
            SevenDayWidgetProviderA::class.java, SevenDayWidgetProviderB::class.java,
            SevenDayWidgetProviderC::class.java, SevenDayWidgetProviderD::class.java
        )
        val manager = AppWidgetManager.getInstance(context)
        for (provider in providers) {
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isNotEmpty()) {
                val intent = android.content.Intent(context, provider).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}