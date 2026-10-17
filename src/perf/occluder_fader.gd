class_name OccluderFader
extends Node
## Screen-door fade of characters that block the view of the player (perf_polish).
##
## NPCs, companions and wildlife are not camera blockers (the camera never pushes in for them),
## so one standing between the camera and the player - or right at the lens - used to hide the
## player or fill the screen. The fader (a child of PlayerCamera) casts rays from the camera to
## the player's feet, chest and head and checks a sphere around the lens, 15 times a second;
## whatever it hits on Layers.NPC | COMPANION | WILDLIFE fades to a 72 % screen door in 0.15 s
## and back in 0.3 s once clear:
##   * toon-shaded humanoids: a per-surface override with a twin material on
##     src/perf/shaders/toon_dither.gdshader (+ outline_dither) carrying every parameter of the
##     original; the original override (hit flash, status) is put back afterwards,
##   * creatures: their shaders' `occlusion_fade` instance uniform (creature_common.gdshaderinc).
## The shared toon material of buildings never gets a discard. Only in the default camera mode
## (riding, flight and cinematics restore everything); the ridden mount is never faded.

const RATE := 15.0
## Screen-door share of an occluder (0 solid .. 1 gone).
const FADE := 0.72
const FADE_OUT_S := 0.15
const FADE_BACK_S := 0.3
const MASK := Layers.NPC | Layers.COMPANION | Layers.WILDLIFE
## Anything this close to the lens fades as well (an NPC or the companion right behind the player).
const LENS_RADIUS := 0.85
const TOON_DITHER := preload("res://src/perf/shaders/toon_dither.gdshader")
const OUTLINE_DITHER := preload("res://src/perf/shaders/outline_dither.gdshader")

## The camera rig this fader serves (set by PlayerCamera).
var rig: Node3D = null
## body instance id -> {"body": WeakRef, "fade": float, "target": float, "geos": Array (WeakRef), "saved": Dictionary}
var faded: Dictionary = {}

static var _twins: Dictionary = {}       # source material instance id -> twin ShaderMaterial
var _timer := 0.0
var _lens_shape := SphereShape3D.new()


func _ready() -> void:
	_lens_shape.radius = LENS_RADIUS


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.0 / RATE
		_scan()
	_animate(delta)


func _exit_tree() -> void:
	for id: int in faded.keys():
		_restore(faded[id])
	faded.clear()


## Bodies currently faded (or fading back), for tests.
func faded_bodies() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for id: int in faded:
		var b: Node3D = (faded[id]["body"] as WeakRef).get_ref()
		if b != null:
			out.append(b)
	return out


## Current fade (0..FADE) of a body, 0 when it is not faded.
func fade_of(body: Node) -> float:
	if body == null or not faded.has(body.get_instance_id()):
		return 0.0
	return float(faded[body.get_instance_id()]["fade"])


func _scan() -> void:
	var hits := {}
	var cam: Camera3D = rig.get("camera") if rig != null else null
	var follow: Node3D = rig.get("target") if rig != null else null
	var active := cam != null and follow != null and is_instance_valid(follow) and follow.is_inside_tree() \
			and StringName(rig.get("mode")) == &"default" and cam.is_inside_tree()
	if active:
		var space := cam.get_world_3d().direct_space_state
		var from := cam.global_position
		var skip: Array[RID] = []
		if follow is CollisionObject3D:
			skip.append((follow as CollisionObject3D).get_rid())
		var mount: Variant = follow.get("mount") if "mount" in follow else null
		for h in [0.35, 1.15, 1.6]:
			var to: Vector3 = follow.global_position + Vector3.UP * float(h)
			var ex := skip.duplicate()
			for k in 3:
				var q := PhysicsRayQueryParameters3D.create(from, to, MASK, ex)
				var r := space.intersect_ray(q)
				if r.is_empty():
					break
				var c: Object = r["collider"]
				if c is Node3D and c != mount:
					hits[(c as Node3D).get_instance_id()] = c
				ex.append(r["rid"])
		var sp := PhysicsShapeQueryParameters3D.new()
		sp.shape = _lens_shape
		sp.transform = Transform3D(Basis.IDENTITY, from)
		sp.collision_mask = MASK
		sp.exclude = skip
		for r: Dictionary in space.intersect_shape(sp, 8):
			var c: Object = r["collider"]
			if c is Node3D and c != mount:
				hits[(c as Node3D).get_instance_id()] = c
	for id: int in faded:
		faded[id]["target"] = 0.0
	for id: int in hits:
		var b: Node3D = hits[id]
		if b.is_in_group(&"player"):
			continue
		if not faded.has(id):
			faded[id] = {"body": weakref(b), "fade": 0.0, "target": FADE, "geos": [], "saved": {}}
		faded[id]["target"] = FADE


func _animate(delta: float) -> void:
	for id: int in faded.keys():
		var e: Dictionary = faded[id]
		var b: Node3D = (e["body"] as WeakRef).get_ref()
		if b == null or not is_instance_valid(b) or not b.is_inside_tree():
			faded.erase(id)
			continue
		var f := float(e["fade"])
		var t := float(e["target"])
		if t > f:
			f = minf(t, f + delta * FADE / FADE_OUT_S)
		else:
			f = maxf(t, f - delta * FADE / FADE_BACK_S)
		e["fade"] = f
		if f <= 0.0 and t <= 0.0:
			_restore(e)
			faded.erase(id)
		else:
			_apply(e, b, f)


func _apply(e: Dictionary, body: Node3D, f: float) -> void:
	if (e["geos"] as Array).is_empty():
		var stack: Array[Node] = [body]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				(e["geos"] as Array).append(weakref(n))
	var saved: Dictionary = e["saved"]
	for w: WeakRef in e["geos"]:
		var mi := w.get_ref() as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			continue
		if _has_instance_param(mi, &"occlusion_fade"):
			mi.set_instance_shader_parameter(&"occlusion_fade", f)
			continue
		for s in mi.mesh.get_surface_count():
			var cur := mi.get_surface_override_material(s)
			var key := "%d|%d" % [mi.get_instance_id(), s]
			var twin: ShaderMaterial = null
			if saved.has(key):
				twin = saved[key][1]
				if cur != twin:
					# the owner replaced the override meanwhile (hit flash): twin the new one
					saved.erase(key)
					twin = null
			if twin == null:
				var src := mi.get_active_material(s)
				twin = twin_of(src)
				if twin == null:
					continue
				saved[key] = [cur, twin, weakref(mi), s]
				mi.set_surface_override_material(s, twin)
			twin.set_shader_parameter(&"dither_fade", f)
			if twin.next_pass is ShaderMaterial:
				(twin.next_pass as ShaderMaterial).set_shader_parameter(&"dither_fade", f)


func _restore(e: Dictionary) -> void:
	var saved: Dictionary = e["saved"]
	for key: String in saved:
		var rec: Array = saved[key]
		var mi := (rec[2] as WeakRef).get_ref() as MeshInstance3D
		if mi != null and is_instance_valid(mi) and mi.get_surface_override_material(int(rec[3])) == rec[1]:
			mi.set_surface_override_material(int(rec[3]), rec[0])
	saved.clear()
	for w: WeakRef in e["geos"]:
		var mi := w.get_ref() as MeshInstance3D
		if mi != null and is_instance_valid(mi) and _has_instance_param(mi, &"occlusion_fade"):
			mi.set_instance_shader_parameter(&"occlusion_fade", 0.0)


static func _has_instance_param(mi: MeshInstance3D, pname: StringName) -> bool:
	if mi.has_meta(&"occl_param"):
		return bool(mi.get_meta(&"occl_param"))
	var found := false
	for d: Dictionary in RenderingServer.instance_geometry_get_shader_parameter_list(mi.get_instance()):
		if StringName(d.get("name", "")) == pname:
			found = true
			break
	mi.set_meta(&"occl_param", found)
	return found


## The dithering twin of a toon material (cached per source), or null for any other material.
static func twin_of(src: Material) -> ShaderMaterial:
	var sm := src as ShaderMaterial
	if sm == null or sm.shader != ToonMaterials.TOON_SHADER:
		return null
	var id := sm.get_instance_id()
	if _twins.has(id):
		var t: ShaderMaterial = _twins[id]
		if t != null:
			return t
	var twin := _copy(sm, TOON_DITHER)
	if sm.next_pass is ShaderMaterial and (sm.next_pass as ShaderMaterial).shader == ToonMaterials.OUTLINE_SHADER:
		twin.next_pass = _copy(sm.next_pass as ShaderMaterial, OUTLINE_DITHER)
	_twins[id] = twin
	return twin


static func _copy(src: ShaderMaterial, shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	for u: Dictionary in src.shader.get_shader_uniform_list():
		var n := StringName(u["name"])
		m.set_shader_parameter(n, src.get_shader_parameter(n))
	return m
