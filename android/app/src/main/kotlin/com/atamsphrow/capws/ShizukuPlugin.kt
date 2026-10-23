package com.atamsphrow.capws

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.util.concurrent.Executors

/**
 * MethodChannel side of the native bridge. Nothing here does real work; it routes
 * calls to [PackageInspector] (unprivileged reads) and [ShizukuService] (privileged
 * writes), and pushes Shizuku connection changes up to Dart over an EventChannel.
 *
 * Every privileged call and the full inventory run on a background executor: the
 * shell fallback blocks on waitFor(), and a device with 400 apps takes long enough
 * to inventory that doing it on the platform thread would drop frames.
 */
class ShizukuPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL = "com.atamsphrow.capws/shizuku"
        private const val EVENT_CHANNEL = "com.atamsphrow.capws/shizuku_events"
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var events: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    // Shizuku dies and comes back on its own — ADB wifi sessions in particular — so
    // the UI is told about it instead of silently failing on the next write.
    private val binderReceived = Shizuku.OnBinderReceivedListener {
        emit(mapOf("event" to "binderReceived"))
    }
    private val binderDead = Shizuku.OnBinderDeadListener {
        emit(mapOf("event" to "binderDead"))
    }
    private val permissionResult =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode != ShizukuService.PERMISSION_REQUEST_CODE) {
                return@OnRequestPermissionResultListener
            }
            val granted = grantResult == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
            emit(mapOf("event" to "permissionResult", "granted" to granted))
        }

    fun attach() {
        ShizukuService.unlockHiddenApis()
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        // Sticky: fires immediately if Shizuku already handed us the binder through
        // ShizukuProvider before this Activity existed.
        Shizuku.addBinderReceivedListenerSticky(binderReceived)
        Shizuku.addBinderDeadListener(binderDead)
        Shizuku.addRequestPermissionResultListener(permissionResult)
    }

    fun detach() {
        Shizuku.removeBinderReceivedListener(binderReceived)
        Shizuku.removeBinderDeadListener(binderDead)
        Shizuku.removeRequestPermissionResultListener(permissionResult)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        pendingPermissionResult = null
        worker.shutdown()
    }

    // -------------------------------------------------------------- EventChannel

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun emit(payload: Map<String, Any?>) {
        main.post { events?.success(payload) }
    }

    // ------------------------------------------------------------- MethodChannel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getShizukuStatus" -> result.success(ShizukuService.status(activity))

            "requestShizukuPermission" -> requestShizukuPermission(result)

            "getInventory" -> onWorker(result) { PackageInspector.inventory(activity) }

            "getAppIcon" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName == null) {
                    result.error("bad_args", "packageName manquant", null)
                } else {
                    val size = call.argument<Int>("size") ?: 96
                    onWorker(result) { PackageInspector.appIcon(activity, packageName, size) }
                }
            }

            "setRuntimePermission" -> {
                val packageName = call.argument<String>("packageName")
                val permission = call.argument<String>("permission")
                val grant = call.argument<Boolean>("grant")
                if (packageName == null || permission == null || grant == null) {
                    result.error("bad_args", "packageName, permission ou grant manquant", null)
                } else {
                    onWorker(result) {
                        ShizukuService.setRuntimePermission(packageName, permission, grant)
                    }
                }
            }

            "setAppOp" -> {
                val packageName = call.argument<String>("packageName")
                val op = call.argument<String>("op")
                val allow = call.argument<Boolean>("allow")
                if (packageName == null || op == null || allow == null) {
                    result.error("bad_args", "packageName, op ou allow manquant", null)
                } else {
                    onWorker(result) { ShizukuService.setAppOp(packageName, op, allow) }
                }
            }

            "getAppOpMode" -> {
                val packageName = call.argument<String>("packageName")
                val op = call.argument<String>("op")
                if (packageName == null || op == null) {
                    result.error("bad_args", "packageName ou op manquant", null)
                } else {
                    onWorker(result) { ShizukuService.getAppOpMode(packageName, op) }
                }
            }

            "openAppSettings" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName == null) {
                    result.error("bad_args", "packageName manquant", null)
                } else {
                    result.success(openAppSettings(packageName))
                }
            }

            "openSpecialSetting" -> {
                val kind = call.argument<String>("kind") ?: ""
                val packageName = call.argument<String>("packageName")
                result.success(openSpecialSetting(kind, packageName))
            }

            "openShizukuInstall" -> result.success(openShizukuInstall())

            "launchShizuku" -> result.success(launchShizuku())

            else -> result.notImplemented()
        }
    }

    /** Runs [block] off the platform thread and replies on it. */
    private fun onWorker(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            val outcome = runCatching(block)
            main.post {
                outcome
                    .onSuccess { result.success(it) }
                    .onFailure { result.error("native_error", it.message, it.stackTraceToString()) }
            }
        }
    }

    private fun requestShizukuPermission(result: MethodChannel.Result) {
        if (!ShizukuService.isRunning()) {
            result.error("shizuku_unavailable", "Shizuku n'est pas actif.", null)
            return
        }
        if (ShizukuService.hasPermission()) {
            result.success(true)
            return
        }
        if (runCatching { Shizuku.isPreV11() }.getOrDefault(false)) {
            result.error(
                "shizuku_pre_v11",
                "Cette version de Shizuku est trop ancienne (pre-v11). Mets-la à jour.",
                null,
            )
            return
        }
        pendingPermissionResult?.error("cancelled", "Nouvelle demande de permission", null)
        pendingPermissionResult = result
        val requested = runCatching {
            Shizuku.requestPermission(ShizukuService.PERMISSION_REQUEST_CODE)
        }
        if (requested.isFailure) {
            pendingPermissionResult = null
            result.error(
                "request_failed",
                requested.exceptionOrNull()?.message ?: "Demande de permission impossible",
                null,
            )
        }
    }

    // ------------------------------------------------------------------- intents

    private fun startActivitySafely(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    private fun openAppSettings(packageName: String): Boolean = startActivitySafely(
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    )

    /**
     * Special permissions each have their own Settings screen and none of them can be
     * toggled by a third-party app directly. When Shizuku cannot do it either, this
     * is the honest fallback. Vendor ROMs sometimes drop these screens, so every
     * branch degrades to the app's own details page.
     */
    private fun openSpecialSetting(kind: String, packageName: String?): Boolean {
        val uri = packageName?.let { Uri.fromParts("package", it, null) }
        val intent = when (kind) {
            "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "usageAccess" -> Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            "overlay" -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, uri)
            "writeSettings" -> Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, uri)
            "notifications" -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)

            "allFiles" ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, uri)
                } else {
                    null
                }

            "installPackages" -> Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, uri)

            "exactAlarm" ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, uri)
                } else {
                    null
                }

            else -> null
        }

        val target = intent ?: return packageName?.let { openAppSettings(it) } ?: false
        if (startActivitySafely(target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))) return true
        return packageName?.let { openAppSettings(it) } ?: false
    }

    private fun openShizukuInstall(): Boolean {
        val market = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("market://details?id=${ShizukuService.SHIZUKU_PACKAGE}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (startActivitySafely(market)) return true
        return startActivitySafely(
            Intent(Intent.ACTION_VIEW, Uri.parse("https://shizuku.rikka.app/download/"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    private fun launchShizuku(): Boolean {
        val intent = activity.packageManager
            .getLaunchIntentForPackage(ShizukuService.SHIZUKU_PACKAGE)
            ?: return false
        return startActivitySafely(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
