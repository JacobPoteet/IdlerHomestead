-- Journal search by name, the remembered chapter and a very large chapter (D120, #208). Mid-game state
-- like the `journal` scenario: some notes written, ideas learned, the rest still ???.
local Journal = require("src.sim.systems.journal")
local JournalScene = require("src.scenes.journal")

local function midGame(world)
  for i, note in ipairs(world.registry:all("notes")) do
    if i % 3 ~= 0 then
      world.meta.journal.notes[note.id] = { day = 1 + i % 20, season = "spring", year = 1, run = 1 }
    end
  end
  local learned = 0
  for _, def in ipairs(Journal.nodes(world)) do
    if Journal.status(world, def.id) == "idea" then
      learned = learned + 1
      if learned % 2 == 0 then
        Journal.learnNow(world, def.id)
      end
    end
  end
end

--- One chapter holding every node of the journal, in journal order: far more than fits a view.
local function oneBigChapter(world)
  local nodes = {}
  for _, def in ipairs(Journal.nodes(world)) do
    nodes[#nodes + 1] = def
  end
  return { { id = "everything", name = "Everything", area = "Test", nodes = nodes } }
end

return function(d)
  JournalScene.lastChapter = nil
  d:newGame()
  midGame(d:world())
  d:frames(3)

  local function openSearch()
    for _, c in ipairs(d:scene().nav.chips) do
      if c.kind == "search" then
        d:click(c.x + c.w / 2, c.y + c.h / 2)
        return
      end
    end
    error("no search chip")
  end

  d:pick("Journal")
  d:frames(8)
  d:shot("overview")

  -- Search: tap the field, type, see only names the player knows.
  openSearch()
  d:frames(2)
  d:shot("field_focused")
  d:text("a")
  d:shot("results_a")
  d:text("x")
  d:shot("results_ax")
  -- A query that only a still-unknown node's name could match must look like any other empty search.
  local scene = d:scene()
  local hidden
  for _, def in ipairs(Journal.nodes(d:world())) do
    if Journal.status(d:world(), def.id) == "unknown" then
      hidden = def.name
      break
    end
  end
  d:key("backspace")
  d:key("backspace")
  d:text(hidden:sub(1, 10))
  d:shot("results_hidden_name_none")
  d:key("escape")
  d:frames(2)
  d:shot("cleared")

  -- Tap a result: jump to its chapter with the card open.
  openSearch()
  d:text("axe")
  local row = scene.nav.body
  d:click(row.x + row.w / 2, row.y + scene.nav.list.rowH / 2)
  d:frames(3)
  d:shot("jumped")

  -- Leave and reopen: back in that chapter.
  d:key("escape") -- card away
  d:key("escape") -- back to the overview
  d:key("escape") -- close
  d:frames(2)
  d:pick("Journal")
  d:frames(8)
  d:shot("reopened")
  d:key("escape") -- back to the overview
  d:key("escape") -- close
  d:frames(2)

  -- A very large chapter scrolls at a readable size instead of shrinking.
  JournalScene.chapterSource = oneBigChapter
  JournalScene.lastChapter = nil
  local ok, err = pcall(function()
    d:pick("Journal")
    d:frames(8)
    local s = d:scene()
    local tile = s.nav.grid.tileOf[1]
    d:click(s.nav.body.x + tile.x + tile.w / 2, s.nav.body.y + tile.y + tile.h / 2)
    d:frames(3)
    d:shot("big_top")
    local b = s.nav.body
    d:wheel(-8, b.x + b.w / 2, b.y + b.h / 2)
    d:frames(2)
    d:shot("big_scrolled")
    -- Search for a node deep in the chapter: the chapter scrolls to it.
    openSearch()
    local deep -- the last node whose name is known: far down the big chapter
    for _, def in ipairs(Journal.nodes(d:world())) do
      if Journal.status(d:world(), def.id) ~= "unknown" then
        deep = def.name
      end
    end
    d:text(deep)
    local r = s.nav.body
    d:click(r.x + r.w / 2, r.y + s.nav.list.rowH / 2)
    d:frames(3)
    d:shot("big_jump")
    d:key("escape")
    d:key("escape")
    d:key("escape")
  end)
  JournalScene.chapterSource = nil
  JournalScene.lastChapter = nil
  if not ok then
    error(err, 0)
  end
end
