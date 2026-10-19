---
name: bisiodex-release
description: Hunt new Bisio images on the web, cut them out, get them approved, renamed and given a rarity, then ship them as a new claude-bisio release.
disable-model-invocation: true
---

# bisiodex-release

One run takes new Bisios from web image search all the way to a published GitHub release. The user is the curator. They approve every candidate, name and rarity, and both merges. The agent does the legwork between those **gates**.

`$SKILL` is this folder (`.claude/skills/bisiodex-release`). `$SCRATCH` is the session scratchpad. Downloads, cutouts and previews stay there. Only the approved PNGs reach the repo.

Asset contracts, naming and weights are in `context/operations/OPERATIONS.md` § Variants. Read it before step 4.

## 1. Worktree

Pull `main` in the shared clone, then `git worktree add -b feat/<slug> ../claude-bisio-worktrees/<slug> origin/main` and `git branch --unset-upstream` in the new worktree.

Done when: the worktree sits on a fresh branch from `origin/main`, with no upstream set.

## 2. Hunt

Search **Yandex Images** with `agent-browser`, using a named session. In this environment Google shows a captcha, and Bing and DuckDuckGo return junk or nothing. Open `https://yandex.com/images/search?text=<query>` and pull the originals out of the result links:

```js
[...document.querySelectorAll("a[href*=img_url]")].map(a => decodeURIComponent(new URL(a.href).searchParams.get("img_url")))
```

Good targets are memes and photomontages, in the line of shrek, joestar and duxio: Bisio as a vegetable, an object or a character. Plain portraits make Common filler at most. If the user names a specific meme and Yandex has nothing, say so. Do not fabricate a composite.

Download each file into its own subfolder of `$SCRATCH/dl/` and check it with `file`. Drop HTML, stock-agency watermarks and shots that are not Bisio.

Done when: 8–12 real image files are downloaded and checked, each one a distinct Bisio.

## 3. Cut out and normalise

1. Build the tool once: `swiftc -O $SKILL/scripts/cutout.swift -o $SCRATCH/cutout`. It uses the macOS 14+ Vision foreground mask.
2. For each candidate, run `cutout src.png cut.png`, then `magick cut.png -trim +repage -resize 480x480\> norm.png`, then `sh bin/trim-bisios.sh norm.png`.
3. Look at every result on a dark background. Vision keeps only the subject, so a **halo** around it gets dropped: sun rays, glow, a frame that belongs to the joke. In that case rebuild the mask from colour plus a radial falloff, and union it with the Vision face mask. Recipe that worked for the Teletubbies sun (the yellow channel minus the blue sky):
   ```sh
   magick src.png -fx "min(1,max(0,(min(r,g)-b-0.18)*6))" -blur 0x1.5 -colorspace gray m_y.png
   magick -size WxH radial-gradient:white-black -fx "min(1,max(0,(u-0.3)*3))" -roll +DX+DY m_rad.png   # centre on the subject
   magick m_y.png m_rad.png -compose multiply -composite face_mask.png -compose lighten -composite -fx "u<0.35?0:min(1,(u-0.35)*1.6)" m.png
   magick src.png m.png -alpha off -compose copyopacity -composite -trim +repage -resize 480x480 norm.png
   ```
   Get `face_mask.png` with `magick cut.png -alpha extract`. The last threshold removes low-alpha smudges, which turn grey on light terminals.
4. Write a short note for each candidate, and flag what is still wrong: text left over from the meme, a bystander's limb, a lost halo.

Done when: every candidate has a `norm.png` that `trim-bisios.sh` reports as conforming, and has been viewed and noted.

## 4. Review gate: approval and names

Write `$SCRATCH/candidates.json` with id, proposed slug, note, warn and png for each candidate. The slug is lowercase letters only and puns on Bisio (`pomodorisio`, `solisio`), and it must describe what is left after the cutout. Build the page with `python3 -I $SKILL/scripts/build_review.py candidates.json <next dex number> review.html`. Each card shows the cutout next to its chafa render with the banner preset (`bin/preview-bisio.sh --chafa`), so the user judges what the terminal will actually show. Flag in the note any candidate whose render loses the face.

Publish it as an Artifact with `capabilities: {db: {}, user: {}}`. The page saves each choice to the `picks` collection as `{name, approved}`. Users cannot look at local files, so always send candidates through the page. Read the choices back with `ArtifactData` `list` on `picks`.

When the user asks for a different cutout or name, update `candidates.json`, rebuild and republish to the same file path. A default name only shows when there is no `picks` doc for that candidate.

Done when: the user says the selection is done and `picks` holds their final approved set and names.

## 5. Hall of Fame preview

Run `git archive HEAD | tar -x -C $SCRATCH/hofprev`. In that copy, add the approved PNGs as `NN-slug.png`, add a `BISIO_WEIGHT_<SLUG>` for each, and extend `bin/demo-hof.sh` (counts, `dex`, and the total, which is the sum of the counts). Then run `sh bin/demo-hof.sh` there. Screenshot the result to check it before pointing the user to `assets/hof-demo.html`.

Done when: the new tiles render in the real HOF next to the existing ones.

## 6. Rarity gate

The tier comes from the weight. The thresholds live in `_bisio_hof_tiles_frag` in `bin/_counter.sh`. Propose a tier and weight for each new Bisio, then show the before and after numbers from:

```sh
python3 -I $SKILL/scripts/dex_odds.py bin/banner.config.sh slug=weight ...
```

It prints tier shares, per-variant pull % and the expected number of pulls to complete the dex. Always quote its output rather than doing the sums by hand: hand arithmetic has already shipped wrong numbers once. Flag any jump in completion time; a new Legendary is what moves it most.

Done when: the user has confirmed a tier for every new Bisio and `dex_odds.py` has been run on the final weights.

## 7. Wire and check

In the worktree:
1. Copy each PNG to `assets/bisio/NN-slug.png` (`magick f -strip PNG32:f`).
2. Add `BISIO_WEIGHT_<SLUG>` next to its tier in `bin/banner.config.sh`.
3. Extend the mock state in `bin/demo-hof.sh`, following the existing pattern.
4. **Tuning gate.** Ask the user which Bisios to tune, new or already shipped (fixing existing ones is in scope). For each, open `bin/tune-bisio.sh NN-slug.png` in a new iTerm window, since the tuner is an interactive TUI the agent cannot drive:
```sh
osascript <<'E'
tell application "iTerm2"
  activate
  create window with default profile command "/bin/zsh -lc 'cd <worktree> && bin/tune-bisio.sh NN-slug.png; exec zsh -l'"
end tell
E
```
   The user saves with `w`. Then build the before/after sheet with `bin/preview-bisio.sh $SCRATCH/tuned.png assets/bisio/src/NN-slug.png assets/bisio/NN-slug.png` and show it. Skip when the user wants no tuning.
5. Run `bats tests/ > out; echo EXIT=$?` and `shellcheck --severity=error bin/*.sh`.

Done when: both checks exit 0, and `git status` shows only the new PNGs, `banner.config.sh`, `demo-hof.sh` and, if anything was tuned, the tuned PNGs, `assets/bisio/src/` and `assets/bisio/recipes.tsv`.

## 8. PR

Commit and push, then open a PR titled `feat: add <slugs> variants`. The `feat:` prefix is what makes release-please cut a minor release. Put the dex / slug / tier / weight table and the `dex_odds.py` before and after in the body. Wait on `gh pr checks <n> --watch`.

Done when: the PR is open and CI is green.

## 9. Release gate

Wait for an explicit go from the user, then:
1. Squash-merge the PR.
2. Wait for release-please to open `chore(main): release X.Y.0` and show it to the user.
3. Merge it only after a second go.
4. Verify with `gh release view vX.Y.0`.

Users pick the release up through the daily update prompt in `bin/_update_check.sh`.

Done when: `gh release view` shows the new tag.
