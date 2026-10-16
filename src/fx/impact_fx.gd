class_name ImpactFx
extends RefCounted
## Element impact bursts for hits on targets and the world, blocks and parries.
## Gameplay code only calls these for hits that really happened (see
## BendingFeedback): a visible hit always means damage was applied.
##
##   ImpactFx.hit(self, ElementDefs.Element.FIRE, pos, dir, heavy)
##   ImpactFx.block(self, element, pos, dir)
##   ImpactFx.parry(self, element, pos)

## Spawn counters (tests compare them with applied damage).
static var hits_shown := 0


static func hit(from: Node, element: int, pos: Vector3, dir: Vector3 = Vector3.ZERO, heavy: bool = false) -> void:
	hits_shown += 1
	FxLib.note(&"impact_hit")
	var k := 1.5 if heavy else 1.0
	var d := dir.normalized() if dir.length_squared() > 1e-4 else Vector3.UP
	match element:
		ElementDefs.Element.AIR:
			AirFx.swirl(from, pos, 0.5 * k, 0.32, {"grow": 2.0, "spin": 14.0, "opacity": 0.7, "height": 0.15})
			FxBurst.spawn(from, &"dust", pos, {"color": Color(0.9, 0.95, 1.0), "count": 0.4 * k, "size": 0.5, "dir": d})
		ElementDefs.Element.EARTH:
			FxDebris.spawn(from, pos, {"count": int(4 * k), "size": 0.09 * k, "up": 3.0, "out": 2.5, "dir": d, "ground_y": pos.y - 1.1})
			FxBurst.spawn(from, &"dust", pos, {"color": EarthFx.ROCK_COLOR.lightened(0.3), "count": 0.5 * k, "size": 0.55 * k, "dir": d})
		ElementDefs.Element.FIRE:
			FxBurst.spawn(from, &"flame", pos, {"size": 0.55 * k, "count": 0.7 * k, "dir": d, "spread": 70.0})
			FxBurst.spawn(from, &"sparks", pos, {"count": 0.6 * k, "dir": d})
			FxFlash.spawn(from, pos, Color(1.0, 0.6, 0.25), 2.0 * k, 0.15, 4.0)
		ElementDefs.Element.WATER:
			IceFx.splash(from, pos, 0.7 * k, d)
		_:
			FxBurst.spawn(from, &"dust", pos, {"color": Color(0.95, 0.92, 0.85), "count": 0.4, "size": 0.4})
	FxBurst.spawn(from, &"sparkle" if element != ElementDefs.Element.FIRE else &"embers", pos, {"count": 0.4 * k, "dir": d})


static func block(from: Node, element: int, pos: Vector3, dir: Vector3 = Vector3.ZERO) -> void:
	FxLib.note(&"impact_block")
	var d := dir.normalized() if dir.length_squared() > 1e-4 else Vector3.UP
	FxBurst.spawn(from, &"sparks", pos, {"count": 0.5, "dir": d, "color": FxLib.palette(element)[0]})
	match element:
		ElementDefs.Element.AIR:
			AirFx.swirl(from, pos, 0.4, 0.25, {"grow": 1.6, "spin": 18.0, "opacity": 0.6, "height": 0.1})
		ElementDefs.Element.EARTH:
			FxDebris.spawn(from, pos, {"count": 3, "size": 0.07, "up": 2.0, "out": 1.5, "dir": d, "ground_y": pos.y - 1.1})
		ElementDefs.Element.FIRE:
			FxBurst.spawn(from, &"flame", pos, {"size": 0.4, "count": 0.5, "dir": d})
		ElementDefs.Element.WATER:
			FxBurst.spawn(from, &"droplets", pos, {"count": 0.5, "dir": d})


static func parry(from: Node, element: int, pos: Vector3) -> void:
	FxLib.note(&"impact_parry")
	var pal := FxLib.palette(element)
	FxRing.spawn(from, pos, 1.6, pal[0], 0.3, {"normal": Vector3.UP, "opacity": 0.9, "width": 0.25, "inner": pal[1], "fill": 0.0})
	FxBurst.spawn(from, &"sparkle", pos, {"count": 1.5, "spread": 180.0, "speed": 1.6})
	FxFlash.spawn(from, pos, pal[1].lightened(0.3), 3.0, 0.2, 5.0)
	match element:
		ElementDefs.Element.AIR:
			AirFx.swirl(from, pos - Vector3.UP * 0.4, 1.0, 0.35, {"grow": 2.0, "spin": 20.0})
		ElementDefs.Element.FIRE:
			FireFx.burst(from, pos, 1.3)
		ElementDefs.Element.WATER:
			IceFx.splash(from, pos, 1.0)
		ElementDefs.Element.EARTH:
			FxDebris.spawn(from, pos, {"count": 5, "size": 0.1, "up": 3.0, "out": 2.0, "ground_y": pos.y - 1.2})


## Projectile hitting terrain / walls.
static func world(from: Node, element: int, pos: Vector3, normal: Vector3, size: float = 1.0, surface: StringName = &"dirt") -> void:
	FxLib.note(&"impact_world")
	match element:
		ElementDefs.Element.AIR:
			AirFx.ground_puff(from, pos, surface, 0.7 * size, normal)
		ElementDefs.Element.EARTH:
			EarthFx.impact(from, pos, size * 0.6, surface, pos.y)
		ElementDefs.Element.FIRE:
			FireFx.burst(from, pos, size, normal)
			FxDecal.spawn(from, pos, &"scorch", 0.5 + size * 0.5, normal)
		ElementDefs.Element.WATER:
			IceFx.splash(from, pos, size, normal, pos.y)
