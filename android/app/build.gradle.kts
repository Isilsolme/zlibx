import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // Built-in Kotlin: no longer explicitly apply kotlin-android.
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load android/key.properties if present. Absent on fresh clones — release
// builds then FAIL loudly instead of silently falling back to the debug
// signing config (a debug-signed "release" must never be distributed).
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) load(FileInputStream(file))
}

android {
    namespace = "com.open_library.app"
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.open_library.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Android only, 64-bit only: ship arm64-v8a and nothing else.
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                val candidate = file(storeFilePath)
                if (candidate.exists()) {
                    storeFile = candidate
                    storePassword = keystoreProperties["storePassword"] as String?
                    keyAlias = keystoreProperties["keyAlias"] as String?
                    keyPassword = keystoreProperties["keyPassword"] as String?
                }
            }
        }
    }

    buildTypes {
        release {
            // Release signing requires key.properties + keystore. Refuse to
            // build a release with the debug key: fail here, loudly.
            // Never the debug key. A missing keystore is rejected in the
            // taskGraph check below, so debug builds / tests still configure.
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { t ->
        val n = t.name
        n.contains("Release") &&
            (n.startsWith("assemble") || n.startsWith("bundle") ||
                n.startsWith("package") || n.startsWith("validateSigning"))
    }
    if (wantsRelease && android.signingConfigs.getByName("release").storeFile == null) {
        throw GradleException(
            "Release signing requires android/key.properties with a valid keystore; " +
                "refusing to sign a release build with the debug key."
        )
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
