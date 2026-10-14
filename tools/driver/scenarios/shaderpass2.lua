-- Shader pass batch 2 (#193, D84): wind sway of crops, brush and trees (two frames apart, plus a gale),
-- morning mist over the creek at dawn and burnt off by mid-morning, and night lights (campfire, lamp, wood
-- stove, shack window) over the time-of-day grade.
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(4)
  local function dismissFinds() -- a find popup can open on any day: take the first card
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
  --- Jump the clock to `hour` (24h) of the current day, then let the look settle.
  local function at(hour, frames)
    local now = Calendar.now(world)
    world.state.calendar.elapsed = world.state.calendar.elapsed + ((hour - now.hour) % 24) / 24 * dayLength
    d:frames(frames or 60, 0.05)
  end

  -- Tidy the yard round the truck, then lay it out: a shack, a stove, a lamp, a campfire, a trees and a field.
  local tx, ty = Grid.coords(grid, world.state.land.truck)
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if
      world.registry:get("objects", obj.id).clearable ~= false
      and math.abs(x - tx) <= 10
      and math.abs(y - ty) <= 8
    then
      Grid.removeObject(world, anchor)
    end
  end
  for _, put in ipairs({
    { "shack", 3, -2 },
    { "wood_stove", 7, -1 },
    { "lamp", 2, 1 },
    { "campfire", -2, 2 },
    { "tree", -5, -2 },
    { "tree", -6, 1 },
    { "brush", -3, -2 },
    { "brush", 6, 2 },
  }) do
    Grid.placeObject(world, put[1], tx + put[2], ty + put[3])
  end
  -- A small field of radishes and potatoes, some thirsty.
  for fy = 4, 6 do
    for fx = -3, 2 do
      local i = Grid.index(grid, tx + fx, ty + fy)
      world.state.fields.tilled[i] = true
      world.state.crops[i] = {
        id = (fx + fy) % 2 == 0 and "radish" or "potato",
        growth = 0.3 + 0.12 * (fx + 3),
        moisture = fx == 2 and 0 or 1,
      }
    end
  end
  local yard = { tx, ty + 3 }

  -- Wind: a calm, then a gale. Two frames a moment apart show the sway; the gale leans further.
  sky("clear")
  at(12, 80)
  look(yard)
  zoomTo(3)
  d:shot("wind_calm_a")
  d:frames(37, 0.05) -- about half a sway period, so the second frame leans the other way
  d:shot("wind_calm_b")
  sky("windy")
  at(12, 80)
  d:shot("wind_windy_a")
  d:frames(26, 0.05)
  d:shot("wind_windy_b")
  zoomTo(2)
  d:shot("wind_windy_zoom2")

  -- Mist at dawn over the creek, thinner at mid-morning, none in a gale.
  sky("clear")
  local sunrise = Calendar.daylight(world)
  local waterTile
  for i = 1, grid.w * grid.h do
    if not waterTile and Grid.terrain(world, i).water then
      waterTile = { Grid.coords(grid, i) }
    end
  end
  look(waterTile)
  zoomTo(2)
  at(sunrise + 0.3, 90)
  dismissFinds()
  d:shot("mist_dawn_zoom2")
  zoomTo(1)
  d:shot("mist_dawn_zoom1")
  zoomTo(3)
  d:shot("mist_dawn_zoom3")
  at(sunrise + 2.2, 60)
  zoomTo(2)
  d:shot("mist_fading")
  at(sunrise + 5, 60)
  d:shot("mist_gone")
  sky("windy")
  at(sunrise + 0.3, 90)
  dismissFinds()
  d:shot("mist_windy")
  sky("clear")

  -- Night: the campfire and stove burn (there is fuel and the night is cold), the lamp is on, the shack is home.
  local _, sunset = Calendar.daylight(world)
  world.state.power.charge[world.state.land.truck] = 50
  for _, id in ipairs({ "wood" }) do
    Ledger.add(world, id, 20, "scenario")
  end
  look(yard)
  zoomTo(3)
  at(sunset - 0.3, 20)
  snap("lights_dusk_zoom3")
  at(sunset + 2, 40)
  dismissFinds()
  snap("lights_night_zoom3")
  zoomTo(2)
  snap("lights_night_zoom2")
  zoomTo(1)
  snap("lights_night_zoom1")
  look({ tx + 5, ty })
  zoomTo(2)
  snap("lights_night_pan")
end
