-- The Wardrobe (GDD §9.4, D154; docs/PLAN_WARDROBE_MENU.md): a page of paper like the Ledger's, where the
-- homesteader's clothes are tried on and chosen. A tab strip names the five slots; a tap or a keyboard focus
-- on a garment tile previews it on the big figure and moves the two meters (Day work, Night heat); a garment not
-- yet earned shows its shape and a hint instead. Only Wear changes what is chosen, through the wardrobe system's
-- own `wear`; whether that is today's outfit or waits for dawn is the sim's rule, and the scene only says so.
-- The draft is kept for the session (src/ui/wardrobe_state.lua). The scene reads the sim through the system's
-- accessors and never touches meta.wardrobe. Layout is src/ui/wardrobe_layout.lua, words and numbers
-- src/ui/wardrobe_text.lua, the figures src/render/wardrobe_preview.lua; knobs tuning.ui.wardrobe.

local Assets = require("src.render.assets")
local Books = require("src.ui.books")
local Buttons = require("src.ui.buttons")
local Character = require("src.render.character")
local Draw = require("src.ui.draw")
local FocusGrid = require("src.ui.focus_grid")
local Motion = require("src.ui.motion")
local Paper = require("src.ui.paper")
local Plate = require("src.ui.plate")
local Preview = require("src.render.wardrobe_preview")
local Sandbox = require("src.sim.systems.sandbox")
local ScrollList = require("src.ui.scroll_list")
local Sim = require("src.sim.systems.wardrobe")
local Text = require("src.ui.text")
local WardrobeLayout = require("src.ui.wardrobe_layout")
local WardrobeState = require("src.ui.wardrobe_state")
local WardrobeText = require("src.ui.wardrobe_text")
local theme = require("src.ui.theme")

local Wardrobe = { name = "wardrobe", dissolve = "book" } -- it comes and goes like a book (D142)
Wardrobe.__index = Wardrobe

local ARROWS =
  { left = "left", a = "left", right = "right", d = "right", up = "up", w = "up", down = "down", s = "down" }

--- `world`: the world whose clothes these are (the run's, or the recovery scene's meta world).
--- opts: { variant = "play" | "recovery", onWorn = fn(appliesNow) after a Wear, onToast = fn(text) }.
function Wardrobe.new(world, opts)
  opts = opts or {}
  return setmetatable({
    world = world,
    variant = opts.variant or "play",
    onWorn = opts.onWorn,
    onToast = opts.onToast or function() end,
    worn = false,
  }, Wardrobe)
end

--- Open the Wardrobe over the top scene. opts as `new`, plus `world` (default: the running session's). The
--- homestead on the stack lends its toaster, as it does to the books.
function Wardrobe.open(app, opts)
  opts = opts or {}
  local home
  for _, scene in ipairs(app.stack) do
    if scene.toaster and scene.log then
      home = scene
    end
  end
  app:push(Wardrobe.new(opts.world or app.ctx.session.world, {
    variant = opts.variant,
    onWorn = opts.onWorn,
    onToast = opts.onToast or (home and home:toaster() or nil),
  }))
end

function Wardrobe:enter()
  local ctx = self.app.ctx
  self.cfg = ctx.tuning.ui.wardrobe
  self.bookCfg = ctx.tuning.ui.book
  self.ui = ctx.tuning.ui
  self.minTouch = ctx.tuning.input.minTouchTarget
  self.registry = self.world.registry
  Preview.setup(self.cfg)
  self.buttons = Buttons.new(self.minTouch) -- the tabs, Close, Reset and Wear
  self.tileButtons = Buttons.new(self.minTouch) -- the garment tiles in view
  self.list = ScrollList.new(function()
    self:layoutTiles()
  end)
  self.focus = FocusGrid.new({ "tabs", "tiles", "actions", "presets" })
  self.slots = Sim.slots(self.world)
  self.maxTiles = 0 -- the garments of the longest slot
  for _, slot in ipairs(self.slots) do
    self.maxTiles = math.max(self.maxTiles, #Sim.garments(self.world, slot))
  end
  local world = self.world
  self.state = WardrobeState.new(Sim.committed(world), function(id)
    return Sim.owned(world, id)
  end)
  self.state:restore()
  local last = WardrobeState.last()
  self.slot = last and last.slot or self.slots[1]
  self.lockedDef = nil -- a garment not yet earned that was tapped or focused (its shape and hint show)
  self.wantFocus = "tile:" .. self.state:draft()[self.slot] -- the first layout puts the (unshown) focus here
  -- Opening the Wardrobe answers the "New clothes" stamp. The first new garment, if there is one, is the slot
  -- shown and where the (unshown) focus starts; its dot stays until it is looked at.
  Sim.stampSeen(world)
  local firstNew = self:firstNew()
  if firstNew then
    self.slot = firstNew.slot
    self.wantFocus = "tile:" .. firstNew.id
  end
  self:derive()
end

--- The first garment that is new, in slot order then content order, or nil.
function Wardrobe:firstNew()
  for _, slot in ipairs(self.slots) do
    for _, def in ipairs(Sim.garments(self.world, slot)) do
      if Sim.isNew(self.world, def.id) then
        return def
      end
    end
  end
  return nil
end

function Wardrobe:exit()
  WardrobeState.remember(self.state, self.slot)
  Preview.clear()
  if self.worn and self.variant == "play" and self.app.ctx.session then
    self.app.ctx.session:save() -- a quit right after cannot lose the outfit
  end
end

--- What the sim says now, kept between frames: today's outfit, whether a Wear applies at once.
function Wardrobe:derive()
  local world = self.world
  self.dressed = Sim.dressed(world)
  self.dressedKey = Sim.dressedKey(world)
  self.applies = Sim.appliesNow(world)
end

function Wardrobe:resize(view)
  self.view = view
  Preview.clear()
  self:layout()
end

--- Lay everything out for the slot showing: the geometry, the scroll window, the buttons and the focus list.
function Wardrobe:layout()
  local cfg = self.cfg
  self.garments = Sim.garments(self.world, self.slot)
  self.L =
    WardrobeLayout.rects(cfg, self.bookCfg, self.view, self.minTouch, #self.garments, { maxTiles = self.maxTiles })
  local tiles, contentH = WardrobeLayout.tiles(cfg, self.L.grid, #self.garments)
  self.tileRects = tiles
  self.list:fit(self.L.grid, contentH, self.ui.scrollHintHeight)
  self:layoutButtons()
  self:layoutTiles()
end

local function measureBody(label)
  return Text.measure(label, "body")
end

--- The tab strip, Close, Reset and Wear.
function Wardrobe:layoutButtons()
  local cfg, bookCfg, L = self.cfg, self.bookCfg, self.L
  local buttons = self.buttons
  buttons:clear()
  local items = {}
  local pages = {}
  for n, slot in ipairs(self.slots) do
    pages[n] = { id = slot, label = cfg.slots[slot], icon = cfg.slotIcons[slot] }
  end
  local lay = Books.layoutTabs(bookCfg, pages, self.slot, L.strip, self.minTouch, measureBody, bookCfg.iconSize)
  for n, tab in ipairs(lay.tabs) do
    local page = pages[n]
    local id = "tab:" .. page.id
    buttons:add({
      x = tab.x,
      y = tab.y,
      w = tab.w,
      h = tab.h,
      id = id,
      label = page.label,
      icon = page.icon,
      selected = page.id == self.slot,
      showLabel = tab.label,
      onPress = function()
        self:showSlot(page.id)
      end,
      draw = function(b)
        Paper.drawTab(bookCfg, b, self.buttons.pressed == b)
        if Sim.newCount(self.world, page.id) > 0 then
          self:drawDot(b.x + b.w - self.cfg.dotSize - 2, b.y + 2)
        end
        self:drawFocus(b)
      end,
    })
    items[#items + 1] = { id = id, zone = "tabs", x = tab.x, y = tab.y, w = tab.w, h = tab.h }
  end
  local close = lay.close
  buttons:add({
    x = close.x,
    y = close.y,
    w = close.w,
    h = close.h,
    id = "close",
    label = self.variant == "recovery" and cfg.done or cfg.close,
    onPress = function()
      self.app:pop()
    end,
    draw = function(b)
      self.buttons:drawOne(b, theme.colors)
      self:drawFocus(b)
    end,
  })
  items[#items + 1] = { id = "close", zone = "tabs", x = close.x, y = close.y, w = close.w, h = close.h }

  local changed = self.state:changed()
  for _, spec in ipairs({
    {
      "reset",
      L.reset,
      cfg.reset,
      nil,
      function()
        self:resetDraft()
      end,
    },
    {
      "wear",
      L.wear,
      cfg.wear,
      "accent",
      function()
        self:wear()
      end,
    },
  }) do
    local id, r, label, style, press = spec[1], spec[2], spec[3], spec[4], spec[5]
    buttons:add({
      x = r.x,
      y = r.y,
      w = r.w,
      h = r.h,
      id = id,
      label = label,
      style = style,
      enabled = changed,
      onPress = press,
      draw = function(b)
        self.buttons:drawOne(b, theme.colors)
        self:drawFocus(b)
      end,
    })
    items[#items + 1] = { id = id, zone = "actions", x = r.x, y = r.y, w = r.w, h = r.h }
  end

  for n, def in ipairs(self.garments) do
    local r = self.tileRects[n]
    items[#items + 1] = { id = "tile:" .. def.id, zone = "tiles", x = r.x, y = self.L.grid.y + r.y, w = r.w, h = r.h }
  end
  self.focus:set(items)
  if self.wantFocus then
    self.focus:focus(self.wantFocus)
    self.wantFocus = nil
  end
end

--- The garment tiles that are in the scroll window (only those get buttons, as in the Catalog).
function Wardrobe:layoutTiles()
  local cfg, world = self.cfg, self.world
  self.tileButtons:clear()
  local origin = self.list:origin()
  for n, def in ipairs(self.garments) do
    local r = self.tileRects[n]
    local y = origin + r.y
    if self.list:visible(y, r.h) then
      local owned = Sim.owned(world, def.id)
      self.tileButtons:add({
        x = r.x,
        y = y,
        w = r.w,
        h = r.h,
        id = "tile:" .. def.id,
        def = def,
        label = owned and def.name or (cfg.locked .. " " .. def.name),
        onPress = function()
          self.focus:show(false)
          self.focus:focus("tile:" .. def.id)
          self:pick(def)
        end,
        draw = function(b)
          self:drawTile(b, def)
        end,
      })
    end
  end
end

--- Show another slot's garments.
function Wardrobe:showSlot(slot)
  if slot == self.slot then
    return
  end
  self.slot = slot
  self.lockedDef = nil
  self.list.offset = 0
  self:layout()
end

--- A tile was tapped or focused: an owned garment goes into the draft; one not yet earned only shows its hint
--- and shape, and the draft stays as it is.
function Wardrobe:pick(def)
  if Sim.owned(self.world, def.id) then
    self.state:preview(def.slot, def.id)
    self.lockedDef = nil
    Sim.markSeen(self.world, def.id) -- looked at: its dot (and its tab's, if it was the last) goes
  else
    self.lockedDef = def
  end
  self:layoutButtons()
  self:layoutTiles()
end

function Wardrobe:resetDraft()
  self.state:reset()
  self.lockedDef = nil
  self:layoutButtons()
  self:layoutTiles()
end

--- Wear the draft: the sim chooses it, and says whether it is today's outfit now or from dawn.
function Wardrobe:wear()
  if not self.state:changed() then
    return
  end
  local world, cfg = self.world, self.cfg
  local now = Sim.appliesNow(world)
  local ok, reason, autoWasOn = Sim.wear(world, self.state:draft())
  if not ok then
    print("wardrobe: could not wear the draft: " .. tostring(reason))
    return
  end
  self.worn = true
  self.lockedDef = nil
  self.state:setCommitted(Sim.committed(world))
  self.onToast(now and cfg.toastNow or cfg.toastDawn)
  if autoWasOn then
    self.onToast(cfg.toastAutoOff)
  end
  if self.onWorn then
    self.onWorn(now)
  end
  self:derive()
  self:layoutButtons()
  self:layoutTiles()
end

function Wardrobe:update()
  local world = self.world
  -- Dawn passes while the menu is open: the sim moves today's outfit, and "Today" and "Dawn" move with it.
  if Sim.dressedKey(world) ~= self.dressedKey or Sim.appliesNow(world) ~= self.applies then
    self:derive()
    self:layoutButtons()
    self:layoutTiles()
  end
  self:warm()
end

--- Paint the figures the next frame will draw: the big one, a locked garment's shape and the tiles' little ones.
--- It happens here, outside drawing, a few at a time (tuning.ui.wardrobe.previewBuilds), because switching to a
--- canvas in the middle of a scissored draw disturbs the scissor.
function Wardrobe:warm()
  local draft = self.state:draft()
  Preview.frame(self.cfg.previewBuilds)
  Preview.figure(self.registry, draft, true)
  if self.lockedDef then
    Preview.silhouette(self.registry, draft, self.lockedDef.slot, self.lockedDef.id)
  end
  for _, b in ipairs(self.tileButtons.list) do
    self:thumb(b.def)
  end
end

-- Input ------------------------------------------------------------------------------------------------------

function Wardrobe:action(name, data)
  if name == "cancel" or name == "wardrobe" then
    self.app:pop()
    return true
  end
  if name == "press" then
    self.focus:show(false) -- the pointer is back in charge
  end
  if self.buttons:action(name, data) then
    return true
  end
  local inside = data.x ~= nil and self.list:contains(data.x, data.y)
  if name == "select" or name == "press" then
    if inside and self.tileButtons:action(name, data) then
      if name == "press" then
        self.list:action(name, data) -- a press on a tile can still begin a drag that scrolls
      end
      return true
    end
  elseif name == "hover" then
    if inside then
      self.tileButtons:action(name, data)
    else
      self.tileButtons.hovered = nil
    end
  elseif name == "release" then
    self.tileButtons:action(name, data)
  end
  local jump = name == "pageUp" or name == "pageDown" or name == "listHome" or name == "listEnd"
  if name == "press" or name == "release" then
    self.list:action(name, data, self.ui)
  elseif (name == "pan" and not data.keys) or (name == "zoom" and inside) or jump then
    if self.list:action(name, data, self.ui) then
      self:layoutTiles()
    end
  elseif name == "select" and data.x then
    local p = self.L.paper
    if data.x < p.x or data.x >= p.x + p.w or data.y < p.y or data.y >= p.y + p.h then
      self.app:pop() -- a tap outside the paper puts it away
    end
  end
  return true -- the Wardrobe is modal: nothing reaches the world under it
end

--- Move the keyboard focus one step, previewing a garment as the focus lands on it and switching the slot as it
--- lands on a tab.
function Wardrobe:moveFocus(dir)
  self.focus:show(true)
  local prefer = {
    tabs = "tab:" .. self.slot,
    tiles = "tile:" .. tostring(self.state:draft()[self.slot]),
  }
  self:onFocus(self.focus:move(dir, prefer))
end

function Wardrobe:onFocus(id)
  if not id then
    return
  end
  local slot = id:match("^tab:(.+)$")
  if slot then
    self:showSlot(slot)
    return
  end
  local garment = id:match("^tile:(.+)$")
  if garment then
    for n, def in ipairs(self.garments) do
      if def.id == garment then
        local r = self.tileRects[n]
        self.list:reveal(r.y, r.h)
        self:pick(def)
        return
      end
    end
  end
end

--- Enter presses the focused control (Close, Reset, Wear); anywhere else it wears the draft.
function Wardrobe:activate()
  local id = self.focus:shown() and self.focus:current() or nil
  if id == "close" then
    self.app:pop()
  elseif id == "reset" then
    self:resetDraft()
  else
    self:wear()
  end
end

function Wardrobe:keypressed(key)
  if ARROWS[key] then
    self:moveFocus(ARROWS[key])
  elseif key == "return" or key == "kpenter" then
    self:activate()
  elseif key == "backspace" then
    self:resetDraft()
  end
end

-- Drawing ------------------------------------------------------------------------------------------------------

--- The keyboard focus ring round control `b` when it has the focus (inside the control, so a strip tab keeps it
--- on the paper).
function Wardrobe:drawFocus(b, outside)
  if not (self.focus:shown() and self.focus:current() == b.id) then
    return
  end
  local gap = outside and self.cfg.focusGap or -self.cfg.focusGap
  love.graphics.setColor(theme.colors.text)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", b.x - gap + 0.5, b.y - gap + 0.5, b.w + 2 * gap - 1, b.h + 2 * gap - 1)
end

-- The garments' own pixels as a tile's little figure: the draft with this garment on, or for one not yet earned
-- the draft with the garment's shape over it in ink.
function Wardrobe:thumb(def)
  local draft = self.state:draft()
  if Sim.owned(self.world, def.id) then
    local outfit = {}
    for slot, id in pairs(draft) do
      outfit[slot] = id
    end
    outfit[def.slot] = def.id
    return Preview.figure(self.registry, outfit), nil
  end
  return Preview.figure(self.registry, draft), Preview.silhouette(self.registry, draft, def.slot, def.id)
end

function Wardrobe:drawTile(b, def)
  local cfg, colors = self.cfg, theme.colors
  local draft = self.state:draft()
  local owned = Sim.owned(self.world, def.id)
  local selected = owned and draft[def.slot] == def.id
  local pressed = self.tileButtons.pressed == b
  local fill = colors.button
  if not owned then
    fill = colors.buttonDisabled
  elseif pressed then
    fill = colors.buttonPressed
  elseif self.tileButtons.hovered == b then
    fill = colors.buttonHover
  end
  local isNew = Sim.isNew(self.world, def.id)
  local ring = (selected and colors.accent) or (self.lockedDef == def and colors.textDim) or nil -- a locked tile in view gets a quiet ring
  local gx, gy
  if isNew and not selected then
    ring, gx, gy = Motion.signal("amber", b.w, b.h, b.x * 31 + b.y) -- the calm amber glint on a new garment
  end
  Plate.draw(b.x, b.y, b.w, b.h, {
    base = fill,
    kind = "button",
    ink = ring,
    glintX = gx,
    glintY = gy,
    lit = pressed and 0 or nil,
    alpha = 1,
    weather = false,
  })
  local ts = cfg.thumbScale
  local tx, ty = b.x + math.floor((b.w - Character.W * ts) / 2), b.y + cfg.thumbTop
  local base, over = self:thumb(def)
  love.graphics.setColor(1, 1, 1, 1)
  if base then
    love.graphics.draw(base, tx, ty, 0, ts, ts)
  end
  if over then
    love.graphics.draw(over, tx, ty, 0, ts, ts)
  end
  -- The name: the garment's, or ??? for one not yet earned.
  local nameY = ty + Character.H * ts + cfg.nameGap
  local maxW = b.w - 2 * cfg.namePad
  local lines = owned
      and WardrobeText.nameLines(def.name, function(s)
        return (Text.measure(s, "small"))
      end, maxW, cfg.nameLines, cfg.ellipsis)
    or { cfg.locked }
  for n, line in ipairs(lines) do
    Text.draw(line, b.x + cfg.namePad, nameY + (n - 1) * cfg.lineH, {
      size = "small",
      width = maxW,
      align = "center",
      color = owned and colors.text or colors.textDim,
    })
  end
  -- Weight, as pips: one, two or three (the class is no secret, it says what to aim for).
  local pips = cfg.pips[def.class]
  local px = b.x + b.w - cfg.pipPad - (pips * cfg.pipSize + (pips - 1) * cfg.pipGap)
  love.graphics.setColor(colors.text[1], colors.text[2], colors.text[3], 0.9)
  for k = 0, pips - 1 do
    love.graphics.rectangle("fill", px + k * (cfg.pipSize + cfg.pipGap), b.y + cfg.pipPad, cfg.pipSize, cfg.pipSize)
  end
  -- The pill: what is worn today, or chosen for dawn.
  local word, kind = WardrobeText.pill(cfg, def.id, self.state:committed(), self.dressed, def.slot, self.variant)
  if word then
    local ink = kind == "dawn" and colors.accent or cfg.pillTodayInk
    local pw = Text.measure(word, "small") + 2 * cfg.pillPad
    local x = b.x + math.floor((b.w - pw) / 2)
    local y = b.y + b.h - cfg.pillBottom - cfg.pillH
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", x, y, pw, cfg.pillH)
    love.graphics.setColor(ink)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, pw - 1, cfg.pillH - 1)
    Text.draw(
      word,
      x + cfg.pillPad,
      y + math.floor((cfg.pillH - 7) / 2),
      { size = "small", color = ink, shadow = false }
    )
  end
  if isNew then
    self:drawDot(b.x + cfg.dotPad, b.y + cfg.dotPad)
  end
  self:drawFocus(b, true)
end

--- The new-garment dot: a stepped amber square with a dark rim, at (x, y).
function Wardrobe:drawDot(x, y)
  local cfg = self.cfg
  local d = cfg.dotSize
  love.graphics.setColor(cfg.dotRim[1], cfg.dotRim[2], cfg.dotRim[3], 1)
  love.graphics.rectangle("fill", x - 1, y, d + 2, d)
  love.graphics.rectangle("fill", x, y - 1, d, d + 2)
  love.graphics.setColor(theme.colors.accent)
  love.graphics.rectangle("fill", x + 1, y, d - 2, d)
  love.graphics.rectangle("fill", x, y + 1, d, d - 2)
end

-- The ground under the figure: the grass sprite's top rows in spring to autumn (and always in the recovery
-- scene), flat snow when the land is white.
local groundQuads = {}

function Wardrobe:drawGround(g, scale)
  local cfg = self.cfg
  if self.variant ~= "recovery" and Plate.snow() >= cfg.snowMin then
    love.graphics.setColor(cfg.snowGround)
    love.graphics.rectangle("fill", g.x, g.y, g.w, g.h)
    return
  end
  local sp = Assets.sprite("grass_1")
  local rows = cfg.groundRows
  local key = sp.image
  local quads = groundQuads[key]
  if not quads then
    quads = {}
    groundQuads[key] = quads
  end
  local qx, qy = sp.quad:getViewport()
  love.graphics.setColor(1, 1, 1, 1)
  local artW = math.floor(g.w / scale)
  local x = 0
  while x < artW do
    local w = math.min(sp.w, artW - x)
    local k = w .. ":" .. rows
    local quad = quads[k]
    if not quad then
      quad = love.graphics.newQuad(qx, qy, w, rows, sp.image:getDimensions())
      quads[k] = quad
    end
    love.graphics.draw(sp.image, quad, g.x + x * scale, g.y, 0, scale, scale)
    x = x + w
  end
end

local function meterValues(self)
  local world = self.world
  local draft = Sim.effects(world, self.state:draft())
  local committed = Sim.effects(world, self.state:committed())
  return draft, committed, Sim.scale(world)
end

-- One meter: its label, a bar with a centre tick, the fill (solid for a benefit, dithered amber for a cost), the
-- worn value as a tick when the draft differs, and the signed number.
function Wardrobe:drawMeter(key, label, axis, value, worn, scale)
  local cfg, colors = self.cfg, theme.colors
  local m = self.L.meters[key]
  local _, th = Text.measure(label, "small")
  Text.draw(label, m.label.x, m.label.y + math.floor((m.label.h - th) / 2), { size = "small", color = colors.textDim })
  local bar = m.bar
  local half = math.floor(bar.w / 2)
  local mid = bar.x + half
  local track = self.ui.topChips.barTrack
  love.graphics.setColor(track)
  love.graphics.rectangle("fill", bar.x, bar.y, bar.w, bar.h)
  local n, side = WardrobeText.fill(value, scale, half)
  if n > 0 then
    local x0 = side > 0 and mid + 1 or mid - n
    if WardrobeText.isCost(axis, value) then
      love.graphics.setColor(colors.accent)
      local period = cfg.meterCostDither
      for px = x0, x0 + n - 1 do
        for py = bar.y, bar.y + bar.h - 1 do
          if (px + py) % period == 0 then
            love.graphics.rectangle("fill", px, py, 1, 1)
          end
        end
      end
    else
      love.graphics.setColor(self.ui.topChips.barOk)
      love.graphics.rectangle("fill", x0, bar.y, n, bar.h)
    end
  end
  love.graphics.setColor(colors.text[1], colors.text[2], colors.text[3], 0.6)
  love.graphics.rectangle("fill", mid, bar.y - 1, 1, bar.h + 2) -- zero
  if math.abs(worn - value) > 1e-9 then
    local wn, wside = WardrobeText.fill(worn, scale, half)
    love.graphics.setColor(colors.text)
    love.graphics.rectangle("fill", mid + wside * wn, bar.y - 2, 1, bar.h + 4) -- what is worn
  end
  local cost = WardrobeText.isCost(axis, value)
  Text.draw(WardrobeText.percent(value), m.num.x, m.num.y + math.floor((m.num.h - th) / 2), {
    size = "small",
    color = cost and colors.accent or colors.text,
  })
end

function Wardrobe:draw()
  local cfg, bookCfg, L, colors = self.cfg, self.bookCfg, self.L, theme.colors
  local world, draft = self.world, self.state:draft()
  Preview.frame(0) -- drawing only uses the figures `warm` made
  local paper, strip = L.paper, L.strip
  Draw.overlay(self.app.view)
  Paper.drawPool(bookCfg, paper.x, paper.y, paper.w, paper.h, Motion.night())
  Paper.draw(bookCfg, paper.x, paper.y, paper.w, paper.h)
  Paper.drawLamp(bookCfg, paper.x, paper.y, paper.w, paper.h, Motion.night())
  love.graphics.setColor(colors.panelBorder)
  love.graphics.rectangle("fill", paper.x + 2, strip.y + strip.h, paper.w - 4, 1)
  self.buttons:draw()

  -- The left column: title, state, figure, meters.
  local tw = Text.measure(cfg.title, "body")
  Text.draw(cfg.title, L.title.x, L.title.y, { size = "body" })
  if Sandbox.on(world) then
    Text.draw(self.ui.sandbox.tag, L.title.x + tw + 8, L.title.y, { size = "small", color = colors.accent })
  end
  Text.draw(WardrobeText.stateLine(cfg, draft, self.state:committed(), self.dressed), L.state.x, L.state.y, {
    size = "small",
    color = colors.textDim,
  })
  local pv = L.preview
  Paper.draw(bookCfg, pv.x, pv.y, pv.w, pv.h, { base = cfg.previewBack, fibre = false })
  self:drawGround(L.ground, pv.scale)
  local fig = Preview.figure(self.registry, draft)
  love.graphics.setColor(1, 1, 1, 1)
  if fig then
    love.graphics.draw(fig, L.figure.x, L.figure.y, 0, pv.scale, pv.scale)
  end
  if self.lockedDef then
    local shape = Preview.silhouette(self.registry, draft, self.lockedDef.slot, self.lockedDef.id)
    love.graphics.setColor(1, 1, 1, 1)
    if shape then
      love.graphics.draw(shape, L.figure.x, L.figure.y, 0, pv.scale, pv.scale)
    end
  end
  local now, worn, scale = meterValues(self)
  self:drawMeter("work", cfg.meterWork, "work", now.work, worn.work, scale.work)
  self:drawMeter("heat", cfg.meterHeat, "heat", now.cold, worn.cold, scale.cold)

  -- The right column: the slot's name and count, the tiles, the detail line, the tag beside Wear.
  local owned, total = 0, #self.garments
  for _, def in ipairs(self.garments) do
    if Sim.owned(world, def.id) then
      owned = owned + 1
    end
  end
  Text.draw(cfg.slots[self.slot], L.heading.x, L.heading.y, { size = "body" })
  Text.draw(string.format(cfg.count, owned, total), L.heading.x, L.heading.y + 1, {
    size = "small",
    width = L.heading.w,
    align = "right",
    color = colors.textDim,
  })
  self.list:begin(self.app.view.scale)
  self.tileButtons:draw()
  self.list:finish()
  self.list:drawCue(self.ui)
  self:drawDetail()
  Text.draw(WardrobeText.tag(cfg, self.applies), L.tag.x, L.tag.y + 1, {
    size = "small",
    width = L.tag.w,
    color = colors.textDim,
  })
end

--- The two lines under the tiles: the garment in the draft for this slot, or the hint of the locked one on show.
function Wardrobe:drawDetail()
  local cfg, colors, world = self.cfg, theme.colors, self.world
  local def = self.lockedDef or self.registry:get("garments", self.state:draft()[self.slot])
  local owned = Sim.owned(world, def.id)
  local hint, have, need
  if not owned then
    hint = WardrobeText.hint(def, Sim.threshold(world, def.id))
    have, need = Sim.progress(world, def.id)
  end
  local line1, line2 = WardrobeText.detail(cfg, def, owned, hint, have, need)
  local d = self.L.detail
  Text.draw(line1, d.x, d.y, { size = "small", width = d.w })
  if line2 then
    Text.draw(line2, d.x, d.y + cfg.lineH, { size = "small", width = d.w, color = colors.textDim })
  end
end

return Wardrobe
