package dev.paperos.app

import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Classifies the activity intents that are not documents.
 *
 * `FileBrowserChannel` owns `ACTION_VIEW`, because a VIEW intent is a document
 * to import and open. Everything else is launcher traffic: pressing Home, or
 * tapping the PaperOS icon while it is already running. Those must reset the
 * Flutter hierarchy to Paper Home instead of leaving the user inside whatever
 * screen they last used.
 *
 * The channel is deliberately tiny. It does not read the role, launch apps, or
 * touch storage; it answers one question — "why did Android bring us here?" —
 * and delivers the answer exactly once.
 */
class SystemIntentChannel {

    companion object {
        const val CHANNEL = "dev.paperos/system_intent"

        const val KIND_HOME = "home"
        const val KIND_LAUNCHER = "launcher"
        const val KIND_VIEW = "view"
    }

    private var channel: MethodChannel? = null
    private var dartReady = false

    /** An intent that arrived before Dart installed its handler. */
    private var pending: String? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { methodChannel ->
            methodChannel.setMethodCallHandler(::onCall)
        }
    }

    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
        dartReady = false
        pending = null
    }

    /**
     * A cold start delivers the intent through [android.app.Activity.getIntent],
     * not through onNewIntent. Stash it until Dart asks for it.
     */
    fun setInitialIntent(intent: Intent?) {
        val kind = classify(intent) ?: return
        pending = kind
    }

    /**
     * A warm start (Home pressed again, or the launcher icon tapped) arrives
     * here. Deliver immediately when Dart is listening; otherwise keep it for
     * the next `ready` call.
     */
    fun handleNewIntent(intent: Intent?) {
        val kind = classify(intent) ?: return
        val active = channel
        if (dartReady && active != null) {
            active.invokeMethod("systemIntent", kind)
        } else {
            pending = kind
        }
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Dart is installed. Hand over anything stashed during startup and
            // from this point on use direct callbacks.
            "ready" -> {
                dartReady = true
                result.success(pending)
                pending = null
            }
            // A resume drain, for the same reason FileBrowserChannel has one:
            // an intent delivered while the engine was paused must not be lost.
            "takePending" -> {
                result.success(pending)
                pending = null
            }
            else -> result.notImplemented()
        }
    }

    private fun classify(intent: Intent?): String? {
        if (intent == null) return null
        val categories = intent.categories ?: emptySet()
        if (intent.action == Intent.ACTION_MAIN && categories.contains(Intent.CATEGORY_HOME)) {
            return KIND_HOME
        }
        if (intent.action == Intent.ACTION_MAIN && categories.contains(Intent.CATEGORY_LAUNCHER)) {
            return KIND_LAUNCHER
        }
        if (intent.action == Intent.ACTION_VIEW) return KIND_VIEW
        return null
    }
}
