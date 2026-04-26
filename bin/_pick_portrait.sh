# shellcheck shell=sh
# Weighted-random portrait picker shared between banner.sh and claudiosay.sh.
# Caller must have sourced banner.config.sh first so BISIO_WEIGHT_* are set.
#
# Usage: path=$(bisio_pick_portrait "/path/to/assets/bisio")
#   Prints chosen *.png path on stdout, or nothing if dir missing/empty/all-zero-weight.
#
# Files must be named `NN-slug.png` (e.g. `01-main.png`). The `NN-` prefix
# is the canonical-membership gate alongside positive `BISIO_WEIGHT_<UPPER>`.
# Unprefixed PNGs are silently skipped.
#
# Subshell body keeps positional-param mutation ("set --") out of the caller.

bisio_pick_portrait() (
  dir=$1
  [ -d "$dir" ] || exit 0
  set --
  for f in "$dir"/[0-9][0-9]-*.png; do
    [ -f "$f" ] && set -- "$@" "$f"
  done
  [ "$#" -gt 0 ] || exit 0

  # Build slug<TAB>weight lines for every prefixed png. POSIX-safe lookup of
  # BISIO_WEIGHT_<UPPER> via eval. Keeps the picker variant-agnostic — drop a
  # new png in assets/bisio/ and define its weight in banner.config.sh.
  weights=""
  for f in "$@"; do
    base=${f##*/}
    slug=${base#[0-9][0-9]-}
    slug=${slug%.png}
    upper=$(printf '%s' "$slug" | tr '[:lower:]' '[:upper:]')
    eval "w=\${BISIO_WEIGHT_$upper:-0}"
    # shellcheck disable=SC2154  # `w` is assigned by the eval above.
    weights="$weights$slug	$w
"
  done

  # Mix PID with seconds — BSD awk srand() has 1-sec resolution, so
  # back-to-back calls in the same second would otherwise pick the same idx.
  seed=$(( $$ ^ $(date +%s 2>/dev/null || echo 0) ))
  {
    printf '%s' "$weights"
    printf '%s\n' '---'
    printf '%s\n' "$@"
  } | awk -v s="$seed" '
    BEGIN { srand(s); phase = 1 }
    phase == 1 && $0 == "---" { phase = 2; next }
    phase == 1 {
      # slug<TAB>weight
      n = split($0, kv, "\t")
      if (n >= 2) w[kv[1]] = kv[2] + 0
      next
    }
    {
      n = split($0, p, "/"); base = p[n]
      sub(/^[0-9][0-9]-/, "", base); sub(/\.png$/, "", base)
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
