extends Node
## Settlements hook of the playable scenes (WorldHooks, docs/modules/worldscene.md): streams every
## settlement (Settlements.ALL: the Water Tribe, arctic villages, Air Temple, Ba Sing Se, Omashu,
## the Earth Kingdom villages, the Fire Nation capital, Crimson Harbor and the Fire Nation
## villages) through the scene's WorldContent before the player spawns, so loading waits for the
## buildings around the spawn. In the training grounds the airball court and the Flame Kata
## Grounds are left out (the tutorial's own sparring grounds stand there).

var scene: PlayableScene
var providers: Array[ContentProvider] = []


func world_setup(p_scene: PlayableScene) -> void:
	scene = p_scene
	if scene == null or scene.content == null:
		return
	var opts := {}
	if scene.is_tutorial:
		# the tutorial's training grounds stand on the Air Temple's airball court and in the Fire
		# Nation capital's Flame Kata Grounds (settlements_ef): leave those pieces out
		opts["skip_tags"] = [&"airball_court", &"flame_kata_grounds"]
	providers = Settlements.register(scene.content, opts)


func world_exit() -> void:
	# the providers belong to the scene's WorldContent and leave with it
	providers.clear()
