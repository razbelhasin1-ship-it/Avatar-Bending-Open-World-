extends ComboAbility
## Earth Punch: each strike stomps a rock chunk out of the ground right in
## front of the punching fist, then punches it forward as a projectile.
## Three hits; the third (two-handed) rips a bigger rock that knocks back.

var _riser: EarthCommon.RockRiser = null


func on_step_begin(_i: int, sd: Dictionary) -> void:
	_drop_riser()
	var r := float(sd.get("rock", 0.2))
	var side := ctx.right() * (0.25 if StringName(sd.get("hand", &"hand_r")) == &"hand_r" else -0.25)
	if StringName(sd.get("hand", &"")) == &"hands":
		side = Vector3.ZERO
	var ground := ctx.ground_point(ctx.origin() + ctx.forward() * 0.9 + side)
	var to := _fist(sd) + ctx.forward() * (0.35 + r)
	var rise := maxf(time_to_event(StringName(sd.get("event", &"release"))), 0.04)
	_riser = EarthCommon.rise_rock(ctx, ground, to, r, rise)


func update(delta: float) -> void:
	if _riser and is_instance_valid(_riser) and not _riser.released:
		_riser.target = _fist(_step_data) + ctx.forward() * (0.35 + float(_step_data.get("rock", 0.2)))
	super.update(delta)


func strike(_i: int, sd: Dictionary) -> void:
	var r := float(sd.get("rock", 0.2))
	var speed := float(param("speed", 30.0))
	var rock: MeshInstance3D = null
	var from := _fist(sd) + ctx.forward() * (0.35 + r)
	if _riser and is_instance_valid(_riser) and not _riser.released:
		rock = _riser.take()
		from = rock.global_position
	else:
		rock = EarthFx.rock(ctx.caster, r)
	_riser = null
	var dir := ctx.aim_dir_from(from, speed, 0.6)
	var h := step_hit()
	EarthCommon.launch(self, rock, from, dir, speed, r, h, {"range": float(param("range", 28.0)), "gravity": 2.5,
			"splash": 1.6 if step == 2 else 0.0, "splash_hit": {"damage": 6.0, "reaction": HitInfo.Reaction.STAGGER, "force": 5.0, "poise": 15.0}})
	sound(&"cast_light", from, 0.0 if step < 2 else 2.0)
	if ctx.is_player():
		BendingFeedback.shake(0.08 if step < 2 else 0.18, 0.1)


func _fist(sd: Dictionary) -> Vector3:
	var h := StringName(sd.get("hand", &"hand_r"))
	if h == &"hands":
		return ctx.hands_pos()
	return ctx.socket_pos(h)


func _drop_riser() -> void:
	if _riser and is_instance_valid(_riser) and not _riser.released:
		_riser.drop()
	_riser = null


func on_cancel(_reason: StringName) -> void:
	_drop_riser()


func on_finish() -> void:
	_drop_riser()
