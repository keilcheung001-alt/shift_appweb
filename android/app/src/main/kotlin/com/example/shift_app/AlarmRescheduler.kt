package com.example.shift_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.Intent.ACTION_BOOT_COMPLETED

class AlarmRescheduler : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // 你原本嘅鬧鐘邏輯可以照放呢度
        // 我只係加多一行用嚟重新排程 widget 更新
        if (intent.action == ACTION_BOOT_COMPLETED) {
            DailyWidgetUpdater.schedule(context)
        }
    }
}