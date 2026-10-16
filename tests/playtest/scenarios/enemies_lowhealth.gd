extends RefCounted
## Low-health behaviour of bandits with the real player: a brawler that surrenders
## (kneels, hands raised, "I yield!", loot handed over, spared: further hits are ignored)
## and an archer that flees (runs from the player, vanishes out of sight with half XP).
## Health is set to 35 % up front (time saver); the last hits are real light strikes.

const E := ElementDefs.Element
const S := EnemyBase.State
const DT := 1.0 / 60.0

var p: Playtest
var player: PlayerCharacter
var cam: Camera3D


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.WATER)
	var arena: Node = await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": E.WATER, "spawn": false})
	player = arena.get("player")
	player.camera_rig.require_capture = false
	player.resources.infinite_chi = true
	player.health.invulnerable = true
	cam = Camera3D.new()
	cam.fov = 50.0
	arena.add_child(cam)
	var toasts: Array = []
	Events.notify.connect(func(t: String, _k: StringName) -> void: toasts.append(t))
	var group: Array = arena.call("spawn_group", [&"bandit_brawler", &"bandit_archer"], [Vector3(-1.5, 0, -2.0), Vector3(3.5, 0, -6.0)])
	var brawler: EnemyBase = group[0]
	var archer: EnemyBase = group[1]
	brawler.low_health_mode = &"surrender"
	archer.low_health_mode = &"flee"
	brawler.health.health = brawler.health.max_health * 0.35
	archer.health.health = archer.health.max_health * 0.35
	brawler.brain.engage(player)
	archer.brain.engage(player)
	await p.wait_game(1.2)
	# Strike the brawler until it gives up.
	var t := 0.0
	while not brawler.surrendered and brawler.is_alive() and t < 12.0:
		await _strike(brawler)
		t += 0.4
	p.check(brawler.surrendered and brawler.state == S.SURRENDER, "the brawler surrendered (%s)" % brawler.get_state_name())
	await p.wait_game(0.9)
	await _shot("lowhealth_1_surrender", brawler)
	var hp := brawler.health.health
	var r := Combat.deal(brawler, HitInfo.make(20.0, player, E.WATER, HitInfo.Reaction.STAGGER, Vector3.FORWARD, 4.0))
	p.check(r == Combat.Result.IGNORED and brawler.health.health == hp, "a surrendered enemy is spared")
	p.check(toasts.any(func(s: String) -> bool: return s.contains("surrendered")), "surrender toast with the loot")
	# Then the archer: hit it once more and it runs.
	t = 0.0
	while archer.state != S.FLEE and archer.is_alive() and t < 12.0:
		await _strike(archer)
		t += 0.4
	p.check(archer.state == S.FLEE, "the archer flees (%s)" % archer.get_state_name())
	await p.wait_game(0.6)
	await _shot("lowhealth_2_flee", archer)
	var fled := [false]
	archer.defeated.connect(func(_e: EnemyBase, how: StringName) -> void: fled[0] = how == &"fled")
	t = 0.0
	while not fled[0] and t < 10.0:
		await p.wait_game(0.25)
		t += 0.25
	p.check(fled[0], "the archer fled out of sight (defeated: fled)")
	p.check(brawler.surrendered and brawler.state == S.SURRENDER, "the brawler still kneels")
	await _shot("lowhealth_3_after", brawler)


func _strike(e: EnemyBase) -> void:
	var to := e.global_position - player.global_position
	to.y = 0.0
	if to.length() > 4.0:
		player.rotation.y = atan2(-to.x, -to.z)
		player.camera_rig.snap_behind(player)
		p.hold(&"move_forward")
		await p.wait_game(0.2)
		p.release(&"move_forward")
	player.targeting.lock(e)
	await p.tap(&"attack_light")
	await p.wait_game(0.25)


func _shot(name: String, e: EnemyBase) -> void:
	var a := player.global_position
	var b := e.global_position
	var mid := a.lerp(b, 0.6) + Vector3.UP
	var d := b - a
	d.y = 0.0
	var sep := maxf(d.length(), 2.0)
	var fwd := d / sep
	var side := Vector3(-fwd.z, 0, fwd.x)
	cam.look_at_from_position(mid + side * (3.0 + sep * 0.7) - fwd * 2.0 + Vector3.UP * 1.6, mid, Vector3.UP)
	cam.make_current()
	await p.screenshot(name)
	player.camera_rig.make_current()
