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

--- Work-time multiplier for a speed stat: 1 / (1 + modifier). A +1 bonus halves the time.
function Stats.timeFactor(world, name)
  return 1 / (1 + Stats.modifier(world, name))
end

return Stats
