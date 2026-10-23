import 'package:flutter/material.dart';

import '../services/inventory_controller.dart';
import '../services/shizuku_bridge.dart';

/// Explains the Shizuku situation and offers the one action that moves it forward.
///
/// Shizuku has four distinct states and each needs a different next step, so a
/// generic "not available" message would leave the user stuck. When [compact] is
/// set the card disappears entirely once everything is ready, which keeps the
/// per-app screens clean.
class ShizukuStatusCard extends StatelessWidget {
  const ShizukuStatusCard({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = InventoryScope.of(context);
    final status = controller.status;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (compact && status.isReady) return const SizedBox.shrink();

    final (IconData icon, String title, String body, String? actionLabel, VoidCallback? action) =
        switch (status.readiness) {
          ShizukuReadiness.notInstalled => (
            Icons.extension_off_outlined,
            'Shizuku n\'est pas installé',
            'CAPWS a besoin de Shizuku pour modifier les permissions. Sans lui, '
                'l\'app reste consultable et renvoie vers les réglages Android.',
            'Installer Shizuku',
            () => controller.bridge.openShizukuInstall(),
          ),
          ShizukuReadiness.notRunning => (
            Icons.power_settings_new,
            'Shizuku est installé mais inactif',
            status.preV11
                ? 'Cette version de Shizuku est antérieure à la v11 et ne gère pas '
                      'les permissions runtime. Mets-la à jour.'
                : 'Démarre le service depuis l\'app Shizuku : par appairage sans fil '
                      '(débogage ADB sans fil), par USB depuis un PC, ou directement '
                      'si ton téléphone est rooté. À refaire après chaque redémarrage '
                      'en mode non rooté.',
            'Ouvrir Shizuku',
            () => controller.bridge.launchShizuku(),
          ),
          ShizukuReadiness.permissionMissing => (
            Icons.lock_outline,
            'Permission Shizuku requise',
            'Shizuku tourne, mais CAPWS n\'a pas encore l\'autorisation de l\'utiliser.',
            'Demander l\'autorisation',
            () => controller.requestShizukuPermission(),
          ),
          ShizukuReadiness.ready => (
            Icons.verified_user_outlined,
            'Shizuku actif',
            'Les permissions peuvent être modifiées directement'
                '${status.version > 0 ? ' — service v${status.version}' : ''}.',
            null,
            null,
          ),
        };

    final ready = status.isReady;
    final container = ready ? colors.secondaryContainer : colors.errorContainer;
    final onContainer = ready ? colors.onSecondaryContainer : colors.onErrorContainer;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: container,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: onContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(color: onContainer),
                  ),
                ),
                IconButton(
                  tooltip: 'Revérifier',
                  onPressed: controller.refreshStatus,
                  icon: Icon(Icons.refresh, color: onContainer),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: onContainer)),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(onPressed: action, child: Text(actionLabel)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
