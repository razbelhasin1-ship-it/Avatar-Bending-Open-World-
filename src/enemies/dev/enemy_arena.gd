extends "res://scenes/dev/combat_arena.gd"
## Enemy arena (dev scene): the combat arena courtyard with enemy groups instead of
## the training dummies. Every archetype can be fought here with the real player.
##
##   godot --path . -- --scene=res://scenes/dev/enemy_arena.tscn --element=earth
##   Router.goto("res://scenes/dev/enemy_arena.tscn", {"element": e, "enemies": [&"fire_soldier"], "spawn": false})
## Keys: F5 respawn the group, F6 next group, F9 enemies passive/active.

const GROUPS: Array = [
	[&"bandit_brawler", &"bandit_skirmisher", &"bandit_archer"],
	[&"fire_soldier", &"fire_shieldbearer", &"fire_archer"],
	[&"earth_rogue", &"dai_li_agent"],
	[&"water_pirate", &"pirate_cutlass", &"pirate_archer"],
	[&"fire_captain"],
	[&"earth_chief"],
	[&"komodo_rhino"],
]
## Where the group stands (in front of the player start, facing it).
const SPOTS: Array[Vector3] = [Vector3(0, 0, -10), Vector3(-4.5, 0, -12), Vector3(4.5, 0, -12), Vector3(-2, 0, -16), Vector3(2.5, 0, -17)]

var enemies: Array[EnemyBase] = []
var group_index := 0
var director: EncounterDirector = null


func _spawn_targets() -> void:
	director = EncounterDirector.new()
	director.name = "EncounterDirector"
	director.use_world_sites = false
	add_child(director)
	var ids: Array = Router.params.get("enemies", [])
	if bool(Router.params.get("spawn", true)):
		spawn_group(ids if not ids.is_empty() else GROUPS[0])


## Removes the current enemies and spawns `ids` on the arena spots.
func spawn_group(ids: Array, spots: Array = []) -> Array[EnemyBase]:
	clear_enemies()
	var i := 0
	for id: Variant in ids:
		var p: Vector3 = spots[i] if i < spots.size() else SPOTS[i % SPOTS.size()]
		var xf := Transform3D(Basis(Vector3.UP, 0.0), p)   # facing -Z... turned toward the start below
		var to := START - p
		xf.basis = Basis(Vector3.UP, atan2(-to.x, -to.z))
		var e := director.spawn_enemy(StringName(id), xf, {"seed": 100 + i, "leash": 40.0})
		enemies.append(e)
		i += 1
	return enemies


func clear_enemies() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	AttackTokens.reset()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_F5:
			spawn_group(GROUPS[group_index])
		KEY_F6:
			group_index = (group_index + 1) % GROUPS.size()
			spawn_group(GROUPS[group_index])
		KEY_F9:
			for e in enemies:
				if is_instance_valid(e):
					e.dormant = not e.dormant
		_:
			super._unhandled_key_input(event)
