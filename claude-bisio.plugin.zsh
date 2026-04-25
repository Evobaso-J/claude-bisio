# --- Claude CLI startup banner ---
# Captures plugin dir at source time so the function can locate bin/banner.sh.
typeset -g CLAUDE_BISIO_DIR="${0:A:h}"

function claude_with_banner() {
  # Banner only on bare `claude` (no args) in an interactive TTY.
  if [ $# -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
    local banner="$CLAUDE_BISIO_DIR/bin/banner.sh"
    if [ -x "$banner" ]; then
      CLAUDE_BISIO_DIR="$CLAUDE_BISIO_DIR" "$banner"
    fi
  fi
  command claude "$@"
}

# Standalone banner — same gating as claude_with_banner, minus launching the CLI.
function bisio() {
  if [ $# -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
    local banner="$CLAUDE_BISIO_DIR/bin/banner.sh"
    if [ -x "$banner" ]; then
      CLAUDE_BISIO_DIR="$CLAUDE_BISIO_DIR" "$banner"
    fi
  fi
}

alias claude='claude_with_banner'
# --- end Claude CLI banner setup ---
