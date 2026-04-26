#!/bin/sh
# claude-bisio banner core. POSIX sh.
# Renders a viewport-fit Bisio portrait via chafa, with composed figlet titles.
# Falls back to a static heredoc if chafa is missing.

set -u

repo_dir="${CLAUDE_BISIO_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
assets_dir="$repo_dir/assets"
bisio_dir="$assets_dir/bisio"
fallback_txt="$assets_dir/bisio-fallback.txt"
title_cc="$assets_dir/title-claude-code.txt"
title_bisio="$assets_dir/title-bisio.txt"

config_file="$repo_dir/bin/banner.config.sh"
[ -f "$config_file" ] && . "$config_file"

picker="$repo_dir/bin/_pick_portrait.sh"
# shellcheck source=bin/_pick_portrait.sh
[ -f "$picker" ] && . "$picker"

counter="$repo_dir/bin/_counter.sh"
# shellcheck source=bin/_counter.sh
[ -f "$counter" ] && . "$counter"

# --- pick a portrait from $bisio_dir/*.png ---
png=""
if command -v bisio_pick_portrait >/dev/null 2>&1; then
  png=$(bisio_pick_portrait "$bisio_dir")
fi

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/claude-bisio"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio"
hint_sentinel="$state_root/hint-shown"
first_sentinel="$state_root/first-shown"

# First-ever banner show: force main.png so the user meets the canonical Bisio
# before the weighted-random roulette kicks in on subsequent launches.
if [ ! -f "$first_sentinel" ] && [ -f "$bisio_dir/main.png" ]; then
  png="$bisio_dir/main.png"
fi

# Record a missed banner call when we bail before rendering due to terminal
# constraints. Counter is sourced above; guard for the opt-out path.
_bisio_miss_and_exit() {
  command -v bisio_record_miss >/dev/null 2>&1 && bisio_record_miss
  exit 0
}

# --- terminal size (subshell swallows /dev/tty open errors per LEARNINGS §7) ---
size=$( (stty size < /dev/tty) 2>/dev/null )
[ -n "$size" ] || _bisio_miss_and_exit
rows=${size% *}
cols=${size#* }
case "$rows$cols" in *[!0-9]*) _bisio_miss_and_exit ;; esac
[ "$cols" -ge 30 ] && [ "$rows" -ge 8 ] || _bisio_miss_and_exit

# --- helpers ---
detect_install_cmd() {
  # macOS has its own /usr/bin/apt (Java tool, not the Debian one) - anchor on uname.
  os=$(uname -s 2>/dev/null)
  case "$os" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        printf 'brew install chafa'
        return
      fi
      printf 'brew install chafa  (install Homebrew first: https://brew.sh)'
      return
      ;;
    Linux|*BSD)
      if command -v brew >/dev/null 2>&1; then
        printf 'brew install chafa'
      elif command -v apt-get >/dev/null 2>&1; then
        printf 'sudo apt-get install chafa'
      elif command -v dnf >/dev/null 2>&1; then
        printf 'sudo dnf install chafa'
      elif command -v pacman >/dev/null 2>&1; then
        printf 'sudo pacman -S chafa'
      elif command -v zypper >/dev/null 2>&1; then
        printf 'sudo zypper install chafa'
      elif command -v apk >/dev/null 2>&1; then
        printf 'sudo apk add chafa'
      else
        printf "install 'chafa' via your package manager"
      fi
      return
      ;;
  esac
  # Windows (msys/cygwin/git-bash) and other
  if command -v choco >/dev/null 2>&1; then
    printf 'choco install chafa'
  elif command -v scoop >/dev/null 2>&1; then
    printf 'scoop install chafa'
  elif command -v winget >/dev/null 2>&1; then
    printf 'winget install chafa'
  else
    printf "install 'chafa' via your package manager"
  fi
}

print_hint_once() {
  [ -f "$hint_sentinel" ] && return 0
  mkdir -p "$state_root" 2>/dev/null || return 0
  cmd=$(detect_install_cmd)
  printf '[claude-bisio] chafa not found - install for viewport-fit: %s\n\n' "$cmd"
  : > "$hint_sentinel" 2>/dev/null || true
}

show_fallback() {
  [ -f "$fallback_txt" ] && cat "$fallback_txt"
  printf '\n'
}

# Visual width of the Bisiodex body string (no ANSI).
# Layout: optional "New Bisio discovered: <slug>!   " (26 + slug) + bar (10) + "  " (2) + "C/T".
# Counter is always rightmost.
bisio_dex_body_width() {
  _bdw_caught=$1
  _bdw_total=$2
  _bdw_new=$3
  _bdw_latest=$4
  _bdw_count="${_bdw_caught}/${_bdw_total}"
  _bdw=$(( 12 + ${#_bdw_count} ))
  [ "$_bdw_new" = "1" ] && _bdw=$(( _bdw + 26 + ${#_bdw_latest} ))
  printf '%s\n' "$_bdw"
}

# Print one Bisiodex status line (left-padded by $5) with trailing newline.
# Bar is 10 segments. Color from CLAUDE_BISIO_DEX_COLOR or _NEW_COLOR.
bisio_render_dex_line() {
  _drl_caught=$1
  _drl_total=$2
  _drl_new=$3
  _drl_latest=$4
  _drl_pad=${5:-0}

  _drl_filled=${CLAUDE_BISIO_DEX_FILLED:-▰}
  _drl_empty=${CLAUDE_BISIO_DEX_EMPTY:-▱}
  _drl_color=${CLAUDE_BISIO_DEX_COLOR:-1;96}
  _drl_newcolor=${CLAUDE_BISIO_DEX_NEW_COLOR:-1;93}

  if [ "$_drl_total" -le 0 ] 2>/dev/null; then
    _drl_segs=0
  else
    _drl_segs=$(( (_drl_caught * 10 + _drl_total / 2) / _drl_total ))
    [ "$_drl_segs" -gt 10 ] && _drl_segs=10
    [ "$_drl_segs" -lt 0 ] && _drl_segs=0
    # Show ≥1 filled if anything caught; never full unless actually full.
    [ "$_drl_caught" -gt 0 ] && [ "$_drl_segs" -eq 0 ] && _drl_segs=1
    [ "$_drl_caught" -lt "$_drl_total" ] && [ "$_drl_segs" -ge 10 ] && _drl_segs=9
  fi

  _drl_bar=""
  _drl_i=0
  while [ "$_drl_i" -lt "$_drl_segs" ]; do
    _drl_bar="${_drl_bar}${_drl_filled}"
    _drl_i=$(( _drl_i + 1 ))
  done
  while [ "$_drl_i" -lt 10 ]; do
    _drl_bar="${_drl_bar}${_drl_empty}"
    _drl_i=$(( _drl_i + 1 ))
  done

  if [ "$_drl_new" = "1" ]; then
    _drl_active=$_drl_newcolor
    _drl_prefix=$(printf 'New Bisio discovered: %s!   ' "$_drl_latest")
  else
    _drl_active=$_drl_color
    _drl_prefix=""
  fi

  printf '%*s\033[%sm%s%s  %d/%d\033[0m\n' \
    "$_drl_pad" '' "$_drl_active" \
    "$_drl_prefix" "$_drl_bar" "$_drl_caught" "$_drl_total"
}

# --- chafa missing path ---
if ! command -v chafa >/dev/null 2>&1; then
  print_hint_once
  show_fallback
  exit 0
fi

[ -f "$png" ] || { show_fallback; exit 0; }

# --- PNG sha for cache key ---
if command -v shasum >/dev/null 2>&1; then
  png_sha=$(shasum -a 256 "$png" 2>/dev/null | cut -c1-8)
elif command -v sha256sum >/dev/null 2>&1; then
  png_sha=$(sha256sum "$png" 2>/dev/null | cut -c1-8)
else
  png_sha=nosha
fi
[ -n "$png_sha" ] || png_sha=nosha

# --- chafa args from config ---
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
# CHAFA_EXTRA: deliberate word-split via eval - free-form flag string
[ -n "${CHAFA_EXTRA:-}" ] && eval "set -- \"\$@\" $CHAFA_EXTRA"

flags_str="$*"
if command -v shasum >/dev/null 2>&1; then
  flags_sha=$(printf '%s' "$flags_str" | shasum -a 256 | cut -c1-8)
elif command -v sha256sum >/dev/null 2>&1; then
  flags_sha=$(printf '%s' "$flags_str" | sha256sum | cut -c1-8)
else
  flags_sha=nosha
fi
[ -n "$flags_sha" ] || flags_sha=nosha
cache_dir="$cache_root/v1-${png_sha}-${flags_sha}"

# --- title block measurements ---
title_cc_rows=$(awk 'END{print NR}' "$title_cc")
title_bisio_rows=$(awk 'END{print NR}' "$title_bisio")
title_cc_w=$(awk '{ if (length>m) m=length } END { print m+0 }' "$title_cc")
title_bisio_w=$(awk '{ if (length>m) m=length } END { print m+0 }' "$title_bisio")
title_w=$title_cc_w
[ "$title_bisio_w" -gt "$title_w" ] && title_w=$title_bisio_w
title_h=$(( title_cc_rows + 2 + title_bisio_rows ))

# --- continuous layout algorithm ---
# Cell aspect: portrait W cols → H ≈ W * 0.6 rows (PNG 456×547, cell 1:2).
margin=2
gutter=4
# Reserve rows for Claude's own welcome box + prompt that prints after the banner.
reserve=${CLAUDE_BISIO_RESERVE:-14}
case "$reserve" in *[!0-9]*) reserve=14 ;; esac
avail_rows=$(( rows - margin - reserve ))
[ "$avail_rows" -lt 1 ] && avail_rows=1

# Cap portrait rows so the image doesn't fill the whole viewport on tall terminals.
max_ph=${CLAUDE_BISIO_MAX_HEIGHT:-22}
case "$max_ph" in *[!0-9]*) max_ph=22 ;; esac
[ "$max_ph" -lt 1 ] && max_ph=1

layout=
pw=0
ph=0

# 1. side-by-side
side_w_by_cols=$(( cols - title_w - gutter ))
side_w_by_rows=$(( avail_rows * 10 / 6 ))
side_w=$side_w_by_cols
[ "$side_w_by_rows" -lt "$side_w" ] && side_w=$side_w_by_rows
if [ "$side_w" -ge 30 ] && [ "$avail_rows" -ge "$title_h" ]; then
  layout=side
  pw=$side_w
  ph=$(( pw * 6 / 10 ))
  [ "$ph" -lt "$title_h" ] && ph=$title_h
  [ "$ph" -gt "$avail_rows" ] && ph=$avail_rows
  if [ "$ph" -gt "$max_ph" ]; then
    ph=$max_ph
    new_pw=$(( ph * 10 / 6 ))
    [ "$new_pw" -lt "$pw" ] && pw=$new_pw
  fi
fi

# 2. stacked
if [ -z "$layout" ]; then
  stack_rows_avail=$(( avail_rows - title_h - 1 ))
  stack_w_by_rows=$(( stack_rows_avail * 10 / 6 ))
  stack_w=$cols
  [ "$stack_w_by_rows" -lt "$stack_w" ] && stack_w=$stack_w_by_rows
  if [ "$stack_w" -ge 40 ] && [ "$stack_rows_avail" -ge 24 ]; then
    layout=stacked
    pw=$stack_w
    ph=$(( pw * 6 / 10 ))
    [ "$ph" -gt "$stack_rows_avail" ] && ph=$stack_rows_avail
    if [ "$ph" -gt "$max_ph" ]; then
      ph=$max_ph
      new_pw=$(( ph * 10 / 6 ))
      [ "$new_pw" -lt "$pw" ] && pw=$new_pw
    fi
  fi
fi

# 3. portrait-only
if [ -z "$layout" ]; then
  solo_w_by_rows=$(( avail_rows * 10 / 6 ))
  solo_w=$cols
  [ "$solo_w_by_rows" -lt "$solo_w" ] && solo_w=$solo_w_by_rows
  if [ "$solo_w" -ge 30 ]; then
    layout=solo
    pw=$solo_w
    ph=$(( pw * 6 / 10 ))
    [ "$ph" -gt "$avail_rows" ] && ph=$avail_rows
    if [ "$ph" -gt "$max_ph" ]; then
      ph=$max_ph
      new_pw=$(( ph * 10 / 6 ))
      [ "$new_pw" -lt "$pw" ] && pw=$new_pw
    fi
  fi
fi

[ -n "$layout" ] || _bisio_miss_and_exit

# --- render or cache hit ---
cache_file="$cache_dir/${pw}x${ph}.ans"
if [ ! -f "$cache_file" ]; then
  mkdir -p "$cache_dir" 2>/dev/null || { show_fallback; exit 0; }
  if ! chafa --size "${pw}x${ph}" "$@" "$png" > "$cache_file" 2>/dev/null; then
    rm -f "$cache_file"
    show_fallback
    exit 0
  fi
fi

# --- compose & print ---
# Blank line between the prompt/command and the banner.
printf '\n'
rendered=0
case "$layout" in
  solo)
    cat "$cache_file"
    bisio_back=2
    rendered=1
    ;;
  stacked)
    cat "$cache_file"
    printf '\n'
    title_color=${CLAUDE_BISIO_TITLE_COLOR:-1;38;2;217;119;87}
    # Center title under portrait of width pw.
    pad=$(( (pw - title_cc_w) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    awk -v p="$pad" -v c="$title_color" \
      'BEGIN{ for(i=0;i<p;i++) s=s" " } { printf "%s\033[%sm%s\033[0m\n", s, c, $0 }' \
      "$title_cc"
    printf '\n'
    pad_b=$(( (pw - title_bisio_w) / 2 ))
    [ "$pad_b" -lt 0 ] && pad_b=0
    awk -v p="$pad_b" -v c="$title_color" \
      'BEGIN{ for(i=0;i<p;i++) s=s" " } { printf "%s\033[%sm%s\033[0m\n", s, c, $0 }' \
      "$title_bisio"
    bisio_back=1
    rendered=1
    ;;
  side)
    titles_tmp=$(mktemp 2>/dev/null) || titles_tmp="${TMPDIR:-/tmp}/claude-bisio-titles.$$"
    # Use actual cache_file row count: chafa can emit fewer rows than requested
    # for some aspect ratios. v_offset based on requested ph would push titles
    # past portrait bottom, where they'd render at column 0 (line="" branch).
    actual_ph=$(awk 'END{print NR}' "$cache_file")
    v_offset=$(( (actual_ph - title_h) / 2 ))
    [ "$v_offset" -lt 0 ] && v_offset=0
    {
      _i=0
      while [ "$_i" -lt "$v_offset" ]; do printf '\n'; _i=$(( _i + 1 )); done
      cat "$title_cc"
      printf '\n\n'
      cat "$title_bisio"
    } > "$titles_tmp"

    title_color=${CLAUDE_BISIO_TITLE_COLOR:-1;38;2;217;119;87}
    # Vertically center titles against portrait via leading blank rows in
    # titles_tmp. Image taller than titles is fine — the awk paste below
    # leaves the right column blank for trailing rows. Title content is
    # wrapped in $c…ESC[0m on non-empty rows; blank rows stay uncolored.
    awk -v gutter="$gutter" -v c="$title_color" '
      NR==FNR { p[FNR]=$0; np=FNR; next }
      {
        line = (FNR <= np) ? p[FNR] : ""
        sep = ""
        for (i=0; i<gutter; i++) sep = sep " "
        if ($0 != "") {
          printf "%s\033[0m%s\033[%sm%s\033[0m\n", line, sep, c, $0
        } else {
          printf "%s\033[0m%s\n", line, sep
        }
      }
      END {
        if (np > FNR) {
          for (i = FNR+1; i <= np; i++) print p[i] "\033[0m"
        }
      }
    ' "$cache_file" "$titles_tmp"

    rm -f "$titles_tmp"
    bisio_back=1
    rendered=1
    ;;
esac

# Record the pull only when something was actually shown.
if [ "$rendered" = "1" ] && command -v bisio_record_pull >/dev/null 2>&1; then
  pulled_slug=${png##*/}
  pulled_slug=${pulled_slug%.png}
  bisio_record_pull "$pulled_slug" "$rows" "$cols" "${bisio_back:-1}"
fi

# Bisiodex status line. Renders only when the counter populated dex vars
# (skipped on opt-out and on no-render fallback paths).
if [ "$rendered" = "1" ] && [ -n "${BISIO_DEX_TOTAL:-}" ]; then
  dex_w=$(bisio_dex_body_width \
    "${BISIO_DEX_CAUGHT:-0}" "${BISIO_DEX_TOTAL:-0}" \
    "${BISIO_DEX_NEW:-0}" "${BISIO_DEX_LATEST:-}")
  case "$layout" in
    solo)
      # No title block — center under image.
      dex_pad=$(( (pw - dex_w) / 2 ))
      ;;
    stacked)
      # Right-align the counter to the right edge of the widest title.
      # Titles are centered under image of width pw, so the widest title's
      # right edge sits at (pw + title_w)/2.
      dex_pad=$(( (pw + title_w) / 2 - dex_w ))
      ;;
    side)
      # Right-align the counter to the right edge of the widest title in
      # the right column. Right column starts at pw+gutter, widest title
      # ends at pw + gutter + title_w.
      dex_pad=$(( pw + gutter + title_w - dex_w ))
      ;;
    *)
      dex_pad=0
      ;;
  esac
  [ "$dex_pad" -lt 0 ] && dex_pad=0
  bisio_render_dex_line \
    "${BISIO_DEX_CAUGHT:-0}" "${BISIO_DEX_TOTAL:-0}" \
    "${BISIO_DEX_NEW:-0}" "${BISIO_DEX_LATEST:-}" \
    "$dex_pad"
fi

# Hall of Fame celebration. Fires only on the launch where the counter just
# crossed the completion edge (BISIO_DEX_JUST_COMPLETED=1). No-op otherwise.
# Stays AFTER the dex bar so the user sees it fill 4/4 first.
if [ "$rendered" = "1" ] && command -v bisio_announce_completion >/dev/null 2>&1; then
  bisio_announce_completion
fi

# Trailing blank line before the welcome box / prompt.
[ "$rendered" = "1" ] && printf '\n'

if [ "$rendered" = "1" ] && [ ! -f "$first_sentinel" ]; then
  mkdir -p "$state_root" 2>/dev/null && : > "$first_sentinel" 2>/dev/null || true
fi

exit 0
