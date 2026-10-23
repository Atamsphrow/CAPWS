import 'package:flutter/material.dart';

import '../models/app_info.dart';
import '../services/package_manager_service.dart';
import '../services/shizuku_bridge.dart';
import 'app_icon.dart';

/// One row in the Apps tab: identity on the left, permission pressure on the right.
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    required this.app,
    required this.inventory,
    required this.bridge,
    required this.onTap,
  });

  final AppInfo app;
  final Inventory inventory;
  final ShizukuBridge bridge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    var sensitiveGranted = 0;
    var sensitiveTotal = 0;
    for (final permission in app.permissions) {
      if (!inventory.infoOf(permission.name).protection.isSensitive) continue;
      sensitiveTotal++;
      if (permission.granted) sensitiveGranted++;
    }

    return ListTile(
      onTap: onTap,
      leading: AppIcon(packageName: app.packageName, bridge: bridge),
      title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        app.packageName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (app.isSystem)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.settings_suggest_outlined, size: 18, color: colors.outline),
            ),
          if (!app.enabled)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.block, size: 18, color: colors.outline),
            ),
          _SensitiveBadge(granted: sensitiveGranted, total: sensitiveTotal),
        ],
      ),
    );
  }
}

/// "3/7" — granted runtime permissions over requested ones. Tinted only when
/// something is actually granted, so a scan down the list finds the live ones.
class _SensitiveBadge extends StatelessWidget {
  const _SensitiveBadge({required this.granted, required this.total});

  final int granted;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (total == 0) {
      return Text(
        '—',
        style: theme.textTheme.labelMedium?.copyWith(color: colors.outline),
      );
    }

    final active = granted > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? colors.secondaryContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$granted/$total',
        style: theme.textTheme.labelMedium?.copyWith(
          color: active ? colors.onSecondaryContainer : colors.onSurfaceVariant,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
