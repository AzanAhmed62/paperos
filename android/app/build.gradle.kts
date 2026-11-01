import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin
    // Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Production signing is supplied by the person who owns the key. Nothing is
// generated or checked in. Supported sources, in order:
//   1. -Ppaperos.keyProperties=C:\secure\paperos-release.properties
//   2. PAPEROS_KEY_PROPERTIES environment variable
//   3. android/key.properties (traditional Flutter location, git-ignored)
// Individual values may also come from Gradle properties or PAPEROS_* env vars.
val keystoreProperties = Properties()
val keystoreCandidates = listOfNotNull(
    (project.findProperty("paperos.keyProperties") as String?)?.let { file(it) },
    System.getenv("PAPEROS_KEY_PROPERTIES")?.let { file(it) },
    rootProject.file("key.properties"),
)
val keystorePropertiesFile = keystoreCandidates.firstOrNull { it.isFile }
keystorePropertiesFile?.let { source ->
    FileInputStream(source).use { keystoreProperties.load(it) }
}

fun signingValue(property: String, environment: String): String? {
    val fromGradle = (project.findProperty(property) as String?)?.trim()
    if (!fromGradle.isNullOrEmpty()) return fromGradle
    val fromEnvironment = System.getenv(environment)?.trim()
    if (!fromEnvironment.isNullOrEmpty()) return fromEnvironment
    val fromFile = keystoreProperties.getProperty(property)?.trim()
        ?: keystoreProperties.getProperty(property.removePrefix("paperos."))?.trim()
    return if (fromFile.isNullOrEmpty()) null else fromFile
}

val releaseStoreFile = signingValue("paperos.storeFile", "PAPEROS_STORE_FILE")
val releaseStorePassword =
    signingValue("paperos.storePassword", "PAPEROS_STORE_PASSWORD")
val releaseKeyAlias = signingValue("paperos.keyAlias", "PAPEROS_KEY_ALIAS")
val releaseKeyPassword =
    signingValue("paperos.keyPassword", "PAPEROS_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
// An explicit, non-distributable escape hatch for artifact-composition
// analysis on machines without production credentials. It never produces an
// installable release by accident: the file is plainly named "-unsigned".
val allowUnsignedRelease =
    (project.findProperty("paperos.allowUnsignedRelease") as String?)
        ?.equals("true", ignoreCase = true) == true

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

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Never fall back to the debug key. Without credentials the release
            // tasks fail below, unless an explicit unsigned-analysis build was
            // requested.
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
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

tasks.configureEach {
    if (name == "assembleRelease" || name == "bundleRelease") {
        doFirst {
            if (!hasReleaseSigning && !allowUnsignedRelease) {
                throw GradleException(
                    "PaperOS release signing is not configured. Provide " +
                        "android/key.properties or PAPEROS_* credentials. " +
                        "For a non-installable size-analysis build only, pass " +
                        "-Ppaperos.allowUnsignedRelease=true.",
                )
            }
            if (!hasReleaseSigning) {
                logger.warn(
                    "WARNING: building an UNSIGNED release for analysis only. " +
                        "This artifact is not installable and must not be distributed.",
                )
            }
        }
    }
}

flutter {
    source = "../.."
}
