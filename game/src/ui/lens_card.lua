-- The lens side card (GDD §9.4, D141, D145): the Power panel's contents (what the network makes and uses, the
-- battery bank and the truck, the priority list, the sources and devices with their switches) and the Water
-- lens's readout, on a card that floats over the lensed world instead of covering it. A side card on a wide view,
-- a bottom sheet on a tall one; it folds to a strip so a placement stays in sight. Everything is tappable (no
-- hover), and rows scroll as one list. The geometry is src/ui/lens.lua; the pool and band painting is the
-- renderer's. Presentation only: the switches go through the Power system's own setters.

local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")
local Water = require("src.sim.systems.water")
local Buttons = require("src.ui.buttons")
local Grid = require("src.sim.grid")
local Plate = require("src.ui.plate")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Card = {}
Card.__index = Card

local GREEN = { 0.45, 0.82, 0.42 }
local PAD = 8

--- `ctx` = the app context (tuning, input), `world` the sim world.
function Card.new(ctx, world)
  local touch = ctx.tuning.input.minTouchTarget
  return setmetatable({
    ctx = ctx,
    world = world,
    cfg = ctx.tuning.ui.lens,
    list = ScrollList.new(),
    buttons = Buttons.new(touch),
    rowButtons = Buttons.new(touch),
    items = {},
    lens = nil,
    collapsed = false,
    rect = { x = 0, y = 0, w = 0, h = 0 },
    refresh = 0,
  }, Card)
end

-- Height of a wrapped note. The font needs a window; headless (tests) there is none, and a row's worth will do.
local function noteHeight(str, w, rowH)
  local ok, h = pcall(Text.wrappedHeight, str, "small", w)
  return ok and h or rowH
end

local function textWidth(str)
  local ok, w = pcall(Text.measure, str, "small")
  return ok and w or #str * 6
end

local function stateColor(state)
  if state == "ok" then
    return GREEN
  elseif state == "short" then
    return theme.colors.danger
  end
  return theme.colors.textDim
end

local function stateText(row)
  if row.state == "off" then
    return "Off"
  elseif row.state == "idle" then
    return "Idle"
  elseif row.state == "short" then
    return string.format("Short %d%%", math.floor(row.ratio * 100))
  end
  return "On"
end

--- Show lens `id` ("power" | "water") in `rect`. `collapsed` folds it to the strip. `onClose` runs on Close and
--- `onFold(collapsed)` when the player folds or opens the card.
function Card:setup(id, rect, collapsed, onClose, onFold)
  if self.lens ~= id then
    self.list.offset = 0
  end
  self.lens, self.rect, self.collapsed, self.onClose, self.onFold = id, rect, collapsed, onClose, onFold
  self:layout()
end

-- Rows of the power card; `w` is the width of the body.
function Card:powerRows(w, rows)
  local world, cfg = self.world, self.world.tuning.power
  local rowH = self.cfg.rowH
  local flow = Power.flow(world)
  local satisfaction = Power.satisfaction(world)
  local function add(r)
    rows[#rows + 1] = r
  end
  add({ kind = "text", h = 13, str = string.format("Making %.1f kW   Using %.1f kW", flow.generation, flow.served) })
  add({
    kind = "text",
    h = 15,
    color = satisfaction >= 1 and GREEN or theme.colors.danger,
    str = flow.demand <= 0 and "Nothing is asking for power"
      or string.format("%d%% of demand served", math.floor(satisfaction * 100 + 0.5)),
  })
  local bank = Power.bank(world)
  if bank.capacity > 0 then
    add({ kind = "text", h = 11, str = string.format("Battery bank  %.1f / %d kWh", bank.charge, bank.capacity) })
    add({ kind = "bar", h = 14, frac = bank.charge / bank.capacity })
  end
  local truck = world.state.land.truck
  local truckCap = Power.capacity(world, truck)
  add({ kind = "text", h = 11, str = string.format("Truck  %.1f / %d kWh", Power.charge(world, truck), truckCap) })
  add({ kind = "bar", h = 15, frac = Power.charge(world, truck) / truckCap, mark = cfg.truckReserveKwh / truckCap })
  local lends = Power.truckLends(world)
  add({
    kind = "button",
    h = rowH + 8,
    label = lends and "Truck lends power above its trip reserve" or "Truck keeps its charge",
    selected = lends,
    press = function()
      Power.setTruckLends(world, not Power.truckLends(world))
    end,
  })
  add({ kind = "head", h = 12, str = "Priority: served first at the top" })
  local hasSinks = {}
  for _, sink in ipairs(Power.sinkList(world)) do
    hasSinks[sink.tier] = true
  end
  local order = Power.order(world)
  for n, id in ipairs(order) do
    local tier = flow.tiers[id] or { demand = 0, served = 0, charging = 0 }
    local detail, color
    if rawget(cfg.chargeTiers, id) ~= nil then
      detail = tier.charging > 0 and string.format("+%.1f kW", tier.charging) or "not charging"
      color = tier.charging > 0 and GREEN or theme.colors.textDim
    elseif tier.demand > 0 then
      local ratio = tier.served / tier.demand
      detail = string.format("%d%%", math.floor(ratio * 100 + 0.5))
      color = ratio >= 1 - cfg.overdrawEpsilon and GREEN or theme.colors.danger
    else
      detail = hasSinks[id] and "idle" or "none"
      color = theme.colors.textDim
    end
    add({
      kind = "tier",
      h = rowH,
      name = string.format("%d. %s", n, Power.tierName(world, id)),
      detail = detail,
      color = color,
      up = n > 1 and function()
        Power.moveTier(world, id, -1)
      end or nil,
      down = n < #order and function()
        Power.moveTier(world, id, 1)
      end or nil,
    })
  end
  add({ kind = "gap", h = 6 })
  add({ kind = "head", h = 12, str = "Sources" })
  local sources = Power.sourceList(world)
  if #sources == 0 then
    add({ kind = "text", h = 14, str = "None", color = theme.colors.textDim })
  end
  for _, src in ipairs(sources) do
    local generator = src.curve == "fuel"
    local detail
    if generator then
      detail = src.output > 0 and string.format("%.1f kW", src.output)
        or string.format("fuel %d", Ledger.get(world, "fuel"))
    else
      detail = string.format("%.1f / %g kW", src.output, src.peak)
    end
    add({
      kind = "source",
      h = rowH,
      name = src.name,
      detail = detail,
      color = src.output > 0 and GREEN or theme.colors.textDim,
      switch = generator and { label = src.enabled and "Auto" or "Off", on = src.enabled, anchor = src.anchor } or nil,
    })
  end
  add({ kind = "gap", h = 6 })
  add({ kind = "head", h = 12, str = "Devices" })
  local sinks = Power.sinkList(world)
  if #sinks == 0 then
    add({ kind = "text", h = 14, str = "None placed yet", color = theme.colors.textDim })
  end
  for _, sink in ipairs(sinks) do
    add({
      kind = "sink",
      h = rowH,
      name = sink.name,
      sub = string.format("%s  %.2g kW", Power.tierName(world, sink.tier), sink.draw),
      detail = stateText(sink),
      color = stateColor(sink.state),
      switch = { label = sink.enabled and "On" or "Off", on = sink.enabled, anchor = sink.anchor },
    })
  end
  local legend = self.cfg.legend.power
  add({ kind = "legend", h = noteHeight(legend, w, self.cfg.rowH) + 6, str = legend })
end

-- Rows of the water card.
function Card:waterRows(w, rows)
  local world = self.world
  local function add(r)
    rows[#rows + 1] = r
  end
  local units, capacity = Water.stored(world)
  if Water.hasCistern(world) then
    add({ kind = "text", h = 13, str = string.format("Cistern  %d / %d", units, capacity) })
    add({ kind = "bar", h = 14, frac = Water.fraction(world) })
  else
    add({ kind = "text", h = 14, str = "No cistern yet", color = theme.colors.textDim })
  end
  for _, field in ipairs({ "drip", "sprinkler" }) do
    local anchors = Grid.anchorsWith(world, field)
    if #anchors > 0 then
      add({ kind = "head", h = 12, str = field == "drip" and "Drip lines" or "Sprinklers" })
      for _, anchor in ipairs(anchors) do
        local def = world.registry:get("objects", world.state.grid.objects[anchor].id)
        local state = Water.dripState(world, anchor)
        local thirsty = Water.dripThirsty(world, anchor)
        add({
          kind = "source",
          h = self.cfg.rowH,
          name = def.name,
          detail = state == "dry" and "Dry" or state == "frozen" and "Frozen" or string.format("%d thirsty", thirsty),
          color = state == "dry" and theme.colors.danger or theme.colors.textDim,
        })
      end
    end
  end
  local pumps = Grid.anchorsWith(world, "pump")
  if #pumps > 0 then
    add({ kind = "head", h = 12, str = "Pumps" })
    for _, anchor in ipairs(pumps) do
      local def = world.registry:get("objects", world.state.grid.objects[anchor].id)
      local state = Water.pumpState(world, anchor)
      add({ kind = "source", h = self.cfg.rowH, name = def.name, detail = state, color = theme.colors.textDim })
    end
  end
  local legend = self.cfg.legend.water
  add({ kind = "legend", h = noteHeight(legend, w, self.cfg.rowH) + 6, str = legend })
end

--- Lay the card out for the current state: the header buttons, then the rows of the body.
function Card:layout()
  local r, cfg = self.rect, self.cfg
  local touch = self.ctx.tuning.input.minTouchTarget
  local strip = math.max(cfg.stripH, touch)
  self.buttons:clear()
  self.rowButtons:clear()
  self.items = {}
  local bh = strip - 6
  self.buttons:add({
    x = r.x + r.w - PAD - 56,
    y = r.y + 3,
    w = 56,
    h = bh,
    label = "Close",
    onPress = function()
      self.onClose()
    end,
  })
  self.buttons:add({
    x = r.x + r.w - PAD - 56 - 4 - touch,
    y = r.y + 3,
    w = touch,
    h = bh,
    label = self.collapsed and "+" or "-",
    onPress = function()
      self.collapsed = not self.collapsed
      self.onFold(self.collapsed)
    end,
  })
  self.titleW = r.w - 2 * PAD - 56 - 4 - touch - 4
  if self.collapsed then
    return
  end
  local body = { x = r.x + PAD, y = r.y + strip + 2, w = r.w - 2 * PAD, h = r.h - strip - 2 - PAD }
  local rows = {}
  if self.lens == "power" then
    self:powerRows(body.w, rows)
  else
    self:waterRows(body.w, rows)
  end
  local contentH = 0
  for _, row in ipairs(rows) do
    contentH = contentH + row.h
  end
  local ui = self.ctx.tuning.ui
  local view = self.list:fit(body, contentH, ui.scrollHintHeight, cfg.rowH * 2)
  local right = body.x + body.w - (self.list.overflow and (ui.scrollBarWidth + 4) or 0)
  local left = body.x
  local ry = self.list:origin()
  local function text(x, y, str, color, width)
    self.items[#self.items + 1] = { kind = "text", x = x, y = y, str = str, color = color, width = width }
  end
  for _, row in ipairs(rows) do
    if ry + row.h > view.y and ry < view.y + view.h then
      local k = row.kind
      if k == "text" or k == "head" then
        text(left, ry, row.str, row.color or (k == "head" and theme.colors.textDim or theme.colors.text))
      elseif k == "legend" then
        text(left, ry + 4, row.str, theme.colors.textDim, body.w)
      elseif k == "bar" then
        self.items[#self.items + 1] =
          { kind = "bar", x = left, y = ry, w = right - left, frac = row.frac, mark = row.mark }
      elseif k == "button" then
        self.rowButtons:add({
          x = left,
          y = ry,
          w = right - left,
          h = row.h - 4,
          label = row.label,
          selected = row.selected,
          onPress = function()
            row.press()
            self:changed()
          end,
        })
      elseif k == "tier" then
        text(left + 4, ry + 8, row.name, theme.colors.text)
        text(right - 124, ry + 8, row.detail, row.color)
        local bw = math.max(24, touch / 2)
        self.rowButtons:add({
          x = right - 2 * bw - 2,
          y = ry,
          w = bw,
          h = row.h,
          label = "^",
          enabled = row.up ~= nil,
          onPress = function()
            row.up()
            self:changed()
          end,
        })
        self.rowButtons:add({
          x = right - bw,
          y = ry,
          w = bw,
          h = row.h,
          label = "v",
          enabled = row.down ~= nil,
          onPress = function()
            row.down()
            self:changed()
          end,
        })
      elseif k == "source" or k == "sink" then
        text(left + 4, ry + (row.sub and 3 or 8), row.name, theme.colors.text)
        if row.sub then
          text(left + 4, ry + 13, row.sub, theme.colors.textDim)
        end
        local sw = row.switch and 52 or 0
        text(right - sw - 4 - textWidth(row.detail), ry + 8, row.detail, row.color)
        if row.switch then
          local sw0 = row.switch
          self.rowButtons:add({
            x = right - sw,
            y = ry,
            w = sw,
            h = row.h,
            label = sw0.label,
            selected = sw0.on,
            onPress = function()
              Power.setEnabled(self.world, sw0.anchor, not Power.isEnabled(self.world, sw0.anchor))
              self:changed()
            end,
          })
        end
      end
    end
    ry = ry + row.h
  end
end

--- The player changed a switch or the priorities: rebuild the network numbers now (so a paused game shows the
--- effect) and lay out again.
function Card:changed()
  Power.refresh(self.world)
  self:layout()
end

function Card:contains(x, y)
  local r = self.rect
  return x ~= nil and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function Card:update(dt)
  self.refresh = self.refresh - dt
  if self.refresh <= 0 and self.lens then
    self.refresh = 0.25
    self:layout()
  end
end

--- Feed an input action. Returns true when the card used it (it only answers inside its rect, so the world
--- stays tappable around it).
function Card:action(name, data)
  if name == "press" or name == "release" then
    self.list:action(name, data)
  end
  local inside = self:contains(data.x, data.y)
  if name == "release" then
    self.grab = false
  elseif name == "press" then
    self.grab = inside -- a drag that starts on the card scrolls it (a pan carries no position)
  end
  if (name == "press" or name == "select" or name == "hover" or name == "release") and inside then
    if self.buttons:action(name, data) then
      return true
    end
    if self.list:contains(data.x, data.y) and self.rowButtons:action(name, data) then
      return true
    end
    return name ~= "hover"
  end
  local mine = name == "zoom" and inside or name == "pan" and not data.keys and (self.grab or inside)
  if mine then
    if self.list:action(name, data, self.ctx.tuning.ui) then
      self:layout()
    end
    return true
  end
  return false
end

local function drawItem(item)
  if item.kind == "text" then
    Text.draw(item.str, item.x, item.y, { size = "small", color = item.color, width = item.width })
  else
    love.graphics.setColor(theme.colors.background)
    love.graphics.rectangle("fill", item.x, item.y, item.w, 8, 2, 2)
    love.graphics.setColor(GREEN)
    local fill = (item.w - 2) * math.min(1, item.frac)
    if fill >= 1 then
      love.graphics.rectangle("fill", item.x + 1, item.y + 1, fill, 6, 2, 2)
    end
    if item.mark then
      love.graphics.setColor(theme.colors.accent)
      love.graphics.rectangle("fill", item.x + item.w * item.mark, item.y - 2, 1, 12)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function Card:draw(view)
  local r, cfg = self.rect, self.cfg
  Plate.draw(r.x, r.y, r.w, r.h, { kind = "panel", weather = false })
  local strip = math.max(cfg.stripH, self.ctx.tuning.input.minTouchTarget)
  local title = cfg.title[self.lens]
  local _, th = Text.measure(title, "body")
  local ty = r.y + (strip - th) / 2
  Text.draw(title, r.x + PAD, ty, { size = "body" })
  if self.collapsed then
    local flow = self.lens == "power" and Power.flow(self.world)
    local summary = flow and string.format("%.1f kW in, %.1f kW out", flow.generation, flow.served)
      or string.format("%d%%", math.floor(Water.fraction(self.world) * 100 + 0.5))
    local x = r.x + PAD + Text.measure(title, "body") + 10
    if x + Text.measure(summary, "small") < r.x + self.titleW then
      Text.draw(summary, x, ty + 1, { size = "small", color = theme.colors.textDim })
    end
  end
  self.buttons:draw()
  if self.collapsed then
    return
  end
  self.list:begin(view.scale)
  for _, item in ipairs(self.items) do
    drawItem(item)
  end
  self.rowButtons:draw()
  self.list:finish()
  self.list:drawCue(self.ctx.tuning.ui)
end

return Card
