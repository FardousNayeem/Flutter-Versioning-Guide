# Sources

## Official documentation

- Flutter, Set up flavors for Android: https://docs.flutter.dev/deployment/flavors
- Flutter, Set up flavors for iOS and macOS: https://docs.flutter.dev/deployment/flavors-ios
- Flutter, Build and release an iOS app (build name and number mapping): https://docs.flutter.dev/deployment/ios
- Flutter, Package dependency management (`pubspec.lock`, upgrades): https://docs.flutter.dev/packages-and-plugins/dependency-management
- Android Developers, Version your app (versionCode rules and the 2100000000 limit): https://developer.android.com/studio/publish/versioning
- Android Developers, Sign your app (upload key, Play App Signing): https://developer.android.com/studio/publish/app-signing
- Android Developers, Build multiple APKs (ABI splits and version codes): https://developer.android.com/build/configure-apk-splits
- Apple, Xcode help on version and build numbers: https://help.apple.com/xcode/mac/current/en.lproj/devc092854f5.html
- Firebase, Get readable crash reports for Flutter (symbol upload): https://firebase.google.com/docs/crashlytics/flutter/get-deobfuscated-reports
- Android Developers, Meet Google Play's target API level requirement: https://developer.android.com/google/play/requirements/target-sdk
- Play Console Help, Target API level requirements for Google Play apps: https://support.google.com/googleplay/android-developer/answer/11926878
- Android Developers, Support 16 KB page sizes: https://developer.android.com/guide/practices/page-sizes
- Android Developers, zipalign (`-c -P 16` alignment check): https://developer.android.com/tools/zipalign
- Apple, Upcoming requirements (minimum Xcode and SDK for uploads): https://developer.apple.com/news/upcoming-requirements/
- bundletool, `dump manifest --xpath`: https://developer.android.com/tools/bundletool
- Flutter, Measuring your app's size (`--analyze-size`): https://docs.flutter.dev/perf/app-size
- Codemagic, Automatic build versioning (CI build number strategies): https://docs.codemagic.io/knowledge-codemagic/build-versioning/
- Codemagic, Importing variables from JSON (`--dart-define-from-file`): https://docs.codemagic.io/knowledge-others/dart-define-from-file-secrets/

## Flutter SDK source (verified against Flutter 3.44.7)

- `packages/flutter/lib/src/services/flavor.dart`: `appFlavor`, read from the `FLUTTER_APP_FLAVOR` define, `null` when no flavor is given.
- `packages/flutter_tools/gradle/src/main/kotlin/FlutterPluginConstants.kt`: `ABI_VERSION` map (arm32 1, arm64 2, x86_64 4; 3 reserved for removed x86).
- `packages/flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt`: `versionCodeOverride = abiVersionCode * 1000 + versionCode` for split APKs.
- `packages/flutter_tools/lib/src/runner/flutter_command.dart`, `extractDartDefines`: values from `--dart-define-from-file` are added first, then `--dart-define` values.
- `packages/flutter_tools/lib/src/build_info.dart`: defines passed to Gradle as `-Pdart-defines=<base64 list>`.
- `packages/flutter_tools/lib/src/ios/xcode_build_settings.dart`: build number written to `FLUTTER_BUILD_NUMBER`, which backs `CFBundleVersion`.

## Other references

- Code With Andrea, How to store API keys in Flutter: `--dart-define` vs `.env` files: https://www.codewithandrea.com/articles/flutter-api-keys-dart-define-env-files/
- .NET for Android build message XA0004, which quotes Google Play's versionCode limit of 2100000000: https://learn.microsoft.com/en-us/dotnet/android/messages/xa0004
