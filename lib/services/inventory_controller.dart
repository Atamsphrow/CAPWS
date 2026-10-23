import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/app_info.dart';
import '../models/permission_catalog.dart';
import '../models/permission_info.dart';
import 'error_reporter.dart';
import 'package_manager_service.dart';
import 'shizuku_bridge.dart';

/// Which slice of the installed apps a screen is looking at.
///
/// System apps are excluded by default: on a stock device they outnumber the ones
/// the user installed and bury them. [systemOnly] exists so the dashboard can
/// drill straight into that category.
enum AppScope {
  userOnly,
  all,
  systemOnly;

  bool allows(AppInfo app) => switch (this) {
    AppScope.userOnly => app.isUserApp,
    AppScope.all => true,
    AppScope.systemOnly => app.isSystem,
  };
}

/// Wraps the install-source filter so that "no filter" and "installed by nothing"
/// stay distinguishable: a null [value] is itself a real category (preinstalled or
/// pushed over adb), so a bare nullable String could not express both.
@immutable
class InstallerFilter {
  const InstallerFilter(this.value);

  final String? value;

  @override
  bool operator ==(Object other) => other is InstallerFilter && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Search text and toggles shared by the Apps and Permissions tabs.
@immutable
class Filters {
  const Filters({
    this.query = '',
    this.scope = AppScope.userOnly,
    this.onlyGranted = false,
    this.onlySensitive = false,
    this.installer,
  });

  final String query;
  final AppScope scope;
  final bool onlyGranted;
  final bool onlySensitive;

  /// Install-source filter, reached from the dashboard. Null means "any source".
  final InstallerFilter? installer;

  bool get hasInstallerFilter => installer != null;

  int get activeCount =>
      (scope == AppScope.userOnly ? 0 : 1) +
      (onlyGranted ? 1 : 0) +
      (onlySensitive ? 1 : 0) +
      (hasInstallerFilter ? 1 : 0);

  Filters copyWith({
    String? query,
    AppScope? scope,
    bool? onlyGranted,
    bool? onlySensitive,
    InstallerFilter? installer,
    bool resetInstaller = false,
  }) => Filters(
    query: query ?? this.query,
    scope: scope ?? this.scope,
    onlyGranted: onlyGranted ?? this.onlyGranted,
    onlySensitive: onlySensitive ?? this.onlySensitive,
    installer: resetInstaller ? null : (installer ?? this.installer),
  );

  @override
  bool operator ==(Object other) =>
      other is Filters &&
      other.query == query &&
      other.scope == scope &&
      other.onlyGranted == onlyGranted &&
      other.onlySensitive == onlySensitive &&
      other.installer == installer;

  @override
  int get hashCode => Object.hash(query, scope, onlyGranted, onlySensitive, installer);
}

/// Single source of truth for the UI: the device snapshot, the Shizuku status, the
/// active filters, and the privileged writes.
///
/// A successful write patches the in-memory snapshot instead of re-reading the
/// whole device — a full inventory takes a second or two on a loaded phone, and
/// re-running it after every switch would make the UI feel broken.
class InventoryController extends ChangeNotifier {
  InventoryController({ShizukuBridge? bridge})
    : _bridge = bridge ?? ShizukuBridge(),
      _status = const ShizukuStatus.unknown() {
    _packages = PackageManagerService(_bridge);
    _eventSubscription = _bridge.events.listen(_onShizukuEvent);
  }

  final ShizukuBridge _bridge;
  late final PackageManagerService _packages;
  StreamSubscription<ShizukuEvent>? _eventSubscription;

  Inventory? _inventory;
  ShizukuStatus _status;
  bool _loading = false;
  String? _error;
  Filters _filters = const Filters();

  ShizukuBridge get bridge => _bridge;
  Inventory? get inventory => _inventory;
  ShizukuStatus get status => _status;
  bool get loading => _loading;
  String? get error => _error;
  Filters get filters => _filters;

  /// Reads the Shizuku status and the full device inventory.
  Future<void> refresh({bool showSpinner = true}) async {
    if (showSpinner) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      _status = await _bridge.status();
      _inventory = await _packages.load();
      _error = null;
    } catch (error, stack) {
      _error = '$error';
      ErrorReporter.instance.record(
        kind: AppErrorKind.inventory,
        message: '$error',
        stack: '$stack',
        context: 'lecture de l\'inventaire (getInventory)',
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Cheap re-read of just the Shizuku side, for when the user comes back from the
  /// Shizuku app or from a Settings screen.
  Future<void> refreshStatus() async {
    _status = await _bridge.status();
    notifyListeners();
  }

  Future<bool> requestShizukuPermission() async {
    try {
      final granted = await _bridge.requestPermission();
      await refreshStatus();
      return granted;
    } catch (error) {
      _error = '$error';
      notifyListeners();
      return false;
    }
  }

  void setFilters(Filters filters) {
    if (filters == _filters) return;
    _filters = filters;
    notifyListeners();
  }

  void updateQuery(String query) => setFilters(_filters.copyWith(query: query));

  void resetFilters() => setFilters(const Filters());

  // -------------------------------------------------------------------- writes

  /// Applies a permission change through whichever path the permission supports.
  /// Returns the raw result so the caller can surface `via` and `error`.
  Future<PermissionWriteResult> setPermission({
    required String packageName,
    required PermissionInfo permission,
    required bool grant,
  }) async {
    if (!_status.isReady) {
      return PermissionWriteResult.failed(
        'Shizuku indisponible : impossible de modifier cette permission.',
      );
    }

    final mode = PermissionCatalog.modeFor(permission);
    final PermissionWriteResult result;
    switch (mode) {
      case ToggleMode.runtime:
        result = await _bridge.setRuntimePermission(
          packageName: packageName,
          permission: permission.name,
          grant: grant,
        );
      case ToggleMode.appOp:
        final op = PermissionCatalog.specialFor(permission.name)!.appOp!;
        result = await _bridge.setAppOp(
          packageName: packageName,
          op: op,
          allow: grant,
        );
      case ToggleMode.redirectOnly:
      case ToggleMode.readOnly:
        result = PermissionWriteResult.failed(
          PermissionCatalog.readOnlyReason(permission) ??
              'Cette permission ne peut pas être modifiée directement.',
        );
    }

    if (result.ok) {
      final current = _inventory;
      if (current != null) {
        _inventory = current.withPermissionState(
          packageName: packageName,
          permission: permission.name,
          granted: grant,
        );
        notifyListeners();
      }
    } else {
      // A refused write is the failure mode that matters most here and the one a
      // user cannot diagnose alone, so it goes into the report even though the UI
      // also shows it in a snackbar.
      ErrorReporter.instance.record(
        kind: AppErrorKind.permissionWrite,
        message: result.error ?? 'échec sans message',
        context:
            '${grant ? 'grant' : 'revoke'} ${permission.name} '
            '-> $packageName (mode ${mode.name})',
      );
    }
    return result;
  }

  // ------------------------------------------------------------------- queries

  /// Apps matching the current filters. `onlySensitive` and `onlyGranted` read as
  /// "has at least one permission of that kind".
  List<AppInfo> filteredApps() {
    final current = _inventory;
    if (current == null) return const [];
    final needle = _filters.query.trim().toLowerCase();

    return current.apps.where((app) {
      if (!_filters.scope.allows(app)) return false;
      final installerFilter = _filters.installer;
      if (installerFilter != null && app.installer != installerFilter.value) return false;

      if (needle.isNotEmpty) {
        final matchesApp =
            app.label.toLowerCase().contains(needle) ||
            app.packageName.toLowerCase().contains(needle);
        final matchesPermission = app.permissions.any(
          (permission) => _permissionMatches(current.infoOf(permission.name), needle),
        );
        if (!matchesApp && !matchesPermission) return false;
      }

      if (_filters.onlySensitive || _filters.onlyGranted) {
        final hasMatch = app.permissions.any((permission) {
          final info = current.infoOf(permission.name);
          if (_filters.onlySensitive && !info.protection.isSensitive) return false;
          if (_filters.onlyGranted && !permission.granted) return false;
          return true;
        });
        if (!hasMatch) return false;
      }

      return true;
    }).toList();
  }

  /// Permission names matching the current filters, grouped by category.
  Map<PermissionCategory, List<String>> filteredPermissionsByCategory() {
    final current = _inventory;
    if (current == null) return const {};
    final needle = _filters.query.trim().toLowerCase();
    final grouped = <PermissionCategory, List<String>>{};

    for (final entry in current.byCategory().entries) {
      final kept = <String>[];
      for (final name in entry.value) {
        final info = current.infoOf(name);

        if (_filters.onlySensitive && !info.protection.isSensitive) continue;

        final usages = current.usagesOf(name);
        final inScope = usages.where((usage) => _filters.scope.allows(usage.app));
        if (inScope.isEmpty && needle.isEmpty) {
          // A permission nothing in scope requests is noise, unless the user
          // searched for it by name.
          continue;
        }
        if (_filters.onlyGranted && !inScope.any((usage) => usage.granted)) continue;

        if (needle.isNotEmpty && !_permissionMatches(info, needle)) continue;

        kept.add(name);
      }
      if (kept.isNotEmpty) grouped[entry.key] = kept;
    }
    return grouped;
  }

  bool _permissionMatches(PermissionInfo info, String needle) =>
      info.name.toLowerCase().contains(needle) ||
      info.displayLabel.toLowerCase().contains(needle);

  void _onShizukuEvent(ShizukuEvent event) {
    // Any connection change can invalidate whether writes will work at all, so the
    // status is re-read rather than inferred from the event itself.
    refreshStatus();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

/// Makes the controller available to the whole widget tree and rebuilds dependents
/// when it notifies.
class InventoryScope extends InheritedNotifier<InventoryController> {
  const InventoryScope({
    super.key,
    required InventoryController controller,
    required super.child,
  }) : super(notifier: controller);

  static InventoryController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<InventoryScope>();
    assert(scope != null, 'Aucun InventoryScope dans l\'arbre de widgets.');
    return scope!.notifier!;
  }
}
