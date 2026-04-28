# --- Claude CLI startup banner ---
# Captures plugin dir at source time so the function can locate bin/banner.sh.
typeset -g CLAUDE_BISIO_DIR="${0:A:h}"

# Source banner.config.sh in the user's shell so config-file knobs (e.g.
# CLAUDE_BISIO_CHECK_UPDATES) reach in-shell helpers like _update_check.sh.
# banner.sh re-sources the same file in its own subprocess; user env-exports
# still win because every assignment uses the `: "${VAR=default}"` form.
if [ -f "$CLAUDE_BISIO_DIR/bin/banner.config.sh" ]; then
  . "$CLAUDE_BISIO_DIR/bin/banner.config.sh"
fi

if [ -f "$CLAUDE_BISIO_DIR/bin/_update_check.sh" ]; then
  . "$CLAUDE_BISIO_DIR/bin/_update_check.sh"
fi

function claude_with_banner() {
  # Banner only on bare `claude` (no args) in an interactive TTY.
  if [ $# -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
    local banner="$CLAUDE_BISIO_DIR/bin/banner.sh"
    if [ -x "$banner" ]; then
      CLAUDE_BISIO_DIR="$CLAUDE_BISIO_DIR" "$banner"
    fi
    if command -v bisio_update_check >/dev/null 2>&1; then
      bisio_update_check
    fi
  fi
  command claude "$@"
}

# Standalone banner - same gating as claude_with_banner, minus launching the CLI.
function bisio() {
  if [ $# -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
    local banner="$CLAUDE_BISIO_DIR/bin/banner.sh"
    if [ -x "$banner" ]; then
      CLAUDE_BISIO_DIR="$CLAUDE_BISIO_DIR" "$banner"
    fi
  fi
}

# Speech-bubble next to a Bisio portrait. Forwards args (or stdin) as the message.
function claudiosay() {
  if [ -t 1 ]; then
    local script="$CLAUDE_BISIO_DIR/bin/claudiosay.sh"
    if [ -x "$script" ]; then
      CLAUDE_BISIO_DIR="$CLAUDE_BISIO_DIR" "$script" "$@"
    fi
  fi
}

alias claude='claude_with_banner'
# --- end Claude CLI banner setup ---
