#!/usr/bin/env bats
# Counter behavior tests. Each case isolates XDG_STATE_HOME + a fake repo.

setup() {
  TEST_TMP="$(mktemp -d)"
  export XDG_STATE_HOME="$TEST_TMP/state"
  export FAKE_REPO="$TEST_TMP/repo"
  mkdir -p "$FAKE_REPO/assets/bisio" "$FAKE_REPO/bin"

  for slug in main allucinato rapput patema; do
    : > "$FAKE_REPO/assets/bisio/$slug.png"
  done

  export BISIO_WEIGHT_MAIN=45
  export BISIO_WEIGHT_ALLUCINATO=30
  export BISIO_WEIGHT_RAPPUT=20
  export BISIO_WEIGHT_PATEMA=5

  unset CLAUDE_BISIO_NO_COUNTER
  unset BISIO_DEX_JUST_COMPLETED BISIO_HOF_URL

  export repo_dir="$FAKE_REPO"
  # shellcheck source=../bin/_counter.sh
  . "$BATS_TEST_DIRNAME/../bin/_counter.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
}

counts_file() { printf '%s/claude-bisio/counts.txt' "$XDG_STATE_HOME"; }
hof_file()    { printf '%s/claude-bisio/hall-of-fame.html' "$XDG_STATE_HOME"; }

read_count() {
  awk -v k="$1" '$1==k { print $2; exit }' "$(counts_file)"
}

@test "first pull on fresh state sets new-variant dex vars" {
  # Direct call (not `run`) so the exported BISIO_DEX_* vars propagate.
  bisio_record_pull "main" 30 80 > "$TEST_TMP/out"
  [ ! -s "$TEST_TMP/out" ]
  [ "$BISIO_DEX_NEW" = "1" ]
  [ "$BISIO_DEX_LATEST" = "main" ]
  [ "$BISIO_DEX_CAUGHT" = "1" ]
  [ "$BISIO_DEX_TOTAL" = "4" ]
  [ -f "$(counts_file)" ]
  [ "$(read_count main)" = "1" ]
}

@test "duplicate pull is silent and clears NEW flag" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "main" 30 80 > "$TEST_TMP/out"
  [ ! -s "$TEST_TMP/out" ]
  [ "$BISIO_DEX_NEW" = "0" ]
  [ "$BISIO_DEX_LATEST" = "main" ]
  [ "$BISIO_DEX_CAUGHT" = "1" ]
  [ "$BISIO_DEX_TOTAL" = "4" ]
  [ "$(read_count main)" = "2" ]
}

@test "edge transition writes hall-of-fame HTML and is silent on stdout" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  bisio_record_pull "rapput" 30 80 >/dev/null
  run bisio_record_pull "patema" 30 80
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$(hof_file)" ]
  grep -q '<title>claude-bisio · Hall of Fame</title>' "$(hof_file)"
  grep -q 'Final catch:.*<b>patema</b>' "$(hof_file)"
  grep -q 'data:image/png;base64,' "$(hof_file)"
  grep -q 'Longest streak of main bisio' "$(hof_file)"
  grep -q 'Longest streak without seeing main bisio' "$(hof_file)"
}

@test "completion edge sets BISIO_DEX_JUST_COMPLETED, next non-edge clears it" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  bisio_record_pull "rapput" 30 80 >/dev/null
  bisio_record_pull "patema" 30 80 >/dev/null
  [ "$BISIO_DEX_JUST_COMPLETED" = "1" ]
  [ -n "$BISIO_HOF_URL" ]
  case "$BISIO_HOF_URL" in
    file://*hall-of-fame.html) ;;
    *) printf 'unexpected BISIO_HOF_URL: %s\n' "$BISIO_HOF_URL" >&2; return 1 ;;
  esac

  bisio_record_pull "main" 30 80 >/dev/null
  [ "$BISIO_DEX_JUST_COMPLETED" = "0" ]
}

@test "edge fires no second time after completion" {
  for s in main allucinato rapput patema; do
    bisio_record_pull "$s" 30 80 >/dev/null
  done
  _mtime_before=$(stat -f %m "$(hof_file)" 2>/dev/null || stat -c %Y "$(hof_file)")
  sleep 1
  run bisio_record_pull "main" 30 80
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  _mtime_after=$(stat -f %m "$(hof_file)" 2>/dev/null || stat -c %Y "$(hof_file)")
  [ "$_mtime_before" = "$_mtime_after" ]
}

@test "retired variant: completion preserved, orphan pruned" {
  for s in main allucinato rapput patema; do
    bisio_record_pull "$s" 30 80 >/dev/null
  done
  # Retire patema by zeroing its weight + removing the png from canonical scan.
  rm "$FAKE_REPO/assets/bisio/patema.png"
  export BISIO_WEIGHT_PATEMA=0

  run bisio_record_pull "main" 30 80
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # Orphan pruned: patema is no longer in counts file.
  ! grep -q '^patema ' "$(counts_file)"
}

@test "added variant after completion: fresh hall-of-fame fires" {
  for s in main allucinato rapput patema; do
    bisio_record_pull "$s" 30 80 >/dev/null
  done
  : > "$FAKE_REPO/assets/bisio/solai.png"
  export BISIO_WEIGHT_SOLAI=10

  bisio_record_pull "solai" 30 80 >/dev/null
  [ "$BISIO_DEX_JUST_COMPLETED" = "1" ]
  grep -q 'Final catch:.*<b>solai</b>' "$(hof_file)"
}

@test "opt-out env var skips state entirely" {
  CLAUDE_BISIO_NO_COUNTER=1 run bisio_record_pull "main" 30 80
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$(counts_file)" ]
  [ ! -f "$(hof_file)" ]
  # Counter must not populate dex vars when opted out.
  CLAUDE_BISIO_NO_COUNTER=1 bisio_record_pull "main" 30 80 >/dev/null
  [ -z "${BISIO_DEX_TOTAL:-}" ]
  [ -z "${BISIO_DEX_JUST_COMPLETED:-}" ]
}

@test "main streak updates on consecutive main pulls" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  bisio_record_pull "main" 30 80 >/dev/null
  [ "$(read_count __main_streak_longest)" = "3" ]
  [ "$(read_count __main_streak_current)" = "1" ]
  # After main,main,main,allucinato,main: nonmain longest=1, current=0.
  [ "$(read_count __nonmain_streak_longest)" = "1" ]
  [ "$(read_count __nonmain_streak_current)" = "0" ]
}

@test "non-main streak updates on consecutive non-main pulls" {
  # Sequence main, allucinato, rapput, patema, main → nonmain longest = 3.
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  bisio_record_pull "rapput" 30 80 >/dev/null
  bisio_record_pull "patema" 30 80 >/dev/null
  bisio_record_pull "main" 30 80 >/dev/null
  [ "$(read_count __nonmain_streak_longest)" = "3" ]
  [ "$(read_count __nonmain_streak_current)" = "0" ]
  [ "$(read_count __main_streak_longest)" = "1" ]
  [ "$(read_count __main_streak_current)" = "1" ]
  [ -f "$(hof_file)" ]
  grep -q 'Longest streak without seeing main bisio: <b>3 pulls</b>' "$(hof_file)"
  grep -q 'Longest streak of main bisio: <b>1 pulls</b>' "$(hof_file)"
}

@test "bisio_announce_completion is no-op without flag" {
  BISIO_DEX_JUST_COMPLETED=0 run bisio_announce_completion
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bisio_announce_completion plain-text fallback under !TTY" {
  # bats redirects stdout, so [ -t 1 ] is false → fallback path.
  BISIO_DEX_JUST_COMPLETED=1 BISIO_HOF_URL="file:///tmp/hof.html" \
    run bisio_announce_completion
  [ "$status" -eq 0 ]
  [[ "$output" == *"All Bisio discovered!"* ]]
  [[ "$output" == *"file:///tmp/hof.html"* ]]
  # No escape codes in fallback path.
  [[ "$output" != *$'\033'* ]]
}

@test "bisio_announce_completion is no-op when flag set but URL missing" {
  BISIO_DEX_JUST_COMPLETED=1 BISIO_HOF_URL="" run bisio_announce_completion
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
