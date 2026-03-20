plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.noor.noor_ai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.noor.noor_ai"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.clear()
            abiFilters += "arm64-v8a"
        }
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DMNN_AVAILABLE=ON",
                    "-DBUILD_SHARED_LIBS=ON",
                    "-DEIGEN_BUILD_TESTING=OFF",
                    "-DEIGEN_BUILD_BTL=OFF",
                    "-DBUILD_TESTING=OFF",
                    "-DEDGEMIND_ENABLE_SHERPA_MNN_ASR=ON",
                    "-DEDGEMIND_ENABLE_RNNOISE_ASR_DENOISE=OFF"
                )
                targets += listOf("edgemind_core")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../native/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
