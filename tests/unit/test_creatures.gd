extends TestCase
## Creatures module: construction, sockets, dimensions, gait/footsteps, IK contact,
## flight transitions, actions, burrowing, look-at, LOD, dragon trail and bird flocks.

const REQUIRED_SOCKETS: Array[StringName] = [&"saddle", &"head", &"mouth", &"tail", &"rider_left", &"rider_right", &"back", &"chest"]

var _rigs: Array[Node] = []
var _steps: Array = []


func after_each() -> void:
	if Events.footstep.is_connected(_on_footstep):
		Events.footstep.disconnect(_on_footstep)
	for r in _rigs:
		if is_instance_valid(r):
			r.queue_free()
	_rigs.clear()
	_steps.clear()


func _on_footstep(actor: Node3D, pos: Vector3, _yaw: float, size: float, weight: float, surface: StringName) -> void:
	_steps.append({"actor": actor, "pos": pos, "size": size, "weight": weight, "surface": surface})


func _spawn(species: StringName, cfg: Dictionary = {}) -> CreatureRig:
	var c := cfg.duplicate()
	if not c.has("idle"):
		c["idle"] = false
	c["sounds"] = false
	var rig := CreatureRig.create(species, c)
	add_child(rig)
	_rigs.append(rig)
	rig.set_lod(0)
	return rig


## Moves the rig with a constant velocity for `t` seconds of physics frames.
func _drive(rig: CreatureRig, vel: Vector3, t: float) -> void:
	var n := int(t * Engine.physics_ticks_per_second)
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in n:
		rig.global_position += vel * dt
		rig.set_locomotion(vel, true, dt)
		await get_tree().physics_frame


# --- Construction ------------------------------------------------------------------------

func test_create_every_species() -> void:
	for sp in CreatureRig.species_list():
		var rig := CreatureRig.create(sp, {"seed": 3, "sounds": false})
		if not expect(rig != null, "%s created" % sp):
			continue
		expect(rig.skel.count() >= 10, "%s has a skeleton (%d bones)" % [sp, rig.skel.count()])
		expect(rig.skeleton.get_bone_count() == rig.skel.count(), "%s Skeleton3D matches" % sp)
		var mesh := rig.mesh_instance.mesh as ArrayMesh
		expect(mesh != null and mesh.get_surface_count() >= 2, "%s has a multi-surface mesh" % sp)
		var verts := 0
		for si in mesh.get_surface_count():
			verts += (mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			expect(rig.mesh_instance.get_surface_override_material(si) != null, "%s surface %d has a material" % [sp, si])
		expect(verts > 300 and verts < 60000, "%s vertex budget (%d)" % [sp, verts])
		expect(rig.legs.size() >= 2 and not rig.gaits.is_empty(), "%s has legs and gaits" % sp)
		for i in rig.skel.count():
			expect(rig.skel.glob[i].origin.is_finite(), "%s bone %d finite at rest" % [sp, i])
		rig.free()
	expect(CreatureRig.create(&"not_a_species") == null, "unknown species returns null")


func test_mesh_is_cached_per_species() -> void:
	var a := _spawn(&"turtle_duck", {"seed": 1})
	var b := _spawn(&"turtle_duck", {"seed": 2})
	expect(a.mesh_instance.mesh == b.mesh_instance.mesh, "same mesh resource reused")
	var c := _spawn(&"turtle_duck", {"scale": 1.5})
	expect(c.mesh_instance.mesh != a.mesh_instance.mesh, "scaled variant builds its own mesh")
	expect_near(c.get_dimensions()["length"], a.get_dimensions()["length"] * 1.5, 0.01, "length scales")


func test_sockets_exist_and_follow_bones() -> void:
	for sp in CreatureRig.species_list():
		var rig := _spawn(sp)
		for s in REQUIRED_SOCKETS:
			expect(rig.get_socket(s) != null, "%s socket %s" % [sp, s])
	await frames(3)
	for rig: CreatureRig in _rigs:
		var d := rig.get_dimensions()
		var saddle := rig.get_socket(&"saddle")
		expect_near(saddle.position.y, d["saddle_height"], float(d["height"]) * 0.2 + 0.1, "%s saddle height" % rig.species_id)
		var head := rig.get_socket(&"head")
		expect(head.position.z < 0.0, "%s head is in front (-Z)" % rig.species_id)
		expect(head.position.y > 0.1, "%s head above ground" % rig.species_id)


func test_dimensions_sane() -> void:
	var expect_ranges := {
		&"sky_bison": [7.0, 9.0, 3.6, 4.6], &"dragon": [18.0, 23.0, 3.0, 5.5], &"polar_bear_dog": [2.6, 3.6, 1.8, 2.6],
		&"badgermole": [4.0, 5.2, 1.4, 2.2], &"otter_penguin": [0.3, 1.0, 0.8, 1.3], &"turtle_duck": [0.3, 0.8, 0.3, 0.6],
		&"ostrich_horse": [2.0, 3.2, 2.4, 3.2], &"komodo_rhino": [3.5, 5.0, 1.2, 2.0],
	}
	for sp: StringName in expect_ranges:
		var rig := CreatureRig.create(sp, {"sounds": false})
		var d := rig.get_dimensions()
		var r: Array = expect_ranges[sp]
		for key in ["length", "height", "width", "saddle_height", "paw_size", "weight", "can_fly", "walk_speed", "run_speed"]:
			expect(d.has(key), "%s dimension %s" % [sp, key])
		expect(float(d["length"]) >= r[0] and float(d["length"]) <= r[1], "%s length %.2f" % [sp, d["length"]])
		expect(float(d["height"]) >= r[2] and float(d["height"]) <= r[3], "%s height %.2f" % [sp, d["height"]])
		expect(float(d["saddle_height"]) <= float(d["height"]), "%s saddle below top" % sp)
		expect(float(d["run_speed"]) > float(d["walk_speed"]), "%s runs faster than it walks" % sp)
		expect(bool(d["can_fly"]) == (sp == &"sky_bison" or sp == &"dragon"), "%s can_fly" % sp)
		rig.free()
	var bison := CreatureRig.create(&"sky_bison")
	var dog := CreatureRig.create(&"polar_bear_dog")
	expect(float(bison.get_dimensions()["weight"]) >= 1.0, "bison is heavy")
	expect(float(dog.get_dimensions()["weight"]) < float(bison.get_dimensions()["weight"]), "dog lighter than bison")
	expect(bison.legs.size() == 6, "sky bison has six legs")
	bison.free()
	dog.free()


# --- Gait ------------------------------------------------------------------------------

func test_walk_footsteps_per_cycle() -> void:
	Events.footstep.connect(_on_footstep)
	for case in [[&"polar_bear_dog", 4], [&"sky_bison", 6], [&"badgermole", 4]]:
		var rig := _spawn(case[0])
		await frames(2)
		var v := Vector3(0, 0, -rig.walk_speed)
		await _drive(rig, v, 1.5)
		var c0 := rig.gait.cycles + rig.gait.phase
		var s0 := _count_steps(rig)
		await _drive(rig, v, 6.0)
		var cycles := rig.gait.cycles + rig.gait.phase - c0
		var steps := _count_steps(rig) - s0
		expect(cycles >= 2.5, "%s completes walk cycles (%.2f)" % [case[0], cycles])
		var per := float(steps) / maxf(cycles, 0.1)
		expect_near(per, float(case[1]), 0.6, "%s footsteps per cycle" % case[0])
		expect(rig.gait.current_gait() == rig.gaits[0]["name"], "%s uses its walk gait" % case[0])


func _count_steps(rig: CreatureRig) -> int:
	var n := 0
	for s: Dictionary in _steps:
		if s["actor"] == rig:
			n += 1
	return n


func test_footstep_payload() -> void:
	Events.footstep.connect(_on_footstep)
	var rig := _spawn(&"sky_bison")
	await frames(2)
	await _drive(rig, Vector3(0, 0, -1.6), 2.5)
	var mine := _steps.filter(func(s: Dictionary) -> bool: return s["actor"] == rig)
	expect(not mine.is_empty(), "bison emits footsteps")
	for s: Dictionary in mine:
		expect_near(s["pos"].y, 0.0, 0.05, "paw planted on the ground")
		expect_near(s["size"], 0.9, 0.01, "bison paw size")
		expect(float(s["weight"]) >= 1.0, "heavy footstep")
		expect(s["surface"] == &"grass", "surface from WorldData")


func test_gait_changes_with_speed_and_feet_stay_planted() -> void:
	var rig := _spawn(&"polar_bear_dog")
	await frames(2)
	await _drive(rig, Vector3(0, 0, -11.0), 3.0)
	expect(rig.gait.current_gait() == &"gallop", "dog gallops at 11 m/s (got %s)" % rig.gait.current_gait())
	# No foot sliding: a planted foot keeps its world position until it lifts.
	var leg := rig.legs[0]
	var held := 0
	var slid := false
	for i in 40:
		var was_planted := leg.planted
		var p := leg.foot_world
		await _drive(rig, Vector3(0, 0, -3.5), 1.0 / Engine.physics_ticks_per_second)
		if was_planted and leg.planted:
			held += 1
			if p.distance_to(leg.foot_world) > 1e-4:
				slid = true
	expect(held > 5, "observed planted frames")
	expect(not slid, "planted feet do not slide")
	# IK reaches the planted paws.
	var worst := 0.0
	for l in rig.legs:
		if l.planted:
			worst = maxf(worst, l.paw_world.distance_to(l.foot_world))
	expect(worst < 0.08, "IK reaches planted paws (err %.3f m)" % worst)


func test_settles_when_stopped_and_turning() -> void:
	var rig := _spawn(&"polar_bear_dog")
	await frames(2)
	await _drive(rig, Vector3(0, 0, -1.5), 1.0)
	await _drive(rig, Vector3.ZERO, 1.5)
	rig.rotation.y += 0.8
	await _drive(rig, Vector3.ZERO, 2.5)
	for l in rig.legs:
		expect(l.planted, "leg %s planted after settling" % l.id)
	expect(not rig.gait.moving, "not moving")


# --- Flight ----------------------------------------------------------------------------

func test_flight_transitions() -> void:
	for sp: StringName in [&"sky_bison", &"dragon"]:
		var rig := _spawn(sp)
		var events: Array = []
		rig.action_event.connect(func(a: StringName, e: StringName) -> void: events.append([a, e]))
		await frames(2)
		var d := rig.set_flying(true)
		expect(d > 0.5, "%s takeoff has a duration" % sp)
		expect(rig.is_flying() and rig.is_action_playing(&"takeoff"), "%s taking off" % sp)
		for i in 220:
			rig.global_position += Vector3(0, 0.03, -0.1)
			rig.set_flight(true, Vector3(0, 1.8, -6.0), 0.0, 0.1)
			await get_tree().physics_frame
		expect_near(rig.flight_w, 1.0, 0.01, "%s fully airborne" % sp)
		expect(events.has([&"takeoff", &"leap"]), "%s leap event" % sp)
		for l in rig.legs:
			expect(l.free > 0.95, "%s legs tucked in flight" % sp)
		rig.set_flight(true, Vector3(0, 0, -15.0), 0.5, 0.0)
		await frames(10)
		expect(rig.pose.body_roll > 0.2, "%s banks into a right turn (roll %.2f)" % [sp, rig.pose.body_roll])
		expect(rig.set_flying(false) > 0.5, "%s landing has a duration" % sp)
		for i in 200:
			rig.global_position.y = maxf(0.0, rig.global_position.y - 0.08)
			rig.set_locomotion(Vector3.ZERO, rig.global_position.y <= 0.01, 1.0 / 60.0)
			await get_tree().physics_frame
		expect_near(rig.flight_w, 0.0, 0.01, "%s back on the ground" % sp)
		expect(events.has([&"land", &"touchdown"]), "%s touchdown event" % sp)
	var dog := _spawn(&"polar_bear_dog")
	expect(dog.set_flying(true) == 0.0 and not dog.is_flying(), "non-flyers ignore set_flying")
	var b2 := _spawn(&"sky_bison")
	expect(b2.play_action(&"takeoff") > 0.0 and b2.is_flying(), "play_action(takeoff) enters flight")
	b2.play_action(&"land")
	expect(not b2.is_flying() and b2.is_landing(), "play_action(land) requests landing")


# --- Actions ---------------------------------------------------------------------------

func test_actions_events_and_finish() -> void:
	var rig := _spawn(&"dragon")
	var events: Array = []
	var finished: Array = []
	rig.action_event.connect(func(a: StringName, e: StringName) -> void: events.append([a, e]))
	rig.action_finished.connect(func(a: StringName) -> void: finished.append(a))
	await frames(2)
	var d := rig.play_action(&"roar")
	expect(d > 1.0, "roar duration")
	await seconds(d + 0.6)
	expect(events.has([&"roar", &"vocal_start"]), "roar vocal event")
	expect(finished.has(&"roar"), "roar finished")
	expect(rig.play_action(&"breathe_fire_start") > 0.0, "fire start supported")
	await seconds(0.9)
	expect(events.has([&"breathe_fire_start", &"fire_start"]), "fire_start event")
	expect(rig.is_action_playing(&"breathe_fire_start"), "fire breath holds")
	expect(rig.pose.jaw > 0.6, "jaw open while breathing fire")
	rig.play_action(&"breathe_fire_end")
	await seconds(0.2)
	expect(events.has([&"breathe_fire_end", &"fire_end"]), "fire_end event")
	expect(rig.play_action(&"no_such_action") == 0.0, "unsupported action returns 0")
	for sp in CreatureRig.species_list():
		var r2 := CreatureRig.create(sp, {"sounds": false})
		var acts := r2.supported_actions()
		for need: StringName in [&"sniff", &"look_around", &"shake", &"bite"]:
			expect(acts.has(need), "%s supports %s" % [sp, need])
		r2.free()


func test_hold_actions_and_cancel_on_move() -> void:
	var rig := _spawn(&"polar_bear_dog")
	await frames(2)
	rig.play_action(&"sit")
	await seconds(2.0)
	expect(rig.is_action_playing(&"sit"), "sit holds")
	expect(rig.pose.body_pitch > 0.25, "sitting pitches the body up")
	await _drive(rig, Vector3(0, 0, -4.0), 0.8)
	expect(not rig.is_action_playing(&"sit"), "moving stands the dog up")
	await _drive(rig, Vector3.ZERO, 0.8)
	rig.play_action(&"lie_down")
	await seconds(2.0)
	expect(rig.is_action_playing(&"lie_down"), "lie_down holds")
	rig.stop_action()
	await seconds(1.2)
	expect(rig.current_action() == &"", "stop_action ends it")


func test_badgermole_burrow_cycle() -> void:
	var rig := _spawn(&"badgermole")
	var events: Array = []
	rig.action_event.connect(func(a: StringName, e: StringName) -> void: events.append([a, e]))
	await frames(2)
	rig.play_action(&"dig_in")
	await seconds(3.3)
	expect(events.has([&"dig_in", &"burrowed"]), "burrowed event")
	expect(not rig.mesh_instance.visible, "hidden underground")
	expect(rig.skel.glob[rig.motor.pelvis].origin.y < -1.0, "body below ground")
	await _drive(rig, Vector3(0, 0, -3.0), 1.0)
	expect(not rig.mesh_instance.visible, "still hidden while tunnelling")
	rig.play_action(&"emerge")
	await seconds(2.4)
	expect(events.has([&"emerge", &"burst"]), "emerge burst event")
	expect(rig.mesh_instance.visible, "visible after emerging")
	expect(rig.skel.glob[rig.motor.pelvis].origin.y > 0.6, "body back above ground")


# --- Look / LOD / misc -------------------------------------------------------------------

func test_look_at_turns_head() -> void:
	var rig := _spawn(&"polar_bear_dog")
	await frames(3)
	var head := rig.get_socket(&"head")
	var before := head.global_position
	rig.look_at_point(rig.global_position + Vector3(6, 2, -2))
	await seconds(1.5)
	expect(head.global_position.x > before.x + 0.1, "head turns toward the target (dx %.2f)" % (head.global_position.x - before.x))
	rig.clear_look()
	await seconds(1.5)
	expect(absf(head.global_position.x - before.x) < 0.1, "head returns when cleared")


func test_lod_levels() -> void:
	var rig := _spawn(&"sky_bison", {"detail": 2})
	await frames(2)
	var full := rig.mesh_instance.get_surface_override_material(0) as ShaderMaterial
	expect(full.next_pass != null and (full.next_pass as ShaderMaterial).shader == CreatureMaterials.FUR_SHADER, "LOD0 has fur shells")
	rig.set_lod(2)
	var low := rig.mesh_instance.get_surface_override_material(0) as ShaderMaterial
	expect((low.next_pass as ShaderMaterial).shader == CreatureMaterials.OUTLINE_SHADER, "LOD2 drops the shells")
	var t0 := rig.time
	await frames(3)
	expect(rig.time >= t0, "still animating at LOD2")
	rig.set_lod(3)
	expect(rig.mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "LOD3 stops casting shadows")
	rig.set_lod(-1)
	await frames(2)
	expect(rig.lod <= 3, "auto LOD active")
	var live := _spawn(&"polar_bear_dog")
	var old_detail: int = Settings.get_value("graphics", "detail")
	var old_preset: String = Settings.get_value("graphics", "preset")
	Settings.set_value("graphics", "detail", 0)
	Events.graphics_settings_changed.emit()
	var lm := live.mesh_instance.get_surface_override_material(0) as ShaderMaterial
	expect((lm.next_pass as ShaderMaterial).shader == CreatureMaterials.OUTLINE_SHADER, "runtime detail 0 drops shells")
	Settings.set_value("graphics", "detail", old_detail)
	Settings.set_value("graphics", "preset", old_preset)
	Events.graphics_settings_changed.emit()
	var mobile := _spawn(&"polar_bear_dog", {"detail": 0})
	var mm := mobile.mesh_instance.get_surface_override_material(0) as ShaderMaterial
	expect((mm.next_pass as ShaderMaterial).shader == CreatureMaterials.OUTLINE_SHADER, "detail 0 (mobile) has no shells")


func test_dragon_body_follows_path() -> void:
	var rig := _spawn(&"dragon")
	await frames(2)
	await _drive(rig, Vector3(0, 0, -6.0), 3.0)
	var spine10 := rig.skeleton.global_transform * rig.skel.glob[rig.skel.idx(&"spine_10")].origin
	var root := rig.global_position
	expect_near(spine10.z - root.z, 6.0, 1.0, "hips trail ~6 m behind the shoulders on a straight path")
	expect(absf(spine10.x - root.x) < 0.8, "body stays on the path line")
	# Turn: the body bends along the curve (tail not straight behind the new heading).
	for i in 60:
		rig.rotation.y += 0.025
		var fwd := -rig.global_basis.z
		rig.global_position += fwd * 6.0 / 60.0
		rig.set_locomotion(fwd * 6.0, true, 1.0 / 60.0)
		await get_tree().physics_frame
	var tail := rig.skeleton.global_transform * rig.skel.glob[rig.skel.idx(&"spine_20")].origin
	var straight := rig.global_position + rig.global_basis.z * 12.0
	expect(tail.distance_to(straight) > 1.5, "tail follows the curved path")


func test_swimming_floats_at_water_level() -> void:
	var rig := _spawn(&"turtle_duck")
	await frames(2)
	rig.global_position = Vector3(0, 0.0, 0)
	rig.set_swimming(true, 0.5)
	await seconds(2.0)
	var pel := rig.skeleton.global_transform * rig.skel.glob[rig.motor.pelvis].origin
	expect_near(pel.y, 0.5, 0.08, "pelvis floats at the water line")
	for l in rig.legs:
		expect(l.free > 0.9, "legs paddle (free) while swimming")


func test_bird_flock() -> void:
	var flock := BirdFlock.create(&"gull", 10, Vector3(0, 0, 0), 20.0, 15.0, 3)
	add_child(flock)
	_rigs.append(flock)
	await seconds(1.0)
	var pts := flock.bird_positions()
	expect(pts.size() == 10, "ten birds")
	for p in pts:
		expect(p.is_finite(), "finite position")
		expect(p.y > 3.0 and p.y < 35.0, "birds stay in the sky band (%.1f)" % p.y)
	flock.startle(Vector3(0, 10, 0))
	await seconds(1.0)
	var climbed := 0
	for i in pts.size():
		if flock.bird_positions()[i].y > pts[i].y:
			climbed += 1
	expect(climbed >= 5, "startled birds climb away (%d)" % climbed)


func test_update_cost_budget() -> void:
	var rigs: Array[CreatureRig] = []
	for sp: StringName in [&"sky_bison", &"dragon", &"polar_bear_dog", &"badgermole"]:
		rigs.append(_spawn(sp))
	await frames(3)
	var t0 := Time.get_ticks_usec()
	var n := 30
	for i in n:
		for r in rigs:
			r.global_position += Vector3(0, 0, -0.05)
			r.set_locomotion(Vector3(0, 0, -3.0), true, 1.0 / 60.0)
			r._step(1.0 / 60.0)
	var per := float(Time.get_ticks_usec() - t0) / float(n * rigs.size()) / 1000.0
	print("    creature update cost: %.3f ms per companion per frame (headless)" % per)
	expect(per < 4.0, "companion update under 4 ms (%.3f)" % per)
