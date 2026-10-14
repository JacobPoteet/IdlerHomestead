-- luacheck config for game/, tests/ and tools/. Run from the repo root: luacheck game tests tools
-- Formatting belongs to StyLua (.stylua.toml), so line length is not checked here.

std = "luajit"

-- LÖVE injects `love` as a global; the game and tests reach everything else through require.
globals = { "love" }

max_line_length = false

-- Unused arguments are allowed: LÖVE callbacks (love.draw, love.keypressed, ...) receive
-- parameters that many handlers ignore.
ignore = { "212" }
