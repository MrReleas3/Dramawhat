plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.vad_app"
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "version"
    productFlavors {
        create("personal") {
            dimension = "version"
            applicationId = "com.dramawhat.app.personal"
            resValue("string", "app_name", "Dramawhat Personal")
        }
        create("production") {
            dimension = "version"
            applicationId = "com.dramawhat.app"
            resValue("string", "app_name", "Dramawhat")
        }
        create("qa") {
            dimension = "version"
            applicationId = "com.dramawhat.app.testing"
            resValue("string", "app_name", "Dramawhat Testing")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        jniLibs {
            excludes += setOf(
                "lib/x86_64/**",
                "lib/x86/**",
                "lib/armeabi-v7a/**",
                "lib/armeabi/**"
            )
        }
        resources {
            excludes += setOf(
                "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
                "META-INF/NOTICE.md",
                "META-INF/LICENSE.md",
                "META-INF/NOTICE",
                "META-INF/LICENSE",
                "META-INF/*.kotlin_module",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
