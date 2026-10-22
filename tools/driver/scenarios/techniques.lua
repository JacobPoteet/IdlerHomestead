-- The Techniques page and the first-aid kit (H5 + B10, #388, #354, D199): the Techniques chapter of the Journal with one
-- technique known and one an idea, and the event card for a sprained ankle with the Splinting third option and the kit
-- option beside the two it always has. The event is offered through the Events debug path; the page and the card are the
-- real ones. Desktop and phone.
local Events = require("src.sim.systems.events")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")

return function(d)
  d:newGame()
  local world = d:world()
  d:frames(10)

  -- Splinting known; Bandaging an idea (its notes written); Haggling still ???.
  for _, note in ipairs({ "ankle_sprain", "splint_made", "festering_cut", "kit_bought" }) do
    Journal.write(world, note)
  end
  assert(Journal.learnNow(world, "splinting"))
  assert(Journal.status(world, "bandaging") == "idea")

  d:pick("Journal")
  d:frames(8)
  d:shot("overview")
  local scene = d:scene()
  local at
  for i, chapter in ipairs(scene.chapters) do
    if chapter.id == "techniques" then
      at = i
    end
  end
  assert(at, "a Techniques chapter")
  scene.nav.offset = 0
  scene:layoutButtons()
  local tile = scene.nav.grid.tileOf[at]
  d:click(scene.nav.body.x + tile.x + tile.w / 2, scene.nav.body.y + tile.y - scene.nav.offset + tile.h / 2)
  d:frames(4)
  d:shot("page")
  for _ = 1, 4 do -- the chapter, then the journal, close in as many Escapes as they need
    if d:scene().eventShown then
      break
    end
    d:key("escape")
    d:frames(2)
  end

  -- The card: the two base options, the Splinting third option and the kit.
  Ledger.add(world, "first_aid_kit", 1)
  Ledger.add(world, "wood", 6)
  assert(Events.force(world, "sprained_ankle"))
  d:frames(10)
  local s = d:scene()
  s.toast, s.toastQueue = nil, {}
  assert(s:eventShown(), "the event card is up")
  assert(#Events.pending(world).options == 4, "two base options, the splint and the kit")
  d:shot("card")
end
