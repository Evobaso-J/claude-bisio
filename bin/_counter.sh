# shellcheck shell=sh
# claude-bisio collection counter. POSIX sh.
#
# Tracks Bisio variant pulls across `claude` launches.
# Exports BISIO_DEX_* env vars for the banner status line. On the
# completion edge, writes a self-contained Hall of Fame HTML page to the
# state dir and sets BISIO_DEX_JUST_COMPLETED=1 + BISIO_HOF_URL=file://...
# so banner.sh can fire the celebration AFTER the dex bar fills.
#
# State: ${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio/counts.txt
# Hall:  ${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio/hall-of-fame.html
# Format: one `slug count` line per key. Keys starting with `__` are metadata.
#
# Caller contract: source banner.config.sh first (so BISIO_WEIGHT_* are set),
# then source this file, then call `bisio_record_pull <slug> <rows> <cols>`
# AFTER the portrait has been successfully rendered. After the dex bar prints,
# call `bisio_announce_completion` to fire the celebration on the edge launch.
#
# Opt-out: CLAUDE_BISIO_NO_COUNTER=1 short-circuits the recorder.

# Hard-coded streak slug. If main.png is renamed, update here too.
_BISIO_STREAK_SLUG="main"

# Identity for the hall of fame: git config → $USER → anonymous.
_bisio_identity() {
  _bi_name=$(git config --global user.name 2>/dev/null)
  if [ -z "$_bi_name" ]; then _bi_name="${USER:-anonymous}"; fi
  [ -n "$_bi_name" ] || _bi_name="anonymous"
  printf '%s' "$_bi_name"
}

# Base64-encode a file as a single line. Mac (BSD) and Linux (GNU) both
# accept `base64 < file`; outputs may be wrapped — strip newlines for safe
# inlining as a data URI.
_bisio_b64_file() {
  base64 < "$1" 2>/dev/null | tr -d '\n\r'
}

# Emit one variant tile to stdout.
_bisio_html_tile() {
  _bht_slug=$1; _bht_count=$2; _bht_b64=$3
  printf '<article class="tile"><img alt="%s" src="data:image/png;base64,%s"><h3>%s</h3><p class="count">%d×</p></article>\n' \
    "$_bht_slug" "$_bht_b64" "$_bht_slug" "$_bht_count"
}

# Render full hall-of-fame HTML to stdout. Caller redirects to a tmp file,
# then atomically mv-renames to hall-of-fame.html.
# Args: name date total final_slug final_pull main_streak nonmain_streak
#       canonical_pipe_list bisio_dir counts_file
_bisio_render_html() {
  _brh_name=$1; _brh_date=$2; _brh_total=$3; _brh_slug=$4; _brh_pull=$5
  _brh_main_streak=$6; _brh_nonmain_streak=$7
  shift 7
  _brh_canlist=$1; _brh_dir=$2; _brh_counts=$3

  cat <<'__HEAD__'
<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<title>claude-bisio · Hall of Fame</title>
<style>
  :root { --bg:#0d0d0d; --fg:#d4d4d4; --acc:#ffd700; --dim:#666; --line:#333; --card:#161616; }
  * { box-sizing: border-box; }
  body { background: var(--bg); color: var(--fg); font-family: "SF Mono","Cascadia Mono",Menlo,Consolas,monospace; margin: 0; padding: 2rem; }
  h1, h2, h3 { color: var(--acc); margin: 0 0 .5rem; }
  h1 { font-size: 1.6rem; letter-spacing: .04em; }
  header { border-bottom: 1px solid var(--line); padding-bottom: 1rem; margin-bottom: 1.5rem; }
  header .meta { color: var(--dim); font-size: .9rem; }
  .stats-card { background: var(--card); border: 1px solid var(--line); border-radius: 6px; padding: 1.25rem 1.5rem; margin-bottom: 2.5rem; }
  .stats { display: grid; grid-template-columns: repeat(auto-fit,minmax(240px,1fr)); gap: .6rem 1.5rem; }
  .stats .row b { color: var(--acc); font-weight: 600; }
  .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1rem; }
  @media (max-width: 800px) { .grid { grid-template-columns: repeat(2, 1fr); } }
  @media (max-width: 500px) { .grid { grid-template-columns: 1fr; } }
  .tile { display: flex; flex-direction: column; align-items: center; border: 1px solid var(--line); padding: .8rem; text-align: center; transition: border-color .15s; }
  .tile:hover { border-color: var(--acc); }
  .tile img { max-width: 100%; max-height: 280px; width: auto; height: auto; object-fit: contain; margin: 0 auto; image-rendering: pixelated; }
  .tile h3 { font-size: 1rem; margin-top: auto; padding-top: .5rem; }
  .tile .count { color: var(--acc); font-size: 1.4rem; margin: 0; }
  footer { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid var(--line); color: var(--dim); font-size: .85rem; }
  footer a { color: var(--acc); text-decoration: none; }
</style>
</head><body>
__HEAD__

  printf '<header><h1>✦ Hall of Fame ✦</h1><div class="meta">%s · %s</div></header>\n' \
    "$_brh_name" "$_brh_date"

  _missed=$(awk '$1=="__missed_banner" { print $2; exit }' "$_brh_counts" 2>/dev/null)
  [ -n "$_missed" ] || _missed=0

  printf '<div class="stats-card">\n'
  printf '<section class="stats">\n'
  printf '<div class="row">Total pulls: <b>%d</b></div>\n' "$_brh_total"
  printf '<div class="row">Final catch: <b>%s</b> (pull #%d)</div>\n' "$_brh_slug" "$_brh_pull"
  printf '<div class="row">Longest streak of main bisio: <b>%d pulls</b></div>\n' "$_brh_main_streak"
  printf '<div class="row">Longest streak without seeing main bisio: <b>%d pulls</b></div>\n' "$_brh_nonmain_streak"
  printf '<div class="row">Missed pulls (terminal too small): <b>%d</b></div>\n' "$_missed"
  printf '</section>\n'
  printf '</div>\n'

  printf '<section class="grid">\n'
  _brh_old_ifs=$IFS
  IFS='|'
  # shellcheck disable=SC2086
  set -- $_brh_canlist
  IFS=$_brh_old_ifs
  for _slug in "$@"; do
    [ -n "$_slug" ] || continue
    _png="$_brh_dir/$_slug.png"
    [ -f "$_png" ] || continue
    _count=$(awk -v k="$_slug" '$1==k { print $2; exit }' "$_brh_counts" 2>/dev/null)
    [ -n "$_count" ] || _count=0
    _b64=$(_bisio_b64_file "$_png")
    _bisio_html_tile "$_slug" "$_count" "$_b64"
  done
  printf '</section>\n'

  printf '<footer><a href="https://github.com/Evobaso-J/claude-bisio">github.com/Evobaso-J/claude-bisio</a></footer>\n'
  printf '</body></html>\n'
}

# Static celebration line + OSC 8 hyperlink, both on the same row.
# Bold yellow on terminal bg — high contrast on light and dark themes.
# Args: hof_url
# Caller guarantees TTY; the !TTY fallback lives in bisio_announce_completion.
_bisio_celebrate() {
  # shellcheck disable=SC1003
  printf '\033[1;33mAll Bisio discovered!\033[0m \033]8;;%s\033\\Access the hall of fame\033]8;;\033\\\n' "$1"
}

# Public: increment __missed_banner metadata. Called by banner.sh when the
# banner bails before rendering due to terminal size / no /dev/tty / no fitting
# layout. Tracked as a stat in the Hall of Fame. Idempotent on opt-out.
bisio_record_miss() {
  [ "${CLAUDE_BISIO_NO_COUNTER:-}" = "1" ] && return 0
  _brm_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio"
  _brm_counts="$_brm_state_dir/counts.txt"
  mkdir -p "$_brm_state_dir" 2>/dev/null || return 0
  if [ -f "$_brm_counts" ]; then _brm_in=$_brm_counts; else _brm_in=/dev/null; fi
  _brm_tmp=$(mktemp "$_brm_state_dir/counts.XXXXXX" 2>/dev/null) || return 0
  awk -v out="$_brm_tmp" '
    /^[A-Za-z0-9_]+ [0-9]+$/ {
      if ($1 == "__missed_banner") { miss = $2 + 1; next }
      print > out
    }
    END {
      if (miss == 0) miss = 1
      printf "__missed_banner %d\n", miss > out
      close(out)
    }
  ' "$_brm_in" 2>/dev/null || { rm -f "$_brm_tmp"; return 0; }
  mv "$_brm_tmp" "$_brm_counts" 2>/dev/null || rm -f "$_brm_tmp"
}

# Public: called by banner.sh AFTER the dex bar has rendered. No-op unless
# the completion edge just fired in this process (BISIO_DEX_JUST_COMPLETED=1).
bisio_announce_completion() {
  [ "${BISIO_DEX_JUST_COMPLETED:-0}" = "1" ] || return 0
  _bac_url=${BISIO_HOF_URL:-}
  [ -n "$_bac_url" ] || return 0
  if [ -t 1 ]; then
    _bisio_celebrate "$_bac_url"
  else
    printf 'All Bisio discovered! %s\n' "$_bac_url"
  fi
}

# Public entry point. Idempotent on opt-out / missing repo / missing assets.
bisio_record_pull() {
  [ "${CLAUDE_BISIO_NO_COUNTER:-}" = "1" ] && return 0

  _brp_slug=$1
  _brp_rows=$2
  _brp_cols=$3
  _brp_back=${4:-1}
  [ -n "$_brp_slug" ] || return 0

  _brp_repo="${repo_dir:-}"
  [ -n "$_brp_repo" ] || return 0
  _brp_bisio_dir="$_brp_repo/assets/bisio"
  [ -d "$_brp_bisio_dir" ] || return 0

  _brp_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio"
  _brp_counts="$_brp_state_dir/counts.txt"
  mkdir -p "$_brp_state_dir" 2>/dev/null || return 0

  # Canonical = pngs ∩ slugs with positive BISIO_WEIGHT_*.
  _brp_canonical=$(
    for f in "$_brp_bisio_dir"/*.png; do
      [ -f "$f" ] || continue
      _slug=${f##*/}; _slug=${_slug%.png}
      _var=BISIO_WEIGHT_$(printf '%s' "$_slug" | tr '[:lower:]' '[:upper:]')
      eval "_w=\${$_var:-0}"
      # `[ -gt ]` quietly fails on non-numeric, which is the desired skip.
      # shellcheck disable=SC2154
      [ "$_w" -gt 0 ] 2>/dev/null && printf '%s\n' "$_slug"
    done
  )
  [ -n "$_brp_canonical" ] || return 0

  if [ -f "$_brp_counts" ]; then
    _brp_in=$_brp_counts
  else
    _brp_in=/dev/null
  fi

  _brp_tmp=$(mktemp "$_brp_state_dir/counts.XXXXXX" 2>/dev/null) || return 0

  # BSD awk rejects newlines inside -v; flatten with `|`.
  _brp_canonical_flat=$(printf '%s' "$_brp_canonical" | tr '\n' '|')

  # awk does the read-modify-prune-write atomically into _brp_tmp,
  # then prints decision tokens on stdout for the shell to consume.
  _brp_decision=$(
    awk -v slug="$_brp_slug" \
        -v streak_slug="$_BISIO_STREAK_SLUG" \
        -v canonical_list="$_brp_canonical_flat" \
        -v out_state="$_brp_tmp" '
      BEGIN {
        nc = split(canonical_list, _cans, "|")
        cn = 0
        for (i = 1; i <= nc; i++) {
          if (_cans[i] != "") {
            canonical[_cans[i]] = 1
            canon_arr[++cn] = _cans[i]
          }
        }
        # Sort canon_arr ascending for deterministic write + tie-breaks.
        for (i = 1; i <= cn; i++) {
          for (j = i + 1; j <= cn; j++) {
            if (canon_arr[j] < canon_arr[i]) {
              t = canon_arr[i]; canon_arr[i] = canon_arr[j]; canon_arr[j] = t
            }
          }
        }
      }
      /^[A-Za-z0-9_]+ [0-9]+$/ {
        k = $1; v = $2 + 0
        if (k ~ /^__/) { meta[k] = v; next }
        counts[k] = v
      }
      END {
        pre_complete = (cn > 0) ? 1 : 0
        for (i = 1; i <= cn; i++) {
          c = canon_arr[i]
          if (!(c in counts) || counts[c] <= 0) { pre_complete = 0; break }
        }

        was_zero = (!(slug in counts) || counts[slug] <= 0) ? 1 : 0
        counts[slug] = (counts[slug] + 0) + 1

        mcur = meta["__main_streak_current"] + 0
        mlng = meta["__main_streak_longest"] + 0
        ncur = meta["__nonmain_streak_current"] + 0
        nlng = meta["__nonmain_streak_longest"] + 0
        if (slug == streak_slug) {
          mcur += 1
          if (mcur > mlng) mlng = mcur
          ncur = 0
        } else {
          ncur += 1
          if (ncur > nlng) nlng = ncur
          mcur = 0
        }

        post_complete = (cn > 0) ? 1 : 0
        n_seen = 0
        for (i = 1; i <= cn; i++) {
          c = canon_arr[i]
          if ((c in counts) && counts[c] > 0) n_seen++
          else post_complete = 0
        }

        total = 0
        for (i = 1; i <= cn; i++) total += (counts[canon_arr[i]] + 0)

        # Write canonical-only state (orphans dropped) + metadata.
        for (i = 1; i <= cn; i++) {
          c = canon_arr[i]
          printf "%s %d\n", c, counts[c] + 0 > out_state
        }
        printf "__main_streak_current %d\n",    mcur > out_state
        printf "__main_streak_longest %d\n",    mlng > out_state
        printf "__nonmain_streak_current %d\n", ncur > out_state
        printf "__nonmain_streak_longest %d\n", nlng > out_state
        # Preserve other __ metadata (e.g. __missed_banner) untouched.
        for (k in meta) {
          if (k == "__main_streak_current" || k == "__main_streak_longest") continue
          if (k == "__nonmain_streak_current" || k == "__nonmain_streak_longest") continue
          printf "%s %d\n", k, meta[k] + 0 > out_state
        }
        close(out_state)

        is_canonical = (slug in canonical) ? 1 : 0
        printf "%d %d %d %d %d %d %d %d %d\n", \
          pre_complete, post_complete, was_zero, is_canonical, \
          n_seen, cn, total, mlng, nlng
      }
    ' "$_brp_in"
  ) || { rm -f "$_brp_tmp"; return 0; }

  if ! mv "$_brp_tmp" "$_brp_counts" 2>/dev/null; then
    rm -f "$_brp_tmp"
    return 0
  fi

  # Parse decision tokens.
  # shellcheck disable=SC2086
  set -- $_brp_decision
  [ "$#" -eq 9 ] || return 0
  _pre=$1; _post=$2; _wasz=$3; _iscan=$4
  _nseen=$5; _ncan=$6; _total=$7
  _main_streak=$8; _nonmain_streak=$9

  # Always export Bisiodex vars for banner status-line consumption.
  # `_wasz=1 && _iscan=1` covers both the new-variant-first-pull case and the
  # completion-edge case (final catch is itself a was_zero canonical pull).
  BISIO_DEX_CAUGHT=$_nseen
  BISIO_DEX_TOTAL=$_ncan
  BISIO_DEX_LATEST=$_brp_slug
  if [ "$_wasz" = "1" ] && [ "$_iscan" = "1" ]; then
    BISIO_DEX_NEW=1
  else
    BISIO_DEX_NEW=0
  fi
  export BISIO_DEX_CAUGHT BISIO_DEX_TOTAL BISIO_DEX_LATEST BISIO_DEX_NEW

  # Edge transition → write hall-of-fame HTML and arm the announce flag.
  # No stdout from here; banner.sh emits the celebration after the dex bar.
  if [ "$_pre" = "0" ] && [ "$_post" = "1" ]; then
    _bcname=$(_bisio_identity)
    _bcdate=$(date +%Y-%m-%d 2>/dev/null)
    _hof_path="$_brp_state_dir/hall-of-fame.html"

    _hof_tmp=$(mktemp "$_brp_state_dir/hof.XXXXXX" 2>/dev/null) || _hof_tmp=""
    if [ -n "$_hof_tmp" ]; then
      _bisio_render_html \
        "$_bcname" "$_bcdate" "$_total" "$_brp_slug" "$_total" \
        "$_main_streak" "$_nonmain_streak" \
        "$_brp_canonical_flat" "$_brp_bisio_dir" "$_brp_counts" \
        > "$_hof_tmp" 2>/dev/null
      if mv "$_hof_tmp" "$_hof_path" 2>/dev/null; then
        BISIO_DEX_JUST_COMPLETED=1
        BISIO_HOF_URL="file://$_hof_path"
        export BISIO_DEX_JUST_COMPLETED BISIO_HOF_URL
        return 0
      fi
      rm -f "$_hof_tmp"
    fi
    # Fallthrough: file write failed → don't arm the flag.
  fi

  # Non-edge return: clear stale flag from a prior call in same process.
  BISIO_DEX_JUST_COMPLETED=0
  export BISIO_DEX_JUST_COMPLETED
  return 0
}
