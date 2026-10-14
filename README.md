# Idler Homestead

An idle homestead game built with [LÖVE](https://love2d.org/) 11.5.

Project scaffolding comes from [bootstrap-love2d-project](https://github.com/Oval-Tutu/bootstrap-love2d-project). See [USAGE.md](USAGE.md) for the full build, debug and release documentation.

## Running

- Open `Workspace.code-workspace` in VS Code and install the recommended extensions.
- <kbd>Ctrl</kbd>+<kbd>F5</kbd> runs the game, <kbd>F5</kbd> runs it under the debugger.
- From a terminal: `love game`
- In-game: drag (or arrow keys / WASD) to pan, mouse wheel / pinch / <kbd>+</kbd> <kbd>-</kbd> to zoom.
- Tap/click a tile and the homesteader walks there and does the obvious job (clear, till, plant, water, harvest, fill the bucket at the creek). Pick a seed in the toolbar to till and plant; **Hand** just walks. **Plan field** marks a rectangle (two taps) for the routine to farm; the tool turns itself off afterwards (hold Shift to plan several). Right-click / long-press inspects a tile.
- With the **rod** in hand, tap the creek to fish (hold mouse/finger/Space to reel, let go to ease off).
- Tap the **truck** to check its charge and drive to town to sell the crate and shop. **Catalog** orders arrive next morning; **Place** puts delivered equipment down. **Pantry** sets how much food to keep, preserve and sell. **Fish** opens the fish guide.
- Leave the controls alone for 30 seconds and the **routine** takes over; reorder it from the **Routine** button.
- Debug keys: <kbd>F1</kbd> debug overlay, <kbd>F2</kbd> cycle sim speed, <kbd>F3</kbd> performance overlay, <kbd>F6</kbd> reload tuning & shaders. With F1 on, the Catalog's Debug button toggles cheat mode (every item, free, instant; not saved).

## Testing

The simulation layer is plain Lua and is tested headless through LÖVE (no window):

```
lovec tests          # Windows (prints to the console)
love tests           # macOS / Linux
lovec tests rng      # only test files whose name contains "rng"
```

Run from the repo root. In VS Code: *Tasks: Run Test Task*. Tests live in `tests/test_*.lua`.

## Building

<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd> builds a date-stamped `.love` file into `builds/`. Pushing to GitHub runs the multi-platform CI build; configure targets in [game/product.env](game/product.env).

### Build label

The title screen shows the build tag and short commit hash (D91). Source runs read them from `.git`; packaged builds read `game/src/core/version_stamp.lua`, which the release workflow generates with `tools/stamp_version.sh` (gitignored). Run that script by hand to stamp a local build; `tools/stamp_version.sh --clear` removes it.
