package com.example.shift_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class AlarmRescheduler : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // 不再啟動 Activity，而是純粹作為一個系統廣播接收器來處理排程[cite: 6]
        val team = intent.getStringExtra("team") ?: "A"

        Log.d("AlarmRescheduler", "鬧鐘排程服務已確認，隊伍: $team")

        // 這裡確保邏輯鏈條不被中斷，讓 Flutter 端透過 MethodChannel 重新註冊
        // 建議在 MainActivity 中接收此廣播並觸發 scheduleAlarm
    }
}