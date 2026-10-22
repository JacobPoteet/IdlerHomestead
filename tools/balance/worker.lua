-- Balance harness worker thread (see parallel.lua). Own Lua state: loads the registry and tuning,
-- applies the same overrides, then plays "policy\tseed" units from the work channel until it
-- reads the empty stop marker. Each result list goes back as "ok\tpolicy\tseed\t<lua data>".

local configText, work, done = ...

package.path = "game/?.lua;game/?/init.lua;tools/balance/?.lua;" .. package.path

local Parallel = require("parallel")
local config = Parallel.decode(configText)

local name, seed = "?", "?"
local ok, err = xpcall(function()
  local Balance = require("balance")
  local Features = require("features")
  Balance.applyOverrides(config.sets)
  require("event_policy").configure(config.events or nil)
  local ctx = Balance.context()
  local features = Features.parse(config.features or nil)
  while true do
    local unit = work:demand()
    if unit == "" then
      return
    end
    name, seed = unit:match("^([^\t]+)\t(%d+)$")
    local results = Balance.playSeed(
      ctx,
      name,
      tonumber(seed),
      config.years,
      config.runs,
      features,
      config.outfit or nil,
      config.events or nil,
      config.pair or nil,
      config.loadout or nil
    )
    done:push("ok\t" .. name .. "\t" .. seed .. "\t" .. Parallel.encode(results))
  end
end, debug.traceback)
if not ok then
  done:push("error\t" .. tostring(name) .. "\t" .. tostring(seed) .. "\t" .. tostring(err))
end
