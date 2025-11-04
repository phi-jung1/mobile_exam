package com.example.mo_be

import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.content.res.Configuration
import android.app.Activity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MainActivity : FlutterActivity() {

    private val OVERLAY_CHANNEL = "overlay_detector"
    private val SCREENSHOT_CHANNEL = "screenshot_detector"
    private val SPLIT_SCREEN_CHANNEL = "split_screen_detector"

    private var screenshotObserver: ContentObserver? = null
    private var splitScreenChannel: MethodChannel? = null

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

        // ---------- Split Screen detection ----------
        splitScreenChannel = MethodChannel(messenger, SPLIT_SCREEN_CHANNEL)
        
        splitScreenChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkSplitScreen" -> {
                    val isInSplitScreen = isInMultiWindowMode()
                    Log.d("SplitScreenDetector", "🔍 Split screen check: $isInSplitScreen")
                    result.success(isInSplitScreen)
                }
                else -> result.notImplemented()
            }
        }
        
        // Check split screen immediately on start
        checkAndNotifySplitScreen()
    }

    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        
        Log.d("SplitScreenDetector", "📱 Multi-window mode changed: $isInMultiWindowMode")
        
        // Notify Flutter immediately
        splitScreenChannel?.invokeMethod("onSplitScreenChanged", mapOf(
            "isInSplitScreen" to isInMultiWindowMode
        ))
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        
        // Additional check on configuration changes
        val isInSplitScreen = isInMultiWindowMode()
        Log.d("SplitScreenDetector", "⚙️ Configuration changed. Split screen: $isInSplitScreen")
        
        splitScreenChannel?.invokeMethod("onSplitScreenChanged", mapOf(
            "isInSplitScreen" to isInSplitScreen
        ))
    }

    override fun onResume() {
        super.onResume()
        // Check split screen when app resumes
        checkAndNotifySplitScreen()
    }

    private fun checkAndNotifySplitScreen() {
        val isInSplitScreen = isInMultiWindowMode()
        Log.d("SplitScreenDetector", "🔄 Checking split screen status: $isInSplitScreen")
        
        splitScreenChannel?.invokeMethod("onSplitScreenChanged", mapOf(
            "isInSplitScreen" to isInSplitScreen
        ))
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