#!/usr/bin/env sh
# claude-bisio SessionStart hook.
# Picks a banner tier matching the terminal's dimensions and writes it
# directly to /dev/tty. Zero stdout = zero model-context cost.

dir="$(dirname -- "$0")"

# Windows branch: delegate to PowerShell if available.
case "${OS:-}" in
  Windows_NT)
    if command -v powershell >/dev/null 2>&1; then
      powershell -ExecutionPolicy Bypass -File "$dir/banner.ps1" >/dev/null 2>&1
    fi
    exit 0
    ;;
esac

# Detect terminal dimensions via /dev/tty. Hooks inherit no COLUMNS/LINES,
# so `stty size < /dev/tty` is the most reliable path.
rows=24
cols=80
size=$( (stty size < /dev/tty) 2>/dev/null )
if [ -n "$size" ]; then
  rows=${size% *}
  cols=${size#* }
fi

# Pick the biggest tier that fits. Thresholds leave a couple of rows free
# for whatever CC renders after the banner, so the whole portrait stays in
# view without scroll.
if   [ "$rows" -ge 55 ] && [ "$cols" -ge 90 ];  then tier=lg
elif [ "$rows" -ge 40 ] && [ "$cols" -ge 65 ];  then tier=md
elif [ "$rows" -ge 30 ] && [ "$cols" -ge 48 ];  then tier=sm
else                                                  tier=xs
fi

banner="$dir/banner-$tier.txt"
[ -r "$banner" ] || banner="$dir/banner-xs.txt"
[ -r "$banner" ] || exit 0

# Subshell so /dev/tty open-failure stderr is captured, not leaked.
(
  {
    printf '\r'
    cat "$banner"
    printf '\n'
  } > /dev/tty
) 2>/dev/null

exit 0
