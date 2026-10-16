extends Node
## Enemies module hook for the playable scenes (WorldHooks): installs the
## EncounterDirector (world sites from WorldData + EncounterSites) and registers the
## EncounterProvider with the scene's WorldContent so authored outposts are built.
## The training grounds (tutorial) have no encounters.

var scene: Node = null
var director: EncounterDirector = null


func world_setup(p_scene: Node) -> void:
	scene = p_scene
	if bool(p_scene.get("is_tutorial")):
		return
	director = EncounterDirector.new()
	director.name = "Encounters"
	add_child(director)
	# Exclusions keep trees / props out of the outposts; the provider builds them.
	var content: WorldContent = p_scene.get("content")
	if content != null:
		for s in director.sites:
			if s.kind == &"outpost" or s.kind == &"den":
				content.add_exclusion(s.center, s.radius + 4.0, ContentExclusions.TAG_TREES | ContentExclusions.TAG_PROPS | ContentExclusions.TAG_ROCKS, 4.0)
		content.register_provider(EncounterProvider.new(director.sites))


func player_spawned(player: Node3D) -> void:
	if director:
		director.setup(player)


func world_ready() -> void:
	pass


func world_exit() -> void:
	if director and is_instance_valid(director):
		director.queue_free()
	director = null
