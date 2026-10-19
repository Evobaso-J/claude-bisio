#!/bin/sh
# shellcheck shell=sh
# Build a review sheet for candidate bisio PNGs: one row per input, the source
# image on the left and its chafa render (same flags as the banner) on the
# right, so a candidate can be judged on how it actually looks in a terminal.
#
# Requires chafa, ImageMagick v7 (`magick`) and python3. Dev helper only; the
# plugin itself never calls this.
# Usage: bin/preview-bisio.sh OUT.png IN.png [more.png...]
#        bin/preview-bisio.sh --chafa OUT.png IN.png   chafa render only
#   PREVIEW_SIZE=WxH  chafa cell grid (default 40x40)
set -eu

chafa_only=0
[ "${1:-}" = "--chafa" ] && { chafa_only=1; shift; }
if [ "$#" -lt 2 ]; then
  echo "usage: bin/preview-bisio.sh [--chafa] OUT.png IN.png [more.png...]" >&2
  exit 1
fi
for _t in chafa magick python3; do
  command -v "$_t" >/dev/null 2>&1 || { echo "preview-bisio: $_t required" >&2; exit 1; }
done

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=bin/banner.config.sh
. "$repo_dir/bin/banner.config.sh"
font=${PREVIEW_FONT:-/System/Library/Fonts/Menlo.ttc}
out=$1
shift

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Banner preset, but format forced to symbols (the last --format wins):
# sixel/kitty output can't be rasterized below.
set_chafa_args() {
  # shellcheck source=bin/_chafa_args.sh
  . "$repo_dir/bin/_chafa_args.sh"
  chafa_args="$* --format symbols"
}

# ANSI (SGR 38;5 / 38;2 fg, CSI nC skips) -> ImageMagick draw commands.
ansi_to_mvg() {
  python3 -c '
import re, sys
CW, CH = 8, 16
# Block elements (U+2580..259F) as exact cell fractions (x0, y0, x1, y1): font
# glyphs leave gaps between rows. Anything else falls back to font text.
Q = {"ul": (0,0,.5,.5), "ur": (.5,0,1,.5), "ll": (0,.5,.5,1), "lr": (.5,.5,1,1)}
BLK = {0x2580: [(0,0,1,.5)], 0x2588: [(0,0,1,1)], 0x2590: [(.5,0,1,1)],
       0x2591: [(0,0,1,1)], 0x2592: [(0,0,1,1)], 0x2593: [(0,0,1,1)],
       0x2594: [(0,0,1,1/8)], 0x2595: [(7/8,0,1,1)]}
for k in range(1, 8):
    BLK[0x2580 + k] = [(0, 1 - k/8, 1, 1)]
    BLK[0x2590 - k] = [(0, 0, k/8, 1)]
for cp, qs in zip(range(0x2596, 0x25A0), ["ll", "lr", "ul", "ul ll lr", "ul lr", "ul ur ll", "ul ur lr", "ur", "ur ll", "ur ll lr"]):
    BLK[cp] = [Q[q] for q in qs.split()]
def c256(n):
    if n < 16:
        base = [(0,0,0),(205,0,0),(0,205,0),(205,205,0),(0,0,238),(205,0,205),(0,205,205),(229,229,229),
                (127,127,127),(255,0,0),(0,255,0),(255,255,0),(92,92,255),(255,0,255),(0,255,255),(255,255,255)]
        return base[n]
    if n < 232:
        n -= 16
        lv = [0,95,135,175,215,255]
        return (lv[n//36], lv[n//6%6], lv[n%6])
    v = 8 + (n-232)*10
    return (v, v, v)
fg = (229,229,229)
out = []
cols = 0
for y, line in enumerate(sys.stdin.read().splitlines()):
    x = 0
    for m in re.finditer(r"\x1b\[([0-9;?]*)([A-Za-z])|([^\x1b])", line):
        if m.group(3):
            ch = m.group(3)
            col = "fill \"#%02x%02x%02x\"" % fg
            if ord(ch) in BLK:
                for x0, y0, x1, y1 in BLK[ord(ch)]:
                    out.append("%s rectangle %g,%g %g,%g" % (col, (x+x0)*CW, (y+y0)*CH, (x+x1)*CW - 1e-3, (y+y1)*CH - 1e-3))
            elif ch != " ":
                out.append("%s text %d,%d \"%s\"" % (col, x*CW, y*CH + 12, ch))
            x += 1
        elif m.group(2) == "C":
            x += int(m.group(1) or 1)
        elif m.group(2) == "m":
            p = [int(v) for v in m.group(1).split(";") if v.isdigit()] or [0]
            if p[:2] == [38, 5]: fg = c256(p[2])
            elif p[:2] == [38, 2]: fg = tuple(p[2:5])
            elif p[0] in (0, 39): fg = (229,229,229)
    cols = max(cols, x)
    rows = y + 1
print("viewbox 0 0 %d %d" % (cols*CW, rows*CH))
print("\n".join(out))
'
}

set_chafa_args
i=0
for png in "$@"; do
  i=$((i + 1))
  # shellcheck disable=SC2086 # chafa_args is a deliberate word-split flag list
  chafa --size "${PREVIEW_SIZE:-40x40}" $chafa_args "$png" | ansi_to_mvg > "$tmp/$i.mvg"
  geom=$(sed -n '1s/^viewbox 0 0 //p' "$tmp/$i.mvg" | tr ' ' x)
  magick -size "$geom" xc:'#1e1e1e' -font "$font" -pointsize 13 -draw "@$tmp/$i.mvg" "$tmp/$i-chafa.png"
  [ "$chafa_only" -eq 1 ] && { mv "$tmp/$i-chafa.png" "$out"; echo "$out"; exit 0; }
  h=${geom#*x}
  magick "$png" -background '#808080' -alpha remove -resize "x$h" "$tmp/$i-src.png"
  magick "$tmp/$i-src.png" "$tmp/$i-chafa.png" -background '#1e1e1e' -splice 16x0 +append \
    -gravity North -splice 0x28 -font "$font" -fill white -pointsize 18 -annotate +0+4 "$(basename "$(dirname "$png")")/$(basename "$png")" "$tmp/row-$(printf %03d "$i").png"
done
magick "$tmp"/row-*.png -background '#1e1e1e' -append "$out"
echo "$out"
