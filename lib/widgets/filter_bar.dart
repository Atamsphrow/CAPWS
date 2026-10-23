import 'package:flutter/material.dart';

import '../models/app_info.dart';
import '../services/inventory_controller.dart';

/// Search field plus the three filter chips from the spec, shared by both list
/// tabs so a query typed in one carries over to the other.
class FilterBar extends StatefulWidget {
  const FilterBar({super.key, required this.hintText});

  final String hintText;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = InventoryScope.of(context);
    final filters = controller.filters;

    // The dashboard can change the query while this field is offscreen, so the
    // field is reconciled with the controller rather than owning the truth.
    if (_text.text != filters.query) {
      _text.value = TextEditingValue(
        text: filters.query,
        selection: TextSelection.collapsed(offset: filters.query.length),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchBar(
            controller: _text,
            hintText: widget.hintText,
            leading: const Icon(Icons.search),
            trailing: [
              if (filters.query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => controller.updateQuery(''),
                ),
            ],
            onChanged: controller.updateQuery,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Apps système'),
                selected: filters.scope != AppScope.userOnly,
                onSelected: (selected) => controller.setFilters(
                  filters.copyWith(scope: selected ? AppScope.all : AppScope.userOnly),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Accordées seulement'),
                selected: filters.onlyGranted,
                onSelected: (selected) =>
                    controller.setFilters(filters.copyWith(onlyGranted: selected)),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Sensibles seulement'),
                selected: filters.onlySensitive,
                onSelected: (selected) =>
                    controller.setFilters(filters.copyWith(onlySensitive: selected)),
              ),
              if (filters.hasInstallerFilter) ...[
                const SizedBox(width: 8),
                InputChip(
                  avatar: const Icon(Icons.storefront_outlined, size: 18),
                  label: Text(installerLabel(filters.installer!.value)),
                  onDeleted: () =>
                      controller.setFilters(filters.copyWith(resetInstaller: true)),
                ),
              ],
              if (filters.activeCount > 0) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: controller.resetFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Réinitialiser'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
