class_name WorldSaveGuard
extends Node
## Keeps saves consistent (group &"persist", added as the world's LAST child so SaveSystem's
## call_group runs it after the player and the renderer have written their state): a save
## taken while the player is dead, swimming, airborne, mounted or travelling stores a safe,
## solid place instead of where the body happens to be, plus the tracked region.

var scene: WorldScene


func _init(p_scene: WorldScene = null) -> void:
	scene = p_scene
	name = "SaveGuard"


func _ready() -> void:
	add_to_group(&"persist")


func write_save_state() -> void:
	if scene == null or not is_instance_valid(scene) or scene.player == null or not is_instance_valid(scene.player):
		return
	var p := scene.player
	if scene.region_director and scene.region_director.current_region != &"":
		GameState.region = scene.region_director.current_region
	if scene.travel and scene.travel.busy:
		var d := scene.travel.pending_destination
		GameState.player_position = d.origin
		GameState.player_yaw = d.basis.get_euler().y
		return
	if not p.is_alive() or p.get_state() == PlayerCharacter.State.DEAD:
		var rp := scene.respawn.respawn_point(p.global_position) if scene.respawn else WorldData.get_spawn(GameState.element)
		GameState.player_position = rp.origin
		GameState.player_yaw = rp.basis.get_euler().y
		GameState.player_health_ratio = RespawnSystem.RESPAWN_HEALTH
		return
	var unsafe := p.get_state() == PlayerCharacter.State.MOUNTED
	if p.motor:
		unsafe = unsafe or p.motor.swimming or not p.motor.on_floor
	if unsafe and p.motor:
		var safe := p.motor.last_safe_position()
		if safe.is_finite():
			GameState.player_position = safe
	if not GameState.player_position.is_finite():
		GameState.player_position = WorldData.get_spawn(GameState.element).origin
