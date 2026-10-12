-- Stat modifiers (GDD §8.2): equipment owned this run (catalog items with `equipment = true`)
-- and perks known in the Field Journal both contribute their `modifiers` tables.
-- Systems combine a tuning base with Stats.modifier(world, "statName").

local Stats = {}

--- Sum of a stat's modifiers across owned equipment (0 if none).
function Stats.modifier(world, name)
  -- Required here, not at load, because Inventory (through Actors and Weather) requires Stats.
  local Inventory = require("src.sim.systems.inventory")
  local total = 0
  for _, itemId in ipairs(Inventory.equipmentIds(world)) do
    local mods = world.registry:get("catalog", itemId).modifiers
    if mods and mods[name] then
      total = total + mods[name]
    end
  end
  local journal = world.meta.journal
  if journal then
    for _, perk in ipairs(world.registry:all("perks")) do
      if journal.known[perk.id] and perk.modifiers and perk.modifiers[name] then
        total = total + perk.modifiers[name]
      end
    end
  end
  return total
end

--- Work-time multiplier for a speed stat: 1 / (1 + modifier). A +1 bonus halves the time.
function Stats.timeFactor(world, name)
  return 1 / (1 + Stats.modifier(world, name))
end

return Stats
