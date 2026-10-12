local T = require("harness")
local Camera = require("src.core.camera")

local view = { w = 640, h = 360, scale = 2 }

local function newCamera()
  local c = Camera.new({ tileSize = 16, zoomLevels = { 1, 2, 3 }, zoomIndex = 2 })
  c:setBounds(64 * 16, 48 * 16)
  c:centerOn(512, 384, view)
  return c
end

T.test("camera: view <-> world round trip", function()
  local c = newCamera()
  local wx, wy = c:viewToWorld(100, 50, view)
  local vx, vy = c:worldToView(wx, wy, view)
  T.near(vx, 100)
  T.near(vy, 50)
end)

T.test("camera: zoom keeps the anchor point fixed", function()
  local c = newCamera()
  local before = { c:viewToWorld(200, 100, view) }
  c:zoomBy(1, 200, 100, view)
  T.eq(c:zoom(), 3)
  local after = { c:viewToWorld(200, 100, view) }
  T.near(after[1], before[1], 1e-6)
  T.near(after[2], before[2], 1e-6)
end)

T.test("camera: zoom is limited to the configured levels", function()
  local c = newCamera()
  c:zoomBy(10, 0, 0, view)
  T.eq(c:zoom(), 3)
  c:zoomBy(-10, 0, 0, view)
  T.eq(c:zoom(), 1)
end)

T.test("camera: panning clamps to map bounds", function()
  local c = newCamera()
  c:pan(100000, 100000, view)
  local wx, wy = c:viewToWorld(0, 0, view)
  T.near(wx, 0)
  T.near(wy, 0)
end)

T.test("camera: small maps are centred", function()
  local c = Camera.new({ tileSize = 16, zoomLevels = { 1 }, zoomIndex = 1 })
  c:setBounds(160, 160)
  c:pan(50, 50, view)
  T.eq(c.x, 80)
  T.eq(c.y, 80)
end)

T.test("camera: world <-> tile is 1-based", function()
  local c = newCamera()
  T.eq(select(1, c:worldToTile(0, 0)), 1)
  T.eq(select(1, c:worldToTile(15.9, 0)), 1)
  T.eq(select(1, c:worldToTile(16, 0)), 2)
  local wx, wy = c:tileToWorld(3, 2)
  T.eq(wx, 32)
  T.eq(wy, 16)
end)
