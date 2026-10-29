plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin
    // Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.paperos.app"
    compileSdk = flutter.compileSdkVersion
    // A transitive native package (jni) requires Flutter's NDK. Pin it so the
    // build does not silently fall back to an older AGP default.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "dev.paperos.app"
        // 24 is the floor: PdfRenderer, RoleManager fallback path and the
        // Flutter embedding all require it, and no current Play Store device
        // is below it.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resourceConfigurations += listOf("en")
    }

    buildTypes {
        release {
            // PaperOS has no signing key configured in this repository. The
            // debug key is used so `flutter build apk --release` produces a
            // runnable artifact; replace before any real distribution.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }
}

flutter {
    source = "../.."
}
