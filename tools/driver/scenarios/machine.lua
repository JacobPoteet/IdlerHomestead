-- Machines (GDD §7.4, D65): the auto-harvester placed beside a field, the reach shown while
-- placing, working (arm, progress ring, card and reach), unpowered (red reach, card, toast), and the
-- Machines chapter of the journal. The scenario sets the homestead up directly (as if bought and
-- placed, with a field already grown), then lets the sim run so the machine does real work.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Machines = require("src.sim.systems.machines")

-- Place `id` on the free tile nearest `near` where it fits. Returns its anchor tile index.
local function place(world, id, near)
  local grid = world.state.grid
  local nx, ny = Grid.coords(grid, near)
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - nx) ^ 2 + (y - ny) ^ 2
    if (not bestDist or dist < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, dist
    end
  end
  assert(best, "no spot for " .. id)
  Inventory.addObject(world, id)
  assert(Inventory.place(world, id, best))
  return best
end

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local site = Grid.index(grid, math.min(grid.w - 8, sx + 6), math.min(grid.h - 6, sy + 2))
  d:advance(4) -- late morning: the sun is up

  -- Tidy the clutter around the site so the capture shows the field, not the messy start.
  local siteX, siteY = Grid.coords(grid, site)
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if
      world.registry:get("objects", obj.id).clearable ~= false
      and math.abs(x - siteX) <= 7
      and math.abs(y - siteY) <= 6
    then
      Grid.removeObject(world, anchor)
    end
  end
  local array = place(world, "solar_array", Grid.index(grid, siteX + 5, siteY - 3))

  local scene = d:scene()
  local view = d.game.app.view
  local cx, cy = scene.camera:tileToWorld(siteX, siteY)
  scene.camera:centerOn(cx, cy, view)

  -- Placing: the ghost and the 7x7 patch it will reach.
  Inventory.addObject(world, "auto_harvester")
  scene.mode, scene.placing = "place", "auto_harvester"
  scene.hover = site
  d:frames(2)
  d:shot("placing")
  scene.mode, scene.placing, scene.hover = "act", nil, nil
  world.state.inventory.objects.auto_harvester = nil
  scene:layout()

  local harvester = place(world, "auto_harvester", site)
  local hx, hy = Grid.coords(grid, harvester)
  -- A grown field around it: most ripe, some still growing.
  local n = 0
  for y = hy - 3, hy + 3 do
    for x = hx - 3, hx + 3 do
      local i = Grid.index(grid, x, y)
      if
        Grid.inBounds(grid, x, y)
        and Grid.terrain(world, i).tillable
        and not world.occupancy[i]
        and math.abs(x - hx) + math.abs(y - hy) > 1
      then
        n = n + 1
        world.state.fields.tilled[i] = true
        world.state.fields.plan[i] = n % 3 == 0 and "potato" or "radish"
        world.state.crops[i] = { id = world.state.fields.plan[i], growth = n % 4 == 0 and 0.5 or 1, moisture = 1 }
      end
    end
  end

  -- Working: the arm reaches out, the ring fills, the card says so.
  scene.selected = harvester
  local frames = 0
  while Machines.done(world) < 3 and frames < 2000 do
    d:frames(10)
    frames = frames + 10
  end
  assert(Machines.done(world) >= 3, "the harvester never worked")
  while
    not (Machines.at(world, harvester).job and Machines.at(world, harvester).job.progress > 0.6) and frames < 3000
  do
    d:frames(1)
    frames = frames + 1
  end
  scene.toast = nil
  d:shot("working")

  -- Unpowered: the array and the folding panel go away (as if sold); the reach turns red and the
  -- card says why.
  for anchor, obj in pairs(grid.objects) do
    if world.registry:get("objects", obj.id).source then
      Grid.removeObject(world, anchor)
    end
  end
  for _ = 1, 40 do
    d:frames(5)
    if Machines.at(world, harvester).status == "unpowered" then
      break
    end
  end
  assert(
    Machines.at(world, harvester).status == "unpowered",
    "expected unpowered, got " .. Machines.at(world, harvester).status
  )
  d:frames(4)
  d:shot("unpowered")

  -- The Machines chapter of the Field Journal, once its notes are written.
  scene.toast = nil
  scene.toastQueue = {}
  for _ = 1, 40 do
    world.events:emit("crop.harvested", { amount = 1 })
  end
  world.events:emit("power.full", { battery = array })
  scene.toast = nil
  scene.toastQueue = {}
  d:pick("Journal")
  d:frames(2)
  local journal = d:scene()
  journal:select("auto_harvester") -- opens the node's chapter and its card
  d:frames(3)
  d:shot("journal")
end
