class_name RespawnSystem
extends Node
## Death and safety for a playable scene (docs/GAME_DESIGN.md §5):
## * Events.player_died -> short beat -> fade -> respawn at the nearest safe point (home
##   city spawn, the spawn of any visited capital, discovered shrines / villages / harbors /
##   training grounds) with 50 % health; nothing else changes, so no progress is lost.
## * Fall-out-of-world net: a player far below the terrain with nothing solid under them,
##   beyond the world's edge, or with a non-finite position is faded back to the last safe
##   ground (in addition to WorldRenderer's own 1.5 m collision net).
## * Optional leash (tutorial): straying `leash_radius` m from `fixed_point` or falling
##   `leash_drop` m below it resets the player there.

signal respawned(at: Transform3D)
signal rescued(from: Vector3, to: Vector3)

const DEATH_DELAY := 2.2
const RESPAWN_HEALTH := 0.5
const SAFE_TYPES: Array[StringName] = [&"shrine", &"village", &"dock", &"training_ground"]
## Below the terrain by this much (with nothing solid underneath) = fell out of the world.
const FALL_DEPTH := 30.0
const ABS_FLOOR := -300.0
const WORLD_LIMIT := 4060.0
const CHECK_INTERVAL := 0.2

var scene: PlayableScene
var player: PlayerCharacter
var active := true
## A respawn / rescue sequence is running.
var busy := false
var deaths := 0
var rescues := 0
var health_ratio := RESPAWN_HEALTH
## Use `fixed_point` for every respawn and rescue (tutorial arena).
var use_fixed := false
var fixed_point := Transform3D.IDENTITY
## Leash around fixed_point (0 = off).
var leash_radius := 0.0
var leash_drop := 10.0
var leash_message := "Stay within the training grounds."
var last_respawn := Transform3D.IDENTITY

var _check_t := 0.0


func setup(p_scene: PlayableScene, p_player: PlayerCharacter) -> void:
	scene = p_scene
	player = p_player
	if not Events.player_died.is_connected(_on_player_died):
		Events.player_died.connect(_on_player_died)


func _exit_tree() -> void:
	if Events.player_died.is_connected(_on_player_died):
		Events.player_died.disconnect(_on_player_died)


func _valid() -> bool:
	return is_instance_valid(scene) and is_instance_valid(player) and player.is_inside_tree() and not scene.is_exiting()


func _on_player_died() -> void:
	if not active or busy or not _valid():
		return
	_respawn_sequence()


func _respawn_sequence() -> void:
	busy = true
	deaths += 1
	var died_at := player.global_position
	await scene.wait_seconds(DEATH_DELAY)
	if not _valid():
		busy = false
		return
	if player.is_alive() and player.get_state() != PlayerCharacter.State.DEAD:
		busy = false     # revived by something else (auto respawn backstop)
		return
	var at := respawn_point(died_at)
	await scene.fade_through(func() -> void: await _place(at, true), 0.6, 0.7)
	busy = false
	if _valid():
		Events.notify.emit("You recover your strength at %s." % _place_name(at.origin), &"info")


## Nearest safe point to `from` (Transform3D facing the way the place is oriented).
func respawn_point(from: Vector3) -> Transform3D:
	if use_fixed:
		return fixed_point
	var best := WorldData.get_spawn(GameState.element)
	var best_d := best.origin.distance_to(from)
	for e in ElementDefs.ALL:
		if e == GameState.element:
			continue
		if RegionDirector.is_visited(StringName(ElementDefs.get_data(e).get("home_region", &""))):
			var s := WorldData.get_spawn(e)
			var d := s.origin.distance_to(from)
			if d < best_d:
				best = s
				best_d = d
	for poi: Dictionary in WorldData.get_pois():
		if not SAFE_TYPES.has(StringName(poi.get("type", &""))) or not GameState.discovered_pois.has(String(poi.get("id", ""))):
			continue
		var p := WorldData.get_safe_ground(poi["position"])
		var d := p.distance_to(from)
		if d < best_d:
			best_d = d
			best = Transform3D(Basis(Vector3.UP, float(poi.get("yaw", 0.0))), p)
	return best


func _place(at: Transform3D, revive: bool) -> void:
	await scene.wait_for_ground(at.origin, 8.0)
	if not _valid():
		return
	var x := scene.ground_transform(at)
	last_respawn = x
	if revive:
		player.respawn_at(x, health_ratio)
		# respawn_at only revives a depleted HealthComponent; a scripted death keeps full health.
		var h := player.health
		if h and not is_equal_approx(h.health, h.max_health * health_ratio):
			h.health = h.max_health * health_ratio
			h.changed.emit(h.health, h.max_health)
		respawned.emit(x)
	else:
		if player.get_state() == PlayerCharacter.State.MOUNTED:
			player.dismount(x.origin)
		player.teleport(x)
		player.velocity = Vector3.ZERO
	for i in 2:
		await get_tree().physics_frame


func _place_name(pos: Vector3) -> String:
	var poi := WorldData.get_nearest_poi(pos, &"", 120.0)
	if not poi.is_empty():
		return String(poi.get("name", "a safe place"))
	for e in ElementDefs.ALL:
		if WorldData.get_spawn(e).origin.distance_to(pos) < 60.0:
			return String(ElementDefs.get_data(e).get("home_name", "a safe place"))
	return "a safe place"


# --- fall-out-of-world net ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active or busy or not _valid():
		return
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = CHECK_INTERVAL
	var why := needs_rescue()
	if why != &"":
		rescue(why)


## &"" when the player is fine, else why a rescue is needed (&"nan", &"edge", &"fell", &"leash").
func needs_rescue() -> StringName:
	var st := player.get_state()
	if st == PlayerCharacter.State.DEAD or st == PlayerCharacter.State.CINEMATIC:
		return &""
	var p := player.global_position
	if not p.is_finite():
		return &"nan"
	if use_fixed and leash_radius > 0.0:
		var c := fixed_point.origin
		if Vector2(p.x - c.x, p.z - c.z).length() > leash_radius or p.y < c.y - leash_drop:
			return &"leash"
	if st == PlayerCharacter.State.MOUNTED:
		return &""
	if absf(p.x) > WORLD_LIMIT or absf(p.z) > WORLD_LIMIT:
		return &"edge"
	if p.y < ABS_FLOOR:
		return &"fell"
	if p.y < WorldData.get_height(p.x, p.z) - FALL_DEPTH:
		# Caves and tunnels are fine: only rescue when nothing solid is below.
		var space := player.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 60.0, Layers.WORLD | Layers.CONSTRUCT)
		var ex: Array[RID] = [player.get_rid()]
		q.exclude = ex
		if space.intersect_ray(q).is_empty():
			return &"fell"
	return &""


## Fades the player back onto safe ground. `why` only changes the message.
func rescue(why: StringName = &"fell") -> void:
	if busy or not _valid():
		return
	busy = true
	rescues += 1
	var from := player.global_position
	var to: Transform3D
	if use_fixed:
		to = fixed_point
	else:
		var base := player.motor.last_safe_position() if player.motor else from
		if not base.is_finite() or why == &"edge":
			var c := from if from.is_finite() else WorldData.get_spawn(GameState.element).origin
			base = Vector3(clampf(c.x, -WORLD_LIMIT + 160.0, WORLD_LIMIT - 160.0), c.y, clampf(c.z, -WORLD_LIMIT + 160.0, WORLD_LIMIT - 160.0))
		var safe := WorldData.get_safe_ground(base)
		to = Transform3D(Basis(Vector3.UP, player.motor.yaw if player.motor else 0.0), safe)
	await scene.fade_through(func() -> void: await _place(to, false), 0.3, 0.5)
	busy = false
	if _valid():
		rescued.emit(from, to.origin)
		match why:
			&"leash": Events.notify.emit(leash_message, &"warning")
			&"edge": Events.notify.emit("The open sea turns you back.", &"warning")
			_: Events.notify.emit("You find your footing again.", &"info")
