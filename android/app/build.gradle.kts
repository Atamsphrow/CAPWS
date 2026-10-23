import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Real signing credentials live in android/key.properties, which is gitignored and
// never checked in. When it is absent (fresh clone, CI without secrets) the release
// build falls back to the debug key rather than failing at configuration time.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.atamsphrow.capws"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.atamsphrow.capws"
        // Shizuku itself requires API 23; 24 is the Flutter floor anyway.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // Declared explicitly: the file keeps its .jks name for continuity but
                // was migrated to PKCS12, since keytool now warns that JKS is a
                // proprietary legacy format.
                storeType = "PKCS12"

                // v1 (JAR signing) is only needed below API 24, and minSdk is 24.
                // v3 carries the key-rotation lineage, so it is worth having from the
                // first release rather than after a key is already in the wild.
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "CAPWS: android/key.properties absent - the release build is signed " +
                        "with the debug key and cannot be published."
                )
                signingConfigs.getByName("debug")
            }

            // Left off deliberately. This app reaches IPermissionManager,
            // IPackageManager and Shizuku.newProcess purely by reflection, so R8 sees
            // them as unused and would strip or rename them. The failure would surface
            // only at runtime, only in release, as a permission toggle that silently
            // does nothing. proguard-rules.pro already carries the keep rules needed to
            // turn this on; flip it once a release build has been validated on a device.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Shizuku client API + the ContentProvider that lets Shizuku bind to us early.
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    // Lets us reflect on IPermissionManager / IPackageManager, which are on the
    // non-SDK denylist from Android 9 onwards.
    implementation("org.lsposed.hiddenapibypass:hiddenapibypass:6.1")
}

flutter {
    source = "../.."
}
