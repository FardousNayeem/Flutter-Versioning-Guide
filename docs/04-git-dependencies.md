# 04 Git dependencies

This applies when the app depends on a package from a git repository and wants the latest commit of a branch:

```yaml
dependencies:
  shared_ui:
    git:
      url: https://github.com/org/shared_ui.git
      ref: main
```

Skip this doc if all dependencies come from pub.dev. Set `TRACKED_GIT_DEP=""` in `build.sh`.

## Where the commit is recorded

| File | Holds |
|---|---|
| `pubspec.yaml` | `ref: main`: the branch, not a commit |
| `pubspec.lock` | `resolved-ref: <40-char sha>`: the commit pub resolved |
| `.dart_tool/package_config.json` | `rootUri: .../.pub-cache/git/shared_ui-<sha>/`: the directory the compiler reads |

`flutter pub get` does not move a git dependency once the lock has a `resolved-ref`. The branch moves on GitHub and the app keeps building the old commit until someone runs `flutter pub upgrade shared_ui`. A fix merged in the package reaches testers only when someone remembers to do that.

## Two policies

| Policy | Command | Result |
|---|---|---|
| Follow the branch (default) | `tool/build.sh ...` | Every build adopts the branch head first |
| Pin | `PIN_DEPS=1 tool/build.sh ...` | The build uses exactly the commit in `pubspec.lock` |

Following the branch has a cost: a broken commit on the package's `main` goes into the next build. Pinning is how you:

- rebuild an old release byte for byte (check out its commit, then `PIN_DEPS=1`),
- ship a hotfix while the package's `main` is broken.

If GitHub is unreachable, the sync step prints a warning and builds the locked commit.

## What `sync-git-dep.sh` does

```
tool/sync-git-dep.sh shared_ui            adopt branch head, verify
tool/sync-git-dep.sh shared_ui --pin      install the locked commit, verify
tool/sync-git-dep.sh shared_ui --check    verify only
```

1. Reads `url` and `ref` for the package from `pubspec.yaml`.
2. `git ls-remote <url> refs/heads/<ref>` gets the branch head without cloning.
3. Sync mode: if the lock already has the head, does nothing, so `pubspec.lock` is not rewritten. Otherwise runs `flutter pub upgrade <package>`, naming the package so no other dependency moves.
4. Pin mode: `flutter pub get --enforce-lockfile`, which fails instead of rewriting a lock that does not satisfy `pubspec.yaml`.
5. **Verifies**: the lock's `resolved-ref` must equal the sha in the pub-cache directory named by `package_config.json`. If they differ, it exits 1.
6. In sync mode, fails if the lock still does not match the branch head after the upgrade, for example because a version constraint held it back.

Output:

```
shared_ui
  main (remote)  903f6d27ca2fb634bcc06c9a3c6ec76975ea285e
  lock           903f6d27ca2fb634bcc06c9a3c6ec76975ea285e   (was ea9b526)
  compiled       903f6d27ca2fb634bcc06c9a3c6ec76975ea285e
```

### Why verify

The lock is a record of what pub resolved. `package_config.json` is what the compiler will read. They can disagree after a branch switch, a merge that took the other side's lock, or an interrupted `pub` run. In that case the lock names one commit and the binary contains another. The check costs nothing and turns that into an error.

A `path:` override used while developing the package has no sha, so the check fails. Use `flutter run` for that work, not `build.sh`.

## The stale compile

After the dependency moves, the build can still ship the old code:

1. Gradle's task `compileFlutterBuild<Variant>` is skipped when its inputs have not changed.
2. Its inputs come from the depfile written by the **previous** build, which lists the files that build read, including `.pub-cache/git/shared_ui-<old sha>/...`.
3. The new commit is in a **new** directory, `shared_ui-<new sha>/`. The old directory still exists and has not changed.
4. Gradle sees no changed input, skips the Dart compile, and packages the previous `libapp.so`.

`flutter build` reports success. The version number is new, the ledger names the new commit, and the code is old.

`build.sh` step 8 deletes the Dart build state before every build:

```bash
rm -rf .dart_tool/flutter_build build/app/intermediates/flutter
```

This adds one full Dart compile per build, typically under two minutes. `flutter clean` also works but deletes more and forces a slower rebuild.

## Recording

`build.sh` writes the first seven characters of the compiled commit into the ledger's `dep` column. It is read after the sync step, so it is the commit the build compiled, not the one the branch pointed at when the build started.

Commit `pubspec.lock` together with `tool/versions.tsv`. Otherwise the commit in the `git` column does not contain the dependency commit in the `dep` column, and the build cannot be reproduced from history.
