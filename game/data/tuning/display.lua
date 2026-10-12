-- Rendering & virtual resolution.
return {
  tileSize = 16, -- pixels per grid tile edge in source art (GDD §9.2: 16x16 tentative)
  minVirtualWidth = 640, -- virtual pixels; the window is integer-scaled so at least this much is visible
  minVirtualHeight = 360, -- virtual pixels; extra space from other aspect ratios widens the view (no letterbox)
}
