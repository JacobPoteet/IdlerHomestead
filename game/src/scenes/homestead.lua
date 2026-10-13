-- The homestead: runs the session, draws the world, and turns taps into orders.
--
-- Controls (GDD §5.2, §10): tap a tile and the homesteader walks there and does the obvious
-- thing (clear, till, plant, water, harvest, fill bucket, load the smoker, walk). What's "in hand"
-- decides the rest: a seed tills/plants, the rod fishes. "Plan field" marks a rectangle (two taps)
-- for the routine to farm; "Place" puts down equipment from the inventory. Tapping the truck opens
-- the truck panel. After tuning.idle.takeoverDelay seconds without input (less with habits perks),
-- the routine takes over; "Start routine" does it at once (D43). The speed button cycles the sim
-- speed (paused/1x/2x/4x, D42); panels and the camera keep working while paused.

local Camera = require("src.core.camera")
local Session = require("src.session")
local Grid = require("src.sim.grid")
local Calendar = require("src.sim.systems.calendar")
local Sleep = require("src.sim.systems.sleep")
local Shelter = require("src.sim.systems.shelter")
local Ledger = require("src.sim.systems.ledger")
local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Needs = require("src.sim.systems.needs")
local Food = require("src.sim.systems.food")
local Ftue = require("src.sim.systems.ftue")
local Spoilage = require("src.sim.systems.spoilage")
local Inventory = require("src.sim.systems.inventory")
local Placement = require("src.sim.systems.placement")
local PlaceCard = require("src.ui.place_card")
local Highlight = require("src.ui.highlight")
local PlaceText = require("src.ui.place_text")
local Journal = require("src.sim.systems.journal")
local Weather = require("src.sim.systems.weather")
local Nightly = require("src.sim.systems.nightly")
local AlertText = require("src.ui.alert_text")
local Forecast = require("src.ui.forecast")
local NightText = require("src.ui.night_text")
local SpoilText = require("src.ui.spoil_text")
local Run = require("src.meta.run")
local Stats = require("src.sim.stats")
local Power = require("src.sim.systems.power")
local Land = require("src.sim.systems.land")
local Water = require("src.sim.systems.water")
local Processing = require("src.sim.systems.processing")
local Market = require("src.sim.systems.market")
local Stand = require("src.sim.systems.stand")
local Cat = require("src.sim.systems.cat")
local Animals = require("src.sim.systems.animals")
local Finds = require("src.sim.systems.finds")
local Machines = require("src.sim.systems.machines")
local Renderer = require("src.render.world_renderer")
local ActionRing = require("src.render.action_ring")
local Assets = require("src.render.assets")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local ChipText = require("src.ui.chip_text")
local Toolbar = require("src.ui.toolbar")
local ScrollList = require("src.ui.scroll_list")
local MessageLog = require("src.ui.message_log")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Homestead = { name = "homestead", opaque = true }
Homestead.__index = Homestead

local TOAST_TIME = 2.6

function Homestead.new()
  return setmetatable({}, Homestead)
end

function Homestead:enter(slot, data)
  local ctx = self.app.ctx
  local tuning = ctx.tuning
  self.session = Session.new({ store = ctx.store, slot = slot, data = data, registry = ctx.registry, tuning = tuning })
  ctx.session = self.session
  self.session:save() -- a new slot exists on disk as soon as it's started
  self.world = self.session.world

  local grid = self.world.state.grid
  local tile = tuning.display.tileSize
  self.camera = Camera.new({
    tileSize = tile,
    zoomLevels = tuning.camera.zoomLevels,
    zoomIndex = tuning.camera.defaultZoomIndex,
  })
  self.camera:setBounds(grid.w * tile, grid.h * tile)
  local hs = Actors.homesteader(self.world)
  self.camera.x, self.camera.y = (hs.x - 0.5) * tile, (hs.y - 0.5) * tile
  self.renderer = Renderer.new(self.world)
  self.buttons = Buttons.new(tuning.input.minTouchTarget)
  self.paletteButtons = Buttons.new(tuning.input.minTouchTarget)
  self.paletteLists = { tools = ScrollList.new(), more = ScrollList.new() }
  self.mode = "act" -- "act" | "plan" | "place"
  self.seed = nil -- crop id in hand
  self.tool = nil -- "rod" in hand
  self.placing = nil -- object id being placed
  self.toast = nil
  self.toastQueue = {}
  local logCfg = self.app.ctx.tuning.ui.log
  self.log = MessageLog.new(logCfg.maxLines, logCfg.coalesceSeconds) -- what the toasts said (D90, #167); UI state, not saved
  self.held = {} -- toasts that came in while asleep, shown in the morning (D70)
  self.frostTold = {} -- crop id -> calendar day its won't-ripen warning last showed (D70, #165)
  self:subscribe()
end

-- World events the player should hear about.
function Homestead:subscribe()
  local events, world = self.world.events, self.world
  local function name(kind, id)
    return world.registry:get(kind, id).name
  end
  self.unsubscribe = {
    events:on("fishing.ready", function()
      -- The fishing mini-game plays in real time: don't let the world race past it.
      self.session:setSpeed(self.app.ctx.tuning.time.defaultSpeed)
      self.app:push(require("src.scenes.fishing").new(world, function(fish, size, first)
        self:showToast(string.format("%s%s, %d cm", first and "New! " or "", fish.name, size))
      end))
    end),
    events:on("fish.caught", function(e)
      if e.mode == "idle" then
        self:showToast("Caught a " .. name("fish", e.fish) .. (e.first and " (new!)" or ""))
      end
    end),
    events:on("market.delivered", function(e)
      self:showToast("Delivered: " .. name("catalog", e.item))
      self:layout()
    end),
    events:on("processing.done", function(e)
      self:showToast(string.format("%d %s ready", e.count, name("resources", e.output)))
    end),
    events:on("cat.arrived", function()
      self:showToast("A cat has settled in")
    end),
    events:on("cat.petted", function(e)
      self:showToast(e.bond >= world.tuning.cat.cat.maxBond and "Purrrr. Best of friends" or "Purr")
    end),
    events:on("mice.caught", function()
      if not self.session:sleeping() then -- asleep: it is in the morning report
        self:queueToast("The cat caught a mouse in the night")
      end
    end),
    events:on("mice.raided", function(e)
      if self.session:sleeping() then
        return -- asleep: it is in the morning report
      end
      local parts = {}
      for _, res in ipairs(world.registry:all("resources")) do
        if e.lost[res.id] then
          parts[#parts + 1] = string.format("%d %s", e.lost[res.id], res.name:lower())
        end
      end
      self:queueToast("Mice got into the stores: lost " .. table.concat(parts, ", "))
    end),
    events:on("animals.collected", function(e)
      self:showToast(string.format("Collected %d egg%s", e.count, e.count == 1 and "" or "s"))
    end),
    events:on("animals.milked", function(e)
      self:showToast(string.format("Collected %d milk", e.count))
    end),
    events:on("animals.short", function(e)
      local goats = e.kind == "goats"
      if e.feed then
        self:queueToast(goats and "The goats ran short of hay. Buy bales or tend the pen." or "The hens ran short of feed. Buy a sack or tend the coop.")
      elseif e.water then
        self:queueToast(goats and "The goats' trough ran dry. Tend the pen." or "The hens' waterer ran dry. Tend the coop.")
      end
    end),
    events:on("animals.lost", function(e)
      local name = e.kind == "goats" and "goat" or "hen"
      self:queueToast(e.reason == "thirst" and ("A " .. name .. " was lost: no water") or ("A " .. name .. " was lost: no " .. (e.kind == "goats" and "hay" or "feed")))
    end),
    events:on("animals.predator", function(e)
      if self.session:sleeping() then
        return -- asleep: it is in the morning report
      end
      local goats = e.kind == "goats"
      if e.stopped then
        self:queueToast(goats and "A coyote tried the pen in the night. The fence held." or "A fox tried the coop in the night. The door held.")
      elseif goats then
        self:queueToast(string.format("A coyote got into the pen: lost %d goat%s", e.killed, e.killed == 1 and "" or "s"))
      else
        self:queueToast(string.format("A fox got into the coop: lost %d hen%s", e.killed, e.killed == 1 and "" or "s"))
      end
    end),
    events:on("animals.nestFull", function()
      self:queueToast("The nest box is full: the hens have stopped laying until you collect")
    end),
    events:on("animals.pailFull", function()
      self:queueToast("The milk pail is full: the goats have dried up until you collect")
    end),
    events:on("routine.idleHint", function()
      -- Only while the player is looking at the world; panels would hide it (D55).
      if self.app:top() == self then
        self:showToast("Homesteader is idle: press R or tap Start routine")
      end
    end),
    -- The routine laid out the starter field (D61, D88): say so, and how to change it.
    events:on("crop.starterPlanned", function(e)
      self:heldToast(
        "starterPlanned",
        string.format("Routine planned a starter field (%d tiles). Plan field changes it", e.tiles)
      )
    end),
    events:on("stand.sold", function(e)
      self:showToast(string.format("Roadside stand sold %d items for $%d", e.units, e.earned))
    end),
    -- The truck reached a full trip's charge (D72, #162); the tip card (D69) says what to do on the first one.
    events:on("market.tripReady", function()
      self:heldToast("tripReady", "The truck is charged: tap it to drive to town")
    end),
    -- Building over clutter and crops (D79, #197): an order that cannot go on says why.
    events:on("placement.held", function(e)
      local p = self.app.ctx.tuning.ui.placement
      local what = name("objects", e.object):lower()
      if e.kind == "full" then
        self:queueToast(string.format("%s: %s", what, string.format(p.orderFull, name("resources", e.resource):lower())))
      elseif e.kind == "blocked" then
        self:queueToast(string.format("%s: %s", what, p.orderBlocked))
      else
        self:queueToast(string.format("%s: %s", what, p.orderUnreachable))
      end
    end),
    events:on("placement.done", function(e)
      self:queueToast(string.format(self.app.ctx.tuning.ui.placement.done, name("objects", e.object):lower()))
    end),
    events:on("placement.cancelled", function(e)
      local p = self.app.ctx.tuning.ui.placement
      if e.reason == "player" then
        self:queueToast(string.format(p.cancelled, name("objects", e.object):lower()))
      else
        self:queueToast(string.format(p.lostItem, name("objects", e.object):lower()))
      end
    end),
    events:on("market.held", function(e)
      self:showToast(name("catalog", e.item) .. " is waiting at the gate: no room in storage")
    end),
    events:on("processing.blocked", function(e)
      self:showToast(string.format("%d %s waiting: no room in storage", e.count, name("resources", e.output)))
    end),
    events:on("market.cancelled", function(e)
      self:showToast(string.format("Cancelled %s: refunded $%d", name("catalog", e.item), e.amount))
    end),
    events:on("market.refunded", function(e)
      self:queueToast(string.format("%s can never fit in storage: refunded $%d", name("catalog", e.item), e.amount))
    end),
    events:on("fish.lost", function(e)
      if e.reason == "full" then
        self:showToast(name("fish", e.fish) .. " got away: no room to keep it")
      end
    end),
    events:on("ledger.overflow", function(e)
      -- Several goods overflowing together are one log line, and the toast shows the merged line.
      local part = string.format("%d %s", e.lost, name("resources", e.id):lower())
      self.log:addPart("overflow", part, "Storage full: lost %s", self:stamp())
      self:present(self.log:lines()[1].text)
    end),
    -- Spoilage is reported once a night (D68, #151): see Homestead:spoilageNews, shown when awake.
    -- Journal news waits its turn so a note and the idea it sparks are both seen.
    events:on("journal.note", function(e)
      self:newsToast("New note: " .. world.registry:get("notes", e.note).line)
    end),
    events:on("journal.idea", function(e)
      self:newsToast("New idea: " .. Journal.node(world, e.item).name .. " · see the Journal")
    end),
    events:on("needs.depleted", function()
      self.failed = true
    end),
    -- Warnings (D70): low food, fuel or health, said once per crossing. Held while asleep so the fast
    -- night does not swallow them; the morning report comes first, then these.
    events:on("alert.raised", function(e)
      self:heldToast("alert:" .. e.kind, AlertText.toast(e))
    end),
    events:on("sleep.started", function()
      local day = Calendar.now(world).day
      if self.bedtimeDay ~= day then
        self.bedtimeDay = day -- once a day: going back to bed after a "stay up" is not news
        self:queueToast(NightText.bedtime(world))
      end
    end),
    events:on("calendar.newSeason", function(e)
      if e.season == "autumn" then
        local text = AlertText.autumnToast(world)
        if text then
          self:heldToast("autumn", text)
        end
      end
    end),
    events:on("weather.forecast", function(e)
      self:newsToast(Forecast.news(world, e.piece))
    end),
    events:on("weather.changed", function(e)
      local news = Forecast.weatherNews(world, e.kind)
      if news then
        self:newsToast(news)
      end
    end),
    events:on("threat.warned", function(e)
      self:newsToast(Forecast.threatWarning(world, e.threat, e.days))
    end),
    events:on("threat.started", function(e)
      local news = Forecast.threatStarted(world, e.threat)
      if news then
        self:newsToast(news)
      end
    end),
    events:on("threat.ended", function(e)
      -- The summary goes first: the note the strike just wrote waits behind it (asleep, both are held
      -- in the order they were raised, so the summary still leads).
      local text = Forecast.threatSummary(world, e)
      if self.session:sleeping() then
        self:newsToast(text)
      else
        self:urgentToast(text)
      end
    end),
    events:on("weather.froze", function()
      self:newsToast("The creek froze. Cut a hole to fish or fetch water.")
    end),
    events:on("water.dry", function()
      self:queueToast("A drip line is dry. Fill the cistern or the crops need hand watering.")
    end),
    events:on("water.restored", function()
      self:queueToast("Drip lines are watering again.")
    end),
    events:on("machine.unpowered", function(e)
      self:queueToast(name("objects", e.kind) .. " has ripe crops but no power")
    end),
    events:on("power.brownout", function(e)
      self:queueToast(string.format("Power short: %s at %d%%", Power.tierName(world, e.tier), math.floor(e.ratio * 100)))
    end),
    events:on("weather.coldSnap", function(e)
      self:newsToast(e.active and "Cold snap! Fires need far more wood." or "The cold snap broke.")
    end),
    events:on("finds.picked", function(e)
      local def = world.registry:get("finds", e.find)
      self:queueToast("Took: " .. def.name .. " · " .. def.line)
    end),
    events:on("journal.learned", function(e)
      local where = Journal.kindOf(world, e.item) == "perks" and "from your next run" or "now in the catalog"
      self:queueToast("Learned: " .. Journal.node(world, e.item).name .. " · " .. where)
    end),
  }
end

function Homestead:exit()
  self:saveNow()
  for _, off in ipairs(self.unsubscribe or {}) do
    off()
  end
  if self.app.ctx.session == self.session then
    self.app.ctx.session = nil
  end
end

function Homestead:saveNow()
  local ok, err = self.session:save()
  if not ok then
    print("Save failed: " .. tostring(err))
  end
end

function Homestead:focus(hasFocus)
  if not hasFocus then
    self:saveNow()
  end
end

function Homestead:quit()
  self:saveNow()
end

function Homestead:resize(view)
  local s = view.scale
  local w, h = math.floor(view.w * s + 0.5), math.floor(view.h * s + 0.5)
  -- Dragging the window edge fires many resizes: reuse the canvas when the pixel size is
  -- unchanged and free the old one's GPU memory right away when it has to be replaced.
  if not (self.canvas and self.canvas:getWidth() == w and self.canvas:getHeight() == h) then
    if self.canvas then
      self.canvas:release()
    end
    self.canvas = love.graphics.newCanvas(w, h)
    self.canvas:setFilter("nearest", "nearest")
  end
  self.camera:clamp(view)
  self:layout()
end

--- Say what spoiled overnight (D68, #151): a card with the explanation the first time ever, a queued
--- toast after that. It waits for the homesteader to be up and the world to be on top, so a night's
--- loss is not lost to the fast-forward.
function Homestead:spoilageNews()
  local world = self.world
  -- A morning report carries the night's spoilage itself (D70): leave it in Food until that card is up.
  if not Food.hasReport(world) or self.session:sleeping() or self.app:top() ~= self or Nightly.hasReport(world) then
    return
  end
  local report = Food.takeReport(world)
  if report.first then
    self:record(SpoilText.summary(world, report)) -- the card explains; the log keeps the one-line fact
    local app = self.app
    app:push(require("src.scenes.notice").new({
      title = "Food spoils",
      headline = SpoilText.summary(world, report),
      message = SpoilText.explanation(world),
      okLabel = "Got it",
      more = {
        label = "Open Pantry",
        onPress = function()
          app:push(require("src.scenes.pantry").new(world))
        end,
      },
    }))
  else
    -- Ahead of the note the same night may have written, which waits behind it.
    self:urgentToast(SpoilText.summary(world, report))
  end
end

--- The date a message log line is stamped with.
function Homestead:stamp()
  local now = Calendar.now(self.world)
  return { day = now.day, hour = now.hour, at = Calendar.elapsed(self.world) }
end

--- Put a line in the message log (D90, #167). Every toast goes through here, once, when it is raised
--- (or, for news held through the night, when the homesteader is up), so a toast that was replaced or
--- ran out unseen can still be read there.
function Homestead:record(text)
  self.log:add(text, self:stamp())
end

--- Put a toast on screen without logging it (it was logged already).
function Homestead:present(text)
  self.toast = { text = text, time = TOAST_TIME }
end

function Homestead:showToast(text)
  self:record(text)
  self:present(text)
end

--- Show after the current toast (and any already waiting) instead of replacing it.
function Homestead:queueToast(text)
  self:record(text)
  if not self.toast then
    self:present(text)
    return
  end
  self.toastQueue[#self.toastQueue + 1] = text
end

--- Queue a toast, or hold it until the homesteader is up when it comes in during the fast-forwarded
--- night (D70, D90). A held toast with a key is replaced by a newer one with the same key; with no key
--- it is always kept, and the held toasts come out in the order they were raised.
function Homestead:heldToast(key, text)
  if not self.session:sleeping() then
    self:queueToast(text)
    return
  end
  for _, held in ipairs(self.held) do
    if key and held.key == key then
      held.text = text
      return
    end
  end
  self.held[#self.held + 1] = { key = key, text = text }
end

--- Hand the held toasts over once the homesteader is up (after the morning report, which is a card).
function Homestead:releaseHeld()
  if self.session:sleeping() or #self.held == 0 then
    return
  end
  local held = self.held
  self.held = {}
  for _, h in ipairs(held) do
    self:queueToast(h.text)
  end
end

--- Show now, putting whatever was showing back at the head of the queue (nothing is lost).
function Homestead:urgentToast(text)
  self:record(text)
  if self.toast then
    table.insert(self.toastQueue, 1, self.toast.text)
  end
  self:present(text)
end

--- News the player should hear, held through the fast-forwarded night so it is not read to nobody.
function Homestead:newsToast(text)
  self:heldToast(nil, text)
end

--- Open the message log (tap the toast area or the Log button).
function Homestead:openLog()
  self.app:push(require("src.scenes.message_log").new(self.log))
end

function Homestead:toaster()
  return function(text)
    self:showToast(text)
  end
end

-- HUD buttons --------------------------------------------------------------------------

function Homestead:setHand(seed, tool)
  self.seed, self.tool, self.mode, self.planStart, self.placing = seed, tool, "act", nil, nil
  if self.placeCard and self.placeCard.kind == "confirm" then
    self.placeCard = nil -- leaving Place drops a confirmation that was up (D79)
  end
  self:layout()
  local late = seed and self:frostWarning(seed)
  if late then
    self:showToast(late) -- picking a seed that cannot ripen in time: say so before the first tile (#165)
  end
end

-- First object waiting in the inventory (sorted for stability), or nil.
function Homestead:nextPlaceable()
  local ids = {}
  for id in pairs(self.world.state.inventory.objects) do
    if Placement.available(self.world, id) > 0 then -- items already promised to a queued order are not offered
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids[1]
end

-- Top-bar stats, in order: { icon, text }. Big numbers are abbreviated so the strip stays short.
local function count(n)
  if n >= 10000 then
    return string.format("%dk", math.floor(n / 1000))
  end
  return tostring(n)
end

function Homestead:stats()
  local world = self.world
  local truck = world.state.land.truck
  -- Warmth in stock, in nights of this season's need (or the raw amount when no fire is needed).
  local warmth, need = Needs.warmthInStock(world), Needs.warmthNeeded(world)
  -- The truck chip says "go" once a trip is possible (D72, #162), in the accent colour.
  local battery = string.format("%d%%", math.floor(Power.charge(world, truck) / Power.capacity(world, truck) * 100))
  local tripReady = Market.canTrip(world) and not world.state.market.inTown
  -- Each entry is { icon, text, colour, id = chip id } (the id keys the tap-to-explain card, #158).
  local stats = {
    { "icon_money", "$" .. count(Ledger.get(world, "money")), id = "money" },
    -- Food, firewood and health turn amber, then red, as they run low (D70, #157; thresholds in tuning.alerts).
    { "icon_food", string.format("%.1fd", Needs.foodDays(world)), AlertText.chipColor(world, "food"), id = "food" },
    { "icon_heart", tostring(math.floor(Needs.condition(world) + 0.5)), AlertText.chipColor(world, "condition"), id = "condition" },
    {
      "icon_battery",
      tripReady and (battery .. " " .. self.app.ctx.tuning.ui.labels.tripReady) or battery,
      tripReady and theme.colors.accent or nil,
      id = "battery",
    },
    -- Spare goods (D75): units above their keep targets, what the stand and the truck can sell.
    { "icon_crate", count(select(2, Food.surpluses(world))), id = "surplus" },
    { "icon_wood", count(Ledger.get(world, "wood")), id = "wood" },
    {
      "icon_firewood",
      need > 0 and string.format("%.1fn", warmth / need) or string.format("%.0f", warmth),
      -- The firewood chip turns red when either firewood store is full (D59), and amber then red as the
      -- stock falls short of the coming nights (D70).
      (Ledger.isFull(world, "firewood") or Ledger.isFull(world, "seasoned_firewood")) and theme.colors.danger
        or AlertText.chipColor(world, "fuel"),
      id = "firewood",
    },
  }
  local tonight = Spoilage.tonight(world)
  if tonight.warn then
    -- Fresh food is about to rot (D68, D73): the number is how many units go tonight.
    stats[#stats + 1] = { "icon_spoiled", "-" .. tonight.units, theme.colors.danger, id = "spoiled" }
  end
  if Water.hasCistern(world) then
    -- Cistern stock, once there is a cistern to hold it.
    stats[#stats + 1] = { "icon_water", string.format("%d%%", math.floor(Water.fraction(world) * 100 + 0.5)), id = "water" }
  end
  if Animals.hasCoop(world) then
    -- Hens (red when they are short of feed or water) and the eggs waiting in the nest box.
    local flock = Animals.info(world)
    local short = flock.hens > 0 and (flock.hungryDays > 0 or flock.thirstyDays > 0 or flock.feedDays < 1)
    stats[#stats + 1] = { "icon_hen", string.format("%d/%d", flock.hens, flock.housing), short and theme.colors.danger or nil, id = "hens" }
    stats[#stats + 1] = { "icon_egg", tostring(flock.nest), id = "eggs" }
  end
  if Animals.hasPen(world) then
    -- Goats (red when short of hay or water, or the animal-feed warning is red) and the milk in the pail.
    local herd = Animals.goatInfo(world)
    local short = herd.goats > 0 and (herd.hungryDays > 0 or herd.thirstyDays > 0 or herd.feedDays < 1)
    stats[#stats + 1] = {
      "icon_goat",
      string.format("%d/%d", herd.goats, herd.housing),
      short and theme.colors.danger or AlertText.chipColor(world, "animals"),
      id = "goats",
    }
    stats[#stats + 1] = { "icon_milk", tostring(herd.pail), id = "milk" }
  end
  return stats
end

-- Width of the stat strip with `gap` between stats.
function Homestead:statsWidth(gap)
  local ui = self.app.ctx.tuning.ui
  local total = 0
  for _, s in ipairs(self:stats()) do
    total = total + Assets.sprite(s[1]).w + ui.statIconGap + Text.measure(s[2], "small")
  end
  return total + gap * (#self:stats() - 1)
end

-- True when the stats don't fit beside the date and need their own row under it.
function Homestead:wantsStatRow()
  local ui = self.app.ctx.tuning.ui
  local room = self.app.view.w - ui.menuWidth - ui.log.buttonWidth - 2 - ui.statsAfterDate - ui.barPadding
  return self:statsWidth(ui.statMinGap) > room
end

function Homestead:layout()
  local view = self.app.view
  local world = self.world
  local ui = self.app.ctx.tuning.ui
  local compact = view.w < ui.compactWidth
  local btnH = compact and ui.compactButtonHeight or ui.buttonHeight
  self.btnH = btnH
  self.statRow = self:wantsStatRow()
  self.topRowH = compact and ui.compactTopBarHeight or ui.topBarHeight
  self.topH = self.topRowH + (self.statRow and ui.statRowHeight or 0)
  self.buttons:clear()
  self.seedButtons = {}
  self.buttons:add({
    x = view.w - ui.menuWidth - 2,
    y = 0,
    w = ui.menuWidth,
    h = self.topRowH,
    label = "Menu",
    onPress = function()
      self:openMenu()
    end,
  })
  -- The message log (D90, #167): everything the toasts said, one tap away beside Menu.
  self.buttons:add({
    x = view.w - ui.menuWidth - ui.log.buttonWidth - 4,
    y = 0,
    w = ui.log.buttonWidth,
    h = self.topRowH,
    label = "Log",
    onPress = function()
      self:openLog()
    end,
  })
  self:layoutToolbar(view)
  self:layoutControls(view)
  self:layoutCard()
end

--- Build the bottom toolbar and place it (D72, #168, #17). A wide view gets the classic bar (tools left,
--- books right, one row); a narrow one gets a palette bar: Hand, Tools, the tool in hand, Pantry, Journal
--- and More, with the rest of the tools and books in the palette that Tools and More open above the bar.
--- Placement is pure (src/ui/toolbar.lua); this only decides what the buttons are and what they say.
function Homestead:layoutToolbar(view)
  local world = self.world
  local ui = self.app.ctx.tuning.ui
  local bw, L = ui.buttonWidths, ui.labels
  local inHand = self.mode == "act"
  local function fit(label, min, icon)
    return math.max(min, math.ceil(Text.measure(label, "body")) + ui.controlTextPadding + (icon and 15 or 0))
  end
  -- A press on a tool or book closes an open palette, does its thing, and lays the bar out again.
  local function act(fn)
    return function(b)
      self.palette = nil
      fn(b)
      self:layout()
    end
  end
  self.seedButtons = {}

  local hand = {
    id = "hand",
    w = bw.hand,
    label = L.hand,
    selected = inHand and not self.seed and not self.tool,
    onPress = act(function()
      self:setHand(nil, nil)
    end),
  }
  local tools = {}
  for _, crop in ipairs(world.registry:all("crops")) do
    local button = {
      id = "seed:" .. crop.id,
      w = bw.seed,
      icon = "icon_" .. crop.seed,
      label = tostring(Ledger.get(world, crop.seed)),
      selected = self.seed == crop.id and self.mode ~= "place",
      onPress = act(function()
        if self.seed == crop.id and inHand then
          self:setHand(nil, nil)
        else
          self:setHand(crop.id, nil)
        end
      end),
    }
    self.seedButtons[crop.id] = button
    tools[#tools + 1] = button
  end
  tools[#tools + 1] = {
    id = "rod",
    w = fit(L.rod, bw.rod, true),
    icon = "icon_rod",
    label = L.rod,
    selected = inHand and self.tool == "rod",
    onPress = act(function()
      self:setHand(nil, self.tool ~= "rod" and "rod" or nil)
    end),
  }
  tools[#tools + 1] = {
    id = "untill",
    w = fit(L.untill, bw.untill),
    label = L.untill,
    selected = inHand and self.tool == "untill",
    onPress = act(function()
      self:setHand(nil, self.tool ~= "untill" and "untill" or nil)
    end),
  }
  local placeable = self:nextPlaceable()
  if placeable then
    local def = world.registry:get("objects", placeable)
    local label = L.place .. " " .. def.name:lower()
    tools[#tools + 1] = {
      id = "place",
      gapBefore = ui.groupGap,
      w = math.max(bw.placeMin, math.ceil(Text.measure(label, "body")) + 12),
      label = label,
      short = L.place,
      style = "accent",
      selected = self.mode == "place",
      onPress = act(function()
        if self.mode == "place" then
          self:setHand(nil, nil)
        else
          self.mode, self.placing, self.planStart = "place", placeable, nil
          self:showToast("Tap where the " .. def.name:lower() .. " should go")
        end
      end),
    }
  end
  tools[#tools + 1] = {
    id = "plan",
    gapBefore = not placeable and ui.groupGap or nil,
    w = fit(L.plan, bw.plan),
    label = L.plan,
    selected = self.mode == "plan",
    onPress = act(function()
      if self.mode == "plan" then
        self:setHand(self.seed, nil)
        return
      end
      self.mode, self.planStart, self.tool, self.placing = "plan", nil, nil, nil
      self:showToast(self.seed and "Tap two corners to plan " .. world.registry:get("crops", self.seed).name
        or "Tap two corners to clear a plan")
    end),
  }
  local routineList = {
    id = "routineList",
    w = fit(L.routineList, bw.routine),
    label = L.routineList,
    onPress = act(function()
      self.app:push(require("src.scenes.routine").new(world))
    end),
  }
  self.journalPrompt = Journal.needsChoice(world)
  local pantry = {
    id = "pantry",
    w = bw.pantry,
    label = L.pantry,
    onPress = act(function()
      self.app:push(require("src.scenes.pantry").new(world))
    end),
  }
  local catalog = {
    id = "catalog",
    w = bw.catalog,
    label = L.catalog,
    onPress = act(function()
      self.app:push(require("src.scenes.catalog").new(world, self:toaster()))
    end),
  }
  local fishGuide = {
    id = "fish",
    w = fit(L.fishGuide, bw.fish),
    label = L.fishGuide,
    onPress = act(function()
      self.app:push(require("src.scenes.guide").new(world))
    end),
  }
  local journal = {
    id = "journal",
    w = bw.journal,
    label = L.journal,
    style = self.journalPrompt and "accent" or nil,
    onPress = act(function()
      self.app:push(require("src.scenes.journal").new(world, self:toaster()))
    end),
  }

  -- Palette bar pieces: the two palette buttons and a shortcut for the tool in hand.
  local function opener(id, label, min)
    return {
      id = id,
      w = fit(label, min),
      label = label,
      selected = self.palette == id,
      onPress = function()
        self.palette = self.palette ~= id and id or nil
        for _, list in pairs(self.paletteLists) do
          list.offset = 0 -- a palette opens at its top
        end
        self:layout()
      end,
    }
  end
  local toolsButton, moreButton = opener("tools", L.tools, bw.tools), opener("more", L.more, bw.more)
  local active
  for _, id in ipairs({ "place", "plan", "rod", "untill" }) do
    for _, b in ipairs(tools) do
      if b.id == id and b.selected and not active then
        active = b
      end
    end
  end
  for _, b in ipairs(tools) do
    if not active and b.selected and b.id:find("^seed:") then
      active = b
    end
  end
  self.activeChip = nil
  if active then
    local label = active.short or active.label
    self.activeChip = {
      id = "active",
      of = active.id,
      source = active,
      w = fit(label, bw.activeMin, active.icon ~= nil),
      icon = active.icon,
      label = label,
      short = active.short,
      selected = true,
      onPress = active.onPress,
    }
  end

  local left = { hand }
  for _, b in ipairs(tools) do
    left[#left + 1] = b
  end
  left[#left + 1] = routineList
  local spec = {
    left = left,
    right = { pantry, catalog, fishGuide, journal },
    fixedLeft = { hand },
    toolsButton = toolsButton,
    active = self.activeChip,
    fixedRight = { pantry, journal },
    moreButton = moreButton,
    tools = tools,
    more = { routineList, catalog, fishGuide },
  }
  -- The palette is capped (D87, #184): a few rows, and never up into the speed/routine/power column;
  -- more than fits scrolls (drag, wheel, keys) with a thumb beside the buttons.
  local scroll = {}
  for name, list in pairs(self.paletteLists) do
    scroll[name] = list.offset
  end
  local arranged = Toolbar.arrange(spec, view, {
    pad = ui.barPadding,
    gap = ui.buttonGap,
    h = self.btnH,
    margin = ui.barMargin,
    paletteGap = ui.paletteGap,
    paletteMaxRows = ui.paletteMaxRows,
    paletteTop = self.topH + ui.buttonGap + 3 * (self.btnH + ui.buttonGap),
    scrollBarWidth = ui.scrollBarWidth,
    scroll = scroll,
  })
  self.toolbar = arranged
  self.bottomH = arranged.bottomH
  for _, b in ipairs(arranged.bar) do
    self.buttons:add(b)
  end
  self.paletteRect = nil
  self.paletteButtons:clear()
  if arranged.popups and self.palette then
    local popup = arranged.popups[self.palette]
    self.paletteRect = popup
    self.paletteList = self.paletteLists[self.palette]
    self.paletteList:fit(popup.view, popup.contentH, 0, 1)
    self.paletteList.offset = popup.offset
    -- Buttons that scrolled out of the window are left out; half-hidden ones answer only inside it.
    for _, b in ipairs(popup.items) do
      if b.y + b.h > popup.view.y and b.y < popup.view.y + popup.view.h then
        self.paletteButtons:add(b)
      end
    end
  else
    self.palette = nil -- the view got wide enough for the full bar
    self.paletteList = nil
  end
end

-- First-time tip card (D69, #152) ---------------------------------------------------------

--- The tip card due now, or nil. It waits for the homestead to be on top (no panel, find or fishing
--- game over it) and never pauses the sim.
function Homestead:dueCard()
  if self.app:top() ~= self or Finds.pending(self.world) then
    return nil
  end
  return Ftue.current(self.world)
end

--- The id the card slot would show now (cheap: the update loop compares it with the one on screen).
function Homestead:cardIdNow()
  if self.placeCard then
    return "place:" .. self.placeCard.kind .. ":" .. self.placeCard.tile -- the player's own card has the slot (D79)
  end
  local due = self:dueCard()
  if due then
    return due.id
  end
  if self.app:top() == self and not self.session:sleeping() and not Finds.pending(self.world) and Nightly.hasReport(self.world) then
    return "night:" .. Nightly.report(self.world).day
  end
  return nil
end

-- The target footprint of the open placement card as a rect in view pixels, or nil (D86, #206).
function Homestead:placeCardRect()
  local pc, world = self.placeCard, self.world
  if not pc then
    return nil
  end
  local tiles
  if pc.kind == "confirm" then
    tiles = Placement.preview(world, self.placing, pc.tile).tiles
  else
    local order = Placement.orderAt(world, pc.tile)
    tiles = order and Placement.footprintOf(world, order)
  end
  if not tiles or #tiles == 0 then
    return nil
  end
  local grid, camera, view = world.state.grid, self.camera, self.app.view
  local list = {}
  for _, t in ipairs(tiles) do
    local tx, ty = Grid.coords(grid, t)
    list[#list + 1] = { x = tx, y = ty }
  end
  local size = camera.tileSize * camera:zoom()
  return PlaceCard.bounds(list, function(tx, ty)
    local wx, wy = camera:tileToWorld(tx, ty)
    local vx, vy = camera:worldToView(wx, wy, view)
    return vx, vy, size, size
  end)
end

--- Where a placement card of height h goes so it never covers the tile it describes: the camera pans so the
--- footprint sits above the card; when the map edge stops that, the card hangs under the top bar instead.
--- Returns the card's y (`y` is the usual slot above the toolbar).
function Homestead:keepTargetClear(y, h)
  local rect = self:placeCardRect()
  local gap = self.app.ctx.tuning.ui.placement.cardGap
  if not rect or not PlaceCard.overlaps(rect, y, h, gap) then
    return y
  end
  local view = self.app.view
  local dy = PlaceCard.panFor(rect, y, gap, self.topH)
  if dy and dy ~= 0 then
    self.camera:pan(0, dy, view)
    rect = self:placeCardRect()
    if not PlaceCard.overlaps(rect, y, h, gap) then
      return y
    end
  end
  local top = PlaceCard.topY(self.topH, gap)
  if not PlaceCard.overlaps(rect, top, h, gap) then
    return top
  end
  -- Neither slot clears it as it stands: pan the footprint below a top card if it fits there.
  local below = top + h + gap
  if rect.y + rect.h <= view.h - self.bottomH and rect.y < below then
    self.camera:pan(0, below - rect.y, view)
    rect = self:placeCardRect()
    if not PlaceCard.overlaps(rect, top, h, gap) then
      return top
    end
  end
  return y
end

--- Build the card's rectangle and buttons: a panel above the toast line with the text and two buttons.
function Homestead:layoutCard()
  local ctx = self.app.ctx
  local cfg, view = ctx.tuning.ftue, self.app.view
  self.cardButtons = self.cardButtons or Buttons.new(ctx.tuning.input.minTouchTarget)
  self.cardButtons:clear()
  self.card, self.cardId, self.cardKind = nil, nil, nil
  local spec = self:cardSpec()
  if not spec then
    return
  end
  local pad = cfg.cardPadding
  local w = math.min(cfg.cardMaxWidth, view.w - 2 * cfg.cardMargin)
  local inner = w - 2 * pad
  local _, titleH = Text.measure(spec.title, "body")
  local textH = 0
  for _, line in ipairs(spec.lines) do
    line.h = Text.wrappedHeight(line.text, "small", inner)
    textH = textH + line.h + (spec.lineGap or 0)
  end
  local btnH = self.btnH
  local h = pad + titleH + 3 + textH + pad + btnH + pad
  local x = math.floor((view.w - w) / 2)
  local y = math.floor(view.h - self.bottomH - cfg.cardBottomGap - h)
  if spec.kind == "place" then
    y = self:keepTargetClear(y, h)
  end
  self.card = { x = x, y = y, w = w, h = h, title = spec.title, lines = spec.lines, lineGap = spec.lineGap or 0, titleH = titleH, pad = pad }
  self.cardId = spec.id
  self.cardKind = spec.kind
  local bw = math.floor((inner - ctx.tuning.ui.buttonGap) / 2)
  local by = y + h - pad - btnH
  self.cardButtons:add({
    x = x + pad,
    y = by,
    w = bw,
    h = btnH,
    label = spec.leftLabel,
    onPress = function()
      spec.onLeft()
      self:layoutCard()
    end,
  })
  self.cardButtons:add({
    x = x + w - pad - bw,
    y = by,
    w = bw,
    h = btnH,
    label = spec.rightLabel or "Got it",
    style = "accent",
    onPress = function()
      spec.onGotIt()
      self:layoutCard()
    end,
  })
end

--- What the card slot holds now, or nil. A first-time tip card (D69) has the slot whenever one is due;
--- otherwise the morning report (D70, #159) takes it. The report waits in the sim until it is dismissed
--- or has timed out, so a tip card in front of it only delays it. Returns { id, kind, title, lines =
--- { { text, color } }, leftLabel, onLeft, onGotIt }.
function Homestead:cardSpec()
  local world = self.world
  local pc = self.placeCard
  if pc then
    local p = self.app.ctx.tuning.ui.placement
    local colors = { text = theme.colors.text, dim = theme.colors.textDim, warn = theme.colors.danger }
    if pc.kind == "confirm" then
      local preview = Placement.preview(world, self.placing, pc.tile)
      local text = PlaceText.confirm(world, self.placing, preview, colors)
      return {
        id = "place:confirm:" .. pc.tile,
        kind = "place",
        title = text.title,
        lines = text.lines,
        lineGap = 2,
        leftLabel = p.cancel,
        rightLabel = p.confirm,
        onLeft = function()
          self.placeCard = nil
        end,
        onGotIt = function()
          self:confirmPlacement(pc.tile)
        end,
      }
    end
    local order = Placement.orderAt(world, pc.tile)
    if order then
      local text = PlaceText.order(world, order, colors)
      return {
        id = "place:order:" .. pc.tile,
        kind = "place",
        title = text.title,
        lines = text.lines,
        lineGap = 2,
        leftLabel = p.orderClose,
        rightLabel = p.orderCancel,
        onLeft = function()
          self.placeCard = nil
        end,
        onGotIt = function()
          Placement.cancel(world, pc.tile)
          self.placeCard = nil
        end,
      }
    end
    self.placeCard = nil
  end
  local due = self:dueCard()
  if due then
    return {
      id = due.id,
      kind = "tip",
      title = due.title,
      lines = { { text = due.text, color = theme.colors.text } },
      leftLabel = "Skip tips",
      onLeft = function()
        Ftue.skip(world)
        self:showToast("Tips off. Menu > Tips turns them back on")
      end,
      onGotIt = function()
        Ftue.dismiss(world, due.id)
      end,
    }
  end
  if self.app:top() ~= self or self.session:sleeping() or Finds.pending(world) or not Nightly.hasReport(world) then
    return nil
  end
  local report = Nightly.report(world)
  local view = self:reportView(report)
  local left = { leftLabel = "Pantry", onLeft = function()
    self.app:push(require("src.scenes.pantry").new(world))
  end }
  if view.first then
    -- The first spoilage ever: the card carries the explanation (D68) behind a button.
    left = { leftLabel = "Why?", onLeft = function()
      local app = self.app
      app:push(require("src.scenes.notice").new({
        title = "Food spoils",
        headline = view.first,
        message = SpoilText.explanation(world),
        okLabel = "Got it",
        more = { label = "Open Pantry", onPress = function()
          app:push(require("src.scenes.pantry").new(world))
        end },
      }))
    end }
  elseif not view.spoil then
    left = { leftLabel = "Journal", onLeft = function()
      self.app:push(require("src.scenes.journal").new(world, self:toaster()))
    end }
  end
  local lines = {}
  for _, line in ipairs(view.lines) do
    lines[#lines + 1] = { text = line.text, color = line.color or theme.colors.text }
  end
  return {
    id = "night:" .. report.day,
    kind = "report",
    title = "Morning report",
    lines = lines,
    lineGap = 2,
    leftLabel = left.leftLabel,
    onLeft = left.onLeft,
    onGotIt = function()
      self:dismissReport()
    end,
  }
end

--- The report's text lines, built once per report (the spoilage report waiting in Food is taken with
--- it, so the explanation card of the first spoilage is offered here and not twice).
function Homestead:reportView(report)
  if self.reportShown and self.reportShown.day == report.day then
    return self.reportShown
  end
  local lines, spoil = NightText.morning(self.world, report)
  local first
  if Food.hasReport(self.world) then
    local spoilReport = Food.takeReport(self.world)
    if spoilReport.first then
      first = SpoilText.summary(self.world, spoilReport)
    end
  end
  self.reportShown = { day = report.day, lines = lines, spoil = spoil, first = first }
  self.reportTimer = self.app.ctx.tuning.ui.reportSeconds
  return self.reportShown
end

function Homestead:dismissReport()
  Nightly.take(self.world)
  self.reportShown, self.reportTimer = nil, nil
end

--- Taps on the card read it rather than direct the homesteader, so they do not reset the takeover timer.
function Homestead:ignoresActivityAt(x, y)
  return self:overCard(x, y) or self:chipAt(x, y) ~= nil or self:overToast(x, y) -- a chip's explanation is not directing the homesteader either (D72)
end

--- Is the point on the toast? (Its rectangle is the one drawn last, grown to the touch size.)
function Homestead:overToast(x, y)
  local r = self.toast and self.toastHit
  return r ~= nil and x ~= nil and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function Homestead:overCard(x, y)
  local c = self.card
  return c ~= nil and x >= c.x and x < c.x + c.w and y >= c.y and y < c.y + c.h
end

--- Where a tip card's `highlight` target is on screen now, { x, y, w, h } or nil (D89, #171). Reads layout
--- only; a target that is missing or off screen gives nil and nothing is drawn.
function Homestead:highlightRect(target)
  local function inList(list, match)
    for _, b in ipairs(list) do
      if b.id and match(b.id) then
        return { x = b.x, y = b.y, w = b.w, h = b.h }
      end
    end
    return nil
  end
  local function button(id)
    return inList(self.buttons.list, function(bid)
      return bid == id
    end) or inList(self.paletteButtons.list, function(bid)
      return bid == id
    end)
  end
  local find = {
    button = button,
    seed = function()
      return inList(self.paletteButtons.list, function(bid)
        return bid:find("^seed:") ~= nil
      end) or inList(self.buttons.list, function(bid)
        return bid:find("^seed:") ~= nil
      end)
    end,
    chip = function(id)
      for _, r in ipairs(self:chipRects()) do
        if r.id == id then
          return r
        end
      end
      return nil
    end,
    tile = function(name)
      local world, camera, view = self.world, self.camera, self.app.view
      local i = name == "truck" and Land.truck(world) or nil
      if not i then
        return nil
      end
      local grid = world.state.grid
      local def, anchor = Grid.object(world, i)
      local tiles = { i }
      if def then
        local ax, ay = Grid.coords(grid, anchor)
        tiles = Grid.footprintTiles(grid, def, ax, ay) or tiles
      end
      local list = {}
      for _, t in ipairs(tiles) do
        local tx, ty = Grid.coords(grid, t)
        list[#list + 1] = { x = tx, y = ty }
      end
      local size = camera.tileSize * camera:zoom()
      return PlaceCard.bounds(list, function(tx, ty)
        local wx, wy = camera:tileToWorld(tx, ty)
        local vx, vy = camera:worldToView(wx, wy, view)
        return vx, vy, size, size
      end)
    end,
  }
  return Highlight.visible(Highlight.resolve(target, find), self.app.view)
end

--- The pulsing outline for the tip card on screen, if its step has a `highlight` that can be found.
function Homestead:drawHighlight()
  if self.cardKind ~= "tip" or not self.cardId then
    return
  end
  local def = self.world.registry:get("ftue", self.cardId)
  local rect = def and def.highlight and self:highlightRect(def.highlight)
  if rect then
    Highlight.draw(rect, self.app.ctx.tuning.ftue, theme.colors.accent, love.timer.getTime(), self.app.view)
  end
end

function Homestead:drawCard()
  local c = self.card
  if not c then
    return
  end
  self:drawHighlight()
  Draw.panel(c.x, c.y, c.w, c.h)
  Text.draw(c.title, c.x + c.pad, c.y + c.pad, { size = "body", color = theme.colors.accent })
  local y = c.y + c.pad + c.titleH + 3
  for _, line in ipairs(c.lines) do
    Text.draw(line.text, c.x + c.pad, y, { size = "small", width = c.w - 2 * c.pad, color = line.color })
    y = y + line.h + c.lineGap
  end
  self.cardButtons:draw()
end

-- Speed and routine buttons: a column under the top bar, away from the (crowded) toolbar.
function Homestead:speedLabel()
  local speed = self.session:effectiveSpeed() -- fast while asleep (D56)
  return speed == 0 and "Paused" or string.format(self.app.ctx.tuning.ui.labels.speed, speed)
end

--- Skip the rest of the night (D56): only while asleep.
function Homestead:skipNight()
  if self.session:skipNight() then
    self:layout()
  end
end

function Homestead:routineLabel()
  if self.session:sleeping() then
    return self.session:skippingNight() and self.app.ctx.tuning.ui.labels.skipping or self.app.ctx.tuning.ui.labels.skipNight
  end
  if not self.session:canStartRoutine() then
    return self.app.ctx.tuning.ui.labels.resting
  end
  local L = self.app.ctx.tuning.ui.labels
  return self.world.control == "idle" and L.routineOn or L.startRoutine
end

function Homestead:controlsKey()
  return self:speedLabel() .. "|" .. self:routineLabel() .. "|" .. tostring(Power.satisfaction(self.world) < 1)
end

function Homestead:openPower()
  self.app:push(require("src.scenes.power").new(self.world, self:toaster()))
end

function Homestead:cycleSpeed()
  self.session:cycleSpeed(self.app.ctx.tuning.time.speedSteps)
  self:layout()
end

--- Hand over to the routine now (D43). Says why when it can't.
function Homestead:startRoutine()
  if self.world.control == "idle" then
    return true -- already running
  end
  local ok = self.session:startRoutineNow()
  if not ok then
    self:showToast("The routine rests at night")
  else
    self:showToast(self.app.ctx.tuning.ui.startRoutineHint)
  end
  self:layout()
  return ok
end

function Homestead:layoutControls(view)
  local ui = self.app.ctx.tuning.ui
  local x2, y = view.w - ui.buttonGap, self.topH + ui.buttonGap
  local speedLabel, routineLabel = self:speedLabel(), self:routineLabel()
  local function addCol(label, b)
    b.label = label
    b.w = math.max(ui.controlMinWidth, math.ceil(Text.measure(label, "body")) + ui.controlTextPadding)
    b.x, b.y, b.h = x2 - b.w, y, self.btnH
    self.buttons:add(b)
    y = y + b.h + ui.buttonGap
  end
  addCol(speedLabel, {
    style = self.session:effectiveSpeed() == 0 and "accent" or nil,
    enabled = not self.session:timeHeld(), -- the speed waits for the drive home (D78) or the tip card (D92)
    onPress = function()
      self:cycleSpeed()
    end,
  })
  if self.session:sleeping() then
    addCol(routineLabel, { -- the routine rests at night, so its slot becomes the skip control
      enabled = routineLabel == self.app.ctx.tuning.ui.labels.skipNight,
      style = "accent",
      onPress = function()
        self:skipNight()
      end,
    })
  else
    addCol(routineLabel, {
      enabled = routineLabel == self.app.ctx.tuning.ui.labels.startRoutine,
      onPress = function()
        self:startRoutine()
      end,
    })
  end
  addCol(ui.labels.power, {
    style = Power.satisfaction(self.world) < 1 and "danger" or nil, -- lit while the homestead is short of power
    onPress = function()
      self:openPower()
    end,
  })
  self.controlsKeyShown = self:controlsKey()
end

--- The winter-readiness card (D70, #166): the pill, expanded.
function Homestead:openReadiness()
  local world = self.world
  local headline, message = AlertText.readinessCard(world)
  if not headline then
    return
  end
  local app = self.app
  app:push(require("src.scenes.notice").new({
    title = "Winter readiness",
    headline = headline,
    message = message,
    okLabel = "Got it",
    more = {
      label = "Open Pantry",
      onPress = function()
        app:push(require("src.scenes.pantry").new(world))
      end,
    },
  }))
end

function Homestead:openMenu()
  self.app:push(require("src.scenes.menu").new(function()
    self.app:switch(require("src.scenes.slots").new())
  end))
end

-- Update ---------------------------------------------------------------------------------

--- Seconds without input before the routine takes over (shortened by habits perks).
function Homestead:takeoverDelay()
  local idle = self.app.ctx.tuning.idle
  return math.max(idle.minTakeoverDelay, idle.takeoverDelay - Stats.modifier(self.world, "idleTakeover"))
end

function Homestead:update(dt)
  local ctx = self.app.ctx
  -- A first-time tip card on screen holds game time and the takeover countdown while it is read (D92, #230).
  self.session:setTipUp(self.cardKind == "tip" and self.card ~= nil)
  self.session:update(dt) -- (also ends a hand-started routine at bedtime)
  local idle = self.session:routineForced() or ctx.input:idleSeconds() >= self:takeoverDelay()
  self.session:setControl(idle and "idle" or "active")
  if self.session:timeHeld() then
    -- Time stands still in town (D78) and under a tip card (D92): the takeover countdown waits too, so
    -- the routine does not grab the homesteader the moment the truck is back or the card is closed.
    ctx.input:holdIdle(dt)
  end
  if self.session:inTown() then
    if self.app:top() == self and not Finds.pending(self.world) then
      -- A save written in town loads paused in town: the town menu comes back (it is the only way home).
      self:openPanel("truck")
    end
  end
  if self.failed then
    -- Condition hit zero: the run is over (GDD §4.3). Record it, then search & rescue.
    local slot, data = self.session.slot, self.session.data
    Run.fail(data, self.world)
    self.app:switch(require("src.scenes.rescue").new(), slot, data)
    return
  end
  self.renderer:update(dt)
  -- A find waits for a free screen (not behind the fishing mini-game or a panel), also after a load.
  if Finds.pending(self.world) and self.app:top() == self then
    self.app:push(require("src.scenes.finds").new(self.world))
    return
  end
  self:spoilageNews()
  if self:cardIdNow() ~= self.cardId then
    self:layoutCard()
  end
  if self.cardKind == "report" and self.cardId then
    -- The morning report folds itself away if nobody reads it (a tip card in front pauses the count).
    self.reportTimer = (self.reportTimer or 0) - dt
    if self.reportTimer <= 0 then
      self:dismissReport()
      self:layoutCard()
    end
  end
  self:releaseHeld()
  if self.toast then
    self.toast.time = self.toast.time - dt
    if self.toast.time <= 0 then
      self.toast = nil
      if #self.toastQueue > 0 then
        self:present(table.remove(self.toastQueue, 1))
      end
    end
  end
  if self:controlsKey() ~= self.controlsKeyShown or self:wantsStatRow() ~= self.statRow then
    self:layout()
  end
  -- The Journal button lights up while there's an idea to pick and nothing queued (GDD §8.1).
  if Journal.needsChoice(self.world) ~= self.journalPrompt then
    self:layout()
  end
  -- Seed counts change as you plant and harvest; keep the toolbar labels current.
  for cropId, button in pairs(self.seedButtons) do
    button.label = tostring(Ledger.get(self.world, self.world.registry:get("crops", cropId).seed))
  end
  if self.activeChip then
    self.activeChip.label = self.activeChip.short or self.activeChip.source.label -- the shortcut mirrors the tool in hand
  end
  if self.placeCard and self.placeCard.kind == "order" and not Placement.orderAt(self.world, self.placeCard.tile) then
    self.placeCard = nil -- the order was built or cancelled
    self:layoutCard()
  end
  if self.mode == "place" and Placement.available(self.world, self.placing) <= 0 then
    self:setHand(nil, nil)
  end
end

-- Input ----------------------------------------------------------------------------------

function Homestead:tileAt(vx, vy)
  local view = self.app.view
  local wx, wy = self.camera:viewToWorld(vx, vy, view)
  local tx, ty = self.camera:worldToTile(wx, wy)
  if Grid.inBounds(self.world.state.grid, tx, ty) then
    return Grid.index(self.world.state.grid, tx, ty)
  end
  return nil
end

function Homestead:inWorldArea(y)
  return y > self.topH and y < self.app.view.h - self.bottomH
end

function Homestead:applyPlan(a, b)
  local grid = self.world.state.grid
  local ax, ay = Grid.coords(grid, a)
  local bx, by = Grid.coords(grid, b)
  local count = 0
  for y = math.min(ay, by), math.max(ay, by) do
    for x = math.min(ax, bx), math.max(ax, bx) do
      if Crops.setPlan(self.world, Grid.index(grid, x, y), self.seed) and self.seed then
        count = count + 1
      end
    end
  end
  if self.seed then
    self:showToast(string.format("Planned %d tiles of %s. Tilling and planting start now", count,self.world.registry:get("crops", self.seed).name))
    local late = count > 0 and AlertText.frost(self.world, self.seed)
    if late then
      self:queueToast(late) -- planned anyway; the tiles are tinted amber on the map (#165)
    end
  else
    self:showToast("Plan cleared")
  end
end

--- The won't-ripen-before-winter text for a crop, or nil: none when it will ripen, or when this crop's
--- warning already showed today (a row of taps must not repeat it).
function Homestead:frostWarning(cropId)
  if not cropId then
    return nil
  end
  local text = AlertText.frost(self.world, cropId)
  local day = Calendar.now(self.world).day
  if not text or self.frostTold[cropId] == day then
    return nil
  end
  self.frostTold[cropId] = day
  return text
end

--- The player confirmed the card: queue the order (crops and plans under it go now) and leave Place.
function Homestead:confirmPlacement(i)
  local world, id = self.world, self.placing
  local p = self.app.ctx.tuning.ui.placement
  self.placeCard = nil
  local result, reason, rule = Placement.request(world, id, i)
  if result == "queued" then
    self:showToast(p.ordered)
    self:setHand(nil, nil)
  elseif result == "placed" then
    self:showToast("Placed " .. world.registry:get("objects", id).name:lower())
    self:setHand(nil, nil)
  else
    self:showToast(PlaceText.reason(world, reason, rule))
  end
end

function Homestead:tap(i)
  local world = self.world
  self.selected = i
  if self.mode == "plan" then
    if not self.planStart then
      self.planStart = i
    else
      self:applyPlan(self.planStart, i)
      self.planStart = nil
      -- One plan per selection (D77, #192): back to the normal hand with the seed kept, so the next tap
      -- walks or acts. Holding Shift on a keyboard keeps the tool on for several plans.
      local keep = love.keyboard and love.keyboard.isDown("lshift", "rshift")
      if not keep then
        self.mode = "act"
        self:layout()
      end
    end
    return
  end
  if self.mode == "place" then
    -- Any buildable tile its own rules allow (D79). Open ground is placed at once; trees, rocks and crops in
    -- the way open the confirmation card first, which says what will be cleared or removed.
    local preview = Placement.preview(world, self.placing, i)
    if not preview.ok then
      self.placeCard = nil
      self:showToast(PlaceText.reason(world, preview.reason, preview.rule))
      self:layoutCard()
    elseif preview.immediate then
      self.placeCard = nil
      if Placement.request(world, self.placing, i) == "placed" then
        self:showToast("Placed " .. world.registry:get("objects", self.placing).name:lower())
        self:setHand(nil, nil)
      else
        self:showToast(PlaceText.reason(world, "bounds"))
      end
    else
      self.placeCard = { kind = "confirm", tile = i }
      self:layoutCard()
    end
    return
  end
  local queued = self.mode == "act" and Placement.orderAt(world, i)
  if queued then
    self.placeCard = { kind = "order", tile = queued.tile } -- a tap on a waiting building shows its order (D79)
    self:layoutCard()
    return
  end
  if Cat.at(world, i) then
    Cat.pet(world) -- tap the cat to pet it, wherever the homesteader is
    return
  end
  local obj = Grid.object(world, i)
  if obj and obj.id == "truck" then
    self.app:push(require("src.scenes.truck").new(world, self:toaster()))
    return
  end
  if obj and obj.machine then
    return -- a tap on a machine shows its card (and reach); its power switch is in the power panel
  end
  if obj and (obj.source or obj.sink or obj.battery) then
    self:openPower() -- panels, batteries and powered devices open the power panel
    return
  end
  local hs = Actors.homesteader(world)
  local taskType, full = Actors.order(world, hs, i, { crop = self.seed, tool = self.tool })
  if taskType then
    self.session:cancelRoutine() -- any order hands control back (D43)
    if taskType.id ~= "move" then
      -- Tilling or planting a crop that cannot ripen in time says so (D70, #165), once a day per crop;
      -- the order still goes ahead.
      local late = (taskType.id == "till" or taskType.id == "plant") and self:frostWarning(self.seed)
      self:showToast(late or taskType.verb)
    end
  elseif full then
    -- Refused for lack of room: say which store is full (D59).
    self:showToast(string.format("%s storage is full", world.registry:get("resources", full).name))
  elseif self.tool == "untill" then
    self:showToast(self.app.ctx.tuning.ui.placement.noUntill)
  else
    self:showToast("Can't do anything there")
  end
end

function Homestead:action(name, data)
  if self.card then
    if self.cardButtons:action(name, data) then
      return true
    end
    -- The card is solid: a tap on it never reaches the ground beneath.
    if data.x and self:overCard(data.x, data.y) and (name == "press" or name == "select" or name == "context") then
      return true
    end
  end
  if self.buttons:action(name, data) then
    return true
  end
  local pr = self.paletteRect
  if pr then
    local list = self.paletteList
    local over = data.x and data.x >= pr.x and data.x < pr.x + pr.w and data.y >= pr.y and data.y < pr.y + pr.h
    -- Palette buttons answer only inside the palette's window (a half-scrolled one must not reach out).
    if (name == "press" or name == "select" or name == "hover") and list:contains(data.x, data.y) and self.paletteButtons:action(name, data) then
      return true
    elseif name == "release" then
      self.paletteButtons:action(name, data)
    elseif name == "press" then
      self.palettePress = over -- a drag that began on the palette scrolls it, not the camera
    end
    local step = self.app.ctx.tuning.ui.scrollWheelStep
    if list.overflow and ((name == "pan" and (self.palettePress or data.keys)) or (name == "zoom" and over)) then
      if list:action(name, data, step) then
        self:layout()
      end
      return true
    end
  end
  if pr and data.x and (name == "press" or name == "select" or name == "context") then
    -- An open palette is solid; a tap outside it puts it away without reaching the ground (D72, #17).
    local inside = data.x >= pr.x and data.x < pr.x + pr.w and data.y >= pr.y and data.y < pr.y + pr.h
    if name == "select" and not inside then
      self.palette = nil
      self:layout()
    end
    return true
  end
  local view = self.app.view
  if name == "select" and data.x and self:overToast(data.x, data.y) then
    self:openLog() -- tapping the toast opens the message log (D90, #167)
    return true
  end
  if name == "select" and data.x then
    local chip = self:chipAt(data.x, data.y)
    if chip then
      self:openChip(chip)
      return true
    end
  end
  local hit = self.readinessHit
  if name == "select" and hit and data.x >= hit.x and data.x < hit.x + hit.w and data.y >= hit.y and data.y < hit.y + hit.h then
    self:openReadiness()
    return true
  end
  if name == "pan" then
    self.camera:pan(data.dx, data.dy, view)
  elseif name == "zoom" then
    self.camera:zoomBy(data.steps, data.x, data.y, view)
  elseif name == "hover" then
    self.hover = self:inWorldArea(data.y) and self:tileAt(data.x, data.y) or nil
  elseif name == "select" then
    if self:inWorldArea(data.y) then
      local i = self:tileAt(data.x, data.y)
      if i then
        self:tap(i)
      end
    end
  elseif name == "context" then
    if self:inWorldArea(data.y) then
      self.selected = self:tileAt(data.x, data.y) -- inspect only
    end
  elseif name == "speed" then
    self:cycleSpeed()
  elseif name == "routine" then
    self:startRoutine()
  elseif name == "skipNight" then
    self:skipNight()
  elseif name == "cancel" then
    if self.palette then
      self.palette = nil
      self:layout()
    elseif self.placeCard then
      self.placeCard = nil
      self:layoutCard()
    elseif self.planStart then
      self.planStart = nil
    elseif self.mode ~= "act" then
      self:setHand(self.seed, nil)
    else
      self:openMenu()
    end
  else
    return false
  end
  return true
end

-- Drawing --------------------------------------------------------------------------------

local function outlineTile(camera, i, grid, color, width)
  local x, y = Grid.coords(grid, i)
  local wx, wy = camera:tileToWorld(x, y)
  local z = camera:zoom()
  love.graphics.setColor(color)
  love.graphics.setLineWidth((width or 1) / z)
  love.graphics.rectangle("line", wx + 0.5 / z, wy + 0.5 / z, camera.tileSize - 1 / z, camera.tileSize - 1 / z)
end

function Homestead:drawOverlays()
  local world = self.world
  local grid, camera, tile = world.state.grid, self.camera, self.camera.tileSize
  local hs = Actors.homesteader(world)
  if hs.job and hs.job.task ~= "move" then
    outlineTile(camera, hs.job.target, grid, { 1, 0.9, 0.55, 0.6 })
  end
  if hs.job and #hs.job.path > 0 then
    love.graphics.setColor(1, 1, 1, 0.35)
    for _, i in ipairs(hs.job.path) do
      local x, y = Grid.coords(grid, i)
      love.graphics.rectangle("fill", (x - 0.5) * tile - 1, (y - 0.5) * tile - 1, 2, 2)
    end
  end
  if self.planStart then
    local target = self.hover or self.planStart
    local ax, ay = Grid.coords(grid, self.planStart)
    local bx, by = Grid.coords(grid, target)
    love.graphics.setColor(0.95, 0.88, 0.6, 0.25)
    love.graphics.rectangle(
      "fill",
      (math.min(ax, bx) - 1) * tile,
      (math.min(ay, by) - 1) * tile,
      (math.abs(ax - bx) + 1) * tile,
      (math.abs(ay - by) + 1) * tile
    )
  end
  local visuals = world.tuning.visuals
  if self.mode == "place" and world.registry:get("objects", self.placing).placeOn == "waterTable" then
    -- Wells and pumps only go where the water table is high: tint those tiles while placing one.
    love.graphics.setColor(visuals.waterSpots)
    for i = 1, #grid.terrain do
      if Grid.terrain(world, i).tillable and not world.occupancy[i] and Land.hasWaterTable(world, i) then
        local x, y = Grid.coords(grid, i)
        local wx, wy = camera:tileToWorld(x, y)
        love.graphics.rectangle("fill", wx, wy, tile, tile)
      end
    end
  end
  -- Drip zones: the selected line's, or the one being placed under the pointer.
  local zoneAnchor
  if self.selected then
    local obj, anchor = Grid.object(world, self.selected)
    zoneAnchor = obj and obj.drip and anchor or nil
  end
  if zoneAnchor then
    love.graphics.setColor(visuals.waterZone[Water.dripState(world, zoneAnchor) == "dry" and "dry" or "ok"])
    for _, i in ipairs(Water.dripTiles(world, zoneAnchor)) do
      local x, y = Grid.coords(grid, i)
      local wx, wy = camera:tileToWorld(x, y)
      love.graphics.rectangle("fill", wx, wy, tile, tile)
    end
  elseif self.mode == "place" and self.hover and world.registry:get("objects", self.placing).drip then
    local radius = world.registry:get("objects", self.placing).drip.radius
    local hx, hy = Grid.coords(grid, self.hover)
    love.graphics.setColor(visuals.waterZone.ok)
    for y = hy - radius, hy + radius do
      for x = hx - radius, hx + radius do
        if Grid.inBounds(grid, x, y) then
          local wx, wy = camera:tileToWorld(x, y)
          love.graphics.rectangle("fill", wx, wy, tile, tile)
        end
      end
    end
  end
  -- Machine reach (D65): the selected machine's area, or the one being placed under the pointer.
  local reach, reachColor
  if self.selected then
    local obj, anchor = Grid.object(world, self.selected)
    if obj and obj.machine then
      reach = Machines.areaTiles(world, anchor)
      local unit = Machines.at(world, anchor)
      reachColor = unit and unit.status == "unpowered" and visuals.machine.zoneUnpowered or visuals.machine.zone
    end
  elseif self.mode == "place" and self.hover and world.registry:get("objects", self.placing).machine then
    local r = world.registry:get("objects", self.placing).machine.radius
    local hx, hy = Grid.coords(grid, self.hover)
    reach, reachColor = {}, visuals.machine.zone
    for y = hy - r, hy + r do
      for x = hx - r, hx + r do
        if Grid.inBounds(grid, x, y) then
          reach[#reach + 1] = Grid.index(grid, x, y)
        end
      end
    end
  end
  -- Heater slot (D82): a shelter's own slot when it is selected or being placed, and the sleeping
  -- shelter's slot while a heat source is being placed, so the player sees where a fire counts in full.
  if not reach then
    local slotDef, sx, sy
    if self.selected then
      local obj, anchor = Grid.object(world, self.selected)
      if obj and obj.shelter then
        slotDef = obj
        sx, sy = Grid.coords(grid, anchor)
      end
    elseif self.mode == "place" and self.hover then
      local def = world.registry:get("objects", self.placing)
      if def.shelter then
        slotDef = def
        sx, sy = Grid.coords(grid, self.hover)
      elseif def.heatSource or (def.sink and def.sink.effects and def.sink.effects.warmthPerKwh) then
        local anchor, bed = Shelter.best(world)
        if anchor then
          slotDef = bed
          sx, sy = Grid.coords(grid, anchor)
        end
      end
    end
    if slotDef then
      reach, reachColor = Shelter.slotTiles(world, slotDef, sx, sy), visuals.shelter.zone
    end
  end
  if reach and #reach > 0 then
    love.graphics.setColor(reachColor)
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, i in ipairs(reach) do
      local x, y = Grid.coords(grid, i)
      local wx, wy = camera:tileToWorld(x, y)
      love.graphics.rectangle("fill", wx, wy, tile, tile)
      minX, minY, maxX, maxY = math.min(minX, wx), math.min(minY, wy), math.max(maxX, wx + tile), math.max(maxY, wy + tile)
    end
    -- A solid edge so the reach reads over crops and soil as well as grass.
    local edge = { reachColor[1], reachColor[2], reachColor[3], 0.9 }
    love.graphics.setColor(edge)
    love.graphics.setLineWidth(1 / camera:zoom())
    love.graphics.rectangle("line", minX, minY, maxX - minX, maxY - minY)
  end
  -- Buildings waiting for the way to be cleared (D79): a faint ghost with an accent outline on the footprint.
  for _, order in ipairs(Placement.orders(world)) do
    local def = world.registry:get("objects", order.object)
    local sprite = Assets.sprite(order.object)
    local x, y = Grid.coords(grid, order.tile)
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.draw(sprite.image, sprite.quad, (x - 1) * tile, (y - 1 + (def.footprintH or 1)) * tile - sprite.h)
    for _, t in ipairs(Grid.footprintTiles(grid, def, x, y)) do
      outlineTile(camera, t, grid, order.why and theme.colors.danger or theme.colors.accent, 2)
    end
  end
  local target = self.mode == "place" and (self.placeCard and self.placeCard.kind == "confirm" and self.placeCard.tile or self.hover)
  if target then
    -- Ghost of the object being placed: green where it fits now, amber where trees, rocks or crops must go
    -- first (those tiles are outlined: orange to clear, red to remove), red where it can't go.
    local def = world.registry:get("objects", self.placing)
    local sprite = Assets.sprite(self.placing)
    local x, y = Grid.coords(grid, target)
    local preview = Placement.preview(world, self.placing, target)
    if not preview.ok then
      love.graphics.setColor(1, 0.45, 0.45, 0.7)
    elseif preview.immediate then
      love.graphics.setColor(0.6, 1, 0.6, 0.7)
    else
      love.graphics.setColor(1, 0.8, 0.4, 0.7)
    end
    local bottom = (y - 1 + (def.footprintH or 1)) * tile
    love.graphics.draw(sprite.image, sprite.quad, (x - 1) * tile, bottom - sprite.h)
    if preview.ok then
      for _, c in ipairs(preview.clear) do
        outlineTile(camera, c.anchor, grid, theme.colors.accent, 2)
      end
      for _, t in ipairs(preview.tiles) do
        local status = Crops.tileStatus(world, t)
        if status.crop or status.plan then
          outlineTile(camera, t, grid, theme.colors.danger, 2)
        end
      end
    end
  end
  if self.hover then
    outlineTile(camera, self.hover, grid, { 1, 1, 1, 0.35 })
  end
  -- The selection outline is drawn over the graded world (Renderer:drawSelection, D85).
end

function Homestead:drawTopBar(view)
  local world = self.world
  local ui = self.app.ctx.tuning.ui
  love.graphics.setColor(theme.colors.panel)
  love.graphics.rectangle("fill", 0, 0, view.w, self.topH)
  local now = Calendar.now(world)
  local hour = math.floor(now.hour)
  local minute = math.floor((now.hour - hour) * 60)
  local season = now.season:gsub("^%l", string.upper)
  local date = string.format("Day %d · %s · %02d:%02d", now.dayOfSeason, season, hour, minute)
  local _, th = Text.measure(date, "body")
  Text.draw(date, 8, math.floor((self.topRowH - th) / 2), { size = "body" })
  -- Stats sit beside the date, or on their own row under it when the view is too narrow.
  local x, rowTop, room
  if self.statRow then
    x, rowTop, room = ui.barPadding, self.topRowH, view.w - 2 * ui.barPadding
  else
    x, rowTop, room = ui.statsAfterDate, 0, view.w - ui.menuWidth - ui.log.buttonWidth - 2 - ui.statsAfterDate - ui.barPadding
  end
  local rowH = self.statRow and ui.statRowHeight or self.topRowH
  local gap = self:statsWidth(ui.statGap) <= room and ui.statGap or ui.statMinGap
  for _, s in ipairs(self:stats()) do
    local sprite = Assets.sprite(s[1])
    local y = rowTop + math.floor((rowH - sprite.h) / 2)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(sprite.image, sprite.quad, x, y)
    Text.draw(s[2], x + sprite.w + ui.statIconGap, y + 1, { size = "small", color = s[3] })
    x = x + sprite.w + ui.statIconGap + Text.measure(s[2], "small") + gap
  end
end

--- The tap targets of the stat chips, { { id, x, y, w, h } }: each chip plus the gap after it, at least
--- the minimum touch size tall and wide, so a finger can hit one (D72, #158). Laid out exactly like
--- drawTopBar draws the strip, so a test can check them without a canvas.
function Homestead:chipRects()
  local view = self.app.view
  local ui = self.app.ctx.tuning.ui
  local minSize = self.app.ctx.tuning.input.minTouchTarget
  local x, rowTop, room
  if self.statRow then
    x, rowTop, room = ui.barPadding, self.topRowH, view.w - 2 * ui.barPadding
  else
    x, rowTop, room = ui.statsAfterDate, 0, view.w - ui.menuWidth - ui.log.buttonWidth - 2 - ui.statsAfterDate - ui.barPadding
  end
  local rowH = self.statRow and ui.statRowHeight or self.topRowH
  local gap = self:statsWidth(ui.statGap) <= room and ui.statGap or ui.statMinGap
  local rects = {}
  for _, s in ipairs(self:stats()) do
    local width = Assets.sprite(s[1]).w + ui.statIconGap + Text.measure(s[2], "small")
    local w = math.max(minSize, width + gap)
    local h = math.max(minSize, rowH)
    rects[#rects + 1] = {
      id = s.id,
      x = x - (w - width) / 2,
      y = rowTop + (rowH - h) / 2,
      w = w,
      h = h,
    }
    x = x + width + gap
  end
  return rects
end

--- The chip id under a point, or nil.
function Homestead:chipAt(x, y)
  for _, r in ipairs(self:chipRects()) do
    if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
      return r.id
    end
  end
  return nil
end

--- Open the explanation card for a chip: what it is, its unit, its value in plain words, what moves it,
--- and a shortcut to the panel that deals with it (D72, #158).
function Homestead:openChip(id)
  local world, app = self.world, self.app
  local card = ChipText.card(world, id)
  world.events:emit("hud.chipOpened", { chip = id }) -- retires the "tap a chip" tip (D89, #186)
  local more
  if card.shortcut then
    local panel = card.shortcut.panel
    more = {
      label = card.shortcut.label,
      onPress = function()
        self:openPanel(panel)
      end,
    }
  end
  app:push(require("src.scenes.notice").new({
    title = card.title,
    headline = card.headline,
    message = card.message,
    okLabel = "Got it",
    more = more,
  }))
end

--- Open a panel by name from a shortcut: "pantry" | "power" | "catalog" | "truck" | "load" | "journal".
function Homestead:openPanel(name)
  local world, app = self.world, self.app
  if name == "pantry" then
    app:push(require("src.scenes.pantry").new(world))
  elseif name == "power" then
    self:openPower()
  elseif name == "catalog" then
    app:push(require("src.scenes.catalog").new(world, self:toaster()))
  elseif name == "truck" then
    app:push(require("src.scenes.truck").new(world, self:toaster()))
  elseif name == "load" then
    app:push(require("src.scenes.load").new(world, self:toaster()))
  elseif name == "journal" then
    app:push(require("src.scenes.journal").new(world, self:toaster()))
  else
    error("unknown panel " .. tostring(name))
  end
end

-- Storage pills (D59): which stores are full, and what is being held back for lack of room.
-- Returns { { text, color } } in the same shape as the weather pills; empty when all is well.
function Homestead:storageNotes()
  local world = self.world
  local notes, full = {}, {}
  for _, res in ipairs(world.registry:all("resources")) do
    -- A full coop is not a warning (it only holds new hens at the gate), so hens are left out.
    if res.id ~= "water" and res.category ~= "animal" and Ledger.isFull(world, res.id) then
      full[#full + 1] = res.name
    end
  end
  if #full > 0 then
    notes[#notes + 1] = { "Full: " .. table.concat(full, ", "), theme.colors.danger }
  end
  local held = Market.heldOrders(world)
  if #held > 0 then
    local names = {}
    for _, h in ipairs(held) do
      names[#names + 1] = world.registry:get("catalog", h.item).name
    end
    notes[#notes + 1] = { "Order waiting for room: " .. table.concat(names, ", ") .. " · cancel in Catalog", theme.colors.accent }
  end
  for _, batch in ipairs(Processing.blockedBatches(world)) do
    notes[#notes + 1] = {
      string.format("%d %s waiting in the station for room", batch.count, world.registry:get("resources", batch.output).name),
      theme.colors.accent,
    }
  end
  return notes
end

-- Winter forecast under the top bar, from autumn on (GDD §4.1); loud during the cold snap.
function Homestead:drawForecast()
  local world = self.world
  -- The weather pill comes first: today and the days ahead (D51).
  local lines = { { "Weather: " .. Forecast.weather(world), theme.colors.text } }
  -- Threats the player has been warned of (D67): amber while coming, red while they are on.
  for _, t in ipairs(Forecast.threats(world)) do
    lines[#lines + 1] = { t[1], t[2] and theme.colors.danger or theme.colors.accent }
  end
  if Weather.isColdSnap(world) then
    lines[#lines + 1] = { "Cold snap", theme.colors.danger }
  else
    local summary = Forecast.summary(world)
    if summary then
      local frozen = Weather.isFrozen(world)
      lines[#lines + 1] = { (frozen and "This winter: " or "Forecast: ") .. summary, theme.colors.accent }
    end
  end
  -- Winter readiness (D70, #166): fuel and food against the winter ahead; tap it for the details.
  local readyText, readyColor = AlertText.readinessPill(world)
  if readyText then
    lines[#lines + 1] = { readyText .. " (tap)", readyColor, tag = "readiness" }
  end
  for _, line in ipairs(self:storageNotes()) do
    lines[#lines + 1] = line
  end
  local y = self.topH + 4
  self.readinessHit = nil
  for _, line in ipairs(lines) do
    local text, color = line[1], line[2]
    local w = Text.measure(text, "small") + 12
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 4, y, w, 14, 3, 3)
    Text.draw(text, 4, y + 2, { size = "small", width = w, align = "center", color = color })
    if line.tag == "readiness" then
      -- A finger-sized target around the pill (it is 14 px tall, the minimum is tuning.input.minTouchTarget).
      local grow = math.max(0, (self.app.ctx.tuning.input.minTouchTarget - 14) / 2)
      self.readinessHit = { x = 0, y = y - grow, w = w + 8, h = 14 + 2 * grow }
    end
    y = y + 16
  end
  self.forecastBottom = y -- the sleep banner sits below the pills, so they never overlap on a narrow view
end

function Homestead:drawBottomBar(view)
  love.graphics.setColor(theme.colors.panel)
  love.graphics.rectangle("fill", 0, view.h - self.bottomH, view.w, self.bottomH)
end

--- "5 h to morning" / "40 min to morning" while sleeping (D56).
function Homestead:untilMorningText()
  local hours = Sleep.hoursUntilMorning(self.world)
  if hours < 1 then
    return string.format("%d min to morning", math.max(1, math.ceil(hours * 60)))
  end
  return string.format("%d h to morning", math.ceil(hours))
end

--- A centred pill under the top bar while the homesteader sleeps: what is happening, how long
--- is left and how fast time is passing (D56). The Skip night button sits in the control column.
function Homestead:drawSleepBanner(view)
  if not self.session:sleeping() then
    return
  end
  local speed = self.session:effectiveSpeed()
  local text = string.format("Zzz  Sleeping · %s · %gx", self:untilMorningText(), speed)
  if speed == 0 then
    text = "Sleeping · paused"
  end
  local w, h = Text.measure(text, "body")
  w = w + 20
  local x, y = math.floor((view.w - w) / 2), math.max(self.topH + 6, (self.forecastBottom or 0) + 2)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x, y, w, h + 8, 6, 6)
  Text.draw(text, x, y + 4, { size = "body", width = w, align = "center", color = theme.colors.accent })
end

--- One line saying what the tool in hand does on the next tap, or nil for the empty hand (D72, #168).
--- Text comes from tuning.ui.captions.
function Homestead:captionText()
  local world, c = self.world, self.app.ctx.tuning.ui.captions
  local function crop(id)
    return world.registry:get("crops", id).name
  end
  if self.mode == "place" and self.placing then
    return string.format(c.place, world.registry:get("objects", self.placing).name:lower())
  elseif self.mode == "plan" then
    return self.seed and string.format(c.planSeed, crop(self.seed)) or c.planClear
  elseif self.tool == "rod" then
    return c.rod
  elseif self.tool == "untill" then
    return c.untill
  elseif self.seed then
    return string.format(c.seed, crop(self.seed))
  end
  return nil
end

--- The routine badge's text and colour: what the homesteader is doing and, while the player is in
--- charge, when the routine would take over (D72, #168).
function Homestead:badgeText()
  local b = self.app.ctx.tuning.ui.badges
  if Actors.homesteader(self.world).asleep then
    return b.asleep, theme.colors.textDim
  elseif self.session:effectiveSpeed() == 0 then -- also true in town (D78)
    return b.paused, theme.colors.accent
  elseif self.world.control == "idle" then
    return b.running, theme.colors.accent
  elseif not self.session:canStartRoutine() then
    -- Bedtime (D35): the routine rests too, so a countdown would never finish.
    return b.resting, theme.colors.textDim
  end
  local remaining = self:takeoverDelay() - self.app.ctx.input:idleSeconds()
  return string.format(b.countdown, math.max(0, math.ceil(remaining))), theme.colors.textDim
end

--- The status pills just above the toolbar: the tool caption at the left and the routine badge at the
--- right. When both do not fit side by side the caption rides one row higher. Sets self.captionTop, the
--- y of the caption's top (the tile card sits above it), or nil without a caption.
function Homestead:drawPills(view)
  local ui = self.app.ctx.tuning.ui
  local h = ui.pillHeight
  local rowY = view.h - self.bottomH - ui.pillGap - h
  local badge, color = self:badgeText()
  local bw = Text.measure(badge, "small") + 12
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", view.w - bw - 4, rowY, bw, h, 3, 3)
  Text.draw(badge, view.w - bw - 4, rowY + 2, { size = "small", width = bw, align = "center", color = color })
  self.captionTop = nil
  local caption = self:captionText()
  if caption then
    local cw = math.min(Text.measure(caption, "small") + 12, view.w - 8)
    local cy = rowY
    if cw + bw + 12 > view.w then
      cy = rowY - h - ui.pillGap
    end
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 4, cy, cw, h, 3, 3)
    Text.draw(caption, 4, cy + 2, { size = "small", width = cw, align = "center", color = theme.colors.text })
    self.captionTop = cy
  end
end

function Homestead:tileInfo(i)
  local world = self.world
  local grid = world.state.grid
  local lines = {}
  local queued = Placement.orderAt(world, i)
  if queued then
    lines[#lines + 1] = string.format(self.app.ctx.tuning.ui.placement.orderTitle, world.registry:get("objects", queued.object).name)
  end
  local terrain = Grid.terrain(world, i)
  lines[#lines + 1] = world.state.fields.tilled[i] and "Tilled soil" or terrain.name
  if terrain.tillable then
    lines[#lines + 1] = string.format("Soil %d%%", math.floor(grid.soil[i] * 100 + 0.5))
    if Land.hasWaterTable(world, i) and not world.occupancy[i] then
      local shallow = Land.waterTable(world, i) >= world.tuning.water.table.shallow
      lines[#lines + 1] = shallow and "Water table high: dig here" or "Water table: wells work"
    end
  end
  local obj, anchor = Grid.object(world, i)
  if obj then
    lines[#lines + 1] = obj.name
    if obj.battery then
      lines[#lines + 1] = string.format("Battery %.1f / %d kWh", Power.charge(world, anchor), obj.battery)
    end
    if obj.source then
      lines[#lines + 1] = string.format("Making %.2f / %g kW", Power.outputOf(world, anchor), obj.source.peak)
    end
    if obj.machine then
      local info = Machines.info(world, anchor)
      local status = {
        working = "Working",
        starting = "Working",
        slow = string.format("Slow: power %d%%", math.floor(info.ratio * 100 + 0.5)),
        unpowered = "NO POWER: crops wait",
        full = info.full and (world.registry:get("resources", info.full).name .. " store full") or "Store full",
        idle = "Idle: nothing ripe",
        off = "Switched off",
      }
      lines[#lines + 1] = status[info.status]
      lines[#lines + 1] = string.format("Reach %d · %g kW working", info.radius, info.draw)
      lines[#lines + 1] = string.format("Picked %d this run", info.done)
    elseif obj.sink then
      local state = Power.sinkState(world, anchor)
      local ratio = math.floor(Power.sinkRatio(world, anchor) * 100 + 0.5)
      lines[#lines + 1] = state == "ok" and "Powered" or state == "short" and string.format("Short of power (%d%%)", ratio) or state == "off" and "Switched off" or "Idle"
    end
    if obj.waterSource then
      if obj.waterSource.stored then
        local units, capacity = Water.stored(world)
        local low = Water.fraction(world) < world.tuning.water.lowFraction
        lines[#lines + 1] = string.format("Water %d / %d%s", math.floor(units), capacity, low and " (low)" or "")
      else
        lines[#lines + 1] = "Fills the bucket here"
      end
    end
    if obj.placeOn == "waterTable" then
      lines[#lines + 1] = string.format("Water table %d%%", math.floor(Land.waterTable(world, anchor) * 100 + 0.5))
    end
    if obj.pump then
      local mode = Water.pumpState(world, anchor)
      local text = {
        pumping = string.format("Pumping %g/h", obj.pump.rate),
        slow = "Pumping slowly",
        nopower = "No power: not pumping",
        full = "Cistern full",
        nocistern = "Needs a cistern",
      }
      lines[#lines + 1] = text[mode]
    end
    if obj.drip then
      local mode = Water.dripState(world, anchor)
      local thirsty = Water.dripThirsty(world, anchor)
      if mode == "dry" then
        lines[#lines + 1] = "DRY: cistern empty"
      elseif mode == "frozen" then
        lines[#lines + 1] = "Frozen ground: idle"
      else
        lines[#lines + 1] = "Watering its zone"
      end
      if thirsty > 0 then
        lines[#lines + 1] = string.format("%d thirsty crops in zone", thirsty)
      end
    end
    if obj.station then
      local batch = Processing.batch(world, anchor)
      if batch and batch.blocked then
        local recipe = world.registry:get("recipes", batch.recipe)
        lines[#lines + 1] = string.format("%s done · %d waiting for storage room", recipe.name, batch.count)
      elseif batch then
        local hours = batch.remaining / (world.tuning.time.dayLength / 24)
        local recipe = world.registry:get("recipes", batch.recipe)
        lines[#lines + 1] = string.format("%s %d · %.1fh left", recipe.name, batch.count, hours)
      else
        lines[#lines + 1] = "Idle"
      end
    end
    if obj.stand then
      local cap, today = Stand.cap(world), Stand.todayCap(world)
      lines[#lines + 1] = today < cap and string.format("Up to %d today (cap %d)", today, cap) or string.format("Sells up to %d a day", cap)
      lines[#lines + 1] = string.format("Pays %d%% of town price", math.floor(world.tuning.stand.priceFraction * 100 + 0.5))
      local last = Stand.last(world)
      if last then
        lines[#lines + 1] = string.format("Day %d: %d sold, $%d", last.day, last.units, last.earned)
      elseif select(2, Food.surpluses(world)) == 0 then
        lines[#lines + 1] = "Nothing spare to sell"
      else
        lines[#lines + 1] = "No sales yet"
      end
    end
    if obj.coop then
      local flock = Animals.info(world)
      lines[#lines + 1] = string.format("Hens %d / %d", flock.hens, flock.housing)
      lines[#lines + 1] = string.format("Nest %d / %d eggs", flock.nest, flock.nestCap)
      if flock.hens > 0 then
        local days = flock.feedDays == math.huge and "" or string.format(" · %.0fd", flock.feedDays)
        lines[#lines + 1] = string.format("Feed %.0f / %d%s", flock.feed, flock.feedCap, days)
        lines[#lines + 1] = string.format("Water %.1f / %d", flock.water, flock.waterCap)
        if flock.hungryDays > 0 or flock.thirstyDays > 0 then
          lines[#lines + 1] = flock.thirstyDays > 0 and "Dry: tend the coop" or "Hungry: add feed"
        end
      end
      lines[#lines + 1] = string.format("Fox guard %d%%", math.floor(flock.guard * 100 + 0.5))
    end
    if obj.pen then
      local herd = Animals.goatInfo(world)
      lines[#lines + 1] = string.format("Goats %d / %d", herd.goats, herd.housing)
      lines[#lines + 1] = string.format("Pail %d / %d milk", herd.pail, herd.pailCap)
      if herd.goats > 0 then
        local days = herd.feedDays == math.huge and "" or string.format(" · %.0fd", herd.feedDays)
        lines[#lines + 1] = string.format("Hay %.0f / %d%s", herd.feed, herd.feedCap, days)
        lines[#lines + 1] = string.format("Water %.1f / %d", herd.water, herd.waterCap)
        if herd.hungryDays > 0 or herd.thirstyDays > 0 then
          lines[#lines + 1] = herd.thirstyDays > 0 and "Dry: tend the pen" or "Hungry: add hay"
        end
      end
      lines[#lines + 1] = string.format("Coyote guard %d%%", math.floor(herd.guard * 100 + 0.5))
    end
    if obj.heatSource then
      lines[#lines + 1] = string.format("Heat x%.1f · needs %d a night", obj.heatSource, Needs.warmthNeeded(world))
    end
    if obj.heatSource or (obj.sink and obj.sink.effects and obj.sink.effects.warmthPerKwh) then
      local reach = Shelter.heatReach(world, anchor)
      lines[#lines + 1] = reach >= 1 and "Beside the bed: full heat" or string.format("Too far from bed: %d%%", math.floor(reach * 100 + 0.5))
    end
    if obj.shelter then -- the shelter ladder (D82)
      lines[#lines + 1] = obj.insulation < 1 and string.format("Keeps heat: %d%% less fuel", math.floor((1 - obj.insulation) * 100 + 0.5)) or "Keeps no heat"
      lines[#lines + 1] = string.format("Rest: %+d%% condition", math.floor((obj.recovery - 1) * 100 + 0.5))
      lines[#lines + 1] = string.format("Heater slot: %d tiles", obj.heaterRadius or 0)
      if (obj.studySpeed or 0) > 0 then
        lines[#lines + 1] = string.format("Desk: study +%d%%", math.floor(obj.studySpeed * 100 + 0.5))
      end
    end
  end
  local crop = world.state.crops[i]
  if crop then
    local def = world.registry:get("crops", crop.id)
    if Crops.isMature(crop) then
      lines[#lines + 1] = def.name .. ": ready"
    else
      lines[#lines + 1] = string.format("%s: %d%%%s", def.name, math.floor(crop.growth * 100), crop.moisture > 0 and "" or ", thirsty")
    end
    lines[#lines + 1] = AlertText.cropFrostLine(world, crop) -- days to the freeze (D70, #165)
  elseif world.state.fields.plan[i] then
    local planned = world.state.fields.plan[i]
    lines[#lines + 1] = "Planned: " .. world.registry:get("crops", planned).name
    local risk = Crops.frostRisk(world, planned)
    if risk then
      lines[#lines + 1] = risk.level == "late" and "Too late: frost first" or "Close to frost"
    end
  end
  return lines
end

function Homestead:drawInfo(view)
  local info -- the tile card's rectangle, when it is up (a wide toast keeps clear of it)
  if self.selected then
    local lines = self:tileInfo(self.selected)
    local h = #lines * 11 + 8
    local y = (self.card and self.card.y or self.captionTop or view.h - self.bottomH) - h - 4 -- above the tip card (or the tool caption) when one is up
    local w = 132
    for _, line in ipairs(lines) do
      w = math.max(w, Text.measure(line, "small") + 14) -- a long line widens the card rather than spilling out
    end
    Draw.panel(4, y, w, h)
    for n, line in ipairs(lines) do
      Text.draw(line, 10, y + 4 + (n - 1) * 11, { size = "small", color = n == 1 and theme.colors.text or theme.colors.textDim })
    end
    info = { x = 4, y = y, w = w, h = h }
  end
  if self.toast then
    -- A toast wider than the view wraps onto more lines (D70), growing upward from the usual line.
    local maxW = view.w - 16
    local w = math.min(Text.measure(self.toast.text, "body") + 16, maxW)
    local textH = Text.wrappedHeight(self.toast.text, "body", w - 16)
    local h = math.max(18, textH + 8)
    local ui = self.app.ctx.tuning.ui
    local x, y = (view.w - w) / 2, view.h - self.bottomH - ui.pillHeight - ui.pillGap - 4 - h -- clear of the status pills
    if info and x < info.x + info.w and y + h > info.y then
      y = info.y - 4 - h -- a wide toast on a narrow view rides above the tile card instead of covering it
    end
    love.graphics.setColor(0, 0, 0, 0.55 * math.min(1, self.toast.time * 3))
    love.graphics.rectangle("fill", x, y, w, h, 3, 3)
    Text.draw(self.toast.text, x + 8, y + 4, { size = "body", width = w - 16, align = "center" })
    -- The tap target: at least a finger tall, so a thin toast is still easy to hit.
    local minSize = self.app.ctx.tuning.input.minTouchTarget
    local grow = math.max(0, minSize - h)
    self.toastHit = { x = x, y = y - grow / 2, w = w, h = h + grow }
  else
    self.toastHit = nil
  end
end

function Homestead:draw()
  local view = self.app.view
  local tint, light, daylight = self.renderer:lighting()

  -- World -> canvas -> colour grade -> screen
  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.clear(0, 0, 0, 1)
  self.camera:attach(view)
  local x1, y1, x2, y2 = self.camera:visibleTiles(view)
  self.renderer:draw(self.session.clock:alpha(), { x1, y1, x2, y2 }, daylight)
  self:drawOverlays()
  love.graphics.pop()
  love.graphics.setCanvas()
  love.graphics.origin()
  local haze = self.renderer:heatHaze(self.camera, view, { x1, y1, x2, y2 }, daylight)
  self.renderer:drawGraded(self.canvas, tint, light, view.scale * self.camera:zoom(), haze)
  love.graphics.pop()
  -- Night lights, fireflies, dust and the selection outline sit over the graded world, in world space again.
  love.graphics.push("all")
  self.camera:attach(view)
  self.renderer:drawLights({ x1, y1, x2, y2 }, daylight)
  self.renderer:drawAmbient({ x1, y1, x2, y2 }, daylight)
  if self.selected then
    self.renderer:drawSelection(self.selected, view.scale * self.camera:zoom())
  end
  love.graphics.pop() -- the camera transform
  love.graphics.pop() -- the saved graphics state
  local z = self.camera:zoom() -- rain is built on the world's art-pixel grid, so it scales with the zoom (#193)
  self.renderer:drawRain(view, {
    zoom = z,
    ox = (view.w / 2 - self.camera.x * z) % z,
    oy = (view.h / 2 - self.camera.y * z) % z,
    wx = math.ceil(self.camera.x - view.w / 2 / z), -- the world art pixel at the grid's first column and row, to place splashes on the ground
    wy = math.ceil(self.camera.y - view.h / 2 / z),
  })

  -- HUD (not graded)
  ActionRing.draw(self.world, self.camera, view, { top = self.topH, bottom = view.h - self.bottomH })
  self:drawTopBar(view)
  self:drawForecast()
  self:drawBottomBar(view)
  self:drawPills(view)
  self:drawSleepBanner(view)
  self:drawInfo(view)
  if self.paletteRect then
    local r = self.paletteRect
    Draw.panel(r.x, r.y, r.w, r.h)
    self.paletteList:begin(self.app.view.scale)
    self.paletteButtons:draw()
    self.paletteList:finish()
    if r.scrolls then
      local ui = self.app.ctx.tuning.ui
      local v = r.view
      self.paletteList:drawThumb(ui.scrollBarWidth, ui.scrollHintHeight, { x = r.x + r.w - ui.buttonGap, y = v.y, w = 0, h = v.h })
    end
  end
  self.buttons:draw()
  self:drawCard()
end

function Homestead:debugLines()
  local c = self.camera
  local hs = Actors.homesteader(self.world)
  local job = hs.job and string.format("%s@%d (%.1fs)", hs.job.task, hs.job.target, hs.job.progress) or "-"
  local priorities = {}
  for _, e in ipairs(self.world.state.priorities) do
    priorities[#priorities + 1] = e.category .. (e.enabled and "" or "(off)")
  end
  return {
    string.format("camera: %.0f,%.0f zoom=%dx  control=%s mode=%s", c.x, c.y, c:zoom(), self.world.control, self.mode),
    string.format("homesteader: %.1f,%.1f bucket=%d job=%s", hs.x, hs.y, hs.bucket, job),
    "routine: " .. table.concat(priorities, " > "),
  }
end

return Homestead
