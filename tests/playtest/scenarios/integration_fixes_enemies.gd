extends RefCounted
## Enemy bender variety (enemy arena, the real AI against a passive, invulnerable player):
## each bender archetype - firebender soldier, rogue earthbender, rogue waterbender, the new
## renegade airbender, the fire lieutenant - duels alone while the player shifts between close
## and mid range, then all four benders fight together. Logs every telegraph and cast,
## checks that each bender mixes its element techniques (kit scripts, enemy-tuned) with its
## basic attacks, telegraphs them, and that the attack-token cap holds in the group.
## Observer-camera screenshots the first time each technique is cast. ARCH=a,b to limit.

const E := ElementDefs.Element
const TECH: Array[StringName] = [&"enemy_fire_burst", &"enemy_fire_ring", &"enemy_fire_whip", &"enemy_earth_pillar", &"enemy_earth_stomp",
	&"enemy_earth_spikes", &"enemy_water_surge", &"enemy_ice_trap", &"enemy_ice_wall", &"enemy_air_push", &"enemy_air_sweep", &"enemy_wind_blade",
	&"enemy_flame_sweep", &"enemy_earth_wall", &"enemy_ice_shards"]

var p: Playtest
var arena: Node
var pl: PlayerCharacter
var cam: Camera3D
var shots := {}


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.EARTH, true)
	arena = await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": E.EARTH, "spawn": false})
	await p.wait_game(0.4)
	pl = p.player() as PlayerCharacter
	pl.camera_rig.require_capture = false
	pl.health.invulnerable = true
	cam = Camera3D.new()
	cam.fov = 55.0
	arena.add_child(cam)
	var only := OS.get_environment("ARCH")
	var all: Array[StringName] = [&"fire_soldier", &"earth_rogue", &"water_pirate", &"air_renegade", &"fire_captain"]
	var variety := {}
	for arch in all:
		if only != "" and not only.split(",").has(String(arch)):
			continue
		variety[arch] = await _duel(arch)
	if only == "":
		await _group()
	var lines: Array[String] = []
	for k: StringName in variety:
		lines.append("%s %s" % [k, str(variety[k])])
	p.note("VARIETY | " + " | ".join(lines))


## One bender alone for ~26 s of game time; returns {cast id: count}.
func _duel(arch: StringName) -> Dictionary:
	p.note("--- duel: %s ---" % arch)
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	pl.camera_rig.snap_behind(pl)
	var es: Array = arena.call("spawn_group", [arch], [Vector3(0, 0, -7.5)])
	var e: EnemyBase = es[0]
	var casts := {}
	var tells: Array = []
	e.controller.ability_started.connect(func(ab: BendingAbility) -> void:
		casts[ab.def.id] = int(casts.get(ab.def.id, 0)) + 1)
	e.attack_telegraphed.connect(func(_en: EnemyBase, at: Dictionary, secs: float) -> void:
		tells.append("%s %.2f" % [at.get("id", &"?"), secs]))
	var t := 0.0
	var phase := 0
	while t < 26.0:
		await p.wait_game(0.1)
		t += 0.1
		# shift between close (techniques that clear space) and mid range every 4 s
		if int(t / 4.0) != phase:
			phase = int(t / 4.0)
			var want := 2.4 if phase % 2 == 1 else 7.5
			var to := pl.global_position - e.global_position
			to.y = 0.0
			var dir := to.normalized() if to.length() > 0.5 else Vector3.BACK
			pl.teleport(Transform3D(pl.global_basis, e.global_position + dir * want))
		if pl.states.state == PlayerCharacter.State.KNOCKED_DOWN or pl.states.state == PlayerCharacter.State.HITSTUN:
			pass
		var cur := e.controller.current
		if cur != null and TECH.has(cur.def.id) and not shots.has(cur.def.id) and cur.time > 0.22:
			shots[cur.def.id] = true
			await _obs("integration_fixes_enemy_%s_%s" % [arch, String(cur.def.id).trim_prefix("enemy_")], e, cur.def.id)
	p.note("%s casts %s" % [arch, str(casts)])
	p.note("%s telegraphs %s" % [arch, ", ".join(tells.slice(0, 14))])
	var techs := 0
	for id: StringName in casts:
		if TECH.has(id):
			techs += 1
	p.check(casts.size() >= 3, "%s mixed %d different attacks" % [arch, casts.size()])
	p.check(techs >= 1, "%s used its element techniques (%d)" % [arch, techs])
	p.check(not tells.is_empty(), "%s telegraphed its attacks" % arch)
	arena.call("clear_enemies")
	await p.wait_game(0.5)
	return casts


## Four benders together: varied techniques, at most two attacking at once (tokens).
func _group() -> void:
	p.note("--- group ---")
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	pl.camera_rig.snap_behind(pl)
	var es: Array = arena.call("spawn_group", [&"fire_soldier", &"earth_rogue", &"water_pirate", &"air_renegade"])
	var casts := {}
	var max_attacking := 0
	for e: EnemyBase in es:
		e.controller.ability_started.connect(func(ab: BendingAbility) -> void: casts[ab.def.id] = int(casts.get(ab.def.id, 0)) + 1)
	var t := 0.0
	var shot := false
	while t < 24.0:
		await p.wait_game(0.1)
		t += 0.1
		var attacking := 0
		for e: EnemyBase in es:
			if is_instance_valid(e) and e.state == EnemyBase.State.ATTACK:
				attacking += 1
		max_attacking = maxi(max_attacking, attacking)
		if not shot and t > 6.0 and attacking >= 1:
			shot = true
			cam.look_at_from_position(Vector3(9.0, 6.0, 6.0), Vector3(0, 1.0, -6.0), Vector3.UP)
			cam.make_current()
			await p.wait_game(0.05)
			await p.screenshot("integration_fixes_enemy_group")
			pl.camera_rig.make_current()
	var techs := 0
	for id: StringName in casts:
		if TECH.has(id):
			techs += 1
	p.note("group casts %s, max attacking at once %d" % [str(casts), max_attacking])
	p.check(techs >= 3, "the group used %d different element techniques" % techs)
	p.check(max_attacking <= 2, "at most two attacked at once (%d)" % max_attacking)
	arena.call("clear_enemies")


func _obs(shot: String, e: EnemyBase, id: StringName) -> void:
	var a := e.global_position + Vector3.UP
	var b := pl.global_position + Vector3.UP
	var mid := a.lerp(b, 0.5)
	var f := b - a
	f.y = 0.0
	var fwd := f.normalized() if f.length() > 0.3 else Vector3.BACK
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var d := maxf(6.0, a.distance_to(b) * 0.9 + 4.0)
	cam.look_at_from_position(mid + right * d + Vector3.UP * 2.6, mid, Vector3.UP)
	cam.make_current()
	await p.wait_game(0.05)
	await p.screenshot(shot)
	p.note("shot %s (%s)" % [shot, id])
	pl.camera_rig.make_current()
