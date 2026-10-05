# 01 Version numbers

## Two numbers, two audiences

Every Flutter build carries two values. In `pubspec.yaml` they are written together as `version: 1.4.2+57`.

| Flutter | Flag | Android | iOS | Who reads it |
|---|---|---|---|---|
| build name (`1.4.2`) | `--build-name` | `versionName` | `CFBundleShortVersionString` | People: store listing, About screen |
| build number (`57`) | `--build-number` | `versionCode` | `CFBundleVersion` | Machines: install and upload checks |

The flags override `pubspec.yaml`. `tool/build.sh` always passes both, so the `version:` line in `pubspec.yaml` is never used for a release build. Leave it in place: `flutter run` still reads it.

Only the build number decides whether an install or upload is accepted. The build name is a label.

## Rules enforced outside your build

None of these rules can be detected by `flutter build`. A build that breaks them succeeds, and the failure appears later on a device or in a store console.

### Android devices

| Install over an existing app with | Result |
|---|---|
| higher `versionCode` | Installs as an update |
| same `versionCode` | Installs (reinstall). Sideloading and `adb install -r` accept it |
| lower `versionCode` | Refused. `adb` reports `INSTALL_FAILED_VERSION_DOWNGRADE`; the on-device installer shows only "App not installed" |
| different signing key | Refused: `INSTALL_FAILED_UPDATE_INCOMPATIBLE` |

The device compares codes per **application id**. Two tiers with different application ids are two apps with two separate code lines.

### Google Play

- `versionCode` is an integer from 1 to **2100000000**.
- Each upload needs a code Play has not accepted before for that package. Re-uploading a code fails with "Version code N has already been used".
- When an app moves to Play from another codebase (for example a native rewrite), the new codebase must continue from the highest code the old one used.

### Apple App Store and TestFlight

- `CFBundleShortVersionString`: up to three period-separated integers, for example `1.4.2`.
- `CFBundleVersion`: one to three period-separated integers. App Store Connect rejects an upload whose build number it has already seen for the same version string.
- Flutter writes the build number into the Xcode setting `FLUTTER_BUILD_NUMBER`, which backs `CFBundleVersion`.

### Consequence for the build script

A plain integer that only goes up, per application id, satisfies all three. The template enforces:

- versionName matches `MAJOR.MINOR.PATCH` (accepted by both stores),
- versionCode is an integer, never below the highest the tier has used, never above 2100000000,
- on store tiers, versionCode is never reused unless `--reuse-code` says the previous build was never uploaded.

## Choosing when to change each number

| Change | build name | build number |
|---|---|---|
| New release with user-visible changes | `--patch`, `--minor` or `--major` | Taken automatically (these imply `--bump`) |
| Same release, new build for testers or a store resubmission | Keep | `--bump` |
| Same code rebuilt for a local test device, never uploaded | Keep | Keep (rebuild in place) |
| Rebuild of a past release for investigation | Keep | Keep, with `PIN_DEPS=1` and the old commit checked out; do not upload |

## Showing the version in the app

Read it at runtime from the platform, not from a Dart constant, so the screen shows what the store and device see:

```dart
import 'package:package_info_plus/package_info_plus.dart';

final info = await PackageInfo.fromPlatform();
final label = '${info.version} (${info.buildNumber})'; // "1.4.2 (57)"
```
