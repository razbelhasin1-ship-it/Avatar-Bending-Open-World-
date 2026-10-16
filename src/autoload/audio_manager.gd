extends Node
## Audio playback (autoload "Audio").
##
## Sound files live in res://assets/audio/sfx/<name>.wav (or .ogg), with optional
## variants <name>_1 .. <name>_6 picked at random. Music lives in
## res://assets/audio/music/<track>.ogg|.wav. Missing sounds are skipped with a
## one-time warning so gameplay never depends on an audio file existing.
##
## Buses: Master > Music, SFX, Ambience, UI, Voice (created by Settings).
##
## On top of plain playback the manager provides (see docs/modules/audio.md):
## * voice management: per-category limits + priorities (SoundCatalog, VoicePool)
##   and distance attenuation tuned per size class (small / medium / large / huge),
## * helpers: play_footstep / play_landing / play_bending / play_hit / loops,
## * a music stack with combat layering (MusicDirector) and regional music,
## * layered ambience (AmbienceMixer) and reverb environments on the SFX bus.
## It listens to Events (footstep, landed, hit_landed, combat_state_changed,
## region_entered, weather_changed, time_of_day_changed, ...) so most game code
## never has to call it directly.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const EXTS := ["wav", "ogg", "mp3"]
const POOL_3D := 40
const POOL_2D := 12
## play_sfx's historical default max distance: treated as "use the size class".
const LEGACY_MAX_DISTANCE := 120.0
## Music is lowered by this much while a stinger plays.
const STINGER_DUCK_DB := 9.0

## Play footsteps/landings for every Events.footstep / Events.landed.
var auto_footsteps := true
## Play impact layers for every Events.hit_landed (abilities then only need
## sounds for world impacts, casts and loops).
var auto_hit_sounds := true
## Switch music/ambience on Events.region_entered / weather / time of day.
var auto_region_audio := true
## Play stingers for level up, quest complete, discovery, item pickup.
var auto_stingers := true

var _cache: Dictionary = {}          # dir+name -> Array[AudioStream]
var _missing: Dictionary = {}
var _last_played: Dictionary = {}    # name -> msec, for spam protection
var _music_track: StringName = &""
var _ambience_name: StringName = &""
var _environment: StringName = &"open"
var _env_from: Dictionary = {}
var _env_to: Dictionary = {}
var _env_t := 1.0
var _env_fade := 1.0
var _env_last_usec := 0
var _reverb: AudioEffectReverb
var _region: StringName = &""
var _hour := 12.0
var _next_loop_id := 1
var _debug_overlay: Node = null

var voices: VoicePool
var music: MusicDirector
var ambience: AmbienceMixer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.ensure_audio_buses()
	voices = VoicePool.new()
	voices.name = "Voices"
	add_child(voices)
	voices.setup(POOL_3D, POOL_2D)
	music = MusicDirector.new()
	music.name = "Music"
	add_child(music)
	music.setup(func(track: StringName) -> AudioStream: return _looping(get_stream(track, MUSIC_DIR)))
	ambience = AmbienceMixer.new()
	ambience.name = "Ambience"
	add_child(ambience)
	ambience.setup(func(n: StringName) -> AudioStream: return _looping(get_stream(n)))
	_reverb = AudioEnvironments.ensure_reverb(&"SFX")
	_env_to = AudioEnvironments.preset(&"open")
	_env_from = _env_to
	_connect_events()


func _connect_events() -> void:
	Events.footstep.connect(_on_footstep)
	Events.landed.connect(_on_landed)
	Events.hit_landed.connect(_on_hit_landed)
	Events.combat_state_changed.connect(func(on: bool) -> void: music.set_combat(on))
	Events.region_entered.connect(_on_region_entered)
	Events.weather_changed.connect(_on_weather_changed)
	Events.time_of_day_changed.connect(_on_time_of_day)
	Events.returning_to_menu.connect(_on_returning_to_menu)
	Events.player_died.connect(func() -> void: music.reset_combat())
	Events.player_level_up.connect(func(_l: int) -> void: _auto_stinger(&"level_up"))
	Events.quest_completed.connect(func(_q: StringName) -> void: _auto_stinger(&"quest_complete"))
	Events.poi_discovered.connect(func(_p: StringName) -> void: _auto_stinger(&"discovery"))
	Events.item_collected.connect(func(_i: StringName, _c: int) -> void: _auto_stinger(&"pickup", -4.0))


func _auto_stinger(sound_name: StringName, volume_db: float = 0.0) -> void:
	if auto_stingers:
		play_stinger(sound_name, volume_db)


func _exit_tree() -> void:
	# Stop every playback before the players are freed, then give the mixer
	# thread one buffer to drop them, so the AudioServer does not keep stream
	# playbacks alive past shutdown ("resources still in use" on quit).
	stop_all()
	if not Engine.is_editor_hint():
		OS.delay_msec(int(ceil(AudioServer.get_output_latency() * 1000.0)) + 100)


## Immediately silences every voice, loop, music track and ambience layer.
func stop_all() -> void:
	if voices:
		for v in voices.voices3d + voices.voices2d:
			voices.release(v)
	for n: Node in [music, ambience]:
		if n == null:
			continue
		for c in n.get_children():
			if c is AudioStreamPlayer:
				(c as AudioStreamPlayer).stop()


func _process(_delta: float) -> void:
	var r := AudioFader.real_delta(_env_last_usec)
	var delta: float = r[0]
	_env_last_usec = r[1]
	if _env_t < 1.0:
		_env_t = minf(1.0, _env_t + delta / maxf(_env_fade, 0.01))
		AudioEnvironments.apply(_reverb, AudioEnvironments.blend(_env_from, _env_to, smoothstep(0.0, 1.0, _env_t)))


# --- Streams -------------------------------------------------------------------------

## Returns a stream for `sound_name` (random variant) or null.
func get_stream(sound_name: StringName, dir: String = SFX_DIR) -> AudioStream:
	var key := dir + String(sound_name)
	if not _cache.has(key):
		var list: Array[AudioStream] = []
		var base := _find(dir + String(sound_name))
		if base:
			list.append(base)
		for i in range(1, 7):
			var v := _find("%s%s_%d" % [dir, sound_name, i])
			if v:
				list.append(v)
		_cache[key] = list
	var arr: Array = _cache[key]
	if arr.is_empty():
		if not _missing.has(key):
			_missing[key] = true
			if OS.is_debug_build():
				print_verbose("Audio: missing sound '%s'" % key)
		return null
	return arr[randi() % arr.size()]


## Every variant of a sound (empty when missing).
func get_variants(sound_name: StringName, dir: String = SFX_DIR) -> Array:
	get_stream(sound_name, dir)
	return (_cache.get(dir + String(sound_name), []) as Array).duplicate()


func has_sound(sound_name: StringName) -> bool:
	return get_stream(sound_name) != null


func _find(path_no_ext: String) -> AudioStream:
	for ext: String in EXTS:
		var p := "%s.%s" % [path_no_ext, ext]
		if ResourceLoader.exists(p):
			return load(p) as AudioStream
	return null


func _looping(stream: AudioStream) -> AudioStream:
	if stream:
		_set_loop(stream)
	return stream


# --- One-shots -------------------------------------------------------------------------

## Plays a positional sound. Returns the player (or null if missing, throttled,
## out of range or outvoted). `max_distance` <= 0 (or the legacy default 120)
## uses the sound's size class (SoundCatalog.SIZE_PARAMS).
func play_sfx(sound_name: StringName, position: Vector3, volume_db: float = 0.0, pitch_variance: float = 0.08, max_distance: float = 120.0) -> AudioStreamPlayer3D:
	return _play_3d(sound_name, position, null, volume_db, pitch_variance, max_distance, 0.0)


## Like play_sfx but the sound follows `node` while it plays (projectiles, creatures).
func play_sfx_attached(sound_name: StringName, node: Node3D, volume_db: float = 0.0, pitch_variance: float = 0.08) -> AudioStreamPlayer3D:
	if node == null or not is_instance_valid(node):
		return null
	return _play_3d(sound_name, node.global_position, node, volume_db, pitch_variance, 0.0, 0.0)


func _play_3d(sound_name: StringName, position: Vector3, follow: Node3D, volume_db: float, pitch_variance: float,
		max_distance: float, priority_bonus: float, pitch: float = 1.0) -> AudioStreamPlayer3D:
	var category := SoundCatalog.category_of(sound_name)
	if category != &"step" and _throttled(sound_name, position):
		return null
	var stream := get_stream(sound_name)
	if stream == null:
		return null
	var size := SoundCatalog.size_params(SoundCatalog.size_of(sound_name))
	var max_d: float = size["max"] if (max_distance <= 0.0 or is_equal_approx(max_distance, LEGACY_MAX_DISTANCE)) else max_distance
	var priority := float(SoundCatalog.priority_of(sound_name)) + priority_bonus
	var lp := listener_position()
	if lp.is_finite():
		var d := lp.distance_to(position)
		if d > max_d:
			return null
		priority -= 25.0 * clampf(d / max_d, 0.0, 1.0)
	var v := voices.acquire(true, sound_name, category, priority)
	if v == null:
		return null
	var p := v.p3
	p.bus = SoundCatalog.category_info(category)["bus"] if category != &"ui" else &"SFX"
	p.unit_size = size["unit"]
	p.max_distance = max_d
	p.attenuation_filter_cutoff_hz = size["cutoff"]
	p.attenuation_filter_db = size["filter_db"]
	p.global_position = position
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-pitch_variance, pitch_variance)))
	if follow:
		v.follow = weakref(follow)
	p.stream = stream
	p.play()
	return p


## Plays a non-positional sound (UI, player-centric stingers).
func play_2d(sound_name: StringName, volume_db: float = 0.0, bus: StringName = &"SFX", pitch_variance: float = 0.0) -> AudioStreamPlayer:
	if _throttled(sound_name):
		return null
	var stream := get_stream(sound_name)
	if stream == null:
		return null
	var category := SoundCatalog.category_of(sound_name)
	var v := voices.acquire(false, sound_name, category, float(SoundCatalog.priority_of(sound_name)))
	if v == null:
		return null
	var p := v.p2
	p.stream = stream
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	p.play()
	return p


func play_ui(sound_name: StringName, volume_db: float = 0.0) -> void:
	play_2d(sound_name, volume_db, &"UI")


## 2D stinger (level up, quest complete...) that briefly ducks the music.
func play_stinger(sound_name: StringName, volume_db: float = 0.0) -> AudioStreamPlayer:
	var p := play_2d(sound_name, volume_db, &"SFX")
	if p and p.stream:
		music.duck(STINGER_DUCK_DB, minf(p.stream.get_length(), 4.0))
	return p


# --- Footsteps, landings, hits, bending ---------------------------------------------------

## Footstep for a surface (WorldData.get_surface ids). `weight` 0..1+ scales
## loudness and lowers the pitch of heavy walkers; `size` (foot length in m)
## above ~0.6 adds the large creature thump layer.
func play_footstep(surface: StringName, position: Vector3, weight: float = 1.0, size: float = 0.28, priority_bonus: float = 0.0) -> AudioStreamPlayer3D:
	var w := clampf(weight, 0.0, 2.0)
	var vol := linear_to_db(clampf(0.3 + 0.7 * w, 0.15, 1.5))
	var pitch := 1.0 - 0.06 * clampf(w - 1.0, -1.0, 1.0) - 0.12 * clampf((size - 0.3) / 0.7, 0.0, 1.0)
	var main := _play_3d(SoundCatalog.step_for_surface(surface), position, null, vol, 0.07, 0.0, priority_bonus, pitch)
	if size >= 0.6:
		_play_3d(&"creature_step_heavy", position, null, vol + 1.0, 0.06, 0.0, priority_bonus, 1.0)
	elif w >= 1.3:
		_play_3d(&"step_heavy", position, null, vol - 3.0, 0.06, 0.0, priority_bonus, 1.0)
	return main


## Landing after a jump/fall. `impact` is the vertical speed at touchdown (m/s).
func play_landing(surface: StringName, position: Vector3, impact: float, priority_bonus: float = 0.0) -> AudioStreamPlayer3D:
	var strength := clampf(impact / 12.0, 0.0, 1.5)
	var vol := linear_to_db(clampf(0.35 + 0.65 * strength, 0.2, 1.4))
	if impact < 2.0:
		return play_footstep(surface, position, 0.8, 0.28, priority_bonus)
	var p: AudioStreamPlayer3D
	if surface == &"snow":
		p = _play_3d(&"land_snow", position, null, vol, 0.06, 0.0, priority_bonus)
	elif impact >= 9.0:
		p = _play_3d(&"land_heavy", position, null, vol, 0.06, 0.0, priority_bonus)
	else:
		p = _play_3d(&"land_soft", position, null, vol, 0.06, 0.0, priority_bonus)
	if surface != &"snow" and impact >= 5.0:
		_play_3d(SoundCatalog.step_for_surface(surface), position, null, vol - 4.0, 0.05, 0.0, priority_bonus)
	if surface == &"snow" and impact >= 9.0:
		_play_3d(&"land_heavy", position, null, vol - 5.0, 0.05, 0.0, priority_bonus)
	return p


## One-shot for an element event (see BendingSounds). Returns the player or null.
func play_bending(element: int, event: StringName, position: Vector3, volume_db: float = 0.0, pitch_variance: float = 0.06) -> AudioStreamPlayer3D:
	var sound := BendingSounds.sound_for(element, event)
	if sound == &"":
		return null
	if SoundCatalog.is_loop(sound):
		push_warning("Audio.play_bending: '%s' is a loop, use start_bending_loop()" % sound)
		return null
	return _play_3d(sound, position, null, volume_db, pitch_variance, 0.0, 0.0)


## Starts the looping sound for an element event (charge_loop, shield_loop...)
## following `target`. Returns a handle for stop_loop(), or 0.
func start_bending_loop(element: int, event: StringName, target: Node3D, volume_db: float = 0.0, fade_in: float = 0.15) -> int:
	var sound := BendingSounds.sound_for(element, event)
	if sound == &"":
		return 0
	return play_loop(sound, target, volume_db, fade_in)


## Plays the sounds that sell a landed hit (element impact, flesh, block, parry,
## body fall on kills). Called automatically from Events.hit_landed when
## auto_hit_sounds is on.
func play_hit(hit: HitInfo, target: Node, result: int) -> void:
	if hit == null:
		return
	var pos := hit.position
	if pos == Vector3.ZERO and target is Node3D:
		pos = (target as Node3D).global_position + Vector3.UP
	var icy := hit.reaction == HitInfo.Reaction.FREEZE or hit.status.has("chill") or String(hit.ability_id).contains("ice")
	var layers := BendingSounds.hit_layers(hit.element, hit.is_heavy, result, icy)
	var vol := 2.0 if hit.is_heavy else 0.0
	for i in layers.size():
		var sweet := 0.0 if i == 0 else (-7.0 if hit.element != BendingSounds.NONE else -4.0)
		_play_3d(layers[i], pos, null, vol + sweet, 0.07, 0.0, 10.0)
	if result == Combat.Result.KILLED and target is Node3D:
		# Weak reference: the target may be freed before the body hits the ground.
		var wr: WeakRef = weakref(target)
		get_tree().create_timer(0.45, true).timeout.connect(func() -> void:
			var t := wr.get_ref() as Node3D
			var p := t.global_position if t != null and t.is_inside_tree() else pos
			_play_3d(&"body_fall", p, null, 0.0, 0.06, 0.0, 5.0))


# --- Loops -------------------------------------------------------------------------------

## Starts a looping sound. `target` (Node3D) makes it positional and following;
## null with `position` = Vector3.INF plays it non-positional. Returns a handle.
func play_loop(sound_name: StringName, target: Node3D = null, volume_db: float = 0.0, fade_in: float = 0.15, position: Vector3 = Vector3.INF) -> int:
	var stream := _looping(get_stream(sound_name))
	if stream == null:
		return 0
	var positional := target != null or position.is_finite()
	var priority := float(SoundCatalog.priority_of(sound_name))
	var v := voices.acquire(positional, sound_name, &"loop", priority, true)
	if v == null:
		return 0
	var id := _next_loop_id
	_next_loop_id += 1
	v.loop_id = id
	v.base_db = volume_db
	v.gain = 0.0 if fade_in > 0.0 else 1.0
	v.target = 1.0
	v.rate = 1.0 / maxf(fade_in, 0.01)
	if positional:
		var size := SoundCatalog.size_params(SoundCatalog.size_of(sound_name))
		v.p3.bus = &"SFX"
		v.p3.unit_size = size["unit"]
		v.p3.max_distance = size["max"]
		v.p3.attenuation_filter_cutoff_hz = size["cutoff"]
		v.p3.attenuation_filter_db = size["filter_db"]
		v.p3.pitch_scale = 1.0
		v.p3.global_position = target.global_position if target else position
		if target:
			v.follow = weakref(target)
	else:
		v.p2.bus = &"SFX"
		v.p2.pitch_scale = 1.0
	v.set_volume_db(-80.0 if v.gain <= 0.0 else volume_db)
	v.play(stream, randf() * stream.get_length() * 0.8)
	return id


func stop_loop(loop_id: int, fade_out: float = 0.3) -> void:
	var v := voices.find_loop(loop_id)
	if v == null:
		return
	v.target = 0.0
	v.rate = 1.0 / maxf(fade_out, 0.01)
	v.stop_when_silent = true


func set_loop_volume(loop_id: int, volume_db: float) -> void:
	var v := voices.find_loop(loop_id)
	if v:
		v.base_db = volume_db


## Pitch of a loop (e.g. raise fire_charge_loop as a charge builds).
func set_loop_pitch(loop_id: int, pitch: float) -> void:
	var v := voices.find_loop(loop_id)
	if v:
		v.set_pitch(maxf(pitch, 0.05))


func is_loop_playing(loop_id: int) -> bool:
	var v := voices.find_loop(loop_id)
	return v != null and not v.stop_when_silent


# --- Music -------------------------------------------------------------------------------

## Crossfades to a music track (looping). Pass &"" to fade out. This sets the
## base layer; combat music (Events.combat_state_changed) and overrides play
## on top of it and fall back to it afterwards.
func play_music(track: StringName, fade: float = 2.0, volume_db: float = 0.0) -> void:
	if track == _music_track:
		return
	_music_track = track
	music.set_base(track, fade, volume_db)


## The base track last requested with play_music().
func current_music() -> StringName:
	return _music_track


## The track actually playing right now (base, combat or override).
func active_music() -> StringName:
	return music.active_track()


## Combat layering (normally driven by Events.combat_state_changed).
func set_combat(in_combat: bool) -> void:
	music.set_combat(in_combat)


func is_in_combat() -> bool:
	return music.is_in_combat()


## Plays `track` above everything (cutscenes). &"" returns to normal layering.
func set_music_override(track: StringName, fade: float = 1.5, volume_db: float = 0.0) -> void:
	music.set_override(track, fade, volume_db)


# --- Ambience ----------------------------------------------------------------------------

## Loops an ambience bed (wind, city, waves...). Pass &"" to stop.
func set_ambience(ambience_name: StringName, volume_db: float = 0.0, fade: float = 2.0) -> void:
	if ambience_name == _ambience_name:
		return
	_ambience_name = ambience_name
	ambience.set_layer(&"base", ambience_name, volume_db, fade)


## Extra ambience layers mixed over the base bed: &"weather", &"night",
## &"local" (settlement, cave...). &"" fades the layer out.
func set_ambience_layer(layer: StringName, ambience_name: StringName, volume_db: float = 0.0, fade: float = 2.0) -> void:
	if layer == &"base":
		_ambience_name = ambience_name
	ambience.set_layer(layer, ambience_name, volume_db, fade)


func ambience_layers() -> Dictionary:
	return ambience.layers()


# --- Reverb environments -----------------------------------------------------------------

## Glides the SFX bus reverb to a preset: &"open", &"forest", &"cave", &"city",
## &"temple", &"ice" (AudioEnvironments.PRESETS).
func set_environment(env: StringName, fade: float = 1.0) -> void:
	if not AudioEnvironments.has_preset(env):
		push_warning("Audio.set_environment: unknown environment '%s'" % env)
		return
	if env == _environment and _env_t >= 1.0:
		return
	_env_from = AudioEnvironments.blend(_env_from, _env_to, smoothstep(0.0, 1.0, _env_t))
	_env_to = AudioEnvironments.preset(env)
	_environment = env
	_env_fade = fade
	_env_t = 0.0 if fade > 0.0 else 1.0
	if fade <= 0.0:
		AudioEnvironments.apply(_reverb, _env_to)


func current_environment() -> StringName:
	return _environment


## Current reverb parameters on the SFX bus (for tests / debug).
func environment_params() -> Dictionary:
	return AudioEnvironments.blend(_env_from, _env_to, smoothstep(0.0, 1.0, _env_t))


# --- Introspection -------------------------------------------------------------------------

## Busy voices, optionally of one category.
func voice_count(category: StringName = &"") -> int:
	return voices.count(category)


func active_voices() -> Array[Dictionary]:
	return voices.snapshot()


## Position of the active 3D listener (AudioListener3D or camera), or Vector3.INF.
func listener_position() -> Vector3:
	var vp := get_viewport()
	if vp == null:
		return Vector3.INF
	var l := vp.get_audio_listener_3d()
	if l:
		return l.global_position
	var cam := vp.get_camera_3d()
	if cam:
		return cam.global_position
	return Vector3.INF


## Shows/hides the audio debug overlay (meters, spectrum, voices, music state).
func show_debug_overlay(visible_flag: bool = true) -> void:
	if visible_flag and _debug_overlay == null:
		_debug_overlay = AudioDebugOverlay.new()
		add_child(_debug_overlay)
	elif not visible_flag and _debug_overlay != null:
		_debug_overlay.queue_free()
		_debug_overlay = null


# --- Event handlers ------------------------------------------------------------------------

func _on_footstep(actor: Node3D, position: Vector3, _yaw: float, size: float, weight: float, surface: StringName) -> void:
	if not auto_footsteps:
		return
	var s := surface if surface != &"" else WorldData.get_surface(position)
	var bonus := 25.0 if actor and actor.is_in_group(&"player") else 0.0
	play_footstep(s, position, weight, size, bonus)


func _on_landed(actor: Node3D, position: Vector3, impact: float, surface: StringName) -> void:
	if not auto_footsteps:
		return
	var s := surface if surface != &"" else WorldData.get_surface(position)
	var bonus := 25.0 if actor and actor.is_in_group(&"player") else 0.0
	play_landing(s, position, absf(impact), bonus)


func _on_hit_landed(hit: HitInfo, target: Node, result: int) -> void:
	if auto_hit_sounds:
		play_hit(hit, target, result)


func _on_region_entered(region_id: StringName) -> void:
	_region = region_id
	if not auto_region_audio:
		return
	if SoundCatalog.REGION_MUSIC.has(region_id):
		play_music(SoundCatalog.REGION_MUSIC[region_id], 3.0)
	if SoundCatalog.REGION_AMBIENCE.has(region_id):
		set_ambience(SoundCatalog.REGION_AMBIENCE[region_id], 0.0, 3.0)
	_update_night_layer()


func _on_weather_changed(weather: StringName) -> void:
	if auto_region_audio:
		set_ambience_layer(&"weather", SoundCatalog.WEATHER_AMBIENCE.get(weather, &""), 0.0, 4.0)


func _on_time_of_day(hour: float) -> void:
	_hour = hour
	if auto_region_audio:
		_update_night_layer()


func _update_night_layer() -> void:
	var night := (_hour >= 20.5 or _hour < 5.0) and SoundCatalog.NIGHT_REGIONS.has(_region)
	var want: StringName = &"amb_night" if night else &""
	if ambience.layer_sound(&"night") != want:
		set_ambience_layer(&"night", want, -2.0, 6.0)


func _on_returning_to_menu() -> void:
	music.reset_combat()
	ambience.clear(1.5)
	_ambience_name = &""
	_region = &""
	set_environment(&"open", 0.5)


# --- Internals -----------------------------------------------------------------------------

func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var w := stream as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


## Spam protection: the same sound at (roughly) the same place within 25 ms is
## dropped. Positional sounds are keyed by a 2 m grid cell so one attack hitting
## several targets still sounds on each of them.
func _throttled(sound_name: StringName, position: Vector3 = Vector3.INF) -> bool:
	var key: Variant = sound_name
	if position.is_finite():
		key = "%s@%d,%d,%d" % [sound_name, floori(position.x * 0.5), floori(position.y * 0.5), floori(position.z * 0.5)]
	var now := Time.get_ticks_msec()
	var last: int = _last_played.get(key, -1000)
	if now - last < 25:
		return true
	_last_played[key] = now
	if _last_played.size() > 512:
		_last_played.clear()
	return false
