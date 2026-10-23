import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/shizuku_bridge.dart';

/// Lazily loads an app icon over the MethodChannel and keeps it in memory.
///
/// Icons are fetched per tile rather than shipped with the inventory: a few
/// hundred PNGs in one channel reply is the difference between a snappy list and
/// a two-second stall. The cache is process-wide because the same packages are
/// re-rendered constantly while scrolling and navigating.
class AppIcon extends StatefulWidget {
  const AppIcon({
    super.key,
    required this.packageName,
    required this.bridge,
    this.size = 40,
  });

  final String packageName;
  final ShizukuBridge bridge;
  final double size;

  static final Map<String, Uint8List?> _cache = {};

  /// Dropped when the app list is reloaded, so a reinstalled app picks up its new
  /// icon instead of the stale one.
  static void clearCache() => _cache.clear();

  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  Uint8List? _bytes;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageName != widget.packageName) {
      _resolved = false;
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (AppIcon._cache.containsKey(widget.packageName)) {
      setState(() {
        _bytes = AppIcon._cache[widget.packageName];
        _resolved = true;
      });
      return;
    }
    Uint8List? bytes;
    try {
      bytes = await widget.bridge.appIcon(
        widget.packageName,
        size: (widget.size * 2.5).round(),
      );
    } catch (_) {
      bytes = null;
    }
    AppIcon._cache[widget.packageName] = bytes;
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bytes = _bytes;

    if (bytes != null) {
      return Image.memory(
        bytes,
        width: widget.size,
        height: widget.size,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(widget.size / 4),
      ),
      child: _resolved
          ? Icon(Icons.android, size: widget.size * 0.6, color: colors.onSurfaceVariant)
          : null,
    );
  }
}
