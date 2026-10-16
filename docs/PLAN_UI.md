# Interface redesign plan (D137–D142)

The design lives in [GDD §9.4](GDD.md#94-interface-the-mvp-redesign-d137d142) and decisions D137–D142. This file holds the build order, what each phase replaces, and what the throwaway prototype taught us. Tracking issue: #300.

## Phases

Each phase is one PR, merged on green CI (✓ = merged), with driver screenshots at desktop, phone and landscape. Later phases build on earlier ones; the order keeps the game playable after every merge.

| # | Phase | Issue | Replaces | Done when |
|---|---|---|---|---|
| 1 ✓ | **Foundation**: pixel font in `Text` (every scene), plate kit (`ui_plate.glsl`, `Draw.plate`, knobs in tuning), a frosted capture that works with bloom on or off, icon pipeline (tools, verbs, signals, seed packets) | #291 | LÖVE's default font, `Draw.panel`'s flat rectangles | Every scene renders in the new font and plates; no text is graded; tests and driver pass |
| 2 ✓ | **Pencil plans**: planned tiles, sketched sprouts, placement ghosts, queued orders; the chalk pass at night | #292 | The faint-sprout plan ghost, plan marker, translucent ghosts (D79, D102) | Plans read at zoom 1–3, by day and night, on grass, soil and snow |
| 3 ✓ | **Resting HUD**: clock and speed plates, vitals, Menu, decision stamps, homesteader badge, tool badge, book plates; phone and landscape layouts | #293 | Top bar and chip strip (D112), bottom toolbar and palettes (D72, D87), the Speed, Start routine and Power column, the idle hint line | The old buttons are gone; every function they had is reachable; tap targets stay at least `input.minTouchTarget` |
| 4 | **Tool wheel and tools**: wheel widget, input (hold right click, long-press, Tab, 1–6, flick), Hand, Hoe (seed ring, Untill, drag to plan), Pail, Axe, Rod; short right click inspects | #294 | Seed buttons, Rod, Untill, Plan field, Hand buttons | Every old toolbar action is a tool or ring choice; the wheel works by mouse, touch and keys |
| 5 | **Hammer and crate**: the crate ring, Move, Pick up, Demolish, Order more; delivery count on the wedge and badge | #295 | The Place button (D79), object-card Pick up, Move, Destroy buttons (D98, D110) | All placement, move and removal flows from D79, D98, D110 and D115 still work through the hammer |
| 6 | **Notebook and Ledger**: tabbed paper books; Journal, Fish guide, Diary; Pantry, Routine, Catalog, Truck & town; world shortcuts | #296 | Separate Journal, Fish guide, Log, Pantry, Routine, Catalog and Truck panels as top-level screens | Two book plates open every former panel; tabs remember the last page within a session |
| 7 | **Lenses**: lens framework (blueprint wash, dither data layer), Power lens with the priority list side card, Water lens, auto-on rules | #297 | The Power panel (§7.5 UI), the water-spot, drip-zone and range tints while placing (D108) as separate looks | Power and Water read without the old panel; switching on from vital, tool and placement |
| 8 | **Motion and weather**: dither open and close, amber glint and red beat, frost and snow on plates, paper books lit by a night light pool | #298 | Alpha fades, pulsing borders | Reduce motion and Ambient effects are respected |
| 9 | **Area drags**: Axe marks an area for clearing, Pail queues watering over an area, both drawn in pencil until done | #299 | One tap per tile | Marked areas work through the task board; the routine and the hand share them |

Not in scope: the desktop companion mode (§9.3, M4), real final art for every icon (placeholders follow the icon rules), Soil, Reach and Warmth lenses.

## Risks to watch

- **Driver and tests use toolbar labels.** Many driver scenarios call `d:pick("Plan field")`, `d:press("Pantry")` and similar. Phase 3 and 4 need a driver helper that equips a tool or opens a book by id, and scenarios moved to it in the same PR.
- **Discoverability of the wheel.** Phase 4 adds a first-time tip ("Hold right click for tools", "Long-press for tools") through the D69 tip cards, and the tool badge is always a tappable route.
- **Muscle memory.** Wedge positions are data, but they are not to change after release.
- **Performance on phones** (docs/PERF.md): the plate capture is one downsample and two blur passes per frame at 1/6 size; lenses are one full-screen pass. Each effect gets a switch in tuning and in the F8 editor.

## Prototype findings (throwaway, `uxproto` shots)

The prototype drew a mock HUD over the real game, pencil plans and ghosts, and the tool wheel, at desktop (1280x720), phone (390x844) and landscape (844x390). Shots: `docs/screens/uxproto_*`. What needs tuning when it is built for real:

| Area | Finding | Tune to |
|---|---|---|
| Pencil colour | The first ink (0.17, 0.19, 0.27) read navy, like a UI highlight | A greyer graphite, about (0.19, 0.20, 0.24); check on snow and on tilled soil |
| Pencil at night | Plans vanished under the night grade once the old plan-marker lift was off | Draw the sketch again after the grade in pale chalk (0.80, 0.84, 0.92) at about 0.9 x the crop-cue night lift; it read well |
| Hatch density | A 1-in-4 diagonal at 0.42 alpha is calm at zoom 2 | Check zoom 1, where it may vanish, and zoom 3, where it may look like a texture |
| Plan outlines | Every gap in a planned block (a bush that cannot be planned) draws its own box, and tilled tiles kept full outlines | Outline only the outer edge of each planned area; drop inner edges between planned and tilled tiles |
| Sketched sprouts | The stage-1 sprite sketched into scribbles at zoom 1–2 | Sketch the ripe stage instead, so the plan shows what it will become |
| Placement ghost | Status-tinted pencil (green, amber, red, blue for an upgrade) read clearly; hatch 0.7 and wash 0.18 are a little dense | Hatch about 0.55 |
| Plate see-through | 0.38 of the world showing through is subtle on busy grass, which keeps text clear | Keep 0.3–0.4; expose in the F8 editor |
| Plates by time of day | A 0.45 share of the grade warms plates at golden hour but barely dims them at night | Dim the plate base more at night (never the text) |
| Winter on plates | Frost from corners (reach 7 px) and ragged snow on top edges read as intended; snow on a 20 px Menu plate covered part of its icon | Skip snow on plates under about 24 px; keep frost to the outline ring on small plates |
| Pixel font | 7 px caps at one font pixel per UI pixel read well on desktop | Needs more glyphs (accented letters, ×, →, °, ‹ ›, the double-bang warning mark); check the slashed zero at a glance |
| UI scale | Text drawn at 2x while plates and icons stayed at 1x broke phone and landscape | Scale the whole HUD as one unit (one scale for text, icons and plates) |
| Phone vitals | Six vitals on one plate do not fit 195 UI px | Two rows of three; long values ("4 · 2.1n") may need shortening |
| Bottom row on phones | Icons only; book and tool badges at 1x were small | Draw the tool badge's seed packet at 2x on phones |
| Countdown ring | A sparse arc of single pixels round the portrait looked broken | A solid stepped arc |
| Wheel size | 12 px icons in 24 px wedges were too small, and the centre label covered a wedge | 2x icons in 32 px wedges (36 px selected), radius 58 (48 on phones), seed ring at 106 (84); label under the ring |
| Wheel backdrop | The dimming disc was a smooth circle, out of style | A stepped, dithered ring |
| Frosted capture | The prototype sampled the bloom path's graded canvas and fell back to the ungraded world | Capture from the graded frame on both paths |

The prototype code lives on the local branch `proto/ui-redesign` (flags `ProtoHud.enabled` and `Sketch.enabled`, scenario `uxproto`) and is the starting point for phases 1 and 2.
