class_name FerryDock
extends Node3D
## Ferry landing at a port quay (WorldData.get_ports): a timber platform with a ferry-master's
## signpost and paper lantern, a bell frame and cargo in the port nation's colours, plus the
## Interactable "Take the ferry" that TravelSystem answers with a destination choice.
## The ferry itself waits moored at the port's berth (FerryBoat, owned by TravelSystem).

signal requested(dock: FerryDock)

var port: Dictionary = {}
var port_id: StringName = &""
var interactable: Interactable
## TravelSystem sets this so the prompt disappears while a trip is under way.
var available := true

static var _kits: Dictionary = {}      # nation -> KitResult


func _init(p_port: Dictionary = {}) -> void:
	port = p_port
	port_id = StringName(port.get("id", &""))


func _ready() -> void:
	name = "Dock_%s" % String(port_id)
	var quay: Vector3 = port.get("quay", Vector3.ZERO)
	var yaw := float(port.get("yaw", 0.0))
	global_transform = Transform3D(Basis(Vector3.UP, yaw), quay)
	var nation := NationPalette.nation_for_region(StringName(port.get("region", &"")))
	var res := kit_for(nation)
	var inst := res.instantiate({"name": "Landing", "vis_end": 420.0})
	add_child(inst)
	interactable = Interactable.new()
	interactable.name = "Ferry"
	interactable.prompt = "Take the ferry"
	interactable.radius = 3.2
	interactable.interact_priority = 2
	interactable.lock_time = 0.4
	interactable.position = Vector3(0.9, 0.0, -0.6)
	interactable.focus_offset = Vector3(0, 1.6, 0)
	add_child(interactable)
	interactable.interacted.connect(func(_p: Node3D) -> void:
		if available:
			requested.emit(self))


## Shared landing geometry per nation (built once; local frame: -Z faces the water).
static func kit_for(nation: StringName) -> KitResult:
	if _kits.has(nation):
		return _kits[nation]
	var kit := BuildingKit.new(NationPalette.get_palette(nation), 0, 77)
	# timber deck (low, so it reads as a landing without blocking movement)
	kit.box(Vector3(0, 0.08, -0.8), Vector3(4.2, 0.16, 3.6), &"wood", true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.box(Vector3(sx * 2.0, 0.0, -0.8 + sz * 1.7), Vector3(0.24, 0.5, 0.24), &"wood_dark", false)
	# ferry-master's signpost with a hanging board and a lantern
	var post := Vector3(0.9, 0.16, -0.6)
	kit.cylinder(post, 3.4, 0.11, &"wood_dark", 8, true, 0.09)
	kit.beam(post + Vector3(0, 3.2, 0), post + Vector3(-1.3, 3.2, 0), 0.12, 0.12, &"wood_dark")
	kit.box(post + Vector3(-0.75, 2.55, 0), Vector3(1.05, 0.62, 0.08), &"wood", false)
	kit.box(post + Vector3(-0.75, 2.55, -0.05), Vector3(0.78, 0.38, 0.02), &"trim", false)
	kit.lantern(post + Vector3(-1.25, 2.75, 0), {"style": &"paper", "range": 9.0, "energy": 1.4})
	# bell frame
	var bell := Vector3(-1.3, 0.16, -1.6)
	for sx in [-1.0, 1.0]:
		kit.box(bell + Vector3(sx * 0.45, 0.9, 0), Vector3(0.12, 1.8, 0.12), &"wood_dark", false)
	kit.beam(bell + Vector3(-0.6, 1.8, 0), bell + Vector3(0.6, 1.8, 0), 0.14, 0.14, &"wood_dark")
	var bronze := Color(0.66, 0.44, 0.2).srgb_to_linear()
	kit.g().cylinder(bell + Vector3(0, 0.98, 0), bell + Vector3(0, 1.05, 0), 0.34, 0.33, 12, bronze.darkened(0.2), 3)
	kit.g().cylinder(bell + Vector3(0, 1.05, 0), bell + Vector3(0, 1.58, 0), 0.31, 0.21, 12, bronze, 0)
	kit.g().blob(bell + Vector3(0, 1.6, 0), 0.21, 1, bronze, null, 0.0, Vector3(1, 0.7, 1))
	kit.g().cylinder(bell + Vector3(0, 1.72, 0), bell + Vector3(0, 1.8, 0), 0.05, 0.05, 6, bronze.darkened(0.3), 0)
	kit.collide_box(bell + Vector3(0, 0.9, 0), Vector3(1.0, 1.8, 0.3))
	# cargo
	kit.box(Vector3(-1.5, 0.5, 0.4), Vector3(0.7, 0.7, 0.7), &"wood", true)
	kit.box(Vector3(-0.8, 0.45, 0.6), Vector3(0.6, 0.6, 0.6), &"wood_dark", true)
	kit.g().cylinder(Vector3(1.6, 0.16, 0.5), Vector3(1.6, 0.36, 0.5), 0.36, 0.34, 10, kit.col(&"cloth_alt").darkened(0.35), 1)
	# nation banner on a pole
	kit.flag(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-2.1, 0.16, -2.4)), 4.6, 1.4, 0.9)
	var res := kit.build()
	_kits[nation] = res
	return res
