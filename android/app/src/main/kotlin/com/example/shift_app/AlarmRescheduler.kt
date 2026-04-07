package com.example.shift_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class AlarmRescheduler : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val team = intent.getStringExtra("team") ?: "A"

        val flutterIntent = Intent(context, MainActivity::class.java).apply {
            action = "RESCHEDULE_ALARM"
            putExtra("team", team)
        }
        context.sendBroadcast(flutterIntent)

        Log.d("AlarmRescheduler", "請求重新排程鬧鐘，隊伍: $team")
    }
}