-- Fishing (GDD §7.10). Per-species values live in data/content/fish.lua.
return {
  -- Idle routine
  idleAttemptTime = 25, -- seconds the routine spends on one cast
  idleCatchChance = 0.5, -- chance a routine cast lands a (common) fish
  baitIdleBonus = 0.25, -- added catch chance when the routine uses a bait
  -- Active fishing: approach, then the tension mini-game
  castTime = 0.6, -- seconds to set up at the bank before the mini-game opens
  biteDelayMin = 2, -- seconds before a bite (min)
  biteDelayMax = 6, -- seconds before a bite (max)
  baitBiteSpeed = 0.6, -- bite delay multiplier with bait (lower = faster)
  biteWindow = 0.9, -- seconds to press and set the hook once the bobber dips
  rarityBoostActive = 1.5, -- weight multiplier for non-common fish when actively fishing
  -- Tension fight (all rates per second; tension and line are 0..1)
  startLine = 0.15, -- how far the fish starts reeled in
  reelSpeed = 0.22, -- line gained per second while holding (before fish pull)
  pullSlowdown = 0.6, -- how much the fish's pull slows reeling (0 = none)
  tensionRise = 0.32, -- tension gained per second while holding
  pullTension = 0.55, -- extra tension per second per unit of fish pull while holding
  tensionFall = 0.65, -- tension lost per second while released
  runSpeed = 0.18, -- line lost per second per unit of fish pull while released
  surgeDuration = 0.8, -- seconds a surge lasts
  surgeBoost = 0.9, -- added pull during a surge (multiplier on strength)
  restingDrain = 0.35, -- stamina drain while released, relative to holding
  minPull = 0.35, -- fraction of strength a fully tired fish still pulls with
  slipTime = 0.5, -- seconds at max tension before the fish slips the hook
  escapeTime = 1.6, -- seconds at zero line (released) before the fish swims off
}
