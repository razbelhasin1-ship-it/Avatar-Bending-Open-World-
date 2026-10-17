class_name WorldFireSpot
extends Node3D
## A pooled stand-in that makes one baked world fire (a brazier, torch, lantern or campfire
## merged into a settlement / outpost / POI cell mesh) answer to bending - see WorldFires.
## It carries the two shared fire contracts at the flame:
##   * IGNITE / EXTINGUISH hooks: groups &"ignitable" / &"extinguishable" with ignite() /
##     extinguish() and their radii, used by FireEnv.heat / ignite_at, WaterEnv.extinguish,
##     AirEnv / FireEnv.extinguish (surges, jets, waves, gusts, fire blasts);
##   * a FireHitProxy (HURTBOX area, team NEUTRAL, no lock, always IGNORED): any bending hit
##     on the flame reacts by FireHitProxy.reaction (water douses, strong wind / heavy earth
##     douses, fire lights).
## It has no mesh: the fire's look is the baked geometry, switched by WorldFires' shader mask.

var spot_id := -1
var ignite_radius := 0.6
var extinguish_radius := 0.6
var proxy: FireHitProxy = null


func _ready() -> void:
	add_to_group(FireEnv.IGNITABLE)
	add_to_group(FireEnv.EXTINGUISHABLE)
	add_to_group(&"world_fire")
	proxy = FireHitProxy.make(0.8, _on_hit)
	proxy.position = Vector3.UP * 0.15
	add_child(proxy)


## Binds the stand-in to a fire (world position of the flame base, reach radius). The hit
## sphere wraps the flame generously and sits up in the flame: its centre (the aim point the
## line-of-sight checks use) must clear the bowl / lantern box the fire stands in, while the
## sphere still reaches down to chest height for a brazier on a plinth.
func bind(id: int, pos: Vector3, radius: float) -> void:
	spot_id = id
	global_position = pos
	ignite_radius = clampf(radius + 0.25, 0.45, 1.0)
	extinguish_radius = ignite_radius
	if proxy:
		proxy.position = Vector3.UP * minf(radius, 0.5)
		proxy.set_radius(clampf(radius + 0.45, 0.6, 1.0))
		proxy.active = true


func release() -> void:
	spot_id = -1
	if proxy:
		proxy.active = false


func is_burning() -> bool:
	return spot_id >= 0 and WorldFires.is_lit(spot_id)


## IGNITE hook. True if the fire caught.
func ignite(by: Node = null, _at: Vector3 = Vector3.ZERO) -> bool:
	return spot_id >= 0 and WorldFires.ignite(spot_id, by)


## EXTINGUISH hook. True if it was burning.
func extinguish(by: Node = null, _at: Vector3 = Vector3.ZERO) -> bool:
	return spot_id >= 0 and WorldFires.extinguish(spot_id, by)


func _on_hit(hit: HitInfo) -> void:
	match FireHitProxy.reaction(hit):
		&"ignite":
			ignite(hit.source, hit.position)
		&"douse":
			extinguish(hit.source, hit.position)
