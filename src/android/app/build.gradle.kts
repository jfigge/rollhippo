import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key, if this machine has been given one.
//
// `key.properties` is gitignored and holds four lines — storeFile,
// storePassword, keyAlias, keyPassword. Together with the .jks it names they
// are the whole of what a new machine needs before it can build something Play
// will accept, which is the same bargain `release.env` and `keys/` strike for
// App Store Connect.
//
// It is deliberately optional. A checkout without it still builds `--release`,
// signed with the debug key Gradle generates on the spot — which is what CI
// does on every push and must keep doing, because handing a runner a real
// signing key to prove that AOT still compiles would be paying a genuine
// secret for nothing. See the `release` build type below for the fallback, and
// `.github/workflows/ci.yml` for what that artefact is and is not.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasUploadKey = keystorePropertiesFile.exists()
if (hasUploadKey) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.rollhippo.rollhippo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Frozen, and not by choice — Play ties a listing to its applicationId
        // at the first upload and there is no changing it afterwards, short of
        // publishing a second app and asking everybody to reinstall. It matches
        // PRODUCT_BUNDLE_IDENTIFIER in ios/Runner.xcodeproj on purpose, so the
        // two stores name the same app the same thing.
        applicationId = "com.rollhippo.rollhippo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Both come from the `version:` line in pubspec.yaml — 1.0.0+2 is
        // versionName 1.0.0 and versionCode 2. Play refuses a versionCode it
        // has already seen, exactly as Connect refuses a build number, so a
        // second upload means bumping the +N there and rebuilding.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Declared only when there is a key to put in it. An empty signingConfig
        // is not harmless: Gradle would resolve `getByName("release")` and then
        // fail at the signing task with a null store, which is a worse error
        // and arrives later than this file simply not offering one.
        if (hasUploadKey) {
            create("release") {
                // Resolved against `android/` rather than `android/app/`, so the
                // path in key.properties reads from the directory a person
                // editing it is thinking of. An absolute path works too, and is
                // what `make keystore` writes.
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The upload key when this machine has one, the debug key when it
            // does not. Play rejects a debug-signed upload outright, so the
            // fallback can never accidentally ship — the worst it does is
            // produce an APK that only sideloads, which is precisely what CI
            // wants and what `make android` has always made.
            //
            // Note "upload" rather than "signing". Play holds the real app
            // signing key itself under Play App Signing, re-signs every bundle
            // with it, and treats this one only as proof of who uploaded. That
            // is the one meaningful difference from Apple: losing this key is
            // recoverable — Google resets it on request — where losing an Apple
            // Distribution certificate is not.
            signingConfig =
                if (hasUploadKey) {
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
