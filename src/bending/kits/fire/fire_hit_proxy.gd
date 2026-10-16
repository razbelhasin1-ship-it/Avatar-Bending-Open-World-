class_name FireHitProxy
extends Area3D
## Lets a fire world object (a burning grass cell, a brazier) answer to bending hits of
## EVERY element without becoming a combat target - so water whips, air gusts and earth
## blows put fires out and fire bolts light braziers, with no change to those kits:
##
## * an Area3D on Layers.HURTBOX in group &"damageable", team NEUTRAL, tagged &"no_lock"
##   (lock-on / soft aim skip it);
## * receive_hit() hands the hit to `on_hit` and ALWAYS returns IGNORED: no damage, no
##   hit feedback, nothing counted, and projectiles fly on through it.
##
##   var proxy := FireHitProxy.make(0.8, func(hit: HitInfo) -> void: ...)
##   brazier.add_child(proxy)
##   FireHitProxy.reaction(hit)   # &"douse" / &"ignite" / &"" by element (shared rule)

var team: int = Combat.Team.NEUTRAL
var active := true
var on_hit: Callable = Callable()


static func make(radius: float, handler: Callable) -> FireHitProxy:
	var p := FireHitProxy.new()
	p.name = "FireHitProxy"
	p.on_hit = handler
	p.collision_layer = Layers.HURTBOX
	p.collision_mask = 0
	p.monitoring = false
	p.monitorable = true
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	cs.shape = s
	p.add_child(cs)
	p.add_to_group(&"damageable")
	p.set_meta(&"no_lock", true)
	p.set_meta(&"no_burn", true)
	return p


## What a hit does to fire: water douses; a strong gust (force >= 4 or heavy) blows it
## out; a heavy earth blow smothers it; fire lights it. Physical / light hits: nothing.
static func reaction(hit: HitInfo) -> StringName:
	match hit.element:
		ElementDefs.Element.WATER:
			return &"douse"
		ElementDefs.Element.AIR:
			return &"douse" if hit.is_heavy or hit.force >= 4.0 else &""
		ElementDefs.Element.EARTH:
			return &"douse" if hit.is_heavy else &""
		ElementDefs.Element.FIRE:
			return &"ignite"
	if hit.status.has("soaked"):
		return &"douse"
	return &""


func set_radius(r: float) -> void:
	for c in get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is SphereShape3D:
			((c as CollisionShape3D).shape as SphereShape3D).radius = r


func is_alive() -> bool:
	return active and is_inside_tree()


func get_aim_point() -> Vector3:
	return global_position


func get_display_name() -> String:
	return ""


func receive_hit(hit: HitInfo) -> int:
	if active and on_hit.is_valid():
		on_hit.call(hit)
	return Combat.Result.IGNORED
