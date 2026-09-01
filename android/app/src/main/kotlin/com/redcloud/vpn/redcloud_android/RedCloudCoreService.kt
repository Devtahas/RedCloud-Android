package com.redcloud.vpn.redcloud_android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class RedCloudCoreService : Service() {

    companion object {
        const val ACTION_START = "com.redcloud.vpn.START_CORE_SERVICE"
        const val ACTION_STOP = "com.redcloud.vpn.STOP_CORE_SERVICE"
        private const val CHANNEL_ID = "redcloud_core_channel"
        private const val NOTIFICATION_ID = 9991

        fun start(context: Context) {
            val intent = Intent(context, RedCloudCoreService::class.java).apply {
                action = ACTION_START
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                MainActivity.appendNativeLog("ServiceError", "خطا در اجرای سرویس: ${e.message}")
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, RedCloudCoreService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                context.stopService(intent)
            } catch (_: Exception) {}
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireServiceWakeLock()
        MainActivity.appendNativeLog("Service", "سرویس دائمی پس‌زمینه (RedCloudCoreService) فعال شد.")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = buildForegroundNotification()
        startForeground(NOTIFICATION_ID, notification)

        // فلگ START_STICKY مانع از مرگ پروسس توسط اندروید می‌شود
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        MainActivity.appendNativeLog("TaskKiller", "برنامه از دکمه مربع (Recent Apps) بسته شد؛ سرویس ارتباطی زنده ماند.")
        // با عدم فراخوانی stopSelf، سرویس و هسته‌های فعال زنده می‌مانند.
        super.onTaskRemoved(rootIntent)
    }

    private fun acquireServiceWakeLock() {
        try {
            val powerManager = applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "RedCloudVPN::StickyServiceWakeLock")
            wakeLock?.setReferenceCounted(false)
            wakeLock?.acquire()
        } catch (e: Exception) {
            MainActivity.appendNativeLog("ServiceWakeLock", "خطا در دریافت WakeLock سرویس: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "RedCloud Core Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "سرویس زنده نگه داشتن هسته‌های ضدسانسور RedCloud"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("RedCloud VPN")
            .setContentText("اتصال امن در پس‌زمینه فعال است")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
        MainActivity.appendNativeLog("Service", "سرویس پس‌زمینه متوقف شد.")
        super.onDestroy()
    }
}