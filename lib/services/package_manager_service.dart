import '../models/app_info.dart';
import '../models/permission_catalog.dart';
import '../models/permission_info.dart';
import 'shizuku_bridge.dart';

/// One app's stance on one permission, used by the permission-centric screens.
class PermissionUsage {
  const PermissionUsage({required this.app, required this.granted});

  final AppInfo app;
  final bool granted;
}

/// An immutable snapshot of the device: every app, every permission they ask for,
/// and the metadata needed to describe them.
///
/// Both tabs read from the same snapshot so they can never disagree, and the
/// reverse index (permission -> apps) is built once here rather than by scanning
/// the app list on every rebuild.
class Inventory {
  Inventory({
    required this.androidSdk,
    required this.currentUserId,
    required this.apps,
    required this.permissions,
  }) : _usageByPermission = _buildReverseIndex(apps);

  final int androidSdk;
  final int currentUserId;
  final List<AppInfo> apps;
  final Map<String, PermissionInfo> permissions;

  final Map<String, List<PermissionUsage>> _usageByPermission;

  static Map<String, List<PermissionUsage>> _buildReverseIndex(List<AppInfo> apps) {
    final index = <String, List<PermissionUsage>>{};
    for (final app in apps) {
      for (final permission in app.permissions) {
        index
            .putIfAbsent(permission.name, () => <PermissionUsage>[])
            .add(PermissionUsage(app: app, granted: permission.granted));
      }
    }
    for (final usages in index.values) {
      usages.sort((a, b) => a.app.label.toLowerCase().compareTo(b.app.label.toLowerCase()));
    }
    return index;
  }

  /// Every permission that at least one installed app declares, which is the only
  /// set that is actually actionable.
  Iterable<String> get permissionNames => _usageByPermission.keys;

  List<PermissionUsage> usagesOf(String permissionName) =>
      _usageByPermission[permissionName] ?? const [];

  /// Never null: permissions the system refused to resolve still need a row.
  PermissionInfo infoOf(String permissionName) =>
      permissions[permissionName] ?? PermissionInfo.unresolved(permissionName);

  AppInfo? appOf(String packageName) {
    for (final app in apps) {
      if (app.packageName == packageName) return app;
    }
    return null;
  }

  int get userAppCount => apps.where((app) => app.isUserApp).length;
  int get systemAppCount => apps.where((app) => app.isSystem).length;
  int get disabledAppCount => apps.where((app) => !app.enabled).length;

  /// Granted runtime permissions across the whole device — the headline number on
  /// the dashboard. Install-time and signature permissions are excluded because
  /// nothing can be done about them.
  int get grantedSensitiveCount {
    var total = 0;
    for (final app in apps) {
      for (final permission in app.permissions) {
        if (!permission.granted) continue;
        if (infoOf(permission.name).protection.isSensitive) total++;
      }
    }
    return total;
  }

  /// Apps holding at least one granted runtime permission.
  int get appsWithSensitiveCount => apps
      .where(
        (app) => app.permissions.any(
          (permission) => permission.granted && infoOf(permission.name).protection.isSensitive,
        ),
      )
      .length;

  /// Install sources, most-used first.
  List<({String? installer, int count})> installerBreakdown() {
    final counts = <String?, int>{};
    for (final app in apps) {
      counts[app.installer] = (counts[app.installer] ?? 0) + 1;
    }
    final entries = counts.entries.map((e) => (installer: e.key, count: e.value)).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return entries;
  }

  /// Permission names grouped into the categories shown in the Permissions tab.
  Map<PermissionCategory, List<String>> byCategory() {
    final grouped = <PermissionCategory, List<String>>{};
    for (final name in permissionNames) {
      final category = PermissionCatalog.categoryFor(infoOf(name));
      grouped.putIfAbsent(category, () => <String>[]).add(name);
    }
    for (final names in grouped.values) {
      names.sort(
        (a, b) => infoOf(a).displayLabel.toLowerCase().compareTo(
          infoOf(b).displayLabel.toLowerCase(),
        ),
      );
    }
    return grouped;
  }

  /// Rebuilds the snapshot with one permission flipped for one app, so a
  /// successful toggle is reflected without re-reading the whole device.
  Inventory withPermissionState({
    required String packageName,
    required String permission,
    required bool granted,
  }) => Inventory(
    androidSdk: androidSdk,
    currentUserId: currentUserId,
    apps: [
      for (final app in apps)
        if (app.packageName == packageName)
          app.copyWithPermission(permission, granted)
        else
          app,
    ],
    permissions: permissions,
  );
}

/// Turns the raw native payload into an [Inventory].
class PackageManagerService {
  PackageManagerService(this._bridge);

  final ShizukuBridge _bridge;

  Future<Inventory> load() async {
    final raw = await _bridge.inventory();

    final apps = <AppInfo>[
      for (final entry in (raw['apps'] as List<Object?>? ?? const []))
        AppInfo.fromMap(entry! as Map<Object?, Object?>),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    final permissions = <String, PermissionInfo>{};
    final rawPermissions = raw['permissions'] as Map<Object?, Object?>? ?? const {};
    rawPermissions.forEach((key, value) {
      final name = key as String;
      permissions[name] = PermissionInfo.fromMap(name, value! as Map<Object?, Object?>);
    });

    return Inventory(
      androidSdk: (raw['androidSdk'] as num?)?.toInt() ?? 0,
      currentUserId: (raw['currentUserId'] as num?)?.toInt() ?? 0,
      apps: apps,
      permissions: permissions,
    );
  }
}
