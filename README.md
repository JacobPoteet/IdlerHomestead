# Idler Homestead

An idle homestead game built with [LÃ–VE](https://love2d.org/) 11.5.

Project scaffolding comes from [bootstrap-love2d-project](https://github.com/Oval-Tutu/bootstrap-love2d-project). See [USAGE.md](USAGE.md) for the full build, debug and release documentation.

## Running

- Open `Workspace.code-workspace` in VS Code and install the recommended extensions.
- <kbd>Ctrl</kbd>+<kbd>F5</kbd> runs the game, <kbd>F5</kbd> runs it under the debugger.
- From a terminal: `love game`
- <kbd>F3</kbd> toggles the performance overlay in-game.

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
