#!/usr/bin/env bash
# Build one release of this app for one tier, stamped with a version taken from
# tool/versions.tsv, and record what was built.
#
#   tool/build.sh apk --release                           staging, same code as last staging build
#   tool/build.sh apk --release --bump                    staging, next code
#   tool/build.sh appbundle --release --tier prod --bump  production AAB, next code
#   tool/build.sh appbundle --release --tier prod --patch 1.4.2 -> 1.4.3, next code
#   VERSION_NAME=2.4.0 tool/build.sh ipa --release --tier prod --bump
#   tool/build.sh appbundle --release --tier prod --bump --dry-run
#
# Options owned by this script (never passed to flutter):
#   --tier NAME      which tier to build; must have config/tiers/NAME.json
#   --bump           take the next versionCode for this tier
#   --patch          next versionName: 1.4.2 -> 1.4.3. Implies --bump
#   --minor          next versionName: 1.4.2 -> 1.5.0. Implies --bump
#   --major          next versionName: 1.4.2 -> 2.0.0. Implies --bump
#   --reuse-code     allow a rebuild at the last code on a store tier
#   --allow-dirty    allow a store-tier build from uncommitted changes
#   --allow-branch   allow a store-tier build from a branch not in STORE_BRANCHES
#   --dry-run        print the version and the flutter command, build nothing
#
# Everything else is passed to `flutter build` unchanged.
#
# Environment:
#   VERSION_NAME   versionName for this build (default: the tier's last name)
#   NOTE           free text recorded in the ledger
#   OUT_DIR        where artifacts are copied (default: <repo>/dist)
#   PIN_DEPS=1     build the locked commit of TRACKED_GIT_DEP; do not move it
set -euo pipefail

# ---- Project settings ----
# The only block to edit when adopting this script.
APP_SLUG=myapp            # used in artifact file names
DEFAULT_TIER=staging      # tier built when --tier is not given
STORE_TIERS="prod"        # tiers uploaded to a store: a code can never be reused
STORE_BRANCHES="main"     # branches a store-tier build may start from; empty allows any
TIER_MECHANISM=flavor     # flavor: pass --flavor <tier>; property: pass -Ptier=<tier> (Android only)
TRACKED_GIT_DEP=""        # a git dependency that follows a branch; empty to disable
OBFUSCATE=1               # 1: --obfuscate --split-debug-info, symbols kept per build
MAX_CODE=2100000000       # Google Play's upper limit for versionCode
MIN_TARGET_SDK=36         # store tiers: lowest targetSdk Google Play accepts (docs/10-store-gates.md)

root=$(cd "$(dirname "$0")/.." && pwd)
tool=$root/tool
ledger=$tool/versions.tsv
cd "$root"

die() { echo "build.sh: $*" >&2; exit 1; }
say() { echo "build.sh: $*"; }

# ---- 1. Arguments ----
[ $# -ge 1 ] || die "usage: tool/build.sh <apk|appbundle|ipa> [--tier NAME] [--bump] [flutter args...]"
target=$1; shift
case "$target" in
  apk|appbundle|ipa) ;;
  *) die "target '$target' is not supported; use apk, appbundle or ipa" ;;
esac

tier=$DEFAULT_TIER; bump=0; part=""; reuse=0; allow_dirty=0; allow_branch=0; dry=0; pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    --tier) [ $# -ge 2 ] || die "--tier needs a value"; tier=$2; shift ;;
    --tier=*) tier=${1#--tier=} ;;
    --bump) bump=1 ;;
    # A new name always gets a new code: a store rejects a new name on an old code.
    --patch|--minor|--major)
      [ -z "$part" ] || die "use one of --patch, --minor, --major"
      part=${1#--}; bump=1 ;;
    --reuse-code) reuse=1 ;;
    --allow-dirty) allow_dirty=1 ;;
    --allow-branch) allow_branch=1 ;;
    --dry-run) dry=1 ;;
    # The script sets these. A second value on the command line would make the
    # artifact disagree with the ledger row written for it.
    --build-name*|--build-number*|--flavor*|--dart-define-from-file*|--split-debug-info*|-Ptier*)
      die "'$1' is set by this script; remove it" ;;
    # Flutter's Gradle plugin rewrites each split APK's code to abi*1000+code
    # (arm32 1, arm64 2, x86_64 4). The ledger would record 7 while devices
    # hold 2007, and the next --bump (8) would be refused by every one of them.
    --split-per-abi)
      die "--split-per-abi stamps abi*1000+code, not the ledger's code. Build an appbundle for stores, or a universal apk." ;;
    *) pass+=("$1") ;;
  esac
  shift
done

is_store=0
for t in $STORE_TIERS; do [ "$t" = "$tier" ] && is_store=1; done

config=$root/config/tiers/$tier.json
[ -f "$config" ] || die "no config for tier '$tier' (expected config/tiers/$tier.json)"

if [ "$TIER_MECHANISM" = property ] && [ "$target" = ipa ]; then
  die "TIER_MECHANISM=property is Android only; iOS tiers need flavors (Xcode schemes)"
fi

# A store-tier refusal. In a dry run it is printed instead, so --dry-run shows
# every problem the real build would stop on.
refuse() { if [ "$dry" = 1 ]; then say "would refuse: $*"; else die "$*"; fi; }

# ---- 2. Config pairing ----
# Each tier file declares which tier it is. A file copied from another tier and
# not fully edited is caught here, before anything is compiled.
declared=$(sed -n 's/.*"APP_TIER"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config" | head -1)
[ "$declared" = "$tier" ] || die "config/tiers/$tier.json declares APP_TIER='$declared', expected '$tier'"

# ---- 3. Source state, read before anything below edits the tree ----
git_sha=$(git rev-parse --short HEAD 2>/dev/null || echo '-')
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  git_sha="$git_sha+dirty"
  if [ "$is_store" = 1 ] && [ "$allow_dirty" != 1 ]; then
    refuse "uncommitted changes; a $tier build must come from a commit. Commit, or pass --allow-dirty."
  fi
fi

# A store build from a feature branch ships code that was never merged, and the
# commit in the ledger may later be rebased away. Detached HEAD reads as '-'.
branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo '-')
if [ "$is_store" = 1 ] && [ -n "$STORE_BRANCHES" ] && [ "$allow_branch" != 1 ]; then
  on_store_branch=0
  for b in $STORE_BRANCHES; do [ "$b" = "$branch" ] && on_store_branch=1; done
  [ "$on_store_branch" = 1 ] ||
    refuse "a $tier build must start from: $STORE_BRANCHES. HEAD is on '$branch'. Switch branch, or pass --allow-branch."
fi

# ---- 4. One build at a time ----
# Taken before the ledger is read: two builds reading it at once would both
# take the same "next" code.
if [ "$dry" != 1 ]; then
  lock=$tool/.build.lock
  mkdir "$lock" 2>/dev/null || die "another build holds $lock. If none is running, remove it."
  stamp=$(mktemp)
  scratch=$(mktemp -d)
  trap 'rm -rf "$stamp" "$scratch"; rmdir "$lock" 2>/dev/null || true' EXIT
fi
# Date and time are both taken at the start, so a build that runs past midnight
# is recorded under the day it began.
start_date=$(date +%Y-%m-%d)
start_time=$(date +%H:%M:%S%z)

# ---- 5. Version from the ledger ----
[ -f "$ledger" ] || die "tool/versions.tsv is missing"
row() { awk -F'\t' -v s="$tier" -v c="$1" '$1!~/^#/ && NF>=4 && $2==s {v=$c} END{print v}' "$ledger"; }
last_name=$(row 3)
last_code=$(row 4)
max_code=$(awk -F'\t' -v s="$tier" '$1!~/^#/ && NF>=4 && $2==s && $4+0>m {m=$4+0} END{print m+0}' "$ledger")

[ -n "$last_name" ] || die "no '$tier' row in tool/versions.tsv. Add an opening row by hand (see the file header).
If this app is already on a store, the opening code is the highest code the store holds, not a guess."

if [ -n "$part" ]; then
  [ -z "${VERSION_NAME:-}" ] || die "VERSION_NAME and --$part both set the name; use one"
  echo "$last_name" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "last $tier name '$last_name' is not MAJOR.MINOR.PATCH; set VERSION_NAME once"
  IFS=. read -r major minor patch <<EOF
$last_name
EOF
  case "$part" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
  esac
  name=$major.$minor.$patch
else
  name=${VERSION_NAME:-$last_name}
fi
echo "$name" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "versionName '$name' is not MAJOR.MINOR.PATCH"

if [ "$bump" = 1 ]; then
  code=$((max_code + 1))
else
  code=$last_code
  if [ "$is_store" = 1 ] && [ "$reuse" != 1 ]; then
    die "$tier is a store tier and $code is its last code. A store rejects a code it has accepted.
Use --bump. Use --reuse-code only if $code was never uploaded."
  fi
fi

[ "$code" -ge "$max_code" ] || die "$tier has already used code $max_code; refusing $code. Use --bump."
[ "$code" -le "$MAX_CODE" ] || die "code $code is above the store limit $MAX_CODE"

if [ "$bump" != 1 ]; then
  say "REBUILD IN PLACE at $name+$code. A device holding $code can reinstall it; a store will not take it."
fi

# ---- 6. The flutter command ----
symbols=""
cmd=(flutter build "$target")
cmd+=(${pass[@]+"${pass[@]}"})
cmd+=(--build-name="$name" --build-number="$code" --dart-define-from-file="$config")
if [ "$TIER_MECHANISM" = flavor ]; then
  cmd+=(--flavor "$tier")
else
  cmd+=(-Ptier="$tier")
fi
out_dir=${OUT_DIR:-$root/dist}
if [ "$OBFUSCATE" = 1 ]; then
  symbols=$out_dir/symbols/$APP_SLUG-$tier-v$name+$code
  cmd+=(--obfuscate --split-debug-info="$symbols")
fi

say "tier $tier, version $name+$code, branch $branch"
say "${cmd[*]}"
if [ "$dry" = 1 ]; then
  say "dry run: nothing built, nothing recorded"
  exit 0
fi

# ---- 7. Tracked git dependency ----
dep_sha="-"
if [ -n "$TRACKED_GIT_DEP" ]; then
  if [ -n "${PIN_DEPS:-}" ]; then
    say "PIN_DEPS set: building the locked $TRACKED_GIT_DEP"
    "$tool/sync-git-dep.sh" "$TRACKED_GIT_DEP" --pin
  else
    "$tool/sync-git-dep.sh" "$TRACKED_GIT_DEP"
  fi
  dep_sha=$(awk -v p="  $TRACKED_GIT_DEP:" '$0==p {f=1; next} f && /^(  )?[^ ]/ {exit}
    f && $1=="resolved-ref:" {gsub(/"/,"",$2); print substr($2,1,7); exit}' pubspec.lock)
  dep_sha=${dep_sha:--}
fi

# ---- 8. Fresh Dart compile ----
# Gradle decides whether the Dart compile is up to date from the input list of
# the previous build. A git dependency that moved to a new commit lives in a new
# pub-cache directory that list does not name, so the compile can be skipped and
# the old code shipped under the new version.
rm -rf .dart_tool/flutter_build build/app/intermediates/flutter

# The SDK that compiled the build. Two builds of one commit with different SDKs
# are different binaries, so the ledger needs this to explain a difference.
flutter_ver=$(flutter --version --machine 2>/dev/null |
  sed -n 's/.*"frameworkVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
flutter_ver=${flutter_ver:--}

# ---- 9. Build ----
"${cmd[@]}"

# ---- 10. Collect artifacts ----
# Found by modification time inside the directories flutter writes release
# artifacts to, so a flavor, an ABI split or a new flag cannot break the path.
artifacts=()
while IFS= read -r -d '' f; do artifacts+=("$f"); done < <(
  find build/app/outputs/flutter-apk build/app/outputs/bundle build/ios/ipa \
    -newer "$stamp" -type f \( -name '*.apk' -o -name '*.aab' -o -name '*.ipa' \) \
    -print0 2>/dev/null || true)

[ ${#artifacts[@]} -gt 0 ] || die "flutter reported success but wrote no new .apk/.aab/.ipa. Nothing recorded."

# ---- 11. Read the version back out of each artifact ----
# --build-number reaches the binary only through `versionCode = flutter.versionCode`
# in Gradle and FLUTTER_BUILD_NUMBER in Xcode. A hard-coded value in either
# file wins silently, and the ledger would record a code the artifact does not
# carry. Each reader needs a tool; without it the check is skipped, with a warning.

# Newest copy of an Android build-tools binary, from PATH or the SDK.
android_tool() {
  command -v "$1" 2>/dev/null && return 0
  local sdk v
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
    [ -n "$sdk" ] && [ -d "$sdk/build-tools" ] || continue
    v=$(ls "$sdk/build-tools" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
    [ -x "$sdk/build-tools/$v/$1" ] && { echo "$sdk/build-tools/$v/$1"; return 0; }
  done
  return 1
}

# Prints "<versionCode> <targetSdk or ->", or nothing when no reader is available.
read_stamp() {
  local tool_path plist
  case "$1" in
    *.apk)
      tool_path=$(android_tool aapt2) || return 0
      "$tool_path" dump badging "$1" 2>/dev/null | awk -F"'" '
        /^package:/ { for (i = 1; i < NF; i++) if ($i ~ /versionCode=$/) c = $(i+1) }
        /^targetSdkVersion:/ { t = $2 }
        END { if (c != "") print c, (t != "" ? t : "-") }' ;;
    *.aab)
      command -v bundletool >/dev/null 2>&1 || return 0
      echo "$(bundletool dump manifest --bundle="$1" --xpath=/manifest/@android:versionCode 2>/dev/null)" \
           "$(bundletool dump manifest --bundle="$1" --xpath=/manifest/uses-sdk/@android:targetSdkVersion 2>/dev/null || echo -)" ;;
    *.ipa)
      command -v plutil >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 || return 0
      plist=$(unzip -Z1 "$1" | grep -E '^Payload/[^/]+\.app/Info\.plist$' | head -1 || true)
      [ -n "$plist" ] || return 0
      unzip -p "$1" "$plist" > "$scratch/Info.plist"
      echo "$(plutil -extract CFBundleVersion raw -o - "$scratch/Info.plist" 2>/dev/null) -" ;;
  esac
}

target_sdk="-"
for a in "${artifacts[@]}"; do
  got=$(read_stamp "$a" || true)
  got_code=${got%% *}
  got_sdk=${got##* }
  case "$got_code" in
    ''|*[!0-9]*)
      say "warning: could not read the version from $(basename "$a") (needs aapt2, bundletool or plutil). Not verified."
      continue ;;
  esac
  case "$got_sdk" in ''|*[!0-9]*) got_sdk="-" ;; esac
  [ "$got_code" = "$code" ] || die "$(basename "$a") carries versionCode $got_code, but this build is $code.
A hard-coded versionCode in android/app/build.gradle(.kts) or CFBundleVersion in Info.plist overrides --build-number. Nothing recorded."
  if [ "$got_sdk" != "-" ]; then
    target_sdk=$got_sdk
    if [ "$is_store" = 1 ] && [ "$got_sdk" -lt "$MIN_TARGET_SDK" ]; then
      die "$(basename "$a") targets SDK $got_sdk; Google Play requires $MIN_TARGET_SDK for updates. Raise targetSdk. Nothing recorded."
    fi
  fi
  say "verified $(basename "$a"): versionCode $got_code, targetSdk $got_sdk"
done

# ---- 12. File artifacts ----
sha16() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -c1-16; }

mkdir -p "$out_dir"
base=$APP_SLUG-$tier-v$name+$code
filed=(); sizes=(); hashes=()
for a in "${artifacts[@]}"; do
  ext=${a##*.}
  if [ ${#artifacts[@]} -eq 1 ]; then
    dest=$out_dir/$base.$ext
  else
    dest=$out_dir/$base-$(basename "$a" ".$ext").$ext
  fi
  cp -f "$a" "$dest"
  filed+=("$(basename "$dest")")
  sizes+=("$(wc -c < "$dest" | tr -d ' ')")
  hashes+=("$(sha16 "$dest")")
  say "filed $dest"
done

# ---- 13. Record ----
# Written only after a successful build: a row claims an artifact exists, and
# the next build takes its number from the last row. Column order is in the
# header of tool/versions.tsv. note stays last so it is always $NF.
clean() { printf '%s' "$1" | tr '\t\n' '  '; }
join() { local IFS=,; echo "$*"; }

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$start_date" "$tier" "$name" "$code" "$git_sha" "$dep_sha" "$(join "${filed[@]}")" \
  "$start_time" "$(clean "$branch")" "$flutter_ver" "$target_sdk" \
  "$(join "${sizes[@]}")" "$(join "${hashes[@]}")" "$(clean "${NOTE:--}")" >> "$ledger"

say "recorded in tool/versions.tsv. Commit it with pubspec.lock."
[ -z "$symbols" ] || say "symbols in $symbols. Upload them to your crash reporter before release."
