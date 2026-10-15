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
		if step_t <= 0.0:
			step_t = 0.42
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
				if v.has("position") and (v["position"] as Vector3).distance_to(s.pos + Vector3.UP * 2.1) < 1.6:
					on = true
					break
			var target := 5.0 if on else 0.5
			var cur: float = s.mat.get_shader_parameter(&"emission_energy")
			s.mat.set_shader_parameter(&"emission_energy", lerpf(cur, target, minf(1.0, delta * 10.0)))
			var sc := lerpf(s.orb.scale.x, 1.35 if on else 1.0, minf(1.0, delta * 8.0))
			s.orb.scale = Vector3.ONE * sc


var _shrines: Array = []
var _driver: Driver


func _shrine(root: Node3D, element: int, pos: Vector3, color: Color, label: String) -> Shrine:
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
	l.font = load("res://assets/fonts/Marcellus-Regular.ttf")
	l.font_size = 64
	l.pixel_size = 0.006
	l.outline_size = 14
	l.modulate = Color(0.94, 0.89, 0.78)
	l.outline_modulate = Color(0.1, 0.08, 0.07)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos + Vector3.UP * 3.0
	root.add_child(l)
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
	sm.sky_top_color = Color(0.2, 0.27, 0.45)
	sm.sky_horizon_color = Color(0.95, 0.66, 0.45)
	sm.ground_horizon_color = Color(0.6, 0.45, 0.35)
	sm.ground_bottom_color = Color(0.2, 0.16, 0.14)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.62, 0.5)
	env.fog_density = 0.006
	Settings.configure_environment(env)
	env.volumetric_fog_enabled = false
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, -35, 0)
	sun.light_color = Color(1.0, 0.82, 0.65)
	sun.light_energy = 1.2
	Settings.configure_sun(sun)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 58.0
	root.add_child(cam)
	cam.position = Vector3(0, 6.2, 14.5)
	cam.look_at(Vector3(0, 1.4, -7))
	cam.make_current()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	ground.mesh = pm
	ground.material_override = ToonMaterials.make(Color(0.52, 0.47, 0.38), {"outline": false})
	root.add_child(ground)
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
		l.font_size = 48
		l.pixel_size = 0.005
		l.outline_size = 10
		l.modulate = Color(0.94, 0.89, 0.78)
		l.outline_modulate = Color(0.1, 0.08, 0.07)
		l.rotation_degrees = Vector3(-70, 0, 0)
		l.position = tile.position + Vector3(0, 0.08, 1.45)
		root.add_child(l)
	_shrine(root, ElementDefs.Element.AIR, Vector3(-9, 0.12, -4), ElementDefs.DATA[ElementDefs.Element.AIR]["color"], "Air")
	_shrine(root, ElementDefs.Element.EARTH, Vector3(-4.5, 0.12, -9), ElementDefs.DATA[ElementDefs.Element.EARTH]["color"], "Earth")
	_shrine(root, ElementDefs.Element.FIRE, Vector3(2.5, 0.12, -10), ElementDefs.DATA[ElementDefs.Element.FIRE]["color"], "Fire")
	_shrine(root, ElementDefs.Element.WATER, Vector3(8.5, 0.12, -5.5), ElementDefs.DATA[ElementDefs.Element.WATER]["color"], "Water")
	_shrine(root, -1, Vector3(-1.0, 0.12, -38), Color(0.75, 0.55, 0.95), "Creatures  40 m")
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


func _orb_pos(i: int) -> Vector3:
	return (_shrines[i] as Shrine).pos + Vector3.UP * 2.1


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
	# Weather + night layers, leave combat.
	Events.weather_changed.emit(&"rain")
	Events.time_of_day_changed.emit(22.5)
	Events.combat_state_changed.emit(false)
	for id in loops:
		Audio.stop_loop(id, 0.5)
	await p.wait(1.5)
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
