package com.ledgy.ledgy

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.speech.SpeechRecognizer

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ledgy.ledgy2/speech")
            .setMethodCallHandler { call, result ->
                if (call.method == "supportsOnDevice") {
                    val available = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
                    result.success(available)
                } else {
                    result.notImplemented()
                }
            }
    }
}
