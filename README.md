# claude-bisio

A zsh wrapper that prints a Claudio Bisio ASCII-art banner before launching the [Claude Code](https://claude.com/claude-code) CLI.

Pun on "claude" — the actor Claudio Bisio greets you every time you run `claude`.

## Install

### As an oh-my-zsh custom plugin

```sh
git clone https://github.com/Evobaso-J/claude-bisio \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/claude-bisio"
```

Then add `claude-bisio` to the `plugins=(...)` line in your `~/.zshrc` and reload:

```sh
exec zsh
```

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

Remove the plugin from `plugins=(...)` (oh-my-zsh), or delete the `source` line from `~/.zshrc` (manual install). To bypass the wrapper for a single invocation: `command claude ...`.

## Requirements

- `zsh`
- [`claude`](https://claude.com/claude-code) on `$PATH`
- An interactive terminal (the banner auto-skips for pipes and non-TTYs)

## Roadmap

- v0.2: auto-resize banner to terminal width/height
- v0.3: optional `chafa` re-render from the bundled source image
- v0.4: `CLAUDE_BISIO_QUIET`, `CLAUDE_BISIO_CENTER`, subcommand CLI

## License

MIT — see [LICENSE](LICENSE).

Source portrait: `assets/bisio.png`.
