-- Plain-words descriptions of spoilage (D68, #151) for the pantry, the HUD and the notice card.
-- All numbers come from the Spoilage accessors; this file only turns them into sentences.

local Spoilage = require("src.sim.systems.spoilage")

local SpoilText = {}

local BAND_WORDS = { fast = "Spoils fast", steady = "Spoils steadily", slow = "Keeps well" }

--- "may lose 1", "lose 3" or "lose 2-3" for tonight's range.
function SpoilText.loss(info)
  if info.lo == info.hi then
    return string.format("lose %d", info.lo)
  elseif info.lo == 0 then
    return string.format("may lose %d", info.hi)
  end
  return string.format("lose %d-%d", info.lo, info.hi)
end

--- One line for a pantry row: "Spoils fast: 50% a night. Tonight: lose 2".
function SpoilText.rateLine(info)
  return string.format("%s: %d%% a night. Tonight: %s", BAND_WORDS[info.band], info.percent, SpoilText.loss(info))
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
    parts[#parts + 1] = "Only a powered chest freezer slows spoilage."
  end
  if slow.preserves.fish then
    parts[#parts + 1] = "Load fish into the smoker: smoked fish never spoils."
  else
    parts[#parts + 1] = "Smoked and canned food never spoils."
  end
  parts[#parts + 1] = "Pantry or sell crate makes no difference."
  return table.concat(parts, " ")
end

--- The first-spoil explanation (card body).
function SpoilText.explanation(world)
  return "Fresh food rots a little every night, about a fixed share of what you hold. Fish go fastest, "
    .. "radishes next, potatoes and eggs slowly. Eat it, sell it (the stand or a truck trip) or preserve it "
    .. "before then. The Pantry shows each food's rate and what you are likely to lose tonight. "
    .. SpoilText.slowing(world)
end

return SpoilText
