-- Shader pass batch 3 (#193, D85): the selection outline on an object and a tile at three zooms, fireflies
-- on a summer evening, dust motes on a windy dry day, and heat shimmer (hot summer noon, lit stove).
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(4)
  local function dismissFinds()
    for _ = 1, 3 do
      local top = d.game.app:top()
      if top.select and top.take then
        top:select(1)
        top:take()
      end
      d:frames(2, 0.05)
    end
  end
  dismissFinds()
  local scene, view = d:scene(), d.game.app.view
  local cam = scene.camera
  local grid = world.state.grid
  local tile = world.tuning.display.tileSize
  local dayLength = world.tuning.time.dayLength

  local function snap(name)
    dismissFinds()
    d:frames(4, 0.05)
    dismissFinds()
    d:shot(name)
  end
  local function zoomTo(index)
    cam.zoomIndex = index
    cam:clamp(view)
    d:frames(2, 0.05)
  end
  local function look(t)
    cam:centerOn((t[1] - 0.5) * tile, (t[2] - 0.5) * tile, view)
  end
  local function sky(kind)
    local days = world.state.weather.sky.days
    for n = 1, 4 do
      days[n] = kind
    end
  end
  local function at(hour, frames)
    local now = Calendar.now(world)
    world.state.calendar.elapsed = world.state.calendar.elapsed + ((hour - now.hour) % 24) / 24 * dayLength
    d:frames(frames or 60, 0.05)
  end
  local function toSeason(name)
    while Calendar.now(world).season ~= name do
      world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
    end
  end

  local tx, ty = Grid.coords(grid, world.state.land.truck)
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if world.registry:get("objects", obj.id).clearable ~= false and math.abs(x - tx) <= 10 and math.abs(y - ty) <= 8 then
      Grid.removeObject(world, anchor)
    end
  end
  for _, put in ipairs({ { "shack", 3, -2 }, { "wood_stove", 7, -1 }, { "campfire", -2, 2 }, { "tree", -5, -2 }, { "brush", -3, -2 } }) do
    Grid.placeObject(world, put[1], tx + put[2], ty + put[3])
  end
  local yard = { tx, ty + 1 }

  -- Selection: the shack (3x2 footprint), then a bare tile, at three zooms.
  sky("clear")
  at(12, 40)
  look({ tx + 3, ty - 1 })
  scene.selected = Grid.index(grid, tx + 3, ty - 2)
  for _, index in ipairs({ 1, 2, 3 }) do
    zoomTo(index)
    snap("select_shack_zoom" .. index)
  end
  scene.selected = Grid.index(grid, tx, ty + 3)
  look({ tx, ty + 3 })
  zoomTo(3)
  snap("select_tile_zoom3")
  zoomTo(2)
  snap("select_tile_zoom2")

  -- Fireflies: a summer dusk beside the creek.
  scene.selected = nil
  toSeason("summer")
  local _, sunset = Calendar.daylight(world)
  local waterTile
  for i = 1, grid.w * grid.h do
    if not waterTile and Grid.terrain(world, i).water then
      waterTile = { Grid.coords(grid, i) }
    end
  end
  look(waterTile)
  zoomTo(2)
  at(sunset + 0.9, 30)
  snap("fireflies_creek_zoom2")
  zoomTo(3)
  snap("fireflies_creek_zoom3")
  look({ waterTile[1] + 2, waterTile[2] + 2 })
  snap("fireflies_pan")

  -- Dust motes: a dry, windy summer afternoon.
  sky("windy")
  look(yard)
  zoomTo(2)
  at(15, 80)
  snap("dust_windy_zoom2")
  zoomTo(3)
  snap("dust_windy_zoom3")
  sky("clear")
  at(15, 80)
  snap("dust_calm_zoom3")

  -- Heat shimmer: hot clear summer noon over the land, and a lit stove and campfire on a cold evening.
  local sunrise, ss = Calendar.daylight(world)
  look(yard)
  zoomTo(3)
  at((sunrise + ss) / 2, 60)
  snap("heat_noon_a")
  d:frames(5, 0.05)
  snap("heat_noon_b")
  toSeason("autumn")
  sky("clear")
  d:frames(10, 0.05)
  sky("clear")
  at(17, 120)
  for _, id in ipairs({ "firewood", "seasoned_firewood" }) do
    Ledger.add(world, id, 20, "scenario")
  end
  look({ tx + 5, ty })
  zoomTo(3)
  snap("heat_fires_a")
  d:frames(5, 0.05)
  snap("heat_fires_b")
end
