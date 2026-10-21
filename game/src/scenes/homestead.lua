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
local Established = require("src.sim.systems.established")
local Events = require("src.sim.systems.events")
local EventCard = require("src.ui.event_card")
local EventText = require("src.ui.event_text")
local Notices = require("src.ui.notices")
local Footing = require("src.sim.systems.footing")
local FellingText = require("src.ui.felling_text")
local FootingText = require("src.ui.footing_text")
local Goal = require("src.sim.systems.goal")
local GoalText = require("src.ui.goal_text")
local Status = require("src.sim.systems.status")
local StatusText = require("src.ui.status_text")
local Ftue = require("src.sim.systems.ftue")
local Marks = require("src.sim.systems.marks")
local Placement = require("src.sim.systems.placement")
local PlaceCard = require("src.ui.place_card")
local Highlight = require("src.ui.highlight")
local PlaceText = require("src.ui.place_text")
local RangePreview = require("src.ui.range_preview")
local Journal = require("src.sim.systems.journal")
local Weather = require("src.sim.systems.weather")
local Nightly = require("src.sim.systems.nightly")
local AlertText = require("src.ui.alert_text")
local Forecast = require("src.ui.forecast")
local NightText = require("src.ui.night_text")
local Dusk = require("src.sim.systems.dusk")
local Readiness = require("src.sim.systems.readiness")
local Tonight = require("src.ui.tonight")
local TonightCard = require("src.ui.tonight_card")
local TonightText = require("src.ui.tonight_text")
local SpoilText = require("src.ui.spoil_text")
local Run = require("src.meta.run")
local Stats = require("src.sim.stats")
local Power = require("src.sim.systems.power")
local Land = require("src.sim.systems.land")
local Water = require("src.sim.systems.water")
local Processing = require("src.sim.systems.processing")
local Market = require("src.sim.systems.market")
local Sandbox = require("src.sim.systems.sandbox")
local Stand = require("src.sim.systems.stand")
local Routine = require("src.sim.systems.routine")
local Tasks = require("src.sim.systems.tasks")
local Cat = require("src.sim.systems.cat")
local Animals = require("src.sim.systems.animals")
local Finds = require("src.sim.systems.finds")
local Machines = require("src.sim.systems.machines")
local Wardrobe = require("src.sim.systems.wardrobe")
local WardrobePreview = require("src.render.wardrobe_preview")
local WardrobeScene = require("src.scenes.wardrobe")
local WardrobeState = require("src.ui.wardrobe_state")
local WardrobeText = require("src.ui.wardrobe_text")
local Renderer = require("src.render.world_renderer")
local Sampler = require("src.audio.sampler")
local ActionRing = require("src.render.action_ring")
local Assets = require("src.render.assets")
local Book = require("src.scenes.book")
local Books = require("src.ui.books")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Plate = require("src.ui.plate")
local Sketch = require("src.render.sketch")
local ChipText = require("src.ui.chip_text")
local ChipStrip = require("src.ui.chip_strip")
local Hud = require("src.ui.hud")
local Dissolve = require("src.render.dissolve")
local LensCard = require("src.ui.lens_card")
local Motion = require("src.ui.motion")
local LensRenderer = require("src.render.lens")
local LensState = require("src.ui.lens")
local Settings = require("src.core.settings")
local Icons = require("src.ui.icons")
local ToolWheel = require("src.ui.tool_wheel")
local ScrollList = require("src.ui.scroll_list")
local MessageLog = require("src.ui.message_log")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Homestead = { name = "homestead", opaque = true }

-- The Hammer's modes (D139): a tap on a building moves, picks up or demolishes it.
local HAMMER_MODES = { move = true, pickup = true, demolish = true }
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
  Books.reset() -- the books open on their first pages in a fresh session (D143)
  WardrobeState.reset() -- and the Wardrobe forgets the draft it was left with (D154)
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
  LensState.forced = nil
  self.lens = LensState.new(tuning.ui.lens) -- the Power and Water lenses (D141, D145)
  self.lensView = LensRenderer.new(self.world)
  self.lensCard = LensCard.new(ctx, self.world)
  self.tonight = Tonight.new() -- the dusk check's card (D161): opens at dusk, dismissible, re-opened from its stamp or T
  self.tonightCard = TonightCard.new(ctx)
  self.tonightAge = 0
  self:lookTonight()
  self.eventCard = EventCard.new(ctx) -- the misfortune event's card (D172): shares the free band with Tonight, one at a time
  self.eventFade = Motion.transition("card")
  self.noticeCurrent, self.noticeOwner = nil, nil
  -- Dissolves (D142): the wheel, the tip card, the tile card and the lens come in and go out through the dither.
  self.wheelFade = Motion.transition("wheel")
  self.cardFade = Motion.transition("card")
  self.infoFade = Motion.transition("card")
  self.lensFade = Motion.transition("lens")
  self.wheelLast = {} -- the wheel's last shown state, kept to draw it dissolving away
  self.paletteButtons = Buttons.new(tuning.input.minTouchTarget)
  local relayout = function()
    self:layout()
  end
  self.paletteLists = {
    tools = ScrollList.new(relayout),
    notebook = ScrollList.new(relayout),
    ledger = ScrollList.new(relayout),
  }
  self.mode = "act" -- "act" | "plan" | "place"
  self.seed = nil -- crop id in hand
  self.tool = nil -- "rod" in hand
  self.placing = nil -- object id being placed
  self.moving = nil -- anchor of the placed object being moved (D98), or nil
  self.toast = nil
  self.toastQueue = {}
  local logCfg = self.app.ctx.tuning.ui.log
  self.world.state.log = self.world.state.log or {}
  self.log = MessageLog.new(logCfg.maxLines, logCfg.coalesceSeconds, self.world.state.log) -- what the toasts said (D90, #167); kept in the run state so it is saved (D120, #224)
  self.held = {} -- toasts that came in while asleep, shown in the morning (D70)
  self.newClothes = {} -- names of garments earned and not yet announced; one toast says them all (D155)
  self.frostTold = {} -- crop id -> calendar day its won't-ripen warning last showed (D70, #165)
  self:subscribe()
  WardrobePreview.dressWorld(self.world.registry, Wardrobe.dressed(self.world)) -- the figure wears today's outfit from the first frame
  self:attachAudio()
end

--- Hand the audio service this world: it listens to the event bus itself and reads the weather look,
--- the pause state and the view through this snapshot (D100). Read-only.
function Homestead:attachAudio()
  local tile = self.world.tuning.display.tileSize
  self.app.ctx.audio:attach(self.world, function()
    return Sampler.snapshot({
      world = self.world,
      speed = self.session:effectiveSpeed(),
      fx = self.renderer.fx,
      center = { self.camera.x / tile, self.camera.y / tile },
    })
  end)
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
      if not world.registry:get("catalog", e.item).object then
        self:showToast("Delivered: " .. name("catalog", e.item)) -- a building counts on the Hammer instead (D139)
      end
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
        self:queueToast(
          goats and "The goats ran short of hay. Buy bales or tend the pen."
            or "The hens ran short of feed. Buy a sack or tend the coop."
        )
      elseif e.water then
        self:queueToast(
          goats and "The goats' trough ran dry. Tend the pen." or "The hens' waterer ran dry. Tend the coop."
        )
      end
    end),
    events:on("animals.lost", function(e)
      local animal = e.kind == "goats" and "goat" or "hen"
      self:queueToast(
        e.reason == "thirst" and ("A " .. animal .. " was lost: no water")
          or ("A " .. animal .. " was lost: no " .. (e.kind == "goats" and "hay" or "feed"))
      )
    end),
    events:on("animals.predator", function(e)
      if self.session:sleeping() then
        return -- asleep: it is in the morning report
      end
      local goats = e.kind == "goats"
      if e.stopped then
        self:queueToast(
          goats and "A coyote tried the pen in the night. The fence held."
            or "A fox tried the coop in the night. The door held."
        )
      elseif goats then
        self:queueToast(
          string.format("A coyote got into the pen: lost %d goat%s", e.killed, e.killed == 1 and "" or "s")
        )
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
    -- Idle nudges (D55, D93): shown only while the player is looking at the world. Under a panel they
    -- wait in `pendingHint` and come out when the world is on top again (#120).
    events:on("routine.idleHint", function()
      self:raiseHint("idle")
    end),
    events:on("routine.nothingToDo", function()
      self:raiseHint("nothing")
    end),
    -- The routine laid out the starter field (D61, D88): say so, and how to change it.
    events:on("crop.starterPlanned", function(e)
      self:heldToast(
        "starterPlanned",
        string.format("Routine planned a starter field (%d tiles). Plan field changes it", e.tiles)
      )
    end),
    -- Footing (D162, #341): the gained card is a panel (updateTonight); a slip and the way back get a held toast.
    events:on("footing.slipped", function()
      self:heldToast("footing", FootingText.slippedLine)
    end),
    events:on("footing.regained", function()
      self:heldToast("footing", FootingText.regainedLine)
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
        self:queueToast(
          string.format("%s: %s", what, string.format(p.orderFull, name("resources", e.resource):lower()))
        )
      elseif e.kind == "blocked" then
        self:queueToast(string.format("%s: %s", what, p.orderBlocked))
      else
        self:queueToast(string.format("%s: %s", what, p.orderUnreachable))
      end
    end),
    -- The Untill tool pulled a planted crop (#254).
    events:on("crop.removed", function(e)
      if e.cause == "untill" then
        self:queueToast(string.format(self.app.ctx.tuning.ui.placement.pulledCrop, name("crops", e.crop):lower()))
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
    -- Events (D169, #347; the card is D172, #348): the card is the way in, so an offer only writes the log line (a card
    -- missed behind another is still on record); how it ended gets a toast, and a card that ran out says so.
    events:on("event.offered", function(e)
      local d = world.registry:get("events", e.id)
      self:record(d.title .. ": " .. d.line)
    end),
    events:on("event.chosen", function(e)
      self:newsToast(e.order and string.format(EventText.orderToast, e.label) or e.label)
    end),
    events:on("event.ignored", function(e)
      local text = e.label
      if e.reason == "expired" then
        text = string.format(EventText.ignoredToast, e.label)
      elseif e.reason == "order" then
        text = string.format(EventText.orderToast, e.label)
      end
      self:newsToast(text)
    end),
    events:on("journal.idea", function(e)
      self:newsToast("New idea: " .. Journal.node(world, e.item).name .. " · see the Journal")
    end),
    events:on("needs.depleted", function(e)
      self.failed = e or {}
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
      local news = Forecast.news(world, e.piece)
      if news then
        self:newsToast(news)
      end
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
    events:on("water.dry", function(e)
      local what = e.kind == "sprinkler" and "A sprinkler" or "A drip line"
      self:queueToast(what .. " is dry. Fill the cistern or the crops need hand watering.")
    end),
    events:on("water.restored", function(e)
      self:queueToast((e.kind == "sprinkler" and "Sprinklers are" or "Drip lines are") .. " watering again.")
    end),
    events:on("machine.unpowered", function(e)
      self:queueToast(name("objects", e.kind) .. " has ripe crops but no power")
    end),
    events:on("power.brownout", function(e)
      self:queueToast(
        string.format("Power short: %s at %d%%", Power.tierName(world, e.tier), math.floor(e.ratio * 100))
      )
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
    events:on("wardrobe.unlocked", function(e) -- earned clothes: named in one toast once the homesteader is up
      self.newClothes[#self.newClothes + 1] = world.registry:get("garments", e.id).name
    end),
    events:on(
      "wardrobe.dressed",
      function(e) -- the outfit changed (a Wear that applies now, or a dawn): repaint the figure
        WardrobePreview.dressWorld(world.registry, e.dressed)
        if e.reason == "auto" then -- Auto wore a saved outfit at dawn: say which night it dressed for
          local cfg = self.app.ctx.tuning.ui.wardrobe
          self:heldToast("wardrobe.auto", string.format(cfg.toastAuto, cfg.autoNights[e.night]))
        end
      end
    ),
  }
end

function Homestead:exit()
  self:saveNow()
  self.app.ctx.audio:detach()
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
  self.unfocused = not hasFocus -- an unfocused window is an away player: an event card's ignore window waits (D169)
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
          Book.open(app, "pantry")
        end,
      },
    }))
  else
    -- Ahead of the note the same night may have written, which waits behind it.
    self:urgentToast(SpoilText.summary(world, report))
  end
end

--- The one-time "Established" card (D117, #277): the slot's first Great Winter survived. It waits for the
--- homestead to be on top and the homesteader to be up (a modal open, or asleep, queues it), and the mark's
--- `seen` flag keeps it from ever showing twice on a slot, across saves and later runs.
function Homestead:establishedNews()
  local meta = self.world.meta
  if
    not Established.cardDue(meta)
    or self.session:sleeping()
    or self.app:top() ~= self
    or Finds.pending(self.world)
  then
    return
  end
  Established.cardShown(meta)
  local t = self.app.ctx.tuning.ui.greatWinter
  self:record(t.logLine)
  self.app:push(require("src.scenes.notice").new({
    title = t.cardTitle,
    headline = t.cardHeadline,
    message = t.cardMessage,
    okLabel = t.cardOk,
  }))
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
  local audio = self.app.ctx.audio -- absent in tests that build their own context
  if audio then
    audio:play("toast")
  end
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
  self:openPanel("diary")
end

--- One toast for the garments earned since the last one (several on one dawn read as one), held while the
--- homesteader sleeps like the other news.
function Homestead:announceClothes()
  local names = self.newClothes
  if #names == 0 or self.session:sleeping() then
    return
  end
  self.newClothes = {}
  self:queueToast(WardrobeText.unlockToast(self.app.ctx.tuning.ui.wardrobe, names))
end

--- Open the Wardrobe (the "New clothes" stamp, the C key).
function Homestead:openWardrobe()
  WardrobeScene.open(self.app)
end

function Homestead:toaster()
  return function(text)
    self:showToast(text)
  end
end

-- HUD buttons --------------------------------------------------------------------------

--- The Plan button (D94, #205). A tap turns the tool on, a tap while it is on turns it off; a second tap
--- within `ui.planLatchWindow` seconds of the one that turned it on latches it, so it stays on after each
--- plan (the touch counterpart of holding Shift); a tap while latched unlatches and turns it off.
--- `now` is real seconds (love.timer.getTime in play).
function Homestead:pressPlan(now)
  local ui = self.app.ctx.tuning.ui
  if self.mode == "plan" then
    if not self.planLatch and self.planTapAt and now - self.planTapAt <= ui.planLatchWindow then
      self.planLatch = true
      self.planTapAt = nil
      self:showToast(ui.planLatchToast)
      self:layout()
    else
      self:setHand(self.seed, nil)
    end
    return
  end
  self.mode, self.planStart, self.tool, self.placing, self.moving = "plan", nil, nil, nil, nil
  self.planLatch, self.planTapAt = false, now
  local crops = self.world.registry
  self:showToast(
    self.seed and "Tap two corners to plan " .. crops:get("crops", self.seed).name or "Tap two corners to clear a plan"
  )
  self:layout()
end

function Homestead:setHand(seed, tool)
  self.seed, self.tool, self.mode, self.planStart, self.placing, self.moving = seed, tool, "act", nil, nil, nil
  self.planLatch, self.planTapAt = false, nil
  if self.placeCard and self.placeCard.kind == "confirm" then
    self.placeCard = nil -- leaving Place drops a confirmation that was up (D79)
  end
  self:layout()
  local late = seed and self:frostWarning(seed)
  if late then
    self:showToast(late) -- picking a seed that cannot ripen in time: say so before the first tile (#165)
  end
end

--- The crate (D139): delivered objects waiting to be placed, sorted by id for stability, as { { id, count } }.
--- Items already promised to a queued order are not offered.
function Homestead:crateItems()
  local items = {}
  for id in pairs(self.world.state.inventory.objects) do
    local count = Placement.available(self.world, id)
    if count > 0 then
      items[#items + 1] = { id = id, count = count }
    end
  end
  table.sort(items, function(a, b)
    return a.id < b.id
  end)
  return items
end

--- How many things wait in the crate: the count on the Hammer wedge and the tool badge.
function Homestead:crateCount()
  local n = 0
  for _, item in ipairs(self:crateItems()) do
    n = n + item.count
  end
  return n
end

-- First object waiting in the crate, or nil.
function Homestead:nextPlaceable()
  local first = self:crateItems()[1]
  return first and first.id
end

--- Hold a crate item's ghost for placing (D79 preview and confirm card).
function Homestead:startPlacing(id)
  local def = self.world.registry:get("objects", id)
  self:setHand(nil, nil)
  self.mode, self.placing, self.moving, self.planStart = "place", id, nil, nil
  self:showToast("Tap where the " .. def.name:lower() .. " should go")
  self:layout()
end

-- The resting HUD (GDD §9.4, D137, #293) --------------------------------------------------

--- The vitals the HUD shows: the chip strip's entries without the weather, which sits on the clock (D112
--- chips, the same accessors as their cards). Returns the vitals and the weather entry.
function Homestead:vitalEntries()
  local out, weather = {}, nil
  for _, e in ipairs(ChipStrip.entries(self.world)) do
    if e.id == "weather" then
      weather = e
    else
      out[#out + 1] = e
    end
  end
  return out, weather
end

--- "Day 3 · Spring", the clock's first line.
function Homestead:dateText()
  local now = Calendar.now(self.world)
  return string.format("Day %d · %s", now.dayOfSeason, (now.season:gsub("^%l", string.upper)))
end

--- The pressing-goal line's words, fitted to the view, and its level (0 fine, 1 amber, 2 red; D163, #342).
function Homestead:goalLine(view)
  local ui = self.app.ctx.tuning.ui
  local H = ui.hud
  local maxW = math.min(ui.goal.lineMaxWidth, view.w - 2 * H.pad) - H.stampSize - H.textPad
  local text = GoalText.line(self.goal, maxW, function(s)
    return (Text.measure(s, "small"))
  end)
  return text, GoalText.level(self.goal)
end

--- The status chips under the Condition meter (D167, #346): { { id, label, icon, w } } for the statuses active, in the
--- order applied. The label is the main effect and the days left, or the name and the days when the view is narrow.
function Homestead:statusChips(view)
  local ui = self.app.ctx.tuning.ui
  local H, cfg = ui.hud, ui.status
  local maxW = math.min(cfg.chipMaxWidth, view.w - 2 * H.pad) - H.stampSize - H.textPad
  local out = {}
  for _, st in ipairs(Status.active(self.world)) do
    local label = StatusText.chip(cfg, st, maxW, function(t)
      return (Text.measure(t, "small"))
    end)
    out[#out + 1] = {
      id = st.id,
      label = label,
      icon = StatusText.icon(Assets.has, st),
      w = H.stampSize + Text.measure(label, "small") + H.textPad,
      name = st.name,
    }
  end
  return out
end

--- Open the detail card of a status (a chip's tap): what it does, how long it lasts, what clears it (D167, #346).
function Homestead:openStatus(id)
  self.app:push(require("src.scenes.status").new(self.world, id))
end

--- Open the Progress panel: the goal ladder, Footing, the run's milestones and the gates (D163, #342).
function Homestead:openProgress()
  self.app:push(require("src.scenes.progress").new(self.world))
end

--- The decision stamps due now, in order (D137): { id, icon, label, color, onPress }. Each is something
--- that waits on the player: an idea to pick, a winter that is not covered, a store holding things back, a
--- delivery waiting in the crate.
function Homestead:stampList()
  local world, L = self.world, self.app.ctx.tuning.ui.labels
  local colors = theme.colors
  local list = {}
  if Journal.needsChoice(world) then
    list[#list + 1] = {
      id = "journal",
      icon = "icon_signal_idea",
      label = L.journalStamp,
      color = colors.accent,
      onPress = function()
        self:openPanel("journal")
      end,
    }
  end
  local readyText, readyColor = AlertText.readinessPill(world)
  if readyText and readyColor ~= colors.text then
    list[#list + 1] = {
      id = "readiness",
      icon = "icon_signal_alert",
      label = readyText,
      color = readyColor,
      onPress = function()
        self:openReadiness()
      end,
    }
  end
  local look = self.tonightLook
  if look and self.tonight:stampDue(look.due, look.leads, look.gaps) then
    -- The Tonight card is closed and there is something to see (the evening, or a gap): the stamp brings it back (D161).
    local worst = math.max(look.warmth.level, look.food.level, look.water.level)
    list[#list + 1] = {
      id = "tonight",
      icon = "icon_signal_alert",
      label = look.gaps > 0 and string.format("%s: %d to fix", TonightText.stamp, look.gaps) or TonightText.stamp,
      color = worst >= 2 and colors.danger or worst == 1 and colors.accent or colors.text,
      onPress = function()
        self:toggleTonight()
      end,
    }
  end
  if Events.waiting(world) > 0 and self.noticeOwner ~= "event" then
    -- An event card is waiting behind another card or a panel (its window waits too): the stamp brings it forward.
    list[#list + 1] = {
      id = "event",
      icon = "icon_signal_alert",
      label = EventText.stamp,
      color = colors.accent,
      onPress = function()
        self.noticeCurrent = "event"
      end,
    }
  end
  local notes = self:storageNotes()
  if #notes > 0 then
    list[#list + 1] = {
      id = "storage",
      icon = "icon_signal_alert",
      label = notes[1][1],
      color = notes[1][2],
      onPress = function()
        self:openStorageNotes(notes)
      end,
    }
  end
  local placeable = self.mode ~= "place" and self:nextPlaceable()
  if placeable then
    local def = world.registry:get("objects", placeable)
    list[#list + 1] = {
      id = "delivery",
      icon = "icon_crate",
      label = self:crateCount() > 1 and string.format(L.crateStamp, self:crateCount())
        or string.format(L.deliveryStamp, def.name:lower()),
      color = colors.accent,
      onPress = function()
        self:openHammerRing() -- the crate, with every delivery in it (D139)
      end,
    }
  end
  if Wardrobe.stampDue(world) then
    list[#list + 1] = {
      id = "wardrobe",
      icon = "icon_signal_clothes",
      label = self.app.ctx.tuning.ui.wardrobe.stamp,
      color = colors.accent,
      onPress = function()
        self:openWardrobe() -- opening it answers the stamp
      end,
    }
  end
  return list
end

--- The storage stamp, expanded: every store holding something back (D59, D93).
function Homestead:openStorageNotes(notes)
  local lines = {}
  for _, n in ipairs(notes) do
    lines[#lines + 1] = n[1]
  end
  self.app:push(require("src.scenes.notice").new({
    title = "Storage",
    message = table.concat(lines, "\n"),
    okLabel = "Got it",
  }))
end

--- What the HUD shows that changes its layout; the scene lays out again when this changes.
function Homestead:hudKey()
  local parts = {
    self:dateText(),
    self:speedLabel(),
    self:routineLabel(),
    tostring(self:hintKind()),
    tostring(self.session:timeHeld()),
    self.mode,
    tostring(self.seed),
    tostring(self.tool),
    tostring(self.placing),
    tostring(self.moving),
    tostring(self.palette),
    tostring(self:captionText()),
    tostring(self.world.control),
    tostring(Actors.homesteader(self.world).asleep),
  }
  for _, e in ipairs(ChipStrip.entries(self.world)) do
    parts[#parts + 1] = e.id .. "=" .. e.text .. (e.icons and #e.icons or "")
  end
  for _, s in ipairs(self:stampList()) do
    parts[#parts + 1] = s.id .. ":" .. s.label
  end
  parts[#parts + 1] = "goal:" .. (self:goalLine(self.app.view))
  for _, c in ipairs(self:statusChips(self.app.view)) do
    parts[#parts + 1] = "status:" .. c.id .. ":" .. c.label
  end
  return table.concat(parts, "|")
end

function Homestead:layout()
  local view = self.app.view
  local ui = self.app.ctx.tuning.ui
  self.btnH = view.w < ui.compactWidth and ui.compactButtonHeight or ui.buttonHeight
  self.buttons:clear()
  self.seedButtons = {}
  self:layoutHud(view)
  self:layoutCard()
end

--- The tool in hand as the tool badge shows it: { icon, extra icon or nil, label }.
function Homestead:toolInHand()
  local world, L = self.world, self.app.ctx.tuning.ui.labels
  if self.mode == "place" and self.placing then
    local def = world.registry:get("objects", self.placing)
    local id = "icon_" .. self.placing -- the building in hand; the Hammer's own icon until the crate (#295)
    return Assets.has(id) and id or "icon_crate", nil, (self.moving and L.moving or L.place) .. " " .. def.name:lower()
  elseif HAMMER_MODES[self.tool] then
    local names = { move = L.hammerMove, pickup = L.hammerPickUp, demolish = L.hammerDemolish }
    return "icon_verb_" .. self.tool, nil, names[self.tool]
  elseif self.mode == "plan" then
    return "icon_tool_hoe", self.seed and Icons.packet(self.seed) or nil, L.plan
  elseif self.tool == "rod" then
    return Icons.tool(world, "rod"), nil, L.rod
  elseif self.tool == "untill" then
    return "icon_verb_untill", nil, L.untill
  elseif self.tool == "pail" or self.tool == "axe" then
    return Icons.tool(world, self.tool), nil, L[self.tool]
  elseif self.seed then
    local crop = world.registry:get("crops", self.seed)
    return "icon_tool_hoe", Icons.packet(self.seed), crop.name .. " " .. Ledger.get(world, crop.seed)
  end
  return "icon_tool_hand", nil, L.hand
end

--- Build the resting HUD's plates and the trays that open above them (D137). Placement is pure
--- (src/ui/hud.lua); this decides what the plates are, what they say and what a tap does.
function Homestead:layoutHud(view)
  local world = self.world
  local ui = self.app.ctx.tuning.ui
  local H, L = ui.hud, ui.labels
  local minTouch = self.app.ctx.tuning.input.minTouchTarget
  local inHand = self.mode == "act"
  local function fit(label, min, icon)
    return math.max(min, math.ceil(Text.measure(label, "body")) + ui.controlTextPadding + (icon and 15 or 0))
  end
  -- A press on a tray button closes the tray, does its thing, and lays the HUD out again.
  local function act(fn)
    return function(b)
      self.palette = nil
      fn(b)
      self:layout()
    end
  end

  -- The tools tray (until the tool wheel, #294): Hand, a packet per crop, Rod, Untill, Place, Plan field.
  local tools = {
    {
      id = "hand",
      w = fit(L.hand, ui.buttonWidths.hand, true),
      icon = "icon_tool_hand",
      label = L.hand,
      selected = inHand and not self.seed and not self.tool,
      onPress = act(function()
        self:setHand(nil, nil)
      end),
    },
  }
  for _, crop in ipairs(self:seedCrops()) do
    local button = {
      id = "seed:" .. crop.id,
      w = ui.buttonWidths.seed,
      icon = Icons.packet(crop.id),
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
    w = fit(L.rod, ui.buttonWidths.rod, true),
    icon = Icons.tool(world, "rod"),
    label = L.rod,
    selected = inHand and self.tool == "rod",
    onPress = act(function()
      self:setHand(nil, self.tool ~= "rod" and "rod" or nil)
    end),
  }
  tools[#tools + 1] = {
    id = "untill",
    w = fit(L.untill, ui.buttonWidths.untill, true),
    icon = "icon_verb_untill",
    label = L.untill,
    selected = inHand and self.tool == "untill",
    onPress = act(function()
      self:setHand(nil, self.tool ~= "untill" and "untill" or nil)
    end),
  }
  -- The crate (D139): a Place button per item waiting, or while moving the button that cancels.
  local crate = self.moving and { { id = self.placing } } or self:crateItems()
  for _, item in ipairs(crate) do
    local def = world.registry:get("objects", item.id)
    local label = (self.moving and L.moving or L.place) .. " " .. def.name:lower()
    tools[#tools + 1] = {
      id = "place:" .. item.id,
      w = math.max(ui.buttonWidths.placeMin, math.ceil(Text.measure(label, "body")) + 12),
      label = label,
      style = "accent",
      selected = self.mode == "place" and self.placing == item.id,
      onPress = act(function()
        if self.mode == "place" and self.placing == item.id then
          self:setHand(nil, nil)
        else
          self:startPlacing(item.id)
        end
      end),
    }
  end
  tools[#tools + 1] = {
    id = "plan",
    w = fit(L.plan, ui.buttonWidths.plan),
    label = L.plan,
    selected = self.mode == "plan",
    latched = self.mode == "plan" and self.planLatch or nil,
    onPress = act(function()
      self:pressPlan(love.timer.getTime())
    end),
  }

  local trays = { tools = tools } -- the books open as books (#296); only the tools tray is left

  -- Measure the plates.
  local vitals, weather = self:vitalEntries()
  local weatherW = 0
  for n, id in ipairs(weather and (weather.icons or { weather.icon }) or {}) do
    weatherW = weatherW + Assets.sprite(id).w + (n > 1 and ui.topChips.iconGap or 0)
  end
  local timeW = Text.measure("00:00", "body")
  local clockW = math.max(Text.measure(self:dateText(), "body"), timeW + H.gap + weatherW) + 2 * H.textPad
  local spec = {
    clock = { w = clockW, h = H.clockH },
    speed = { w = 3 * H.speedSegment, h = H.clockH, segments = 3 },
    menu = { w = math.max(minTouch, H.clockH), h = H.clockH },
    vitals = {},
    vitalH = H.vitalH,
    stamps = {},
    books = {},
  }
  for _, e in ipairs(vitals) do
    spec.vitals[#spec.vitals + 1] = { id = e.id, w = ChipStrip.width(world, e) }
  end
  -- The pressing-goal line (D163, #342): its own line under the top plates, wide as its words up to a cap.
  local goalText, goalLevel = self:goalLine(view)
  spec.goal = { w = H.stampSize + Text.measure(goalText, "small") + H.textPad, h = ui.goal.lineH }
  local chips = self:statusChips(view)
  spec.statusAnchor = "condition"
  spec.statuses = {}
  for _, c in ipairs(chips) do
    spec.statuses[#spec.statuses + 1] = { id = c.id, w = c.w, h = H.stampSize }
  end
  local stamps = self:stampList()
  for _, s in ipairs(stamps) do
    spec.stamps[#spec.stamps + 1] = {
      id = s.id,
      w = H.stampSize + Text.measure(s.label, "small") + H.textPad,
      iconW = H.stampSize,
      h = H.stampSize,
    }
  end
  local state, line2 = self:badgeLines()
  local portrait = Assets.sprite("homesteader")
  spec.badge = {
    w = portrait.w + 4 * H.textPad + math.max(Text.measure(state, "body"), Text.measure(line2, "small")),
    compactW = H.badgeH,
    h = H.badgeH,
  }
  local icon, extra, toolLabel = self:toolInHand()
  local iconsW = Assets.sprite(icon).w + (extra and Assets.sprite(extra).w + 2 or 0)
  spec.tool = {
    w = iconsW + 3 * H.textPad + Text.measure(toolLabel, "body"),
    compactW = iconsW + 2 * H.iconPad,
    h = H.badgeH,
  }
  for _, b in ipairs({ { "notebook", L.notebook }, { "ledger", L.ledger } }) do
    spec.books[#spec.books + 1] = {
      id = b[1],
      w = Assets.sprite("icon_book_" .. b[1]).w + 3 * H.textPad + Text.measure(b[2], "body"),
      compactW = H.badgeH,
    }
  end
  local caption = self:captionText()
  if caption then
    spec.caption = { w = Text.measure(caption, "small") + 2 * H.textPad, h = ui.pillHeight }
  end
  local out = Hud.arrange(spec, view, { pad = H.pad, gap = H.gap, vitalGap = H.vitalGap, vitalPad = H.vitalPad })
  self.hud = out
  self.hudCaption = caption
  self.topH = out.topH
  self.statusBottom = out.statusBottom -- the right-hand status column's foot (nil without one); the Tonight card sits below it
  self.bottomH = view.h - out.bottomTop

  -- The plates that answer a tap are buttons with their own drawing (Buttons `draw`), so a label stays for
  -- the screenshot driver and the keyboard while the plate shows an icon.
  local add = function(r, b)
    b.x, b.y, b.w, b.h = r.x, r.y, r.w, r.h
    return self.buttons:add(b)
  end
  add(out.clock, {
    id = "clock",
    label = self:dateText(),
    onPress = function()
      self:openChip("weather")
    end,
    draw = function(b)
      self:drawClock(b, weather)
    end,
  })
  local speed = self.session:effectiveSpeed()
  local held = self.session:timeHeld() -- the speed waits for the drive home (D78) or the tip card (D92)
  local steps = self.app.ctx.tuning.time.speedSteps
  local segments = {
    { id = "pause", label = L.pause, on = speed == 0, glyph = "pause", scale = 0 },
    { id = "play", label = L.play, on = speed == 1, glyph = "play", scale = 1 },
    { id = "fast", label = L.fast, on = speed > 1, glyph = "fast" },
  }
  for k, seg in ipairs(segments) do
    add(out.segments[k], {
      id = seg.id,
      label = seg.label,
      enabled = not held,
      selected = seg.on,
      onPress = function()
        local scale = seg.scale
        if not scale then
          -- Fast: the first fast step, then the next on each tap.
          scale = steps[#steps]
          for _, s in ipairs(steps) do
            if s > math.max(1, speed) then
              scale = s
              break
            end
          end
          if speed >= steps[#steps] then
            scale = steps[3] or steps[#steps]
          end
        end
        self.session:setSpeed(scale)
        self:layout()
      end,
      draw = function(b)
        self:drawSpeedSegment(b, seg.glyph, speed)
      end,
    })
  end
  add(out.menu, {
    id = "menu",
    label = L.menu,
    onPress = function()
      self:openMenu()
    end,
    draw = function(b)
      self:drawIconPlate(b, "icon_menu")
    end,
  })
  if out.goal then
    local colors = theme.colors
    local stamp = {
      icon = goalLevel > 0 and "icon_signal_alert" or "icon_signal_idea",
      label = goalText,
      color = goalLevel >= 2 and colors.danger or goalLevel == 1 and colors.accent or colors.text,
    }
    add(out.goal, {
      id = "goal",
      label = goalText,
      onPress = function()
        self:openProgress()
      end,
      draw = function(b)
        self:drawStamp(b, stamp, false)
      end,
    })
  end
  -- A status chip is a plate of an icon and words (never colour alone); a tap opens its card (D167, #346).
  for n, r in ipairs(out.statuses) do
    local c = chips[n]
    local chip = { icon = c.icon, label = c.label, color = theme.colors.text }
    add(r, {
      id = "status:" .. c.id,
      label = c.name .. ": " .. c.label,
      onPress = function()
        self:openStatus(c.id)
      end,
      draw = function(b)
        self:drawStamp(b, chip, false)
      end,
    })
  end
  for n, r in ipairs(out.stamps) do
    local s = stamps[n]
    add(r, {
      id = s.id,
      label = s.label,
      onPress = s.onPress,
      draw = function(b)
        self:drawStamp(b, s, r.compact)
      end,
    })
  end
  -- The homesteader badge: what they are doing, and the routine switch (D43, D93). With the routine on and
  -- nothing to do it opens the priorities instead; it pulses gently while a nudge applies.
  local hint = self:hintKind()
  add(out.badge, {
    id = "badge",
    label = self:routineLabel(),
    pulse = hint ~= nil,
    onPress = function()
      if hint == "nothing" then
        self:openPanel("routine")
      elseif world.control == "idle" then
        self.session:cancelRoutine()
        self.session:setControl("active")
        self:layout()
      else
        self:startRoutine()
      end
    end,
    draw = function(b)
      self:drawBadge(b, out.compact)
    end,
  })
  add(out.tool, {
    id = "tools",
    label = L.tools,
    selected = self.wheel ~= nil or self.palette == "tools",
    onPress = function(b)
      -- The touch route to the tool wheel (D138): it opens over the badge and a tap chooses.
      if self.wheel then
        self.wheel = nil
        self:layout()
      else
        self:openWheel(b.x + b.w / 2, b.y + b.h / 2, false)
      end
    end,
    draw = function(b)
      self:drawToolBadge(b, out.compact)
    end,
  })
  for i, r in ipairs(out.books) do
    local id = spec.books[i].id
    add(r, {
      id = id,
      label = L[id],
      onPress = function()
        self.palette = nil
        self:openBook(id) -- the Notebook or the Ledger, on the page it was left on
      end,
      draw = function(b)
        self:drawIconPlate(b, "icon_book_" .. id, not out.compact and L[id] or nil)
      end,
    })
  end

  -- The open tray, above the plate that owns it; it scrolls when it is taller than its cap (D87).
  self.paletteRect = nil
  self.paletteButtons:clear()
  self.paletteList = nil
  if self.palette and not trays[self.palette] then
    self.palette = nil
  end
  if self.palette then
    local anchor = out.tool
    local list = self.paletteLists[self.palette]
    local cfg = {
      pad = H.pad,
      gap = ui.buttonGap,
      h = self.btnH,
      maxRows = ui.paletteMaxRows,
      top = self.topH,
      scrollBarWidth = ui.scrollBarWidth,
      scroll = list.offset,
    }
    local tray = Hud.tray(trays[self.palette], anchor, view, cfg, false)
    self.paletteRect = tray
    self.paletteList = list
    list:fit(tray.view, tray.contentH, 0, 1)
    list.offset = tray.offset
    -- Buttons that scrolled out of the window are left out; half-hidden ones answer only inside it.
    for _, b in ipairs(tray.items) do
      if b.y + b.h > tray.view.y and b.y < tray.view.y + tray.view.h then
        self.paletteButtons:add(b)
      end
    end
  end
  self.hudKeyShown = self:hudKey()
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
  if
    self.app:top() == self
    and not self.session:sleeping()
    and not Finds.pending(self.world)
    and Nightly.hasReport(self.world)
  then
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
    tiles = Placement.preview(world, self.placing, pc.tile, self.moving).tiles
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
--- Returns the card's y (`y` is the usual slot above the bottom plates).
function Homestead:keepTargetClear(y, h)
  local camera = self.camera
  local curX, curY = camera.x, camera.y
  local glide = self.autoPan
  if glide then
    camera.x, camera.y = glide.toX, glide.toY -- fit from where the last glide was heading
  end
  self.autoPan = nil
  local result = self:fitTarget(y, h)
  local toX, toY = camera.x, camera.y
  camera.x, camera.y = curX, curY
  self.autoPan = PlaceCard.glide(curX, curY, toX, toY) -- the pan is eased, not a jump (D120)
  return result
end

--- The fit itself: pans the camera (to its final spot; the caller eases there) and returns the card's y.
function Homestead:fitTarget(y, h)
  local rect = self:placeCardRect()
  local gap = self.app.ctx.tuning.ui.placement.cardGap
  if not rect then
    return y
  end
  local view = self.app.view
  if not PlaceCard.overlaps(rect, y, h, gap) then
    -- Clear of the card, but a drag may have left it behind the top or bottom plates: bring it back if that keeps it clear.
    local into = PlaceCard.panIntoBand(rect, self.topH, view.h - self.bottomH, gap)
    if into == 0 then
      return y
    end
    local camera = self.camera
    local x0, y0 = camera.x, camera.y
    camera:pan(0, into, view)
    if not PlaceCard.overlaps(self:placeCardRect(), y, h, gap) then
      return y
    end
    camera.x, camera.y = x0, y0 -- no room beside the card: lift it above the card below instead
  end
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

--- The player moved the map with a placement card open: their move wins, so any glide stops, and the view
--- re-fits once they have let go for `refitDelay` (D120).
function Homestead:mapMoved()
  self.autoPan = nil
  if self.placeCard and self.cardKind == "place" then
    self.refitTimer = self.app.ctx.tuning.ui.placement.refitDelay
  end
end

--- Per frame, real time: advance the glide and run the re-fit after a drag.
function Homestead:updateCardPan(dt)
  if not self.placeCard then
    self.autoPan, self.refitTimer = nil, nil
    return
  end
  local cfg = self.app.ctx.tuning.ui.placement
  local due
  self.refitTimer, due = PlaceCard.refitStep(self.refitTimer, dt, self.pointerDown)
  if due then
    self:layoutCard()
  end
  local g = self.autoPan
  if g then
    local x, y, done = PlaceCard.glideStep(g, dt, cfg.panSeconds)
    self.camera.x, self.camera.y = x, y
    self.camera:clamp(self.app.view)
    if done then
      self.autoPan = nil
    end
  end
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
  self.card = {
    x = x,
    y = y,
    w = w,
    h = h,
    title = spec.title,
    lines = spec.lines,
    lineGap = spec.lineGap or 0,
    titleH = titleH,
    pad = pad,
  }
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
      local preview = Placement.preview(world, self.placing, pc.tile, self.moving)
      local text = PlaceText.confirm(world, self.placing, preview, colors, self.moving ~= nil)
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
  local left = {
    leftLabel = "Pantry",
    onLeft = function()
      self:openPanel("pantry")
    end,
  }
  if view.first then
    -- The first spoilage ever: the card carries the explanation (D68) behind a button.
    left = {
      leftLabel = "Why?",
      onLeft = function()
        local app = self.app
        app:push(require("src.scenes.notice").new({
          title = "Food spoils",
          headline = view.first,
          message = SpoilText.explanation(world),
          okLabel = "Got it",
          more = {
            label = "Open Pantry",
            onPress = function()
              Book.open(app, "pantry")
            end,
          },
        }))
      end,
    }
  elseif not view.spoil then
    left = {
      leftLabel = "Journal",
      onLeft = function()
        self:openPanel("journal")
      end,
    }
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
  return self:overCard(x, y) or self:overTonight(x, y) or self:chipAt(x, y) ~= nil or self:overToast(x, y) -- a chip's explanation is not directing the homesteader either (D72)
end

--- Is the point on the toast? (Its rectangle is the one drawn last, grown to the touch size.)
function Homestead:overToast(x, y)
  local r = self.toast and self.toastHit
  return r ~= nil and x ~= nil and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

--- Is the point on the Tonight card (when it is up)?
function Homestead:overTonight(x, y)
  return self.tonightRect ~= nil and self:tonightShown() and self.tonightCard:contains(x, y)
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
  local c, list = self.card, nil
  if c then
    self.cardLast, self.cardLastButtons = c, self.cardButtons.list -- kept to draw it dissolving away
  else
    c, list = self.cardLast, self.cardLastButtons
  end
  if not c or not Dissolve.begin(self.cardFade:coverage()) then
    return
  end
  if self.card then
    self:drawHighlight()
  end
  Draw.panel(c.x, c.y, c.w, c.h)
  Text.draw(c.title, c.x + c.pad, c.y + c.pad, { size = "body", color = theme.colors.accent })
  local y = c.y + c.pad + c.titleH + 3
  for _, line in ipairs(c.lines) do
    Text.draw(line.text, c.x + c.pad, y, { size = "small", width = c.w - 2 * c.pad, color = line.color })
    y = y + line.h + c.lineGap
  end
  if list then
    for _, b in ipairs(list) do -- going away: the buttons are drawn but no longer answer
      self.cardButtons:drawOne(b, theme.colors)
    end
  else
    self.cardButtons:draw()
  end
  Dissolve.finish()
end

-- Speed and routine: the speed plate and the homesteader badge (D137).
function Homestead:speedLabel()
  local speed = self.session:effectiveSpeed() -- fast while asleep (D56)
  return speed == 0 and "Paused" or string.format(self.app.ctx.tuning.ui.labels.speed, speed)
end

local HINT_TEXT = {
  idle = "Homesteader is idle: press R or tap Start routine",
  nothing = "Nothing to do: check the Routine priorities",
}

--- Move the dissolves toward where things are now (D142). The wheel counts as there once it shows (a held
--- press waits `showDelay` first).
function Homestead:stepFades(dt)
  local w = self.wheel
  local shown = w ~= nil and not (w.held and love.timer.getTime() - w.at < self.app.ctx.tuning.ui.wheel.showDelay)
  Motion.step(self.wheelFade, shown, dt)
  Motion.step(self.cardFade, self.card ~= nil, dt)
  Motion.step(self.infoFade, self.selected ~= nil, dt)
  local id = self.lens:active()
  if id and self.lensLast and id ~= self.lensLast then
    self.lensFade.amount = 0 -- one lens switched for another: the new one dissolves in
  end
  Motion.step(self.lensFade, id ~= nil, dt)
  if id then
    self.lensLast = id
  elseif not self.lensFade:shown() then
    self.lensLast = nil
  end
  if not self.cardFade:shown() then
    self.cardLast, self.cardLastButtons = nil, nil
  end
  if not self.infoFade:shown() then
    self.infoLast = nil
  end
end

--- Show an idle nudge now, or hold it while a panel covers the world (D93, #120).
function Homestead:raiseHint(kind)
  if self.app:top() == self then
    self.pendingHint = nil
    self:showToast(HINT_TEXT[kind])
  else
    self.pendingHint = kind
  end
end

--- The world is back on top: deliver a held nudge if it still applies.
function Homestead:resume()
  local kind = self.pendingHint
  self.pendingHint = nil
  if kind and Routine.hintKind(self.world) == kind then
    self:showToast(HINT_TEXT[kind])
  end
end

function Homestead:routineLabel()
  if not self.session:canStartRoutine() then
    return self.app.ctx.tuning.ui.labels.resting
  end
  local L = self.app.ctx.tuning.ui.labels
  return self.world.control == "idle" and L.routineOn or L.startRoutine
end

--- The nudge that holds right now, for the Routine button's pulse (D93, #120). Not while asleep.
function Homestead:hintKind()
  if self.session:sleeping() then
    return nil
  end
  return Routine.hintKind(self.world)
end

--- Switch a lens on by hand ("power" | "water"), as the vital or a tap on a device does (D141, D145).
function Homestead:showLens(id)
  self.lens:show(id, "vital")
  self.lensFold = nil
end

--- The lens the tool in hand or the item being placed wants right now, or nil.
function Homestead:lensTrigger()
  if self.mode == "place" and self.placing then
    return LensState.forObject(self.world.registry:get("objects", self.placing))
  end
  return LensState.forTool(self.app.ctx.tuning.ui.lens, self.tool)
end

--- Where the lens card is and what it shows; set up again only when something it depends on changes.
function Homestead:layoutLensCard()
  local id = self.lens:active()
  if not id then
    self.lensCardKey = nil
    return
  end
  local view, cfg = self.app.view, self.app.ctx.tuning.ui.lens
  local small = math.min(view.w, view.h) < cfg.smallView
  local collapsed = self.lensFold
  if collapsed == nil then
    collapsed = cfg.collapseOnPlace and small and self.lens.source == "trigger" and self.mode == "place"
  end
  local touch = self.app.ctx.tuning.input.minTouchTarget
  local bounds = { top = math.max(self.topH, self.statusBottom or 0), bottom = view.h - self.bottomH }
  local spec = LensState.cardRect(cfg, view, bounds, collapsed, touch)
  self.lensRect, self.lensLayout = spec.rect, spec.layout
  local r = spec.rect
  local key = table.concat({ id, tostring(collapsed), r.x, r.y, r.w, r.h }, ":")
  if key ~= self.lensCardKey then
    self.lensCardKey = key
    self.lensCard:setup(id, r, collapsed, function()
      self.lens:dismiss()
      self.lensFold = nil
    end, function(folded)
      self.lensFold = folded
      self.lensCardKey = nil
    end)
  end
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
        Book.open(app, "pantry")
      end,
    },
  }))
end

-- The notice queue and the event card (D168, D172, #348; docs/PLAN_DEPTH.md §4, §6.2, §6.3) --------------------

--- Decide which notice card is up (tuning.ui.notices.rank): the Tonight card and an event card never share the screen.
--- Cards the player opens (a panel, a book, a status card), the tip and report cards and a lens cover the world and every
--- notice waits behind them, so a notice never opens over another card. Once a frame, before the cards are laid out.
function Homestead:updateNotices()
  local waiting = { tonight = self:tonightFits(), event = Events.waiting(self.world) > 0 }
  local rank = self.app.ctx.tuning.ui.notices.rank
  self.noticeCurrent = Notices.pick(rank, waiting, self.noticeCurrent)
  local covered = self.app:top() ~= self or self.card ~= nil or self.lens:active()
  self.noticeOwner = not covered and self.noticeCurrent or nil
  if self.noticeOwner == "event" and self.noticeOwnerPrev ~= "event" then
    self.eventCard.focusShown = false
    self.eventKey = nil
  end
  self.noticeOwnerPrev = self.noticeOwner
end

--- Is the event card up?
function Homestead:eventShown()
  return self.noticeOwner == "event" and self.eventRect ~= nil
end

--- Is the point on the event card (when it is up)?
function Homestead:overEvent(x, y)
  return self:eventShown() and self.eventCard:contains(x, y)
end

--- What EventText.build needs from the world.
function Homestead:eventEnv()
  local world, ev = self.world, self.app.ctx.tuning.events
  return {
    name = function(id)
      return world.registry:get("resources", id).name
    end,
    have = function(id)
      return Ledger.get(world, id)
    end,
    status = function(id)
      return world.registry:get("statuses", id)
    end,
    away = self.eventAway == true,
    speed = self.session:effectiveSpeed(),
    hourSeconds = Calendar.hourLength(world),
    ignoreHours = ev.ignoreHours,
    ignoreMinSeconds = ev.ignoreMinSeconds,
  }
end

--- Once a frame: the open event, in words, and where it goes; set up again only when its words or place change.
function Homestead:layoutEvent(dt)
  Motion.step(self.eventFade, self.noticeOwner == "event", dt)
  local ev = Events.pending(self.world)
  if self.noticeOwner ~= "event" or not ev then
    if not self.eventFade:shown() then
      self.eventRect, self.eventKey = nil, nil
    end
    return
  end
  local view, cfg = self.app.view, self.app.ctx.tuning.ui.eventCard
  local touch = self.app.ctx.tuning.input.minTouchTarget
  local model = EventText.build(ev, self:eventEnv())
  local card = self.eventCard
  local bounds = { top = math.max(self.topH, self.statusBottom or 0), bottom = view.h - self.bottomH }
  local first = Tonight.place(cfg, view, bounds, 0, touch)
  local contentH = card:measure(model, first.rect.w - 2 * cfg.pad) + card:timerHeight() + 4
  local spec = Tonight.place(cfg, view, bounds, contentH, touch)
  local r = spec.rect
  self.eventRect, self.eventLayout = r, spec.layout
  local parts = { ev.id, r.x, r.y, r.w, r.h }
  for _, o in ipairs(model.options) do
    parts[#parts + 1] = tostring(o.enabled) .. (o.reason or "")
  end
  local key = table.concat(parts, ":")
  if key ~= self.eventKey then
    self.eventKey = key
    card:setup(model, r, function(index)
      self:answerEvent(index)
    end, function()
      self:answerEvent(nil)
    end)
  else
    card.model.timer = model.timer -- the words that change every frame, without laying the blocks out again
  end
end

--- An option (1 or 2) or the ignore block (nil) was pressed.
function Homestead:answerEvent(index)
  if index then
    Events.choose(self.world, index)
  else
    Events.ignore(self.world, "ignored")
  end
  self.noticeCurrent = nil
  self.eventKey = nil
  self:layout() -- the stamp goes
end

-- The Tonight card (D161, #340, docs/PLAN_DEPTH.md §3.1) --------------------------------------------------

--- Look at the figures again: the card and the stamp read this one cached look, refreshed `ui.tonight.refresh` real
--- seconds apart (the figures walk the stock, the power network and the objects; the stamp is asked every frame).
function Homestead:lookTonight()
  self.tonightLook = Readiness.tonight(self.world)
  self.goal = Goal.current(self.world, self.tonightLook) -- the pressing-goal line reads the same look (D163)
  self.tonightModel = nil -- built again when the card is up
  self.tonightRev = (self.tonightRev or 0) + 1
  self.tonightAge = self.app.ctx.tuning.ui.tonight.refresh
end

function Homestead:tonightDay()
  return Calendar.now(self.world).day
end

--- Can the card be drawn now? It is open, and not under a lens (which takes the side of the view) or, on a tall view
--- where it is a sheet, in the way of a tip or report card.
function Homestead:tonightShown()
  return self:tonightFits() and self.noticeOwner ~= "event"
end

--- Could the Tonight card be drawn, were no other notice up? (The notice queue decides who is up; see updateNotices.)
function Homestead:tonightFits()
  if not self.tonight.open or self.lens:active() then
    return false
  end
  local view = self.app.view
  return view.w > view.h or self.card == nil
end

--- The stamp or the T key: bring the card up, or put it away.
function Homestead:toggleTonight()
  if self.noticeOwner == "event" then
    self:showToast(EventText.busy) -- an event card is up: one card at a time, answer it first
    return
  end
  if self.tonight.open then
    self.footingCard = false -- closing the Footing card; the next opening is the Tonight card
  end
  self.tonight:toggle(self:tonightDay(), self.tonightLook.due)
  self:lookTonight()
  self.tonightKey = nil
  self.tonightCard.focusShown = false
  self:layout() -- the stamp comes or goes
end

--- The card's Close (and Esc): put it away; in the evening it stays away until tomorrow's.
function Homestead:dismissTonight()
  self.footingCard = false
  self.tonight:dismiss(self:tonightDay(), self.tonightLook.due)
  self.tonightKey = nil
  self.tonightRect = nil
  self:layout()
end

--- A fix button: an order through Dusk, or a book opened.
function Homestead:tonightFix(fix)
  if fix.kind == "open" then
    self:openPanel(fix.book)
    return
  end
  local ok, result = Dusk.apply(self.world, fix.id)
  if ok and fix.id == "fill" then
    self.session:cancelRoutine() -- any order hands control back (D43)
  elseif ok and fix.id == "fish" then
    local running = self.world.control == "idle"
    self:startRoutine() -- the Fish category now leads; the routine says so itself when it starts
    if not running then
      fix = nil
    end
  end
  local text = fix and TonightText.fixToast(fix, ok, result)
  if text then
    self:showToast(text)
  end
  self:lookTonight()
end

--- Once a frame: keep the card in step with the evening and with its figures, and set it where it goes.
function Homestead:updateTonight(dt)
  self.tonightAge = self.tonightAge - dt
  if self.tonightAge <= 0 then
    self:lookTonight()
  end
  local due, leads = Readiness.tonightDue(self.world)
  local asleep = Actors.homesteader(self.world).asleep == true
  self.tonight:sync(due, leads, self:tonightDay(), asleep)
  -- The one-time Footing card (D162): a panel in the Tonight card's place, up once it is earned, awake and on top.
  if Footing.cardDue(self.world) and not asleep and self.app:top() == self then
    Footing.cardShown(self.world)
    self.footingCard = true
    self.tonight.open, self.tonight.manual = true, true
    self:record(FootingText.logLine)
    self:lookTonight()
    self.tonightKey = nil
    self.tonightCard.focusShown = false
  end
  self:layoutTonight()
end

--- Where the card is and what it shows; set up again only when the figures or the place change.
function Homestead:layoutTonight()
  if not self:tonightShown() then
    self.tonightRect, self.tonightKey = nil, nil
    return
  end
  local view, cfg = self.app.view, self.app.ctx.tuning.ui.tonight
  local touch = self.app.ctx.tuning.input.minTouchTarget
  local look = self.tonightLook
  if not self.tonightModel then
    if self.footingCard then
      self.tonightModel = FootingText.build(Footing.checks(self.world), self.app.ctx.tuning.night.footing)
    else
      self.tonightModel = TonightText.build(look, Dusk.fixes(self.world, look))
    end
  end
  local model = self.tonightModel
  local bounds = { top = math.max(self.topH, self.statusBottom or 0), bottom = view.h - self.bottomH }
  local first = Tonight.place(cfg, view, bounds, 0, touch)
  local contentH = self.tonightCard:measure(model, first.rect.w - 2 * cfg.pad)
  local spec = Tonight.place(cfg, view, bounds, contentH, touch)
  local r = spec.rect
  self.tonightRect, self.tonightLayout = r, spec.layout
  local key = table.concat({ r.x, r.y, r.w, r.h, self.tonightRev }, ":")
  if key ~= self.tonightKey then
    self.tonightKey = key
    self.tonightCard:setup(model, r, function()
      self:dismissTonight()
    end, function(fix)
      self:tonightFix(fix)
    end)
  end
end

--- Keys the card answers while it is up: Tab moves the focus ring along its buttons, Enter presses the focused one.
function Homestead:keypressed(key)
  if self:eventShown() then
    if key == "tab" then
      local back = love.keyboard and love.keyboard.isDown("lshift", "rshift")
      self.eventCard:moveFocus(back and -1 or 1)
    elseif key == "return" or key == "kpenter" then
      if self.eventCard.focusShown then
        self.eventCard:activate()
      end
    end
    return
  end
  if not (self.tonightRect and self:tonightShown()) then
    return
  end
  if key == "tab" then
    local back = love.keyboard and love.keyboard.isDown("lshift", "rshift")
    self.tonightCard:moveFocus(back and -1 or 1)
  elseif key == "return" or key == "kpenter" then
    if self.tonightCard.focusShown then
      self.tonightCard:activate()
    end
  end
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
  local delay = math.max(idle.minTakeoverDelay, idle.takeoverDelay - Stats.modifier(self.world, "idleTakeover"))
  -- The player's idle delay setting (D96) scales it, never below the floor.
  return math.max(idle.minTakeoverDelay, delay * self.app.ctx.settings:get("idleDelay"))
end

function Homestead:update(dt)
  local ctx = self.app.ctx
  -- An event card's ignore window runs only while the player is present (D169, PLAN_DEPTH 6.3): its real-seconds floor
  -- is fed the real frame time, and it waits while the app is unfocused or no input has come past the takeover delay.
  -- It also waits while the card is not on screen (behind another card or a panel, the notice queue): an event must not run
  -- out unseen, but game time never waits for it (D168).
  self:updateNotices()
  local away = self.unfocused == true or ctx.input:idleSeconds() >= self:takeoverDelay()
  self.eventAway = away
  Events.setAway(self.world, away or (Events.waiting(self.world) > 0 and self.noticeOwner ~= "event"))
  Events.advanceReal(self.world, dt)
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
    Run.fail(data, self.world, self.failed)
    self.app:switch(require("src.scenes.rescue").new(), slot, data)
    return
  end
  self.renderer:update(dt, self.session:effectiveSpeed()) -- effects follow game speed and pause (D97)
  self.lens:sync(self:lensTrigger())
  self.lensView:tick(dt)
  self:stepFades(dt)
  if self.lens:active() then
    self:layoutLensCard()
    self.lensCard:update(dt)
  end
  self:updateTonight(dt)
  self:layoutEvent(dt)
  -- A find waits for a free screen (not behind the fishing mini-game or a panel), also after a load.
  if Finds.pending(self.world) and self.app:top() == self then
    self.app:push(require("src.scenes.finds").new(self.world))
    return
  end
  self:spoilageNews()
  self:establishedNews()
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
  self:updateCardPan(dt)
  self:releaseHeld()
  self:announceClothes()
  if self.toast then
    self.toast.time = self.toast.time - dt
    if self.toast.time <= 0 then
      self.toast = nil
      if #self.toastQueue > 0 then
        self:present(table.remove(self.toastQueue, 1))
      end
    end
  end
  -- The HUD lays out again when what it shows changes size or kind (a vital's value, a stamp, the tool).
  if self:hudKey() ~= self.hudKeyShown then
    self:layout()
  end
  -- Seed counts change as you plant and harvest; keep the tray's labels current.
  for cropId, button in pairs(self.seedButtons) do
    button.label = tostring(Ledger.get(self.world, self.world.registry:get("crops", cropId).seed))
  end
  if self.placeCard and self.placeCard.kind == "order" and not Placement.orderAt(self.world, self.placeCard.tile) then
    self.placeCard = nil -- the order was built or cancelled
    self:layoutCard()
  end
  if self.mode == "place" and not self.moving and Placement.available(self.world, self.placing) <= 0 then
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

-- The tiles of the rectangle between tiles a and b, row by row.
function Homestead:rectTiles(a, b)
  local grid = self.world.state.grid
  local ax, ay = Grid.coords(grid, a)
  local bx, by = Grid.coords(grid, b)
  local tiles = {}
  for y = math.min(ay, by), math.max(ay, by) do
    for x = math.min(ax, bx), math.max(ax, bx) do
      tiles[#tiles + 1] = Grid.index(grid, x, y)
    end
  end
  return tiles
end

--- Plan the rectangle a..b with the seed in hand. Every tile growing a crop (the same kind too) is replaced (D110, #257): the
--- player confirms once, and the card says what is lost. Clearing never pulls a crop.
function Homestead:applyPlan(a, b)
  local tiles = self:rectTiles(a, b)
  local preview = self.seed and Crops.replacePreview(self.world, tiles, self.seed)
  if preview and #preview.tiles > 0 then
    local p = self.app.ctx.tuning.ui.placement
    local text = PlaceText.replaceConfirm(self.world, preview, self.seed)
    self.app:push(require("src.scenes.confirm").new({
      title = text.title,
      message = text.text,
      confirmLabel = p.replaceLabel,
      danger = true,
      onConfirm = function()
        self:finishPlan(tiles)
      end,
    }))
    return
  end
  self:finishPlan(tiles)
end

function Homestead:finishPlan(tiles)
  local result = Crops.planReplacing(self.world, tiles, self.seed)
  local count = result.planned
  if self.seed then
    self:showToast(
      string.format(
        "Planned %d tiles of %s. Tilling and planting start now",
        count,
        self.world.registry:get("crops", self.seed).name
      )
    )
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
  local name = world.registry:get("objects", id).name:lower()
  local result, reason, rule = self:requestHere(i)
  if result == "queued" then
    self:showToast(self.moving and string.format(p.moveOrdered, name) or p.ordered)
    self:setHand(nil, nil)
  elseif result == "placed" then
    self:showToast(self.moving and string.format(p.moved, name) or "Placed " .. name)
    self:setHand(nil, nil)
  else
    self:showToast(PlaceText.reason(world, reason, rule))
  end
end

-- Place the item in hand at tile i, or move the object being moved there (D98): Placement's answer.
function Homestead:requestHere(i)
  if self.moving then
    return Placement.requestMove(self.world, self.moving, i)
  end
  return Placement.request(self.world, self.placing, i)
end

--- Start moving the placed object at `anchor`: Place mode with that object as the ghost. It stays where it is
--- until the spot is chosen (and cleared); leaving Place cancels (D98, #15).
function Homestead:startMove(anchor)
  local world = self.world
  local p = self.app.ctx.tuning.ui.placement
  local check = Placement.moveCheck(world, anchor)
  if not check.ok then
    self:showToast(PlaceText.pickUpRefusal(world, check))
    return
  end
  local id = world.state.grid.objects[anchor].id
  self:setHand(nil, nil)
  self.mode, self.placing, self.moving = "place", id, anchor
  self:showToast(string.format(p.moveStart, world.registry:get("objects", id).name:lower()))
  self:layout()
end

--- A tap with one of the Hammer's modes (D139): the D98 and D110 flows, on the building (or crop) tapped.
function Homestead:hammerTap(i)
  local world = self.world
  local p = self.app.ctx.tuning.ui.placement
  local def, anchor = Grid.object(world, i)
  local building = def and def.placeable and anchor
  if self.tool == "move" then
    if building then
      self:startMove(anchor)
    else
      self:showToast(p.noMove)
    end
  elseif self.tool == "pickup" then
    if building then
      self:askPickUp(anchor)
    else
      self:showToast(p.noPickUp)
    end
  elseif building then
    self:askDestroy(anchor)
  elseif world.state.crops[i] then
    self:askDestroyCrop(i)
  else
    self:showToast(p.noDemolish)
  end
end

--- Pick the object at `anchor` up, asking first when that throws something away (D98, #15).
function Homestead:askPickUp(anchor)
  local world = self.world
  local p = self.app.ctx.tuning.ui.placement
  local check = Placement.pickUpCheck(world, anchor)
  if not check.ok then
    self:showToast(PlaceText.pickUpRefusal(world, check))
    return
  end
  local name = world.registry:get("objects", world.state.grid.objects[anchor].id).name:lower()
  local function pick()
    if Placement.pickUp(world, anchor) then
      self:showToast(string.format(p.pickedUp, name))
      self:layout()
    end
  end
  if check.warn then
    local text = PlaceText.pickUpConfirm(world, anchor, check.warn)
    self.app:push(require("src.scenes.confirm").new({
      title = text.title,
      message = text.text,
      confirmLabel = p.pickConfirmLabel,
      danger = true,
      onConfirm = pick,
    }))
  else
    pick()
  end
end

--- Destroy the object at `anchor` after a confirmation that says what is lost (D110, #255). No refund.
function Homestead:askDestroy(anchor)
  local world = self.world
  local p = self.app.ctx.tuning.ui.placement
  local check = Placement.destroyCheck(world, anchor)
  if not check.ok then
    self:showToast(PlaceText.pickUpRefusal(world, check))
    return
  end
  local name = world.registry:get("objects", world.state.grid.objects[anchor].id).name:lower()
  local text = PlaceText.destroyConfirm(world, anchor, check.lose)
  self.app:push(require("src.scenes.confirm").new({
    title = text.title,
    message = text.text,
    confirmLabel = p.destroyConfirmLabel,
    danger = true,
    onConfirm = function()
      local ok, refused = Placement.destroy(world, anchor)
      if ok then
        self:showToast(string.format(p.destroyedObject, name))
        self:layout()
      elseif refused then
        self:showToast(PlaceText.pickUpRefusal(world, refused))
      end
    end,
  }))
end

--- Destroy the crop on tile i after a confirmation (D110, #255). No refund; the soil stays tilled.
function Homestead:askDestroyCrop(i)
  local world = self.world
  local p = self.app.ctx.tuning.ui.placement
  local crop = world.state.crops[i]
  if not crop then
    return
  end
  local name = world.registry:get("crops", crop.id).name:lower()
  local text = PlaceText.destroyCropConfirm(world, i)
  self.app:push(require("src.scenes.confirm").new({
    title = text.title,
    message = text.text,
    confirmLabel = p.destroyConfirmLabel,
    danger = true,
    onConfirm = function()
      if Crops.remove(world, i) then
        self:showToast(string.format(p.destroyedCrop, name))
      end
    end,
  }))
end

-- Tools that only take part of what a tap can do: the Pail only waters, the Axe only clears and fells.
local TOOL_CATEGORIES = {
  pail = { water = true },
  axe = { clear = true, trees = true },
}

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
      local keep = self.planLatch or (love.keyboard and love.keyboard.isDown("lshift", "rshift"))
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
    local preview = Placement.preview(world, self.placing, i, self.moving)
    if not preview.ok then
      self.placeCard = nil
      self:showToast(PlaceText.reason(world, preview.reason, preview.rule))
      self:layoutCard()
    elseif preview.immediate and #preview.replaces == 0 then
      self.placeCard = nil
      local name = world.registry:get("objects", self.placing).name:lower()
      if self:requestHere(i) == "placed" then
        self:showToast(self.moving and string.format(self.app.ctx.tuning.ui.placement.moved, name) or "Placed " .. name)
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
  if HAMMER_MODES[self.tool] then
    self:hammerTap(i)
    return
  end
  if Cat.at(world, i) then
    Cat.pet(world) -- tap the cat to pet it, wherever the homesteader is
    return
  end
  local obj = Grid.object(world, i)
  if obj and obj.book then
    self:openPanel(obj.book) -- the truck opens the Ledger on Truck & town, the camp or shack on the Pantry (D143)
    return
  end
  if obj and obj.station then
    -- A tap on a station with a batch in it says what it is doing and shows its card, rather than
    -- sending the homesteader over for nothing (D93, #135).
    local anchor = select(2, Grid.object(world, i))
    local batch = Processing.batch(world, anchor)
    if batch then
      local recipe = world.registry:get("recipes", batch.recipe)
      local out = world.registry:get("resources", recipe.output).name
      if batch.blocked then
        self:showToast(string.format("%d %s waiting for storage room: discard it from the card", batch.count, out))
      else
        self:showToast(
          string.format("%s: %.1fh left", recipe.name, batch.remaining / (world.tuning.time.dayLength / 24))
        )
      end
      return
    end
  end
  if obj and obj.machine then
    return -- a tap on a machine shows its card (and reach); its power switch is in the power panel
  end
  if obj and (obj.source or obj.sink or obj.battery) then
    self:showLens(LensState.forObject(obj)) -- a panel, battery or powered device shows its lens (D141)
    return
  end
  local hs = Actors.homesteader(world)
  local taskType, full, limited =
    Actors.order(world, hs, i, { crop = self.seed, tool = self.tool, categories = TOOL_CATEGORIES[self.tool] })
  if taskType then
    self.session:cancelRoutine() -- any order hands control back (D43)
    if taskType.id ~= "move" then
      -- Tilling or planting a crop that cannot ripen in time says so (D70, #165), once a day per crop;
      -- the order still goes ahead.
      local late = (taskType.id == "till" or taskType.id == "plant") and self:frostWarning(self.seed)
      local crop = taskType.id == "untill" and world.state.crops[i]
      if crop then
        late =
          string.format(self.app.ctx.tuning.ui.placement.pullCrop, world.registry:get("crops", crop.id).name:lower())
      end
      self:showToast(late or taskType.verb)
    end
  elseif full then
    -- Refused for lack of room: say which store is full (D59).
    self:showToast(string.format("%s storage is full", world.registry:get("resources", full).name))
  elseif limited == "felling" then
    -- Refused because the season's allowance of wood from trees is used up (#362): say what is left to do.
    self:showToast(FellingText.refused)
  elseif self.tool == "untill" then
    self:showToast(self.app.ctx.tuning.ui.placement.noUntill)
  elseif self.tool == "pail" or self.tool == "axe" then
    self:showToast(self.app.ctx.tuning.ui.placement[self.tool == "pail" and "noWater" or "noClear"])
  else
    self:showToast("Can't do anything there")
  end
end

-- Area drags (GDD §9.4, D138, D147) ----------------------------------------------------------

local AREA_TOOLS = { axe = "clear", pail = "water" } -- the tool in hand -> the kind of mark it drags out

--- A press with the Axe or the Pail in hand starts an area at that tile. A drag that begins on a tile already marked
--- (by this tool) cancels marks instead of adding them. Two fingers cancel it and pan (Input marks that pan).
function Homestead:areaDragBegin(data)
  self.areaDrag = nil
  local kind = AREA_TOOLS[self.tool]
  if not kind or self.mode ~= "act" or self.app:top() ~= self or self.wheel or not data.x then
    return
  end
  if not self:inWorldArea(data.x, data.y) or self:chipAt(data.x, data.y) then
    return
  end
  local i = self:tileAt(data.x, data.y)
  if i then
    self.areaDrag = {
      kind = kind,
      start = i,
      last = i,
      x = data.x,
      y = data.y,
      panned = false,
      erase = Marks.has(self.world, kind, i),
    }
  end
end

--- A drag moved the pointer: grow the area. Returns true when the drag was ours (the view does not pan).
function Homestead:areaDragMove(data)
  local d = self.areaDrag
  if not d then
    return false
  end
  if data.pinch or data.keys then
    self.areaDrag = nil -- two fingers pan and zoom; the keys pan
    return false
  end
  d.x, d.y, d.panned = d.x + data.dx, d.y + data.dy, true
  d.last = (self:inWorldArea(d.x, d.y) and self:tileAt(d.x, d.y)) or d.last
  return true
end

--- The pointer let go: mark (or cancel) the area, or, if the pointer never left its tile, treat it as the tap it was.
function Homestead:areaDragEnd(data)
  local d = self.areaDrag
  self.areaDrag = nil
  if not d or not d.panned then
    return -- a plain tap: Input follows with `select`
  end
  local last = (data.x and self:inWorldArea(data.x, data.y) and self:tileAt(data.x, data.y)) or d.last
  if last == d.start then
    self:tap(d.start) -- a wobble inside one tile is still a tap
    return
  end
  local tiles = self:rectTiles(d.start, last)
  local text = self.app.ctx.tuning.ui.placement
  local n
  if d.erase then
    n = Marks.remove(self.world, d.kind, tiles)
    self:showToast(n > 0 and string.format(text.unmarked, n) or text[d.kind == "clear" and "noClear" or "noWater"])
  else
    n = Marks.add(self.world, d.kind, tiles)
    if n > 0 then
      self:showToast(string.format(d.kind == "clear" and text.markedClear or text.markedWater, n))
    else
      self:showToast(text[d.kind == "clear" and "noClear" or "noWater"])
    end
  end
end

function Homestead:action(name, data)
  if name == "press" then
    self.pointerDown = true
  elseif name == "release" then
    self.pointerDown = false
  end
  if self.lens:active() and self.lensCard:action(name, data) then
    return true
  end
  -- The event card likewise (D172): it answers only inside its own rectangle.
  if self:eventShown() and self.eventCard:action(name, data) then
    return true
  end
  -- The Tonight card answers only inside its own rectangle (D161): the world stays tappable around it.
  if self.tonightRect and self:tonightShown() and self.tonightCard:action(name, data) then
    return true
  end
  if name == "tonight" then
    self:toggleTonight() -- T: open or close the dusk check at any hour
    return true
  end
  if name == "status" then
    local first = Status.active(self.world)[1] -- H: the first status's card (a chip's tap opens its own, D167)
    if first then
      self:openStatus(first.id)
    else
      self:showToast(self.app.ctx.tuning.ui.status.none)
    end
    return true
  end
  if name == "progress" then
    self:openProgress() -- P: the Progress panel (it closes on P again, D163)
    return true
  end
  -- The tool wheel (D138): held by a right press or long-press, or open after a tap on the tool badge.
  if self:wheelAction(name, data) then
    return true
  end
  if name == "wheelOpen" then
    self.areaDrag = nil -- a long press became the wheel, not an area
    self:openWheel(data.x, data.y, true)
    return true
  elseif name == "toolWheel" then
    local view = self.app.view
    self:openWheel(view.w / 2, view.h / 2, false)
    return true
  elseif name == "wardrobe" then
    self:openWardrobe() -- C: the homesteader's clothes (D154)
    return true
  elseif name:match("^tool%d$") then
    local wedge = self.app.ctx.tuning.ui.wheel.wedges[tonumber(name:sub(5))]
    if wedge then
      self:equip(wedge.id)
    end
    return true
  end
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
    if
      (name == "press" or name == "select" or name == "hover")
      and list:contains(data.x, data.y)
      and self.paletteButtons:action(name, data)
    then
      return true
    elseif name == "release" then
      self.paletteButtons:action(name, data)
      list:action(name, data) -- a drag that ends moving lets the palette coast (D94)
    elseif name == "press" then
      self.palettePress = over -- a drag that began on the palette scrolls it, not the camera
      list:action(name, data)
    end
    local step = self.app.ctx.tuning.ui
    local jump = name == "pageUp" or name == "pageDown" or name == "listHome" or name == "listEnd"
    if
      list.overflow and ((name == "pan" and (self.palettePress or data.keys)) or (name == "zoom" and over) or jump)
    then
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
  -- The tile card's own buttons (discard a station's waiting output, D93; pick up, move, destroy). An open
  -- tray is drawn over the card, so it answers first.
  if
    self.infoButtons
    and (name == "press" or name == "select" or name == "release")
    and data.x
    and self.infoButtons:action(name, data)
  then
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
      local lens = LensState.forVital(self.app.ctx.tuning.ui.lens, chip)
      if lens and self.lens:active() == lens then
        self.lens:dismiss() -- the vital again puts its lens away
      else
        self:openChip(chip)
      end
      return true
    end
  end
  -- The Axe and the Pail drag out an area to mark (D147); the drag does not pan the view.
  if name == "press" then
    self:areaDragBegin(data)
  elseif name == "release" then
    self:areaDragEnd(data)
  elseif name == "pan" and self:areaDragMove(data) then
    return true
  end
  if name == "press" then
    -- A finger held on a tile while placing shows the item's preview and range there (#268); a drag pans
    -- instead, and letting go places or not as before.
    self.pressTile = self.mode == "place" and self:inWorldArea(data.x, data.y) and self:tileAt(data.x, data.y) or nil
  elseif name == "release" then
    self.pressTile = nil
  end
  if name == "pan" then
    self.pressTile = nil -- a drag moves the view; the held preview would point at the wrong ground
    self.camera:pan(data.dx, data.dy, view)
    self:mapMoved()
  elseif name == "zoom" then
    self.camera:zoomBy(data.steps, data.x, data.y, view)
    self:mapMoved()
  elseif name == "hover" then
    self.hover = self:inWorldArea(data.x, data.y) and self:tileAt(data.x, data.y) or nil
  elseif name == "select" then
    if self:inWorldArea(data.x, data.y) then
      local i = self:tileAt(data.x, data.y)
      if i then
        self:tap(i)
      end
    end
  elseif name == "context" then
    if self:inWorldArea(data.x, data.y) then
      self.selected = nil -- a short right click puts the selection away; a tap selects (playtest)
    end
  elseif name == "speed" then
    self:cycleSpeed()
  elseif name == "routine" then
    self:startRoutine()
  elseif name == "cancel" then
    if self.palette then
      self.palette = nil
      self:layout()
    elseif self.placeCard then
      self.placeCard = nil
      self:layoutCard()
    elseif self.areaDrag then
      self.areaDrag = nil
    elseif self.planStart then
      self.planStart = nil
    elseif self.tonightRect and self:tonightShown() then
      self:dismissTonight() -- Esc puts the Tonight card away before it opens the menu
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

--- The tile the item being placed would go on: the confirmation card's tile, else the tile held under a finger
--- (touch has no hover, #268), else the one under the mouse. Nil when not placing.
function Homestead:placeTarget()
  if self.mode ~= "place" then
    return nil
  end
  if self.placeCard and self.placeCard.kind == "confirm" then
    return self.placeCard.tile
  end
  return self.pressTile or self.hover
end

--- Is lens `id` showing and painting the world (so the separate tints it replaces stay off)?
function Homestead:lensDraws(id)
  return self.lens:active() == id and self.world.tuning.visuals.lens.enabled
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
    -- The plan being drawn, in pencil like the plans it will join (D142).
    local rect = self:rectTiles(self.planStart, target)
    local inRect = {}
    for _, i in ipairs(rect) do
      inRect[i] = true
    end
    local x1, y1, x2, y2 = camera:visibleTiles(self.app.view)
    Sketch.drawPlans(world, tile, function(i)
      return inRect[i] == true
    end, { x1, y1, x2, y2 }, function()
      return world.tuning.visuals.sketch.ink
    end, 1, rect)
    -- Tiles whose crop this plan would replace (D110, #257): a red tint and an X, so the loss is visible before the second tap.
    if self.seed then
      local replaced = Crops.replacePreview(world, self:rectTiles(self.planStart, target), self.seed)
      local look = world.tuning.visuals.replacePreview
      for _, i in ipairs(replaced.tiles) do
        local x, y = Grid.coords(grid, i)
        local wx, wy = camera:tileToWorld(x, y)
        love.graphics.setColor(look.fill)
        love.graphics.rectangle("fill", wx, wy, tile, tile)
        love.graphics.setColor(look.edge)
        love.graphics.setLineWidth(1 / camera:zoom())
        love.graphics.line(wx + 2, wy + 2, wx + tile - 2, wy + tile - 2)
        love.graphics.line(wx + tile - 2, wy + 2, wx + 2, wy + tile - 2)
      end
    end
  end
  local drag = self.areaDrag
  if drag and drag.panned and drag.last ~= drag.start then
    -- The area being dragged out, in the pencil of the tool: hatch for the Axe, waves for the Pail; red when it cancels.
    local rect = self:rectTiles(drag.start, drag.last)
    local cfg = world.tuning.visuals.sketch
    local ink = drag.erase and cfg.status.refused or (drag.kind == "clear" and cfg.markClearInk or cfg.markWaterInk)
    local x1, y1, x2, y2 = camera:visibleTiles(self.app.view)
    local style = drag.kind == "water" and { wave = true } or { always = true }
    local inArea = {}
    for _, i in ipairs(rect) do
      inArea[i] = true
    end
    Sketch.drawPlans(world, tile, function(i)
      return inArea[i] == true
    end, { x1, y1, x2, y2 }, function()
      return ink
    end, cfg.previewShare, rect, style)
  end
  local visuals = world.tuning.visuals
  -- Range preview while placing (#268): the ranges of placed items of the same kind, dimmed, drawn first so the
  -- range being placed and its overlaps sit on top; touch shows it while the finger is held on a tile.
  local rangePreview
  local placeTile = self:placeTarget()
  if placeTile then
    rangePreview = RangePreview.build(world, self.placing, placeTile, self.moving)
  end
  if rangePreview and (rangePreview.kind == "drip" or rangePreview.kind == "sprinkler") and self:lensDraws("water") then
    rangePreview = nil -- the Water lens shows irrigation coverage while placing (D145)
  end
  if rangePreview then
    local look = visuals.rangePreview
    for _, other in ipairs(rangePreview.others) do
      love.graphics.setColor(look.others)
      local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
      for _, i in ipairs(other.tiles) do
        local x, y = Grid.coords(grid, i)
        local wx, wy = camera:tileToWorld(x, y)
        love.graphics.rectangle("fill", wx, wy, tile, tile)
        minX, minY, maxX, maxY =
          math.min(minX, wx), math.min(minY, wy), math.max(maxX, wx + tile), math.max(maxY, wy + tile)
      end
      love.graphics.setColor(look.othersEdge)
      love.graphics.setLineWidth(1 / camera:zoom())
      love.graphics.rectangle("line", minX, minY, maxX - minX, maxY - minY)
    end
  end
  -- Drip zones: the selected line's, or the one being placed under the pointer.
  local zoneAnchor
  if self.selected and self.mode ~= "place" then
    local obj, anchor = Grid.object(world, self.selected)
    zoneAnchor = obj and Water.irrigationKind(obj) and anchor or nil
  end
  if zoneAnchor then
    love.graphics.setColor(visuals.waterZone[Water.dripState(world, zoneAnchor) == "dry" and "dry" or "ok"])
    for _, i in ipairs(Water.dripTiles(world, zoneAnchor)) do
      local x, y = Grid.coords(grid, i)
      local wx, wy = camera:tileToWorld(x, y)
      love.graphics.rectangle("fill", wx, wy, tile, tile)
    end
  elseif rangePreview and (rangePreview.kind == "drip" or rangePreview.kind == "sprinkler") then
    love.graphics.setColor(visuals.waterZone.ok)
    for _, i in ipairs(rangePreview.mine) do
      local x, y = Grid.coords(grid, i)
      local wx, wy = camera:tileToWorld(x, y)
      love.graphics.rectangle("fill", wx, wy, tile, tile)
    end
  end
  -- Machine reach (D65): the selected machine's area, or the one being placed under the pointer.
  local reach, reachColor
  if self.selected and self.mode ~= "place" then
    local obj, anchor = Grid.object(world, self.selected)
    if obj and obj.machine then
      reach = Machines.areaTiles(world, anchor)
      local unit = Machines.at(world, anchor)
      reachColor = unit and unit.status == "unpowered" and visuals.machine.zoneUnpowered or visuals.machine.zone
    end
  elseif rangePreview and rangePreview.kind == "machine" then
    reach, reachColor = rangePreview.mine, visuals.machine.zone
  end
  -- Heater slot (D82): a shelter's own slot when it is selected or being placed, and the sleeping
  -- shelter's slot while a heat source is being placed, so the player sees where a fire counts in full.
  if not reach then
    local slotDef, sx, sy
    if self.selected and self.mode ~= "place" then
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
      minX, minY, maxX, maxY =
        math.min(minX, wx), math.min(minY, wy), math.max(maxX, wx + tile), math.max(maxY, wy + tile)
    end
    -- A solid edge so the reach reads over crops and soil as well as grass.
    local edge = { reachColor[1], reachColor[2], reachColor[3], 0.9 }
    love.graphics.setColor(edge)
    love.graphics.setLineWidth(1 / camera:zoom())
    love.graphics.rectangle("line", minX, minY, maxX - minX, maxY - minY)
  end
  if rangePreview and #rangePreview.overlap > 0 then
    love.graphics.setColor(visuals.rangePreview.overlap)
    for _, i in ipairs(rangePreview.overlap) do
      local x, y = Grid.coords(grid, i)
      local wx, wy = camera:tileToWorld(x, y)
      love.graphics.rectangle("fill", wx, wy, tile, tile)
    end
  end
  -- Buildings waiting for the way to be cleared (D79): a pencil sketch (D142) with an accent outline on the footprint.
  local sketch = visuals.sketch
  for _, order in ipairs(Placement.orders(world)) do
    local def = world.registry:get("objects", order.object)
    local sprite = Assets.sprite(order.object)
    local x, y = Grid.coords(grid, order.tile)
    local ink = order.why and sketch.status.held or sketch.status.queued
    Sketch.sprite(sprite, (x - 1) * tile, (y - 1 + (def.footprintH or 1)) * tile - sprite.h, ink, sketch.ghost)
    for _, t in ipairs(Grid.footprintTiles(grid, def, x, y)) do
      outlineTile(camera, t, grid, order.why and theme.colors.danger or theme.colors.accent, 2)
    end
  end
  if self.moving and world.state.grid.objects[self.moving] then
    -- The object being moved stays where it is until the new spot is ready: outline where it stands.
    local mdef = world.registry:get("objects", world.state.grid.objects[self.moving].id)
    local mx, my = Grid.coords(grid, self.moving)
    for _, t in ipairs(Grid.footprintTiles(grid, mdef, mx, my)) do
      outlineTile(camera, t, grid, theme.colors.accent, 2)
    end
  end
  local target = self:placeTarget()
  if target then
    -- Ghost of the object being placed: green where it fits now, amber where trees, rocks or crops must go
    -- first (those tiles are outlined: orange to clear, red to remove), red where it can't go.
    local def = world.registry:get("objects", self.placing)
    local sprite = Assets.sprite(self.placing)
    local x, y = Grid.coords(grid, target)
    local preview = Placement.preview(world, self.placing, target, self.moving)
    local replaceTag = PlaceText.replaceTag(world, self.placing, preview)
    -- A pencil sketch in the preview's ink (D142): green goes up at once, amber clears first, red cannot go
    -- there, blue is an upgrade over the old building (D115), which is outlined.
    local inks = sketch.status
    local ink = inks.clear
    if not preview.ok then
      ink = inks.refused
    elseif replaceTag then
      ink = inks.replace
    elseif preview.immediate then
      ink = inks.ok
    end
    local bottom = (y - 1 + (def.footprintH or 1)) * tile
    Sketch.sprite(sprite, (x - 1) * tile, bottom - sprite.h, ink, sketch.ghost)
    if preview.ok then
      for _, old in ipairs(preview.replaces) do
        local odef = world.registry:get("objects", grid.objects[old].id)
        local ox, oy = Grid.coords(grid, old)
        for _, t in ipairs(Grid.footprintTiles(grid, odef, ox, oy)) do
          outlineTile(camera, t, grid, theme.colors.accent, 3) -- the building that goes away
        end
      end
      if replaceTag then
        local wx = camera:tileToWorld(x, y)
        local z = camera:zoom()
        love.graphics.push()
        love.graphics.translate(wx, bottom - sprite.h)
        love.graphics.scale(1 / z, 1 / z)
        local tw, th = Text.measure(replaceTag, "small")
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, -th - 4, tw + 6, th + 2)
        Text.draw(replaceTag, 3, -th - 3, { size = "small", color = theme.colors.accent })
        love.graphics.pop()
      end
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

-- The tool wheel (GDD §9.4, D138, #294) ---------------------------------------------------

--- The wheel's wedge for the tool in hand.
function Homestead:currentTool()
  if self.mode == "place" or HAMMER_MODES[self.tool] then
    return "hammer"
  elseif self.mode == "plan" or self.seed or self.tool == "untill" then
    return "hoe"
  elseif self.tool == "rod" or self.tool == "pail" or self.tool == "axe" then
    return self.tool
  end
  return "hand"
end

--- The crops whose packets the Hoe's ring and the tools tray list: every crop with seed in the store, and every crop
--- whose seed is learned (D177). An unlearned crop with no seed stays off both, so the packets never name it (D117).
function Homestead:seedCrops()
  local world, list = self.world, {}
  for _, crop in ipairs(world.registry:all("crops")) do
    if Ledger.get(world, crop.seed) > 0 or Journal.isKnown(world, crop.id .. "_seeds") then
      list[#list + 1] = crop
    end
  end
  return list
end

--- The seed the Hoe takes when no packet is chosen: the last one used while it lasts, else the first crop
--- with seed to sow, else the first crop.
function Homestead:defaultSeed()
  local world = self.world
  local crops = world.registry:all("crops")
  local function has(id)
    return Ledger.get(world, world.registry:get("crops", id).seed) > 0
  end
  if self.lastSeed and has(self.lastSeed) then
    return self.lastSeed
  end
  for _, crop in ipairs(crops) do
    if has(crop.id) then
      return crop.id
    end
  end
  return crops[1] and crops[1].id
end

--- The ring a wedge fans out past the wheel: the Hoe's seed packets, then Untill and Plan field. More than
--- fit end in More, which opens the full tray. { { kind, crop?, icon, label } }.
function Homestead:ringItems(id)
  if id == "hammer" then
    return self:hammerRing()
  elseif id ~= "hoe" then
    return {}
  end
  local world, ui = self.world, self.app.ctx.tuning.ui
  local L = ui.labels
  local seeds = {}
  for _, crop in ipairs(self:seedCrops()) do
    seeds[#seeds + 1] = {
      kind = "seed",
      crop = crop.id,
      icon = Icons.packet(crop.id),
      label = crop.name .. " " .. Ledger.get(world, crop.seed),
      count = Ledger.get(world, crop.seed),
    }
  end
  local tail = {
    { kind = "untill", icon = "icon_verb_untill", label = L.untill },
    { kind = "plan", icon = "icon_verb_plan", label = L.plan },
  }
  local room = ui.wheel.maxRing - #tail
  local items = {}
  for i, s in ipairs(seeds) do
    if #seeds > room and i >= room then
      items[#items + 1] = { kind = "more", icon = "icon_tool_hoe", label = L.more }
      break
    end
    items[#items + 1] = s
  end
  for _, t in ipairs(tail) do
    items[#items + 1] = t
  end
  return items
end

--- The Hammer's ring (D139): each item in the crate as a thumbnail of its world sprite with its count, then
--- Move, Pick up, Demolish and Order more. A crate too big to show ends in More, which opens the tools tray.
function Homestead:hammerRing()
  local world, ui = self.world, self.app.ctx.tuning.ui
  local L = ui.labels
  local tail = {
    { kind = "move", icon = "icon_verb_move", label = L.hammerMove },
    { kind = "pickup", icon = "icon_verb_pickup", label = L.hammerPickUp },
    { kind = "demolish", icon = "icon_verb_demolish", label = L.hammerDemolish },
    { kind = "order", icon = "icon_book_ledger", label = L.orderMore },
  }
  local crate = self:crateItems()
  local room = ui.wheel.maxRing - #tail
  local items = {}
  for i, c in ipairs(crate) do
    if #crate > room and i >= room then
      items[#items + 1] = { kind = "more", icon = "icon_crate", label = L.more }
      break
    end
    local name = world.registry:get("objects", c.id).name
    items[#items + 1] = { kind = "crate", object = c.id, sprite = c.id, label = name, count = c.count }
  end
  for _, t in ipairs(tail) do
    items[#items + 1] = t
  end
  return items
end

--- Open the wheel with the Hammer's ring showing, at the middle of the view (a delivery stamp, an empty crate).
function Homestead:openHammerRing()
  local view = self.app.view
  self:openWheel(view.w / 2, view.h / 2, false)
  self.wheel.highlight = "hammer"
end

--- Take a tool from the wheel or a key (D138): `id` is a wedge, `item` a ring item or nil.
function Homestead:equip(id, item)
  self.palette = nil
  if id == "hand" then
    self:setHand(nil, nil)
  elseif id == "hoe" then
    local kind = item and item.kind
    if kind == "untill" then
      self:setHand(nil, "untill")
    elseif kind == "more" then
      self.palette = "tools"
      self:layout()
    elseif kind == "plan" then
      if self.mode ~= "plan" then
        self:setHand(self.seed or self:defaultSeed(), nil)
      end
      self:pressPlan(love.timer.getTime())
    else
      local crop = item and item.crop or self.seed or self:defaultSeed()
      self.lastSeed = crop
      self:setHand(crop, nil)
    end
  elseif id == "pail" or id == "axe" or id == "rod" then
    self:setHand(nil, id)
  elseif id == "hammer" then
    -- D139: a crate item holds its ghost; Move, Pick up and Demolish are modes; Order more opens the Catalog.
    -- The Hammer alone takes the first item in the crate, or shows its ring when the crate is empty.
    local kind = item and item.kind
    local placeable = kind == "crate" and item.object or (kind == nil and self:nextPlaceable())
    if placeable then
      self:startPlacing(placeable)
    elseif HAMMER_MODES[kind] then
      self:setHand(nil, kind)
    elseif kind == "order" then
      self:openPanel("buildings")
    elseif kind == "more" then
      self.palette = "tools"
      self:layout()
    else
      self:openHammerRing()
    end
  end
end

--- Equip by a label the old toolbar used ("Hand", "Rod", "Untill", "Plan field", "Place campfire", "Move",
--- "Pick up", "Demolish", "Order more"), for the
--- screenshot driver and keyboard-free scripts. Returns whether a label matched.
function Homestead:equipByLabel(label)
  local L = self.app.ctx.tuning.ui.labels
  local want = label:lower()
  if want == L.hand:lower() then
    self:equip("hand")
  elseif want == L.rod:lower() then
    self:equip("rod")
  elseif want == L.untill:lower() then
    self:equip("hoe", { kind = "untill" })
  elseif want == L.plan:lower() then
    self:equip("hoe", { kind = "plan" })
  elseif want == L.pail:lower() or want == L.axe:lower() then
    self:equip(want)
  elseif want == L.hammerMove:lower() or want == L.hammerPickUp:lower() or want == L.hammerDemolish:lower() then
    local kinds = { [L.hammerMove:lower()] = "move", [L.hammerPickUp:lower()] = "pickup" }
    self:equip("hammer", { kind = kinds[want] or "demolish" })
  elseif want == L.orderMore:lower() then
    self:equip("hammer", { kind = "order" })
  elseif want:find("^" .. L.place:lower() .. " ") then
    local name = want:sub(#L.place + 2)
    for _, c in ipairs(self:crateItems()) do
      if self.world.registry:get("objects", c.id).name:lower() == name then
        self:equip("hammer", { kind = "crate", object = c.id })
        return true
      end
    end
    return false
  else
    return false
  end
  return true
end

--- Does a right press or a long-press at (x, y) open the wheel here (Input asks, D138)? Over the world only,
--- with no panel, card or tray in the way.
function Homestead:wantsWheel(x, y)
  return self.app:top() == self
    and not self.palette
    and not (self.card and self:overCard(x, y))
    and self:inWorldArea(x, y)
    and self:chipAt(x, y) == nil
end

--- Open the wheel at (x, y): held (the pointer chooses on release) or sticky (a tap chooses, D138).
function Homestead:openWheel(x, y, held)
  local view = self.app.view
  local cfg = self.app.ctx.tuning.ui.wheel
  local sizes = ToolWheel.sizes(cfg, view)
  local cx, cy = ToolWheel.centre(x, y, view, sizes, self.app.ctx.tuning.ui.hud.pad)
  self.palette = nil
  self.wheel = {
    cx = cx,
    cy = cy,
    px = x,
    py = y,
    at = love.timer.getTime(),
    held = held,
    highlight = held and nil or self:currentTool(),
  }
  self:layout()
end

--- Point the wheel at (x, y): which wedge and ring item would be taken.
function Homestead:aimWheel(x, y)
  local w = self.wheel
  local cfg = self.app.ctx.tuning.ui.wheel
  local sizes = ToolWheel.sizes(cfg, self.app.view)
  local counts = { hoe = #self:ringItems("hoe") }
  local sticky = w.highlight
  local spread = ToolWheel.spread(cfg, counts[sticky] or 0)
  w.px, w.py = x, y
  w.highlight, w.sub = ToolWheel.pick(w.cx, w.cy, x, y, cfg.wedges, sizes, counts, spread, sticky)
  if not w.highlight then
    w.highlight, w.sub = sticky, nil -- the middle keeps the last choice in sight; letting go there cancels
    w.cancel = true
  else
    w.cancel = false
  end
end

--- Take what the wheel points at and close it (or just close it from the middle).
function Homestead:releaseWheel()
  local w = self.wheel
  self.wheel = nil
  if w and w.highlight and not w.cancel then
    local items = self:ringItems(w.highlight)
    self:equip(w.highlight, w.sub and items[w.sub] or nil)
  else
    self:layout()
  end
end

--- A tap on a sticky wheel (opened by the tool badge or a key): a wedge or ring item takes it, elsewhere
--- closes the wheel.
function Homestead:tapWheel(x, y)
  local lay = self.wheelLayout
  local w = self.wheel
  if lay then
    for id, r in pairs(lay.wedges) do
      if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
        if self:ringItems(id)[1] and w.highlight ~= id then
          w.highlight, w.sub = id, nil -- a tool with a ring: the first tap shows its ring
          return
        end
        self.wheel = nil
        self:equip(id)
        return
      end
    end
    for k, r in ipairs(lay.ring) do
      if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
        self.wheel = nil
        self:equip(w.highlight, self:ringItems(w.highlight)[k])
        return
      end
    end
  end
  self.wheel = nil
  self:layout()
end

--- Input while the wheel is open; returns true when it took the action.
function Homestead:wheelAction(name, data)
  local w = self.wheel
  if name == "wheelMove" and w then
    self:aimWheel(data.x, data.y)
    return true
  elseif name == "wheelRelease" and w then
    self:aimWheel(data.x, data.y)
    self:releaseWheel()
    return true
  end
  if not w or w.held then
    return false
  end
  if name == "hover" then
    local lay = self.wheelLayout
    local function over(r)
      return data.x >= r.x and data.x < r.x + r.w and data.y >= r.y and data.y < r.y + r.h
    end
    for id, r in pairs(lay and lay.wedges or {}) do
      if over(r) and id ~= w.highlight then
        w.highlight, w.sub = id, nil
      end
    end
    for k, r in ipairs(lay and lay.ring or {}) do
      if over(r) then
        w.sub = k
      end
    end
    return true
  elseif name == "select" then
    self:tapWheel(data.x, data.y)
    return true
  elseif name == "press" or name == "release" or name == "pan" or name == "context" then
    return true -- the open wheel is solid
  elseif name == "cancel" or name == "toolWheel" then
    self.wheel = nil
    self:layout()
    return true
  end
  return false
end

--- The wheel over everything: the world dims round it, the six tools on plates (2x icons), the ring of the
--- highlighted tool, and its name under the ring. A held wheel waits `showDelay` before it shows, so a quick
--- flick equips without it.
function Homestead:drawWheel()
  local w = self.wheel
  self.wheelLayout = nil
  local ui = self.app.ctx.tuning.ui
  local cfg = ui.wheel
  if w then
    if w.held and love.timer.getTime() - w.at < cfg.showDelay then
      return
    end
    local last = self.wheelLast -- kept (in one table) to draw the wheel dissolving away once it is let go
    last.cx, last.cy, last.px, last.py, last.held, last.highlight, last.sub =
      w.cx, w.cy, w.px, w.py, w.held, w.highlight, w.sub
  else
    w = self.wheelLast.cx and self.wheelLast -- a closed wheel: only the dissolve is left
  end
  if not w or not Dissolve.begin(self.wheelFade:coverage()) then
    if not self.wheelFade:shown() then
      self.wheelLast.cx = nil
    end
    return
  end
  local closing = self.wheel == nil
  local colors = theme.colors
  local world, view = self.world, self.app.view
  local sizes = ToolWheel.sizes(cfg, view)
  local items = self:ringItems(w.highlight)
  local spread = ToolWheel.spread(cfg, #items)
  local lay = ToolWheel.layout(w.cx, w.cy, cfg.wedges, sizes, w.highlight, #items, spread, w.highlight)
  self.wheelLayout = not closing and lay or nil
  local crate = self:crateCount()
  -- The world behind dims in two stepped bands round the wheel.
  love.graphics.setColor(cfg.dim)
  love.graphics.circle("fill", w.cx, w.cy, sizes.ring + sizes.ringItem / 2 + 6, 40)
  love.graphics.circle("fill", w.cx, w.cy, sizes.radius + sizes.selected / 2 + 6, 32)
  for _, wedge in ipairs(cfg.wedges) do
    local r = lay.wedges[wedge.id]
    local on = wedge.id == w.highlight
    Plate.draw(r.x, r.y, r.w, r.h, {
      ink = on and colors.accent or nil,
      lit = on and 0.35 or nil,
      base = on and colors.buttonHover or nil,
      weather = false,
    })
    local icon = Icons.tool(world, wedge.id)
    local sp = Assets.sprite(icon)
    Icons.draw(icon, r.x + math.floor((r.w - 2 * sp.w) / 2), r.y + math.floor((r.h - 2 * sp.h) / 2), 2)
    if wedge.id == "hammer" and crate > 0 then
      self:drawCount(crate, r.x + r.w, r.y + r.h) -- deliveries waiting in the crate (D139)
    end
  end
  for k, r in ipairs(lay.ring) do
    local item = items[k]
    local on = k == w.sub
    Plate.draw(r.x, r.y, r.w, r.h, { ink = on and colors.accent or nil, lit = on and 0.35 or nil, weather = false })
    if item.sprite then
      Icons.drawFit(item.sprite, r.x + 1, r.y + 1, r.w - 2, r.h - 2, 2) -- a crate item: its world sprite (D139)
    else
      local sp = Assets.sprite(item.icon)
      local scale = r.w >= 2 * sp.w + 4 and 2 or 1
      local ix, iy = r.x + math.floor((r.w - scale * sp.w) / 2), r.y + math.floor((r.h - scale * sp.h) / 2)
      Icons.draw(item.icon, ix, iy, scale)
    end
    if item.count then
      local text = tostring(item.count)
      local tw = Text.measure(text, "small")
      Text.draw(text, r.x + r.w - tw - 2, r.y + r.h - 10, {
        size = "small",
        color = item.count > 0 and colors.text or colors.danger,
      })
    end
  end
  -- The name of what would be taken, under the wheel, or over it when under would reach the tool badge.
  local name = w.highlight and ui.labels[w.highlight] or ""
  if w.sub and items[w.sub] then
    name = name .. " · " .. items[w.sub].label
  end
  if name ~= "" then
    local tw, th = Text.measure(name, "body")
    local lx = math.floor(w.cx - tw / 2 - ui.hud.textPad)
    local ly = math.floor(w.cy + sizes.radius + sizes.selected / 2 + 6)
    if lay.ring[1] and w.sub then
      ly = math.floor(w.cy + sizes.ring + sizes.ringItem / 2 + 4)
    end
    local badge = self.hud.tool
    local floor = (badge and badge.y or view.h) - th - 12
    if ly > floor then
      local top = (lay.ring[1] and w.sub) and sizes.ring + sizes.ringItem / 2 or sizes.radius + sizes.selected / 2
      ly = math.max(math.floor(w.cy - top - th - 12), 0)
    end
    Plate.draw(lx, ly, tw + 2 * ui.hud.textPad, th + 6, { weather = false })
    Text.draw(name, lx + ui.hud.textPad, ly + 4, { color = colors.accent })
  end
  -- Where the pointer is, while the wheel is held.
  if w.held then
    love.graphics.setColor(colors.accent)
    love.graphics.rectangle("fill", math.floor(w.px) - 1, math.floor(w.py) - 1, 3, 3)
  end
  Dissolve.finish()
end

-- Drawing the resting HUD (D137, D142) -------------------------------------------------------

--- A tap target's plate in its state: pressed, selected (amber outline), signalling, or off. `opts.signal` is
--- "amber" (attention: a quiet outline with a glint) or "red" (danger: a slow beat); a button that `pulse`s
--- signals amber (D142). Nothing flashes (src/ui/motion.lua).
function Homestead:hudPlate(b, opts)
  opts = opts or {}
  local colors = theme.colors
  local ink = opts.ink
  if b.selected then
    ink = colors.accent
  end
  local signal = opts.signal or (b.pulse and "amber") or nil
  local gx, gy
  if signal and not b.selected then
    ink, gx, gy = Motion.signal(signal, b.w, b.h, b.x * 31 + b.y)
  end
  local pressed = self.buttons.pressed == b
  Plate.draw(b.x, b.y, b.w, b.h, {
    ink = ink,
    base = pressed and colors.buttonPressed or opts.base,
    lit = pressed and 0 or nil,
    glintX = gx,
    glintY = gy,
  })
end

--- An icon centred on its plate, or at the left with words after it.
function Homestead:drawIconPlate(b, icon, words)
  self:hudPlate(b)
  local H = self.app.ctx.tuning.ui.hud
  local sp = Assets.sprite(icon)
  local iy = math.floor(b.y + (b.h - sp.h) / 2)
  if words then
    Icons.draw(icon, b.x + H.textPad, iy)
    local _, th = Text.measure(words, "body")
    Text.draw(words, b.x + 2 * H.textPad + sp.w, b.y + math.floor((b.h - th) / 2) + 1)
  else
    Icons.draw(icon, math.floor(b.x + (b.w - sp.w) / 2), iy)
  end
end

--- The clock: the date, then the time and the forecast glyphs (today first, the days after quieter).
function Homestead:drawClock(b, weather)
  self:hudPlate(b)
  local H, ui = self.app.ctx.tuning.ui.hud, self.app.ctx.tuning.ui
  local now = Calendar.now(self.world)
  local hour = math.floor(now.hour)
  local minute = math.floor((now.hour - hour) * 60)
  local x = b.x + H.textPad
  Text.draw(self:dateText(), x, b.y + 3)
  local time = string.format("%02d:%02d", hour, minute)
  Text.draw(time, x, b.y + 14, { color = theme.colors.textDim })
  if weather then
    local ix = x + Text.measure("00:00", "body") + H.gap
    for n, id in ipairs(weather.icons or { weather.icon }) do
      local sp = Assets.sprite(id)
      Icons.draw(id, ix, b.y + 13, 1, n > 1 and 0.65 or 1)
      ix = ix + sp.w + ui.topChips.iconGap
    end
  end
end

--- One speed button: pause bars, a play triangle, or the fast arrows (with the speed while fast).
function Homestead:drawSpeedSegment(b, glyph, speed)
  self:hudPlate(b)
  local colors = theme.colors
  local on = b.selected
  local c = not b.enabled and colors.textDim or on and colors.accent or colors.text
  local cx, cy = math.floor(b.x + b.w / 2), math.floor(b.y + b.h / 2)
  love.graphics.setColor(c)
  if glyph == "pause" then
    love.graphics.rectangle("fill", cx - 3, cy - 4, 2, 8)
    love.graphics.rectangle("fill", cx + 1, cy - 4, 2, 8)
  elseif glyph == "play" then
    for k = 0, 4 do
      love.graphics.rectangle("fill", cx - 2 + k, cy - 4 + k, 1, 9 - 2 * k)
    end
  elseif on and speed > 1 then
    local label = string.format("%gx", speed)
    local tw, th = Text.measure(label, "small")
    Text.draw(label, math.floor(cx - tw / 2), math.floor(cy - th / 2) + 1, { size = "small", color = c })
  else
    for k = 0, 3 do
      love.graphics.rectangle("fill", cx - 5 + k, cy - 3 + k, 1, 7 - 2 * k)
      love.graphics.rectangle("fill", cx + k, cy - 3 + k, 1, 7 - 2 * k)
    end
  end
end

--- A decision stamp: its signal icon, and its words while there is room.
function Homestead:drawStamp(b, stamp, compact)
  local colors = theme.colors
  local signal = (stamp.color == colors.danger and "red") or (stamp.color == colors.accent and "amber") or nil
  self:hudPlate(b, { ink = stamp.color, signal = signal })
  local H = self.app.ctx.tuning.ui.hud
  local sp = Assets.sprite(stamp.icon)
  local ix = compact and math.floor(b.x + (b.w - sp.w) / 2) or b.x + math.floor((H.stampSize - sp.w) / 2)
  Icons.draw(stamp.icon, ix, math.floor(b.y + (b.h - sp.h) / 2))
  if not compact then
    local _, th = Text.measure(stamp.label, "small")
    Text.draw(stamp.label, b.x + H.stampSize, b.y + math.floor((b.h - th) / 2) + 1, {
      size = "small",
      color = stamp.color,
    })
  end
end

--- The homesteader badge's two lines: the state (Routine, Hands-on, Asleep, Resting, Paused) and what is
--- happening (the job, the countdown to the routine, or nothing to do).
function Homestead:badgeLines()
  local H = self.app.ctx.tuning.ui.hud
  local world = self.world
  local hs = Actors.homesteader(world)
  local function job()
    if not hs.job then
      return nil
    end
    if hs.job.task == "move" then
      return H.walking
    end
    local def = Tasks.get(world, hs.job.task)
    local category = type(def) == "table" and rawget(def, "category")
    return category and rawget(H.jobs, category) or "Working"
  end
  if hs.asleep then
    return H.states.asleep, self:untilMorningText()
  elseif self.session:effectiveSpeed() == 0 then -- also true in town (D78)
    return H.states.paused, job() or ""
  elseif world.control == "idle" then
    if self:hintKind() == "nothing" then
      return H.states.routine, H.idleLine
    end
    return H.states.routine, job() or H.walking
  elseif not self.session:canStartRoutine() then
    return H.states.resting, job() or ""
  end
  local remaining = math.max(0, math.ceil(self:takeoverDelay() - self.app.ctx.input:idleSeconds()))
  return H.states.handsOn, job() or string.format(H.countdownLine, remaining)
end

--- The homesteader badge: the portrait inside the idle countdown ring, and two lines while there is room.
function Homestead:drawBadge(b, compact)
  self:hudPlate(b)
  local H = self.app.ctx.tuning.ui.hud
  local colors = theme.colors
  local sp = Assets.sprite("homesteader")
  local px = compact and math.floor(b.x + (b.w - sp.w) / 2) or b.x + H.textPad
  local py = math.floor(b.y + (b.h - sp.h) / 2)
  Icons.draw("homesteader", px, py)
  -- The countdown ring: the share of the takeover delay still to run, as a stepped arc round the portrait.
  local world = self.world
  if world.control ~= "idle" and self.session:canStartRoutine() and self.session:effectiveSpeed() > 0 then
    local delay = self:takeoverDelay()
    local left = math.max(0, math.min(1, 1 - self.app.ctx.input:idleSeconds() / delay))
    local cx, cy = px + sp.w / 2, py + sp.h / 2
    for k = 0, H.countdownSteps - 1 do
      local a = -math.pi / 2 + k / H.countdownSteps * 2 * math.pi
      local lit = k / H.countdownSteps < left
      love.graphics.setColor(lit and colors.accent or colors.panelBorder)
      love.graphics.rectangle(
        "fill",
        math.floor(cx + math.cos(a) * H.countdownRadius),
        math.floor(cy + math.sin(a) * H.countdownRadius),
        1,
        1
      )
    end
  end
  if not compact then
    local state, line2 = self:badgeLines()
    local tx = px + sp.w + 2 * H.textPad
    Text.draw(state, tx, b.y + 4)
    Text.draw(line2, tx, b.y + 16, { size = "small", color = colors.textDim })
  end
end

--- The tool badge: the tool in hand (and its seed packet), and its name while there is room.
function Homestead:drawToolBadge(b, compact)
  self:hudPlate(b)
  local H = self.app.ctx.tuning.ui.hud
  local icon, extra, label = self:toolInHand()
  local sp = Assets.sprite(icon)
  local ew = extra and Assets.sprite(extra).w + 2 or 0
  local x = compact and math.floor(b.x + (b.w - sp.w - ew) / 2) or b.x + H.textPad
  local iy = math.floor(b.y + (b.h - sp.h) / 2)
  Icons.draw(icon, x, iy)
  if extra then
    Icons.draw(extra, x + sp.w + 2, iy)
  end
  if not compact then
    local _, th = Text.measure(label, "body")
    Text.draw(label, x + sp.w + ew + H.textPad, b.y + math.floor((b.h - th) / 2) + 1)
  end
  local crate = self:crateCount()
  if crate > 0 then
    self:drawCount(crate, b.x + b.w, b.y + b.h) -- deliveries waiting in the crate (D139)
  end
end

--- A count tag (amber, on a small plate) whose bottom-right corner sits at (right, bottom), just inside a plate.
function Homestead:drawCount(n, right, bottom)
  local text = tostring(n)
  local tw, th = Text.measure(text, "small")
  local w, h = tw + 4, th + 3
  local x, y = math.floor(right - w + 2), math.floor(bottom - h + 2)
  Plate.draw(x, y, w, h, { ink = theme.colors.accent, weather = false })
  Text.draw(text, x + 2, y + 2, { size = "small", color = theme.colors.accent })
end

--- The vitals plates (D112 chips): icon, value, level mark and thin gauge, drawn fresh each frame.
function Homestead:drawVitals()
  local world = self.world
  local byId = {}
  for _, e in ipairs(self:vitalEntries()) do
    byId[e.id] = e
  end
  for _, row in ipairs(self.hud.vitals) do
    local worst = 0 -- the row's plate signals its worst vital: amber for a warning, red for danger (D112, D142)
    for _, item in ipairs(row.items) do
      local e = byId[item.id]
      worst = e and math.max(worst, e.level or 0) or worst
    end
    if worst > 0 then
      local ink, gx, gy = Motion.signal(worst >= 2 and "red" or "amber", row.w, row.h, row.x * 31 + row.y)
      Plate.draw(row.x, row.y, row.w, row.h, { ink = ink, glintX = gx, glintY = gy })
    else
      Plate.draw(row.x, row.y, row.w, row.h)
    end
    for _, item in ipairs(row.items) do
      local e = byId[item.id]
      if e then
        ChipStrip.draw(world, e, item.x, row.y + 5)
      end
    end
  end
end

--- What the next tap does with the tool in hand (D72, #168), on a plate above the tool badge. Hidden while
--- the wheel is open: the wheel names what would be taken instead.
function Homestead:drawCaption()
  local r = self.hud.caption
  if not (r and self.hudCaption) or self.wheel then
    return
  end
  Plate.draw(r.x, r.y, r.w, r.h)
  local _, th = Text.measure(self.hudCaption, "small")
  Text.draw(self.hudCaption, r.x, r.y + math.floor((r.h - th) / 2) + 1, {
    size = "small",
    width = r.w,
    align = "center",
  })
end

--- The tap targets of the vitals, { { id, x, y, w, h } }: each vital plus half the gap on either side, at
--- least the minimum touch size tall, so a finger can hit one (D72, #158).
function Homestead:chipRects()
  local minSize = self.app.ctx.tuning.input.minTouchTarget
  local gap = self.app.ctx.tuning.ui.hud.vitalGap
  local rects = {}
  for _, row in ipairs(self.hud and self.hud.vitals or {}) do
    local h = math.max(minSize, row.h)
    for _, item in ipairs(row.items) do
      local w = math.max(minSize, item.w + gap)
      rects[#rects + 1] = {
        id = item.id,
        x = item.x - (w - item.w) / 2,
        y = row.y + (row.h - h) / 2,
        w = w,
        h = h,
      }
    end
  end
  return rects
end

--- The vital under a point, or nil.
function Homestead:chipAt(x, y)
  for _, r in ipairs(self:chipRects()) do
    if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
      return r.id
    end
  end
  return nil
end

--- Is the point over the world, not over a HUD plate (the plates float over the land)?
function Homestead:inWorldArea(x, y)
  if not (x and y) then
    return false
  end
  if self.lens:active() and self.lensCard:contains(x, y) then
    return false
  end
  if self:overTonight(x, y) or self:overEvent(x, y) then
    return false
  end
  for _, b in ipairs(self.buttons.list) do
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
      return false
    end
  end
  for _, row in ipairs(self.hud and self.hud.vitals or {}) do
    if x >= row.x and x < row.x + row.w and y >= row.y and y < row.y + row.h then
      return false
    end
  end
  local c = self.hud and self.hud.caption
  if c and x >= c.x and x < c.x + c.w and y >= c.y and y < c.y + c.h then
    return false
  end
  return true
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
    tone = card.level >= 2 and theme.colors.danger or card.level == 1 and theme.colors.accent or theme.colors.text,
    rows = card.rows,
    why = card.why,
    width = app.ctx.tuning.ui.modal.width,
    okLabel = "Got it",
    more = more,
  }))
end

--- Open a panel by name from a shortcut. A name in tuning.ui.book.shortcuts ("pantry" | "routine" | "catalog" |
--- "buildings" | "truck" | "journal" | "fish" | "diary") opens its book on that page (D143); "buildings" is the
--- Hammer's Order more, the Catalog scrolled to its first building (D139). Also "power" and "load".
function Homestead:openPanel(name)
  local world, app = self.world, self.app
  if name == "power" or name == "water" then
    self:showLens(name)
  elseif name == "load" then
    app:push(require("src.scenes.load").new(world, self:toaster()))
  else
    self:openBook(name, name == "buildings" and { buildings = true } or nil)
  end
end

--- Open a book: by shortcut name (on that page) or by book id, "notebook" | "ledger" (on the page it was last left
--- on). `catalogOpts` goes to the Catalog page.
function Homestead:openBook(name, catalogOpts)
  Book.open(self.app, name, catalogOpts)
end

-- Storage pills (D59): which stores are full, and what is being held back for lack of room.
-- Returns { { text, color } } in the same shape as the weather pills; empty when all is well.
function Homestead:storageNotes()
  local world = self.world
  local notes, full = {}, {}
  -- Only stores that are actually holding something back are listed (D93, #135): a finished batch's
  -- output, or a harvest/pick/catch that has no room. A merely full store (spare wood) is quiet.
  local now = world.state.calendar.elapsed
  if not self.blockingAt or math.abs(now - self.blockingAt) >= self.app.ctx.tuning.ui.storageNoteRefresh then
    self.blockingAt = now
    self.blocking = Tasks.blockedResources(world, Actors.homesteader(world))
    for _, batch in ipairs(Processing.blockedBatches(world)) do
      self.blocking[batch.output] = true
    end
  end
  for _, res in ipairs(world.registry:all("resources")) do
    -- A full coop is not a warning (it only holds new hens at the gate), so hens are left out.
    if res.id ~= "water" and res.category ~= "animal" and self.blocking[res.id] and Ledger.isFull(world, res.id) then
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
    notes[#notes + 1] =
      { "Order waiting for room: " .. table.concat(names, ", ") .. " · cancel in Catalog", theme.colors.accent }
  end
  for _, batch in ipairs(Processing.blockedBatches(world)) do
    notes[#notes + 1] = {
      string.format(
        "%d %s waiting in the station for room",
        batch.count,
        world.registry:get("resources", batch.output).name
      ),
      theme.colors.accent,
    }
  end
  return notes
end

-- Winter forecast under the decision stamps, from autumn on (GDD §4.1); loud during the cold snap.
function Homestead:drawForecast()
  local world = self.world
  -- The weather is a chip in the top bar now (D112): today and the days ahead as glyphs, the words in its modal.
  local lines = {}
  if Sandbox.on(world) then
    lines[1] = { self.app.ctx.tuning.ui.sandbox.tag, theme.colors.accent } -- a sandbox slot says so (D134)
  end
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
  -- Winter readiness and full stores wait on the player, so they are decision stamps now (D137).
  local pad = self.app.ctx.tuning.ui.hud.pad
  local y = self.hud.stampsBottom
  for _, line in ipairs(lines) do
    local text, color = line[1], line[2]
    local w = Text.measure(text, "small") + 12
    Plate.draw(pad, y, w, 14)
    Text.draw(text, pad, y + 3, { size = "small", width = w, align = "center", color = color })
    y = y + 16
  end
  self.forecastBottom = y -- the sleep banner sits below the pills, so they never overlap on a narrow view
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
--- is left and how fast time is passing (D56).
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
  Plate.draw(x, y, w, h + 8)
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
    return string.format(self.moving and c.moving or c.place, world.registry:get("objects", self.placing).name:lower())
  elseif self.mode == "plan" then
    if self.planLatch then
      return c.planKept
    end
    return self.seed and string.format(c.planSeed, crop(self.seed)) or c.planClear
  elseif self.tool == "rod" then
    return c.rod
  elseif self.tool == "untill" then
    return c.untill
  elseif self.tool == "pail" then
    return c.pail
  elseif self.tool == "axe" then
    return c.axe
  elseif HAMMER_MODES[self.tool] then
    return c[self.tool]
  elseif self.seed then
    return string.format(c.seed, crop(self.seed))
  end
  return nil
end

function Homestead:tileInfo(i)
  local world = self.world
  local grid = world.state.grid
  local lines = {}
  local queued = Placement.orderAt(world, i)
  if queued then
    lines[#lines + 1] =
      string.format(self.app.ctx.tuning.ui.placement.orderTitle, world.registry:get("objects", queued.object).name)
  end
  local terrain = Grid.terrain(world, i)
  lines[#lines + 1] = world.state.fields.tilled[i] and "Tilled soil" or terrain.name
  local mark = Marks.kindAt(world, i)
  if mark then
    lines[#lines + 1] = self.app.ctx.tuning.ui.placement[mark == "clear" and "markClear" or "markWater"]
  end
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
      lines[#lines + 1] = state == "ok" and "Powered"
        or state == "short" and string.format("Short of power (%d%%)", ratio)
        or state == "off" and "Switched off"
        or "Idle"
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
    if Water.irrigationKind(obj) then
      local mode = Water.dripState(world, anchor)
      lines[#lines + 1] = string.format("Uses %g water per crop", Water.unitsPerWatering(world, anchor))
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
      lines[#lines + 1] = today < cap and string.format("Up to %d today (cap %d)", today, cap)
        or string.format("Sells up to %d a day", cap)
      lines[#lines + 1] =
        string.format("Pays %d%% of town price", math.floor(world.tuning.stand.priceFraction * 100 + 0.5))
      local have, missing = {}, {}
      for _, tier in ipairs(Stand.tiers(world)) do
        local list = tier.owned and have or missing
        list[#list + 1] = tier.name:lower()
      end
      lines[#lines + 1] = string.format("Upgrades: %s", #have > 0 and table.concat(have, ", ") or "none yet")
      if #missing > 0 then
        lines[#lines + 1] = "Can add: " .. table.concat(missing, ", ")
      end
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
      -- D104: wood burned tonight in this fire, from the shared outlook's warmth need.
      local fuelHeat = world.registry:get("resources", Needs.fuelId(world)).heat
      local wood = math.ceil(Needs.warmthNeeded(world) / (fuelHeat * obj.heatSource.efficiency) - 1e-9)
      lines[#lines + 1] = string.format("Efficiency x%.1f · burns %d wood tonight", obj.heatSource.efficiency, wood)
    end
    if obj.storage and obj.storage.wood then
      local id = Needs.fuelId(world)
      lines[#lines + 1] = string.format(
        "Dry store: +%d wood (holds %d / %d)",
        obj.storage.wood,
        Ledger.get(world, id),
        Ledger.capacity(world, id)
      )
    end
    if obj.heatSource or (obj.sink and obj.sink.effects and obj.sink.effects.warmthPerKwh) then
      local reach = Shelter.heatReach(world, anchor)
      lines[#lines + 1] = reach >= 1 and "Beside the bed: full heat"
        or string.format("Too far from bed: %d%%", math.floor(reach * 100 + 0.5))
    end
    if obj.shelter then -- the shelter ladder (D82)
      lines[#lines + 1] = obj.insulation < 1
          and string.format("Keeps heat: %d%% less fuel", math.floor((1 - obj.insulation) * 100 + 0.5))
        or "Keeps no heat"
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
      lines[#lines + 1] =
        string.format("%s: %d%%%s", def.name, math.floor(crop.growth * 100), crop.moisture > 0 and "" or ", thirsty")
    end
    lines[#lines + 1] = AlertText.cropFrostLine(world, crop) -- days to the freeze (D70, #165)
  elseif world.state.fields.plan[i] then
    local planned = world.state.fields.plan[i]
    lines[#lines + 1] = "Planned: " .. world.registry:get("crops", planned).name
    local risk = Crops.frostRisk(world, planned)
    if not Crops.inWindow(world, planned) and not Weather.isFrozen(world) then
      lines[#lines + 1] = "Not planted until " .. AlertText.windowSeasons(world, planned)
    elseif risk then
      lines[#lines + 1] = risk.level == "late" and "Too late: frost first" or "Close to frost"
    end
  end
  return lines
end

--- The selected station and its batch when the batch is finished and waiting for storage room (D93, #135).
function Homestead:blockedStation(tile)
  local obj, anchor = Grid.object(self.world, tile or self.selected)
  local batch = obj and obj.station and Processing.batch(self.world, anchor)
  if batch and batch.blocked then
    return anchor, batch
  end
end

--- Ask, then throw away the output a station is holding for room (D93, #135).
function Homestead:askDiscard(anchor, batch)
  local world = self.world
  local out = world.registry:get("resources", world.registry:get("recipes", batch.recipe).output).name
  self.app:push(require("src.scenes.confirm").new({
    title = "Discard waiting output?",
    message = string.format(
      "The %d %s waiting in the station will be thrown away. The station is free to work again.",
      batch.count,
      out:lower()
    ),
    confirmLabel = "Discard",
    danger = true,
    onConfirm = function()
      local count = Processing.discard(world, anchor)
      if count then
        self:showToast(string.format("Discarded %d %s", count, out:lower()))
      end
    end,
  }))
end

function Homestead:drawInfo(view)
  local info -- the tile card's rectangle, when it is up (a wide toast keeps clear of it)
  self.infoButtons = self.infoButtons or Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.infoButtons:clear()
  local selected = self.selected
  if selected then
    self.infoLast = selected -- kept to draw the card dissolving away
  else
    selected = self.infoLast
  end
  if selected and Dissolve.begin(self.infoFade:coverage()) then
    local lines = self:tileInfo(selected)
    local anchor, batch = self:blockedStation(selected)
    local minSize = self.app.ctx.tuning.input.minTouchTarget
    local def = Grid.object(self.world, selected)
    -- The card only informs (D139): a player-placed object says the Hammer moves, picks up or demolishes it.
    if def and def.placeable and self.mode ~= "place" and not Placement.orderAt(self.world, selected) then
      lines[#lines + 1] = self.app.ctx.tuning.ui.placement.hammerHint
    end
    local mark = Marks.kindAt(self.world, selected)
    local rows = (anchor and 1 or 0) + (mark and 1 or 0)
    local btnH = rows * (minSize + 4) -- room for the buttons under the lines
    local h = #lines * 11 + 8 + btnH
    local base = self.card and self.card.y or view.h - self.bottomH
    if self.tonightRect and self.tonightLayout == "sheet" then
      base = math.min(base, self.tonightRect.y) -- and above the Tonight sheet on a tall view
    end
    if self:eventShown() and self.eventLayout == "sheet" then
      base = math.min(base, self.eventRect.y) -- and the event sheet
    end
    local y = base - h - 4 -- above the tip card (or the tool caption) when one is up
    local w = 132
    for _, line in ipairs(lines) do
      w = math.max(w, Text.measure(line, "small") + 14) -- a long line widens the card rather than spilling out
    end
    if rows > 0 then
      w = math.max(w, 150)
    end
    Draw.panel(4, y, w, h)
    for n, line in ipairs(lines) do
      Text.draw(
        line,
        10,
        y + 4 + (n - 1) * 11,
        { size = "small", color = n == 1 and theme.colors.text or theme.colors.textDim }
      )
    end
    local buttonY = y + #lines * 11 + 6
    if mark then
      -- A mark is an order on the board: the card cancels it (D147). Dragging the same tool over it does too.
      self.infoButtons:add({
        x = 10,
        y = buttonY,
        w = w - 12,
        h = minSize,
        label = self.app.ctx.tuning.ui.placement.cancelMark,
        size = "small",
        onPress = function()
          Marks.remove(self.world, mark, { selected })
        end,
      })
      buttonY = buttonY + minSize + 4
    end
    if anchor then
      self.infoButtons:add({
        x = 10,
        y = buttonY,
        w = w - 12,
        h = minSize,
        label = "Discard waiting output",
        size = "small",
        style = "danger",
        onPress = function()
          self:askDiscard(anchor, batch)
        end,
      })
    end
    if rows > 0 then
      self.infoButtons:draw()
    end
    if not self.selected then
      self.infoButtons:clear() -- going away: nothing on it answers any more
    end
    Dissolve.finish()
    info = { x = 4, y = y, w = w, h = h }
  end
  if self.toast then
    -- A toast wider than the view wraps onto more lines (D70), growing upward from the usual line.
    local maxW = view.w - 16
    local w = math.min(Text.measure(self.toast.text, "body") + 16, maxW)
    local textH = Text.wrappedHeight(self.toast.text, "body", w - 16)
    local h = math.max(18, textH + 8)
    local x, y = (view.w - w) / 2, view.h - self.bottomH - h -- just above the bottom plates and the caption
    if self.lens:active() and self.lensLayout == "sheet" and self.lensRect then
      y = math.min(y, self.lensRect.y - 4 - h) -- a toast rides above the lens sheet on a tall view
    end
    if self.tonightRect and self.tonightLayout == "sheet" then
      y = math.min(y, self.tonightRect.y - 4 - h) -- and above the Tonight sheet
    end
    if self:eventShown() and self.eventLayout == "sheet" then
      y = math.min(y, self.eventRect.y - 4 - h) -- and the event sheet
    end
    if info and x < info.x + info.w and y + h > info.y then
      y = info.y - 4 - h -- a wide toast on a narrow view rides above the tile card instead of covering it
    end
    Plate.draw(x, y, w, h, { alpha = 0.92 * math.min(1, self.toast.time * 3), weather = false })
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
  self.renderer:drawMarkSketch({ x1, y1, x2, y2 }, 1) -- the Axe's and the Pail's marks, in pencil over the objects (D147)
  self:drawOverlays()
  love.graphics.pop()
  love.graphics.setCanvas()
  love.graphics.origin()
  local haze = self.renderer:heatHaze(self.camera, view, { x1, y1, x2, y2 }, daylight)
  -- Night lights are painted into the light buffer, which the grade reads (D128).
  love.graphics.push("all")
  self.camera:attach(view)
  local lights =
    self.renderer:paintLights({ x1, y1, x2, y2 }, daylight, self.canvas:getWidth(), self.canvas:getHeight())
  love.graphics.pop() -- the camera transform
  love.graphics.pop()
  local bloom = self.renderer:bloomOn()
  -- The graded frame goes into a canvas: with bloom, lit windows, flame cores and fireflies join it so the
  -- bloom can glow round them (D129); either way the HUD plates look through a blurred copy of it (D142).
  local graded = self.renderer:gradedBuffer(self.canvas:getWidth(), self.canvas:getHeight())
  love.graphics.push("all")
  love.graphics.setCanvas(graded)
  love.graphics.clear(0, 0, 0, 1)
  local ox, oy = self.renderer.screenGrid(self.camera, view)
  self.renderer:drawGraded(self.canvas, tint, light, view.scale * self.camera:zoom(), haze, lights, { ox, oy })
  if bloom then
    love.graphics.push("all")
    self.camera:attach(view)
    self.renderer:drawSunbeams({ x1, y1, x2, y2 })
    self.renderer:drawEmissive()
    self.renderer:drawAmbient({ x1, y1, x2, y2 }, daylight)
    love.graphics.pop() -- the camera transform
    love.graphics.pop()
  end
  love.graphics.pop() -- back from the graded canvas to the screen
  -- A lens (D141, D145) runs the graded frame through one more pass into a canvas of its own, which then stands
  -- in for the frame, so the plates look through the blueprint too.
  -- It dissolves in and out through the dither (D142): while it does, the graded frame stays under it.
  local lensId = self.lens:active() or (self.lensFade:shown() and self.lensLast) or nil
  local shown = graded
  local lensOn = lensId ~= nil
    and self.world.tuning.visuals.lens.enabled
    and self:lensPass(graded, ox, oy, daylight, lensId)
  if lensOn then
    shown = self.lensCanvas
    local cover = self.lensFade:coverage()
    if cover < 1 then
      shown = self:lensMix(graded, cover, view)
    end
  end
  if bloom and not lensOn then
    self.renderer:drawBloom(graded, daylight)
  else
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(shown, 0, 0)
  end
  Plate.capture(shown)
  love.graphics.pop()
  -- Lit windows, fireflies, dust and the selection outline sit over the graded world, in world space again.
  love.graphics.push("all")
  self.camera:attach(view)
  if not bloom and not lensOn then
    self.renderer:drawSunbeams({ x1, y1, x2, y2 })
    self.renderer:drawEmissive()
    self.renderer:drawAmbient({ x1, y1, x2, y2 }, daylight)
  end
  self.renderer:drawCropCues({ x1, y1, x2, y2 }, daylight)
  if lensOn then -- the lens repaints the world, so the marks go over it again, in chalk (D147)
    self.renderer:drawMarkSketch({ x1, y1, x2, y2 }, self.world.tuning.visuals.sketch.chalkShare, true)
  end
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

  -- HUD (not graded; its plates take a share of the world's light, D142)
  local snow, frozen = self.renderer:winterAmounts()
  Plate.setLight(tint, daylight, frozen, snow) -- the daylight level (0 night .. 1 day), so plates dim at night (D142)
  ActionRing.draw(self.world, self.camera, view, { top = self.topH, bottom = view.h - self.bottomH })
  self:drawVitals()
  self:drawForecast()
  self:drawCaption()
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
      self.paletteList:drawThumb(
        ui.scrollBarWidth,
        ui.scrollHintHeight,
        { x = r.x + r.w - ui.buttonGap, y = v.y, w = 0, h = v.h }
      )
    end
  end
  self.buttons:draw()
  self:drawCard()
  if self.tonightRect and self:tonightShown() then
    self.tonightCard:draw(view)
  end
  if self.eventRect and Dissolve.begin(self.eventFade:coverage()) then
    self.eventCard:draw(view)
    Dissolve.finish()
  end
  if self.lens:active() and Dissolve.begin(self.lensFade:coverage()) then
    self.lensCard:draw(view)
    Dissolve.finish()
  end
  self:drawWheel()
end

--- The graded frame with the lens dissolved over it at `cover` (0..1), in a canvas of its own.
function Homestead:lensMix(graded, cover, view)
  local w, h = graded:getDimensions()
  if not self.lensMixCanvas or self.lensMixCanvas:getWidth() ~= w or self.lensMixCanvas:getHeight() ~= h then
    self.lensMixCanvas = love.graphics.newCanvas(w, h)
    self.lensMixCanvas:setFilter("linear", "linear")
  end
  love.graphics.push("all")
  love.graphics.setCanvas(self.lensMixCanvas)
  love.graphics.origin()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(graded, 0, 0)
  if Dissolve.begin(cover, view.scale) then
    love.graphics.draw(self.lensCanvas, 0, 0)
    Dissolve.finish()
  end
  love.graphics.pop()
  return self.lensMixCanvas
end

--- Run the graded frame through the lens into `self.lensCanvas`. Returns false when the shader is missing.
function Homestead:lensPass(graded, ox, oy, daylight, id)
  local w, h = graded:getDimensions()
  if not self.lensCanvas or self.lensCanvas:getWidth() ~= w or self.lensCanvas:getHeight() ~= h then
    self.lensCanvas = love.graphics.newCanvas(w, h)
    self.lensCanvas:setFilter("linear", "linear")
  end
  local view = self.app.view
  local still = Settings.read("reduceMotion", false) or not Settings.read("ambientFx", true)
  local preview
  if self.mode == "place" and self.placing then
    preview = { id = self.placing, tile = self:placeTarget(), skip = self.moving }
  end
  return self.lensView:pass(graded, self.lensCanvas, {
    id = id,
    camera = self.camera,
    view = view,
    origin = { ox, oy },
    pixelSize = view.scale * self.camera:zoom(),
    daylight = daylight,
    time = still and 0 or self.renderer.time,
    preview = preview,
  })
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
