import 'package:capws/models/app_info.dart';
import 'package:capws/models/permission_catalog.dart';
import 'package:capws/models/permission_info.dart';
import 'package:capws/services/inventory_controller.dart';
import 'package:capws/services/package_manager_service.dart';
import 'package:flutter_test/flutter_test.dart';

PermissionInfo permission(
  String name, {
  PermissionProtection protection = PermissionProtection.dangerous,
  String? group,
}) => PermissionInfo(
  name: name,
  label: null,
  description: null,
  group: group,
  groupLabel: null,
  protection: protection,
  known: true,
);

AppInfo app(
  String packageName, {
  bool isSystem = false,
  String? installer,
  Map<String, bool> permissions = const {},
}) => AppInfo(
  packageName: packageName,
  label: packageName,
  versionName: '1.0',
  isSystem: isSystem,
  enabled: true,
  targetSdk: 34,
  installer: installer,
  firstInstall: DateTime(2026),
  lastUpdate: DateTime(2026),
  permissions: [
    for (final entry in permissions.entries)
      AppPermission(name: entry.key, granted: entry.value),
  ],
);

void main() {
  group('PermissionCatalog.modeFor', () {
    test('runtime permissions are toggled through the runtime path', () {
      expect(
        PermissionCatalog.modeFor(permission('android.permission.CAMERA')),
        ToggleMode.runtime,
      );
    });

    test('app-op backed special permissions use the app-op path', () {
      expect(
        PermissionCatalog.modeFor(permission('android.permission.SYSTEM_ALERT_WINDOW')),
        ToggleMode.appOp,
      );
      expect(
        PermissionCatalog.specialFor('android.permission.PACKAGE_USAGE_STATS')?.appOp,
        'GET_USAGE_STATS',
      );
    });

    test('accessibility is redirect-only because it is a secure setting', () {
      expect(
        PermissionCatalog.modeFor(
          permission('android.permission.BIND_ACCESSIBILITY_SERVICE'),
        ),
        ToggleMode.redirectOnly,
      );
    });

    test('install-time and signature permissions are read-only', () {
      for (final protection in [
        PermissionProtection.normal,
        PermissionProtection.signature,
        PermissionProtection.signatureOrSystem,
        PermissionProtection.unknown,
      ]) {
        final info = permission('android.permission.INTERNET', protection: protection);
        expect(PermissionCatalog.modeFor(info), ToggleMode.readOnly);
        expect(PermissionCatalog.readOnlyReason(info), isNotNull);
      }
    });

    test('a dangerous permission has no read-only explanation', () {
      expect(
        PermissionCatalog.readOnlyReason(permission('android.permission.CAMERA')),
        isNull,
      );
    });
  });

  group('PermissionCatalog.categoryFor', () {
    test('uses the Android permission group when there is one', () {
      expect(
        PermissionCatalog.categoryFor(
          permission('android.permission.CAMERA', group: 'android.permission-group.CAMERA'),
        ),
        PermissionCatalog.camera,
      );
    });

    test('falls back to the permission name when it has no group', () {
      expect(
        PermissionCatalog.categoryFor(permission('android.permission.RECORD_AUDIO')),
        PermissionCatalog.microphone,
      );
      expect(
        PermissionCatalog.categoryFor(permission('com.vendor.WEIRD_THING')),
        PermissionCatalog.other,
      );
    });

    test('special permissions win over their group', () {
      expect(
        PermissionCatalog.categoryFor(
          permission(
            'android.permission.SYSTEM_ALERT_WINDOW',
            group: 'android.permission-group.CAMERA',
          ),
        ),
        PermissionCatalog.special,
      );
    });

    test('every category is reachable from the ordered list', () {
      expect(PermissionCatalog.ordered, contains(PermissionCatalog.special));
      expect(PermissionCatalog.ordered.toSet().length, PermissionCatalog.ordered.length);
    });
  });

  group('Inventory', () {
    Inventory build() => Inventory(
      androidSdk: 34,
      currentUserId: 0,
      apps: [
        app(
          'com.a',
          installer: 'com.android.vending',
          permissions: {
            'android.permission.CAMERA': true,
            'android.permission.INTERNET': true,
          },
        ),
        app(
          'com.b',
          permissions: {
            'android.permission.CAMERA': false,
            'android.permission.RECORD_AUDIO': true,
          },
        ),
        app(
          'com.sys',
          isSystem: true,
          permissions: {'android.permission.CAMERA': true},
        ),
      ],
      permissions: {
        'android.permission.CAMERA': permission('android.permission.CAMERA'),
        'android.permission.RECORD_AUDIO': permission('android.permission.RECORD_AUDIO'),
        'android.permission.INTERNET': permission(
          'android.permission.INTERNET',
          protection: PermissionProtection.normal,
        ),
      },
    );

    test('indexes apps by permission, sorted by label', () {
      final usages = build().usagesOf('android.permission.CAMERA');
      expect(usages.map((usage) => usage.app.packageName), ['com.a', 'com.b', 'com.sys']);
      expect(usages.map((usage) => usage.granted), [true, false, true]);
    });

    test('counts only granted runtime permissions as sensitive', () {
      // CAMERA granted twice and RECORD_AUDIO once; INTERNET is normal, so excluded.
      expect(build().grantedSensitiveCount, 3);
      // com.a, com.b and com.sys each hold at least one granted runtime permission.
      expect(build().appsWithSensitiveCount, 3);
    });

    test('separates user and system apps', () {
      final inventory = build();
      expect(inventory.userAppCount, 2);
      expect(inventory.systemAppCount, 1);
    });

    test('resolves unknown permissions instead of returning null', () {
      final info = build().infoOf('com.vendor.NEVER_DECLARED');
      expect(info.protection, PermissionProtection.unknown);
      expect(info.known, isFalse);
      expect(info.displayLabel, 'NEVER_DECLARED');
    });

    test('withPermissionState patches one app without touching the others', () {
      final patched = build().withPermissionState(
        packageName: 'com.b',
        permission: 'android.permission.CAMERA',
        granted: true,
      );
      expect(
        patched.usagesOf('android.permission.CAMERA').map((usage) => usage.granted),
        [true, true, true],
      );
      expect(patched.grantedSensitiveCount, 4);
    });

    test('groups install sources with the busiest first', () {
      final breakdown = build().installerBreakdown();
      expect(breakdown.first.count, 2); // the two null-installer apps
      expect(breakdown.map((entry) => entry.installer), contains('com.android.vending'));
    });
  });

  group('Filters', () {
    test('resetInstaller clears the filter that copyWith cannot null out', () {
      const filters = Filters(installer: InstallerFilter('com.android.vending'));
      expect(filters.copyWith(onlyGranted: true).installer, isNotNull);
      expect(filters.copyWith(resetInstaller: true).installer, isNull);
    });

    test('an installer filter on a null value is still a filter', () {
      const filters = Filters(installer: InstallerFilter(null));
      expect(filters.hasInstallerFilter, isTrue);
      expect(filters.activeCount, 1);
    });

    test('equality covers every field so setFilters can short-circuit', () {
      expect(const Filters(), const Filters());
      expect(const Filters(query: 'a'), isNot(const Filters()));
      expect(const Filters(scope: AppScope.all), isNot(const Filters()));
      expect(const Filters(onlyGranted: true), isNot(const Filters()));
      expect(const Filters(onlySensitive: true), isNot(const Filters()));
      expect(
        const Filters(installer: InstallerFilter(null)),
        isNot(const Filters()),
      );
    });

    test('userOnly is the default scope and does not count as active', () {
      expect(const Filters().scope, AppScope.userOnly);
      expect(const Filters().activeCount, 0);
    });
  });

  group('AppScope', () {
    test('filters by system flag', () {
      final user = app('com.user');
      final system = app('com.sys', isSystem: true);
      expect(AppScope.userOnly.allows(user), isTrue);
      expect(AppScope.userOnly.allows(system), isFalse);
      expect(AppScope.systemOnly.allows(system), isTrue);
      expect(AppScope.systemOnly.allows(user), isFalse);
      expect(AppScope.all.allows(user) && AppScope.all.allows(system), isTrue);
    });
  });

  group('installerLabel', () {
    test('names the well-known stores and keeps unknown ids verbatim', () {
      expect(installerLabel('com.android.vending'), 'Google Play');
      expect(installerLabel(null), 'Préinstallée ou adb');
      expect(installerLabel('com.unknown.store'), 'com.unknown.store');
    });
  });
}
