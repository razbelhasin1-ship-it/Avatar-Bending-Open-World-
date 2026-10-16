class_name BendingContext
extends RefCounted
## Everything an ability needs to know about its caster. Works for the player
## AND for non-player casters (enemies reuse the same abilities with team ENEMY):
##
##   var ctx := BendingContext.new(enemy_body, enemy_rig, ElementDefs.Element.FIRE, Combat.Team.ENEMY)
##   ctx.aim_provider = func() -> Dictionary: return {"target": player, "direction": dir}
##   var bc := BendingController.new(); enemy_body.add_child(bc); bc.setup(ctx)
##
## Abilities steer the caster's body through the movement request fields
## (move_mode, move_velocity, gravity_scale, face_dir ...); the owner (player
## state machine / enemy AI) applies them every physics tick.

enum Move {
	BRAKE,  ## stop quickly (default during attacks)
	FREE,   ## normal locomotion at move_speed_scale (defense, light upper-body strikes)
	DRIVE,  ## velocity = move_velocity (dashes, lunges)
	ROOT,   ## rig root motion moves the body
	HOLD,   ## keep position exactly
}

var caster: Node3D
var body: CharacterBody3D
var rig: HumanoidRig
var element: int = ElementDefs.Element.NONE
var team: int = Combat.Team.PLAYER
var controller: BendingController = null
## Object with has_chi/spend_chi/add_focus/spend_focus and `upkeep` (PlayerResources); null = unlimited.
var resources: Object = null
## () -> {"direction": Vector3, "target": Node3D or null, "point": Vector3}
var aim_provider: Callable = Callable()
## Called for every hit an ability delivers: (hit, target, result).
var on_hit: Callable = Callable()
## Current move intent of the caster (world dir, length 0..1): dodges read it.
## The owner updates it every tick (player input / AI).
var move_input := Vector3.ZERO

# --- movement request (reset by the controller when an ability begins) ------------------
var move_mode: int = Move.BRAKE
var move_velocity := Vector3.ZERO
var move_speed_scale := 0.0
var brake_rate := 40.0
## Gravity multiplier while the ability runs (0 = hover, dash).
var gravity_scale := 1.0
## Desired facing (ZERO = keep) and turn rate in deg/s.
var face_dir := Vector3.ZERO
var face_rate := 1440.0
## Poise armor (poise damage the current action ignores) and i-frames flag.
var poise_armor := 0.0
var invulnerable := false
## Damage reduction 0..1 while executing (earth armor style actions).
var damage_reduction := 0.0
## Set while delivering parry counters: those hits grant no extra Focus.
var no_focus := false


func _init(p_caster: Node3D = null, p_rig: HumanoidRig = null, p_element: int = ElementDefs.Element.NONE, p_team: int = Combat.Team.PLAYER) -> void:
	caster = p_caster
	body = p_caster as CharacterBody3D
	rig = p_rig
	element = p_element
	team = p_team


func reset_request() -> void:
	move_mode = Move.BRAKE
	move_velocity = Vector3.ZERO
	move_speed_scale = 0.0
	brake_rate = 40.0
	gravity_scale = 1.0
	face_dir = Vector3.ZERO
	face_rate = 1440.0
	poise_armor = 0.0
	invulnerable = false
	damage_reduction = 0.0


func is_valid() -> bool:
	return caster != null and is_instance_valid(caster) and caster.is_inside_tree()


func is_player() -> bool:
	return team == Combat.Team.PLAYER and caster != null and caster.is_in_group(&"player")


func world() -> World3D:
	return caster.get_world_3d()


func space() -> PhysicsDirectSpaceState3D:
	return caster.get_world_3d().direct_space_state


func tree() -> SceneTree:
	return caster.get_tree()


## Layers this caster's attacks can damage.
func hit_mask() -> int:
	return Layers.PLAYER_ATTACK_TARGETS if team == Combat.Team.PLAYER else Layers.ENEMY_ATTACK_TARGETS


## World geometry that stops projectiles / blocks line of sight.
func solid_mask() -> int:
	return Layers.SOLID


func exclude() -> Array[RID]:
	var out: Array[RID] = []
	var co := caster as CollisionObject3D
	if co:
		out.append(co.get_rid())
	return out


# --- spatial helpers ----------------------------------------------------------------------

func origin() -> Vector3:
	return caster.global_position


func forward() -> Vector3:
	var f := -caster.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 1e-6 else Vector3.FORWARD


func right() -> Vector3:
	var f := forward()
	return Vector3(-f.z, 0.0, f.x)


## World position of a rig socket (hand_l, hand_r, foot_l, foot_r, chest, head, mouth...).
func socket_pos(socket_name: StringName) -> Vector3:
	if rig != null and is_instance_valid(rig):
		var s := rig.get_socket(socket_name)
		if s:
			return s.global_position
	var o := origin()
	match socket_name:
		&"hand_l": return o + Vector3.UP * 1.3 - right() * 0.3 + forward() * 0.3
		&"hand_r": return o + Vector3.UP * 1.3 + right() * 0.3 + forward() * 0.3
		&"foot_l": return o - right() * 0.15
		&"foot_r": return o + right() * 0.15
		&"head": return o + Vector3.UP * 1.6
	return o + Vector3.UP * 1.25


## Midpoint between both hands.
func hands_pos() -> Vector3:
	return (socket_pos(&"hand_l") + socket_pos(&"hand_r")) * 0.5


## Ground height under a point (physics first, then WorldData).
func ground_y(p: Vector3, probe_up: float = 2.0, probe_down: float = 6.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * probe_up, p + Vector3.DOWN * probe_down, Layers.WORLD)
	q.exclude = exclude()
	var r := space().intersect_ray(q)
	if not r.is_empty():
		return (r["position"] as Vector3).y
	return WorldData.get_height(p.x, p.z)


func ground_point(p: Vector3) -> Vector3:
	return Vector3(p.x, ground_y(p), p.z)


func surface_at(p: Vector3) -> StringName:
	return GroundSampler.surface(p)


# --- aim ---------------------------------------------------------------------------------

## {"direction": Vector3 (normalized, may have y), "target": Node3D or null, "point": Vector3}
func aim() -> Dictionary:
	if aim_provider.is_valid():
		var a: Variant = aim_provider.call()
		if a is Dictionary:
			var d: Dictionary = a
			if not d.has("direction") or (d["direction"] as Vector3).length_squared() < 1e-6:
				d["direction"] = forward()
			return d
	return {"direction": forward(), "target": null, "point": origin() + forward() * 10.0}


func aim_target() -> Node3D:
	var t: Variant = aim().get("target")
	return t as Node3D if t is Node3D and is_instance_valid(t) else null


## Horizontal aim direction.
func aim_flat() -> Vector3:
	var d: Vector3 = aim()["direction"]
	d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-6 else forward()


## Aim point for a target (its chest), or `fallback_dist` along the aim.
static func target_point(t: Node3D) -> Vector3:
	if t == null or not is_instance_valid(t):
		return Vector3.ZERO
	if t.has_method("get_aim_point"):
		return t.call("get_aim_point")
	return t.global_position + Vector3.UP * 1.1


## Direction from `from` to the aim (target point with lead for projectiles of `speed`).
func aim_dir_from(from: Vector3, speed: float = 0.0, lead: float = 0.6) -> Vector3:
	var t := aim_target()
	if t != null:
		var p := target_point(t)
		if speed > 0.0 and lead > 0.0:
			p = BendingContext.lead_point(from, p, target_velocity(t), speed, lead)
		var d := p - from
		if d.length_squared() > 0.01:
			return d.normalized()
	var a: Dictionary = aim()
	var pt: Vector3 = a.get("point", Vector3.INF)
	if pt.is_finite() and (pt - from).length() > 1.5:
		return (pt - from).normalized()
	return (a["direction"] as Vector3).normalized()


static func target_velocity(t: Node3D) -> Vector3:
	if t is CharacterBody3D:
		return (t as CharacterBody3D).velocity
	if t is RigidBody3D:
		return (t as RigidBody3D).linear_velocity
	if t.has_method("get_velocity"):
		return t.call("get_velocity")
	return Vector3.ZERO


## Intercept point for a projectile of `speed` from `from` toward a target at
## `p` moving with `v`; `lead` 0..1 blends from no lead to full intercept.
static func lead_point(from: Vector3, p: Vector3, v: Vector3, speed: float, lead: float = 1.0) -> Vector3:
	if speed <= 0.0 or v.length_squared() < 0.01:
		return p
	var d := p - from
	var a := v.dot(v) - speed * speed
	var b := 2.0 * d.dot(v)
	var c := d.dot(d)
	var t := -1.0
	if absf(a) < 1e-4:
		t = -c / b if absf(b) > 1e-4 else -1.0
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var s := sqrt(disc)
			var t1 := (-b - s) / (2.0 * a)
			var t2 := (-b + s) / (2.0 * a)
			t = minf(t1, t2) if minf(t1, t2) > 0.0 else maxf(t1, t2)
	if t <= 0.0 or t > 3.0:
		return p
	return p + v * t * clampf(lead, 0.0, 1.0)


# --- resources -----------------------------------------------------------------------------

func has_chi(amount: float) -> bool:
	return resources == null or resources.call("has_chi", amount)


func spend_chi(amount: float) -> bool:
	return resources == null or resources.call("spend_chi", amount)


func set_upkeep(per_second: float) -> void:
	if resources != null and "upkeep" in resources:
		resources.set("upkeep", per_second)


func chi() -> float:
	return float(resources.get("chi")) if resources != null and "chi" in resources else 100.0


func focus() -> float:
	return float(resources.get("focus")) if resources != null and "focus" in resources else 100.0


func add_focus(amount: float) -> void:
	if resources != null and resources.has_method("add_focus"):
		resources.call("add_focus", amount)


func spend_focus(amount: float) -> bool:
	if resources == null or not resources.has_method("spend_focus"):
		return true
	return resources.call("spend_focus", amount)


# --- hits ----------------------------------------------------------------------------------

## Builds a HitInfo from an ability hit dictionary (see AbilityDef).
func make_hit(h: Dictionary, direction: Vector3, attack_id: int = 0, ability_id: StringName = &"") -> HitInfo:
	var hit := HitInfo.make(float(h.get("damage", 10.0)), caster, element, int(h.get("reaction", HitInfo.Reaction.FLINCH)) as HitInfo.Reaction,
			direction, float(h.get("force", 0.0)))
	hit.team = team
	hit.lift = float(h.get("lift", 0.0))
	hit.stun_time = float(h.get("stun", 0.0))
	hit.poise_damage = float(h.get("poise", 10.0))
	hit.is_heavy = bool(h.get("heavy", false))
	hit.is_projectile = bool(h.get("projectile", false))
	hit.deflectable = bool(h.get("deflectable", hit.is_projectile))
	hit.unblockable = bool(h.get("unblockable", false))
	if h.has("status"):
		hit.status = (h["status"] as Dictionary).duplicate()
	if attack_id != 0:
		hit.attack_id = attack_id
	hit.ability_id = ability_id
	return hit
