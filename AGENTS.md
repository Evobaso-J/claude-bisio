# AGENTS.md

<!-- exodia:section:overview -->
**claude-bisio** is a zsh plugin that prints a Claudio Bisio portrait banner before launching the [Claude Code](https://claude.com/claude-code) CLI. Pure POSIX shell, no build step. Ships a `claudiosay` cowsay-style utility and a gamified "Bisiodex" collection layer with a Hall of Fame HTML export on completion. See `README.md` for user-facing docs; `context/architecture/decisions.jsonl` `a001` + `a008` for why the SessionStart-hook approach was abandoned in favor of a shell wrapper.

## Commands

<!-- exodia:section:commands -->
Check `.github/workflows/test.yml` for the canonical test invocation. **Do not run lint, test, or typecheck unless explicitly asked** — CI owns these gates.

## Context Router

<!-- exodia:section:router -->
Route by task type. Read the relevant L2 module, then load L3 data (`.jsonl` / `.yaml`) only when needed. **Max 2 hops.**

| Task type | Load |
| --------- | ---- |
| Banner pipeline, render flow, plugin entry, file layout, state/cache paths | `context/architecture/ARCHITECTURE.md` |
| Shell idioms, env-var contracts, chafa cache scheme, miss handling, testing | `context/patterns/PATTERNS.md` |
| Bisio variants, Bisiodex, Hall of Fame, in-world naming, `BISIO_DEX_*` semantics | `context/domain/DOMAIN.md` |
| Install/update flow, CI, oh-my-zsh integration, config knobs, adding a variant | `context/operations/OPERATIONS.md` |
| Banner doesn't render, terminal-size bails, chafa missing, SessionStart-hook history | `context/debugging/DEBUGGING.md` |

## Behavioral Rules

<!-- exodia:section:rules -->
1. **Route first.** Use the Context Router table above before loading any data file. Do not guess; the router exists to avoid guessing.
2. **Load lazily.** Never load all L3 files at once. Max 2 hops: router → L2 narrative → (optional) L3 data. If the task is answerable from L2 alone, stop there.
3. **Append only.** `.jsonl` data files are append-only. When an entry becomes obsolete, mark it `archived`; do not delete.
4. **Rationale required.** ADRs and decisions must include *why*. An entry without a reason will rot.
5. **Read before write.** Before appending to a data file, scan it for a duplicate or near-duplicate. Update or supersede rather than create a duplicate.
6. **Existing patterns win.** Read `context/patterns/PATTERNS.md` before introducing a new convention. If an existing pattern covers the case, use it.
7. **IDs are timestamps.** All L3 entries use the format `{type}_{YYYYMMDD}_{HHMMSS}_{4hex}` where `{type}` is the target file's `_schema` value (first line of the `.jsonl`). This makes IDs sortable and collision-free.
8. **Context update as final task.** When planning work with a todo list, always add a final step: "Evaluate context update." At that step, walk the §Self-Update Rules table below and decide if any entry should be captured. If nothing qualifies, skip. Do not create entries just to fill the step.
9. **Operations awareness.** Check `context/operations/OPERATIONS.md` before touching user-visible text, env variables, routing, deploy config, or anything that differs by environment/tenant/variant. When in doubt, open the file.
10. **Do not run lint, test, or typecheck unless explicitly asked.** CI and pre-commit hooks own these gates. Detected commands in this repo: `shellcheck --severity=error bin/*.sh`, `shellcheck bin/_counter.sh`, `bats tests/`. Running them ad-hoc wastes wall time and muddies terminal output.

## Self-Update Rules

<!-- exodia:section:self-update -->
The context files are **shared, living documentation** about the codebase, not personal memory. After completing a task, check whether any codebase fact, decision, or pattern (discovered or taught) should be logged for future sessions. Write in objective, third-person terms (the team decided X because Y), not first-person recollection (I learned X). **Do not ask the user for permission; just do it.** The user can always revert via git.

### When to update

All target-file paths below are relative to the context directory (`context/`).

| Signal during conversation | Target file | What to write |
| -------------------------- | ----------- | ------------- |
| Codebase assumption corrected by user or by evidence | L2 `.md` file for that area | Update the incorrect section |
| Bug pattern identified with non-obvious root cause | `debugging/playbooks.jsonl` | New playbook entry |
| Pitfall or footgun confirmed ("don't do X" / "watch out for Y") | `debugging/gotchas.jsonl` | New gotcha entry |
| Architecture or design decision taken by the team | `architecture/decisions.jsonl` | New ADR entry |
| PR review surfaces new check (prod break, near-miss) | `patterns/reviews.jsonl` | New review entry |
| API contract changes or deprecated | `patterns/reviews.jsonl` | New entry tagged `migration` with `old_pattern` / `new_pattern` |
| Variant-specific behavior confirmed | `operations/variants.yaml` | New entry under the relevant variant |
| Domain term clarified or new entity appears | `domain/glossary.yaml` | New or updated term |

### How to update

1. **Read the target file first**: check for duplicates or entries that should be updated instead of duplicated.
2. **Branch-scoped dedup.** Check the current branch (`git branch --show-current`). If an entry on the same topic was added on the **current branch** (check with `git diff <default-branch> -- <file>`), **replace it in-place** instead of appending. A branch is a unit of work; it should produce one entry per topic, not one per iteration or conversation. Once an entry is merged, it is settled and should not be overwritten; only superseded by a new entry on a new branch if the understanding changes.
3. **Use the existing schema**: every `.jsonl` file starts with a `_schema` line (JSON object with `_schema`, `_version`, `_description`, `_fields`). Read `_fields` to know which keys an entry must carry. Match field names exactly. Do not invent fields. If the schema must evolve, bump `_version` in the first line before adding entries with the new shape.
4. **Generate the ID**: format `{type}_{YYYYMMDD}_{HHMMSS}_{4hex}` using the current date/time. When replacing an entry per rule 2, keep the original ID.
5. **Append, don't rewrite**: add new lines at the end of `.jsonl` files. For `.md` and `.yaml` files, edit the relevant section. Exception: see rule 2; entries added on the current branch are mutable until merged.
6. **Archive, don't delete.** When a `.jsonl` entry becomes obsolete (gotcha no longer applies, runbook replaced, experiment failed), set `status: archived` on the entry instead of removing the line. Preserves history for retrospectives. The `status` field is part of every appendable schema's `_fields` (ADR schemas use `status: superseded` for the same purpose, with `supersedes: <id>` pointing at the replacement).
7. **Keep entries atomic**: one insight per entry. Don't bundle multiple gotchas into one.
8. **Be concise**: write for a developer who will read this months later without the conversation context.
9. **Point, don't hardcode**: never copy values that already live in source files (versions, ports, config). Reference the file instead.

### What NOT to capture

- Anything already in the context files (check first).
- Ephemeral debugging steps that only apply to this session.
- User preferences about agent behavior (those belong in `.claude/` or equivalent settings, not here).
- Information that can be derived from reading the code or git history.

### What NOT to capture (codebase-specific)

These rot fast; pointer only, never hardcode:

- Dependency versions, ports, env-var values, API endpoints, hostnames: reference the source file (`see package.json`, `defined in .env.example`).
- Function signatures, type definitions, class hierarchies, DB schemas: derivable by reading code.
- Git-derivable facts (commit author, date, PR number, blame line): use `git log` / `git blame`.
- Patterns already obvious from `package.json` / lockfile / `pyproject.toml` dependencies ("we use Redux" when `redux` is in deps).
- Test names, file counts, directory listings: rerun the command.
- One-session workarounds that will be gone next branch, unless the fix teaches a durable rule.

### When adding a new L3 file

If a recurring signal does not fit any target file in the table above, a new L3 file may be justified. Pick its format from the **File Format Strategy** table embedded above (or in `heuristics/format-strategy.md` at scaffolder time). Add a row to the signal-target table at the same time so future sessions route to it.

### File Format Strategy

| Format | Use when the data is | Examples |
| ------ | -------------------- | -------- |
| `.jsonl` | Append-only list of dated records, OR id-keyed record list mutated by id-rewrite. One self-contained record per line. | decisions, gotchas, playbooks, reviews, runbooks, migrations, experiments, releases |
| `.yaml` | Named, structured tree describing the *shape* of something stable. Mutated by editing nodes in place. | glossary, variants, datasets registry |
| `.md` | Long-form narrative: prose read top to bottom. The L2 module file is always `.md`; additional `.md` files at L3 are rare. | walkthroughs, calendars |

If two formats fit, prefer `.jsonl`; agents handle line-delimited records more reliably than nested YAML, and append-only is safer for long-running context. JSONL files always start with a single-line schema header: `{"_schema": "<type>", "_version": "1.0", "_description": "...", "_fields": [...]}`.

## Quick Action Table

<!-- exodia:section:quick-actions -->
| Developer says | Action sequence |
| -------------- | --------------- |
| "add a variant" | `context/operations/OPERATIONS.md` § Variants → `bin/banner.config.sh` (weight) + `assets/bisio/NN-slug.png` |
| "banner doesn't render" | `context/debugging/DEBUGGING.md` § Common Topics |
| "tweak chafa flags" | `context/operations/OPERATIONS.md` § Configuration → `bin/banner.config.sh` |
| "what is the dex / hall of fame" | `context/domain/DOMAIN.md` § Entities → `BISIO_COUNTER_SPEC.md` / `BISIO_HOF_SPEC.md` for locked decisions |
| "why no SessionStart hook" | `context/debugging/DEBUGGING.md` § Common Topics → ADRs `a001` / `a008` + gotchas `g001`–`g011` (do not retry that path) |
| "test the counter" | `tests/counter.bats` (bats) — see `context/patterns/PATTERNS.md` § Testing for isolation conventions |
| "release / publish" | `context/operations/OPERATIONS.md` § Deploy — distribution is the `main` branch tip |

## Context Structure

<!-- exodia:section:structure -->
```text
context/
├── architecture/
│   ├── ARCHITECTURE.md      # render pipeline, entry points, state/cache layout
│   └── decisions.jsonl      # ADRs
├── patterns/
│   ├── PATTERNS.md          # POSIX sh idioms, env-var contracts, testing
│   └── reviews.jsonl        # PR review checks, migrations, anti-patterns
├── domain/
│   ├── DOMAIN.md            # variants, Bisiodex, Hall of Fame
│   └── glossary.yaml        # in-world terminology
├── operations/
│   ├── OPERATIONS.md        # install/update, CI, config layers, variants axis
│   └── variants.yaml        # portrait variants registry
└── debugging/
    ├── DEBUGGING.md         # diagnose banner/counter/install issues
    ├── gotchas.jsonl        # known footguns
    └── playbooks.jsonl      # symptom → root cause → fix
```
