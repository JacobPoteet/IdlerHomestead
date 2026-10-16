import sys

S = sys.argv[1]


def edit(p, pairs):
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        assert old in s, (p, old[:70])
        s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8", newline="\n").write(s)


funcs = open(S + "/p4_scene_funcs.lua", encoding="utf-8").read()

# The scene: the wheel's functions before the HUD drawing, its input first, its drawing last.
edit("game/src/scenes/homestead.lua", [
    ('local Icons = require("src.ui.icons")\n', 'local Icons = require("src.ui.icons")\nlocal ToolWheel = require("src.ui.tool_wheel")\n'),
    ('-- Drawing the resting HUD (D137, D142) ----', funcs.lstrip("\n") + '\n-- Drawing the resting HUD (D137, D142) ----'),
    ('''  add(out.tool, {
    id = "tools",
    label = L.tools,
    selected = self.palette == "tools",
    onPress = toggle("tools"),''', '''  add(out.tool, {
    id = "tools",
    label = L.tools,
    selected = self.wheel ~= nil or self.palette == "tools",
    onPress = function(b)
      -- The touch route to the tool wheel (D138): it opens over the badge and a tap chooses.
      if self.wheel then
        self.wheel = nil
        self:layout()
      else
        self:openWheel(b.x + b.w / 2, b.y + b.h / 2, false)
      end
    end,'''),
    ('''  if self.card then
    if self.cardButtons:action(name, data) then''', '''  -- The tool wheel (D138): held by a right press or long-press, or open after a tap on the tool badge.
  if self:wheelAction(name, data) then
    return true
  end
  if name == "wheelOpen" then
    self:openWheel(data.x, data.y, true)
    return true
  elseif name == "toolWheel" then
    local view = self.app.view
    self:openWheel(view.w / 2, view.h / 2, false)
    return true
  elseif name:match("^tool%d$") then
    local wedge = self.app.ctx.tuning.ui.wheel.wedges[tonumber(name:sub(5))]
    if wedge then
      self:equip(wedge.id)
    end
    return true
  end
  if self.card then
    if self.cardButtons:action(name, data) then'''),
    ('''  self.buttons:draw()
  self:drawCard()''', '''  self.buttons:draw()
  self:drawCard()
  self:drawWheel()'''),
    # Tool-limited orders: the Pail waters, the Axe clears (D138).
    ('''  local taskType, full = Actors.order(world, hs, i, { crop = self.seed, tool = self.tool })''',
     '''  local taskType, full =
    Actors.order(world, hs, i, { crop = self.seed, tool = self.tool, categories = TOOL_CATEGORIES[self.tool] })'''),
    ('''  elseif self.tool == "untill" then
    self:showToast(self.app.ctx.tuning.ui.placement.noUntill)
  else''', '''  elseif self.tool == "untill" then
    self:showToast(self.app.ctx.tuning.ui.placement.noUntill)
  elseif self.tool == "pail" or self.tool == "axe" then
    self:showToast(self.app.ctx.tuning.ui.placement[self.tool == "pail" and "noWater" or "noClear"])
  else'''),
    ('''  elseif self.tool == "untill" then
    return c.untill
  elseif self.seed then''', '''  elseif self.tool == "untill" then
    return c.untill
  elseif self.tool == "pail" then
    return c.pail
  elseif self.tool == "axe" then
    return c.axe
  elseif self.seed then'''),
    ('''  elseif self.tool == "untill" then
    return "icon_verb_untill", nil, L.untill
  elseif self.seed then''', '''  elseif self.tool == "untill" then
    return "icon_verb_untill", nil, L.untill
  elseif self.tool == "pail" or self.tool == "axe" then
    return Icons.tool(world, self.tool), nil, L[self.tool]
  elseif self.seed then'''),
    ('''  if self.mode == "place" and self.placing then
    local def = world.registry:get("objects", self.placing)
    local id = "icon_" .. self.placing''', '''  if self.mode == "place" and self.placing then
    local def = world.registry:get("objects", self.placing)
    local id = "icon_" .. self.placing -- the building in hand; the Hammer's own icon until the crate (#295)'''),
])

# The sim: an order can be limited to some task categories.
edit("game/src/sim/systems/tasks.lua", [
    ('''--- The task the player means by tapping tile i, or nil.
--- A task type that would apply to the tile but for a full store stops the search: the tap is
--- refused (nil) and the second return is the id of the resource that is full (#74), rather than
--- quietly falling through to some lesser task.
function Tasks.taskForTile(world, actor, i, order)
  for _, t in ipairs(world.taskTypes.list) do
    if t.clickOrder then''', '''--- The task the player means by tapping tile i, or nil.
--- A task type that would apply to the tile but for a full store stops the search: the tap is
--- refused (nil) and the second return is the id of the resource that is full (#74), rather than
--- quietly falling through to some lesser task. `order.categories` (a set of task category ids), when
--- given, limits the tap to those categories: the tool in hand does only its own work (D138).
function Tasks.taskForTile(world, actor, i, order)
  local only = order and order.categories
  for _, t in ipairs(world.taskTypes.list) do
    if t.clickOrder and (not only or only[t.category]) then'''),
])

# Words.
edit("game/data/tuning/ui.lua", [
    ('''    journalStamp = "Pick an idea",''', '''    hoe = "Hoe", -- the tool wheel's tools (D138); Hand and Rod are above
    pail = "Pail",
    axe = "Axe",
    hammer = "Hammer",
    more = "More", -- the last item of a ring too long to show: opens the full tray
    hammerEmpty = "Nothing in the crate to build: order buildings in the Catalog", -- the Hammer with an empty crate
    journalStamp = "Pick an idea",'''),
    ('''    rod = "Rod: tap the water to fish",''', '''    rod = "Rod: tap the water to fish",
    pail = "Pail: tap a thirsty crop to water it", -- D138
    axe = "Axe: tap a tree, rock, log or brush to clear it", -- D138'''),
    ('''    planSeed = "Plan %s: tap two corners (double-tap Plan to keep on)",
    planClear = "Plan field: tap two corners to clear a plan (double-tap Plan to keep on)",
    planKept = "Plan kept on: tap two corners; tap Plan to stop",''', '''    planSeed = "Plan %s: tap two corners (take Plan again quickly to keep it on)",
    planClear = "Plan field: tap two corners to clear a plan (take Plan again quickly to keep it on)",
    planKept = "Plan kept on: tap two corners; take Plan again to stop",'''),
    ('''    noUntill = "Only tilled soil can be untilled",''', '''    noUntill = "Only tilled soil can be untilled",
    noWater = "Nothing to water there", -- the Pail tapped where no crop is thirsty (D138)
    noClear = "Nothing to clear there", -- the Axe tapped where nothing can be cleared (D138)'''),
])

edit("game/data/content/ftue.lua", [
    ('"Cleared! Tap the tool at the bottom, pick a seed, then tap open ground to till and plant it."',
     '"Cleared! Hold right click (or press and hold on a touch screen) for your tools: take the Hoe and a seed, then tap open ground to till and plant it. The tool at the bottom opens them too."'),
])

# A pencil for Plan field, on the Hoe's ring.
edit("game/src/render/placeholders.lua", [
    ('''P.icon_signal_alert = rows({''', '''P.icon_verb_plan = rows({
  "........oo..",
  ".......oaao.",
  "......oWoao.",
  ".....oWWo...",
  "....oWWo....",
  "...oWWo.....",
  "..oWWo......",
  ".opWo.......",
  ".opo........",
  ".oo.........",
  "............",
  "pppppppppp..",
})

P.icon_signal_alert = rows({'''),
])
edit("game/assets/manifest.lua", [
    ('''    icon_verb_untill = { placeholder = "icon_verb_untill", w = 12, h = 12 },''', '''    icon_verb_untill = { placeholder = "icon_verb_untill", w = 12, h = 12 },
    icon_verb_plan = { placeholder = "icon_verb_plan", w = 12, h = 12 },'''),
])

# The driver: tools by their old labels go through the wheel's equip.
edit("tools/driver/driver.lua", [
    ('''function Driver:pick(label)
  if self:tryPress(label) then
    return
  end''', '''function Driver:pick(label)
  if self:tryPress(label) then
    return
  end
  local scene = self:scene()
  if scene.equipByLabel and scene:equipByLabel(label) then
    self:frames(1)
    return -- a tool: taken as the tool wheel would (D138)
  end'''),
])
edit("tools/driver/scenarios/scroll.lua", [
    ('''  -- The Tools palette with many seeds: capped, scrollbar thumb, wheel and drag.
  if d:tryPress("Tools") then''', '''  -- The tools tray with many seeds (the Hoe ring's More, D138): capped, scrollbar thumb, wheel and drag.
  d:scene():equip("hoe", { kind = "more" })
  do'''),
])
print("scene ok")
