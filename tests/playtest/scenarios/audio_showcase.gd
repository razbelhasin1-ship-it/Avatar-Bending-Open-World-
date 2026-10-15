extends RefCounted
## Audio showcase: a dusk courtyard with four element shrines, a creature
## shrine far away and a path of surface tiles. A walker emits real
## Events.footstep signals across the surfaces while abilities, loops, hits,
## creatures, combat music, regional ambience, weather and reverb environments
## are driven through the Audio API. Orbs glow while their voices play and the
## debug overlay shows live bus meters, spectrum, voices and music state.

const SURFACES: Array[StringName] = [&"snow", &"stone", &"wood", &"grass", &"sand", &"water"]
const SURFACE_COLORS := [Color(0.93, 0.95, 1.0), Color(0.55, 0.55, 0.58), Color(0.55, 0.36, 0.2),
	Color(0.36, 0.6, 0.3), Color(0.89, 0.78, 0.52), Color(0.25, 0.5, 0.8)]
const TILE := 3.2


class Shrine:
	var element: int
	var pos: Vector3
	var orb: MeshInstance3D
	var mat: ShaderMaterial
	var color: Color
	var size := 1.0
	var pulse := 1.0
	var orb_pos: Vector3


class Driver:
	extends Node
	## Moves the walker, emits footsteps and makes orbs pulse with real voices.
	var shrines: Array = []
	var walker: Node3D
	var t := 0.0
	var step_t := 0.0
	var foot := 0
	var steps := 0
	var limit_violations := 0
	var max_voices := 0

	func _process(delta: float) -> void:
		t += delta
		var x := -TILE * 3.0 + fmod(t * 1.7, TILE * 6.0)
		walker.position = Vector3(x, 0.9, 3.0)
		step_t -= delta
		while step_t <= 0.0:  # software rendering can drop to a few fps: never skip steps
			step_t += 0.42
			foot = 1 - foot
			var idx := clampi(int((x + TILE * 3.0) / TILE), 0, SURFACES.size() - 1)
			Events.footstep.emit(walker, Vector3(x, 0.0, 3.0 + (0.15 if foot else -0.15)), 0.0, 0.28, 1.0, SURFACES[idx])
			steps += 1
		var active := Audio.active_voices()
		max_voices = maxi(max_voices, active.size())
		for cat: StringName in SoundCatalog.CATEGORIES:
			if Audio.voice_count(cat) > int(SoundCatalog.CATEGORIES[cat]["limit"]):
				limit_violations += 1
		for s: Shrine in shrines:
			var on := false
			for v: Dictionary in active:
				if v.has("position") and (v["position"] as Vector3).distance_to(s.orb_pos) < 1.6 * s.size:
					on = true
					break
			var target := 5.0 if on else 0.5
			var cur: float = s.mat.get_shader_parameter(&"emission_energy")
			s.mat.set_shader_parameter(&"emission_energy", lerpf(cur, target, minf(1.0, delta * 10.0)))
			s.pulse = lerpf(s.pulse, 1.35 if on else 1.0, minf(1.0, delta * 8.0))
			s.orb.scale = Vector3.ONE * s.pulse * s.size


var _shrines: Array = []
var _driver: Driver
var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _root: Node3D


func _shrine(root: Node3D, element: int, pos: Vector3, color: Color, label: String, scale_factor: float = 1.0) -> Shrine:
	var s := Shrine.new()
	s.element = element
	s.pos = pos
	s.color = color
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.55
	cyl.height = 1.5
	base.mesh = cyl
	base.material_override = ToonMaterials.make(Color(0.62, 0.58, 0.52))
	base.position = pos + Vector3.UP * 0.75
	root.add_child(base)
	var cap := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.7
	cm.bottom_radius = 0.6
	cm.height = 0.16
	cap.mesh = cm
	cap.material_override = ToonMaterials.make(color.darkened(0.35))
	cap.position = pos + Vector3.UP * 1.55
	root.add_child(cap)
	s.orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.38
	sm.height = 0.76
	s.orb.mesh = sm
	s.mat = ToonMaterials.make(color, {"emission": color, "emission_energy": 0.5, "unique": true, "rim": 0.8})
	s.orb.material_override = s.mat
	s.orb.position = pos + Vector3.UP * 2.1
	root.add_child(s.orb)
	var l := Label3D.new()
	l.text = label
	l.font = load("res://assets/fonts/Cinzel-Variable.ttf")
	l.font_size = 96
	l.pixel_size = 0.01 * scale_factor
	l.outline_size = 18
	l.modulate = Color(0.97, 0.92, 0.8)
	l.outline_modulate = Color(0.1, 0.08, 0.07)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos + Vector3.UP * (3.0 * scale_factor)
	root.add_child(l)
	if scale_factor != 1.0:
		for n: Node3D in [base, cap, s.orb]:
			n.position = pos + (n.position - pos) * scale_factor
			n.scale = Vector3.ONE * scale_factor
	s.size = scale_factor
	s.orb_pos = s.orb.position
	_shrines.append(s)
	return s


func _build(p: Playtest) -> Node3D:
	var root := Node3D.new()
	root.name = "AudioShowcase"
	p.get_tree().root.add_child(root)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.13, 0.17, 0.36)
	sm.sky_horizon_color = Color(0.93, 0.55, 0.34)
	sm.sky_curve = 0.12
	sm.ground_horizon_color = Color(0.45, 0.3, 0.24)
	sm.ground_bottom_color = Color(0.12, 0.1, 0.1)
	sm.sun_angle_max = 12.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.45, 0.42)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	Settings.configure_environment(env)
	env.volumetric_fog_enabled = false
	we.environment = env
	root.add_child(we)
	_env = env
	_sky = sm
	_root = root
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-20, -140, 0)
	sun.light_color = Color(1.0, 0.76, 0.55)
	sun.light_energy = 1.25
	Settings.configure_sun(sun)
	root.add_child(sun)
	# Framed so the scene sits left of the debug overlay panel.
	var cam := Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.position = Vector3(4.3, 5.6, 15.0)
	cam.look_at(Vector3(4.8, 1.6, -8))
	cam.make_current()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	ground.material_override = ToonMaterials.make(Color(0.4, 0.36, 0.27), {"outline": false})
	root.add_child(ground)
	# Distant peaks for depth (Southern Air Temple style silhouettes).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 9:
		var peak := MeshInstance3D.new()
		var pk := CylinderMesh.new()
		pk.top_radius = 0.0
		pk.bottom_radius = rng.randf_range(18.0, 34.0)
		pk.height = rng.randf_range(28.0, 55.0)
		pk.radial_segments = 7
		peak.mesh = pk
		peak.material_override = ToonMaterials.make(Color(0.36, 0.33, 0.45).lerp(Color(0.55, 0.4, 0.42), rng.randf()), {"outline": false})
		peak.position = Vector3(-120.0 + i * 30.0 + rng.randf_range(-8, 8), pk.height * 0.5 - 2.0, -150.0 - rng.randf_range(0, 40))
		root.add_child(peak)
	# Stone posts with warm lanterns around the courtyard.
	for i in 10:
		var a := PI * (0.1 + 0.8 * float(i) / 9.0)
		var post := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.35, 1.2, 0.35)
		post.mesh = bm2
		post.material_override = ToonMaterials.make(Color(0.5, 0.45, 0.4))
		post.position = Vector3(cos(a) * 14.0, 0.6, -5.0 - sin(a) * 14.0)
		root.add_child(post)
		var lamp := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.16
		lm.height = 0.32
		lamp.mesh = lm
		lamp.material_override = ToonMaterials.make(Color(1.0, 0.75, 0.4), {"emission": Color(1.0, 0.6, 0.25), "emission_energy": 3.0, "outline": false})
		lamp.position = post.position + Vector3.UP * 0.75
		root.add_child(lamp)
	var court := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 13.0
	cm.bottom_radius = 13.2
	cm.height = 0.12
	cm.radial_segments = 64
	court.mesh = cm
	court.material_override = ToonMaterials.make(Color(0.66, 0.61, 0.53), {"outline": false})
	court.position = Vector3(0, 0.06, -5)
	root.add_child(court)
	for i in SURFACES.size():
		var tile := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(TILE - 0.12, 0.1, 2.2)
		tile.mesh = bm
		tile.material_override = ToonMaterials.make(SURFACE_COLORS[i], {"outline": false})
		tile.position = Vector3(-TILE * 3.0 + TILE * (i + 0.5), 0.14, 3.0)
		root.add_child(tile)
		var l := Label3D.new()
		l.text = String(SURFACES[i])
		l.font = load("res://assets/fonts/Marcellus-Regular.ttf")
		l.font_size = 72
		l.pixel_size = 0.0075
		l.outline_size = 14
		l.modulate = Color(0.97, 0.92, 0.8)
		l.outline_modulate = Color(0.1, 0.08, 0.07)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = tile.position + Vector3(0, 0.45, 1.35)
		root.add_child(l)
	_shrine(root, ElementDefs.Element.AIR, Vector3(-9, 0.12, -4), ElementDefs.DATA[ElementDefs.Element.AIR]["color"], "Air")
	_shrine(root, ElementDefs.Element.EARTH, Vector3(-4.5, 0.12, -9), ElementDefs.DATA[ElementDefs.Element.EARTH]["color"], "Earth")
	_shrine(root, ElementDefs.Element.FIRE, Vector3(2.5, 0.12, -10), ElementDefs.DATA[ElementDefs.Element.FIRE]["color"], "Fire")
	_shrine(root, ElementDefs.Element.WATER, Vector3(8.5, 0.12, -5.5), ElementDefs.DATA[ElementDefs.Element.WATER]["color"], "Water")
	_shrine(root, -1, Vector3(-6.0, 0.0, -40), Color(0.75, 0.55, 0.95), "Creatures 40 m", 2.6)
	var walker := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.75
	walker.mesh = cap
	walker.material_override = ToonMaterials.make(Color(0.85, 0.42, 0.2))
	walker.add_to_group(&"player")
	root.add_child(walker)
	_driver = Driver.new()
	_driver.shrines = _shrines
	_driver.walker = walker
	root.add_child(_driver)
	return root


## Dusk -> rainy night: dim the sun, darken the sky, start rain streaks.
func _nightfall(p: Playtest) -> void:
	var t := p.get_tree().create_tween().set_parallel(true)
	t.tween_property(_sun, "light_energy", 0.25, 1.2)
	t.tween_property(_sun, "light_color", Color(0.55, 0.62, 0.9), 1.2)
	t.tween_property(_sky, "sky_top_color", Color(0.03, 0.04, 0.09), 1.2)
	t.tween_property(_sky, "sky_horizon_color", Color(0.18, 0.17, 0.26), 1.2)
	t.tween_property(_env, "ambient_light_energy", 0.35, 1.2)
	t.tween_property(_env, "fog_light_color", Color(0.16, 0.17, 0.24), 1.2)
	var rain := GPUParticles3D.new()
	rain.amount = int(2500 * Settings.effects_scale())
	rain.lifetime = 0.9
	rain.preprocess = 1.0
	rain.visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.5, 18)
	pm.direction = Vector3(0.12, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.55)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 0.78, 0.95, 0.26)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = mat
	rain.draw_pass_1 = q
	rain.position = Vector3(2, 12, -2)
	_root.add_child(rain)


func _orb_pos(i: int) -> Vector3:
	return (_shrines[i] as Shrine).orb_pos


func _hit(element: int, pos: Vector3, heavy: bool, result: int) -> void:
	var h := HitInfo.make(10.0, null, element, HitInfo.Reaction.STAGGER if heavy else HitInfo.Reaction.FLINCH, Vector3.FORWARD)
	h.position = pos
	h.is_heavy = heavy
	Events.hit_landed.emit(h, null, result)


func run(p: Playtest) -> void:
	var root := _build(p)
	Audio.show_debug_overlay(true)
	Audio.set_environment(&"open", 0.0)
	Events.region_entered.emit(&"earth_kingdom")
	await p.wait(2.0)
	# Abilities and loops at the shrines.
	var E := ElementDefs.Element
	var loops: Array[int] = []
	loops.append(Audio.start_bending_loop(E.FIRE, &"charge_loop", _shrines[2].orb))
	loops.append(Audio.start_bending_loop(E.WATER, &"shield_loop", _shrines[3].orb))
	loops.append(Audio.start_bending_loop(E.AIR, &"shield_loop", _shrines[0].orb))
	for k in 3:
		for i in 4:
			var e: int = (_shrines[i] as Shrine).element
			Audio.play_bending(e, &"cast_light", _orb_pos(i))
			await p.wait(0.12)
			Audio.play_bending(e, &"impact", _orb_pos(i))
		await p.wait(0.35)
	Audio.set_loop_pitch(loops[0], 1.25)
	p.check(Audio.voice_count() > 0, "voices are playing during the ability sequence")
	await p.screenshot("audio_overview")
	# Big simultaneous burst: priorities and limits under load.
	Audio.play_bending(E.FIRE, &"explosion", _orb_pos(2))
	Audio.play_bending(E.EARTH, &"special", _orb_pos(1))
	Audio.play_bending(E.WATER, &"shatter", _orb_pos(3))
	Audio.play_bending(E.AIR, &"cast_heavy", _orb_pos(0))
	Audio.play_sfx(&"parry", Vector3(0, 1.5, 6))
	for i in 4:
		_hit((_shrines[i] as Shrine).element, _orb_pos(i), i % 2 == 0, Combat.Result.HIT)
	await p.wait(0.35)
	await p.screenshot("audio_bending_burst")
	# Combat music layering.
	Events.combat_state_changed.emit(true)
	p.check(Audio.active_music() == &"music_combat", "combat music layered over the regional theme")
	for k in 6:
		_hit(-1, Vector3(randf_range(-3, 3), 1.2, randf_range(0, 4)), k % 3 == 0, Combat.Result.HIT if k % 4 != 3 else Combat.Result.BLOCKED)
		await p.wait(0.3)
	await p.wait(0.8)
	await p.screenshot("audio_combat_music")
	# Cave reverb + far creatures.
	Audio.set_environment(&"cave", 0.6)
	Audio.play_sfx(&"dragon_roar", _orb_pos(4))
	await p.wait(0.4)
	Audio.play_sfx(&"bison_call", _orb_pos(4) + Vector3(3, 0, 0))
	Audio.play_sfx(&"dog_bark", Vector3(6, 1, 1))
	await p.wait(1.2)
	p.check(Audio.current_environment() == &"cave", "cave reverb active")
	await p.screenshot("audio_cave_creatures")
	# Weather + night layers, leave combat (music returns after the exit delay).
	Events.weather_changed.emit(&"rain")
	Events.time_of_day_changed.emit(22.5)
	Events.combat_state_changed.emit(false)
	Audio.set_environment(&"open", 2.0)
	_nightfall(p)
	for id in loops:
		Audio.stop_loop(id, 0.5)
	await p.wait(2.0)
	p.check(Audio.active_music() == &"music_combat", "combat music holds through short lulls")
	await p.wait(3.0)
	p.note("music after combat: active=%s base=%s combat=%s exit_timer=%.2f" % [Audio.active_music(), Audio.current_music(),
		Audio.is_in_combat(), Audio.music._exit_timer])
	p.check(Audio.active_music() == &"music_earth_kingdom", "regional theme returns after combat")
	p.check(Audio.ambience_layers().get(&"weather") == &"amb_rain", "rain layer playing")
	p.check(Audio.ambience_layers().get(&"night") == &"amb_night", "night layer playing")
	await p.screenshot("audio_night_rain")
	p.check(_driver.steps >= 10, "walker emitted %d footsteps through Events.footstep" % _driver.steps)
	p.check(_driver.limit_violations == 0, "no category ever exceeded its voice limit")
	p.note("max simultaneous voices %d, stolen %d, dropped %d" % [_driver.max_voices, Audio.voices.stolen, Audio.voices.dropped])
	var spec_max := -999.0
	for c in Audio.get_children():
		if c is AudioDebugOverlay:
			for v in (c as AudioDebugOverlay).spectrum_db():
				spec_max = maxf(spec_max, v)
	p.note("overlay spectrum max %.1f dB (driver: %s)" % [spec_max, AudioServer.get_driver_name()])
	p.check(spec_max > -70.0, "the mixer produced real output (master spectrum peak %.1f dB)" % spec_max)
	Audio.show_debug_overlay(false)
	Events.returning_to_menu.emit()
	root.queue_free()
