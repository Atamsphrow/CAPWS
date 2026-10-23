/// One permission as requested by one app, with its current grant state.
class AppPermission {
  const AppPermission({required this.name, required this.granted});

  final String name;
  final bool granted;

  AppPermission copyWith({bool? granted}) =>
      AppPermission(name: name, granted: granted ?? this.granted);

  factory AppPermission.fromMap(Map<Object?, Object?> map) => AppPermission(
    name: map['name'] as String,
    granted: map['granted'] as bool? ?? false,
  );
}

/// An installed package plus everything it asks for.
class AppInfo {
  const AppInfo({
    required this.packageName,
    required this.label,
    required this.versionName,
    required this.isSystem,
    required this.enabled,
    required this.targetSdk,
    required this.installer,
    required this.firstInstall,
    required this.lastUpdate,
    required this.permissions,
  });

  final String packageName;
  final String label;
  final String? versionName;
  final bool isSystem;
  final bool enabled;
  final int targetSdk;

  /// Package name of the installer (a store, a sideload helper, or null for
  /// preinstalled apps and anything installed via adb).
  final String? installer;

  final DateTime firstInstall;
  final DateTime lastUpdate;
  final List<AppPermission> permissions;

  bool get isUserApp => !isSystem;

  AppInfo copyWithPermission(String name, bool granted) => AppInfo(
    packageName: packageName,
    label: label,
    versionName: versionName,
    isSystem: isSystem,
    enabled: enabled,
    targetSdk: targetSdk,
    installer: installer,
    firstInstall: firstInstall,
    lastUpdate: lastUpdate,
    permissions: [
      for (final permission in permissions)
        if (permission.name == name) permission.copyWith(granted: granted) else permission,
    ],
  );

  factory AppInfo.fromMap(Map<Object?, Object?> map) => AppInfo(
    packageName: map['packageName'] as String,
    label: (map['label'] as String?) ?? map['packageName'] as String,
    versionName: map['versionName'] as String?,
    isSystem: map['isSystem'] as bool? ?? false,
    enabled: map['enabled'] as bool? ?? true,
    targetSdk: map['targetSdk'] as int? ?? 0,
    installer: map['installer'] as String?,
    firstInstall: DateTime.fromMillisecondsSinceEpoch(
      (map['firstInstallTime'] as num?)?.toInt() ?? 0,
    ),
    lastUpdate: DateTime.fromMillisecondsSinceEpoch(
      (map['lastUpdateTime'] as num?)?.toInt() ?? 0,
    ),
    permissions: [
      for (final entry in (map['permissions'] as List<Object?>? ?? const []))
        AppPermission.fromMap(entry! as Map<Object?, Object?>),
    ],
  );
}

/// Human-readable name for the well-known install sources, so the dashboard does
/// not just show raw package names.
String installerLabel(String? installer) {
  switch (installer) {
    case null:
      return 'Préinstallée ou adb';
    case 'com.android.vending':
      return 'Google Play';
    case 'com.android.packageinstaller':
    case 'com.google.android.packageinstaller':
      return 'Installateur système (APK)';
    case 'org.fdroid.fdroid':
      return 'F-Droid';
    case 'com.aurora.store':
      return 'Aurora Store';
    case 'com.amazon.venezia':
      return 'Amazon Appstore';
    case 'com.huawei.appmarket':
      return 'Huawei AppGallery';
    case 'com.sec.android.app.samsungapps':
      return 'Galaxy Store';
    case 'com.xiaomi.mipicks':
      return 'GetApps (Xiaomi)';
    default:
      return installer;
  }
}
