-- Active vs idle play (GDD §5.2). Expect heavy iteration here.
return {
  takeoverDelay = 30, -- seconds without input before the homesteader follows its routine
  minTakeoverDelay = 5, -- seconds; perks can shorten the takeover delay down to this
  activeWorkMultiplier = 1.25, -- work speed for jobs the player ordered directly
  idleWorkMultiplier = 0.8, -- work speed for jobs chosen by the idle routine
  recheckInterval = 1, -- seconds an idle homesteader waits before looking for work again
  -- Input in these scenes (names, see src/scenes) does not reset the takeover timer: reading a panel is not directing the homesteader (D55)
  browsePanels = { "catalog", "journal", "pantry", "power", "guide", "truck", "routine" }, -- scene names; panel input is ignored by the takeover timer
  hintAfter = 45, -- game seconds (about 1/7 of a day; deliberately real-time feel, D56) idle with the routine off before the "press R" hint
  hintInterval = 120, -- game seconds between idle hints, so it nags at most about twice a day
}
