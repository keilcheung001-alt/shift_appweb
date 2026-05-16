package com.example.shift_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.shift_app/alarm"
    private lateinit var alarmReschedulerReceiver: BroadcastReceiver

    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState) }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); triggerAllWidgetsUpdate() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 注册 WidgetUpdaterPlugin
        flutterEngine.plugins.add(WidgetUpdaterPlugin())

        alarmReschedulerReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == "RESCHEDULE_ALARM") {
                    val team = intent.getStringExtra("team") ?: "A"
                    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).invokeMethod("rescheduleAlarm", mapOf("team" to team))
                }
            }
        }
        val filter = IntentFilter("RESCHEDULE_ALARM")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.registerReceiver(this, alarmReschedulerReceiver, filter, ContextCompat.RECEIVER_EXPORTED)
        } else {
            registerReceiver(alarmReschedulerReceiver, filter)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleAlarm" -> {
                    val team = call.argument<String>("team") ?: "A"
                    val triggerTime = call.argument<Long>("triggerTime") ?: 0
                    scheduleAlarm(this, team, triggerTime)
                    result.success(null)
                }
                "cancelAlarm" -> {
                    val team = call.argument<String>("team") ?: "A"
                    cancelAlarm(this, team)
                    result.success(null)
                }
                "showAlarm" -> {
                    val team = call.argument<String>("team") ?: "A"
                    sendBroadcast(Intent(this, AlarmReceiver::class.java).apply { putExtra("team", team) })
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() { super.onDestroy(); try { unregisterReceiver(alarmReschedulerReceiver) } catch(e: Exception) {} }

    private fun scheduleAlarm(context: Context, team: String, triggerTime: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("team", team)
            putExtra("triggerTime", triggerTime)
        }
        // 固定 requestCode (用 team 字母的 ASCII 碼)
        val requestCode = team.firstOrNull()?.code ?: 1001
        val pendingIntent = PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val currentTime = System.currentTimeMillis()
        // 拒絕過去或太接近（5秒內）的時間
        if (triggerTime <= currentTime + 5000) {
            android.util.Log.w("MainActivity", "🚨 拒絕排程無效時間: triggerTime=$triggerTime, currentTime=$currentTime")
            return
        }
        android.util.Log.d("MainActivity", "⏰ 鬧鐘排程成功: 隊伍=$team, 距離現在還有 ${(triggerTime - currentTime) / 1000} 秒")
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

    private fun cancelAlarm(context: Context, team: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply { putExtra("team", team) }
        val requestCode = team.firstOrNull()?.code ?: 1001
        val pendingIntent = PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
        android.util.Log.d("MainActivity", "❌ 已取消隊伍 $team 嘅鬧鐘")
    }

    private fun triggerAllWidgetsUpdate() {
        listOf(MyAppWidgetProviderA::class.java, MyAppWidgetProviderB::class.java, MyAppWidgetProviderC::class.java, MyAppWidgetProviderD::class.java).forEach { provider ->
            sendBroadcast(Intent(this, provider).apply { action = AppWidgetManager.ACTION_APPWIDGET_UPDATE })
        }
    }
}