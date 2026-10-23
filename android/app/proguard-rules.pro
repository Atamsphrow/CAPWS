# Keep rules for CAPWS.
#
# Everything privileged in this app is reached by reflection, so R8's reachability
# analysis cannot see it. These rules exist so that turning on isMinifyEnabled in
# app/build.gradle.kts does not silently break permission toggles at runtime.

# Shizuku's client API. Shizuku.newProcess in particular is a restricted method
# invoked only via getDeclaredMethod, and the remote process object it returns is
# also handled reflectively (getInputStream / getErrorStream / waitFor).
-keep class rikka.shizuku.** { *; }
-keep class moe.shizuku.** { *; }
-keep interface rikka.shizuku.** { *; }

# Unlocks the non-SDK denylist so IPermissionManager / IPackageManager can be
# reflected on at all; called by name from ShizukuService.
-keep class org.lsposed.hiddenapibypass.** { *; }

# Our own bridge classes are entry points from the Flutter engine and from
# reflection-heavy code paths.
-keep class com.atamsphrow.capws.** { *; }

# Reflection targets are framework classes and are never in the APK, but keeping
# the attributes means stack traces from a failed invoke stay readable.
-keepattributes Signature,InnerClasses,EnclosingMethod,Exceptions
