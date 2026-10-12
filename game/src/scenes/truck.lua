-- The truck (GDD §6.5, §7.6): battery status, and the trip to town as a menu.
-- At home: charge, solar output, "Drive to town". In town: sell the crate, buy (no delivery fee,
-- pickup-only items allowed), then drive home.

local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Power = require("src.sim.systems.power")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Truck = { name = "truck" }
Truck.__index = Truck

local ROW_H = 22

function Truck.new(world, onToast)
  return setmetatable({ world = world, onToast = onToast }, Truck)
end

function Truck:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Truck:inTown()
  return self.world.state.market.inTown
end

function Truck:resize(view)
  if self:inTown() then
    self.box = Panel.box(view, 600, view.h - 16)
  else
    self.box = Panel.box(view, 300, 150)
  end
  self:layout()
end

function Truck:layout()
  local b, world = self.box, self.world
  self.buttons:clear()
  if not self:inTown() then
    Panel.closeButton(self.buttons, b, function()
      self.app:pop()
    end)
    self.buttons:add({
      x = b.x + 12,
      y = b.y + b.h - 34,
      w = b.w - 24,
      h = 26,
      label = "Drive to town",
      style = "accent",
      enabled = Market.canTrip(world),
      onPress = function()
        if Market.startTrip(world) then
          self:resize(self.app.view)
        end
      end,
    })
    return
  end
  -- Town
  self.buttons:add({
    x = b.x + b.w - 100,
    y = b.y + 6,
    w = 92,
    h = 22,
    label = "Drive home",
    style = "accent",
    onPress = function()
      Market.endTrip(world)
      self.app:pop()
    end,
  })
  local _, total = Market.crateQuote(world)
  self.buttons:add({
    x = b.x + 12,
    y = b.y + b.h - 34,
    w = b.w / 2 - 24,
    h = 26,
    label = total > 0 and ("Sell crate  $" .. total) or "Crate is empty",
    enabled = total > 0,
    style = "accent",
    onPress = function()
      local earned = Market.sellCrate(world)
      self.onToast("Sold for $" .. earned)
      self:layout()
    end,
  })
  self.shopRows = {}
  local x = b.x + b.w / 2 + 6
  local n = 0
  for _, item in ipairs(world.registry:all("catalog")) do
    if Market.isKnown(world, item.id) then
      n = n + 1
      local y = b.y + 50 + (n - 1) * ROW_H
      if y + ROW_H < b.y + b.h - 8 then
        self.shopRows[#self.shopRows + 1] = { item = item, y = y, x = x }
        local reason = Market.cannotBuy(world, item.id, true)
        self.buttons:add({
          x = b.x + b.w - 70,
          y = y,
          w = 60,
          h = ROW_H - 2,
          label = reason == "owned" and "Owned" or ("$" .. Market.itemPrice(world, item.id)),
          enabled = reason == nil,
          style = world.state.market.specials[item.id] and "accent" or nil,
          onPress = function()
            if Market.buyInTown(world, item.id) then
              self.onToast("Bought " .. item.name)
            end
            self:layout()
          end,
        })
      end
    end
  end
end

function Truck:update(dt)
  self.refresh = (self.refresh or 0) - dt
  if self.refresh <= 0 then
    self.refresh = 0.5
    self:layout()
  end
end

function Truck:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" and not self:inTown() then
    self.app:pop()
  end
  return true
end

local function bar(x, y, w, h, frac, color)
  love.graphics.setColor(theme.colors.background)
  love.graphics.rectangle("fill", x, y, w, h, 2, 2)
  love.graphics.setColor(color)
  love.graphics.rectangle("fill", x + 1, y + 1, math.max(0, (w - 2) * math.min(1, frac)), h - 2, 2, 2)
end

function Truck:draw()
  local b, world = self.box, self.world
  local truck = world.state.land.truck
  if not self:inTown() then
    local charge, cap = Power.charge(world, truck), Power.capacity(world, truck)
    local cost = world.tuning.economy.tripCost
    Panel.frame(self.app.view, b, "Electric truck", "Charged by the folding solar panel.")
    bar(b.x + 12, b.y + 46, b.w - 24, 12, charge / cap, { 0.45, 0.82, 0.42 })
    -- Mark how much a trip needs.
    local mx = b.x + 12 + (b.w - 24) * cost / cap
    love.graphics.setColor(theme.colors.accent)
    love.graphics.rectangle("fill", mx, b.y + 43, 1, 18)
    Text.draw(string.format("%.1f / %d kWh · a trip uses %d", charge, cap, cost), b.x + 12, b.y + 64, { size = "small" })
    Text.draw(string.format("Solar now: %.2f kW", Power.output(world)), b.x + 12, b.y + 78, {
      size = "small",
      color = theme.colors.textDim,
    })
  else
    Panel.frame(self.app.view, b, "Town", string.format("You have $%d", Ledger.get(world, "money")))
    local lines, total, units = Market.crateQuote(world)
    Text.draw(string.format("Sell crate (%d / %d cargo)", units, world.tuning.economy.cargoCapacity), b.x + 12, b.y + 38, {
      size = "small",
      color = theme.colors.textDim,
    })
    for n, line in ipairs(lines) do
      local y = b.y + 52 + (n - 1) * 14
      if y < b.y + b.h - 50 then
        local res = world.registry:get("resources", line.id)
        Panel.icon(Panel.resourceIcon(line.id), b.x + 12, y)
        Text.draw(string.format("%s  %d x $%d", res.name, line.units, line.price), b.x + 28, y + 1, { size = "small" })
      end
    end
    Text.draw(string.format("Total $%d", total), b.x + 12, b.y + b.h - 50, { size = "small", color = theme.colors.accent })
    Text.draw("Shop", b.x + b.w / 2 + 6, b.y + 38, { size = "small", color = theme.colors.textDim })
    for _, row in ipairs(self.shopRows or {}) do
      Panel.icon(Panel.catalogIcon(row.item), row.x, row.y + 4)
      Text.draw(row.item.name, row.x + 16, row.y + 5, { size = "small" })
    end
  end
  self.buttons:draw()
end

return Truck
