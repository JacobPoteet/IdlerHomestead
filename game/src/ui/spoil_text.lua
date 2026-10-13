-- Plain-words descriptions of spoilage (D68, D73) for the pantry, the HUD and the notice card.
-- All numbers come from the Spoilage accessors; this file only turns them into sentences.

local Spoilage = require("src.sim.systems.spoilage")

local SpoilText = {}

local function days(n)
  return n == 1 and "1 day" or string.format("%d days", n)
end

--- "in 3 days", "tomorrow night" or "tonight" for a whole number of days left.
function SpoilText.when(daysLeft)
  if daysLeft <= 0 then
    return "tonight"
  elseif daysLeft == 1 then
    return "tomorrow night"
  end
  return "in " .. days(daysLeft)
end

--- One line for a pantry row: "Keeps 7 days. Oldest batch spoils in 3 days" or, when something is
--- past its shelf life, "4 past their shelf life: 2 rot tonight".
function SpoilText.ageLine(info)
  if info.rotting > 0 then
    return string.format("%d past their shelf life: %d rot tonight", info.rotting, info.tonight)
  elseif info.tonight > 0 then
    return string.format("Oldest batch spoils tonight: %d will rot", info.tonight)
  end
  local keeps = days(math.floor(info.shelfLife + 0.5))
  if info.daysLeft then
    return string.format("Keeps %s. Oldest batch spoils %s", keeps, SpoilText.when(info.daysLeft))
  end
  return "Keeps " .. keeps
end

--- "3 Radish, 1 Creek chub" for a list of { resource, amount }.
function SpoilText.items(world, lost)
  local parts = {}
  for _, entry in ipairs(lost) do
    parts[#parts + 1] = string.format("%d %s", entry.amount, world.registry:get("resources", entry.resource).name)
  end
  return table.concat(parts, ", ")
end

--- The morning/evening loss line shown instead of a silent loss.
function SpoilText.summary(world, report)
  return string.format("Spoiled overnight: %s. See the Pantry.", SpoilText.items(world, report.lost))
end

--- What slows spoilage, as the game really treats it (one paragraph).
function SpoilText.slowing(world)
  local slow = Spoilage.slowing(world)
  local parts = {}
  if slow.freezer == "on" then
    parts[#parts + 1] = string.format("The chest freezer is on: fresh food keeps %.1fx longer.", slow.keeps)
  elseif slow.freezer == "off" then
    parts[#parts + 1] = "The chest freezer has no power, so it is not slowing anything."
  else
    parts[#parts + 1] = "Only a powered chest freezer makes fresh food keep longer."
  end
  if slow.preserves.fish then
    parts[#parts + 1] = "Load fish into the smoker: smoked fish never spoils."
  else
    parts[#parts + 1] = "Smoked and canned food never spoils."
  end
  if slow.preserves.dairy then
    parts[#parts + 1] = "Press milk into cheese: cheese keeps."
  end
  parts[#parts + 1] = "Kept, spare or loaded on the truck makes no difference."
  return table.concat(parts, " ")
end

-- "fish and milk 2 days, radishes 7, ..." from the shelf-life tuning, shortest first.
local function shelfLives(world)
  local byLife, order = {}, {}
  for _, res in ipairs(world.registry:all("resources")) do
    local life = Spoilage.shelfLife(world, res.id)
    if life and res.calories then
      local label = res.category == "fish" and "fish" or res.name:lower()
      if not byLife[life] then
        byLife[life] = {}
        order[#order + 1] = life
      end
      local seen = false
      for _, l in ipairs(byLife[life]) do
        seen = seen or l == label
      end
      if not seen then
        table.insert(byLife[life], label)
      end
    end
  end
  table.sort(order)
  local parts = {}
  for _, life in ipairs(order) do
    parts[#parts + 1] = table.concat(byLife[life], " and ") .. " " .. days(life)
  end
  return table.concat(parts, ", ")
end

--- The first-spoil explanation (card body).
function SpoilText.explanation(world)
  return "Fresh food keeps for a while, then rots. Each harvest, catch or collection is a batch with its "
    .. "own age, and nothing in it spoils until it is older than the food's shelf life ("
    .. shelfLives(world)
    .. "). After that it rots over a night or two. The oldest food is eaten and sold first. The Pantry "
    .. "shows when each food's oldest batch spoils. "
    .. SpoilText.slowing(world)
end

return SpoilText
