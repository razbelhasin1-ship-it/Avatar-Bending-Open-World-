class_name FireRingWave
extends Node3D
## A standing wall of flame racing outward from a point in a full circle (Fire Ring,
## the Inferno's release, Fire Burst's flash). Gameplay and visual share ONE radius
## curve, so targets are hit exactly when the flames reach them (once per attack id);
## targets more than `clearance` above the ground jumped it; walls / constructs between
## the centre and a target shield it (line of sight). Grass catches and snow steams
## along the front; a scorched ring stays where it ends.
##
##   FireRingWave.start(ctx, ground_center, 6.5, 0.38, hit, attack_id, &"fire_ring",
##       {"height": 1.3, "clearance": 1.4})
##   FireRingWave.visual(ctx, ground_center, 3.8, 0.16)       # flames only, no hits

var ctx: BendingContext
var center := Vector3.ZERO
var r0 := 0.6
var radius := 6.0
var duration := 0.4
var hold := 0.18
var h: Dictionary = {}
var attack_id := 0
var ability_id: StringName = &""
var clearance := 1.4
var power := 1.0
var hits_enabled := true
var env := true
var mark := true
var t := 0.0
var mesh_i: MeshInstance3D
var mat: ShaderMaterial
var _next_env := 1.5
var _done_hits := false
var _env_dirs := 8

## Live waves (tests).
static var live: Array[FireRingWave] = []


static func start(p_ctx: BendingContext, p_center: Vector3, p_radius: float, p_duration: float, hit: Dictionary, p_attack_id: int,
		p_ability: StringName, opts: Dictionary = {}) -> FireRingWave:
	var w := _make(p_ctx, p_center, p_radius, p_duration, opts)
	w.h = hit
	w.attack_id = p_attack_id
	w.ability_id = p_ability
	w.hits_enabled = true
	return w


## Visual-only ring (Fire Burst flash): no hits, no environment.
static func visual(p_ctx: BendingContext, p_center: Vector3, p_radius: float, p_duration: float, opts: Dictionary = {}) -> FireRingWave:
	var o := opts.duplicate()
	o["env"] = false
	o["mark"] = false
	var w := _make(p_ctx, p_center, p_radius, p_duration, o)
	w.hits_enabled = false
	return w


static func _make(p_ctx: BendingContext, p_center: Vector3, p_radius: float, p_duration: float, opts: Dictionary) -> FireRingWave:
	var w := FireRingWave.new()
	w.name = "FireRingWave"
	w.ctx = p_ctx
	w.center = p_center
	w.radius = p_radius
	w.duration = maxf(p_duration, 0.05)
	w.r0 = float(opts.get("r0", 0.6))
	w.hold = float(opts.get("hold", 0.18))
	w.clearance = float(opts.get("clearance", 1.4))
	w.power = float(opts.get("power", 1.0))
	w.env = bool(opts.get("env", true))
	w.mark = bool(opts.get("mark", true))
	w._env_dirs = 8 if FxLib.tier() >= 2 else (6 if FxLib.tier() == 1 else 4)
	FxLib.root(p_ctx.caster).add_child(w)
	w.global_position = p_center
	w.mesh_i = MeshInstance3D.new()
	w.mesh_i.mesh = FxMeshes.arc_wall(-PI, PI, float(opts.get("height", 1.2)), 72, float(opts.get("lean", 0.3)))
	w.mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.mat = wall_material()
	w.mat.set_shader_parameter(&"fade", 0.0)
	w.mat.set_shader_parameter(&"tongue_scale", float(opts.get("tongues", 10.0 / 0.7)))
	w.mesh_i.material_override = w.mat
	w.add_child(w.mesh_i)
	w._apply_radius(w.r0)
	live.append(w)
	return w


## The flame-wall material (banded, thin hot core, fades near the camera).
static func wall_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/fx/fire/fx_flame_wall.gdshader")
	m.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
	return m


## Radius of the front at time `time` (s): fast start, easing out.
func radius_at(time: float) -> float:
	var u := clampf(time / duration, 0.0, 1.0)
	return lerpf(r0, radius, 1.0 - pow(1.0 - u, 1.6))


func _apply_radius(r: float) -> void:
	mesh_i.scale = Vector3(r, 1.0, r)


func _physics_process(delta: float) -> void:
	t += delta
	var r := radius_at(t)
	if ctx == null or not ctx.is_valid():
		hits_enabled = false
		env = false
	if hits_enabled and not _done_hits:
		_hit(r)
		if t >= duration:
			_done_hits = true
	if env:
		while r >= _next_env and _next_env <= radius:
			_env_at(_next_env)
			_next_env += 1.6
		if t >= duration and mark:
			mark = false
			FireMarks.ring(ctx.caster, center, radius * 1.02, {"glow": 1.0})


func _process(_delta: float) -> void:
	var r := radius_at(t)
	_apply_radius(r)
	var burn := clampf((t - duration) / maxf(hold + 0.25, 0.05), 0.0, 1.0)
	mat.set_shader_parameter(&"fade", burn)
	mat.set_shader_parameter(&"opacity", 1.0 - burn * burn * 0.6)
	if t >= duration + hold + 0.25:
		live.erase(self)
		queue_free()


func _exit_tree() -> void:
	live.erase(self)


func _hit(r: float) -> void:
	var c := center + Vector3.UP * 0.9
	var high: Array = []
	for tgt in BendingHits.targets_in_sphere(ctx, c, r + 0.45):
		if not (tgt is Node3D) or tgt is FireHitProxy:
			continue
		var feet := (tgt as Node3D).global_position.y
		if feet - center.y > clearance:
			high.append(tgt)
	BendingHits.sphere(ctx, c, r + 0.45, h, attack_id, ability_id, {"push": &"radial", "exclude": high})


func _env_at(r: float) -> void:
	var off := randf() * TAU
	for i in _env_dirs:
		var a := off + TAU * float(i) / _env_dirs
		var p := center + Vector3(sin(a), 0.0, -cos(a)) * r + Vector3.UP * 0.3
		FireEnv.heat(ctx, p, 0.9, power * 0.5, {"mark": 0.0})
