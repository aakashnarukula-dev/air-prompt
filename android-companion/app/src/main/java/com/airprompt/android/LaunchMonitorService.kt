package com.airprompt.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class LaunchMonitorService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var monitorJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIFICATION_ID, baseNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startMonitoring()
        return START_STICKY
    }

    override fun onDestroy() {
        monitorJob?.cancel()
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startMonitoring() {
        if (monitorJob?.isActive == true) return
        monitorJob = scope.launch {
            val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
            while (isActive) {
                val backendBaseUrl = prefs.getString(MainActivity.KEY_BACKEND_BASE_URL, null)
                val deviceId = prefs.getString(MainActivity.KEY_DEVICE_ID, null)
                if (!backendBaseUrl.isNullOrBlank() && !deviceId.isNullOrBlank()) {
                    val launchUrl = MainActivity.fetchPendingLaunchUrlStatic(backendBaseUrl, deviceId)
                    val previous = prefs.getString(MainActivity.KEY_LAST_LAUNCH_URL, null)
                    if (!launchUrl.isNullOrBlank() && launchUrl != previous) {
                        prefs.edit().putString(MainActivity.KEY_LAST_LAUNCH_URL, launchUrl).apply()
                        if (AirPromptApp.isForeground) {
                            val intent = Intent(this@LaunchMonitorService, MainActivity::class.java).apply {
                                data = android.net.Uri.parse(launchUrl)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                            }
                            startActivity(intent)
                        } else {
                            showLaunchNotification(launchUrl)
                        }
                    }
                }
                delay(2_000)
            }
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Air Prompt",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Air Prompt ready for launches from your Mac."
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(
                LAUNCH_CHANNEL_ID,
                "Air Prompt Launches",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts when your Mac starts a new Air Prompt session."
            }
        )
    }

    private fun baseNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            1,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Air Prompt ready")
            .setContentText("Listening for launches from your Mac.")
            .setSmallIcon(android.R.drawable.sym_def_app_icon)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .build()
    }

    private fun showLaunchNotification(launchUrl: String) {
        val intent = PendingIntent.getActivity(
            this,
            2,
            Intent(this, MainActivity::class.java).apply {
                data = android.net.Uri.parse(launchUrl)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, LAUNCH_CHANNEL_ID)
            .setContentTitle("Air Prompt session ready")
            .setContentText("Tap to open dictation on your phone.")
            .setSmallIcon(android.R.drawable.sym_def_app_icon)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(intent)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(LAUNCH_NOTIFICATION_ID, notification)
    }

    companion object {
        private const val CHANNEL_ID = "airprompt-monitor"
        private const val LAUNCH_CHANNEL_ID = "airprompt-launch"
        private const val NOTIFICATION_ID = 1001
        private const val LAUNCH_NOTIFICATION_ID = 1002
    }
}
