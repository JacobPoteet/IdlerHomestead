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
  -- Each held order (due, but no room in storage) gets its own row with a refund button (D60).
  self.heldCount = #Market.heldOrders(self.world)
  self.box = Panel.box(view, 380, 70 + (#items + self.heldCount) * ROW_H + 30)
  self:layout()
end

local REASONS = {
  owned = "Owned",
  ordered = "Ordered",
  ["pickup only"] = "In town",
  ["too big for storage"] = "Too big",
}

-- How many rows fit between the header and the footer line.
function Catalog:visibleRows()
  return math.max(1, math.floor((self.box.h - 42 - 40 - (self.heldCount or 0) * ROW_H) / ROW_H))
end

-- Scroll by whole rows (drag, wheel or arrow keys) when the catalog outgrows the panel.
function Catalog:scrollBy(rows)
  local most = math.max(0, #self:items() - self:visibleRows())
  self.top = math.max(0, math.min(most, (self.top or 0) + rows))
  self:layout()
end

function Catalog:layout()
  local b, world = self.box, self.world
  self.buttons:clear()
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)
  self.rows = {}
  local items, visible = self:items(), self:visibleRows()
  self.top = math.max(0, math.min(self.top or 0, #items - visible))
  for n = self.top + 1, math.min(#items, self.top + visible) do
    local item = items[n]
    local y = b.y + 42 + (n - self.top - 1) * ROW_H
    self.rows[#self.rows + 1] = { item = item, y = y }
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
  -- Held orders sit just above the footer, each with a cancel-and-refund button.
  self.heldRows = {}
  local held = Market.heldOrders(world)
  for n, h in ipairs(held) do
    local y = b.y + b.h - 40 - (#held - n + 1) * ROW_H
    self.heldRows[#self.heldRows + 1] = { held = h, y = y }
    self.buttons:add({
      x = b.x + b.w - 84,
      y = y,
      w = 74,
      h = ROW_H - 2,
      label = "Refund $" .. h.paid,
      onPress = function()
        -- The index can shift if another order was delivered meanwhile: look the order up again.
        for _, now in ipairs(Market.heldOrders(world)) do
          if now.item == h.item then
            Market.cancelHeld(world, now.index)
            break
          end
        end
        self:resize(self.app.view)
      end,
    })
  end
end

function Catalog:update()
  -- Money changes while the panel is open; keep button states honest. A held order appearing or
  -- going away changes the panel's height, so that re-runs the whole layout.
  local money = Ledger.get(self.world, "money")
  local held = #Market.heldOrders(self.world)
  if held ~= self.heldCount then
    self:resize(self.app.view)
  elseif money ~= self.lastMoney then
    self.lastMoney = money
    self:layout()
  end
end

function Catalog:action(name, data)
  if self.buttons:action(name, data) then
    return true
  end
  if name == "cancel" then
    self.app:pop()
  elseif name == "pan" then
    self.dragged = (self.dragged or 0) + data.dy
    local rows = math.floor(math.abs(self.dragged) / ROW_H)
    if rows > 0 then
      self.dragged = self.dragged - (self.dragged > 0 and 1 or -1) * rows * ROW_H
      self:scrollBy(data.dy > 0 and -rows or rows) -- dragging up shows later rows
    end
  elseif name == "zoom" then
    self:scrollBy(-data.steps)
  elseif name == "release" then
    self.dragged = 0
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
  for _, row in ipairs(self.heldRows) do
    local item = world.registry:get("catalog", row.held.item)
    Panel.icon(Panel.catalogIcon(item), b.x + 12, row.y + 5)
    Text.draw(item.name .. ": waiting, no room in storage", b.x + 30, row.y + 6, {
      size = "small",
      width = b.w - 124,
      color = theme.colors.danger,
    })
  end
  local hidden = #self:items() - self:visibleRows()
  if hidden > 0 then
    Text.draw(
      string.format("Drag or scroll for more (%d more)", hidden - self.top > 0 and hidden - self.top or 0),
      b.x + 12,
      b.y + b.h - 34,
      { size = "small", color = theme.colors.textDim }
    )
  end
  local names = {}
  for _, o in ipairs(world.state.market.orders) do
    if not o.held then -- held orders have their own rows above
      names[#names + 1] = world.registry:get("catalog", o.item).name
    end
  end
  if #names > 0 then
    Text.draw("Coming tomorrow: " .. table.concat(names, ", "), b.x + 12, b.y + b.h - 18, {
      size = "small",
      width = b.w - 24,
      color = theme.colors.textDim,
    })
  end
  self.buttons:draw()
end

return Catalog
