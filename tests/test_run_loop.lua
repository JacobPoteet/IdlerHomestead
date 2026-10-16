-- The roguelite loop (GDD §4.3): fail -> rescue -> recovery -> new land, knowledge kept.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local serialize = require("src.core.serialize")
local Session = require("src.session")
local Run = require("src.meta.run")
local Journal = require("src.sim.systems.journal")
local Fishing = require("src.sim.systems.fishing")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Wardrobe = require("src.sim.systems.wardrobe")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local ctx = { registry = reg, tuning = tun }

local function newSession(data, seed)
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  return Session.new({ store = store, slot = 1, data = data, registry = reg, tuning = tun, seed = seed })
end

-- Starve the homesteader until Condition hits zero. Returns true once needs.depleted fires.
local function starve(world)
  local depleted = false
  world.events:on("needs.depleted", function()
    depleted = true
  end)
  for _, res in ipairs(reg:all("resources")) do
    if res.calories then
      Ledger.remove(world, res.id, Ledger.get(world, res.id))
    end
  end
  for _ = 1, 20 do
    Needs.daily(world)
    if depleted then
      return true
    end
  end
  return false
end

T.test("run loop: failing records the run, finishes the study, and drops the run state", function()
  local data = Save.newSlotData("Loop")
  local session = newSession(data, 11)
  local world = session.world
  Fishing.land(world, "creek_chub", 12, "active")
  world.events:emit("food.spoiled", { resource = "creek_chub", category = "fish", amount = 1 })
  T.truthy(Journal.study(world, "smoker"))
  T.truthy(starve(world), "condition reaches zero")
  local summary = Run.fail(data, world)
  T.eq(data.run, nil)
  T.truthy(Run.isRecovering(data))
  T.truthy(data.header.recovering)
  T.eq(summary.run, 1)
  T.eq(#data.meta.career.history, 1)
  T.eq(data.meta.recovery.finishedStudy, "smoker", "the study in progress finishes during recovery")
  local noted = {}
  for _, id in ipairs(summary.notes) do
    noted[id] = true
  end
  T.truthy(noted.first_catch and noted.fish_spoil, "notes written this run are in the summary")
  T.eq(Run.rescues(data.meta), 1)
end)

T.test("run loop: one free study, then new land with the same knowledge", function()
  local data = Save.newSlotData("Loop")
  local world = newSession(data, 11).world
  world.meta.journal.notes.bucket_hauling = { day = 1, run = 1 }
  world.meta.journal.notes.felled_tree = { day = 1, run = 1 }
  T.truthy(starve(world))
  Run.fail(data, world)
  local metaWorld = Run.metaWorld(ctx, data.meta)
  T.truthy(Run.freeStudy(data, metaWorld, "big_bucket"))
  T.eq(select(2, Run.freeStudy(data, metaWorld, "axe")), "used", "only one free study")
  T.eq(Journal.status(metaWorld, "axe"), "idea")
  -- Save, reload, head out.
  local reloaded = serialize.decode(serialize.encode(data))
  Run.startNext(reloaded)
  T.falsy(Run.isRecovering(reloaded))
  T.eq(Run.number(reloaded.meta), 2)
  local next = newSession(reloaded, 22)
  local world2 = next.world
  T.truthy(reloaded.run, "a fresh run was generated")
  T.eq(world2.state.calendar.day, 1)
  T.eq(Journal.status(world2, "big_bucket"), "known", "knowledge carried over")
  T.truthy(Journal.hasNote(world2, "felled_tree"))
  T.falsy(world2.state.land.truck == world.state.land.truck and world2.state.seed == world.state.seed, "new land")
  -- No salvage: money and stock reset to the starting kit.
  T.eq(Ledger.get(world2, "money"), world2.tuning.run.startingResources.money)
  Fishing.land(world2, "sunfish", 12, "active")
  T.eq(reloaded.meta.journal.notes.first_catch.run, 2, "notes remember which run wrote them")
end)

-- Clothes between runs (D155): the Wardrobe opens over the recovery scene on the slot's meta.

T.test("run loop: Wear in recovery applies now, survives a save, and the next run wears it", function()
  local data = Save.newSlotData("Loop")
  local world = newSession(data, 11).world
  Wardrobe.grant(world, "straw_hat")
  Wardrobe.grant(world, "wool_sweater")
  T.truthy(starve(world))
  Run.fail(data, world)
  local metaWorld = Run.metaWorld(ctx, data.meta)
  T.truthy(Wardrobe.appliesNow(metaWorld), "between runs a Wear is today's outfit at once")
  local dressed
  metaWorld.events:on("wardrobe.dressed", function(e)
    dressed = e.dressed
  end)
  local ok, reason, autoWasOn = Wardrobe.wear(metaWorld, { head = "straw_hat", torso = "wool_sweater" })
  T.truthy(ok, reason)
  T.falsy(autoWasOn)
  T.eq(dressed and dressed.head, "straw_hat", "the dressed event fired")
  T.eq(Wardrobe.dressed(metaWorld).torso, "wool_sweater", "with no run, today's outfit is the chosen one")
  -- The scene saves with store:write exactly as Learn does; a reload keeps the outfit.
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  store:write(1, data)
  local reloaded = store:read(1)
  T.eq(Wardrobe.committed(Run.metaWorld(ctx, reloaded.meta)).head, "straw_hat")
  -- Head out: the new run's snapshot wears it from its first moment.
  Run.startNext(reloaded)
  local nextWorld = newSession(reloaded, 22).world
  T.eq(Wardrobe.dressed(nextWorld).head, "straw_hat")
  T.eq(Wardrobe.dressed(nextWorld).torso, "wool_sweater")
  T.eq(Wardrobe.owned(nextWorld, "straw_hat"), true, "and the clothes are still owned")
end)

T.test("run loop: the recovery scene lists the run's new clothes and lays out at every view", function()
  local Recovery = require("src.scenes.recovery")
  local Text = require("src.ui.text")
  -- The pixel font needs the image module, which a headless run does not load: a flat 9 px line stands in.
  local wrappedHeight, measure = Text.wrappedHeight, Text.measure
  Text.wrappedHeight = function()
    return 9
  end
  Text.measure = function(s)
    return #s * 6, 9
  end
  local data = Save.newSlotData("Loop")
  local world = newSession(data, 11).world
  Wardrobe.grant(world, "straw_hat")
  Wardrobe.grant(world, "scarf")
  T.truthy(starve(world))
  Run.fail(data, world)
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  local views = { { 640, 360 }, { 390, 844 }, { 844, 390 } }
  for _, v in ipairs(views) do
    local w, h = v[1], v[2]
    local scene = Recovery.new()
    local pushed
    scene.app = {
      ctx = { tuning = tun, registry = reg, store = store },
      view = { w = w, h = h, scale = 1 },
      stack = {},
      push = function(_, s)
        pushed = s
      end,
    }
    scene:enter(1, data)
    scene:resize({ w = w, h = h, scale = 1 })
    local where = "recovery " .. w .. "x" .. h
    local listed = {}
    for _, id in ipairs(scene.clothes) do
      listed[id] = true
    end
    T.truthy(listed.straw_hat and listed.scarf, where .. ": the garments earned this run are listed")
    T.truthy(listed.bandana, where .. ": and so is the one being rescued earned")
    T.truthy(scene.clothesH > 0, where .. ": the row takes room")
    local change, head
    for _, b in ipairs(scene.buttons.list) do
      if b.label == tun.ui.wardrobe.recoveryButton then
        change = b
      elseif b.label == "Head out" then
        head = b
      end
      if b == change or b == head then
        T.truthy(
          b.x >= scene.box.x and b.x + b.w <= scene.box.x + scene.box.w and b.y + b.h <= scene.box.y + scene.box.h,
          where .. ": " .. tostring(b.label) .. " inside the panel"
        )
      end
    end
    T.truthy(change and head, where .. ": both buttons exist")
    local overlap = change.x < head.x + head.w
      and head.x < change.x + change.w
      and change.y < head.y + head.h
      and head.y < change.y + change.h
    T.falsy(overlap, where .. ": Change clothes and Head out do not overlap")
    if w < tun.ui.wardrobe.recoveryStackWidth then
      T.truthy(change.y + change.h <= head.y, where .. ": stacked above Head out")
    else
      T.eq(change.y, head.y, where .. ": beside Head out")
    end
    change.onPress()
    T.eq(pushed and pushed.variant, "recovery", where .. ": Change clothes opens the recovery Wardrobe")
    T.eq(pushed.world, scene.metaWorld)
  end
  Text.wrappedHeight, Text.measure = wrappedHeight, measure
end)

T.test("run loop: the rescuer remembers you", function()
  local data = Save.newSlotData("Loop")
  for _ = 1, 2 do
    local world = newSession(data, 3).world
    T.truthy(starve(world))
    Run.fail(data, world)
    Run.startNext(data)
  end
  T.eq(Run.rescues(data.meta), 2)
  T.eq(Run.number(data.meta), 3)
end)

-- What failed (D99, #216, #173) -------------------------------------------------------------

T.test("run cause: cold, hunger or both, from the last day's shortfalls", function()
  T.eq(Run.cause(tun, { hunger = 1, cold = 0, shelter = "truck" }).kind, "hunger")
  T.eq(Run.cause(tun, { hunger = 0, cold = 0.5, shelter = "camp" }).kind, "cold")
  T.eq(Run.cause(tun, { hunger = 0, cold = 0.5, shelter = "camp" }).shelter, "camp")
  T.eq(Run.cause(tun, { hunger = 0.5, cold = 0.5 }).kind, "both", "neither dominates")
  T.eq(Run.cause(tun, { hunger = 1, cold = 0.1 }).kind, "hunger", "one far larger than the other")
  T.eq(Run.cause(tun, nil).kind, "unknown")
end)

T.test("run cause: the text names the failure, the shelter and the next rung", function()
  local cold = Run.failureText(reg, tun, { kind = "cold", shelter = "truck" })
  T.truthy(cold.line:find("truck", 1, true))
  T.truthy(cold.line:find("cold", 1, true))
  T.truthy(cold.hint:find("Shelter page", 1, true))
  T.truthy(cold.hint:find("camp", 1, true), "the camp is the next rung above the truck")
  T.eq(cold.icon, "icon_cold")
  local camp = Run.failureText(reg, tun, { kind = "cold", shelter = "camp" })
  T.truthy(camp.hint:find("shack", 1, true))
  local top = Run.failureText(reg, tun, { kind = "cold", shelter = "shack" })
  T.truthy(top.hint:find("wood", 1, true), "nothing above the shack")
  local hungry = Run.failureText(reg, tun, { kind = "hunger", shelter = "truck" })
  T.truthy(hungry.line:find("food", 1, true))
  T.falsy(hungry.page)
  T.truthy(Run.failureText(reg, tun, { kind = "unknown" }).line)
end)

T.test("run cause: a starved run records hunger and the shelter", function()
  local data = Save.newSlotData("Cause")
  local world = newSession(data, 11).world
  local got
  world.events:on("needs.depleted", function(e)
    got = e
  end)
  T.truthy(starve(world))
  T.truthy(got and got.hunger > 0 and got.shelter, "the payload carries the shortfall and the shelter")
  local summary = Run.fail(data, world, got)
  T.truthy(summary.cause.kind == "hunger" or summary.cause.kind == "both", "starved (a cold night may share it)")
  T.eq(summary.cause.shelter, got.shelter)
  T.eq(data.meta.career.history[1].cause.kind, summary.cause.kind)
  local other = Save.newSlotData("None")
  T.eq(Run.fail(other, newSession(other, 3).world).cause.kind, "unknown", "tools may omit it")
end)

T.test("run cause: the first suggestion depends on the cause", function()
  T.truthy(Run.firstChange(reg, tun, { kind = "cold", shelter = "truck" }):find("camp", 1, true))
  T.truthy(Run.firstChange(reg, tun, { kind = "hunger" }):find("field", 1, true))
  T.truthy(Run.firstChange(reg, tun, { kind = "unknown" }))
end)
