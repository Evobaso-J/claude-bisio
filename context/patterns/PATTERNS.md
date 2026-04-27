# Patterns

<!-- exodia:section:intro -->
Shell idioms used across `bin/`. Read this before introducing new shell code or env vars.

## Component / Module Conventions

<!-- exodia:section:components -->
- POSIX sh only in `bin/*.sh`. The shebang is `#!/bin/sh` for executables; sourced files (`_counter.sh`, `_pick_portrait.sh`, `banner.config.sh`) carry `# shellcheck shell=sh`.
- File naming: `bin/_<helper>.sh` for sourced-only files (underscore prefix); plain names for executables.
- `set -u` at top of executables; `set -eu` for install/update bootstrappers (see `install.sh:16`, `update.sh:13`).
- Asset files use `NN-slug.<ext>` naming; the two-digit prefix is a canonical-membership gate, not cosmetic. The picker globs `[0-9][0-9]-*.png` and silently skips unprefixed files (see `bin/_pick_portrait.sh:18`, `bin/_counter.sh:201`).

## Reusable Utilities

<!-- exodia:section:utilities -->
- `bisio_pick_portrait <dir>` — `bin/_pick_portrait.sh`. Weighted-random selection from `assets/bisio/`. Reads `BISIO_WEIGHT_<UPPER>` per slug. Subshell body keeps `set --` mutation out of caller.
- `bisio_record_pull <slug> <rows> <cols> [back]` — `bin/_counter.sh`. Increments count, updates streaks, exports `BISIO_DEX_*` vars, writes Hall of Fame on completion edge. Idempotent on opt-out (`CLAUDE_BISIO_NO_COUNTER=1`).
- `bisio_record_miss` — `bin/_counter.sh`. Bumps `__missed_banner` metadata. Called when banner bails before render.
- `bisio_announce_completion` — `bin/_counter.sh`. No-op unless `BISIO_DEX_JUST_COMPLETED=1` and `BISIO_HOF_URL` set in current process.
- Config defaults: `: "${VAR=default}"` in `bin/banner.config.sh`. An exported value (including explicit empty string) wins. `export` is required because the renderer runs in a subprocess.

## API & External Services

<!-- exodia:section:api -->
External commands used: `chafa` (PNG → ANSI), `git` (install/update), `awk`, `stty`, `shasum` / `sha256sum`, `base64`, `mktemp`, `figlet` artifacts (pre-rendered into `assets/title-*.txt`). All optional except `chafa` for the rich render path; `assets/bisio-fallback.txt` is the chafa-missing fallback.

Chafa is invoked once per layout decision. Render cache key: `v1-${png_sha:0:8}-${flags_sha:0:8}/${pw}x${ph}.ans`. PNG sha is over the file bytes; flags sha is over the assembled `$*` chafa flag string. Both shas degrade to `nosha` if neither `shasum` nor `sha256sum` is on PATH (see `bin/banner.sh:202-209`).

## Authentication

<!-- exodia:section:auth -->
N/A — purely local plugin, no network calls beyond the user-triggered `git pull` in `update.sh`.

## Observability / Telemetry (if applicable)

<!-- exodia:section:tracking -->
No telemetry leaves the machine. Local instrumentation:

- `counts.txt` — per-variant pull counts + `__metadata` keys (`__main_streak_current`, `__main_streak_longest`, `__nonmain_streak_*`, `__missed_banner`).
- `hall-of-fame.html` — generated on completion edge; embeds variant tiles as base64 data URIs so the file is self-contained.
- `hint-shown`, `first-shown` sentinels under `$XDG_STATE_HOME/claude-bisio/` — one-shot flags.

## Testing

<!-- exodia:section:testing -->
- bats: `bats tests/` (see `tests/counter.bats`). Each test isolates `XDG_STATE_HOME` and a fake repo via `mktemp -d`. Direct function calls (not `run`) when exported `BISIO_DEX_*` vars must propagate.
- shellcheck: `shellcheck --severity=error bin/*.sh` (errors-only sweep) and `shellcheck bin/_counter.sh` (strict). CI definition: `.github/workflows/test.yml`.

## Accessibility & i18n (if applicable)

<!-- exodia:section:a11y -->
Terminal accessibility:
- Banner gates on TTY: skipped under non-TTY stdin/stdout (see `claude-bisio.plugin.zsh:7`).
- Static ASCII fallback at `assets/bisio-fallback.txt` when `chafa` is missing.
- Hall of Fame plain-text fallback in `bisio_announce_completion` under non-TTY (see `bin/_counter.sh:171-175`).
- No i18n. UI strings are English.

## L3 Data

<!-- exodia:section:l3 -->
- `reviews.jsonl`: PR review checks, migrations, anti-patterns.
