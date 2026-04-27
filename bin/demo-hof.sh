#!/usr/bin/env sh
# Render a Hall-of-Fame preview from mock state into assets/hof-demo.html.
# Used for visual iteration: edit the inline HTML heredoc inside
# _bisio_render_html (bin/_counter.sh), run this script, reload the file
# in your browser.
#
# The output path is gitignored — never committed.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
export repo_dir

# Real BISIO_WEIGHT_* values so RNG-sanity expected % matches production.
# shellcheck source=./banner.config.sh
. "$repo_dir/bin/banner.config.sh"
# shellcheck source=./_counter.sh
. "$repo_dir/bin/_counter.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Mock state. Variant slugs and dex order must match files in assets/bisio/.
# Counts pick a realistic-looking distribution that exercises every visual
# branch: most-pulled, dup streak with holder, all-different streak, missed
# banners, first-random slug, every rarity tier.
cat >"$tmp/counts.txt" <<'COUNTS'
main 14
allucinato 13
photo 12
hair 4
rapput 3
notbisio 2
pate 1
duxio 1
__missed_banner 3
__dup_streak_longest 5
__dup_streak_slug main
__diff_streak_longest 4
__first_random_slug allucinato
__first_random_pull_n 2
COUNTS

dex='01:main|02:allucinato|03:rapput|04:pate|05:duxio|06:hair|07:notbisio|08:photo'
out="$repo_dir/assets/hof-demo.html"

_bisio_render_html \
  "Demo Bisio" \
  "$(date -u +%Y-%m-%d)" \
  50 \
  duxio \
  50 \
  5 \
  4 \
  "$dex" \
  "$repo_dir/assets/bisio" \
  "$tmp/counts.txt" \
  "4d 12h" >"$out"

printf 'Wrote %s\n' "$out"
