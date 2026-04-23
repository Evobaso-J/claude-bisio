#!/usr/bin/env sh
# claude-bisio SessionStart hook.
# Writes banner to /dev/tty (Unix) or delegates to PowerShell (Windows).
# Zero stdout = zero model-context cost.

dir="$(dirname -- "$0")"
banner="$dir/banner.txt"

[ -r "$banner" ] || exit 0

# Windows branch: hand off to PowerShell if we're running under a Windows
# environment (Git Bash, MSYS2, Cygwin all set OS=Windows_NT).
case "${OS:-}" in
  Windows_NT)
    if command -v powershell >/dev/null 2>&1; then
      powershell -ExecutionPolicy Bypass -File "$dir/banner.ps1" >/dev/null 2>&1
    fi
    exit 0
    ;;
esac

# Unix branch: write to controlling TTY. Subshell so /dev/tty open-failure
# stderr is captured by the outer 2>/dev/null instead of leaking.
(
  {
    printf '\r'
    cat "$banner"
    printf '\n'
  } > /dev/tty
) 2>/dev/null

exit 0
