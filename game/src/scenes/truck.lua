-- The truck (GDD §6.5, §7.6): battery status, the load, and the trip to town as a menu.
-- At home: charge, the load (D75: what goes to town, loaded in the Load the truck panel), solar output,
-- "Load the truck" and "Drive to town". In town: sell the load, buy (no delivery fee, pickup-only
-- items allowed), then drive home. Anything not loaded stays home.

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
  -- The shop list scrolls by whole rows (drag or wheel) when it outgrows the panel.
  local visible = self:shopVisibleRows()
  self.top = math.max(0, math.min(self.top or 0, #known - visible))
  for n = self.top + 1, math.min(#known, self.top + visible) do
    local item = known[n]
    local y = b.y + 50 + (n - self.top - 1) * ROW_H
    self.shopRows[#self.shopRows + 1] = { item = item, y = y, x = x }
    local reason = Market.cannotBuy(world, item.id, true)
    self.buttons:add({
      x = b.x + b.w - 70,
      y = y,
      w = 60,
      h = ROW_H - 2,
      label = reason == "owned" and "Owned" or reason == "no room" and "No room" or reason == "too big for storage" and "Too big" or ("$" .. Market.itemPrice(world, item.id)),
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
  self.shopMore = #known - self.top - visible
end

-- Shop rows that fit between the header and the bottom edge.
function Truck:shopVisibleRows()
  return math.max(1, math.floor((self.box.h - 50 - 16) / ROW_H))
end

function Truck:scrollShop(rows)
  self.top = (self.top or 0) + rows
  self:layout()
end

function Truck:update(dt)
  self.refresh = (self.refresh or 0) - dt
  if self.refresh <= 0 then
    self.refresh = 0.5
    self:layout()
  end
end

function Truck:action(name, data)
  if self.buttons:action(name, data) then
    return true
  end
  if name == "cancel" and not self:inTown() then
    self.app:pop()
  elseif self:inTown() and name == "pan" then
    self.dragged = (self.dragged or 0) + data.dy
    local rows = math.floor(math.abs(self.dragged) / ROW_H)
    if rows > 0 then
      self.dragged = self.dragged - (self.dragged > 0 and 1 or -1) * rows * ROW_H
      self:scrollShop(data.dy > 0 and -rows or rows) -- dragging up shows later rows
    end
  elseif self:inTown() and name == "zoom" then
    self:scrollShop(-data.steps)
  elseif name == "release" then
    self.dragged = 0
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
    Text.draw(string.format("%.1f / %d kWh · a trip uses %d", charge, cap, cost), b.x + 12, b.y + 74, { size = "small" })
    -- The load (D75): what goes to town, and what else could.
    Text.draw(Truck.loadText(trip), b.x + 12, b.y + 92, { size = "small", width = w, color = trip.units > 0 and theme.colors.accent or nil })
    bar(b.x + 12, b.y + 106, b.w - 24, 6, trip.units / trip.cargo, theme.colors.accent)
    Text.draw(Truck.spareText(trip), b.x + 12, b.y + 116, { size = "small", width = w, color = dim })
    Text.draw(string.format("Making %.2f kW, homestead using %.2f kW", Power.output(world), Power.flow(world).served), b.x + 12, b.y + 132, {
      size = "small",
      color = dim,
      width = w,
    })
  else
    Panel.frame(self.app.view, b, "Town", string.format("You have $%d", Ledger.get(world, "money")))
    local lines, total, units = Market.loadQuote(world)
    Text.draw(string.format("The load (%d / %d cargo)", units, Market.cargoCapacity(world)), b.x + 12, b.y + 38, {
      size = "small",
      color = theme.colors.textDim,
    })
    for n, line in ipairs(lines) do
      local y = b.y + 52 + (n - 1) * 14
      if y < b.y + b.h - 64 then
        local res = world.registry:get("resources", line.id)
        Panel.icon(Panel.resourceIcon(line.id), b.x + 12, y)
        Text.draw(string.format("%s  %d x $%d", res.name, line.units, line.price), b.x + 28, y + 1, { size = "small" })
      end
    end
    if units == 0 then
      Text.draw("Nothing loaded. Load the truck at home before the next trip; unloaded goods stay home.", b.x + 12, b.y + 52, {
        size = "small",
        width = b.w / 2 - 24,
        color = theme.colors.textDim,
      })
    end
    Text.draw(string.format("Total $%d", total), b.x + 12, b.y + b.h - 50, { size = "small", color = theme.colors.accent })
    -- A trip costs no game time (D78): the clock waits while the town menu is open.
    Text.draw("Game time is paused while you are in town.", b.x + 12, b.y + b.h - 50, {
      size = "small",
      width = b.w - 24,
      align = "right",
      color = theme.colors.textDim,
    })
    Text.draw("Shop", b.x + b.w / 2 + 6, b.y + 38, { size = "small", color = theme.colors.textDim })
    if (self.shopMore or 0) > 0 then
      Text.draw(string.format("Drag or scroll: %d more", self.shopMore), b.x + b.w / 2 + 6, b.y + b.h - 14, {
        size = "small",
        color = theme.colors.textDim,
      })
    end
    for _, row in ipairs(self.shopRows or {}) do
      Panel.icon(Panel.catalogIcon(row.item), row.x, row.y + 4)
      Text.draw(row.item.name, row.x + 16, row.y + 5, { size = "small" })
    end
  end
  self.buttons:draw()
end

return Truck
