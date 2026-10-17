class_name EarthWaveFx
extends Node3D
## The visible front of an earth shockwave: rings of stone shards that burst up
## out of the ground as the wave passes, leaning outward, then sink back, with
## dust kicked up along the front. One MultiMesh (one draw call). Gameplay hits
## are delivered separately by EarthShockwave on the same timing.
##
##   EarthWaveFx.spawn(self, center, 5.0, 0.28, &"dirt", ground_fn, {"rings": 3, "per_ring": 10, "height": 0.7})

const MAX := 48

var mmi: MultiMeshInstance3D
var t := 0.0
## Per instance: [pop time, base Transform3D (unscaled), peak height, width]
var _items: Array = []
var _dust: Array = []
var _surface: StringName = &"dirt"
var _life := 0.0


static func spawn(from: Node, center: Vector3, radius: float, duration: float, surface: StringName, ground_fn: Callable, opts: Dictionary = {}) -> EarthWaveFx:
	var w := FxLib.take(from, &"earth_wave", EarthWaveFx._make) as EarthWaveFx
	w.global_transform = Transform3D(Basis.IDENTITY, center)
	w._surface = surface
	w.t = 0.0
	w._items.clear()
	w._dust.clear()
	var rings := int(opts.get("rings", 3))
	var per := int(opts.get("per_ring", 10))
	var height := float(opts.get("height", 0.7))
	var inner := float(opts.get("inner", 0.3))
	var keep := float(opts.get("keep", 0.12))
	var scale_k := clampf(FxLib.scale(), 0.5, 1.2)
	per = maxi(4, int(round(per * scale_k)))
	w.mmi.multimesh.mesh = EarthMeshes.spike(1.0, 0.32, randi() % 4, surface, 0.35)
	var n := 0
	for ri in rings:
		var rr := radius * lerpf(inner, 1.0, float(ri + 1) / rings)
		var a0 := randf() * TAU
		for i in per:
			if n >= MAX:
				break
			var a := a0 + TAU * float(i) / per + randf_range(-0.2, 0.2)
			var dir := Vector3(sin(a), 0.0, -cos(a))
			var p := center + dir * rr * randf_range(0.92, 1.08)
			p.y = float(ground_fn.call(p)) if ground_fn.is_valid() else center.y
			# -Z of the spike mesh leans outward, along the wave.
			var b := Basis.looking_at(dir, Vector3.UP).rotated(Vector3.UP, randf_range(-0.3, 0.3))
			var hk := height * randf_range(0.7, 1.25) * lerpf(1.0, 0.75, float(ri) / maxf(rings - 1, 1))
			w._items.append([rr / radius * duration, Transform3D(b, p - center), hk, randf_range(0.8, 1.2)])
			n += 1
		# A few dust puffs on each ring.
		for k in 3:
			var a := randf() * TAU
			var p := center + Vector3(sin(a), 0.0, -cos(a)) * rr
			p.y = float(ground_fn.call(p)) if ground_fn.is_valid() else center.y
			w._dust.append([rr / radius * duration, p, false])
	w.mmi.multimesh.visible_instance_count = n
	for i in n:
		w.mmi.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)), (w._items[i][1] as Transform3D).origin))
	w._life = duration + keep + 0.45
	return w


static func _make() -> EarthWaveFx:
	var w := EarthWaveFx.new()
	w.name = "EarthWave"
	w.mmi = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	w.mmi.multimesh = mm
	w.mmi.material_override = EarthMeshes.material()
	w.mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(w.mmi)
	return w


func fx_reset() -> void:
	t = _life


func _process(delta: float) -> void:
	t += delta
	var mm := mmi.multimesh
	for i in mini(_items.size(), mm.visible_instance_count):
		var it: Array = _items[i]
		var lt := t - float(it[0])
		var k := 0.0
		if lt > 0.0:
			if lt < 0.07:
				k = lt / 0.07
			elif lt < 0.19:
				k = 1.0
			else:
				k = clampf(1.0 - (lt - 0.19) / 0.26, 0.0, 1.0)
		var base: Transform3D = it[1]
		var h := float(it[2]) * maxf(k, 0.001)
		var wd := float(it[3]) * float(it[2]) * maxf(minf(k * 2.0, 1.0), 0.001)
		mm.set_instance_transform(i, Transform3D(base.basis * Basis.from_scale(Vector3(wd, h, wd)), base.origin + Vector3.DOWN * 0.15 * (1.0 - k)))
	for d: Array in _dust:
		if not bool(d[2]) and t >= float(d[0]):
			d[2] = true
			FxBurst.spawn(self, &"dust", d[1], {"color": EarthPalette.color(_surface, "dust"), "count": 0.35, "size": 0.7, "speed": 0.8})
	if t >= _life:
		mm.visible_instance_count = 0
		FxLib.release(self)
