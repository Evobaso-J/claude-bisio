# shellcheck shell=sh
# Weighted-random portrait picker shared between banner.sh and claudiosay.sh.
# Caller must have sourced banner.config.sh first so BISIO_WEIGHT_* are set.
#
# Usage: path=$(bisio_pick_portrait "/path/to/assets/bisio")
#   Prints chosen *.png path on stdout, or nothing if dir missing/empty/all-zero-weight.
#
# Subshell body keeps positional-param mutation ("set --") out of the caller.

bisio_pick_portrait() (
  dir=$1
  [ -d "$dir" ] || exit 0
  set --
  for f in "$dir"/*.png; do
    [ -f "$f" ] && set -- "$@" "$f"
  done
  [ "$#" -gt 0 ] || exit 0
  # Mix PID with seconds — BSD awk srand() has 1-sec resolution, so
  # back-to-back calls in the same second would otherwise pick the same idx.
  seed=$(( $$ ^ $(date +%s 2>/dev/null || echo 0) ))
  printf '%s\n' "$@" | awk -v s="$seed" \
    -v w_main="${BISIO_WEIGHT_MAIN:-0}" \
    -v w_allucinato="${BISIO_WEIGHT_ALLUCINATO:-0}" \
    -v w_rapput="${BISIO_WEIGHT_RAPPUT:-0}" \
    -v w_patema="${BISIO_WEIGHT_PATEMA:-0}" '
    BEGIN {
      srand(s)
      w["main"] = w_main + 0
      w["allucinato"] = w_allucinato + 0
      w["rapput"] = w_rapput + 0
      w["patema"] = w_patema + 0
    }
    {
      n = split($0, p, "/"); base = p[n]; sub(/\.png$/, "", base)
      if ((base in w) && w[base] > 0) {
        paths[++count] = $0; weights[count] = w[base]; total += w[base]
      }
    }
    END {
      if (count == 0 || total <= 0) exit
      r = rand() * total; cum = 0
      for (i = 1; i <= count; i++) {
        cum += weights[i]
        if (r < cum) { print paths[i]; exit }
      }
      print paths[count]
    }
  '
)
