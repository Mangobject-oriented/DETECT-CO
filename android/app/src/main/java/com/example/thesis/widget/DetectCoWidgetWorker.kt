package com.example.thesis.widget
import com.example.thesis.R

import android.content.ComponentName
import android.content.Context
import android.widget.RemoteViews
import androidx.work.CoroutineWorker
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.google.firebase.database.FirebaseDatabase
import kotlinx.coroutines.tasks.await
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.roundToInt

class DetectCoWidgetWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(
    appContext,
    workerParams
) {

    companion object {

        const val PREFS_NAME =
            "detect_co_widget"

        const val KEY_STATUS =
            "status"

        const val KEY_TEMPERATURE =
            "temperature"

        const val KEY_RAIN =
            "rain"

        const val KEY_FLOOD =
            "flood"

        private const val FIREBASE_URL =
            "https://test1-thesisgrp20-default-rtdb.asia-southeast1.firebasedatabase.app"

        // Same Calamba location used by the DETECT-CO weather logic.
        private const val LATITUDE =
            14.15

        private const val LONGITUDE =
            121.05

        private const val ESP32_TIMEOUT_MS =
            30_000L

        fun runImmediately(context: Context) {
            val request =
                OneTimeWorkRequestBuilder<DetectCoWidgetWorker>()
                    .build()

            WorkManager
                .getInstance(context)
                .enqueue(request)
        }
    }

    override suspend fun doWork(): Result {
        return try {

            val firebaseData =
                readFirebaseData()

            val distance =
                firebaseData.distance

            val sensorTemperature =
                firebaseData.temperature

            val timestamp =
                firebaseData.timestamp

            val now =
                System.currentTimeMillis()

            val esp32Online =
                timestamp != null &&
                    kotlin.math.abs(
                        now - timestamp
                    ) <= ESP32_TIMEOUT_MS

            /*
             * The ESP32 stores ultrasonic distance in centimeters.
             * Convert distance to rise above the 150 cm normal baseline.
             *
             * rise 0–4 cm  -> SAFE
             * rise 5–40 cm -> FLOODING
             * rise >40 cm  -> CRITICAL
             */
            val floodStatus =
                if (!esp32Online) {
                    "IDLE"
                } else if (
                    distance == null ||
                    !distance.isFinite() ||
                    distance >= 200.0 ||
                    distance < 0.0
                ) {
                    "IDLE"
                } else {
                    val waterRiseCm =
                        maxOf(0.0, 150.0 - distance)

                    when {
                        waterRiseCm <= 4.0 -> "SAFE"
                        waterRiseCm <= 40.0 -> "FLOODING"
                        else -> "CRITICAL"
                    }
                }

            val status =
                if (!esp32Online) {
                    "IDLE"
                } else {
                    when (floodStatus) {
                        "FLOODING" -> "FLOODING"
                        "CRITICAL" -> "CRITICAL"
                        else -> "SAFE"
                    }
                }

            /*
             * Temperature:
             *
             * If ESP32 is online and has a temperature,
             * use the actual sensor temperature.
             *
             * Otherwise use Open-Meteo.
             */
            val weather =
                if (
                    esp32Online &&
                    sensorTemperature != null &&
                    sensorTemperature.isFinite()
                ) {
                    WeatherData(
                        temperature = sensorTemperature,
                        rainProbability = null
                    )
                } else {
                    fetchOpenMeteo()
                }

            val temperatureText =
                weather.temperature
                    ?.let {
                        String.format(
                            "%.1f°C",
                            it
                        )
                    }
                    ?: "--°C"

            val rainText =
                weather.rainProbability
                    ?.let {
                        "${it.roundToInt()}%"
                    }
                    ?: "--%"

            val floodText =
                "Flood: $floodStatus"

            saveData(
                status = status,
                temperature = temperatureText,
                rain = rainText,
                flood = floodText
            )

            updateWidgets()

            Result.success()

        } catch (e: Exception) {

            /*
             * Do not destroy the widget if one network request
             * temporarily fails.
             *
             * Keep the last successfully retrieved values.
             */
            updateWidgets()

            Result.retry()
        }
    }

    private suspend fun readFirebaseData(): FirebaseData {

        val database =
            FirebaseDatabase.getInstance(
                FIREBASE_URL
            )

        val snapshot =
            database
                .getReference("flood")
                .get()
                .await()

        val distance =
            snapshot.child("distance")
                .getValue(Double::class.java)

        val temperature =
            snapshot.child("temperature")
                .getValue(Double::class.java)

        val timestamp =
            snapshot.child("timestamp")
                .getValue(Long::class.java)
                ?: snapshot.child("timestamp")
                    .getValue(Double::class.java)
                    ?.toLong()

        val normalizedTimestamp =
            if (
                timestamp != null &&
                timestamp < 100_000_000_000L
            ) {
                timestamp * 1000L
            } else {
                timestamp
            }

        return FirebaseData(
            distance = distance,
            temperature = temperature,
            timestamp = normalizedTimestamp
        )
    }

    private fun fetchOpenMeteo(): WeatherData {

        val urlString =
            "https://api.open-meteo.com/v1/forecast" +
                "?latitude=$LATITUDE" +
                "&longitude=$LONGITUDE" +
                "&current=temperature_2m,precipitation_probability" +
                "&timezone=Asia%2FManila"

        val connection =
            URL(urlString)
                .openConnection() as HttpURLConnection

        connection.requestMethod =
            "GET"

        connection.connectTimeout =
            10_000

        connection.readTimeout =
            10_000

        connection.useCaches =
            true

        return try {

            val response =
                connection.inputStream
                    .bufferedReader()
                    .use { it.readText() }

            val json =
                JSONObject(response)

            val current =
                json.getJSONObject(
                    "current"
                )

            val temperature =
                if (
                    current.has(
                        "temperature_2m"
                    )
                ) {
                    current.getDouble(
                        "temperature_2m"
                    )
                } else {
                    null
                }

            val probability =
                if (
                    current.has(
                        "precipitation_probability"
                    )
                ) {
                    current.getDouble(
                        "precipitation_probability"
                    )
                } else {
                    null
                }

            WeatherData(
                temperature = temperature,
                rainProbability = probability
            )

        } finally {
            connection.disconnect()
        }
    }

    private fun saveData(
        status: String,
        temperature: String,
        rain: String,
        flood: String
    ) {
        applicationContext
            .getSharedPreferences(
                PREFS_NAME,
                Context.MODE_PRIVATE
            )
            .edit()
            .putString(
                KEY_STATUS,
                status
            )
            .putString(
                KEY_TEMPERATURE,
                temperature
            )
            .putString(
                KEY_RAIN,
                rain
            )
            .putString(
                KEY_FLOOD,
                flood
            )
            .apply()
    }

    private fun updateWidgets() {

        val context =
            applicationContext

        val manager =
            android.appwidget.AppWidgetManager
                .getInstance(context)

        val component =
            ComponentName(
                context,
                DetectCoWidgetProvider::class.java
            )

        val ids =
            manager.getAppWidgetIds(
                component
            )

        if (ids.isEmpty()) {
            return
        }

        val prefs =
            context.getSharedPreferences(
                PREFS_NAME,
                Context.MODE_PRIVATE
            )

        for (id in ids) {

            val views =
                RemoteViews(
                    context.packageName,
                    R.layout.detect_co_widget
                )

            views.setTextViewText(
                R.id.widget_status,
                prefs.getString(
                    KEY_STATUS,
                    "IDLE"
                )
            )

            views.setTextViewText(
                R.id.widget_temperature,
                prefs.getString(
                    KEY_TEMPERATURE,
                    "--°C"
                )
            )

            views.setTextViewText(
                R.id.widget_rain,
                prefs.getString(
                    KEY_RAIN,
                    "--%"
                )
            )

            views.setTextViewText(
                R.id.widget_flood,
                prefs.getString(
                    KEY_FLOOD,
                    "Flood: IDLE"
                )
            )

            manager.updateAppWidget(
                id,
                views
            )
        }
    }

    private data class FirebaseData(
        val distance: Double?,
        val temperature: Double?,
        val timestamp: Long?
    )

    private data class WeatherData(
        val temperature: Double?,
        val rainProbability: Double?
    )
}
