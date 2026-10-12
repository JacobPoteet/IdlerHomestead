-- Stat modifiers from equipment owned this run (GDD §8.2 starting gear, catalog tools).
-- A catalog item with `equipment = true` contributes its `modifiers` table while owned.
-- Systems combine a tuning base with Stats.modifier(world, "statName").

local Stats = {}

--- Sum of a stat's modifiers across owned equipment (0 if none).
function Stats.modifier(world, name)
  local total = 0
  for itemId in pairs(world.state.inventory.equipment) do
    local mods = world.registry:get("catalog", itemId).modifiers
    if mods and mods[name] then
      total = total + mods[name]
    end
  end
  return total
end

return Stats
