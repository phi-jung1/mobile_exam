package com.example.mo_be

import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MainActivity : FlutterActivity() {

    private val OVERLAY_CHANNEL = "overlay_detector"
    private val SCREENSHOT_CHANNEL = "screenshot_detector"

    private var screenshotObserver: ContentObserver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // ---------- Overlay detection ----------
        MethodChannel(messenger, OVERLAY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkOverlayPermission", "isOverlayEnabled" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                else -> result.notImplemented()
            }
        }

        // ---------- Screenshot detection ----------
        val screenshotChannel = MethodChannel(messenger, SCREENSHOT_CHANNEL)
        screenshotObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                super.onChange(selfChange)
                Log.d("ScreenshotDetector", "📸 Screenshot detected!")
                screenshotChannel.invokeMethod("onScreenshot", null)
            }
        }

        try {
            contentResolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                true,
                screenshotObserver!!
            )
            Log.d("ScreenshotDetector", "✅ Screenshot observer registered.")
        } catch (e: Exception) {
            Log.e("ScreenshotDetector", "⚠️ Failed to register observer: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            screenshotObserver?.let {
                contentResolver.unregisterContentObserver(it)
                Log.d("ScreenshotDetector", "🧹 Screenshot observer unregistered.")
            }
        } catch (e: Exception) {
            Log.e("ScreenshotDetector", "⚠️ Failed to unregister observer: ${e.message}")
        }
    }
}
