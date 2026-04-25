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

# --- pick a portrait from $bisio_dir/*.png ---
png=""
if [ -d "$bisio_dir" ]; then
  set --
  for f in "$bisio_dir"/*.png; do
    [ -f "$f" ] && set -- "$@" "$f"
  done
  if [ "$#" -gt 0 ]; then
    # Mix PID with seconds — BSD awk srand() has 1-sec resolution, so
    # back-to-back calls in the same second would otherwise pick the same idx.
    seed=$(( $$ ^ $(date +%s 2>/dev/null || echo 0) ))
    png=$(printf '%s\n' "$@" | awk -v s="$seed" \
      -v w_main="${BISIO_WEIGHT_MAIN:-0}" \
      -v w_allucinato="${BISIO_WEIGHT_ALLUCINATO:-0}" \
      -v w_rapput="${BISIO_WEIGHT_RAPPUT:-0}" \
      -v w_patema="${BISIO_WEIGHT_PATEMA:-0}" '
      BEGIN {
        srand(s)
        w["main"] = w_main + 0
        w["allucinato"] = w_allucinato + 0
        w["rapput"] = w_rapput + 0
        w["patema"] = w_patema + 0
      }
      {
        n = split($0, p, "/"); base = p[n]; sub(/\.png$/, "", base)
        if ((base in w) && w[base] > 0) {
          paths[++count] = $0; weights[count] = w[base]; total += w[base]
        }
      }
      END {
        if (count == 0 || total <= 0) exit
        r = rand() * total; cum = 0
        for (i = 1; i <= count; i++) {
          cum += weights[i]
          if (r < cum) { print paths[i]; exit }
        }
        print paths[count]
      }
    ')
  fi
fi

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/claude-bisio"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio"
hint_sentinel="$state_root/hint-shown"

# --- terminal size (subshell swallows /dev/tty open errors per LEARNINGS §7) ---
size=$( (stty size < /dev/tty) 2>/dev/null )
[ -n "$size" ] || exit 0
rows=${size% *}
cols=${size#* }
case "$rows$cols" in *[!0-9]*) exit 0 ;; esac
[ "$cols" -ge 30 ] && [ "$rows" -ge 8 ] || exit 0

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

[ -n "$layout" ] || exit 0

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
case "$layout" in
  solo)
    cat "$cache_file"
    printf '\n'
    ;;
  stacked)
    cat "$cache_file"
    printf '\n'
    # Center title under portrait of width pw.
    pad=$(( (pw - title_cc_w) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    awk -v p="$pad" 'BEGIN{ for(i=0;i<p;i++) s=s" " } { print s $0 }' "$title_cc"
    printf '\n'
    pad_b=$(( (pw - title_bisio_w) / 2 ))
    [ "$pad_b" -lt 0 ] && pad_b=0
    awk -v p="$pad_b" 'BEGIN{ for(i=0;i<p;i++) s=s" " } { print s $0 }' "$title_bisio"
    printf '\n'
    ;;
  side)
    titles_tmp=$(mktemp 2>/dev/null) || titles_tmp="${TMPDIR:-/tmp}/claude-bisio-titles.$$"
    {
      cat "$title_cc"
      printf '\n\n'
      cat "$title_bisio"
    } > "$titles_tmp"

    portrait_lines=$(awk 'END{print NR}' "$cache_file")
    title_lines=$(awk 'END{print NR}' "$titles_tmp")
    diff=$(( portrait_lines - title_lines ))

    # Vertically center title block against portrait by padding top.
    if [ "$diff" -gt 0 ]; then
      pad_top=$(( diff / 2 ))
      padded=$(mktemp 2>/dev/null) || padded="${TMPDIR:-/tmp}/claude-bisio-padded.$$"
      i=0
      : > "$padded"
      while [ "$i" -lt "$pad_top" ]; do printf '\n' >> "$padded"; i=$((i+1)); done
      cat "$titles_tmp" >> "$padded"
      mv "$padded" "$titles_tmp"
    fi

    awk -v gutter="$gutter" '
      NR==FNR { p[FNR]=$0; np=FNR; next }
      {
        line = (FNR <= np) ? p[FNR] : ""
        sep = ""
        for (i=0; i<gutter; i++) sep = sep " "
        printf "%s\033[0m%s%s\n", line, sep, $0
      }
      END {
        if (np > FNR) {
          for (i = FNR+1; i <= np; i++) print p[i] "\033[0m"
        }
      }
    ' "$cache_file" "$titles_tmp"

    rm -f "$titles_tmp"
    printf '\n'
    ;;
esac

exit 0
