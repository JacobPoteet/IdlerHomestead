-- Shared helpers for modal panels (catalog, pantry, guide, truck...).

local Assets = require("src.render.assets")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Panel = {}

--- A centred box no bigger than the view (with a margin). A page hosted in a book (view.host, see
--- src/ui/books.lua) gets the book's page body instead: as wide as the body, no taller than it, `hosted` set.
function Panel.box(view, w, h)
  if view.host then
    local host = view.host
    return { x = host.x, y = host.y, w = host.w, h = math.min(h, host.h), hosted = true }
  end
  w = math.min(w, view.w - 16)
  h = math.min(h, view.h - 16)
  return { x = math.floor((view.w - w) / 2), y = math.floor((view.h - h) / 2), w = w, h = h }
end

function Panel.frame(view, box, title, subtitle)
  if not box.hosted then -- a page in a book sits on the book's paper, which draws the overlay and the plate
    Draw.overlay(view)
    Draw.panel(box.x, box.y, box.w, box.h)
  end
  Text.draw(title, box.x + 12, box.y + 9, { size = "body" })
  if subtitle then
    Text.draw(subtitle, box.x + 12, box.y + 24, { size = "small", color = theme.colors.textDim })
  end
end

--- "Close" button in the top-right corner.
function Panel.closeButton(buttons, box, onPress)
  if box.hosted then
    return nil -- a book has one Close tab for all its pages
  end
  return buttons:add({ x = box.x + box.w - 58, y = box.y + 6, w = 52, h = 22, label = "Close", onPress = onPress })
end

--- Draw a 12x12 icon by sprite id, falling back to a neutral icon.
--- scale: whole-number magnification (default 1). tint: { r, g, b } multiplied into the sprite.
function Panel.icon(id, x, y, alpha, scale, tint)
  if not Assets.has(id) then
    id = "icon_unknown"
  end
  tint = tint or { 1, 1, 1 }
  love.graphics.setColor(tint[1], tint[2], tint[3], alpha or 1)
  Assets.draw(id, math.floor(x), math.floor(y), scale or 1)
end

--- Icon id for a resource.
function Panel.resourceIcon(id)
  return "icon_" .. id
end

--- Icon id for a journal node: a perk's own icon, or the catalog item's.
function Panel.nodeIcon(registry, def)
  if registry:has("perks", def.id) then
    return def.icon
  end
  return Panel.catalogIcon(def)
end

--- Icon id for a catalog item: its own icon, its first resource, its object, or a tool.
function Panel.catalogIcon(item)
  if Assets.has("icon_" .. item.id) then
    return "icon_" .. item.id
  end
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
  if item.family and Assets.has("icon_" .. item.family) then
    return "icon_" .. item.family -- a tier of a ladder (D198) wears its family's icon
  end
  if item.modifiers and item.modifiers.rod then
    return "icon_rod"
  end
  return "icon_water"
end

return Panel
