extends Node
## Entry scene. Routes to the main menu, or straight into a scene for development:
##   godot --path . -- --scene=world --element=fire
##   godot --path . -- --scene=tutorial --element=water
##   godot --path . -- --scene=res://scenes/dev/some_test.tscn
## Aliases: world, tutorial, menu, select.

const ALIASES := {
	"world": "res://scenes/world/world.tscn",
	"tutorial": "res://scenes/world/tutorial.tscn",
	"menu": "res://scenes/ui/main_menu.tscn",
	"select": "res://scenes/ui/element_select.tscn",
}


func _ready() -> void:
	await get_tree().process_frame
	var scene_arg := ""
	var element := ElementDefs.Element.NONE
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_arg = a.substr(8)
		elif a.begins_with("--element="):
			element = ElementDefs.from_id(StringName(a.substr(10)))
	if scene_arg.is_empty():
		Router.goto(Router.MAIN_MENU, {}, 0.6)
		return
	var path: String = ALIASES.get(scene_arg, scene_arg)
	if not ElementDefs.is_valid(element):
		element = ElementDefs.Element.WATER
	GameState.new_game(element, scene_arg == "tutorial")
	Router.goto(path, {"element": element, "dev": true, "new_game": true}, 0.1)
