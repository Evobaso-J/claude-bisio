#!/bin/sh
# claude-bisio update-notification helper. POSIX sh; sourced by the plugin.
#
# Detects when a new upstream release exists and offers to run update.sh
# inline. Cache TTL prevents network calls more than once per 24h. The async
# fetch never blocks the claude launch path; the synchronous prompt only fires
# on bare interactive `claude` invocations.
#
# State (under ${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio/):
#   last-update-check   sentinel; mtime is the TTL marker
#   latest-version      cached remote latest tag (version string, no leading v)
#   dismissed-version   version the user said N to (suppresses re-prompt
#                       until a newer release supersedes it)
#
# Public functions:
#   bisio_update_check        top-level entry: spawn async fetch + sync prompt
#   bisio_update_fetch        sync fetcher (also called via async wrapper)
#   bisio_update_prompt       sync prompt; runs update.sh on y, dismisses on n
#
# Config:
#   CLAUDE_BISIO_CHECK_UPDATES   1 = enabled (default), 0 = disabled
#   CLAUDE_BISIO_DIR             plugin root (set by plugin entry)
#   CLAUDE_BISIO_UPDATE_TTL_MIN  cache TTL in minutes (default 1440 = 24h)

_bisio_update_state_dir() {
  printf '%s/claude-bisio' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

# Read .release-please-manifest.json. Format: { ".": "1.0.0" }.
_bisio_update_local_version() {
  _buv_manifest="${CLAUDE_BISIO_DIR:-}/.release-please-manifest.json"
  [ -r "$_buv_manifest" ] || return 1
  _buv_v=$(grep -o '"[0-9][0-9.]*"' "$_buv_manifest" 2>/dev/null | head -1 | tr -d '"')
  [ -n "$_buv_v" ] || return 1
  printf '%s\n' "$_buv_v"
}

# git ls-remote tags from origin. Latest by sort -V; leading v stripped.
_bisio_update_remote_version() {
  _bur_dir="${CLAUDE_BISIO_DIR:-}"
  [ -d "$_bur_dir/.git" ] || return 1
  _bur_v=$(
    git -C "$_bur_dir" ls-remote --tags --refs origin 'v*' 2>/dev/null \
      | awk '{print $2}' \
      | sed 's#^refs/tags/v##' \
      | sort -V \
      | tail -1
  )
  [ -n "$_bur_v" ] || return 1
  printf '%s\n' "$_bur_v"
}

# True (0) when sentinel is missing OR older than CLAUDE_BISIO_UPDATE_TTL_MIN.
_bisio_update_ttl_stale() {
  _bts_state=$(_bisio_update_state_dir)
  _bts_sentinel="$_bts_state/last-update-check"
  [ -f "$_bts_sentinel" ] || return 0
  _bts_ttl="${CLAUDE_BISIO_UPDATE_TTL_MIN:-1440}"
  _bts_hit=$(find "$_bts_sentinel" -mmin +"$_bts_ttl" -print 2>/dev/null)
  [ -n "$_bts_hit" ]
}

# Public: synchronous network fetch. Touches sentinel up-front so failures
# still arm the TTL (avoids retry storms when offline). Writes cache atomically.
bisio_update_fetch() {
  _buf_state=$(_bisio_update_state_dir)
  mkdir -p "$_buf_state" 2>/dev/null || return 0
  _buf_sentinel="$_buf_state/last-update-check"
  _buf_cache="$_buf_state/latest-version"

  : > "$_buf_sentinel" 2>/dev/null

  _buf_v=$(_bisio_update_remote_version) || return 0
  _buf_tmp="$_buf_cache.tmp.$$"
  printf '%s\n' "$_buf_v" > "$_buf_tmp" 2>/dev/null || return 0
  mv "$_buf_tmp" "$_buf_cache" 2>/dev/null || rm -f "$_buf_tmp" 2>/dev/null
}

# Public: read cache, prompt user when an undismissed update exists, run
# update.sh inline on y. Always returns 0 — must never block claude launch.
bisio_update_prompt() {
  _bup_state=$(_bisio_update_state_dir)
  _bup_cache="$_bup_state/latest-version"
  _bup_dismissed="$_bup_state/dismissed-version"

  [ -r "$_bup_cache" ] || return 0
  _bup_remote=$(cat "$_bup_cache" 2>/dev/null)
  [ -n "$_bup_remote" ] || return 0

  _bup_local=$(_bisio_update_local_version) || return 0
  [ "$_bup_local" = "$_bup_remote" ] && return 0

  if [ -r "$_bup_dismissed" ]; then
    _bup_dv=$(cat "$_bup_dismissed" 2>/dev/null)
    [ "$_bup_dv" = "$_bup_remote" ] && return 0
  fi

  printf '\n📦 v%s → v%s available. Update now? [y/N] ' "$_bup_local" "$_bup_remote"
  read -r _bup_ans || _bup_ans=""

  case "$_bup_ans" in
    y|Y|yes|YES)
      _bup_updater="${CLAUDE_BISIO_DIR:-}/update.sh"
      if [ -x "$_bup_updater" ]; then
        if ! "$_bup_updater"; then
          printf '[claude-bisio] update failed; launching old version\n' >&2
        fi
      else
        printf '[claude-bisio] update.sh not found at %s\n' "$_bup_updater" >&2
      fi
      ;;
    *)
      mkdir -p "$_bup_state" 2>/dev/null
      printf '%s\n' "$_bup_remote" > "$_bup_dismissed" 2>/dev/null
      ;;
  esac

  return 0
}

# Public: top-level entry. Spawn async fetch when TTL stale; prompt sync.
bisio_update_check() {
  [ "${CLAUDE_BISIO_CHECK_UPDATES:-1}" = "1" ] || return 0

  if _bisio_update_ttl_stale; then
    # Nested-subshell background: outer subshell exits immediately, inner job
    # gets reparented. No wait, no zombie, no stdout leak into the prompt.
    ( bisio_update_fetch </dev/null >/dev/null 2>&1 & ) 2>/dev/null
  fi

  bisio_update_prompt
}
