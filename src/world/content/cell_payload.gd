class_name CellPayload
extends RefCounted
## Standard, renderer-free result of ContentProvider.build_cell (filled on a worker thread).
## WorldContent turns it into nodes on the main thread, one entry per time-sliced step:
##
##   var p := CellPayload.new()
##   p.add_multimesh(mesh, material, buffer, count, aabb, {"shadow": true, "vis_end": 300.0})
##   p.add_mesh(builder.arrays(), material, Transform3D.IDENTITY, {"vis_end": 900.0})
##   p.add_collider(&"cylinder", world_xform, Vector3(radius, height, 0))   # pooled, near focus only
##   p.add_static_faces(builder.faces())                                    # always-on collision
##   p.add_call(func(cell: ContentCell) -> void: cell.root.add_child(make_light()))
##   cell.payload = p
##
## All transforms/AABBs of multimeshes, meshes and static faces are relative to the cell root
## (`cell.origin()`, the cell centre at y = 0). Collider transforms are in world space.
##
## MultiMesh buffers use Godot's layout: per instance 12 floats (3x4 transform, row-major:
## basis.x.x, basis.y.x, basis.z.x, origin.x, basis.x.y, ...), followed by 4 custom-data floats
## when `custom` is true. Use `write_instance()` to append one.

## {"mesh", "material", "buffer", "count", "custom", "aabb", "shadow", "vis_begin", "vis_end",
##  "margin", "layers", "tag", "sorted"}
var multimeshes: Array[Dictionary] = []
## {"surfaces": [[arrays, material], ...], "transform", "shadow", "vis_begin", "vis_end", "margin", "tag"}
var meshes: Array[Dictionary] = []
## Pooled near-focus colliders: {"type": &"cylinder"|&"box"|&"sphere"|&"capsule", "transform": Transform3D
## (world), "size": Vector3 (cylinder/capsule: radius, height; box: full size; sphere: radius)}.
var colliders: Array[Dictionary] = []
## Always-on static collision of the cell: {"faces": PackedVector3Array (relative to root), "layer": int}
## or {"boxes": [[Transform3D, Vector3 size], ...], "layer": int}.
var static_bodies: Array[Dictionary] = []
## Main-thread callables `func(cell: ContentCell) -> void`, run once each (lights, particles,
## audio loops, interactables). Add nodes under `cell.root` so they are freed with the cell.
var calls: Array[Callable] = []
## Instances (multimesh) + meshes, for statistics.
var instance_count: int = 0


## Appends one instance to a MultiMesh buffer (transform relative to the cell root).
static func write_instance(buf: PackedFloat32Array, t: Transform3D, custom: Color = Color(1, 1, 1, 0), with_custom: bool = true) -> void:
	var b := t.basis
	buf.append(b.x.x); buf.append(b.y.x); buf.append(b.z.x); buf.append(t.origin.x)
	buf.append(b.x.y); buf.append(b.y.y); buf.append(b.z.y); buf.append(t.origin.y)
	buf.append(b.x.z); buf.append(b.y.z); buf.append(b.z.z); buf.append(t.origin.z)
	if with_custom:
		buf.append(custom.r); buf.append(custom.g); buf.append(custom.b); buf.append(custom.a)


## Reads instance `i` back from a buffer (tests, debugging).
static func read_instance(buf: PackedFloat32Array, i: int, with_custom: bool = true) -> Transform3D:
	var k := i * (16 if with_custom else 12)
	return Transform3D(Basis(Vector3(buf[k], buf[k + 4], buf[k + 8]), Vector3(buf[k + 1], buf[k + 5], buf[k + 9]),
			Vector3(buf[k + 2], buf[k + 6], buf[k + 10])), Vector3(buf[k + 3], buf[k + 7], buf[k + 11]))


func add_multimesh(mesh: Mesh, material: Material, buffer: PackedFloat32Array, count: int, aabb: AABB, opts: Dictionary = {}) -> void:
	if count <= 0:
		return
	var d := {"mesh": mesh, "material": material, "buffer": buffer, "count": count, "custom": opts.get("custom", true),
		"aabb": aabb, "shadow": opts.get("shadow", false), "vis_begin": float(opts.get("vis_begin", 0.0)),
		"vis_end": float(opts.get("vis_end", 0.0)), "margin": float(opts.get("margin", 0.0)),
		"layers": int(opts.get("layers", 1)), "tag": opts.get("tag", &""), "sorted": opts.get("sorted", false)}
	multimeshes.append(d)
	instance_count += count


## One mesh from surfaces [[arrays, material], ...] (or a single arrays + material).
func add_mesh(arrays: Array, material: Material, t: Transform3D = Transform3D.IDENTITY, opts: Dictionary = {}) -> void:
	if arrays.is_empty() or (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
		return
	add_mesh_surfaces([[arrays, material]], t, opts)


func add_mesh_surfaces(surfaces: Array, t: Transform3D = Transform3D.IDENTITY, opts: Dictionary = {}) -> void:
	var keep: Array = []
	for s: Array in surfaces:
		var arr: Array = s[0]
		if not arr.is_empty() and arr[Mesh.ARRAY_INDEX] != null and not (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
			keep.append(s)
	if keep.is_empty():
		return
	meshes.append({"surfaces": keep, "transform": t, "shadow": opts.get("shadow", true),
		"vis_begin": float(opts.get("vis_begin", 0.0)), "vis_end": float(opts.get("vis_end", 0.0)),
		"margin": float(opts.get("margin", 0.0)), "tag": opts.get("tag", &""), "layers": int(opts.get("layers", 1))})
	instance_count += 1


func add_collider(type: StringName, world_xform: Transform3D, size: Vector3) -> void:
	colliders.append({"type": type, "transform": world_xform, "size": size})


func add_static_faces(faces: PackedVector3Array, layer: int = Layers.WORLD) -> void:
	if not faces.is_empty():
		static_bodies.append({"faces": faces, "layer": layer})


## boxes: [[Transform3D (relative to root), Vector3 size], ...]
func add_static_boxes(boxes: Array, layer: int = Layers.WORLD) -> void:
	if not boxes.is_empty():
		static_bodies.append({"boxes": boxes, "layer": layer})


func add_call(c: Callable) -> void:
	calls.append(c)


## Number of main-thread steps needed to instantiate this payload.
func step_count() -> int:
	return multimeshes.size() + meshes.size() + (1 if not static_bodies.is_empty() else 0) + calls.size() + 1


func is_empty() -> bool:
	return multimeshes.is_empty() and meshes.is_empty() and colliders.is_empty() and static_bodies.is_empty() and calls.is_empty()
