extends TestCase
## Audio module: asset coverage, catalog/bending mapping, voice management,
## distance culling, music layering, regional audio, environments and loops.

var _cam: Camera3D


func before_each() -> void:
	Audio._last_played.clear()
	Audio.auto_footsteps = true
	Audio.auto_hit_sounds = true
	Audio.auto_region_audio = true
	Audio.auto_stingers = true


func after_each() -> void:
	Audio.music.combat_exit_delay = 4.0
	Audio.music.reset_combat()
	Audio.play_music(&"", 0.0)
	Audio.ambience.clear(0.0)
	Audio.set_ambience(&"", 0.0, 0.0)
	Audio.set_environment(&"open", 0.0)
	for v in Audio.voices.voices3d + Audio.voices.voices2d:
		Audio.voices.release(v)
	if _cam and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null


func _listener_at(pos: Vector3) -> void:
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.global_position = pos
	_cam.make_current()


## Names listed in docs/ARCHITECTURE.md under "Audio names".
func _architecture_names() -> Array[StringName]:
	var out: Array[StringName] = []
	var f := FileAccess.open("res://docs/ARCHITECTURE.md", FileAccess.READ)
	if f == null:
		return out
	var text := f.get_as_text()
	var start := text.find("### Audio names")
	var end := text.find("## Testing rules", start)
	var section := text.substr(start, end - start)
	var lines := section.split("\n")
	var re := RegEx.new()
	re.compile("\\b([a-z]+(?:_[a-z0-9]+)+|jump|parry|pickup|gong|discovery)\\b")
	for i in range(1, lines.size()):
		var line := lines[i]
		var colon := line.find(":")
		var body := line
		for label in ["UI:", "Steps:", "Body:", "Air:", "Earth:", "Fire:", "Water:", "Creatures:", "Ambience loops:", "Stingers:", "Music (looping):"]:
			body = body.replace(label, "")
		if colon < 0 and body.strip_edges().is_empty():
			continue
		for m in re.search_all(body):
			var n := StringName(m.get_string(1))
			if not out.has(n):
				out.append(n)
	return out


func test_catalog_matches_architecture_list() -> void:
	var names := _architecture_names()
	expect(names.size() > 100, "parsed %d names from ARCHITECTURE.md" % names.size())
	var catalog: Array[StringName] = []
	catalog.append_array(SoundCatalog.ALL_SFX)
	catalog.append_array(SoundCatalog.MUSIC_TRACKS)
	for n in names:
		expect(catalog.has(n), "catalog has %s" % n)
	for n in catalog:
		expect(names.has(n), "%s is documented" % n)


func test_every_sound_resolves_and_loads() -> void:
	for n: StringName in SoundCatalog.ALL_SFX:
		var s := Audio.get_stream(n)
		if not expect(s != null, "sound %s resolves" % n):
			continue
		expect(s.get_length() > 0.02, "%s has audio (%.3f s)" % [n, s.get_length()])
	for t: StringName in SoundCatalog.MUSIC_TRACKS:
		var m := Audio.get_stream(t, Audio.MUSIC_DIR)
		if expect(m != null, "music %s resolves" % t):
			expect(m.get_length() >= 60.0 and m.get_length() <= 150.0, "%s is 60-150 s (%.1f)" % [t, m.get_length()])


func test_variations_for_repeated_sounds() -> void:
	for n: StringName in [&"step_snow", &"step_stone", &"step_grass", &"step_wood", &"whoosh_light", &"punch_impact",
			&"kick_impact", &"hit_flesh", &"earth_impact", &"fire_impact", &"water_splash", &"air_blast"]:
		var c := Audio.get_variants(n).size()
		expect(c >= 3 and c <= 6, "%s has 3-6 variants (%d)" % [n, c])


func test_loops_are_flagged() -> void:
	for n: StringName in SoundCatalog.ALL_SFX:
		if not SoundCatalog.is_loop(n):
			continue
		for s: AudioStream in Audio.get_variants(n):
			if s is AudioStreamWAV:
				var w := s as AudioStreamWAV
				expect(w.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s imports with a forward loop" % n)
				expect(w.loop_end >= int(w.get_length() * w.mix_rate) - 2, "%s loops over the whole file" % n)
			elif s is AudioStreamOggVorbis:
				expect((s as AudioStreamOggVorbis).loop, "%s ogg imports with loop on" % n)
	for t: StringName in SoundCatalog.MUSIC_TRACKS:
		var m := Audio.get_stream(t, Audio.MUSIC_DIR)
		if m is AudioStreamOggVorbis:
			expect((m as AudioStreamOggVorbis).loop, "%s ogg imports with loop on" % t)


func test_categories_priorities_sizes() -> void:
	expect_eq(SoundCatalog.category_of(&"step_snow"), &"step")
	expect_eq(SoundCatalog.category_of(&"ui_click"), &"ui")
	expect_eq(SoundCatalog.category_of(&"fire_loop"), &"loop")
	expect_eq(SoundCatalog.category_of(&"dragon_roar"), &"creature")
	expect_eq(SoundCatalog.category_of(&"punch_impact"), &"impact")
	expect_eq(SoundCatalog.category_of(&"earth_stomp"), &"bending")
	expect_eq(SoundCatalog.category_of(&"amb_rain"), &"ambient")
	expect_eq(SoundCatalog.size_of(&"earth_quake"), SoundCatalog.Size.HUGE)
	expect_eq(SoundCatalog.size_of(&"step_grass"), SoundCatalog.Size.SMALL)
	expect(SoundCatalog.priority_of(&"parry") > SoundCatalog.priority_of(&"whoosh_light"), "parry outranks whooshes")
	expect(SoundCatalog.priority_of(&"step_dirt") < SoundCatalog.priority_of(&"air_blast"), "steps are lowest priority")
	var small: Dictionary = SoundCatalog.size_params(SoundCatalog.Size.SMALL)
	var huge: Dictionary = SoundCatalog.size_params(SoundCatalog.Size.HUGE)
	expect(huge["max"] > small["max"] * 4.0, "huge sounds carry much further")
	expect_eq(SoundCatalog.step_for_surface(&"ash"), &"step_ash")
	expect_eq(SoundCatalog.step_for_surface(&"lava"), &"step_dirt")


func test_bending_map_covers_elements() -> void:
	for e: int in BendingSounds.TABLE:
		var t: Dictionary = BendingSounds.TABLE[e]
		for ev: StringName in t:
			var n: StringName = t[ev]
			if n != &"":
				expect(SoundCatalog.ALL_SFX.has(n), "bending map %s/%s -> %s exists" % [e, ev, n])
	for e: int in ElementDefs.ALL:
		for ev: StringName in [&"cast_light", &"cast_heavy", &"impact", &"dash", &"jump", &"wall", &"special"]:
			expect(BendingSounds.sound_for(e, ev) != &"", "element %d has a sound for %s" % [e, ev])
	expect_eq(BendingSounds.sound_for(ElementDefs.Element.FIRE, &"charge_loop"), &"fire_charge_loop")
	expect_eq(BendingSounds.sound_for(ElementDefs.Element.WATER, &"heal_loop"), &"water_heal_loop")
	expect_eq(BendingSounds.sound_for(ElementDefs.Element.EARTH, &"parry"), &"parry")
	var hit := BendingSounds.hit_layers(ElementDefs.Element.FIRE, false, Combat.Result.HIT)
	expect_eq(hit[0], &"fire_impact")
	expect_eq(BendingSounds.hit_layers(ElementDefs.Element.WATER, false, Combat.Result.HIT, true)[0], &"ice_impact")
	expect_eq(BendingSounds.hit_layers(-1, true, Combat.Result.HIT)[0], &"kick_impact")
	expect_eq(BendingSounds.hit_layers(ElementDefs.Element.AIR, false, Combat.Result.BLOCKED), [&"block_impact"] as Array[StringName])
	expect_eq(BendingSounds.hit_layers(ElementDefs.Element.AIR, false, Combat.Result.DEFLECTED)[0], &"parry")
	expect(BendingSounds.hit_layers(ElementDefs.Element.AIR, false, Combat.Result.DODGED).is_empty(), "dodges are silent")


func test_category_voice_limit_and_priority() -> void:
	_listener_at(Vector3.ZERO)
	var limit := int(SoundCatalog.CATEGORIES[&"step"]["limit"])
	var stolen0 := Audio.voices.stolen
	for i in limit + 6:
		Audio.play_footstep(&"stone", Vector3(2, 0, 0), 1.0)
	expect(Audio.voice_count(&"step") <= limit, "steps capped at %d (got %d)" % [limit, Audio.voice_count(&"step")])
	expect(Audio.voices.stolen > stolen0, "equal-priority steps steal the oldest voice")
	# A farther (lower effective priority) step loses against a full category of near ones.
	var dropped0 := Audio.voices.dropped
	expect(Audio.play_footstep(&"stone", Vector3(30, 0, 0), 1.0) == null, "distant step dropped when steps are saturated")
	expect(Audio.voices.dropped > dropped0, "drop counted")
	# Fill the impact category with high-priority parries; a low-priority impact must not steal them.
	var ilimit := int(SoundCatalog.CATEGORIES[&"impact"]["limit"])
	for i in ilimit:
		Audio._last_played.clear()
		Audio.play_sfx(&"parry", Vector3(2, 0, 0))
	expect_eq(Audio.voice_count(&"impact"), ilimit, "impact category full")
	var dropped_before := Audio.voices.dropped
	var p := Audio.play_sfx(&"body_fall", Vector3(2, 0, 0))
	expect(p == null, "low priority impact dropped when category is full of parries")
	expect(Audio.voices.dropped > dropped_before, "drop counted")


func test_distance_culling_and_size_classes() -> void:
	_listener_at(Vector3.ZERO)
	await frames(1)
	expect(Audio.listener_position().is_equal_approx(Vector3.ZERO), "listener is the camera")
	expect(Audio.play_sfx(&"step_grass_never", Vector3.ONE) == null, "missing sound is skipped")
	var far := Audio.play_footstep(&"grass", Vector3(500, 0, 0))
	expect(far == null, "footstep 500 m away is culled")
	var near := Audio.play_footstep(&"grass", Vector3(3, 0, 0))
	if expect(near != null, "near footstep plays"):
		expect_near(near.unit_size, SoundCatalog.SIZE_PARAMS[SoundCatalog.Size.SMALL]["unit"], 0.001, "small unit size")
	var quake := Audio.play_sfx(&"earth_quake", Vector3(300, 0, 0))
	if expect(quake != null, "a quake 300 m away is still audible"):
		expect_near(quake.max_distance, SoundCatalog.SIZE_PARAMS[SoundCatalog.Size.HUGE]["max"], 0.001, "huge max distance")
	var custom := Audio.play_sfx(&"fire_impact", Vector3(5, 0, 0), 0.0, 0.0, 33.0)
	if expect(custom != null, "explicit max distance accepted"):
		expect_near(custom.max_distance, 33.0, 0.001)


func test_footstep_helper_layers() -> void:
	_listener_at(Vector3.ZERO)
	var p := Audio.play_footstep(&"snow", Vector3(1, 0, 0), 1.0, 0.9)
	expect(p != null, "snow step plays")
	var names := Audio.active_voices().map(func(d: Dictionary) -> StringName: return d["sound"])
	expect(names.has(&"step_snow"), "step_snow voice active")
	expect(names.has(&"creature_step_heavy"), "big paws add the heavy creature layer")
	Events.footstep.emit(null, Vector3(2, 0, 0), 0.0, 0.28, 1.0, &"wood")
	names = Audio.active_voices().map(func(d: Dictionary) -> StringName: return d["sound"])
	expect(names.has(&"step_wood"), "Events.footstep plays the surface step")
	Events.landed.emit(null, Vector3(1, 0, 0), 12.0, &"stone")
	names = Audio.active_voices().map(func(d: Dictionary) -> StringName: return d["sound"])
	expect(names.has(&"land_heavy"), "hard landing plays land_heavy")


func test_hit_feedback_from_events() -> void:
	_listener_at(Vector3.ZERO)
	var hit := HitInfo.make(10.0, null, ElementDefs.Element.FIRE, HitInfo.Reaction.FLINCH, Vector3.FORWARD)
	hit.position = Vector3(2, 1, 0)
	Events.hit_landed.emit(hit, null, Combat.Result.HIT)
	var names := Audio.active_voices().map(func(d: Dictionary) -> StringName: return d["sound"])
	expect(names.has(&"fire_impact"), "fire hit plays fire_impact")
	expect(names.has(&"hit_flesh"), "and the flesh layer")
	var blocked := HitInfo.make(10.0, null, -1, HitInfo.Reaction.FLINCH, Vector3.FORWARD)
	blocked.position = Vector3(1, 1, 0)
	Events.hit_landed.emit(blocked, null, Combat.Result.BLOCKED)
	names = Audio.active_voices().map(func(d: Dictionary) -> StringName: return d["sound"])
	expect(names.has(&"block_impact"), "blocked hit plays block_impact")


func test_loop_handles() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var id := Audio.start_bending_loop(ElementDefs.Element.FIRE, &"charge_loop", holder)
	expect(id > 0, "charge loop started")
	expect(Audio.is_loop_playing(id), "loop playing")
	Audio.set_loop_pitch(id, 1.3)
	await seconds(0.2)
	var v := Audio.voices.find_loop(id)
	if expect(v != null, "loop voice exists"):
		expect_near(v.p3.pitch_scale, 1.3, 0.001, "pitch follows the charge")
		expect(v.p3.playing, "loop still playing after 0.2 s")
	Audio.stop_loop(id, 0.05)
	await seconds(0.25)
	expect(Audio.voices.find_loop(id) == null, "stopped loop releases its voice")
	expect(Audio.start_bending_loop(ElementDefs.Element.EARTH, &"charge_loop", holder) == 0, "no earth charge loop -> 0")
	var id2 := Audio.play_loop(&"water_shield_loop", holder)
	holder.queue_free()
	await seconds(0.5)
	expect(Audio.voices.find_loop(id2) == null, "loop stops when its target is freed")


func test_music_combat_layering() -> void:
	Audio.music.combat_exit_delay = 0.2
	Audio.play_music(&"music_earth_kingdom", 0.05)
	await seconds(0.15)
	expect_eq(Audio.current_music(), &"music_earth_kingdom")
	expect_eq(Audio.active_music(), &"music_earth_kingdom")
	await seconds(0.4)
	Events.combat_state_changed.emit(true)
	expect_eq(Audio.active_music(), &"music_combat", "combat music takes over immediately")
	expect_eq(Audio.current_music(), &"music_earth_kingdom", "base track is remembered")
	await seconds(0.3)
	Events.combat_state_changed.emit(false)
	expect_eq(Audio.active_music(), &"music_combat", "leaving combat waits for the exit delay")
	await seconds(0.5)
	expect_eq(Audio.active_music(), &"music_earth_kingdom", "back to the regional theme")
	var earth := {}
	for st: Dictionary in Audio.music.voice_states():
		if st["track"] == &"music_earth_kingdom":
			earth = st
	expect(not earth.is_empty() and earth["playing"] and not earth["paused"], "regional theme resumed")
	expect(float(earth.get("position", 0.0)) > 0.3, "resumed from where it paused, not from the top")
	Audio.set_music_override(&"music_menu", 0.05)
	expect_eq(Audio.active_music(), &"music_menu", "override wins")
	Audio.set_music_override(&"", 0.05)
	expect_eq(Audio.active_music(), &"music_earth_kingdom")


func test_region_weather_and_night_ambience() -> void:
	Events.region_entered.emit(&"fire_nation")
	expect_eq(Audio.current_music(), &"music_fire_nation")
	expect_eq(Audio.ambience_layers().get(&"base"), &"amb_volcanic")
	Events.weather_changed.emit(&"rain")
	expect_eq(Audio.ambience_layers().get(&"weather"), &"amb_rain")
	Events.time_of_day_changed.emit(23.0)
	expect_eq(Audio.ambience_layers().get(&"night"), &"amb_night", "night layer in temperate regions")
	Events.region_entered.emit(&"water_tribe")
	expect_eq(Audio.current_music(), &"music_water_tribe")
	expect(not Audio.ambience_layers().has(&"night"), "no crickets in the arctic")
	Events.weather_changed.emit(&"clear")
	expect(not Audio.ambience_layers().has(&"weather"), "weather layer cleared")
	Events.returning_to_menu.emit()
	expect(Audio.ambience_layers().is_empty(), "menu clears ambience")


func test_environment_presets() -> void:
	Audio.set_environment(&"cave", 0.0)
	expect_eq(Audio.current_environment(), &"cave")
	var p := Audio.environment_params()
	expect_near(float(p["wet"]), float(AudioEnvironments.PRESETS[&"cave"]["wet"]), 0.001, "cave wet")
	var idx := AudioServer.get_bus_index(&"SFX")
	var found := false
	for i in AudioServer.get_bus_effect_count(idx):
		var e := AudioServer.get_bus_effect(idx, i)
		if e is AudioEffectReverb:
			found = true
			expect_near((e as AudioEffectReverb).room_size, float(AudioEnvironments.PRESETS[&"cave"]["room_size"]), 0.001)
	expect(found, "reverb lives on the SFX bus")
	Audio.set_environment(&"temple", 0.3)
	await seconds(0.45)
	expect_near(float(Audio.environment_params()["room_size"]), float(AudioEnvironments.PRESETS[&"temple"]["room_size"]), 0.01, "glides to temple")


func test_stinger_ducks_music() -> void:
	Audio.play_music(&"music_tutorial", 0.0)
	await seconds(0.1)
	var p := Audio.play_stinger(&"level_up")
	expect(p != null, "stinger plays")
	await seconds(0.3)
	expect(Audio.music._duck_db < -3.0, "music ducked under the stinger (%.1f dB)" % Audio.music._duck_db)


## Plays `stream` from just before its end on a private bus with an
## AudioEffectCapture and returns what the engine mixed across the loop point
## (empty when the audio driver is not mixing).
func _capture_wrap(stream: AudioStream, before_end: float, total: float) -> PackedVector2Array:
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "LoopTest")
	AudioServer.set_bus_send(bus, "Master")
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 2.0
	AudioServer.add_bus_effect(bus, cap)
	var p := AudioStreamPlayer.new()
	p.bus = &"LoopTest"
	add_child(p)
	p.stream = stream
	p.play(stream.get_length() - before_end)
	await seconds(total)
	var still_playing := p.playing
	var frames := cap.get_frames_available()
	var buf := cap.get_buffer(frames) if frames > 0 else PackedVector2Array()
	p.stop()
	p.queue_free()
	AudioServer.remove_bus(bus)
	expect(still_playing, "looping stream still playing past its end")
	return buf


## Records the engine output across a WAV loop point to prove the imported loop
## plays seamlessly in Godot (no click at the wrap).
func test_loop_wraps_seamlessly_in_engine() -> void:
	var buf := await _capture_wrap(Audio.get_stream(&"fire_loop"), 0.3, 0.7)
	if buf.size() < 2000:
		print("  (skipped: audio driver is not mixing in this environment, %d frames)" % buf.size())
		return
	var max_step := 0.0
	var steps := PackedFloat32Array()
	for i in range(1, buf.size()):
		var s := absf(buf[i].x - buf[i - 1].x)
		steps.append(s)
		max_step = maxf(max_step, s)
	steps.sort()
	var p999 := steps[int(steps.size() * 0.999)]
	expect(max_step <= p999 * 2.5 + 0.01, "no click at the wrap (max step %.4f vs p99.9 %.4f)" % [max_step, p999])


## Music OGG loops: no decoder gap (silent hole) when the track wraps.
func test_music_loop_has_no_gap_in_engine() -> void:
	var buf := await _capture_wrap(Audio.get_stream(&"music_select", Audio.MUSIC_DIR), 0.4, 0.8)
	if buf.size() < 4000:
		print("  (skipped: audio driver is not mixing in this environment, %d frames)" % buf.size())
		return
	var win := 220  # ~5 ms
	var rms := PackedFloat32Array()
	for s in range(0, buf.size() - win, win):
		var acc := 0.0
		for i in range(s, s + win):
			acc += buf[i].x * buf[i].x + buf[i].y * buf[i].y
		rms.append(sqrt(acc / (2.0 * win)))
	var sorted := rms.duplicate()
	sorted.sort()
	var median := sorted[sorted.size() / 2]
	var quiet := 0
	# Skip the first windows: capture starts before the player is audible.
	for i in range(8, rms.size()):
		if rms[i] < median * 0.03:
			quiet += 1
	expect(median > 0.001, "music is audible through the wrap (median rms %.4f)" % median)
	expect(quiet == 0, "no silent gap at the loop point (%d near-silent 5 ms windows)" % quiet)
