-- The power panel (GDD §7.5): what the network makes and uses, how full the batteries are, which
-- devices are on, and the priority list that decides who is served first when power runs short.
-- Wide views put the summary and priorities on the left and sources and devices on the right;
-- narrow (phone portrait) views stack them. Everything is tappable (no hover, GDD §10).

local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local PowerPanel = { name = "power" }
PowerPanel.__index = PowerPanel

local ROW_H = 24
local WIDE = 560 -- box width at which the two-column layout is used
local GREEN = { 0.45, 0.82, 0.42 }

function PowerPanel.new(world, onToast)
  return setmetatable({ world = world, onToast = onToast }, PowerPanel)
end

function PowerPanel:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
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
    flow.demand <= 0 and "Nothing is asking for power" or string.format("%d%% of demand served", math.floor(satisfaction * 100 + 0.5)),
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
      self:layout()
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
        self:layout()
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
        self:layout()
      end,
    })
    y = y + ROW_H
  end

  -- Sources and devices ---------------------------------------------------------------------
  local ry = wide and (b.y + 38) or (y + 8)
  local bottom = b.y + b.h - 8
  text(rightX, ry, "Sources", theme.colors.textDim)
  ry = ry + 12
  local sources = Power.sourceList(world)
  if #sources == 0 then
    text(rightX + 4, ry + 2, "None", theme.colors.textDim)
    ry = ry + 14
  end
  for _, src in ipairs(sources) do
    if ry + ROW_H > bottom then
      text(rightX + 4, ry, "...", theme.colors.textDim)
      break
    end
    local generator = src.curve == "fuel"
    local detail
    if generator then
      local fuel = Ledger.get(world, "fuel")
      detail = src.output > 0 and string.format("%.1f kW", src.output) or string.format("fuel %d", fuel)
    else
      detail = string.format("%.1f / %g kW", src.output, src.peak)
    end
    text(rightX + 4, ry + 8, src.name, theme.colors.text)
    text(rightX + colW - (generator and 118 or 70), ry + 8, detail, src.output > 0 and GREEN or theme.colors.textDim)
    if generator then
      self.buttons:add({
        x = rightX + colW - 54,
        y = ry,
        w = 52,
        h = ROW_H,
        label = src.enabled and "Auto" or "Off",
        selected = src.enabled,
        onPress = function()
          Power.setEnabled(world, src.anchor, not Power.isEnabled(world, src.anchor))
          self:layout()
        end,
      })
    end
    ry = ry + ROW_H
  end
  ry = ry + 6
  text(rightX, ry, "Devices", theme.colors.textDim)
  ry = ry + 12
  local sinks = Power.sinkList(world)
  if #sinks == 0 then
    text(rightX + 4, ry + 2, "None placed yet", theme.colors.textDim)
  end
  for n, sink in ipairs(sinks) do
    if ry + ROW_H > bottom then
      text(rightX + 4, ry, string.format("+%d more", #sinks - n + 1), theme.colors.textDim)
      break
    end
    text(rightX + 4, ry + 3, sink.name, theme.colors.text)
    text(rightX + 4, ry + 13, string.format("%s  %.2g kW", Power.tierName(world, sink.tier), sink.draw), theme.colors.textDim)
    text(rightX + colW - 112, ry + 8, stateText(sink), stateColor(sink.state))
    self.buttons:add({
      x = rightX + colW - 54,
      y = ry,
      w = 52,
      h = ROW_H,
      label = sink.enabled and "On" or "Off",
      selected = sink.enabled,
      onPress = function()
        Power.setEnabled(world, sink.anchor, not Power.isEnabled(world, sink.anchor))
        self:layout()
      end,
    })
    ry = ry + ROW_H
  end
end

function PowerPanel:update(dt)
  self.refresh = (self.refresh or 0) - dt
  if self.refresh <= 0 then
    self.refresh = 0.25
    self:layout()
  end
end

function PowerPanel:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" then
    self.app:pop()
  end
  return true
end

function PowerPanel:draw()
  local b = self.box
  Panel.frame(self.app.view, b, "Power", "Priority decides who gets power when it is short.")
  for _, item in ipairs(self.items) do
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
  self.buttons:draw()
end

return PowerPanel
