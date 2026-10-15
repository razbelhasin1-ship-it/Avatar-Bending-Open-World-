extends TestCase
## Characters module: build, skeleton, skinning, clips, events, locomotion
## (stride/speed, no foot sliding, footstep counts), states, reactions,
## sockets, root motion, LOD.

const SK = preload("res://src/characters/rig/rig_skeleton_def.gd")

var _steps: Array = []


func before_each() -> void:
	# Character tests run on a flat plane at y = 0 (the baked world is ~130 m high at the origin).
	WorldData.use_flat_world(true)


func after_each() -> void:
	WorldData.use_flat_world(false)


func _make(cfg: Dictionary) -> HumanoidRig:
	var rig := HumanoidRig.create(cfg)
	rig.manual_update = true
	rig.auto_lod = false
	add_child(rig)
	return rig


func _step(rig: HumanoidRig, seconds: float, vel: Vector3 = Vector3.ZERO) -> void:
	var n := int(round(seconds * 60.0))
	for i in n:
		rig.position += vel / 60.0
		rig.set_locomotion(vel, true)
		rig.advance(1.0 / 60.0)


func test_build_every_preset() -> void:
	for preset: StringName in CharacterOutfits.PRESETS:
		for body in ["male", "female"]:
			var spec := CharacterOutfits.resolve({"preset": preset, "body": body})
			var res := CharacterMeshBuilder.build(spec)
			var mesh: ArrayMesh = res["mesh"]
			expect(mesh != null and mesh.get_surface_count() == 2, "%s/%s has body + detail surfaces" % [preset, body])
			expect(int(res["vertex_count"]) > 2000, "%s/%s has a real mesh (%d verts)" % [preset, body, res["vertex_count"]])
			var aabb := mesh.get_aabb()
			expect(aabb.size.y > 1.0 and aabb.size.y < 2.3, "%s/%s plausible height %.2f" % [preset, body, aabb.size.y])
	for age in ["child", "teen", "elder"]:
		var rig := _make({"preset": &"villager_earth", "age": age})
		expect(rig.skeleton != null, "%s rig built" % age)
		rig.queue_free()


func test_mesh_cache_shares_variants() -> void:
	var a := CharacterOutfits.resolve({"preset": &"guard"})
	var b := CharacterOutfits.resolve({"preset": &"guard"})
	expect_eq(a["cache_key"], b["cache_key"], "same config, same key")
	expect(CharacterMeshBuilder.build(a)["mesh"] == CharacterMeshBuilder.build(b)["mesh"], "mesh shared")
	var keys := {}
	for i in 12:
		keys[CharacterOutfits.resolve({"preset": &"villager_earth", "seed": i})["cache_key"]] = true
	expect(keys.size() >= 4, "seeded crowds vary (%d variants of 12)" % keys.size())


func test_skeleton_layout() -> void:
	var d := RigSkeletonDef.new().build(RigSkeletonDef.make_proportions("male", "adult", 0.0))
	expect_eq(d.bone_count(), SK.CORE_COUNT, "core bone count")
	expect_eq(SK.CORE_COUNT, 32)
	for i in d.bone_count():
		expect(d.parents[i] < i, "bone %s parent precedes it" % d.names[i])
	for n in ["root", "hips", "spine", "chest", "upper_chest", "neck", "head", "clavicle_l", "upperarm_l", "forearm_l", "hand_l",
			"fingers_l", "thumb_l", "thigh_r", "shin_r", "foot_r", "toes_r"]:
		expect(d.find(n) >= 0, "bone %s exists" % n)
	expect_near(d.rest_pos[SK.HEAD].y, 1.6, 0.12, "head height")
	expect_near(d.leg_len, 0.889, 0.02, "leg length")
	var rig := _make({"preset": &"water_tribe", "body": "female"})
	expect(rig.skeleton.get_bone_count() > SK.CORE_COUNT, "secondary bones appended (hair/skirt)")
	expect(rig.skeleton.find_bone("hair_back_1") >= 0, "long hair spring bone")
	expect_eq(rig.skeleton.get_bone_name(SK.HAND_R), "hand_r")


func test_skin_weights_normalized() -> void:
	for preset: StringName in [&"air_nomad", &"dai_li", &"fire_soldier", &"water_tribe"]:
		var res := CharacterMeshBuilder.build(CharacterOutfits.resolve({"preset": preset}))
		var d: RigSkeletonDef = res["def"]
		var mesh: ArrayMesh = res["mesh"]
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var bad := 0
			var bad_bone := 0
			for v in w.size() / 4:
				var sum := w[v * 4] + w[v * 4 + 1] + w[v * 4 + 2] + w[v * 4 + 3]
				if absf(sum - 1.0) > 0.002:
					bad += 1
				for k in 4:
					if b[v * 4 + k] < 0 or b[v * 4 + k] >= d.bone_count():
						bad_bone += 1
			expect_eq(bad, 0, "%s surface %d weights sum to 1" % [preset, s])
			expect_eq(bad_bone, 0, "%s surface %d bone indices valid" % [preset, s])


func test_clip_registry_and_format() -> void:
	expect(AnimLibrary.clip_names().size() > 120, "built-in clips registered")
	for n in [&"jab_r", &"jab_l", &"combo_fire", &"combo_earth_3", &"dodge_roll", &"knockdown_back", &"getup", &"wave_r", &"work_hammer",
			&"meditate_loop", &"ride", &"swim", &"stance_air", &"stance_earth", &"stance_fire", &"stance_water", &"idle_elder", &"earth_wall"]:
		expect(AnimLibrary.has_clip(n), "clip %s" % n)
	var c := AnimLibrary.register(&"test_custom_move", {"length": 0.5, "mask": &"arms", "events": {"release": 0.4},
		"keys": [[0.4, {"hand_r": Vector3(0, 0, 1), "fist_r": 1.0}, &"snap"]]})
	expect(c != null and AnimLibrary.get_clip(&"test_custom_move") == c, "custom clip registered")
	expect_near(c.event_time(&"release"), 0.4, 0.0001)
	expect_eq(c.mask, RigPose.MASKS[&"arms"], "mask resolved")
	var al := AnimLibrary.alias(&"test_custom_alias", &"test_custom_move")
	expect(al != null and al.name == &"test_custom_alias", "alias keeps its own name")
	# Implicit base keys: the clip starts and ends at the layer below.
	var base := RigPose.new()
	var out := RigPose.new()
	c.evaluate(0.0, base, out)
	expect((out.v[RigPose.HAND_R] as Vector3).is_equal_approx(base.v[RigPose.HAND_R]), "starts at base")
	c.evaluate(0.4, base, out)
	expect((out.v[RigPose.HAND_R] as Vector3).is_equal_approx(Vector3(0, 0, 1)), "hits key")
	c.evaluate(1.0, base, out)
	expect((out.v[RigPose.HAND_R] as Vector3).is_equal_approx(base.v[RigPose.HAND_R]), "returns to base")
	AnimLibrary.unregister(&"test_custom_move")
	AnimLibrary.unregister(&"test_custom_alias")


func test_mirror_and_spin_blending() -> void:
	var p := RigPose.new()
	p.v[RigPose.HAND_R] = Vector3(0.3, 0.1, 0.8)
	p.v[RigPose.CHEST] = Vector3(5, 20, -4)
	p.v[RigPose.HIPS] = Vector3(0.1, -0.1, 0.0)
	var q := p.duplicate_pose()
	q.mirror()
	expect((q.v[RigPose.HAND_L] as Vector3).is_equal_approx(Vector3(0.3, 0.1, 0.8)), "hands swap")
	expect((q.v[RigPose.CHEST] as Vector3).is_equal_approx(Vector3(5, -20, 4)), "yaw/roll flip")
	q.mirror()
	expect((q.v[RigPose.HIPS] as Vector3).is_equal_approx(p.v[RigPose.HIPS]), "mirror twice is identity")
	# A 360 degree spin key next to the base must not unwind.
	var spin := AnimClip.compile(&"t_spin", {"length": 1.0, "keys": [[0.2, {"hips_rot": Vector3(0, 0, 0)}], [0.8, {"hips_rot": Vector3(0, 360, 0)}]]})
	var base := RigPose.new()
	var out := RigPose.new()
	spin.evaluate(0.9, base, out)
	var yaw: float = (out.v[RigPose.HIPS_ROT] as Vector3).y
	expect(absf(wrapf(yaw, -180.0, 180.0)) < 1.0, "spin end stays at a full turn (yaw %.1f)" % yaw)
	spin.evaluate(0.5, base, out)
	var mid: float = (out.v[RigPose.HIPS_ROT] as Vector3).y
	expect(mid > 120.0 and mid < 250.0, "mid spin %.1f" % mid)


func test_action_events_fire_on_time() -> void:
	var rig := _make({"preset": &"fire_nation"})
	_step(rig, 0.2)
	var log: Array = []
	rig.action_event.connect(func(clip: StringName, ev: StringName) -> void: log.append([clip, ev, rig.action_progress()]))
	var finished: Array = []
	rig.action_finished.connect(func(clip: StringName) -> void: finished.append(clip))
	var clip := AnimLibrary.get_clip(&"fire_jab_r")
	var dur := rig.play_action(&"fire_jab_r", {"speed": 1.0})
	expect_near(dur, clip.length, 0.0001, "duration returned")
	expect(rig.is_playing_action() and rig.current_action() == &"fire_jab_r", "playing")
	_step(rig, dur + 0.1)
	expect_eq(log.size(), clip.events.size(), "every event fired once")
	var tol := (1.0 / 60.0) / clip.length + 0.001
	for e: Array in log:
		var et := clip.event_time(e[1])
		expect(float(e[2]) >= et - 0.0001 and float(e[2]) <= et + tol, "%s at %.3f (expected %.3f)" % [e[1], e[2], et])
	expect_eq(finished, [&"fire_jab_r"], "finished signal")
	expect(not rig.is_playing_action(), "action done")
	# Speed scales duration; mirror plays the other side.
	expect_near(rig.play_action(&"jab_r", {"speed": 2.0}), AnimLibrary.get_clip(&"jab_r").length / 2.0, 0.0001)
	rig.stop_action(0.0)
	expect(not rig.is_playing_action(), "stopped")
	expect_eq(rig.play_action(&"does_not_exist"), 0.0, "unknown clip returns 0")


func test_stride_matches_speed_and_feet_do_not_slide() -> void:
	for speed in [1.4, 3.0, 5.0]:
		var rig := _make({"preset": &"villager_earth"})
		_step(rig, 0.3)
		var loco := rig.animator.loco
		var plants: Array = []
		loco.planted.connect(func(side: int, pos: Vector3, _y: float, _w: float) -> void: plants.append([side, pos]))
		var vel := Vector3(0, 0, -speed)
		_step(rig, 1.5, vel)
		plants.clear()
		var max_slide := 0.0
		var locked: Array = [null, null]
		for i in 240:
			rig.position += vel / 60.0
			rig.set_locomotion(vel, true)
			rig.advance(1.0 / 60.0)
			# From mid-stance to toe-off the ball of the foot is the contact
			# point: it must stay fixed in world space (no sliding).
			for side in 2:
				var ball := rig.get_bone_world(SK.NAMES[SK.TOES[side]]).origin
				var stance_t := loco._foot_phase(side) / maxf(loco.duty, 0.01)
				if loco.is_planted[side] and stance_t > 0.45 and stance_t <= 1.0:
					if locked[side] == null:
						locked[side] = ball
					else:
						max_slide = maxf(max_slide, Vector2(ball.x - (locked[side] as Vector3).x, ball.z - (locked[side] as Vector3).z).length())
				else:
					locked[side] = null
		# Stride = distance between consecutive plants of the same foot.
		var strides: Array = []
		for side in 2:
			var last: Variant = null
			for pl: Array in plants:
				if pl[0] != side:
					continue
				if last != null:
					strides.append((pl[1] as Vector3).distance_to(last))
				last = pl[1]
		var avg := 0.0
		for s: float in strides:
			avg += s
		avg /= maxf(strides.size(), 1)
		var expected: float = speed / loco.cadence
		expect(strides.size() >= 2, "plants recorded at %.1f m/s" % speed)
		expect_near(avg, expected, expected * 0.12, "stride at %.1f m/s" % speed)
		expect(max_slide < 0.02, "planted ball-of-foot drift %.3f m at %.1f m/s" % [max_slide, speed])
		rig.queue_free()


func test_footstep_count_over_walk_cycles() -> void:
	_steps.clear()
	var cb := func(actor: Node3D, pos: Vector3, yaw: float, size: float, weight: float, surface: StringName) -> void:
		_steps.append([actor, pos, yaw, size, weight, surface])
	Events.footstep.connect(cb)
	var body := Node3D.new()
	add_child(body)
	var rig := HumanoidRig.create({"preset": &"water_tribe"})
	rig.manual_update = true
	body.add_child(rig)
	for i in 30:
		rig.set_locomotion(Vector3.ZERO, true)
		rig.advance(1.0 / 60.0)
	_steps.clear()
	var vel := Vector3(0, 0, -1.4)
	var secs := 4.0
	for i in int(secs * 60.0):
		body.position += vel / 60.0
		rig.set_locomotion(vel, true)
		rig.advance(1.0 / 60.0)
	var cad := rig.animator.loco.cadence
	var expected := 2.0 * cad * secs
	Events.footstep.disconnect(cb)
	expect(absf(_steps.size() - expected) <= 2.0, "footsteps %d ~ %.1f expected" % [_steps.size(), expected])
	if not _steps.is_empty():
		var s: Array = _steps[_steps.size() - 1]
		expect(s[0] == body, "actor is the owner body")
		expect_near(float(s[3]), 0.26, 0.04, "foot length")
		expect(float(s[4]) >= 0.5 and float(s[4]) <= 1.4, "walk weight %.2f" % s[4])
		expect_eq(s[5], &"grass", "surface from WorldData")
		# The footprint lies within a step of the body, on the ground.
		expect(absf((s[1] as Vector3).y) < 0.01, "on the ground")
		expect(Vector2((s[1] as Vector3).x - body.position.x, (s[1] as Vector3).z - body.position.z).length() < 1.2, "near the body")


func test_pose_states_and_reactions() -> void:
	var rig := _make({"preset": &"earth_soldier"})
	_step(rig, 0.2)
	rig.set_pose_state(&"airborne")
	expect_eq(rig.get_pose_state(), &"airborne")
	_step(rig, 0.2)
	rig.land(12.0)
	expect_eq(rig.current_action(), &"land_heavy", "heavy landing")
	expect_eq(rig.get_pose_state(), &"normal")
	_step(rig, 1.0)
	var d := rig.play_reaction(HitInfo.Reaction.KNOCKDOWN, -rig.global_basis.z * -1.0)
	expect(d > 0.0, "knockdown clip plays")
	expect(rig.current_action() in [&"knockdown_back", &"knockdown_front"], "knockdown variant")
	_step(rig, d + 0.1)
	expect_eq(rig.get_pose_state(), &"knocked_down", "lands in the down state")
	var g := RigReactions.get_up(rig)
	expect(g > 0.0 and rig.current_action() == &"getup", "gets up")
	_step(rig, g + 0.1)
	expect_eq(rig.get_pose_state(), &"normal")
	# Flinch is additive and does not interrupt an action.
	rig.play_action(&"jab_r")
	expect_eq(rig.play_reaction(&"flinch", Vector3(1, 0, 0)), 0.0)
	expect_eq(rig.current_action(), &"jab_r", "flinch keeps the action")
	rig.set_pose_state(&"blocking")
	_step(rig, 0.3)
	expect_eq(rig.get_pose_state(), &"blocking")
	rig.set_pose_state(&"normal")
	expect(not rig.animator.set_pose_state(&"not_a_state"), "unknown state rejected")


func test_sockets_follow_bones() -> void:
	var rig := _make({"preset": &"air_nomad"})
	_step(rig, 0.1)
	for n in HumanoidRig.SOCKETS:
		var s := rig.get_socket(StringName(n))
		expect(s != null and s.get_parent() is BoneAttachment3D, "socket %s" % n)
	var hand := rig.get_socket(&"hand_r")
	rig.play_action(&"jab_r", {"blend_in": 0.0, "start": AnimLibrary.get_clip(&"jab_r").event_time(&"impact")})
	rig.animator.paused = true
	rig.advance(0.0)
	await frames(2)
	var solver_hand := rig.get_bone_world("hand_r").origin
	expect(hand.global_position.distance_to(solver_hand) < 0.2, "hand socket follows the animated hand")
	expect(hand.global_position.z < -0.35, "hand extended forward on the jab (z=%.2f)" % hand.global_position.z)


func test_robe_panels_follow_legs() -> void:
	var rig := _make({"preset": &"monk_elder"})
	_step(rig, 0.2)
	var s := rig.animator.solver
	var bl := rig.get_bone_index(&"skirt_bl")
	var fl := rig.get_bone_index(&"skirt_fl")
	expect(bl >= 0 and fl >= 0, "robe has quadrant panels")
	expect(s.local_scale[bl].y > 0.99, "standing: full-length robe")
	rig.play_action(&"sit_loop", {"blend_in": 0.0})
	_step(rig, 0.5)
	expect(absf(s.thigh_abduct[0]) < 0.5, "thighs forward are not read as spread (%.2f)" % s.thigh_abduct[0])
	expect(s.local_scale[bl].y < 0.85, "seated: long robe tucked (%.2f)" % s.local_scale[bl].y)
	var back_dir := -s.g_basis[bl].y  # panel hangs along its -Y
	expect(back_dir.z < 0.2, "seated: back panel folds under the thighs, not out behind (z=%.2f)" % back_dir.z)
	var front_dir := -s.g_basis[fl].y
	expect(front_dir.z < -0.6, "seated: front panel lies over the lap (z=%.2f)" % front_dir.z)


func test_props_attach_and_carry_pose() -> void:
	var guard := _make({"preset": &"guard"})
	var spear := guard.get_prop(&"hand_r")
	expect(spear != null, "guard preset carries a spear")
	expect(guard.animator.grip[1] > 0.5 and guard.animator.hold_clips[1] != null, "grip + carry pose on the right hand")
	expect_eq(AnimLibrary.get_clip(&"hold_pole_l").mask_name, &"arm_l")
	expect(_make({"preset": &"air_nomad"}).get_prop(&"back") != null, "air nomad staff on the back")
	_step(guard, 0.6)
	await frames(2)
	var up := spear.global_basis.y.normalized()
	expect(up.y > 0.8, "spear carried upright (up.y=%.2f)" % up.y)
	expect(spear.global_position.distance_to(guard.get_socket(&"hand_r").global_position) < 0.05, "prop rides the hand socket")
	_step(guard, 1.0, Vector3(0, 0, -1.4))
	await frames(1)
	expect(spear.global_basis.y.normalized().y > 0.7, "still upright while walking")
	guard.detach_prop(&"hand_r")
	expect(guard.get_prop(&"hand_r") == null and guard.animator.grip[1] == 0.0 and guard.animator.hold_clips[1] == null, "detach releases the hand")
	var custom := Node3D.new()
	expect(guard.attach_prop(custom, &"hand_l") == custom and custom.get_parent() == guard.get_socket(&"hand_l"), "custom node props")
	for n in RigProps.NAMES:
		var p := RigProps.make(StringName(n))
		expect(p.get_child_count() > 0, "prop %s has meshes" % n)
		p.free()


func test_root_motion_and_lod() -> void:
	var rig := _make({"preset": &"air_nomad"})
	_step(rig, 0.1)
	var d := rig.play_action(&"dodge_roll", {"root_motion": true})
	_step(rig, d)
	var rm := rig.consume_root_motion()
	expect(rm.z < -2.0, "roll travels forward (%.2f)" % rm.z)
	expect(rig.consume_root_motion().length() < 0.001, "consumed")
	rig.set_lod(2)
	expect_eq(rig.lod, 2)
	expect(not rig.animator.secondary.enabled, "secondary motion off at LOD 2")
	expect(not rig.auto_lod, "manual LOD disables auto")
	rig.flash_hit()
	rig.set_status_tint(Color(0.6, 0.85, 1.0), 0.5)
	expect(rig.mesh_instance.get_surface_override_material(0) != null, "unique material for feedback")


func test_look_at_turns_head() -> void:
	var rig := _make({"preset": &"villager_fire"})
	_step(rig, 0.3)
	var before := rig.get_bone_world("head").basis.z
	rig.look_at_point(rig.global_position + Vector3(-3, 1.6, -0.5), 1.0)
	_step(rig, 1.2)
	var after := rig.get_bone_world("head").basis.z
	expect(after.angle_to(before) > deg_to_rad(20.0), "head turned toward the target")
	rig.clear_look_at()


func test_style_changes_body_language() -> void:
	var air := _make({"preset": &"air_nomad", "style": &"earth"})
	var earth := _make({"preset": &"air_nomad", "style": &"air"})
	for r in [air, earth]:
		r.set_combat_stance(true)
	_step(air, 1.0)
	_step(earth, 1.0)
	var w_earth := absf((air.animator.final.v[RigPose.FOOT_L] as Vector3).x)
	var w_air := absf((earth.animator.final.v[RigPose.FOOT_L] as Vector3).x)
	expect(w_earth > w_air + 0.1, "earth horse stance is wider than the air stance")
	var hips_e: float = (air.animator.final.v[RigPose.HIPS] as Vector3).y
	expect(hips_e < -0.1, "earth stance is low")


func test_update_cost_budget() -> void:
	var rigs: Array[HumanoidRig] = []
	for i in 12:
		var r := _make({"preset": [&"villager_earth", &"water_tribe", &"fire_soldier"][i % 3], "seed": i})
		r.position = Vector3(float(i % 4) * 1.5, 0, float(i / 4) * 1.5)
		rigs.append(r)
	for r in rigs:
		_step(r, 0.2)
	var t0 := Time.get_ticks_usec()
	for f in 60:
		for r in rigs:
			r.position += Vector3(0, 0, -1.4) / 60.0
			r.set_locomotion(Vector3(0, 0, -1.4), true)
			r.advance(1.0 / 60.0)
	var full_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 60.0 / rigs.size()
	for r in rigs:
		r.set_lod(2)
	t0 = Time.get_ticks_usec()
	for f in 60:
		for r in rigs:
			r.position += Vector3(0, 0, -1.4) / 60.0
			r.set_locomotion(Vector3(0, 0, -1.4), true)
			r.advance(1.0 / 60.0)
	var far_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 60.0 / rigs.size()
	print("rig update cost: LOD0 %.3f ms, LOD2 %.3f ms per rig per frame" % [full_ms, far_ms])
	expect(far_ms < full_ms, "LOD2 is cheaper than LOD0")
	expect(full_ms < 3.0, "LOD0 rig update under 3 ms on the CI machine (%.2f)" % full_ms)
