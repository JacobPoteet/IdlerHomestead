-- Lighting polish (#283): leaf dapple under a tree at mid-morning and late afternoon (a frame pair, so the
-- flecks are seen to shuffle), hens and goats with their shadows, the autumn rim light on a golden
-- afternoon, the optional depth of field, and the warm night light pools by the campfire.
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")

--- The free spot for `id` nearest (sx + dx, sy + dy), or nil.
local function spotNear(world, id, sx, sy, dx, dy)
  local grid = world.state.grid
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - sx - dx) ^ 2 + (y - sy - dy) ^ 2
    if (not bestDist or dist < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, dist
    end
  end
  return best
end

--- The tree nearest (sx, sy) with open ground below it for its shadow.
local function treeNear(world, sx, sy)
  local grid = world.state.grid
  local best, bestDist
  for anchor, obj in pairs(grid.objects) do
    if obj.id == "tree" then
      local x, y = Grid.coords(grid, anchor)
      local dist = (x - sx) ^ 2 + (y - sy) ^ 2
      if not bestDist or dist < bestDist then
        best, bestDist = anchor, dist
      end
    end
  end
  return best
end

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  d:advance(2)
  for _ = 1, 3 do -- a find popup can open on any day: take the first card
    local top = d.game.app:top()
    if top.select and top.take then
      top:select(1)
      top:take()
    end
    d:frames(2, 0.05)
  end
  local scene, view = d:scene(), d.game.app.view
  local settings = d.game.app.ctx.settings
  local tile = world.tuning.display.tileSize
  local dayLength = world.tuning.time.dayLength
  local function at(hour)
    local now = Calendar.now(world)
    world.state.calendar.elapsed = world.state.calendar.elapsed + ((hour - now.hour) % 24) / 24 * dayLength
    d:frames(40, 0.05)
  end
  local function look(tx, ty, zoom)
    scene.camera.zoomIndex = zoom
    scene.camera:centerOn((tx - 0.5) * tile, (ty - 0.5) * tile, view)
    scene.camera:clamp(view)
    d:frames(2, 0.05)
  end
  local days = world.state.weather.sky.days
  local function sky(kind)
    for n = 1, #days do
      days[n] = kind
    end
  end
  sky("clear")

  -- Leaf dapple: sun flecks through the canopy's shadow, morning and afternoon.
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local tree = assert(treeNear(world, sx, sy), "no tree on the map")
  local tx, ty = Grid.coords(grid, tree)
  look(tx, ty + 1, 3)
  for _, hour in ipairs({ 9.5, 16 }) do
    at(hour)
    d:shot(("dapple_%04.1f_a"):format(hour))
    d:frames(12, 0.05)
    d:shot(("dapple_%04.1f_b"):format(hour))
  end

  -- Hens and goats cast shadows like everything else.
  local coop = assert(spotNear(world, "chicken_coop", sx, sy, 3, 3), "no spot for the coop")
  Inventory.addObject(world, "chicken_coop")
  assert(Inventory.place(world, "chicken_coop", coop))
  local pen = assert(spotNear(world, "goat_pen", sx, sy, -4, 3), "no spot for the pen")
  Inventory.addObject(world, "goat_pen")
  assert(Inventory.place(world, "goat_pen", pen))
  Ledger.add(world, "hen", 5, "driver")
  Ledger.add(world, "goat", 3, "driver")
  Ledger.add(world, "chicken_feed", 10, "driver")
  local cx, cy = Grid.coords(grid, coop)
  look(cx + 1, cy + 2, 3)
  at(10)
  d:shot("hens_shadows")
  local px, py = Grid.coords(grid, pen)
  look(px + 1, py + 1, 3)
  d:shot("goats_shadows")

  -- Night: warm pools of light round the campfire and lamp.
  Ledger.add(world, "wood", 20, "driver")
  at(21)
  look(sx, sy, 3)
  d:shot("night_pools_zoom3")
  look(sx, sy, 1)
  d:shot("night_pools_zoom1")

  -- Autumn: a warm rim of light on the sun side of every sprite, strongest at low sun.
  local now = Calendar.now(world)
  local perSeason = world.tuning.time.daysPerSeason
  world.state.calendar.elapsed = world.state.calendar.elapsed + ((3 - now.seasonIndex) * perSeason + (4 - now.dayOfSeason)) * dayLength
  Ledger.add(world, "canned_food", 20, "driver")
  at(16.5)
  sky("clear") -- after the jump: the sim rolls the new days' weather on the first frames of the new day
  for _ = 1, 4 do -- the morning report and any find popup
    if d.game.app:top() ~= scene then
      d:key("escape")
    end
    d:tryPress("Got it")
    d:frames(2, 0.05)
  end
  look(sx, sy, 3)
  d:frames(20, 0.05)
  d:shot("autumn_rim_zoom3")
  look(tx, ty + 1, 3)
  d:shot("autumn_rim_tree")
  look(sx, sy, 2)
  d:shot("autumn_rim_zoom2")
  at(11)
  d:shot("autumn_noon_zoom2")

  -- Depth of field (off by default): the top and bottom of the view soften on the art-pixel grid.
  settings:set("depthOfField", true)
  d:frames(2, 0.05)
  d:shot("dof_on")
  settings:set("depthOfField", false)
  d:frames(2, 0.05)
  d:shot("dof_off")

end
