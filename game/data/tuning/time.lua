-- Simulation clock.
return {
  tickRate = 20, -- simulation ticks per second of game time
  maxTicksPerFrame = 400, -- cap on catch-up ticks in one frame; backlog beyond this is dropped
  debugTimeScales = { 1, 2, 5, 10, 30 }, -- time-scale steps cycled by the debug speed key
}
