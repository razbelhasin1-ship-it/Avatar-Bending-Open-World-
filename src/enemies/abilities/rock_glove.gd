extends BendingAbility
## Dai Li Rock Glove (enemy technique): the agent punches its stone glove off the
## hand on a chain. On hit the glove clamps the target (FREEZE = rooted for
## hit.stun seconds); then the chain reels the glove back to the hand.
## Uses the same projectile / hit pipeline as every bending attack.

const STONE := Color(0.33, 0.33, 0.31)


func begin() -> void:
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 900.0
	play_clip(def.clip, {"speed": def.clip_speed, "start": def.clip_start, "blend_in": 0.05})
	FxBurst.spawn(ctx.caster, &"dust", ctx.socket_pos(&"hand_r"), {"color": Color(0.55, 0.52, 0.46), "count": 0.3, "size": 0.35})


func on_event(event: StringName) -> void:
	if event != &"release":
		return
	ctx.face_dir = Vector3.ZERO
	var hand := ctx.socket_pos(&"hand_r")
	var speed := float(param("speed", 20.0))
	var dir := ctx.aim_dir_from(hand, speed, 0.5)
	var from := hand + dir * 0.25
	var rock := EarthFx.rock(ctx.caster, float(param("radius", 0.2)), 1, STONE)
	var chain := GloveChain.new()
	chain.caster = ctx.caster
	chain.rig = ctx.rig
	chain.rock = rock
	FxLib.root(ctx.caster).add_child(chain)
	var on_impact := func(_p: BendingProjectile, pos: Vector3, _n: Vector3, target: Node) -> void:
		chain.impact_at(pos, target != null)
	var on_finish := func(v: Node3D) -> void:
		chain.retract(v as MeshInstance3D)
	var p := BendingProjectile.launch(ctx, from, dir, speed, hit_data(), {"radius": float(param("radius", 0.2)),
			"range": float(param("range", 16.0)), "attack_id": attack_id, "ability_id": def.id, "visual": rock, "align": false,
			"spin": Vector3(0, 0, 9.0), "impact_size": 0.6, "on_impact": on_impact, "on_finish": on_finish})
	chain.projectile = p
	sound(&"cast_light", from, -2.0)


## A dark chain from the punching hand to the flying glove; reels the glove back
## to the hand after impact, then frees itself (independent of the ability).
class GloveChain extends Node3D:
	var caster: Node3D
	var rig: HumanoidRig
	var rock: MeshInstance3D
	var projectile: BendingProjectile
	var _mesh: MeshInstance3D
	var _back_t := -1.0
	var _from := Vector3.ZERO
	var _age := 0.0

	func _ready() -> void:
		_mesh = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = 1.0
		cm.radial_segments = 5
		cm.rings = 1
		_mesh.mesh = cm
		_mesh.material_override = ToonMaterials.make(Color(0.16, 0.16, 0.17), {"outline": false})
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)

	func _hand() -> Vector3:
		if rig != null and is_instance_valid(rig) and rig.is_inside_tree():
			var s := rig.get_socket(&"hand_r")
			if s:
				return s.global_position
		if caster != null and is_instance_valid(caster):
			return caster.global_position + Vector3.UP * 1.3
		return global_position

	func impact_at(pos: Vector3, _on_target: bool) -> void:
		_from = pos

	func retract(v: MeshInstance3D) -> void:
		if v != null and is_instance_valid(v):
			rock = v
		if rock != null and is_instance_valid(rock):
			_from = rock.global_position
			rock.visible = true
		_back_t = 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age > 4.0:
			_done()
			return
		var hand := _hand()
		var tip := hand
		if _back_t < 0.0:
			if projectile != null and is_instance_valid(projectile) and projectile.alive:
				tip = projectile.global_position
			elif rock != null and is_instance_valid(rock):
				tip = rock.global_position
		else:
			_back_t += delta
			var u := clampf(_back_t / 0.3, 0.0, 1.0)
			tip = _from.lerp(hand, u * u)
			if rock != null and is_instance_valid(rock):
				rock.global_position = tip
			if u >= 1.0:
				_done()
				return
		var d := tip - hand
		var l := d.length()
		if l < 0.05:
			_mesh.visible = false
			return
		_mesh.visible = true
		var y := d / l
		var x := y.cross(Vector3.UP)
		if x.length_squared() < 1e-4:
			x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		var z := x.cross(y).normalized()
		_mesh.global_transform = Transform3D(Basis(x, y * l, z), hand + d * 0.5)

	func _done() -> void:
		if rock != null and is_instance_valid(rock):
			EarthFx.release_rock(rock)
		rock = null
		queue_free()
