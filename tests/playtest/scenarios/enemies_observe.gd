extends RefCounted
## Watches an enemy group fight an idle (or blocking) player in the enemy arena and
## logs every state change / telegraph / strike with game time, taking screenshots
## at the first telegraph and strike of each enemy.
## ENEMIES="fire_soldier,bandit_archer" ELEMENT=earth DURATION=12 BLOCK=1 SHOTS=1
var t0 := 0
var p: Playtest
var shots_taken: Dictionary = {}


func run(pt: Playtest) -> void:
	p = pt
	var ids: Array = []
	for s in OS.get_environment("ENEMIES").split(",", false):
		ids.append(StringName(s.strip_edges()))
	if ids.is_empty():
		ids = [&"bandit_brawler", &"bandit_skirmisher", &"bandit_archer"]
	var el := ElementDefs.from_id(StringName(OS.get_environment("ELEMENT"))) if OS.get_environment("ELEMENT") != "" else ElementDefs.Element.FIRE
	GameState.new_game(el, true)
	var arena: Node = await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": el, "enemies": ids})
	var player: PlayerCharacter = arena.get("player")
	player.camera_rig.require_capture = false
	player.resources.infinite_chi = true
	var god := OS.get_environment("GOD") != ""
	if god:
		player.health.invulnerable = true
	await p.wait_game(0.2)
	t0 = Engine.get_physics_frames()
	for e: EnemyBase in arena.get("enemies"):
		var en := e
		e.state_changed.connect(func(n: int, o: int) -> void:
			_log("%s %s -> %s" % [en.display_name, EnemyBase.STATE_NAMES[o], EnemyBase.STATE_NAMES[n]]))
		e.attack_telegraphed.connect(func(_e: EnemyBase, a: Dictionary, s: float) -> void:
			_log("%s TELEGRAPH %s (%.2fs)" % [en.display_name, a.get("id"), s])
			_shot("tele_%s_%s" % [en.archetype_id, a.get("id")]))
		e.attack_struck.connect(func(_e: EnemyBase, a: Dictionary) -> void:
			_log("%s STRIKE %s" % [en.display_name, a.get("id")])
			_shot("strike_%s_%s" % [en.archetype_id, a.get("id")]))
	Events.hit_landed.connect(func(hit: HitInfo, target: Node, result: int) -> void:
		_log("HIT %s -> %s %s dmg %.1f %s" % [hit.ability_id, target.name, Combat.Result.keys()[result], hit.damage, HitInfo.Reaction.keys()[hit.reaction]]))
	var dur := float(OS.get_environment("DURATION")) if OS.get_environment("DURATION") != "" else 10.0
	var block := OS.get_environment("BLOCK") != ""
	var t := 0.0
	while t < dur:
		if block:
			p.hold(&"block")
		await p.wait_game(0.5)
		t += 0.5
		if int(t * 2) % 4 == 0:
			player.camera_rig.snap_behind(player)
	p.release(&"block")
	await p.screenshot("observe_end")
	for e: EnemyBase in arena.get("enemies"):
		if is_instance_valid(e):
			_log("%s at %s bar %s visible %s rig %s" % [e.display_name, e.global_position, e.bar.global_position, e.bar.visible, e.visual.node().global_position])
	var alive := 0
	for e: EnemyBase in arena.get("enemies"):
		if is_instance_valid(e) and e.is_alive():
			alive += 1
	_log("player health %.1f / %.1f, alive enemies %d, tokens %d" % [player.health.health, player.health.max_health, alive, AttackTokens.count(player)])


func _log(s: String) -> void:
	print("[%6.2f] %s" % [float(Engine.get_physics_frames() - t0) / 60.0, s])


func _shot(name: String) -> void:
	if OS.get_environment("SHOTS") == "" or shots_taken.has(name):
		return
	shots_taken[name] = true
	p.screenshot(name)
