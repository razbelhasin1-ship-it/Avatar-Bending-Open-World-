class_name FireMarks
extends Node3D
## Persistent burn marks left by fire (docs/modules/bending_fire.md "Environment"):
## a charred, sooty patch whose embers glow orange and cool to black over a few
## seconds, then the mark stays and fades out late (fights leave scars). Projected
## Decal on Forward+ / Mobile (it also darkens grass blades inside its box, so
## burnt grass reads as charred stubble), a flat ground quad on Compatibility.
## Pooled and capped per quality tier; the oldest mark is recycled first.
##
##   FireMarks.burn(self, ground_pos, 1.4)                  # round burn
##   FireMarks.burn(self, ground_pos, 1.0, {"stretch": 2.5, "dir": fwd})   # streak
##   FireMarks.burn(self, p, 0.8, {"glow": 0.0})           # cold soot (no embers)
##   FireMarks.ring(self, center, 6.0)                       # a scorched ring (Fire Ring, Inferno)

## Max live round marks per effects tier (Mobile renderer: 3, it allows 8 decals per mesh).
const CAPS: Array[int] = [5, 9, 14, 22]
const RING_CAPS: Array[int] = [1, 2, 3, 4]
## Seconds a mark stays per tier (fades over the last 30 %).
const LIFE: Array[float] = [14.0, 24.0, 40.0, 60.0]
## Seconds the embers take to cool.
const COOL := 5.0

var decal: Decal = null
var quad: MeshInstance3D = null
var quad_mat: StandardMaterial3D = null
var t := 0.0
var life := 30.0
var glow := 1.0

static var _tex: Dictionary = {}
## Marks spawned (tests).
static var spawned := 0


static func cap(shape: StringName = &"burn") -> int:
	if Settings.is_mobile_renderer():
		return 3 if shape == &"burn" else 1
	return (CAPS if shape == &"burn" else RING_CAPS)[FxLib.tier()]


## Leaves a burn mark at a ground point. opts: glow (0..1.5 embers), stretch (>1 =
## a streak along `dir`), dir (Vector3), normal (ground normal), life (s).
static func burn(from: Node, pos: Vector3, radius: float = 1.2, opts: Dictionary = {}) -> FireMarks:
	return _spawn(&"burn", from, pos, radius, opts)


## A scorched ring of `radius` (the outer edge) around a ground point.
static func ring(from: Node, center: Vector3, radius: float, opts: Dictionary = {}) -> FireMarks:
	var o := opts.duplicate()
	o["stretch"] = 1.0
	return _spawn(&"ring", from, center, radius, o)


static func _spawn(shape: StringName, from: Node, pos: Vector3, radius: float, opts: Dictionary) -> FireMarks:
	if from == null or not is_instance_valid(from) or not from.is_inside_tree():
		return null
	var kind := StringName("fire_mark_" + String(shape))
	FxLib.set_cap(kind, cap(shape))
	var m := FxLib.take(from, kind, func() -> Node3D: return FireMarks._make(shape)) as FireMarks
	var n: Vector3 = opts.get("normal", Vector3.UP)
	n = n.normalized() if n.length_squared() > 0.01 else Vector3.UP
	var dir: Vector3 = opts.get("dir", Vector3.ZERO)
	dir = (dir - n * dir.dot(n))
	if dir.length_squared() < 0.01:
		dir = n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD).rotated(n, randf() * TAU)
	dir = dir.normalized()
	var x := n.cross(dir).normalized()
	var stretch := maxf(1.0, float(opts.get("stretch", 1.0)))
	m.global_transform = Transform3D(Basis(x, n, -dir).orthonormalized(), pos + n * 0.03)
	m.scale = Vector3(radius, maxf(1.0, radius * 0.25), radius * stretch)
	m.t = 0.0
	m.life = float(opts.get("life", LIFE[FxLib.tier()]))
	m.glow = clampf(float(opts.get("glow", 1.0)), 0.0, 1.5)
	m._apply(1.0, m.glow)
	spawned += 1
	return m


static func _make(shape: StringName) -> FireMarks:
	var m := FireMarks.new()
	m.name = "FireMark_%s" % shape
	if Settings.is_compatibility_renderer():
		m.quad = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2, 2)
		m.quad.mesh = pm
		m.quad_mat = StandardMaterial3D.new()
		m.quad_mat.albedo_texture = texture(shape, &"albedo")
		m.quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.quad_mat.emission_enabled = true
		m.quad_mat.emission_texture = texture(shape, &"emission")
		m.quad_mat.emission = Color(1.0, 0.45, 0.12)
		m.quad_mat.render_priority = -1
		m.quad.material_override = m.quad_mat
		m.quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.add_child(m.quad)
	else:
		m.decal = Decal.new()
		m.decal.size = Vector3(2.0, 1.2, 2.0)
		m.decal.texture_albedo = texture(shape, &"albedo")
		m.decal.texture_emission = texture(shape, &"emission")
		m.decal.emission_energy = 1.0
		m.decal.upper_fade = 0.35
		m.decal.lower_fade = 0.35
		m.decal.normal_fade = 0.0
		m.decal.cull_mask = 1
		m.add_child(m.decal)
	return m


func fx_reset() -> void:
	t = life


func _apply(alpha: float, ember: float) -> void:
	if decal:
		decal.modulate = Color(1, 1, 1, alpha)
		decal.emission_energy = ember * 2.2
	elif quad_mat:
		quad_mat.albedo_color = Color(1, 1, 1, alpha)
		quad_mat.emission_energy_multiplier = ember * 2.0


func _process(delta: float) -> void:
	t += delta
	var ember := glow * clampf(1.0 - t / COOL, 0.0, 1.0)
	ember *= ember
	# Embers breathe while they cool.
	ember *= 0.8 + 0.2 * sin(t * 9.0 + global_position.x)
	var fade_start := life * 0.7
	var a := 1.0 if t < fade_start else clampf(1.0 - (t - fade_start) / maxf(life - fade_start, 0.01), 0.0, 1.0)
	_apply(a, ember)
	if t >= life:
		FxLib.release(self)


## Baked textures (src/fx/fire/textures/gen_fire_marks.py) for a shape (&"burn",
## &"ring"): &"albedo" (soot + scorched rim, alpha) or &"emission" (embers).
static func texture(shape: StringName, which: StringName) -> Texture2D:
	var key := "%s_%s" % [shape, which]
	if not _tex.has(key):
		_tex[key] = load("res://src/fx/fire/textures/%s.png" % key)
	return _tex[key]
