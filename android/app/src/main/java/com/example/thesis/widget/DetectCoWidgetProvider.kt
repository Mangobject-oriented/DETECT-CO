package com.example.thesis.widget
import com.example.thesis.R

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

class DetectCoWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val WORK_NAME = "detect_co_widget_update"

        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName =
                ComponentName(context, DetectCoWidgetProvider::class.java)

            val appWidgetIds =
                appWidgetManager.getAppWidgetIds(componentName)

            if (appWidgetIds.isEmpty()) {
                return
            }

            val intent = Intent(context, DetectCoWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, appWidgetIds)
            }

            context.sendBroadcast(intent)
        }

        fun scheduleUpdates(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request =
                PeriodicWorkRequestBuilder<DetectCoWidgetWorker>(
                    15,
                    TimeUnit.MINUTES
                )
                    .setConstraints(constraints)
                    .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request
            )
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)

        scheduleUpdates(context)

        DetectCoWidgetWorker.runImmediately(context)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        super.onUpdate(
            context,
            appWidgetManager,
            appWidgetIds
        )

        scheduleUpdates(context)

        // Show the current saved/default state immediately.
        for (appWidgetId in appWidgetIds) {
            updateWidget(
                context,
                appWidgetManager,
                appWidgetId
            )
        }

        // Then fetch fresh Firebase/Open-Meteo data.
        DetectCoWidgetWorker.runImmediately(context)
    }

    override fun onDeleted(
        context: Context,
        appWidgetIds: IntArray
    ) {
        super.onDeleted(context, appWidgetIds)

        val manager = AppWidgetManager.getInstance(context)

        val componentName =
            ComponentName(
                context,
                DetectCoWidgetProvider::class.java
            )

        val remainingIds =
            manager.getAppWidgetIds(componentName)

        if (remainingIds.isEmpty()) {
            WorkManager
                .getInstance(context)
                .cancelUniqueWork(WORK_NAME)
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val views =
            RemoteViews(
                context.packageName,
                R.layout.detect_co_widget
            )

        // Tapping the widget opens DETECT-CO.
        val launchIntent =
            context.packageManager.getLaunchIntentForPackage(
                context.packageName
            )

        if (launchIntent != null) {
            launchIntent.flags =
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP

            val pendingIntent =
                PendingIntent.getActivity(
                    context,
                    1000 + appWidgetId,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
                )

            views.setOnClickPendingIntent(
                R.id.widget_root,
                pendingIntent
            )
        }

        val prefs =
            context.getSharedPreferences(
                DetectCoWidgetWorker.PREFS_NAME,
                Context.MODE_PRIVATE
            )

        views.setTextViewText(
            R.id.widget_status,
            prefs.getString(
                DetectCoWidgetWorker.KEY_STATUS,
                "IDLE"
            )
        )

        views.setTextViewText(
            R.id.widget_temperature,
            prefs.getString(
                DetectCoWidgetWorker.KEY_TEMPERATURE,
                "--°C"
            )
        )

        views.setTextViewText(
            R.id.widget_rain,
            prefs.getString(
                DetectCoWidgetWorker.KEY_RAIN,
                "--%"
            )
        )

        views.setTextViewText(
            R.id.widget_flood,
            prefs.getString(
                DetectCoWidgetWorker.KEY_FLOOD,
                "Flood: IDLE"
            )
        )

        appWidgetManager.updateAppWidget(
            appWidgetId,
            views
        )
    }
}
