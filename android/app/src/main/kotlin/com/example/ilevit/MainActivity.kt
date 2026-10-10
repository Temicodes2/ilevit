package com.example.ilevit

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var notificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DailyNoteReminder.createNotificationChannel(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ilevit/daily_note_reminder"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestNotificationPermission(result)
                "scheduleDaily" -> {
                    val hour = call.argument<Int>("hour")
                    val minute = call.argument<Int>("minute")
                    if (hour == null || minute == null || hour !in 0..23 || minute !in 0..59) {
                        result.error("invalid_time", "A valid reminder time is required.", null)
                    } else {
                        DailyNoteReminder.schedule(this, hour, minute)
                        result.success(null)
                    }
                }
                "cancelDaily" -> {
                    DailyNoteReminder.cancel(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.error("permission_in_progress", "A notification permission request is already active.", null)
            return
        }
        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATION_PERMISSION
        )
    }

    @Deprecated("Deprecated in Android")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            notificationPermissionResult?.success(granted)
            notificationPermissionResult = null
        }
    }

    companion object {
        private const val REQUEST_NOTIFICATION_PERMISSION = 70421
    }
}
