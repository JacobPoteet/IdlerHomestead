-- Shared helpers for modal panels (catalog, pantry, guide, truck...).

local Assets = require("src.render.assets")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Panel = {}

--- A centred box no bigger than the view (with a margin).
function Panel.box(view, w, h)
  w = math.min(w, view.w - 16)
  h = math.min(h, view.h - 16)
  return { x = math.floor((view.w - w) / 2), y = math.floor((view.h - h) / 2), w = w, h = h }
end

function Panel.frame(view, box, title, subtitle)
  Draw.overlay(view)
  Draw.panel(box.x, box.y, box.w, box.h)
  Text.draw(title, box.x + 12, box.y + 9, { size = "body" })
  if subtitle then
    Text.draw(subtitle, box.x + 12, box.y + 24, { size = "small", color = theme.colors.textDim })
  end
end

--- "Close" button in the top-right corner.
function Panel.closeButton(buttons, box, onPress)
  return buttons:add({ x = box.x + box.w - 58, y = box.y + 6, w = 52, h = 22, label = "Close", onPress = onPress })
end

--- Draw a 12x12 icon by sprite id, falling back to a neutral icon.
function Panel.icon(id, x, y, alpha)
  if not Assets.has(id) then
    id = "icon_unknown"
  end
  local s = Assets.sprite(id)
  love.graphics.setColor(1, 1, 1, alpha or 1)
  love.graphics.draw(s.image, s.quad, math.floor(x), math.floor(y))
end

--- Icon id for a resource.
function Panel.resourceIcon(id)
  return "icon_" .. id
end

--- Icon id for a catalog item: its first resource, its object, or a tool.
function Panel.catalogIcon(item)
  if item.gives then
    local first
    for res in pairs(item.gives) do
      if not first or res < first then
        first = res
      end
    end
    return "icon_" .. first
  end
  if item.object then
    return "icon_" .. item.object
  end
  if item.modifiers and item.modifiers.rod then
    return "icon_rod"
  end
  return "icon_water"
end

return Panel
