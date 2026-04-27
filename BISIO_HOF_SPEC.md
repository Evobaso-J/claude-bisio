# Bisio Hall-of-Fame — feature spec (v0.4.0)

Handoff doc from grill session 2026-04-26. Builds on `BISIO_COUNTER_SPEC.md` (v0.3.0). Branch: TBD.

Adds a stat-rich HTML "Hall of Fame" page rendered to the state directory on completion-edge transition. Sibling surface to the existing terminal `collection-card.txt`.

---

## Locked decisions

| # | Decision | Resolution |
|---|---|---|
| H1 | Surface | Static HTML file. No terminal output beyond a single line printing the file path next to the existing share URL |
| H2 | Path | `${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio/hall-of-fame.html` (sibling of `counts.txt` and `collection-card.txt`) |
| H3 | Render trigger | Completion-edge transition only (`!pre && post`). Same hook as the prize card. Pre-completion launches do NOT generate or update the file |
| H4 | Idempotency | Atomic overwrite on each completion edge (mktemp + mv same dir). Mirrors `collection-card.txt` |
| H5 | Concurrency | Inherits Q10 from v0.3 — atomic write only, no flock. HTML render fires after state is committed |
| H6 | Opt-out | `CLAUDE_BISIO_NO_COUNTER=1` skips HoF generation entirely (counter and HoF share the kill switch) |
| H7 | Documentation | Same anti-cheat-by-absence policy. README does not mention the file path. Console line at completion ("Hall of Fame: <path>") is the only discovery mechanism |
| H8 | Browser launch | None. Print path only. User opens manually. No `open`/`xdg-open` invocation (cross-platform pain, surprising side effect) |
| H9 | Static vs dynamic | Single self-contained HTML file. Inline CSS, no external assets, no JS dependency, no network fetch. Works offline, copy-pasteable |
| H10 | Asset embedding | Variant thumbnails referenced by relative path `../../../<repo>/assets/bisio/<slug>.png` is fragile. Decision: omit thumbnails in v0.4.0. Text-only stats. Defer image embedding (base64 inline) to v0.5 |

---

## New stats surfaced

Existing prize-card stats carry over (total pulls, final catch, longest main streak, longest non-main streak).

**Net-new on HoF page only:**

| Group | Item | Derivation |
|---|---|---|
| A | Per-variant table: slug \| pulls \| % of total | existing per-slug counts |
| A | Most-pulled variant + count | derived |
| A | RNG sanity table: actual % vs expected % from `BISIO_WEIGHT_*`, delta column | derived from counts + weight env vars |
| C-light | Longest dup streak: holder slug + run length | new metadata `__dup_streak_*` |
| C-light | Longest all-different streak: run length | new metadata `__diff_streak_*` |
| Extra | First random Bisio: slug + pull # (first non-`main` pull) | new metadata `__first_random_*` |
| Extra | Completion time: duration from first pull to dex completion | metadata `__first_pull_epoch` (semantics in `BISIO_COUNTER_SPEC.md` Q21) |

---

## State file additions

Same file: `${XDG_STATE_HOME:-$HOME/.local/state}/claude-bisio/counts.txt`. New metadata keys live alongside existing v0.3 keys.

```
__first_random_slug <slug>    # set on first non-main pull where slug != main && key absent
__first_random_pull_n <n>
__dup_streak_current <n>      # current run of same slug back-to-back
__dup_streak_longest <n>
__dup_streak_slug <slug>      # holder of longest dup record
__diff_streak_current <n>     # current run of distinct slugs
__diff_streak_longest <n>
__diff_streak_set a,b,c       # current run set, comma-joined
__last_slug <slug>            # dup detection + diff windowing
```

### Parser regex split (BREAKING from v0.3 single regex)

v0.3 used one regex for all lines: `^[A-Za-z0-9_]+ [0-9]+$`. v0.4 splits per key family:

```sh
# Canonical / count keys (no __ prefix). Values must be int.
canonical_re='^[A-Za-z0-9_]+ [0-9]+$'

# Metadata keys (__ prefix). Values may be int OR slug-like string OR comma-joined slug list.
metadata_re='^__[A-Za-z0-9_]+ [A-Za-z0-9_,-]+$'
```

Lines failing **both** regexes are silently skipped (forward-compat).

### Streak update rules (extends v0.3 main/non-main streak logic)

On every `bisio_record_pull <slug>`:

```
# Dup streak
if slug == __last_slug:
  __dup_streak_current += 1
else:
  __dup_streak_current = 1
if __dup_streak_current > __dup_streak_longest:
  __dup_streak_longest = __dup_streak_current
  __dup_streak_slug = slug

# All-different streak
if slug in __diff_streak_set:
  __diff_streak_current = 1
  __diff_streak_set = slug
else:
  __diff_streak_current += 1
  __diff_streak_set += "," + slug
if __diff_streak_current > __diff_streak_longest:
  __diff_streak_longest = __diff_streak_current

# First random
if __first_random_slug absent and slug != "main":
  __first_random_slug = slug
  __first_random_pull_n = pull_n_global

__last_slug = slug
```

`pull_n_global` = sum of all canonical-key counts post-increment (== total pulls). No new global counter needed.

---

## Architecture

### Files added

```
bin/_hof.sh                 # ~150 lines. HTML template render + percent-encode helper
tests/hof.bats              # ~100 lines. HTML structure assertions
tests/fixtures/hof/         # Snapshot HTMLs for diff comparison
```

### Files modified

```
bin/_counter.sh             # Extend bisio_record_pull with new metadata updates
                            # Call bisio_render_hof on completion edge
                            # Update parser regex split
README.md                   # No new env vars to document. No mention of HoF file
CHANGELOG.md                # v0.4.0 entry
```

### `_hof.sh` exports

```sh
# Reads current state, renders HTML to atomic temp file, mv to final path.
# Caller already verified completion edge fired.
bisio_render_hof <state_file> <hof_path> <repo_url> <user_name> <date_iso>
```

Internally:
- Parses canonical + metadata keys
- Computes derived stats (most-pulled, RNG delta, catch order)
- Reads `BISIO_WEIGHT_*` from environment (must be sourced from `banner.config.sh` upstream)
- Templates HTML via heredoc with `awk`/`printf` substitutions
- Atomic write

### `_counter.sh` integration

In `bisio_record_pull`, after completion-edge detection (`!pre && post`):

```sh
if [ "$pre_complete" = "0" ] && [ "$post_complete" = "1" ]; then
  bisio_render_card "$tmp_state"   # existing v0.3
  bisio_render_hof "$state_file" "$hof_path" "$repo_url" "$user_name" "$(date +%Y-%m-%d)"
  printf 'Hall of Fame: %s\n' "$hof_path"
fi
```

### `banner.sh` integration

No change beyond v0.3. `_counter.sh` handles the new branch internally.

---

## HTML structure (v0.4.0)

Single-file, inline CSS, no JS, no external fonts. Target ~400 lines incl. CSS.

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>claude-bisio — Hall of Fame</title>
  <style>/* inline, ~150 lines */</style>
</head>
<body>
  <header>
    <h1>✦ claude-bisio ✦</h1>
    <p class="subtitle">Hall of Fame</p>
    <p class="meta">{{user_name}} · {{date_iso}} · {{total_pulls}} pulls</p>
  </header>

  <section class="highlights">
    <!-- grid: Final catch, Most pulled, First random -->
  </section>

  <section class="streaks">
    <h2>Streaks</h2>
    <ul>
      <li>Longest main streak: {{main_longest}}</li>
      <li>Longest non-main streak: {{nonmain_longest}}</li>
      <li>Longest dup streak: {{dup_longest}} ({{dup_slug}})</li>
      <li>Longest all-different streak: {{diff_longest}}</li>
    </ul>
  </section>

  <section class="distribution">
    <h2>Distribution</h2>
    <table>
      <thead><tr><th>Variant</th><th>Pulls</th><th>%</th></tr></thead>
      <tbody><!-- per-variant rows, count desc --></tbody>
    </table>
  </section>

  <section class="rng-sanity">
    <h2>RNG sanity</h2>
    <table>
      <thead><tr><th>Variant</th><th>Actual %</th><th>Expected %</th><th>Δ</th></tr></thead>
      <tbody><!-- per-variant, delta colored: |Δ|<5% green, <15% yellow, ≥15% red --></tbody>
    </table>
  </section>

  <footer>
    <a href="{{repo_url}}">{{repo_url}}</a>
  </footer>
</body>
</html>
```

### Style notes

- Dark background (`#0d1117`-ish), monospace headings, sans body
- No external CDN fonts. `font-family: ui-monospace, SFMono-Regular, Menlo, monospace`
- Tables zebra-striped via `:nth-child(even)`
- Highlights grid: CSS grid, 4 cols desktop / 2 cols ≤600px / 1 col ≤400px (mobile sharing)

---

## Tests (Bats coverage)

| Test | Setup | Asserts |
|---|---|---|
| HoF generated on completion edge | state has 3/4, pull the 4th | `hall-of-fame.html` exists, contains `Full collection unlocked` and `4/4` |
| HoF NOT generated pre-completion | state has 2/4, pull a 3rd | file does not exist |
| HoF NOT regenerated on duplicate pull post-completion | state has 4/4, pull again | file mtime unchanged |
| HoF re-fires on canonical growth | state has 4/4, canonical grows to 5, pull the new one | file regenerated with new totals |
| First random Bisio recorded | sequence main, allucinato | `__first_random_slug allucinato`, `__first_random_pull_n 2` |
| First random NOT overwritten | sequence main, allucinato, rapput | `__first_random_slug` still `allucinato` |
| Dup streak tracked | sequence main, main, main, allucinato | `__dup_streak_longest 3`, `__dup_streak_slug main` |
| All-different streak tracked | sequence main, allucinato, rapput, patema | `__diff_streak_longest 4`, set contains all 4 |
| All-different streak resets on repeat | sequence main, allucinato, main | current=1, set={main}, longest=2 (from prefix main,allucinato) |
| RNG sanity column shape | weights configured 5,3,1,1; pulls 50,30,10,10 | actual % matches; delta column present |
| Comma in metadata value parses | state line `__diff_streak_set a,b,c` | parser accepts, value preserved |
| Opt-out env | `CLAUDE_BISIO_NO_COUNTER=1` | no HoF file written |
| Atomic write survives kill | simulated SIGKILL between mktemp + mv | original HoF file (if exists) intact |
| Stale string-value line skipped | malformed `__foo bar baz` line | parser skips, no abort |

---

## Out of scope (deferred to v0.5+)

- Variant thumbnails inline (base64) on HoF page — image weight + render complexity
- Browser auto-open on completion
- HoF schema versioning header line
- Pre-completion live HoF (regenerate every pull)
- Customizable HTML theme via env var
- JSON export sibling (`hall-of-fame.json`) for tooling
- Per-launch timeline / time-series stats (requires timestamp schema bump)
- Coupon-collector expected-vs-actual math (group E from grill brainstorm)
- Multi-user / multi-machine state merge

---

## Implementation order

1. `_counter.sh` parser regex split (canonical vs metadata)
2. `_counter.sh` extend `bisio_record_pull` with new metadata updates (dup, diff, first-of-variant, first-random, last-slug)
3. New Bats tests for metadata-only updates (no HTML yet)
4. `bin/_hof.sh` skeleton — state read, derived stats compute
5. HTML template render via heredoc
6. `_counter.sh` completion-edge call out to `bisio_render_hof` + path printout
7. `tests/hof.bats` — full HTML structure assertions
8. CI passes (extend `.github/workflows/test.yml` to include `tests/hof.bats`)
9. CHANGELOG entry for v0.4.0

---

## Open implementation questions (defer to coding chat)

- Exact HTML escaping helper for slug strings (POSIX `awk`)
- RNG sanity color thresholds — confirm 5% / 15% bands or pick tighter/looser
- Catch-order list: pull # only, or also include "(NEW)" badge for the most-recent catch?
- Whether `__diff_streak_set` is worth persisting vs recomputing from a small cap (e.g. last K=canonical_size pulls stored as a separate ring buffer)
- HoF file permissions — default umask, or explicit `chmod 600` (state file is private)
