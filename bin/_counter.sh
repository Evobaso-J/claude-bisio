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

# Escape HTML special chars in the single positional arg, write to stdout.
# Used for git user.name (the only render input not gated by a strict regex).
_bisio_html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e "s/'/\&#39;/g" -e 's/"/\&quot;/g'
}

# Build per-variant <tr> rows for the RNG-sanity table to stdout.
# The panel's <thead> + wrapping <table>/<section> live in the inline HTML
# body inside _bisio_render_html.
# Args: dex_list counts_file weights
_bisio_hof_table_rows() {
  awk -v dex="$1" -v counts="$2" -v weights="$3" '
    BEGIN {
      while ((getline ln < counts) > 0) {
        if (ln ~ /^[A-Za-z0-9_]+ [0-9]+$/) {
          split(ln, f, " ")
          if (f[1] !~ /^__/) c[f[1]] = f[2] + 0
        }
      }
      close(counts)
      nw = split(weights, ws, "|")
      tot_w = 0
      for (i = 1; i <= nw; i++) {
        if (ws[i] == "") continue
        split(ws[i], wp, ":")
        w = wp[2] + 0
        wmap[wp[1]] = w
        tot_w += w
      }
      nd = split(dex, ds, "|")
      tot_c = 0
      cnt_n = 0
      for (i = 1; i <= nd; i++) {
        s = ds[i]; sub(/^[0-9]+:/, "", s)
        if (s == "") continue
        cnt_n++
        slugs[cnt_n] = s
        cs[cnt_n] = (s in c) ? c[s] : 0
        tot_c += cs[cnt_n]
      }
      for (i = 1; i <= cnt_n; i++) {
        s = slugs[i]
        actual   = (tot_c > 0) ? (cs[i] * 100.0 / tot_c) : 0
        expected = (tot_w > 0 && (s in wmap)) ? (wmap[s] * 100.0 / tot_w) : 0
        delta    = actual - expected
        absd     = (delta < 0) ? -delta : delta
        cls      = (absd < 5) ? "delta-good" : ((absd < 15) ? "delta-warn" : "delta-bad")
        sign     = (delta >= 0) ? "+" : ""
        printf "<tr><td>%s</td><td class=\"num\">%.1f%%</td><td class=\"num\">%.1f%%</td><td class=\"num %s\">%s%.1f%%</td></tr>\n", \
          s, actual, expected, cls, sign, delta
      }
    }'
}

# Build per-variant <article class="tile"> blocks to stdout.
# Args: dex_list bisio_dir counts_file
_bisio_hof_tiles_frag() {
  _htf_dex_list=$1; _htf_dir=$2; _htf_counts=$3

  _htf_old_ifs=$IFS
  IFS='|'
  # shellcheck disable=SC2086
  set -- $_htf_dex_list
  IFS=$_htf_old_ifs
  for _entry in "$@"; do
    [ -n "$_entry" ] || continue
    _dex=${_entry%%:*}
    _slug=${_entry#*:}
    [ -n "$_slug" ] || continue
    _png=""
    for _candidate in "$_htf_dir"/[0-9][0-9]-"$_slug".png; do
      [ -f "$_candidate" ] && _png=$_candidate && break
    done
    [ -n "$_png" ] || continue
    _count=$(awk -v k="$_slug" '$1==k { print $2; exit }' "$_htf_counts" 2>/dev/null)
    [ -n "$_count" ] || _count=0
    _w_var=BISIO_WEIGHT_$(printf '%s' "$_slug" | tr '[:lower:]' '[:upper:]')
    eval "_w_val=\${$_w_var:-0}"
    case "$_w_val" in *[!0-9]*|"") _w_val=0 ;; esac
    if [ "$_w_val" -le 5 ]; then
      _tier_class=legendary; _tier_label=Legendary
    elif [ "$_w_val" -le 20 ]; then
      _tier_class=rare; _tier_label=Rare
    elif [ "$_w_val" -le 30 ]; then
      _tier_class=uncommon; _tier_label=Uncommon
    else
      _tier_class=common; _tier_label=Common
    fi
    _b64=$(_bisio_b64_file "$_png")
    printf '<article class="tile"><img alt="%s" src="data:image/png;base64,%s"><h3>#%s %s</h3><div class="tile-footer"><span class="tile-rarity rarity-%s">%s</span><span class="tile-pulls">Number of Pulls: <b>%d</b></span></div></article>\n' \
      "$_slug" "$_b64" "$_dex" "$_slug" "$_tier_class" "$_tier_label" "$_count"
  done
}

# Format a duration in seconds per BISIO_COUNTER_SPEC.md Q21:
# - empty / non-numeric / 0 epoch → "unknown"
# - delta < 60 → "Ns"
# - delta ≥ 60 → largest two units from {d,h,m,s} (zero second unit allowed,
#   e.g. "2d 0h", to keep a leading-unit partner)
# Args: first_epoch now_epoch
_bisio_format_duration() {
  _bfd_first=$1
  _bfd_now=$2
  case "$_bfd_first" in ''|*[!0-9]*) printf 'unknown\n'; return 0 ;; esac
  case "$_bfd_now"   in ''|*[!0-9]*) printf 'unknown\n'; return 0 ;; esac
  [ "$_bfd_first" -gt 0 ] 2>/dev/null || { printf 'unknown\n'; return 0; }
  _bfd_delta=$(( _bfd_now - _bfd_first ))
  [ "$_bfd_delta" -lt 0 ] && _bfd_delta=0
  if [ "$_bfd_delta" -lt 60 ]; then
    printf '%ds\n' "$_bfd_delta"
    return 0
  fi
  _bfd_d=$(( _bfd_delta / 86400 ))
  _bfd_h=$(( (_bfd_delta % 86400) / 3600 ))
  _bfd_m=$(( (_bfd_delta % 3600) / 60 ))
  _bfd_s=$(( _bfd_delta % 60 ))
  if [ "$_bfd_d" -gt 0 ]; then
    printf '%dd %dh\n' "$_bfd_d" "$_bfd_h"
  elif [ "$_bfd_h" -gt 0 ]; then
    printf '%dh %dm\n' "$_bfd_h" "$_bfd_m"
  else
    printf '%dm %ds\n' "$_bfd_m" "$_bfd_s"
  fi
}

# Render full hall-of-fame HTML to stdout. The page body is inlined as a
# heredoc below — no external template file. Caller redirects to a tmp file,
# then atomically mv-renames to hall-of-fame.html.
# Args: name date total final_slug final_pull main_streak nonmain_streak
#       dex_pipe_list bisio_dir counts_file completion_time
# dex_pipe_list format: "01:main|02:allucinato|03:rapput|04:patema"
_bisio_render_html() {
  _brh_name=$1; _brh_date=$2; _brh_total=$3; _brh_slug=$4; _brh_pull=$5
  _brh_main_streak=$6; _brh_nonmain_streak=$7
  shift 7
  _brh_dex_list=$1; _brh_dir=$2; _brh_counts=$3; _brh_completion_time=$4

  # Build canonical weights string `slug:weight|slug:weight|…` from env, in
  # dex order so RNG-sanity rows match the dex sequence.
  _brh_weights=""
  _brh_oifs=$IFS
  IFS='|'
  # shellcheck disable=SC2086
  set -- $_brh_dex_list
  IFS=$_brh_oifs
  for _e in "$@"; do
    [ -n "$_e" ] || continue
    _w_slug=${_e#*:}
    _w_var=BISIO_WEIGHT_$(printf '%s' "$_w_slug" | tr '[:lower:]' '[:upper:]')
    eval "_w_val=\${$_w_var:-0}"
    case "$_w_val" in *[!0-9]*|"") _w_val=0 ;; esac
    if [ -n "$_brh_weights" ]; then
      _brh_weights="$_brh_weights|$_w_slug:$_w_val"
    else
      _brh_weights="$_w_slug:$_w_val"
    fi
  done

  # Scalar metadata values from counts.txt.
  _bgi() { awk -v k="$1" '$1==k && $2 ~ /^[0-9]+$/ { print $2; exit }' "$_brh_counts" 2>/dev/null; }
  _bgs() { awk -v k="$1" '$1==k { print $2; exit }' "$_brh_counts" 2>/dev/null; }

  _missed=$(_bgi __missed_banner);             [ -n "$_missed" ]   || _missed=0
  _dup_lng=$(_bgi __dup_streak_longest);       [ -n "$_dup_lng" ]  || _dup_lng=0
  _dup_slug=$(_bgs __dup_streak_slug)
  _diff_lng=$(_bgi __diff_streak_longest);     [ -n "$_diff_lng" ] || _diff_lng=0
  _first_rand_slug=$(_bgs __first_random_slug)
  _first_rand_n=$(_bgi __first_random_pull_n); [ -n "$_first_rand_n" ] || _first_rand_n=0

  # Most-pulled (count desc, slug asc).
  _most_pair=$(awk -v dex="$_brh_dex_list" -v counts="$_brh_counts" '
    BEGIN {
      while ((getline ln < counts) > 0) {
        if (ln ~ /^[A-Za-z0-9_]+ [0-9]+$/) {
          split(ln, f, " ")
          if (f[1] !~ /^__/) c[f[1]] = f[2] + 0
        }
      }
      close(counts)
      n = split(dex, e, "|")
      bs = ""; bc = -1
      for (i = 1; i <= n; i++) {
        s = e[i]; sub(/^[0-9]+:/, "", s)
        if (s == "") continue
        cnt = (s in c) ? c[s] : 0
        if (bs == "" || cnt > bc || (cnt == bc && s < bs)) { bs = s; bc = cnt }
      }
      if (bs != "") printf "%s %d", bs, bc
    }')
  _most_slug=${_most_pair% *}; _most_count=${_most_pair##* }

  # Conditional-row inner-content fragments. Empty data → literal em-dash;
  # populated → `<b>…</b> (…)` matching the visual design.
  if [ -n "$_most_slug" ]; then
    _most_value=$(printf '<b>%s</b> (%d×)' "$_most_slug" "$_most_count")
  else
    _most_value="—"
  fi
  if [ -n "$_first_rand_slug" ] && [ "$_first_rand_n" -gt 0 ] 2>/dev/null; then
    _first_random_value=$(printf '<b>%s</b> (pull #%d)' "$_first_rand_slug" "$_first_rand_n")
  else
    _first_random_value="—"
  fi
  if [ "$_dup_lng" -gt 0 ] 2>/dev/null; then
    if [ -n "$_dup_slug" ]; then
      _dup_value=$(printf '<b>%d pulls</b> (%s)' "$_dup_lng" "$_dup_slug")
    else
      _dup_value=$(printf '<b>%d pulls</b>' "$_dup_lng")
    fi
  else
    _dup_value="—"
  fi
  if [ "$_diff_lng" -gt 0 ] 2>/dev/null; then
    _diff_value=$(printf '<b>%d pulls</b>' "$_diff_lng")
  else
    _diff_value="—"
  fi

  # Block fragments. `$()` strips the trailing newline of each fragment, but
  # the heredoc adds its own newline after each `${…}` expansion, so the seam
  # remains a single `\n` between rows/tiles and the closing tag.
  _brh_rng=$(_bisio_hof_table_rows "$_brh_dex_list" "$_brh_counts" "$_brh_weights") || return 1
  _brh_tiles=$(_bisio_hof_tiles_frag "$_brh_dex_list" "$_brh_dir" "$_brh_counts") || return 1

  # HTML-escape git user.name (only render input not gated by a strict regex).
  _brh_name_esc=$(_bisio_html_escape "$_brh_name")

  cat <<HTML
<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<title>claude-bisio · Hall of Fame</title>
<style>
  :root { --bg:#0d0d0d; --fg:#d4d4d4; --acc:#ffd700; --dim:#888; --line:#333; --card:#161616; --good:#7cc97c; --warn:#e0c068; --bad:#e57c7c; }
  * { box-sizing: border-box; }
  body { background: var(--bg); color: var(--fg); font-family: "SF Mono","Cascadia Mono",Menlo,Consolas,monospace; margin: 0 auto; padding: 2rem; max-width: 1100px; }
  h1, h2, h3 { color: var(--acc); margin: 0 0 .5rem; }
  h1 { font-size: 1.6rem; letter-spacing: .04em; }
  h2 { font-size: 1.05rem; margin: 0 0 .75rem; letter-spacing: .03em; }
  header { display: flex; justify-content: space-between; align-items: baseline; gap: 1rem; flex-wrap: wrap; border-bottom: 1px solid var(--line); padding-bottom: 1rem; margin-bottom: 1.5rem; }
  header .meta { color: var(--dim); font-size: .9rem; }
  header .repo-link { color: var(--acc); text-decoration: none; font-size: .85rem; white-space: nowrap; }
  header .repo-link:hover { text-decoration: underline; }
  .stats-card { background: var(--card); border: 1px solid var(--line); border-radius: 6px; padding: 1.25rem 1.5rem; margin-bottom: 2rem; }
  .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1.1rem 1.5rem; }
  .stat { min-width: 0; font-size: 1rem; line-height: 1.35; }
  .stat-label { display: block; color: var(--dim); font-size: .72rem; text-transform: uppercase; letter-spacing: .06em; margin-bottom: .15rem; }
  .stat b { color: var(--acc); font-weight: 600; }
  section.panel { background: var(--card); border: 1px solid var(--line); border-radius: 6px; padding: 1rem 1.25rem; margin-bottom: 1.5rem; }
  section.panel ol, section.panel ul { margin: 0; padding-left: 1.25rem; }
  section.panel li { margin: .15rem 0; }
  section.panel li b { color: var(--acc); }
  .table-wrap { overflow-x: auto; }
  table.dex { width: 100%; border-collapse: collapse; font-size: .92rem; }
  table.dex th, table.dex td { padding: .4rem 1rem; text-align: left; border-bottom: 1px solid var(--line); white-space: nowrap; }
  table.dex th:first-child, table.dex td:first-child { padding-left: 0; }
  table.dex th:last-child, table.dex td:last-child { padding-right: 0; }
  table.dex th { color: var(--acc); font-weight: 600; }
  table.dex tbody tr:nth-child(even) { background: rgba(255,255,255,0.02); }
  table.dex th.num, table.dex td.num { text-align: right; font-variant-numeric: tabular-nums; }
  .delta-good { color: var(--good); }
  .delta-warn { color: var(--warn); }
  .delta-bad  { color: var(--bad); }
  .panels-2col { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; margin-bottom: 1.5rem; }
  @media (max-width: 700px) { .panels-2col { grid-template-columns: 1fr; } }
  .panels-2col > section.panel { margin-bottom: 0; }
  .table-scroll { max-height: 200px; overflow-y: auto; }
  .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1rem; margin-top: 1rem; }
  @media (max-width: 800px) { .grid { grid-template-columns: repeat(2, 1fr); } }
  @media (max-width: 500px) { .grid { grid-template-columns: 1fr; } }
  .tile { display: flex; flex-direction: column; align-items: center; border: 1px solid var(--line); padding: .8rem; text-align: center; transition: border-color .15s; }
  .tile:hover { border-color: var(--acc); }
  .tile img { max-width: 100%; max-height: 280px; width: auto; height: auto; object-fit: contain; margin: 0 auto; image-rendering: pixelated; }
  .tile h3 { font-size: 1rem; margin-top: auto; padding-top: .5rem; }
  .tile-footer { display: flex; justify-content: space-between; align-items: baseline; width: 100%; padding-top: .5rem; font-size: .9rem; }
  .tile-pulls { color: var(--dim); }
  .tile-pulls b { color: var(--fg); font-weight: 600; }
  .tile-rarity { font-weight: 600; letter-spacing: .04em; text-transform: uppercase; font-size: .8rem; }
  .rarity-legendary { color: #D97757; }
  .rarity-rare      { color: #c060e0; }
  .rarity-uncommon  { color: #6cb0ff; }
  .rarity-common    { color: #888; }
  footer { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid var(--line); color: var(--dim); font-size: .85rem; }
  footer a { color: var(--acc); text-decoration: none; }
</style>
</head><body>
<header><div class="header-title"><h1>✦ Hall of Fame ✦</h1><div class="meta">${_brh_name_esc} · ${_brh_date}</div></div><a class="repo-link" href="https://github.com/Evobaso-J/claude-bisio">github.com/Evobaso-J/claude-bisio</a></header>
<div class="stats-card">
<section class="stats">
<div class="stat"><span class="stat-label">Total pulls:</span> <b>${_brh_total}</b></div>
<div class="stat"><span class="stat-label">Completion time:</span> <b>${_brh_completion_time}</b></div>
<div class="stat"><span class="stat-label">Final catch:</span> <b>${_brh_slug}</b> (pull #${_brh_pull})</div>
<div class="stat"><span class="stat-label">Most pulled:</span> ${_most_value}</div>
<div class="stat"><span class="stat-label">First variant seen:</span> ${_first_random_value}</div>
<div class="stat"><span class="stat-label">Longest streak of main bisio:</span> <b>${_brh_main_streak} pulls</b></div>
<div class="stat"><span class="stat-label">Longest non-main streak:</span> <b>${_brh_nonmain_streak} pulls</b></div>
<div class="stat"><span class="stat-label">Longest dup streak:</span> ${_dup_value}</div>
<div class="stat"><span class="stat-label">Longest all-different streak:</span> ${_diff_value}</div>
<div class="stat"><span class="stat-label">Missed (tiny terminal):</span> <b>${_missed}</b></div>
</section>
</div>
<section class="panel"><h2>RNG sanity</h2><div class="table-wrap table-scroll">
<table class="dex"><thead><tr><th>Variant</th><th class="num">Actual %</th><th class="num">Expected %</th><th class="num">Δ</th></tr></thead><tbody>
${_brh_rng}
</tbody></table></div></section>
<section class="grid">
${_brh_tiles}
</section>
</body></html>
HTML
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
      next
    }
    /^__[A-Za-z0-9_]+ [A-Za-z0-9_,-]+$/ {
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

  # Canonical = NN-prefixed pngs ∩ slugs with positive BISIO_WEIGHT_*.
  # The `NN-` prefix is the canonical-membership gate: unprefixed PNGs in
  # assets/bisio/ are silently skipped (matches picker behavior).
  _brp_canonical=$(
    for f in "$_brp_bisio_dir"/[0-9][0-9]-*.png; do
      [ -f "$f" ] || continue
      _base=${f##*/}
      _slug=${_base#[0-9][0-9]-}; _slug=${_slug%.png}
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

  # Capture the pre-write first-pull epoch. Used downstream on completion edge
  # to distinguish "real first pull was earlier" (delta-from-stored) from
  # "this write is the first lazy-init" (render as unknown per spec Q21).
  _first_epoch_pre=$(awk '$1=="__first_pull_epoch" && $2 ~ /^[0-9]+$/ { print $2; exit }' "$_brp_in" 2>/dev/null)

  # BSD awk rejects newlines inside -v; flatten with `|`.
  _brp_canonical_flat=$(printf '%s' "$_brp_canonical" | tr '\n' '|')

  # awk does the read-modify-prune-write atomically into _brp_tmp,
  # then prints two stdout lines:
  #   line 1: 10 decision tokens
  #   line 2: NN:slug|NN:slug|... dex list for HoF rendering
  _brp_full=$(
    awk -v slug="$_brp_slug" \
        -v streak_slug="$_BISIO_STREAK_SLUG" \
        -v canonical_list="$_brp_canonical_flat" \
        -v now_epoch="$(date +%s 2>/dev/null)" \
        -v out_state="$_brp_tmp" '
      BEGIN {
        # canonical_list comes pre-sorted in dex order from the shell glob
        # `[0-9][0-9]-*.png` — no awk-side re-sort. canon_arr index = dex#.
        nc = split(canonical_list, _cans, "|")
        cn = 0
        for (i = 1; i <= nc; i++) {
          if (_cans[i] != "") {
            canonical[_cans[i]] = 1
            canon_arr[++cn] = _cans[i]
          }
        }
      }
      # Canonical counts + int metadata. Higher precedence — int meta lines
      # match this regex first and route to meta[] (numeric).
      /^[A-Za-z0-9_]+ [0-9]+$/ {
        k = $1; v = $2 + 0
        if (k ~ /^__/) meta[k] = v
        else counts[k] = v
        next
      }
      # String/comma-joined metadata (slug values, set lists). Forward-compat:
      # only matches __-prefixed keys with non-numeric single-token values.
      /^__[A-Za-z0-9_]+ [A-Za-z0-9_,-]+$/ {
        meta_str[$1] = $2
        next
      }
      END {
        pre_complete = (cn > 0) ? 1 : 0
        for (i = 1; i <= cn; i++) {
          c = canon_arr[i]
          if (!(c in counts) || counts[c] <= 0) { pre_complete = 0; break }
        }

        was_zero = (!(slug in counts) || counts[slug] <= 0) ? 1 : 0
        counts[slug] = (counts[slug] + 0) + 1

        # main / non-main streak (v0.3 behavior).
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
        meta["__main_streak_current"]    = mcur
        meta["__main_streak_longest"]    = mlng
        meta["__nonmain_streak_current"] = ncur
        meta["__nonmain_streak_longest"] = nlng

        # pull_n_global = canonical sum post-increment (== total pulls).
        total = 0
        for (i = 1; i <= cn; i++) total += (counts[canon_arr[i]] + 0)

        # First variant seen: first non-main canonical pull.
        if ((slug in canonical) && slug != streak_slug && \
            !("__first_random_slug" in meta_str)) {
          meta_str["__first_random_slug"] = slug
          meta["__first_random_pull_n"]   = total
        }

        # Dup streak.
        last = ("__last_slug" in meta_str) ? meta_str["__last_slug"] : ""
        dcur = meta["__dup_streak_current"] + 0
        dlng = meta["__dup_streak_longest"] + 0
        dslug = ("__dup_streak_slug" in meta_str) ? meta_str["__dup_streak_slug"] : ""
        if (last != "" && slug == last) dcur += 1
        else                            dcur = 1
        if (dcur > dlng) { dlng = dcur; dslug = slug }
        meta["__dup_streak_current"] = dcur
        meta["__dup_streak_longest"] = dlng
        if (dslug != "") meta_str["__dup_streak_slug"] = dslug

        # All-different streak: current run of distinct slugs.
        diffcur = meta["__diff_streak_current"] + 0
        difflng = meta["__diff_streak_longest"] + 0
        setstr  = ("__diff_streak_set" in meta_str) ? meta_str["__diff_streak_set"] : ""
        in_set = 0
        if (setstr != "") {
          ns = split(setstr, _sa, ",")
          for (i = 1; i <= ns; i++) if (_sa[i] == slug) { in_set = 1; break }
        }
        if (in_set) {
          diffcur = 1
          setstr  = slug
        } else {
          diffcur += 1
          setstr   = (setstr == "") ? slug : (setstr "," slug)
        }
        if (diffcur > difflng) difflng = diffcur
        meta["__diff_streak_current"] = diffcur
        meta["__diff_streak_longest"] = difflng
        meta_str["__diff_streak_set"] = setstr

        # Last slug for next-pull dup detection.
        meta_str["__last_slug"] = slug

        # First-pull epoch. Set lazily on the very first legit write iff the
        # key is missing. Never overwritten. Drives HoF "Completion time".
        if (!("__first_pull_epoch" in meta) && now_epoch + 0 > 0) {
          meta["__first_pull_epoch"] = now_epoch + 0
        }

        post_complete = (cn > 0) ? 1 : 0
        n_seen = 0
        for (i = 1; i <= cn; i++) {
          c = canon_arr[i]
          if ((c in counts) && counts[c] > 0) n_seen++
          else post_complete = 0
        }

        # Write canonical-only state (orphans dropped) + all metadata.
        for (i = 1; i <= cn; i++) {
          c = canon_arr[i]
          printf "%s %d\n", c, counts[c] + 0 > out_state
        }
        for (k in meta)     printf "%s %d\n", k, meta[k] + 0 > out_state
        for (k in meta_str) printf "%s %s\n", k, meta_str[k]   > out_state
        close(out_state)

        is_canonical = (slug in canonical) ? 1 : 0
        dex_latest = 0
        for (i = 1; i <= cn; i++) {
          if (canon_arr[i] == slug) { dex_latest = i; break }
        }
        printf "%d %d %d %d %d %d %d %d %d %d\n", \
          pre_complete, post_complete, was_zero, is_canonical, \
          n_seen, cn, total, mlng, nlng, dex_latest

        # Second stdout line: NN:slug|NN:slug|... for HoF rendering.
        for (i = 1; i <= cn; i++) {
          if (i > 1) printf "|"
          printf "%02d:%s", i, canon_arr[i]
        }
        printf "\n"
      }
    ' "$_brp_in"
  ) || { rm -f "$_brp_tmp"; return 0; }

  if ! mv "$_brp_tmp" "$_brp_counts" 2>/dev/null; then
    rm -f "$_brp_tmp"
    return 0
  fi

  # Split awk's two-line stdout into decision (line 1) and dex list (line 2)
  # using a literal-newline IFS. POSIX-safe.
  _brp_old_ifs=$IFS
  IFS='
'
  # shellcheck disable=SC2086
  set -- $_brp_full
  IFS=$_brp_old_ifs
  _brp_decision=${1:-}
  _brp_dex_list=${2:-}

  # Parse decision tokens.
  # shellcheck disable=SC2086
  set -- $_brp_decision
  [ "$#" -eq 10 ] || return 0
  _pre=$1; _post=$2; _wasz=$3; _iscan=$4
  _nseen=$5; _ncan=$6; _total=$7
  _main_streak=$8; _nonmain_streak=$9
  _dex_latest=${10}

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
  if [ "$_dex_latest" -gt 0 ] 2>/dev/null; then
    BISIO_DEX_LATEST_NUM=$(printf '%02d' "$_dex_latest")
  else
    BISIO_DEX_LATEST_NUM=""
  fi
  export BISIO_DEX_CAUGHT BISIO_DEX_TOTAL BISIO_DEX_LATEST BISIO_DEX_NEW BISIO_DEX_LATEST_NUM

  # Edge transition → write hall-of-fame HTML and arm the announce flag.
  # No stdout from here; banner.sh emits the celebration after the dex bar.
  if [ "$_pre" = "0" ] && [ "$_post" = "1" ]; then
    _bcname=$(_bisio_identity)
    _bcdate=$(date +%Y-%m-%d 2>/dev/null)
    _hof_path="$_brp_state_dir/hall-of-fame.html"

    # Completion time: prefer the epoch that existed BEFORE this write. The
    # awk pipeline lazy-inits __first_pull_epoch in the same write that
    # completes the dex on legacy state, which would yield a meaningless 0s
    # delta. Spec Q21: render "unknown" when the key was missing at the
    # completion edge.
    if [ -n "$_first_epoch_pre" ]; then
      _completion_time=$(_bisio_format_duration "$_first_epoch_pre" "$(date +%s 2>/dev/null)")
    else
      _completion_time="unknown"
    fi

    _hof_tmp=$(mktemp "$_brp_state_dir/hof.XXXXXX" 2>/dev/null) || _hof_tmp=""
    if [ -n "$_hof_tmp" ]; then
      if _bisio_render_html \
           "$_bcname" "$_bcdate" "$_total" "$_brp_slug" "$_total" \
           "$_main_streak" "$_nonmain_streak" \
           "$_brp_dex_list" "$_brp_bisio_dir" "$_brp_counts" "$_completion_time" \
           > "$_hof_tmp" 2>/dev/null \
         && mv "$_hof_tmp" "$_hof_path" 2>/dev/null; then
        BISIO_DEX_JUST_COMPLETED=1
        BISIO_HOF_URL="file://$_hof_path"
        export BISIO_DEX_JUST_COMPLETED BISIO_HOF_URL
        return 0
      fi
      rm -f "$_hof_tmp"
    fi
    # Fallthrough: render or file write failed → don't arm the flag.
  fi

  # Non-edge return: clear stale flag from a prior call in same process.
  BISIO_DEX_JUST_COMPLETED=0
  export BISIO_DEX_JUST_COMPLETED
  return 0
}
