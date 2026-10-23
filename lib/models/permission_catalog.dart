import 'package:flutter/material.dart';

import 'permission_info.dart';

/// A user-facing grouping for the Permissions tab.
class PermissionCategory {
  const PermissionCategory(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;

  @override
  bool operator ==(Object other) => other is PermissionCategory && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// How — if at all — a permission can be changed from inside the app.
enum ToggleMode {
  /// Runtime permission: grantRuntimePermission / `pm grant` via Shizuku.
  runtime,

  /// App-op backed "special" permission: `appops set` via Shizuku.
  appOp,

  /// Only reachable by sending the user to a Settings screen. Accessibility
  /// services live behind a secure setting that is deliberately not scripted here.
  redirectOnly,

  /// Install-time or signature permission. Android provides no way to revoke it,
  /// so the UI shows the state and explains why there is no switch.
  readOnly,
}

/// Everything CAPWS knows about a special (non-runtime) permission.
class SpecialPermission {
  const SpecialPermission({required this.appOp, required this.settingsKind});

  /// The app-op name for `appops set`, or null when there is no scriptable op.
  final String? appOp;

  /// Key understood by ShizukuPlugin.openSpecialSetting.
  final String settingsKind;
}

/// Static knowledge about Android permissions: how to group them, and which of
/// them are special cases rather than plain runtime permissions.
abstract final class PermissionCatalog {
  static const camera = PermissionCategory('camera', 'Caméra', Icons.photo_camera_outlined);
  static const microphone = PermissionCategory('microphone', 'Micro', Icons.mic_none_outlined);
  static const location = PermissionCategory(
    'location',
    'Localisation',
    Icons.location_on_outlined,
  );
  static const contacts = PermissionCategory(
    'contacts',
    'Contacts',
    Icons.contacts_outlined,
  );
  static const calendar = PermissionCategory(
    'calendar',
    'Agenda',
    Icons.calendar_month_outlined,
  );
  static const sms = PermissionCategory('sms', 'SMS', Icons.sms_outlined);
  static const phone = PermissionCategory('phone', 'Téléphone', Icons.call_outlined);
  static const storage = PermissionCategory(
    'storage',
    'Fichiers et stockage',
    Icons.folder_outlined,
  );
  static const media = PermissionCategory(
    'media',
    'Photos et médias',
    Icons.perm_media_outlined,
  );
  static const sensors = PermissionCategory(
    'sensors',
    'Capteurs corporels',
    Icons.monitor_heart_outlined,
  );
  static const activity = PermissionCategory(
    'activity',
    'Activité physique',
    Icons.directions_walk_outlined,
  );
  static const nearby = PermissionCategory(
    'nearby',
    'Appareils à proximité',
    Icons.bluetooth_outlined,
  );
  static const notifications = PermissionCategory(
    'notifications',
    'Notifications',
    Icons.notifications_none_outlined,
  );
  static const special = PermissionCategory(
    'special',
    'Accès spéciaux',
    Icons.admin_panel_settings_outlined,
  );
  static const network = PermissionCategory('network', 'Réseau', Icons.wifi_outlined);
  static const other = PermissionCategory('other', 'Autres', Icons.tune_outlined);

  /// Android permission-group id -> our category.
  static const Map<String, PermissionCategory> _byGroup = {
    'android.permission-group.CAMERA': camera,
    'android.permission-group.MICROPHONE': microphone,
    'android.permission-group.LOCATION': location,
    'android.permission-group.CONTACTS': contacts,
    'android.permission-group.CALENDAR': calendar,
    'android.permission-group.SMS': sms,
    'android.permission-group.PHONE': phone,
    'android.permission-group.CALL_LOG': phone,
    'android.permission-group.STORAGE': storage,
    'android.permission-group.READ_MEDIA_VISUAL': media,
    'android.permission-group.READ_MEDIA_AURAL': media,
    'android.permission-group.SENSORS': sensors,
    'android.permission-group.ACTIVITY_RECOGNITION': activity,
    'android.permission-group.NEARBY_DEVICES': nearby,
    'android.permission-group.NOTIFICATIONS': notifications,
  };

  /// Special permissions, keyed by permission name. The app-op names are the ones
  /// `appops` accepts, which do not always match the permission name.
  static const Map<String, SpecialPermission> _special = {
    'android.permission.SYSTEM_ALERT_WINDOW': SpecialPermission(
      appOp: 'SYSTEM_ALERT_WINDOW',
      settingsKind: 'overlay',
    ),
    'android.permission.PACKAGE_USAGE_STATS': SpecialPermission(
      appOp: 'GET_USAGE_STATS',
      settingsKind: 'usageAccess',
    ),
    'android.permission.WRITE_SETTINGS': SpecialPermission(
      appOp: 'WRITE_SETTINGS',
      settingsKind: 'writeSettings',
    ),
    'android.permission.MANAGE_EXTERNAL_STORAGE': SpecialPermission(
      appOp: 'MANAGE_EXTERNAL_STORAGE',
      settingsKind: 'allFiles',
    ),
    'android.permission.REQUEST_INSTALL_PACKAGES': SpecialPermission(
      appOp: 'REQUEST_INSTALL_PACKAGES',
      settingsKind: 'installPackages',
    ),
    'android.permission.SCHEDULE_EXACT_ALARM': SpecialPermission(
      appOp: 'SCHEDULE_EXACT_ALARM',
      settingsKind: 'exactAlarm',
    ),
    'android.permission.USE_EXACT_ALARM': SpecialPermission(
      appOp: 'SCHEDULE_EXACT_ALARM',
      settingsKind: 'exactAlarm',
    ),
    // Accessibility is gated by a secure setting rather than an app-op. Scripting
    // it means rewriting enabled_accessibility_services by hand, which is easy to
    // corrupt, so CAPWS only points the user at the right screen.
    'android.permission.BIND_ACCESSIBILITY_SERVICE': SpecialPermission(
      appOp: null,
      settingsKind: 'accessibility',
    ),
  };

  static SpecialPermission? specialFor(String permissionName) => _special[permissionName];

  static bool isSpecial(String permissionName) => _special.containsKey(permissionName);

  /// Where a permission belongs in the Permissions tab.
  static PermissionCategory categoryFor(PermissionInfo info) {
    if (isSpecial(info.name)) return special;

    final group = info.group;
    if (group != null) {
      final mapped = _byGroup[group];
      if (mapped != null) return mapped;
    }

    // Plenty of permissions have no group at all, so fall back to the name.
    return _byName(info.name);
  }

  static PermissionCategory _byName(String name) {
    final upper = name.toUpperCase();
    bool has(String fragment) => upper.contains(fragment);

    if (has('CAMERA')) return camera;
    if (has('RECORD_AUDIO') || has('MICROPHONE') || has('CAPTURE_AUDIO')) return microphone;
    if (has('LOCATION') || has('GPS')) return location;
    if (has('CONTACT') || has('ACCOUNTS')) return contacts;
    if (has('CALENDAR')) return calendar;
    if (has('SMS') || has('MMS')) return sms;
    if (has('CALL') || has('PHONE') || has('DIAL')) return phone;
    if (has('MEDIA_IMAGE') || has('MEDIA_VIDEO') || has('MEDIA_AUDIO')) return media;
    if (has('STORAGE') || has('DOCUMENTS') || has('MEDIA')) return storage;
    if (has('BODY_SENSORS') || has('HEALTH')) return sensors;
    if (has('ACTIVITY_RECOGNITION') || has('STEP')) return activity;
    if (has('BLUETOOTH') || has('NEARBY') || has('UWB') || has('NFC')) return nearby;
    if (has('NOTIFICATION')) return notifications;
    if (has('INTERNET') || has('NETWORK') || has('WIFI') || has('VPN')) return network;
    return other;
  }

  /// Decides which control the UI may offer for a permission.
  static ToggleMode modeFor(PermissionInfo info) {
    final special = specialFor(info.name);
    if (special != null) {
      return special.appOp == null ? ToggleMode.redirectOnly : ToggleMode.appOp;
    }
    if (info.protection == PermissionProtection.dangerous) return ToggleMode.runtime;
    return ToggleMode.readOnly;
  }

  /// Why a permission cannot be toggled, for the UI to show instead of a switch.
  static String? readOnlyReason(PermissionInfo info) {
    switch (info.protection) {
      case PermissionProtection.normal:
        return 'Permission accordée à l\'installation : Android ne permet pas de la '
            'révoquer, même avec Shizuku.';
      case PermissionProtection.signature:
      case PermissionProtection.signatureOrSystem:
        return 'Permission réservée aux apps signées avec la clé de la plateforme. '
            'Non modifiable.';
      case PermissionProtection.unknown:
        return 'Permission non résolue par le système (définie par le constructeur '
            'ou par une app désinstallée). État non modifiable.';
      case PermissionProtection.dangerous:
        return null;
    }
  }

  /// Every category, in the order the Permissions tab shows them.
  static const List<PermissionCategory> ordered = [
    location,
    camera,
    microphone,
    contacts,
    calendar,
    sms,
    phone,
    storage,
    media,
    nearby,
    sensors,
    activity,
    notifications,
    special,
    network,
    other,
  ];
}
