extends Node
## Companions module hook for the playable scenes (WorldHooks): spawns the element's
## companion (GameState.companion["type"], else ElementDefs) beside the player on safe
## ground, in the open world and in the training grounds (where it enables the "call" and
## "ride" lessons). The companion keeps itself near the player from then on.

var scene: Node = null
var companion: Companion = null


func world_setup(p_scene: Node) -> void:
	scene = p_scene


func player_spawned(player: Node3D) -> void:
	if scene == null or not scene.has_method("spawn_companion"):
		return
	if not bool(GameState.companion.get("unlocked", true)):
		return
	var id := StringName(String(GameState.companion.get("type", "")))
	var pc := player as PlayerCharacter
	if id == &"" or not CompanionProfile.SPECIES.has(id):
		id = CompanionProfile.species_for_element(pc.element if pc else GameState.element)
	if not CompanionProfile.SPECIES.has(id):
		return
	companion = Companion.create(id)
	companion.player = pc
	companion.renderer = scene.get("renderer")
	var at := Companion.spawn_transform(player, id)
	scene.call("spawn_companion", companion, at)
	companion.motor.teleport(at.origin, at.basis.get_euler().y)
	companion.rig.reset_feet()


func world_ready() -> void:
	pass


func world_exit() -> void:
	companion = null
