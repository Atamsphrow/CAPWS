import 'package:flutter/material.dart';

import '../models/permission_catalog.dart';
import '../models/permission_info.dart';
import '../services/shizuku_bridge.dart';

/// A row with a switch that actually changes a permission.
///
/// Used from both directions — permissions of one app, and apps holding one
/// permission — so the identity shown ([title], [subtitle], [leading]) is supplied
/// by the caller while the permission semantics live here.
class PermissionToggleTile extends StatefulWidget {
  const PermissionToggleTile({
    super.key,
    required this.permission,
    required this.granted,
    required this.shizukuReady,
    required this.title,
    required this.onChange,
    this.subtitle,
    this.leading,
    this.onOpenSettings,
    this.onTap,
    this.showProtectionBadge = true,
  });

  final PermissionInfo permission;
  final bool granted;
  final bool shizukuReady;

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Performs the privileged write. Returns the raw result so this tile can report
  /// which path handled it, or why it failed.
  final Future<PermissionWriteResult> Function(bool grant) onChange;

  /// Opens the relevant Settings screen — the honest fallback whenever Shizuku
  /// cannot do the job.
  final VoidCallback? onOpenSettings;

  final VoidCallback? onTap;
  final bool showProtectionBadge;

  @override
  State<PermissionToggleTile> createState() => _PermissionToggleTileState();
}

class _PermissionToggleTileState extends State<PermissionToggleTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mode = PermissionCatalog.modeFor(widget.permission);
    final changeable = mode == ToggleMode.runtime || mode == ToggleMode.appOp;

    return ListTile(
      onTap: widget.onTap,
      leading: widget.leading,
      title: Row(
        children: [
          Expanded(child: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis)),
          if (widget.showProtectionBadge) _ProtectionBadge(mode: mode),
        ],
      ),
      subtitle: widget.subtitle == null
          ? null
          : Text(
              widget.subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
      trailing: _buildTrailing(context, mode, changeable),
    );
  }

  Widget _buildTrailing(BuildContext context, ToggleMode mode, bool changeable) {
    if (_busy) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (!changeable) {
      // No switch at all: a disabled switch reads as "we could do this but won't",
      // when the truth is that Android provides no way to.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.granted ? Icons.lock_outline : Icons.lock_open_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.outline,
          ),
          if (widget.onOpenSettings != null)
            IconButton(
              tooltip: mode == ToggleMode.redirectOnly
                  ? 'Ouvrir les réglages système'
                  : 'Voir dans les réglages',
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: widget.onOpenSettings,
            ),
        ],
      );
    }

    if (!widget.shizukuReady) {
      return IconButton(
        tooltip: 'Shizuku indisponible — ouvrir les réglages système',
        icon: const Icon(Icons.open_in_new),
        onPressed: widget.onOpenSettings,
      );
    }

    return Switch(value: widget.granted, onChanged: (value) => _handleChange(value));
  }

  Future<void> _handleChange(bool grant) async {
    final confirmed = await _confirm(grant);
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final result = await widget.onChange(grant);
    if (!mounted) return;
    setState(() => _busy = false);

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (result.ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${widget.permission.displayLabel} '
            '${grant ? 'accordée' : 'révoquée'}'
            '${result.via == null ? '' : ' (${result.via})'}',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Échec de la modification.'),
          duration: const Duration(seconds: 6),
          action: widget.onOpenSettings == null
              ? null
              : SnackBarAction(label: 'Réglages', onPressed: widget.onOpenSettings!),
        ),
      );
    }
  }

  /// Confirmation is required in both directions: revoking can break a running
  /// app, and granting hands out real access.
  Future<bool> _confirm(bool grant) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(grant ? Icons.lock_open_outlined : Icons.block),
        title: Text(grant ? 'Accorder la permission ?' : 'Révoquer la permission ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.permission.displayLabel}\n${widget.title}'),
            const SizedBox(height: 12),
            Text(
              grant
                  ? 'L\'app aura immédiatement accès, sans passer par sa propre demande '
                        'de permission.'
                  : 'L\'app peut se fermer ou mal fonctionner si elle utilise cette '
                        'permission en ce moment.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(grant ? 'Accorder' : 'Révoquer'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Tells the user *why* a row behaves the way it does.
class _ProtectionBadge extends StatelessWidget {
  const _ProtectionBadge({required this.mode});

  final ToggleMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final (String label, Color background, Color foreground) = switch (mode) {
      ToggleMode.runtime => ('runtime', colors.primaryContainer, colors.onPrimaryContainer),
      ToggleMode.appOp => ('spéciale', colors.tertiaryContainer, colors.onTertiaryContainer),
      ToggleMode.redirectOnly => (
        'réglages',
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
      ToggleMode.readOnly => (
        'fixe',
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };

    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
