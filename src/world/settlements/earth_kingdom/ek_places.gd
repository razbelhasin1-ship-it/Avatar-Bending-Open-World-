class_name EkPlaces
extends RefCounted
## Enterable Earth Kingdom interiors (BuildingKit recipes, thread-safe; origin = ground centre,
## -Z = the door side). Walls are hollow with real openings, floors and ceilings collide, the
## lights inside are interior lights (they also shine by day, never become night glows).
##   tea_shop       the Lower Ring tea shop: counter and tea-jar shelves, a stove with a kettle,
##                  low tables with cushions, hanging lanterns, scrolls, a sign over the door
##   training_hall  the earthbending hall of the Middle Ring: sand arena, rock pillars and
##                  practice boulders, the master's dais under green banners, braziers

const TEA_W := 14.0
const TEA_D := 12.0
const HALL_W := 24.0
const HALL_D := 18.0


static func build(kit: BuildingKit, kind: StringName, _spec: Dictionary) -> void:
	match kind:
		&"tea_shop": tea_shop(kit)
		&"training_hall": training_hall(kit)


static func _interior_light(kit: BuildingKit, pos: Vector3, col: Color, range_m: float, energy: float) -> void:
	kit.add_light(pos, col, range_m, energy, 3)
	kit.lights[kit.lights.size() - 1]["interior"] = true


static func tea_shop(kit: BuildingKit) -> void:
	var w := TEA_W
	var d := TEA_D
	var hw := w * 0.5
	var hd := d * 0.5
	var style := EkStyle.LOWER
	var tim := EkStyle.timber(EkStyle.MIDDLE)
	var wall_c := EkStyle.wall(EkStyle.MIDDLE, 0)
	var bh := 0.5
	var h := 3.8
	kit.box(Vector3(0, bh * 0.5, 0), Vector3(w + 0.8, bh, d + 0.8), EkStyle.base(style))
	kit.stairs(Vector3(0, 0, -hd - 1.6), Vector3(0, bh, -hd - 0.4), 3.0, {"role": EkStyle.base(style)})
	var wo := {"role": wall_c, "cap_role": tim, "base_role": EkStyle.base(style), "piers": 2.4, "pier_role": tim}
	kit.wall(Vector3(hw, bh, -hd), Vector3(-hw, bh, -hd), h, 0.3, wo.merged({"openings": [
		{"t": 0.5, "width": 2.6, "height": 2.7, "kind": &"door", "leaf": &"open", "frame_role": tim},
		{"t": 0.17, "width": 1.6, "height": 1.2, "kind": &"window", "sill": 1.0, "frame_role": tim},
		{"t": 0.83, "width": 1.6, "height": 1.2, "kind": &"window", "sill": 1.0, "frame_role": tim}]}, true))
	kit.wall(Vector3(-hw, bh, hd), Vector3(hw, bh, hd), h, 0.3, wo.merged({"openings": [
		{"t": 0.78, "width": 1.1, "height": 2.2, "kind": &"door", "leaf": &"closed", "frame_role": tim}]}, true))
	kit.wall(Vector3(hw, bh, hd), Vector3(hw, bh, -hd), h, 0.3, wo.merged({"openings": [{"t": 0.5, "width": 1.4, "height": 1.2, "kind": &"window", "sill": 1.0, "frame_role": tim}]}, true))
	kit.wall(Vector3(-hw, bh, -hd), Vector3(-hw, bh, hd), h, 0.3, wo.merged({"openings": [{"t": 0.5, "width": 1.4, "height": 1.2, "kind": &"window", "sill": 1.0, "frame_role": tim}]}, true))
	kit.box(Vector3(0, bh + 0.05, 0), Vector3(w - 0.5, 0.1, d - 0.5), EkStyle.timber(EkStyle.FARM), true)
	kit.box(Vector3(0, bh + h - 0.06, 0), Vector3(w - 0.4, 0.12, d - 0.4), &"interior", false)
	var ro := EkStyle.roof_opts(EkStyle.MIDDLE, 1, {"overhang": 1.2, "curve": 0.7})
	RoofsLite.hip(kit, Vector3(0, bh + h, 0), w, d, 3.6, ro)
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -hd - 2.2)))
	kit.mark(&"interior", Transform3D(Basis(), Vector3(0, bh + 0.1, 0)))
	if kit.lod >= 2:
		return
	var y := bh + 0.1
	# sign board over the door + lanterns outside
	kit.box(Vector3(0, bh + h + 0.25, -hd - 0.35), Vector3(3.4, 0.8, 0.12), tim, false)
	kit.box(Vector3(0, bh + h + 0.25, -hd - 0.42), Vector3(3.0, 0.55, 0.04), EkStyle.CLOTH_GOLD, false)
	for sx: float in [-1.0, 1.0]:
		KitX.lantern(kit, Vector3(sx * 2.2, bh + 2.9, -hd - 0.6), {"style": &"paper", "light": sx > 0.0, "range": 8.0, "color": Color(1.0, 0.58, 0.28)})
	if kit.lod > 0:
		_interior_light(kit, Vector3(0, y + 2.6, 0), Color(1.0, 0.74, 0.44), 11.0, 1.4)
		return
	# counter + shelves of tea jars along the back
	kit.box(Vector3(-1.0, y + 0.55, hd - 2.4), Vector3(6.0, 1.1, 0.7), tim, true)
	kit.box(Vector3(-1.0, y + 1.12, hd - 2.4), Vector3(6.2, 0.06, 0.85), EkStyle.timber(EkStyle.UPPER), false)
	kit.box(Vector3(-1.0, y + 1.3, hd - 0.4), Vector3(7.0, 2.6, 0.4), tim, true)
	for row in 3:
		kit.box(Vector3(-1.0, y + 0.6 + row * 0.75, hd - 0.68), Vector3(6.8, 0.05, 0.42), EkStyle.timber(EkStyle.FARM), false)
		for k in 9:
			var jp := Vector3(-4.2 + k * 0.8, y + 0.63 + row * 0.75, hd - 0.68)
			var jc: Color = [Color(0.60, 0.32, 0.18), Color(0.30, 0.46, 0.34), Color(0.80, 0.72, 0.52)][(k + row) % 3]
			kit.g().cylinder(jp, jp + Vector3(0, 0.36, 0), 0.15, 0.12, 6, kit.col(jc.srgb_to_linear()), 2)
	# stove with a glowing fire and the kettle
	var sp := Vector3(hw - 1.6, y, hd - 1.6)
	kit.box(sp + Vector3(0, 0.5, 0), Vector3(1.6, 1.0, 1.2), EkStyle.base(EkStyle.LOWER), true)
	var gb := kit.g(&"glow")
	gb.uv = Vector2(0, 1)
	gb.box(Transform3D(Basis(), sp + Vector3(0, 0.45, -0.62)), Vector3(0.7, 0.35, 0.04), Color(1.0, 0.45, 0.15))
	kit.g().cylinder(sp + Vector3(0, 1.0, 0), sp + Vector3(0, 1.35, 0), 0.28, 0.22, 8, kit.col(EkStyle.WALL_DARK), 2)
	kit.g().cylinder(sp + Vector3(0.3, 1.25, 0), sp + Vector3(0.55, 1.4, 0), 0.04, 0.03, 4, kit.col(EkStyle.WALL_DARK), 0)
	_interior_light(kit, sp + Vector3(0, 1.2, -0.8), Color(1.0, 0.55, 0.25), 6.0, 1.2)
	# low tables with cushions + stools
	var tables := [Vector3(-3.6, 0, -2.2), Vector3(0.6, 0, -2.6), Vector3(4.0, 0, -1.8), Vector3(-3.2, 0, 1.0), Vector3(3.8, 0, 1.4)]
	for i in tables.size():
		var tp: Vector3 = tables[i] + Vector3(0, y, 0)
		kit.cylinder(tp, 0.55, 0.65, tim, 10, true)
		kit.g().cylinder(tp + Vector3(0, 0.55, 0), tp + Vector3(0, 0.62, 0), 0.12, 0.1, 6, kit.col(Color(0.92, 0.90, 0.84)), 2)
		for s in 4:
			var a := TAU * s / 4.0 + 0.4 * i
			kit.box(tp + Vector3(cos(a) * 1.05, 0.12, sin(a) * 1.05), Vector3(0.55, 0.24, 0.55), EkStyle.AWNINGS[(i + s) % 5], false)
	# hanging lanterns (interior lights), scrolls, plants
	for k in 3:
		var lp := Vector3(lerpf(-hw * 0.55, hw * 0.55, k / 2.0), y + h - 1.1, -0.6)
		kit.lantern(lp, {"style": &"paper", "light": false, "color": Color(1.0, 0.70, 0.40)})
		if k != 1:
			_interior_light(kit, lp, Color(1.0, 0.72, 0.42), 9.0, 1.3)
	for k in 2:
		KitX.banner(kit, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-hw + 0.2, y + 3.0, -1.5 + k * 3.0)), 0.7, 1.6, Color(0.90, 0.86, 0.74), EkStyle.COPING, &"none")
	for sx: float in [-1.0, 1.0]:
		kit.g().cylinder(Vector3(sx * (hw - 0.8), y, -hd + 0.8), Vector3(sx * (hw - 0.8), y + 0.5, -hd + 0.8), 0.3, 0.25, 8, kit.col(Color(0.5, 0.3, 0.2).srgb_to_linear()), 2)
		kit.g().blob(Vector3(sx * (hw - 0.8), y + 1.0, -hd + 0.8), 0.5, 1, kit.col(Color(0.24, 0.46, 0.20).srgb_to_linear()), kit.rng, 0.25)


static func training_hall(kit: BuildingKit) -> void:
	var w := HALL_W
	var d := HALL_D
	var hw := w * 0.5
	var hd := d * 0.5
	var h := 7.0
	var bh := 0.6
	var stone := EkStyle.WALL_STONE
	var tim := EkStyle.timber(EkStyle.MIDDLE)
	kit.box(Vector3(0, bh * 0.5, 0), Vector3(w + 1.6, bh, d + 1.6), EkStyle.WALL_DARK)
	kit.stairs(Vector3(0, 0, -hd - 2.4), Vector3(0, bh, -hd - 0.8), 5.0, {"role": EkStyle.WALL_DARK})
	var wo := {"role": stone, "cap_role": EkStyle.COPING, "base_role": EkStyle.WALL_DARK, "piers": 3.0, "pier_role": EkStyle.WALL_STONE_2}
	var clere := []
	for k in 5:
		clere.append({"t": (k + 0.5) / 5.0, "width": 1.6, "height": 1.0, "kind": &"window", "sill": h - 1.8, "frame_role": tim})
	kit.wall(Vector3(hw, bh, -hd), Vector3(-hw, bh, -hd), h, 0.6, wo.merged({"openings": [
		{"t": 0.5, "width": 4.0, "height": 4.2, "kind": &"gate", "leaf": &"open", "frame_role": EkStyle.WALL_DARK}]}, true))
	kit.wall(Vector3(-hw, bh, hd), Vector3(hw, bh, hd), h, 0.6, wo.merged({"openings": clere}, true))
	kit.wall(Vector3(hw, bh, hd), Vector3(hw, bh, -hd), h, 0.6, wo.merged({"openings": clere.slice(0, 4)}, true))
	kit.wall(Vector3(-hw, bh, -hd), Vector3(-hw, bh, hd), h, 0.6, wo.merged({"openings": clere.slice(1, 5)}, true))
	var y := bh
	kit.box(Vector3(0, y + 0.05, 0), Vector3(w - 1.0, 0.1, d - 1.0), EkStyle.PAVING, true)
	kit.box(Vector3(0, y + h - 0.08, 0), Vector3(w - 0.8, 0.16, d - 0.8), &"interior", false)
	var ro := EkStyle.roof_opts(EkStyle.MIDDLE, 0, {"overhang": 1.4, "curve": 0.8})
	KitRoofs.hip(kit, Vector3(0, y + h, 0), w, d, 4.6, ro.merged({"ornaments": true}, true))
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -hd - 3.0)))
	kit.mark(&"interior", Transform3D(Basis(), Vector3(0, y + 0.1, 0)))
	if kit.lod >= 2:
		return
	KitX.emblem_earth(kit, Vector3(0, y + h + 1.0, -hd - 0.5), 2.2, EkStyle.GOLD, 0.1)
	for sx: float in [-1.0, 1.0]:
		KitX.banner(kit, Transform3D(Basis(), Vector3(sx * 4.2, y + h - 0.6, -hd - 0.4)), 1.4, 4.4, EkStyle.CLOTH_GREEN, EkStyle.CLOTH_GOLD, &"earth")
		kit.brazier(Vector3(sx * 4.2, 0.0, -hd - 3.4), {"height": 1.0, "radius": 0.55, "range": 10.0})
	if kit.lod > 0:
		_interior_light(kit, Vector3(0, y + 4.0, 0), Color(1.0, 0.72, 0.42), 16.0, 1.4)
		return
	# sand arena with a stone border
	kit.box(Vector3(0, y + 0.12, -1.0), Vector3(12.0, 0.04, 9.0), EkStyle.FIELD_DIRT.lightened(0.25), false)
	for sz: float in [-1.0, 1.0]:
		kit.box(Vector3(0, y + 0.18, -1.0 + sz * 4.6), Vector3(12.4, 0.16, 0.3), EkStyle.WALL_DARK, false)
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * 6.2, y + 0.18, -1.0), Vector3(0.3, 0.16, 9.2), EkStyle.WALL_DARK, false)
	# rock pillars along the walls, practice boulders
	for sx: float in [-1.0, 1.0]:
		for k in 3:
			var pp := Vector3(sx * (hw - 2.2), y, lerpf(-hd + 3.0, hd - 4.0, k / 2.0))
			var ph := 2.2 + float((k + int(sx > 0.0)) % 3) * 0.6
			kit.box(pp + Vector3(0, ph * 0.5, 0), Vector3(1.1, ph, 1.1), EkStyle.base(EkStyle.LOWER), true)
			kit.g().blob(pp + Vector3(0, ph + 0.15, 0), 0.6, 0, kit.col(EkStyle.base(EkStyle.LOWER)), kit.rng, 0.35, Vector3(1.0, 0.5, 1.0))
	for k in 4:
		var bp := Vector3(-4.0 + k * 2.6, y + 0.1, -4.2 + (k % 2) * 6.0)
		var s := 0.5 + (k % 3) * 0.15
		kit.g().blob(bp + Vector3(0, s, 0), s, 1, kit.col(EkStyle.base(EkStyle.LOWER) * 0.92), kit.rng, 0.3)
		kit.collide_box(bp + Vector3(0, s, 0), Vector3(s * 1.6, s * 2.0, s * 1.6))
	# the master's dais under banners, a stone seat
	var dz := hd - 2.6
	kit.box(Vector3(0, y + 0.3, dz), Vector3(8.0, 0.6, 3.6), EkStyle.WALL_DARK, true)
	kit.stairs(Vector3(0, y, dz - 2.6), Vector3(0, y + 0.6, dz - 1.8), 3.0, {"role": EkStyle.WALL_DARK})
	kit.box(Vector3(0, y + 0.9, dz + 0.6), Vector3(1.6, 0.6, 1.0), EkStyle.base(EkStyle.UPPER), true)
	kit.box(Vector3(0, y + 1.7, dz + 1.05), Vector3(1.6, 1.4, 0.2), EkStyle.base(EkStyle.UPPER), false)
	for sx: float in [-1.0, 1.0]:
		KitX.banner(kit, Transform3D(Basis(Vector3.UP, PI), Vector3(sx * 2.4, y + h - 0.5, hd - 0.4)), 1.6, 4.6, EkStyle.CLOTH_GREEN, EkStyle.CLOTH_GOLD, &"earth")
		kit.brazier(Vector3(sx * 3.4, y + 0.6, dz - 0.6), {"height": 0.8, "radius": 0.45, "light": false})
		_interior_light(kit, Vector3(sx * 3.4, y + 2.2, dz - 0.6), Color(1.0, 0.56, 0.24), 12.0, 1.8)
	KitX.emblem_earth(kit, Vector3(0, y + 4.2, hd - 0.4), 2.0, EkStyle.GOLD, 0.0)
	_interior_light(kit, Vector3(0, y + 4.5, -2.0), Color(1.0, 0.78, 0.5), 14.0, 1.2)
