extends Node
## Settlements hook of the playable scenes (WorldHooks, docs/modules/worldscene.md): streams the
## Northern Water Tribe, the arctic villages and the Southern Air Temple through the scene's
## WorldContent before the player spawns, so loading waits for the buildings around the spawn.
## In the training grounds the airball court is left out (the tutorial's own sparring ground
## stands on that terrace).

var scene: PlayableScene
var providers: Array[ContentProvider] = []


func world_setup(p_scene: PlayableScene) -> void:
	scene = p_scene
	if scene == null or scene.content == null:
		return
	var opts := {}
	if scene.is_tutorial:
		opts["skip_tags"] = [&"airball_court"]
	providers = Settlements.register(scene.content, opts)


func world_exit() -> void:
	# the providers belong to the scene's WorldContent and leave with it
	providers.clear()
