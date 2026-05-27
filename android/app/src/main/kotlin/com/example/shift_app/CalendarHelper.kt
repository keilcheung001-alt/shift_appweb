package com.example.shift_app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CalendarContract
import androidx.core.content.ContextCompat
import java.util.TimeZone

class CalendarHelper(private val context: Context) {

    // 呢個係檢查權限嘅函數
    fun hasCalendarPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED
    }

    fun addEvent(title: String, startMillis: Long, endMillis: Long, description: String): Boolean {
        // 如果冇權限，即刻彈走，唔會再因為冇權限而搞到彈 App
        if (!hasCalendarPermissions()) {
            return false
        }

        return try {
            val calendarId = getWritableCalendarId()
            if (calendarId == -1L) return false

            val values = ContentValues()
            values.put(CalendarContract.Events.CALENDAR_ID, calendarId)
            values.put(CalendarContract.Events.TITLE, title)
            values.put(CalendarContract.Events.DESCRIPTION, description)
            values.put(CalendarContract.Events.DTSTART, startMillis)
            values.put(CalendarContract.Events.DTEND, endMillis)
            values.put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)

            val uri = context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            uri != null
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun deleteEventsByTitle(pattern: String): Int {
        // 同樣加多個權限檢查
        if (!hasCalendarPermissions()) return 0

        var deleted = 0
        try {
            val projection = arrayOf(CalendarContract.Events._ID, CalendarContract.Events.TITLE)
            val cursor = context.contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                projection,
                null,
                null,
                null
            )
            cursor?.use {
                while (it.moveToNext()) {
                    val title = it.getString(1)
                    if (title?.contains(pattern) == true) {
                        val id = it.getLong(0)
                        val uri = Uri.withAppendedPath(CalendarContract.Events.CONTENT_URI, id.toString())
                        context.contentResolver.delete(uri, null, null)
                        deleted++
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return deleted
    }

    private fun getWritableCalendarId(): Long {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.IS_PRIMARY
        )
        val cursor = context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            null,
            null,
            null
        )
        cursor?.use {
            while (it.moveToNext()) {
                val isPrimary = it.getInt(2) == 1
                if (isPrimary) return it.getLong(0)
            }
            if (it.count > 0) return it.getLong(0)
        }
        return -1L
    }
}