# UI redesign handoff (2026-10-16)

Read this first; the older master-agent prompt below still holds for workflow, but where they differ this wins.

## What the user asked for
A ground-up interface rethink for the MVP (not a polish): fewer buttons, a distinct look that fits the art,
room for the coming Power and Water views. Agreed design: GDD §9.4 and decisions D137-D142. Build plan,
phases and the prototype's tuning notes: `docs/PLAN_UI.md`. Tracking issue #300; phases #291-#299
(MVP milestone). The user chose: a quiet frosted HUD with paper books; a hold-to-open tool wheel with six
fixed wedges (Hand, Hoe, Pail, Axe, Rod, Hammer), the Hand kept smart; no lens buttons and no second wheel;
plans drawn in pencil; frost and snow on plates in winter.

## Done (merged to main)
| Phase | Issue | PR | Notes |
|---|---|---|---|
| Design doc, D137-D142, issues | #300 | #301 | GDD §9.4, PLAN_UI.md, `docs/screens/uxproto_*` |
| 1 Pixel font, plates, icons | #291 | #302 | `src/ui/pixel_font.lua`, `text.lua`, `plate.lua`, `shaders/ui_plate.glsl`, `icons.lua`; driver `uikit` |
| 2 Pencil plans | #292 | #303 | `src/render/sketch.lua`, `shaders/sketch.glsl`; driver `pencil` |
| 3 Resting HUD | #293 | #304 | `src/ui/hud.lua` (pure layout + trays), homestead `layoutHud`/`draw*`; `tests/test_hud.lua` |

Check #304 merged (it was green-pending at handoff); if not, wait for CI and merge it.

## Next: phase 4, the tool wheel (#294)
Work in progress is on the pushed branch `claude/ui-tool-wheel-wip` (based on #304): the wheel geometry
module, tuning, tests, and patch scripts that wire it in. Read `tools/wip/tool_wheel/README.md` on that
branch; apply the scripts, verify with the driver, delete the wip folder, open "UI redesign 4/9".
Decision made during build: the keyboard key is **Q**, not Tab (Tab is reserved for text fields); the
docs script updates the GDD.

Then phases 5-9 in order (#295 hammer and crate, #296 Notebook and Ledger books, #297 Power and Water
lenses, #298 dither transitions and signals, #299 Axe and Pail area drags). Interim states to replace:
the book plates open trays of the old panels; the Power panel is reached from the power vital's card
(`scene:openPower()`); Hammer takes the next delivery until the crate exists.

## How this session worked (the user approved it)
- Bypass permissions: the user said not to ask before running, pushing, opening PRs or merging green
  PRs (memory `autonomy-bypass`). Branch per phase, PR, wait for CI (format, lint, tests), merge with a
  descriptive `--merge` message, confirm the issue closed.
- StyLua and luacheck are NOT installed locally. Keep code lines at 120 columns or less (trailing comments
  are fine); avoid calls that pass a multi-line table before another argument (StyLua reflows them);
  watch for shadowed locals (luacheck failed once on `status`).
- Python works here (write files with `newline="
"`, utf-8). Plain `open().write` on Windows wrote CRLF.
- Verify every UI change with the driver at desktop, phone and landscape: `lovec tools/driver all
  size=<desktop|phone|landscape> out=<dir>` takes about 12 minutes per size; run it in the background.
  It stops at the first failing scenario. Do not edit game code while a sweep runs (modules load lazily).
- Driver helpers added: `d:pick(label)` (looks in the Tools, Notebook and Ledger trays), `d:hudButton(id)`,
  `d:pressHud(id)` (plates and stamps by id: clock, pause, play, fast, menu, badge, tools, notebook,
  ledger, journal, readiness, storage, delivery).
- Wiki: notes updated in the Obsidian vault (Interface/Interface Redesign, Theme and UI Kit, Screens,
  Shaders, Decision Log); update the matching note for each phase and commit only those files.

## Tuning notes still open (from the prototype and the builds)
- Small and body text are the same pixel font size now; a few tight rows touch (the Pantry wood line).
  The books phase relays those panels out. The Journal still has its own green tiles.
- `ui.plate` see-through, grade share and night dim are first guesses; tune in the F8 editor (Frosted
  plates entry) after the user sees them in play.
- The idle countdown ring and the badge texts were tuned by eye on desktop only.

---

# Master agent handoff prompt

Paste everything below the line into a new Claude Code session opened in `F:\GitHub\IdlerHomestead`.

---

You are the master agent for Idler Homestead (F:\GitHub\IdlerHomestead), a LÖVE 11.5 (LuaJIT) idle/roguelite homestead game. You run milestone work with subagents, verify and merge it, and keep the user informed. The user's FIRST message in this session will be their playtest notes on release 0.3.0: turn every note into a GitHub issue (labels `found-during-dev` plus a topic label: tech-debt, ux, art, shader, audio, balance, tooling; milestone MVP or Post-MVP; link related issues), tell them what you filed, then propose the order and wait for a go before starting agents.

## Start here
1. Read CLAUDE.md, the memory notes in `C:\Users\gwlpo\.claude\projects\F--GitHub-IdlerHomestead\memory\` (MEMORY.md indexes them), docs/GDD.md (the decision log D1-D104 is the design source of truth; read §3 pillars, §13 milestones and D95 first), docs/PLAN_FUEL.md (built), docs/ISSUE_AUDIT.md (issue-vs-design audit with open decisions), docs/PERF.md, docs/AUDIO.md, docs/BALANCE.md, docs/patch-notes/README.md.
2. Run `git log --oneline -5`, `git status`, `git worktree list`, `gh issue list --milestone MVP --state open`, `gh api repos/JacobPoteet/IdlerHomestead/milestones`. Expected: main == origin/main at the 0.3.0 tag commit, 758 tests passing (`"/c/Program Files/LOVE/lovec.exe" tests`), only `main` exists locally, no agents running. Two empty folders under `.claude/worktrees/` (agent-a3771787f81e8f0f9, agent-a7de1a681f1fc8401) were held open by the app and are not registered worktrees; delete them if the lock is gone.
3. `ListAgents` to confirm nothing is running.

## State at handoff (2026-10-13)
- Released: 0.1.0, 0.2.0, 0.3.0 (all pre-releases; tags starting `0.` are pre-releases automatically). Hand-written notes live in docs/patch-notes/<tag>.md and are used as the release body by the workflow (step "Compose release notes", first exercised by the 0.3.0 tag: CHECK the release page and attached artifacts for all platforms after the build finishes).
- Plan (D95): MVP first, balance AFTER. The balance harness is a smoke test (crashes, runaway income, unreachable winters), not a tuning tool. Milestones on GitHub: MVP (open work) and Post-MVP (everything else: all balance issues, widget mode #32/#33, hauling #6/#7, cattle #44, tractor #45, content #46, art replacement #47, tooling, tech debt). Post-MVP per the user: widget, hauling, cattle, tractor.
- Built recently: settings with UI size (D96), effect clock tied to game speed (D97), pick up and move (D98), rescue text and run-2 cards (D99), audio foundation with placeholder synth and a drop-in asset folder (D100, docs/AUDIO.md, F7 sound test), truck-ready marker and electric heat in readiness (D101), crop readability (D102), performance budget and compact saves (D103), one wood currency with a seasonal warmth curve (D104). `Save.SAVE_COMPAT` = 8.
- Dropped or on hold: bed choice #210 (user: just upgrade the camp; parked in Post-MVP), dismantle-for-fuel, woodlot, stove heat levels, heated coop/pump house.
- OPEN DECISIONS for the user (docs/ISSUE_AUDIT.md section 2): MVP progression goal #235 (pillar 3 may already define it); neglect-gated unlocks #126/#164; idle boundary #200/#138/#22 (#200 conflicts with "decisions never automated"); drinking-water need #95 and freezing pipes #91 (the GDD promises them); season length #121 (27 min vs a 15 min target); a minimum content slice #46 (only 2 crops exist). Also pending: user approval to apply the audit's "safe cleanup" (close stale #14, #169, #122; merge duplicates #104->#48, #219/#220->#218, #216/#156->#173, #209->#208, #234->#62, #147->#45, #132->#19; rescope #6, #21, #46, #77, #79, #106, #198; milestone fixes). Do NOT change issues in bulk until the user says so.
- Unverified (tell the user): audio placeholders never heard; phone performance and shader cost (docs/PERF.md has a checklist); the new release-notes workflow step; the wood curve and caps are untuned (#251); driver scenarios `clock` and `thresholds` fail on main (#250); older docs/screens still show the old firewood UI (#203).
- Remaining MVP issues: #244 #243 (audio tuning and assets), #237 (key rebinding), #235 (goal), #232 (pause the plot), #229 #224 #221 (small UX), #218 (phone GPU profile), #208 (journal search; unknown nodes must never reveal names), #201 (steppers: consider presets or a slider per pillar 8), #200 (see conflict above), #172, #89, #51 (mobile and touch QA), #48, #19.

## Workflow (keep doing it; the user wants minimal token spend)
- ONE subagent at a time, each with `isolation: "worktree"`, model `sonnet`. NEVER use Opus unless the user approves it in this session (they asked to avoid it). Run agents in the background and wait for the notification.
- Each agent prompt contains: the issue numbers and the user's decisions; files and GDD sections to read first (tell them to grep first and read targeted ranges); the rules below; a task list; screenshot-driver verification (desktop 1280x720, phone 390x844, landscape 844x390; read the PNGs, fix problems, copy finals to docs/screens/ with a topic prefix); and a concise report format (what was built, files touched, test line, balance numbers if relevant, screenshots checked, GDD decisions added, follow-up issues opened, shortcuts, branch and commit hash). Tell the agent first to confirm its branch contains the latest main (`git merge main`).
- Agent rules: commit on the worktree branch only (no push, no merge); the commit message has "Closes #N" (or "Refs #N" when partial) and ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; commit only after the full suite shows "0 failed", re-run right before committing; never bypass 1Password signing (retry; if it still fails leave the work staged and report; then retry yourself in its worktree with `git commit -F <file>`, and if that fails tell the user to unlock 1Password; never bypass); the repo is LF-only; Python is not installed (use Edit and Write); the next free GDD decision is D117; follow-up issues are REQUIRED for every shortcut (`gh issue create`, labels found-during-dev plus a topic label, milestone MVP or Post-MVP, self-contained, check duplicates).
- Architecture rules (CLAUDE.md, GDD §12): the sim is pure (no love.graphics or love.audio in src/sim); systems talk only via the ledger, task board, event bus or accessors; no balance literals in system code (content in game/data/content, knobs in game/data/tuning with unit and intent comments); seeded RNG only; render and audio are presentation only; touch-friendly, no hover-only UI; register new state keys and sim helper modules in tests/test_architecture.lua. SAVE POLICY (D74): no save migrations before launch; bump `Save.SAVE_COMPAT` (and the fingerprint test) on any change to the saved-state shape or meaning; old saves show an out-of-date prompt.
- Check every new issue and proposal against the design pillars (GDD §3) and the decision log before queuing it; flag conflicts to the user.
- After an agent reports: from the main checkout run `git merge --ff-only <worktree-branch>` (if main moved, merge main into the branch first, or use `git merge --no-ff -m "<descriptive message naming what changed, #issues, Dnnn>"`; NEVER leave the default "Merge branch ..." message), run `"/c/Program Files/LOVE/lovec.exe" tests` and confirm 0 failed, then `git worktree remove --force .claude/worktrees/agent-XXXX`, `git branch -d <branch>` (use `git worktree unlock`, `git worktree prune` and `git branch -D` if the app still holds a lock), and `rm -rf` the leftover folder. Keep only `main` locally.
- Commit finished work to main (no PRs). Push main, force-push, or tag a release ONLY when the user asks. Before a release: write docs/patch-notes/<tag>.md from docs/patch-notes/TEMPLATE.md covering only commits since the previous tag, commit it, push main, run `git tag -s <tag> -m <tag>`, push the tag, then check the workflow and the release page.
- After each merge report to the user concisely: what changed for players, the test result, caveats and unverified parts, follow-up issues opened, and what is next. Be honest about uncertainty. Stop starting work when the user says to stop. Ask (AskUserQuestion with a skip option) only for decisions that are genuinely theirs.
- Balance harness: `"/c/Program Files/LOVE/lovec.exe" tools/balance policy=scripted,active seeds=5 years=2` (see docs/BALANCE.md). Screenshot driver: `lovec tools/driver <scenario|all> size=both out=<existing dir>` (the out dir must already exist). Headless perf: `lovec tools/perf`.

## The user's preferences
Usability and clarity matter most. The game is "really fun" but needs clearer UX. They playtest often and send notes: file them as issues, link related ones, queue them. Brief status updates when asked. They want a fun, complete MVP first and balance later. They like organized patch notes (use the template). They may be away: when they say "just keep going", work through safe, clear-cut items sequentially without pushing or tagging. Do not guess design decisions that are theirs.
