# 10 Store gates

The rules in [01](01-version-numbers.md) do not change. The rules below change every year, and a build that met them last year is rejected at upload this year. Each one is checked by the store, after the build, so `flutter build` succeeds either way.

Dates checked on 2026-10-05. Re-check the linked pages before relying on them.

## Google Play: target API level

| From | New apps and updates must target |
|---|---|
| 31 August 2025 | Android 15 (API 35) |
| 31 August 2026 | Android 16 (API 36). Extension to 1 November 2026 on request in Play Console |

Wear OS, Android Automotive, Android TV and Android XR have lower floors. An existing app that targets less than API 35 stops being offered to new users on newer Android versions.

The requirement moves each August, roughly one API level per year.

**Guard in `build.sh`:** step 11 reads `targetSdkVersion` out of the artifact and refuses a store-tier build below `MIN_TARGET_SDK`. Raise that setting when Google announces the next level. The value read is also recorded in the ledger's `sdk` column, so the ledger shows which builds would now be rejected.

Flutter sets `targetSdk = flutter.targetSdkVersion` in `android/app/build.gradle.kts`, which follows the Flutter SDK. Upgrading Flutter usually raises it. A hard-coded `targetSdk = 34` in the Gradle file stays at 34 until someone edits it.

## Google Play: 16 KB memory pages

Since 1 November 2025, every update that targets Android 15 or higher must support 16 KB memory page sizes. The extension that could be requested in Play Console ended on 31 May 2026.

Current Flutter SDKs build an engine that supports 16 KB pages; reports differ on the first version that did, so use a 2026 release. The usual failure is a plugin that ships its own native `.so` library built for 4 KB pages: FFmpeg wrappers, image, audio, PDF and database plugins.

Check an APK before uploading the bundle:

```bash
zipalign -c -P 16 -v 4 dist/myapp-staging-v1.4.2+57.apk
```

`Verification successful` means every uncompressed `.so` is aligned to 16 KB inside the archive. It does not check the ELF segment alignment inside each library. Play Console's App bundle explorer reports both, per uploaded bundle. Android Studio's APK Analyzer also flags misaligned libraries.

`build.sh` does not run this check. It needs `zipalign` from the Android build tools, it covers only APKs, and the ELF part needs another tool. Run it once after adding or upgrading a plugin with native code.

## Apple App Store: Xcode and SDK

Since 28 April 2026, uploads to App Store Connect must be built with Xcode 26 or later, against the iOS 26 SDK. The upload is rejected before review.

This limits the SDK the app is compiled against, not the iOS versions it runs on. The deployment target can stay lower.

The requirement moves each spring, after the autumn Xcode release. Pin the Xcode version on the build machine the same way the Flutter version is pinned (see [07](07-ci.md#pin-the-toolchain)).

## Google Play: versionCode limit

`versionCode` stays capped at 2100000000. `build.sh` enforces this with `MAX_CODE`. It matters only for timestamp-based or ABI-multiplied numbering schemes ([03](03-ledger.md#numbering-strategies-compared)).

## Keeping up

Each gate above has an announcement page, listed in [sources](sources.md). When one changes:

1. Update the setting in `tool/build.sh` if there is one (`MIN_TARGET_SDK`).
2. Update this doc's table and the date at the top.
3. Build a staging release with `--bump` and confirm the new value in the ledger's `sdk` column.
