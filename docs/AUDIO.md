# Audio

GDD §9.2 and D100. Every sound is a **cue** in one registry, [game/data/content/sounds.lua](../game/data/content/sounds.lua). Until real sounds exist each cue is a **synthesized placeholder** ([game/src/audio/synth.lua](../game/src/audio/synth.lua)), generated at load. Replacing one is an asset drop, never a code change.

## Replace a sound (steps)

1. Pick the cue id from the table below (or the Sound test screen: Settings > "Listen to every sound", or F7 in the game).
2. Export the sound as **.ogg** (preferred; .wav, .mp3 and .flac also load) and name it after the cue.
3. Put it in `game/assets/audio/<bus>/`, where `<bus>` is the cue's bus: `sfx`, `ambience` or `music`. Example: `game/assets/audio/sfx/fish_caught.ogg`.
4. For variation, add numbered files instead: `clear_1.ogg`, `clear_2.ogg`, `clear_3.ogg` (up to `audio.maxVariants` = 8). One is picked at random per play. A plain `clear.ogg` counts as one more variant.
5. Run the game and open the Sound test: the cue's line now says `file` or `files x3` instead of `synth`. Press Play to hear it.
6. Tune loudness in the cue's `volume` (0..1) in `sounds.lua` if needed. Nothing else changes.

A file that is missing or cannot be decoded is skipped; the placeholder plays instead; a cue with nothing playable is silent. Nothing ever crashes on audio. Cue names can also list explicit paths in a `files = { ... }` field in `sounds.lua`.

To add a **new cue**: add one entry in `sounds.lua` (bus, volume, placeholder generator and args, where/desc), then either map a world event to it in the `events` table of the same file, or call `audio:play("id")` from presentation code.

## Formats and loudness

- Preferred: **Ogg Vorbis, 44.1 kHz, mono** for effects and ambience, stereo only for music. Short one-shots may be .wav.
- Trim silence at both ends; one-shots under about 3 s, except thunder.
- **Loudness**: master each file to about **-16 LUFS integrated for ambience beds and -14 LUFS for effects, peak no higher than -3 dBFS**. The game scales by the cue `volume`, the bus slider and the master slider, and never boosts above the file's level, so a hot file cannot be fixed in-game. Effects should sit under the ambience bed rather than on top of it.
- Files of 1 MB or more (`audio.streamBytes`) are streamed instead of loaded whole; use that for music and long beds.

## Loop rules

- Cues with `loop = true` (all `ambience` cues and future `music`) must be **seamless**: the last sample flows into the first. Loop beds of 6 to 10 s so repetition is not obvious; crossfade the seam in the editor or use the loop points of your tool.
- Loops are never retriggered: the service starts them once and rides their volume (fades of `audio.bedFadeSeconds`).
- One-shots must not loop (`loop = false`); a looping file named for a one-shot cue plays once.

## Behaviour

- **Buses**: `master` x (`music`, `ambience`, `sfx`), sliders in Settings (Master volume, Effects, Ambience, Music), curve `audio.volumeCurve`. "Mute when unfocused" (desktop) fades the game out when the window is in the background.
- **Pause**: while game time is paused (player pause, tip card, town) ambience and music **duck** to `audio.pausedDuck` and keep playing; one-shots tagged `world = true` (chores, deliveries, alerts...) stay silent while paused or while time races past (`audio.maxEventSpeed`: sleep). Interface sounds (tap, toast) always play.
- **Weather**: the rain and wind beds ease with the same easing as the visual look (they read the eased values in `src/render/weather_fx.lua`). Thunder rolls on storm days.
- **Variation** (pitch, which variant, thunder timing) comes from the audio's own seeded RNG (`audio.seed`), never the sim RNG, so the sim stays deterministic.
- **Not available**: mixing with other apps' audio (LÖVE only reads `t.audio.mixwithsystem` in `conf.lua` at start-up, so it cannot be a live option; it stays false there).

## Cues

Buses: sfx / ambience / music (no music tracks yet; the bus and slider exist). "Fires" says when it plays. This table mirrors `sounds.lua`; the Sound test screen lists the same with what each cue currently resolves to.

| Cue | Bus | Fires | Placeholder |
|---|---|---|---|
| `clear` | sfx | a clearing job finishes | soft chop thud |
| `till` | sfx | tile tilled or untilled | dull earthy dig |
| `plant` | sfx | seed planted | tiny soft pat |
| `harvest` | sfx | crop picked | short bright pluck |
| `water` | sfx | crop watered, bucket filled | airy splash |
| `chop_wood` | sfx | firewood split | woody knock |
| `place` | sfx | object placed, machine loaded | set-down thump |
| `stove_lit` | sfx | campfire or stove placed | two warm soft notes |
| `eat` | sfx | homesteader eats | small munch |
| `animal` | sfx | eggs, milk, hen collected | tiny peep |
| `ping` | sfx | smoker or press batch done | soft ding |
| `fish_bite` | sfx | fish bites | rising three-note chime |
| `fish_hooked` | sfx | fishing game starts | firm tug |
| `fish_caught` | sfx | fish landed | four-note arpeggio |
| `fish_lost` | sfx | fish gets away | falling sigh |
| `ui_tap` | sfx | any button press; slider preview | tiny soft tick |
| `toast` | sfx | toast appears | gentle two-tone blip |
| `alert` | sfx | low food, fuel, feed or health | two falling notes |
| `learn` | sfx | journal entry or perk learned | soft rising chime |
| `truck_trip` | sfx | truck leaves or returns | low engine rumble |
| `delivery` | sfx | delivered item arrives | heavy box thud |
| `coin` | sfx | stand sale | coin tink |
| `threat_warn` | sfx | threat forecast | low warning tolls |
| `threat_strike` | sfx | threat strikes | dull heavy hit |
| `brownout` | sfx | power brownout | power-down slide |
| `thunder` | sfx | storm days (rolls) and storm arrival | long low rumble |
| `night_fall` / `dawn` | sfx | it turns dark / light | slow falling / rising notes |
| `sleep` | sfx | homesteader lies down | soft settling sigh |
| `meow` | sfx | a cat settles in | small mew |
| `purr` | sfx | cat petted | tiny low purr |
| `amb_birds` | ambience | day, spring to autumn, no rain | scattered chirps |
| `amb_creek` | ambience | always (faint when frozen) | soft burbling |
| `amb_wind` | ambience | windy and storm days | breathy gusts |
| `amb_crickets` | ambience | night, spring to autumn, no rain | high chirring pulses |
| `amb_rain` | ambience | rain and storm | steady soft hiss |
| `amb_fire` | ambience | near a lit campfire or stove (distance from the view centre) | quiet crackle |
| `amb_hum` | ambience | while power is being generated (inverter) | low 60 Hz hum |

## Code map

| Piece | File |
|---|---|
| Registry (cues, event map) | `game/data/content/sounds.lua` |
| Global knobs | `game/data/tuning/audio.lua` |
| Placeholder generators | `game/src/audio/synth.lua` |
| Files and placeholders to sources | `game/src/audio/library.lua` |
| Volume maths | `game/src/audio/mixer.lua` |
| Event to cue, bed levels (pure) | `game/src/audio/cues.lua` |
| World read for beds | `game/src/audio/sampler.lua` |
| Service (play, beds, duck, focus) | `game/src/audio/service.lua` |
| LÖVE or silent backend | `game/src/audio/backend.lua` |
| Sound test screen | `game/src/scenes/sound_test.lua` |

Tests run on the silent backend (`tests/test_audio.lua`); the screenshot driver is silent unless run with `audio=1` (see tools/driver/README.md).
