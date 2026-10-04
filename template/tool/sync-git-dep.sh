#!/usr/bin/env bash
# Move a git dependency to the head of the branch pubspec.yaml names, then
# prove the compiler will read the commit pubspec.lock records.
#
#   tool/sync-git-dep.sh <package>           adopt the branch head, then verify
#   tool/sync-git-dep.sh <package> --pin     install exactly what the lock pins, then verify
#   tool/sync-git-dep.sh <package> --check   verify only, change nothing
#
# Expects the dependency in this form in pubspec.yaml:
#
#   <package>:
#     git:
#       url: https://github.com/org/repo.git
#       ref: main
#
# Requires git and python3.
set -euo pipefail
cd "$(dirname "$0")/.."

pkg=${1:?usage: tool/sync-git-dep.sh <package> [--pin|--check]}
mode=${2:-sync}
case "$mode" in sync|--pin|--check) ;; *) echo "sync-git-dep: unknown mode $mode" >&2; exit 2 ;; esac

field() {
  awk -v p="  $pkg:" -v k="$1" '$0==p {f=1; next} f && /^(  )?[^ ]/ {exit}
    f && $1==k":" {print $2; exit}' pubspec.yaml
}
url=$(field url)
ref=$(field ref); ref=${ref:-main}
[ -n "$url" ] || { echo "sync-git-dep: no git url for $pkg in pubspec.yaml" >&2; exit 1; }

read_lock() {
  awk -v p="  $pkg:" '$0==p {f=1; next} f && /^(  )?[^ ]/ {exit}
    f && $1=="resolved-ref:" {gsub(/"/,"",$2); print $2; exit}' pubspec.lock 2>/dev/null || true
}

# The pub-cache directory in package_config.json is what the compiler reads.
# The lock is a record of intent; this is the fact.
read_compiled() {
  PKG="$pkg" python3 - <<'PY'
import json, os, re
p = '.dart_tool/package_config.json'
if not os.path.exists(p):
    raise SystemExit
pkg = next((x for x in json.load(open(p))['packages'] if x['name'] == os.environ['PKG']), None)
if pkg:
    m = re.search(r'-([0-9a-f]{40})/?$', pkg['rootUri'])
    print(m.group(1) if m else pkg['rootUri'])
PY
}

# Offline is a warning, not a failure: the lock and the compiled directory are
# both local, and only the "behind the branch" comparison needs the network.
head=$(git ls-remote "$url" "refs/heads/$ref" 2>/dev/null | cut -f1 || true)
[ -n "$head" ] || echo "sync-git-dep: cannot reach $url; skipping the branch comparison" >&2

before=$(read_lock)
case "$mode" in
  sync)
    if [ -z "$head" ]; then
      echo "sync-git-dep: offline, keeping the locked commit" >&2
      flutter pub get --enforce-lockfile
    elif [ "$before" = "$head" ]; then
      echo "sync-git-dep: already at head of $ref"
    else
      # Named package only: moving this dependency is not a reason to move the others.
      flutter pub upgrade "$pkg"
    fi ;;
  --pin)
    # Fails if the lock does not satisfy pubspec.yaml, instead of rewriting it.
    flutter pub get --enforce-lockfile ;;
  --check) ;;
esac
after=$(read_lock)
compiled=$(read_compiled)

echo "$pkg"
echo "  $ref (remote)  ${head:-<unreachable>}"
echo "  lock           ${after:-<none>}$([ "$mode" = sync ] && [ "$after" != "$before" ] && echo "   (was ${before:0:7})")"
echo "  compiled       ${compiled:-<not resolved; run flutter pub get>}"

if [ -n "$compiled" ] && [ "$compiled" != "$after" ]; then
  echo "MISMATCH: lock says ${after:0:7}, compiler reads ${compiled:0:7}. Run flutter pub get." >&2
  exit 1
fi
if [ -n "$head" ] && [ "$after" != "$head" ]; then
  if [ "$mode" = sync ]; then
    echo "pub upgrade did not reach ${head:0:7}. Check the constraint and ref in pubspec.yaml." >&2
    exit 1
  fi
  echo "  behind $ref by design ($mode). Run without a flag to adopt ${head:0:7}."
fi
