# Domain

<!-- exodia:section:intro -->
The "in-world" concepts the plugin presents to the user: variants, the Bisiodex collection, the Hall of Fame. Read this when touching anything user-visible (banner output, naming, state semantics).

## Entities

<!-- exodia:section:entities -->
- **Variant** — a Claudio Bisio portrait. Source of truth: `assets/bisio/NN-slug.png`. Canonical set is the intersection of (PNG with `NN-` prefix) ∩ (positive `BISIO_WEIGHT_<UPPER>` defined in `bin/banner.config.sh`). Current canonical members: `main`, `allucinato`, `rapput`, `patema` (see `bin/banner.config.sh:55-58`).
- **Bisiodex** — the user's collection state. Persisted as KV pairs in `counts.txt`. Surfaced to the banner via `BISIO_DEX_CAUGHT`, `BISIO_DEX_TOTAL`, `BISIO_DEX_LATEST`, `BISIO_DEX_NEW`, `BISIO_DEX_LATEST_NUM` (see `bin/_counter.sh:347-363`).
- **Hall of Fame** — the completion-edge artifact. Self-contained HTML at `${XDG_STATE_HOME}/claude-bisio/hall-of-fame.html`. Renderer: `_bisio_render_html` (`bin/_counter.sh:51-130`). Includes per-variant tiles, longest main / non-main streaks, missed-banner count.
- **Pull** — one banner-rendered launch where a variant was shown. Recorded by `bisio_record_pull`. Banner bails before rendering count as **misses** (`bisio_record_miss`).
- **Streak** — consecutive runs of `main` (`__main_streak_*`) or non-`main` (`__nonmain_streak_*`). Rules: see `bin/_counter.sh:261-273`.

## Relationships

<!-- exodia:section:relationships -->
- Variant **belongs to** Bisiodex (all canonical variants are dex entries; non-canonical pulls are recorded but pruned from state on next write).
- Pull **increments** Variant count and **updates** streaks.
- Bisiodex **completes** when every canonical variant has count > 0. The transition `pre_complete=0 → post_complete=1` triggers Hall of Fame generation (`bin/_counter.sh:367`).
- Adding a new variant after completion **re-arms** the edge: completion fires again on the next pull that fills the new slot (validated by `tests/counter.bats:127-137`).

## User Journey

<!-- exodia:section:journey -->
1. User installs (`install.sh` or plugin manager).
2. User runs `claude` → banner renders the **main** variant on first launch (forced via `first-shown` sentinel; see `bin/banner.sh:41-45`).
3. Subsequent bare `claude` runs draw a weighted-random variant.
4. Counter records each pull; new variants flag `BISIO_DEX_NEW=1` and the dex bar shows "New Bisio discovered…".
5. On the launch that catches the final canonical variant, the dex bar fills `4/4`, then the celebration line prints with an `OSC 8` hyperlink to `hall-of-fame.html`.
6. `claudiosay` is locked to **main** until the Hall of Fame file exists (see `bin/claudiosay.sh:67-73`); after completion it draws weighted-random.

## Type System

<!-- exodia:section:types -->
No type system. Domain entities live as:
- Filename conventions (`NN-slug.png`).
- Env var naming convention (`BISIO_WEIGHT_<UPPER_SLUG>`, `BISIO_DEX_*`).
- KV records in `counts.txt` (regex gate: `^[A-Za-z0-9_]+ [0-9]+$`; see `bin/_counter.sh:246`).
- Specs at repo root: `BISIO_COUNTER_SPEC.md` (v0.3 counter), `BISIO_HOF_SPEC.md` (v0.4 hall of fame). These are the locked-decision sources for behavioral semantics.

## L3 Data

<!-- exodia:section:l3 -->
- `glossary.yaml`: extended terminology and synonyms.
