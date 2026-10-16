class_name BendingChallenge
extends Node3D
## A short bending challenge (quest objectives of type `challenge`, trainer lessons):
##
##   {"kind": &"targets", "title": "Strike the posts", "count": 3, "hits": 6,
##    "ability": &"water_whip" | "slot": &"light" | &"technique" | &"heavy" | &"any", "time": 45.0}
##     training posts (TrainingDummy) rise on an arc in front of the player; land `hits` hits
##     with the right moves before the time runs out.
##   {"kind": &"spar", "title": "Spar with Kallik", "archetype": &"spar_water", "time": 90.0}
##     a sparring partner (EnemyBase, no rewards) fights until it yields (surrenders) — the
##     master stops the bout if the player drops below 20 % health.
##
## Fails on time out, death, or walking 35 m away (no stuck state). `finished(success)` fires
## once, then everything it spawned fades out. A ChallengeHud shows title, progress and timer.

signal finished(success: bool)
signal progressed(done: int, needed: int)

const LEAVE_RADIUS := 35.0

var spec: Dictionary = {}
var title := "Training"
var needed := 1
var done := 0
var time_left := 60.0
var time_total := 60.0
var center := Vector3.ZERO
var targets: Array[Node3D] = []
var opponent: EnemyBase = null
var hud: ChallengeHud = null
var running := false
var result := -1

var _player: Node3D = null


## Starts a challenge under `host` (the scene) in front of the player. Returns it (await `finished`).
static func begin(host: Node, p_spec: Dictionary, player: Node3D) -> BendingChallenge:
	var c := BendingChallenge.new()
	c.spec = p_spec
	c._player = player
	host.add_child(c)
	c._start()
	return c


func _start() -> void:
	name = "BendingChallenge"
	add_to_group(&"bending_challenge")
	title = String(spec.get("title", "Training"))
	time_total = float(spec.get("time", 60.0))
	time_left = time_total
	var pl := _player
	var fwd := -pl.global_basis.z
	fwd.y = 0.0
	fwd = _open_direction(fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD)
	center = pl.global_position + fwd * 6.0
	match StringName(str(spec.get("kind", "targets"))):
		&"spar":
			needed = 1
			_spawn_opponent(fwd)
		_:
			needed = int(spec.get("hits", 4))
			_spawn_targets(fwd, int(spec.get("count", 3)))
	hud = ChallengeHud.new()
	add_child(hud)
	hud.show_challenge(title, _progress_text(), 1.0)
	Events.hit_landed.connect(_on_hit)
	Events.player_died.connect(_on_player_died)
	running = true
	Audio.play_2d(&"gong", -8.0)


## The player's facing when there are 6.5 m of open floor that way, else the most open of eight
## directions (a player who just faced the master on his dais gets the posts behind them, in the
## room, not in the wall behind the master).
func _open_direction(facing: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := _player.global_position + Vector3.UP * 1.2
	var best := facing
	var best_len := -1.0
	for i in 8:
		var d := facing.rotated(Vector3.UP, TAU * i / 8.0)
		var q := PhysicsRayQueryParameters3D.create(from, from + d * 7.0, Layers.SOLID)
		var r := space.intersect_ray(q)
		var free := 7.0 if r.is_empty() else from.distance_to(r["position"])
		if i == 0 and free >= 6.5:
			return facing
		# a slight preference for directions near the facing
		var score := free - 0.15 * float(mini(i, 8 - i))
		if score > best_len:
			best_len = score
			best = d
	return best


## Spot on the floor near `p` within 1.5 m of the player's height, or INF.
func _floor(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 3.0, Layers.SOLID)
	var r := space.intersect_ray(q)
	if r.is_empty():
		return Vector3.INF
	var g: Vector3 = r["position"]
	return g if absf(g.y - _player.global_position.y) < 1.5 else Vector3.INF


func _spawn_targets(fwd: Vector3, count: int) -> void:
	var right := Vector3.UP.cross(fwd).normalized() * -1.0
	var placed := 0
	for radius: float in [6.0, 4.5, 3.2]:
		if placed >= count:
			break
		for i in count * 2:
			if placed >= count:
				break
			var k := (float(i) / maxf(1.0, float(count * 2 - 1)) - 0.5) * 1.6
			var p := _player.global_position + (fwd * cos(k) + right * sin(k)) * radius
			var g := _floor(p)
			if not g.is_finite() or not NpcSteering.walkable(_player, _player.global_position, g, 1.5):
				continue
			var near := false
			for t in targets:
				if t.global_position.distance_to(g) < 2.0:
					near = true
			if near:
				continue
			var d := TrainingDummy.new()
			d.look = &"post"
			d.max_health = 100000.0
			d.display_name = "Training Post"
			var face := (_player.global_position - g)
			face.y = 0.0
			d.transform = Transform3D(Basis(Vector3.UP, atan2(-face.x, -face.z)), g)
			add_child(d)
			d.add_to_group(&"quest_target")
			targets.append(d)
			FxBurst.spawn(self, &"dust_ring", g + Vector3.UP * 0.1, {"count": 0.6})
			placed += 1
	if targets.is_empty():
		# nowhere to stand a post (tight interior): one right in front of the player
		var d2 := TrainingDummy.new()
		d2.look = &"post"
		d2.max_health = 100000.0
		d2.transform = Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), _player.global_position + fwd * 2.5)
		add_child(d2)
		d2.add_to_group(&"quest_target")
		targets.append(d2)


func _spawn_opponent(fwd: Vector3) -> void:
	TrainerLessons.ensure_spar_archetypes()
	var arch := StringName(str(spec.get("archetype", "spar_water")))
	var g := _floor(center)
	if not g.is_finite():
		g = _player.global_position + fwd * 4.0
	var face := _player.global_position - g
	opponent = EnemyBase.create(arch, {"home": Transform3D(Basis(Vector3.UP, atan2(-face.x, -face.z)), g),
		"rewards": false, "low_health_mode": &"surrender", "leash": 40.0, "seed": 11})
	add_child(opponent)
	opponent.add_to_group(&"sparring")
	opponent.defeated.connect(func(_e: EnemyBase, _how: StringName) -> void:
		done = 1
		_finish(true))
	FxBurst.spawn(self, &"dust_ring", g + Vector3.UP * 0.1, {"count": 0.6})


func _progress_text() -> String:
	if StringName(str(spec.get("kind", "targets"))) == &"spar":
		return "Make your partner yield"
	return "Hits  %d / %d" % [done, needed]


func _process(delta: float) -> void:
	if not running:
		return
	time_left -= delta
	if hud:
		hud.set_progress(_progress_text(), clampf(time_left / time_total, 0.0, 1.0), time_left)
	if time_left <= 0.0:
		_finish(false, "Time is up.")
		return
	if _player == null or not is_instance_valid(_player):
		_finish(false)
		return
	if Vector2(_player.global_position.x - center.x, _player.global_position.z - center.z).length() > LEAVE_RADIUS:
		_finish(false, "You left the training ground.")
		return
	if opponent != null and is_instance_valid(_player) and _player.get("health") is HealthComponent:
		var h: HealthComponent = _player.get("health")
		if h.health < h.max_health * 0.2:
			_finish(false, "Enough! Catch your breath.")


func _on_hit(hit: HitInfo, target: Node, result_code: int) -> void:
	if not running or hit == null or target == null:
		return
	if not targets.has(target as Node3D):
		return
	if hit.source == null or not is_instance_valid(hit.source) or not (hit.source as Node).is_in_group(&"player"):
		return
	if result_code != Combat.Result.HIT and result_code != Combat.Result.KILLED:
		return
	if not _move_ok(hit.ability_id):
		if hud:
			hud.flash_wrong()
		return
	done += 1
	progressed.emit(done, needed)
	if hud:
		hud.pulse()
	if done >= needed:
		_finish(true)


func _move_ok(id: StringName) -> bool:
	var want := StringName(str(spec.get("ability", "")))
	if want != &"":
		return id == want
	var slot := StringName(str(spec.get("slot", "any")))
	if slot == &"any":
		return true
	var d := AbilityRegistry.get_def(id)
	return d != null and AbilityDef.SLOT_NAMES.get(d.slot, &"") == slot


func _on_player_died() -> void:
	_finish(false, "")


## Ends the challenge (also callable by tests / a give-up action).
func _finish(success: bool, why: String = "") -> void:
	if not running:
		return
	running = false
	result = 1 if success else 0
	if Events.hit_landed.is_connected(_on_hit):
		Events.hit_landed.disconnect(_on_hit)
	if Events.player_died.is_connected(_on_player_died):
		Events.player_died.disconnect(_on_player_died)
	if hud:
		hud.show_result(success, why)
	if success:
		Audio.play_2d(&"quest_complete", -6.0)
	finished.emit(success)
	_cleanup()


func give_up() -> void:
	_finish(false, "")


func _cleanup() -> void:
	await get_tree().create_timer(2.2).timeout
	if opponent != null and is_instance_valid(opponent):
		opponent.vanish()
	for t in targets:
		if is_instance_valid(t):
			FxBurst.spawn(self, &"dust", t.global_position + Vector3.UP * 0.3, {"count": 0.5})
			t.queue_free()
	targets.clear()
	await get_tree().create_timer(1.2).timeout
	queue_free()
