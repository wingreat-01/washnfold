import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing values live in android/key.properties (never commit it).
val keystoreProps = Properties()
val keystoreFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystoreFile.exists()
if (hasReleaseKeystore) {
    keystoreProps.load(FileInputStream(keystoreFile))
}

android {
    // Keep the namespace as-is so MainActivity's package still resolves.
    // It is separate from applicationId and can differ from it.
    namespace = "com.example.washnfold"

    // Google Play requires targeting API 36+. maxOf() uses your Flutter
    // version's value when it is already 36 or higher, otherwise forces 36.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // PERMANENT once uploaded to Google Play. Change it only if you
        // want a different ID, and only before your first upload.
        applicationId = "com.prohubapps.laundry"
        minSdk = flutter.minSdkVersion
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        // Taken from pubspec.yaml: version: 1.0.0+1  (the +1 is versionCode).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
                storeFile = file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // With key.properties present, sign with the upload key.
            // Without it, fall back to debug keys so local
            // `flutter run --release` still works. Play rejects
            // debug-signed bundles, so you can't upload by accident.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
