extends Node3D
## Dev scene: the building kit's four nation showcase buildings (Water Tribe ice hall, Earth
## Kingdom hall, Fire Nation temple, Air Nomad tower) on a stone plaza in the real world (flat
## grassland east of Ba Sing Se), with streamed vegetation around and the real sky/day-night.
##   godot --path . -- --scene=res://scenes/dev/worldcontent_buildings.tscn

const SITE := Vector2(2686.0, -118.0)
const NATIONS: Array[StringName] = [&"water_tribe", &"earth_kingdom", &"fire_nation", &"air_nomads"]
const SPACING := 26.0

var world: WorldRenderer
var content: WorldContent
var cam: Camera3D
var plaza_y := 0.0
## nation -> {"node": Node3D, "result": KitResult, "origin": Vector3, "build_ms": float}
var buildings: Dictionary = {}


func _ready() -> void:
	cam = Camera3D.new()
	cam.far = 30000.0
	add_child(cam)
	cam.current = true
	world = WorldRenderer.new()
	add_child(world)
	world.setup(cam, cam)
	plaza_y = _site_height() + 0.35
	content = WorldContent.new()
	add_child(content)
	content.setup(cam, cam)
	content.add_exclusion(Vector3(SITE.x, 0, SITE.y), 62.0, ContentExclusions.TAG_ALL, 8.0)
	NationPalette.prepare_materials()
	_build_plaza()
	for i in NATIONS.size():
		var nation := NATIONS[i]
		var origin := Vector3(SITE.x + (i - 1.5) * SPACING, plaza_y, SITE.y)
		var t0 := Time.get_ticks_usec()
		var kit := BuildingKit.new(NationPalette.get_palette(nation), 0, 100 + i)
		BuildingPresets.demo(kit, Transform3D.IDENTITY)
		var res := kit.build()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var node := res.instantiate({"name": String(nation)})
		node.position = origin
		add_child(node)
		buildings[nation] = {"node": node, "result": res, "origin": origin, "build_ms": ms}
	look_at_overview()
	world.set_time_of_day(Router.params.get("hour", 15.5))


func _site_height() -> float:
	var m := -INF
	for k in 64:
		var x := SITE.x + (k % 8 - 3.5) * 16.0
		var z := SITE.y + (k / 8 - 3.5) * 8.0
		m = maxf(m, WorldData.get_height(x, z))
	return m


func _build_plaza() -> void:
	var kit := BuildingKit.new(NationPalette.get_palette(&"neutral"), 0, 7)
	var w := SPACING * 4.0 + 8.0
	var d := 44.0
	kit.box(Vector3(0, -1.5, 0), Vector3(w, 3.0, d), &"stone")
	kit.box(Vector3(0, -0.02, 0), Vector3(w - 1.2, 0.06, d - 1.2), &"floor", false)
	for i in int(w / 4.0):
		kit.box(Vector3(-w * 0.5 + 2.0 + i * 4.0, 0.0, 0), Vector3(0.08, 0.07, d - 1.4), &"stone_dark", false)
	var res := kit.build()
	var node := res.instantiate({"name": "Plaza"})
	node.position = Vector3(SITE.x, plaza_y, SITE.y)
	add_child(node)


func look_from(pos: Vector3, at: Vector3, fov: float = 60.0) -> void:
	cam.global_position = pos
	cam.look_at(at, Vector3.UP)
	cam.fov = fov


func look_at_overview() -> void:
	look_from(Vector3(SITE.x - 6.0, plaza_y + 24.0, SITE.y - 62.0), Vector3(SITE.x, plaza_y + 5.0, SITE.y), 58.0)


## Camera in front of one building (dist m, height m above the plaza).
func look_at_building(nation: StringName, dist: float = 26.0, height: float = 6.0, side: float = 0.35) -> void:
	var o: Vector3 = buildings[nation]["origin"]
	look_from(o + Vector3(side * dist, height, -dist), o + Vector3(0, 5.0, 0), 60.0)


## Camera inside the Earth Kingdom hall looking at the door.
func look_inside(nation: StringName = &"earth_kingdom") -> void:
	var res: KitResult = buildings[nation]["result"]
	var o: Vector3 = buildings[nation]["origin"]
	var inner: Transform3D = res.markers.get(&"interior", Transform3D())
	var p := o + inner.origin
	look_from(p + Vector3(2.5, 1.7, 2.8), p + Vector3(0, 1.3, -4.0), 72.0)
