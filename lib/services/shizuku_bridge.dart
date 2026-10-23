import 'package:flutter/services.dart';

/// What is standing between CAPWS and being able to change permissions.
enum ShizukuReadiness {
  notInstalled,
  notRunning,
  permissionMissing,

  /// Shizuku is running and has granted CAPWS the API permission.
  ready,
}

/// Snapshot of the Shizuku side of the world.
class ShizukuStatus {
  const ShizukuStatus({
    required this.installed,
    required this.running,
    required this.permissionGranted,
    required this.shouldShowRationale,
    required this.preV11,
    required this.version,
    required this.uid,
  });

  const ShizukuStatus.unknown()
    : installed = false,
      running = false,
      permissionGranted = false,
      shouldShowRationale = false,
      preV11 = false,
      version = -1,
      uid = -1;

  final bool installed;
  final bool running;
  final bool permissionGranted;
  final bool shouldShowRationale;

  /// Pre-v11 Shizuku has no runtime permission model; the user must update.
  final bool preV11;
  final int version;
  final int uid;

  ShizukuReadiness get readiness {
    if (!installed) return ShizukuReadiness.notInstalled;
    if (!running) return ShizukuReadiness.notRunning;
    if (!permissionGranted) return ShizukuReadiness.permissionMissing;
    return ShizukuReadiness.ready;
  }

  bool get isReady => readiness == ShizukuReadiness.ready;

  factory ShizukuStatus.fromMap(Map<Object?, Object?> map) => ShizukuStatus(
    installed: map['installed'] as bool? ?? false,
    running: map['running'] as bool? ?? false,
    permissionGranted: map['permissionGranted'] as bool? ?? false,
    shouldShowRationale: map['shouldShowRationale'] as bool? ?? false,
    preV11: map['preV11'] as bool? ?? false,
    version: (map['version'] as num?)?.toInt() ?? -1,
    uid: (map['uid'] as num?)?.toInt() ?? -1,
  );
}

/// Outcome of a privileged write, including which path performed it.
class PermissionWriteResult {
  const PermissionWriteResult({required this.ok, this.via, this.error});

  final bool ok;

  /// `binder`, `shell`, `appops`… — useful when a device behaves oddly and the
  /// user needs to know that the fallback kicked in.
  final String? via;
  final String? error;

  factory PermissionWriteResult.fromMap(Map<Object?, Object?> map) => PermissionWriteResult(
    ok: map['ok'] as bool? ?? false,
    via: map['via'] as String?,
    error: map['error'] as String?,
  );

  factory PermissionWriteResult.failed(String message) =>
      PermissionWriteResult(ok: false, error: message);
}

/// Events the native side pushes without being asked.
enum ShizukuEvent { binderReceived, binderDead, permissionGranted, permissionDenied }

/// Thin, typed wrapper over the MethodChannel. No caching and no business rules —
/// that belongs to [InventoryController].
class ShizukuBridge {
  ShizukuBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _channel = methodChannel ?? const MethodChannel(_methodChannelName),
       _events = eventChannel ?? const EventChannel(_eventChannelName);

  static const _methodChannelName = 'com.atamsphrow.capws/shizuku';
  static const _eventChannelName = 'com.atamsphrow.capws/shizuku_events';

  final MethodChannel _channel;
  final EventChannel _events;

  /// Shizuku can die and come back on its own (ADB wifi sessions especially), so
  /// the UI subscribes rather than assuming the first status reading holds.
  Stream<ShizukuEvent> get events => _events.receiveBroadcastStream().map((raw) {
    final map = (raw as Map).cast<Object?, Object?>();
    return switch (map['event'] as String?) {
      'binderReceived' => ShizukuEvent.binderReceived,
      'binderDead' => ShizukuEvent.binderDead,
      'permissionResult' =>
        (map['granted'] as bool? ?? false)
            ? ShizukuEvent.permissionGranted
            : ShizukuEvent.permissionDenied,
      _ => ShizukuEvent.binderDead,
    };
  });

  Future<ShizukuStatus> status() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('getShizukuStatus');
    if (raw == null) return const ShizukuStatus.unknown();
    return ShizukuStatus.fromMap(raw);
  }

  /// Shows Shizuku's own permission prompt. Resolves once the user answers.
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestShizukuPermission') ?? false;

  /// Full device inventory: apps, their permissions, and permission metadata.
  Future<Map<Object?, Object?>> inventory() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('getInventory');
    return raw ?? const {};
  }

  Future<Uint8List?> appIcon(String packageName, {int size = 96}) =>
      _channel.invokeMethod<Uint8List>('getAppIcon', {
        'packageName': packageName,
        'size': size,
      });

  Future<PermissionWriteResult> setRuntimePermission({
    required String packageName,
    required String permission,
    required bool grant,
  }) => _write('setRuntimePermission', {
    'packageName': packageName,
    'permission': permission,
    'grant': grant,
  });

  Future<PermissionWriteResult> setAppOp({
    required String packageName,
    required String op,
    required bool allow,
  }) => _write('setAppOp', {'packageName': packageName, 'op': op, 'allow': allow});

  /// `allow`, `ignore`, `deny`, `default`, or null when it cannot be read.
  Future<String?> appOpMode({required String packageName, required String op}) =>
      _channel.invokeMethod<String>('getAppOpMode', {
        'packageName': packageName,
        'op': op,
      });

  Future<bool> openAppSettings(String packageName) async =>
      await _channel.invokeMethod<bool>('openAppSettings', {
        'packageName': packageName,
      }) ??
      false;

  Future<bool> openSpecialSetting(String kind, {String? packageName}) async =>
      await _channel.invokeMethod<bool>('openSpecialSetting', {
        'kind': kind,
        'packageName': packageName,
      }) ??
      false;

  Future<bool> openShizukuInstall() async =>
      await _channel.invokeMethod<bool>('openShizukuInstall') ?? false;

  Future<bool> launchShizuku() async =>
      await _channel.invokeMethod<bool>('launchShizuku') ?? false;

  Future<PermissionWriteResult> _write(String method, Map<String, Object?> args) async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(method, args);
      if (raw == null) return PermissionWriteResult.failed('Réponse native vide.');
      return PermissionWriteResult.fromMap(raw);
    } on PlatformException catch (error) {
      return PermissionWriteResult.failed(error.message ?? error.code);
    } on MissingPluginException {
      return PermissionWriteResult.failed('Pont natif indisponible.');
    }
  }
}
