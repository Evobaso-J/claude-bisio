#!/bin/sh
# claudiosay: cowsay-style speech bubble next to a Claudio Bisio portrait.
# POSIX sh. Reads text from arguments or stdin, picks a portrait via the
# shared weighted-random picker, renders it small via chafa, and splices a
# bubble alongside with a "<-" tail pointing at Bisio.

set -u

repo_dir="${CLAUDE_BISIO_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
assets_dir="$repo_dir/assets"
bisio_dir="$assets_dir/bisio"

config_file="$repo_dir/bin/banner.config.sh"
# shellcheck source=bin/banner.config.sh
[ -f "$config_file" ] && . "$config_file"
picker="$repo_dir/bin/_pick_portrait.sh"
# shellcheck source=bin/_pick_portrait.sh
[ -f "$picker" ] && . "$picker"

# --- input: $@ wins over stdin; require something ---
if [ "$#" -gt 0 ]; then
  msg=$*
elif [ ! -t 0 ]; then
  msg=$(cat)
else
  printf 'usage: claudiosay <text>  |  echo text | claudiosay\n' >&2
  exit 1
fi
[ -n "$msg" ] || { printf 'claudiosay: empty message\n' >&2; exit 1; }

# --- terminal size (fallback 80) ---
size=$( (stty size < /dev/tty) 2>/dev/null )
cols=80
if [ -n "$size" ]; then
  c=${size#* }
  case "$c" in *[!0-9]*) ;; *) cols=$c ;; esac
fi
[ "$cols" -lt 30 ] && cols=30

# --- sizing ---
# Portrait: small fixed band — 12 to 24 cols, ~1/3 of viewport.
pw=$(( cols / 3 ))
[ "$pw" -gt 24 ] && pw=24
[ "$pw" -lt 12 ] && pw=12
ph=$(( pw * 6 / 10 ))
[ "$ph" -lt 6 ] && ph=6

gutter=2
arrow_w=3   # "<- " or "   "
# Bubble inner-text width = remaining cols after portrait + gutter + arrow + "| " + " |".
bw=$(( cols - pw - gutter - arrow_w - 4 ))
[ "$bw" -gt 56 ] && bw=56
[ "$bw" -lt 8 ]  && bw=8

# --- temp files ---
tmp_portrait="${TMPDIR:-/tmp}/claudiosay-portrait.$$"
tmp_bubble="${TMPDIR:-/tmp}/claudiosay-bubble.$$"
tmp_raw="${TMPDIR:-/tmp}/claudiosay-raw.$$"
trap 'rm -f "$tmp_portrait" "$tmp_bubble" "$tmp_raw"' EXIT INT TERM

# --- pick portrait ---
# Gate: until the user reaches the Hall of Fame, claudiosay is locked to main
# so rare variants stay a banner-only discovery. CLAUDE_BISIO_NO_COUNTER
# users opted out of the dex game — give them random as before.
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio"
hof_file="$state_dir/hall-of-fame.html"
png=""
if [ "${CLAUDE_BISIO_NO_COUNTER:-}" != "1" ] && [ ! -f "$hof_file" ]; then
  for _f in "$bisio_dir"/[0-9][0-9]-main.png; do
    [ -f "$_f" ] && png=$_f && break
  done
fi
if [ -z "$png" ] && command -v bisio_pick_portrait >/dev/null 2>&1; then
  png=$(bisio_pick_portrait "$bisio_dir")
fi

# --- render via chafa (with same cache scheme as banner.sh) ---
# chafa is mandatory. Missing chafa, missing PNG, or render failure aborts.
command -v chafa >/dev/null 2>&1 || { printf 'claudiosay: chafa not found\n' >&2; exit 1; }
[ -n "$png" ] && [ -f "$png" ]    || { printf 'claudiosay: no portrait found\n' >&2; exit 1; }

set --
[ -n "${CHAFA_SYMBOLS:-}" ]           && set -- "$@" --symbols "$CHAFA_SYMBOLS"
[ -n "${CHAFA_COLORS:-}" ]            && set -- "$@" --colors "$CHAFA_COLORS"
[ -n "${CHAFA_FORMAT:-}" ]            && set -- "$@" --format "$CHAFA_FORMAT"
[ "${CHAFA_FG_ONLY:-}" = "yes" ]      && set -- "$@" --fg-only
[ -n "${CHAFA_DITHER:-}" ]            && set -- "$@" --dither "$CHAFA_DITHER"
[ -n "${CHAFA_DITHER_GRAIN:-}" ]      && set -- "$@" --dither-grain "$CHAFA_DITHER_GRAIN"
[ -n "${CHAFA_DITHER_INTENSITY:-}" ]  && set -- "$@" --dither-intensity "$CHAFA_DITHER_INTENSITY"
[ "${CHAFA_INVERT:-}" = "yes" ]       && set -- "$@" --invert
[ -n "${CHAFA_THRESHOLD:-}" ]         && set -- "$@" --threshold "$CHAFA_THRESHOLD"
[ -n "${CHAFA_FONT_RATIO:-}" ]        && set -- "$@" --font-ratio "$CHAFA_FONT_RATIO"
[ -n "${CHAFA_EXTRA:-}" ] && eval "set -- \"\$@\" $CHAFA_EXTRA"

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/claude-bisio"
if command -v shasum >/dev/null 2>&1; then
  png_sha=$(shasum -a 256 "$png" 2>/dev/null | cut -c1-8)
  flags_sha=$(printf '%s' "$*" | shasum -a 256 | cut -c1-8)
elif command -v sha256sum >/dev/null 2>&1; then
  png_sha=$(sha256sum "$png" 2>/dev/null | cut -c1-8)
  flags_sha=$(printf '%s' "$*" | sha256sum | cut -c1-8)
else
  png_sha=nosha; flags_sha=nosha
fi
[ -n "$png_sha" ]   || png_sha=nosha
[ -n "$flags_sha" ] || flags_sha=nosha
cache_dir="$cache_root/v1-${png_sha}-${flags_sha}"
cache_file="$cache_dir/${pw}x${ph}.ans"
if [ ! -f "$cache_file" ]; then
  mkdir -p "$cache_dir" 2>/dev/null || { printf 'claudiosay: cannot create cache dir\n' >&2; exit 1; }
  if ! chafa --size "${pw}x${ph}" "$@" "$png" > "$cache_file" 2>/dev/null; then
    rm -f "$cache_file"
    printf 'claudiosay: chafa render failed\n' >&2
    exit 1
  fi
fi
cp "$cache_file" "$tmp_portrait"

# --- build bubble ---
printf '%s' "$msg" | fold -s -w "$bw" > "$tmp_raw"
body_lines=$(awk 'END{print NR}' "$tmp_raw")
[ "$body_lines" -ge 1 ] || body_lines=1

# Shrink bubble to widest wrapped line — cowsay-style fit, no trailing whitespace.
max_w=$(awk '{ if (length>m) m=length } END { print m+0 }' "$tmp_raw")
[ "$max_w" -ge 1 ] || max_w=1
[ "$max_w" -lt "$bw" ] && bw=$max_w

{
  # top border:  .---<bw+2>---.
  printf '.'
  i=0; while [ "$i" -lt "$(( bw + 2 ))" ]; do printf '-'; i=$((i+1)); done
  printf '.\n'
  # body lines, left-aligned, padded to bw
  awk -v w="$bw" '{ printf "| %-*s |\n", w, $0 }' "$tmp_raw"
  # bottom border
  printf "'"
  i=0; while [ "$i" -lt "$(( bw + 2 ))" ]; do printf '-'; i=$((i+1)); done
  printf "'\n"
} > "$tmp_bubble"

bubble_h=$(( body_lines + 2 ))

# --- splice portrait + bubble side-by-side, with cowsay-style "/" tail ---
# Bubble sits at top; below the bubble two "/" chars trail diagonally
# down-left toward the portrait, mirroring cowsay's "\" tail.
# Pad each portrait slot to pw bytes so the bubble stays column-aligned
# even when it overflows past the portrait's last row. Chafa lines are
# already much longer than pw bytes (ANSI escapes), so %-*s is a no-op
# for them; empty rows get space-padded to pw.
awk -v gutter="$gutter" -v bubble_h="$bubble_h" -v pw="$pw" '
  NR==FNR { p[FNR]=$0; np=FNR; next }
  { b[FNR]=$0; nb=FNR }
  END {
    sep = ""
    for (i = 0; i < gutter; i++) sep = sep " "
    total = (np > nb) ? np : nb
    for (i = 1; i <= total; i++) {
      pl = (i <= np) ? p[i] : ""
      bl = (i <= nb) ? b[i] : ""
      if (i == bubble_h + 1 && i <= np)      tail = "  /"
      else if (i == bubble_h + 2 && i <= np) tail = " / "
      else                                   tail = "   "
      printf "%-*s\033[0m%s%s%s\n", pw, pl, sep, tail, bl
    }
  }
' "$tmp_portrait" "$tmp_bubble"

printf '\n'
exit 0
