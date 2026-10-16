extends Node
## NPC hook of the playable scenes (WorldHooks): installs the NpcDirector (townsfolk + named
## characters, talk, barks, reactions), streams crowd records through the scene's WorldContent
## (NpcProvider), pre-builds the home nation's crowd meshes while the loading screen waits, and
## installs the wildlife (WildlifeDirector + WildlifeProvider). Nothing in the training grounds.

var scene: Node = null
var director: NpcDirector = null
var provider: NpcProvider = null
var wildlife: WildlifeDirector = null
var wildlife_provider: WildlifeProvider = null


func world_setup(p_scene: Node) -> void:
	scene = p_scene
	if bool(p_scene.get("is_tutorial")):
		return
	director = NpcDirector.new()
	add_child(director)
	wildlife = WildlifeDirector.new()
	add_child(wildlife)
	var content: WorldContent = p_scene.get("content")
	if content != null and WorldData.has_world_data():
		provider = NpcProvider.new(director)
		content.register_provider(provider)
		wildlife_provider = WildlifeProvider.new(wildlife)
		content.register_provider(wildlife_provider)
	var e := int(p_scene.get("element"))
	if ElementDefs.is_valid(e):
		director.prewarm(ElementDefs.id_of(e))


func player_spawned(player: Node3D) -> void:
	if director != null:
		director.player = player
	if wildlife != null:
		wildlife.player = player


func world_ready() -> void:
	pass


func world_exit() -> void:
	if director != null and is_instance_valid(director):
		director.active = false
	provider = null
	wildlife_provider = null
