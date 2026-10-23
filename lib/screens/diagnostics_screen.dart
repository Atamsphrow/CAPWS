import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_identity.dart';
import '../services/error_reporter.dart';
import '../services/inventory_controller.dart';

/// The in-app bug and error log, plus the context needed to make sense of it.
///
/// This is what turns "ça ne marche pas" into something actionable: the report it
/// copies carries the Android version, the Shizuku state, and every captured
/// failure with its stack — the things that decide whether a permission toggle was
/// refused by Shizuku, by Android, or by a bug here.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final ErrorReporter _reporter = ErrorReporter.instance;

  @override
  void initState() {
    super.initState();
    _reporter.addListener(_onChange);
    // Opening the screen is what clears the dashboard badge.
    _reporter.markSeen();
  }

  @override
  void dispose() {
    _reporter.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// Everything the log alone cannot tell you.
  Map<String, String> _header(InventoryController controller) {
    final inventory = controller.inventory;
    final self = inventory?.appOf(AppIdentity.packageName);
    final status = controller.status;

    return {
      'App': '${AppIdentity.name} ${self?.versionName ?? '(version inconnue)'} '
          '(${AppIdentity.packageName})',
      'Android SDK': '${inventory?.androidSdk ?? 0}',
      'Utilisateur Android': '${inventory?.currentUserId ?? 0}',
      'Shizuku': 'installé=${status.installed} actif=${status.running} '
          'permission=${status.permissionGranted} '
          'version=${status.version} uid=${status.uid}'
          '${status.preV11 ? ' PRE-V11' : ''}',
      'Inventaire': inventory == null
          ? 'non chargé'
          : '${inventory.apps.length} apps '
                '(${inventory.userAppCount} utilisateur, '
                '${inventory.systemAppCount} système), '
                '${inventory.grantedSensitiveCount} permissions runtime accordées',
      'Erreur de chargement': controller.error ?? 'aucune',
    };
  }

  Future<void> _copyReport(InventoryController controller) async {
    final report = _reporter.buildReport(_header(controller));
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Rapport copié (${report.length} caractères)')),
      );
  }

  /// Proves the capture chain works on the device rather than only in theory.
  void _selfTest() {
    _reporter.record(
      kind: AppErrorKind.manual,
      message: 'Auto-test du capteur déclenché depuis l\'écran Diagnostic.',
      context: 'bouton « Tester le capteur »',
    );
    // Thrown inside a post-frame callback so it travels through
    // PlatformDispatcher.onError, exercising the real async path too.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.error(
        StateError('Erreur de test CAPWS — capture asynchrone vérifiée'),
        StackTrace.current,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = InventoryScope.of(context);
    final theme = Theme.of(context);
    final entries = _reporter.entries;

    return Scaffold(
      appBar: AppBar(
        // No leading arrow: the phone's back action is the only way back by design.
        automaticallyImplyLeading: false,
        title: const Text('Diagnostic'),
        actions: [
          IconButton(
            tooltip: 'Copier le rapport',
            onPressed: () => _copyReport(controller),
            icon: const Icon(Icons.copy_all_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'test':
                  _selfTest();
                case 'clear':
                  _reporter.clear();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'test', child: Text('Tester le capteur')),
              PopupMenuItem(value: 'clear', child: Text('Vider le journal')),
            ],
          ),
        ],
      ),
      body: ListView(
        children: [
          _HeaderCard(entries: _header(controller)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Row(
              children: [
                Text('Journal', style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                Text(
                  _reporter.dropped > 0
                      ? '${entries.length} entrée(s), ${_reporter.dropped} plus ancienne(s) supprimée(s)'
                      : '${entries.length} entrée(s)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Aucune erreur capturée depuis le lancement.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Le journal vit en mémoire : il repart à zéro à chaque '
                      'démarrage de l\'app.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final entry in entries) _ErrorTile(error: entry),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.entries});

  final Map<String, String> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in entries.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 132,
                      child: Text(
                        entry.key,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        entry.value,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.error});

  final AppError error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final trace = error.stack;

    return ExpansionTile(
      leading: Icon(_iconFor(error.kind), color: colors.error),
      title: Text(error.message, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${error.shortTime} · ${error.kind.label}'
        '${error.context == null ? '' : ' · ${error.context}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(error.message, style: theme.textTheme.bodyMedium),
              if (error.context != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  'Contexte : ${error.context}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (trace != null && trace.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  // Stack frames must not wrap mid-line to stay readable, so the
                  // trace scrolls sideways instead.
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      trace.trimRight(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  IconData _iconFor(AppErrorKind kind) => switch (kind) {
    AppErrorKind.flutter => Icons.widgets_outlined,
    AppErrorKind.platform => Icons.bolt_outlined,
    AppErrorKind.native => Icons.memory_outlined,
    AppErrorKind.permissionWrite => Icons.edit_off_outlined,
    AppErrorKind.inventory => Icons.inventory_2_outlined,
    AppErrorKind.manual => Icons.science_outlined,
  };
}
