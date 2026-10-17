-- The top bar's stat chips (D112, #267): what each chip is made of (icon, number, level mark, trend
-- arrow, fill bar), its width and how it is drawn. Presentation only: it reads the sim through the same
-- accessors as the modals (ChipStatus) and never changes it. The homestead scene lays the strip out.

local Animals = require("src.sim.systems.animals")
local Food = require("src.sim.systems.food")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Needs = require("src.sim.systems.needs")
local Power = require("src.sim.systems.power")
local Spoilage = require("src.sim.systems.spoilage")
local Water = require("src.sim.systems.water")
local Weather = require("src.sim.systems.weather")
local Assets = require("src.render.assets")
local ChipStatus = require("src.ui.chip_status")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local ChipStrip = {}

-- Big numbers are abbreviated so the strip stays short.
local function count(n)
  if n >= 10000 then
    return string.format("%dk", math.floor(n / 1000))
  end
  return tostring(n)
end

local function levelColor(level)
  if level >= 2 then
    return theme.colors.danger
  elseif level == 1 then
    return theme.colors.accent
  end
  return nil
end

--- One chip: { icon (sprite id), icons? (sprite ids, drawn side by side instead of `icon`), text, color?,
--- id, level, frac?, trend? }. The level mark (D112) is part of the text, so it is measured with it.
local function chip(world, id, icon, text)
  local s = ChipStatus.of(world, id)
  local marks = world.tuning.ui.topChips.marks
  if s.level > 0 and marks[s.level] ~= "" then
    text = (text ~= "" and (text .. " ") or "") .. marks[s.level]
  end
  return {
    icon = icon,
    text = text,
    color = levelColor(s.level),
    id = id,
    level = s.level,
    frac = s.frac,
    trend = s.trend,
  }
end

--- The strip's chips in order. Entries that only make sense with a building (cistern, coop, pen) appear
--- once it is placed.
function ChipStrip.entries(world)
  local ui = world.tuning.ui
  local truck = Land.truck(world)
  local woodOutlook = Needs.woodOutlook(world)
  local entries = {}
  local function add(e)
    entries[#entries + 1] = e
    return e
  end

  -- Weather: today and the days the forecast shows, as glyphs (a different shape per kind, no text).
  local w = add(chip(world, "weather", "icon_wx_clear", ""))
  w.icons = {}
  for n, day in ipairs(Weather.outlook(world)) do
    if n > ui.topChips.weatherDays then
      break
    end
    w.icons[#w.icons + 1] = "icon_wx_" .. day.kind
  end

  add(chip(world, "money", "icon_money", "$" .. count(Ledger.get(world, "money"))))
  add(chip(world, "food", "icon_food", string.format("%.1fd", Needs.foodDays(world))))
  -- Drinking water (D160): days of water on hand (cistern plus canteen) at the daily drink.
  add(chip(world, "drink", "icon_water", string.format("%.1fd", math.min(Needs.waterDays(world), 99))))
  add(chip(world, "condition", "icon_heart", tostring(math.floor(Needs.condition(world) + 0.5))))
  -- The truck chip says "ready" once a trip is possible (D72, #162), in the accent colour.
  local battery = string.format("%d%%", math.floor(Power.charge(world, truck) / Power.capacity(world, truck) * 100))
  local tripReady = Market.canTrip(world) and not world.state.market.inTown
  local b =
    add(chip(world, "battery", "icon_battery", tripReady and (battery .. " " .. ui.labels.tripReady) or battery))
  b.color = tripReady and theme.colors.accent or nil
  -- Spare goods (D75): units above their keep targets, what the stand and the truck can sell.
  add(chip(world, "surplus", "icon_crate", count(select(2, Food.surpluses(world)))))
  -- Wood (D104): the logs held, then the nights they last at tonight's need once a fire is needed.
  add(
    chip(
      world,
      "wood",
      "icon_wood",
      woodOutlook.nights == math.huge and count(woodOutlook.stock)
        or string.format(
          woodOutlook.nights >= 10 and "%s · %.0fn" or "%s · %.1fn",
          count(woodOutlook.stock),
          woodOutlook.nights
        )
    )
  )
  local tonight = Spoilage.tonight(world)
  if tonight.warn then
    -- Fresh food is about to rot (D68, D73): the number is how many units go tonight.
    add(chip(world, "spoiled", "icon_spoiled", "-" .. tonight.units))
  end
  if Water.hasCistern(world) then
    add(chip(world, "water", "icon_water", string.format("%d%%", math.floor(Water.fraction(world) * 100 + 0.5))))
  end
  if Animals.hasCoop(world) then
    local flock = Animals.info(world)
    add(chip(world, "hens", "icon_hen", string.format("%d/%d", flock.hens, flock.housing)))
    add(chip(world, "eggs", "icon_egg", tostring(flock.nest)))
  end
  if Animals.hasPen(world) then
    local herd = Animals.goatInfo(world)
    add(chip(world, "goats", "icon_goat", string.format("%d/%d", herd.goats, herd.housing)))
    add(chip(world, "milk", "icon_milk", tostring(herd.pail)))
  end
  return entries
end

--- Width of a chip's content (icon or icons, number, trend arrow), without the gap after it.
function ChipStrip.width(world, e)
  local ui = world.tuning.ui
  local w = 0
  if e.icons then
    for n, id in ipairs(e.icons) do
      w = w + Assets.sprite(id).w + (n > 1 and ui.topChips.iconGap or 0)
    end
  else
    w = Assets.sprite(e.icon).w
  end
  if e.text ~= "" then
    w = w + ui.statIconGap + Text.measure(e.text, "small")
  end
  if e.trend and e.trend ~= 0 then
    w = w + ui.topChips.markGap + ui.topChips.trendSize
  end
  return w
end

--- Width of a whole strip of entries with `gap` between chips.
function ChipStrip.stripWidth(world, entries, gap)
  local total = 0
  for _, e in ipairs(entries) do
    total = total + ChipStrip.width(world, e)
  end
  return total + gap * (#entries - 1)
end

local function trendTriangle(x, y, size, direction)
  if direction > 0 then
    love.graphics.polygon("fill", x, y + size, x + size, y + size, x + size / 2, y)
  else
    love.graphics.polygon("fill", x, y, x + size, y, x + size / 2, y + size)
  end
end

--- Draw a chip with its left edge at x and its icon top at y.
function ChipStrip.draw(world, e, x, y)
  local ui = world.tuning.ui
  local cfg = ui.topChips
  local width = ChipStrip.width(world, e)
  local iconH = Assets.sprite(e.icons and e.icons[1] or e.icon).h
  love.graphics.setColor(1, 1, 1, 1)
  local cx = x
  for n, id in ipairs(e.icons or { e.icon }) do
    local sprite = Assets.sprite(id)
    love.graphics.setColor(1, 1, 1, (e.icons and n > 1) and 0.8 or 1) -- today at full strength, the days after a little quieter
    love.graphics.draw(sprite.image, sprite.quad, cx, y)
    cx = cx + sprite.w + (e.icons and cfg.iconGap or 0)
  end
  if e.icons then
    cx = cx - cfg.iconGap -- no gap after the last day icon
  end
  if e.text ~= "" then
    cx = cx + ui.statIconGap
    Text.draw(e.text, cx, y + 1, { size = "small", color = e.color })
    cx = cx + Text.measure(e.text, "small")
  end
  if e.trend and e.trend ~= 0 then
    local c = e.color or theme.colors.text
    love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
    trendTriangle(cx + cfg.markGap, y + math.floor((iconH - cfg.trendSize) / 2), cfg.trendSize, e.trend)
  end
  if e.frac then
    local by = y + iconH + cfg.barGap
    love.graphics.setColor(cfg.barTrack)
    love.graphics.rectangle("fill", x, by, width, cfg.barHeight)
    local fill = e.level >= 2 and theme.colors.danger or e.level == 1 and theme.colors.accent or cfg.barOk
    love.graphics.setColor(fill[1], fill[2], fill[3], fill[4] or 1)
    love.graphics.rectangle(
      "fill",
      x,
      by,
      math.max(e.frac > 0 and 1 or 0, math.floor(width * e.frac + 0.5)),
      cfg.barHeight
    )
  end
end

return ChipStrip
