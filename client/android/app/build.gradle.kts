import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load release signing credentials from android/key.properties (kept out of git).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "dev.rudnowski.freevpn"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.rudnowski.freevpn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            // flutter_v2ray executes libtun2socks.so as a standalone binary via
            // ProcessBuilder, which requires the .so files to be extracted to
            // disk (nativeLibraryDir). The modern default (extractNativeLibs=false)
            // keeps them inside the APK, so tun2socks silently never starts and
            // the VPN connects without passing any traffic.
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        // Only define the release signing config when key.properties is present.
        // Falls back to debug signing otherwise (e.g. on machines without the key).
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the real release keystore when configured; otherwise debug keys
            // so `flutter run --release` still works on unconfigured machines.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // R8 was stripping Room/WorkManager generated classes
            // (androidx.work.impl.WorkDatabase_Impl), which google_mobile_ads needs
            // at startup, causing an immediate crash. Native libs dominate APK size,
            // so disabling code shrinking here has negligible size impact.
            isMinifyEnabled = false
            isShrinkResources = false

            // Ship only real-device architectures. x86/x86_64 are emulator-only and
            // the v2ray core (libgojni.so) is ~30 MB per ABI, so dropping them trims
            // a lot from the bundle/APK. Debug builds keep all ABIs for emulators.
            ndk {
                abiFilters += listOf("arm64-v8a", "armeabi-v7a")
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
