-- The truck (GDD §6.5, §7.6): battery status, the load, and the trip to town as a menu.
-- At home: charge, the load (D75: what goes to town, loaded in the Load the truck panel), solar output,
-- "Load the truck" and "Drive to town". In town: sell the load, buy (no delivery fee, pickup-only
-- items allowed), then drive home. Anything not loaded stays home.

local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Power = require("src.sim.systems.power")
local Buttons = require("src.ui.buttons")
local ItemCard = require("src.ui.item_card")
local Panel = require("src.ui.panel")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Truck = { name = "truck" }
Truck.__index = Truck

local ROW_H = 22
local LOAD_ROW_H = 14 -- one line of the load list in town
local HOME_H = 196 -- panel height at home: status, bar, load lines, power line, two buttons

--- "about 5 hours", "under an hour", "about 2 days" for in-game hours (the truck charges by the sun).
function Truck.duration(hours)
  if hours < 1 then
    return "under an hour"
  elseif hours < 24 then
    local n = math.ceil(hours)
    return n == 1 and "about 1 hour" or string.format("about %d hours", n)
  end
  local n = math.ceil(hours / 24)
  return n == 1 and "about 1 day" or string.format("about %d days", n)
end

--- The headline of the home panel from Market.tripStatus: "Trip ready" or what is missing.
function Truck.statusText(trip)
  if trip.ready then
    return "Trip ready: drive to town"
  end
  local missing = trip.cost - trip.charge
  if trip.hours then
    return string.format("%.1f kWh to go: %s at this rate", missing, Truck.duration(trip.hours))
  end
  return string.format("%.1f kWh to go: not charging now", missing)
end

--- What the truck carries and is worth, from Market.tripStatus.
function Truck.loadText(trip)
  if trip.units == 0 then
    return string.format("Load: empty (0 / %d cargo)", trip.cargo)
  end
  return string.format("Load: %d / %d cargo, worth $%d in town", trip.units, trip.cargo, trip.value)
end

--- What else could go, from Market.tripStatus.
function Truck.spareText(trip)
  if trip.spare == 0 then
    return "Nothing spare left at home to load"
  end
  return string.format("%d spare units at home not loaded", trip.spare)
end

function Truck.new(world, onToast)
  return setmetatable({ world = world, onToast = onToast }, Truck)
end

function Truck:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.shopButtons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  local relayout = function()
    self:layout()
  end
  self.shop, self.loadList = ScrollList.new(relayout), ScrollList.new(relayout)
  self.card = ItemCard.new(self.app.ctx.tuning.input.minTouchTarget)
end

--- Open the item card for a shop row (#266).
function Truck:showCard(item)
  self.card:open(self.world, item.id, true, function()
    return self:buy(item)
  end)
  self.card:layout(self.app.view)
end

--- Buy `item` in town (from a row button or the item card). True when it went through.
function Truck:buy(item)
  local ok = Market.buyInTown(self.world, item.id)
  if ok then
    self.onToast("Bought " .. item.name)
  end
  self:layout()
  return ok and true or false
end

function Truck:inTown()
  return self.world.state.market.inTown
end

function Truck:resize(view)
  if self:inTown() then
    self.box = Panel.box(view, 600, view.h - 16)
  else
    self.box = Panel.box(view, 300, HOME_H)
  end
  self:layout()
end

-- Start the trip (the panel turns into the town menu).
function Truck:drive()
  if Market.startTrip(self.world) then
    self:resize(self.app.view)
  end
end

function Truck:layout()
  local b, world = self.box, self.world
  self.buttons:clear()
  if not self:inTown() then
    Panel.closeButton(self.buttons, b, function()
      self.app:pop()
    end)
    local half = (b.w - 24 - 6) / 2
    self.buttons:add({
      x = b.x + 12,
      y = b.y + b.h - 34,
      w = half,
      h = 26,
      label = "Load the truck",
      onPress = function()
        self.app:push(require("src.scenes.load").new(world, self.onToast))
      end,
    })
    self.buttons:add({
      x = b.x + 12 + half + 6,
      y = b.y + b.h - 34,
      w = half,
      h = 26,
      label = "Drive to town",
      style = "accent",
      enabled = Market.canTrip(world),
      onPress = function()
        -- An empty truck with goods to spare is most likely a forgotten load: ask once.
        if Market.loadUnits(world) == 0 and Market.spareUnits(world) > 0 then
          self.app:push(require("src.scenes.confirm").new({
            title = "The truck is empty",
            message = "Nothing is loaded, so nothing will be sold in town. Load the truck first, or drive just to shop?",
            confirmLabel = "Drive anyway",
            cancelLabel = "Not yet",
            onConfirm = function()
              self:drive()
            end,
          }))
        else
          self:drive()
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
  local _, total, units = Market.loadQuote(world)
  self.buttons:add({
    x = b.x + 12,
    y = b.y + b.h - 34,
    w = b.w / 2 - 24,
    h = 26,
    label = units > 0 and ("Sell the load  $" .. total) or "Nothing loaded",
    enabled = units > 0,
    style = "accent",
    onPress = function()
      local earned = Market.sellLoad(world)
      self.onToast("Sold for $" .. earned)
      self:layout()
    end,
  })
  self.shopRows = {}
  local x = b.x + b.w / 2 + 6
  local known = {}
  for _, item in ipairs(world.registry:all("catalog")) do
    if Market.isKnown(world, item.id) then
      known[#known + 1] = item
    end
  end
  -- Both town lists scroll (D87, #8): the shop on the right and the load on the left clip to their
  -- windows and take drag, wheel and keys.
  local ui = self.app.ctx.tuning.ui
  self.shopButtons:clear()
  local shopTop = b.y + 50
  self.shop:fit(
    { x = x - 6, y = shopTop, w = b.x + b.w - x + 6, h = b.y + b.h - 56 - shopTop },
    #known * ROW_H,
    ui.scrollHintHeight,
    ROW_H
  )
  local lines = Market.loadQuote(world)
  local loadTop = b.y + 52
  self.loadList:fit(
    { x = b.x + 8, y = loadTop, w = b.w / 2 - 16, h = b.y + b.h - 64 - loadTop },
    #lines * LOAD_ROW_H,
    ui.scrollHintHeight,
    LOAD_ROW_H
  )
  local barRoom = self.shop.overflow and ui.scrollBarWidth + 2 or 0
  for n, item in ipairs(known) do
    local y = self.shop:origin() + (n - 1) * ROW_H
    if not self.shop:visible(y, ROW_H) then
      goto continue
    end
    self.shopRows[#self.shopRows + 1] = { item = item, y = y, x = x }
    local reason = Market.cannotBuy(world, item.id, true)
    self.shopButtons:add({
      x = b.x + b.w - 70 - barRoom,
      y = y,
      w = 60,
      h = ROW_H - 2,
      label = (reason == "owned" or reason == "replaced") and "Owned"
        or reason == "needs Footing" and world.tuning.progress.gate.short
        or reason == "no room" and "No room"
        or reason == "too big for storage" and "Too big"
        or ("$" .. Market.itemPrice(world, item.id)),
      enabled = reason == nil,
      style = world.state.market.specials[item.id] and "accent" or nil,
      onPress = function()
        self:buy(item)
      end,
    })
    ::continue::
  end
end

function Truck:update(dt)
  self.refresh = (self.refresh or 0) - dt
  if self.refresh <= 0 then
    self.refresh = 0.5
    self:layout()
    self.card:layout(self.app.view)
  end
end

--- The shop item whose row is under view point (x, y), or nil.
function Truck:rowAt(x, y)
  if not self.shop:contains(x, y) then
    return nil
  end
  for _, row in ipairs(self.shopRows or {}) do
    if y >= row.y and y < row.y + ROW_H then
      return row.item
    end
  end
  return nil
end

function Truck:action(name, data)
  if self.card:isOpen() then -- the item card is modal (#266)
    return self.card:action(name, data)
  end
  if name == "press" or name == "release" then
    self.shop:action(name, data)
    self.loadList:action(name, data)
  end
  if self.buttons:action(name, data) then
    return true
  end
  if self:inTown() then
    -- The list under the pointer (or last touched) takes the drag, wheel and keys.
    if data.x then
      self.leftFocus = data.x < self.box.x + self.box.w / 2
    end
    if name == "press" or name == "select" or name == "hover" then
      if self.shop:contains(data.x, data.y) and self.shopButtons:action(name, data) then
        return true
      end
      -- A tap on the rest of a shop row shows what the item is before buying (#266).
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
      self.shopButtons:action(name, data)
    elseif (self.leftFocus and self.loadList or self.shop):action(name, data, self.app.ctx.tuning.ui) then
      self:layout()
    end
  end
  if name == "cancel" and not self:inTown() then
    self.app:pop()
  end
  return true
end

local function bar(x, y, w, h, frac, color)
  love.graphics.setColor(theme.colors.background)
  love.graphics.rectangle("fill", x, y, w, h, 2, 2)
  local fill = math.max(0, (w - 2) * math.min(1, frac))
  if fill >= 1 then
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x + 1, y + 1, fill, h - 2, 2, 2)
  end
end

function Truck:draw()
  local b, world = self.box, self.world
  if not self:inTown() then
    local trip = Market.tripStatus(world)
    local charge, cap, cost = trip.charge, trip.capacity, trip.cost
    local dim, w = theme.colors.textDim, b.w - 24
    Panel.frame(self.app.view, b, "Electric truck", "Charged from spare power, after the homestead.")
    -- Ready or not, in words (D72, #162).
    Text.draw(Truck.statusText(trip), b.x + 12, b.y + 36, {
      size = "body",
      width = w,
      color = trip.ready and theme.colors.accent or theme.colors.text,
    })
    bar(b.x + 12, b.y + 56, b.w - 24, 12, charge / cap, { 0.45, 0.82, 0.42 })
    -- Mark how much a trip needs.
    local mx = b.x + 12 + (b.w - 24) * cost / cap
    love.graphics.setColor(theme.colors.accent)
    love.graphics.rectangle("fill", mx, b.y + 53, 1, 18)
    Text.draw(
      string.format("%.1f / %d kWh · a trip uses %d", charge, cap, cost),
      b.x + 12,
      b.y + 74,
      { size = "small" }
    )
    -- The load (D75): what goes to town, and what else could.
    Text.draw(
      Truck.loadText(trip),
      b.x + 12,
      b.y + 92,
      { size = "small", width = w, color = trip.units > 0 and theme.colors.accent or nil }
    )
    bar(b.x + 12, b.y + 106, b.w - 24, 6, trip.units / trip.cargo, theme.colors.accent)
    Text.draw(Truck.spareText(trip), b.x + 12, b.y + 116, { size = "small", width = w, color = dim })
    Text.draw(
      string.format("Making %.2f kW, homestead using %.2f kW", Power.output(world), Power.flow(world).served),
      b.x + 12,
      b.y + 132,
      {
        size = "small",
        color = dim,
        width = w,
      }
    )
  else
    Panel.frame(self.app.view, b, "Town", string.format("You have $%d", Ledger.get(world, "money")))
    local lines, total, units = Market.loadQuote(world)
    Text.draw(string.format("The load (%d / %d cargo)", units, Market.cargoCapacity(world)), b.x + 12, b.y + 38, {
      size = "small",
      color = theme.colors.textDim,
    })
    self.loadList:begin(self.app.view.scale)
    for n, line in ipairs(lines) do
      local y = self.loadList:origin() + (n - 1) * LOAD_ROW_H
      if self.loadList:visible(y, LOAD_ROW_H) then
        local res = world.registry:get("resources", line.id)
        Panel.icon(Panel.resourceIcon(line.id), b.x + 12, y)
        Text.draw(string.format("%s  %d x $%d", res.name, line.units, line.price), b.x + 28, y + 1, { size = "small" })
      end
    end
    self.loadList:finish()
    self.loadList:drawCue(self.app.ctx.tuning.ui)
    if units == 0 then
      Text.draw(
        "Nothing loaded. Load the truck at home before the next trip; unloaded goods stay home.",
        b.x + 12,
        b.y + 52,
        {
          size = "small",
          width = b.w / 2 - 24,
          color = theme.colors.textDim,
        }
      )
    end
    Text.draw(
      string.format("Total $%d", total),
      b.x + 12,
      b.y + b.h - 50,
      { size = "small", color = theme.colors.accent }
    )
    -- A trip costs no game time (D78): the clock waits while the town menu is open.
    Text.draw("Game time is paused while you are in town.", b.x + 12, b.y + b.h - 50, {
      size = "small",
      width = b.w - 24,
      align = "right",
      color = theme.colors.textDim,
    })
    Text.draw("Shop", b.x + b.w / 2 + 6, b.y + 38, { size = "small", color = theme.colors.textDim })
    self.shop:begin(self.app.view.scale)
    for _, row in ipairs(self.shopRows or {}) do
      Panel.icon(Panel.catalogIcon(row.item), row.x, row.y + 4)
      Text.draw(row.item.name, row.x + 16, row.y + 5, { size = "small" })
    end
    self.shopButtons:draw()
    self.shop:finish()
    self.shop:drawCue(self.app.ctx.tuning.ui)
  end
  self.buttons:draw()
  self.card:draw(self.app.view)
end

return Truck
