-- Shelter ladder (D82, issue #198, first slice: truck, camp, shack).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Power = require("src.sim.systems.power")
local Readiness = require("src.sim.systems.readiness")
local Shelter = require("src.sim.systems.shelter")
local Sleep = require("src.sim.systems.sleep")
local Actors = require("src.sim.systems.actors")
local serialize = require("src.core.serialize")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function dayIn(season)
  for n, s in ipairs(tun.time.seasons) do
    if s == season then
      return (n - 1) * tun.time.daysPerSeason + 2
    end
  end
end

--- Place `id` on the legal tile nearest the truck that is at least `ring` tiles from it.
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

--- A legal tile for `id` more than `radius` tiles from the shelter at `anchor`.
local function placeFar(world, id, anchor, radius)
  Inventory.addObject(world, id)
  for i = 1, #world.state.grid.terrain do
    if Shelter.distanceTo(world, anchor, i) > radius and Inventory.canPlace(world, id, i) then
      T.truthy(Inventory.place(world, id, i))
      return i
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

T.test("shelter content: camp and shack are catalog items with notes, art and ranks", function()
  local sprites = require("assets.manifest").sprites
  local truck, camp, shack = reg:get("objects", "truck"), reg:get("objects", "camp"), reg:get("objects", "shack")
  T.truthy(truck.shelterRank < camp.shelterRank and camp.shelterRank < shack.shelterRank)
  T.truthy(truck.insulation > camp.insulation and camp.insulation > shack.insulation)
  T.truthy(truck.recovery < camp.recovery and camp.recovery < shack.recovery)
  for _, id in ipairs({ "camp", "shack" }) do
    T.truthy(reg:get("catalog", id).object == id)
    T.truthy(sprites[id] and sprites["icon_" .. id], id .. " art in the manifest")
  end
  T.truthy(reg:has("notes", "truck_cold") and reg:has("notes", "camp_cold"))
end)

T.test("shelter: insulation scales tonight's warmth need and winter readiness reads the same accessor", function()
  local world = newWorld(2)
  setTime(world, dayIn("winter"), 12)
  local raw = require("src.sim.systems.weather").warmthNeed(world)
  T.truthy(raw > 0)
  T.eq(Shelter.id(world), "truck")
  T.near(Needs.warmthNeeded(world), raw, 1e-9)
  local aheadTruck = Readiness.warmthAhead(world)
  local winterTruck = Readiness.winter(world)
  local campAt = placeNear(world, "camp", 3)
  T.eq(Shelter.id(world), "camp")
  T.near(Needs.warmthNeeded(world), raw * reg:get("objects", "camp").insulation, 1e-9)
  T.near(Readiness.warmthAhead(world), aheadTruck * reg:get("objects", "camp").insulation, 1e-6)
  Inventory.addObject(world, "shack") -- the upgrade goes over the camp (D115)
  T.truthy(Inventory.place(world, "shack", campAt))
  T.eq(Shelter.id(world), "shack")
  local shackInsulation = reg:get("objects", "shack").insulation
  T.near(Needs.warmthNeeded(world), raw * shackInsulation, 1e-9)
  local winterShack = Readiness.winter(world)
  T.near(winterShack.fuel.need, winterTruck.fuel.need * shackInsulation, 1e-6)
end)

T.test("shelter: a heat source inside the heater slot counts fully, farther ones at the far rate", function()
  local world = newWorld(2)
  clearHeat(world)
  local camp = placeNear(world, "camp", 3)
  local radius = reg:get("objects", "camp").heaterRadius
  local stove = placeNear(world, "wood_stove", 3)
  -- Put the stove right beside the camp instead of wherever it landed.
  Grid.removeObject(world, stove)
  Inventory.addObject(world, "wood_stove")
  local near
  for i = 1, #world.state.grid.terrain do
    if Shelter.distanceTo(world, camp, i) == 1 and Inventory.canPlace(world, "wood_stove", i) then
      near = i
      break
    end
  end
  T.truthy(Inventory.place(world, "wood_stove", near))
  T.truthy(Shelter.inHeaterSlot(world, near))
  T.eq(Needs.heatEfficiency(world), reg:get("objects", "wood_stove").heatSource.efficiency)
  Grid.removeObject(world, near)
  local far = placeFar(world, "wood_stove", camp, radius)
  T.truthy(far and not Shelter.inHeaterSlot(world, far))
  T.near(
    Needs.heatEfficiency(world),
    reg:get("objects", "wood_stove").heatSource.efficiency * tun.shelter.farHeat,
    1e-9
  )
end)

T.test("shelter: an electric heater outside the slot makes less warmth", function()
  local function warmthMade(far)
    local world = newWorld(4)
    clearHeat(world)
    local camp = placeNear(world, "camp", 3)
    local bank = placeNear(world, "battery_bank", 2)
    if far then
      placeFar(world, "electric_heater", camp, reg:get("objects", "camp").heaterRadius)
    else
      Inventory.addObject(world, "electric_heater")
      for i = 1, #world.state.grid.terrain do
        if Shelter.distanceTo(world, camp, i) == 1 and Inventory.canPlace(world, "electric_heater", i) then
          T.truthy(Inventory.place(world, "electric_heater", i))
          break
        end
      end
    end
    Power.add(world, bank, 20)
    setTime(world, dayIn("winter"), 18)
    for _ = 1, math.floor(tun.time.dayLength / 24 * 2 / STEP) do
      world:tick(STEP)
    end
    return world.state.power.warmth
  end
  local near, far = warmthMade(false), warmthMade(true)
  T.truthy(near > 0)
  T.near(far, near * tun.shelter.farHeat, near * 0.05)
end)

T.test("sleep: the best reachable shelter is the bed, and the night's event names it", function()
  local world = newWorld(3)
  local actor = Actors.homesteader(world)
  local truck = world.state.land.truck
  T.eq(Sleep.bedJob(world, actor).target, truck, "only the truck at first")
  local camp = placeNear(world, "camp", 3)
  T.eq(Sleep.bedJob(world, actor).target, camp, "a camp beats the truck")
  -- A camp and a shack side by side cannot be built through the shop (D115); set the shack down directly.
  local shack, shackD
  for i = 1, #world.state.grid.terrain do
    local check = Inventory.check(world, "shack", i)
    local d = Grid.distance(world.state.grid, truck, i)
    if
      check.rule == "replace"
      and #check.clear == 0
      and #check.crops == 0
      and d >= 6
      and (not shackD or d < shackD)
    then
      shack, shackD = i, d
    end
  end
  T.truthy(shack and Grid.placeObject(world, "shack", Grid.coords(world.state.grid, shack)), "a shack beside the camp")
  local job = Sleep.bedJob(world, actor)
  T.eq(job.target, shack, "a shack beats the camp, however near the camp is")
  local started = {}
  world.events:on("sleep.started", function(e)
    started[#started + 1] = e
  end)
  setTime(world, 5, Sleep.bedtimeHours(world) % 24 + 0.5)
  require("src.sim.systems.tasks").get(world, "sleep").complete(world, actor, shack)
  T.eq(started[1].shelter, "shack")
end)

T.test("shelter: better sleep restores more Condition on a fed, warm day", function()
  local function recovered(withShack)
    local world = newWorld(5)
    setTime(world, dayIn("summer"), 12)
    if withShack then
      placeNear(world, "shack", 3)
    end
    world.state.needs.condition = 50
    Ledger.add(world, "canned_food", 20)
    Needs.daily(world)
    return world.state.needs.condition - 50
  end
  T.near(recovered(false), tun.needs.dailyRecovery, 1e-9)
  T.near(recovered(true), tun.needs.dailyRecovery * reg:get("objects", "shack").recovery, 1e-9)
end)

T.test("shelter: a desk speeds study only while resting in the shack", function()
  local world = newWorld(6)
  T.eq(Shelter.studySpeed(world), 0)
  placeNear(world, "shack", 3)
  T.eq(Shelter.studySpeed(world), reg:get("objects", "shack").studySpeed)
end)

T.test("shelter: a cold night in the truck writes the note that makes the camp an idea", function()
  local world = newWorld(2)
  setTime(world, dayIn("autumn"), 12)
  T.falsy(Journal.hasNote(world, "truck_cold"))
  Needs.warm(world)
  T.truthy(Journal.hasNote(world, "truck_cold"))
  T.falsy(Journal.hasNote(world, "camp_cold"))
  placeNear(world, "camp", 3)
  Needs.warm(world)
  T.truthy(Journal.hasNote(world, "camp_cold"))
end)

T.test("shelter: the same seed and shelters give the same nights", function()
  local function play()
    local world = newWorld(9)
    placeNear(world, "camp", 3)
    setTime(world, dayIn("autumn"), 6)
    for _ = 1, math.floor(tun.time.dayLength * 3 / STEP) do
      world:tick(STEP)
    end
    return serialize.encode({ needs = world.state.needs, ledger = world.state.ledger, calendar = world.state.calendar })
  end
  T.eq(play(), play())
end)
