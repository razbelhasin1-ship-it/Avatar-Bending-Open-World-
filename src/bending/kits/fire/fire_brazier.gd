class_name FireBrazier
extends Node3D
## A fire you light with firebending and put out with water or wind: the ready-made
## implementation of the IGNITE and EXTINGUISH hooks (FireEnv). Three looks, all in the
## toon style with ink outlines:
##   &"brazier"  bronze fire bowl with a flared rim on three legs (Fire Nation)
##   &"torch"    a wooden pole with a black iron cage head
##   &"lantern"  a stone lantern (pedestal, post, fire box with paper windows, roof)
## Lit by any fire reaching it (FireEnv.heat / ignite_at, or a fire hit on its
## FireHitProxy); doused by water hits, strong gusts, heavy earth blows, WaterEnv /
## FireEnv.extinguish. Quests and puzzles listen to the signals.
##
##   var b := FireBrazier.new(); b.kind = &"torch"; b.lit = false
##   add_child(b); b.global_position = p
##   b.ignited.connect(func(by: Node) -> void: ...)
##   b.relight_time = 20.0   # an eternal flame relights itself (0: stays out)
##   b.burn_time = 0.0       # > 0: burns out on its own after that many seconds

signal ignited(by: Node)
signal extinguished(by: Node)

@export var kind: StringName = &"brazier"
@export var lit := false
@export var relight_time := 0.0
@export var burn_time := 0.0
## Hook radii around the flame (FireEnv / WaterEnv add them to their reach).
var ignite_radius := 0.7
var extinguish_radius := 0.7
## The hook node at the flame (in groups &"ignitable" / &"extinguishable"): the shared
## contracts measure their reach from it.
var hook: FlameHook = null
var flame: FireFx.FireBall = null
var light: OmniLight3D = null
var proxy: FireHitProxy = null
var glow_mat: ShaderMaterial = null
var _flame_y := 1.15
var _t := 0.0
var _state_t := 0.0

## Braziers lit / put out since start (tests).
static var lit_count := 0


func _ready() -> void:
	add_to_group(&"fire_brazier")
	_build()
	hook = FlameHook.new()
	hook.name = "FlameHook"
	hook.owner_fire = self
	hook.position = Vector3.UP * _flame_y
	add_child(hook)
	# The hit proxy sits just above the prop's collision so hits from any side reach it.
	proxy = FireHitProxy.make(0.55, _on_hit)
	proxy.position = Vector3.UP * (_flame_y + 0.22)
	add_child(proxy)
	if lit:
		lit = false
		_set_lit(true, null, false)


func is_burning() -> bool:
	return lit


## Where the flame burns (world).
func flame_point() -> Vector3:
	return global_position + Vector3.UP * _flame_y


## IGNITE hook. Returns true if it caught fire.
func ignite(by: Node = null, _at: Vector3 = Vector3.ZERO) -> bool:
	if lit:
		return false
	_set_lit(true, by, true)
	return true


## EXTINGUISH hook. Returns true if it was burning.
func extinguish(by: Node = null, _at: Vector3 = Vector3.ZERO) -> bool:
	if not lit:
		return false
	_set_lit(false, by, true)
	return true


func _on_hit(hit: HitInfo) -> void:
	match FireHitProxy.reaction(hit):
		&"ignite":
			ignite(hit.source, hit.position)
		&"douse":
			extinguish(hit.source, hit.position)


func _set_lit(on: bool, by: Node, feedback: bool) -> void:
	lit = on
	_state_t = 0.0
	var p := flame_point()
	if on:
		lit_count += 1
		if flame == null or not is_instance_valid(flame):
			flame = FireFx.FireBall.make()
			add_child(flame)
		flame.position = Vector3.UP * (_flame_y + 0.08)
		flame.setup(0.22 if kind == &"brazier" else (0.13 if kind == &"torch" else 0.09))
		flame.set_heat(1.1)
		if feedback and is_inside_tree():
			FireFx.burst(self, p, 0.6)
			FxBurst.spawn(self, &"embers", p, {"count": 0.8})
			Audio.play_bending(ElementDefs.Element.FIRE, &"ignite", p, -2.0)
		ignited.emit(by)
	else:
		if flame != null and is_instance_valid(flame):
			flame.queue_free()
		flame = null
		if feedback and is_inside_tree():
			FireEnv.steam(self, p, 0.6)
			FxBurst.spawn(self, &"smoke", p + Vector3.UP * 0.2, {"count": 0.6, "size": 0.6})
		extinguished.emit(by)
	if light:
		light.visible = on
	if glow_mat:
		glow_mat.set_shader_parameter(&"emission_energy", 1.6 if on else 0.0)


func _process(delta: float) -> void:
	_t += delta
	_state_t += delta
	if lit:
		if light and light.visible:
			light.light_energy = 1.1 * (0.85 + 0.1 * sin(_t * 11.0) + 0.05 * sin(_t * 23.0))
		if burn_time > 0.0 and _state_t >= burn_time:
			_set_lit(false, null, true)
	elif relight_time > 0.0 and _state_t >= relight_time:
		_set_lit(true, null, true)


# --- looks -----------------------------------------------------------------------------------

func _part(mesh: Mesh, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi


static func _cyl(top: float, bottom: float, h: float, seg: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _build() -> void:
	var col := CollisionShape3D.new()
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	add_child(body)
	body.add_child(col)
	match kind:
		&"torch":
			_flame_y = 2.05
			var wood := ToonMaterials.make(Color(0.36, 0.24, 0.15))
			var iron := ToonMaterials.make(Color(0.17, 0.16, 0.16), {"specular": 0.4})
			_part(_cyl(0.05, 0.065, 1.9, 8), Vector3(0, 0.95, 0), wood)
			_part(_cyl(0.13, 0.08, 0.26, 8), Vector3(0, 1.98, 0), iron)
			for i in 4:
				var a := TAU * i / 4.0
				_part(_box(Vector3(0.025, 0.34, 0.025)), Vector3(cos(a) * 0.12, 2.05, sin(a) * 0.12), iron)
			_part(_cyl(0.1, 0.1, 0.05, 8), Vector3(0, 1.88, 0), wood)
			var cap := CylinderShape3D.new()
			cap.radius = 0.1
			cap.height = 1.8
			col.shape = cap
			col.position = Vector3(0, 0.9, 0)
			ignite_radius = 0.5
			extinguish_radius = 0.5
		&"lantern":
			_flame_y = 1.02
			var stone := ToonMaterials.make(Color(0.6, 0.58, 0.54))
			var dark := ToonMaterials.make(Color(0.43, 0.41, 0.39))
			glow_mat = ToonMaterials.make(Color(0.95, 0.86, 0.66), {"unique": true, "emission": Color(1.0, 0.62, 0.25), "emission_energy": 0.0})
			_part(_cyl(0.32, 0.38, 0.16, 6), Vector3(0, 0.08, 0), dark)
			_part(_cyl(0.11, 0.13, 0.62, 6), Vector3(0, 0.47, 0), stone)
			_part(_cyl(0.3, 0.24, 0.1, 6), Vector3(0, 0.83, 0), dark)
			_part(_box(Vector3(0.36, 0.34, 0.36)), Vector3(0, 1.05, 0), glow_mat)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_part(_box(Vector3(0.07, 0.36, 0.07)), Vector3(sx * 0.18, 1.05, sz * 0.18), stone)
			_part(_cyl(0.06, 0.48, 0.24, 6), Vector3(0, 1.34, 0), dark)
			_part(_cyl(0.03, 0.06, 0.12, 6), Vector3(0, 1.5, 0), stone)
			var box := BoxShape3D.new()
			box.size = Vector3(0.6, 0.86, 0.6)
			col.shape = box
			col.position = Vector3(0, 0.43, 0)
			ignite_radius = 0.5
			extinguish_radius = 0.5
		_:
			_flame_y = 1.08
			var bronze := ToonMaterials.make(Color(0.55, 0.36, 0.18), {"specular": 0.5, "rim": 0.25})
			var dark_b := ToonMaterials.make(Color(0.24, 0.16, 0.1))
			var coal := ToonMaterials.make(Color(0.12, 0.08, 0.06), {"outline": false, "emission": Color(1.0, 0.35, 0.08), "emission_energy": 0.6})
			for i in 3:
				var a := TAU * i / 3.0 + 0.5
				var leg := _part(_cyl(0.035, 0.05, 1.0, 6), Vector3(cos(a) * 0.32, 0.48, sin(a) * 0.32), dark_b)
				leg.rotation = Vector3(sin(a) * -0.28, 0.0, cos(a) * 0.28)
			_part(_cyl(0.18, 0.14, 0.08, 10), Vector3(0, 0.12, 0), dark_b)
			_part(_cyl(0.5, 0.26, 0.3, 14), Vector3(0, 0.95, 0), bronze)
			_part(_cyl(0.56, 0.52, 0.05, 14), Vector3(0, 1.11, 0), bronze)
			_part(_cyl(0.44, 0.44, 0.04, 12), Vector3(0, 1.08, 0), coal)
			var bshape := CylinderShape3D.new()
			bshape.radius = 0.5
			bshape.height = 0.98
			col.shape = bshape
			col.position = Vector3(0, 0.49, 0)
	if FxLib.tier() >= 1 or not Settings.is_mobile_device():
		light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.26)
		light.omni_range = 7.0 if kind == &"brazier" else 5.0
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		light.position = Vector3.UP * (_flame_y + 0.35)
		light.visible = false
		add_child(light)


## The flame's hook node: carries the IGNITE / EXTINGUISH contracts at the fire itself.
class FlameHook extends Node3D:
	var owner_fire: FireBrazier = null
	var ignite_radius := 0.6
	var extinguish_radius := 0.6

	func _ready() -> void:
		add_to_group(FireEnv.IGNITABLE)
		add_to_group(FireEnv.EXTINGUISHABLE)
		if owner_fire != null:
			ignite_radius = owner_fire.ignite_radius
			extinguish_radius = owner_fire.extinguish_radius

	func ignite(by: Node = null, at: Vector3 = Vector3.ZERO) -> bool:
		return owner_fire != null and owner_fire.ignite(by, at)

	func extinguish(by: Node = null, at: Vector3 = Vector3.ZERO) -> bool:
		return owner_fire != null and owner_fire.extinguish(by, at)

	func is_burning() -> bool:
		return owner_fire != null and owner_fire.lit
