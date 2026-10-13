-- Fireflies, dust motes and heat shimmer (D85): the amounts are decided from the calendar and weather alone
-- (render/ambient.lua), so they test headless with a stub fx.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Calendar = require("src.sim.systems.calendar")
local Ambient = require("src.render.ambient")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local function newWorld()
  return World.new({ registry = reg, tuning = tun }, World.newState(1))
end

--- Put the clock on `season` at `hour`.
local function setClock(world, season, hour)
  local dayLength = tun.time.dayLength
  while Calendar.now(world).season ~= season do
    world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  end
  local now = Calendar.now(world)
  world.state.calendar.elapsed = world.state.calendar.elapsed + ((hour - now.hour) % 24) / 24 * dayLength
end

local function fx(wind, rain, wet)
  return {
    wind = wind or 1,
    rainAndWet = function()
      return rain or 0, wet or 0
    end,
  }
end

T.test("fireflies come out on a summer evening only", function()
  local world = newWorld()
  setClock(world, "summer", 12)
  T.eq(Ambient.fireflyAmount(world, fx()), 0, "none at noon")
  local _, sunset = Calendar.daylight(world)
  setClock(world, "summer", sunset + 1)
  T.truthy(Ambient.fireflyAmount(world, fx()) > 0.9, "out an hour after sunset")
  T.eq(Ambient.fireflyAmount(world, fx(1, 1)), 0, "not in rain")
  T.eq(Ambient.fireflyAmount(world, fx(2)), 0, "not in a gale")
  setClock(world, "winter", sunset + 1)
  T.eq(Ambient.fireflyAmount(world, fx()), 0, "none in winter")
end)

T.test("dust needs dry daylight and rises with the wind", function()
  local world = newWorld()
  setClock(world, "summer", 14)
  local calm = Ambient.dustAmount(world, fx(1), 1, 0)
  local windy = Ambient.dustAmount(world, fx(1.7), 1, 0)
  T.truthy(calm > 0 and windy > calm, "windy air holds more dust than calm air")
  T.eq(Ambient.dustAmount(world, fx(1.7), 0, 0), 0, "none at night")
  T.eq(Ambient.dustAmount(world, fx(1.7, 0, 1), 1, 0), 0, "none on wet ground")
  T.eq(Ambient.dustAmount(world, fx(1.7), 1, 1), 0, "none under snow")
end)

T.test("heat shimmer is for hot clear summer noons", function()
  local world = newWorld()
  setClock(world, "summer", 13)
  local noon = Ambient.heatAmount(world, 1, 0)
  T.truthy(noon > 0, "hot at noon")
  setClock(world, "summer", 19)
  T.truthy(Ambient.heatAmount(world, 1, 0) < noon, "cooler in the evening")
  setClock(world, "winter", 13)
  T.eq(Ambient.heatAmount(world, 1, 0), 0, "none in winter")
end)

T.test("ambient tuning is well-formed", function()
  local v = tun.visuals
  T.truthy(v.dust.cell > 0 and math.abs(math.log(v.dust.cell) / math.log(2) % 1) < 1e-9, "dust cell is a power of two")
  T.truthy(v.heat.maxSources <= 4, "heat sources fit the shader array")
  T.truthy(v.selection.thickness >= 1, "selection ring has thickness")
end)
