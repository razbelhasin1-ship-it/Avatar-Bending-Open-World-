class_name WorldHooks
extends RefCounted
## Plug-in slots through which later modules attach to the playable scenes without editing
## them (docs/modules/worldscene.md "Module hooks").
##
## A hook is a script at one of HOOK_PATHS (or added to `PlayableScene.extra_hooks`) whose
## class extends Node. If the file exists, the scene instantiates it under its "Hooks" node
## and calls, when present:
##
##   func world_setup(scene: PlayableScene) -> void     # before the player spawns (providers, NPCs)
##   func player_spawned(player: PlayerCharacter) -> void  # e.g. scene.spawn_companion(...)
##   func world_ready() -> void                           # play begins (after the arrival)
##   func world_exit() -> void                            # scene is leaving the tree
##
## `scene.is_tutorial` tells a hook whether it runs in the training grounds.

const HOOK_PATHS: Array[String] = [
	"res://src/companions/world_hook.gd",
	"res://src/quests/world_hook.gd",
	"res://src/npc/world_hook.gd",
	"res://src/enemies/world_hook.gd",
	"res://src/world/settlements/world_hook.gd",
]


## Instantiates every available hook under `parent`. Returns the hook nodes.
static func install(parent: Node, extra: Array[String] = []) -> Array[Node]:
	var out: Array[Node] = []
	var paths: Array[String] = HOOK_PATHS.duplicate()
	for p in extra:
		if not paths.has(p):
			paths.append(p)
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			push_warning("WorldHooks: cannot instantiate %s" % path)
			continue
		var inst: Variant = script.new()
		if not (inst is Node):
			push_warning("WorldHooks: %s does not extend Node" % path)
			continue
		var n := inst as Node
		n.name = "%sHook" % path.get_base_dir().get_file().to_pascal_case()
		parent.add_child(n)
		out.append(n)
	return out


## Calls `method(args...)` on every hook that implements it.
static func call_all(hooks: Array[Node], method: StringName, args: Array = []) -> void:
	for h in hooks:
		if is_instance_valid(h) and h.has_method(method):
			h.callv(method, args)
