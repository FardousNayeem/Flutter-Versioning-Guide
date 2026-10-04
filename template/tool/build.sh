#!/usr/bin/env bash
# Build one release of this app for one tier, stamped with a version taken from
# tool/versions.tsv, and record what was built.
#
#   tool/build.sh apk --release                           staging, same code as last staging build
#   tool/build.sh apk --release --bump                    staging, next code
#   tool/build.sh appbundle --release --tier prod --bump  production AAB, next code
#   VERSION_NAME=2.4.0 tool/build.sh ipa --release --tier prod --bump
#   tool/build.sh appbundle --release --tier prod --bump --dry-run
#
# Options owned by this script (never passed to flutter):
#   --tier NAME     which tier to build; must have config/tiers/NAME.json
#   --bump          take the next versionCode for this tier
#   --reuse-code    allow a rebuild at the last code on a store tier
#   --allow-dirty   allow a store-tier build from uncommitted changes
#   --dry-run       print the version and the flutter command, build nothing
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
TIER_MECHANISM=flavor     # flavor: pass --flavor <tier>; property: pass -Ptier=<tier> (Android only)
TRACKED_GIT_DEP=""        # a git dependency that follows a branch; empty to disable
OBFUSCATE=1               # 1: --obfuscate --split-debug-info, symbols kept per build
MAX_CODE=2100000000       # Google Play's upper limit for versionCode

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

tier=$DEFAULT_TIER; bump=0; reuse=0; allow_dirty=0; dry=0; pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    --tier) [ $# -ge 2 ] || die "--tier needs a value"; tier=$2; shift ;;
    --tier=*) tier=${1#--tier=} ;;
    --bump) bump=1 ;;
    --reuse-code) reuse=1 ;;
    --allow-dirty) allow_dirty=1 ;;
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

# ---- 2. Config pairing ----
# Each tier file declares which tier it is. A file copied from another tier and
# not fully edited is caught here, before anything is compiled.
declared=$(sed -n 's/.*"APP_TIER"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config" | head -1)
[ "$declared" = "$tier" ] || die "config/tiers/$tier.json declares APP_TIER='$declared', expected '$tier'"

# ---- 3. Source state, read before anything below edits the tree ----
git_sha=$(git rev-parse --short HEAD 2>/dev/null || echo '-')
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  git_sha="$git_sha+dirty"
  if [ "$is_store" = 1 ] && [ "$allow_dirty" != 1 ] && [ "$dry" != 1 ]; then
    die "uncommitted changes; a $tier build must come from a commit. Commit, or pass --allow-dirty."
  fi
fi

# ---- 4. One build at a time ----
# Taken before the ledger is read: two builds reading it at once would both
# take the same "next" code.
if [ "$dry" != 1 ]; then
  lock=$tool/.build.lock
  mkdir "$lock" 2>/dev/null || die "another build holds $lock. If none is running, remove it."
  stamp=$(mktemp)
  trap 'rm -f "$stamp"; rmdir "$lock" 2>/dev/null || true' EXIT
fi

# ---- 5. Version from the ledger ----
[ -f "$ledger" ] || die "tool/versions.tsv is missing"
row() { awk -F'\t' -v s="$tier" -v c="$1" '$1!~/^#/ && NF>=4 && $2==s {v=$c} END{print v}' "$ledger"; }
last_name=$(row 3)
last_code=$(row 4)
max_code=$(awk -F'\t' -v s="$tier" '$1!~/^#/ && NF>=4 && $2==s && $4+0>m {m=$4+0} END{print m+0}' "$ledger")

[ -n "$last_name" ] || die "no '$tier' row in tool/versions.tsv. Add an opening row by hand (see the file header).
If this app is already on a store, the opening code is the highest code the store holds, not a guess."

name=${VERSION_NAME:-$last_name}
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

say "tier $tier, version $name+$code"
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

mkdir -p "$out_dir"
base=$APP_SLUG-$tier-v$name+$code
filed=()
for a in "${artifacts[@]}"; do
  ext=${a##*.}
  if [ ${#artifacts[@]} -eq 1 ]; then
    dest=$out_dir/$base.$ext
  else
    dest=$out_dir/$base-$(basename "$a" ".$ext").$ext
  fi
  cp -f "$a" "$dest"
  filed+=("$(basename "$dest")")
  say "filed $dest"
done

# ---- 11. Record ----
# Written only after a successful build: a row claims an artifact exists, and
# the next build takes its number from the last row.
note=$(printf '%s' "${NOTE:--}" | tr '\t\n' '  ')
filed_list=$(IFS=,; echo "${filed[*]}")
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(date +%Y-%m-%d)" "$tier" "$name" "$code" "$git_sha" "$dep_sha" "$filed_list" "$note" >> "$ledger"

say "recorded in tool/versions.tsv. Commit it with pubspec.lock."
[ -z "$symbols" ] || say "symbols in $symbols. Upload them to your crash reporter before release."
