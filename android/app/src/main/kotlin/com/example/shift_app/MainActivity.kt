package com.example.shift_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.shift_app/alarm"
    private val CALENDAR_CHANNEL = "calendar_channel"
    private val calendarHelper by lazy { CalendarHelper(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        triggerAllWidgetsUpdate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(WidgetUpdaterPlugin())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "refreshAlarms" -> {
                    result.success(true)
                }
                "setAlarm" -> {
                    val team = call.argument<String>("team") ?: "A"
                    val timeInMillis = (call.argument<Any>("timeInMillis") as? Number)?.toLong() ?: 0L
                    val alarmId = call.argument<Int>("alarmId") ?: 1001
                    setAlarm(this, team, timeInMillis, alarmId)
                    result.success(null)
                }
                // --- 我加入咗呢個對接，令 Flutter 可以順利呼叫 ---
                "scheduleAlarm" -> {
                    val team = call.argument<String>("team") ?: "A"
                    val triggerTime = (call.argument<Any>("triggerTime") as? Number)?.toLong() ?: 0L
                    setAlarm(this, team, triggerTime, 9999)
                    result.success(true)
                }
                // ----------------------------------------------------
                "cancelAlarm" -> {
                    val team = call.argument<String>("team") ?: "A"
                    val alarmId = call.argument<Int>("alarmId") ?: 1001
                    cancelAlarm(this, team, alarmId)
                    result.success(null)
                }
                "showAlarm" -> {
                    val team = call.argument<String>("team") ?: "A"
                    val intent = Intent(this, AlarmReceiver::class.java)
                    intent.putExtra("team", team)
                    intent.putExtra("alarmId", 9999)
                    sendBroadcast(intent)
                    result.success(null)
                }
                "checkExactAlarmPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        result.success(alarmManager.canScheduleExactAlarms())
                    } else {
                        result.success(true)
                    }
                }
                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                        startActivity(intent)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "addEvent" -> {
                    val title = call.argument<String>("title") ?: ""
                    val startMillis = (call.argument<Any>("startMillis") as? Number)?.toLong() ?: 0L
                    val endMillis = (call.argument<Any>("endMillis") as? Number)?.toLong() ?: 0L
                    val description = call.argument<String>("description") ?: ""
                    val success = calendarHelper.addEvent(title, startMillis, endMillis, description)
                    result.success(success)
                }
                "deleteEventsByTitle" -> {
                    val pattern = call.argument<String>("pattern") ?: ""
                    val deleted = calendarHelper.deleteEventsByTitle(pattern)
                    result.success(deleted)
                }
                "openSettings" -> {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    val uri = Uri.fromParts("package", packageName, null)
                    intent.data = uri
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setAlarm(context: Context, team: String, triggerTime: Long, alarmId: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java)
        intent.putExtra("team", team)
        intent.putExtra("alarmId", alarmId)

        val pendingIntent = PendingIntent.getBroadcast(
            context, alarmId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(triggerTime, pendingIntent), pendingIntent)
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
            }
        }
    }

    private fun cancelAlarm(context: Context, team: String, alarmId: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java)
        intent.putExtra("team", team)

        val pendingIntent = PendingIntent.getBroadcast(
            context, alarmId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
    }

    private fun triggerAllWidgetsUpdate() {
        val providers = listOf(
            MyAppWidgetProviderA::class.java,
            MyAppWidgetProviderB::class.java,
            MyAppWidgetProviderC::class.java,
            MyAppWidgetProviderD::class.java
        )

        for (provider in providers) {
            val updateIntent = Intent(this, provider)
            updateIntent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            sendBroadcast(updateIntent)
        }
    }
}