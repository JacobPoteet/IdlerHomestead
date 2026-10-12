-- World camera.
return {
  zoomLevels = { 1, 2, 3 }, -- world zoom multipliers on top of the window scale; integers keep pixels crisp
  defaultZoomIndex = 2, -- index into zoomLevels used when a homestead is opened
  keyPanSpeed = 240, -- virtual pixels per second when panning with arrow keys / WASD
  pinchStepRatio = 1.3, -- finger-distance ratio a pinch must reach to step one zoom level
}
