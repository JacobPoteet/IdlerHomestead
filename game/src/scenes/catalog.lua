-- Supply catalog (GDD §6.3): order anytime, delivered next morning to the drop-off for a fee.
-- Pickup-only items are listed but can only be bought on a truck trip.

local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Buttons = require("src.ui.buttons")
local ItemCard = require("src.ui.item_card")
local Panel = require("src.ui.panel")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Catalog = { name = "catalog" }
Catalog.__index = Catalog

local ROW_H = 24
local HINT_H = 30 -- px of footer for the two-line "where money comes from" hint

function Catalog.new(world, onToast)
  return setmetatable({ world = world, onToast = onToast }, Catalog)
end

function Catalog:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.rowButtons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.list = ScrollList.new(function()
    self:layout()
  end)
  self.card = ItemCard.new(self.app.ctx.tuning.input.minTouchTarget)
end

--- Open the item card for a catalog item (#266).
function Catalog:showCard(item)
  self.card:open(self.world, item.id, false, function()
    return self:order(item)
  end)
  self.card:layout(self.app.view)
end

function Catalog:items()
  return Market.catalogList(self.world) -- every item while debug cheat mode is on (D126)
end

--- The debug toggle shows while the F1 overlay is on, and stays while cheating so it can be turned off.
function Catalog:debugShown()
  local game = self.app.ctx.game
  return Market.cheatOn(self.world) or (game ~= nil and game.debug ~= nil and game.debug.visible == true)
end

--- When money is under the cheapest order (and nothing is on its way), say where early money comes
--- from (D88, #161). Nil otherwise.
function Catalog:moneyHintText()
  local world = self.world
  if #world.state.market.orders > 0 then
    return nil
  end
  local cheapest = Market.cheapestOrder(world)
  if not cheapest or Ledger.get(world, "money") >= cheapest then
    return nil
  end
  return string.format(
    "Cheapest order is $%d. Earn it by clearing junk piles ($%d to $%d each) or selling spare food on a truck trip.",
    cheapest,
    self:junkPay()
  )
end

--- The least and most cash one junk pile pays, read from its content definition.
function Catalog:junkPay()
  local pay = self.world.registry:get("objects", "junk").yields.money
  if type(pay) == "number" then
    return pay, pay
  end
  return pay[1], pay[2]
end

function Catalog:resize(view)
  local items = self:items()
  -- Each held order (due, but no room in storage) gets its own row with a refund button (D60).
  self.heldCount = #Market.heldOrders(self.world)
  self.moneyHint = self:moneyHintText()
  self.hintH = self.moneyHint and HINT_H or 0
  self.box = Panel.box(view, 380, 70 + (#items + self.heldCount) * ROW_H + 30 + self.hintH)
  self:layout()
  self.card:layout(view)
end

local REASONS = {
  owned = "Owned",
  replaced = "Owned", -- a better tier is owned: the lower one is covered (D115)
  ordered = "Ordered",
  ["pickup only"] = "In town",
  ["too big for storage"] = "Too big",
}

function Catalog:layout()
  local b, world = self.box, self.world
  self.buttons:clear()
  self.rowButtons:clear()
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)
  self.debugWasShown = self:debugShown()
  if self.debugWasShown then
    local cfg = self.app.ctx.tuning.ui.catalogCheat
    self.buttons:add({
      x = b.x + b.w - 58 - 4 - cfg.buttonWidth,
      y = b.y + 6,
      w = cfg.buttonWidth,
      h = 22,
      label = cfg.button,
      style = Market.cheatOn(world) and "accent" or nil,
      onPress = function()
        Market.setCheat(world, not Market.cheatOn(world))
        self:resize(self.app.view)
      end,
    })
  end
  self.rows = {}
  -- The item list scrolls (D87, #8) between the header and the held orders / footer.
  local items = self:items()
  local ui = self.app.ctx.tuning.ui
  local top = b.y + 42
  local room = b.y + b.h - 40 - (self.hintH or 0) - (self.heldCount or 0) * ROW_H - top
  self.list:fit({ x = b.x, y = top, w = b.w, h = room }, #items * ROW_H, ui.scrollHintHeight, ROW_H)
  local right = b.x + b.w - 84 - (self.list.overflow and ui.scrollBarWidth + 2 or 0)
  for n, item in ipairs(items) do
    local y = self.list:origin() + (n - 1) * ROW_H
    if not self.list:visible(y, ROW_H) then
      goto continue
    end
    self.rows[#self.rows + 1] = { item = item, y = y }
    local reason = Market.cannotBuy(world, item.id, false)
    local fee = world.tuning.economy.deliveryFee
    self.rowButtons:add({
      x = right,
      y = y,
      w = 74,
      h = ROW_H - 2,
      label = REASONS[reason]
        or (Market.cheatOn(world) and ui.catalogCheat.row or ("Order $" .. (Market.itemPrice(world, item.id) + fee))),
      enabled = reason == nil,
      style = world.state.market.specials[item.id] and "accent" or nil,
      onPress = function()
        self:order(item)
      end,
    })
    ::continue::
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
  if self:debugShown() ~= self.debugWasShown then -- F1 toggled the overlay
    self:layout()
  end
  local held = #Market.heldOrders(self.world)
  if held ~= self.heldCount then
    self:resize(self.app.view)
  elseif (self:moneyHintText() ~= nil) ~= (self.moneyHint ~= nil) then
    self:resize(self.app.view)
  elseif money ~= self.lastMoney then
    self.lastMoney = money
    self:layout()
    self.card:layout(self.app.view)
  end
end

--- The catalog item whose row is under view point (x, y), or nil.
function Catalog:rowAt(x, y)
  if not self.list:contains(x, y) then
    return nil
  end
  for _, row in ipairs(self.rows) do
    if y >= row.y and y < row.y + ROW_H then
      return row.item
    end
  end
  return nil
end

--- Order `id` (from a row button or the item card). True when the order went through.
function Catalog:order(item)
  local ok = Market.order(self.world, item.id) -- in cheat mode this is a free, immediate grant (D126)
  if ok and Market.cheatOn(self.world) then
    self.onToast(string.format(self.app.ctx.tuning.ui.catalogCheat.granted, item.name))
  elseif ok then
    self.onToast("Ordered " .. item.name .. " · arrives tomorrow")
  end
  self:layout()
  return ok and true or false
end

function Catalog:action(name, data)
  if self.card:isOpen() then -- the item card is modal (#266)
    return self.card:action(name, data)
  end
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
    -- A tap on the rest of a row shows what the item is before buying (#266).
    local item = name == "select" and self:rowAt(data.x, data.y)
    if item then
      self:showCard(item)
      return true
    end
  elseif name == "context" then -- a long-press or right click shows the same card
    local item = self:rowAt(data.x, data.y)
    if item then
      self:showCard(item)
    end
  elseif name == "release" then
    self.rowButtons:action(name, data)
  elseif name == "cancel" then
    self.app:pop()
  elseif self.list:action(name, data, self.app.ctx.tuning.ui) then
    self:layout()
  end
  return true
end

function Catalog:draw()
  local b, world = self.box, self.world
  local fee = world.tuning.economy.deliveryFee
  local cheat = self.app.ctx.tuning.ui.catalogCheat
  Panel.frame(
    self.app.view,
    b,
    "Catalog",
    Market.cheatOn(world) and cheat.subtitle
      or string.format(
        "You have $%d · $%d delivery · arrives %02d:00 tomorrow",
        Ledger.get(world, "money"),
        fee,
        world.tuning.economy.deliveryHour
      )
  )
  if Market.cheatOn(world) then
    Text.draw(cheat.tag, b.x + 80, b.y + 9, { size = "body", color = theme.colors.danger })
  end
  self.list:begin(self.app.view.scale)
  for _, row in ipairs(self.rows) do
    local item = row.item
    Panel.icon(Panel.catalogIcon(item), b.x + 12, row.y + 5)
    Text.draw(item.name, b.x + 30, row.y + 6, { size = "small" })
    local price = Market.itemPrice(world, item.id)
    local label = Market.cheatOn(world) and "$0" or ("$" .. price)
    if not Market.cheatOn(world) and world.state.market.specials[item.id] then
      label = label .. "  sale!"
    end
    Text.draw(label, b.x + 170, row.y + 6, {
      size = "small",
      color = world.state.market.specials[item.id] and theme.colors.accent or theme.colors.textDim,
    })
  end
  self.rowButtons:draw()
  self.list:finish()
  self.list:drawCue(self.app.ctx.tuning.ui)
  for _, row in ipairs(self.heldRows) do
    local item = world.registry:get("catalog", row.held.item)
    Panel.icon(Panel.catalogIcon(item), b.x + 12, row.y + 5)
    Text.draw(item.name .. ": waiting, no room in storage", b.x + 30, row.y + 6, {
      size = "small",
      width = b.w - 124,
      color = theme.colors.danger,
    })
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
  elseif self.moneyHint then
    Text.draw(self.moneyHint, b.x + 12, b.y + b.h - 34, {
      size = "small",
      width = b.w - 24,
      color = theme.colors.accent,
    })
  end
  self.buttons:draw()
  self.card:draw(self.app.view)
end

return Catalog
