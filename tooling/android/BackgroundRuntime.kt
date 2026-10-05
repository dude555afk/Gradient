package com.dude555afk.gradient

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

data class GradientBackgroundTask(
    val id: String,
    val conversationId: String,
    val title: String,
    val detail: String,
    val startedAt: Long = System.currentTimeMillis(),
)

class BackgroundRuntime(private val context: Context) {
    companion object {
        const val CHANNEL_ID = "gradient_agent_tasks"
        const val NOTIFICATION_ID = 41
    }

    private var task: GradientBackgroundTask? = null
    var service: GenerationForegroundService? = null
        private set

    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, "gradient/background")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            val args =
                                call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                            task = GradientBackgroundTask(
                                id = args["taskId"]?.toString() ?: "",
                                conversationId =
                                    args["conversationId"]?.toString() ?: "",
                                title = args["title"]?.toString()
                                    ?.takeIf { it.isNotBlank() } ?: "Gradient",
                                detail = args["detail"]?.toString()
                                    ?.takeIf { it.isNotBlank() }
                                    ?: "Gradient is working…",
                            )
                            reconcile()
                            result.success(null)
                        }

                        "update" -> {
                            val args =
                                call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                            val current = task
                            if (current != null &&
                                current.id == args["taskId"]?.toString()
                            ) {
                                task = current.copy(
                                    detail = args["detail"]?.toString()
                                        ?.takeIf { it.isNotBlank() }
                                        ?: current.detail,
                                )
                                service?.refresh()
                            }
                            result.success(null)
                        }

                        "stop" -> {
                            val args =
                                call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                            if (task?.id == args["taskId"]?.toString()) {
                                task = null
                                reconcile()
                            }
                            result.success(null)
                        }

                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    result.error("background", error.message, null)
                }
            }
    }

    fun currentTask() = task

    fun serviceStarted(value: GenerationForegroundService) {
        service = value
    }

    fun serviceStopped(value: GenerationForegroundService) {
        if (service === value) service = null
    }

    fun clearTask() {
        task = null
    }

    private fun reconcile() {
        if (task != null) {
            val running = service
            if (running != null) {
                running.refresh()
            } else {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, GenerationForegroundService::class.java),
                )
            }
        } else {
            service?.stopGenerationService()
        }
    }

    fun buildNotification(): Notification {
        ensureChannel()

        val current = task
        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.addFlags(
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )

        val open = PendingIntent.getActivity(
            context,
            41,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stop = PendingIntent.getService(
            context,
            42,
            Intent(context, GenerationForegroundService::class.java)
                .setAction(GenerationForegroundService.STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(current?.title ?: "Gradient")
            .setContentText(current?.detail ?: "Gradient is working…")
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(current?.detail ?: "Gradient is working…")
            )
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setUsesChronometer(true)
            .setWhen(current?.startedAt ?: System.currentTimeMillis())
            .setContentIntent(open)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stop,
            )
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return

        context.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Gradient tasks",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    setShowBadge(false)
                    setSound(null, null)
                }
            )
    }
}
