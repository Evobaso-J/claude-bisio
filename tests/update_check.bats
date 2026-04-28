#!/usr/bin/env bats
# Update-check behavior tests. Each case isolates XDG_STATE_HOME, fake plugin
# dir, PATH-shadowed git stub, and stub update.sh.

setup() {
  TEST_TMP="$(mktemp -d)"
  export XDG_STATE_HOME="$TEST_TMP/state"
  export FAKE_REPO="$TEST_TMP/repo"
  mkdir -p "$FAKE_REPO/.git" "$FAKE_REPO/bin"

  # Local manifest pinned to 1.0.0 — the "current" version under test.
  printf '{ ".": "1.0.0" }\n' > "$FAKE_REPO/.release-please-manifest.json"

  # Stub update.sh: logs invocation, honors TEST_UPDATE_EXIT for failure tests.
  export STUB_LOG="$TEST_TMP/stub.log"
  : > "$STUB_LOG"
  cat > "$FAKE_REPO/update.sh" <<EOF
#!/bin/sh
echo "STUB_UPDATE_RAN" >> "$STUB_LOG"
exit "\${TEST_UPDATE_EXIT:-0}"
EOF
  chmod +x "$FAKE_REPO/update.sh"

  # PATH-shadow git so ls-remote returns canned output controlled by env vars.
  STUB_BIN="$TEST_TMP/stubbin"
  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/git" <<'EOF'
#!/bin/sh
# Drop -C <dir> if present.
if [ "$1" = "-C" ]; then shift 2; fi
case "$1" in
  ls-remote)
    if [ -n "${TEST_GIT_LSREMOTE_EXIT:-}" ] && [ "$TEST_GIT_LSREMOTE_EXIT" != "0" ]; then
      exit "$TEST_GIT_LSREMOTE_EXIT"
    fi
    [ -n "${TEST_GIT_LSREMOTE_OUTPUT:-}" ] && printf '%s\n' "$TEST_GIT_LSREMOTE_OUTPUT"
    ;;
  *)
    ;;
esac
EOF
  chmod +x "$STUB_BIN/git"
  export PATH="$STUB_BIN:$PATH"

  export CLAUDE_BISIO_DIR="$FAKE_REPO"
  unset CLAUDE_BISIO_CHECK_UPDATES
  unset CLAUDE_BISIO_UPDATE_TTL_MIN
  unset TEST_GIT_LSREMOTE_OUTPUT TEST_GIT_LSREMOTE_EXIT TEST_UPDATE_EXIT

  # shellcheck source=../bin/_update_check.sh
  . "$BATS_TEST_DIRNAME/../bin/_update_check.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
}

state_dir() { printf '%s/claude-bisio' "$XDG_STATE_HOME"; }
cache_file() { printf '%s/latest-version' "$(state_dir)"; }
sentinel_file() { printf '%s/last-update-check' "$(state_dir)"; }
dismissed_file() { printf '%s/dismissed-version' "$(state_dir)"; }

@test "fetch writes cache and touches sentinel on git success" {
  export TEST_GIT_LSREMOTE_OUTPUT='abc123 refs/tags/v1.1.0'
  bisio_update_fetch
  [ -f "$(cache_file)" ]
  [ "$(cat "$(cache_file)")" = "1.1.0" ]
  [ -f "$(sentinel_file)" ]
}

@test "fetch silent and sentinel touched on git failure" {
  export TEST_GIT_LSREMOTE_EXIT=1
  bisio_update_fetch
  [ ! -f "$(cache_file)" ]
  [ -f "$(sentinel_file)" ]
}

@test "fetch picks newest tag via sort -V" {
  export TEST_GIT_LSREMOTE_OUTPUT='aaa refs/tags/v0.1.0
bbb refs/tags/v1.0.0
ccc refs/tags/v1.10.0
ddd refs/tags/v1.2.0'
  bisio_update_fetch
  [ "$(cat "$(cache_file)")" = "1.10.0" ]
}

@test "fetch silent when .git missing" {
  rm -rf "$FAKE_REPO/.git"
  export TEST_GIT_LSREMOTE_OUTPUT='abc refs/tags/v1.1.0'
  bisio_update_fetch
  [ ! -f "$(cache_file)" ]
  # Sentinel still touched (TTL still arms, even on quick-bail).
  [ -f "$(sentinel_file)" ]
}

@test "prompt no-op when local equals cached remote" {
  mkdir -p "$(state_dir)"
  printf '1.0.0\n' > "$(cache_file)"
  run bisio_update_prompt
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$(dismissed_file)" ]
}

@test "prompt no-op when remote equals dismissed" {
  mkdir -p "$(state_dir)"
  printf '1.1.0\n' > "$(cache_file)"
  printf '1.1.0\n' > "$(dismissed_file)"
  run bisio_update_prompt
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prompt fires when remote is newer than dismissed" {
  mkdir -p "$(state_dir)"
  printf '1.2.0\n' > "$(cache_file)"
  printf '1.1.0\n' > "$(dismissed_file)"
  out=$(printf 'n\n' | bisio_update_prompt 2>&1)
  [[ "$out" == *"v1.0.0"* ]]
  [[ "$out" == *"v1.2.0"* ]]
  [ "$(cat "$(dismissed_file)")" = "1.2.0" ]
}

@test "prompt N writes dismissed-version" {
  mkdir -p "$(state_dir)"
  printf '1.1.0\n' > "$(cache_file)"
  out=$(printf 'n\n' | bisio_update_prompt 2>&1)
  [ "$(cat "$(dismissed_file)")" = "1.1.0" ]
  ! grep -q "STUB_UPDATE_RAN" "$STUB_LOG"
}

@test "prompt empty answer (just Enter) treated as N" {
  mkdir -p "$(state_dir)"
  printf '1.1.0\n' > "$(cache_file)"
  out=$(printf '\n' | bisio_update_prompt 2>&1)
  [ "$(cat "$(dismissed_file)")" = "1.1.0" ]
  ! grep -q "STUB_UPDATE_RAN" "$STUB_LOG"
}

@test "prompt Y runs update.sh and does not write dismissed" {
  mkdir -p "$(state_dir)"
  printf '1.1.0\n' > "$(cache_file)"
  out=$(printf 'y\n' | bisio_update_prompt 2>&1)
  grep -q "STUB_UPDATE_RAN" "$STUB_LOG"
  [ ! -f "$(dismissed_file)" ]
}

@test "prompt Y with update.sh failure prints stderr but returns 0" {
  mkdir -p "$(state_dir)"
  printf '1.1.0\n' > "$(cache_file)"
  export TEST_UPDATE_EXIT=1
  out=$(printf 'y\n' | bisio_update_prompt 2>&1)
  [[ "$out" == *"update failed"* ]]
  grep -q "STUB_UPDATE_RAN" "$STUB_LOG"
}

@test "prompt no-op when cache absent" {
  run bisio_update_prompt
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prompt no-op when manifest missing" {
  rm -f "$FAKE_REPO/.release-please-manifest.json"
  mkdir -p "$(state_dir)"
  printf '1.1.0\n' > "$(cache_file)"
  run bisio_update_prompt
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prompt no-op when manifest malformed" {
  printf 'not json at all\n' > "$FAKE_REPO/.release-please-manifest.json"
  mkdir -p "$(state_dir)"
  printf '1.1.0\n' > "$(cache_file)"
  run bisio_update_prompt
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ttl stale when sentinel missing" {
  mkdir -p "$(state_dir)"
  run _bisio_update_ttl_stale
  [ "$status" -eq 0 ]
}

@test "ttl fresh when sentinel touched and TTL high" {
  mkdir -p "$(state_dir)"
  touch "$(sentinel_file)"
  CLAUDE_BISIO_UPDATE_TTL_MIN=99999 run _bisio_update_ttl_stale
  [ "$status" -eq 1 ]
}

@test "check disabled by env var skips fetch and prompt" {
  export TEST_GIT_LSREMOTE_OUTPUT='abc refs/tags/v1.1.0'
  CLAUDE_BISIO_CHECK_UPDATES=0 run bisio_update_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$(cache_file)" ]
  [ ! -f "$(sentinel_file)" ]
}
