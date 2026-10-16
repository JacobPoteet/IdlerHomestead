-- The homesteader's wardrobe (D149 to D153, src/sim/systems/wardrobe.lua): the accessor maths, the dawn
-- snapshot, the unlock rules, the saved shape and the Sandbox.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local serialize = require("src.core.serialize")
local Session = require("src.session")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Character = require("src.render.character")
local Inventory = require("src.sim.systems.inventory")
local Needs = require("src.sim.systems.needs")
local Readiness = require("src.sim.systems.readiness")
local Run = require("src.meta.run")
local Shelter = require("src.sim.systems.shelter")
local Wardrobe = require("src.sim.systems.wardrobe")
local Weather = require("src.sim.systems.weather")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local SLOTS = tun.wardrobe.slots

local function newWorld(meta, seed)
  return World.new({ registry = reg, tuning = tun, meta = meta or {} }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function dayIn(season)
  for n, s in ipairs(tun.time.seasons) do
    if s == season then
      return (n - 1) * tun.time.daysPerSeason + 2
    end
  end
end

-- Tick across the next midnight (the new day, "dawn" of the wardrobe).
local function acrossMidnight(world)
  local now = require("src.sim.systems.calendar").now(world)
  setTime(world, now.day, 23.99)
  for _ = 1, 20 do
    world:tick(STEP)
  end
end

local function ownAll(world)
  for _, def in ipairs(reg:all("garments")) do
    Wardrobe.grant(world, def.id)
  end
end

--- The first garment of each slot in a weight class, content order.
local function classOutfit(class)
  local outfit = {}
  for _, def in ipairs(reg:all("garments")) do
    if def.class == class and not outfit[def.slot] then
      outfit[def.slot] = def.id
    end
  end
  return outfit
end

local function emit(world, name, payload, times)
  for _ = 1, times or 1 do
    world.events:emit(name, payload or {})
  end
end

-- Content and tuning --------------------------------------------------------------------------------

T.test("wardrobe content: five slots, one starter and default each, all three classes in every slot", function()
  local starters, defaults, classes = {}, {}, {}
  for _, def in ipairs(reg:all("garments")) do
    if def.starter then
      starters[def.slot] = (starters[def.slot] or 0) + 1
      T.eq(def.class, "mid", def.id .. " starter is the baseline")
      T.falsy(def.unlock, def.id .. " a starter has no unlock")
    else
      T.truthy(def.unlock and def.hint, def.id .. " is earned and says how")
    end
    if def.default then
      defaults[def.slot] = (defaults[def.slot] or 0) + 1
      T.truthy(def.starter, def.id .. " default is a starter")
    end
    classes[def.slot] = classes[def.slot] or {}
    classes[def.slot][def.class] = true
  end
  T.eq(#SLOTS, 5)
  for _, slot in ipairs(SLOTS) do
    T.eq(starters[slot], 1, slot .. " has one starter")
    T.eq(defaults[slot], 1, slot .. " has one default")
    T.truthy(classes[slot].light and classes[slot].mid and classes[slot].heavy, slot .. " offers every class")
  end
  T.same(Character.slots, SLOTS, "the painter and the tuning agree on the slots")
end)

T.test("wardrobe content: hints are short actions, a %d only where the unlock has a threshold", function()
  local kinds = {
    season = true,
    winters = true,
    snowDays = true,
    snaps = true,
    frosts = true,
    harvests = true,
    crops = true,
    fish = true,
    built = true,
    builtField = true,
    machines = true,
    cleared = true,
    trips = true,
    rescues = true,
    runs = true,
    established = true,
  }
  local probe = newWorld()
  for _, def in ipairs(reg:all("garments")) do
    if def.unlock then
      T.truthy(kinds[def.unlock.kind], def.id .. " has a kind the system evaluates: " .. tostring(def.unlock.kind))
      local words = 0
      for _ in def.hint:gmatch("%S+") do
        words = words + 1
      end
      T.truthy(words <= 5, def.id .. " hint is at most five words")
      T.falsy(def.hint:find("%.$"), def.id .. " hint has no full stop")
      local n = Wardrobe.threshold(probe, def.id)
      T.eq(
        def.hint:find("%%d") ~= nil,
        n ~= nil and n > 1,
        def.id .. " hint has %d exactly when the threshold is above one"
      )
    end
  end
  for id in pairs(tun.wardrobe.unlocks) do
    T.truthy(reg:has("garments", id), id .. " is a garment")
  end
end)

T.test("wardrobe tuning: the meters' scale is the largest an outfit reaches", function()
  local c = tun.wardrobe
  local weights = 0
  for _, slot in ipairs(c.slots) do
    weights = weights + c.slotWeight[slot]
  end
  T.eq(weights, 8)
  T.near(c.scale.work, weights * c.classes.light.work, 1e-9)
  T.near(c.scale.cold, math.max(weights * c.classes.light.cold, -weights * c.classes.heavy.cold), 1e-9)
end)

-- Accessor maths ----------------------------------------------------------------------------------------

T.test("wardrobe: the starter outfit is exactly 1.0 and +0, so nothing else changes", function()
  local world = newWorld()
  local outfit = Wardrobe.dressed(world)
  for _, slot in ipairs(SLOTS) do
    T.truthy(reg:get("garments", outfit[slot]).starter, slot .. " starts in the starter")
  end
  T.eq(Wardrobe.insulation(world), 1)
  T.eq(Wardrobe.workBonus(world), 1)
  local e = Wardrobe.effects(world)
  T.eq(e.work, 0)
  T.eq(e.cold, 0)
  T.eq(Shelter.nightInsulation(world), Shelter.insulation(world))
end)

T.test("wardrobe: a full light outfit is about +4% work and +6% heat needed, a full heavy one -8%", function()
  local world = newWorld()
  ownAll(world)
  T.truthy(Wardrobe.wear(world, classOutfit("light")))
  local light = Wardrobe.effects(world, classOutfit("light"))
  T.near(light.work, 0.04, 1e-9)
  T.near(light.cold, 0.06, 1e-9)
  T.near(Wardrobe.workBonus(world), 1.04, 1e-9)
  T.near(Wardrobe.insulation(world), 1.06, 1e-9)
  T.truthy(Wardrobe.wear(world, classOutfit("heavy")))
  T.near(Wardrobe.effects(world).cold, -0.08, 1e-9)
  T.near(Wardrobe.insulation(world), 0.92, 1e-9)
  T.eq(Wardrobe.workBonus(world), 1, "heavy gives no work bonus")
  T.truthy(Wardrobe.wear(world, classOutfit("mid")))
  T.eq(Wardrobe.insulation(world), 1)
  T.eq(Wardrobe.workBonus(world), 1)
  local scale = Wardrobe.scale(world)
  T.near(scale.work, 0.04, 1e-9)
  T.near(scale.cold, 0.08, 1e-9)
end)

T.test("wardrobe: each slot counts by its weight points", function()
  local world = newWorld()
  ownAll(world)
  for slot, weight in pairs(tun.wardrobe.slotWeight) do
    local e = Wardrobe.effects(world, { [slot] = classOutfit("light")[slot] })
    T.near(e.work, weight * tun.wardrobe.classes.light.work, 1e-9, slot)
    T.near(e.cold, weight * tun.wardrobe.classes.light.cold, 1e-9, slot)
  end
end)

T.test("wardrobe: clothes alone never cut the heat needed below the floor", function()
  local heavy = tun.wardrobe.classes.heavy -- the tuning tables are shared by every test: put the number back
  local was = heavy.cold
  heavy.cold = -0.05 -- a full heavy outfit would be 0.60
  local world = newWorld()
  ownAll(world)
  T.truthy(Wardrobe.wear(world, classOutfit("heavy")))
  local cold, insulation = Wardrobe.effects(world).cold, Wardrobe.insulation(world)
  heavy.cold = was
  T.near(cold, -0.4, 1e-9, "the effect itself is not clamped")
  T.eq(insulation, tun.wardrobe.insulationFloor)
end)

T.test("wardrobe: the clothes join the shelter's insulation in the night's need and the forecast", function()
  local function winterNeed(class)
    local world = newWorld()
    ownAll(world)
    setTime(world, 1, 7)
    T.truthy(Wardrobe.wear(world, classOutfit(class))) -- the opening window: today's outfit at once
    setTime(world, dayIn("winter"), 12)
    local raw = Weather.warmthNeed(world)
    T.truthy(raw > 0, "a winter day needs warmth")
    return Needs.warmthNeeded(world), raw * Shelter.insulation(world), Readiness.warmthAhead(world), world
  end
  local mid, midBase, midAhead = winterNeed("mid")
  T.eq(mid, midBase, "mid changes nothing")
  local light, _, lightAhead = winterNeed("light")
  local heavy, _, heavyAhead = winterNeed("heavy")
  T.near(light / mid, 1.06, 1e-9)
  T.near(heavy / mid, 0.92, 1e-9)
  T.near(lightAhead / midAhead, 1.06, 1e-9, "the readiness forecast follows")
  T.near(heavyAhead / midAhead, 0.92, 1e-9)
end)

T.test("wardrobe: the work bonus multiplies the homesteader's work rate", function()
  local function remaining(class)
    local world = newWorld()
    ownAll(world)
    T.truthy(Wardrobe.wear(world, classOutfit(class)))
    local hs = Actors.homesteader(world)
    hs.job = { task = "till", target = world.state.land.spawn, path = {}, progress = 0, ordered = true }
    local p = Actors.progress(world, hs)
    hs.job = nil
    return p.remaining
  end
  local mid = remaining("mid")
  T.near(remaining("light"), mid / 1.04, 1e-9)
  T.eq(remaining("heavy"), mid, "heavy is no faster")
end)

-- The dawn rule ---------------------------------------------------------------------------------------------

T.test("wardrobe: a mid-day change waits for dawn; the opening window and the time between runs do not", function()
  local world = newWorld()
  ownAll(world)
  local seen = {}
  world.events:on("wardrobe.dressed", function(e)
    seen[#seen + 1] = e.reason
  end)
  setTime(world, 1, 7)
  T.truthy(Wardrobe.appliesNow(world), "the first morning")
  T.truthy(Wardrobe.wear(world, { head = "straw_hat" }))
  T.eq(Wardrobe.dressed(world).head, "straw_hat", "applied at once in the opening window")
  T.same(seen, { "wear" })
  setTime(world, 1, 21)
  T.falsy(Wardrobe.appliesNow(world), "after the first evening")
  setTime(world, 2, 12)
  T.falsy(Wardrobe.appliesNow(world), "a later day")
  local key = Wardrobe.dressedKey(world)
  T.truthy(Wardrobe.wear(world, { torso = "wool_sweater", head = "wool_toque" }))
  T.eq(Wardrobe.committed(world).torso, "wool_sweater", "chosen now")
  T.eq(Wardrobe.dressed(world).torso, "flannel_shirt", "worn today still")
  T.eq(Wardrobe.dressed(world).head, "straw_hat")
  T.eq(Wardrobe.dressedKey(world), key)
  T.eq(Wardrobe.insulation(world), Wardrobe.insulation(world))
  local before = Wardrobe.insulation(world)
  acrossMidnight(world)
  T.eq(Wardrobe.dressed(world).torso, "wool_sweater", "dawn dresses the chosen outfit")
  T.eq(Wardrobe.dressed(world).head, "wool_toque")
  T.truthy(Wardrobe.dressedKey(world) ~= key)
  T.truthy(Wardrobe.insulation(world) < before)
  T.same(seen, { "wear", "dawn" })
end)

T.test("wardrobe: the night's warmth settles with the outfit worn through the day", function()
  local world = newWorld()
  ownAll(world)
  setTime(world, dayIn("winter"), 12)
  local night
  world.events:on("needs.warmed", function(e)
    night = e.needed
  end)
  local need = Needs.warmthNeeded(world)
  T.truthy(Wardrobe.wear(world, classOutfit("heavy")))
  acrossMidnight(world)
  T.truthy(night, "the night was settled")
  T.truthy(math.abs(night - need) < need * 0.2, "about tonight's need before the change")
  T.eq(Wardrobe.dressed(world).torso, classOutfit("heavy").torso)
end)

T.test("wardrobe: between runs a Wear is chosen at once and the next run starts in it", function()
  local data = Save.newSlotData("Dress")
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  local function session()
    return Session.new({ store = store, slot = 1, data = data, registry = reg, tuning = tun, seed = 5 })
  end
  local world = session().world
  Wardrobe.grant(world, "scarf")
  Run.fail(data, world)
  local metaWorld = Run.metaWorld({ registry = reg, tuning = tun }, data.meta)
  T.truthy(Wardrobe.appliesNow(metaWorld), "no run, nothing to protect")
  T.truthy(Wardrobe.owned(metaWorld, "scarf"))
  T.truthy(Wardrobe.wear(metaWorld, { extra = "scarf" }))
  T.eq(Wardrobe.dressed(metaWorld).extra, "scarf", "with no run, today's outfit is the chosen one")
  Run.startNext(data)
  data.run = nil
  local next = session().world
  T.eq(Wardrobe.dressed(next).extra, "scarf", "the new run's snapshot wears it")
  T.eq(Wardrobe.committed(next).extra, "scarf")
end)

-- Writers ----------------------------------------------------------------------------------------------------

T.test("wardrobe: Wear checks every id and changes nothing on a refusal", function()
  local world = newWorld()
  Wardrobe.grant(world, "straw_hat")
  local before = Wardrobe.committed(world)
  local ok, reason = Wardrobe.wear(world, { head = "nope" })
  T.eq(ok, false)
  T.eq(reason, "unknown")
  reason = select(2, Wardrobe.wear(world, { head = "flannel_shirt" }))
  T.eq(reason, "slot")
  reason = select(2, Wardrobe.wear(world, { head = "wool_toque" }))
  T.eq(reason, "locked")
  reason = select(2, Wardrobe.wear(world, { cape = "x" }))
  T.eq(reason, "slot")
  reason = select(2, Wardrobe.wear(world, { torso = "tank_top", head = "wool_toque" }))
  T.eq(reason, "locked", "one bad id refuses the lot")
  T.same(Wardrobe.committed(world), before)
  T.truthy(Wardrobe.wear(world, { head = "straw_hat" }))
  T.eq(Wardrobe.committed(world).head, "straw_hat")
  T.eq(Wardrobe.committed(world).torso, before.torso, "the other slots keep what they were")
end)

T.test("wardrobe: new markers, the stamp and the recovery list", function()
  local world = newWorld()
  T.eq(Wardrobe.newCount(world), 0)
  T.falsy(Wardrobe.stampDue(world))
  T.truthy(Wardrobe.grant(world, "straw_hat"))
  T.falsy(Wardrobe.grant(world, "straw_hat"), "already owned")
  T.truthy(Wardrobe.grant(world, "wool_sweater"))
  T.truthy(Wardrobe.isNew(world, "straw_hat"))
  T.eq(Wardrobe.newCount(world), 2)
  T.eq(Wardrobe.newCount(world, "head"), 1)
  T.eq(Wardrobe.newCount(world, "legs"), 0)
  T.truthy(Wardrobe.stampDue(world))
  Wardrobe.stampSeen(world)
  T.falsy(Wardrobe.stampDue(world))
  T.truthy(Wardrobe.isNew(world, "straw_hat"), "the dots stay until each tile is seen")
  Wardrobe.markSeen(world, "straw_hat")
  T.falsy(Wardrobe.isNew(world, "straw_hat"))
  T.eq(Wardrobe.newCount(world), 1)
  T.same(Wardrobe.earnedThisRun(world), { "straw_hat", "wool_sweater" })
  T.same(Wardrobe.earnedThisRun(world, 2), {})
end)

T.test("wardrobe: unlocking emits an event with the run number", function()
  local world = newWorld({ career = { runs = 3, history = {} } })
  local got
  world.events:on("wardrobe.unlocked", function(e)
    got = e
  end)
  Wardrobe.grant(world, "scarf")
  T.same(got, { id = "scarf", run = 3 })
  T.same(Wardrobe.earnedThisRun(world), { "scarf" })
end)

T.test("wardrobe: presets keep an owned outfit under a known name; a manual Wear turns Auto off", function()
  local world = newWorld()
  ownAll(world)
  T.eq(Wardrobe.preset(world, "cold"), nil)
  local cold = classOutfit("heavy")
  T.truthy(Wardrobe.savePreset(world, "cold", cold))
  T.same(Wardrobe.preset(world, "cold"), cold)
  T.eq(select(2, Wardrobe.savePreset(world, "storm", cold)), "name")
  T.eq(select(2, Wardrobe.savePreset(world, "warm", { head = "straw_hat" })), "unknown", "a whole outfit")
  local fresh = newWorld()
  T.eq(select(2, Wardrobe.savePreset(fresh, "warm", Wardrobe.committed(fresh))), nil)
  local locked = Wardrobe.committed(fresh)
  locked.head = "wool_toque"
  T.eq(select(2, Wardrobe.savePreset(fresh, "cold", locked)), "locked")
  T.falsy(Wardrobe.autoOn(world))
  Wardrobe.setAuto(world, true)
  T.truthy(Wardrobe.autoOn(world))
  local ok, _, autoWasOn = Wardrobe.wear(world, { head = "straw_hat" })
  T.truthy(ok)
  T.truthy(autoWasOn)
  T.falsy(Wardrobe.autoOn(world), "choosing an outfit by hand turns Auto off")
end)

-- The saved shape ------------------------------------------------------------------------------------------

T.test("wardrobe: a new slot's meta has the whole saved shape", function()
  local data = Save.newSlotData("Shape")
  newWorld(data.meta)
  local w = data.meta.wardrobe
  for _, key in ipairs({ "owned", "fresh", "earned", "worn", "presets", "counts" }) do
    T.eq(type(w[key]), "table", key)
  end
  T.eq(w.stamp, false)
  T.eq(w.auto, false)
  for _, slot in ipairs(SLOTS) do
    T.truthy(w.worn[slot], slot .. " is dressed")
  end
  local owned = 0
  for _ in pairs(w.owned) do
    owned = owned + 1
  end
  T.eq(owned, #SLOTS, "only the starters")
end)

T.test("wardrobe: the wardrobe survives a save and load, run and slot both", function()
  local data = Save.newSlotData("Round trip")
  local world = newWorld(data.meta, 7)
  ownAll(world)
  Wardrobe.markSeen(world, "scarf")
  Wardrobe.savePreset(world, "warm", classOutfit("light"))
  Wardrobe.savePreset(world, "cold", classOutfit("heavy"))
  Wardrobe.setAuto(world, true)
  setTime(world, 1, 7)
  T.truthy(Wardrobe.wear(world, classOutfit("heavy")))
  emit(world, "market.trip", {}, 2)
  data.run = world.state
  local loaded = serialize.decode(serialize.encode(Save.forDisk(data)))
  local again = World.new({ registry = reg, tuning = tun, meta = loaded.meta }, loaded.run)
  T.same(Wardrobe.committed(again), Wardrobe.committed(world))
  T.same(Wardrobe.dressed(again), Wardrobe.dressed(world))
  T.eq(Wardrobe.insulation(again), Wardrobe.insulation(world))
  T.truthy(Wardrobe.owned(again, "down_parka"))
  T.falsy(Wardrobe.isNew(again, "scarf"))
  T.truthy(Wardrobe.isNew(again, "straw_hat"))
  T.same(Wardrobe.preset(again, "warm"), classOutfit("light"))
  T.same(Wardrobe.preset(again, "cold"), classOutfit("heavy"))
  T.falsy(Wardrobe.autoOn(again), "the manual Wear turned Auto off, and that is what was saved")
  T.eq(select(1, Wardrobe.progress(again, "denim_jacket")), 2, "the counters are saved")
end)

T.test("wardrobe: unknown, misplaced and unowned ids in a save become the starter", function()
  local meta = {
    wardrobe = {
      owned = { ghost = true, scarf = true },
      fresh = { ghost = true },
      worn = { head = "ghost", torso = "wool_toque", legs = "wool_trousers", feet = "work_boots", extra = "scarf" },
    },
  }
  local world = newWorld(meta)
  local worn = Wardrobe.committed(world)
  T.eq(worn.head, "bare_head")
  T.eq(worn.torso, "flannel_shirt")
  T.eq(worn.legs, "work_pants", "not owned")
  T.eq(worn.feet, "work_boots")
  T.eq(worn.extra, "scarf", "owned and in its slot: kept")
  T.falsy(meta.wardrobe.owned.ghost)
  T.falsy(meta.wardrobe.fresh.ghost)
  T.truthy(meta.wardrobe.owned.work_pants, "the starters are always owned")
  world.state.wardrobe.dressed.head = "ghost"
  Wardrobe.init(world)
  T.eq(Wardrobe.dressed(world).head, "bare_head", "a run saved with a removed garment still loads")
  T.eq(Wardrobe.effects(world, { head = "ghost" }).work, 0, "the maths treats it as the starter too")
end)

-- Presets and the dawn auto-dress -----------------------------------------------------------------------

local function presetWorld()
  local world = newWorld()
  ownAll(world)
  Wardrobe.savePreset(world, "warm", classOutfit("light"))
  Wardrobe.savePreset(world, "cold", classOutfit("heavy"))
  Wardrobe.setAuto(world, true)
  return world
end

T.test("wardrobe auto: a cold night dresses the Cold preset at dawn and says so", function()
  local world = presetWorld()
  setTime(world, dayIn("winter") - 1, 12)
  local seen = {}
  world.events:on("wardrobe.dressed", function(e)
    seen[#seen + 1] = { reason = e.reason, night = e.night }
  end)
  T.eq(Wardrobe.autoNight(world), "cold")
  acrossMidnight(world)
  T.same(Wardrobe.dressed(world), classOutfit("heavy"), "today is the Cold preset")
  T.same(Wardrobe.committed(world), classOutfit("heavy"), "and it is the chosen outfit")
  T.same(seen, { { reason = "auto", night = "cold" } })
  T.truthy(Wardrobe.autoOn(world), "Auto stays on")
  T.truthy(Wardrobe.insulation(world) < 1)
end)

T.test("wardrobe auto: a warm night dresses the Warm preset", function()
  local world = presetWorld()
  Wardrobe.wear(world, classOutfit("heavy"))
  Wardrobe.setAuto(world, true) -- a manual Wear turns it off; this test wants it on
  setTime(world, dayIn("summer"), 12)
  T.eq(Wardrobe.autoNight(world), "warm")
  acrossMidnight(world)
  T.same(Wardrobe.dressed(world), classOutfit("light"))
  T.truthy(Wardrobe.workBonus(world) > 1)
end)

T.test("wardrobe auto: the threshold is the weather system's own figure", function()
  local world = presetWorld()
  local c = tun.wardrobe.autoColdNeed
  for _, season in ipairs(tun.time.seasons) do
    setTime(world, dayIn(season), 12)
    local need = Weather.warmthNeed(world)
    T.eq(Wardrobe.autoNight(world), need >= c and "cold" or "warm", season)
  end
end)

T.test("wardrobe auto: an empty preset changes nothing, and nothing is ever written to a preset", function()
  local world = newWorld()
  ownAll(world)
  Wardrobe.savePreset(world, "warm", classOutfit("light"))
  Wardrobe.setAuto(world, true)
  local before = Wardrobe.committed(world)
  setTime(world, dayIn("winter") - 1, 12)
  acrossMidnight(world)
  T.same(Wardrobe.committed(world), before, "no Cold preset: today's clothes stay")
  T.eq(Wardrobe.preset(world, "cold"), nil, "and the empty preset is still empty")
  Wardrobe.savePreset(world, "cold", classOutfit("heavy"))
  local warm, cold = Wardrobe.preset(world, "warm"), Wardrobe.preset(world, "cold")
  acrossMidnight(world)
  acrossMidnight(world)
  T.same(Wardrobe.preset(world, "warm"), warm, "a preset is never edited by Auto")
  T.same(Wardrobe.preset(world, "cold"), cold)
end)

T.test("wardrobe auto: off by default, and a manual Wear turns it off and says so", function()
  local world = newWorld()
  ownAll(world)
  T.falsy(Wardrobe.autoOn(world), "off in a new slot")
  Wardrobe.savePreset(world, "warm", classOutfit("light"))
  Wardrobe.savePreset(world, "cold", classOutfit("heavy"))
  setTime(world, dayIn("winter") - 1, 12)
  local before = Wardrobe.committed(world)
  acrossMidnight(world)
  T.same(Wardrobe.dressed(world), before, "Auto off: dawn does not dress a preset")
  Wardrobe.setAuto(world, true)
  local ok, _, wasOn = Wardrobe.wear(world, { head = "straw_hat" })
  T.truthy(ok)
  T.truthy(wasOn, "the Wear reports that Auto was on")
  T.falsy(Wardrobe.autoOn(world))
  local _, _, again = Wardrobe.wear(world, { head = "bare_head" })
  T.falsy(again, "and does not report it twice")
end)

T.test("wardrobe auto: a preset naming a garment the slot does not own is not worn", function()
  local world = newWorld()
  Wardrobe.grant(world, "wool_toque")
  Wardrobe.savePreset(
    world,
    "cold",
    { head = "wool_toque", torso = "flannel_shirt", legs = "work_pants", feet = "work_boots", extra = "no_extra" }
  )
  Wardrobe.setAuto(world, true)
  world.meta.wardrobe.owned.wool_toque = nil -- lost since it was saved (cannot happen in play; a hand-edited save)
  local before = Wardrobe.committed(world)
  setTime(world, dayIn("winter") - 1, 12)
  acrossMidnight(world)
  T.same(Wardrobe.committed(world), before, "the preset is refused whole")
  T.same(Wardrobe.preset(world, "cold").head, "wool_toque", "and left as it was saved")
end)

-- Sandbox --------------------------------------------------------------------------------------------------

T.test("wardrobe: a sandbox slot owns everything and unlocks nothing", function()
  local data = Save.newSlotData("Sandbox", { sandbox = true })
  local world = newWorld(data.meta)
  for _, def in ipairs(reg:all("garments")) do
    T.truthy(Wardrobe.owned(world, def.id), def.id)
  end
  T.falsy(Wardrobe.grant(world, "scarf"))
  T.same(Wardrobe.evaluate(world), {})
  T.eq(Wardrobe.newCount(world), 0)
  T.falsy(Wardrobe.stampDue(world))
  setTime(world, 1, 7)
  T.truthy(Wardrobe.wear(world, classOutfit("heavy")))
  T.eq(Wardrobe.dressed(world).extra, classOutfit("heavy").extra)
end)

-- Unlock rules ----------------------------------------------------------------------------------------------

local function owns(world, id)
  return Wardrobe.owned(world, id)
end

T.test("wardrobe unlock: seasons lived through (summers, winters, snowy days, frosts, cold snaps)", function()
  local world = newWorld()
  T.falsy(owns(world, "linen_shirt"))
  emit(world, "calendar.newSeason", { season = "autumn", year = 1 }) -- summer ended
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "linen_shirt"), "a summer")
  T.falsy(owns(world, "tank_top"))
  emit(world, "calendar.newSeason", { season = "autumn", year = 2 }, 2)
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "tank_top"), "three summers")
  T.falsy(owns(world, "wool_toque"), "a summer is not a winter")

  emit(world, "calendar.newSeason", { season = "spring", year = 2 }) -- winter ended
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "wool_toque"))
  T.falsy(owns(world, "wool_sweater"))
  emit(world, "calendar.newSeason", { season = "spring", year = 3 })
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "wool_sweater"))
  T.falsy(owns(world, "wool_trousers"))
  emit(world, "calendar.newSeason", { season = "spring", year = 4 })
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "wool_trousers"))
  T.falsy(owns(world, "down_parka"))
  emit(world, "calendar.newSeason", { season = "spring", year = 5 })
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "down_parka"), "four winters, over any number of runs")

  T.falsy(owns(world, "trapper_hat"))
  emit(world, "weather.coldSnap", { active = true })
  Wardrobe.evaluate(world)
  T.falsy(owns(world, "trapper_hat"), "a snap begun is not a snap survived")
  emit(world, "weather.coldSnap", { active = false })
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "trapper_hat"))

  T.falsy(owns(world, "scarf"))
  emit(world, "weather.froze", {})
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "scarf"))
end)

T.test("wardrobe unlock: days in the frozen season, counted at each dawn", function()
  local world = newWorld()
  world.debugInvincible = true
  setTime(world, dayIn("spring"), 12)
  emit(world, "calendar.newDay", { day = 2 }, 20)
  T.eq(select(1, Wardrobe.progress(world, "snow_boots")), 0, "spring days are not snowy")
  setTime(world, dayIn("winter"), 12)
  emit(world, "calendar.newDay", { day = 2 }, 9)
  T.falsy(owns(world, "snow_boots"))
  emit(world, "calendar.newDay", { day = 2 })
  T.truthy(owns(world, "snow_boots"), "ten snowy days, checked at the dawn that counted the tenth")
end)

T.test("wardrobe unlock: crops and harvests", function()
  local world = newWorld()
  emit(world, "crop.harvested", { crop = "radish", amount = 1 }, 14)
  Wardrobe.evaluate(world)
  T.falsy(owns(world, "straw_hat"), "one kind so far")
  T.falsy(owns(world, "shorts"))
  emit(world, "crop.harvested", { crop = "potato", amount = 1 })
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "shorts"), "fifteen harvests")
  T.truthy(owns(world, "straw_hat"), "two kinds")
end)

T.test("wardrobe unlock: fish species in the guide", function()
  local meta = { fishGuide = {} }
  local world = newWorld(meta)
  local fish = reg:all("fish")
  for i = 1, 4 do
    meta.fishGuide[fish[i].id] = { count = 1, best = 1, firstDay = 1 }
  end
  Wardrobe.evaluate(world)
  T.falsy(owns(world, "canvas_shoes"))
  meta.fishGuide[fish[5].id] = { count = 1, best = 1, firstDay = 1 }
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "canvas_shoes"))
end)

T.test("wardrobe unlock: things built, and machines standing at once", function()
  local world = newWorld()
  emit(world, "object.placed", { object = "camp", tile = 1 })
  Wardrobe.evaluate(world)
  T.falsy(owns(world, "overalls"))
  T.falsy(owns(world, "flat_cap"), "a camp is not a power source")
  emit(world, "object.placed", { object = "shack", tile = 1 })
  emit(world, "object.placed", { object = "solar_array", tile = 2 })
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "overalls"))
  T.truthy(owns(world, "flat_cap"))

  local function place(id)
    Inventory.addObject(world, id)
    local truck = world.state.land.truck
    local grid = world.state.grid
    local Grid = require("src.sim.grid")
    for i = 1, #grid.terrain do
      if Grid.distance(grid, truck, i) >= 3 and Inventory.canPlace(world, id, i) then
        T.truthy(Inventory.place(world, id, i))
        return
      end
    end
    error("no room for " .. id)
  end
  place("auto_harvester")
  place("auto_harvester")
  Wardrobe.evaluate(world)
  T.falsy(owns(world, "work_gloves"))
  place("auto_harvester")
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "work_gloves"), "three at once")
end)

T.test("wardrobe unlock: trees felled and trips to town", function()
  local world = newWorld()
  emit(world, "object.cleared", { object = "tree", species = "pine" }, 29)
  emit(world, "object.cleared", { object = "brush" }, 5)
  Wardrobe.evaluate(world)
  T.falsy(owns(world, "mittens"), "brush is not a tree")
  emit(world, "object.cleared", { object = "tree", species = "birch" })
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "mittens"))
  emit(world, "market.trip", {}, 4)
  Wardrobe.evaluate(world)
  T.falsy(owns(world, "denim_jacket"))
  emit(world, "market.trip", {})
  Wardrobe.evaluate(world)
  T.truthy(owns(world, "denim_jacket"))
end)

T.test("wardrobe unlock: rescues, runs and the Great Winter, evaluated at the end of a run", function()
  local data = Save.newSlotData("Memories")
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  local function session(seed)
    return Session.new({ store = store, slot = 1, data = data, registry = reg, tuning = tun, seed = seed })
  end
  local world = session(3).world
  T.falsy(Wardrobe.owned(world, "bandana"))
  local got = {}
  world.events:on("wardrobe.unlocked", function(e)
    got[#got + 1] = e.id
  end)
  Run.fail(data, world)
  T.same(got, { "bandana" }, "the first rescue")
  T.same(Wardrobe.earnedThisRun(world, 1), { "bandana" })
  T.truthy(Wardrobe.stampDue(world))
  Run.startNext(data)
  local second = session(4).world
  T.falsy(Wardrobe.owned(second, "oilskin_coat"))
  Run.fail(data, second)
  Run.startNext(data)
  local third = session(5).world
  Run.fail(data, third)
  Run.startNext(data)
  local fourth = session(6).world
  T.truthy(Wardrobe.owned(fourth, "oilskin_coat"), "rescued three times")
  T.same(Wardrobe.earnedThisRun(fourth, 3), { "oilskin_coat" })
  T.falsy(Wardrobe.owned(fourth, "felt_boots"))
  Run.fail(data, fourth)
  Run.startNext(data)
  local fifth = session(7).world -- run 5 begins
  T.eq(data.meta.career.runs, 5)
  T.truthy(Wardrobe.owned(fifth, "felt_boots"), "start run 5")
  T.same(Wardrobe.earnedThisRun(fifth, 5), { "felt_boots" })
  T.falsy(Wardrobe.owned(fifth, "insulated_bibs"))
  data.meta.established = { run = 5, year = 3, seen = false }
  Wardrobe.evaluate(fifth)
  T.truthy(Wardrobe.owned(fifth, "insulated_bibs"), "the Great Winter lived through")
end)

T.test("wardrobe unlock: a garment is earned once and a dawn only counts what has been done", function()
  local world = newWorld()
  world.debugInvincible = true
  emit(world, "weather.froze", {})
  setTime(world, 2, 12)
  acrossMidnight(world)
  T.truthy(owns(world, "scarf"), "evaluated at dawn")
  Wardrobe.markSeen(world, "scarf")
  local runs = 0
  world.events:on("wardrobe.unlocked", function()
    runs = runs + 1
  end)
  acrossMidnight(world)
  T.eq(runs, 0, "never earned twice")
  T.falsy(Wardrobe.isNew(world, "scarf"))
end)
