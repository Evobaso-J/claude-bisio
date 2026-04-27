# Bisio Counter — feature spec (v0.3.0)

Handoff doc from grill session 2026-04-26. Branch: `feat/catch-them-all`.

Gamification feature for `claude-bisio`: track which Bisio variants the user has seen across `claude` launches, fire a milestone line when a new variant is pulled, fire a shareable prize card on full collection.

---

## Status (2026-04-27)

Superseded by `BISIO_HOF_SPEC.md` (v0.4.0). Following items **dropped** from v0.3 — replaced by the HTML Hall of Fame surface + single-line OSC 8 link:

- Q5 / Q16 / Q18 — terminal prize card (Unicode `╔═╗` box, full + compact tiers)
- Q6 — `collection-card.txt` persistence and `x.com/intent/tweet?text=…` share URL
- §"Prize card — full-box render", §"Prize card — compact render", §"`collection-card.txt`", §"Share URL template"
- POSIX percent-encode helper
- README env-var section for `CLAUDE_BISIO_NO_COUNTER` (deferred — anti-cheat-by-absence still applies)
- `CHANGELOG.md` v0.3.0 entry (deferred)

Completion edge now fires `_bisio_celebrate`: bold-yellow line + OSC 8 hyperlink to `hall-of-fame.html`. Plain-text fallback under `!TTY`.

Everything else in this spec — state schema, streak metadata, `__first_pull_epoch`, atomic write, opt-out, Bisiodex bar, new-variant glow, NN-prefix canonical gate, CI — shipped as written.

---

## Locked decisions

| # | Decision | Resolution |
|---|---|---|
| Q1 | Trigger | Only `claude` (banner-fired) increments. `bisio` standalone command will be removed soon (test-only). `claudiosay` excluded |
| Q2 | State schema | KV plain text. One line per key: `slug count\n`. POSIX-awk-friendly, no jq dep |
| Q3 | Canonical set | Filesystem scan `assets/bisio/*.png` ∩ slugs with positive `BISIO_WEIGHT_*` (mirrors picker logic). New PNG drop with new weight = auto-counts toward completion |
| Q4 | Display verbosity | Always-on **Bisiodex status line** under the BISIO title every launch: `▰▰▰▰▱▱▱▱▱▱  47/100`. Bold bright cyan. Counter is always rightmost. On a new-variant first pull the same line renders bold bright yellow with a `New Bisio discovered: #NN <slug>!   ` prefix (replaces the v0.3.0 cursor-jump overlay). Duplicate pulls show the line in normal color. Rendered by `banner.sh` from vars exported by `_counter.sh` |
| Q4.5 | Dex number | Every canonical variant carries a "dex number" derived from sorted-position of its slug in the canonical list. Source of truth: PNG filename prefix `NN-slug.png` (e.g. `01-main.png`, `02-allucinato.png`). The `NN-` prefix is the canonical-membership gate alongside positive `BISIO_WEIGHT_*` — unprefixed PNGs are silently skipped by both picker and counter. Dex# is always rendered zero-padded (`#02`). #1 is `main` |
| Q5 | Prize | ASCII text card with stats. No bespoke art asset |
| Q6 | Share mechanism | Inline render at completion (A) + persisted `collection-card.txt` to state dir (C) + `x.com/intent/tweet?text=…` URL printed (E) |
| Q7 | Opt-out | Single env var `CLAUDE_BISIO_NO_COUNTER=1` skips state read/write entirely |
| Q8 | Variant churn | Intersect-on-read. `effective_seen = state_keys ∩ canonical_set`. Lazy prune of non-canonical, non-metadata keys on next legit write |
| Q9 | Re-fire | Edge transition. `pre_complete = (seen ⊇ canonical)` snapshot, increment, `post_complete` snapshot. Fire iff `!pre && post`. No persistent "completed" flag |
| Q10 | Concurrency | Atomic write only (mktemp + mv same dir). No flock / mkdir-mutex. Worst case = one count off-by-one on simultaneous launches; acceptable |
| Q11 | Control surface | None. No new commands. No documented reset. Anti-cheat by absence-of-advertising. Power users can find/edit the file but normal users won't |
| Q12 | Identity (share card name) | `git config --global user.name` → `$USER` → `anonymous`. Auto chain, no override env |
| Q13 | Share URL prefill | Stat-heavy English (template below) |
| Q14 | Tests | Bats + fixtures + GitHub Actions CI. New `tests/counter.bats`, ~150 lines |
| Q15 | Picker / counter coupling | New file `bin/_counter.sh` exposing `bisio_record_pull` + `bisio_format_milestone_or_card`. Sourced only by `banner.sh`. Picker (`_pick_portrait.sh`) stays pure |
| Q15.5 | Increment site | Increment fires AFTER successful chafa render in `banner.sh`, NOT after pick. Skip-entirely paths must not increment. Rule: count only what the user actually saw |
| Q16 | Card visual | Unicode double-box `╔═╗║╚╝`. ~54 cols wide |
| Q17 | Ship scope | Single PR, single version bump → v0.3.0. No staged/feature-flagged rollout |
| Q18 | Narrow terminal | Tiered: `cols < 60` → compact stat lines (no box), `cols ≥ 60` → full double-box. `collection-card.txt` always full-format box (file is for sharing, not viewing) |
| Q19 | Tie-breaks | Composite sort. Primary count desc, secondary slug asc. Deterministic for tests |
| Q20 | Stat slot replacement | `Final catch: <triggering-slug> (pull #N)` + `Longest streak of main bisio: <N> pulls` + `Longest streak without seeing main bisio: <N> pulls`. No `Collection:` count row (the variant tile grid is the visual collection); no `Rarest:` row |
| Q21 | Time to completion | Track epoch of first-ever pull as metadata key `__first_pull_epoch`. On completion edge, render `Time to completion: <human-readable>` on prize card and include in share URL. Set lazily on first legit write if missing. Never overwritten. Pruned only if the entire state file is reset |

---

## State file

**Path:** `${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio/counts.txt`

(Sibling of existing `first-shown` sentinel created by `banner.sh`.)

**Format:** kv plain text. One line per key.

```
main 47
allucinato 18
rapput 12
patema 1
__main_streak_current 0
__main_streak_longest 12
__nonmain_streak_current 2
__nonmain_streak_longest 8
__first_pull_epoch 1745625600
```

**Parser rules:**
- Skip blank lines and lines failing regex `^[A-Za-z0-9_]+ [0-9]+$`
- Keys starting with `__` = metadata. Excluded from canonical/intersection logic. Never pruned
- Keys without `__` prefix and not present in canonical set = orphans. Pruned on next legit write (lazy)
- Atomic write: `mktemp` in same dir, write full file, `mv` over

**Streak metadata semantics:**
- On pull of `main`: `__main_streak_current += 1`; `__main_streak_longest = max(...)`; `__nonmain_streak_current = 0`
- On pull of any non-`main`: `__nonmain_streak_current += 1`; `__nonmain_streak_longest = max(...)`; `__main_streak_current = 0`
- Streak variant slug (`main`) hard-coded as constant in `_counter.sh`. If `01-main.png` ever renumbered/renamed, update the slug constant

**Time-to-completion metadata semantics:**
- `__first_pull_epoch` set lazily on first legit write iff the key is missing. Value: `date +%s` at write time. Never overwritten on subsequent writes
- On completion edge transition, compute `delta = now_epoch - __first_pull_epoch`
- Format: largest two non-zero units from `{d, h, m, s}`. Examples: `12d 4h`, `3h 27m`, `47s`, `2d 0h` (zero unit allowed only when leading unit needs a partner). Single-unit fallback when delta < 60s
- Edge case: if `__first_pull_epoch` is missing at completion (state file pre-dates v0.3.x or was hand-edited), render `Time to completion: unknown` and omit from share URL

---

## Architecture

### Files added

```
bin/_counter.sh              # ~120 lines. KV I/O, edge transition, card rendering
tests/counter.bats           # ~150 lines. Bats suite
tests/fixtures/              # Fake assets/bisio + state files for deterministic tests
.github/workflows/test.yml   # Bats + shellcheck on PR
```

### Files modified

```
bin/banner.sh                # Source _counter.sh, call bisio_record_pull post-render
README.md                    # Document CLAUDE_BISIO_NO_COUNTER ONLY (no reset, no path)
CHANGELOG.md (or release notes)  # v0.3.0 entry
```

### `_counter.sh` exports

```sh
# Reads state, applies pull, writes state, emits milestone line (if any) and card (if completion edge).
# Caller passes the slug that was just rendered, current rows/cols for narrow-tty branching,
# and lines_back: how many lines up from cursor the last visible banner row sits
# (solo=2 because of trailing `printf '\n'`; stacked=1; side=1). Defaults to 1.
bisio_record_pull <slug> <rows> <cols> [<lines_back>]
```

Internally it computes:
- pre/post completeness
- top-2-by-count + bottom-1-by-count (with composite tie-break)
- streak update for `main`
- milestone line vs prize card decision
- atomic state file write

### `banner.sh` integration

Increment hook lives at the **end of each successful render path** in the `case "$layout" in solo|stacked|side` block — after `cat "$cache_file"` actually emits the rendered output.

```sh
case "$layout" in
  solo) cat "$cache_file"; printf '\n'; rendered=1 ;;
  stacked) ... rendered=1 ;;
  side) ... rendered=1 ;;
esac

# Slug = basename of $png, stripped of NN- prefix and .png suffix
if [ "${rendered:-0}" = "1" ] && command -v bisio_record_pull >/dev/null 2>&1; then
  slug="${png##*/}"
  slug="${slug#[0-9][0-9]-}"
  slug="${slug%.png}"
  bisio_record_pull "$slug" "$rows" "$cols"
fi
```

Counter source file at top of `banner.sh`, sibling of picker source line:
```sh
counter="$repo_dir/bin/_counter.sh"
[ -f "$counter" ] && . "$counter"
```

`bisio_record_pull` itself respects the opt-out env var as its first line:
```sh
[ "${CLAUDE_BISIO_NO_COUNTER:-}" = "1" ] && return 0
```

---

## UX outputs

### Bisiodex status line (every launch)

Rendered by `banner.sh` directly under the BISIO title (or under the image in `solo`):

```
▰▰▰▰▱▱▱▱▱▱  47/100
```

- 10 segments. Filled = `CLAUDE_BISIO_DEX_FILLED` (default `▰`), empty = `CLAUDE_BISIO_DEX_EMPTY` (default `▱`). Round-to-nearest, never 0 unless `caught=0`, never 10 unless `caught≥total`.
- Counter (`C/T`) is always the rightmost element.
- Color = `CLAUDE_BISIO_DEX_COLOR` (default `1;96`, bold bright cyan).
- Position: centered under image in `solo`/`stacked`; left-padded by `pw + gutter` in `side` to anchor under the BISIO title.

`_counter.sh` exports four shell vars after every successful pull, consumed by `banner.sh`:

```
BISIO_DEX_CAUGHT=<n>          # canonical variants seen post-pull
BISIO_DEX_TOTAL=<N>           # canonical total
BISIO_DEX_LATEST=<slug>       # slug just pulled
BISIO_DEX_LATEST_NUM=<NN|"">  # zero-padded dex# of latest slug (empty if non-canonical)
BISIO_DEX_NEW=0|1             # 1 iff was_zero=1 && is_canonical=1
```

When `CLAUDE_BISIO_NO_COUNTER=1`, vars stay unset and the status line is skipped.

### New-variant glow

On the launch where a previously-uncaught canonical variant is pulled, the status line renders with `CLAUDE_BISIO_DEX_NEW_COLOR` (default `1;93`, bold bright yellow) and a leading `New Bisio discovered: <slug>!   ` prefix (counter still rightmost):

```
New Bisio discovered: #02 allucinato!   ▰▰▰▰▱▱▱▱▱▱  47/100
```

Next launch (no longer a new variant) returns to normal color, prefix dropped. Replaces the v0.3.0 absolute-positioned overlay.

### Prize card — full-box render (cols ≥ 60)

```
╔════════════════════════════════════════════════════╗
║  ✦✦✦  CLAUDE-BISIO  ✦✦✦                            ║
║  Full collection unlocked — 4/4                    ║
║                                                    ║
║  Andrea Basile · 2026-04-26                        ║
║  Total pulls: 78                                   ║
║  Time to completion: 12d 4h                        ║
║  Final catch: patema (pull #78)                    ║
║  Longest streak of main bisio: 12 pulls            ║
║  Longest streak without seeing main bisio: 8 pulls ║
║                                                    ║
║  github.com/Evobaso-J/claude-bisio                 ║
╚════════════════════════════════════════════════════╝

Share: https://x.com/intent/tweet?text=Caught%20them%20all%20%E2%9C%A6%20claude-bisio%204%2F4...
```

### Prize card — compact render (30 ≤ cols < 60)

```
✦✦✦ CLAUDE-BISIO — Full collection 4/4 ✦✦✦
Andrea Basile · 2026-04-26
Total pulls: 78
Time to completion: 12d 4h
Final catch: patema (pull #78)
Longest streak of main bisio: 12 pulls
Longest streak without seeing main bisio: 8 pulls
github.com/Evobaso-J/claude-bisio

Share: https://x.com/intent/tweet?text=...
```

### `collection-card.txt` — always full-box format regardless of terminal

Persisted to `${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio/collection-card.txt`. Idempotent — overwritten on each completion edge transition.

### Share URL template

Decoded:
```
Caught them all ✦ claude-bisio 4/4 in 12d 4h. Final catch: patema on pull #78. Longest main-bisio streak: 12. Longest main-less streak: 8. github.com/Evobaso-J/claude-bisio
```

URL-encoded into `https://x.com/intent/tweet?text=…`. POSIX `printf` + `awk` percent-encode helper. Char budget OK (~195 decoded). When `__first_pull_epoch` is missing, the `in <duration>` clause is dropped and the tweet falls back to the Q13-baseline wording.

---

## Tests (Bats coverage)

Each test isolates `XDG_STATE_HOME` to a temp dir + symlinks/copies fake `assets/bisio/` fixtures.

| Test | Setup | Asserts |
|---|---|---|
| First pull, fresh state | empty state, canonical={main,allucinato,rapput,patema} | counts.txt has `main 1`, milestone line `1/4`, no card |
| Duplicate pull, no milestone | state has `main 5` | post: `main 6`, no stdout line |
| Edge transition fires once | state has 3/4 distinct, pull the 4th | card rendered, `Final catch: <4th>`, card file written |
| Edge transition silent on subsequent | state has 4/4, pull any | no card, no milestone line |
| Variant retired, completion preserved | state has 4/4, canonical shrinks to 3 | no fire, intersection still complete, orphan key pruned on next write |
| Variant added post-completion, fresh fire | state has old 4/4, canonical grows to 5, pull the new one | card fires again with new totals |
| Opt-out env var | `CLAUDE_BISIO_NO_COUNTER=1` | state file untouched, no milestone, no card |
| Streak update on main | sequence of pulls main,main,main,allucinato,main | `__main_streak_longest = 3`, `__main_streak_current = 1`, `__nonmain_streak_longest = 1`, `__nonmain_streak_current = 0` |
| Streak update without main | sequence main,allucinato,rapput,patema,main | `__nonmain_streak_longest = 3`, `__nonmain_streak_current = 0`, HoF row reads `Longest streak without seeing main bisio: 3 pulls` |
| First-pull epoch set once | empty state, pull main, pull main again | `__first_pull_epoch` written on first pull, value unchanged after second pull |
| Time-to-completion rendered on edge | seed `__first_pull_epoch=now-12d-4h`, fixture canonical=4, pull the 4th | card shows `Time to completion: 12d 4h`, share URL contains `in%2012d%204h` |
| Time-to-completion missing on legacy state | seed full state with no `__first_pull_epoch`, pull the 4th | card shows `Time to completion: unknown`, share URL omits the `in <duration>` clause |
| Atomic write survives kill | simulated SIGKILL between mktemp + mv | original state file intact |
| Narrow-terminal compact card | cols=50, fire completion | compact card branch, share URL printed, file is full-box |
| Card persistence | fire completion | `collection-card.txt` exists, equals full-box format |

CI: GitHub Actions workflow runs `bats tests/` + `shellcheck bin/*.sh` on PR.

---

## Documentation surface

**README.md additions:**

Single section near the env-var docs:

> ### Counter
> `claude-bisio` quietly tracks which Bisio variants you've pulled. New variants surface a `✦ New Bisio` line; collecting them all unlocks a shareable card.
>
> Disable with `export CLAUDE_BISIO_NO_COUNTER=1` before sourcing the plugin.

**Intentionally NOT documented:**
- State file path
- Reset procedure
- The `__main_streak_*` and `__nonmain_streak_*` metadata keys
- Anything that would help a user "cheat" their collection

(Anti-cheat by absence; Q11.)

---

## Out of scope (deferred)

- `bisio-collection` inspect/reset command
- Multi-variant streak tracking (only `main` for v0.3)
- Schema versioning header line in counts.txt — add when needed
- Web-hosted completion landing page
- Per-completion "achievement timestamp" history
- Locale/i18n of share text

---

## Implementation order

1. `bin/_counter.sh` skeleton — KV read/write, atomic mv, opt-out guard
2. Edge-transition logic + intersection prune
3. Streak update for `main`
4. `__first_pull_epoch` lazy-init + duration formatter
5. Milestone line formatting
6. Card formatting (full + compact tiers)
7. Share URL builder + percent-encode helper
8. `banner.sh` integration — source counter, hook post-render
9. `tests/counter.bats` + fixtures
10. `.github/workflows/test.yml` (bats + shellcheck)
11. README env var docs
12. CHANGELOG / release notes for v0.3.0

---

## Open implementation questions (defer to coding chat)

- Exact percent-encode helper in POSIX sh (single awk vs `od`-based)
- `collection-card.txt` overwrite vs append-only (current decision: idempotent overwrite on each fire)
- Exact wording of the README env-var section
- Whether `update.sh` / `install.sh` need any edits (probably no — counter file is just another `bin/*.sh`)
