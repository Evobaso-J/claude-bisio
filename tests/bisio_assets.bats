#!/usr/bin/env bats
# Asset contract: every assets/bisio/NN-slug.png must be portrait or square
# (height >= width). Required by the side-mode layout in bin/banner.sh, which
# reserves rows from pw assuming a portrait aspect. Wide PNGs cause titles to
# render below the image instead of beside it.
# See: context/operations/OPERATIONS.md ("Adding a variant").

@test "every bisio asset is portrait or square (h >= w)" {
  shopt -s nullglob 2>/dev/null || true
  for png in "$BATS_TEST_DIRNAME"/../assets/bisio/[0-9][0-9]-*.png; do
    [ -f "$png" ] || continue
    bytes=$(od -An -tx1 -N 8 -j 16 "$png" | tr -d ' \n')
    [ "${#bytes}" -eq 16 ] || { echo "$png: cannot read IHDR"; return 1; }
    w=$(printf '%d' "0x${bytes%????????}")
    h=$(printf '%d' "0x${bytes#????????}")
    if [ "$h" -lt "$w" ]; then
      echo "$png: ${w}x${h} (h<w) — must be portrait or square"
      return 1
    fi
  done
}

# Tightness contract: chafa fits the whole canvas into the cell box, so any
# transparent left/right padding shrinks the visible figure. Vertical pad to
# square is fine (canonical fix for naturally landscape source art); only
# horizontal alpha padding is disallowed. Detected by full-bbox trim and
# comparing widths only — vertical trim is ignored.
@test "no horizontal alpha padding on bisio variants" {
  if command -v magick >/dev/null 2>&1; then
    im_id() { magick identify -format "$1" "$2"; }
    im_trim_w() { magick "$1" -trim +repage -format '%w' info:; }
  elif command -v identify >/dev/null 2>&1 && command -v convert >/dev/null 2>&1; then
    im_id() { identify -format "$1" "$2"; }
    im_trim_w() { convert "$1" -trim +repage -format '%w' info:; }
  else
    skip "imagemagick not installed"
  fi
  shopt -s nullglob 2>/dev/null || true
  for png in "$BATS_TEST_DIRNAME"/../assets/bisio/[0-9][0-9]-*.png; do
    [ -f "$png" ] || continue
    orig_w=$(im_id '%w' "$png")
    trim_w=$(im_trim_w "$png")
    if [ "$orig_w" != "$trim_w" ]; then
      echo "$png: width ${orig_w}→${trim_w} after alpha trim — has transparent left/right padding. Run bin/trim-bisios.sh on it."
      return 1
    fi
  done
}
