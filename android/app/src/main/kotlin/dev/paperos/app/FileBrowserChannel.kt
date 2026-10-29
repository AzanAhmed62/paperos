package dev.paperos.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Android side of the PaperOS folder browser.
 *
 * PaperOS declares no storage permission, so a file browser can only exist on
 * top of the Storage Access Framework: the user grants one folder through the
 * system picker, the grant is persisted, and every listing and read afterwards
 * is a `ContentResolver` call scoped to that grant.
 *
 * One [MethodChannel] carries the whole feature so that the Dart layer has a
 * single seam ([dev.paperos.platform.file_browser_service.FileBrowserService])
 * and no widget ever touches a platform channel.
 *
 * It also carries `ACTION_VIEW` intents ("Open with PaperOS"): the intent is
 * stashed and either handed to the running app through `onExternalDocument` or
 * collected once at startup through `takeExternalDocument`.
 */
class FileBrowserChannel(private val context: Context) {

    companion object {
        const val CHANNEL = "dev.paperos/files"

        private const val REQUEST_TREE = 0x0F17

        private const val ERROR_UNAVAILABLE = "unavailable"
        private const val ERROR_ACCESS = "access_denied"
        private const val ERROR_UNKNOWN = "unknown"

        /** Everything copied out of a tree lands in this cache sub-directory. */
        private const val CACHE_DIR = "browser"
    }

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "paperos-files").apply { isDaemon = true }
    }

    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var hostActivity: Activity? = null

    private var channel: MethodChannel? = null

    /** The Dart result waiting on the folder picker, if one is open. */
    private var pendingPick: MethodChannel.Result? = null

    /** The most recent `ACTION_VIEW` document, consumed on request. */
    @Volatile
    private var pendingExternal: Map<String, Any?>? = null

    fun setHostActivity(activity: Activity?) {
        hostActivity = activity
    }

    fun attach(messenger: BinaryMessenger) {
        val methodChannel = MethodChannel(messenger, CHANNEL)
        methodChannel.setMethodCallHandler(::onCall)
        channel = methodChannel
    }

    fun dispose() {
        executor.shutdownNow()
        channel?.setMethodCallHandler(null)
        channel = null
        pendingPick = null
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickLocation" -> pickLocation(result)
            "listChildren" -> listChildren(call, result)
            "materialise" -> materialise(call, result)
            "releaseLocation" -> releaseLocation(call, result)
            "takeExternalDocument" -> takeExternalDocument(result)
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------- locations

    private fun pickLocation(result: MethodChannel.Result) {
        val activity = hostActivity
        if (activity == null) {
            result.error(ERROR_UNAVAILABLE, "PaperOS has no window to show the picker in.", null)
            return
        }
        if (pendingPick != null) {
            result.error(ERROR_UNKNOWN, "A folder picker is already open.", null)
            return
        }
        pendingPick = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
            activity.startActivityForResult(intent, REQUEST_TREE)
        } catch (error: Throwable) {
            pendingPick = null
            result.error(ERROR_UNAVAILABLE, "This device has no folder picker.", error.toString())
        }
    }

    /**
     * Called from the host activity. Returns true when the result belonged to
     * the folder picker, so the activity knows not to forward it any further.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_TREE) return false
        val result = pendingPick ?: return true
        pendingPick = null

        val uri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            result.success(null)
            return true
        }

        // A read grant is what makes the folder usable at all next launch. If
        // the provider refuses to persist it, browsing still works this session.
        try {
            context.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: Throwable) {
            // Not fatal.
        }

        val label = queryDisplayName(uri) ?: uri.lastPathSegment ?: "Folder"
        result.success(mapOf("uri" to uri.toString(), "label" to label))
        return true
    }

    private fun queryDisplayName(treeUri: Uri): String? {
        return try {
            val documentId = DocumentsContract.getTreeDocumentId(treeUri)
            val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
            context.contentResolver.query(
                documentUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun listChildren(call: MethodCall, result: MethodChannel.Result) {
        val treeUriString = call.argument<String>("treeUri")
        if (treeUriString.isNullOrEmpty()) {
            result.error(ERROR_UNKNOWN, "treeUri is required.", null)
            return
        }
        val directoryUriString = call.argument<String>("directoryUri")

        executor.execute {
            try {
                val treeUri = Uri.parse(treeUriString)
                val parentId = if (directoryUriString.isNullOrEmpty()) {
                    DocumentsContract.getTreeDocumentId(treeUri)
                } else {
                    DocumentsContract.getDocumentId(Uri.parse(directoryUriString))
                }
                val childrenUri =
                    DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)

                val projection = arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                )

                val entries = ArrayList<Map<String, Any?>>()
                context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                    while (cursor.moveToNext()) {
                        val documentId = cursor.getString(0) ?: continue
                        val name = cursor.getString(1) ?: continue
                        val mimeType = cursor.getString(2)
                        val size = if (cursor.isNull(3)) null else cursor.getLong(3)
                        val modified = if (cursor.isNull(4)) null else cursor.getLong(4)
                        val documentUri =
                            DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)

                        entries.add(
                            mapOf(
                                "uri" to documentUri.toString(),
                                "name" to name,
                                "isDirectory" to
                                    (mimeType == DocumentsContract.Document.MIME_TYPE_DIR),
                                "mimeType" to mimeType,
                                "byteSize" to size,
                                "lastModified" to modified,
                            ),
                        )
                    }
                }

                // Folders first, then alphabetical: the order a person expects
                // from a file list.
                entries.sortWith(
                    compareBy({ !(it["isDirectory"] as Boolean) }, { (it["name"] as String).lowercase() }),
                )

                main.post { result.success(entries) }
            } catch (error: SecurityException) {
                main.post {
                    result.error(
                        ERROR_ACCESS,
                        "PaperOS is not allowed to read that folder.",
                        error.toString(),
                    )
                }
            } catch (error: Throwable) {
                main.post {
                    result.error(
                        ERROR_UNKNOWN,
                        "That folder could not be listed.",
                        error.toString(),
                    )
                }
            }
        }
    }

    private fun materialise(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrEmpty()) {
            result.error(ERROR_UNKNOWN, "uri is required.", null)
            return
        }
        val name = call.argument<String>("name") ?: "document"

        executor.execute {
            try {
                val uri = Uri.parse(uriString)
                val directory = File(context.cacheDir, CACHE_DIR)
                if (!directory.exists() && !directory.mkdirs()) {
                    throw java.io.IOException("Could not create the cache directory.")
                }
                val target = File(directory, sanitise(name))

                val input = context.contentResolver.openInputStream(uri)
                    ?: throw java.io.FileNotFoundException(uriString)
                input.use { source ->
                    target.outputStream().use { sink -> source.copyTo(sink) }
                }

                main.post { result.success(target.absolutePath) }
            } catch (error: SecurityException) {
                main.post {
                    result.error(
                        ERROR_ACCESS,
                        "PaperOS is not allowed to read that file.",
                        error.toString(),
                    )
                }
            } catch (error: Throwable) {
                main.post {
                    result.error(
                        ERROR_UNKNOWN,
                        "That file could not be read.",
                        error.toString(),
                    )
                }
            }
        }
    }

    private fun releaseLocation(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrEmpty()) {
            result.success(false)
            return
        }
        try {
            context.contentResolver.releasePersistableUriPermission(
                Uri.parse(uriString),
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            result.success(true)
        } catch (error: Throwable) {
            // Releasing is best effort; the row is gone either way.
            result.success(false)
        }
    }

    // -------------------------------------------------------- external intents

    /** Stashes the intent the activity launched with, if it is a VIEW. */
    fun setInitialIntent(intent: Intent?) {
        stash(intent)
    }

    /** Called from the host activity for every later VIEW intent. */
    fun handleNewIntent(intent: Intent?) {
        val map = stash(intent) ?: return
        main.post { channel?.invokeMethod("onExternalDocument", map) }
    }

    private fun stash(intent: Intent?): Map<String, Any?>? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        val data: Uri = intent.data ?: return null
        val map = mapOf(
            "uri" to data.toString(),
            "name" to intentName(intent, data),
            "mimeType" to intent.type,
        )
        pendingExternal = map
        return map
    }

    private fun intentName(intent: Intent, data: Uri): String {
        // Some apps put a readable name in EXTRA_TITLE; otherwise ask the
        // provider; otherwise fall back to the last path segment.
        val fromExtra = intent.getStringExtra(Intent.EXTRA_TITLE)
        if (!fromExtra.isNullOrBlank()) return fromExtra
        queryDisplayName(data)?.let { if (it.isNotBlank()) return it }
        return data.lastPathSegment ?: "document"
    }

    private fun takeExternalDocument(result: MethodChannel.Result) {
        val pending = pendingExternal
        pendingExternal = null
        result.success(pending)
    }

    // ----------------------------------------------------------------- utils

    /** Strips path separators so a provider-supplied name cannot escape. */
    private fun sanitise(name: String): String {
        val cleaned = name
            .replace('/', '_')
            .replace('\\', '_')
            .replace("\u0000", "")
            .trim()
        return cleaned.ifEmpty { "document" }
    }
}
