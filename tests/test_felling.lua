-- The limit on wood from trees (issue #362, tuning.wood.fellAllowance): in a limited season felled trees add to a tally,
-- the Axe refuses trees once it reaches the allowance (logs and brush still clear), the routine and the marks stop
-- there too, the Tonight card and the readiness card say so, and the tally starts over with the next season.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local AlertText = require("src.ui.alert_text")
local Dusk = require("src.sim.systems.dusk")
local Felling = require("src.sim.systems.felling")
local FellingText = require("src.ui.felling_text")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Marks = require("src.sim.systems.marks")
local Needs = require("src.sim.systems.needs")
local Readiness = require("src.sim.systems.readiness")
local Save = require("src.core.save")
local Tasks = require("src.sim.systems.tasks")
local TonightText = require("src.ui.tonight_text")
local serialize = require("src.core.serialize")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local SEASON = tun.time.daysPerSeason

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function setDay(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + (hour or 12) / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function winterDay(n)
  return 3 * SEASON + (n or 2)
end

--- Anchors of the world's trees (kind "tree") or of the objects with an id, nearest the spawn first.
local function things(world, kind)
  local out = {}
  for anchor, obj in pairs(world.state.grid.objects) do
    local def = reg:get("objects", obj.id)
    if (kind == "tree" and def.kind == "tree") or (kind ~= "tree" and obj.id == kind) then
      out[#out + 1] = anchor
    end
  end
  local spawn = world.state.land.spawn
  table.sort(out, function(a, b)
    local da, db = Grid.distance(world.state.grid, a, spawn), Grid.distance(world.state.grid, b, spawn)
    if da == db then
      return a < b
    end
    return da < db
  end)
  return out
end

--- Fell the tree at `anchor` the way a finished job does, giving back the wood it dropped.
local function fell(world, anchor)
  local before = Ledger.get(world, "wood")
  Tasks.get(world, "clear").complete(world, Actors.homesteader(world), anchor)
  return Ledger.get(world, "wood") - before
end

local function treeDef()
  return reg:get("objects", "tree")
end

--- Fell trees until the allowance is used; returns the wood they gave and the trees left standing.
local function useUp(world)
  local trees, total = things(world, "tree"), 0
  while not Felling.limited(world, treeDef()) do
    total = total + fell(world, table.remove(trees, 1))
  end
  return total, trees
end

T.test("felling: the allowance is data, winter has one, the other seasons are unlimited", function()
  local world = newWorld()
  T.eq(Felling.allowance(world, "winter"), tun.wood.fellAllowance.winter)
  T.eq(Felling.allowance(world, "spring"), nil)
  setDay(world, 2)
  local out = Felling.outlook(world)
  T.eq(out.season, "winter", "spring looks ahead to the winter that has a limit")
  T.falsy(out.now)
  T.eq(out.left, out.allowance)
  T.eq(out.daysAway, 3 * SEASON - 2 + 1)
  T.falsy(Felling.limited(world, treeDef()), "no limit in spring")
  setDay(world, winterDay())
  out = Felling.outlook(world)
  T.truthy(out.now)
  T.eq(out.daysAway, 0)
  T.eq(out.used, 0)
end)

T.test("felling: trees in winter fill the tally, then the Axe refuses trees but not logs or brush", function()
  local world = newWorld()
  setDay(world, winterDay())
  local hs = Actors.homesteader(world)
  local trees = things(world, "tree")
  T.truthy(#trees >= 8)
  T.truthy(Tasks.get(world, "clear").canDo(world, hs, trees[1]), "a tree is fellable while there is allowance")
  local total, left = useUp(world)
  T.truthy(total >= tun.wood.fellAllowance.winter, "the last tree may carry the tally past the allowance")
  T.truthy(total < tun.wood.fellAllowance.winter + 9, "but only by one tree")
  T.eq(Felling.outlook(world).used, total)
  -- A tap on a tree: refused with the reason, no order.
  local task, full, why = Actors.order(world, hs, left[1], { categories = { clear = true } })
  T.eq(task, nil)
  T.eq(full, nil)
  T.eq(why, "felling")
  T.eq(hs.order, nil, "no order was queued")
  -- The same hand still takes brush and logs.
  local brush = things(world, "brush")[1]
  T.truthy(brush, "the start has brush")
  local brushTask = Actors.order(world, hs, brush, { categories = { clear = true } })
  T.eq(brushTask and brushTask.id, "clear")
  local log = things(world, "log")[1]
  if log then
    T.truthy(Tasks.get(world, "clear").canDo(world, hs, log), "logs are dead wood: not limited")
  end
end)

T.test("felling: the routine and the Axe marks leave trees alone once the allowance is used", function()
  local world = newWorld()
  setDay(world, winterDay())
  local _, left = useUp(world)
  local hs = Actors.homesteader(world)
  T.falsy(Tasks.get(world, "fell").canDo(world, hs, left[1]), "the 'Clear trees' routine category cannot start a tree")
  Marks.add(world, "clear", { left[1] })
  T.falsy(Tasks.get(world, "clear_marked").canDo(world, hs, left[1]), "a marked tree waits")
  T.truthy(Marks.has(world, "clear", left[1]), "and keeps its mark")
  -- The Tonight card's Chop fix marks no trees while the allowance is used up.
  setDay(world, winterDay(), 18)
  Ledger.remove(world, "wood", Ledger.get(world, "wood"))
  local before = Marks.count(world, "clear")
  Dusk.apply(world, "chop")
  for _, anchor in ipairs(Marks.list(world, "clear")) do
    local kind = reg:get("objects", world.state.grid.objects[anchor].id).kind
    T.truthy(kind ~= "tree" or anchor == left[1], "only the mark that was already there is a tree")
  end
  T.truthy(Marks.count(world, "clear") >= before)
  -- Next spring everything is allowed again, and next winter the tally has started over.
  setDay(world, 4 * SEASON + 2)
  T.falsy(Felling.limited(world, treeDef()))
  setDay(world, 7 * SEASON + 2)
  local out = Felling.outlook(world)
  T.eq(out.used, 0)
  T.eq(out.left, out.allowance)
end)

T.test("felling: brush and logs never count toward the tally", function()
  local world = newWorld()
  setDay(world, winterDay())
  for _, id in ipairs({ "brush", "log" }) do
    for _, anchor in ipairs(things(world, id)) do
      fell(world, anchor)
    end
  end
  T.eq(Felling.outlook(world).used, 0)
end)

T.test("felling: outside a limited season nothing is counted", function()
  local world = newWorld()
  setDay(world, 2)
  fell(world, things(world, "tree")[1])
  T.eq(world.state.felling.wood, 0)
  setDay(world, winterDay())
  T.eq(Felling.outlook(world).used, 0)
end)

T.test("felling: the Tonight card and the readiness card say how much the trees can still give", function()
  local world = newWorld()
  setDay(world, winterDay(), 17)
  local out = Felling.outlook(world)
  T.eq(FellingText.tonight(out), string.format("Trees: %d of %d wood left this winter.", out.allowance, out.allowance))
  local tonight = Readiness.tonight(world)
  T.eq(tonight.warmth.felling.left, out.allowance)
  local model = TonightText.build(tonight, {})
  T.truthy(model.rows[1].text:find("wood left this winter", 1, true), model.rows[1].text)
  useUp(world)
  model = TonightText.build(Readiness.tonight(world), {})
  T.truthy(model.rows[1].text:find("no more wood this winter", 1, true), model.rows[1].text)
  local _, message = AlertText.readinessCard(world)
  T.truthy(message:find("no more wood this winter", 1, true), message)
  -- Before the cold the card warns that the wood must be stored first.
  setDay(world, 2 * SEASON + 5)
  _, message = AlertText.readinessCard(world)
  T.truthy(message and message:find("trees give only", 1, true), tostring(message))
  T.eq(FellingText.tonight(Felling.outlook(world)), nil, "the Tonight card keeps quiet outside the limited season")
end)

T.test("felling: the tally is run state and survives a save", function()
  local world = newWorld()
  setDay(world, winterDay())
  fell(world, things(world, "tree")[1])
  local used = Felling.outlook(world).used
  T.truthy(used > 0)
  local copy = serialize.decode(serialize.encode(world.state.felling))
  T.eq(copy.wood, used)
  T.eq(copy.key, world.state.felling.key)
  T.truthy(Save.SAVE_COMPAT >= 18)
end)

T.test(
  "felling: the base wood cap holds Footing's fuel test through autumn; only a hard winter night passes it (A2 note)",
  function()
    -- The A2 note guessed that 3 nights of fuel in autumn is about 63 wood against a base cap of 60. Measured: the nights ramp
    -- up, so autumn's last night burns about 8 wood (3 nights = 24) and the 63 is a cold-snap night in deep winter.
    local world = newWorld()
    Inventory.addObject(world, "campfire")
    local truck = world.state.land.truck
    for i = 1, #world.state.grid.terrain do
      if Grid.distance(world.state.grid, truck, i) >= 1 and Inventory.canPlace(world, "campfire", i) then
        T.truthy(Inventory.place(world, "campfire", i))
        break
      end
    end
    local cap = Ledger.get(world, "wood") + Ledger.room(world, "wood") -- the base cap, no woodshed
    local worst = 0
    for d = 2 * SEASON + 1, 3 * SEASON do
      setDay(world, d)
      worst = math.max(worst, Needs.woodOutlook(world).perNight * tun.night.footing.fuelNights)
    end
    T.truthy(worst > 0)
    T.truthy(worst <= cap, string.format("three autumn nights (%d wood at most) fit the base cap of %d", worst, cap))
  end
)
