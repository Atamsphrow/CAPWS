import 'package:flutter/material.dart';

import '../main.dart';
import '../models/app_info.dart';
import '../services/error_reporter.dart';
import '../services/inventory_controller.dart';
import '../services/package_manager_service.dart';
import '../widgets/shizuku_status_card.dart';
import 'about_screen.dart';
import 'diagnostics_screen.dart';

/// Landing screen: the Shizuku situation first, then the counters that lead
/// somewhere. Every number here is a link into a filtered list — a dashboard that
/// only reports is a dead end.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = InventoryScope.of(context);
    final inventory = controller.inventory;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CAPWS'),
        actions: [
          IconButton(
            tooltip: 'Recharger l\'inventaire',
            onPressed: controller.loading ? null : () => controller.refresh(),
            icon: const Icon(Icons.refresh),
          ),
          // The badge is the only signal that something went wrong while the user
          // was on another screen, so it watches the reporter directly.
          ListenableBuilder(
            listenable: ErrorReporter.instance,
            builder: (context, _) {
              final unseen = ErrorReporter.instance.unseen;
              return IconButton(
                tooltip: 'Diagnostic et journal d\'erreurs',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
                ),
                icon: Badge(
                  isLabelVisible: unseen > 0,
                  label: Text('$unseen'),
                  child: const Icon(Icons.bug_report_outlined),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'À propos',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.refresh(showSpinner: false),
        child: ListView(
          children: [
            const ShizukuStatusCard(compact: false),
            if (controller.error != null) _ErrorCard(message: controller.error!),
            if (inventory == null)
              _LoadingBlock(loading: controller.loading)
            else
              ..._buildContent(context, inventory),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, Inventory inventory) {
    final theme = Theme.of(context);
    final navigator = HomeNavigator.of(context);

    return [
      _SectionTitle('Apps installées'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: _StatTile(
                value: '${inventory.apps.length}',
                label: 'Total',
                icon: Icons.apps,
                onTap: () => navigator.go(1, filters: const Filters(scope: AppScope.all)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                value: '${inventory.userAppCount}',
                label: 'Utilisateur',
                icon: Icons.person_outline,
                onTap: () => navigator.go(1, filters: const Filters()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                value: '${inventory.systemAppCount}',
                label: 'Système',
                icon: Icons.settings_suggest_outlined,
                onTap: () =>
                    navigator.go(1, filters: const Filters(scope: AppScope.systemOnly)),
              ),
            ),
          ],
        ),
      ),
      if (inventory.disabledAppCount > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'dont ${inventory.disabledAppCount} désactivée(s)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),

      _SectionTitle('Permissions sensibles'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => navigator.go(
              2,
              filters: const Filters(
                scope: AppScope.all,
                onlySensitive: true,
                onlyGranted: true,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    size: 36,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${inventory.grantedSensitiveCount}',
                          style: theme.textTheme.headlineMedium,
                        ),
                        Text(
                          'permissions runtime actuellement accordées, '
                          'réparties sur ${inventory.appsWithSensitiveCount} app(s)',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ),

      _SectionTitle('Sources d\'installation'),
      ..._buildInstallerRows(context, inventory, navigator),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _buildInstallerRows(
    BuildContext context,
    Inventory inventory,
    HomeNavigator navigator,
  ) {
    final breakdown = inventory.installerBreakdown();
    return [
      for (final entry in breakdown.take(8))
        ListTile(
          leading: const Icon(Icons.storefront_outlined),
          title: Text(installerLabel(entry.installer)),
          trailing: Text('${entry.count}'),
          onTap: () => navigator.go(
            1,
            filters: Filters(
              scope: AppScope.all,
              installer: InstallerFilter(entry.installer),
            ),
          ),
        ),
      if (breakdown.length > 8)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            '+ ${breakdown.length - 8} autre(s) source(s)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String value;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(value, style: theme.textTheme.headlineSmall),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 64),
    child: Center(
      child: loading
          ? const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Lecture des apps installées…'),
              ],
            )
          : const Text('Aucune donnée. Tire vers le bas pour recharger.'),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
            ),
          ],
        ),
      ),
    );
  }
}
