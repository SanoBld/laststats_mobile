plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.laststats_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        // Persistent keystore committed to the repo.
        // rootProject.file() resolves relative to the android/ directory.
        create("localDebug") {
            storeFile     = rootProject.file("debug.keystore")
            storePassword = "android"
            keyAlias      = "androiddebugkey"
            keyPassword   = "android"
        }
    }

    defaultConfig {
        applicationId = "com.example.laststats_mobile"
        minSdk        = flutter.minSdkVersion
        targetSdk     = flutter.targetSdkVersion
        versionCode   = flutter.versionCode
        versionName   = flutter.versionName
    }

    buildTypes {
        // Both debug and release use the same committed keystore,
        // so every APK produced (locally or on CI) has an identical signature.
        debug {
            signingConfig = signingConfigs.getByName("localDebug")
        }
        release {
            signingConfig = signingConfigs.getByName("localDebug")
            isShrinkResources = false
            isMinifyEnabled   = false
        }
    }
}

dependencies {
    // Required for flutter_local_notifications on API < 26
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}