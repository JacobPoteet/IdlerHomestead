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

--- The confirmation card for a preview that needs clearing or removing: { title, lines = { { text, color } } }.
--- `colors` = { text, dim, warn } come from the caller's theme.
function PlaceText.confirm(world, objectId, preview, colors)
  local p = world.tuning.ui.placement
  local name = world.registry:get("objects", objectId).name:lower()
  local lines = {}
  if #preview.clear > 0 then
    lines[#lines + 1] = { text = string.format(p.clears, countNames(world, preview.clear)), color = colors.text }
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
    lines[#lines + 1] = { text = string.format(p.steps, name), color = colors.dim }
  end
  return { title = string.format(p.title, name), lines = lines }
end

--- The card for a queued order: { title, lines }.
function PlaceText.order(world, order, colors)
  local p = world.tuning.ui.placement
  local def = world.registry:get("objects", order.object)
  local lines = {}
  local check = Inventory.check(world, order.object, order.tile, true)
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
  return { title = string.format(p.orderTitle, def.name), lines = lines }
end

return PlaceText
