-- The Field Journal navigation (D81, #194): the chapter overview grouped under areas, a focused chapter
-- fitted to the view, a node card, the filter, and a grown journal (108 chapters, via the scene's
-- test-only `chapterSource` hook) that scrolls. Mid-game state: two thirds of the notes written, some
-- ideas learned, one queued, the rest still ???.
local Journal = require("src.sim.systems.journal")
local JournalScene = require("src.scenes.journal")

local function midGame(world)
  for i, note in ipairs(world.registry:all("notes")) do
    if i % 3 ~= 0 then
      world.meta.journal.notes[note.id] = { day = 1 + i % 20, season = "spring", year = 1, run = 1 }
    end
  end
  local learned, queued = 0, false
  for _, def in ipairs(Journal.nodes(world)) do
    if Journal.status(world, def.id) == "idea" then
      learned = learned + 1
      if learned % 2 == 0 then
        Journal.learnNow(world, def.id)
      elseif not queued then
        Journal.study(world, def.id)
        queued = true
      end
    end
  end
end

--- A journal grown to `copies` times the real chapters: same nodes (so their status is real), new
--- names, and one area per copy.
local function grown(copies)
  return function(world)
    local real = Journal.chapters(world)
    local out = {}
    for copy = 1, copies do
      for _, chapter in ipairs(real) do
        out[#out + 1] = {
          id = chapter.id .. copy,
          name = copy == 1 and chapter.name or (chapter.name .. " " .. copy),
          area = copy == 1 and chapter.area or ("Region " .. copy),
          nodes = chapter.nodes,
        }
      end
    end
    return out
  end
end

return function(d)
  --- Tap a navigation chip by its label (chips are hit rectangles, not Buttons, so d:press cannot see them).
  local function chip(label)
    for _, c in ipairs(d:scene().nav.chips) do
      if c.label == label then
        d:click(c.x + c.w / 2, c.y + c.h / 2)
        return
      end
    end
    error("no chip " .. label)
  end

  d:newGame()
  midGame(d:world())
  d:frames(3)

  d:press("Journal")
  d:frames(8)
  d:shot("overview")

  -- Tap the Animals tile (the node we focus on lives there), then a node, then the filter.
  local scene = d:scene()
  local function tapTile(name)
    for i, chapter in ipairs(scene.chapters) do
      if chapter.name == name then
        scene.nav.offset = 0
        scene:layoutButtons()
        local tile = scene.nav.grid.tileOf[i]
        d:click(scene.nav.body.x + tile.x + tile.w / 2, scene.nav.body.y + tile.y - scene.nav.offset + tile.h / 2)
        return
      end
    end
    error("no chapter " .. name)
  end
  tapTile("Water & Soil")
  d:frames(3)
  d:shot("chapter")
  local fit = scene.nav.fit
  local nodes = (fit.map.regions[2] or fit.map.regions[1]).nodes
  local node = nodes[1]
  d:click(fit.ox + (node.x + node.w / 2) * fit.scale, fit.oy + (node.y + node.h / 2) * fit.scale)
  d:frames(3)
  d:shot("card")
  chip("Ideas")
  d:frames(2)
  d:shot("filter_chapter")
  chip("< Chapters")
  d:frames(2)
  d:shot("filter_overview")
  chip("All")
  chip("Queue")
  d:frames(2)
  d:shot("queue_jump")
  d:key("escape") -- card away
  d:key("escape") -- back to the overview
  d:key("escape") -- close
  d:frames(2)

  -- A grown journal: 108 chapters under 12 areas, scrolled by wheel and by drag.
  JournalScene.chapterSource = grown(12)
  local ok, err = pcall(function()
    d:press("Journal")
    d:frames(8)
    d:shot("grown_top")
    local s = d:scene()
    local b = s.nav.body
    d:wheel(-12, b.x + b.w / 2, b.y + b.h / 2)
    d:frames(2)
    d:shot("grown_scrolled")
    d:drag(b.x + b.w / 2, b.y + b.h - 10, b.x + b.w / 2, b.y + 10)
    d:frames(2)
    d:shot("grown_dragged")
    chip("Ideas")
    d:frames(2)
    d:shot("grown_filter")
    chip("All")
    d:key("escape")
  end)
  JournalScene.chapterSource = nil
  if not ok then
    error(err, 0)
  end
end
