-- Field schemas for each content kind (see src/core/registry.lua for the spec format).
-- Unknown fields in content files are rejected, so add new fields here first.
return {
  resources = {
    name = "string", -- display name
    category = "string", -- currency | material | seed | food | ...
    capacity = "number?", -- default storage cap; absent means unlimited until storage buildings set one
    calories = "number?", -- food energy per unit; present means it can be eaten
  },
  terrain = {
    name = "string",
    walkable = "boolean", -- can actors stand on it
    tillable = "boolean?", -- can be tilled into a field
    water = "boolean?", -- buckets can be filled here
    walkCost = "number?", -- movement cost multiplier (default 1)
  },
  objects = {
    name = "string",
    blocks = "boolean", -- blocks movement
    walkCost = "number?", -- movement cost multiplier when not blocking (default 1)
    clearTime = "number?", -- seconds of work to clear (absent with clearable = false)
    clearable = "boolean?", -- default true
    yields = "table?", -- resource -> amount or { min, max } when cleared
    autoClear = "boolean?", -- idle homesteader clears it without an order
    footprintW = "number?", -- tiles wide (default 1); anchored at the top-left tile
    footprintH = "number?", -- tiles tall (default 1)
  },
  crops = {
    name = "string",
    seed = "string", -- resource consumed to plant
    produce = "string", -- resource gained on harvest
    growDays = "number", -- watered game days to mature
    yield = "number", -- base produce per harvest, scaled by soil
    seedReturn = "table", -- { min, max } seeds back per harvest
  },
  task_categories = {
    name = "string",
  },
}
