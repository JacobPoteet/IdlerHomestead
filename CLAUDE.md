# Idler Homestead

Idle / roguelite homestead game in LÖVE 11.5 (LuaJIT). The design source of truth is [docs/GDD.md](docs/GDD.md). Read the relevant sections before implementing a feature, and update the doc (including the decision log) when a design decision changes.

## Running
- `love game` (or `lovec game` on Windows for console output). LÖVE is installed at `C:\Program Files\LOVE`.
- Tests: `lovec tests` (optional name filter, e.g. `lovec tests m3`). Headless (no window or GPU needed); exits 1 if any test failed or a test file errored. CI (`.github/workflows/ci.yml`) runs exactly this on push to main and on PRs.
- Balance harness (headless whole-run simulation, not part of the test suite): `lovec tools/balance policy=all seeds=20 years=1 [out=file.csv|json] [set=needs.coldDamage=15] [jobs=N] [profile=1]`. Seeds run on worker threads (`jobs`, default CPU count; output identical to `jobs=1`); `profile=1` samples the sim with LuaJIT's profiler. Policies: idle, scripted, active. Details and findings in [docs/BALANCE.md](docs/BALANCE.md); `lovec tools/balance help=1` lists options.
- Performance probe (headless; sim ms per tick, allocation per tick, save size): `lovec tools/perf [policy=active] [warm=84] [ticks=2000] [set=...]`; frame cost in a window: `lovec tools/driver perf`. Budget, baseline and the phone checklist in [docs/PERF.md](docs/PERF.md); F3 shows the same figures live.
- Screenshot driver (plays the real game with scripted input, in-memory saves; needs a window): `lovec tools/driver <scenario|all> [size=desktop|phone|both] [out=dir]`. Scenarios in `tools/driver/scenarios/`; see [tools/driver/README.md](tools/driver/README.md). Use it to verify UI changes.
- Debug keys: F1 overlay, F2 sim speed, F3 performance overlay, F6 reload tuning + shaders live.

## Architecture rules (GDD §12)
- `game/src/sim/` is pure game logic: **no `love.graphics` / `love.audio` calls**, so it can be tested headless and fast-forwarded.
- Systems communicate only through the **resource ledger**, **task board**, and **event bus**. They never reach into another system's internals.
- Content definitions live in `game/data/content/`. Global balance knobs live in `game/data/tuning/<domain>.lua`.
- **No numeric literals for balance values in system code.** Read them from tuning or content. Tuning access is strict (unknown keys error).
- Every tuning value gets a comment with its unit and intent.
- All randomness goes through the seeded RNG service.
- Save slot state = `{ meta = ..., run = ... }`. Run state is discarded on failure, and meta persists.
- No save migrations before launch, and saves do not need to load older shapes: **bump `Save.SAVE_COMPAT`** (`game/src/core/save.lua`) on a breaking save change and update the fingerprint in `tests/test_save_compat.lua` (it fails until you do). Older saves get a "can't be loaded" prompt (Delete / Keep), never a silent delete (GDD D74).
- Input goes through the action abstraction (mouse, touch, keyboard). No hover-only UI. Platform-specific features check capability flags, never OS names.
- Sim state is plain serializable tables, kept separate from definitions.
- `game/src/render/` is presentation: it reads sim state and never changes it. Sprites are looked up by id through `game/assets/manifest.lua` (placeholders in `src/render/placeholders.lua`); shaders live in `game/shaders/` with parameters in `data/tuning/visuals.lua`. See docs/ASSETS.md.
- When adding a sim helper module outside `src/sim/systems/`, add it to the list in `tests/test_architecture.lua`.

## Wiki
- Project documentation lives in the wiki, which sits outside this repo. Every change to main updates the matching wiki note first (and the Decision Log when a choice had a constraint behind it). `docs/GDD.md` stays the design source of truth.
- The wiki's location is held in agent memory and in the gitignored `.claude/wiki-path.local`. Never write its path in the repo (a file, comment or commit message).

## Tracking work
- Remaining work is tracked as GitHub issues grouped into milestones **M3–M7** (matching GDD §13).
- When you notice follow-up work that the GDD doesn't track (shortcuts, polish, tech debt), open an issue labelled `found-during-dev` plus a topic label (`tech-debt`, `ux`, `art`, `shader`, `audio`, `balance`, `tooling`).
- Verify UI changes by actually running the game (a scripted screenshot driver is planned as a repo tool, see the "screenshot driver" issue).

## Style
- Follow `.editorconfig` and `.stylua.toml` (2-space indent).
- Modules return a table; prefer `local M = {}` ... `return M`.
