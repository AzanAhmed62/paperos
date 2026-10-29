package dev.paperos.app

import android.app.Activity
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Keeps the display awake while a document is open.
 *
 * Uses `FLAG_KEEP_SCREEN_ON` rather than a `WakeLock`:
 *  - no `WAKE_LOCK` permission is required
 *  - the flag is tied to PaperOS' own window, so it cannot keep the screen on
 *    after the user leaves
 *  - it costs one window-flag mutation and nothing else
 */
class KeepScreenOnChannel {

    companion object {
        const val CHANNEL = "dev.paperos/keep_screen_on"
    }

    private var activity: Activity? = null

    fun setActivity(activity: Activity) {
        this.activity = activity
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(::onCall)
    }

    fun dispose() {
        activity = null
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setKeepScreenOn" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                apply(enabled)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun apply(enabled: Boolean) {
        val host = activity
        if (host == null) {
            // Nothing to hold awake; report success so Dart does not retry.
            return
        }
        host.runOnUiThread {
            val window = host.window ?: return@runOnUiThread
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }
}
