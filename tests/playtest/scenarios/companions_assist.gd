extends RefCounted
## Companion combat assist in the enemy arena: a bandit group engages the (invulnerable,
## blocking) player and the element's companion joins in with its move — dragon fire
## breath, sky bison tail gust, polar bear dog pounce, badgermole tremor. Observer shots of
## the wind-up and the strike, checks that real hits land (credited to the player) and that
## the cooldown holds. SPECIES=<id> limits it to one.

const E := ElementDefs.Element

var p: Playtest
var arena: Node
var pl: PlayerCharacter
var c: Companion
var cam: Camera3D
var hits: Array = []


func run(pt: Playtest) -> void:
	p = pt
	var only := OS.get_environment("SPECIES")
	for pair: Array in [[&"dragon", E.FIRE], [&"sky_bison", E.AIR], [&"polar_bear_dog", E.WATER], [&"badgermole", E.EARTH]]:
		if only != "" and String(pair[0]) != only:
			continue
		await _assist(pair[0], pair[1])


func _assist(species: StringName, e: int) -> void:
	var tag := String(species)
	GameState.new_game(e)
	arena = await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": e, "enemies": [&"bandit_brawler", &"bandit_skirmisher"]})
	await p.wait_game(0.5)
	pl = arena.get("player")
	pl.camera_rig.require_capture = false
	pl.health.invulnerable = true
	c = Companion.create(species)
	c.player = pl
	arena.add_child(c)
	var side := pl.global_transform.basis.x
	c.motor.teleport(pl.global_position - side * (c.prof.f(c.prof.follow, "side") + 1.0) + pl.global_transform.basis.z * 2.0, pl.rotation.y)
	c.rig.reset_feet()
	pl.companion = c
	c.assist.cooldown_left = 0.0
	cam = Camera3D.new()
	cam.fov = 55.0
	arena.add_child(cam)
	hits.clear()
	var cb := func(hit: HitInfo, target: Node, result: int) -> void:
		if String(hit.ability_id).begins_with("companion_"):
			hits.append([hit, target, result])
	Events.hit_landed.connect(cb)
	var ens: Array = arena.get("enemies")
	for en: EnemyBase in ens:
		en.brain.engage(pl)
	# Wait for the move.
	var ok := await p.wait_until(func() -> bool: return c.assist.phase == CompanionAssist.Phase.ACT, 40.0)
	p.check(ok, "%s starts its assist move (%s)" % [tag, c.get_mode_name()])
	await p.wait_game(_windup_time(species))
	await _observe("%s_1_windup" % tag)
	ok = await p.wait_until(func() -> bool: return not hits.is_empty(), 20.0)
	p.check(ok, "%s lands a hit" % tag)
	await _observe("%s_2_strike" % tag)
	await p.wait_game(0.4)
	await _observe("%s_3_after" % tag)
	Events.hit_landed.disconnect(cb)
	if not hits.is_empty():
		var h: HitInfo = hits[0][0]
		p.check(h.source == pl and h.team == Combat.Team.PLAYER, "%s hit credited to the player" % tag)
		p.check(int(hits[0][2]) in [Combat.Result.HIT, Combat.Result.KILLED, Combat.Result.BLOCKED], "%s hit result %d" % [tag, int(hits[0][2])])
		p.note("%s: %d hit(s), first %.1f dmg reaction %d" % [tag, hits.size(), h.damage, h.reaction])
	await p.wait_game(2.0)
	p.check(c.assist.cooldown_left > 0.0 or c.assist.phase != CompanionAssist.Phase.NONE, "%s cooldown running (%.1f s)" % [tag, c.assist.cooldown_left])
	c.queue_free()
	await p.frames(2)


func _windup_time(species: StringName) -> float:
	match species:
		&"dragon":
			return 0.9
		&"sky_bison":
			return 0.55
		&"polar_bear_dog":
			return 0.45
		&"badgermole":
			return 0.75
	return 0.5


## Three-quarter view framing the companion and its target.
func _observe(shot_name: String) -> void:
	var tgt := c.assist.target
	var a := c.global_position + Vector3.UP * c.prof.body_height() * 0.5
	var b := tgt.global_position + Vector3.UP * 1.0 if tgt != null and is_instance_valid(tgt) else a + CompanionNav.dir_of(c.motor.yaw) * 6.0
	var mid := a.lerp(b, 0.45)
	var span := maxf(a.distance_to(b), c.prof.radius() * 3.0)
	var line := CompanionNav.flat_dir(b - a)
	if line == Vector3.ZERO:
		line = CompanionNav.dir_of(c.motor.yaw)
	var side := Vector3(-line.z, 0.0, line.x)
	var pos := mid + side * (span * 1.1 + 5.0) + Vector3.UP * (2.0 + span * 0.25) - line * span * 0.25
	cam.global_position = pos
	cam.look_at(mid, Vector3.UP)
	cam.make_current()
	await p.frames(1)
	await p.screenshot(shot_name)
	pl.camera_rig.make_current()
