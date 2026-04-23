#!/usr/bin/env sh
# claude-bisio SessionStart hook.
# Writes banner directly to /dev/tty. Zero stdout = zero model-context cost.

dir="$(dirname -- "$0")"
banner="$dir/banner.txt"

[ -r "$banner" ] || exit 0

# Subshell so the /dev/tty open-failure stderr (if any) is captured
# by the outer 2>/dev/null, not leaked to the hook's real stderr.
(
  {
    printf '\r'
    cat "$banner"
    printf '\n'
  } > /dev/tty
) 2>/dev/null

exit 0
