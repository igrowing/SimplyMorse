package com.simplytools.simplymorse

import android.content.Context
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "simplymorse/platform"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Whether this device delivers raw mic audio via
                // AudioSource.UNPROCESSED (API 24+). "false" means the
                // vendor HAL may still apply processing even when the
                // UNPROCESSED source is requested.
                "getUnprocessedSupport" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        val audioManager =
                            getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        result.success(
                            audioManager.getProperty(
                                AudioManager.PROPERTY_SUPPORT_AUDIO_UNPROCESSED
                            ) == "true"
                        )
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
