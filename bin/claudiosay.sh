#!/bin/sh
# claudiosay: cowsay-style speech bubble next to a Claudio Bisio portrait.
# POSIX sh. Reads text from arguments or stdin, picks a portrait via the
# shared weighted-random picker, renders it small via chafa, and splices a
# bubble alongside with a "<-" tail pointing at Bisio.

set -u

repo_dir="${CLAUDE_BISIO_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
assets_dir="$repo_dir/assets"
bisio_dir="$assets_dir/bisio"
fallback_txt="$assets_dir/bisio-fallback.txt"

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

# --- pick portrait + render via chafa (with same cache scheme as banner.sh) ---
png=""
if command -v bisio_pick_portrait >/dev/null 2>&1; then
  png=$(bisio_pick_portrait "$bisio_dir")
fi

: > "$tmp_portrait"
if [ -n "$png" ] && [ -f "$png" ] && command -v chafa >/dev/null 2>&1; then
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
    mkdir -p "$cache_dir" 2>/dev/null
    if ! chafa --size "${pw}x${ph}" "$@" "$png" > "$cache_file" 2>/dev/null; then
      rm -f "$cache_file"
      cache_file=""
    fi
  fi
  [ -n "$cache_file" ] && [ -f "$cache_file" ] && cp "$cache_file" "$tmp_portrait"
fi

# --- fallback when chafa missing or render failed: clip the static fallback ---
if [ ! -s "$tmp_portrait" ] && [ -f "$fallback_txt" ]; then
  awk -v rows="$ph" -v w="$pw" '
    NR<=rows { line=$0; if (length(line)>w) line=substr(line,1,w); print line }
  ' "$fallback_txt" > "$tmp_portrait"
fi

# --- build bubble ---
printf '%s' "$msg" | fold -s -w "$bw" > "$tmp_raw"
body_lines=$(awk 'END{print NR}' "$tmp_raw")
[ "$body_lines" -ge 1 ] || body_lines=1

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
awk -v gutter="$gutter" -v bubble_h="$bubble_h" '
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
      printf "%s\033[0m%s%s%s\n", pl, sep, tail, bl
    }
  }
' "$tmp_portrait" "$tmp_bubble"

printf '\n'
exit 0
