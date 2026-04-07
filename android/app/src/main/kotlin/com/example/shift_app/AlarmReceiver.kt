package com.example.shift_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.media.RingtoneManager
import androidx.core.app.NotificationCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val team = intent.getStringExtra("team") ?: "A"
        val alarmId = intent.getIntExtra("alarmId", 1001)

        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "AlarmReceiver:notification"
        )
        wakeLock.acquire(10000)

        showNotification(context, team, alarmId)

        val rescheduleIntent = Intent(context, AlarmRescheduler::class.java).apply {
            putExtra("team", team)
        }
        context.sendBroadcast(rescheduleIntent)
    }

    private fun showNotification(context: Context, team: String, alarmId: Int) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val vibrationPattern = longArrayOf(0, 2000, 1000, 2000, 1000, 2000)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.deleteNotificationChannel("shift_channel")
            val channel = NotificationChannel(
                "shift_channel",
                "班次提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                enableVibration(true)
                // 避免 val 衝突，使用 this.vibrationPattern
                this.vibrationPattern = vibrationPattern
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), null)
                setBypassDnd(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            context, alarmId, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, "shift_channel")
            .setContentTitle("⏰ 班次提醒")
            .setContentText("$team 隊的班次快要開始了！")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setVibrate(vibrationPattern)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
            .build()

        notificationManager.notify(alarmId, notification)
    }
}