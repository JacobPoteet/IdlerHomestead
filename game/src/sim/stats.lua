-- Stat modifiers (GDD §8.2): equipment owned this run (catalog items with `equipment = true`)
-- and perks known in the Field Journal both contribute their `modifiers` tables.
-- Systems combine a tuning base with Stats.modifier(world, "statName").

local Stats = {}

--- Sum of a stat's modifiers across owned equipment (0 if none).
-- Reused sorted id list and per-registry perk list (#132): this runs several times a tick, so it must not
-- allocate. Summing in the same order (equipment ids sorted, then perks in registry order) keeps the
-- floating-point result identical to the original.
local scratchIds = {}
local perkCache = setmetatable({}, { __mode = "k" })

-- The perks that carry modifiers, in registry order (a registry's content never changes after loading).
local function modifierPerks(registry)
  local list = perkCache[registry]
  if not list then
    list = {}
    for _, perk in ipairs(registry:all("perks")) do
      if perk.modifiers then
        list[#list + 1] = perk
      end
    end
    perkCache[registry] = list
  end
  return list
end

function Stats.modifier(world, name)
  -- Required here, not at load, because Inventory (through Actors and Weather) requires Stats.
  local Inventory = require("src.sim.systems.inventory")
  local total = 0
  local n = Inventory.fillEquipmentIds(world, scratchIds)
  for k = 1, n do
    local mods = world.registry:get("catalog", scratchIds[k]).modifiers
    if mods and mods[name] then
      total = total + mods[name]
    end
  end
  local journal = world.meta.journal
  if journal then
    local known = journal.known
    for _, perk in ipairs(modifierPerks(world.registry)) do
      if known[perk.id] and perk.modifiers[name] then
        total = total + perk.modifiers[name]
      end
    end
  end
  return total
end

--- The size multiplier tiered upgrades give a building (D198, #382): 1 + the modifier its object definition names in
--- `tierStat` (the stove's heat, the cistern's store, ...), or 1 for an object with no tiers.
function Stats.scale(world, def)
  if def.tierStat then
    return 1 + Stats.modifier(world, def.tierStat)
  end
  return 1
end

--- Work-time multiplier for a speed stat: 1 / (1 + modifier). A +1 bonus halves the time.
function Stats.timeFactor(world, name)
  return 1 / (1 + Stats.modifier(world, name))
end

--- The statuses' combined effect on a stat (D166, #345): a multiplier (1 = no effect) for workSpeed, fallChance,
--- carryCapacity, conditionRecovery, studySpeed, warmthNeed and waterNeed, a flat sum for conditionDrain (0 = none).
--- The companion of `modifier` for things that slow or worsen, not equipment bonuses; the two compose by product
--- (the wardrobe's work bonus and this one multiply). See Status.modifier.
function Stats.factor(world, name)
  return require("src.sim.systems.status").modifier(world, name)
end

return Stats
