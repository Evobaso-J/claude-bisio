# Debugging

<!-- exodia:section:intro -->
How to diagnose problems with the banner, counter, or install path. Start here when something breaks. **Before reattempting any SessionStart-hook or `/dev/tty`-based approach, read `architecture/decisions.jsonl` `a001` (current architecture) + `a008` (historical attempt log) and the linked `g002`–`g011` gotchas in this module.** That path was tried across five reverted commits; each failure mode is captured.

## Local Environment Setup

<!-- exodia:section:env-setup -->
Requirements (see `README.md` § Requirements):
- `zsh` (interactive)
- `claude` on `$PATH`
- `chafa` (mandatory; banner is silently skipped without it)

For test runs:
- `bats` — see `.github/workflows/test.yml:14-17` for CI install (`sudo apt-get install -y bats shellcheck` on Ubuntu).
- `shellcheck` — same source.

State + cache locations (delete to reset): `${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio/` and `${XDG_CACHE_HOME:-$HOME/.cache}/claude-bisio/`.

## How to use this module

<!-- exodia:section:how-to-use -->
1. Reproduce the symptom.
2. Search `playbooks.jsonl` for matching symptoms.
3. If found → follow the playbook's fix.
4. If not found → once solved, append a new playbook entry per the Self-Update Rules.
5. For recurring footguns (not tied to a specific bug), append to `gotchas.jsonl` instead.

## Common Topics

<!-- exodia:section:topics -->
- **Banner does not render** — gating is strict: bare `claude` only, both stdin and stdout must be TTY. Pipes / non-TTY output skip silently. See `claude-bisio.plugin.zsh:7`.
- **Banner bails on small terminals** — minimum 30 cols × 8 rows; below that → `_bisio_miss_and_exit` (records a miss). See `bin/banner.sh:60`.
- **`/dev/tty` and stty errors leak to stderr** — must wrap in subshell: `size=$( (stty size < /dev/tty) 2>/dev/null )`. The shell's open-error fires before the redirect's `2>/dev/null` takes effect. → gotcha `g001`.
- **Chafa missing** — banner silently skips via `_bisio_miss_and_exit`. `install.sh` provisions chafa per OS / package manager.
- **Cache stale** — invalidates automatically on PNG bytes or flag string change. To force: `rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/claude-bisio"`.
- **First-pull bias** — fresh state forces `01-main.png` regardless of weights, gated by `first-shown` sentinel (`bin/banner.sh:41-45`). Delete sentinel to reset that behavior.
- **Counter test isolation** — bats tests source `bin/_counter.sh` after setting `XDG_STATE_HOME` and a fake `repo_dir` (see `tests/counter.bats:23-26`). Tests calling `bisio_record_pull` directly (not via `run`) preserve exported `BISIO_DEX_*` vars; tests asserting stdout/exit status use `run`.
- **SessionStart-hook approach (do not retry)** — five commits (`cc1586c`..`c1d3f54`) attempted this and were reverted; per-commit attempt log lives in `architecture/decisions.jsonl` `a008`. Failure modes, each captured as a gotcha:
  - SessionStart is non-blocking; `/dev/tty` writes from a background hook fight CC's ink-style TUI (duplicate prompt, banner clipped) → `g002`, `g009`
  - Hook stdout is captured as model context (~1500–2000 tokens), no zero-token UI channel → `g003`
  - No plugin lifecycle hooks (PostInstall / OnEnable / PluginActivate) exist → `g010`
  - PowerShell hook entry on macOS triggers a CC-visible error → `g004`
  - stty / tput open errors leak past `2>/dev/null` → `g001`
  - Chafa tiering fixes content sizing, not placement → `g011`
- **Forward paths if revisited** — three viable approaches in `architecture/decisions.jsonl` `a007` (port wrapper to bash/fish/PowerShell, accept token cost via `additionalContext`, or wait for upstream UI-only channel). Four explicitly rejected paths linked there.

## L3 Data

<!-- exodia:section:l3 -->
- `gotchas.jsonl`: known footguns and how to avoid them.
- `playbooks.jsonl`: symptom → root cause → fix recipes.
