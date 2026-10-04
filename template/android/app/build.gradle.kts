// Excerpt: the parts of android/app/build.gradle.kts that tool/build.sh relies
// on. Merge into your own file; do not replace it.

android {
    defaultConfig {
        // Filled from --build-name / --build-number. Never hard-code these:
        // tool/build.sh owns the numbers and the ledger records them.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One flavor per tier. The names must match config/tiers/<name>.json and
    // the --tier values passed to tool/build.sh.
    flavorDimensions += "tier"
    productFlavors {
        create("staging") {
            dimension = "tier"
            // A separate application id makes staging a separate install with
            // its own versionCode line, on devices and on Play.
            applicationId = "com.example.myapp.staging"
            resValue("string", "app_name", "MyApp Staging")
        }
        create("prod") {
            dimension = "tier"
            applicationId = "com.example.myapp"
            resValue("string", "app_name", "MyApp")
        }
    }
    // Launcher label: android:label="@string/app_name" in AndroidManifest.xml.
    // Launcher icons: android/app/src/staging/res/mipmap-*/ and
    // android/app/src/prod/res/mipmap-*/. Gradle picks the flavor's source set
    // on its own; nothing to swap or revert per build.

    buildTypes {
        release {
            // Fail at configure time rather than fall back to the debug key: a
            // debug-signed release cannot update an existing install.
            signingConfig = signingConfigs.findByName("release")
                ?: throw GradleException("android/key.properties is missing; release signing is not configured.")
        }
    }
}
