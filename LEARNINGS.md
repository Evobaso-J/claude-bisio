# LEARNINGS — Why we reverted the Claude Code plugin experiment

**TL;DR:** Claude Code's SessionStart hook cannot produce a clean splash banner in the TUI. The plugin approach is fundamentally unsuitable for a pre-prompt greeting. Use a shell wrapper instead.

This file records everything we tried between commits `cc1586c` and `c1d3f54`, so future-us (or anyone forking this repo) does not re-run the experiment.

---

## Constraints, discovered in order

### 1. SessionStart is non-blocking
CC launches SessionStart hooks in the background and continues rendering its TUI immediately. Any output the hook produces — stdout, stderr, or `/dev/tty` — races CC's own render. There is no way to tell CC "wait for this hook before painting."

Source: [hooks reference](https://code.claude.com/docs/en/hooks.md).

### 2. Hook stdout is captured as *model context*
Anything the hook prints on stdout is added to the system prompt for the model. An ASCII portrait is ~2 KB → ~1500–2000 tokens per fresh session. Stdout is *not* a free "display in UI" channel; it's a context-injection channel that CC happens to echo in the transcript.

### 3. There is no zero-token "display to user only" field
We looked for `hookSpecificOutput.systemMessage`, `.notice`, `.banner`, etc. None exist. The only hook output channels are:
- `stdout` → model context (tokens)
- `hookSpecificOutput.additionalContext` → model context (tokens)
- `stderr` → shown as hook error notice in CC UI (not tokens, but styled as error)
- `/dev/tty` → raw terminal write, bypasses CC entirely

### 4. `/dev/tty` writes fight CC's ink-based TUI renderer
CC renders with an ink-style React-to-TTY library. When a background process writes to `/dev/tty` after CC has drawn its TUI, CC's renderer sees the terminal state has shifted and redraws. Symptoms:
- **Duplicate input prompt** — the input box gets drawn twice as CC re-layouts.
- **Banner interleaved with UI** — half the banner appears, then CC re-paints over it, then more banner, then UI.
- **Banner clipped by CC's status bar / welcome header** — CC's later paints cover the top or right of the portrait.

See screenshot in chat history (turn where user reported "input line duplicated, banner cut"). A tiered chafa-downsampled portrait that fits the viewport did *not* fix this — the fight is structural, not about size.

### 5. No plugin lifecycle hooks
CC has no `PostInstall`, `OnEnable`, or `PluginActivate` event. A banner installed via `/plugin install` cannot confirm itself visually; the user must restart their session. Upstream tracking: [anthropics/claude-code#11240](https://github.com/anthropics/claude-code/issues/11240).

### 6. PowerShell hook on macOS = CC-visible error
Registering a second hook entry that invokes `powershell` on macOS triggers `/bin/sh: powershell: command not found`. CC surfaces this as a "SessionStart:startup hook error" notice that overlaps the banner. Fix: single sh hook that internally branches on `OS=Windows_NT` and delegates to PowerShell only when appropriate. (Shipped in `c715f55`.)

### 7. stty / tput open failures leak stderr
`stty size < /dev/tty 2>/dev/null` looks safe but isn't — the shell's own "Device not configured" error on a failed `< /dev/tty` redirect is emitted *before* stty's `2>/dev/null` takes effect. Must wrap in subshell: `size=$( (stty size < /dev/tty) 2>/dev/null )`. Same trick needed for the `> /dev/tty` write.

### 8. Chafa tiering works for content, not for placement
Shipping four pre-rendered portraits (xs/sm/md/lg, 16–50 rows) and picking by `stty size` gave clean, viewport-fitting visuals. Content was fine. But constraints #1 and #4 above still produced interleave artifacts on every tier.

---

## What we tried (in order of commits, all reverted)

| Commit | Attempt | Why it failed |
|--------|---------|---------------|
| `cc1586c` | Node hook writing to `/dev/tty` | Race; Node ~80 ms cold start loses to TUI |
| `b54835d` | Rename to `evobaso@claude-bisio` | Cosmetic only — install-command readability |
| `ed60151` | Replace Node with POSIX sh (1–5 ms fork) | Faster, still races TUI; duplicate prompt appeared |
| `c715f55` | Collapse sh + ps1 into single platform-dispatch | Removed `powershell not found` error; banner-cut issue remained |
| `c1d3f54` | Four chafa-rendered tiers sized to viewport | Visuals finally fit, but `/dev/tty` vs CC TUI fight unchanged |

---

## What works: the original zsh wrapper

The pre-plugin approach (`claude-bisio.plugin.zsh` from `db97f3f`) works cleanly because it runs **before** `claude` is invoked:

1. Shell alias replaces `claude` with `claude_with_banner`.
2. Function prints banner directly to the terminal.
3. Then `command claude "$@"` launches CC, which starts with a clean slate and draws its TUI normally.

No race. No TUI fight. No token cost. The one limitation: it's shell-specific (zsh only today).

---

## If someone picks this up again — viable paths

1. **Port the wrapper to bash / fish / PowerShell.** Distribute via Homebrew or npm so it installs as a binary on `$PATH` regardless of shell. This is the only known way to get a reliable pre-prompt banner across platforms.
2. **Accept the token cost.** Emit the banner via `hookSpecificOutput.additionalContext`. Banner shows in the transcript, not above the prompt. Costs ~1500–2000 tokens per fresh session (prompt cache amortizes within a session).
3. **Wait for CC to add a zero-token UI-only channel.** Track [anthropics/claude-code#11240](https://github.com/anthropics/claude-code/issues/11240) and any proposal for a `systemMessage` / `notice` field.

Do **not**:
- Re-try `/dev/tty` writes in a SessionStart hook and expect clean placement.
- Build a tiered-portrait system to fix placement — it doesn't.
- Add a PowerShell hook entry as a sibling to a sh entry without a platform guard.
