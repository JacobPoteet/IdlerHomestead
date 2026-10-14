-- Startup order guard (#222): a window mode change recreates the GL context and leaves canvases blank,
-- so the sprite atlas (painted into a canvas by Assets.load) must be built AFTER Game:restoreWindow().
-- Built before it, a remembered window size different from conf.lua's blanked every sprite and icon
-- (the world drew as noise and the HUD icons were missing). Testing it for real needs a GL context and a
-- remembered window, so this checks the call order in the source.
local T = require("harness")

T.test("startup: Assets.load runs after the remembered window is restored", function()
  local f = assert(io.open("game/src/game.lua", "r"))
  local src = f:read("*a")
  f:close()
  local body = src:match("function Game%.new.-\nend\n") or src
  local restore = body:find("self:restoreWindow()", 1, true)
  local load = body:find("Assets.load()", 1, true)
  T.truthy(restore and load, "both calls found in Game.new")
  T.truthy(load > restore, "Assets.load() must come after self:restoreWindow()")
end)
