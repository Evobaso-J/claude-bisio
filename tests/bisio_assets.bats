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
