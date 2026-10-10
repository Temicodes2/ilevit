package com.example.ilevit

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

object DailyNoteReminder {
    private const val CHANNEL_ID = "daily_note_reminder"
    private const val NOTIFICATION_ID = 70421
    private const val ALARM_REQUEST_CODE = 70421

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Daily note reminder",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "A gentle daily prompt to write a note."
            }
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    fun schedule(context: Context, hour: Int, minute: Int) {
        context.getSharedPreferences("daily_note_reminder", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("enabled", true)
            .putInt("hour", hour)
            .putInt("minute", minute)
            .apply()
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = alarmIntent(context)
        val nextReminder = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }
        alarmManager.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            nextReminder.timeInMillis,
            AlarmManager.INTERVAL_DAY,
            pendingIntent
        )
    }

    fun cancel(context: Context) {
        context.getSharedPreferences("daily_note_reminder", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("enabled", false)
            .apply()
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(alarmIntent(context))
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(NOTIFICATION_ID)
    }

    fun show(context: Context) {
        createNotificationChannel(context)
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                context,
                NOTIFICATION_ID,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(context)
        }
        val notification = notificationBuilder
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setContentTitle("A little note, a stronger streak")
            .setContentText("Take a moment to capture one idea today.")
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, notification)
    }

    private fun alarmIntent(context: Context): PendingIntent {
        val intent = Intent(context, DailyNoteReminderReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
