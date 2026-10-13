-- Audio (D100): the Settings screen with the Sound sliders, the sound test screen, and a game running
-- with the silent audio backend (every play is recorded in d.audioLog, so the scenario can assert on it).
return function(d)
  local ctx = d.game.app.ctx
  local audio = ctx.audio

  d:press("Settings")
  d:frames(3)
  d:key("pagedown")
  d:frames(3)
  d:shot("settings_sound")
  ctx.settings:set("volumeMaster", 0.4)
  d:frames(2)
  d:shot("settings_sound_40")
  d:key("pagedown")
  d:key("pagedown")
  d:frames(3)
  d:shot("settings_end")
  d:press("Listen to every sound")
  d:frames(3)
  d:shot("soundtest_top")
  d:key("pagedown")
  d:frames(3)
  d:shot("soundtest_scrolled")
  d:key("escape")
  d:key("escape")
  d:frames(2)

  d:newGame()
  d:frames(60)
  if d.audioLog then -- only the silent backend records plays
    local loops = 0
    for _, e in ipairs(d.audioLog) do
      if e.loop then
        loops = loops + 1
      end
    end
    assert(loops > 0, "no ambience bed started in a running game")
  end
  assert(audio.beds.amb_creek and audio.beds.amb_creek.playing, "the creek bed should be playing")
  d:shot("homestead")
end
