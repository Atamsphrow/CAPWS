import 'package:flutter/material.dart';

import '../models/permission_catalog.dart';
import '../services/inventory_controller.dart';
import '../widgets/filter_bar.dart';
import 'permission_detail_screen.dart';

/// Every permission any installed app declares, grouped into categories.
///
/// The list is built from what apps actually request rather than from the full
/// system permission table: a permission nothing asks for cannot be acted on, so
/// showing it would only pad the list.
class PermissionsListScreen extends StatelessWidget {
  const PermissionsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = InventoryScope.of(context);
    final inventory = controller.inventory;
    final grouped = controller.filteredPermissionsByCategory();
    final categories = PermissionCatalog.ordered
        .where(grouped.containsKey)
        .toList(growable: false);
    final total = grouped.values.fold<int>(0, (sum, names) => sum + names.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilterBar(hintText: 'Nom de permission'),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.refresh(showSpinner: false),
        child: inventory == null
            ? const Center(child: CircularProgressIndicator())
            : categories.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 64),
                  Center(child: Text('Aucune permission ne correspond aux filtres.')),
                ],
              )
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      '$total permission(s) dans ${categories.length} catégorie(s)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final category in categories)
                    _CategorySection(
                      category: category,
                      permissionNames: grouped[category]!,
                    ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category, required this.permissionNames});

  final PermissionCategory category;
  final List<String> permissionNames;

  @override
  Widget build(BuildContext context) {
    final controller = InventoryScope.of(context);
    final inventory = controller.inventory!;
    final theme = Theme.of(context);

    return ExpansionTile(
      leading: Icon(category.icon, color: theme.colorScheme.primary),
      title: Text(category.label),
      subtitle: Text('${permissionNames.length} permission(s)'),
      // Sensitive categories are the ones worth opening first.
      initiallyExpanded: category == PermissionCatalog.special,
      children: [
        for (final name in permissionNames)
          Builder(
            builder: (context) {
              final info = inventory.infoOf(name);
              final usages = inventory.usagesOf(name);
              final grantedCount = usages.where((usage) => usage.granted).length;

              return ListTile(
                contentPadding: const EdgeInsets.only(left: 32, right: 16),
                title: Text(info.displayLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  info.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Text(
                  '$grantedCount/${usages.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: grantedCount > 0
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: grantedCount > 0 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PermissionDetailScreen(permissionName: name),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
