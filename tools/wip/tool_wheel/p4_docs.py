def edit(p, pairs):
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        assert old in s, (p, old[:70])
        s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8", newline="\n").write(s)


edit("docs/GDD.md", [
    ('''| Keyboard | Tab (at the screen centre); keys 1–6 equip a tool directly | Arrows, Enter |''',
     '''| Keyboard | Q (at the screen centre; Tab stays with text fields); keys 1–6 equip a tool directly | Hover or a tap; Q or Esc closes it |'''),
    ('''| Touch | Long-press the world, or tap the tool badge | Slide and lift, or tap a wedge |''',
     '''| Touch | Long-press the world, or tap the tool badge | Slide and lift, or tap a wedge (the first tap on the Hoe shows its ring) |'''),
    ('''Tools are chosen on the tool wheel: hold right click, long-press, Tab, or keys 1–6 (§9.4, D138). |''',
     '''Tools are chosen on the tool wheel: hold right click, long-press, Q, or keys 1–6 (§9.4, D138). |'''),
    ('''The wheel removes the belt: hold right click, long-press, tap the tool badge or Tab; keys 1–6 equip directly;''',
     '''The wheel removes the belt: hold right click, long-press, tap the tool badge or Q (Tab stays with text fields); keys 1–6 equip directly;'''),
    ('''*Built so far:* the pixel font, plates and icons (#291), pencil plans (#292), and the resting HUD (#293: `src/ui/hud.lua` lays the plates out, pure and tested in `tests/test_hud.lua`; until the tool wheel and the tabbed books land, the tool badge opens a tools tray and each book a tray of its pages, and the power vital's card is the way into the Power panel).''',
     '''*Built so far:* the pixel font, plates and icons (#291), pencil plans (#292), the resting HUD (#293: `src/ui/hud.lua` lays the plates out, pure and tested in `tests/test_hud.lua`; until the tabbed books land each book opens a tray of its pages, and the power vital's card is the way into the Power panel), and the tool wheel (#294: `src/ui/tool_wheel.lua` is the geometry, tested in `tests/test_tool_wheel.lua`; `Input` turns a held right press, a right drag or a long-press into `wheelOpen`/`wheelMove`/`wheelRelease` where the scene wants a wheel, and a quick right click still inspects. An order can carry a set of task categories, so the Pail only waters and the Axe only clears. The Hoe's ring holds the seed packets, Untill and Plan field, and a ring too long ends in More, which opens the tools tray. Until the crate (#295) the Hammer takes the next delivery).'''),
])
edit("docs/PLAN_UI.md", [
    ('| 4 | **Tool wheel and tools**', '| 4 ✓ | **Tool wheel and tools**'),
])
print("docs ok")
