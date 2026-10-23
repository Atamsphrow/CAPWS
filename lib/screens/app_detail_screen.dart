import 'package:flutter/material.dart';

import '../models/app_info.dart';
import '../models/permission_catalog.dart';
import '../models/permission_info.dart';
import '../services/inventory_controller.dart';
import '../services/shizuku_bridge.dart';
import '../widgets/app_icon.dart';
import '../widgets/permission_toggle_tile.dart';
import '../widgets/shizuku_status_card.dart';
import 'permission_detail_screen.dart';

/// Everything one app asks for, grouped by category, with a switch per permission.
class AppDetailScreen extends StatefulWidget {
  const AppDetailScreen({super.key, required this.packageName});

  final String packageName;

  @override
  State<AppDetailScreen> createState() => _AppDetailScreenState();
}

class _AppDetailScreenState extends State<AppDetailScreen> {
  /// Real app-op state for the special permissions.
  ///
  /// PackageManager's REQUESTED_PERMISSION_GRANTED flag does not track app-ops, so
  /// for overlay/usage-access/all-files the manifest flag can say "granted" while
  /// the op is set to ignore. These are read separately, and only when Shizuku can
  /// actually answer.
  final Map<String, bool> _appOpStates = {};
  bool _appOpsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAppOps());
  }

  Future<void> _loadAppOps() async {
    final controller = InventoryScope.of(context);
    if (!controller.status.isReady) return;

    final app = controller.inventory?.appOf(widget.packageName);
    if (app == null) return;

    final resolved = <String, bool>{};
    for (final permission in app.permissions) {
      final special = PermissionCatalog.specialFor(permission.name);
      final op = special?.appOp;
      if (op == null) continue;
      final mode = await controller.bridge.appOpMode(
        packageName: widget.packageName,
        op: op,
      );
      if (mode != null) resolved[permission.name] = mode == 'allow';
    }
    if (!mounted) return;
    setState(() {
      _appOpStates
        ..clear()
        ..addAll(resolved);
      _appOpsLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = InventoryScope.of(context);
    final inventory = controller.inventory;
    final app = inventory?.appOf(widget.packageName);

    if (inventory == null || app == null) {
      return Scaffold(
        // No leading arrow anywhere: the phone's back action (button or gesture) is
        // the only way back by design.
        appBar: AppBar(
          title: const Text('App introuvable'),
          automaticallyImplyLeading: false,
        ),
        body: const Center(
          child: Text('Cette app n\'est plus présente dans l\'inventaire.'),
        ),
      );
    }

    final grouped = <PermissionCategory, List<PermissionInfo>>{};
    for (final permission in app.permissions) {
      final info = inventory.infoOf(permission.name);
      grouped.putIfAbsent(PermissionCatalog.categoryFor(info), () => []).add(info);
    }
    for (final infos in grouped.values) {
      infos.sort(
        (a, b) => a.displayLabel.toLowerCase().compareTo(b.displayLabel.toLowerCase()),
      );
    }
    final categories = PermissionCatalog.ordered
        .where(grouped.containsKey)
        .toList(growable: false);

    final grantedByName = {
      for (final permission in app.permissions) permission.name: permission.granted,
    };

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(app.label, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Ouvrir dans les réglages Android',
            onPressed: () => controller.bridge.openAppSettings(app.packageName),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: ListView(
        children: [
          _AppHeader(app: app, controller: controller),
          const ShizukuStatusCard(compact: true),
          if (app.permissions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Cette app ne demande aucune permission.')),
            ),
          for (final category in categories) ...[
            _CategoryHeader(category: category, count: grouped[category]!.length),
            for (final info in grouped[category]!)
              PermissionToggleTile(
                permission: info,
                granted: _isGranted(info, grantedByName),
                shizukuReady: controller.status.isReady,
                title: info.displayLabel,
                subtitle: _subtitleFor(info),
                onChange: (grant) => _apply(controller, info, grant),
                onOpenSettings: () => _openSettings(controller, info),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PermissionDetailScreen(permissionName: info.name),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// For app-op permissions the op is authoritative once we have read it.
  bool _isGranted(PermissionInfo info, Map<String, bool> manifestFlags) =>
      _appOpStates[info.name] ?? manifestFlags[info.name] ?? false;

  String _subtitleFor(PermissionInfo info) {
    final parts = <String>[info.shortName];
    if (PermissionCatalog.isSpecial(info.name) && !_appOpsLoaded) {
      parts.add('état app-op non vérifié');
    }
    return parts.join(' · ');
  }

  Future<PermissionWriteResult> _apply(
    InventoryController controller,
    PermissionInfo info,
    bool grant,
  ) async {
    final result = await controller.setPermission(
      packageName: widget.packageName,
      permission: info,
      grant: grant,
    );
    if (result.ok && PermissionCatalog.specialFor(info.name)?.appOp != null && mounted) {
      setState(() => _appOpStates[info.name] = grant);
    }
    return result;
  }

  void _openSettings(InventoryController controller, PermissionInfo info) {
    final special = PermissionCatalog.specialFor(info.name);
    if (special != null) {
      controller.bridge.openSpecialSetting(
        special.settingsKind,
        packageName: widget.packageName,
      );
    } else {
      controller.bridge.openAppSettings(widget.packageName);
    }
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({required this.app, required this.controller});

  final AppInfo app;
  final InventoryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(packageName: app.packageName, bridge: controller.bridge, size: 56),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.packageName, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Tag(app.isSystem ? 'Système' : 'Utilisateur'),
                    if (!app.enabled) _Tag('Désactivée'),
                    if (app.versionName != null) _Tag('v${app.versionName}'),
                    _Tag('SDK cible ${app.targetSdk}'),
                    _Tag(installerLabel(app.installer)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${app.permissions.length} permission(s) déclarée(s)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.category, required this.count});

  final PermissionCategory category;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(category.icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(category.label, style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          Text(
            '($count)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
