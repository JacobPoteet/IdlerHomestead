-- Performance budget (#19, D103; numbers measured in docs/PERF.md). Targets for a mid-range phone
-- (about 3 to 4 times slower per thread than the desktop the baselines were taken on); the F3 overlay
-- flags a figure that goes over, and tests/test_perf_budget.lua enforces the allocation figures.
return {
  simMsPerTick = 0.5, -- ms of CPU per sim tick, averaged over a frame window, on a mid phone (desktop today: about 0.03)
  worstTickMs = 8, -- ms for the single worst tick on a mid phone (idle job searches, new-day work); desktop today: 1 to 7
  drawMs = 8, -- ms of CPU to submit one frame on a mid phone, which leaves room in a 16.6 ms frame for update and the GPU
  frameMs = 16.6, -- ms per frame to hold 60 fps (the target on a mid phone); 33.3 would be the floor (30 fps)
  testWindowDays = 5, -- in-game days the allocation test plays before it measures (a pass of the scripted policy)
  testAllocKbPerTick = 4, -- KB the sim may allocate per tick, averaged, in that test (measured about 0.6 after #132; 6.3 before)
  testAllocKbWorstTick = 512, -- KB the worst single tick of that test may allocate (new-day and idle-search work)
}
