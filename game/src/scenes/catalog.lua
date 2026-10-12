-- Supply catalog (GDD §6.3): order anytime, delivered next morning to the drop-off for a fee.
-- Pickup-only items are listed but can only be bought on a truck trip.

local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Catalog = { name = "catalog" }
Catalog.__index = Catalog

local ROW_H = 24

function Catalog.new(world, onToast)
  return setmetatable({ world = world, onToast = onToast }, Catalog)
end

function Catalog:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Catalog:items()
  local list = {}
  for _, item in ipairs(self.world.registry:all("catalog")) do
    if Market.isKnown(self.world, item.id) then
      list[#list + 1] = item
    end
  end
  return list
end

function Catalog:resize(view)
  local items = self:items()
  self.box = Panel.box(view, 380, 70 + #items * ROW_H + 30)
  self:layout()
end

local REASONS = { owned = "Owned", ordered = "Ordered", ["pickup only"] = "In town" }

function Catalog:layout()
  local b, world = self.box, self.world
  self.buttons:clear()
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)
  self.rows = {}
  for n, item in ipairs(self:items()) do
    local y = b.y + 42 + (n - 1) * ROW_H
    self.rows[n] = { item = item, y = y }
    local reason = Market.cannotBuy(world, item.id, false)
    local fee = world.tuning.economy.deliveryFee
    self.buttons:add({
      x = b.x + b.w - 84,
      y = y,
      w = 74,
      h = ROW_H - 2,
      label = REASONS[reason] or ("Order $" .. (Market.itemPrice(world, item.id) + fee)),
      enabled = reason == nil,
      style = world.state.market.specials[item.id] and "accent" or nil,
      onPress = function()
        if Market.order(world, item.id) then
          self.onToast("Ordered " .. item.name .. " · arrives tomorrow")
        end
        self:layout()
      end,
    })
  end
end

function Catalog:update()
  -- Money changes while the panel is open; keep button states honest.
  local money = Ledger.get(self.world, "money")
  if money ~= self.lastMoney then
    self.lastMoney = money
    self:layout()
  end
end

function Catalog:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" then
    self.app:pop()
  end
  return true
end

function Catalog:draw()
  local b, world = self.box, self.world
  local fee = world.tuning.economy.deliveryFee
  Panel.frame(self.app.view, b, "Catalog", string.format(
    "You have $%d · $%d delivery · arrives %02d:00 tomorrow",
    Ledger.get(world, "money"),
    fee,
    world.tuning.economy.deliveryHour
  ))
  for _, row in ipairs(self.rows) do
    local item = row.item
    Panel.icon(Panel.catalogIcon(item), b.x + 12, row.y + 5)
    Text.draw(item.name, b.x + 30, row.y + 6, { size = "small" })
    local price = Market.itemPrice(world, item.id)
    local label = "$" .. price
    if world.state.market.specials[item.id] then
      label = label .. "  sale!"
    end
    Text.draw(label, b.x + 170, row.y + 6, {
      size = "small",
      color = world.state.market.specials[item.id] and theme.colors.accent or theme.colors.textDim,
    })
  end
  local orders = world.state.market.orders
  if #orders > 0 then
    local names = {}
    for _, o in ipairs(orders) do
      names[#names + 1] = world.registry:get("catalog", o.item).name
    end
    Text.draw("Coming tomorrow: " .. table.concat(names, ", "), b.x + 12, b.y + b.h - 18, {
      size = "small",
      width = b.w - 24,
      color = theme.colors.textDim,
    })
  end
  self.buttons:draw()
end

return Catalog
