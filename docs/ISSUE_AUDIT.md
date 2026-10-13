# Issue audit (open issues vs design goals)

Snapshot: 2026-10-13, 136 open issues, HEAD `eadea48` (D98). Read-only audit; nothing was changed on GitHub. Checked against GDD pillars (§3), §5.2 automation boundary, §13/D95 (MVP first, balance after) and the decision log D1-D98, with code greps where noted. Anything marked *unverified* was not confirmed in code.

## 1. Summary

| Verdict | Count | Meaning |
|---|---|---|
| FITS | 87 | Supports pillars, correctly scoped (milestone notes in section 4) |
| DESIGN-CALL | 24 | Needs a user decision before work |
| STALE/DONE | 7 | Already delivered or made obsolete |
| DUPLICATE/MERGE | 9 | Fold into another issue |
| RESCOPE | 7 | Right idea, wrong shape |
| CONFLICT | 2 | Contradicts a decided D-number or pillar |
| **Total** | **136** | |

FITS issues (87) are every open issue not listed in sections 2.1-2.5. Most are Post-MVP art, balance-harness, tooling and follow-up items that are correctly scoped.

## 2. Non-FITS issues

### 2.1 CONFLICT

| # | Title | Conflicts with | Evidence / note |
|---|---|---|---|
| 200 | Idle truck trips: routine loads and drives | GDD §5.2 table (truck trips "Never automated"), pillar 5 ("only the player makes decisions"), FTUE promise "will not sell, buy, drive" | Issue itself says D75 left it off. Needs an explicit GDD amendment or should be closed. GAMEPLAY_LOOP.md Q6 is the same question. Related #138. |
| 7 | Truck trips are instant; homesteader never leaves | D78 (town trips take no game time, "advance the clock on return" knob deliberately not built) | D78 is recent and deliberate. Reopening needs a new decision that supersedes D78 (timed trips are listed Post-MVP in D95, so only the conflict, not the milestone, is wrong). |

### 2.2 DESIGN-CALL (one-line question each)

| # | Title | Question |
|---|---|---|
| 235 | MVP progression goal | What is "winning/progressing" for MVP (survive N years, tier, all chapters, score)? Blocks scope of #173/#216/#156. MVP-critical. |
| 126 | Progression gates reward neglect | Keep "Full battery"/"Cold night" gating power items and heater, or change the notes? Harness found power items unreachable for careful play. Same family as #164 and GAMEPLAY_LOOP Q8. MVP-critical (decides whether the power ladder is reachable). |
| 138 | Idle policy dies in first winter | Should an unattended homestead be able to survive a year (pillar 5 "idle anytime")? Tied to #200. |
| 95 | Drinking-water need not built | GDD §4.2 lists Water as a daily need; build it (MVP) or amend the GDD to defer? Currently Post-MVP while the GDD promises it. |
| 91 | Pipes/pumps do not freeze | Same: GDD §4.1 says they freeze. Build or amend. Links #211. |
| 22 | Should idle routine spend bait? | Never / pin / active only. |
| 64 | Catalog scene duplicates journal shop view | One data model two views (§8.3): fold Catalog into journal cards or keep both? `src/scenes/catalog.lua` still exists (verified). |
| 71 | Speed policy: auto-slowdown, orders while paused | Four sub-questions; D42/D78 only partly answer. |
| 84 | Power: open design questions | Generator charge mode, truck-lends default, pumps/machines tiers. |
| 92 | Water network is one global stock | Pipes/links or accept the abstraction (D50)? |
| 93 | Bucket can drain cistern drip lines need | Reserve, creek-first, or toggle? |
| 96 | Water table depth has no effect | Scale pump rate / dry wells, or leave as a gate? |
| 99 | Weather changes only at midnight | Keep exact day forecast (D51) or add intra-day fronts? |
| 100 | Turbine ignores weather / exceeds peak | Bias wind by sky and add storm cut-out? |
| 102 | Forecast UI | Should forecast get less certain further out? |
| 103 | Winter precipitation / snow kind | Needs GDD §7.1/4.1 pass; snow as weather kind? |
| 118 | Cat upkeep beyond one fish a day | Cat food, hunger, kittens? |
| 121 | Season 27 min vs 15 min target (D56 vs D12) | Shorten seasons/crops, or amend the target? Affects "fun" pacing. |
| 134 | Finds discard into full store | Grey out finds that do not fit, or wait? (D59 says hold, don't destroy.) |
| 136 | Storage capacities for fish/crops/seeds/wood unset | Pick capacities with storage buildings; hold paths untested in real play. |
| 150 | Default routine thresholds | Ship any default conditions for new runs? |
| 180 | Trailer: real trip, kids, breeding, selling | Scope for goats/cattle step; touches #7 and D78. |
| 211 | Shelter protects pipes from freezing | Radius, tiers, cost (depends on #91). |
| 233 | Plan also waters? | D92 limited Plan to till/plant; extend? |

### 2.3 STALE/DONE (close or trim)

| # | Title | Evidence |
|---|---|---|
| 15 | Move or pick up placed objects | Built, D98 (`Placement.pickUp`, `requestMove`, `tests/test_pickup.lua`). Follow-up is #242. |
| 227 | Cancel after crops removed loses crops | D98 part (6) "#227 fixed". |
| 236 | Shader/ambient ignore game speed and pause | D97 effect clock, `src/render/effect_clock.lua`. Residual is #241. |
| 50 | Settings menu | D96 built; leftovers already split to #237-#240. Close #50. |
| 14 | Should reading a panel count as active? | Decided: no, D55 (§14 item 14 struck through). |
| 169 | Surplus perishables spoil in the crate | The crate no longer exists (D75 keep targets + truck load; D73 per-batch spoilage). Premise obsolete. |
| 122 | Rescale old-save timers on day-length change | Saves need not load older shapes (CLAUDE.md, D74 `SAVE_COMPAT`). Obsolete. |

### 2.4 DUPLICATE/MERGE

| # | Title | Merge into | Note |
|---|---|---|---|
| 104 | Weather audio loops | #48 | Sub-task of audio; both MVP. Keep as a checklist item. |
| 219 | Shader polish batch 2 | #218 | One shader follow-up issue. |
| 220 | Shader polish batch 3 | #218 | Same; #218 is MVP but only its phone-GPU profile item is MVP-relevant. |
| 216 | Rescue: mention what failed (shelter) | #173 | Both are recovery-scene explanations; also fold #156 (threat history in run summary) into the same work. |
| 234 | Journal overview onto ScrollList | #62 | Journal scrolling work. |
| 209 | Journal full-map toggle / D81 rework | #208 | Same area (D81 shortcuts). |
| 147 | More machine kinds | #45 | Mini-tractor is the first extra kind. |
| 164 | Spoilage gates and text | #126 | Point 1 (gates need loss) is the same neglect-gate problem. Point 2 (Stand cooler text says "+4 a day" but the item only adds `standCap = 4`, verified in `catalog.lua:415`) is still a valid small fix. |
| 132 | Sim allocation churn | #19 | Performance work; keep one perf issue. |

### 2.5 RESCOPE

| # | Title | How |
|---|---|---|
| 6 | Physical hauling | Body is written around the sell crate (D31, superseded by D75: "Nothing is moved"). Rewrite for drop-off tile -> storage and the keep/spare model. Post-MVP is right. |
| 21 | Save format: size and migration coverage | Migrations are dropped (D74, CLAUDE.md): delete that half. Keep grid-size/compact-encoding part only; MVP is fine. |
| 46 | Content expansion | Epic. Split a minimum-viable content slice (only 2 crops: radish, potato; 7 fish; see section 3) from the Post-MVP tail (neighbor radio, more events). |
| 77 | Idle job search per-tile canDo and Dijkstra | D58 (#123) already did part of #77 (anchor index). Re-measure, then fold into #19. |
| 79 | CI/CD pipeline | `.github/workflows/ci.yml` (tests) and `build.yml` (tagged Android/desktop builds) exist. Trim to remaining items: stylua check, harness smoke, release artifacts (*unverified* which of these are already in build.yml). |
| 106 | Roadside stand: player control, spread customers, tuning | The "not at the stand" pin exists (D62, kept by D75). Keep only customers-through-the-day and tuning review (the latter is balance, post-MVP). |
| 198 | Shelter ladder | First slice shipped (D82; follow-ups #210-#217 exist). Retitle to "Cabin and heated workshop" so the epic is not confused with the built part. |

## 3. Milestone fit (D95: MVP = fun, minimal, complete; balance deferred)

| Issue | Now | Suggested | Why |
|---|---|---|---|
| 210 | Post-MVP | **MVP** | D95 lists #210 in the MVP core-UX set, but the GitHub milestone says Post-MVP. |
| 241, 242 | none | Post-MVP (241 could ride with polish) | No milestone assigned. |
| 87 | Post-MVP | MVP (do with #48) | Audio `newSource` will not be found by the driver shim; it breaks UI verification the moment audio lands. |
| 175 | Post-MVP | MVP candidate | Winter readiness ignores electric heat and unsplit wood: misleading on the game's key gate (pillar 2). |
| 185 | Post-MVP | MVP candidate (cheap) | GDD §5.2 "pending decisions show as gentle notifications"; GAMEPLAY_LOOP gap 6. |
| 95, 91 | Post-MVP | Decide (see 2.2) | GDD promises both; either MVP or amend the GDD. |
| 126 / 164 | Post-MVP | **MVP decision** | Gates unreachable for careful players decide whether the preserve/power ladders are playable at all. |
| 46 | Post-MVP | Split | A minimum content slice is part of "complete". |
| 13 | Post-MVP | MVP-borderline | Fishing is the headline activity but every water tile is the same spot; §7.10 wants spot variety. |
| 16 | Post-MVP | Consider MVP | Readability companion to #20; default font is the current UI. |
| 237 | MVP | Post-MVP | Not in D95's list; keybinding screen is not needed for a minimal complete game. |
| 224 | MVP | Post-MVP | Issue calls itself low priority (needs a SAVE_COMPAT bump). |
| 221 | MVP | fine, cosmetic | Low value, quick. |
| 218 | MVP | Trim | Only the phone GPU profile item belongs with #19/#51; the rest is polish. |
| 65 | Post-MVP | Risk note | "Winter is the gate" (pillar 2) is not enforced for engaged play; D95 defers balance, but the MVP's central promise is untested until then. |
| 121 | Post-MVP | Risk note | Pacing (27 min/season) affects the MVP feel as much as any feature. |
| 239 | MVP | fine | Blocked by #48. |

## 4. MISSING: promised by GDD, built nowhere, no open issue

| Item | Source | Evidence | MVP-critical? |
|---|---|---|---|
| Crop variety and growing rungs (raised beds, greenhouse; only radish and potato exist) | §5.3, §8.2 | `crops.lua` has 2 crops; #46 only mentions "more crops" inside an epic | Yes, a minimum slice |
| Discoveries (new crops/fish/animals/events in future runs) | §8.2 "not in yet" | grep finds no code | No (post) |
| In-store-only weekly specials | §6.3 | Discount specials exist (`market.lua`, `economy.specialsPerWeek`); no `inStore` field found (*unverified* beyond grep) | No |
| Root cellar, solar dehydrator, canning | §5.3 | Catalog has smoker and chest freezer only; #212 covers only a shack cellar slot | No; preserving works with smoker |
| Fish trap/trotline, pond stocking | §5.3 | none in catalog or issues | No |
| Log splitter, heat pump | §5.3 | none | No |
| Truck upgrades: bigger battery, bed-mounted solar | §7.6 | only bed rack (#199) | No |
| Wild foraging/trapping, rabbits/deer pests | §7.7 | none | No |
| Distant neighbor on the radio | §7.8 | no radio code (grep); only mentioned in #46 | No |
| Pending-decision notifications beyond study/finds (ripe crops, winter prep) | §5.2 | GAMEPLAY_LOOP gap 6; D72 added "truck ready" toast | Partly (small) |
| Fishing / clearing guided tutorial | §11 | GAMEPLAY_LOOP gap 2; FTUE (D69) coverage *unverified* | Low |
| Tile-size decision before art pass | §14 #5 | #47 mentions it; no decision | Yes before any art replacement |
| Study during the day (open question 3) | §14 #3 | no issue | No |
| Desktop widget content (winter readiness in widget) | §9.3 | #32/#33 | No (Post-MVP per D95) |
| Release/store packaging (Steam/itch, signed Windows build) | not in GDD | #79 only | Post-MVP |

## 5. Recommended MVP shortlist order

1. #235 progression goal (decides what the run summary, recovery and onboarding must show).
2. #126 + #164: neglect-gated unlocks decision (and the cooler text fix).
3. #95 / #91: build or amend the GDD (water need, freezing pipes).
4. #200 + #138: idle boundary decision (close #200 as conflict unless GDD §5.2 is amended).
5. #48 audio (+#104, #239, #87 shim first).
6. #20 sprite readability (+#16 font call).
7. #173 + #216 + #156: later-run onboarding and recovery explanation (after #235).
8. #51 mobile/touch QA, then #19 (+#77, #132) and #218 phone profile, #89 phone HUD.
9. Small UX batch: #210, #175, #185, #232, #201, #208, #172, #229, #221.
10. #21 save size, #46 minimum content slice, #13 fishing spots, #224 last.

Housekeeping before that: close #15, #227, #236, #50, #14, #169, #122; merge the nine in 2.4; assign milestones to #241/#242.
