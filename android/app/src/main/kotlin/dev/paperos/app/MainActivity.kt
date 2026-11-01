package dev.paperos.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * The single PaperOS activity.
 *
 * It carries three intent filters (see AndroidManifest.xml):
 *  - MAIN + LAUNCHER : PaperOS as a normal app
 *  - MAIN + HOME + DEFAULT : PaperOS as a selectable home app
 *  - MAIN + VIEW for `application/pdf` and `text/plain` : "Open with PaperOS"
 *
 * All platform channels are attached in [configureFlutterEngine] and released
 * in [cleanUpFlutterEngine], so no native object outlives the engine.
 */
class MainActivity : FlutterActivity() {

    private var appCatalog: AppCatalogChannel? = null
    private var pdfRender: PdfRenderChannel? = null
    private var keepScreenOn: KeepScreenOnChannel? = null
    private var fileBrowser: FileBrowserChannel? = null
    private var safFiles: SafFileChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        appCatalog = AppCatalogChannel(this).also { channel ->
            channel.setHostActivity(this)
            channel.attach(messenger)
        }

        pdfRender = PdfRenderChannel().also { channel ->
            channel.setContext(this)
            channel.attach(messenger)
        }

        keepScreenOn = KeepScreenOnChannel().also { channel ->
            channel.setActivity(this)
            channel.attach(messenger)
        }

        fileBrowser = FileBrowserChannel(this).also { channel ->
            channel.setHostActivity(this)
            // A cold start from "Open with" carries the document in the
            // activity's own intent, which will never reach onNewIntent.
            channel.setInitialIntent(intent)
            channel.attach(messenger)
        }

        safFiles = SafFileChannel(this).also { channel ->
            channel.setHostActivity(this)
            channel.attach(messenger)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        fileBrowser?.handleNewIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // The folder picker owns one request code; everything else belongs to
        // the Flutter embedding (plugins) and must fall through to super.
        val handledByBrowser = fileBrowser?.onActivityResult(requestCode, resultCode, data) == true
        val handledBySaf = safFiles?.onActivityResult(requestCode, resultCode, data) == true
        if (!handledByBrowser && !handledBySaf) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        appCatalog?.dispose()
        pdfRender?.dispose()
        keepScreenOn?.dispose()
        fileBrowser?.dispose()
        safFiles?.dispose()
        appCatalog = null
        pdfRender = null
        keepScreenOn = null
        fileBrowser = null
        safFiles = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
