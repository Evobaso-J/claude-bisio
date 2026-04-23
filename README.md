# claude-bisio

A Claudio Bisio ASCII-art banner that greets you every time [Claude Code](https://claude.com/claude-code) starts a session.

Pun on "claude" — the Italian actor Claudio Bisio says hi before the CLI does.

## Install

### As a Claude Code plugin (recommended)

Works on macOS, Linux, and Windows. No shell setup, no aliases, no forgery of `claude`.

```sh
/plugin marketplace add Evobaso-J/claude-bisio
/plugin install evobaso@claude-bisio
```

The banner will show on every new Claude Code session. Requires Node.js on `$PATH` (bundled with most Claude Code installs).

### As an oh-my-zsh custom plugin (zsh only, legacy)

Prefer the Claude Code plugin above. This one is kept for zsh users who also want the banner when running `claude` *outside* Claude Code (e.g. `claude --version`).

```sh
git clone https://github.com/Evobaso-J/claude-bisio \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/claude-bisio"
```

Then add `claude-bisio` to the `plugins=(...)` line in your `~/.zshrc` and reload:

```sh
exec zsh
```

### Manual zsh source (legacy)

```sh
git clone https://github.com/Evobaso-J/claude-bisio ~/.claude-bisio
echo 'source ~/.claude-bisio/claude-bisio.plugin.zsh' >> ~/.zshrc
exec zsh
```

## How it works

- **Plugin mode:** a `SessionStart` hook (`hooks/banner.js`) writes the banner straight to `/dev/tty` (Unix) or the Windows console. It never touches the hook's stdout, so Claude Code does **not** inject it as model context — **zero token cost**.
- **Zsh mode:** a shell function wraps `claude` and prints the banner before delegating to `command claude "$@"`.

## Disable

- **Plugin mode:** `/plugin uninstall evobaso@claude-bisio`, or `/plugin disable evobaso@claude-bisio` to keep it installed but silent.
- **Zsh mode:** remove the plugin from `plugins=(...)`, or delete the `source` line from `~/.zshrc`. To bypass the wrapper for a single invocation: `command claude ...`.

## Requirements

- **Plugin mode:** Claude Code with plugin support, Node.js on `$PATH`, an interactive terminal.
- **Zsh mode:** `zsh`, `claude` on `$PATH`, an interactive terminal (the banner auto-skips for pipes and non-TTYs).

## Roadmap

- v0.2: auto-resize banner to terminal width/height
- v0.3: optional `chafa` re-render from the bundled source image
- v0.4: `CLAUDE_BISIO_QUIET`, `CLAUDE_BISIO_CENTER`, subcommand CLI

## License

MIT — see [LICENSE](LICENSE).

Source portrait: `assets/bisio.png`.
