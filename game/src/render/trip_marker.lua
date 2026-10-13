-- The truck's trip-ready marker (D101, #185): a small bobbing arrow over the truck sprite while a trip
-- can start and the homesteader is not in town. Pure rules, no drawing: the renderer feeds it the
-- sim's answers (Market.canTrip, market.inTown) and the real-time effect clock (a UI cue, D97).

local TripMarker = {}

--- Is the marker shown? A trip must be possible and the player still at home.
function TripMarker.visible(canTrip, inTown)
  return canTrip == true and not inTown
end

--- The marker's vertical offset in whole art pixels (0 at rest, down is positive). `cfg` =
--- tuning.visuals.tripMarker. Reduce motion (D96) holds it still at the top of the bob.
function TripMarker.offset(uiTime, cfg, reduceMotion)
  if reduceMotion then
    return 0
  end
  local phase = 0.5 + 0.5 * math.sin(uiTime / cfg.bobSeconds * 2 * math.pi)
  return math.floor(phase * cfg.bobPixels + 0.5)
end

return TripMarker
