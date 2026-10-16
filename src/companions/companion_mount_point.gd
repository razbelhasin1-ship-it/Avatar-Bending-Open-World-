class_name CompanionMountPoint
extends Interactable
## The companion's "Ride the Sky Bison" prompt: an Interactable (lowest priority, so NPCs and
## objects win) that mounts on interact. The mount action does the same without the prompt;
## both paths go through Companion.request_mount, so gamepads (interact = Y) and touch
## (contextual button) can ride too.

var companion: Companion = null


func _init() -> void:
	super._init()
	interact_priority = -1
	animation = &""
	lock_time = 0.05


func get_interaction_text(_player: Node3D) -> String:
	return prompt


func can_interact(player: Node3D) -> bool:
	return enabled and companion != null and is_instance_valid(companion) and companion.can_mount(player)


func interact(player: Node3D) -> void:
	if companion != null and is_instance_valid(companion):
		companion.request_mount(player)
	interacted.emit(player)
