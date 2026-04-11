import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

val nativeAbi = "arm64-v8a"
val nativeLibName = "libedgemind_core.so"

fun String.capitalizeAscii(): String = replaceFirstChar {
    if (it.isLowerCase()) it.titlecase() else it.toString()
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.noor.noor_ai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
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
            abiFilters += nativeAbi
        }
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DMNN_AVAILABLE=ON",
                    "-DBUILD_SHARED_LIBS=ON",
                    "-DEDGEMIND_ENABLE_ZVEC=ON",
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

    packaging {
        jniLibs {
            pickFirsts += setOf(
                "lib/$nativeAbi/libc++_shared.so",
                "lib/$nativeAbi/$nativeLibName"
            )
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

afterEvaluate {
    listOf("debug", "profile", "release").forEach { variant ->
        val capitalizedVariant = variant.capitalizeAscii()
        val syncTask = tasks.register("sync${capitalizedVariant}EdgemindCoreJniLib") {
            group = "build"
            description = "Copies the rebuilt $nativeLibName into src/main/jniLibs for $variant."
            dependsOn("externalNativeBuild${capitalizedVariant}")
            doLast {
                val candidateRoots = listOf(
                    layout.buildDirectory.dir("intermediates/cxx/$variant").get().asFile,
                    layout.buildDirectory.dir("intermediates/cmake/$variant").get().asFile,
                    rootProject.layout.buildDirectory.dir("app/intermediates/cxx/$variant").get().asFile,
                    rootProject.layout.buildDirectory.dir("app/intermediates/cmake/$variant").get().asFile,
                ).distinct()

                val matches = candidateRoots
                    .filter { it.exists() }
                    .flatMap { root ->
                        fileTree(root) {
                            include("**/obj/$nativeAbi/$nativeLibName")
                        }.files
                    }

                val newestMatch = matches.maxByOrNull { it.lastModified() }
                    ?: throw GradleException(
                        buildString {
                            append("Could not find rebuilt $nativeLibName for $variant. Looked under: ")
                            append(candidateRoots.joinToString { it.absolutePath })
                        }
                    )

                copy {
                    from(newestMatch)
                    into(layout.projectDirectory.dir("src/main/jniLibs/$nativeAbi"))
                }
            }
        }

        tasks.named("merge${capitalizedVariant}NativeLibs").configure {
            dependsOn(syncTask)
        }

        tasks.named("merge${capitalizedVariant}JniLibFolders").configure {
            dependsOn(syncTask)
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
