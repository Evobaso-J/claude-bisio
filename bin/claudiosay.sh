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

# --- terminal size (fallback 80x24) ---
size=$( (stty size < /dev/tty) 2>/dev/null )
cols=80
rows=24
if [ -n "$size" ]; then
  r=${size% *}
  c=${size#* }
  case "$r" in *[!0-9]*) ;; *) rows=$r ;; esac
  case "$c" in *[!0-9]*) ;; *) cols=$c ;; esac
fi
[ "$cols" -lt 30 ] && cols=30
[ "$rows" -lt 8 ]  && rows=8

# --- sizing ---
# Mirror banner.sh's viewport model: subtract margin + reserve for Claude's
# welcome box, cap height via CLAUDE_BISIO_MAX_HEIGHT, scale via 0.6 cell aspect.
margin=2
reserve=${CLAUDE_BISIO_RESERVE:-4}
case "$reserve" in *[!0-9]*) reserve=4 ;; esac
avail_rows=$(( rows - margin - reserve ))
[ "$avail_rows" -lt 6 ] && avail_rows=6

max_ph=${CLAUDE_BISIO_MAX_HEIGHT:-40}
case "$max_ph" in *[!0-9]*) max_ph=40 ;; esac
[ "$max_ph" -lt 6 ] && max_ph=6

gutter=2
arrow_w=3      # "<- " or "   "
borders_w=4    # "| " + " |"
min_bw=20      # smallest readable bubble before we squeeze the portrait

# Portrait width budget: limited by remaining cols after bubble AND by avail rows via aspect.
pw_by_cols=$(( cols - min_bw - gutter - arrow_w - borders_w ))
pw_by_rows=$(( avail_rows * 10 / 6 ))
pw=$pw_by_cols
[ "$pw_by_rows" -lt "$pw" ] && pw=$pw_by_rows

# Apply max-height cap (via aspect: ph = pw * 6/10, so pw <= max_ph * 10/6).
max_pw=$(( max_ph * 10 / 6 ))
[ "$pw" -gt "$max_pw" ] && pw=$max_pw
[ "$pw" -lt 12 ] && pw=12

ph=$(( pw * 6 / 10 ))
[ "$ph" -gt "$max_ph" ]    && ph=$max_ph
[ "$ph" -gt "$avail_rows" ] && ph=$avail_rows
[ "$ph" -lt 6 ] && ph=6

# Bubble inner-text width: take whatever cols remain after the portrait.
bw=$(( cols - pw - gutter - arrow_w - borders_w ))
[ "$bw" -gt 80 ] && bw=80
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
portrait_h=$(awk 'END{print NR}' "$tmp_portrait")
[ "$portrait_h" -ge 0 ] || portrait_h=0

# Vertically center the bubble against the portrait (when portrait is taller).
pad_top=0
diff=$(( portrait_h - bubble_h ))
if [ "$diff" -gt 0 ]; then
  pad_top=$(( diff / 2 ))
  padded="${TMPDIR:-/tmp}/claudiosay-padded.$$"
  : > "$padded"
  i=0; while [ "$i" -lt "$pad_top" ]; do printf '\n' >> "$padded"; i=$((i+1)); done
  cat "$tmp_bubble" >> "$padded"
  mv "$padded" "$tmp_bubble"
fi

# Arrow row in the spliced output: top-pad + top-border + middle-of-text-rows.
arrow_row=$(( pad_top + 2 + body_lines / 2 ))

# --- splice portrait + bubble side-by-side, inject "<- " at arrow row ---
awk -v gutter="$gutter" -v arrow_row="$arrow_row" '
  NR==FNR { p[FNR]=$0; np=FNR; next }
  {
    line = (FNR <= np) ? p[FNR] : ""
    sep = ""
    for (i=0; i<gutter; i++) sep = sep " "
    arrow = (FNR == arrow_row) ? "<- " : "   "
    printf "%s\033[0m%s%s%s\n", line, sep, arrow, $0
  }
  END {
    if (np > FNR) {
      for (i = FNR+1; i <= np; i++) print p[i] "\033[0m"
    }
  }
' "$tmp_portrait" "$tmp_bubble"

printf '\n'
exit 0
