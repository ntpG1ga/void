plugins {
    id("com.android.application")
}

android {
    namespace = "com.metascript.voidsample"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.metascript.voidsample"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
        ndk { abiFilters += "arm64-v8a" }
    }

    // The engine's assets/ (font.ttf, ...) ride in the APK; VoidNative.prepare extracts them.
    sourceSets["main"].assets.srcDir("../../assets")
}
