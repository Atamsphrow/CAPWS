import 'package:flutter/material.dart';

import '../models/permission_catalog.dart';
import '../services/inventory_controller.dart';
import '../widgets/app_icon.dart';
import '../widgets/permission_toggle_tile.dart';
import '../widgets/shizuku_status_card.dart';
import 'app_detail_screen.dart';

/// One permission, every app that requests it, and a switch per app.
///
/// This is the inverse of [AppDetailScreen] and the reason the reverse index in
/// Inventory exists: "who has my microphone" is the question a permission manager
/// is really for.
class PermissionDetailScreen extends StatelessWidget {
  const PermissionDetailScreen({super.key, required this.permissionName});

  final String permissionName;

  @override
  Widget build(BuildContext context) {
    final controller = InventoryScope.of(context);
    final inventory = controller.inventory;

    if (inventory == null) {
      return Scaffold(
        // No leading arrow anywhere: the phone's back action (button or gesture) is
        // the only way back by design.
        appBar: AppBar(
          title: const Text('Permission'),
          automaticallyImplyLeading: false,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final info = inventory.infoOf(permissionName);
    final usages = inventory.usagesOf(permissionName);
    final visible = usages
        .where((usage) => controller.filters.scope.allows(usage.app))
        .toList(growable: false);
    final hidden = usages.length - visible.length;
    final mode = PermissionCatalog.modeFor(info);
    final grantedCount = usages.where((usage) => usage.granted).length;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(info.displayLabel, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        children: [
          _PermissionHeader(
            name: info.name,
            description: info.description,
            mode: mode,
            grantedCount: grantedCount,
            totalCount: usages.length,
            readOnlyReason: PermissionCatalog.readOnlyReason(info),
          ),
          const ShizukuStatusCard(compact: true),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Aucune app visible ne demande cette permission.')),
            ),
          for (final usage in visible)
            PermissionToggleTile(
              permission: info,
              granted: usage.granted,
              shizukuReady: controller.status.isReady,
              title: usage.app.label,
              subtitle: usage.app.packageName,
              showProtectionBadge: false,
              leading: AppIcon(
                packageName: usage.app.packageName,
                bridge: controller.bridge,
              ),
              onChange: (grant) => controller.setPermission(
                packageName: usage.app.packageName,
                permission: info,
                grant: grant,
              ),
              onOpenSettings: () => _openSettings(controller, usage.app.packageName),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AppDetailScreen(packageName: usage.app.packageName),
                ),
              ),
            ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '$hidden app(s) masquée(s) par le filtre « apps système ».',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _openSettings(InventoryController controller, String packageName) {
    final special = PermissionCatalog.specialFor(permissionName);
    if (special != null) {
      controller.bridge.openSpecialSetting(
        special.settingsKind,
        packageName: packageName,
      );
    } else {
      controller.bridge.openAppSettings(packageName);
    }
  }
}

class _PermissionHeader extends StatelessWidget {
  const _PermissionHeader({
    required this.name,
    required this.description,
    required this.mode,
    required this.grantedCount,
    required this.totalCount,
    required this.readOnlyReason,
  });

  final String name;
  final String? description;
  final ToggleMode mode;
  final int grantedCount;
  final int totalCount;
  final String? readOnlyReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(name, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(
            'Accordée à $grantedCount app(s) sur $totalCount qui la demandent',
            style: theme.textTheme.titleSmall,
          ),
          if (description != null) ...[
            const SizedBox(height: 12),
            Text(
              description!,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          if (readOnlyReason != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 20, color: colors.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      readOnlyReason!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (mode == ToggleMode.redirectOnly) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.open_in_new, size: 20, color: colors.onTertiaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Accès géré par un réglage sécurisé du système. CAPWS ouvre '
                      'l\'écran concerné plutôt que de le modifier, pour éviter de '
                      'corrompre la configuration.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
