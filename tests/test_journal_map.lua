-- Field Journal map: chapter content and the auto-layout (GDD §8.3, D41).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local JournalMap = require("src.ui.journal_map")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local content = { registry = reg } -- Journal's content queries only need the registry

local function overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Chapters --------------------------------------------------------------------------------

T.test("chapters: every journal node's page is listed by exactly one chapter", function()
  for _, def in ipairs(Journal.nodes(content)) do
    local count = 0
    for _, chapter in ipairs(reg:all("chapters")) do
      for _, page in ipairs(chapter.pages) do
        if page == def.page then
          count = count + 1
        end
      end
    end
    T.eq(count, 1, def.id .. " (page '" .. def.page .. "') is in " .. count .. " chapters")
    T.truthy(Journal.chapterOf(content, def.id), def.id .. " has a chapter")
  end
end)

T.test("chapters: no page is claimed by two chapters", function()
  local seen = {}
  for _, chapter in ipairs(reg:all("chapters")) do
    for _, page in ipairs(chapter.pages) do
      T.falsy(seen[page], "page '" .. page .. "' is listed by " .. chapter.id .. " and " .. tostring(seen[page]))
      seen[page] = chapter.id
    end
  end
end)

T.test("chapters: Journal.chapters holds every node once and hides empty chapters", function()
  local placed = {}
  for _, chapter in ipairs(Journal.chapters(content)) do
    T.truthy(#chapter.nodes > 0, chapter.id .. " is empty but shown")
    for _, def in ipairs(chapter.nodes) do
      T.falsy(placed[def.id], def.id .. " is in two chapters")
      placed[def.id] = chapter.id
      T.eq(Journal.chapterOf(content, def.id), chapter.id)
    end
  end
  for _, def in ipairs(Journal.nodes(content)) do
    T.truthy(placed[def.id], def.id .. " is on no chapter")
  end
end)

-- Layout ----------------------------------------------------------------------------------

T.test("layout: every node is placed once, inside its region, with no overlaps", function()
  local map = JournalMap.build(Journal.chapters(content), 200)
  local all = {}
  for _, region in ipairs(map.regions) do
    T.truthy(region.x >= 0 and region.y >= 0 and region.x + region.w <= map.w and region.y + region.h <= map.h, region.id .. " is inside the map")
    for _, node in ipairs(region.nodes) do
      T.truthy(node.x >= region.x and node.x + node.w <= region.x + region.w, node.id .. " fits its region horizontally")
      T.truthy(node.y >= region.y and node.y + node.h <= region.y + region.h, node.id .. " fits its region vertically")
      all[#all + 1] = node
    end
    for _, stamp in ipairs(region.stamps) do
      T.truthy(stamp.x >= region.x and stamp.x + stamp.w <= region.x + region.w, "stamp " .. stamp.note .. " fits its region horizontally")
      T.truthy(stamp.y >= region.y and stamp.y + stamp.h <= region.y + region.h, "stamp " .. stamp.note .. " fits its region vertically")
      all[#all + 1] = stamp
    end
  end
  for i = 1, #all do
    for j = i + 1, #all do
      T.falsy(overlaps(all[i], all[j]), (all[i].id or all[i].note) .. " overlaps " .. (all[j].id or all[j].note))
    end
  end
  for _, def in ipairs(Journal.nodes(content)) do
    T.truthy(map.nodes[def.id], def.id .. " has a place on the map")
  end
  for i = 1, #map.regions do
    for j = i + 1, #map.regions do
      T.falsy(overlaps(map.regions[i], map.regions[j]), map.regions[i].id .. " overlaps " .. map.regions[j].id)
    end
  end
end)

T.test("layout: a link joins every needed note to its node", function()
  local map = JournalMap.build(Journal.chapters(content), 200)
  for _, region in ipairs(map.regions) do
    local expected = 0
    for _, node in ipairs(region.nodes) do
      expected = expected + #(node.def.needs or {})
    end
    T.eq(#region.links, expected, region.id .. " link count")
    for _, link in ipairs(region.links) do
      T.truthy(link.stamp.x + link.stamp.w <= link.node.x, "links run from the stamp column to the node column")
    end
  end
end)

T.test("layout: columns stay within the height budget (a lone tall region excepted)", function()
  local chapters = Journal.chapters(content)
  local tall = JournalMap.build(chapters, 10000)
  T.eq(tall.w > 0, true)
  local narrow = JournalMap.build(chapters, 200)
  -- A smaller budget never makes the map taller, and spreads it wider.
  T.truthy(narrow.h <= tall.h)
  T.truthy(narrow.w >= tall.w)
  local seenX = {}
  for _, region in ipairs(narrow.regions) do
    seenX[region.x] = (seenX[region.x] or 0) + 1
  end
  for x, count in pairs(seenX) do
    if count > 1 then
      local bottom = 0
      for _, region in ipairs(narrow.regions) do
        if region.x == x then
          bottom = math.max(bottom, region.y + region.h)
        end
      end
      T.truthy(bottom <= 200, "stacked column at x=" .. x .. " is " .. bottom .. " tall")
    end
  end
end)

-- Ownership badge -------------------------------------------------------------------------

T.test("inventory: owns() covers equipment and objects", function()
  local world = World.new({ registry = reg, tuning = tun, meta = {} }, World.newState(1))
  T.falsy(Inventory.owns(world, "axe"))
  Inventory.addEquipment(world, "axe")
  T.truthy(Inventory.owns(world, "axe"))
  T.falsy(Inventory.owns(world, "smoker"))
  Inventory.addObject(world, "smoker")
  T.truthy(Inventory.owns(world, "smoker"))
  T.falsy(Inventory.owns(world, "radish_seeds"), "supplies are consumed, never owned")
end)
