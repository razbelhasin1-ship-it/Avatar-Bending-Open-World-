class_name TouchLayout
extends RefCounted
## Where every touch widget goes (docs/GAME_DESIGN.md "Touch layout"), in the overlay's
## design-pixel space (1920x1080 base, wider/taller with the `expand` stretch, already
## inset by the display safe area).
##
## Right thumb (mirrored when left-handed): a large Strike button near the corner, Heavy /
## Dodge / Defend / Jump around it, and an arc of the four technique slots + the round
## Signature slot outside them. Left thumb: the floating stick zone with a resting hint.
## Top-right: a row of small menu buttons (pause, lock-on, call companion, map, journal).
## The contextual Interact / Dismount button sits bottom-centre, its text toward the middle.
##
##   var l := TouchLayout.compute(Rect2(Vector2.ZERO, size), 1.0, false, [&"pause", &"lock"])
##   l.buttons[&"strike"]    # {"center": Vector2, "radius": float}

## Offsets from the bottom-right corner (x left of it, y above it) and radii at scale 1.
const CLUSTER := {
	&"strike": [Vector2(220, 210), 96.0],
	&"heavy": [Vector2(415, 240), 62.0],
	&"dodge": [Vector2(395, 95), 58.0],
	&"defend": [Vector2(300, 415), 58.0],
	&"jump": [Vector2(115, 405), 64.0],
}
## Technique arc around the Strike button: radius and angles (degrees, screen space, y down).
const ARC_RADIUS := 340.0
const ARC_ANGLES := {&"tech_0": -96.0, &"tech_1": -120.0, &"tech_2": -145.0, &"tech_3": -172.0, &"signature": 162.0}
const TECH_RADIUS := 52.0
const SIGNATURE_RADIUS := 62.0
## Extent of the cluster from the corner at scale 1 (fit check).
const CLUSTER_EXTENT := Vector2(620, 610)
const TOP_RADIUS := 46.0
const TOP_SPACING := 112.0
const TOP_MARGIN := Vector2(66, 64)
const STICK_RADIUS := 118.0
## Top of the stick zone (below the vitals).
const STICK_ZONE_TOP := 170.0
## Fraction of the width (from the stick side) where a thumb starts the stick.
const STICK_ZONE_W := 0.46
const INTERACT_RADIUS := 60.0
const INTERACT_OFFSET := Vector2(150, 150)
## Order of the top bar from the right edge.
const TOP_ORDER: Array[StringName] = [&"pause", &"lock", &"call", &"map", &"journal"]


## Layout for `rect` (overlay local space) at `scale` (touch.button_scale). `top_ids`
## lists the top-bar buttons to place (hidden ones are skipped so the row stays packed).
## Returns {"buttons": {id: {"center", "radius"}}, "stick_zone": Rect2, "stick_rest": Vector2,
##          "stick_radius": float, "scale": float (effective), "interact_text_dir": -1|1}.
static func compute(rect: Rect2, scale: float, left_handed: bool, top_ids: Array = []) -> Dictionary:
	var w := rect.size.x
	var h := rect.size.y
	# The cluster must fit: shrink the effective scale on short / narrow screens.
	var s := clampf(scale, 0.6, 1.6)
	s = minf(s, (h - 150.0) / CLUSTER_EXTENT.y)
	s = minf(s, (w * 0.5) / CLUSTER_EXTENT.x)
	s = maxf(s, 0.45)
	var corner := rect.end
	var buttons := {}
	var mirror := func(p: Vector2) -> Vector2:
		return Vector2(rect.position.x + rect.end.x - p.x, p.y) if left_handed else p
	for id: StringName in CLUSTER:
		var spec: Array = CLUSTER[id]
		var off: Vector2 = spec[0]
		buttons[id] = {"center": mirror.call(corner - off * s), "radius": float(spec[1]) * s}
	var strike_c: Vector2 = corner - (CLUSTER[&"strike"][0] as Vector2) * s
	for id: StringName in ARC_ANGLES:
		var a := deg_to_rad(float(ARC_ANGLES[id]))
		var c := strike_c + Vector2(cos(a), sin(a)) * ARC_RADIUS * s
		var r := SIGNATURE_RADIUS if id == &"signature" else TECH_RADIUS
		buttons[id] = {"center": mirror.call(c), "radius": r * s}
	# Mounted: Descend takes the Dodge spot.
	buttons[&"descend"] = (buttons[&"dodge"] as Dictionary).duplicate()
	# Top bar (never mirrored: the vitals own the top-left).
	var ts := clampf(scale, 0.96, 1.3)
	var x := rect.end.x - TOP_MARGIN.x * ts
	for id: StringName in TOP_ORDER:
		if not top_ids.has(id):
			continue
		buttons[id] = {"center": Vector2(x, rect.position.y + TOP_MARGIN.y * ts), "radius": TOP_RADIUS * ts}
		x -= TOP_SPACING * ts
	# Contextual button: bottom centre, offset toward the cluster; text toward the middle.
	# Never inside the cluster: big buttons / narrow screens push it toward the middle.
	var ir := INTERACT_RADIUS * maxf(s, 0.9)
	var cluster_left := corner.x - CLUSTER_EXTENT.x * s
	var ic := Vector2(minf(rect.position.x + w * 0.5 + INTERACT_OFFSET.x * s, cluster_left - 24.0 - ir), rect.end.y - INTERACT_OFFSET.y * s)
	buttons[&"interact"] = {"center": mirror.call(ic), "radius": ir}
	# Stick.
	var sr := STICK_RADIUS * s
	var zone := Rect2(rect.position.x, rect.position.y + STICK_ZONE_TOP, w * STICK_ZONE_W, h - STICK_ZONE_TOP)
	var rest := Vector2(rect.position.x + sr + 110.0 * s, rect.end.y - sr - 150.0 * s)
	if left_handed:
		zone.position.x = rect.end.x - zone.size.x
		rest = mirror.call(rest)
	return {"buttons": buttons, "stick_zone": zone, "stick_rest": rest, "stick_radius": sr, "scale": s,
			"interact_text_dir": 1 if left_handed else -1}


## True if no two buttons of `ids` overlap (used by tests for every scale / aspect).
static func overlaps(layout: Dictionary, ids: Array) -> Array:
	var out: Array = []
	var b: Dictionary = layout["buttons"]
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if not b.has(ids[i]) or not b.has(ids[j]):
				continue
			var a: Dictionary = b[ids[i]]
			var c: Dictionary = b[ids[j]]
			if (a["center"] as Vector2).distance_to(c["center"]) < float(a["radius"]) + float(c["radius"]):
				out.append([ids[i], ids[j]])
	return out
