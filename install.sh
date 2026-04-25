#!/bin/sh
# claude-bisio bootstrap. POSIX sh.
# - Installs chafa via the OS package manager (skipped if already present).
# - Clones the plugin repo into $CLAUDE_BISIO_DIR (default: $HOME/.claude-bisio).
# - Appends the source line to ~/.zshrc once.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Evobaso-J/claude-bisio/main/install.sh | sh
#   ./install.sh                     (when run from a clone)
#
# Env overrides:
#   CLAUDE_BISIO_DIR   target install dir (default $HOME/.claude-bisio)
#   CLAUDE_BISIO_REPO  git remote URL    (default https://github.com/Evobaso-J/claude-bisio)
#   CLAUDE_BISIO_REF   git ref           (default main)

set -eu

REPO_URL="${CLAUDE_BISIO_REPO:-https://github.com/Evobaso-J/claude-bisio}"
REPO_REF="${CLAUDE_BISIO_REF:-main}"
TARGET_DIR="${CLAUDE_BISIO_DIR:-$HOME/.claude-bisio}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
SOURCE_LINE="source \"$TARGET_DIR/claude-bisio.plugin.zsh\""

log()  { printf '[claude-bisio] %s\n' "$*"; }
warn() { printf '[claude-bisio] %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

# --- sudo wrapper (no-op when root) ---
SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

# --- install chafa ---
install_chafa() {
  if command -v chafa >/dev/null 2>&1; then
    log "chafa already installed - skipping"
    return 0
  fi

  os=$(uname -s 2>/dev/null || echo unknown)
  case "$os" in
    Darwin)
      if ! command -v brew >/dev/null 2>&1; then
        die "Homebrew not found. Install it first: https://brew.sh - then re-run this script."
      fi
      log "installing chafa via Homebrew"
      brew install chafa
      ;;
    Linux)
      if command -v brew >/dev/null 2>&1; then
        log "installing chafa via Homebrew"
        brew install chafa
      elif command -v apt-get >/dev/null 2>&1; then
        log "installing chafa via apt-get"
        $SUDO apt-get update
        $SUDO apt-get install -y chafa
      elif command -v dnf >/dev/null 2>&1; then
        log "installing chafa via dnf"
        $SUDO dnf install -y chafa
      elif command -v pacman >/dev/null 2>&1; then
        log "installing chafa via pacman"
        $SUDO pacman -S --noconfirm chafa
      elif command -v zypper >/dev/null 2>&1; then
        log "installing chafa via zypper"
        $SUDO zypper install -y chafa
      elif command -v apk >/dev/null 2>&1; then
        log "installing chafa via apk"
        $SUDO apk add chafa
      else
        die "no supported package manager found. Install 'chafa' manually, then re-run."
      fi
      ;;
    *)
      die "unsupported OS '$os'. Install 'chafa' manually, then re-run. (Windows: use WSL.)"
      ;;
  esac
}

# --- clone or update plugin ---
install_plugin() {
  if [ -d "$TARGET_DIR/.git" ]; then
    log "plugin already cloned at $TARGET_DIR - run 'git -C $TARGET_DIR pull' to update"
    return 0
  fi
  if [ -e "$TARGET_DIR" ]; then
    die "$TARGET_DIR exists but is not a git checkout. Move it aside, then re-run."
  fi
  command -v git >/dev/null 2>&1 || die "git not found. Install git, then re-run."
  log "cloning $REPO_URL into $TARGET_DIR"
  git clone --branch "$REPO_REF" --depth 1 "$REPO_URL" "$TARGET_DIR"
}

# --- wire into ~/.zshrc ---
wire_zshrc() {
  if [ ! -f "$ZSHRC" ]; then
    log "creating $ZSHRC"
    : > "$ZSHRC"
  fi
  if grep -Fqs "claude-bisio.plugin.zsh" "$ZSHRC"; then
    log "source line already present in $ZSHRC - skipping"
    return 0
  fi
  log "adding source line to $ZSHRC"
  printf '\n# claude-bisio\n%s\n' "$SOURCE_LINE" >> "$ZSHRC"
}

main() {
  install_chafa
  install_plugin
  wire_zshrc
  log "done. Run: exec zsh"
}

main "$@"
