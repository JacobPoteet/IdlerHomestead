-- Active vs idle play (GDD §5.2). Expect heavy iteration here.
return {
  takeoverDelay = 30, -- seconds without input before the homesteader follows its routine
  minTakeoverDelay = 5, -- seconds; perks can shorten the takeover delay down to this
  activeWorkMultiplier = 1.25, -- work speed for jobs the player ordered directly
  idleWorkMultiplier = 0.8, -- work speed for jobs chosen by the idle routine
  recheckInterval = 1, -- seconds an idle homesteader waits before looking for work again
}
