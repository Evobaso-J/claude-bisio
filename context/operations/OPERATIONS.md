# Operations

<!-- exodia:section:intro -->
How the plugin gets onto a user's machine, how it stays current, what its CI does, and the per-variant axis the runtime cares about (portrait variants). No multi-environment deploy — this is a user-installed shell plugin.

## Environments

<!-- exodia:section:environments -->
Single execution environment: the user's interactive zsh session. State and cache live under XDG dirs:
- State: `${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio/`
- Cache: `${XDG_CACHE_HOME:-$HOME/.cache}/claude-bisio/`

CI runs on `ubuntu-latest` only (see `.github/workflows/test.yml:10`). macOS / Linux distinctions are runtime concerns handled by `install.sh` (package-manager dispatch).

Supported install hosts: macOS (Homebrew), Linux (`apt-get` / `dnf` / `pacman` / `zypper` / `apk`). Windows users go via WSL. Source: `install.sh:42-77`.

## Variants

<!-- exodia:section:variants -->
The runtime "variant" axis is the portrait set, not deployment targets. Canonical variants and weights live in `bin/banner.config.sh:55-58` (`BISIO_WEIGHT_MAIN`, `BISIO_WEIGHT_ALLUCINATO`, `BISIO_WEIGHT_RAPPUT`, `BISIO_WEIGHT_PATEMA`). Mapping table tracked in `variants.yaml`.

Adding a variant: drop `assets/bisio/NN-newslug.png` and add `BISIO_WEIGHT_NEWSLUG=<n>` in `bin/banner.config.sh`. Picker is variant-agnostic; counter rebuilds the canonical set on every `bisio_record_pull` call.

## Configuration System

<!-- exodia:section:config -->
- Defaults set in `bin/banner.config.sh` via `: "${VAR=default}"`. Sourced by `bin/banner.sh` and `bin/claudiosay.sh`.
- Override path: export the variable in `~/.zshrc` **before** the plugin source line. `export` is required because the renderer runs in a subprocess.
- Three config layers, evaluated in order: env (highest) → `banner.config.sh` defaults → hardcoded fallbacks inside `banner.sh` (e.g. `CLAUDE_BISIO_RESERVE` falls back to 14 inside `banner.sh:251` if both env and config are unset; this is intentional belt-and-braces).
- Cache invalidates automatically on flag change (sha keyed on `$*`; see `bin/banner.sh:227-233`).

Knobs: `CHAFA_*` (render flags), `CLAUDE_BISIO_RESERVE` / `CLAUDE_BISIO_MAX_HEIGHT` (viewport), `CLAUDE_BISIO_TITLE_COLOR`, `CLAUDE_BISIO_DEX_*` (dex bar), `CLAUDE_BISIO_NO_COUNTER` (opt-out).

## Deploy

<!-- exodia:section:deploy -->
- **CI**: `.github/workflows/test.yml` — runs on `push` to `main` and on `pull_request`. Steps: install bats + shellcheck via apt, run shellcheck (errors-only sweep on `bin/*.sh` + strict on `bin/_counter.sh`), run `bats tests/`.
- **Release**: no automated release pipeline. Distribution is via the `main` branch tip — `install.sh` clones with `--branch main --depth 1`, `update.sh` does `git merge --ff-only origin/main`. Version overrides via `CLAUDE_BISIO_REF`.
- **User install**: `curl … install.sh | sh` or git clone + `install.sh`. Plugin-manager users (zinit / antigen / zplug / sheldon / oh-my-zsh) skip `install.sh` for the source-line wiring but still need `chafa` separately.

## Localization / i18n (if applicable)

<!-- exodia:section:i18n -->
N/A. UI strings are English-only. The persona is Italian (Claudio Bisio) but in-app copy is not localized.

## L3 Data

<!-- exodia:section:l3 -->
- `variants.yaml`: portrait variants — slug, weight, dex#, source PNG.
