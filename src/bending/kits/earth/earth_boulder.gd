extends BendingAbility
## Earth Boulder (heavy). Stomp: a boulder tears out of the ground and rises
## above the bender (earth_raise). Holding keeps it hovering overhead while you
## aim (earth_hold) and charges it bigger; releasing (or a tap) hurls it with
## earth_throw: heavy impact, knockdown, splash damage around the impact.
## Poise armor through the whole move (Earth heavies are hard to interrupt).

enum Phase { LIFT, HOLD, THROW }

var phase := Phase.LIFT
var charge := 0.0
var hold_t := 0.0
var _riser: EarthCommon.RockRiser = null
var _radius := 0.55
var _thrown := false
var _charge_spent := 0.0


func begin() -> void:
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	ctx.poise_armor = def.poise_armor
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 720.0
	_radius = float(param("radius", 0.55))
	play_clip(param("lift_clip", &"earth_raise"), {"speed": float(param("lift_speed", 1.3)), "blend_in": 0.06})
	max_time = def.max_hold + 4.0


func _hover_point() -> Vector3:
	return ctx.origin() + Vector3.UP * (2.35 + _radius) + ctx.forward() * 0.35


func on_event(event: StringName) -> void:
	match phase:
		Phase.LIFT:
			if event == &"stomp":
				var g := ctx.ground_point(ctx.origin() + ctx.forward() * 1.2)
				var rise := maxf(time_to_event(&"release"), 0.1)
				_riser = EarthCommon.rise_rock(ctx, g, _hover_point(), _radius, rise)
				_riser.follow = _hover_point
				sound(&"stomp", g)
				if ctx.is_player():
					BendingFeedback.shake(0.2, 0.15)
			elif event == &"release":
				phase = Phase.HOLD
				hold_t = 0.0
				play_clip(param("hold_clip", &"earth_hold"), {"blend_in": 0.12})
				clip_end = INF
		Phase.THROW:
			if event == &"release" and not _thrown:
				_throw()


func update(delta: float) -> void:
	match phase:
		Phase.HOLD:
			hold_t += delta
			ctx.face_dir = ctx.aim_flat()
			if input_held and def.charge_time > 0.0:
				var want := clampf(hold_t / def.charge_time, 0.0, 1.0)
				var extra := float(param("charge_chi", 10.0))
				if want > charge and ctx.spend_chi((want - charge) * extra):
					charge = want
				var r := float(param("radius", 0.55)) * (1.0 + charge * 0.4)
				if _riser and is_instance_valid(_riser) and _riser.rock:
					_riser.rock.scale = Vector3.ONE * r * 2.0
				_radius = r
			if not input_held or hold_t >= def.max_hold:
				phase = Phase.THROW
				ctx.face_dir = ctx.aim_flat()
				ctx.face_rate = 1440.0
				play_clip(param("throw_clip", &"earth_throw"), {"start": float(param("throw_start", 0.55)), "speed": float(param("throw_speed", 1.2)), "blend_in": 0.06})
		Phase.THROW:
			if time >= clip_end:
				finish()
		Phase.LIFT:
			if time >= clip_end + 0.2:
				# The lift clip never delivered its release event: hold anyway.
				on_event(&"release")


func _throw() -> void:
	_thrown = true
	ctx.face_dir = Vector3.ZERO
	var speed := float(param("speed", 24.0)) + charge * 4.0
	var rock: MeshInstance3D = null
	var from := _hover_point()
	if _riser and is_instance_valid(_riser) and not _riser.released:
		rock = _riser.take()
		# Use the hover point unless the rock is already close to it (the
		# rising animation may lag behind when frames are slow).
		if rock.global_position.distance_to(from) < 0.6:
			from = rock.global_position
	else:
		rock = EarthFx.rock(ctx.caster, _radius)
	_riser = null
	from += ctx.forward() * 0.4
	var dir := ctx.aim_dir_from(from, speed, 0.7)
	var h := hit_data({"damage": float(def.hit.get("damage", 26.0)) + 14.0 * charge, "force": 9.0 + 4.0 * charge})
	var splash := float(param("splash", 2.2)) * (1.0 + charge * 0.4)
	EarthCommon.launch(self, rock, from, dir, speed, _radius, h, {"range": 32.0, "gravity": 5.0, "splash": splash,
			"splash_hit": {"damage": 10.0 + 8.0 * charge, "reaction": HitInfo.Reaction.STAGGER, "force": 6.0, "stun": 0.5, "poise": 25.0, "heavy": true}})
	sound(&"cast_heavy", from, 2.0)
	sound(&"launch", from)
	BendingFeedback.impulse(dir, 0.25)
	if ctx.is_player():
		BendingFeedback.shake(0.25 + charge * 0.15, 0.2)


func _drop() -> void:
	if _riser and is_instance_valid(_riser) and not _riser.released:
		_riser.drop()
	_riser = null


func on_cancel(_reason: StringName) -> void:
	_drop()


func on_finish() -> void:
	_drop()
