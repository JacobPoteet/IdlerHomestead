-- Homestead map.
-- The map must be wider than the widest view at the camera's zoom-out limit (zoom 1) so the edge is never
-- on screen (#260, D106): 4K at the default 2x UI shows 1920 x 1080 virtual px = 120 x 67.5 tiles, and 16:10
-- shows 120 x 75, so 128 x 80 covers every 16:9 and 16:10 display from 1080p to 4K.
return {
  mapWidth = 128, -- tiles; at least ceil(widest view width / tileSize) + a margin
  mapHeight = 80, -- tiles; at least ceil(tallest view height / tileSize) + a margin
}
