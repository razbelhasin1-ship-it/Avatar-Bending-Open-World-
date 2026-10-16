class_name NwtHomes
extends RefCounted
## Water Tribe dwellings (BuildingKit recipes, thread-safe, origin = ground centre of the
## footprint, -Z = front/door). Every recipe has a variant `v` (deterministic sizes, tints and
## options) and reads `kit.lod` (0 full, 1 simplified, 2 silhouette). Foundations reach 1.2 m
## under the origin so small ground undulations never show a gap.
##   dome_home   ice-block drum with a ribbed ice dome, entry vestibule, curtain door
##   block_house stepped snow-block house (1-3 receding storeys): cornices, rounded corner
##               pillars, portico or awning, parapets, a small dome / lookout / roof stair
##   tower_house block house with a slender round tower and a glossy ice spire
##   warehouse   long low harbour store with big doors
##   noble_house walled courtyard compound with a two-storey hall, dome and tower
##   igloo       snow-block igloo with an entry tunnel (villages)
##   hide_tent   hide tent / yurt (fishing camps)


static func _rng(kind: StringName, v: int) -> RandomNumberGenerator:
	return ContentHash.rng(ContentHash.hash4(ContentHash.hash_name(String(kind)), v, 31))


## Footprint (width along the street, depth) of a variant.
static func footprint(kind: StringName, v: int) -> Vector2:
	var r := _rng(kind, v)
	match kind:
		&"dome_home":
			var rad := 3.0 + (v % 4) * 0.45
			return Vector2(rad * 2.0 + 1.2, rad * 2.0 + 2.4)
		&"block_house":
			return Vector2(r.randf_range(7.0, 11.0), r.randf_range(6.0, 9.0))
		&"tower_house":
			return Vector2(r.randf_range(8.0, 10.0), r.randf_range(7.5, 9.0))
		&"warehouse":
			return Vector2(r.randf_range(14.0, 19.0), r.randf_range(9.0, 11.0))
		&"noble_house":
			return Vector2(r.randf_range(18.0, 22.0), r.randf_range(17.0, 20.0))
		&"igloo":
			return Vector2(6.0, 7.0)
		&"hide_tent":
			return Vector2(5.0, 5.0)
	return Vector2(8, 8)


static func build(kit: BuildingKit, kind: StringName, v: int) -> void:
	match kind:
		&"dome_home": dome_home(kit, v)
		&"block_house": block_house(kit, v)
		&"tower_house": tower_house(kit, v)
		&"warehouse": warehouse(kit, v)
		&"noble_house": noble_house(kit, v)
		&"igloo": igloo(kit, v)
		&"hide_tent": hide_tent(kit, v)


## Window on a face of the current frame: local centre `c` on the face plane facing -Z.
static func _win(kit: BuildingKit, c: Vector3, w: float, h: float, lit: bool) -> void:
	if kit.lod >= 2:
		if lit:
			kit.g(&"glow").box(Transform3D(Basis(), c + Vector3(0, 0, -0.05)), Vector3(w * 1.3, h * 1.2, 0.05), kit.col(&"glow") * 0.6)
		return
	KitX.window(kit, c, w, h, NwtStyle.navy(), 0.0, lit)


## Window on a side face at local x = sx * half_w (sx = -1 left, +1 right), centre (y, z).
static func _side_win(kit: BuildingKit, sx: float, half_w: float, y: float, z: float, w: float, h: float, lit: bool) -> void:
	kit.push(Transform3D(Basis(Vector3.UP, -sx * PI * 0.5), Vector3(sx * half_w, y, z)))
	_win(kit, Vector3.ZERO, w, h, lit)
	kit.pop()


## Round ice-block home: drum + ribbed dome + barrel-vault vestibule with a curtain door.
static func dome_home(kit: BuildingKit, v: int) -> void:
	var rng := _rng(&"dome_home", v)
	var r := 3.0 + (v % 4) * 0.45
	var h := 2.3 + rng.randf_range(0.0, 0.9)
	var squash := rng.randf_range(0.72, 0.92)
	var y := 0.35
	var wall := NwtStyle.wall(v)
	kit.cylinder(Vector3(0, -1.2, 0), 1.2 + y, r + 0.45, &"base", 16, true)
	kit.cylinder(Vector3(0, y, 0), h, r, wall, 18, true)
	if kit.lod < 2:
		kit.cylinder(Vector3(0, y + h - 0.32, 0), 0.34, r + 0.08, NwtStyle.navy(), 18, false)
		if kit.lod == 0:
			kit.cylinder(Vector3(0, y, 0), 0.32, r + 0.06, &"base", 18, false)
	for k in 3:
		var a := PI * 0.5 + (k - 1) * 1.15 + PI
		var dir := Vector3(cos(a), 0, sin(a))
		kit.push(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) + PI), dir * (r - 0.02) + Vector3(0, y + h * 0.55, 0)))
		_win(kit, Vector3.ZERO, 0.55, 0.75, (v + k) % 3 == 0)
		kit.pop()
	KitRoofs.dome(kit, Vector3(0, y + h, 0), r + 0.12, {"squash": squash, "role": NwtStyle.dome(v), "rib_role": &"wall_alt",
		"block_lines": true, "slot": &"ice", "finial": kit.lod < 2 and v % 3 == 0, "finial_role": &"trim"})
	# vestibule: two side walls, a vaulted roof and the curtain door
	var vw := 2.4
	var vd := 2.2
	var vh := 2.3
	var z0 := -r + 0.5
	var z1 := z0 - vd
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * (vw * 0.5 - 0.2), y + vh * 0.5 - 0.2, (z0 + z1) * 0.5), Vector3(0.4, vh - 0.4, vd), wall)
	if kit.lod < 2:
		var segs := 7 if kit.lod == 0 else 4
		var vc := NwtStyle.dome(v + 1)
		for i in segs:
			var a0 := PI * float(i) / segs
			var a1 := PI * float(i + 1) / segs
			var p0 := Vector3(cos(a0) * vw * 0.5, y + vh - 0.4 + sin(a0) * 0.8, 0)
			var p1 := Vector3(cos(a1) * vw * 0.5, y + vh - 0.4 + sin(a1) * 0.8, 0)
			kit.g(&"ice").flat_quad(p1 + Vector3(0, 0, z1), p0 + Vector3(0, 0, z1), p0 + Vector3(0, 0, z0), p1 + Vector3(0, 0, z0), vc)
		kit.g().flat_quad(Vector3(-vw * 0.5, y + vh - 0.4, z1), Vector3(vw * 0.5, y + vh - 0.4, z1), Vector3(vw * 0.5, y + vh + 0.4, z1), Vector3(-vw * 0.5, y + vh + 0.4, z1), wall)
		KitX.doorway(kit, Vector3(0, y, z1 + 0.02), 1.2, 2.0, NwtStyle.navy(), &"cloth" if v % 2 == 0 else &"cloth_alt", 0.02)
	else:
		kit.box(Vector3(0, y + vh * 0.5, (z0 + z1) * 0.5), Vector3(vw, vh, vd), wall)
	kit.collide_box(Vector3(0, y + vh + 0.1, (z0 + z1) * 0.5), Vector3(vw, 0.5, vd))
	if kit.lod == 0:
		if v % 2 == 1:
			kit.lantern(Vector3(vw * 0.5 + 0.5, y, z1 + 0.3), {"style": &"ice", "height": 1.3, "light": v % 4 == 1, "range": 7.0})
		else:
			# drying fish line / furs on a rack beside the door
			kit.beam(Vector3(-vw * 0.5 - 0.6, y, z1 + 0.4), Vector3(-vw * 0.5 - 0.6, y + 1.6, z1 + 0.4), 0.06, 0.06, &"wood")
			kit.beam(Vector3(-vw * 0.5 - 0.6, y + 1.55, z1 + 0.4), Vector3(-r - 0.3, y + 1.55, z1 + 2.4), 0.05, 0.05, &"wood")
			kit.box(Vector3(-vw * 0.5 - 0.9, y + 1.1, z1 + 1.2), Vector3(0.05, 0.9, 0.8), Color(0.62, 0.52, 0.42).srgb_to_linear(), false)
		KitX.icicles(kit, Vector3(-r * 0.7, y + h - 0.32, -r * 0.72), Vector3(r * 0.7, y + h - 0.32, -r * 0.72), 1.2, 0.5)
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, z1 - 1.0)))


## Stepped snow-block house: 1-3 storeys receding towards the back.
static func block_house(kit: BuildingKit, v: int) -> void:
	var rng := _rng(&"block_house", v)
	var fp := footprint(&"block_house", v)
	var w := fp.x
	var d := fp.y
	var floors := 1 + (v % 3)
	var y := 0.3
	var wall := NwtStyle.wall(v)
	var wall2 := NwtStyle.wall(v + 3)
	kit.box(Vector3(0, -0.45, 0), Vector3(w + 0.5, 1.5, d + 0.5), &"base")
	var cw := w
	var cd := d
	var cz := 0.0
	for f in floors:
		var fh := rng.randf_range(2.8, 3.4)
		var role: Color = wall if f % 2 == 0 else wall2
		kit.box(Vector3(0, y + fh * 0.5, cz), Vector3(cw, fh, cd), role)
		if kit.lod < 2:
			# cornice + navy band under the parapet
			kit.box(Vector3(0, y + fh - 0.22, cz), Vector3(cw + 0.16, 0.32, cd + 0.16), NwtStyle.navy(), false)
			kit.box(Vector3(0, y + fh + 0.02, cz), Vector3(cw + 0.42, 0.18, cd + 0.42), role, false)
			if kit.lod == 0 and f == 0:
				# rounded ice pillars on the front corners
				for sx: float in [-1.0, 1.0]:
					kit.cylinder(Vector3(sx * (cw * 0.5 - 0.05), y - 0.2, cz - cd * 0.5 + 0.05), fh, 0.32, wall2, 8, false)
				KitX.joints(kit, -cw * 0.5 + 0.3, cw * 0.5 - 0.3, y, y + fh - 0.45, cz - cd * 0.5, 0.9)
				KitX.icicles(kit, Vector3(-cw * 0.5, y + fh - 0.39, cz - cd * 0.5 - 0.09), Vector3(cw * 0.5, y + fh - 0.39, cz - cd * 0.5 - 0.09), 1.0, 0.45)
		# windows: front row (+ sides at LOD0); one lit glow per storey at LOD2
		var nwin := maxi(int((cw - 1.5) / 2.2), 1)
		for i in nwin:
			var wx := lerpf(-cw * 0.5 + 1.2, cw * 0.5 - 1.2, (i + 0.5) / nwin) if nwin > 1 else (cw * 0.28 if f == 0 else 0.0)
			if f == 0 and absf(wx) < 1.4:
				continue
			var lit := ContentHash.unit(ContentHash.hash4(v, f, i)) < 0.35
			if kit.lod < 2 or lit:
				_win(kit, Vector3(wx, y + fh * 0.52, cz - cd * 0.5), 0.6, 0.95, lit)
		if kit.lod == 0:
			for sx: float in [-1.0, 1.0]:
				_side_win(kit, sx, cw * 0.5, y + fh * 0.52, cz, 0.55, 0.85, rng.randf() < 0.25)
		if f == 0 and kit.lod < 2:
			var curtain: StringName = &"cloth" if v % 2 == 0 else &"cloth_alt"
			KitX.doorway(kit, Vector3(0, y, cz - cd * 0.5), 1.25, 2.2, NwtStyle.navy(), curtain, 0.0)
			if v % 3 == 0:
				# portico: two ice pillars, lintel and a little dome canopy over the door
				for sx: float in [-1.0, 1.0]:
					kit.cylinder(Vector3(sx * 1.05, y, cz - cd * 0.5 - 1.1), 2.5, 0.2, wall2, 8, true)
				kit.box(Vector3(0, y + 2.6, cz - cd * 0.5 - 0.6), Vector3(2.6, 0.3, 1.4), NwtStyle.navy(), true)
				if kit.lod == 0:
					KitRoofs.dome(kit, Vector3(0, y + 2.75, cz - cd * 0.5 - 0.6), 0.75, {"squash": 0.8, "role": NwtStyle.dome(v), "slot": &"ice",
						"finial": false, "ribs": false})
			elif v % 3 == 1 and kit.lod == 0:
				# cloth awning on two poles
				var az := cz - cd * 0.5
				for sx: float in [-1.0, 1.0]:
					kit.beam(Vector3(sx * 1.4, y, az - 1.6), Vector3(sx * 1.4, y + 2.3, az - 1.6), 0.07, 0.07, &"wood")
				kit.g(&"cloth").flat_quad(Vector3(-1.6, y + 2.75, az - 0.05), Vector3(1.6, y + 2.75, az - 0.05), Vector3(1.6, y + 2.3, az - 1.7),
						Vector3(-1.6, y + 2.3, az - 1.7), kit.col(&"cloth" if v % 2 == 0 else &"accent", false))
				kit.g(&"cloth").flat_quad(Vector3(-1.6, y + 2.3, az - 1.7), Vector3(1.6, y + 2.3, az - 1.7), Vector3(1.6, y + 2.75, az - 0.05),
						Vector3(-1.6, y + 2.75, az - 0.05), kit.col(&"cloth" if v % 2 == 0 else &"accent", false))
		y += fh
		var nd := cd * rng.randf_range(0.6, 0.75)
		var nw := cw * rng.randf_range(0.7, 0.9)
		var ncz := cz + (cd - nd) * 0.5
		if kit.lod < 2:
			var front := cz - cd * 0.5 + 0.2
			KitX.merlons(kit, Vector3(-cw * 0.5 + 0.25, y + 0.1, front), Vector3(cw * 0.5 - 0.25, y + 0.1, front), 0.36, 0.6, 0.8, 0.5, role)
			if f == floors - 1:
				var back := cz + cd * 0.5 - 0.2
				KitX.merlons(kit, Vector3(cw * 0.5 - 0.25, y + 0.1, back), Vector3(-cw * 0.5 + 0.25, y + 0.1, back), 0.36, 0.6, 0.8, 0.5, role)
				for sx: float in [-1.0, 1.0]:
					KitX.merlons(kit, Vector3(sx * (cw * 0.5 - 0.2), y + 0.1, front), Vector3(sx * (cw * 0.5 - 0.2), y + 0.1, back), 0.36, 0.6, 0.8, 0.5, role)
			if kit.lod == 0:
				kit.box(Vector3(0, y + 0.14, cz), Vector3(cw - 0.7, 0.1, cd - 0.7), &"snow", false)
		if f < floors - 1:
			cw = nw
			cd = nd
			cz = ncz
	# roof feature
	var feat := v % 4
	if feat == 0:
		var dr := minf(cw, cd) * 0.32
		kit.cylinder(Vector3(0, y, cz), 0.9, dr, wall2, 14, true)
		if kit.lod < 2:
			kit.cylinder(Vector3(0, y + 0.7, cz), 0.22, dr + 0.06, NwtStyle.navy(), 14, false)
		KitRoofs.dome(kit, Vector3(0, y + 0.9, cz), dr + 0.1, {"squash": 0.82, "role": NwtStyle.dome(v), "rib_role": &"wall_alt",
			"slot": &"ice", "finial": kit.lod < 2, "finial_role": &"trim"})
	elif feat == 1:
		var lr := minf(cw, cd) * 0.2
		kit.cylinder(Vector3(cw * 0.25, y, cz + cd * 0.15), 2.6, lr, wall, 12, true)
		if kit.lod < 2:
			kit.cylinder(Vector3(cw * 0.25, y + 2.3, cz + cd * 0.15), 0.3, lr + 0.08, NwtStyle.navy(), 12, false)
			_win(kit, Vector3(cw * 0.25, y + 1.5, cz + cd * 0.15 - lr), 0.4, 0.7, v % 8 == 1)
		KitRoofs.cone(kit, Vector3(cw * 0.25, y + 2.6, cz + cd * 0.15), lr + 0.4, lr * 4.0, {"role": NwtStyle.spire(v), "alt_role": NwtStyle.spire(v + 2),
			"slot": &"ice", "flare": 0.15, "trim_role": &"trim", "finial_role": &"trim", "sides": 12})
	elif feat == 2 and kit.lod == 0 and floors < 3:
		# roof terrace: stair up the side wall
		kit.stairs(Vector3(w * 0.5 + 0.6, 0.3, -d * 0.5 + 1.0), Vector3(w * 0.5 + 0.6, y - 0.1, d * 0.5 - 0.8), 1.0, {"role": wall2})
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -d * 0.5 - 1.0)))
	if kit.lod == 0 and v % 3 == 2:
		kit.banner(Transform3D(Basis(), Vector3(-w * 0.5 + 0.9, 3.0, -d * 0.5 - 0.1)), 0.7, 2.2, {"role": &"cloth", "alt_role": &"cloth_alt"})


## Block house with a slender round tower at a back corner, crowned by a glossy ice spire.
static func tower_house(kit: BuildingKit, v: int) -> void:
	var rng := _rng(&"tower_house", v)
	var fp := footprint(&"tower_house", v)
	var w := fp.x
	var d := fp.y
	var y := 0.3
	var h := rng.randf_range(5.6, 6.6)
	var wall := NwtStyle.wall(v + 1)
	var wall2 := NwtStyle.wall(v + 4)
	kit.box(Vector3(0, -0.45, 0), Vector3(w + 0.5, 1.5, d + 0.5), &"base")
	kit.box(Vector3(0, y + h * 0.5, 0), Vector3(w, h, d), wall)
	if kit.lod < 2:
		kit.box(Vector3(0, y + h * 0.5 - 0.1, 0), Vector3(w + 0.1, 0.25, d + 0.1), wall2, false)
		kit.box(Vector3(0, y + h - 0.22, 0), Vector3(w + 0.16, 0.32, d + 0.16), NwtStyle.navy(), false)
		kit.box(Vector3(0, y + h + 0.02, 0), Vector3(w + 0.42, 0.18, d + 0.42), wall, false)
		KitX.doorway(kit, Vector3(0, y, -d * 0.5), 1.3, 2.3, NwtStyle.navy(), &"cloth", 0.0)
		var front := -d * 0.5 + 0.2
		KitX.merlons(kit, Vector3(-w * 0.5 + 0.25, y + h + 0.1, front), Vector3(w * 0.5 - 0.25, y + h + 0.1, front), 0.36, 0.65, 0.8, 0.5, wall)
		if kit.lod == 0:
			KitX.joints(kit, -w * 0.5, w * 0.5, y, y + h - 0.45, -d * 0.5, 1.0)
			kit.box(Vector3(0, y + h + 0.14, 0), Vector3(w - 0.7, 0.1, d - 0.7), &"snow", false)
			KitX.icicles(kit, Vector3(-w * 0.5, y + h - 0.39, -d * 0.5 - 0.09), Vector3(w * 0.5, y + h - 0.39, -d * 0.5 - 0.09), 1.0, 0.5)
	for row in 2:
		var wy := y + (1.6 if row == 0 else h * 0.5 + 1.4)
		for sx: float in [-1.0, 1.0]:
			var lit := ContentHash.unit(ContentHash.hash4(v, row, int(sx))) < 0.35
			if kit.lod < 2 or lit:
				_win(kit, Vector3(sx * w * 0.3, wy, -d * 0.5), 0.6, 0.9, lit)
	# tower
	var side := 1.0 if v % 2 == 0 else -1.0
	var tc := Vector3(side * (w * 0.5 - 1.6), 0.0, d * 0.5 - 1.6)
	var tr := rng.randf_range(1.5, 2.0)
	var th := rng.randf_range(12.0, 18.0)
	kit.cylinder(tc + Vector3(0, y, 0), th, tr, wall2, 14, true)
	if kit.lod < 2:
		for band in [h, th * 0.72]:
			kit.cylinder(tc + Vector3(0, y + band - 0.3, 0), 0.34, tr + 0.08, NwtStyle.navy(), 14, false)
		kit.cylinder(tc + Vector3(0, y + th - 0.2, 0), 0.3, tr + 0.45, wall, 14, true)
		if kit.lod == 0:
			for k in 8:
				var a := TAU * k / 8.0
				kit.box(tc + Vector3(cos(a) * (tr + 0.3), y + th + 0.35, sin(a) * (tr + 0.3)), Vector3(0.4, 0.5, 0.4), wall, false)
	kit.push(Transform3D(Basis(), tc + Vector3(0, y + th * 0.82, -tr)))
	_win(kit, Vector3.ZERO, 0.45, 0.9, true)
	kit.pop()
	var sv := v % 3
	KitRoofs.cone(kit, tc + Vector3(0, y + th + 0.1, 0), tr + 0.25, tr * rng.randf_range(3.6, 5.2), {"role": NwtStyle.spire(sv),
		"alt_role": NwtStyle.spire(sv + 1), "slot": &"ice", "flare": 0.1, "trim_role": &"trim", "finial_role": &"trim", "sides": 14})
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -d * 0.5 - 1.0)))
	kit.mark(&"top", Transform3D(Basis(), tc + Vector3(0, y + th, 0)))


## Long harbour warehouse: low block with two big doors, roof with snow and a hoist beam.
static func warehouse(kit: BuildingKit, v: int) -> void:
	var rng := _rng(&"warehouse", v)
	var fp := footprint(&"warehouse", v)
	var w := fp.x
	var d := fp.y
	var h := rng.randf_range(4.6, 5.6)
	var y := 0.25
	var wall := NwtStyle.wall(v + 2)
	kit.box(Vector3(0, -0.5, 0), Vector3(w + 0.5, 1.5, d + 0.5), &"base")
	kit.box(Vector3(0, y + h * 0.5, 0), Vector3(w, h, d), wall)
	if kit.lod < 2:
		kit.box(Vector3(0, y + h - 0.22, 0), Vector3(w + 0.16, 0.32, d + 0.16), NwtStyle.navy(), false)
		kit.box(Vector3(0, y + h + 0.02, 0), Vector3(w + 0.4, 0.18, d + 0.4), wall, false)
		for sx: float in [-1.0, 1.0]:
			var c := Vector3(sx * w * 0.24, y, -d * 0.5)
			kit.box(c + Vector3(0, 1.5, -0.05), Vector3(2.8, 3.0, 0.08), &"window", false)
			kit.box(c + Vector3(0, 3.1, -0.1), Vector3(3.2, 0.3, 0.2), &"wood_dark", false)
			if kit.lod == 0:
				for k in 3:
					kit.box(c + Vector3(-0.9 + k * 0.9, 1.5, -0.12), Vector3(0.12, 3.0, 0.08), &"wood", false)
		KitX.merlons(kit, Vector3(-w * 0.5 + 0.25, y + h + 0.1, -d * 0.5 + 0.2), Vector3(w * 0.5 - 0.25, y + h + 0.1, -d * 0.5 + 0.2), 0.36, 0.55, 0.9, 0.6, wall)
		if kit.lod == 0:
			kit.box(Vector3(0, y + h + 0.14, 0), Vector3(w - 0.7, 0.1, d - 0.7), &"snow", false)
			kit.beam(Vector3(w * 0.1, y + h + 0.3, -d * 0.5 + 0.4), Vector3(w * 0.1, y + h + 0.3, -d * 0.5 - 1.8), 0.25, 0.25, &"wood")
			kit.g().cylinder(Vector3(w * 0.1, y + h + 0.2, -d * 0.5 - 1.6), Vector3(w * 0.1, y + 2.0, -d * 0.5 - 1.6), 0.02, 0.02, 3, kit.col(&"wood_dark"), 0)
			KitX.icicles(kit, Vector3(-w * 0.5, y + h - 0.39, -d * 0.5 - 0.09), Vector3(w * 0.5, y + h - 0.39, -d * 0.5 - 0.09), 0.8, 0.6)
	if v % 2 == 0:
		_win(kit, Vector3(0, y + h * 0.6, -d * 0.5), 0.8, 0.7, true)
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(w * 0.24, 0, -d * 0.5 - 1.2)))


## Walled courtyard compound of a noble family: low wall with a gate, two-storey hall at the
## back with a dome and a tower, side wing, ice lanterns and banners at the gate.
static func noble_house(kit: BuildingKit, v: int) -> void:
	var rng := _rng(&"noble_house", v)
	var fp := footprint(&"noble_house", v)
	var w := fp.x
	var d := fp.y
	var hx := w * 0.5
	var hz := d * 0.5
	var y := 0.2
	var wall := NwtStyle.wall(v)
	var wall2 := NwtStyle.wall(v + 2)
	# courtyard wall
	var wopts := {"role": wall2, "cap_role": NwtStyle.navy(), "cap": true}
	var gate_w := 3.0
	kit.wall(Vector3(hx, y, -hz), Vector3(gate_w * 0.5 + 0.6, y, -hz), 2.6, 0.6, wopts)
	kit.wall(Vector3(-gate_w * 0.5 - 0.6, y, -hz), Vector3(-hx, y, -hz), 2.6, 0.6, wopts)
	kit.wall(Vector3(-hx, y, -hz), Vector3(-hx, y, hz), 2.6, 0.6, wopts)
	kit.wall(Vector3(hx, y, hz), Vector3(hx, y, -hz), 2.6, 0.6, wopts)
	kit.box(Vector3(0, -0.5, 0), Vector3(w + 0.4, 1.4, d + 0.4), &"base", false)
	for sx: float in [-1.0, 1.0]:
		kit.box(Vector3(sx * (gate_w * 0.5 + 0.3), y + 1.9, -hz), Vector3(0.9, 3.8, 0.9), wall)
		if kit.lod < 2:
			kit.ornament(Vector3(sx * (gate_w * 0.5 + 0.3), y + 3.8, -hz), &"orb", 0.6, NwtStyle.dome(1))
			if kit.lod == 0:
				kit.lantern(Vector3(sx * (gate_w * 0.5 + 1.3), y, -hz - 0.9), {"style": &"ice", "height": 1.6, "light": sx > 0.0, "range": 8.0})
				kit.banner(Transform3D(Basis(), Vector3(sx * (gate_w * 0.5 + 0.3), y + 3.4, -hz - 0.47)), 0.7, 2.4, {"role": &"cloth", "alt_role": &"cloth_alt"})
	if kit.lod < 2:
		kit.box(Vector3(0, y + 3.9, -hz), Vector3(gate_w + 1.8, 0.5, 1.0), NwtStyle.navy())
	# main hall (back)
	var mw := w - 3.0
	var md := d * 0.42
	var mz := hz - md * 0.5 - 0.8
	var h1 := 4.0
	var h2 := 3.2
	kit.box(Vector3(0, y + h1 * 0.5, mz), Vector3(mw, h1, md), wall)
	kit.box(Vector3(0, y + h1 + h2 * 0.5, mz + md * 0.12), Vector3(mw * 0.7, h2, md * 0.76), wall2)
	if kit.lod < 2:
		kit.box(Vector3(0, y + h1 - 0.2, mz), Vector3(mw + 0.16, 0.34, md + 0.16), NwtStyle.navy(), false)
		kit.box(Vector3(0, y + h1 + 0.03, mz), Vector3(mw + 0.4, 0.18, md + 0.4), wall, false)
		kit.box(Vector3(0, y + h1 + h2 - 0.2, mz + md * 0.12), Vector3(mw * 0.7 + 0.16, 0.32, md * 0.76 + 0.16), NwtStyle.navy(), false)
		KitX.doorway(kit, Vector3(0, y, mz - md * 0.5), 1.8, 2.8, NwtStyle.navy(), &"cloth", 0.0)
		for sx: float in [-1.0, 1.0]:
			kit.cylinder(Vector3(sx * 1.6, y, mz - md * 0.5 - 1.2), 3.6, 0.28, wall2, 8, true)
		kit.box(Vector3(0, y + 3.75, mz - md * 0.5 - 0.7), Vector3(4.2, 0.35, 1.6), NwtStyle.navy(), true)
		KitX.merlons(kit, Vector3(-mw * 0.5 + 0.25, y + h1 + 0.1, mz - md * 0.5 + 0.2), Vector3(mw * 0.5 - 0.25, y + h1 + 0.1, mz - md * 0.5 + 0.2), 0.36, 0.6, 0.8, 0.5, wall)
	for i in 4:
		var wx := lerpf(-mw * 0.38, mw * 0.38, i / 3.0)
		var lit := ContentHash.unit(ContentHash.hash4(v, i, 9)) < 0.45
		if absf(wx) > 1.5 and (kit.lod < 2 or lit):
			_win(kit, Vector3(wx, y + 2.0, mz - md * 0.5), 0.7, 1.1, lit)
		if kit.lod < 2:
			_win(kit, Vector3(wx * 0.7, y + h1 + 1.6, mz + md * 0.12 - md * 0.38), 0.6, 0.9, ContentHash.unit(ContentHash.hash4(v, i, 11)) < 0.4)
	var dr := minf(mw * 0.7, md * 0.76) * 0.36
	KitRoofs.dome(kit, Vector3(0, y + h1 + h2, mz + md * 0.12), dr, {"squash": 0.9, "role": NwtStyle.dome(v + 2), "rib_role": &"wall_alt",
		"slot": &"ice", "finial": kit.lod < 2, "finial_role": &"trim"})
	# tower in a back corner
	var sx2 := 1.0 if v % 2 == 0 else -1.0
	var tc := Vector3(sx2 * (hx - 2.2), 0, hz - 2.2)
	var th := rng.randf_range(15.0, 21.0)
	kit.cylinder(tc + Vector3(0, y, 0), th, 1.9, wall, 14, true)
	if kit.lod < 2:
		kit.cylinder(tc + Vector3(0, y + th - 0.3, 0), 0.42, 2.4, NwtStyle.navy(), 14, false)
		kit.cylinder(tc + Vector3(0, y + th * 0.55, 0), 0.3, 2.0, NwtStyle.navy(), 14, false)
	kit.push(Transform3D(Basis(), tc + Vector3(0, y + th * 0.8, -1.9)))
	_win(kit, Vector3.ZERO, 0.5, 1.0, true)
	kit.pop()
	KitRoofs.cone(kit, tc + Vector3(0, y + th + 0.1, 0), 2.3, rng.randf_range(7.0, 9.5), {"role": NwtStyle.spire(v), "alt_role": NwtStyle.spire(v + 1),
		"slot": &"ice", "flare": 0.12, "trim_role": &"trim", "finial_role": &"trim", "sides": 14})
	# side wing
	var ww := w * 0.3
	var wd := d * 0.35
	var wx2 := -sx2 * (hx - ww * 0.5 - 0.4)
	kit.box(Vector3(wx2, y + 1.6, -hz * 0.1), Vector3(ww, 3.2, wd), wall2)
	if kit.lod < 2:
		kit.box(Vector3(wx2, y + 3.0, -hz * 0.1), Vector3(ww + 0.14, 0.3, wd + 0.14), NwtStyle.navy(), false)
		kit.push(Transform3D(Basis(Vector3.UP, -sx2 * PI * 0.5), Vector3(wx2 + sx2 * ww * 0.5, y, -hz * 0.1)))
		KitX.doorway(kit, Vector3.ZERO, 1.1, 2.1, NwtStyle.navy(), &"cloth_alt", 0.0)
		kit.pop()
		KitRoofs.dome(kit, Vector3(wx2, y + 3.2, -hz * 0.1), minf(ww, wd) * 0.35, {"squash": 0.8, "role": NwtStyle.dome(v + 1), "slot": &"ice", "finial": false, "ribs": false})
	if kit.lod == 0:
		# courtyard: ice sculpture on a plinth, paving
		kit.box(Vector3(0, y + 0.3, -hz * 0.35), Vector3(1.6, 0.6, 1.6), &"stone_dark")
		kit.cylinder(Vector3(0, y + 0.6, -hz * 0.35), 1.6, 0.35, &"ice", 6, true, 0.05, &"ice")
		kit.box(Vector3(0, y + 0.06, -hz * 0.35), Vector3(w - 2.0, 0.08, d * 0.45), &"floor", false)
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -hz - 1.2)))
	kit.mark(&"interior", Transform3D(Basis(), Vector3(0, y, -hz * 0.35)))


## Snow-block igloo with an entry tunnel and a vent; v varies the size.
static func igloo(kit: BuildingKit, v: int) -> void:
	var r := 2.1 + (v % 3) * 0.35
	var snow := NwtStyle.SNOW.srgb_to_linear()
	kit.cylinder(Vector3(0, -0.8, 0), 0.85, r + 0.1, snow, 14, true)
	KitRoofs.dome(kit, Vector3(0, 0.0, 0), r, {"squash": 0.95, "role": snow, "block_lines": true, "ribs": false,
		"finial": false})
	kit.collide_box(Vector3(0, r * 0.45, 0), Vector3(r * 1.6, r * 0.9, r * 1.6))
	var tw := 1.3
	var tl := 1.6
	var z0 := -r + 0.4
	var segs := 6 if kit.lod == 0 else 3
	for i in segs:
		var a0 := PI * float(i) / segs
		var a1 := PI * float(i + 1) / segs
		var p0 := Vector3(cos(a0) * tw * 0.5, sin(a0) * tw * 0.75, 0)
		var p1 := Vector3(cos(a1) * tw * 0.5, sin(a1) * tw * 0.75, 0)
		kit.g().flat_quad(p1 + Vector3(0, 0, z0 - tl), p0 + Vector3(0, 0, z0 - tl), p0 + Vector3(0, 0, z0), p1 + Vector3(0, 0, z0), snow * 0.96)
	if kit.lod < 2:
		var dark := kit.col(&"window", false)
		for i in segs:
			var a0 := PI * float(i) / segs
			var a1 := PI * float(i + 1) / segs
			kit.g().flat_tri(Vector3(0, 0, z0 - tl + 0.02), Vector3(cos(a1) * tw * 0.42, sin(a1) * tw * 0.65, z0 - tl + 0.02),
					Vector3(cos(a0) * tw * 0.42, sin(a0) * tw * 0.65, z0 - tl + 0.02), dark)
	kit.collide_box(Vector3(0, tw * 0.5, z0 - tl * 0.5), Vector3(tw, tw * 0.75, tl))
	if kit.lod == 0 and v % 2 == 0:
		kit.g().cylinder(Vector3(0, r * 0.9, 0.3), Vector3(0, r * 0.9 + 0.35, 0.3), 0.18, 0.14, 6, kit.col(&"stone_dark"), 2)
	if v % 3 == 1:
		# warm light glowing through an ice window
		_win(kit, Vector3(0, r * 0.55, -r * 0.7), 0.4, 0.4, true)
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, z0 - tl - 0.8)))


## Hide tent of the fishing camps: yurt (v even) or tipi (v odd) in hide colours.
static func hide_tent(kit: BuildingKit, v: int) -> void:
	var hide := Color(0.74, 0.62, 0.48).srgb_to_linear()
	var hide2 := Color(0.56, 0.44, 0.33).srgb_to_linear()
	if v % 2 == 0:
		BuildingPresets.tent(kit, Transform3D(), {"style": &"yurt", "w": 4.4, "h": 3.2, "role": hide, "alt_role": &"cloth"})
	else:
		BuildingPresets.tent(kit, Transform3D(), {"style": &"tipi", "w": 3.8, "h": 4.2, "role": hide, "alt_role": hide2})
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -3.0)))
