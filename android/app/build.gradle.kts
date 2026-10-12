import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseProperties = Properties()
val releasePropertiesFile = rootProject.file("key.properties")
if (releasePropertiesFile.exists()) {
    releasePropertiesFile.inputStream().use { releaseProperties.load(it) }
}
fun signingValue(property: String, environment: String): String? =
    System.getenv(environment)?.takeIf { it.isNotBlank() }
        ?: releaseProperties.getProperty(property)?.takeIf { it.isNotBlank() }
val releaseStore = signingValue("storeFile", "LEDGY_KEYSTORE_PATH")
val releaseAlias = signingValue("keyAlias", "LEDGY_KEY_ALIAS")
val releaseStorePassword = signingValue("storePassword", "LEDGY_STORE_PASSWORD")
val releaseKeyPassword = signingValue("keyPassword", "LEDGY_KEY_PASSWORD")

android {
    namespace = "com.ledgy.ledgy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ledgy.ledgy2"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStore?.let { rootProject.file(it) }
            keyAlias = releaseAlias
            storePassword = releaseStorePassword
            keyPassword = releaseKeyPassword
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// Missing credentials must fail closed, while debug/analyze/test stay usable.
tasks.register("verifyReleaseSigning") {
    doLast {
        check(listOf(releaseStore, releaseAlias, releaseStorePassword, releaseKeyPassword)
            .all { !it.isNullOrBlank() }) {
            "Signing Ledgy belum disiapkan. Jalankan tool/create_keystore.ps1 atau isi secret CI."
        }
        check(rootProject.file(releaseStore!!).isFile) { "Keystore rilis tidak ditemukan." }
    }
}
tasks.configureEach {
    if (name == "preReleaseBuild") dependsOn("verifyReleaseSigning")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
