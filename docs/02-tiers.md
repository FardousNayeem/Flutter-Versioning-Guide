# 02 Tiers

A tier is one deployed copy of the app: `staging` for testers, `prod` for the public. Add more (`qa`, `demo`) the same way.

Each tier differs in:

| Property | Where it is set |
|---|---|
| Application id / bundle identifier | Android flavor / iOS build configuration |
| Launcher label and icon | Android flavor resources / iOS build settings and asset catalog |
| Backend URLs and other compile-time values | `config/tiers/<tier>.json` |
| Version series | Rows for that tier in `tool/versions.tsv` |

`tool/build.sh --tier <name>` selects all four together. No file is edited between builds, so nothing has to be reverted afterwards.

## Why separate application ids

If staging and production share an id, they share one install slot and one versionCode line. A tester cannot keep both installed, and a staging build stamped with a high code blocks the next production update on that device. Separate ids give each tier its own install and its own numbers on devices and in Play.

## Choosing a mechanism

### Flavors (recommended)

Flutter's `--flavor` maps to Android product flavors and to Xcode schemes. It is the only mechanism that covers iOS, and Flutter exposes the active flavor to Dart as `appFlavor`.

Android, in `android/app/build.gradle.kts`:

```kotlin
android {
    flavorDimensions += "tier"
    productFlavors {
        create("staging") {
            dimension = "tier"
            applicationId = "com.example.myapp.staging"
            resValue("string", "app_name", "MyApp Staging")
        }
        create("prod") {
            dimension = "tier"
            applicationId = "com.example.myapp"
            resValue("string", "app_name", "MyApp")
        }
    }
}
```

- Label: set `android:label="@string/app_name"` in `AndroidManifest.xml`.
- Icons: put each tier's launcher icons in `android/app/src/<flavor>/res/mipmap-*/`. Gradle merges the flavor's source set over `main` automatically.

iOS: create one scheme per tier, named exactly like the Android flavor, with build configurations `Debug-<tier>`, `Release-<tier>` and `Profile-<tier>`. Set `PRODUCT_BUNDLE_IDENTIFIER` and a user-defined `APP_DISPLAY_NAME` per configuration. The official walkthrough is linked in [sources](sources.md).

Set `TIER_MECHANISM=flavor` in `tool/build.sh`.

### Gradle property (Android only)

For an Android-only app that does not want flavors, the script can pass `-Ptier=<name>` instead, and Gradle reads it:

```kotlin
val isProd = (project.findProperty("tier") as? String) == "prod"

android {
    defaultConfig {
        applicationId = if (isProd) "com.example.myapp" else "com.example.myapp.staging"
        manifestPlaceholders["appLabel"] = if (isProd) "MyApp" else "MyApp Staging"
    }
    sourceSets {
        getByName("main") {
            res.srcDir(if (isProd) "icons/prod" else "icons/staging")
        }
    }
}
```

A plain `flutter build apk` with no property builds staging, which is the safe default. Set `TIER_MECHANISM=property`. The script refuses `ipa` in this mode.

## Compile-time config

Each tier has one JSON file, passed with `--dart-define-from-file`:

```json
{
  "APP_TIER": "prod",
  "API_BASE_URL": "https://api.example.com"
}
```

Read the values as constants:

```dart
static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');
```

Rules:

- **`APP_TIER` is required** and must equal the file's tier name. It is the key every pairing check uses.
- **Nothing secret goes in these files.** Values passed with `--dart-define` or `--dart-define-from-file` are compiled into the binary and can be extracted from a release APK in minutes, with or without `--obfuscate`. URLs, feature switches and public client ids are fine. Private keys belong on a server.
- Commit the files. They are part of what a build is.
- For `flutter run`, pass the same file: `flutter run --flavor staging --dart-define-from-file=config/tiers/staging.json`. Put it in your IDE launch configuration.

## Pairing checks: three layers

A production application id with the staging backend (or the reverse) installs, launches and works. It just writes to the wrong database. Nothing fails until someone notices the data. Three checks close this, each at the point that can see both values.

| Layer | What it compares | Catches |
|---|---|---|
| `build.sh`, step 2 | `--tier` vs `APP_TIER` in the chosen config file | A tier file copied from another tier and not edited |
| `BuildEnv.verify()` at app start | `appFlavor` vs `APP_TIER` | A manual `flutter build --flavor prod` with the staging config, or no config at all |
| Gradle (optional, property mode) | application id vs URL host in `-Pdart-defines` | Same as above, at build time instead of first launch |

### Startup check

```dart
import 'package:flutter/services.dart' show appFlavor;

abstract final class BuildEnv {
  static const String tier = String.fromEnvironment('APP_TIER');

  static void verify() {
    if (tier.isEmpty) {
      throw StateError('APP_TIER is not set. Build with tool/build.sh.');
    }
    if (appFlavor != null && appFlavor != tier) {
      throw StateError('Flavor "$appFlavor" was built with the "$tier" config.');
    }
  }
}

void main() {
  BuildEnv.verify();
  runApp(const App());
}
```

The full file is [`template/lib/core/build_env.dart`](../template/lib/core/build_env.dart). A crossed build now crashes on its first launch on a tester's device instead of running against the wrong backend.

### Gradle check (property mode)

Flutter passes all compile-time defines to Gradle as the project property `dart-defines`: a comma-separated list of base64-encoded `KEY=VALUE` strings. Values from `--dart-define-from-file` are included, followed by any `--dart-define` flags, so the last occurrence of a key wins. Gradle can therefore compare the application id with the URL before compiling:

```kotlin
import java.net.URI
import java.util.Base64

fun dartDefine(key: String): String? =
    (project.findProperty("dart-defines") as? String)
        ?.split(",")
        ?.mapNotNull { runCatching { String(Base64.getDecoder().decode(it.trim())) }.getOrNull() }
        ?.lastOrNull { it.startsWith("$key=") }
        ?.substringAfter("=")

fun verifyPairing(applicationId: String) {
    val url = dartDefine("API_BASE_URL")
        ?: throw GradleException("API_BASE_URL is not defined; build with tool/build.sh")
    val prodApp = applicationId == "com.example.myapp"
    val prodApi = URI(url).host == "api.example.com"
    if (prodApp != prodApi) {
        throw GradleException("Environment mismatch: $applicationId is pointed at $url")
    }
}
```

Call `verifyPairing(applicationId!!)` at the end of `defaultConfig`. With flavors, Gradle configures every flavor in each run, so a check in `defaultConfig` cannot tell which flavor is being built. Use the startup check there instead.

If the app talks to more than one backend, check each pair. Two backends are two pairs, and either one crossed is the same mistake.
