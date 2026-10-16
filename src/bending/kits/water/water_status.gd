class_name WaterStatus
extends RefCounted
## The SOAKED status (docs/modules/bending_water.md "Soaked"): any hit whose
## status carries {"soaked": seconds} (whips, blasts, surges, waves, jets ...)
## drenches the target for that long. Soaked targets drip (a small emitter
## that follows them, capped), keep a blue tint, and are set up for ice:
##   * freeze reactions on a soaked target last FREEZE_MULT x longer
##     (Ice Trap, Water Shield parry freeze, Ice Shards flash-freeze);
##   * Ice Shards that hit a soaked target flash-freeze it (short FREEZE);
##   * a soaked target that was burning is put out (extinguish hook).
## Works for the player, enemies, dummies and wildlife (duck typed: anything in
## group &"damageable" that is a Node3D). Listening starts on the first water
## ability (WaterStatus.ensure()); hits from enemy waterbenders soak the player.
##
##   WaterStatus.soak(target, 4.0)
##   WaterStatus.is_soaked(target) -> bool
##   WaterStatus.time_left(target) -> float
##   WaterStatus.freeze_time(target, base) -> base or base * FREEZE_MULT

const META := &"water_soaked_until"
const FREEZE_MULT := 1.5
## Max simultaneous drip emitters (the status itself is not capped).
const MAX_DRIPS := 8
const TINT := Color(0.42, 0.68, 1.0)

static var _listener: Listener = null
static var _drips: Array[Node] = []


static func ensure() -> void:
	if _listener != null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.get_node_or_null(^"/root/Events") == null:
		return
	_listener = Listener.new()
	Events.hit_landed.connect(_listener.on_hit)


## Game clock in seconds (physics ticks: hitstop / slow motion stretch it like gameplay).
static func now() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


static func soak(target: Node, seconds: float) -> void:
	if target == null or not is_instance_valid(target) or seconds <= 0.0:
		return
	var until := now() + seconds
	if until <= float(target.get_meta(META, 0.0)):
		return
	var was := is_soaked(target)
	target.set_meta(META, until)
	_tint(target, 0.5)
	if target is Node3D:
		_attach_drip(target as Node3D)
		if not was:
			var t3 := target as Node3D
			FxBurst.spawn(t3, &"droplets", BendingContext.target_point(t3), {"count": 0.5, "speed": 0.6})


static func is_soaked(target: Node) -> bool:
	return target != null and is_instance_valid(target) and float(target.get_meta(META, 0.0)) > now()


static func time_left(target: Node) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	return maxf(0.0, float(target.get_meta(META, 0.0)) - now())


static func clear(target: Node) -> void:
	if target != null and is_instance_valid(target):
		target.set_meta(META, 0.0)


## Freeze duration against `target`: longer on soaked targets.
static func freeze_time(target: Node, base: float) -> float:
	return base * (FREEZE_MULT if is_soaked(target) else 1.0)


static func _tint(target: Node, amount: float) -> void:
	var vis: Variant = target.get("visual") if "visual" in target else null
	if vis is Object and (vis as Object).has_method("tint"):
		(vis as Object).call("tint", TINT, amount)
		return
	var rig: Variant = target.get("rig") if "rig" in target else null
	if rig is HumanoidRig and is_instance_valid(rig):
		(rig as HumanoidRig).set_status_tint(TINT, amount * 0.8)


static func _attach_drip(target: Node3D) -> void:
	for d in _drips:
		if is_instance_valid(d) and d.get_parent() == target:
			return
	for i in range(_drips.size() - 1, -1, -1):
		if not is_instance_valid(_drips[i]):
			_drips.remove_at(i)
	if _drips.size() >= MAX_DRIPS or FxLib.scale() < 0.3:
		return
	var drip := Drip.new()
	drip.target = target
	target.add_child(drip)
	_drips.append(drip)


## Hit listener (Events.hit_landed): soaks targets of hits that carry the status.
class Listener extends RefCounted:
	func on_hit(hit: HitInfo, target: Node, result: int) -> void:
		if hit == null or target == null or not is_instance_valid(target):
			return
		if result != Combat.Result.HIT and result != Combat.Result.KILLED:
			return
		if hit.status.has("soaked"):
			WaterStatus.soak(target, float(hit.status["soaked"]))
		# A drenched target that burns is put out (WaterEnv extinguish hook on damageables).
		if hit.status.has("soaked") and target.has_method("extinguish"):
			target.call("extinguish", hit.source, hit.position)


## Water dripping off a soaked target (follows it, ends with the status).
class Drip extends Node3D:
	var target: Node3D
	var particles: GPUParticles3D
	var _tint_t := 0.0

	func _ready() -> void:
		name = "SoakedDrip"
		particles = GPUParticles3D.new()
		particles.amount = FxLib.amount(10)
		particles.lifetime = 0.6
		particles.local_coords = false
		particles.visibility_aabb = AABB(Vector3(-1.5, -2.5, -1.5), Vector3(3, 4, 3))
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.28, 0.45, 0.2)
		pm.direction = Vector3.DOWN
		pm.spread = 10.0
		pm.initial_velocity_min = 0.2
		pm.initial_velocity_max = 0.6
		pm.gravity = Vector3(0, -9.0, 0)
		pm.scale_min = 0.03
		pm.scale_max = 0.06
		pm.color = Color(0.7, 0.88, 1.0, 0.9)
		particles.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(1, 1.6)
		particles.draw_pass_1 = q
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.billboard_keep_scale = true
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.vertex_color_use_as_albedo = true
		sm.albedo_texture = FxLib.soft_dot()
		particles.material_override = sm
		particles.position = Vector3(0, 1.0, 0)
		add_child(particles)
		particles.emitting = true

	func _process(delta: float) -> void:
		if target == null or not is_instance_valid(target) or not WaterStatus.is_soaked(target) or not Combat.is_alive(target):
			particles.emitting = false
			if target != null and is_instance_valid(target) and "rig" in target and target.get("rig") is HumanoidRig \
					and not ("visual" in target):
				(target.get("rig") as HumanoidRig).set_status_tint(Color.WHITE, 0.0)
			queue_free()
			return
		# Keep the tint while soaked (player / enemy tints fade by themselves).
		_tint_t -= delta
		if _tint_t <= 0.0:
			_tint_t = 0.5
			WaterStatus._tint(target, 0.45)
