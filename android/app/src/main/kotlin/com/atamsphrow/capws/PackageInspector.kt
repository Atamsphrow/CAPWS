package com.atamsphrow.capws

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.PermissionInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import java.io.ByteArrayOutputStream

/**
 * The read-only half of the bridge: everything PackageManager can answer without
 * elevated privileges.
 *
 * The whole inventory is built in one pass and shipped to Dart as a single payload,
 * so the Apps and Permissions tabs always read from a consistent snapshot. Icons are
 * deliberately excluded and fetched lazily per tile instead — bundling a few hundred
 * bitmaps into one MethodChannel reply is what makes this kind of app feel slow.
 */
object PackageInspector {

    /** @return a map with "androidSdk", "apps" (list) and "permissions" (name -> metadata). */
    fun inventory(context: Context): Map<String, Any?> {
        val pm = context.packageManager
        val permissionMeta = HashMap<String, Map<String, Any?>>()
        val groupLabels = HashMap<String, String?>()
        val apps = ArrayList<Map<String, Any?>>()

        for (appInfo in installedApplications(pm)) {
            val packageInfo = packageInfoOrNull(pm, appInfo.packageName) ?: continue
            apps.add(describeApp(pm, appInfo, packageInfo, permissionMeta, groupLabels))
        }

        return mapOf(
            "androidSdk" to Build.VERSION.SDK_INT,
            "currentUserId" to ShizukuService.currentUserId(),
            "apps" to apps,
            "permissions" to permissionMeta,
        )
    }

    private fun describeApp(
        pm: PackageManager,
        appInfo: ApplicationInfo,
        packageInfo: PackageInfo,
        permissionMeta: HashMap<String, Map<String, Any?>>,
        groupLabels: HashMap<String, String?>,
    ): Map<String, Any?> {
        val requested = packageInfo.requestedPermissions
        val flags = packageInfo.requestedPermissionsFlags
        val permissions = ArrayList<Map<String, Any?>>()

        if (requested != null) {
            for (i in requested.indices) {
                val name = requested[i]
                val granted = flags != null && i < flags.size &&
                    (flags[i] and PackageInfo.REQUESTED_PERMISSION_GRANTED) != 0
                permissions.add(mapOf("name" to name, "granted" to granted))
                if (!permissionMeta.containsKey(name)) {
                    permissionMeta[name] = describePermission(pm, name, groupLabels)
                }
            }
        }

        val isSystem = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
            (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0

        return mapOf(
            "packageName" to appInfo.packageName,
            "label" to runCatching { appInfo.loadLabel(pm).toString() }
                .getOrDefault(appInfo.packageName),
            "versionName" to packageInfo.versionName,
            "isSystem" to isSystem,
            "enabled" to appInfo.enabled,
            "targetSdk" to appInfo.targetSdkVersion,
            "installer" to installerOf(pm, appInfo.packageName),
            "firstInstallTime" to packageInfo.firstInstallTime,
            "lastUpdateTime" to packageInfo.lastUpdateTime,
            "permissions" to permissions,
        )
    }

    private fun describePermission(
        pm: PackageManager,
        name: String,
        groupLabels: HashMap<String, String?>,
    ): Map<String, Any?> {
        // Vendor permissions, and permissions declared by an app that has since been
        // uninstalled, simply will not resolve. They still show up in the inventory
        // marked unknown rather than being dropped.
        val info = runCatching { pm.getPermissionInfo(name, 0) }.getOrNull()
            ?: return mapOf(
                "name" to name,
                "label" to null,
                "description" to null,
                "group" to null,
                "groupLabel" to null,
                "protection" to "unknown",
                "known" to false,
            )

        val group = info.group
        if (group != null && !groupLabels.containsKey(group)) {
            groupLabels[group] = runCatching {
                pm.getPermissionGroupInfo(group, 0).loadLabel(pm).toString()
            }.getOrNull()
        }

        return mapOf(
            "name" to name,
            "label" to runCatching { info.loadLabel(pm).toString() }.getOrNull(),
            "description" to runCatching { info.loadDescription(pm)?.toString() }.getOrNull(),
            "group" to group,
            "groupLabel" to groupLabels[group],
            "protection" to protectionName(info),
            "known" to true,
        )
    }

    @Suppress("DEPRECATION")
    private fun protectionName(info: PermissionInfo): String {
        val base = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.protection
        } else {
            info.protectionLevel and PermissionInfo.PROTECTION_MASK_BASE
        }
        return when (base) {
            PermissionInfo.PROTECTION_NORMAL -> "normal"
            PermissionInfo.PROTECTION_DANGEROUS -> "dangerous"
            PermissionInfo.PROTECTION_SIGNATURE -> "signature"
            PermissionInfo.PROTECTION_SIGNATURE_OR_SYSTEM -> "signatureOrSystem"
            else -> "unknown"
        }
    }

    private fun installerOf(pm: PackageManager, packageName: String): String? = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val source = pm.getInstallSourceInfo(packageName)
            source.installingPackageName ?: source.initiatingPackageName
        } else {
            @Suppress("DEPRECATION")
            pm.getInstallerPackageName(packageName)
        }
    }.getOrNull()

    @Suppress("DEPRECATION")
    private fun installedApplications(pm: PackageManager): List<ApplicationInfo> = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0L))
        } else {
            pm.getInstalledApplications(0)
        }
    }.getOrDefault(emptyList())

    /**
     * Fetched per package rather than through getInstalledPackages(GET_PERMISSIONS):
     * the bulk call carries every permission array in one binder transaction and
     * blows the 1 MB limit on devices with a lot of apps.
     */
    @Suppress("DEPRECATION")
    private fun packageInfoOrNull(pm: PackageManager, packageName: String): PackageInfo? =
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()),
                )
            } else {
                pm.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
            }
        }.getOrNull()

    /** PNG bytes for an app icon rendered at [sizePx]; null when it cannot be loaded. */
    fun appIcon(context: Context, packageName: String, sizePx: Int): ByteArray? = runCatching {
        val drawable = context.packageManager.getApplicationIcon(packageName)
        val side = sizePx.coerceIn(24, 256)
        val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, side, side)
        drawable.draw(canvas)
        ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        }
    }.getOrNull()
}
