/// Android's base protection level, which decides whether a permission can be
/// toggled at all.
enum PermissionProtection {
  /// Granted at install time and not revocable — Android has no API for it, and
  /// `pm revoke` refuses. Shown read-only.
  normal,

  /// A runtime permission. This is the only class Shizuku can grant and revoke
  /// through grantRuntimePermission / `pm grant`.
  dangerous,

  /// Reserved for apps signed with the platform key. Not user-controllable.
  signature,
  signatureOrSystem,

  /// PackageManager could not resolve the permission (vendor-defined, or declared
  /// by an app that has since been uninstalled).
  unknown;

  static PermissionProtection parse(String? raw) => switch (raw) {
    'normal' => PermissionProtection.normal,
    'dangerous' => PermissionProtection.dangerous,
    'signature' => PermissionProtection.signature,
    'signatureOrSystem' => PermissionProtection.signatureOrSystem,
    _ => PermissionProtection.unknown,
  };

  bool get isSensitive => this == PermissionProtection.dangerous;
}

/// Metadata for one permission, resolved once per device inventory.
class PermissionInfo {
  const PermissionInfo({
    required this.name,
    required this.label,
    required this.description,
    required this.group,
    required this.groupLabel,
    required this.protection,
    required this.known,
  });

  final String name;
  final String? label;
  final String? description;
  final String? group;
  final String? groupLabel;
  final PermissionProtection protection;
  final bool known;

  /// `android.permission.CAMERA` -> `CAMERA`.
  String get shortName {
    final lastDot = name.lastIndexOf('.');
    return lastDot == -1 ? name : name.substring(lastDot + 1);
  }

  /// The label Android ships is often nicer than the constant name, but plenty of
  /// permissions have none.
  String get displayLabel {
    final value = label?.trim();
    if (value == null || value.isEmpty) return shortName;
    return value;
  }

  factory PermissionInfo.fromMap(String name, Map<Object?, Object?> map) => PermissionInfo(
    name: name,
    label: map['label'] as String?,
    description: map['description'] as String?,
    group: map['group'] as String?,
    groupLabel: map['groupLabel'] as String?,
    protection: PermissionProtection.parse(map['protection'] as String?),
    known: map['known'] as bool? ?? false,
  );

  /// Placeholder for a permission that appears in an app's manifest but that
  /// PackageManager would not resolve at all.
  factory PermissionInfo.unresolved(String name) => PermissionInfo(
    name: name,
    label: null,
    description: null,
    group: null,
    groupLabel: null,
    protection: PermissionProtection.unknown,
    known: false,
  );
}
