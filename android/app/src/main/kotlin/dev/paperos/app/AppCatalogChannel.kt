package dev.paperos.app

import android.app.Activity
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Android side of PaperOS' application launcher support.
 *
 * Responsibilities, and nothing else:
 *  - enumerate launchable activities
 *  - render a launcher's icon as PNG bytes the Flutter layer can cache
 *  - start another package
 *  - report / request the HOME role
 *
 * All of it sits behind one [MethodChannel] so the Dart side has a single,
 * mockable seam ([dev.paperos.app.launcher.LauncherService]) and no widget ever
 * touches a platform channel directly.
 *
 * Package visibility: on API 30+ `queryIntentActivities` only returns packages
 * the manifest declares a `<queries>` entry for. That entry lives in
 * AndroidManifest.xml; without it this channel returns an empty list on modern
 * Android and would look like "no apps installed".
 */
class AppCatalogChannel(private val context: Context) {

    companion object {
        const val CHANNEL = "dev.paperos/app_catalog"

        private const val ERROR_UNAVAILABLE = "unavailable"
        private const val ERROR_NO_APP = "no_app"
        private const val ERROR_LAUNCH_FAILED = "launch_failed"
        private const val ERROR_ICON_FAILED = "icon_failed"

        /**
         * Request code for the HOME-role confirmation.
         *
         * The result itself is not consumed here: `PaperApp` refreshes the role
         * on resume. The request code matters because the platform permission
         * controller reads the caller from `getCallingPackage()`, which Android
         * only populates for `startActivityForResult`. A plain `startActivity`
         * makes the dialog fail silently with "Package name cannot be null".
         */
        private const val REQUEST_HOME_ROLE = 7201
    }

    /** Icons are rasterised off the main thread. 96px covers a 28dp tile at 3x. */
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "paperos-app-catalog").apply { isDaemon = true }
    }

    private val main = Handler(Looper.getMainLooper())

    /**
     * The hosting Flutter activity. Required on API 29+ because the HOME role
     * confirmation dialog must be started from an Activity context.
     */
    @Volatile
    private var hostActivity: Activity? = null

    fun setHostActivity(activity: Activity?) {
        hostActivity = activity
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(::onCall)
    }

    fun dispose() {
        executor.shutdownNow()
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadApps" -> executor.execute { loadApps(result) }
            "loadIcon" -> loadIcon(call, result)
            "launchApp" -> launchApp(call, result)
            "isHomeApp" -> result.success(isHomeApp())
            "requestHomeApp" -> requestHomeApp(result)
            "openHomeSettings" -> openHomeSettings(result)
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------- catalogue

    private fun loadApps(result: MethodChannel.Result) {
        try {
            val packageManager = context.packageManager
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            val resolved: List<ResolveInfo> =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.queryIntentActivities(
                        intent,
                        PackageManager.ResolveInfoFlags.of(0L),
                    )
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.queryIntentActivities(intent, 0)
                }

            val apps = ArrayList<Map<String, Any?>>(resolved.size)
            val seen = HashSet<String>(resolved.size * 2)

            for (info in resolved) {
                val activity: ActivityInfo = info.activityInfo ?: continue
                val packageName = activity.packageName ?: continue
                if (packageName == context.packageName) continue

                val key = "$packageName/${activity.name}"
                if (!seen.add(key)) continue

                val flags = activity.applicationInfo?.flags ?: 0
                val isSystem = (flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                    (flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0

                apps.add(
                    mapOf(
                        "packageName" to packageName,
                        "activityName" to activity.name,
                        "label" to safeLabel(packageManager, info, activity),
                        "isSystem" to isSystem,
                    ),
                )
            }

            // User-installed apps first, then alphabetical. A launcher list that
            // is 90% system components is a launcher list nobody can read.
            apps.sortWith(
                compareBy(
                    { !(it["isSystem"] as Boolean) },
                    { (it["label"] as String).lowercase() },
                ),
            )

            result.success(
                mapOf(
                    "apps" to apps,
                    "totalMatched" to resolved.size,
                    // On Android 11+ an incomplete package-visibility query
                    // usually resolves only this app itself. The Dart drawer
                    // explains that instead of claiming nothing is installed.
                    "restricted" to (resolved.size <= 1),
                ),
            )
        } catch (error: Throwable) {
            result.error(
                ERROR_UNAVAILABLE,
                "PaperOS could not read the list of installed apps.",
                error.toString(),
            )
        }
    }

    private fun safeLabel(
        packageManager: PackageManager,
        info: ResolveInfo,
        activity: ActivityInfo,
    ): String {
        val fromInfo = try {
            info.loadLabel(packageManager)?.toString()
        } catch (_: Throwable) {
            null
        }
        if (!fromInfo.isNullOrBlank()) return fromInfo.trim()

        val fromApp = try {
            activity.applicationInfo?.loadLabel(packageManager)?.toString()
        } catch (_: Throwable) {
            null
        }
        if (!fromApp.isNullOrBlank()) return fromApp.trim()

        return activity.name.substringAfterLast('.').ifEmpty { activity.name }
    }

    // -------------------------------------------------------------------- icons

    private fun loadIcon(call: MethodCall, result: MethodChannel.Result) {
        val packageName = call.argument<String>("packageName")
        if (packageName.isNullOrEmpty()) {
            result.error(ERROR_ICON_FAILED, "packageName is required", null)
            return
        }
        val sizePx = (call.argument<Number>("sizePx")?.toInt() ?: 96)
            .coerceIn(24, 256)

        executor.execute {
            try {
                val drawable = context.packageManager.getApplicationIcon(packageName)
                val bitmap = drawableToBitmap(drawable, sizePx)
                if (bitmap == null) {
                    main.post {
                        result.error(
                            ERROR_ICON_FAILED,
                            "The icon for $packageName could not be drawn.",
                            null,
                        )
                    }
                    return@execute
                }
                val stream = java.io.ByteArrayOutputStream(sizePx * sizePx)
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                bitmap.recycle()
                val bytes = stream.toByteArray()
                main.post { result.success(bytes) }
            } catch (error: Throwable) {
                main.post {
                    result.error(
                        ERROR_ICON_FAILED,
                        "The icon for $packageName could not be drawn.",
                        error.toString(),
                    )
                }
            }
        }
    }

    private fun drawableToBitmap(drawable: Drawable, sizePx: Int): Bitmap? {
        if (drawable is BitmapDrawable) {
            val source = drawable.bitmap
            if (source != null) {
                if (source.width == sizePx && source.height == sizePx) return source
                return Bitmap.createScaledBitmap(source, sizePx, sizePx, true)
            }
        }
        if (drawable.intrinsicWidth <= 0 || drawable.intrinsicHeight <= 0) return null
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, sizePx, sizePx)
        drawable.draw(canvas)
        return bitmap
    }

    // ------------------------------------------------------------------ launch

    private fun launchApp(call: MethodCall, result: MethodChannel.Result) {
        val packageName = call.argument<String>("packageName")
        if (packageName.isNullOrEmpty()) {
            result.error(ERROR_NO_APP, "packageName is required", null)
            return
        }
        val activityName = call.argument<String>("activityName")

        try {
            val intent = Intent()
            if (!activityName.isNullOrEmpty()) {
                intent.setComponent(ComponentName(packageName, activityName))
            } else {
                intent.setPackage(packageName)
            }
            if (intent.component == null) {
                val launch = context.packageManager.getLaunchIntentForPackage(packageName)
                if (launch == null) {
                    result.error(
                        ERROR_NO_APP,
                        "$packageName does not expose a launchable screen.",
                        null,
                    )
                    return
                }
                intent.component = launch.component
            }
            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
            )
            context.startActivity(intent)
            result.success(true)
        } catch (error: SecurityException) {
            result.error(
                ERROR_LAUNCH_FAILED,
                "Android refused to open $packageName.",
                error.toString(),
            )
        } catch (error: Throwable) {
            result.error(
                ERROR_LAUNCH_FAILED,
                "$packageName could not be opened.",
                error.toString(),
            )
        }
    }

    // ---------------------------------------------------------------- home role

    private fun isHomeApp(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = context.getSystemService(RoleManager::class.java)
            return roleManager != null &&
                roleManager.isRoleAvailable(RoleManager.ROLE_HOME) &&
                roleManager.isRoleHeld(RoleManager.ROLE_HOME)
        }
        // Pre-Android 10: "is home" means "is the only / first HOME handler".
        val own = ownHomeComponent() ?: return false
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = context.packageManager.queryIntentActivities(intent, 0)
        if (resolved.isEmpty()) return false
        return resolved.first().activityInfo?.let {
            ComponentName(it.packageName, it.name) == own
        } ?: false
    }

    private fun ownHomeComponent(): ComponentName? {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = context.packageManager.queryIntentActivities(intent, 0)
        val info = resolved.firstOrNull { it.activityInfo?.packageName == context.packageName }
            ?.activityInfo ?: return null
        return ComponentName(info.packageName, info.name)
    }

    /**
     * Starts the platform confirmation flow for the HOME role.
     *
     * API 29+ shows a system dialog created by
     * [RoleManager.createRequestRoleIntent]. Below API 29 there is no role API,
     * so the user is sent to the home-app picker in Settings.
     *
     * Returns a map describing which flow was started, because the Dart side
     * needs to show different copy for each:
     *   - `role_request` : system dialog opened
     *   - `settings`     : Settings screen opened (pre-Android 10)
     *   - `already`      : PaperOS already holds the role
     *   - `unavailable`  : this device will not let PaperOS be the home app
     */
    private fun requestHomeApp(result: MethodChannel.Result) {
        val activity = hostActivity

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = activity?.getSystemService(RoleManager::class.java)
            if (roleManager == null || !roleManager.isRoleAvailable(RoleManager.ROLE_HOME)) {
                result.success(mapOf("flow" to "unavailable", "isHomeApp" to false))
                return
            }
            if (roleManager.isRoleHeld(RoleManager.ROLE_HOME)) {
                result.success(mapOf("flow" to "already", "isHomeApp" to true))
                return
            }
            try {
                activity.startActivityForResult(
                    roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME),
                    REQUEST_HOME_ROLE,
                )
                result.success(mapOf("flow" to "role_request", "isHomeApp" to false))
            } catch (error: Throwable) {
                result.success(mapOf("flow" to "unavailable", "isHomeApp" to false))
            }
            return
        }

        try {
            val intent = Intent(Settings.ACTION_HOME_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            (activity ?: context).startActivity(intent)
            result.success(mapOf("flow" to "settings", "isHomeApp" to false))
        } catch (error: Throwable) {
            result.success(mapOf("flow" to "unavailable", "isHomeApp" to false))
        }
    }

    private fun openHomeSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_HOME_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            (activityOrContext()).startActivity(intent)
            result.success(true)
        } catch (error: Throwable) {
            result.error(
                ERROR_UNAVAILABLE,
                "The home app settings screen could not be opened.",
                error.toString(),
            )
        }
    }

    private fun activityOrContext(): Context = hostActivity ?: context
}
