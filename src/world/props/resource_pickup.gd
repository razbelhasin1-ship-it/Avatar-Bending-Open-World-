class_name ResourcePickup
extends Interactable
## A gatherable resource node (jade, herbs, whale bone, spirit blossoms...): an Interactable the
## player harvests with the interact action. Adds `count` of `item_id` to GameState (which emits
## Events.item_collected, so Audio plays the pickup stinger and quests can count it), shows a
## HUD toast, hides its model and regrows after `respawn_time` seconds.
##
##   var p := ResourcePickup.create(&"jade_shard", 1, mesh, "Jade Shard")
##   p.position = spot; cell_root.add_child(p)

## Emitted after a successful harvest (PoiProvider remembers it across cell reloads).
signal harvested

@export var item_id: StringName = &"herb"
@export var count: int = 1
@export var display_name: String = "Herb"
@export var respawn_time: float = 240.0

var model: Node3D = null
var _regrow := 0.0


## Builds a pickup with a visual mesh (centered at the pickup's origin).
static func create(p_item: StringName, p_count: int, mesh: Mesh, p_name: String, respawn: float = 240.0) -> ResourcePickup:
	var p := ResourcePickup.new()
	p.item_id = p_item
	p.count = p_count
	p.display_name = p_name
	p.respawn_time = respawn
	p.prompt = "Gather %s" % p_name
	p.radius = 1.6
	p.animation = &"interact_r"
	p.lock_time = 0.5
	p.focus_offset = Vector3(0, 0.4, 0)
	if mesh:
		var mi := MeshInstance3D.new()
		mi.name = "Model"
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 120.0
		p.add_child(mi)
		p.model = mi
	return p


func can_interact(player: Node3D) -> bool:
	return _regrow <= 0.0 and super.can_interact(player)


func interact(player: Node3D) -> void:
	if _regrow > 0.0:
		return
	GameState.add_item(item_id, count)
	Events.notify.emit("+%d %s" % [count, display_name], &"info")
	start_regrow(respawn_time)
	super.interact(player)
	harvested.emit()


## Hides the model for `seconds` (already harvested), then regrows it.
func start_regrow(seconds: float) -> void:
	_regrow = maxf(seconds, 0.0)
	if _regrow <= 0.0:
		return
	if model:
		model.visible = false
	set_process(true)


func is_available() -> bool:
	return _regrow <= 0.0


func _ready() -> void:
	super._ready()
	set_process(_regrow > 0.0)


func _process(delta: float) -> void:
	_regrow -= delta
	if _regrow <= 0.0:
		_regrow = 0.0
		if model:
			model.visible = true
		set_process(false)
