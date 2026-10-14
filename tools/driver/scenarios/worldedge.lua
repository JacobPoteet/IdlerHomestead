-- World width (#260, D106): at the zoom-out limit and the default 2x UI the edge of the map is never on
-- screen, on big windows too. Resizes to 1440p (16:9 and 16:10), pans the camera to every corner and checks
-- that the visible rectangle stays inside the map; shots of the right edge and the whole map in view.
-- Windows the display cannot hold (4K on a small monitor) are skipped, the maths for those is in
-- tests/test_camera.lua.
return function(d)
  d:newGame()
  d:advance(1)
  local world = d:world()
  local scene = d:scene()
  local grid = world.state.grid
  local tile = scene.camera.tileSize
  local original = { love.graphics.getDimensions() }
  local function check(label)
    local view, cam = d.game.app.view, scene.camera
    cam.zoomIndex = 1
    cam:clamp(view)
    for _, corner in ipairs({ { 1e6, 1e6 }, { -1e6, -1e6 }, { 1e6, -1e6 }, { -1e6, 1e6 } }) do
      cam:pan(corner[1], corner[2], view)
      local x1, y1 = cam:viewToWorld(0, 0, view)
      local x2, y2 = cam:viewToWorld(view.w, view.h, view)
      assert(x1 >= -1e-6 and y1 >= -1e-6, label .. ": top-left edge visible")
      assert(x2 <= grid.w * tile + 1e-6 and y2 <= grid.h * tile + 1e-6, label .. ": bottom-right edge visible")
      d:frames(2, 0.05)
    end
    d:shot(label .. "_corner")
  end
  for _, size in ipairs({ { 2560, 1440 }, { 2560, 1600 } }) do
    d:resize(size[1], size[2])
    local w, h = love.graphics.getDimensions()
    if w == size[1] and h == size[2] then
      check(size[1] .. "x" .. size[2])
    else
      print(("worldedge: skipped %dx%d (window is %dx%d)"):format(size[1], size[2], w, h))
    end
  end
  d:resize(original[1], original[2])
end
