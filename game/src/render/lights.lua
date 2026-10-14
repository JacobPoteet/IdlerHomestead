-- Which objects glow at night, and where (D84). Reads the sim through accessors only; the object's
-- `light` field in data/content/objects.lua says how (radius, colour, flicker) and when it is on:
--   on = "heat"    a heat source, while the night needs warmth and there is fuel to burn
--   on = "power"   a powered light, while it is switched on and running
--   on = "shelter" the window of the shelter the homesteader sleeps in
-- Pure decisions, no drawing: tested headless.

local Grid = require("src.sim.grid")
local Needs = require("src.sim.systems.needs")
local Power = require("src.sim.systems.power")
local Shelter = require("src.sim.systems.shelter")
local Weather = require("src.sim.systems.weather")

local Lights = {}

--- Is the light of the object at `anchor` on right now (ignoring whether it is dark)?
--- `state` caches the world-wide answers for one frame: { heat = bool|nil, shelter = anchor|nil }.
function Lights.isOn(world, anchor, light, state)
  if light.on == "heat" then
    if state.heat == nil then
      local min = world.tuning.visuals.lights.heatNeedMin
      state.heat = Weather.warmthNeed(world) >= min and Needs.warmthInStock(world) > 0
    end
    return state.heat
  elseif light.on == "power" then
    return Power.sinkState(world, anchor) == "ok"
  elseif light.on == "shelter" then
    if state.shelter == nil then
      state.shelter = Shelter.best(world) or false
    end
    return state.shelter == anchor
  end
  return false
end

--- Lit objects in the tile range `visible` = { x1, y1, x2, y2 } (padded by the light's own reach):
--- a list of { anchor, x, y (world art pixels of the light's centre), left, top (sprite origin), light }.
function Lights.visible(world, visible, margin)
  local grid, tile = world.state.grid, world.tuning.display.tileSize
  local list, state = {}, {}
  for anchor, obj in pairs(grid.objects) do
    local light = world.registry:get("objects", obj.id).light
    if light then
      local x, y = Grid.coords(grid, anchor)
      if
        x >= visible[1] - margin
        and x <= visible[3] + margin
        and y >= visible[2] - margin
        and y <= visible[4] + margin + 2
      then
        if Lights.isOn(world, anchor, light, state) then
          local def = world.registry:get("objects", obj.id)
          local bottom = (y - 1 + (def.footprintH or 1)) * tile
          list[#list + 1] = { anchor = anchor, tileX = x, tileY = y, bottom = bottom, light = light, id = obj.id }
        end
      end
    end
  end
  table.sort(list, function(a, b)
    return a.anchor < b.anchor -- a stable order, so the flicker seeds never swap
  end)
  return list
end

return Lights
