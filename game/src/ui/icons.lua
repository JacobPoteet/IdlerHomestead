-- Interface icons (GDD §9.4, D142): which sprite stands for a tool, a seed packet or a verb, and drawing
-- one at a whole-pixel scale. Presentation only; it reads ownership through Inventory accessors.

local Assets = require("src.render.assets")
local Inventory = require("src.sim.systems.inventory")

local Icons = {}

-- A tool's icon by the equipment owned: the first entry whose equipment is owned wins, the last is the default.
local TOOL_TIERS = {
  hand = { { nil, "icon_tool_hand" } },
  hoe = { { nil, "icon_tool_hoe" } },
  pail = { { "big_bucket", "icon_tool_pail_big" }, { nil, "icon_tool_pail" } },
  axe = { { "axe", "icon_tool_axe" }, { nil, "icon_tool_hatchet" } },
  rod = { { "sturdy_rod", "icon_tool_rod_sturdy" }, { nil, "icon_tool_rod" } },
  hammer = { { nil, "icon_tool_hammer" } },
}

--- The sprite id for tool `id` given what `world` owns (world may be nil: the plain tier).
function Icons.tool(world, id)
  for _, tier in ipairs(TOOL_TIERS[id]) do
    if tier[1] == nil or (world and Inventory.hasEquipment(world, tier[1])) then
      return tier[2]
    end
  end
end

--- The seed-packet sprite for a crop: its own packet when the manifest has one, else the blank packet.
function Icons.packet(cropId)
  local id = "icon_packet_" .. cropId
  return Assets.has(id) and id or "icon_packet"
end

--- Draw sprite `id` at x, y (snapped to whole pixels) at a whole-number `scale`.
function Icons.draw(id, x, y, scale, alpha)
  local sp = Assets.sprite(id)
  scale = scale or 1
  love.graphics.setColor(1, 1, 1, alpha or 1)
  love.graphics.draw(sp.image, sp.quad, math.floor(x + 0.5), math.floor(y + 0.5), 0, scale, scale)
  return sp.w * scale, sp.h * scale
end

return Icons
