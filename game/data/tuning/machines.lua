-- Machines (GDD §7.4, D65): stationary actors that claim tasks in an area and run on power.
-- Per-machine reach, speed and draw live with the object in data/content/objects.lua.
return {
  minPowerRatio = 0.25, -- 0..1; below this share of its draw a machine stops and reports "unpowered" (above it, it works that much slower)
  recheckInterval = 1, -- game seconds an idle machine waits before searching its area again (keeps idle machines cheap)
}
