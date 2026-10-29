package dev.paperos.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.Closeable
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Android side of the PaperOS PDF reader.
 *
 * Uses the platform [PdfRenderer] (API 21+), which means:
 *  - no PDFium binary is shipped inside the APK
 *  - only pages that are actually on screen are ever rasterised
 *  - the Dart side never holds a whole document, only PNG bytes for the page
 *    currently visible plus at most one prefetched neighbour
 *
 * [PdfRenderer] allows only one open [PdfRenderer.Page] at a time, so every
 * operation is funnelled through a single worker thread. That also keeps
 * rasterisation off the platform main thread.
 */
class PdfRenderChannel {

    companion object {
        const val CHANNEL = "dev.paperos/pdf"

        const val ERROR_MISSING = "missing_file"
        const val ERROR_CORRUPT = "corrupt"
        const val ERROR_RANGE = "out_of_range"
        const val ERROR_UNKNOWN_HANDLE = "unknown_handle"
        const val ERROR_CLOSED = "closed"

        private const val MAX_WIDTH_PX = 2048
        private const val MIN_WIDTH_PX = 160
    }

    private class OpenDocument(
        val descriptor: ParcelFileDescriptor,
        val renderer: PdfRenderer,
    ) : Closeable {
        val pageCount: Int get() = renderer.pageCount

        override fun close() {
            runCatching { renderer.close() }
            runCatching { descriptor.close() }
        }
    }

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "paperos-pdf").apply { isDaemon = true }
    }

    private val main = Handler(Looper.getMainLooper())

    /** Open documents keyed by the opaque handle handed to Dart. */
    private val openDocuments = ConcurrentHashMap<String, OpenDocument>()

    private var handleCounter = 0L

    @Volatile
    private var appContext: Context? = null

    fun setContext(context: Context) {
        appContext = context.applicationContext
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(::onCall)
    }

    fun dispose() {
        executor.execute { closeAll() }
        executor.shutdown()
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> openDocument(call, result)
            "renderPage" -> renderPage(call, result)
            "close" -> closeDocument(call, result)
            "closeAll" -> executor.execute {
                closeAll()
                main.post { result.success(true) }
            }
            else -> result.notImplemented()
        }
    }

    // --------------------------------------------------------------------- open

    private fun openDocument(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error(ERROR_MISSING, "No file path was supplied.", null)
            return
        }

        executor.execute {
            var descriptor: ParcelFileDescriptor? = null
            try {
                descriptor = openDescriptor(path)
                val renderer = PdfRenderer(descriptor)
                val document = OpenDocument(descriptor, renderer)
                val id = "pdf${handleCounter++}"
                openDocuments[id] = document

                // First page geometry lets Dart reserve the right aspect ratio
                // before the first render completes, which stops the page from
                // resizing as it loads.
                var widthPt = 0.0
                var heightPt = 0.0
                if (document.pageCount > 0) {
                    document.renderer.openPage(0).use { page ->
                        widthPt = page.width.toDouble()
                        heightPt = page.height.toDouble()
                    }
                }

                main.post {
                    result.success(
                        mapOf(
                            "handle" to id,
                            "pageCount" to document.pageCount,
                            "pageWidthPt" to widthPt,
                            "pageHeightPt" to heightPt,
                        ),
                    )
                }
            } catch (error: SecurityException) {
                closeQuietly(descriptor)
                main.post {
                    result.error(
                        ERROR_MISSING,
                        "PaperOS is not allowed to read that file.",
                        error.toString(),
                    )
                }
            } catch (error: OutOfMemoryError) {
                closeQuietly(descriptor)
                main.post {
                    result.error(
                        ERROR_CORRUPT,
                        "This PDF is too large or too damaged for this device to open.",
                        error.toString(),
                    )
                }
            } catch (error: Throwable) {
                closeQuietly(descriptor)
                main.post {
                    result.error(
                        ERROR_CORRUPT,
                        "This PDF could not be opened. It may be damaged, or not a PDF at all.",
                        error.toString(),
                    )
                }
            }
        }
    }

    private fun openDescriptor(path: String): ParcelFileDescriptor {
        if (path.startsWith("content://")) {
            val context = appContext
                ?: throw java.io.FileNotFoundException("No context available for $path")
            // openFileDescriptor returns null for providers that only expose a
            // pipe. A pipe cannot be memory mapped, and PdfRenderer requires a
            // seekable descriptor, so this is a real (if uncommon) limitation.
            return context.contentResolver.openFileDescriptor(Uri.parse(path), "r")
                ?: throw java.io.FileNotFoundException(
                    "The document provider returned no seekable file for $path",
                )
        }
        val file = java.io.File(path.removePrefix("file://"))
        if (!file.exists()) throw java.io.FileNotFoundException(path)
        if (!file.canRead()) throw SecurityException("Not readable: $path")
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    // --------------------------------------------------------------- rendering

    private fun renderPage(call: MethodCall, result: MethodChannel.Result) {
        val handleId = call.argument<String>("handle")
        val pageIndex = call.argument<Number>("pageIndex")?.toInt()
        if (handleId == null || pageIndex == null) {
            result.error(ERROR_UNKNOWN_HANDLE, "handle and pageIndex are required.", null)
            return
        }

        val requestedWidth =
            (call.argument<Number>("widthPx")?.toDouble() ?: 1080.0).roundToInt()
        val width = requestedWidth.coerceIn(MIN_WIDTH_PX, MAX_WIDTH_PX)

        executor.execute {
            val document = openDocuments[handleId]
            if (document == null) {
                main.post { result.error(ERROR_CLOSED, "This PDF is no longer open.", null) }
                return@execute
            }
            if (pageIndex < 0 || pageIndex >= document.pageCount) {
                main.post {
                    result.error(
                        ERROR_RANGE,
                        "Page ${pageIndex + 1} is outside this document.",
                        null,
                    )
                }
                return@execute
            }

            var bitmap: Bitmap? = null
            try {
                val encoded: ByteArray
                val pageHeight: Int

                document.renderer.openPage(pageIndex).use { page ->
                    val scale = width.toFloat() / max(1, page.width)
                    val height = max(1, (page.height * scale).roundToInt())
                    val target = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    // PaperOS draws pages on white. A PDF page with
                    // transparency would otherwise render black in the dark
                    // theme, which is exactly the wrong thing to do with paper.
                    target.eraseColor(Color.WHITE)
                    val transform = Matrix().apply { postScale(scale, scale) }
                    val clip = Rect(0, 0, width, height)
                    page.render(
                        target,
                        clip,
                        transform,
                        PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY,
                    )
                    bitmap = target
                    pageHeight = target.height

                    val stream = java.io.ByteArrayOutputStream(width * 2)
                    target.compress(Bitmap.CompressFormat.PNG, 100, stream)
                    encoded = stream.toByteArray()
                }

                main.post {
                    result.success(
                        mapOf(
                            "width" to width,
                            "height" to pageHeight,
                            "png" to encoded,
                        ),
                    )
                }
            } catch (error: OutOfMemoryError) {
                main.post {
                    result.error(
                        ERROR_CORRUPT,
                        "This page needs more memory than the device has available.",
                        error.toString(),
                    )
                }
            } catch (error: Throwable) {
                main.post {
                    result.error(
                        ERROR_CORRUPT,
                        "Page ${pageIndex + 1} could not be drawn.",
                        error.toString(),
                    )
                }
            } finally {
                bitmap?.recycle()
            }
        }
    }

    // -------------------------------------------------------------------- close

    private fun closeDocument(call: MethodCall, result: MethodChannel.Result) {
        val handleId = call.argument<String>("handle")
        result.success(true)
        if (handleId == null) return
        executor.execute { openDocuments.remove(handleId)?.close() }
    }

    private fun closeAll() {
        val documents = openDocuments.values.toList()
        openDocuments.clear()
        documents.forEach { it.close() }
    }

    private fun closeQuietly(descriptor: ParcelFileDescriptor?) {
        runCatching { descriptor?.close() }
    }
}
