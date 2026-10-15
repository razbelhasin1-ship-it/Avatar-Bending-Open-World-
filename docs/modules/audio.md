# Audio module

Everything you hear is synthesized offline by `tools/audiogen` (Python, numpy/scipy, no
samples) and played by the `Audio` autoload (`src/autoload/audio_manager.gd`) with helpers in
`src/audio/`. Most gameplay code never needs to call it: Audio listens to `Events`.

| Piece | Files |
| --- | --- |
| Generator | `tools/audiogen/generate.py` (+ `dsp.py`, `instruments.py`, `compose.py`, `master.py`, `sfx_*.py`, `ambience.py`, `music_tracks.py`) |
| Assets | `assets/audio/sfx/*.wav` (one-shots, `*_loop`), `assets/audio/sfx/amb_*.ogg`, `assets/audio/music/*.ogg` |
| Runtime | `Audio` autoload, `SoundCatalog`, `BendingSounds`, `VoicePool`, `MusicDirector`, `AmbienceMixer`, `AudioEnvironments`, `AudioFader`, `AudioDebugOverlay` |
| QA | `tools/audiogen/report.md` (per-file analysis), `tools/audiogen/spectrogram.py`, `tests/unit/test_audio.gd`, `tests/playtest/scenarios/audio_showcase.gd` |

## What gameplay code calls

```gdscript
# Abilities: element + event -> the right sound (see BendingSounds for events)
Audio.play_bending(ElementDefs.Element.FIRE, &"cast_heavy", hand_pos)
Audio.play_bending(element, &"impact", hit_point)          # world impacts (targets are automatic, below)
var h := Audio.start_bending_loop(element, &"charge_loop", self)   # follows the node
Audio.set_loop_pitch(h, 1.0 + charge * 0.3)                # charge builds
Audio.stop_loop(h, 0.25)
Audio.play_sfx_attached(&"fire_whoosh", projectile)        # one-shot that follows a moving node

# Anything else
Audio.play_sfx(&"wing_flap_large", pos)                    # positional, size-class attenuation
Audio.play_ui(&"ui_click")                                 # UI bus
Audio.play_stinger(&"quest_complete")                      # 2D, ducks the music
Audio.play_music(&"music_menu")                            # base music layer
Audio.set_ambience(&"amb_city")                            # base ambience bed
Audio.set_ambience_layer(&"local", &"amb_temple")          # extra bed (cave, settlement, ...)
Audio.set_environment(&"cave")                             # SFX reverb: open forest cave city temple ice
```

### Automatic (driven by `Events`)

| Signal | What Audio does | Switch |
| --- | --- | --- |
| `footstep(actor, pos, yaw, size, weight, surface)` | `play_footstep` (player gets +25 priority; `size >= 0.6` adds `creature_step_heavy`, `weight >= 1.3` adds `step_heavy`). Empty surface -> `WorldData.get_surface(pos)` | `auto_footsteps` |
| `landed(actor, pos, impact, surface)` | `play_landing`: `land_soft` / `land_heavy` (>= 9 m/s) / `land_snow`, plus a surface step on harder landings | `auto_footsteps` |
| `hit_landed(hit, target, result)` | `play_hit`: element impact + flesh layer, `block_impact`, `parry`, `body_fall` 0.45 s after a kill; freeze/chill/ice abilities use `ice_impact` | `auto_hit_sounds` |
| `combat_state_changed(bool)` | combat music layer on/off (off waits `music.combat_exit_delay` = 4 s) | always |
| `region_entered(id)` | regional music + ambience bed (`SoundCatalog.REGION_MUSIC/REGION_AMBIENCE`) | `auto_region_audio` |
| `weather_changed(id)` | weather layer (`rain/storm/thunderstorm/heavy_rain` -> `amb_rain`, `blizzard/snowstorm` -> `amb_blizzard`, else off) | `auto_region_audio` |
| `time_of_day_changed(hour)` | night layer `amb_night` from 20:30 to 05:00 in `earth_kingdom`, `wilds`, `fire_nation` | `auto_region_audio` |
| `player_level_up`, `quest_completed`, `poi_discovered`, `item_collected` | stingers `level_up`, `quest_complete`, `discovery`, `pickup` | `auto_stingers` |
| `returning_to_menu` / `player_died` | clears ambience and combat state | always |

So: **abilities only play casts, loops and world impacts**; target hits are sounded by Audio
from `hit_landed` (do not play `*_impact` again for targets you hit through `Combat.deal`).
The UI module plays `ui_*` sounds; game-event stingers come from Audio.

## API reference (`Audio`)

Existing foundation API (unchanged signatures):

* `get_stream(name, dir := SFX_DIR) -> AudioStream` - random variant or null. `has_sound(name)`.
* `play_sfx(name, position, volume_db := 0, pitch_variance := 0.08, max_distance := 120) -> AudioStreamPlayer3D`
  - `max_distance <= 0` or the legacy default `120` means "use the size class" (below).
* `play_2d(name, volume_db := 0, bus := &"SFX", pitch_variance := 0) -> AudioStreamPlayer`, `play_ui(name, volume_db := 0)`.
* `play_music(track, fade := 2, volume_db := 0)`, `current_music()` (base track), `set_ambience(name, volume_db := 0, fade := 2)`.

Additions:

| Method | Notes |
| --- | --- |
| `play_sfx_attached(name, node, volume_db, pitch_variance)` | follows `node` while playing |
| `play_footstep(surface, pos, weight := 1, size := 0.28, priority_bonus := 0)` | weight scales level (0.3..1.5 linear) and lowers pitch; big feet add creature thump |
| `play_landing(surface, pos, impact_speed, priority_bonus := 0)` | |
| `play_bending(element, event, pos, volume_db := 0, pitch_variance := 0.06)` | one-shots only; `ElementDefs.Element` or `-1` for martial arts |
| `start_bending_loop(element, event, target, volume_db := 0, fade_in := 0.15) -> int` | 0 when the element has no loop for that event |
| `play_loop(name, target := null, volume_db := 0, fade_in := 0.15, position := INF) -> int` | positional when `target` or `position` given; loops start at a random offset |
| `stop_loop(id, fade_out := 0.3)`, `set_loop_volume(id, db)`, `set_loop_pitch(id, pitch)`, `is_loop_playing(id)` | a loop also stops when its target node is freed |
| `play_hit(hit, target, result)` | what `hit_landed` triggers |
| `play_stinger(name, volume_db := 0)` | 2D + music duck (-9 dB for the stinger length, max 4 s) |
| `active_music()`, `set_combat(bool)`, `is_in_combat()`, `set_music_override(track, fade, db)` | override wins over combat wins over base |
| `set_ambience_layer(layer, name, volume_db, fade)`, `ambience_layers() -> {layer: name}` | layers: `base`, `weather`, `night`, `local`, anything |
| `set_environment(name, fade := 1)`, `current_environment()`, `environment_params()` | glides the SFX-bus reverb |
| `voice_count(category := &"")`, `active_voices()`, `listener_position()` | introspection |
| `show_debug_overlay(on := true)` | live meters, spectrum, voices, music/ambience state |
| `stop_all()` | silence everything immediately |

Members: `voices: VoicePool`, `music: MusicDirector` (tunables `combat_exit_delay`,
`combat_fade_in/out`, `resume_window`, `combat_track`), `ambience: AmbienceMixer`, and the
`auto_*` switches above.

### Bending events (`BendingSounds.sound_for(element, event)`)

| event | Air | Earth | Fire | Water |
| --- | --- | --- | --- | --- |
| `cast_light` | air_blast | earth_launch | fire_whoosh | water_whip |
| `cast_heavy` | air_sweep | earth_raise | fire_blast | water_blast |
| `impact` | air_impact | earth_impact | fire_impact | water_splash |
| `charge_loop` | air_shield_loop | - | fire_charge_loop | water_shield_loop |
| `shield_up` / `shield_loop` | air_push / air_shield_loop | earth_wall_rise / - | fire_ignite / fire_loop | water_draw / water_shield_loop |
| `dash`, `jump` | air_dash, air_jump | rock_debris, earth_raise | fire_ignite, fire_ignite | water_splash, water_surge |
| `wall`, `wall_break` | air_push, air_impact | earth_wall_rise, earth_crumble | fire_ring, fire_extinguish | ice_form, ice_shatter |
| `stomp`, `special`, `special_loop` | air_push, air_sweep, air_tornado_loop | earth_stomp, earth_quake, - | fire_explosion, fire_ring, fire_loop | water_wave, water_wave, water_shield_loop |
| extra | `push` | `spikes`, `armor`, `debris`, `launch` | `ignite`, `extinguish`, `explosion` | `draw`, `freeze`, `ice_impact`, `shatter`, `surge`, `heal_loop`, `splash` |

Any element also accepts the martial-arts events `block`, `parry`, `hit`, `fall`, `impact_heavy`.

## Voices, priorities and distance

`SoundCatalog.CATEGORIES` (limit / base priority / bus):

| category | limit | priority | examples |
| --- | --- | --- | --- |
| ui | 6 | 90 | `ui_*` (UI bus) |
| stinger | 3 | 95 | quest_complete, level_up |
| step | 12 | 10 | step_*, land_*, creature_step_heavy |
| body | 10 | 35 | whooshes, jump, dodge |
| impact | 10 | 62 | punch/kick/hit/block/body_fall, parry (88) |
| bending | 14 | 55 | air_/earth_/fire_/water_/ice_/rock_ one-shots |
| creature | 6 | 50 | bison, dragon, dog, badgermole, wings |
| loop | 8 | 80 | `*_loop` handles |
| ambient | 6 | 20 | positional amb one-shots, gong, wind_chime (Ambience bus) |

Effective priority = base (+ per-name override, + caller bonus) - up to 25 by distance. When a
category is full, the weakest voice of that category (lowest priority, then oldest) is stolen
if it is not more important than the new sound; otherwise the new sound is dropped. When all
40 3D (12 2D) voices are busy, the weakest non-loop voice anywhere is stolen under the same rule.
Sounds beyond their max distance from the listener (AudioListener3D or current camera) are not
started at all. The same sound in the same 2 m cell within 25 ms is throttled (steps excepted).

Size classes (inverse-distance attenuation, air-absorption low-pass that deepens with distance):

| size | unit (m) | max (m) | low-pass | used for |
| --- | --- | --- | --- | --- |
| SMALL | 2 | 45 | 7 kHz | steps, whooshes, UI-ish |
| MEDIUM | 4.5 | 95 | 6 kHz | punches, most bending |
| LARGE | 9 | 190 | 4.5 kHz | heavy bending, creatures, walls |
| HUGE | 18 | 380 | 3.5 kHz | explosions, quakes, dragon roar, bison call, gong, tornado |

## Music

`MusicDirector` keeps up to three music voices on the Music bus. Layers: **override >
combat > base**. Switching crossfades (equal power). A track that fades out is *paused*, so
leaving combat resumes the regional theme where it was (within `resume_window` = 60 s; combat
itself restarts from its intro unless re-entered within 10 s). Fades and timers use wall-clock
time so hitstop (`Engine.time_scale`) or a frame-rate drop never stalls the music.

| track | key / mode | tempo | length | character |
| --- | --- | --- | --- | --- |
| music_menu | D gong (major pentatonic) | 76 | 120 s | main theme: dizi, erhu, guzheng, choir, taiko, tam-tam |
| music_select | A major / F# yu | 72 | 93 s | guzheng arpeggios -> xiao -> erhu, building |
| music_water_tribe | E yu, 3/4 | 66 | 109 s | harp flow, breathy xiao, glass bells, choir "oo", drone, wind |
| music_earth_kingdom | G gong | 84 | 114 s | stately guzheng/erhu, muyu, clapper, opera gongs, pipa tremolo |
| music_fire_nation | D minor + b2 colour | 96 | 110 s | taiko ensemble, low brass, spiccato ostinato, aggressive erhu |
| music_air_temple | G zhi | 70 | 110 s | dizi with echoes, xiao, chimes, singing bowl, harp, wind |
| music_combat | E minor | 144 | 93 s | driving taiko, 16th ostinato, brass stabs, rising tension to B major |
| music_tutorial | F gong | 100 | 96 s | light pipa/dizi, woodblocks, pizzicato bass |

## Reverb environments

`AudioEnvironments.PRESETS` on one `AudioEffectReverb` added at runtime to the SFX bus:
`open` (default, nearly dry), `forest`, `cave`, `city`, `temple`, `ice`. World/settlement code
calls `Audio.set_environment()` on entering caves, temples, ice caverns, cities.

## Asset formats and naming

* `assets/audio/sfx/<name>.wav` or `<name>_1..N.wav` (N = 3-5 for repeated sounds; max 6).
  16-bit PCM mono, 44.1 kHz for bright content, 22.05 kHz for low/mid content (earth, creatures,
  body hits). One-shots have a 1.5 ms fade-in and a 30 ms fade-out, trailing silence trimmed.
* `*_loop.wav`: seamless (the tail past the loop point is equal-power crossfaded into the head),
  never faded, with a RIFF `smpl` loop chunk; the import is also set to forward loop.
* `amb_*.ogg`: 40 s stereo OGG Vorbis (~q2.8) loops; `music/*.ogg`: stereo OGG Vorbis (~q3.2)
  loops, the reverb/ringing tail folded onto the head so the wrap is seamless. Import `loop=true`.
* Loudness (ITU-R BS.1770 K-weighted): ui -21, step -24, body -19, impact/bending/creature/stinger
  -17 LUFS (max 300 ms loudness), loops -22, ambience -26, music -19 LUFS integrated. True-peak
  ceiling -1 dBFS (-1.5 for OGG). Limiting is capped at 3 dB (5 dB for impacts/bending) so
  transients stay sharp; very peaky hits therefore sit a little under target (see report).
* Total size: about 34 MB (music 11.9, ambience 4.8, SFX WAV 17.5).

## Regenerating

```bash
pip install soundfile           # OGG encoder (falls back to ffmpeg, then 22 kHz WAV)
python3 tools/audiogen/generate.py --jobs 2            # all sounds, ~2-3 min on 2 cores
python3 tools/audiogen/generate.py --only 'fire_*,music_combat'
python3 tools/audiogen/generate.py --list
godot --headless --path . --import
python3 tools/audiogen/set_import_loops.py && godot --headless --path . --import
python3 tools/audiogen/spectrogram.py out.png 'assets/audio/sfx/earth_*_1.wav' --cols 4
```

Every sound is deterministic (seeded from its name). Sounds are declared with decorators in the
`sfx_*.py` / `ambience.py` / `music_tracks.py` files:

```python
@sfx("earth_stomp", "bending", variants=4, gain_db=1.0)
def earth_stomp(rng, v):            # mono float array at 44.1 kHz
	...

@sfx("fire_loop", "loop", loop=(5.0, 0.8))   # render >= 5.8 s, made seamless
@ambience("amb_rain")                         # stereo (2, n), 40 s loop + 3 s crossfade
@music("music_menu")                          # returns Score.render(rng)
```

### Synthesis notes

* **Air**: steep (cascaded) band-passed noise whose centre/level follow a swell, doppler pitch
  drop after the peak, resonant whistles; swirling bands for shields and the tornado.
* **Earth**: saturated sub sweeps (harmonics keep them audible on phones) + mid punch + noisy
  core, modal rock fractures, granular debris where every pebble rings at its own pitch,
  stick-slip grinding for rising pillars and walls, low rumble.
* **Fire**: turbulent roar beds whose brightness tracks intensity (flicker), sparse click crackle
  with resonant pops, ignition "whoomph" (fast low-pass sweep + pressure thump), steam sizzle.
* **Water**: bubble synthesis (exponentially chirped decaying sinusoids, Minnaert-style size to
  pitch), splashes = transient + spray + bubble cloud + droplet tail, rushing masses.
* **Ice**: inharmonic high partial clusters, crisp cracks, individually pitched shard pings,
  stick-slip creaks rising as ice forms.
* **Creatures**: source-filter voices (band-limited glottal saw, jitter, period doubling, vocal
  fry, aspiration) through moving formant banks; outdoor slap-back.
* **Instruments**: Karplus-Strong strings with exact fractional tuning (allpass in the loop,
  solved as one IIR), guzheng left-hand bends/vibrato, pipa tremolo by re-exciting the same
  string, additive dizi (membrane buzz) / xiao (breath) / erhu (formants, portamento) phrase
  renderer, membrane-mode taiko/tsuzumi/frame drums, modal woodblocks/clapper, blooming tam-tam
  and gliding opera gongs, beating-partial bells, detuned saw string pads, choir, low brass.
* **Composition** (`compose.py`): melodies in jianpu notation (`"5, 1 2 3_ 5_ | 6- 5 3 |"`),
  chord symbols on scale degrees, voiced pads, arpeggio/bass/drum patterns per section,
  humanised timing, per-instrument pan/reverb/echo sends, convolution reverb from synthetic
  impulse responses, tail folding for seamless loops.

## Verification

* `tools/test.sh test_audio`: catalog == ARCHITECTURE list, every name resolves and loads,
  variation counts, loop flags after import, categories/sizes, bending map, voice limits and
  priority stealing, distance culling, footstep/landing/hit events, loop handles, combat music
  layering + resume position, regional/weather/night ambience, reverb presets, stinger ducking,
  and an in-engine capture across a loop point (no click at the wrap).
* `tools/playtest.sh audio_showcase`: real rendering + mixing; checks voice limits are never
  exceeded, combat music holds through lulls and hands back to the regional theme, and that the
  master bus spectrum is non-silent. Screenshots show the debug overlay.
* `tools/audiogen/report.md`: duration, peak/true peak, RMS, loudness, spectral centroid and loop
  boundary metrics for every file.
