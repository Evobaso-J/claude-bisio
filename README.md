# claude-bisio 👨🏻‍🦲

Claudio Bisio greets you every time you run `claude`! 👋

A zsh wrapper that prints a Claudio Bisio banner before launching the [Claude Code](https://claude.com/claude-code) CLI. Falls back to a static ASCII portrait if `chafa` isn't installed.

Ships with the [claudiosay](#claudiosay) utility that pipes messages through Bisio's mouth.

<img src="assets/bisio-preview.gif" alt="claude-bisio banner preview" width="800">

## 🚀 Quick install

One paste - installs `chafa` (via your package manager), clones the plugin to `~/.claude-bisio`, and wires it into `~/.zshrc`:

```sh
curl -fsSL https://raw.githubusercontent.com/Evobaso-J/claude-bisio/main/install.sh | sh
```

Prefer not to pipe `curl` into `sh`? Same result, two steps:

```sh
git clone https://github.com/Evobaso-J/claude-bisio ~/.claude-bisio
~/.claude-bisio/install.sh
```

Then `exec zsh`.

Supported: macOS (Homebrew), Linux (`apt-get` / `dnf` / `pacman` / `zypper` / `apk`). Windows: use WSL.

### 🔄 Update

Fast-forward pull on the existing clone:

```sh
curl -fsSL https://raw.githubusercontent.com/Evobaso-J/claude-bisio/main/update.sh | sh
```

Or directly: `~/.claude-bisio/update.sh` (equivalently `git -C ~/.claude-bisio pull`).

## ▶️ Usage

After install, run `claude` as usual. Banner prints only on bare `claude` (no args) in an interactive TTY, then the real Claude Code CLI starts. Any args skip the banner and forward straight through.

```sh
claude              # banner + CLI
claude --version    # no banner, args forwarded
claude -p "refactor this function" # no banner, args forwarded
```

### 💬 claudiosay

Who needs `cowsay` when you can replace the cow with Claudio Bisio?
Pass the message as args or pipe it on stdin:

```sh
claudiosay 'solai'
echo 'solai' | claudiosay
git log -1 --format=%s | claudiosay
```

## 🎱 Catch 'em all

Each `claude` launch picks a portrait at random. Several Bisios roam the wild 🌿 and a lucky few have glimpsed the rarest ✨. What happens if you discover them all?

## 🛑 Disable

Remove the plugin entry (zinit/antigen/zplug/sheldon/oh-my-zsh) or delete the `source` line (manual install) from your config.

## 📋 Requirements

- `zsh`
- [`claude`](https://claude.com/claude-code) on `$PATH`
- Interactive terminal (banner auto-skips for pipes and non-TTYs)
- [`chafa`](https://hpjansson.org/chafa/) required - installed automatically by `install.sh`. Without it, the banner is silently skipped.

## ⚙️ Configuration

`chafa` flags live in [`bin/banner.config.sh`](bin/banner.config.sh): symbol set, color depth, dithering, fg-only, etc. Edit, save, run `claude` - render cache auto-invalidates on flag change.

`CLAUDE_BISIO_RESERVE` (default `4`) sets rows reserved at the bottom of the viewport for Claude's own welcome box + prompt, so the banner shrinks to fit. Increase if you still see overflow; decrease if there's excess blank space below the banner.

`CLAUDE_BISIO_MAX_HEIGHT` (default `40`) caps portrait rows so the image doesn't fill the entire viewport on tall terminals. Independent of `CLAUDE_BISIO_RESERVE`: reserve protects the bottom, this caps the top.

Every variable above can be overridden by exporting it in `~/.zshrc` (before the plugin source line): see [`bin/banner.config.sh`](bin/banner.config.sh) for overridable defaults. For example, to disable colors and dithering:

```sh
export CHAFA_SYMBOLS=ascii
export CHAFA_COLORS=full
export CLAUDE_BISIO_MAX_HEIGHT=30
```

## 📜 License

MIT - see [LICENSE](LICENSE).
