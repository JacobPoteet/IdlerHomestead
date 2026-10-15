-- Land generation variety (#land): the whole plot at half zoom (creek, tributary, ponds, marshes, woods in
-- three species, meadows, clearings, boulder fields), then close-ups of a pond and of a stand of trees.
-- The seed picks the plot: `lovec tools/driver landgen seed=7`.
local Grid = require("src.sim.grid")

--- The centre tile of the water body (8-way connected water/ford) nearest the middle of the map that has
--- at most `maxTiles` tiles, i.e. a pond rather than the creek.
local function pondCentre(grid, maxTiles)
  local seen, best, bestDist = {}, nil, nil
  for start = 1, #grid.terrain do
    local t = grid.terrain[start]
    if (t == "water" or t == "ford") and not seen[start] then
      local body, stack = {}, { start }
      seen[start] = true
      while #stack > 0 do
        local i = table.remove(stack)
        body[#body + 1] = i
        local x, y = Grid.coords(grid, i)
        for dy = -1, 1 do
          for dx = -1, 1 do
            if Grid.inBounds(grid, x + dx, y + dy) then
              local n = Grid.index(grid, x + dx, y + dy)
              local nt = grid.terrain[n]
              if (nt == "water" or nt == "ford") and not seen[n] then
                seen[n] = true
                stack[#stack + 1] = n
              end
            end
          end
        end
      end
      if #body <= maxTiles then
        local sx, sy = 0, 0
        for _, i in ipairs(body) do
          local x, y = Grid.coords(grid, i)
          sx, sy = sx + x, sy + y
        end
        local cx, cy = sx / #body, sy / #body
        local dist = (cx - grid.w / 2) ^ 2 + (cy - grid.h / 2) ^ 2
        if not bestDist or dist < bestDist then
          best, bestDist = { cx, cy }, dist
        end
      end
    end
  end
  return best
end

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  local scene, view = d:scene(), d.game.app.view
  local tile = world.tuning.display.tileSize
  local cam = scene.camera
  d:advance(1)

  local counts = {}
  for _, obj in pairs(grid.objects) do
    counts[obj.id] = (counts[obj.id] or 0) + 1
  end
  print(
    string.format(
      "plot: %d tree, %d pine, %d birch, %d rock, %d brush, %d log",
      counts.tree or 0,
      counts.pine or 0,
      counts.birch or 0,
      counts.rock or 0,
      counts.brush or 0,
      counts.log or 0
    )
  )

  -- An ASCII map for the log: ~ water, = ford, # road, T oak, P pine, b birch, o rock, " brush, l log, X other.
  local glyph = { tree = "T", pine = "P", birch = "b", rock = "o", brush = '"', log = "l" }
  for y = 1, grid.h do
    local row = {}
    for x = 1, grid.w do
      local i = Grid.index(grid, x, y)
      local obj = grid.objects[i]
      local t = grid.terrain[i]
      if obj then
        row[#row + 1] = glyph[obj.id] or "X"
      elseif t == "water" then
        row[#row + 1] = "~"
      elseif t == "ford" then
        row[#row + 1] = "="
      elseif t == "road" then
        row[#row + 1] = "#"
      else
        row[#row + 1] = "."
      end
    end
    print(table.concat(row))
  end

  -- The whole plot: half zoom is not a shipped zoom level, so add it for this survey.
  cam.zoomLevels = { 0.5, 1, 2, 3 }
  cam.zoomIndex = 1
  cam:centerOn(grid.w * tile / 2, grid.h * tile / 2, view)
  d:frames(4, 0.05)
  d:shot("whole_plot")

  local pond = pondCentre(grid, 150)
  if pond then
    cam.zoomIndex = 3
    cam:centerOn((pond[1] - 0.5) * tile, (pond[2] - 0.5) * tile, view)
    cam:clamp(view)
    d:frames(4, 0.05)
    d:shot("pond")
  end

  -- A dense stand: the tree with the most trees around it.
  local best, bestN = nil, 0
  for anchor, obj in pairs(grid.objects) do
    if (obj.kind or obj.id) == "tree" or obj.id == "pine" or obj.id == "birch" then
      local x, y = Grid.coords(grid, anchor)
      local n = 0
      for dy = -3, 3 do
        for dx = -3, 3 do
          if Grid.inBounds(grid, x + dx, y + dy) then
            local o = grid.objects[Grid.index(grid, x + dx, y + dy)]
            if o and (o.id == "tree" or o.id == "pine" or o.id == "birch") then
              n = n + 1
            end
          end
        end
      end
      if n > bestN then
        best, bestN = anchor, n
      end
    end
  end
  if best then
    local x, y = Grid.coords(grid, best)
    cam.zoomIndex = 3
    cam:centerOn((x - 0.5) * tile, (y - 0.5) * tile, view)
    cam:clamp(view)
    d:frames(4, 0.05)
    d:shot("woods")
  end
end
