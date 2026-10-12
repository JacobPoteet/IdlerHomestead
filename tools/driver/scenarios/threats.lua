-- Growing-season threats (GDD §7.9, D67): the forecast hint and warning toasts for a coming threat,
-- a hail season with a storm on the forecast ("hail likely tomorrow"), the storm's hail knocking the
-- field back, and the summary toast after. The scenario jumps the clock to summer, lays out a small
-- field and writes this year's schedule and sky directly (both are seeded, so a normal run would
-- take a while to roll this), then lets the sim and the UI do the rest.
local Grid = require("src.sim.grid")

local function entry(id, start, days)
  return {
    id = id,
    start = start,
    days = days,
    status = "waiting",
    warned = false,
    rollDay = 0,
    struck = false,
    lost = 0,
    damaged = 0,
    saved = 0,
    broken = false,
  }
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  local view = d.game.app.view
  d:advance(1)

  -- Summer day 2, 8:00.
  local t = world.tuning.time
  local day = t.daysPerSeason + 2
  world.state.calendar.elapsed = (day - 1 + (8 - t.startHour) / 24) * t.dayLength
  world.state.calendar.day = day
  world.state.finds.rollDay = day -- no find offer on the jumped day
  world.tuning.finds.chancePerDay = 0 -- nor the next (the modal would stop time)

  -- A small field beside the homesteader, at mixed growth.
  local grid = world.state.grid
  local hx, hy = d:homesteaderTile()
  local planted = 0
  for dy = 2, 6 do
    for dx = -4, 4 do
      local x, y = hx + dx, hy + dy
      if planted < 20 and x >= 1 and y >= 1 and x <= grid.w and y <= grid.h then
        local i = Grid.index(grid, x, y)
        if Grid.terrain(world, i).tillable and not world.occupancy[i] then
          world.state.fields.tilled[i] = true
          world.state.fields.plan[i] = "radish"
          world.state.crops[i] = { id = "radish", growth = 0.5 + (planted % 6) * 0.1, moisture = 1 }
          planted = planted + 1
        end
      end
    end
  end
  assert(planted > 6, "no room for a field")

  -- Today cloudy, a storm tomorrow; hail season from today for two days, locusts in three days.
  local sky = world.state.weather.sky
  sky.first = day
  sky.days = { "cloudy", "storm", "clear", "clear", "cloudy", "clear", "clear", "clear" }
  local hail = entry("hail", day, 2)
  world.state.threats.years[1] = { hail, entry("locusts", day + 3, 1) }

  local cx, cy = scene.camera:tileToWorld(hx, hy + 3)
  scene.camera:centerOn(cx, cy, view)
  d:frames(4)
  d:shot("forecast")

  -- The locust warning is queued behind the hail-season toast.
  d:frames(56)
  d:shot("warning")

  -- Through the night to the storm: the hail lands at its hour.
  -- Coarse steps until close to the hail hour, then frame by frame so the summary toast is caught.
  local Calendar = require("src.sim.systems.calendar")
  local hailHour = world.registry:get("threats", "hail").hour
  local hours = 0
  while hail.status ~= "done" and hours < 48 do
    local hour = Calendar.now(world).hour
    if hour > hailHour - 0.5 and hour < hailHour + 0.5 then
      d:frames(1)
    else
      d:advance(0.25)
      hours = hours + 0.25
    end
  end
  assert(hail.struck, "the storm did not bring hail")
  scene.camera:centerOn(cx, cy, view)
  d:frames(2)
  d:shot("hail_summary")
  -- The note it wrote, right after.
  d:advance(0.25)
  d:shot("hail_note")
end
