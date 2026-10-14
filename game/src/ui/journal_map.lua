-- Auto-layout for the Field Journal knowledge map (GDD §8.3, D41). Pure geometry: no drawing, so it
-- can be tested headless. Positions come from the data, never from hand placement.
--
-- Each chapter becomes a region: a column of note stamps on the left, a column of nodes on the
-- right, and a link from every stamp to the nodes that need it. Regions are packed into columns
-- in chapter order (next-fit), each column no taller than the space the map has on screen.
--
-- JournalMap.build(chapters, maxHeight) -> map
--   map = { w, h, regions = { region, ... }, nodes = { [nodeId] = node }, stamps = { [noteId] = { stamp, ... } } }
--   region = { id, name, x, y, w, h, nodes = { node }, stamps = { stamp }, links = { { stamp, node } } }
--   node = { id, def, x, y, w, h }   stamp = { note, x, y, w, h }   (all in map coordinates)

local JournalMap = {}

-- Layout metrics, in virtual pixels.
JournalMap.NODE_W = 100 -- node card width
JournalMap.NODE_H = 28 -- node card height (a 2x icon plus margin)
JournalMap.STAMP = 22 -- note stamp edge
JournalMap.PAD = 6 -- inside a region's border
JournalMap.HEADER = 14 -- region title strip
JournalMap.LINK_W = 22 -- gap between the stamp column and the node column (where the lines run)
JournalMap.NODE_GAP = 4 -- vertical gap between nodes
JournalMap.STAMP_GAP = 4 -- vertical gap between stamps
JournalMap.REGION_GAP = 8 -- gap between regions, vertically and between columns

local M = JournalMap

-- Region interiors ------------------------------------------------------------------------

local function average(values)
  local sum = 0
  for _, v in ipairs(values) do
    sum = sum + v
  end
  return sum / #values
end

-- Sort `list` (array of items) by key(item), ties keeping their current order.
local function stableSort(list, key)
  local decorated = {}
  for i, v in ipairs(list) do
    decorated[i] = { v = v, k = key(v, i), i = i }
  end
  table.sort(decorated, function(a, b)
    if a.k ~= b.k then
      return a.k < b.k
    end
    return a.i < b.i
  end)
  for i, d in ipairs(decorated) do
    list[i] = d.v
  end
end

-- Order nodes and stamps to keep the lines from crossing much: a few rounds of putting each side
-- at the average position of what it connects to. Nodes with no notes (starters) sink to the end.
local function order(defs, notes, needsOf)
  local notePos, nodePos = {}, {}
  local function reindex()
    for i, id in ipairs(notes) do
      notePos[id] = i
    end
    for i, def in ipairs(defs) do
      nodePos[def.id] = i
    end
  end
  reindex()
  local users = {}
  for _, def in ipairs(defs) do
    for _, id in ipairs(needsOf(def)) do
      users[id] = users[id] or {}
      users[id][#users[id] + 1] = def.id
    end
  end
  for _ = 1, 3 do
    stableSort(defs, function(def)
      local needs = needsOf(def)
      if #needs == 0 then
        return math.huge
      end
      local at = {}
      for _, id in ipairs(needs) do
        at[#at + 1] = notePos[id]
      end
      return average(at)
    end)
    reindex()
    stableSort(notes, function(id)
      local at = {}
      for _, user in ipairs(users[id]) do
        at[#at + 1] = nodePos[user]
      end
      return average(at)
    end)
    reindex()
  end
end

local function buildRegion(chapter)
  local needsOf = function(def)
    return def.needs or {}
  end
  local defs = {}
  for i, def in ipairs(chapter.nodes) do
    defs[i] = def
  end
  local notes, seen = {}, {}
  for _, def in ipairs(defs) do
    for _, id in ipairs(needsOf(def)) do
      if not seen[id] then
        seen[id] = true
        notes[#notes + 1] = id
      end
    end
  end
  order(defs, notes, needsOf)

  local top = M.HEADER + M.PAD
  local nodeX = M.PAD + (#notes > 0 and (M.STAMP + M.LINK_W) or 0)
  local region = { id = chapter.id, name = chapter.name, nodes = {}, stamps = {}, links = {} }
  local byId = {}
  for i, def in ipairs(defs) do
    local node =
      { id = def.id, def = def, x = nodeX, y = top + (i - 1) * (M.NODE_H + M.NODE_GAP), w = M.NODE_W, h = M.NODE_H }
    region.nodes[i] = node
    byId[def.id] = node
  end

  -- Stamps sit level with the nodes that use them, pushed down just far enough not to overlap.
  local floor = top
  local stampByNote = {}
  for _, id in ipairs(notes) do
    local centers = {}
    for _, def in ipairs(defs) do
      for _, need in ipairs(needsOf(def)) do
        if need == id then
          centers[#centers + 1] = byId[def.id].y + M.NODE_H / 2
        end
      end
    end
    local y = math.max(floor, math.floor(average(centers) - M.STAMP / 2))
    local stamp = { note = id, x = M.PAD, y = y, w = M.STAMP, h = M.STAMP }
    region.stamps[#region.stamps + 1] = stamp
    stampByNote[id] = stamp
    floor = y + M.STAMP + M.STAMP_GAP
  end
  for _, node in ipairs(region.nodes) do
    for _, id in ipairs(needsOf(node.def)) do
      region.links[#region.links + 1] = { stamp = stampByNote[id], node = node }
    end
  end

  local bottom = top
  for _, node in ipairs(region.nodes) do
    bottom = math.max(bottom, node.y + node.h)
  end
  for _, stamp in ipairs(region.stamps) do
    bottom = math.max(bottom, stamp.y + stamp.h)
  end
  region.w = nodeX + M.NODE_W + M.PAD
  region.h = bottom + M.PAD
  return region
end

-- Packing -----------------------------------------------------------------------------------

local function shift(region, dx, dy)
  region.x, region.y = dx, dy
  for _, node in ipairs(region.nodes) do
    node.x, node.y = node.x + dx, node.y + dy
  end
  for _, stamp in ipairs(region.stamps) do
    stamp.x, stamp.y = stamp.x + dx, stamp.y + dy
  end
end

--- chapters: Journal.chapters(world). maxHeight: the tallest a column of regions may grow (a lone
--- region taller than that gets a column to itself).
function JournalMap.build(chapters, maxHeight)
  local regions = {}
  for _, chapter in ipairs(chapters) do
    regions[#regions + 1] = buildRegion(chapter)
  end

  local columns = {}
  for _, region in ipairs(regions) do
    local column = columns[#columns]
    if not column or (column.h + M.REGION_GAP + region.h > maxHeight and #column.regions > 0) then
      column = { regions = {}, w = 0, h = 0 }
      columns[#columns + 1] = column
    end
    if #column.regions > 0 then
      column.h = column.h + M.REGION_GAP
    end
    column.regions[#column.regions + 1] = region
    column.h = column.h + region.h
    column.w = math.max(column.w, region.w)
  end

  local map = { w = 0, h = 0, regions = regions, nodes = {}, stamps = {} }
  local x = 0
  for _, column in ipairs(columns) do
    local y = 0
    for _, region in ipairs(column.regions) do
      region.w = column.w
      shift(region, x, y)
      y = y + region.h + M.REGION_GAP
    end
    x = x + column.w + M.REGION_GAP
    map.h = math.max(map.h, column.h)
  end
  map.w = math.max(0, x - M.REGION_GAP)

  for _, region in ipairs(regions) do
    for _, node in ipairs(region.nodes) do
      map.nodes[node.id] = node
      node.region = region
    end
    for _, stamp in ipairs(region.stamps) do
      map.stamps[stamp.note] = map.stamps[stamp.note] or {}
      table.insert(map.stamps[stamp.note], stamp)
    end
  end
  return map
end

return JournalMap
