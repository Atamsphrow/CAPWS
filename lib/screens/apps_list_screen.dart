import 'package:flutter/material.dart';

import '../services/inventory_controller.dart';
import '../widgets/app_list_tile.dart';
import '../widgets/filter_bar.dart';
import 'app_detail_screen.dart';

/// Every installed app, filtered by the shared search and chips.
class AppsListScreen extends StatelessWidget {
  const AppsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = InventoryScope.of(context);
    final inventory = controller.inventory;
    final apps = controller.filteredApps();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apps'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilterBar(hintText: 'Nom d\'app, package ou permission'),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.refresh(showSpinner: false),
        child: inventory == null
            ? const Center(child: CircularProgressIndicator())
            : apps.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 64),
                  Center(child: Text('Aucune app ne correspond aux filtres.')),
                ],
              )
            : ListView.builder(
                itemCount: apps.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        '${apps.length} app(s)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  final app = apps[index - 1];
                  return AppListTile(
                    app: app,
                    inventory: inventory,
                    bridge: controller.bridge,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AppDetailScreen(packageName: app.packageName),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
