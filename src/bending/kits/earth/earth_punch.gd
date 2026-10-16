extends ComboAbility
## Earth Punch: each strike stomps a rock chunk out of the ground right in
## front of the punching fist (in the colours of that ground), then punches it
## forward as a projectile. Three hits; the third (two-handed) rips a bigger
## rock that knocks back. Every stomp cracks the ground under the foot and
## thumps the camera: earth hits feel heavy from the very first strike.
## No earth underfoot (ice, wood, deep water): a stone-hard fist strike up
## close instead (weaker, short reach) - the bender is never helpless.

var _riser: EarthCommon.RockRiser = null
var _info: Dictionary = {}


func begin() -> void:
	EarthCommon.prepare()
	super.begin()


func on_step_begin(_i: int, sd: Dictionary) -> void:
	_drop_riser()
	ctx.poise_armor = maxf(ctx.poise_armor, ctx.base_poise_armor)
	var r := float(sd.get("rock", 0.2))
	var side := ctx.right() * (0.25 if StringName(sd.get("hand", &"hand_r")) == &"hand_r" else -0.25)
	if StringName(sd.get("hand", &"")) == &"hands":
		side = Vector3.ZERO
	var g := ctx.origin() + ctx.forward() * 0.9 + side
	_info = EarthEnv.material_at(ctx, g)
	if not bool(_info["ok"]):
		return
	r *= lerpf(1.0, EarthEnv.power(_info), 0.6)
	var to := _fist(sd) + ctx.forward() * (0.35 + r)
	var rise := maxf(time_to_event(StringName(sd.get("event", &"release"))), 0.04)
	_riser = EarthCommon.rise_rock(ctx, _info["ground"], to, r, rise, _info["kind"])


func on_event(event: StringName) -> void:
	if event == &"stomp" and not struck:
		# Hung Gar stomp: the planted foot cracks the ground.
		var foot := ctx.socket_pos(&"foot_r" if StringName(_step_data.get("hand", &"hand_r")) == &"hand_r" else &"foot_l")
		var g := EarthEnv.ground(ctx, foot + Vector3.UP * 0.3)
		var kind: StringName = _info.get("kind", &"dirt") if bool(_info.get("ok", false)) else &"stone"
		FxDecal.spawn(ctx.caster, g["point"], &"crack", 0.55 if step < 2 else 0.9)
		FxBurst.spawn(ctx.caster, &"dust", g["point"], {"color": EarthPalette.color(kind, "dust"), "count": 0.25, "size": 0.5, "speed": 0.6})
		return
	super.on_event(event)


func update(delta: float) -> void:
	if _riser and is_instance_valid(_riser) and not _riser.released:
		_riser.target = _fist(_step_data) + ctx.forward() * (0.35 + float(_step_data.get("rock", 0.2)))
	super.update(delta)


func strike(_i: int, sd: Dictionary) -> void:
	if not bool(_info.get("ok", true)):
		_fist_strike(sd)
		return
	var pw := EarthEnv.power(_info)
	var r := float(sd.get("rock", 0.2)) * lerpf(1.0, pw, 0.6)
	var speed := float(param("speed", 30.0))
	var rock: MeshInstance3D = null
	var from := _fist(sd) + ctx.forward() * (0.35 + r)
	if _riser and is_instance_valid(_riser) and not _riser.released:
		# Punch from the fist even if the rising animation lags a frame behind.
		rock = _riser.take()
		rock.global_position = from
	else:
		rock = EarthEnv.rock(ctx.caster, r, _info.get("kind", &"dirt"))
	_riser = null
	var dir := ctx.aim_dir_from(from, speed, 0.6)
	var h := EarthEnv.scaled_hit(step_hit(), _info)
	EarthCommon.launch(self, rock, from, dir, speed, r, h, {"range": float(param("range", 28.0)), "gravity": 2.5, "kind": _info.get("kind", &"dirt"),
			"splash": 1.6 if step == 2 else 0.0, "splash_hit": {"damage": 6.0 * pw, "reaction": HitInfo.Reaction.STAGGER, "force": 5.0, "poise": 15.0}})
	sound(&"cast_light", from, 0.0 if step < 2 else 2.0)
	EarthEnv.shake(ctx, from, 0.1 if step < 2 else 0.22, 0.1)
	BendingFeedback.impulse(dir, 0.06 if step < 2 else 0.14)


## Bare stone fist (nothing to bend here): a short melee strike.
func _fist_strike(sd: Dictionary) -> void:
	var a := ctx.origin() + Vector3.UP * 1.2
	var b := a + ctx.aim_flat() * float(param("fist_reach", 1.9))
	var h := step_hit()
	h["damage"] = float(h.get("damage", 9.0)) * float(param("fist_damage", 0.65))
	BendingHits.sweep(ctx, a, b, 0.45, h, attack_id, def.id)
	BendingFeedback.sound(ElementDefs.Element.NONE, &"cast_light", _fist(sd), -2.0)
	if step == 0 and ctx.is_player():
		EarthEnv.refuse(ctx, def.id, _info)


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
