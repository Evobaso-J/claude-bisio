# claude-bisio

A zsh wrapper that prints a Claudio Bisio banner before launching the [Claude Code](https://claude.com/claude-code) CLI.

Claudio Bisio greets you every time you run `claude`. The banner auto-fits the terminal viewport: portrait rendered via [`chafa`](https://hpjansson.org/chafa/) when available, with composed `CLAUDE` / `BISIO` figlet titles. Falls back to a static ASCII portrait if `chafa` isn't installed.

![claude-bisio banner preview](assets/bisio-preview.png)

## Install

### Plugin managers (one-liner)

Pick your manager and add the line to `~/.zshrc`:

```sh
# zinit
zinit light Evobaso-J/claude-bisio

# antigen
antigen bundle Evobaso-J/claude-bisio

# zplug
zplug "Evobaso-J/claude-bisio"

# sheldon (~/.config/sheldon/plugins.toml)
[plugins.claude-bisio]
github = "Evobaso-J/claude-bisio"
```

Then `exec zsh`.

### oh-my-zsh custom plugin

```sh
git clone https://github.com/Evobaso-J/claude-bisio \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/claude-bisio"
```

Add `claude-bisio` to `plugins=(...)` in `~/.zshrc`, then `exec zsh`.

### Manual

```sh
git clone https://github.com/Evobaso-J/claude-bisio ~/.claude-bisio
echo 'source ~/.claude-bisio/claude-bisio.plugin.zsh' >> ~/.zshrc
exec zsh
```

## Usage

After install, just run `claude` as usual. The banner prints once per invocation, then the real Claude Code CLI starts normally. All arguments are forwarded.

```sh
claude --version
claude -p "refactor this function"
```

## Disable

Remove the plugin entry (zinit/antigen/zplug/sheldon/oh-my-zsh) or delete the `source` line (manual install) from your config. To bypass the wrapper for a single invocation: `command claude ...`.

## Requirements

- `zsh`
- [`claude`](https://claude.com/claude-code) on `$PATH`
- An interactive terminal (the banner auto-skips for pipes and non-TTYs)
- [`chafa`](https://hpjansson.org/chafa/) (optional, for the high-fidelity portrait render — a one-time install hint prints if missing, then the static ASCII fallback is used)

## Configuration

`chafa` flags live in [`bin/banner.config.sh`](bin/banner.config.sh): symbol set, color depth, dithering, fg-only, etc. Edit, save, run `claude` — the render cache auto-invalidates on flag change.

Layout picks itself based on terminal size:

- **side** — portrait left, titles right (wide terminals)
- **stacked** — portrait above, titles centered below (tall, narrow)
- **solo** — portrait only (very small)

## Roadmap

- v0.4: `CLAUDE_BISIO_QUIET`, `CLAUDE_BISIO_CENTER`, subcommand CLI

## License

MIT — see [LICENSE](LICENSE).

Source portrait: `assets/bisio.png`.
