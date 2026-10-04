# Flutter Versioning Guide

This is an easy way to maintain versioning of flutter apps as well as tracking build numbers.

How to build release binaries of a Flutter app so that every build:

- carries a version number that a device and a store will accept,
- talks to the backend of the tier it was built for,
- contains the dependency commits it claims to contain,
- leaves a written record of what was built, from which commit, and where the file went.

The guide is built around one script, `tool/build.sh`, and a ledger file, `tool/versions.tsv`. Both are in [`template/`](template/) and work in any Flutter project after editing one block of settings.

The pattern comes from a production app that ships to Google Play from two tiers (staging and production) and embeds a second Flutter package tracked from a git branch. Every guard in the script exists because its absence once shipped a broken build. The guide removes the project-specific parts and adds iOS, CI, obfuscation symbols and store limits.

## Quick start

```bash
# 1. Copy the template into your app
cp -r template/tool template/config <your-app>/
cp template/lib/core/build_env.dart <your-app>/lib/core/
cat template/.gitignore >> <your-app>/.gitignore

# 2. Edit the settings block at the top of tool/build.sh (APP_SLUG, STORE_TIERS, ...)
# 3. Set up one flavor per tier (docs/02-tiers.md)
# 4. Put each tier's current version in tool/versions.tsv (docs/03-ledger.md)
# 5. Call BuildEnv.verify() first in main()

# Then:
tool/build.sh apk --release --dry-run                    # see what it would do
tool/build.sh apk --release --bump                       # staging APK, next code
tool/build.sh appbundle --release --tier prod --bump     # production AAB, next code
```

## Contents

| Doc | Covers |
|---|---|
| [01 Version numbers](docs/01-version-numbers.md) | versionName and versionCode, how Flutter maps them to Android and iOS, and the rules stores and devices enforce |
| [02 Tiers](docs/02-tiers.md) | Staging and production as separate apps: flavors, application ids, config files, and the checks that stop a crossed pair |
| [03 The version ledger](docs/03-ledger.md) | Why the number lives in `tool/versions.tsv` and not `pubspec.yaml`, numbering strategies compared, bump vs rebuild |
| [04 Git dependencies](docs/04-git-dependencies.md) | Packages tracked from a branch: lock vs compiled code, pinning, the stale compile |
| [05 Anatomy of build.sh](docs/05-anatomy.md) | The script, section by section, with the reason for each line |
| [06 Artifacts and symbols](docs/06-artifacts-and-symbols.md) | Finding and naming outputs, obfuscation, debug symbols, `--split-per-abi` |
| [07 CI](docs/07-ci.md) | Running the same script in GitHub Actions and committing the ledger back |
| [08 Failure catalogue](docs/08-failure-catalogue.md) | Symptom, cause and guard for every failure the script prevents |
| [09 Adoption checklist](docs/09-adoption-checklist.md) | Steps to move an existing project onto this setup |
| [Sources](docs/sources.md) | Official documentation and SDK source the guide relies on |

## Template

```
template/
  tool/build.sh                  the build script
  tool/sync-git-dep.sh           moves and verifies a branch-tracked git dependency
  tool/versions.tsv              the ledger, with two opening rows
  config/tiers/staging.json      compile-time values per tier
  config/tiers/prod.json
  lib/core/build_env.dart        typed access to those values, and a startup check
  android/app/build.gradle.kts   excerpt: flavors, version wiring, signing guard
  .github/workflows/release-build.yml
  .gitignore                     entries the clean-tree check depends on
```

Requirements: bash 3.2 or later (macOS default works), git, awk, and python3 for `sync-git-dep.sh` only.

## Principles

1. **The number comes from a record, not a line someone edits.** One `version:` line cannot serve two tiers.
2. **One switch decides the tier.** The application id, label, icon, backend URLs and version series all follow from `--tier`.
3. **Check where the facts meet.** A check goes in the one place that can see both values it compares.
4. **Fail at build time.** A device that refuses an install, or an app talking to the wrong backend, gives no error at build time. The script turns those into build errors.
5. **Record only what exists.** A ledger row is written after the artifact is on disk, never before.
