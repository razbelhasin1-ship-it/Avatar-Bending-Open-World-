class_name CreatureParts
extends RefCounted
## Reusable body-part builders shared by species: limbs, paws with toes and claws,
## eyes with lids, ears, horns and teeth. All positions are rig space at rest.


## Limb loft through the leg's joints. `radii[i]` = Vector2(half width, half depth) at:
## [top (inside the body), upper joint, lower joint, (meta joint), foot]. The top
## section sits at the hip pulled toward the body center (option `inset`, default 0.5)
## plus `top`, so the limb grows out of the body without a visible cap.
## Options are passed to MeshKit.loft.
static func limb(kit: MeshKit, rig: CreatureRig, l: CreatureLeg, radii: Array, top: Vector3, o: Dictionary = {}) -> void:
	var s := rig.skel
	var hip := s.rest_pos[l.upper]
	var inset: float = o.get("inset", 0.5)
	var pts: Array[Vector3] = [Vector3(hip.x * inset, hip.y, hip.z) + top, hip, s.rest_pos[l.lower]]
	if l.meta >= 0:
		pts.append(s.rest_pos[l.meta])
	pts.append(s.rest_pos[l.foot])
	var secs: Array = []
	for i in pts.size():
		var r: Vector2 = radii[mini(i, radii.size() - 1)]
		var sec := {"p": pts[i], "w": r.x, "h": r.y, "up": Vector3.FORWARD}
		if o.has("fluff_profile"):
			sec["f"] = o["fluff_profile"][mini(i, o["fluff_profile"].size() - 1)]
		secs.append(sec)
	var chain: Array = [s.names[l.upper], s.names[l.lower]]
	if l.meta >= 0:
		chain.append(s.names[l.meta])
	chain.append(s.names[l.foot])
	var oo := o.duplicate()
	oo["weights"] = s.chain_weighter(chain, s.rest_pos[l.foot] + Vector3.DOWN * l.ankle_h, 0.35)
	if not oo.has("cap0"):
		oo["cap0"] = "round"
	if not oo.has("cap1"):
		oo["cap1"] = "round"
	kit.loft(secs, oo)


## Paw: a rounded pad block on the foot bone with `toes` toe bulges and claws.
## size = (half width, half height, half length). Claws go to surface `claw_surface`.
static func paw(kit: MeshKit, rig: CreatureRig, l: CreatureLeg, size: Vector3, toes: int, claw_len: float,
		o: Dictionary = {}, claw_surface: StringName = &"claw", body_surface: StringName = &"fur") -> void:
	var s := rig.skel
	var w := s.rigid_weighter(s.names[l.foot])
	var c := s.rest_pos[l.foot] + Vector3(0, -l.ankle_h + size.y * 0.95, -size.z * 0.35)
	var oo := o.duplicate()
	oo["weights"] = w
	kit.ellipsoid(c, size, oo)
	if toes <= 0:
		return
	var tr := Vector3(size.x / toes * 0.95, size.y * 0.62, size.z * 0.42)
	for t in toes:
		var f := (float(t) + 0.5) / toes * 2.0 - 1.0
		var tc := c + Vector3(f * size.x * 0.78, -size.y * 0.32, -size.z * 0.72 + absf(f) * size.z * 0.18)
		kit.ellipsoid(tc, tr, oo)
		if claw_len > 0.0:
			kit.surface(claw_surface)
			var base := tc + Vector3(0, tr.y * 0.15, -tr.z * 0.75)
			var dir := Vector3(f * 0.15, -0.45, -1.0).normalized()
			var pts := PackedVector3Array([base, base + dir * claw_len * 0.55 + Vector3(0, claw_len * 0.08, 0), base + dir * claw_len])
			kit.tube(pts, PackedFloat32Array([tr.x * 0.42, tr.x * 0.28, 0.0]), {"weights": w, "segs": 6, "sub": 2, "fur": 0.0})
			kit.surface(body_surface)


## Eye + upper lid. The eye bone rotates for look-at, the lid bone for blinks.
static func eye(kit: MeshKit, rig: CreatureRig, eye_bone: StringName, lid_bone: StringName, radius: float,
		look: Vector3, lid_surface: StringName, eye_surface: StringName = &"eye", squash: Vector3 = Vector3.ONE,
		lid_o: Dictionary = {}) -> void:
	var s := rig.skel
	var c := s.rest_pos[s.idx(eye_bone)]
	kit.surface(eye_surface)
	kit.eye(c, radius, look, {"weights": s.rigid_weighter(eye_bone), "scale": squash})
	if lid_bone == &"":
		return
	kit.surface(lid_surface)
	# Upper lid: a dome over the eye, rotated up (open) around the eye center by the lid bone.
	var lr := radius * 1.16
	var z := -look.normalized()
	var secs: Array = []
	var n := 7
	for i in n + 1:
		var a := float(i) / n * PI * 0.5
		secs.append({"p": c + Vector3.UP * lr * squash.y * cos(a), "w": lr * squash.x * sin(a) + 0.0005,
				"h": lr * squash.z * sin(a) + 0.0005, "up": z})
	var oo := lid_o.duplicate()
	oo["weights"] = s.rigid_weighter(lid_bone)
	oo["interp"] = false
	oo["cap0"] = "none"
	oo["cap1"] = "flat"
	oo["fur"] = 0.0
	oo["segs"] = 14
	kit.loft(secs, oo)


## Tapered horn/tusk/spike along a curve, rigid on `bone`.
static func horn(kit: MeshKit, rig: CreatureRig, bone: StringName, pts: PackedVector3Array, base_r: float,
		o: Dictionary = {}) -> void:
	var radii := PackedFloat32Array()
	for i in pts.size():
		var t := float(i) / maxf(pts.size() - 1, 1)
		radii.append(base_r * (1.0 - t) * (1.0 - t * 0.2) + 0.0)
	var oo := o.duplicate()
	oo["weights"] = rig.skel.rigid_weighter(bone)
	if not oo.has("segs"):
		oo["segs"] = 10
	oo["fur"] = 0.0
	kit.tube(pts, radii, oo)


## Flattened ear loft from `base` to `tip`, weighted to `bone`.
## widths = [base, mid, tip] half widths; thickness = half depth.
static func ear(kit: MeshKit, rig: CreatureRig, bone: StringName, base: Vector3, mid: Vector3, tip: Vector3,
		widths: Vector3, thickness: float, o: Dictionary = {}) -> void:
	var up: Vector3 = o.get("face", Vector3.FORWARD)
	var secs := [
		{"p": base, "w": widths.x, "h": thickness, "up": up},
		{"p": mid, "w": widths.y, "h": thickness * 0.8, "up": up},
		{"p": tip, "w": widths.z, "h": thickness * 0.5, "up": up},
	]
	var oo := o.duplicate()
	oo["weights"] = rig.skel.rigid_weighter(bone)
	if not oo.has("cap1"):
		oo["cap1"] = "round"
	kit.loft(secs, oo)


## Row of small conical teeth along a curve (rigid on `bone`), pointing `dir`.
static func teeth(kit: MeshKit, rig: CreatureRig, bone: StringName, pts: PackedVector3Array, dir: Vector3,
		length: float, radius: float) -> void:
	var w := rig.skel.rigid_weighter(bone)
	for p in pts:
		kit.tube(PackedVector3Array([p, p + dir * length * 0.6, p + dir * length]),
				PackedFloat32Array([radius, radius * 0.6, 0.0]), {"weights": w, "segs": 5, "sub": 1, "fur": 0.0})
