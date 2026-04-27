#!/usr/bin/env bats
# Counter behavior tests. Each case isolates XDG_STATE_HOME + a fake repo.

setup() {
  TEST_TMP="$(mktemp -d)"
  export XDG_STATE_HOME="$TEST_TMP/state"
  export FAKE_REPO="$TEST_TMP/repo"
  mkdir -p "$FAKE_REPO/assets/bisio" "$FAKE_REPO/bin"

  # Files are NN-slug.png — the NN- prefix is the canonical-membership gate.
  for entry in "01-main" "02-allucinato" "03-rapput" "04-patema"; do
    : > "$FAKE_REPO/assets/bisio/${entry}.png"
  done

  # HoF render needs the static template at $repo_dir/assets/hof-template.html.
  cp "$BATS_TEST_DIRNAME/../assets/hof-template.html" "$FAKE_REPO/assets/hof-template.html"

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
  [ "$BISIO_DEX_LATEST_NUM" = "01" ]
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
  grep -q 'Longest non-main streak' "$(hof_file)"
  # Tile headers carry the dex#.
  grep -q '<h3>#01 main</h3>' "$(hof_file)"
  grep -q '<h3>#02 allucinato</h3>' "$(hof_file)"
  grep -q '<h3>#03 rapput</h3>' "$(hof_file)"
  grep -q '<h3>#04 patema</h3>' "$(hof_file)"
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
  rm "$FAKE_REPO/assets/bisio/04-patema.png"
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
  : > "$FAKE_REPO/assets/bisio/05-solai.png"
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
  grep -q 'Longest non-main streak:.*<b>3 pulls</b>' "$(hof_file)"
  grep -q 'Longest streak of main bisio:.*<b>1 pulls</b>' "$(hof_file)"
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

read_str() {
  awk -v k="$1" '$1==k { print $2; exit }' "$(counts_file)"
}

@test "first random Bisio recorded on first non-main pull" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  [ "$(read_str __first_random_slug)" = "allucinato" ]
  [ "$(read_count __first_random_pull_n)" = "2" ]
}

@test "first random Bisio NOT overwritten by later non-main pulls" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  bisio_record_pull "rapput" 30 80 >/dev/null
  [ "$(read_str __first_random_slug)" = "allucinato" ]
  [ "$(read_count __first_random_pull_n)" = "2" ]
}

@test "dup streak tracked across consecutive same-slug pulls" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  [ "$(read_count __dup_streak_longest)" = "3" ]
  [ "$(read_str __dup_streak_slug)" = "main" ]
  [ "$(read_count __dup_streak_current)" = "1" ]
}

@test "all-different streak tracked across distinct pulls" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  bisio_record_pull "rapput" 30 80 >/dev/null
  bisio_record_pull "patema" 30 80 >/dev/null
  [ "$(read_count __diff_streak_longest)" = "4" ]
  v=$(read_str __diff_streak_set)
  case "$v" in
    *main*allucinato*rapput*patema*) ;;
    *) printf 'unexpected diff_set: %s\n' "$v" >&2; return 1 ;;
  esac
}

@test "all-different streak resets on repeat slug" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  bisio_record_pull "main" 30 80 >/dev/null
  [ "$(read_count __diff_streak_current)" = "1" ]
  [ "$(read_count __diff_streak_longest)" = "2" ]
  [ "$(read_str __diff_streak_set)" = "main" ]
}

@test "RNG sanity panel uses scrollable table wrapper" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  bisio_record_pull "rapput" 30 80 >/dev/null
  bisio_record_pull "patema" 30 80 >/dev/null
  grep -q 'class="table-wrap table-scroll"' "$(hof_file)"
  ! grep -q '<h2>Distribution</h2>' "$(hof_file)"
  ! grep -q '<div class="panels-2col">' "$(hof_file)"
}

@test "RNG sanity table rendered with delta classes" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  bisio_record_pull "rapput" 30 80 >/dev/null
  bisio_record_pull "patema" 30 80 >/dev/null
  grep -q '<h2>RNG sanity</h2>' "$(hof_file)"
  grep -q '>Actual %<' "$(hof_file)"
  grep -q '>Expected %<' "$(hof_file)"
  # 4 pulls, even split → main is 25% actual vs 45% expected → -20% → delta-bad.
  grep -q 'class="num delta-bad">-20.0%' "$(hof_file)"
}

@test "comma-joined metadata value parses and round-trips" {
  state="$XDG_STATE_HOME/claude-bisio"
  mkdir -p "$state"
  cat <<'EOF' > "$state/counts.txt"
main 1
allucinato 1
rapput 1
__diff_streak_current 3
__diff_streak_longest 3
__diff_streak_set main,allucinato,rapput
__last_slug rapput
__main_streak_current 0
__main_streak_longest 1
__nonmain_streak_current 2
__nonmain_streak_longest 2
EOF
  bisio_record_pull "patema" 30 80 >/dev/null
  v=$(read_str __diff_streak_set)
  case "$v" in
    *main*allucinato*rapput*patema*) ;;
    *) printf 'unexpected diff_set after parse: %s\n' "$v" >&2; return 1 ;;
  esac
  [ "$(read_count __diff_streak_longest)" = "4" ]
}

@test "malformed string-value line is skipped (forward compat)" {
  state="$XDG_STATE_HOME/claude-bisio"
  mkdir -p "$state"
  cat <<'EOF' > "$state/counts.txt"
main 1
__foo bar baz
EOF
  run bisio_record_pull "allucinato" 30 80
  [ "$status" -eq 0 ]
  [ "$(read_count main)" = "1" ]
  [ "$(read_count allucinato)" = "1" ]
  # __foo line dropped because it doesn't match either regex.
  ! grep -q '^__foo ' "$(counts_file)"
}

@test "string metadata survives a bisio_record_miss call" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  bisio_record_miss
  [ "$(read_str __last_slug)" = "allucinato" ]
  [ "$(read_str __first_random_slug)" = "allucinato" ]
  [ "$(read_count __missed_banner)" = "1" ]
}

@test "__first_pull_epoch lazily set on first pull, near current time" {
  before=$(date +%s)
  bisio_record_pull "main" 30 80 >/dev/null
  after=$(date +%s)
  epoch=$(read_count __first_pull_epoch)
  [ -n "$epoch" ]
  [ "$epoch" -ge "$before" ]
  [ "$epoch" -le "$after" ]
}

@test "__first_pull_epoch is not overwritten on subsequent pulls" {
  bisio_record_pull "main" 30 80 >/dev/null
  first=$(read_count __first_pull_epoch)
  sleep 1
  bisio_record_pull "allucinato" 30 80 >/dev/null
  [ "$(read_count __first_pull_epoch)" = "$first" ]
}

@test "completion edge renders Completion time stat with a duration" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  bisio_record_pull "rapput" 30 80 >/dev/null
  bisio_record_pull "patema" 30 80 >/dev/null
  [ -f "$(hof_file)" ]
  grep -Eq 'Completion time:.*<b>[0-9]+[smhd]' "$(hof_file)"
}

@test "legacy state without __first_pull_epoch renders Completion time as unknown" {
  bisio_record_pull "main" 30 80 >/dev/null
  bisio_record_pull "allucinato" 30 80 >/dev/null
  bisio_record_pull "rapput" 30 80 >/dev/null
  # Strip the lazy-init epoch to simulate state from before this stat existed.
  awk '$1 != "__first_pull_epoch"' "$(counts_file)" > "$TEST_TMP/counts.scrubbed"
  mv "$TEST_TMP/counts.scrubbed" "$(counts_file)"
  bisio_record_pull "patema" 30 80 >/dev/null
  [ -f "$(hof_file)" ]
  grep -q 'Completion time:.*<b>unknown</b>' "$(hof_file)"
}
