import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// İmza: android/key.properties (CI'da secret'tan yazılır). Yoksa debug
// anahtarı — cihaza kurulur ama sonraki sürüm üstüne güncellenemez.
val imzaDosyasi = rootProject.file("key.properties")
val imza = Properties().apply { if (imzaDosyasi.exists()) load(FileInputStream(imzaDosyasi)) }

android {
    namespace = "com.bambumpos.personel"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // ota_update (uygulama içi güncelleme) yeni Java API'lerini eski Android'de kullanır.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.bambumpos.personel"
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

    signingConfigs {
        if (imzaDosyasi.exists()) {
            create("surum") {
                storeFile = file(imza.getProperty("storeFile"))
                storePassword = imza.getProperty("storePassword")
                keyAlias = imza.getProperty("keyAlias")
                keyPassword = imza.getProperty("keyPassword")
                storeType = imza.getProperty("storeType") ?: "pkcs12"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (imzaDosyasi.exists()) signingConfigs.getByName("surum") else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
