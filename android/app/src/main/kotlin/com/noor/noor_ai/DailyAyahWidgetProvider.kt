package com.noor.noor_ai

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

class DailyAyahWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        updateAllWidgets(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        private const val PREFS_NAME = "daily_ayah_widget"
        private const val KEY_VERSE = "verse_key"
        private const val KEY_ARABIC = "arabic_text"
        private const val KEY_TRANSLATION = "translation_text"

        fun saveWidgetData(
            context: Context,
            verseKey: String,
            arabicText: String,
            translationText: String,
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putString(KEY_VERSE, verseKey)
                .putString(KEY_ARABIC, arabicText)
                .putString(KEY_TRANSLATION, translationText)
                .apply()

            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, DailyAyahWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            updateAllWidgets(context, appWidgetManager, appWidgetIds)
        }

        private fun updateAllWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val verseKey = prefs.getString(KEY_VERSE, "Today's ayah") ?: "Today's ayah"
            val arabicText = prefs.getString(KEY_ARABIC, "Open Noor AI to load your daily ayah.")
                ?: "Open Noor AI to load your daily ayah."
            val translationText = prefs.getString(KEY_TRANSLATION, "Tap to open Noor AI and read the explanation.")
                ?: "Tap to open Noor AI and read the explanation."

            appWidgetIds.forEach { widgetId ->
                val views = RemoteViews(context.packageName, R.layout.daily_ayah_widget)
                val refreshToken = System.currentTimeMillis().toString()
                views.setTextViewText(R.id.widget_verse_key, verseKey)
                views.setTextViewText(R.id.widget_arabic_text, arabicText)
                views.setTextViewText(R.id.widget_translation_text, translationText)
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    buildLaunchPendingIntent(context, verseKey),
                )
                views.setOnClickPendingIntent(
                    R.id.widget_refresh,
                    buildRefreshPendingIntent(context, refreshToken),
                )
                appWidgetManager.updateAppWidget(widgetId, views)
            }
        }

        private fun buildLaunchPendingIntent(context: Context, verseKey: String): PendingIntent {
            val data = Uri.parse("noorai://daily-ayah/explain")
                .buildUpon()
                .appendQueryParameter("verseKey", verseKey)
                .build()

            val intent = Intent(Intent.ACTION_VIEW, data, context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }

            return PendingIntent.getActivity(
                context,
                verseKey.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun buildRefreshPendingIntent(
            context: Context,
            refreshToken: String,
        ): PendingIntent {
            val data = Uri.parse("noorai://daily-ayah/refresh")
                .buildUpon()
                .appendQueryParameter("requestId", refreshToken)
                .build()

            val intent = Intent(Intent.ACTION_VIEW, data, context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }

            return PendingIntent.getActivity(
                context,
                refreshToken.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}