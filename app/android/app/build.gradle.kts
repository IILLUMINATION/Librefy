import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load the Play Store upload keystore credentials from a properties file
// that lives outside source control (see /.gitignore — *.jks and
// app/android/key.properties are both ignored).
//
// If the file is missing we fall through to debug signing so dev builds
// keep working on a fresh clone; release builds without the file will
// still produce an AAB but it'll be signed with the debug key, which
// Play Console will refuse to upload.
val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {
    namespace = "com.librefy.librefy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // applicationId is what Play Console keys on; changing it after
        // first publish is impossible, so set it once and leave it.
        // `namespace` stays at com.librefy.librefy because that's where
        // MainActivity (Kotlin) lives — moving the Kotlin package would
        // be a much bigger churn for no user-visible benefit.
        applicationId = "com.iilluminat.librefy"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreProps.isNotEmpty()) {
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
                storeFile = keystoreProps["storeFile"]?.let { rootProject.file(it as String) }
                storePassword = keystoreProps["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the upload key when key.properties is present;
            // otherwise debug-sign so `flutter run --release` works
            // on a fresh clone without secrets.
            signingConfig = if (keystoreProps.isNotEmpty()) {
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
