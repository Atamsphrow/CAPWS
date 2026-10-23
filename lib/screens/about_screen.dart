import 'package:flutter/material.dart';

import '../app_identity.dart';
import '../services/inventory_controller.dart';

/// Owner identity and app facts.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _photoHeroTag = 'owner-photo';

  @override
  Widget build(BuildContext context) {
    final controller = InventoryScope.of(context);
    final inventory = controller.inventory;
    final self = inventory?.appOf(AppIdentity.packageName);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      // No leading arrow: the phone's back action is the only way back by design.
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('À propos'),
      ),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _OwnerPhoto(
                    heroTag: _photoHeroTag,
                    size: 88,
                    onTap: () => _openPhoto(context),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppIdentity.ownerName, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          AppIdentity.ownerRole,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('Application', style: theme.textTheme.titleMedium),
          ),
          _InfoRow(label: 'Nom', value: AppIdentity.name),
          _InfoRow(label: 'Description', value: AppIdentity.tagline),
          _InfoRow(label: 'Package', value: AppIdentity.packageName),
          _InfoRow(label: 'Version', value: self?.versionName ?? 'inconnue'),
          if (inventory != null) _InfoRow(label: 'Android SDK', value: '${inventory.androidSdk}'),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('Shizuku', style: theme.textTheme.titleMedium),
          ),
          _InfoRow(
            label: 'État',
            value: controller.status.isReady
                ? 'actif, autorisation accordée'
                : 'indisponible',
          ),
          if (controller.status.version > 0)
            _InfoRow(label: 'Version du service', value: '${controller.status.version}'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => controller.bridge.openShizukuInstall(),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Shizuku sur le Play Store / le site'),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _openPhoto(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        // Opaque:false so the photo appears to lift out of the card over the
        // screen behind it rather than replacing it.
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) => const _PhotoViewer(heroTag: _photoHeroTag),
      ),
    );
  }
}

/// The circular avatar. Kept separate so the Hero child is identical on both
/// sides of the transition.
class _OwnerPhoto extends StatelessWidget {
  const _OwnerPhoto({required this.heroTag, required this.size, required this.onTap});

  final String heroTag;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Photo de ${AppIdentity.ownerName}, toucher pour agrandir',
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Hero(
          tag: heroTag,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.primary, width: 2),
            ),
            child: ClipOval(
              child: Image.asset(
                AppIdentity.ownerPhoto,
                fit: BoxFit.cover,
                // A missing or unreadable asset should not take the screen down.
                errorBuilder: (context, error, stack) => Container(
                  color: colors.surfaceContainerHighest,
                  child: Icon(
                    Icons.person_outline,
                    size: size * 0.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen, pinch-zoomable view of the photo.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.heroTag});

  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tapping the backdrop closes; the image itself keeps its own gestures
          // so a pinch-zoom is never mistaken for a dismiss.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          Center(
            child: Hero(
              tag: heroTag,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Image.asset(
                  AppIdentity.ownerPhoto,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Photo introuvable.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
