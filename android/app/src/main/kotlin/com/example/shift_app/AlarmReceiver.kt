package com.example.shift_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.media.RingtoneManager
import androidx.core.app.NotificationCompat
import android.util.Log
import java.time.LocalDate

class AlarmReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_UPDATE_WIDGETS = "com.example.shift_app.ACTION_UPDATE_WIDGETS"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmReceiver", "收到廣播! Action: ${intent.action}, HasExtra: ${intent.hasExtra("team")}")

        if (intent.action == ACTION_UPDATE_WIDGETS) {
            handleWidgetUpdate(context)
        }

        if (intent.hasExtra("team")) {
            handleNotification(context, intent)
        }
    }

    private fun handleNotification(context: Context, intent: Intent) {
        val team = intent.getStringExtra("team") ?: "A"
        val alarmId = intent.getIntExtra("alarmId", 9999)

        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "AlarmReceiver:notification"
        )
        wakeLock.acquire(10000)

        // 使用 ShiftEngine 取得今日班次
        val currentShift = ShiftEngine.getShiftDisplay(team, LocalDate.now())
        val shiftTime = ShiftEngine.getShiftTime(team, LocalDate.now())

        showNotification(context, team, alarmId, currentShift, shiftTime)

        wakeLock.release()
    }

    private fun showNotification(context: Context, team: String, alarmId: Int, currentShift: String, shiftTime: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val channelId = "shift_channel_v2"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "班次提醒_V2",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.enableVibration(true)
            channel.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), null)
            notificationManager.createNotificationChannel(channel)
        }

        val openIntent = Intent(context, MainActivity::class.java)
        openIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP

        val pendingIntent = PendingIntent.getActivity(
            context, alarmId, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notificationText = if (shiftTime.isNotEmpty()) {
            "$team 隊 $currentShift ($shiftTime) 快要開始了！"
        } else {
            "$team 隊 $currentShift 快要開始了！"
        }

        val notification = NotificationCompat.Builder(context, channelId)
            .setContentTitle("⏰ 班次提醒")
            .setContentText(notificationText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(notificationText))
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .build()

        notificationManager.notify(alarmId, notification)
        Log.d("AlarmReceiver", "Notification 已發送 ID: $alarmId, 班次: $currentShift")
    }

    private fun handleWidgetUpdate(context: Context) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val providers = arrayOf(
            MyAppWidgetProviderA::class.java,
            MyAppWidgetProviderB::class.java,
            MyAppWidgetProviderC::class.java,
            MyAppWidgetProviderD::class.java
        )

        for (provider in providers) {
            val component = ComponentName(context, provider)
            val ids = appWidgetManager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                val updateIntent = Intent(context, provider)
                updateIntent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                updateIntent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                context.sendBroadcast(updateIntent)
            }
        }
    }
}