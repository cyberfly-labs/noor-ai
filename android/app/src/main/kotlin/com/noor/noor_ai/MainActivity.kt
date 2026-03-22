package com.noor.noor_ai

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"com.noor.noor_ai/daily_ayah_widget",
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"updateDailyAyahWidget" -> {
					val args = call.arguments as? Map<*, *>
					val verseKey = args?.get("verseKey") as? String ?: ""
					val arabicText = args?.get("arabicText") as? String ?: ""
					val translationText = args?.get("translationText") as? String ?: ""

					DailyAyahWidgetProvider.saveWidgetData(
						applicationContext,
						verseKey,
						arabicText,
						translationText,
					)
					result.success(true)
				}

				else -> result.notImplemented()
			}
		}
	}
}
