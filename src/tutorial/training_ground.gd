class_name TrainingGround
extends Node3D
## The training grounds of each element: a real place near the home city (the element's
## `training_ground` POI, whose terrain the world generator flattened) dressed in the home
## nation's style with the BuildingKit - a sparring circle with an inlaid element emblem,
## banner posts, lights (ice lanterns, stone lanterns, braziers, paper lanterns) and a master's
## pavilion at the far end. Arena frame: origin on the ground at the POI centre, -Z = towards
## the dummies / the pavilion (and the home city in the distance).
##
##   var site := TrainingGround.site(ElementDefs.Element.FIRE)   # {poi, name, xform, radius}
##   var tg := TrainingGround.new(ElementDefs.Element.FIRE, site["xform"])
##   scene.add_child(tg)
##   tg.local(Vector3(0, 0, 9))     # arena -> world

const SITES := {
	ElementDefs.Element.WATER: &"wt_ice_flats",
	ElementDefs.Element.EARTH: &"ek_stonefist_yard",
	ElementDefs.Element.FIRE: &"fn_flame_kata_grounds",
	ElementDefs.Element.AIR: &"at_airball_courts",
}
## Extra yaw (deg) on top of "face the home city" for a better backdrop.
const YAW_OFFSET := {
	ElementDefs.Element.WATER: 0.0, ElementDefs.Element.EARTH: 0.0,
	ElementDefs.Element.FIRE: 0.0, ElementDefs.Element.AIR: 0.0,
}
## Sparring circle radius (m).
const RING := 13.0
## Player start, dummies, bot (arena frame).
const START := Vector3(0, 0, 8.5)
const DUMMY_POSTS: Array[Vector3] = [Vector3(-3.4, 0, -1.2), Vector3(0, 0, -2.4), Vector3(3.4, 0, -1.2)]
const DUMMY_HUMANOID := Vector3(6.2, 0, -4.6)
const BOT := Vector3(0, 0, -11.0)
const PAVILION := Vector3(0, 0, -19.5)

var element: int = ElementDefs.Element.WATER
var xform := Transform3D.IDENTITY


func _init(p_element: int = ElementDefs.Element.WATER, p_xform: Transform3D = Transform3D.IDENTITY) -> void:
	element = p_element
	xform = p_xform
	name = "TrainingGround"


## The element's training site: {"poi": id, "name", "xform": Transform3D (arena frame in the
## world), "radius", "region"}. Without world data: a flat site at the origin.
static func site(e: int) -> Dictionary:
	var poi := WorldData.get_poi(SITES.get(e, &""))
	if poi.is_empty():
		return {"poi": &"", "name": "Training Grounds", "xform": Transform3D(Basis.IDENTITY, Vector3(0, WorldData.get_height(0, 0), 0)),
				"radius": 30.0, "region": &"wilds"}
	var c: Vector3 = poi["position"]
	c.y = WorldData.get_height(c.x, c.z)
	var home := WorldData.get_spawn(e).origin
	var d := Vector3(home.x - c.x, 0.0, home.z - c.z)
	var yaw := atan2(-d.x, -d.z) + deg_to_rad(float(YAW_OFFSET.get(e, 0.0)))
	return {"poi": StringName(poi["id"]), "name": String(poi.get("name", "Training Grounds")), "xform": Transform3D(Basis(Vector3.UP, yaw), c),
			"radius": float(poi.get("radius", 30.0)), "region": StringName(poi.get("region", &""))}


## Arena-frame point -> world (snapped to the terrain unless `keep_y`).
func local(p: Vector3, keep_y: bool = false) -> Vector3:
	var w := xform * p
	if not keep_y:
		w.y = WorldData.get_height(w.x, w.z)
	return w


## Arena-frame transform facing `dir` (arena frame) -> world.
func local_xform(p: Vector3, dir: Vector3 = Vector3.FORWARD) -> Transform3D:
	var w := local(p)
	var d := xform.basis * dir
	return Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), w)


func _ready() -> void:
	global_transform = Transform3D(xform.basis, Vector3(xform.origin.x, WorldData.get_height(xform.origin.x, xform.origin.z), xform.origin.z))
	var res := build_kit(element)
	add_child(res.instantiate({"name": "Arena", "vis_end": 0.0}))


static func nation_of(e: int) -> StringName:
	match e:
		ElementDefs.Element.WATER: return &"water_tribe"
		ElementDefs.Element.EARTH: return &"earth_kingdom"
		ElementDefs.Element.FIRE: return &"fire_nation"
		ElementDefs.Element.AIR: return &"air_nomads"
	return &"neutral"


## The arena dressing for an element (thread-safe geometry, arena frame).
static func build_kit(e: int) -> KitResult:
	var kit := BuildingKit.new(NationPalette.get_palette(nation_of(e)), 0, 1000 + e)
	var accent := ElementDefs.color_of(e).srgb_to_linear()
	var accent2 := (ElementDefs.get_data(e).get("color_secondary", Color.WHITE) as Color).srgb_to_linear()
	_floor(kit, e, accent, accent2)
	_posts(kit, e)
	_pavilion(kit, e)
	_lights(kit, e)
	return kit.build()


static func _ring_poly(r: float, n: int) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / n
		poly.append(Vector2(cos(a) * r, sin(a) * r))
	return poly


static func _floor(kit: BuildingKit, e: int, accent: Color, accent2: Color) -> void:
	var g := kit.g()
	var stone := kit.col(&"stone", false)
	var dark := kit.col(&"stone_dark", false)
	if e == ElementDefs.Element.EARTH:
		# packed stone yard over the farmland
		kit.slab(_ring_poly(RING + 0.6, 40), -0.25, 0.1, &"floor", true)
		for i in 10:
			var a := TAU * i / 10.0
			g.box(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * RING * 0.5, 0.105, sin(a) * RING * 0.5)), Vector3(0.05, 0.01, RING), dark)
	# ring band of the sparring circle (flush with the ground, never a trip hazard)
	var n := 48
	for i in n:
		var a0 := TAU * float(i) / n
		var a1 := TAU * float(i + 1) / n
		var y := 0.12 if e == ElementDefs.Element.EARTH else 0.03
		var r0 := RING - 0.45
		var r1 := RING + 0.45
		var c := stone if i % 2 == 0 else stone.lerp(dark, 0.35)
		g.flat_quad(Vector3(cos(a0) * r0, y, sin(a0) * r0), Vector3(cos(a1) * r0, y, sin(a1) * r0),
				Vector3(cos(a1) * r1, y, sin(a1) * r1), Vector3(cos(a0) * r1, y, sin(a0) * r1), c)
	# inlaid emblem: concentric discs in the element's colours + four directional bars
	var ey := 0.13 if e == ElementDefs.Element.EARTH else 0.035
	var discs := [[2.6, dark], [2.3, accent], [1.55, stone], [1.25, accent2], [0.55, accent]]
	for k in discs.size():
		var d: Array = discs[k]
		g.cylinder(Vector3(0, ey + k * 0.004, 0), Vector3(0, ey + k * 0.004 + 0.003, 0), float(d[0]), float(d[0]), 28, d[1], 2)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		g.box(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 4.0, ey, sin(a) * 4.0)), Vector3(2.4, 0.01, 0.35), accent)


static func _posts(kit: BuildingKit, e: int) -> void:
	var count := 10
	for i in count:
		var a := TAU * (float(i) + 0.5) / count
		var p := Vector3(cos(a) * (RING + 1.6), 0.0, sin(a) * (RING + 1.6))
		# keep the pavilion side (-Z) and the start side (+Z) open
		if absf(p.x) < 5.0:
			continue
		var face := Basis(Vector3.UP, atan2(p.x, p.z))
		match e:
			ElementDefs.Element.WATER:
				kit.column(p, 3.4, 0.24, &"ice", &"ice")
				kit.g(&"ice").cone(p + Vector3(0, 3.4, 0), p + Vector3(0, 4.3, 0), 0.3, 6, kit.col(&"ice"))
			ElementDefs.Element.EARTH:
				kit.column(p, 3.2, 0.26, &"stone", &"square", &"stone_dark")
				kit.box(p + Vector3(0, 3.35, 0), Vector3(0.8, 0.3, 0.8), &"roof", false)
			ElementDefs.Element.FIRE:
				kit.column(p, 3.6, 0.2, &"wall", &"round", &"stone_dark")
				kit.ornament(p + Vector3(0, 3.6, 0), &"finial", 0.6, &"metal")
			_:
				kit.column(p, 3.4, 0.2, &"wood", &"round", &"stone")
				kit.ornament(p + Vector3(0, 3.4, 0), &"orb", 0.36, &"trim")
		kit.banner(Transform3D(face, p + Vector3(0, 3.0, 0) + face * Vector3(0, 0, -0.3)), 0.8, 2.0, {"role": &"cloth", "alt_role": &"cloth_alt"})


static func _pavilion(kit: BuildingKit, e: int) -> void:
	var c := PAVILION
	var w := 7.0
	var d := 4.6
	var h := 0.55
	kit.box(c + Vector3(0, h * 0.5, 0), Vector3(w, h, d), &"base", true)
	kit.stairs(c + Vector3(0, 0, d * 0.5 + 1.0), c + Vector3(0, h, d * 0.5), 3.0, {"role": &"stone"})
	var col_h := 3.2
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := c + Vector3(sx * (w * 0.5 - 0.5), h, sz * (d * 0.5 - 0.5))
			match e:
				ElementDefs.Element.WATER: kit.column(p, col_h, 0.22, &"ice", &"ice")
				ElementDefs.Element.EARTH: kit.column(p, col_h, 0.24, &"wood", &"round", &"stone_dark")
				ElementDefs.Element.FIRE: kit.column(p, col_h, 0.22, &"wall", &"round", &"stone_dark")
				_: kit.column(p, col_h, 0.2, &"wood", &"round", &"stone")
	var top := c + Vector3(0, h + col_h, 0)
	kit.box(top + Vector3(0, 0.15, 0), Vector3(w - 0.4, 0.3, d - 0.4), &"trim", false)
	match e:
		ElementDefs.Element.WATER:
			kit.default_slot = &"ice"
			KitRoofs.dome(kit, top + Vector3(0, 0.3, 0), 3.0, {"role": &"ice"})
			kit.default_slot = &"solid"
		ElementDefs.Element.FIRE:
			KitRoofs.pagoda(kit, top + Vector3(0, 0.3, 0), w - 0.6, d - 0.4, 2, {})
		ElementDefs.Element.AIR:
			KitRoofs.cone(kit, top + Vector3(0, 0.3, 0), 3.6, 2.6, {"role": &"roof", "alt_role": &"roof_alt"})
		_:
			KitRoofs.hip(kit, top + Vector3(0, 0.3, 0), w - 0.4, d - 0.4, 1.6, {})
	# a low table with a scroll and incense inside
	kit.box(c + Vector3(0, h + 0.25, -0.6), Vector3(1.6, 0.5, 0.7), &"wood_dark", false)
	kit.g().cylinder(c + Vector3(-0.4, h + 0.52, -0.6), c + Vector3(0.4, h + 0.52, -0.6), 0.06, 0.06, 6, kit.col(&"cloth_alt"), 3)


static func _lights(kit: BuildingKit, e: int) -> void:
	var spots: Array[Vector3] = [Vector3(-RING - 0.2, 0, -6.0), Vector3(RING + 0.2, 0, -6.0), Vector3(-RING + 1.5, 0, 6.5), Vector3(RING - 1.5, 0, 6.5)]
	for p in spots:
		match e:
			ElementDefs.Element.WATER: kit.lantern(p, {"style": &"ice", "height": 1.7})
			ElementDefs.Element.EARTH: kit.lantern(p, {"style": &"stone", "height": 1.8})
			ElementDefs.Element.FIRE: kit.brazier(p, {"height": 1.0, "radius": 0.5})
			_: kit.lantern(p, {"style": &"post", "height": 1.8})
	for sx in [-1.0, 1.0]:
		var p2 := PAVILION + Vector3(sx * 4.6, 0, 1.6)
		if e == ElementDefs.Element.FIRE:
			kit.brazier(p2, {"height": 1.1, "radius": 0.55})
		else:
			kit.lantern(p2, {"style": &"stone" if e == ElementDefs.Element.EARTH else (&"ice" if e == ElementDefs.Element.WATER else &"post"), "height": 1.9})
