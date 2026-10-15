class_name HudMockPlayer
extends Node3D
## Stand-in implementing the HUD player contract (Hud.bind_player) for tests, playtests
## and UI previews before the real player controller exists. Not used by gameplay.

signal resource_changed(resource: StringName, value: float, max_value: float)

var health: HealthComponent
var chi := 80.0
var chi_max := 100.0
var focus := 40.0
var focus_max := 100.0
## Five slot dictionaries (0..3 techniques, 4 signature) in the HUD format.
var slots: Array[Dictionary] = []
var lock_target: Node3D = null
var companion: Node3D = null


func _init() -> void:
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 160.0
	add_child(health)
	add_to_group(&"player")


## Fills slots with sample techniques of `element` (ability_* icons, mixed states).
func setup_sample(element: int) -> void:
	var icons := {
		ElementDefs.Element.AIR: [["air_sweep", "Air Sweep", "ability_sweep"], ["air_push", "Air Push", "ability_blast"], ["air_scooter", "Air Scooter", "ability_whirl"], ["air_shield", "Air Shield", "ability_shield"], ["air_tornado", "Air Tornado", "ability_whirl"]],
		ElementDefs.Element.EARTH: [["earth_wall", "Earth Wall", "ability_wall"], ["earth_pillar", "Earth Pillar", "ability_spikes"], ["earth_stomp", "Earth Stomp", "ability_blast"], ["earth_shield", "Earth Shield", "ability_shield"], ["earthquake", "Earthquake", "ability_spikes"]],
		ElementDefs.Element.FIRE: [["flame_sweep", "Flame Sweep", "ability_sweep"], ["fire_burst", "Fire Burst", "ability_blast"], ["fire_ring", "Fire Ring", "ability_flame"], ["flame_guard", "Flame Guard", "ability_shield"], ["inferno", "Inferno", "ability_flame"]],
		ElementDefs.Element.WATER: [["ice_shards", "Ice Shards", "ability_shards"], ["water_surge", "Water Surge", "ability_wave"], ["ice_wall", "Ice Wall", "ability_wall"], ["water_shield", "Water Shield", "ability_shield"], ["tidal_torrent", "Tidal Torrent", "ability_wave"]],
	}
	slots.clear()
	for spec: Array in icons.get(element, icons[ElementDefs.Element.WATER]):
		slots.append({"id": StringName(spec[0]), "name": spec[1], "icon": "res://assets/ui/%s.svg" % spec[2], "element": element,
				"cooldown_ratio": 0.0, "cooldown_left": 0.0, "available": true, "cost": 20.0})


func set_cooldown(i: int, ratio: float, seconds_left: float) -> void:
	slots[i]["cooldown_ratio"] = ratio
	slots[i]["cooldown_left"] = seconds_left


func set_available(i: int, on: bool) -> void:
	slots[i]["available"] = on


func set_chi(v: float) -> void:
	chi = clampf(v, 0.0, chi_max)
	resource_changed.emit(&"chi", chi, chi_max)


func set_focus(v: float) -> void:
	focus = clampf(v, 0.0, focus_max)
	resource_changed.emit(&"focus", focus, focus_max)


func get_resource(resource: StringName) -> Vector2:
	match resource:
		&"chi": return Vector2(chi, chi_max)
		&"focus": return Vector2(focus, focus_max)
		&"health": return Vector2(health.health, health.max_health)
	return Vector2.ZERO


func get_ability_slot_info(i: int) -> Dictionary:
	return slots[i] if i >= 0 and i < slots.size() else {}


func get_lock_target() -> Node3D:
	return lock_target if is_instance_valid(lock_target) else null


func get_companion() -> Node3D:
	return companion if is_instance_valid(companion) else null


## Creates a lockable dummy target with health and a display name.
static func make_target(display: String, max_hp: float = 120.0) -> Node3D:
	var t := Node3D.new()
	t.name = display.replace(" ", "")
	t.set_meta(&"display_name", display)
	var h := HealthComponent.new()
	h.name = "HealthComponent"
	h.max_health = max_hp
	t.add_child(h)
	return t
