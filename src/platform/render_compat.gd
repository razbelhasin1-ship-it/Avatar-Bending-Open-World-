class_name RenderCompat
extends RefCounted
## Renderer workarounds found by the mobile / Web pass (docs/modules/mobile.md).
##
## Compatibility renderer (Web builds, GLES3 devices), Godot 4.7: a MultiMesh with per-instance
## custom data but WITHOUT instance colours can feed garbage into the shader's COLOR in the
## real world scene (vegetation drew saturated red / blue / magenta / black, birds flapped
## wrongly) - although the same data renders correctly in an isolated scene. Giving those
## MultiMeshes white instance colours fixes it (verified in the world with
## tests/playtest/scenarios/mobile_veg_world_probe.gd). Forward+ / Mobile are untouched.
##
##   RenderCompat.configure(mm, true)            # before instance_count (sets use_colors too)
##   mm.instance_count = n
##   mm.buffer = RenderCompat.buffer_for(mm, buf) # stride 16 (xform + custom) -> 20 when needed
##   RenderCompat.whiten(mm)                     # per-instance API users: white colours

const WHITE := [1.0, 1.0, 1.0, 1.0]

static var _needed := -1


## True when MultiMeshes with custom data also need (white) instance colours.
static func multimesh_colors_needed() -> bool:
	if _needed < 0:
		_needed = 1 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 0
	return _needed == 1


## Sets use_custom_data (and use_colors where needed). Call while instance_count == 0.
static func configure(mm: MultiMesh, custom: bool) -> void:
	mm.use_custom_data = custom
	mm.use_colors = custom and multimesh_colors_needed()


## The buffer to upload for `mm`: a TRANSFORM_3D + custom buffer (16 floats per instance)
## gets white colours inserted (20 floats) when `mm` uses colours; anything else is returned
## unchanged.
static func buffer_for(mm: MultiMesh, buf: PackedFloat32Array) -> PackedFloat32Array:
	if not (mm.use_colors and mm.use_custom_data) or mm.transform_format != MultiMesh.TRANSFORM_3D:
		return buf
	var n := mm.instance_count
	if buf.size() != n * 16:
		return buf
	return add_white(buf, n)


## Stride-16 (xform + custom) -> stride-20 (xform + white colour + custom).
static func add_white(buf: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n * 20)
	for i in n:
		var s := i * 16
		var d := i * 20
		for k in 12:
			out[d + k] = buf[s + k]
		out[d + 12] = 1.0
		out[d + 13] = 1.0
		out[d + 14] = 1.0
		out[d + 15] = 1.0
		out[d + 16] = buf[s + 12]
		out[d + 17] = buf[s + 13]
		out[d + 18] = buf[s + 14]
		out[d + 19] = buf[s + 15]
	return out


## Per-instance API users: makes every instance colour white (no-op without colours).
static func whiten(mm: MultiMesh) -> void:
	if not mm.use_colors:
		return
	for i in mm.instance_count:
		mm.set_instance_color(i, Color.WHITE)
