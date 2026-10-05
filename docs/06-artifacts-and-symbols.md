# 06 Artifacts and symbols

## Where Flutter writes release outputs

| Target | Path (flavor `prod`) |
|---|---|
| `apk` | `build/app/outputs/flutter-apk/app-prod-release.apk` |
| `appbundle` | `build/app/outputs/bundle/prodRelease/app-prod-release.aab` |
| `ipa` | `build/ios/ipa/<name>.ipa` |

Gradle also writes the APK to `build/app/outputs/apk/prod/release/`. `build.sh` searches only the three directories above, by modification time, so each artifact is filed once.

## Naming

```
<APP_SLUG>-<tier>-v<name>+<code>.<ext>
myapp-prod-v1.4.2+58.aab
myapp-staging-v1.4.2+57.apk
```

- Tier first: staging and production files never share a name, so neither overwrites the other.
- Name and code: two builds share a file name only if they share both, which only happens on a rebuild in place.
- If one build produces several files, each gets its original base name as a suffix.

Copies go to `OUT_DIR` (default `dist/`, ignored by git). Set `OUT_DIR=~/Builds` to collect builds from several projects in one place.

## Checking the artifact

Before a file is filed, `build.sh` opens it and reads `versionCode` (and `targetSdkVersion`) back out, so a hard-coded value in Gradle or Xcode cannot ship under the ledger's number ([05, step 11](05-anatomy.md#11-read-the-version-back)). The same checks by hand:

```bash
aapt2 dump badging dist/myapp-staging-v1.4.2+57.apk | head -1
bundletool dump manifest --bundle=dist/myapp-prod-v1.4.2+58.aab --xpath=/manifest/@android:versionCode
```

The ledger keeps each filed file's size and SHA-256 prefix. `tool/ledger.sh which <file>` uses the hash to name the build behind any copy of a file, whatever it has been renamed to ([03](03-ledger.md#which-build-is-this-file)).

## App bundle or APK

| Use | Build |
|---|---|
| Upload to Google Play | `appbundle`. Play generates per-device APKs and signs them with the app signing key |
| Install directly on a test device | `apk` (universal: contains every ABI) |
| Upload to App Store Connect / TestFlight | `ipa` |

## `--split-per-abi` and version codes

`flutter build apk --split-per-abi` produces one APK per CPU architecture. Flutter's Gradle plugin then **overrides each APK's versionCode**:

```
versionCode = abiCode * 1000 + buildNumber
abiCode: armeabi-v7a = 1, arm64-v8a = 2, x86_64 = 4   (3 was x86, removed)
```

With `--build-number=7`, the arm64 APK has code 2007. A device that installs it then refuses every universal APK and every later split build numbered below 2007. The ledger records 7, so the next `--bump` produces 8, which that device refuses.

`build.sh` refuses `--split-per-abi`. For smaller downloads on Play, the app bundle already delivers per-ABI APKs. If you must distribute split APKs outside Play, record the effective codes. A split build at code N puts up to 4000 + N on devices, so every later build of that tier needs a code above 4000 + N. Add a ledger row with that code by hand before the next `--bump`.

## Obfuscation and debug symbols

With `OBFUSCATE=1` the script adds:

```bash
--obfuscate --split-debug-info=$OUT_DIR/symbols/<APP_SLUG>-<tier>-v<name>+<code>
```

- `--obfuscate` renames Dart symbols in the release binary, so stack traces from production show meaningless names.
- `--split-debug-info` moves debug information out of the binary into `.symbols` files in that directory, one per architecture, and makes the binary smaller.
- Both work only in release and profile builds.

Stack traces from that build can be decoded only with **those exact symbol files**. Symbols from another build, even of the same code, do not match. The directory name includes tier, name and code so the files cannot be confused.

Obfuscation does not hide string constants, so values from `--dart-define` stay readable. It is not a way to protect secrets.

### Decoding a stack trace locally

```bash
flutter symbolize -i crash.txt -d dist/symbols/myapp-prod-v1.4.2+58/app.android-arm64.symbols
```

### Uploading to Firebase Crashlytics

Upload before release. Crashes reported before the upload are not decoded retroactively.

```bash
firebase crashlytics:symbols:upload \
  --app=<FIREBASE_APP_ID> \
  dist/symbols/myapp-prod-v1.4.2+58
```

`FIREBASE_APP_ID` is the Firebase app id (`1:123:android:abc...`), not the package name. Each tier is a separate Firebase app.

For iOS, Crashlytics also needs the dSYM files from the Xcode archive. Its build phase uploads them when configured.

### Keeping symbols

Keep each production build's symbol directory for as long as that version may be installed on a device. Store them with the artifacts (CI artifact storage, an object store bucket), not only on one laptop.
