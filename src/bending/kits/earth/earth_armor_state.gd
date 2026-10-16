class_name EarthArmorState
extends Node3D
## Earth Armor while it is worn: stone plates ripped from the ground fly onto
## the bender (chest, back, belly, pauldrons, bracers, greaves) and ride the
## rig's bones. While attached:
## * damage reduction (BendingContext.base_damage_reduction - survives every
##   ability start / end) and extra poise armor during actions (base_poise_armor);
## * slower movement (player: PlayerMotor.speed_scale);
## * chi drains every second (no regeneration meanwhile); at 0 chi the armor
##   breaks and falls off.
## Ends: toggled off (EarthArmor shed: plates burst outward and knock back),
## chi out, the caster dying / changing element / leaving the tree, or `max_time`
## (non-player casters without resources). Hits chip the plates.
##
##   var st := EarthArmorState.of(caster)    # null when not armored
##   st.active, st.shed(burst), st.break_off()

signal ended(reason: StringName)

## [name, bone_a, bone_b, t (0..1 along a->b), facing, offset (m along facing), scale (w, thick, len)]
const SLOTS := [
	[&"chest", &"upper_chest", &"neck", 0.15, &"fwd", 0.15, Vector3(0.44, 0.42, 0.42)],
	[&"back", &"upper_chest", &"neck", 0.1, &"back", 0.15, Vector3(0.42, 0.36, 0.3)],
	[&"belly", &"spine", &"chest", 0.5, &"fwd", 0.14, Vector3(0.34, 0.3, 0.2)],
	[&"pauldron_l", &"upperarm_l", &"forearm_l", 0.12, &"out_up_l", 0.09, Vector3(0.26, 0.42, 0.24)],
	[&"pauldron_r", &"upperarm_r", &"forearm_r", 0.12, &"out_up_r", 0.09, Vector3(0.26, 0.42, 0.24)],
	[&"bracer_l", &"forearm_l", &"hand_l", 0.5, &"out_l", 0.05, Vector3(0.15, 0.32, 0.2)],
	[&"bracer_r", &"forearm_r", &"hand_r", 0.5, &"out_r", 0.05, Vector3(0.15, 0.32, 0.2)],
	[&"greave_l", &"shin_l", &"foot_l", 0.42, &"fwd", 0.07, Vector3(0.17, 0.34, 0.22)],
	[&"greave_r", &"shin_r", &"foot_r", 0.42, &"fwd", 0.07, Vector3(0.17, 0.34, 0.22)],
]
## Rig-less casters: slot positions relative to the caster (right, up, back).
const FALLBACK := {
	&"chest": Vector3(0, 1.35, -0.2), &"back": Vector3(0, 1.35, 0.2), &"belly": Vector3(0, 1.05, -0.18),
	&"pauldron_l": Vector3(-0.28, 1.5, 0), &"pauldron_r": Vector3(0.28, 1.5, 0), &"bracer_l": Vector3(-0.32, 1.0, -0.1),
	&"bracer_r": Vector3(0.32, 1.0, -0.1), &"greave_l": Vector3(-0.12, 0.35, -0.08), &"greave_r": Vector3(0.12, 0.35, -0.08),
}

var ctx: BendingContext
var kind: StringName = &"dirt"
var active := false
var reduction := 0.4
var poise := 40.0
var speed_scale := 0.78
var drain := 5.0
var max_time := INF
var age := 0.0
var plates: Array[MeshInstance3D] = []
## Per plate: [from (Vector3), launched_at (s), flight time]
var _fly: Array = []
var _state := 0  # 0 flying in, 1 worn, 2 falling off
var _off_t := 0.0
var _off_vel: Array[Vector3] = []
var _flash := 0.0
var _ctrl: BendingController = null

static var live: Array[EarthArmorState] = []


static func of(caster: Node) -> EarthArmorState:
	if caster == null or not is_instance_valid(caster):
		return null
	var n := caster.get_node_or_null(^"EarthArmor") as EarthArmorState
	return n if n != null and n._state < 2 else null


## Starts the plates flying in from the ground around the feet (they attach on
## attach()). opts: reduction, poise, speed_scale, drain, max_time.
static func don(p_ctx: BendingContext, p_kind: StringName, attach_in: float, opts: Dictionary = {}) -> EarthArmorState:
	var old := of(p_ctx.caster)
	if old != null:
		old._remove(&"replaced")
	var s := EarthArmorState.new()
	s.name = "EarthArmor"
	s.ctx = p_ctx
	s._ctrl = p_ctx.controller
	s.kind = p_kind
	s.reduction = float(opts.get("reduction", 0.4))
	s.poise = float(opts.get("poise", 40.0))
	s.speed_scale = float(opts.get("speed_scale", 0.78))
	s.drain = float(opts.get("drain", 5.0))
	s.max_time = float(opts.get("max_time", INF if p_ctx.resources != null else 30.0))
	s.top_level = true
	p_ctx.caster.add_child(s)
	s.global_transform = Transform3D.IDENTITY
	s._build(maxf(attach_in, 0.08))
	live.append(s)
	if not Events.hit_landed.is_connected(s._on_hit):
		Events.hit_landed.connect(s._on_hit)
	return s


func _build(attach_in: float) -> void:
	var o := ctx.origin()
	var plate_kind := kind
	for i in SLOTS.size():
		var m := MeshInstance3D.new()
		m.mesh = EarthMeshes.plate(i % 6, plate_kind)
		m.material_override = EarthMeshes.material()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		plates.append(m)
		var a := randf() * TAU
		var from := o + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.8, 1.6)
		from.y = EarthEnv.ground_y(ctx, from) - 0.1
		var delay := randf_range(0.0, 0.25) * attach_in
		_fly.append([from, delay, maxf(attach_in - delay, 0.06), 0.0])
		m.global_transform = Transform3D(Basis.from_scale((SLOTS[i][6] as Vector3)), from)
		if i % 3 == 0:
			EarthFx.tear_out(self, from + Vector3.UP * 0.1, 0.35, plate_kind)


## The plates lock on: the armor is now worn (modifiers applied).
func attach() -> void:
	if _state != 0:
		return
	_state = 1
	active = true
	ctx.base_damage_reduction = reduction
	ctx.base_poise_armor = poise
	ctx.damage_reduction = maxf(ctx.damage_reduction, reduction)
	ctx.poise_armor = maxf(ctx.poise_armor, poise)
	_set_speed(speed_scale)
	_flash = 1.0
	FxBurst.spawn(self, &"dust", ctx.origin() + Vector3.UP * 1.0, {"color": EarthPalette.color(kind, "dust"), "count": 0.9, "size": 0.9, "radius": 0.6})
	BendingFeedback.sound(ElementDefs.Element.EARTH, &"armor", ctx.origin() + Vector3.UP, 0.0)


## Toggled off: the plates fly outward (burst = knock back whoever is close).
func shed(burst_hit: Dictionary = {}, burst_radius: float = 3.0, attack_id: int = 0, ability_id: StringName = &"earth_armor") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _state >= 2:
		return out
	if not burst_hit.is_empty() and ctx != null and ctx.is_valid():
		out = BendingHits.sphere(ctx, ctx.origin() + Vector3.UP * 0.9, burst_radius, burst_hit, attack_id if attack_id != 0 else HitInfo.new_attack_id(),
				ability_id, {"push": &"radial", "los": false})
		FxBurst.spawn(self, &"dust_ring", ctx.origin(), {"color": EarthPalette.color(kind, "dust"), "radius": 1.0, "count": 1.2})
	_fall_off(9.0, &"shed")
	return out


## Chi ran out / the caster went down: the plates crumble and drop.
func break_off(reason: StringName = &"broken") -> void:
	if _state >= 2:
		return
	FxDebris.spawn(self, ctx.origin() + Vector3.UP * 1.0 if ctx and ctx.is_valid() else global_position,
			{"count": 8, "size": 0.12, "up": 2.0, "out": 1.8, "ground_y": ctx.origin().y if ctx and ctx.is_valid() else 0.0,
			"color": EarthPalette.color(kind, "debris")})
	BendingFeedback.sound(ElementDefs.Element.EARTH, &"wall_break", global_position, -4.0)
	_fall_off(2.5, reason)


func _fall_off(speed: float, reason: StringName) -> void:
	_state = 2
	active = false
	_off_t = 0.0
	_off_vel.clear()
	var c := ctx.origin() + Vector3.UP * 1.0 if ctx != null and ctx.is_valid() else global_position
	for m in plates:
		var d := m.global_position - c
		d.y = 0.0
		d = d.normalized() if d.length_squared() > 1e-4 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		_off_vel.append(d * speed * randf_range(0.6, 1.1) + Vector3.UP * randf_range(1.0, 3.5))
	_clear_modifiers()
	ended.emit(reason)


func _clear_modifiers() -> void:
	if ctx == null:
		return
	if ctx.base_damage_reduction == reduction:
		ctx.base_damage_reduction = 0.0
	if ctx.base_poise_armor == poise:
		ctx.base_poise_armor = 0.0
	ctx.damage_reduction = minf(ctx.damage_reduction, ctx.base_damage_reduction) if ctx.damage_reduction == reduction else ctx.damage_reduction
	if ctx.poise_armor == poise:
		ctx.poise_armor = ctx.base_poise_armor
	_set_speed(1.0)


func _set_speed(v: float) -> void:
	if ctx == null or not ctx.is_valid():
		return
	var motor: Variant = ctx.caster.get("motor") if "motor" in ctx.caster else null
	if motor is PlayerMotor:
		(motor as PlayerMotor).speed_scale = v


func _remove(reason: StringName) -> void:
	if _state < 2:
		_clear_modifiers()
		ended.emit(reason)
	_state = 3
	active = false
	live.erase(self)
	if Events.hit_landed.is_connected(_on_hit):
		Events.hit_landed.disconnect(_on_hit)
	queue_free()


func _exit_tree() -> void:
	live.erase(self)
	if _state < 2:
		_clear_modifiers()
	if Events.hit_landed.is_connected(_on_hit):
		Events.hit_landed.disconnect(_on_hit)


func _on_hit(hit: HitInfo, target: Node, result: int) -> void:
	if _state != 1 or target != ctx.caster:
		return
	if result == Combat.Result.HIT or result == Combat.Result.BLOCKED:
		_flash = 1.0
		FxDebris.spawn(self, hit.position, {"count": 3, "size": 0.07, "up": 2.0, "out": 1.6, "ground_y": ctx.origin().y,
				"color": EarthPalette.color(kind, "debris")})


func _physics_process(delta: float) -> void:
	step(delta)


## Drain / end conditions (public for tests).
func step(delta: float) -> void:
	if _state != 1:
		return
	age += delta
	if ctx == null or not ctx.is_valid():
		_remove(&"invalid")
		return
	if (_ctrl != null and is_instance_valid(_ctrl) and _ctrl.ctx != ctx) or ctx.element != ElementDefs.Element.EARTH:
		_remove(&"element")
		return
	if not Combat.is_alive(ctx.caster):
		break_off(&"dead")
		return
	if age >= max_time:
		break_off(&"timeout")
		return
	if ctx.resources != null and drain > 0.0:
		if ctx.chi() <= drain * delta or not ctx.spend_chi(drain * delta):
			if ctx.is_player():
				Events.notify.emit("Out of chi: the earth armor crumbles", &"warning")
			break_off(&"chi")
			return
	# Keep the modifiers in force (a framework reset never removes them, but an
	# ability may have lowered poise below the armor's).
	ctx.base_damage_reduction = reduction
	ctx.base_poise_armor = poise
	if ctx.damage_reduction < reduction:
		ctx.damage_reduction = reduction


func _process(delta: float) -> void:
	if _state == 3:
		return
	if _state == 2:
		_off_t += delta
		for i in plates.size():
			var m := plates[i]
			_off_vel[i].y -= 14.0 * delta
			m.global_position += _off_vel[i] * delta
			m.rotate_object_local(Vector3(1, 0, 0), 7.0 * delta)
			if _off_t > 0.6:
				m.scale = m.scale * maxf(0.0, 1.0 - delta * 5.0)
		if _off_t >= 0.9:
			_remove(&"done")
		return
	if ctx == null or not ctx.is_valid():
		_remove(&"invalid")
		return
	var xf := slot_transforms()
	for i in plates.size():
		var target: Transform3D = xf[i]
		if _state == 0:
			# [from, delay, flight time, elapsed]
			var f: Array = _fly[i]
			f[3] = float(f[3]) + delta
			var u := clampf((float(f[3]) - float(f[1])) / float(f[2]), 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			var p := (f[0] as Vector3).lerp(target.origin, e) + Vector3.UP * sin(e * PI) * 0.6
			var b := target.basis if u >= 1.0 else Basis(Vector3.UP, (1.0 - e) * 6.0) * target.basis
			plates[i].global_transform = Transform3D(b, p)
		else:
			plates[i].global_transform = target
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)


## World transforms of every plate slot (rig bones, or fixed offsets without a rig).
func slot_transforms() -> Array:
	var out: Array = []
	var rig := ctx.rig if ctx.rig != null and is_instance_valid(ctx.rig) and ctx.rig.is_inside_tree() else null
	var cb := ctx.caster.global_basis
	var fwd := -cb.z
	var right := cb.x
	for s: Array in SLOTS:
		var scale: Vector3 = s[6]
		var pos := Vector3.ZERO
		var along := Vector3.UP
		var facing := fwd
		if rig != null and rig.get_bone_index(String(s[1])) >= 0 and rig.get_bone_index(String(s[2])) >= 0:
			var a := rig.get_bone_world(String(s[1])).origin
			var b := rig.get_bone_world(String(s[2])).origin
			var bb := rig.get_bone_world(String(s[1])).basis.orthonormalized()
			pos = a.lerp(b, float(s[3]))
			along = (b - a).normalized() if a.distance_to(b) > 0.01 else Vector3.UP
			facing = _facing(StringName(s[4]), -bb.z, bb.x, along)
		else:
			var off: Vector3 = FALLBACK.get(s[0], Vector3(0, 1.2, 0))
			pos = ctx.origin() + right * off.x + Vector3.UP * off.y - fwd * off.z
			facing = _facing(StringName(s[4]), fwd, right, Vector3.UP)
		pos += facing * float(s[5])
		var n := facing.normalized()
		var u := (along - n * along.dot(n))
		u = u.normalized() if u.length_squared() > 1e-4 else n.cross(right).normalized()
		var b2 := Basis(n.cross(u).normalized(), n, u)
		out.append(Transform3D(b2 * Basis.from_scale(scale), pos))
	return out


static func _facing(kind: StringName, fwd: Vector3, right: Vector3, along: Vector3) -> Vector3:
	match kind:
		&"back":
			return -fwd
		&"out_l":
			return (-right * 0.8 + fwd * 0.3).normalized()
		&"out_r":
			return (right * 0.8 + fwd * 0.3).normalized()
		&"out_up_l":
			return (-right * 0.7 + Vector3.UP * 0.7).normalized()
		&"out_up_r":
			return (right * 0.7 + Vector3.UP * 0.7).normalized()
	return fwd
