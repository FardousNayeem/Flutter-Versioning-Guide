# 03 The version ledger

## The problem with `pubspec.yaml`

`version: 1.4.2+57` is one line. With two tiers it feeds two version series:

- A staging build reuses the code production last shipped, or one testers already hold.
- A merge between branches moves one tier's number onto the other.
- A rebuild needs the line edited, and the edit has to be committed or it is lost.
- Nothing records which build went out with which number.

## The ledger

`tool/versions.tsv` is a tab-separated file with one row per successful build, oldest first. `build.sh` writes every column; nothing is typed by hand except an opening row and an optional `NOTE`.

```
# date	tier	name	code	git	dep	filed	time	branch	flutter	sdk	bytes	sha256	note
2026-03-02	staging	1.4.2	57	4be1c09	a91e2f0	myapp-staging-v1.4.2+57.apk	10:14:03+0600	main	3.44.7	36	48211936	3f0c9a1be27d4e55	-
2026-03-02	prod	1.4.2	58	4be1c09	a91e2f0	myapp-prod-v1.4.2+58.aab	10:31:40+0600	main	3.44.7	36	39877120	b81e00d4c6a2f913	-
2026-03-05	staging	1.4.2	57	71d03aa+dirty	c40b9e1	myapp-staging-v1.4.2+57.apk	16:02:55+0600	fix/login	3.44.7	36	48215104	0d97be3a51f2c870	rebuild, dep moved
```

| Column | Meaning |
|---|---|
| `date` | Day the build started |
| `tier` | Which series the row belongs to |
| `name` | versionName used |
| `code` | versionCode used |
| `git` | Commit the build started from; `+dirty` if the tree had uncommitted changes at the start |
| `dep` | Commit of the tracked git dependency that was compiled, or `-` |
| `filed` | File names written to `OUT_DIR` |
| `time` | Time the build started, with UTC offset. Orders several builds on one day, and matches a build to a tester's report or a crash timestamp |
| `branch` | Branch the build started from; `-` for a detached HEAD. A commit on a deleted or rebased branch is hard to find later; the branch name says where to look |
| `flutter` | Flutter SDK version. Two builds of one commit with different SDKs are different binaries |
| `sdk` | `targetSdkVersion` read from the artifact, or `-` if no tool could read it. Shows which past builds a newer Play requirement would reject ([10](10-store-gates.md)) |
| `bytes` | Size of each filed file, in the order of `filed`. A jump between two rows points at the commit that added a large asset or dependency |
| `sha256` | First 16 hex digits of each filed file's SHA-256. Identifies a file after someone renames it |
| `note` | `NOTE=...` from the environment, or `-`. Always the last column |

Rows written before the columns from `time` to `sha256` existed have eight columns and stay valid. The script reads only columns 1 to 4, and `note` is the last column in both forms.

Each tier reads only its own rows, so the two series cannot interfere. Lines starting with `#` are comments.

The script derives three values per tier:

```bash
last_name   # name in the tier's last row
last_code   # code in the tier's last row
max_code    # highest code in any of the tier's rows
```

`max_code` and `last_code` differ only after a deliberate step back (see below). A new build may never go under `max_code`.

## Bump or rebuild

| Command | Code | Use when |
|---|---|---|
| `tool/build.sh apk --release` | `last_code` | Testing a rebuild on a device. The device reinstalls over the same code |
| `tool/build.sh apk --release --bump` | `max_code + 1` | Anything that goes to testers or a store |
| `tool/build.sh ... --patch` (or `--minor`, `--major`) | `max_code + 1`, next name | A new release. The name is computed from the tier's last name |
| `VERSION_NAME=1.5.0 tool/build.sh ... --bump` | `max_code + 1`, given name | A name that is not the next patch, minor or major |

Nothing bumps automatically. A code spent on a build nobody released cannot be reused on a store, so taking one is an explicit decision.

On a **store tier** (listed in `STORE_TIERS`), a rebuild at `last_code` is refused unless `--reuse-code` is passed, because the store has probably already accepted that code.

## Reading the ledger

`tool/ledger.sh` reads the file and changes nothing:

```
tool/ledger.sh                   last 15 builds, aligned
tool/ledger.sh 40 --tier prod    last 40 production builds
tool/ledger.sh stats             per tier: builds, last version, last size and change
tool/ledger.sh which FILE        the row that produced FILE
```

```
date        time           tier     version    git      branch  flutter  size    note
2026-03-02  10:14:03+0600  staging  1.4.2+57   4be1c09  main    3.44.7   46.0MB  -
2026-03-02  10:31:40+0600  prod     1.4.2+58   4be1c09  main    3.44.7   38.0MB  -
```

### Which build is this file?

A tester sends an APK through a chat app, renamed to `app (3).apk`. `tool/ledger.sh which "app (3).apk"` hashes it and finds the row with the same SHA-256 prefix:

```
matched by sha256 3f0c9a1be27d4e55
  staging 1.4.2+57, built 2026-03-02 10:14:03+0600
  commit 4be1c09 on main, dep a91e2f0, flutter 3.44.7, targetSdk 36
  note: -
```

If no hash matches, it falls back to the file name and says so: a matching name with a different hash means the file is not the one that was built.

## Opening a tier

The ledger has no row for a new tier. `build.sh` refuses to guess one:

```
build.sh: no 'prod' row in tool/versions.tsv. Add an opening row by hand (see the file header).
If this app is already on a store, the opening code is the highest code the store holds, not a guess.
```

Add the row by hand:

```
2026-03-01	prod	3.2.0	412	-	-	-	opening row: last native release on Play
```

For an app replacing an earlier codebase on the same store listing, read the highest versionCode from Play Console (App bundle explorer) or App Store Connect. A guessed code that is too low produces builds every existing user's device refuses.

## Stepping back

To abandon a build that was never released, add a row by hand with the earlier code and a note. `last_code` now points to it, `max_code` still remembers the abandoned one, and the next `--bump` goes above both.

## Numbering strategies compared

| Strategy | How the code is chosen | Strength | Weakness |
|---|---|---|---|
| Hand-edited `pubspec.yaml` | Someone edits the line | No tooling | One line for all tiers; forgotten edits; no record |
| CI run number | `${{ github.run_number }}` or Codemagic `BUILD_NUMBER` | Always increases, no file | Tied to one workflow; a new workflow or CI vendor restarts at 1; local builds cannot take a number |
| Git commit count | `git rev-list --count HEAD` | Derived from history | Two builds of one commit get the same code; a rebase or shallow clone changes the count |
| Timestamp | e.g. minutes since an epoch | Always increases | Large numbers approach the 2100000000 limit faster; unreadable |
| **Ledger file** (this guide) | `max_code + 1` per tier, recorded after the build | Per-tier series; works locally and in CI; records commit, dependency and artifact | The ledger must be committed after each build |

The ledger is the only strategy that records what was built. Its cost is discipline: commit `tool/versions.tsv` and `pubspec.lock` after each build. In CI, the workflow commits them (see [07 CI](07-ci.md)). The store-tier clean-tree check also enforces it: the next production build refuses to start until the last ledger row is committed.

## Editing rules

- Append only. Correct history by adding a row with a note, not by changing old rows.
- Keep columns tab-separated: fourteen in rows the script writes, eight are enough in a row added by hand. The script strips tabs and newlines from `NOTE` and the branch name for this reason.
- Resolve merge conflicts by keeping both sides' rows. Every row happened.
