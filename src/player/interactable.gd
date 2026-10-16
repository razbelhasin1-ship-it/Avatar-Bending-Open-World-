class_name Interactable
extends Area3D
## Something the player can interact with (talk, open, pick up, use).
## Put one under an NPC / chest / door: an Area3D in group &"interactable" on
## Layers.INTERACTABLE. The player picks the best one in range and facing,
## shows "[E] <text>" through Events.interaction_prompt and calls interact()
## when the interact action is pressed.
##
##   var it := Interactable.new()
##   it.prompt = "Talk to Master Pakku"
##   it.radius = 2.0
##   it.interacted.connect(func(player): dialogue.start())
##   npc.add_child(it)
##
## Override get_interaction_text / can_interact / interact in a subclass for
## dynamic behaviour. `animation` is the clip the player plays (&"" = none);
## `lock_time` keeps the player in the Interacting state (end_interaction()
## on the player releases it earlier).

signal interacted(player: Node3D)

@export var prompt := "Interact"
@export var radius := 2.0:
	set(v):
		radius = v
		if _shape and _shape.shape is SphereShape3D:
			(_shape.shape as SphereShape3D).radius = v
@export var enabled := true
## Higher wins when several are in range.
@export var interact_priority := 0
@export var animation: StringName = &"interact_r"
@export var lock_time := 0.6
## Offset of the point the player faces / measures distance to.
@export var focus_offset := Vector3(0, 1.0, 0)

var _shape: CollisionShape3D


func _init() -> void:
	collision_layer = Layers.INTERACTABLE
	collision_mask = 0
	monitoring = false
	monitorable = true


func _ready() -> void:
	add_to_group(&"interactable")
	if _shape == null:
		for c in get_children():
			if c is CollisionShape3D:
				_shape = c
				break
	if _shape == null:
		_shape = CollisionShape3D.new()
		var s := SphereShape3D.new()
		s.radius = radius
		_shape.shape = s
		add_child(_shape)


func get_interaction_text(_player: Node3D) -> String:
	return prompt


func can_interact(_player: Node3D) -> bool:
	return enabled and is_visible_in_tree()


func interact(player: Node3D) -> void:
	interacted.emit(player)


func focus_point() -> Vector3:
	return global_position + global_basis * focus_offset
