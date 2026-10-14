-- The power panel (GDD §7.5): what the network makes and uses, how full the batteries are, which
-- devices are on, and the priority list that decides who is served first when power runs short.
-- Wide views put the summary and priorities on the left and sources and devices on the right;
-- narrow (phone portrait) views stack them. Everything is tappable (no hover, GDD §10).

local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local PowerPanel = { name = "power" }
PowerPanel.__index = PowerPanel

local ROW_H = 24
local WIDE = 560 -- box width at which the two-column layout is used
local GREEN = { 0.45, 0.82, 0.42 }

function PowerPanel.new(world, onToast)
  return setmetatable({ world = world, onToast = onToast, list = ScrollList.new() }, PowerPanel)
end

function PowerPanel:enter()
  self.list.onMove = function()
    self:layout()
  end
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.rowButtons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function PowerPanel:resize(view)
  self.box = Panel.box(view, 640, view.h - 16)
  self:layout()
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

-- Build the buttons and the list of things draw() paints (text, bars) for the current state.
function PowerPanel:layout()
  local b, world = self.box, self.world
  local cfg = world.tuning.power
  self.buttons:clear()
  self.items = {}
  local function text(x, y, str, color, size)
    self.items[#self.items + 1] = { kind = "text", x = x, y = y, str = str, color = color, size = size or "small" }
  end
  local function bar(x, y, w, frac, color, mark)
    self.items[#self.items + 1] = { kind = "bar", x = x, y = y, w = w, frac = frac, color = color, mark = mark }
  end
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)

  local wide = b.w >= WIDE
  local colW = wide and (b.w - 36) / 2 or b.w - 24
  local leftX = b.x + 12
  local rightX = wide and (leftX + colW + 12) or leftX
  local flow = Power.flow(world)

  -- Summary ------------------------------------------------------------------------------
  local y = b.y + 38
  local satisfaction = Power.satisfaction(world)
  text(leftX, y, string.format("Making %.1f kW   Using %.1f kW", flow.generation, flow.served), theme.colors.text)
  y = y + 13
  text(
    leftX,
    y,
    flow.demand <= 0 and "Nothing is asking for power"
      or string.format("%d%% of demand served", math.floor(satisfaction * 100 + 0.5)),
    satisfaction >= 1 and GREEN or theme.colors.danger
  )
  y = y + 15
  local bank = Power.bank(world)
  if bank.capacity > 0 then
    text(leftX, y, string.format("Battery bank  %.1f / %d kWh", bank.charge, bank.capacity), theme.colors.textDim)
    y = y + 11
    bar(leftX, y, colW, bank.charge / bank.capacity, GREEN)
    y = y + 14
  end
  local truck = world.state.land.truck
  local truckCap = Power.capacity(world, truck)
  text(leftX, y, string.format("Truck  %.1f / %d kWh", Power.charge(world, truck), truckCap), theme.colors.textDim)
  y = y + 11
  bar(leftX, y, colW, Power.charge(world, truck) / truckCap, GREEN, cfg.truckReserveKwh / truckCap)
  y = y + 15
  local lends = Power.truckLends(world)
  self.buttons:add({
    x = leftX,
    y = y,
    w = colW,
    h = ROW_H,
    label = lends and "Truck lends power above its trip reserve" or "Truck keeps its charge",
    selected = lends,
    onPress = function()
      Power.setTruckLends(world, not Power.truckLends(world))
      self:changed()
    end,
  })
  y = y + ROW_H + 8

  -- Priorities ---------------------------------------------------------------------------
  text(leftX, y, "Priority: served first at the top", theme.colors.textDim)
  y = y + 12
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
    text(leftX + 4, y + 8, string.format("%d. %s", n, Power.tierName(world, id)), theme.colors.text)
    text(leftX + colW - 118, y + 8, detail, color)
    self.buttons:add({
      x = leftX + colW - 52,
      y = y,
      w = 24,
      h = ROW_H,
      label = "^",
      enabled = n > 1,
      onPress = function()
        Power.moveTier(world, id, -1)
        self:changed()
      end,
    })
    self.buttons:add({
      x = leftX + colW - 26,
      y = y,
      w = 24,
      h = ROW_H,
      label = "v",
      enabled = n < #order,
      onPress = function()
        Power.moveTier(world, id, 1)
        self:changed()
      end,
    })
    y = y + ROW_H
  end

  -- Sources and devices: one scrolling list (D76, #82). Rows are laid out from the top of the list
  -- minus the scroll offset; only rows in view get buttons, and they answer only inside the window.
  local ui = self.app.ctx.tuning.ui
  local bottom = b.y + b.h - 8
  local top = wide and (b.y + 38) or (y + 8)
  local rows = {}
  local function row(r)
    rows[#rows + 1] = r
  end
  row({ kind = "head", label = "Sources", h = 12 })
  local sources = Power.sourceList(world)
  if #sources == 0 then
    row({ kind = "none", label = "None", h = 14 })
  end
  for _, src in ipairs(sources) do
    row({ kind = "source", src = src, h = ROW_H })
  end
  row({ kind = "gap", h = 6 })
  row({ kind = "head", label = "Devices", h = 12 })
  local sinks = Power.sinkList(world)
  if #sinks == 0 then
    row({ kind = "none", label = "None placed yet", h = 14 })
  end
  for _, sink in ipairs(sinks) do
    row({ kind = "sink", sink = sink, h = ROW_H })
  end
  local contentH = 0
  for _, r in ipairs(rows) do
    contentH = contentH + r.h
  end
  local viewH = math.max(ROW_H * 2, bottom - top)
  viewH =
    self.list:fit({ x = rightX - 4, y = top, w = colW + 8, h = viewH }, contentH, ui.scrollHintHeight, ROW_H * 2).h
  self.rowButtons:clear()
  self.listItems = {}
  local function ltext(x, ty, str, color)
    self.listItems[#self.listItems + 1] = { kind = "text", x = x, y = ty, str = str, color = color, size = "small" }
  end
  -- Row content stops short of the scroll thumb at the list's right edge.
  local right = rightX + colW - (self.list.overflow and (ui.scrollBarWidth + 4) or 0)
  local ry = self.list:origin()
  for _, r in ipairs(rows) do
    if ry + r.h > top and ry < top + viewH then
      if r.kind == "head" then
        ltext(rightX, ry, r.label, theme.colors.textDim)
      elseif r.kind == "none" then
        ltext(rightX + 4, ry + 2, r.label, theme.colors.textDim)
      elseif r.kind == "source" then
        local src = r.src
        local generator = src.curve == "fuel"
        local detail
        if generator then
          local fuel = Ledger.get(world, "fuel")
          detail = src.output > 0 and string.format("%.1f kW", src.output) or string.format("fuel %d", fuel)
        else
          detail = string.format("%.1f / %g kW", src.output, src.peak)
        end
        ltext(rightX + 4, ry + 8, src.name, theme.colors.text)
        ltext(right - (generator and 118 or 70), ry + 8, detail, src.output > 0 and GREEN or theme.colors.textDim)
        if generator then
          self.rowButtons:add({
            x = right - 54,
            y = ry,
            w = 52,
            h = ROW_H,
            label = src.enabled and "Auto" or "Off",
            selected = src.enabled,
            onPress = function()
              Power.setEnabled(world, src.anchor, not Power.isEnabled(world, src.anchor))
              self:changed()
            end,
          })
        end
      elseif r.kind == "sink" then
        local sink = r.sink
        ltext(rightX + 4, ry + 3, sink.name, theme.colors.text)
        ltext(
          rightX + 4,
          ry + 13,
          string.format("%s  %.2g kW", Power.tierName(world, sink.tier), sink.draw),
          theme.colors.textDim
        )
        ltext(right - 112, ry + 8, stateText(sink), stateColor(sink.state))
        self.rowButtons:add({
          x = right - 54,
          y = ry,
          w = 52,
          h = ROW_H,
          label = sink.enabled and "On" or "Off",
          selected = sink.enabled,
          onPress = function()
            Power.setEnabled(world, sink.anchor, not Power.isEnabled(world, sink.anchor))
            self:changed()
          end,
        })
      end
    end
    ry = ry + r.h
  end
end

--- The player changed a switch or the priorities: rebuild the network numbers now (so a paused game
--- shows the effect) and redraw.
function PowerPanel:changed()
  Power.refresh(self.world)
  self:layout()
end

function PowerPanel:update(dt)
  self.refresh = (self.refresh or 0) - dt
  if self.refresh <= 0 then
    self.refresh = 0.25
    self:layout()
  end
end

function PowerPanel:action(name, data)
  if name == "press" or name == "release" then -- a drag that ends moving lets the list coast (D94)
    self.list:action(name, data)
  end
  if self.buttons:action(name, data) then
    return true
  end
  if name == "press" or name == "select" or name == "hover" then
    -- Row buttons only answer inside the list's window: a half-scrolled row must not reach out of it.
    if self.list:contains(data.x, data.y) and self.rowButtons:action(name, data) then
      return true
    end
  elseif name == "release" then
    self.rowButtons:action(name, data)
  elseif name == "cancel" then
    self.app:pop()
  elseif self.list:action(name, data, self.app.ctx.tuning.ui) then
    self:layout() -- the list follows the finger
  end
  return true
end

local function drawItem(item)
  if item.kind == "text" then
    Text.draw(item.str, item.x, item.y, { size = item.size, color = item.color })
  else
    love.graphics.setColor(theme.colors.background)
    love.graphics.rectangle("fill", item.x, item.y, item.w, 8, 2, 2)
    love.graphics.setColor(item.color)
    local fill = (item.w - 2) * math.min(1, item.frac)
    if fill >= 1 then
      love.graphics.rectangle("fill", item.x + 1, item.y + 1, fill, 6, 2, 2)
    end
    if item.mark then
      love.graphics.setColor(theme.colors.accent)
      love.graphics.rectangle("fill", item.x + item.w * item.mark, item.y - 2, 1, 12)
    end
  end
end

function PowerPanel:draw()
  local b = self.box
  Panel.frame(self.app.view, b, "Power", "Priority decides who gets power when it is short.")
  for _, item in ipairs(self.items) do
    drawItem(item)
  end
  self.buttons:draw()
  -- The sources and devices list is clipped to its window (scissor works in screen pixels).
  local scale = self.app.view.scale
  self.list:begin(scale)
  for _, item in ipairs(self.listItems) do
    drawItem(item)
  end
  self.rowButtons:draw()
  self.list:finish()
  self.list:drawCue(self.app.ctx.tuning.ui)
end

return PowerPanel
