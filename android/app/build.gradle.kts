// cspell:words lazysodium goterl
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material lives in android/key.properties, which is gitignored. Locally
// you create it once (see docs/android-release.md); in CI it is written by
// scripts/android-ci-signing.bash from repository secrets.
//
// Absent, the release build falls back to the Android debug key so `flutter run --release`
// still works for a developer who has no keystore. Such a build can never be published --
// Play rejects the debug key -- so the fallback announces itself rather than producing a
// release-looking artifact that fails only at upload.
val keystoreProperties =
    Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) {
            file.inputStream().use { load(it) }
        }
    }
val releaseStoreFile: String? = keystoreProperties.getProperty("storeFile")

if (releaseStoreFile == null) {
    logger.lifecycle(
        "quark: android/key.properties not found; release builds will use the DEBUG key " +
            "and cannot be uploaded to Play. See docs/android-release.md.",
    )
}

android {
    namespace = "org.autobutler"

    // Pinned rather than taken from flutter.*, so upgrading the Flutter SDK cannot move
    // the SDK levels a published app is compiled and tested against. Play enforces a
    // rolling minimum targetSdk, so raising these stays a deliberate commit.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Matches the iOS bundle ID. Permanent once Play has accepted a build: an
        // applicationId cannot be changed afterwards without publishing a separate
        // listing that shares no installs with this one.
        applicationId = "org.autobutler.quark"
        minSdk = 24
        targetSdk = 36
        // Supplied by --build-name / --build-number; the Makefile derives both from the
        // most recent git tag. See docs/android-release.md.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                // rootProject is android/, so a bare filename sits next to key.properties.
                // An absolute path is passed through unchanged.
                val store = rootProject.file(releaseStoreFile)
                require(store.exists()) {
                    "android/key.properties points storeFile at ${store.absolutePath}, " +
                        "which does not exist. Fix storeFile=, or regenerate the keystore " +
                        "(see docs/android-release.md)."
                }
                storeFile = store
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (releaseStoreFile != null) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// The vault crypto native autofill runs with no Flutter engine (#3597,
// docs/design/native-autofill-vault.md, Decision 1): libsodium, the C library
// the app's Dart links, through lazysodium. @aar turns off transitive
// resolution, so JNA is named here too, at the version lazysodium declares.
dependencies {
    implementation("com.goterl:lazysodium-android:5.2.0@aar")
    implementation("net.java.dev.jna:jna:5.17.0@aar")

    // The JVM unit tests cannot load the Android .so files, so they run the
    // same lazysodium API over lazysodium-java's bundled desktop libsodium,
    // and read the vector file with a real org.json in place of android.jar's
    // stubs.
    testImplementation("junit:junit:4.13.2")
    testImplementation("com.goterl:lazysodium-java:5.2.0")
    testImplementation("org.json:json:20260814")
}

// lazysodium 5.2.0 is Java 21 bytecode; 5.2.0 is the first whose .so files are 16 KB
// aligned, as Play requires. The app is unaffected, since D8 dexes it, but the JVM
// unit tests load it as it is, so they run on a Java 21 toolchain. Gradle finds one
// under /usr/lib/jvm on CI's Ubuntu runners. The vector file the tests read lives
// outside the module, so it is named as an input, or a change to it alone would
// leave the tests up to date.
tasks.withType<Test>().configureEach {
    javaLauncher.set(javaToolchains.launcherFor { languageVersion.set(JavaLanguageVersion.of(21)) })
    inputs.file(rootProject.file("../test/fixtures/vault_vectors.json"))
}
