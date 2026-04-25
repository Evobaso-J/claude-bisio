#!/bin/sh
# claude-bisio updater. POSIX sh.
# Fast-forward pull on the existing clone. No-op if already up to date.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Evobaso-J/claude-bisio/main/update.sh | sh
#   ./update.sh                       (when run from a clone)
#
# Env overrides:
#   CLAUDE_BISIO_DIR   plugin dir (default $HOME/.claude-bisio)
#   CLAUDE_BISIO_REF   git ref    (default main)

set -eu

TARGET_DIR="${CLAUDE_BISIO_DIR:-$HOME/.claude-bisio}"
REPO_REF="${CLAUDE_BISIO_REF:-main}"

log()  { printf '[claude-bisio] %s\n' "$*"; }
warn() { printf '[claude-bisio] %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

[ -d "$TARGET_DIR/.git" ] || die "no clone at $TARGET_DIR. Run install.sh first."
command -v git >/dev/null 2>&1 || die "git not found. Install git, then re-run."

log "fetching origin"
git -C "$TARGET_DIR" fetch --quiet origin "$REPO_REF"

before=$(git -C "$TARGET_DIR" rev-parse HEAD)
log "fast-forwarding $REPO_REF"
git -C "$TARGET_DIR" merge --ff-only "origin/$REPO_REF"
after=$(git -C "$TARGET_DIR" rev-parse HEAD)

if [ "$before" = "$after" ]; then
  log "already up to date ($after)"
else
  log "updated $before -> $after"
fi
