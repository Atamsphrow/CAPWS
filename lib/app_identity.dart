/// Facts about the app itself, kept in one place because the diagnostics report,
/// the about screen and the native channel names all need to agree.
abstract final class AppIdentity {
  static const String name = 'CAPWS';
  static const String tagline = 'Change App Permissions with Shizuku';

  /// Must match `applicationId` in android/app/build.gradle.kts. The app looks
  /// itself up in its own inventory to report its version, which avoids pulling in
  /// a package-info plugin for one string.
  static const String packageName = 'com.atamsphrow.capws';

  static const String ownerName = 'Atamsphrow';
  static const String ownerRole = 'Propriétaire';
  static const String ownerPhoto = 'assets/owner.jpg';

  static const String shizukuSite = 'https://shizuku.rikka.app/';
}
