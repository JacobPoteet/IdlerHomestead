-- luacheck config for game/, tests/ and tools/. Run from the repo root: luacheck game tests tools
-- Formatting belongs to StyLua (.stylua.toml), so line length is not checked here.

std = "luajit"

-- LÖVE injects `love` as a global; the game and tests reach everything else through require.
-- The two game globals are deliberate: product_config (game/conf.lua, read from product.env) and
-- https (game/main.lua, the optional native HTTPS module).
globals = { "love", "product_config", "https" }

-- Third-party code kept as shipped (also listed in .styluaignore).
exclude_files = { "game/lib/**" }

max_line_length = false

-- Unused arguments are allowed: LÖVE callbacks (love.draw, love.keypressed, ...) receive
-- parameters that many handlers ignore.
ignore = { "212" }
