class_name EnemyActions
extends RefCounted
## Runs one enemy attack at a time through three readable phases:
##
##   WINDUP   telegraph: the clip is held at its anticipation key (or a bending charge
##            is held), a glint flashes on the weapon / hand with a wind-up sound, area
##            attacks show a ground ring. The enemy tracks the target, then COMMITS for
##            the last COMMIT_TIME s (sidestepping late still works).
##   ACTIVE   the strike runs; gameplay (sweep / sphere / projectile / bending ability)
##            spawns on the clip's release / impact event (deadline fallback).
##   RECOVER  a fair punish window: no blocking, dodging or turning.
##
## Attack kinds: &"melee" &"projectile" &"slam" (area, optional leap / line) &"bending"
## (casts the element's ability through the enemy's BendingController) &"beast"
## (creature action + hit) &"charge" (beast rush). Every timer has a hard cap.

enum Phase { NONE, WINDUP, ACTIVE, RECOVER }

const COMMIT_TIME := 0.14
const MAX_ATTACK_TIME := 6.0
const GRAVITY := 20.0

var e: EnemyBase
var attack: Dictionary = {}
var phase := Phase.NONE
var phase_t := 0.0
var total_t := 0.0
var target: Node3D = null
var attack_id := 0
var struck := false
var telegraph_time := 0.0
var approach := 0.2
## Poise armor of the running attack.
var armor := 0.0
## Velocity the attack drives the body with (lunges, leaps, charges); ZERO = none.
var drive := Vector3.ZERO
var face_locked := false
## Attack id -> seconds left.
var cooldowns: Dictionary = {}
## Number of attacks started (tests).
var started_count := 0
var strikes := 0

var _strike_at := INF
var _active_end := INF
var _drive_until := 0.0
var _ring: FxRing = null
var _glinted := false
var _steps_left := 0
var _step_wait := 0.0
var _clip: StringName = &""
var _charge_dir := Vector3.ZERO
var _charge_left := 0.0
var _leap_target := Vector3.INF
var _line_t := -1.0
var _line_hits := 0
var _tap_release := false


func _init(p_enemy: EnemyBase) -> void:
	e = p_enemy


func is_busy() -> bool:
	return phase != Phase.NONE


func in_windup() -> bool:
	return phase == Phase.WINDUP


func in_recover() -> bool:
	return phase == Phase.RECOVER


## Seconds of the windup still to come (INF when not winding up).
func windup_left() -> float:
	if phase != Phase.WINDUP:
		return INF
	return maxf(0.0, approach + telegraph_time - phase_t)


func cooldown_left(id: StringName) -> float:
	return float(cooldowns.get(id, 0.0))


func tick_cooldowns(delta: float) -> void:
	for id: StringName in cooldowns.keys():
		var left: float = cooldowns[id] - delta
		if left <= 0.0:
			cooldowns.erase(id)
		else:
			cooldowns[id] = left


## Can `a` start now against a target at `dist` (LOS known by the caller)?
func can_use(a: Dictionary, dist: float, los: bool) -> bool:
	if cooldown_left(a.get("id", &"")) > 0.0:
		return false
	var r: Vector2 = a.get("range", Vector2(0.0, 2.0))
	if dist < r.x or dist > r.y:
		return false
	if bool(a.get("needs_los", false)) and not los:
		return false
	if a.get("kind", &"") == &"bending":
		if e.controller == null:
			return false
		var slot: StringName = (a.get("bending", {}) as Dictionary).get("slot", &"light")
		if e.controller.can_start(slot) != &"":
			return false
	return true


# --- start ------------------------------------------------------------------------------------------

func start(a: Dictionary, p_target: Node3D) -> bool:
	if a.is_empty():
		return false
	cancel(&"restart")
	attack = a
	target = p_target
	phase = Phase.WINDUP
	phase_t = 0.0
	total_t = 0.0
	struck = false
	_glinted = false
	face_locked = false
	drive = Vector3.ZERO
	_strike_at = INF
	_active_end = INF
	_leap_target = Vector3.INF
	_line_t = -1.0
	_line_hits = 0
	attack_id = HitInfo.new_attack_id()
	started_count += 1
	var mult := e.telegraph_mult()
	telegraph_time = float(a.get("telegraph", 0.4)) * mult
	approach = float(a.get("approach", 0.2))
	armor = float(a.get("armor", 0.0))
	_clip = a.get("clip", &"")
	var kind: StringName = a.get("kind", &"melee")
	match kind:
		&"melee", &"projectile", &"slam":
			e.visual.windup(_clip, float(a.get("windup", 0.3)), approach, {"mirror": bool(a.get("mirror", false))})
		&"bending":
			var b: Dictionary = a.get("bending", {})
			if StringName(b.get("slot", &"light")) == &"heavy" and not bool(b.get("tap", false)):
				# The charge itself is the telegraph (gathering fire / rising boulder / water).
				approach = 0.12
				telegraph_time = float(b.get("hold", 0.6)) * mult
				if e.controller == null or e.controller.request(&"heavy") != &"":
					_abort()
					return false
			elif _clip != &"":
				e.visual.windup(_clip, float(a.get("windup", 0.25)), approach)
		&"beast", &"charge":
			approach = 0.1
			e.visual.play(&"growl" if kind == &"beast" else StringName(a.get("action", &"roar")))
	var ring_r := float(a.get("ring", 0.0))
	if ring_r > 0.0:
		var center := _ring_center(a)
		_ring = EnemyTelegraph.ring(e, center, ring_r, e.attack_element(a), approach + telegraph_time + 0.15)
	e.on_attack_started(a, approach + telegraph_time)
	return true


func _ring_center(a: Dictionary) -> Vector3:
	var shape: Dictionary = a.get("shape", {})
	if bool(a.get("leap", false)) and target != null and is_instance_valid(target):
		return e.ground_point(target.global_position)
	return e.ground_point(e.global_position + e.forward() * float(shape.get("reach", 0.0)))


# --- tick -------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	if phase == Phase.NONE:
		return
	phase_t += delta
	total_t += delta
	if total_t > MAX_ATTACK_TIME:
		push_warning("EnemyActions: %s hit its safety timeout" % attack.get("id", &"?"))
		cancel(&"timeout")
		return
	match phase:
		Phase.WINDUP:
			_tick_windup(delta)
		Phase.ACTIVE:
			_tick_active(delta)
		Phase.RECOVER:
			drive = Vector3.ZERO
			if phase_t >= float(attack.get("recover", 0.4)) * e.recover_mult():
				_finish()


func _tick_windup(_delta: float) -> void:
	var total := approach + telegraph_time
	face_locked = phase_t > total - COMMIT_TIME and attack.get("kind", &"") != &"projectile"
	if not _glinted and phase_t >= approach * 0.85:
		_glinted = true
		var g: StringName = attack.get("glint", &"hand_r")
		var el := e.attack_element(attack)
		if g != &"":
			var anchor: Array = e.visual.socket_anchor(g) if g != &"hands" else []
			EnemyTelegraph.glint(e, e.visual.socket_pos(g), el, 1.25 if bool((attack.get("hit", {}) as Dictionary).get("heavy", false)) else 1.0, anchor)
		EnemyTelegraph.windup_sound(el, e.global_position + Vector3.UP * 1.2, telegraph_time > 0.6)
		e.on_telegraph(attack, maxf(0.0, total - phase_t))
	# Leap target tracks the player until the commit.
	if bool(attack.get("leap", false)) and target != null and is_instance_valid(target) and not face_locked:
		_leap_target = target.global_position
		if _ring and is_instance_valid(_ring):
			_ring.global_position = e.ground_point(_leap_target) + Vector3.UP * 0.04
	if phase_t >= total:
		_begin_active()


func _begin_active() -> void:
	phase = Phase.ACTIVE
	phase_t = 0.0
	face_locked = true
	var a := attack
	var kind: StringName = a.get("kind", &"melee")
	match kind:
		&"melee", &"projectile", &"slam":
			var speed := float(a.get("speed", 1.0))
			var tti := e.visual.release(speed, &"impact" if kind != &"projectile" else &"release")
			if not is_finite(tti):
				tti = 0.18
			_strike_at = tti + 0.1
			var c := AnimLibrary.get_clip(_clip)
			_active_end = maxf(tti + 0.05, (c.length * (1.0 - float(a.get("windup", 0.3))) / speed) if c else tti + 0.3)
			_setup_drive(a, tti)
			if kind == &"slam" and a.has("line"):
				_line_t = -1.0
		&"bending":
			var b: Dictionary = a.get("bending", {})
			var slot: StringName = b.get("slot", &"light")
			if slot == &"heavy" and not bool(b.get("tap", false)):
				e.controller.release(&"heavy")
			else:
				var why := e.controller.request(slot) if e.controller else &"empty"
				if why != &"":
					_abort()
					return
				_steps_left = int(b.get("steps", 1)) - 1 if slot == &"light" else 0
				_step_wait = 0.0
				_tap_release = slot == &"heavy"
			_active_end = 4.0
		&"beast":
			var d := e.visual.play(StringName(a.get("action", &"bite")), {"side": 1.0 if randf() < 0.5 else -1.0})
			_strike_at = maxf(0.1, d * 0.45) + 0.15
			_active_end = maxf(d, 0.3)
			_setup_drive(a, maxf(0.1, d * 0.4))
		&"charge":
			var ch: Dictionary = a.get("charge", {})
			_charge_dir = e.flat_dir_to(target) if target != null else e.forward()
			_charge_left = float(ch.get("distance", 14.0))
			drive = _charge_dir * float(ch.get("speed", 10.0))
			_active_end = _charge_left / maxf(float(ch.get("speed", 10.0)), 1.0) + 0.3
			Audio.play_sfx(&"creature_step_heavy", e.global_position, 0.0)


func _setup_drive(a: Dictionary, tti: float) -> void:
	drive = Vector3.ZERO
	_drive_until = 0.0
	if bool(a.get("leap", false)):
		var to := _leap_target if _leap_target.is_finite() else (target.global_position if target != null and is_instance_valid(target) else e.global_position + e.forward() * 4.0)
		var flat := to - e.global_position
		flat.y = 0.0
		var r: Vector2 = a.get("range", Vector2(0, 9))
		var dist := clampf(flat.length(), 0.5, r.y)
		var air := maxf(tti, 0.3)
		drive = flat.normalized() * dist / air if flat.length() > 0.1 else Vector3.ZERO
		_drive_until = air
		e.velocity.y = GRAVITY * air * 0.5
		return
	var lunge := float(a.get("lunge", 0.0))
	if lunge <= 0.0 or target == null or not is_instance_valid(target):
		return
	var shape: Dictionary = a.get("shape", {})
	var reach := float(shape.get("reach", 2.0))
	var dist := e.flat_distance_to(target)
	var need := clampf(dist - reach * 0.75, 0.0, lunge)
	if need < 0.1:
		return
	var t := maxf(tti, 0.12)
	drive = e.forward() * need / t
	_drive_until = t


func _tick_active(delta: float) -> void:
	var kind: StringName = attack.get("kind", &"melee")
	if kind == &"bending":
		_tick_bending(delta)
		return
	if kind == &"charge":
		_tick_charge(delta)
		return
	if phase_t >= _drive_until:
		drive = Vector3.ZERO
	if not struck and phase_t >= _strike_at:
		strike()
	if _line_t >= 0.0:
		_tick_line(delta)
	if struck and phase_t >= _active_end and _line_t < 0.0:
		_to_recover()
	elif phase_t >= _active_end + 1.0:
		_to_recover()


func _tick_bending(delta: float) -> void:
	var bc := e.controller
	if bc == null:
		_to_recover()
		return
	if bc.is_busy():
		var cur := bc.current
		if _tap_release and cur is ChargeAbility and cur.time >= 0.09:
			# Tapped heavy: the telegraph happened before the cast.
			_tap_release = false
			bc.release(&"heavy")
		if cur is ComboAbility and _steps_left > 0:
			var combo := cur as ComboAbility
			if combo.struck:
				_step_wait += delta
			# Kicks at the end of a chain only make sense up close.
			if combo.step >= 1 and target != null and is_instance_valid(target) and e.flat_distance_to(target) > 3.6:
				_steps_left = 0
			elif combo.can_chain() and _step_wait >= 0.12 * e.telegraph_mult():
				# Each extra chain step still shows a small glint (readable rhythm).
				EnemyTelegraph.glint(e, e.visual.socket_pos(&"hand_l" if _steps_left % 2 == 1 else &"hand_r"), e.element, 0.7)
				bc.request(&"light")
				_steps_left -= 1
				_step_wait = 0.0
		if not struck and cur is BendingAbility and _bending_released(cur as BendingAbility):
			struck = true
			strikes += 1
			e.on_attack_struck(attack)
		return
	if not struck:
		struck = true
		e.on_attack_struck(attack)
	_to_recover()


## The cast ability's gameplay moment has happened (bolt / boulder / wave released).
static func _bending_released(cur: BendingAbility) -> bool:
	if cur is ComboAbility:
		return (cur as ComboAbility).struck
	if cur is ChargeAbility:
		return (cur as ChargeAbility).released and cur.time_to_event(&"release") == INF
	return cur.time > 0.05 and cur.time_to_event(&"release") == INF and cur.time_to_event(&"impact") == INF


func _tick_charge(delta: float) -> void:
	_charge_left -= drive.length() * delta
	var head := e.global_position + Vector3.UP * 0.9 + _charge_dir * float((attack.get("shape", {}) as Dictionary).get("reach", 2.0))
	if not struck:
		var h: Dictionary = (attack.get("hit", {}) as Dictionary).duplicate()
		h["damage"] = float(h.get("damage", 8.0)) * e.damage_mult()
		var res := hit_targets(sphere_targets(head, float((attack.get("shape", {}) as Dictionary).get("radius", 1.2)), e.global_position + Vector3.UP * 0.9),
				h, attack.get("id", &"charge"), _charge_dir)
		var stopped := false
		for r: Dictionary in res:
			stopped = stopped or int(r["result"]) in [Combat.Result.HIT, Combat.Result.KILLED, Combat.Result.BLOCKED, Combat.Result.DEFLECTED]
		if stopped:
			struck = true
			strikes += 1
			e.on_attack_struck(attack)
			if float(attack.get("shake", 0.0)) > 0.0:
				BendingFeedback.shake(float(attack["shake"]), 0.25)
	var blocked := phase_t > 0.25 and Vector2(e.velocity.x, e.velocity.z).length() < drive.length() * 0.35
	if _charge_left <= 0.0 or struck or blocked or phase_t > _active_end:
		drive = Vector3.ZERO
		if blocked:
			Audio.play_sfx(&"land_heavy", e.global_position, -2.0)
			FxBurst.spawn(e, &"dust", e.global_position + _charge_dir * 1.5, {"count": 1.0})
		_to_recover()


## Spike line (earth captain): spikes erupt one after another along the facing.
func _tick_line(delta: float) -> void:
	_line_t += delta
	var length := float(attack.get("line", 9.0))
	var n := int(ceil(length / 1.2))
	var want := mini(n, int(_line_t / 0.05) + 1)
	while _line_hits < want:
		var p := e.ground_point(e.global_position + e.forward() * (1.2 + _line_hits * 1.2))
		EarthFx.tear_out(e, p, 0.6, GroundSampler.surface(p))
		FxDebris.spawn(e, p + Vector3.UP * 0.3, {"count": 3, "size": 0.12, "up": 4.0, "out": 1.0, "ground_y": p.y})
		var h: Dictionary = (attack.get("hit", {}) as Dictionary).duplicate()
		h["damage"] = float(h.get("damage", 8.0)) * e.damage_mult()
		hit_targets(sphere_targets(p + Vector3.UP * 0.6, float((attack.get("shape", {}) as Dictionary).get("radius", 0.9)), p + Vector3.UP * 0.2),
				h, attack.get("id", &"spike_line"), e.forward())
		if _line_hits % 2 == 0:
			Audio.play_bending(ElementDefs.Element.EARTH, &"spikes", p, -3.0)
		_line_hits += 1
	if _line_hits >= n:
		_line_t = -1.0


## Delivers the strike of the running attack (called on the rig event or the deadline).
func strike() -> void:
	if struck or phase != Phase.ACTIVE:
		return
	struck = true
	strikes += 1
	var a := attack
	var kind: StringName = a.get("kind", &"melee")
	var h: Dictionary = (a.get("hit", {}) as Dictionary).duplicate()
	h["damage"] = float(h.get("damage", 8.0)) * e.damage_mult()
	var shape: Dictionary = a.get("shape", {})
	var fwd := e.forward()
	var chest := e.global_position + Vector3.UP * 1.05
	var aid: StringName = a.get("id", &"attack")
	match kind:
		&"projectile":
			_launch_projectile(a, h)
		&"slam":
			if a.has("line"):
				_line_t = 0.0
				_line_hits = 0
				Audio.play_bending(ElementDefs.Element.EARTH, &"stomp", e.global_position, 0.0)
			else:
				var center := e.ground_point(e.global_position + fwd * float(shape.get("reach", 0.0)))
				hit_targets(sphere_targets(center + Vector3.UP * 0.6, float(shape.get("radius", 3.0)), center + Vector3.UP * 0.8), h, aid,
						Vector3.ZERO, center)
				_slam_fx(a, center, float(shape.get("radius", 3.0)))
		_:
			match StringName(shape.get("type", &"sweep")):
				&"sphere":
					var c := e.global_position + Vector3.UP * 0.9 + fwd * float(shape.get("reach", 1.5))
					hit_targets(sphere_targets(c, float(shape.get("radius", 1.0)), chest), h, aid)
					if bool(h.get("heavy", false)):
						var g := e.ground_point(c)
						FxBurst.spawn(e, &"dust_ring", g, {"color": FxLib.surface_color(GroundSampler.surface(g)), "count": 0.8})
						FxDecal.spawn(e, g, &"crack", 0.8)
				_:
					hit_targets(capsule_targets(chest + fwd * 0.25, chest + fwd * float(shape.get("reach", 2.0)), float(shape.get("radius", 0.55))),
							h, aid, fwd)
			Audio.play_sfx(&"whoosh_heavy" if bool(h.get("heavy", false)) else &"whoosh_light", chest, -3.0)
	if float(a.get("shake", 0.0)) > 0.0 and e.near_player(14.0):
		BendingFeedback.shake(float(a["shake"]), 0.25)
	e.on_attack_struck(a)


## Damageables overlapping a sphere that `los_from` can see (walls / constructs block).
func sphere_targets(center: Vector3, radius: float, los_from: Vector3) -> Array[Node]:
	var out: Array[Node] = []
	for t in BendingHits.targets_in_sphere(e.ctx, center, radius):
		var tp := BendingContext.target_point(t as Node3D) if t is Node3D else center
		if BendingHits.line_of_sight(e.ctx, los_from, tp, t):
			out.append(t)
	return out


## Damageables overlapping the capsule a..b (weapon swings), line of sight from `a`.
func capsule_targets(a: Vector3, b: Vector3, radius: float) -> Array[Node]:
	var out: Array[Node] = []
	var seg := b - a
	var length := seg.length()
	if length < 0.01:
		return sphere_targets(a, radius, a)
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = length + radius * 2.0
	var y := seg / length
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 1e-4:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(x, y, x.cross(y)).orthonormalized(), (a + b) * 0.5)
	params.collision_mask = e.ctx.hit_mask()
	params.collide_with_areas = true
	params.exclude = e.ctx.exclude()
	for r: Dictionary in e.ctx.space().intersect_shape(params, 32):
		var col: Object = r.get("collider")
		if col == null or not (col is Node):
			continue
		var t := Combat.find_damageable(col as Node)
		if t == null or t == e or out.has(t):
			continue
		var tp := BendingContext.target_point(t as Node3D) if t is Node3D else b
		var u := clampf((tp - a).dot(y) / length, 0.0, 1.0)
		if BendingHits.line_of_sight(e.ctx, a, (a + seg * u).lerp(tp, 0.5), t):
			out.append(t)
	return out


## Delivers the running attack's hit to `targets` with the ENEMY as the hit origin, so
## guards judge where the attacker stands (a shape's centre can lie behind the target),
## pushed along `dir`, or away from `push_from` (default: the enemy). Once per target
## per attack id (BendingHits.deliver: feedback, team checks).
func hit_targets(targets: Array[Node], h: Dictionary, aid: StringName, dir: Vector3 = Vector3.ZERO,
		push_from: Vector3 = Vector3.INF) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var chest := e.global_position + Vector3.UP * 1.0
	var from := push_from if push_from.is_finite() else e.global_position
	for t in targets:
		var tp := BendingContext.target_point(t as Node3D) if t is Node3D else chest
		var push := dir
		if push == Vector3.ZERO:
			push = tp - from
		push.y = 0.0
		if push.length_squared() < 1e-4:
			push = e.forward()
		var hit := e.ctx.make_hit(h, push.normalized(), attack_id, aid)
		hit.element = e.attack_element(attack) if not attack.is_empty() else e.element
		hit.origin = chest
		hit.position = tp.lerp(chest, 0.3) if chest.distance_to(tp) < 3.0 else tp
		out.append({"target": t, "result": BendingHits.deliver(e.ctx, t, hit), "hit": hit})
	return out


func _slam_fx(a: Dictionary, center: Vector3, radius: float) -> void:
	var el := int(a.get("element", e.element))
	var surf := GroundSampler.surface(center)
	match el:
		ElementDefs.Element.FIRE:
			FireFx.explosion(e, center + Vector3.UP * 0.3, radius * 0.9, center.y)
			Audio.play_bending(el, &"explosion", center, 2.0)
		ElementDefs.Element.EARTH:
			EarthFx.quake(e, center, radius, surf)
			Audio.play_bending(el, &"stomp", center, 2.0)
		_:
			FxBurst.spawn(e, &"dust_ring", center, {"color": FxLib.surface_color(surf), "count": 1.2, "radius": radius * 0.4})
			Audio.play_sfx(&"land_heavy", center, 0.0)
	FxRing.spawn(e, center, radius, Color(0.95, 0.85, 0.7), 0.35, {"opacity": 0.6, "width": 0.2, "fill": 0.1})


func _launch_projectile(a: Dictionary, h: Dictionary) -> void:
	var p: Dictionary = a.get("projectile", {})
	var from := e.visual.socket_pos(StringName(p.get("socket", &"hand_r")))
	var speed := float(p.get("speed", 26.0))
	var grav := float(p.get("gravity", 3.0))
	var dir := e.forward()
	if target != null and is_instance_valid(target):
		var tp := BendingContext.target_point(target)
		tp = BendingContext.lead_point(from, tp, BendingContext.target_velocity(target), speed, e.lead_amount())
		var d := tp - from
		var t := d.length() / maxf(speed, 1.0)
		d.y += 0.5 * grav * t * t
		dir = d.normalized()
	var vis: Node3D = EnemyProps.knife_visual(e) if p.get("visual", &"arrow") == &"knife" else EnemyProps.arrow_visual(e)
	h["projectile"] = true
	h["deflectable"] = true
	var trail := bool(p.get("trail", false))
	var is_knife: bool = p.get("visual", &"arrow") == &"knife"
	var step_fx := func(pr: BendingProjectile, _dt: float) -> void:
		if trail and int(pr.traveled * 2.0) % 3 == 0:
			FxBurst.spawn(pr, &"sparkle", pr.global_position, {"count": 0.15, "speed": 0.2})
	var done := func(v: Node3D) -> void:
		if v != null and is_instance_valid(v):
			v.queue_free()
	BendingProjectile.launch(e.ctx, from, dir, speed, h, {"radius": float(p.get("radius", 0.1)), "range": float(p.get("range", 30.0)),
			"gravity": grav, "attack_id": attack_id, "ability_id": a.get("id", &"arrow"), "visual": vis,
			"align": not is_knife, "spin": Vector3(22.0, 0, 0) if is_knife else Vector3.ZERO,
			"impact_size": 0.4, "homing": 0.0, "on_step": step_fx, "on_finish": done})
	Audio.play_sfx(&"whoosh_light", from, -2.0)


# --- events / end -----------------------------------------------------------------------------------

## Rig clip events (connected by EnemyBase).
func on_rig_event(clip: StringName, event: StringName) -> void:
	if phase != Phase.ACTIVE or struck or clip != _clip:
		return
	var kind: StringName = attack.get("kind", &"melee")
	if kind == &"projectile" and event == &"release":
		strike()
	elif (kind == &"melee" or kind == &"slam") and event == &"impact":
		strike()


## Creature action events.
func on_creature_event(_action: StringName, event: StringName) -> void:
	if phase == Phase.ACTIVE and not struck and attack.get("kind", &"") == &"beast" and event == StringName(attack.get("event", &"hit")):
		strike()


func _to_recover() -> void:
	phase = Phase.RECOVER
	phase_t = 0.0
	drive = Vector3.ZERO
	face_locked = true


func _finish() -> void:
	var a := attack
	cooldowns[a.get("id", &"")] = float(a.get("cooldown", 1.5)) * e.cooldown_mult()
	phase = Phase.NONE
	drive = Vector3.ZERO
	face_locked = false
	_release_ring()
	attack = {}
	e.on_attack_finished(a, struck)


func _abort() -> void:
	var a := attack
	phase = Phase.NONE
	drive = Vector3.ZERO
	face_locked = false
	_release_ring()
	if not a.is_empty():
		cooldowns[a.get("id", &"")] = 0.8
	attack = {}
	e.visual.stop(0.15)
	e.on_attack_finished(a, false)


## Interrupts the running attack (stagger, death, despawn). Safe to call any time.
func cancel(reason: StringName = &"cancel") -> void:
	if phase == Phase.NONE:
		return
	var a := attack
	var was := phase
	phase = Phase.NONE
	drive = Vector3.ZERO
	face_locked = false
	_line_t = -1.0
	_release_ring()
	if e.controller != null and e.controller.is_busy():
		e.controller.cancel_current(&"hit" if reason == &"hit" else reason)
	if not a.is_empty():
		cooldowns[a.get("id", &"")] = maxf(cooldown_left(a.get("id", &"")), float(a.get("cooldown", 1.5)) * 0.5)
	attack = {}
	if reason != &"restart":
		if was == Phase.WINDUP:
			e.visual.stop(0.12)
		e.on_attack_finished(a, false)


func _release_ring() -> void:
	if _ring != null and is_instance_valid(_ring):
		FxLib.release(_ring)
	_ring = null
