-- Test runner. From the repo root:  lovec tests   (or: love tests)
-- Runs every tests/test_*.lua file and exits with status 1 if anything failed.
-- Optional filter: lovec tests rng   -> only files whose name contains "rng".

-- Resolve game modules (src.*, data.*) from the game/ folder relative to the repo root.
package.path = "game/?.lua;game/?/init.lua;" .. package.path

local T = require("harness")

function love.load(args)
  local filter = args and args[1]
  local files = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    if name:match("^test_.*%.lua$") and (not filter or name:find(filter, 1, true)) then
      files[#files + 1] = name
    end
  end
  table.sort(files)
  for _, file in ipairs(files) do
    T.beginFile(file)
    local chunk = assert(love.filesystem.load(file))
    local ok, err = pcall(chunk)
    if not ok then
      T.fileError(file, err)
    end
  end
  local failed = T.summary()
  love.event.quit(failed > 0 and 1 or 0)
end
