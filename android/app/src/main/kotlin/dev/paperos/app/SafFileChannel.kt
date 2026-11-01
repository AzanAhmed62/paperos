package dev.paperos.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Storage Access Framework bridge for full backups.
 *
 * `file_picker` is fine for books, but it returns a byte array for saves. A
 * complete library can be hundreds of megabytes, so backup restore uses its
 * own channel that streams to and from a content URI. Nothing here requests a
 * storage permission: ACTION_OPEN_DOCUMENT and ACTION_CREATE_DOCUMENT give
 * scoped access to exactly the file the user chose.
 */
class SafFileChannel(private val context: Context) {

    companion object {
        const val CHANNEL = "dev.paperos/saf"

        private const val REQUEST_OPEN = 0x0F18
        private const val REQUEST_CREATE = 0x0F19
        private const val CACHE_DIR = "saf-imports"
        private const val BUFFER = 64 * 1024

        private const val ERROR_UNAVAILABLE = "unavailable"
        private const val ERROR_IO = "io"
        private const val ERROR_LIMIT = "too_large"
    }

    private sealed interface Pending {
        val result: MethodChannel.Result
    }

    private data class PendingOpen(
        override val result: MethodChannel.Result,
        val maxBytes: Long,
    ) : Pending

    private data class PendingCreate(
        override val result: MethodChannel.Result,
        val source: File,
    ) : Pending

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "paperos-saf").apply { isDaemon = true }
    }
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var hostActivity: Activity? = null
    private var channel: MethodChannel? = null
    private var pending: Pending? = null

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
        pending = null
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickBackup" -> pickBackup(call, result)
            "saveBackup" -> saveBackup(call, result)
            else -> result.notImplemented()
        }
    }

    private fun pickBackup(call: MethodCall, result: MethodChannel.Result) {
        val activity = hostActivity
        if (activity == null) {
            result.error(ERROR_UNAVAILABLE, "PaperOS has no window for the picker.", null)
            return
        }
        if (pending != null) {
            result.error(ERROR_IO, "A file picker is already open.", null)
            return
        }
        val maxBytes = (call.argument<Number>("maxBytes") ?: 0).toLong()
        if (maxBytes <= 0) {
            result.error(ERROR_IO, "Invalid backup size limit.", null)
            return
        }
        pending = PendingOpen(result, maxBytes)
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/zip", "application/octet-stream"))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivityForResult(intent, REQUEST_OPEN)
        } catch (error: Throwable) {
            pending = null
            result.error(ERROR_UNAVAILABLE, "This device has no file picker.", error.toString())
        }
    }

    private fun saveBackup(call: MethodCall, result: MethodChannel.Result) {
        val activity = hostActivity
        if (activity == null) {
            result.error(ERROR_UNAVAILABLE, "PaperOS has no window for the picker.", null)
            return
        }
        if (pending != null) {
            result.error(ERROR_IO, "A file picker is already open.", null)
            return
        }
        val sourcePath = call.argument<String>("sourcePath") ?: ""
        val suggestedName = call.argument<String>("suggestedName") ?: "PaperOS Backup.paperosbackup"
        val mimeType = call.argument<String>("mimeType") ?: "application/zip"
        val source = File(sourcePath)
        if (!source.isFile || !source.canRead()) {
            result.error(ERROR_IO, "The finished backup is no longer available.", null)
            return
        }
        pending = PendingCreate(result, source)
        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType
                putExtra(Intent.EXTRA_TITLE, safeName(suggestedName))
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            activity.startActivityForResult(intent, REQUEST_CREATE)
        } catch (error: Throwable) {
            pending = null
            result.error(ERROR_UNAVAILABLE, "This device has no save picker.", error.toString())
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val current = pending
        if (requestCode != REQUEST_OPEN && requestCode != REQUEST_CREATE) return false
        if (current == null) return true
        pending = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            main.post { current.result.success(null) }
            return true
        }
        when (current) {
            is PendingOpen -> executor.execute { copyIn(current, uri) }
            is PendingCreate -> executor.execute { copyOut(current, uri) }
        }
        return true
    }

    private fun copyIn(current: PendingOpen, uri: Uri) {
        val directory = File(context.cacheDir, CACHE_DIR)
        if (!directory.exists() && !directory.mkdirs()) {
            fail(current.result, ERROR_IO, "PaperOS could not prepare its import cache.")
            return
        }
        val target = File(directory, "backup-${System.currentTimeMillis()}.paperosbackup")
        try {
            var copied = 0L
            context.contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output ->
                    val buffer = ByteArray(BUFFER)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        copied += read
                        if (copied > current.maxBytes) {
                            target.delete()
                            fail(
                                current.result,
                                ERROR_LIMIT,
                                "That backup is larger than PaperOS can restore on this device.",
                            )
                            return
                        }
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                }
            } ?: run {
                target.delete()
                fail(current.result, ERROR_IO, "The selected file could not be opened.")
                return
            }
            val name = displayName(uri) ?: target.name
            main.post {
                current.result.success(
                    mapOf(
                        "path" to target.absolutePath,
                        "name" to name,
                        "bytes" to copied,
                    ),
                )
            }
        } catch (error: Throwable) {
            target.delete()
            fail(current.result, ERROR_IO, "PaperOS could not read that backup.", error.toString())
        }
    }

    private fun copyOut(current: PendingCreate, uri: Uri) {
        try {
            context.contentResolver.openOutputStream(uri, "wt")?.use { output ->
                current.source.inputStream().use { input ->
                    val buffer = ByteArray(BUFFER)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                }
            } ?: run {
                fail(current.result, ERROR_IO, "The selected destination could not be opened.")
                return
            }
            main.post { current.result.success(true) }
        } catch (error: Throwable) {
            fail(current.result, ERROR_IO, "PaperOS could not save the backup.", error.toString())
        }
    }

    private fun displayName(uri: Uri): String? {
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
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

    private fun fail(result: MethodChannel.Result, code: String, message: String, detail: String? = null) {
        main.post { result.error(code, message, detail) }
    }

    private fun safeName(name: String): String {
        val cleaned = name
            .replace('/', '_')
            .replace('\\', '_')
            .replace("\u0000", "")
            .trim()
        return cleaned.ifEmpty { "PaperOS Backup.paperosbackup" }
    }
}
