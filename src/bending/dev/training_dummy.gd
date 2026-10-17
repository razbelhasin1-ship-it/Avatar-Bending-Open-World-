class_name TrainingDummy
extends CharacterBody3D
## Damageable training target for the combat arena and tests.
## * look = &"post": a classic wooden post with a straw-wrapped body, stick arms
##   and a sack head that wobbles on a spring, hops when launched;
## * look = &"humanoid": a HumanoidRig sparring partner that plays the real hit
##   reactions (flinch, stagger, knockback, knockdown -> get up, launch, freeze).
## Shows hit info above it (damage, reaction, result, combo count), resets
## after being knocked out, and records stats for tests (hits_taken,
## damage_taken, last_hit, results).

signal hit_received(hit: HitInfo, result: int)

@export var look: StringName = &"post"
@export var team: int = Combat.Team.ENEMY
@export var max_health := 240.0
@export var display_name := "Training Dummy"
## Block hits from the front (tests guard / BLOCKED feedback).
@export var guarding := false
@export var preset: StringName = &"earth_soldier"

var health: HealthComponent
var rig: HumanoidRig = null
var home := Transform3D.IDENTITY
var hits_taken := 0
var damage_taken := 0.0
var last_hit: HitInfo = null
var results: Array[int] = []
var combo := 0

var _label: Label3D
var _label_t := 0.0
var _combo_t := 0.0
var _wobble := Vector2.ZERO
var _wobble_v := Vector2.ZERO
var _pivot: Node3D
var _mats: Array[ShaderMaterial] = []
var _flash := 0.0
var _down_t := 0.0
var _ko_t := 0.0
var _airborne := false
var _status_t := 0.0


func _ready() -> void:
	add_to_group(&"damageable")
	add_to_group(&"training_dummy")
	collision_layer = Layers.ENEMY
	collision_mask = Layers.SOLID
	floor_max_angle = deg_to_rad(45.0)
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = max_health
	health.max_poise = 30.0
	add_child(health)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.875, 0)
	add_child(cs)
	if look == &"humanoid":
		rig = HumanoidRig.create({"preset": preset, "seed": 3})
		rig.manual_update = true
		add_child(rig)
		rig.set_combat_stance(true)
	else:
		_build_post()
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.35, 0)
	_label.font_size = 64
	_label.pixel_size = 0.004
	_label.outline_size = 12
	_label.modulate = Color(1, 0.95, 0.85)
	_label.outline_modulate = Color(0.08, 0.05, 0.04)
	_label.no_depth_test = true
	_label.text = ""
	add_child(_label)
	home = global_transform


func _build_post() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	var wood := ToonMaterials.make(Color(0.46, 0.31, 0.19), {"unique": true})
	var straw := ToonMaterials.make(Color(0.86, 0.72, 0.42), {"unique": true})
	var rope := ToonMaterials.make(Color(0.55, 0.38, 0.22), {"unique": true})
	var cloth := ToonMaterials.make(Color(0.78, 0.7, 0.56), {"unique": true})
	_mats = [wood, straw, rope, cloth]
	# Base: a squat stone the post is planted in (does not wobble).
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.34
	bm.bottom_radius = 0.42
	bm.height = 0.22
	bm.radial_segments = 10
	base.mesh = bm
	base.position = Vector3(0, 0.11, 0)
	base.material_override = ToonMaterials.make(Color(0.52, 0.5, 0.47))
	add_child(base)
	_part(_pivot, _cyl(0.07, 0.08, 1.9, 8), Vector3(0, 0.95, 0), wood)
	_part(_pivot, _cyl(0.24, 0.26, 0.62, 12), Vector3(0, 1.22, 0), straw)
	for y in [0.98, 1.22, 1.46]:
		_part(_pivot, _cyl(0.255, 0.265, 0.05, 12), Vector3(0, y, 0), rope)
	var arm := _part(_pivot, _cyl(0.035, 0.035, 1.25, 6), Vector3(0, 1.38, 0), wood)
	arm.rotation_degrees = Vector3(0, 0, 90)
	for sx in [-0.62, 0.62]:
		_part(_pivot, _cyl(0.07, 0.06, 0.2, 8), Vector3(sx, 1.38, 0), straw).rotation_degrees = Vector3(0, 0, 90)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.17
	hm.height = 0.38
	hm.radial_segments = 12
	hm.rings = 8
	head.mesh = hm
	head.position = Vector3(0, 1.75, 0)
	head.material_override = cloth
	_pivot.add_child(head)
	# Painted target circle on the chest (where hits read best).
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.12
	dm.bottom_radius = 0.12
	dm.height = 0.01
	disc.mesh = dm
	disc.rotation_degrees = Vector3(90, 0, 0)
	disc.position = Vector3(0, 1.24, -0.255)
	disc.material_override = ToonMaterials.make(Color(0.72, 0.16, 0.1), {"outline": false})
	_pivot.add_child(disc)


func _cyl(r_top: float, r_bot: float, h: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func is_alive() -> bool:
	return health != null and not health.is_dead()


func get_display_name() -> String:
	return display_name


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func receive_hit(hit: HitInfo) -> int:
	if health.is_dead():
		return Combat.Result.IGNORED
	var result := Combat.Result.HIT
	if guarding and not hit.unblockable:
		var to_att := hit.origin - global_position
		to_att.y = 0.0
		if to_att.length() > 0.1 and (-global_basis.z).dot(to_att.normalized()) > 0.3:
			result = Combat.Result.BLOCKED
			hit.damage *= 0.2
	health.apply_damage(hit.damage, hit)
	hits_taken += 1
	damage_taken += hit.damage
	last_hit = hit
	if health.is_dead():
		result = Combat.Result.KILLED
	results.append(result)
	combo = combo + 1 if _combo_t > 0.0 else 1
	_combo_t = 1.6
	_show(hit, result)
	_react(hit, result)
	hit_received.emit(hit, result)
	return result


## Floating readout: damage, the reaction it caused (none named for a damage-only hit: the
## training grounds showed "2  None"), the result when not a plain hit, the combo count.
func _show(hit: HitInfo, result: int) -> void:
	var res := String(Combat.Result.keys()[result]).capitalize()
	var line := "%d" % int(round(hit.damage))
	if hit.reaction != HitInfo.Reaction.NONE:
		line += "  %s" % String(HitInfo.Reaction.keys()[hit.reaction]).capitalize()
	if result != Combat.Result.HIT:
		line += "  (%s)" % res
	if combo > 1:
		line += "\nx%d combo" % combo
	_label.text = line
	_label.modulate = Color(1.0, 0.85, 0.35) if hit.is_heavy else (Color(0.7, 0.85, 1.0) if result == Combat.Result.BLOCKED else Color(1, 0.96, 0.9))
	_label_t = 2.2


func _react(hit: HitInfo, result: int) -> void:
	_flash = 1.0
	var dir := hit.direction
	if hit.status.has("burn"):
		_status_t = 1.5
	if rig:
		rig.flash_hit()
		if result == Combat.Result.KILLED:
			rig.play_reaction(&"death", dir)
			_ko_t = 2.2
			return
		match hit.reaction:
			HitInfo.Reaction.KNOCKBACK, HitInfo.Reaction.PULL:
				var push := dir * hit.force * 0.8 if hit.reaction == HitInfo.Reaction.KNOCKBACK else (hit.origin - global_position).normalized() * hit.force * 0.8
				velocity.x = push.x
				velocity.z = push.z
			HitInfo.Reaction.KNOCKDOWN:
				velocity.x = dir.x * hit.force * 0.5
				velocity.z = dir.z * hit.force * 0.5
				_down_t = 1.4
			HitInfo.Reaction.LAUNCH:
				velocity = dir * hit.force * 0.5 + Vector3.UP * maxf(hit.lift, 5.0)
				_airborne = true
				_down_t = 1.6
		rig.play_reaction(hit.reaction, dir, maxf(hit.stun_time, 1.0) if hit.reaction == HitInfo.Reaction.FREEZE else 1.0)
		if hit.reaction == HitInfo.Reaction.FREEZE:
			rig.set_status_tint(Color(0.7, 0.9, 1.0), 0.8)
			_status_t = maxf(hit.stun_time, 1.0)
		return
	# Post: spring wobble away from the hit (local frame), hop on launches.
	var local := global_basis.inverse() * dir
	var k := clampf(0.25 + hit.force * 0.06 + hit.damage * 0.01, 0.2, 1.4)
	_wobble_v += Vector2(local.z, -local.x) * k * 9.0
	if hit.reaction == HitInfo.Reaction.LAUNCH:
		velocity.y = minf(hit.lift, 6.0) * 0.6
		_airborne = true
	if result == Combat.Result.KILLED:
		_ko_t = 1.6


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 14.0 * delta
	else:
		if _airborne and velocity.y <= 0.0:
			_airborne = false
			if rig:
				rig.land(4.0)
		var hv := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, 14.0 * delta)
		velocity.x = hv.x
		velocity.z = hv.y
		if look == &"post":
			velocity.x = 0.0
			velocity.z = 0.0
	move_and_slide()
	if rig:
		rig.set_locomotion(Vector3(velocity.x, 0, velocity.z), is_on_floor())
		rig.advance(delta)
		if _down_t > 0.0:
			_down_t -= delta
			if _down_t <= 0.0 and not health.is_dead():
				RigReactions.get_up(rig)
		# Drift back home between hits.
		if _down_t <= 0.0 and not health.is_dead() and Vector2(velocity.x, velocity.z).length() < 0.2:
			var to := home.origin - global_position
			to.y = 0.0
			if to.length() > 0.3:
				var v := to.normalized() * minf(1.6, to.length() * 2.0)
				velocity.x = v.x
				velocity.z = v.z
			else:
				var f := -home.basis.z
				rotation.y = lerp_angle(rotation.y, atan2(-f.x, -f.z), 0.1)


func _process(delta: float) -> void:
	_combo_t = maxf(0.0, _combo_t - delta)
	if _label_t > 0.0:
		_label_t -= delta
		_label.modulate.a = clampf(_label_t / 0.4, 0.0, 1.0)
		if _label_t <= 0.0:
			_label.text = ""
	if _pivot:
		# Damped spring wobble around the base.
		_wobble_v += (-_wobble * 80.0 - _wobble_v * 7.0) * delta
		_wobble += _wobble_v * delta
		_wobble = _wobble.limit_length(0.55)
		_pivot.rotation = Vector3(_wobble.x, 0.0, _wobble.y)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		for m in _mats:
			m.set_shader_parameter(&"hit_flash", _flash)
	if _status_t > 0.0:
		_status_t -= delta
		if _status_t <= 0.0 and rig:
			rig.set_status_tint(Color.WHITE, 0.0)
	if _ko_t > 0.0:
		_ko_t -= delta
		if _ko_t <= 0.0:
			reset()


## Full health, back to the spot it was placed at.
func reset() -> void:
	health.revive(1.0)
	velocity = Vector3.ZERO
	global_transform = home
	_wobble = Vector2.ZERO
	_wobble_v = Vector2.ZERO
	_down_t = 0.0
	combo = 0
	if rig:
		rig.set_pose_state(&"normal", 0.0)
		rig.stop_action(0.0)
		rig.animator.loco.reset(rig.skeleton.global_transform)
	_label.text = "Reset"
	_label_t = 0.8


func clear_stats() -> void:
	hits_taken = 0
	damage_taken = 0.0
	last_hit = null
	results.clear()
