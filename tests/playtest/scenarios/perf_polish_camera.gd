extends RefCounted
## Camera polish (perf_polish, docs/qa/perf_polish.md):
##
## 1. Lock-on in close quarters. A bandit brawler (melee) fights the invulnerable player in the
##    enemy arena while the player is locked on, once with the close-quarters framing off (the
##    old camera: straight behind the player) and once on. Every frame records the separation,
##    whether the attacker's chest is hidden behind the player's body (the sight line camera ->
##    attacker passing through the player's capsule), whether it is on screen, and the camera
##    yaw (jitter = yaw-rate reversals). Shots: camera_lock_<off|on>_<n>.
## 2. Occluders. An NPC, then the companion, stand on the line camera -> player: they dither
##    out (OccluderFader) instead of blocking the view, and come back when they step away.
##    Shots: camera_occluder_npc, camera_occluder_companion, camera_occluder_clear.
##
## Run: tools/playtest.sh perf_polish_camera .playtest/cam 960x540

const E := ElementDefs.Element
## Body radius used for the "hidden behind the player" test (capsule 0.32 m + arms / robes).
const BODY_RADIUS := 0.42

var p: Playtest
var report := {}


func run(pt: Playtest) -> void:
	p = pt
	if OS.get_environment("PART") == "occluders":
		await _occluders()
		return
	var off := await _lock_fight(false)
	var on := await _lock_fight(true)
	report["lock_off"] = off
	report["lock_on"] = on
	p.note("close lock-on (< 3.5 m): attacker visible %.0f %% of frames without the framing, %.0f %% with it" % [
			100.0 * float(off["visible_share"]), 100.0 * float(on["visible_share"])])
	p.note("yaw-rate reversals per second: off %.2f, on %.2f; largest yaw step on %.2f deg" % [
			off["reversals_per_s"], on["reversals_per_s"], on["max_step_deg"]])
	p.check(int(on["close_frames"]) >= 30, "the brawler fought at close range (%d close frames)" % on["close_frames"])
	p.check(float(on["visible_share"]) >= 0.85, "close attacker visible with the framing (%.0f %%)" % (100.0 * float(on["visible_share"])))
	p.check(float(on["visible_share"]) >= float(off["visible_share"]), "the framing shows the attacker at least as often as before")
	p.check(float(on["reversals_per_s"]) <= float(off["reversals_per_s"]) + 0.5, "no added jitter (yaw reversals %.2f/s vs %.2f/s)" % [on["reversals_per_s"], off["reversals_per_s"]])
	p.check(float(on["max_step_deg"]) < 8.0, "no camera snap (largest yaw step %.2f deg)" % on["max_step_deg"])
	await _occluders()
	var f := FileAccess.open(p.out_dir.path_join("camera.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))


func _lock_fight(framing: bool) -> Dictionary:
	var tag := "on" if framing else "off"
	GameState.new_game(E.FIRE, true)
	var arena := await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": E.FIRE, "enemies": [&"bandit_brawler"], "no_warmup": true})
	await p.wait_game(0.6)
	var pl := arena.get("player") as PlayerCharacter
	pl.camera_rig.require_capture = false
	pl.health.invulnerable = true
	pl.camera_rig.close_framing = framing
	if pl.companion != null and is_instance_valid(pl.companion):
		pl.companion.queue_free()      # the dragon would join the fight (and the occluder test)
	var ens: Array = arena.get("enemies")
	var en := ens[0] as EnemyBase
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.3)
	p.tap(&"lock_on")
	await p.wait_game(0.3)
	p.check(pl.targeting.lock_target == en, "%s: locked on the brawler" % tag)
	en.brain.engage(pl)
	var cam := pl.camera_rig.camera
	var vp := cam.get_viewport().get_visible_rect().size
	var close := 0
	var visible := 0
	var yaws: Array[float] = []
	var shots := 0
	var t := 0.0
	var next_shot := 2.5
	while t < 9.0:
		await p.frames(1)
		var dt := p.get_tree().root.get_process_delta_time()
		t += dt
		if not is_instance_valid(en) or pl.targeting.lock_target == null:
			if is_instance_valid(en) and en.is_alive():
				pl.targeting.lock(en)
			continue
		var sep := Vector2(en.global_position.x - pl.global_position.x, en.global_position.z - pl.global_position.z).length()
		yaws.append(pl.camera_rig.get_yaw())
		if sep > 3.5:
			continue
		close += 1
		var cpos := cam.global_position
		var tp := BendingContext.target_point(en)
		var hidden := _segment_distance(cpos, tp, pl.global_position + Vector3.UP * 0.25, pl.global_position + Vector3.UP * 1.65) < BODY_RADIUS
		var on_screen := not cam.is_position_behind(tp)
		if on_screen:
			var s := cam.unproject_position(tp)
			on_screen = s.x > 0.0 and s.y > 0.0 and s.x < vp.x and s.y < vp.y
		if on_screen and not hidden:
			visible += 1
		if t >= next_shot and shots < 2 and sep < 2.8:
			shots += 1
			next_shot = t + 3.0
			await p.screenshot("camera_lock_%s_%d" % [tag, shots])
	# jitter: yaw-rate sign reversals (both steps over 0.15 deg)
	var reversals := 0
	var max_step := 0.0
	var prev := 0.0
	for i in range(1, yaws.size()):
		var step := angle_difference(yaws[i - 1], yaws[i])
		max_step = maxf(max_step, absf(rad_to_deg(step)))
		if absf(step) > deg_to_rad(0.15):
			if prev != 0.0 and signf(step) != signf(prev):
				reversals += 1
			prev = step
	var out := {"close_frames": close, "visible_frames": visible, "visible_share": float(visible) / maxf(1.0, close),
		"reversals_per_s": reversals / maxf(1.0, t), "max_step_deg": max_step, "shots": shots}
	p.note("%s: %s" % [tag, str(out)])
	pl.targeting.unlock()
	return out


func _occluders() -> void:
	GameState.new_game(E.WATER, true)
	var arena := await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": E.WATER, "enemies": [], "spawn": false, "no_warmup": true})
	await p.wait_game(0.6)
	var pl := arena.get("player") as PlayerCharacter
	pl.camera_rig.require_capture = false
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, -2)))
	await p.wait_game(0.3)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.8)
	var fader := pl.camera_rig.occluders
	var cam := pl.camera_rig.camera
	# 1.4 m in front of the player (closer to the lens the NPC's own near-camera fade takes over)
	var mid := cam.global_position.lerp(pl.global_position, 0.62)
	var npc := NpcCharacter.create({"key": &"perf_polish_npc", "pos": Vector3(mid.x, 0.0, mid.z), "yaw": PI,
		"look": {"preset": &"villager_water"}})
	arena.add_child(npc)
	npc.set_physics_process(false)     # stands still (no routine without a director)
	await p.wait_game(0.8)
	var f_npc := fader.fade_of(npc)
	p.note("NPC on the camera line: fade %.2f, faded bodies %d" % [f_npc, fader.faded_bodies().size()])
	p.check(f_npc > 0.5, "the NPC between camera and player dithers out (%.2f)" % f_npc)
	await p.screenshot("camera_occluder_npc")
	report["npc_fade"] = f_npc
	npc.global_position = Vector3(6, 0, -8)
	await p.wait_game(0.8)
	p.check(fader.fade_of(npc) == 0.0, "the NPC comes back once off the line")
	var restored := true
	if npc.rig and npc.rig.mesh_instance:
		for s in npc.rig.mesh_instance.get_surface_override_material_count():
			var m := npc.rig.mesh_instance.get_surface_override_material(s) as ShaderMaterial
			if m != null and m.shader == OccluderFader.TOON_DITHER:
				restored = false
	p.check(restored, "the NPC's own materials are back")
	# the companion (a creature shader: instance uniform occlusion_fade)
	var c := pl.companion as Companion
	if c == null or not is_instance_valid(c):
		c = Companion.create(&"polar_bear_dog")
		c.player = pl
		arena.add_child(c)
		pl.companion = c
	await p.wait_game(0.3)
	Events.companion_command.emit(&"stay")
	await p.wait_game(0.2)
	var cmid := cam.global_position.lerp(pl.global_position, 0.5)
	c.motor.teleport(Vector3(cmid.x, 0.0, cmid.z), pl.rotation.y + PI * 0.5)
	await p.wait_game(1.0)
	var f_c := fader.fade_of(c)
	p.note("companion (%s) on the camera line: fade %.2f" % [c.species, f_c])
	p.check(f_c > 0.5, "the companion between camera and player dithers out (%.2f)" % f_c)
	await p.screenshot("camera_occluder_companion")
	report["companion_fade"] = f_c
	c.motor.teleport(pl.global_position + Vector3(3.5, 0.0, 0.5), pl.rotation.y)
	await p.wait_game(1.0)
	p.check(fader.fade_of(c) == 0.0, "the companion comes back once off the line")
	await p.screenshot("camera_occluder_clear")
	Events.companion_command.emit(&"follow")


## Shortest distance between segments a0-a1 and b0-b1.
static func _segment_distance(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
	var pts := Geometry3D.get_closest_points_between_segments(a0, a1, b0, b1)
	return (pts[0] as Vector3).distance_to(pts[1])
