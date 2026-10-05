package com.dude555afk.gradient

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class GenerationForegroundService : Service() {
    companion object {
        const val STOP = "gradient.background.STOP"
    }

    private val runtime
        get() = (application as GradientApplication).backgroundRuntime

    private var wakeLock: PowerManager.WakeLock? = null
    private var stopping = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        stopping = false

        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                BackgroundRuntime.NOTIFICATION_ID,
                runtime.buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(
                BackgroundRuntime.NOTIFICATION_ID,
                runtime.buildNotification(),
            )
        }

        runtime.serviceStarted(this)

        if (intent?.action == STOP) {
            runtime.clearTask()
            stopGenerationService()
        } else if (runtime.currentTask() == null) {
            stopGenerationService()
        } else {
            acquireWakeLock()
        }

        return START_NOT_STICKY
    }

    fun refresh() {
        if (stopping) return
        getSystemService(android.app.NotificationManager::class.java).notify(
            BackgroundRuntime.NOTIFICATION_ID,
            runtime.buildNotification(),
        )
    }

    @android.annotation.SuppressLint("WakelockTimeout")
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return

        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "Gradient:AgentTask",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep the process and shared Flutter engine alive while work is active.
    }

    fun stopGenerationService() {
        if (stopping) return
        stopping = true

        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null

        stopForeground(STOP_FOREGROUND_REMOVE)
        runtime.serviceStopped(this)
        stopSelf()
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        runtime.serviceStopped(this)
        super.onDestroy()
    }
}
