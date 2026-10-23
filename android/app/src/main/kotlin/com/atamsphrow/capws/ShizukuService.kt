package com.atamsphrow.capws

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import org.lsposed.hiddenapibypass.HiddenApiBypass
import rikka.shizuku.Shizuku
import rikka.shizuku.ShizukuBinderWrapper
import rikka.shizuku.SystemServiceHelper
import java.io.InputStream

/**
 * Everything that needs elevated privileges goes through here.
 *
 * Two independent paths are implemented on purpose:
 *
 *  1. the binder path, which reflects on the hidden IPermissionManager (API 30+) or
 *     IPackageManager (API < 30) through a [ShizukuBinderWrapper]. Fast, and it
 *     reports a real result — but the signature of grantRuntimePermission has moved
 *     around between releases (it gained a persistentDeviceId argument on Android
 *     14), so every overload is probed at runtime rather than assumed.
 *
 *  2. the shell path (pm grant, appops set), which is slower and has to be parsed,
 *     but survives signature churn and is the only route for the app-op backed
 *     "special" permissions.
 *
 * Runtime permissions try the binder first and fall back to the shell; app-ops
 * always take the shell.
 */
object ShizukuService {

    const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"
    const val PERMISSION_REQUEST_CODE = 4231

    private var hiddenApiUnlocked = false

    /** IPermissionManager / IPackageManager sit on the non-SDK denylist from API 28 on. */
    fun unlockHiddenApis() {
        if (hiddenApiUnlocked || Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        runCatching { HiddenApiBypass.addHiddenApiExemptions("") }
        hiddenApiUnlocked = true
    }

    // ------------------------------------------------------------------ status

    fun isInstalled(context: Context): Boolean = try {
        context.packageManager.getPackageInfo(SHIZUKU_PACKAGE, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    fun isRunning(): Boolean = runCatching { Shizuku.pingBinder() }.getOrDefault(false)

    fun hasPermission(): Boolean = runCatching {
        if (!Shizuku.pingBinder()) return false
        if (Shizuku.isPreV11()) return false
        Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    }.getOrDefault(false)

    fun shouldShowRationale(): Boolean = runCatching {
        Shizuku.pingBinder() && !Shizuku.isPreV11() && Shizuku.shouldShowRequestPermissionRationale()
    }.getOrDefault(false)

    fun status(context: Context): Map<String, Any?> {
        val installed = isInstalled(context)
        val running = isRunning()
        return mapOf(
            "installed" to installed,
            "running" to running,
            "permissionGranted" to (running && hasPermission()),
            "shouldShowRationale" to (running && shouldShowRationale()),
            "preV11" to runCatching { running && Shizuku.isPreV11() }.getOrDefault(false),
            "version" to runCatching { if (running) Shizuku.getVersion() else -1 }.getOrDefault(-1),
            "uid" to runCatching { if (running) Shizuku.getUid() else -1 }.getOrDefault(-1),
        )
    }

    /** The user id this app runs as; work profiles and secondary users are not 0. */
    fun currentUserId(): Int = android.os.Process.myUid() / 100_000

    // -------------------------------------------------------- runtime permissions

    /**
     * Grants or revokes a runtime permission. The returned map names the path that
     * actually did the work, so the UI can be honest about how it happened.
     */
    fun setRuntimePermission(
        packageName: String,
        permission: String,
        grant: Boolean,
        userId: Int = currentUserId(),
    ): Map<String, Any?> {
        if (!isRunning()) return failure("Shizuku n'est pas actif.")
        if (!hasPermission()) return failure("Permission Shizuku non accordée à CAPWS.")

        val binderError = try {
            unlockHiddenApis()
            val target = permissionManagerInterface()
                ?: throw IllegalStateException("interface système introuvable")
            val method = if (grant) "grantRuntimePermission" else "revokeRuntimePermission"
            if (invokeRuntimePermissionMethod(target, method, packageName, permission, userId)) {
                return success("binder")
            }
            "aucune surcharge de $method n'accepte ces arguments"
        } catch (t: Throwable) {
            t.message ?: t.javaClass.simpleName
        }

        // Fall back to the shell; this is what keeps the app working across the
        // Android 11 and 14 signature changes.
        val verb = if (grant) "grant" else "revoke"
        val shell = runShell("pm $verb --user $userId $packageName $permission")
        return if (shell.exitCode == 0) {
            success("shell")
        } else {
            val detail = shell.combinedOutput().ifBlank { "code ${shell.exitCode}" }
            failure("binder: $binderError | shell: $detail")
        }
    }

    private fun permissionManagerInterface(): Any? {
        val serviceName: String
        val interfaceName: String
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            serviceName = "permissionmgr"
            interfaceName = "android.permission.IPermissionManager"
        } else {
            serviceName = "package"
            interfaceName = "android.content.pm.IPackageManager"
        }
        val raw = SystemServiceHelper.getSystemService(serviceName) ?: return null
        val wrapped = ShizukuBinderWrapper(raw)
        val stub = Class.forName(interfaceName + "\$Stub")
        return stub.getMethod("asInterface", IBinder::class.java).invoke(null, wrapped)
    }

    /**
     * Probes every overload of [methodName] instead of hardcoding a signature.
     * Known shapes:
     *   (String pkg, String perm, int userId)                            — API < 34
     *   (String pkg, String perm, String persistentDeviceId, int userId) — API 34+
     */
    private fun invokeRuntimePermissionMethod(
        target: Any,
        methodName: String,
        packageName: String,
        permission: String,
        userId: Int,
    ): Boolean {
        val candidates = target.javaClass.methods.filter { it.name == methodName }
        var lastError: Throwable? = null
        for (method in candidates) {
            val types = method.parameterTypes
            val args: Array<Any?>? = when {
                types.size == 3 &&
                    types[0] == String::class.java &&
                    types[1] == String::class.java &&
                    types[2] == Int::class.javaPrimitiveType ->
                    arrayOf(packageName, permission, userId)

                types.size == 4 &&
                    types[0] == String::class.java &&
                    types[1] == String::class.java &&
                    types[2] == String::class.java &&
                    types[3] == Int::class.javaPrimitiveType ->
                    arrayOf(packageName, permission, defaultPersistentDeviceId(), userId)

                else -> null
            }
            if (args == null) continue
            try {
                method.invoke(target, *args)
                return true
            } catch (t: Throwable) {
                lastError = t
            }
        }
        lastError?.let { throw it }
        return false
    }

    /** VirtualDeviceManager.PERSISTENT_DEVICE_ID_DEFAULT, added in Android 14. */
    private fun defaultPersistentDeviceId(): String = runCatching {
        Class.forName("android.companion.virtual.VirtualDeviceManager")
            .getField("PERSISTENT_DEVICE_ID_DEFAULT")
            .get(null) as String
    }.getOrDefault("default:0")

    // -------------------------------------------------- app ops (special permissions)

    /**
     * Special permissions (overlay, usage access, write settings, all-files access…)
     * are not runtime permissions but app-ops, so there is no binder path here.
     */
    fun setAppOp(packageName: String, op: String, allow: Boolean): Map<String, Any?> {
        if (!isRunning()) return failure("Shizuku n'est pas actif.")
        if (!hasPermission()) return failure("Permission Shizuku non accordée à CAPWS.")

        val mode = if (allow) "allow" else "ignore"
        val result = runShell("appops set $packageName $op $mode")
        if (result.exitCode == 0) return success("appops")

        // Some ROMs only expose the op through the newer cmd front-end.
        val retry = runShell("cmd appops set $packageName $op $mode")
        return if (retry.exitCode == 0) {
            success("cmd appops")
        } else {
            failure(retry.combinedOutput().ifBlank { "code ${retry.exitCode}" })
        }
    }

    /** Reads an app-op back, so special permissions can show their real state. */
    fun getAppOpMode(packageName: String, op: String): String? {
        if (!isRunning() || !hasPermission()) return null
        val result = runShell("appops get $packageName $op")
        if (result.exitCode != 0) return null
        val text = result.stdout.trim()
        return when {
            text.contains("allow") -> "allow"
            text.contains("ignore") -> "ignore"
            text.contains("deny") -> "deny"
            text.contains("default") -> "default"
            else -> null
        }
    }

    // -------------------------------------------------------------------- shell

    class ShellResult(val exitCode: Int, val stdout: String, val stderr: String) {
        fun combinedOutput(): String = listOf(stdout, stderr)
            .filter { it.isNotBlank() }
            .joinToString(" / ") { it.trim() }
    }

    /**
     * Shizuku.newProcess is a restricted API in shizuku-api, so it is reached by
     * reflection. The returned object is handled reflectively too, which avoids a
     * compile-time dependency on ShizukuRemoteProcess's exact hierarchy.
     */
    fun runShell(command: String): ShellResult = try {
        val newProcess = Shizuku::class.java.getDeclaredMethod(
            "newProcess",
            Array<String>::class.java,
            Array<String>::class.java,
            String::class.java,
        ).apply { isAccessible = true }

        val process = newProcess.invoke(
            null,
            arrayOf("sh", "-c", command),
            null,
            null,
        ) ?: return ShellResult(-1, "", "newProcess a renvoyé null")

        val stdout = (process.javaClass.getMethod("getInputStream").invoke(process) as InputStream)
            .use { it.readBytes().toString(Charsets.UTF_8) }
        val stderr = (process.javaClass.getMethod("getErrorStream").invoke(process) as InputStream)
            .use { it.readBytes().toString(Charsets.UTF_8) }
        val code = process.javaClass.getMethod("waitFor").invoke(process) as Int

        // pm grant will happily exit 0 while printing a stack trace, so treat any
        // exception text on the streams as a failure.
        val looksLikeFailure = stderr.contains("Exception") || stdout.contains("Exception") ||
            stderr.contains("Error:") || stdout.contains("Error:")
        ShellResult(if (code == 0 && looksLikeFailure) 1 else code, stdout, stderr)
    } catch (t: Throwable) {
        ShellResult(-1, "", t.message ?: t.javaClass.simpleName)
    }

    // ------------------------------------------------------------------ helpers

    private fun success(via: String) = mapOf("ok" to true, "via" to via, "error" to null)
    private fun failure(message: String) = mapOf("ok" to false, "via" to null, "error" to message)
}
