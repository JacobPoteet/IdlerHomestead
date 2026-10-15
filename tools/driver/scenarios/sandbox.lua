-- Sandbox save mode (D133): the game mode choice after naming a homestead, the SANDBOX tag in the slot list
-- (beside a normal slot) and on the homestead screen, the Catalog listing everything for free (no Debug
-- toggle), a free grant, and the homesteader surviving empty stores.
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")

return function(d)
  -- A normal homestead first, so the slot list shows both kinds side by side.
  d:newGame()
  d:key("escape") -- the homestead's menu path back to the slots is not needed: the save is written on exit
  d.game.app:switch(require("src.scenes.slots").new())
  d:frames(3)
  d:press("New")
  d:text("Sandbox farm")
  d:shot("name")
  d:press("Next")
  d:frames(2)
  d:shot("mode_choice")
  d:press("Sandbox")
  d:frames(10)
  local world = d:world()
  assert(world.meta.sandbox == true, "the slot is a sandbox")
  d:shot("homestead_tag")

  d:pick("Catalog")
  d:frames(3)
  d:shot("catalog")
  local scene = d:scene()
  assert(#scene.rows > 0)
  assert(not pcall(function()
    d:press("Debug")
  end), "a sandbox has no Debug toggle")
  local money = Ledger.get(world, "money")
  d:press("Get") -- the first listed item, free and at once
  d:frames(2)
  assert(Ledger.get(world, "money") == money and #world.state.market.orders == 0)
  d:shot("granted")
  d:key("escape")
  d:frames(3)

  -- Nothing to eat or burn: health falls to its floor and the run goes on.
  for _, res in ipairs(world.registry:all("resources")) do
    if res.calories or res.heat then
      Ledger.remove(world, res.id, Ledger.get(world, res.id), "test")
    end
  end
  for _ = 1, 8 do -- a few days; a find or notice popping up is dismissed
    for _ = 1, 3 do
      local top = d:scene()
      if top.name == "finds" then -- a find: take the first card
        d:click(top.cards[1].x + top.cards[1].w / 2, top.cards[1].y + top.cards[1].h / 2)
        d:frames(2)
        d:press("Take it")
      end
      d:tryPress("Got it")
      d:frames(2)
    end
    d:advance(12)
  end
  assert(
    d:scene().name == "homestead",
    "not playing: " .. tostring(d:scene().name) .. " " .. table.concat(d:labels(), ",")
  )
  assert(Needs.condition(world) >= world.tuning.sandbox.conditionFloor)
  d:shot("hungry_but_alive")

  -- Back to the slot list: the tag shows on the sandbox slot only.
  d.game.app:switch(require("src.scenes.slots").new())
  d:frames(3)
  d:shot("slot_list")
end
