-- Night lights (D84): which objects glow is decided from the sim by accessors alone (render/lights.lua),
-- and the visual content and tuning are well-formed.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Lights = require("src.render.lights")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local function newWorld()
  return World.new({ registry = reg, tuning = tun }, World.newState(1))
end

--- Put `id` on the first free spot in a scan from beside the truck and return its anchor.
local function place(world, id, dx, dy)
  local grid = world.state.grid
  local tx, ty = Grid.coords(grid, world.state.land.truck)
  for r = 0, 12 do
    for step = 0, 12 do
      local x, y = tx + dx + r, ty + dy + step
      if Grid.inBounds(grid, x, y) then
        local anchor = Grid.placeObject(world, id, x, y)
        if anchor then
          return anchor
        end
      end
    end
  end
  error("no tile for " .. id)
end

local function litIds(world)
  local ids = {}
  for _, item in ipairs(Lights.visible(world, { 1, 1, world.state.grid.w, world.state.grid.h }, 0)) do
    ids[item.id] = true
  end
  return ids
end

T.test("lights: a campfire glows only while the night needs warmth and there is fuel", function()
  local world = newWorld()
  place(world, "campfire", 3, 3)
  for _, id in ipairs({ "wood" }) do
    Ledger.remove(world, id, Ledger.get(world, id), "test") -- an empty woodpile
  end
  T.falsy(litIds(world).campfire, "no fuel: no glow")
  Ledger.add(world, "wood", 5, "test")
  T.truthy(litIds(world).campfire, "fuel and a cold night: glows")
end)

T.test("lights: the shack window glows only for the shelter the homesteader sleeps in", function()
  local world = newWorld()
  place(world, "shack", 5, 0)
  T.truthy(litIds(world).shack, "the shack is the best shelter")
  T.eq(#Lights.visible(world, { 1, 1, 1, 1 }, 0), 0, "a range with no light in it lists nothing")
end)

T.test("lights: every light and sway field in the content is well-formed", function()
  for _, def in ipairs(reg:all("objects")) do
    local l = def.light
    if l then
      T.truthy(l.on == "heat" or l.on == "power" or l.on == "shelter", def.id .. ": known `on`")
      T.truthy(l.radius > 0 and #l.color == 3 and #l.at == 2, def.id .. ": radius, colour, anchor pixel")
      T.truthy(l.flicker >= 0 and l.flicker <= 1, def.id .. ": flicker 0..1")
    end
    local s = def.sway
    if s then
      T.truthy(s.weight > 0 and s.root >= 0 and s.root < 1, def.id .. ": sway weight and root")
    end
  end
end)
