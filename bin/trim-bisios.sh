#!/bin/sh
# shellcheck shell=sh
# Bring a bisio PNG into compliance with the two contracts in
# tests/bisio_assets.bats:
#   1. height >= width (aspect contract)
#   2. no horizontal alpha padding (tightness contract — chafa scales the
#      whole canvas, so transparent left/right columns shrink the figure)
#
# Strategy: detect non-conformance via the alpha bbox; if a horizontal pad
# exists, crop only the left/right transparent columns (vertical pad is
# allowed and is left untouched). Then, if the result is wider than tall,
# pad to square so the aspect contract still holds. Files that already
# conform are skipped with no rewrite — idempotent at the byte level.
#
# Requires ImageMagick. Prefers v7 `magick`; falls back to v6 `convert`/`identify`.
# Usage: bin/trim-bisios.sh assets/bisio/NN-slug.png [more.png...]
set -eu

if command -v magick >/dev/null 2>&1; then
  im_convert() { magick "$@"; }
  im_identify() { magick identify "$@"; }
elif command -v convert >/dev/null 2>&1 && command -v identify >/dev/null 2>&1; then
  im_convert() { convert "$@"; }
  im_identify() { identify "$@"; }
else
  echo "trim-bisios: imagemagick required" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <png>..." >&2
  exit 2
fi

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "skip: $f (not a file)" >&2
    continue
  fi

  orig_dims=$(im_identify -format '%w %h' "$f")
  orig_w=${orig_dims% *}
  orig_h=${orig_dims#* }

  geom=$(im_identify -format '%@' "$f")
  bbox_w=${geom%%x*}
  rest=${geom#*x}
  bbox_h=${rest%%+*}
  rest=${rest#*+}
  x_off=${rest%%+*}

  has_h_pad=0
  [ "$bbox_w" != "$orig_w" ] && has_h_pad=1
  needs_v_pad=0
  [ "$orig_h" -lt "$orig_w" ] && needs_v_pad=1

  if [ "$has_h_pad" -eq 0 ] && [ "$needs_v_pad" -eq 0 ]; then
    echo "ok: $f -> ${orig_w}x${orig_h} (already conforms)"
    continue
  fi

  tmp=$(mktemp -t trim-bisios.XXXXXX) || exit 1
  mv "$tmp" "$tmp.png"
  tmp="$tmp.png"

  if [ "$has_h_pad" -eq 1 ]; then
    im_convert "$f" -crop "${bbox_w}x${orig_h}+${x_off}+0" +repage "$tmp"
    new_w=$bbox_w
    new_h=$orig_h
  else
    cp "$f" "$tmp"
    new_w=$orig_w
    new_h=$orig_h
  fi

  if [ "$new_w" -gt "$new_h" ]; then
    im_convert "$tmp" -gravity center -background none -extent "${new_w}x${new_w}" "$f"
    echo "trim: $f -> ${new_w}x${new_w} (horizontal trim + vertical pad)"
  else
    mv "$tmp" "$f"
    tmp=
    echo "trim: $f -> ${new_w}x${new_h} (horizontal trim)"
  fi
  [ -n "$tmp" ] && rm -f "$tmp"

  # Suppress unused-warning on bbox_h — kept for future readability of geom parse.
  : "$bbox_h"
done
