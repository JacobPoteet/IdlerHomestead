-- Loads global balance/config knobs from data/tuning/<domain>.lua (see GDD §12.3).
-- Domains are listed in data/tuning/init.lua. The result is strict: reading an unknown
-- key raises an error, so a misspelled knob crashes at load instead of silently being nil.

local strict = require("src.core.strict")

local M = {}

local PREFIX = "data.tuning."

--- Load every domain into a strict root table: tuning.time.tickRate, tuning.idle.takeoverDelay, ...
--- Pass `domains` to override the manifest (used by tests).
function M.load(domains)
  domains = domains or require(PREFIX .. "init")
  local root = {}
  for _, name in ipairs(domains) do
    local data = require(PREFIX .. name)
    assert(type(data) == "table", "Tuning domain '" .. name .. "' must return a table")
    root[name] = strict.wrap(data, "tuning." .. name)
  end
  return strict.wrap(root, "tuning")
end

--- Re-read all tuning files from disk into an existing root, keeping references valid.
function M.reload(root, domains)
  domains = domains or require(PREFIX .. "init")
  for _, name in ipairs(domains) do
    package.loaded[PREFIX .. name] = nil
    rawset(root, name, strict.wrap(require(PREFIX .. name), "tuning." .. name))
  end
  return root
end

return M
