-- The dusk check and the Tonight card (GDD §4.2, D161, #340): Readiness.tonight reads the same figures as Needs,
-- Alerts and Readiness over the seasons and the shelters; the card opens at dusk, closes and comes back; the fixes
-- issue ordinary orders; the text and the geometry hold at desktop and phone shapes.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Alerts = require("src.sim.systems.alerts")
local Calendar = require("src.sim.systems.calendar")
local Dusk = require("src.sim.systems.dusk")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Marks = require("src.sim.systems.marks")
local Needs = require("src.sim.systems.needs")
local Readiness = require("src.sim.systems.readiness")
local Shelter = require("src.sim.systems.shelter")
local Sleep = require("src.sim.systems.sleep")
local Tasks = require("src.sim.systems.tasks")
local Weather = require("src.sim.systems.weather")
local serialize = require("src.core.serialize")
local Tonight = require("src.ui.tonight")
local TonightCard = require("src.ui.tonight_card")
local TonightText = require("src.ui.tonight_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.night

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function dayIn(season, year, offset)
  for n, s in ipairs(tun.time.seasons) do
    if s == season then
      return ((year or 1) - 1) * #tun.time.seasons * tun.time.daysPerSeason
        + (n - 1) * tun.time.daysPerSeason
        + (offset or 2)
    end
  end
end

--- Nothing to eat: the ledger holds no food.
local function noFood(world)
  for _, res in ipairs(reg:all("resources")) do
    if res.calories then
      Ledger.remove(world, res.id, Ledger.get(world, res.id))
    end
  end
end

local function clearHeat(world)
  for anchor, obj in pairs(world.state.grid.objects) do
    if reg:get("objects", obj.id).heatSource then
      Grid.removeObject(world, anchor)
    end
  end
end

--- Place `id` on the legal tile nearest the truck at least `ring` tiles from it.
local function placeNear(world, id, ring)
  Inventory.addObject(world, id)
  local truck = world.state.land.truck
  local best, bestD
  for i = 1, #world.state.grid.terrain do
    local d = Grid.distance(world.state.grid, truck, i)
    if d >= ring and Inventory.canPlace(world, id, i) and (not bestD or d < bestD) then
      best, bestD = i, d
    end
  end
  T.truthy(best, "found a spot for " .. id)
  T.truthy(Inventory.place(world, id, best))
  return best
end

-- The figures --------------------------------------------------------------------------------------------

--- Every figure of the card against the accessor it must agree with.
local function checkAgainstAccessors(world, label)
  local t = Readiness.tonight(world)
  local outlook, water = Needs.woodOutlook(world), Needs.waterOutlook(world)
  T.near(t.warmth.need, Needs.warmthNeeded(world), 1e-9, label .. " warmth need")
  T.near(t.warmth.wood, outlook.stock, 1e-9, label .. " wood")
  T.eq(t.warmth.perNight, outlook.perNight, label .. " wood per night")
  T.eq(t.warmth.nights, outlook.nights, label .. " nights covered")
  T.eq(t.warmth.noFire, outlook.noFire, label .. " no fire")
  T.near(t.warmth.fireNeed + t.warmth.electric, t.warmth.need, 1e-9, label .. " electric and fire make the need")
  T.near(t.food.days, Needs.foodDays(world), 1e-9, label .. " food days")
  T.near(t.food.calories, Needs.calories(world), 1e-9, label .. " calories")
  T.near(t.water.days, water.days, 1e-9, label .. " water days")
  T.near(t.water.stock, water.stock, 1e-9, label .. " water stock")
  T.eq(t.warmth.level, (Alerts.level(world, "fuel")), label .. " fuel level is the chip's")
  T.eq(t.food.level, (Alerts.level(world, "food")), label .. " food level is the chip's")
  T.eq(t.water.level, (Alerts.level(world, "drink")), label .. " drink level is the chip's")
  T.eq(t.shelter.id, Shelter.id(world), label .. " shelter")
  T.near(t.shelter.insulation, Shelter.nightInsulation(world), 1e-9, label .. " insulation")
  -- The winter readiness reads the same stock: warmth in stock is wood times what a log gives in the best fire.
  local winter = Readiness.winter(world)
  if winter then
    T.near(winter.fuel.have, t.warmth.wood * Needs.warmthPerWood(world), 1e-9, label .. " readiness stock")
    T.near(winter.food.days, t.food.days, 1e-9, label .. " readiness food")
  end
  return t
end

T.test(
  "tonight: the card's numbers match Needs, Alerts and Readiness over four seasons, two years and every shelter",
  function()
    local needs = {}
    for _, shelter in ipairs({ "truck", "camp", "shack" }) do
      local world = newWorld(3)
      if shelter ~= "truck" then
        local at = placeNear(world, "camp", 3)
        if shelter == "shack" then
          Inventory.addObject(world, "shack")
          T.truthy(Inventory.place(world, "shack", at))
        end
      end
      T.eq(Shelter.id(world), shelter)
      placeNear(world, "campfire", 1)
      Ledger.add(world, "wood", 17)
      Ledger.add(world, "canned_food", 4)
      for year = 1, 2 do
        for _, season in ipairs(tun.time.seasons) do
          for _, offset in ipairs({ 1, 4, 7 }) do
            setTime(world, dayIn(season, year, offset), 15)
            local t = checkAgainstAccessors(world, string.format("%s y%d %s d%d", shelter, year, season, offset))
            needs[#needs + 1] = t.warmth.need
          end
        end
      end
    end
    local varied = {}
    for _, n in ipairs(needs) do
      varied[string.format("%.4f", n)] = true
    end
    local kinds = 0
    for _ in pairs(varied) do
      kinds = kinds + 1
    end
    T.truthy(kinds > 12, "the sweep covered many different nights, not one")
  end
)

T.test("tonight: a shortage shows as a gap with the chips' own levels", function()
  local world = newWorld(2)
  placeNear(world, "campfire", 1)
  setTime(world, dayIn("winter", 1, 3), 15)
  noFood(world)
  world.state.needs.canteen = 0
  local t = checkAgainstAccessors(world, "bare winter")
  T.eq(t.warmth.level, 2)
  T.eq(t.food.level, 2)
  T.eq(t.water.level, 2)
  T.eq(t.gaps, 3)
  Ledger.add(world, "wood", 200)
  Ledger.add(world, "canned_food", 30)
  world.state.needs.canteen = tun.needs.canteenCapacity
  t = checkAgainstAccessors(world, "stocked winter")
  T.eq(t.gaps, 0)
  T.eq(t.warmth.level + t.food.level + t.water.level, 0)
end)

T.test("tonight: summer needs no fire, a missing fire is flagged, and the heaters' share is split out", function()
  local world = newWorld(2)
  clearHeat(world)
  setTime(world, dayIn("summer", 1, 4), 15)
  local t = Readiness.tonight(world)
  T.eq(t.warmth.need, 0)
  T.eq(t.warmth.nights, math.huge)
  T.falsy(t.warmth.noFire)
  setTime(world, dayIn("winter", 1, 4), 15)
  t = Readiness.tonight(world)
  T.truthy(t.warmth.need > 0)
  T.truthy(t.warmth.noFire, "a winter night with no fire placed")
  T.eq(t.warmth.level, 2)
  T.falsy(t.shelter.heat)
  placeNear(world, "campfire", 1)
  t = Readiness.tonight(world)
  T.falsy(t.warmth.noFire)
  T.truthy(t.shelter.heat)
end)

T.test("tonight: asking changes nothing (the saved shape is untouched)", function()
  local world = newWorld(2)
  placeNear(world, "campfire", 1)
  setTime(world, dayIn("autumn", 1, 5), 15)
  local before = serialize.encode(world.state)
  Readiness.tonight(world)
  Readiness.tonightDue(world)
  Dusk.fixes(world)
  T.eq(serialize.encode(world.state), before)
end)

T.test("tonight: exposure is a stub read from the shelter alone, truck highest and shack lowest", function()
  local world = newWorld(2)
  local e = Readiness.tonight(world).exposure
  T.truthy(e.stub)
  T.eq(e.level, "high")
  local at = placeNear(world, "camp", 3)
  T.eq(Readiness.tonight(world).exposure.level, "medium")
  Inventory.addObject(world, "shack")
  T.truthy(Inventory.place(world, "shack", at))
  T.eq(Readiness.tonight(world).exposure.level, "low")
end)

T.test("tonight: risks list a cold snap tonight or coming, and a stormy night", function()
  local world = newWorld(2)
  setTime(world, dayIn("winter", 1, 3), 15)
  Weather.force(world, "clear")
  T.eq(#Readiness.tonight(world).risks, 0, "a clear night with no snap")
  local winter = Weather.winter(world)
  local state = world.state.weather
  state.revealed[1] = 3 -- the whole forecast is known
  setTime(world, dayIn("winter", 1, winter.snapStart), 15)
  local risks = Readiness.tonight(world).risks
  T.eq(risks[1].id, "snap")
  T.eq(risks[1].days, 0)
  Weather.force(world, "clear")
  if winter.snapStart - cfg.snapLookDays >= 1 then
    setTime(world, dayIn("winter", 1, winter.snapStart - 1), 15)
    Weather.force(world, "clear")
    risks = Readiness.tonight(world).risks
    T.eq(risks[1].id, "snap")
    T.eq(risks[1].days, 1)
  end
  world = newWorld(2) -- the sky does not run backwards: a fresh world for the autumn night
  setTime(world, dayIn("autumn", 1, 3), 15)
  Weather.force(world, "storm")
  risks = Readiness.tonight(world).risks
  T.eq(risks[#risks].id, "storm")
  T.eq(risks[#risks].kind, "storm")
end)

-- The evening ----------------------------------------------------------------------------------------

T.test("tonight: the card is due from duskLeadHours before sunset until bedtime, in every season", function()
  local world = newWorld(2)
  T.truthy(cfg.duskLeadHours > 0)
  for _, season in ipairs(tun.time.seasons) do
    setTime(world, dayIn(season, 1, 3), 12)
    local sunrise, sunset = Calendar.daylight(world)
    local from = math.max(sunrise, sunset - cfg.duskLeadHours)
    setTime(world, dayIn(season, 1, 3), from - 0.2)
    T.falsy((Readiness.tonightDue(world)), season .. " just before the lead")
    setTime(world, dayIn(season, 1, 3), from + 0.2)
    local due, leads = Readiness.tonightDue(world)
    T.truthy(due and leads, season .. " just after the lead")
    T.eq(Readiness.tonight(world).due, true)
    setTime(world, dayIn(season, 1, 3), sunset + 0.5)
    T.truthy((Readiness.tonightDue(world)), season .. " after sunset")
    local bed = Sleep.bedtimeHours(world)
    setTime(world, dayIn(season, 1, 3), bed % 24 + 0.2)
    T.falsy((Readiness.tonightDue(world)), season .. " at bedtime")
    setTime(world, dayIn(season, 1, 3), 3)
    T.falsy((Readiness.tonightDue(world)), season .. " in the small hours")
  end
end)

-- The card's state --------------------------------------------------------------------------------

T.test("tonight card: opens once a day at dusk, stays closed once dismissed, comes back from the stamp", function()
  local s = Tonight.new()
  s:sync(false, true, 5, false)
  T.falsy(s.open, "by day it is closed")
  s:sync(true, true, 5, false)
  T.truthy(s.open, "it opens by itself at dusk")
  s:dismiss(5, true)
  s:sync(true, true, 5, false)
  T.falsy(s.open, "dismissed in the evening it stays closed that day")
  T.truthy(s:stampDue(true, true, 0), "the stamp offers it back")
  T.truthy(s:toggle(5, true))
  T.truthy(s.open and s.manual)
  s:sync(false, true, 5, true)
  T.truthy(s.open, "a card the player opened stays through bedtime")
  s:dismiss(5, true)
  s:sync(true, true, 6, false)
  T.truthy(s.open, "the next day's dusk opens it again")
end)

T.test(
  "tonight card: an automatic card puts itself away at bedtime; one dismissed by day still opens at dusk",
  function()
    local s = Tonight.new()
    s:sync(true, true, 2, false)
    T.truthy(s.open)
    s:sync(false, true, 2, false)
    T.falsy(s.open, "the evening is over")
    local d = Tonight.new()
    T.truthy(d:toggle(3, false))
    d:dismiss(3, false) -- closed in the afternoon
    d:sync(true, true, 3, false)
    T.truthy(d.open, "still opens at dusk")
  end
)

T.test("tonight card: it does not lead (Footing held) means no stamp and no automatic opening", function()
  local s = Tonight.new()
  s:sync(true, false, 4, false)
  T.falsy(s.open)
  T.falsy(s:stampDue(true, false, 3))
  T.truthy(s:toggle(4, true), "the T key still brings it up")
end)

T.test(
  "tonight card: the stamp shows in the evening or while something is short, never while the card is open",
  function()
    local s = Tonight.new()
    T.falsy(s:stampDue(false, true, 0), "nothing to see by day when all is well")
    T.truthy(s:stampDue(false, true, 1), "a gap by day")
    T.truthy(s:stampDue(true, true, 0), "the evening")
    s:toggle(1, false)
    T.falsy(s:stampDue(true, true, 2))
  end
)

T.test(
  "tonight card: the place is a side card on a wide view and a sheet on a tall one, inside the free band",
  function()
    local ui = tun.ui.tonight
    local touch = tun.input.minTouchTarget
    for _, view in ipairs({
      { w = 640, h = 360 },
      { w = 1280, h = 720 },
      { w = 780, h = 360 },
      { w = 360, h = 780 },
      { w = 640, h = 1385 },
    }) do
      local bounds = { top = 40, bottom = view.h - 40 }
      local spec = Tonight.place(ui, view, bounds, 200, touch)
      local r = spec.rect
      T.eq(spec.layout, view.w > view.h and "side" or "sheet")
      T.truthy(r.x >= ui.margin and r.x + r.w <= view.w - ui.margin, "inside the width")
      T.truthy(r.y >= bounds.top and r.y + r.h <= bounds.bottom, "inside the band")
      T.truthy(r.w >= 200, "wide enough to read")
      local small = Tonight.place(ui, view, bounds, 10, touch)
      T.truthy(small.rect.h <= r.h, "short content makes a short card")
    end
  end
)

-- The text and the buttons ----------------------------------------------------------------------------

local function fakeCtx()
  return { tuning = tun }
end

T.test("tonight text: the rows carry the figures and a word for the level", function()
  local world = newWorld(2)
  placeNear(world, "campfire", 1)
  setTime(world, dayIn("winter", 1, 3), 15)
  Ledger.add(world, "wood", 4)
  local t = Readiness.tonight(world)
  local model = TonightText.build(t, Dusk.fixes(world, t))
  T.eq(#model.rows, 3)
  T.eq(model.rows[1].id, "warmth")
  T.truthy(model.rows[1].text:find("wood"))
  T.truthy(model.rows[1].word == "Low" or model.rows[1].word == "Short" or model.rows[1].word == "Fine")
  T.eq(model.rows[1].word, ({ [0] = "Fine", "Low", "Short" })[t.warmth.level])
  T.truthy(model.subtitle:find("Sunset in"))
  T.truthy(model.notes[1].text:find("Shelter"))
  T.truthy(model.notes[2].text:find("Exposure"))
  -- A fine night says so and offers no fix.
  Ledger.add(world, "wood", 300)
  Ledger.add(world, "canned_food", 30)
  world.state.needs.canteen = tun.needs.canteenCapacity
  t = Readiness.tonight(world)
  model = TonightText.build(t, Dusk.fixes(world, t))
  T.eq(model.summary, TonightText.ready)
  for _, row in ipairs(model.rows) do
    T.eq(row.fix, nil)
    T.eq(row.level, 0)
  end
end)

T.test("tonight card: a fix is a button a finger can hit, Tab walks the buttons and Enter presses one", function()
  local world = newWorld(2)
  placeNear(world, "campfire", 1)
  setTime(world, dayIn("winter", 1, 3), 15)
  world.state.needs.canteen = 0
  local t = Readiness.tonight(world)
  local model = TonightText.build(t, Dusk.fixes(world, t))
  local card = TonightCard.new(fakeCtx())
  local pressed, closed = {}, 0
  local rect = { x = 300, y = 40, w = 280, h = 300 }
  card:setup(model, rect, function()
    closed = closed + 1
  end, function(fix)
    pressed[#pressed + 1] = fix.id
  end)
  local touch = tun.input.minTouchTarget
  local fixes = 0
  for _, row in ipairs(model.rows) do
    if row.fix then
      fixes = fixes + 1
    end
  end
  T.truthy(fixes >= 2, "wood and water are short")
  T.eq(#card.order, fixes + 1, "the fixes and Close are on the keyboard order")
  for _, b in ipairs(card.rowButtons.list) do
    T.truthy(b.h >= touch and b.w >= touch)
    T.truthy(b.x >= rect.x and b.x + b.w <= rect.x + rect.w)
  end
  -- Keyboard: Tab shows the ring on the first control; Enter presses it.
  T.eq(card:focused(), nil)
  card.focus = 1
  card:moveFocus(1)
  T.truthy(card:focused(), "the ring shows after a key")
  T.eq(card.focus, 1, "on the first control")
  T.truthy(card:activate())
  T.eq(#pressed, 1)
  card:moveFocus(1)
  T.eq(card.focus, 2, "Tab again moves along")
  card:moveFocus(-1)
  card:moveFocus(-1)
  T.eq(card.focus, #card.order, "Shift+Tab wraps to the last, Close")
  -- Touch: a tap on the same button does the same; a tap outside the card is not the card's.
  local first = card.rowButtons.list[1]
  T.truthy(card:action("select", { x = first.x + 2, y = first.y + 2 }))
  T.eq(#pressed, 2)
  T.falsy(card:action("select", { x = 5, y = 5 }), "the world stays tappable around it")
  T.falsy(card:action("press", { x = 5, y = 5 }))
  T.falsy(card:action("pan", { dx = 3, dy = 3 }))
  -- Close, by tap.
  local close = card.buttons.list[1]
  T.truthy(card:action("select", { x = close.x + 2, y = close.y + 2 }))
  T.eq(closed, 1)
  -- A pointer press puts the ring away.
  card:action("press", { x = 5, y = 5 })
  T.eq(card:focused(), nil)
end)

-- The fixes ------------------------------------------------------------------------------------------------

local function treesByDistance(world)
  local hs = Actors.homesteader(world)
  local list = {}
  for anchor, obj in pairs(world.state.grid.objects) do
    local def = reg:get("objects", obj.id)
    if def.chop and def.yields and def.yields.wood then
      local x, y = Grid.coords(world.state.grid, anchor)
      list[#list + 1] = { anchor = anchor, d = (x - hs.x) ^ 2 + (y - hs.y) ^ 2 }
    end
  end
  table.sort(list, function(a, b)
    if a.d ~= b.d then
      return a.d < b.d
    end
    return a.anchor < b.anchor
  end)
  return list
end

T.test("dusk fix: chop marks the nearest trees, no more than the gap needs, and a second tap adds none", function()
  local world = newWorld(2)
  placeNear(world, "campfire", 1)
  setTime(world, dayIn("winter", 1, 3), 15)
  local fixes = Dusk.fixes(world)
  local chop
  for _, f in ipairs(fixes) do
    if f.gap == "warmth" then
      chop = f
    end
  end
  T.truthy(chop and chop.id == "chop" and chop.kind == "order", "wood is short and trees stand")
  T.truthy(chop.count >= 1 and chop.count <= cfg.fix.maxMarks)
  T.truthy(chop.wood > 0)
  local ok, added = Dusk.apply(world, "chop")
  T.truthy(ok)
  T.eq(added, chop.count)
  T.eq(Marks.count(world, "clear"), chop.count)
  local nearest = treesByDistance(world)[1]
  T.truthy(Marks.has(world, "clear", nearest.anchor), "the nearest tree is the first marked")
  -- The marks stand as orders on the board: the next look sees them and asks for no more.
  local again
  for _, f in ipairs(Dusk.fixes(world)) do
    if f.gap == "warmth" then
      again = f
    end
  end
  T.truthy(again.id == "chop" and again.count >= 0)
  if again.queued then
    T.eq(again.count, chop.count)
  else
    T.truthy(again.short < chop.short, "what is already marked counts toward the gap")
  end
end)

T.test("dusk fix: enough wood needs no chop fix; the stock covers the line", function()
  local world = newWorld(2)
  placeNear(world, "campfire", 1)
  setTime(world, dayIn("winter", 1, 3), 15)
  Ledger.add(world, "wood", 300)
  for _, f in ipairs(Dusk.fixes(world)) do
    T.truthy(f.gap ~= "warmth", "no warmth fix on a stocked night")
  end
end)

T.test("dusk fix: no fire placed points at the Catalog; no tree in reach points at town", function()
  local world = newWorld(2)
  clearHeat(world)
  setTime(world, dayIn("winter", 1, 3), 15)
  local fixes = Dusk.fixes(world)
  T.eq(fixes[1].id, "place_fire")
  T.eq(fixes[1].kind, "open")
  T.eq(fixes[1].book, "catalog")
  placeNear(world, "campfire", 1)
  for anchor, obj in pairs(world.state.grid.objects) do
    if reg:get("objects", obj.id).chop then
      Grid.removeObject(world, anchor)
    end
  end
  local buy
  for _, f in ipairs(Dusk.fixes(world)) do
    if f.gap == "warmth" then
      buy = f
    end
  end
  T.eq(buy.id, "buy_wood")
  T.eq(buy.kind, "open")
  T.eq(buy.book, "truck")
  T.falsy((Dusk.apply(world, "chop")), "nothing to mark")
end)

T.test("dusk fix: fish switches the routine's Fish category on and puts it first", function()
  local world = newWorld(2)
  setTime(world, dayIn("summer", 1, 3), 15)
  noFood(world)
  Tasks.setPriorityEnabled(world, "fish", false)
  Tasks.movePriority(world, "fish", 3)
  local fix
  for _, f in ipairs(Dusk.fixes(world)) do
    if f.gap == "food" then
      fix = f
    end
  end
  T.truthy(fix and fix.id == "fish" and fix.kind == "order", "food is short at the start")
  T.truthy(Dusk.apply(world, "fish"))
  T.eq(world.state.priorities[1].category, "fish")
  T.eq(world.state.priorities[1].enabled, true)
end)

T.test("dusk fix: without a rod the food gap points at the Pantry", function()
  local world = newWorld(2)
  world.state.inventory.equipment = {}
  noFood(world)
  setTime(world, dayIn("summer", 1, 3), 15)
  local fix
  for _, f in ipairs(Dusk.fixes(world)) do
    if f.gap == "food" then
      fix = f
    end
  end
  T.eq(fix.id, "open_pantry")
  T.eq(fix.kind, "open")
end)

T.test("dusk fix: fill orders the homesteader to the creek or a well; the order is the ordinary one", function()
  local world = newWorld(2)
  setTime(world, dayIn("summer", 1, 3), 15)
  world.state.needs.canteen = 0
  local fix
  for _, f in ipairs(Dusk.fixes(world)) do
    if f.gap == "water" then
      fix = f
    end
  end
  T.eq(fix.id, "fill")
  local hs = Actors.homesteader(world)
  local ok, verb = Dusk.apply(world, "fill")
  T.truthy(ok)
  T.eq(hs.order.task, "fetch_drinking")
  T.eq(verb, Tasks.get(world, "fetch_drinking").verb)
  T.truthy(hs.order.ordered, "a player order like a tap")
  -- Working the order fills the canteen.
  for _ = 1, 20 * 300 do
    world:tick(1 / tun.time.tickRate)
    if Needs.canteen(world) > 0 then
      break
    end
  end
  T.truthy(Needs.canteen(world) > 0, "the homesteader filled the canteen")
end)

T.test("dusk fix: a fine night has no fixes, and an unknown fix does nothing", function()
  local world = newWorld(2)
  setTime(world, dayIn("summer", 1, 3), 15)
  Ledger.add(world, "canned_food", 30)
  world.state.needs.canteen = tun.needs.canteenCapacity
  T.eq(#Dusk.fixes(world), 0)
  T.falsy((Dusk.apply(world, "nonsense")))
end)
