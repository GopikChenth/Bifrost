package com.arcadelabs.bifrost

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat

class ServerForegroundService : Service() {

    private val CHANNEL_ID = "bifrost_server_status"
    private val NOTIFICATION_ID = 4554
    private val tag = "bifrost-foreground-service"

    override fun onCreate() {
        super.onCreate()
        Log.d(tag, "Foreground Service created.")
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(tag, "Foreground Service started.")

        val name = intent?.getStringExtra("name") ?: "Server"
        val type = intent?.getStringExtra("type") ?: ""
        val version = intent?.getStringExtra("version") ?: ""
        val status = intent?.getStringExtra("status") ?: "Offline"

        val notification = createNotification(name, type, version, status)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        return START_NOT_STICKY
    }

    private fun createNotification(name: String, type: String, version: String, status: String): Notification {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelName = "Server Status"
            val descriptionText = "Displays status and control actions for your server"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, channelName, importance).apply {
                description = descriptionText
            }
            notificationManager.createNotificationChannel(channel)
        }

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent("com.arcadelabs.bifrost.ACTION_STOP").apply {
            `package` = packageName
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val startIntent = Intent("com.arcadelabs.bifrost.ACTION_START").apply {
            `package` = packageName
        }
        val startPendingIntent = PendingIntent.getBroadcast(
            this,
            2,
            startIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val isStarting = status.equals("starting", ignoreCase = true)
        val isStopping = status.equals("stopping", ignoreCase = true)
        val isRunning = status.equals("running", ignoreCase = true)
        val isStartingOrStopping = isStarting || isStopping

        val buttonText = when {
            isStarting -> "Starting"
            isStopping -> "Stopping"
            isRunning -> "Stop"
            else -> "Start"
        }

        val backgroundRes = when {
            isStartingOrStopping -> R.drawable.notification_button_disabled
            isRunning -> R.drawable.notification_button_stop
            else -> R.drawable.notification_button_start
        }

        val remoteViews = RemoteViews(packageName, R.layout.notification_custom).apply {
            setTextViewText(R.id.txt_title, "Server: $name")
            setTextViewText(R.id.txt_subtitle, "$type $version • $status")
            setTextViewText(R.id.btn_action, buttonText)
            setInt(R.id.btn_action, "setBackgroundResource", backgroundRes)
            setTextColor(
                R.id.btn_action,
                if (isStartingOrStopping) Color.parseColor("#B7B7B7") else Color.parseColor("#FFFFFF")
            )

            if (isStartingOrStopping) {
                setOnClickPendingIntent(R.id.btn_action, null)
            } else {
                setOnClickPendingIntent(
                    R.id.btn_action,
                    if (isRunning) stopPendingIntent else startPendingIntent
                )
            }
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setCustomContentView(remoteViews)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        Log.d(tag, "Foreground Service destroyed.")
        super.onDestroy()
    }
}
