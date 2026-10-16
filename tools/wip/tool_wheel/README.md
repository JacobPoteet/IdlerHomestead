# Tool wheel (phase 4, #294): work in progress

Not applied yet. What is done on this branch:
- `game/src/ui/tool_wheel.lua`: pure wheel geometry (centre clamped to the view, wedge and ring layout,
  `pick` by direction with a dead zone, a ring past `subRadius`, a sticky ring that may fan past
  neighbouring wedges). `tests/test_tool_wheel.lua` passes (6 tests).
- `tuning.ui.wheel` (wedge directions, hold time, flick delay, ring spread, sizes) in `data/tuning/ui.lua`.
- `tests/test_tools.lua`: tests for tool-limited orders (needs the `Tasks.taskForTile` change in
  `p4_scene.py`; fails until it is applied).

Patch scripts, written against main after #304 (run from the repo root, in this order, then delete
this folder):
1. `python tools/wip/tool_wheel/p4_input.py`: Input emits `wheelOpen`/`wheelMove`/`wheelRelease` for a
   held right press, a right drag (flick) or a long-press where `scene:wantsWheel(x, y)` is true (a
   quick right click stays `context`); keys Q = `toolWheel`, 1-6 = `tool1..6` (rebindable, with
   Controls screen names).
2. `python tools/wip/tool_wheel/p4_scene.py tools/wip/tool_wheel`: inserts `p4_scene_funcs.lua` into
   the homestead scene (equip, ring items, open/aim/release/tap the wheel, drawWheel), routes input to
   the wheel first, makes the tool badge open the wheel, limits Pail and Axe orders by task category
   (`order.categories` in `Tasks.taskForTile`), adds labels, captions, the `icon_verb_plan` pencil icon,
   tip text, and `equipByLabel` for the driver's `pick`.
3. `python tools/wip/tool_wheel/p4_docs.py`: GDD (Q instead of Tab, built notes) and PLAN_UI status.

Then: run `lovec tests`, the driver `hud`, `clarity`, `scroll`, `place`, `plan` scenarios at all sizes
(a scenario that needs a held wheel can call `scene:openWheel(x, y, true)`, `scene:aimWheel(x, y)` and
`scene:releaseWheel()`), check the wheel screenshots, add a driver scenario `wheel`, fix StyLua line
lengths by hand (not installed locally), and open the PR "UI redesign 4/9".
