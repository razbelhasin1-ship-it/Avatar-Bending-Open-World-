class_name FnPlaces
extends RefCounted
## Enterable Fire Nation interiors (BuildingKit recipes, thread-safe; origin = ground centre,
## -Z = the door side; interior lights shine by day):
##   fn_dojo        the firebending dojo of the Noble Quarter: a long hall with a scorched practice
##                  floor, a row of flame jets (braziers) along the walls, the master's dais
##                  under a great flame emblem, red banners, weapon racks, open clerestory
##   noble_interior a noble's reception house: lacquered floor, a low table with cushions, folding
##                  screens painted gold, a shrine with candles, scrolls, the family's banner

const DOJO_W := 22.0
const DOJO_D := 16.0
const NOBLE_W := 16.0
const NOBLE_D := 12.0


static func build(kit: BuildingKit, kind: StringName, _spec: Dictionary) -> void:
	match kind:
		&"fn_dojo": dojo(kit)
		&"noble_interior": noble_interior(kit)


static func _interior_light(kit: BuildingKit, pos: Vector3, col: Color, range_m: float, energy: float) -> void:
	kit.add_light(pos, col, range_m, energy, 3)
	kit.lights[kit.lights.size() - 1]["interior"] = true


static func _shell(kit: BuildingKit, w: float, d: float, h: float, bh: float, door_w: float, wall_c: Color, windows: bool) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	var wo := {"role": wall_c, "cap_role": FnStyle.BLACK, "base_role": FnStyle.BASALT_DARK, "piers": 2.6, "pier_role": FnStyle.RED_DARK}
	var win := []
	if windows:
		for k in 4:
			win.append({"t": (k + 0.5) / 4.0, "width": 1.4, "height": 1.2, "kind": &"window", "sill": h - 2.0, "frame_role": FnStyle.GOLD})
	kit.wall(Vector3(hw, bh, -hd), Vector3(-hw, bh, -hd), h, 0.45, wo.merged({"openings": [
		{"t": 0.5, "width": door_w, "height": 3.6, "kind": &"gate", "leaf": &"open", "frame_role": FnStyle.GOLD}]}, true))
	kit.wall(Vector3(-hw, bh, hd), Vector3(hw, bh, hd), h, 0.45, wo.merged({"openings": win}, true))
	kit.wall(Vector3(hw, bh, hd), Vector3(hw, bh, -hd), h, 0.45, wo.merged({"openings": win.slice(0, 3)}, true))
	kit.wall(Vector3(-hw, bh, -hd), Vector3(-hw, bh, hd), h, 0.45, wo.merged({"openings": win.slice(1, 4)}, true))


static func dojo(kit: BuildingKit) -> void:
	var w := DOJO_W
	var d := DOJO_D
	var hw := w * 0.5
	var hd := d * 0.5
	var h := 6.6
	var bh := 0.8
	kit.box(Vector3(0, bh * 0.5, 0), Vector3(w + 1.6, bh, d + 1.6), FnStyle.BASALT_DARK)
	kit.stairs(Vector3(0, 0, -hd - 2.8), Vector3(0, bh, -hd - 0.8), 5.0, {"role": FnStyle.BASALT_2})
	_shell(kit, w, d, h, bh, 4.0, FnStyle.wall(FnStyle.NOBLE, 0), true)
	var y := bh
	kit.box(Vector3(0, y + 0.05, 0), Vector3(w - 0.9, 0.1, d - 0.9), FnStyle.PAVING_DARK, true)
	kit.box(Vector3(0, y + h - 0.08, 0), Vector3(w - 0.6, 0.16, d - 0.6), FnStyle.RED_DARK, false)
	var ro := FnStyle.roof_opts(FnStyle.NOBLE, 0, {"overhang": 1.6, "curve": 1.0})
	KitRoofs.hip(kit, Vector3(0, y + h, 0), w, d, 4.6, ro.merged({"ornaments": false}, true))
	FnStyle.flame_finial(kit, Vector3(0, y + h + 4.7, 0), 1.6)
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -hd - 3.2)))
	kit.mark(&"interior", Transform3D(Basis(), Vector3(0, y + 0.1, 0)))
	if kit.lod >= 2:
		return
	KitX.emblem_fire(kit, Vector3(0, y + h + 1.2, -hd - 0.5), 2.2, FnStyle.GOLD, 0.1)
	for sx: float in [-1.0, 1.0]:
		KitX.banner(kit, Transform3D(Basis(), Vector3(sx * 4.4, y + h - 0.5, -hd - 0.35)), 1.4, 4.4, FnStyle.CLOTH_RED, FnStyle.CLOTH_GOLD, &"fire", 2)
		kit.push(Transform3D(Basis(), Vector3(sx * 4.4, 0.0, -hd - 3.8)))
		FnWalls.brazier(kit, 0)
		kit.pop()
	if kit.lod > 0:
		_interior_light(kit, Vector3(0, y + 4.0, 0), Color(1.0, 0.6, 0.3), 16.0, 1.4)
		return
	# scorched practice floor with the flame inlay
	kit.box(Vector3(0, y + 0.12, -1.0), Vector3(12.0, 0.04, 9.0), FnStyle.SCORCH, false)
	FnCivic.flame_inlay(kit, Vector3(0, y + 0.145, -1.0), 6.0, FnStyle.RED)
	# flame jets along the side walls (interior lights), weapon racks
	for sx: float in [-1.0, 1.0]:
		for k in 3:
			var p := Vector3(sx * (hw - 1.2), y + 0.1, lerpf(-hd + 3.0, hd - 4.0, k / 2.0))
			kit.push(Transform3D(Basis(), p))
			FnWalls.brazier(kit, 0)
			kit.pop()
			if k == 1:
				_interior_light(kit, p + Vector3(0, 2.4, 0), Color(1.0, 0.5, 0.2), 10.0, 1.6)
		var rp := Vector3(sx * (hw - 0.6), y, -hd + 1.6)
		kit.box(rp + Vector3(0, 1.0, 0), Vector3(0.3, 2.0, 2.4), FnStyle.RED_DARK, true)
		for k in 3:
			kit.beam(rp + Vector3(-sx * 0.2, 0.3, -0.8 + k * 0.8), rp + Vector3(-sx * 0.2, 2.0, -0.8 + k * 0.8), 0.05, 0.05, FnStyle.STEEL)
	# the master's dais
	var dz := hd - 2.4
	kit.box(Vector3(0, y + 0.35, dz), Vector3(7.0, 0.7, 3.2), FnStyle.BASALT, true)
	kit.stairs(Vector3(0, y, dz - 2.4), Vector3(0, y + 0.7, dz - 1.6), 3.0, {"role": FnStyle.BASALT_2})
	kit.box(Vector3(0, y + 0.95, dz + 0.5), Vector3(1.6, 0.5, 1.0), FnStyle.RED, true)
	KitX.emblem_fire(kit, Vector3(0, y + 4.0, hd - 0.3), 2.6, FnStyle.GOLD, 0.0)
	for sx: float in [-1.0, 1.0]:
		KitX.banner(kit, Transform3D(Basis(Vector3.UP, PI), Vector3(sx * 2.8, y + h - 0.4, hd - 0.3)), 1.6, 4.4, FnStyle.CLOTH_RED, FnStyle.CLOTH_GOLD, &"fire", 2)
		kit.push(Transform3D(Basis(), Vector3(sx * 3.2, y + 0.7, dz - 0.6)))
		FnWalls.brazier(kit, 0)
		kit.pop()
	_interior_light(kit, Vector3(0, y + 3.6, dz - 1.0), Color(1.0, 0.56, 0.25), 13.0, 1.8)


static func noble_interior(kit: BuildingKit) -> void:
	var w := NOBLE_W
	var d := NOBLE_D
	var hw := w * 0.5
	var hd := d * 0.5
	var h := 4.4
	var bh := 1.0
	kit.box(Vector3(0, bh * 0.5, 0), Vector3(w + 2.4, bh, d + 2.4), FnStyle.BASALT)
	kit.stairs(Vector3(0, 0, -hd - 3.4), Vector3(0, bh, -hd - 1.2), 4.0, {"role": FnStyle.BASALT_2})
	_shell(kit, w, d, h, bh, 2.6, FnStyle.wall(FnStyle.NOBLE, 1), false)
	var y := bh
	kit.box(Vector3(0, y + 0.05, 0), Vector3(w - 0.9, 0.1, d - 0.9), FnStyle.RED_DARK, true)
	kit.box(Vector3(0, y + h - 0.08, 0), Vector3(w - 0.6, 0.16, d - 0.6), FnStyle.BLACK, false)
	var ro := FnStyle.roof_opts(FnStyle.NOBLE, 1, {"overhang": 1.4, "curve": 1.0})
	RoofsLite.hip(kit, Vector3(0, y + h, 0), w, d, 1.3, ro.merged({"overhang": 1.4, "horns": false}, true))
	kit.box(Vector3(0, y + h + 0.9 + 0.8, 0.2), Vector3(w * 0.7, 1.6, d * 0.6), FnStyle.wall(FnStyle.NOBLE, 2))
	RoofsLite.hip(kit, Vector3(0, y + h + 2.5, 0.2), w * 0.7, d * 0.6, 2.6, ro)
	FnStyle.flame_finial(kit, Vector3(0, y + h + 5.2, 0.2), 1.0)
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -hd - 3.6)))
	kit.mark(&"interior", Transform3D(Basis(), Vector3(0, y + 0.1, 0)))
	if kit.lod >= 2:
		return
	for i in 6:
		kit.column(Vector3(lerpf(-hw + 0.6, hw - 0.6, i / 5.0), bh, -hd - 0.6), h, 0.2, FnStyle.RED, &"round", FnStyle.BASALT_DARK)
	if kit.lod > 0:
		_interior_light(kit, Vector3(0, y + 3.0, 0), Color(1.0, 0.66, 0.4), 11.0, 1.3)
		return
	# low table + cushions, gold folding screens, a shrine with candles, scrolls
	kit.box(Vector3(0, y + 0.42, 0.6), Vector3(3.0, 0.12, 1.4), FnStyle.BLACK, true)
	for sx: float in [-1.0, 1.0]:
		for k in 2:
			kit.box(Vector3(sx * 2.0, y + 0.16, 0.6 + (k - 0.5) * 0.8), Vector3(0.7, 0.16, 0.7), FnStyle.RED, false)
	for k in 4:
		var x := -2.4 + k * 1.6
		kit.box_t(Transform3D(Basis(Vector3.UP, 0.35 if k % 2 == 0 else -0.35), Vector3(x, y + 1.0, hd - 1.6)), Vector3(1.6, 2.0, 0.06), FnStyle.GOLD * 0.9, false)
	var sh := Vector3(hw - 1.2, y, 0)
	kit.box(sh + Vector3(0, 0.6, 0), Vector3(1.0, 1.2, 2.4), FnStyle.BLACK, true)
	var gb := kit.g(&"glow")
	gb.uv = Vector2(0, 1)
	for k in 3:
		var cp := sh + Vector3(-0.1, 1.2, -0.7 + k * 0.7)
		kit.g().cylinder(cp, cp + Vector3(0, 0.25, 0), 0.05, 0.05, 5, kit.col(Color(0.95, 0.9, 0.8)), 2)
		gb.cone(cp + Vector3(0, 0.25, 0), cp + Vector3(0, 0.38, 0), 0.04, 4, Color(1.0, 0.7, 0.3))
	_interior_light(kit, sh + Vector3(-0.6, 1.6, 0), Color(1.0, 0.66, 0.35), 7.0, 1.2)
	KitX.banner(kit, Transform3D(Basis(Vector3.UP, PI), Vector3(0, y + h - 0.3, hd - 0.3)), 1.6, 2.8, FnStyle.CLOTH_RED, FnStyle.CLOTH_GOLD, &"fire", 2)
	for sx: float in [-1.0, 1.0]:
		KitX.banner(kit, Transform3D(Basis(Vector3.UP, -sx * PI * 0.5), Vector3(sx * (hw - 0.3), y + 3.2, -1.0)), 0.7, 1.6, Color(0.92, 0.88, 0.78), FnStyle.BLACK, &"none")
		kit.lantern(Vector3(sx * 3.0, y + h - 1.0, -1.5), {"style": &"paper", "light": false, "color": Color(1.0, 0.5, 0.25)})
		_interior_light(kit, Vector3(sx * 3.0, y + h - 1.0, -1.5), Color(1.0, 0.6, 0.32), 8.0, 1.2)
