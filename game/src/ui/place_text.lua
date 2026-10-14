-- Text for the placement preview, confirmation and order card (D79, #197). Pure: it reads a
-- Placement.preview result or an order and the registry, and returns lines; the texts are in
-- tuning.ui.placement and there are no numbers of its own.

local Inventory = require("src.sim.systems.inventory")
local Placement = require("src.sim.systems.placement")

local PlaceText = {}

local function plural(n)
  return n == 1 and "" or "s"
end

-- "2 rock, 1 tree" from a list of objects ({ id = objectId }), in a stable order.
local function countNames(world, list)
  local counts, ids = {}, {}
  for _, entry in ipairs(list) do
    if not counts[entry.id] then
      counts[entry.id] = 0
      ids[#ids + 1] = entry.id
    end
    counts[entry.id] = counts[entry.id] + 1
  end
  table.sort(ids)
  local parts = {}
  for _, id in ipairs(ids) do
    parts[#parts + 1] = string.format("%d %s", counts[id], world.registry:get("objects", id).name:lower())
  end
  return table.concat(parts, ", ")
end

--- The reason text for a refused spot (an Inventory.check result with ok = false, or "none").
function PlaceText.reason(world, reason, rule)
  local r = world.tuning.ui.placement.reasons
  return r[rule or reason] or r[reason] or r.bounds
end

--- Why the object can't be picked up or moved (a Placement.pickUpCheck / moveCheck result with ok = false).
function PlaceText.pickUpRefusal(world, check)
  local r = world.tuning.ui.placement.pickReasons
  if check.reason == "storage" then
    local res = world.registry:get("resources", check.resource)
    if check.animal then
      return string.format(r.animals, res.name:lower() .. "s")
    end
    return string.format(r.storage, res.name:lower())
  end
  return r[check.reason] or r.fixed
end

--- The confirmation for picking up something that holds something (check.warn): { title, text }.
function PlaceText.pickUpConfirm(world, anchor, warn)
  local p = world.tuning.ui.placement
  local name = world.registry:get("objects", world.state.grid.objects[anchor].id).name:lower()
  local text
  if warn.kind == "charge" then
    text = string.format(p.pickConfirmCharge, warn.kwh)
  else
    text = string.format(p.pickConfirmOutput, warn.count, world.registry:get("resources", warn.resource).name:lower())
  end
  return { title = string.format(p.pickConfirmTitle, name), text = text }
end

--- The confirmation for destroying the object at `anchor` (lose = Placement.destroyCheck(...).lose): { title, text }.
function PlaceText.destroyConfirm(world, anchor, lose)
  local p = world.tuning.ui.placement
  local name = world.registry:get("objects", world.state.grid.objects[anchor].id).name:lower()
  local parts = { p.destroyNoRefund }
  if lose.batch then
    parts[#parts + 1] = string.format(p.destroyBatch, lose.batch.count, world.registry:get("resources", world.registry:get("recipes", lose.batch.recipe).output).name:lower())
  end
  if lose.charge then
    parts[#parts + 1] = string.format(p.destroyCharge, lose.charge)
  end
  if lose.goods then
    parts[#parts + 1] = string.format(p.destroyGoods, PlaceText.goodsList(world, lose.goods))
  end
  return { title = string.format(p.destroyTitle, name), text = table.concat(parts, " ") }
end

--- "12 stone, 3 hen" from a list of { resource, count } (the goods a destroyed store loses).
function PlaceText.goodsList(world, goods)
  local parts = {}
  for _, g in ipairs(goods) do
    parts[#parts + 1] = string.format("%d %s", math.floor(g.count + 0.5), world.registry:get("resources", g.resource).name:lower())
  end
  return table.concat(parts, ", ")
end

--- The confirmation for destroying the crop on tile i: { title, text }.
function PlaceText.destroyCropConfirm(world, i)
  local p = world.tuning.ui.placement
  local crop = world.state.crops[i]
  local name = world.registry:get("crops", crop.id).name:lower()
  local state = crop.growth >= 1 and p.destroyCropRipe or string.format(p.destroyCropGrowing, math.floor(crop.growth * 100))
  return { title = string.format(p.destroyTitle, name), text = string.format(p.destroyCrop, name, state) }
end

--- The confirmation for planting `cropId` over crops of other kinds (preview = Crops.replacePreview): { title, text }.
function PlaceText.replaceConfirm(world, preview, cropId)
  local p = world.tuning.ui.placement
  local newName = world.registry:get("crops", cropId).name:lower()
  local ids = {}
  for id in pairs(preview.byCrop) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  local parts = {}
  for n, id in ipairs(ids) do
    local count, name = preview.byCrop[id], world.registry:get("crops", id).name:lower()
    parts[#parts + 1] = n == 1 and string.format("%d tile%s of %s", count, plural(count), name) or string.format("%d of %s", count, name)
  end
  local text = string.format(p.replaceText, table.concat(parts, ", "), newName)
  if preview.ripe > 0 then
    text = text .. " " .. string.format(p.replaceRipe, preview.ripe)
  end
  return { title = string.format(p.replaceTitle, newName), text = text }
end

--- The confirmation card for a preview that needs clearing or removing: { title, lines = { { text, color } } }.
--- `colors` = { text, dim, warn } come from the caller's theme. `moving`: the object is being moved (D98).
function PlaceText.confirm(world, objectId, preview, colors, moving)
  local p = world.tuning.ui.placement
  local name = world.registry:get("objects", objectId).name:lower()
  local lines = {}
  if #preview.clear > 0 then
    lines[#lines + 1] = { text = string.format(p.clears, countNames(world, preview.clear)), color = colors.text }
  end
  local replaced = PlaceText.replacedName(world, objectId)
  if replaced and #preview.replaces > 0 then
    lines[#lines + 1] = { text = string.format(p.upgradeLine, replaced, name), color = colors.warn }
  end
  local removes = {}
  if #preview.crops > 0 then
    local ripe = 0
    for _, c in ipairs(preview.crops) do
      if c.mature then
        ripe = ripe + 1
      end
    end
    local part = string.format(p.cropsPart, #preview.crops, plural(#preview.crops))
    if ripe > 0 then
      part = part .. " (" .. string.format(p.ripePart, ripe) .. ")"
    end
    removes[#removes + 1] = part
  end
  if preview.plans > 0 then
    removes[#removes + 1] = string.format(p.plansPart, preview.plans, plural(preview.plans))
  end
  if #removes > 0 then
    lines[#lines + 1] = { text = string.format(p.removes, table.concat(removes, ", ")), color = colors.warn }
  end
  local full = Placement.shortage(world, preview)
  if full then
    lines[#lines + 1] = { text = string.format(p.full, world.registry:get("resources", full).name:lower()), color = colors.warn }
  end
  if #preview.clear > 0 then
    lines[#lines + 1] = { text = string.format(moving and p.moveSteps or p.steps, name), color = colors.dim }
  end
  local title = string.format(moving and p.moveTitle or p.title, name)
  if replaced and #preview.replaces > 0 then
    title = string.format(p.upgradeTitle, replaced, name)
  end
  return { title = title, lines = lines }
end

--- Name (lower case) of the building an upgrade object replaces (the camp for the shack, D115), or nil.
function PlaceText.replacedName(world, objectId)
  local replaces = world.registry:get("objects", objectId).replaces
  return replaces and world.registry:get("objects", replaces).name:lower() or nil
end

--- The ghost's label when the spot is over the building it replaces ("replaces camp"), or nil.
function PlaceText.replaceTag(world, objectId, preview)
  local name = PlaceText.replacedName(world, objectId)
  if name and preview.ok and #preview.replaces > 0 then
    return string.format(world.tuning.ui.placement.upgradeTag, name)
  end
  return nil
end

--- The card for a queued order: { title, lines }.
function PlaceText.order(world, order, colors)
  local p = world.tuning.ui.placement
  local def = world.registry:get("objects", order.object)
  local lines = {}
  local check = Inventory.check(world, order.object, order.tile, true, order.from)
  if #check.clear > 0 then
    lines[#lines + 1] = { text = string.format(p.orderClearing, countNames(world, check.clear)), color = colors.text }
  else
    lines[#lines + 1] = { text = p.orderNothing, color = colors.text }
  end
  local why = order.why
  if why then
    local text
    if why.kind == "full" then
      text = string.format(p.orderFull, world.registry:get("resources", why.resource).name:lower())
    elseif why.kind == "blocked" then
      text = p.orderBlocked
    else
      text = p.orderUnreachable
    end
    lines[#lines + 1] = { text = text, color = colors.warn }
  end
  return { title = string.format(order.from and p.moveOrderTitle or p.orderTitle, def.name), lines = lines }
end

return PlaceText
