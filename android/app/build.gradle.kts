import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (never committed — it and the
// keystore are git-ignored) holds storeFile, storePassword, keyAlias and
// keyPassword. See android/key.properties.example. Without it the release build
// falls back to the debug key, loudly: a warning is printed and the APK is named
// waha-kiosk-release-DEBUGKEY.apk so it cannot be mistaken for a properly signed one.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val useReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.example.waha_platform"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.waha_platform"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // No Geidea/USB SDK here (waha_client has no payment terminal), so
        // no reason to pin below Flutter's own default.
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (useReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (useReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn("WARNING: android/key.properties not found — signing the release build with the DEBUG key.")
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }

    // Renames the built APK from Flutter's generic app-release.apk to
    // something that identifies itself on sight — waha-client-release.apk —
    // since this is handed off/installed manually rather than through a
    // store listing that already carries the app's name.
    applicationVariants.all {
        val variant = this
        variant.outputs
            .map { it as com.android.build.gradle.internal.api.BaseVariantOutputImpl }
            .forEach { output ->
                val keyTag = if (variant.buildType.name == "release" && !useReleaseKey) "-DEBUGKEY" else ""
                output.outputFileName = "waha-client-${variant.buildType.name}$keyTag.apk"
            }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // No native dependencies — waha_client has no payment-terminal SDK and
    // no custom Kotlin diagnostics; MainActivity is a plain FlutterActivity.
}

flutter {
    source = "../.."
}
