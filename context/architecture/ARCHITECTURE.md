# Architecture

<!-- exodia:section:intro -->
A zsh plugin that wraps `claude` with a pre-launch banner. Pure shell — no build step, no daemon, no server. The render pipeline runs once per invocation, **before** `claude` itself starts. Decision history: `decisions.jsonl` `a001` (why a wrapper, not a SessionStart hook) and `a008` (the five reverted hook-based attempts).

## Entry Points & Routing

<!-- exodia:section:routing -->
Single shell entry point sourced from `~/.zshrc`. The entrypoint defines three functions and one alias; there is no router, no command dispatcher.

### Key Files

- `claude-bisio.plugin.zsh` — defines `claude_with_banner`, `bisio`, `claudiosay`; aliases `claude='claude_with_banner'`. Captures plugin dir at source time via `${0:A:h}` and exports it as `CLAUDE_BISIO_DIR` to subprocesses.
- `bin/banner.sh` — invoked by `claude_with_banner` and `bisio`. Picks a portrait, renders via chafa with viewport-aware sizing, composes figlet titles, prints Bisiodex status line.
- `bin/claudiosay.sh` — invoked by `claudiosay`. Side-by-side portrait + speech bubble (cowsay-style).

Gating is identical across `claude_with_banner` and `bisio`: bare invocation only (`$# -eq 0`), interactive stdin and stdout (`[ -t 0 ] && [ -t 1 ]`).

## Modules & Boundaries

<!-- exodia:section:modules -->
- `bin/banner.sh` — render orchestrator (portrait pick → terminal probe → layout choice → chafa render → cache → composition → counter hook).
- `bin/banner.config.sh` — sourced config; `: "${VAR=default}"` form so exported vars win.
- `bin/_pick_portrait.sh` — weighted-random picker (`bisio_pick_portrait`), variant-agnostic.
- `bin/_counter.sh` — collection state I/O. Public: `bisio_record_pull`, `bisio_record_miss`, `bisio_announce_completion`. Private: `_bisio_*` helpers, HTML render, awk state machine.
- `bin/claudiosay.sh` — standalone, reuses picker + chafa cache scheme from banner.sh.
- `assets/bisio/` — canonical PNGs (`NN-slug.png`); the `NN-` prefix is the canonical-membership gate (see `bin/_counter.sh:197-211`).
- `assets/bisio-fallback.txt`, `assets/title-*.txt` — static text assets composed by banner.sh.
- `tests/counter.bats` — counter logic only; isolates `XDG_STATE_HOME` per test.

## State Management

<!-- exodia:section:state -->
Two filesystem roots, both XDG-compliant. Paths defined in `bin/banner.sh:32-33` and `bin/_counter.sh:10-11`.

- `${XDG_CACHE_HOME:-$HOME/.cache}/claude-bisio/v1-<png_sha>-<flags_sha>/<WxH>.ans` — chafa render cache. Auto-invalidates when PNG bytes or chafa flag string change.
- `${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio/` — counts.txt (KV `slug count`, `__metadata` keys), `hall-of-fame.html`, `hint-shown` sentinel, `first-shown` sentinel.

State writes go through `mktemp` + `mv` rename for atomicity (see `bin/_counter.sh:220, 322, 372-379`).

## Build

<!-- exodia:section:build -->
No build step. Distributed as a git clone consumed directly by zsh. `install.sh` clones `$HOME/.claude-bisio` and appends a `source` line to `~/.zshrc`. `update.sh` is `git fetch --quiet origin <ref>` + `git merge --ff-only`.

## Runtime Model

<!-- exodia:section:runtime -->
Synchronous shell pipeline. `claude_with_banner` executes in the foreground in the user's interactive shell, runs `bin/banner.sh` to completion, then `exec`s `command claude "$@"`. There is no concurrency, no background hook, no IPC — the reason the SessionStart hook approach failed (race against Claude Code's TUI renderer; see gotcha `g009`) does not apply here.

## L3 Data

<!-- exodia:section:l3 -->
- `decisions.jsonl`: Architecture Decision Records for non-obvious choices. See also `BISIO_COUNTER_SPEC.md`, `BISIO_HOF_SPEC.md` at repo root for locked feature decisions.
