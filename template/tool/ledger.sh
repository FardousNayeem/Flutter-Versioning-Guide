#!/usr/bin/env bash
# Read tool/versions.tsv. Changes nothing.
#
#   tool/ledger.sh                    last 15 builds, all tiers
#   tool/ledger.sh 40 --tier prod     last 40 production builds
#   tool/ledger.sh stats              per tier: count, last version, size and its change
#   tool/ledger.sh which FILE         which ledger row produced this .apk/.aab/.ipa
#
# Rows from before the time column existed (eight columns) show '-' for the
# fields they do not have.
set -euo pipefail
cd "$(dirname "$0")/.."
ledger=tool/versions.tsv
[ -f "$ledger" ] || { echo "ledger.sh: $ledger is missing" >&2; exit 1; }

# Column numbers of a full row. note is always $NF, in old rows and new.
COLS='BEGIN { FS = "\t"; TIME = 8; BRANCH = 9; FLUTTER = 10; SDK = 11; BYTES = 12; SHA = 13; FULL = 14 }
function f(i) { return (NF >= FULL && $i != "") ? $i : "-" }
function mb(b) { split(b, p, ","); return p[1] ~ /^[0-9]+$/ ? sprintf("%.1fMB", p[1] / 1048576) : "-" }'

cmd=list; n=15; tier=""
while [ $# -gt 0 ]; do
  case "$1" in
    stats) cmd=stats ;;
    which) cmd=which; [ $# -ge 2 ] || { echo "usage: tool/ledger.sh which FILE" >&2; exit 2; }; file=$2; shift ;;
    --tier) [ $# -ge 2 ] || { echo "--tier needs a value" >&2; exit 2; }; tier=$2; shift ;;
    --tier=*) tier=${1#--tier=} ;;
    [0-9]*) n=$1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "ledger.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

case "$cmd" in
  list)
    { printf 'date\ttime\ttier\tversion\tgit\tbranch\tflutter\tsize\tnote\n'
      awk -v t="$tier" "$COLS"'
        $1 ~ /^#/ || NF < 4 { next }
        t != "" && $2 != t { next }
        { print $1, f(TIME), $2, $3 "+" $4, $5, f(BRANCH), f(FLUTTER), mb(f(BYTES)), $NF }
      ' OFS='\t' "$ledger" | tail -n "$n"
    } | column -t -s "$(printf '\t')" ;;

  stats)
    # change is against the tier's previous build that recorded a size, so a
    # dependency or asset that grew the app shows up on the build that added it.
    { printf 'tier\tbuilds\tlast\tlast size\tchange\n'
      awk -v t="$tier" "$COLS"'
        $1 ~ /^#/ || NF < 4 { next }
        t != "" && $2 != t { next }
        !($2 in seen) { seen[$2] = 1; order[++k] = $2 }
        { count[$2]++; last[$2] = $3 "+" $4 }
        f(BYTES) != "-" { prevsize[$2] = size[$2]; size[$2] = f(BYTES) }
        END {
          for (j = 1; j <= k; j++) {
            x = order[j]
            split(size[x], a, ","); split(prevsize[x], b, ",")
            change = (a[1] != "" && b[1] != "") ? sprintf("%+.1fMB", (a[1] - b[1]) / 1048576) : "-"
            print x, count[x], last[x], mb(size[x]), change
          }
        }' OFS='\t' "$ledger"
    } | column -t -s "$(printf '\t')" ;;

  which)
    # By content first: a file renamed by whoever sent it still matches.
    [ -f "$file" ] || { echo "ledger.sh: no such file: $file" >&2; exit 1; }
    sum=$({ sha256sum "$file" 2>/dev/null || shasum -a 256 "$file"; } | cut -c1-16)
    hit=$(awk -v h="$sum" "$COLS"'
      $1 !~ /^#/ && NF >= FULL { n = split($SHA, s, ","); for (i = 1; i <= n; i++) if (s[i] == h) print }' "$ledger")
    how="sha256 $sum"
    if [ -z "$hit" ]; then
      base=$(basename "$file")
      hit=$(awk -F'\t' -v b="$base" '$1 !~ /^#/ { n = split($7, s, ","); for (i = 1; i <= n; i++) if (s[i] == b) print }' "$ledger")
      how="file name only; sha256 $sum is not in the ledger, so this file may differ from the one built"
    fi
    [ -n "$hit" ] || { echo "ledger.sh: $file (sha256 $sum) matches no row" >&2; exit 1; }
    echo "matched by $how"
    printf '%s\n' "$hit" | awk "$COLS"'
      { print "  " $2 " " $3 "+" $4 ", built " $1 " " f(TIME)
        print "  commit " $5 " on " f(BRANCH) ", dep " $6 ", flutter " f(FLUTTER) ", targetSdk " f(SDK)
        print "  note: " $NF }' ;;
esac
