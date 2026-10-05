# 09 Adoption checklist

For an existing Flutter project. Work through the steps in order.

## Files

- [ ] Copy `template/tool/` to `<app>/tool/` and run `chmod +x tool/*.sh` (`build.sh`, `sync-git-dep.sh`, `ledger.sh`).
- [ ] Copy `template/config/tiers/` to `<app>/config/tiers/`. One file per tier, each with `APP_TIER` equal to its file name.
- [ ] Copy `template/lib/core/build_env.dart` and call `BuildEnv.verify()` as the first line of `main()`.
- [ ] Append `template/.gitignore` to the app's `.gitignore`.

## Settings in `tool/build.sh`

- [ ] `APP_SLUG`: short lowercase name for artifact files.
- [ ] `DEFAULT_TIER`: a non-store tier.
- [ ] `STORE_TIERS`: every tier that uploads to Play or App Store Connect.
- [ ] `STORE_BRANCHES`: the branch production is built from (`main`), or empty to allow any.
- [ ] `MIN_TARGET_SDK`: Google Play's current target API requirement ([10](10-store-gates.md)).
- [ ] `TIER_MECHANISM`: `flavor`, or `property` for Android-only apps without flavors.
- [ ] `TRACKED_GIT_DEP`: the package name of a branch-tracked git dependency, or empty.
- [ ] `OBFUSCATE`: `1` unless you have a reason not to.

## Tiers

- [ ] One Android product flavor per tier, named like the config files, each with its own `applicationId`.
- [ ] `android:label="@string/app_name"` in `AndroidManifest.xml`; icons in `android/app/src/<flavor>/res/`.
- [ ] iOS (if shipped): one scheme per tier with the same name, `Release-<tier>` build configurations, a bundle identifier per configuration.
- [ ] Move every per-tier value out of Dart code and into `config/tiers/*.json`.
- [ ] Remove secrets from Dart code and config files.

## Version ledger

- [ ] For each tier, find the current version:
  - on a store: the highest versionCode in Play Console or the highest build number in App Store Connect,
  - not on a store: the code on testers' devices, or `pubspec.yaml`'s current value.
- [ ] Write one opening row per tier in `tool/versions.tsv`, replacing the two example rows.
- [ ] Leave the `version:` line in `pubspec.yaml`. It is used by `flutter run` only.

## First builds

- [ ] `tool/build.sh apk --release --dry-run`: check name, code, flavor and config path.
- [ ] `tool/build.sh appbundle --release --tier prod --bump --dry-run`.
- [ ] Build staging with `--bump`. Install it over the current staging app on a device; it must update, not fail.
- [ ] Open the app and confirm the About screen shows the new version and the staging backend is used.
- [ ] Commit `tool/versions.tsv` and `pubspec.lock`.

## Negative tests

Each must fail with a clear message:

- [ ] `tool/build.sh apk --release --build-number=1`
- [ ] `tool/build.sh appbundle --release --tier prod` (no `--bump`, store tier)
- [ ] Edit `config/tiers/prod.json` to say `"APP_TIER": "staging"`, then build prod.
- [ ] `flutter build apk --flavor prod --release` with no config, then launch it: `BuildEnv.verify()` must throw.
- [ ] From a feature branch: `tool/build.sh appbundle --release --tier prod --bump --dry-run` must print `would refuse`.
- [ ] Set `versionCode = 1` in `android/app/build.gradle.kts`, build staging with `--bump`: step 11 must refuse (needs `aapt2`). Revert the line.
- [ ] `tool/ledger.sh which dist/<last file>` must print the row just written.

## Team

- [ ] Document in the README: "release builds go through `tool/build.sh` only".
- [ ] Add the CI workflow if builds are made in CI, and remove any other release build path.
- [ ] Decide who is allowed to build store tiers, and from which branch.
