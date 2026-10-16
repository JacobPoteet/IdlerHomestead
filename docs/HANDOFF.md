# Handoff

Read this first when picking up the project. Design lives in [GDD.md](GDD.md) (the decision log is the source of
truth; next free decision is D149). The interface redesign (D137-D148, [PLAN_UI.md](PLAN_UI.md)) is finished and merged;
this file keeps only what a new session still needs.

## State
- `main` is green: 961 headless tests, the full driver sweep, StyLua and luacheck clean. `Save.SAVE_COMPAT` = 12.
- Latest tag 0.4.0 (releases are pre-releases while the tag starts with `0.`). Notes are hand-written in
  `docs/patch-notes/<tag>.md` from `TEMPLATE.md`; the redesign has not shipped in a tag yet.
- Plan (D95): MVP first, balance after. Open MVP work is listed by `gh issue list --milestone MVP --state open`.
- Open design questions for the user are in [ISSUE_AUDIT.md](ISSUE_AUDIT.md) section 2. Do not change issues in bulk
  or guess decisions that are theirs.

## Unverified after the redesign (tell the user)
- Nobody has played the finished redesign for feel. Dissolve durations, signal timing, plate see-through, grade share
  and night dim (`ui.plate`, `ui.motion`, tuned in the F8 editor) are first guesses, set from still frames. See #324.
- Phone performance of the plate capture and the lens pass is unmeasured (#315, [PERF.md](PERF.md) checklist).
- The idle countdown ring and badge texts were tuned by eye on desktop only.
- Audio placeholders have never been heard (#243, #244).

## Redesign follow-ups still open
| Area | Issues |
|---|---|
| Books | #309 light paper with dark ink, #310 per-page layout pass, #311 keys to flip tabs, #312 real tab stamp art |
| Lenses | #314 real wiring instead of inferred connections, #315 phone profile, #316 drip line tint and Water card detail |
| Area drags | #318 edge scroll and a desktop pan route, #319 stronger mark patterns, #320 mark moist crops |
| Motion | #322 item card dissolve, #323 remaining alpha pulses and Reduce motion, #324 tune by feel |
| Older UI | #273 chip strip crowding on a phone, #269 touch range preview, #89 phone HUD check |

## Where the interface code lives
| Part | Files |
|---|---|
| Font, plates, icons | `src/ui/pixel_font.lua`, `text.lua`, `plate.lua`, `icons.lua`, `shaders/ui_plate.glsl` |
| Resting HUD | `src/ui/hud.lua` (pure layout), Homestead `layoutHud` / `draw*` |
| Tool wheel, Hammer | `src/ui/tool_wheel.lua`, Homestead `hammerRing` / `hammerTap`, `Input` wheel events |
| Pencil plans, marks | `src/render/sketch.lua`, `shaders/sketch.glsl`, `src/sim/systems/marks.lua`, Homestead `areaDrag*` |
| Books | `src/scenes/book.lua` (hosts the old panel scenes as tabs), `src/ui/books.lua`, `src/ui/paper.lua` |
| Lenses | `src/ui/lens.lua`, `lens_card.lua`, `src/render/lens.lua`, `lens_fields.lua`, `shaders/lens.glsl`; `Homestead:showLens("power"\|"water")` |
| Motion | `src/ui/transition.lua`, `signals.lua`, `motion.lua`, `src/render/dissolve.lua`, `shaders/ui_dissolve.glsl` |

Gotchas that cost time before:
- On a mouse, hovering a wedge with a ring (Hoe, Hammer) shows the ring, so a click on the wedge equips it; the "first
  tap shows the ring" rule is the touch path. Driver scenarios hover first (`input:mousemoved`).
- A held wheel only draws after `showDelay` of real time; scenarios backdate `scene.wheel.at`.
- Pages inside a book call `Panel.box`, which returns the page body (`hosted`); `d:scene()` is the page showing,
  `d:book()` the book. In town the Ledger is locked to Truck & town.
- The driver sets `Motion.settled = true` so scenarios shoot finished screens; only `motion` turns it off.
- The Controls list scrolls (13 rows); the `controls` scenario rebinds a row above the fold.
- Small and body text are the same pixel font size; a few tight rows touch (the Pantry wood line).

## Tooling
- StyLua 2.0.2 (the CI pin): `/c/Users/gwlpo/stylua-2.0.2/bin/stylua.exe --check game tests tools`. Never
  `~/.cargo/bin/stylua` (2.6.0, cannot parse `goto`). luacheck 1.2.0: `luacheck.exe game tests tools`. Run both before
  pushing; CI blocks on them. Never assign to `_` (luacheck flags it as a global; use `select(2, f())`).
- Tests: `lovec tests [filter]` (about 35 s parallel). Driver: `lovec tools/driver <scenario|all> size=both out=<existing
  dir>`; `all size=both` is about 3.5 min, run it in the background and do not edit game code while it runs. Helpers:
  `d:pick(label)`, `d:hudButton(id)`, `d:pressHud(id)`.
- Balance harness and perf probe: see CLAUDE.md, [BALANCE.md](BALANCE.md), [PERF.md](PERF.md).
- The wiki (Obsidian vault) holds the matching notes; update the note for every change to main and commit only your own
  notes. Its path is in agent memory, never in the repo.

## Working with agents (what worked for the redesign)
- One Sonnet worktree agent at a time (`isolation: "worktree"`), in the background; never Opus unless the user allows it.
- Prompt: issue numbers and decisions, files and GDD sections to read first, the repo rules (CLAUDE.md), a report format.
  Tell the agent to `git merge main` first and to take its decision numbers from a stated range.
- Verification the agent does: while building, only `lovec tests <filter>` and single driver scenarios; local lint
  before committing; then the full test run and the full sweep once, just before the commit, with one wait and no chained
  sleep timers. A failure that only shows under load gets re-run alone.
- The coordinator re-runs lint, format and `lovec tests` in the agent's worktree, pushes the branch, opens a PR whose body
  has `Closes #N`, waits for CI, and squash-merges (`gh pr merge N --squash`, descriptive subject and body, no merge commits). Never commit to main directly. A phase
  of the redesign took about 17-21 minutes of agent time, 40-45% of it verification.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR bodies end with the Claude
  Code line. Never bypass commit signing. The repo is LF-only.
- Every shortcut gets a follow-up issue (`found-during-dev` plus a topic label, milestone MVP or Post-MVP, self-contained,
  checked for duplicates). Check new issues against the pillars (GDD §3) and the decision log.
- Bump `Save.SAVE_COMPAT` and the fingerprint in `tests/test_save_compat.lua` on any saved-state change (D74).

## The user's preferences
Usability and clarity matter most. The game is "really fun" but needs clearer UX. They playtest often and send notes:
file them as issues, link related ones, queue them. They want a fun, complete MVP first and balance later, organized
patch notes, brief status updates, minimal token spend, and honesty about what is unverified. When they say "just keep
going", work through safe, clear-cut items one at a time. Ask only for decisions that are genuinely theirs.
