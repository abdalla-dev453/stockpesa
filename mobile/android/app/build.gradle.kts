plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningFile = rootProject.file("key.properties")
val releaseSigningProperties = java.util.Properties().apply {
    if (releaseSigningFile.exists()) {
        releaseSigningFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.example.stockpesa"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.stockpesa"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (releaseSigningFile.exists()) {
        signingConfigs {
            create("release") {
                storeFile = file(requireNotNull(releaseSigningProperties.getProperty("storeFile")) { "storeFile is required in android/key.properties" })
                storePassword = requireNotNull(releaseSigningProperties.getProperty("storePassword")) { "storePassword is required in android/key.properties" }
                keyAlias = requireNotNull(releaseSigningProperties.getProperty("keyAlias")) { "keyAlias is required in android/key.properties" }
                keyPassword = requireNotNull(releaseSigningProperties.getProperty("keyPassword")) { "keyPassword is required in android/key.properties" }
            }
        }
    }

    buildTypes {
        release {
            // Without an operator-provided key.properties, this release remains unsigned.
            // Never sign a distributable build with the developer debug key.
            if (releaseSigningFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
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
