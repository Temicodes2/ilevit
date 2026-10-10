package com.example.ilevit

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DailyNoteReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val preferences = context.getSharedPreferences(
            "daily_note_reminder",
            Context.MODE_PRIVATE
        )
        if (!preferences.getBoolean("enabled", false)) return

        val hour = preferences.getInt("hour", 20)
        val minute = preferences.getInt("minute", 0)
        DailyNoteReminder.schedule(context, hour, minute)
    }
}
