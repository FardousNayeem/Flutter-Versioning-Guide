# 08 Failure catalogue

Each failure below produces a successful `flutter build`. The symptom appears later, on a device, in a store console or in production data.

| # | Symptom | Cause | Guard |
|---|---|---|---|
| 1 | Testers report "App not installed" on update | New versionCode lower than the one on the device | Step 5: code never below the tier's highest |
| 2 | Play rejects upload: "Version code N has already been used" | Rebuild uploaded with an existing code | Step 5: store tiers refuse a reused code without `--reuse-code` |
| 3 | Staging build blocks the next production update on a tester's device | Staging and production share an application id and a code line | Separate application id per tier; one ledger series per tier |
| 4 | Production app writes to the test database | Production application id built with the staging config | Step 2 config pairing; `BuildEnv.verify()` at startup; optional Gradle check |
| 5 | App works but every request to one backend fails | Compile-time define missing; code fell back to a default URL | `BuildEnv.verify()` throws on empty values; config file is always passed |
| 6 | Build claims a fix that is not in it | Dependency moved but Gradle skipped the Dart compile | Step 8 deletes Dart build state |
| 7 | Build contains a dependency commit nobody chose | Lock and `package_config.json` disagree | `sync-git-dep.sh` verifies lock against compiled directory |
| 8 | Testers never get fixes merged in a shared package | Git dependency locked to an old commit | `sync-git-dep.sh` adopts the branch head on each build |
| 9 | Release cannot be reproduced | Built from uncommitted code, or ledger and lock not committed | Step 3 refuses dirty store builds; `+dirty` in the ledger |
| 10 | Old binary filed as a new build | Flutter exited 0 without writing; script took what was in `build/` | Step 10 accepts only files newer than the stamp |
| 11 | A ledger row exists for a build that failed | Row written before the build | Step 13 runs last |
| 12 | Two builds carry the same code | Two builds read the ledger at once | Step 4 lock; CI concurrency group |
| 13 | Universal APK refused after a split APK was installed | `--split-per-abi` set codes to `abi*1000+code` | Step 1 refuses `--split-per-abi` |
| 14 | Production stack traces unreadable | Symbols lost, or from another build | Symbols kept per build, named by tier, name and code |
| 15 | API key leaked | Secret passed via `--dart-define` | Policy: config files hold no secrets (see [02](02-tiers.md#compile-time-config)) |
| 16 | Release APK cannot update existing installs | Signed with the debug key because `key.properties` was missing | Gradle throws when release signing is not configured |
| 17 | Ledger columns shift, wrong code read | Tab or newline in a note | Step 13 strips them |
| 18 | Upload rejected, versionName invalid | Name like `2.0` or `v2.0.0-beta` | Step 5 requires `MAJOR.MINOR.PATCH` |
| 19 | New production series starts at a code below the store's | Opening code guessed | Step 5 refuses a tier with no row; opening row is entered from the store console |
| 20 | Ledger says code 58, device or Play sees 12 | `versionCode` hard-coded in `build.gradle.kts`, overriding `--build-number` | Step 11 reads the code back out of the artifact |
| 21 | Production runs code that was never merged | Store build started from a feature branch | Step 3 refuses store tiers off `STORE_BRANCHES` |
| 22 | Play rejects upload: target API level too low | `targetSdk` below the yearly requirement | Step 11 refuses store tiers below `MIN_TARGET_SDK` |
| 23 | Nobody can say which build a tester's renamed APK is | File name lost in transfer | `sha256` column; `tool/ledger.sh which` |
| 24 | Typo in a release version (`1.4.12` for `1.4.3`) | Name typed by hand | `--patch` / `--minor` / `--major`; CI dropdown |

## Adding a guard

When a new failure ships:

1. Find the earliest point that can see both facts involved.
2. Make that point exit non-zero with a message stating the problem and the fix.
3. Add a comment above the check saying what happened and when.
4. Add a row to this table.
