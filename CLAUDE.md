# Idler Homestead

Idle / roguelite homestead game in LÖVE 11.5 (LuaJIT). The design source of truth is [docs/GDD.md](docs/GDD.md). Read the relevant sections before implementing a feature, and update the doc (including the decision log) when a design decision changes.

## Running
- `love game` (or `lovec game` on Windows for console output). LÖVE is installed at `C:\Program Files\LOVE`.
- F3 toggles the template's performance overlay.

## Architecture rules (GDD §12)
- `game/src/sim/` is pure game logic: **no `love.graphics` / `love.audio` calls**, so it can be tested headless and fast-forwarded.
- Systems communicate only through the **resource ledger**, **task board**, and **event bus**. They never reach into another system's internals.
- Content definitions live in `game/data/content/`. Global balance knobs live in `game/data/tuning/<domain>.lua`.
- **No numeric literals for balance values in system code.** Read them from tuning or content. Tuning access is strict (unknown keys error).
- Every tuning value gets a comment with its unit and intent.
- All randomness goes through the seeded RNG service.
- Save slot state = `{ meta = ..., run = ... }`. Run state is discarded on failure, and meta persists.
- Input goes through the action abstraction (mouse, touch, keyboard). No hover-only UI. Platform-specific features check capability flags, never OS names.
- Sim state is plain serializable tables, kept separate from definitions.

## Style
- Follow `.editorconfig` and `.stylua.toml` (2-space indent).
- Modules return a table; prefer `local M = {}` ... `return M`.
