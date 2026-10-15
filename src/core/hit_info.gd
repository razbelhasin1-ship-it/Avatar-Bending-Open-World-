class_name HitInfo
extends RefCounted
## Everything a damageable needs to know about an incoming hit.
##
## Created by an attacker (ability, enemy attack, hazard) and passed to
## Combat.deal(target, hit). Receivers decide the final outcome (block,
## deflect, dodge, damage) and return a Combat.Result value.

enum Reaction {
	NONE,       ## Damage only (chip / DoT).
	FLINCH,     ## Short upper-body flinch, does not interrupt heavy/armored actions.
	STAGGER,    ## Interrupts the current action for `stun_time`.
	KNOCKBACK,  ## Pushed along `direction` with `force` m/s, stays on feet.
	KNOCKDOWN,  ## Falls to the ground, must get up.
	LAUNCH,     ## Thrown into the air (`lift` m/s upward), lands knocked down.
	PULL,       ## Pulled toward `origin` (tornado, water whip yank).
	FREEZE,     ## Encased/rooted in ice or stone for `stun_time`.
}

var damage: float = 0.0
## ElementDefs.Element of the attack (NONE for physical).
var element: int = -1
## Node that caused the hit (player, enemy, hazard). Used for team checks and aggro.
var source: Node = null
## Team of the attacker (Combat.Team). Hits never affect the same team.
var team: int = 0
var reaction: Reaction = Reaction.FLINCH
## Normalized horizontal direction the target is pushed (attacker -> target).
var direction: Vector3 = Vector3.FORWARD
## Horizontal knockback speed in m/s.
var force: float = 0.0
## Vertical launch speed in m/s.
var lift: float = 0.0
## Seconds of hit-stun / freeze / root.
var stun_time: float = 0.0
## World position where the hit connected (for VFX).
var position: Vector3 = Vector3.ZERO
## Point the effect originates from (projectile origin, tornado center, ...).
var origin: Vector3 = Vector3.ZERO
## Poise damage: how much this breaks guard / armor.
var poise_damage: float = 10.0
var is_heavy: bool = false
var is_projectile: bool = false
var unblockable: bool = false
## Projectiles that can be redirected by water/air defenses set this.
var deflectable: bool = false
## Unique id per attack instance so multi-shape attacks hit each target once.
var attack_id: int = 0
## Ability id or attack name (for stats, quests, tutorial checks).
var ability_id: StringName = &""
## Status effect payloads, e.g. {"burn": 3.0} or {"soaked": 4.0}, {"chill": 2.0}.
var status: Dictionary = {}

static var _next_attack_id: int = 1


static func new_attack_id() -> int:
	_next_attack_id += 1
	return _next_attack_id


static func make(p_damage: float, p_source: Node, p_element: int, p_reaction: Reaction, p_direction: Vector3, p_force: float = 0.0) -> HitInfo:
	var h := HitInfo.new()
	h.damage = p_damage
	h.source = p_source
	h.element = p_element
	h.reaction = p_reaction
	var d := Vector3(p_direction.x, 0.0, p_direction.z)
	h.direction = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	h.force = p_force
	if p_source != null and "team" in p_source:
		h.team = p_source.team
	if p_source is Node3D:
		h.origin = (p_source as Node3D).global_position
	h.attack_id = new_attack_id()
	return h


func duplicate_hit() -> HitInfo:
	var h := HitInfo.new()
	for p in ["damage", "element", "source", "team", "reaction", "direction", "force", "lift",
			"stun_time", "position", "origin", "poise_damage", "is_heavy", "is_projectile",
			"unblockable", "deflectable", "attack_id", "ability_id"]:
		h.set(p, get(p))
	h.status = status.duplicate()
	return h
