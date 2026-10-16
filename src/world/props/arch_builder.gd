class_name ArchBuilder
extends RefCounted
## Natural rock arches from WorldData.get_arches() ({a, b (feet on the ground), width, apex_height}).
## A rock span along a Bezier curve whose top reaches apex_height, thick at the feet (buried in the
## ground) and thinner at the crown, with an irregular faceted cross-section, sediment strata
## bands and mossy/snowy tops by region. Collision is the trimesh of the span (benders can run
## across the top). Thread-safe; returns a KitResult in world space relative to `origin`.

const RING := 10


static func build(rec: Dictionary) -> Dictionary:
	var a: Vector3 = rec["a"]
	var b: Vector3 = rec["b"]
	var width := float(rec.get("width", 9.0))
	var apex := float(rec.get("apex_height", maxf(a.y, b.y) + 30.0))
	var rng := ContentHash.rng(ContentHash.hash_name(String(rec.get("id", "arch"))))
	var origin := (a + b) * 0.5
	origin.y = minf(a.y, b.y)
	var region := WorldData.get_region(origin.x, origin.z)
	var pi := TerrainPatterns.palette_index(region)
	var rock_l := TerrainPatterns.ROCK_L[pi].srgb_to_linear()
	var rock_d := TerrainPatterns.ROCK_D[pi].srgb_to_linear()
	var top_c := Color(0.32, 0.46, 0.18).srgb_to_linear() if pi == 1 or pi == 2 else Color(0.93, 0.95, 1.0).srgb_to_linear()
	# control point so the curve's peak reaches the apex
	var c := (a + b) * 0.5
	c.y = 2.0 * apex - 0.5 * (a.y + b.y)
	var span := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := clampi(int(span / 3.0), 16, 48)
	var kit := BuildingKit.new(NationPalette.get_palette(&"neutral"), 0, rng.randi())
	kit.color_jitter = 0.0
	var gb := kit.g()
	var rings: Array = []
	var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var across := dir.cross(Vector3.UP).normalized()
	for i in steps + 1:
		var t := lerpf(-0.06, 1.06, float(i) / steps)
		var p := _bez(a, c, b, t)
		var tan := (_bez(a, c, b, t + 0.01) - _bez(a, c, b, t - 0.01)).normalized()
		var up := across.cross(tan).normalized()
		if up.y < 0.0:
			up = -up
		var crown := sin(clampf(t, 0.0, 1.0) * PI)
		var half_w := width * 0.5 * lerpf(1.35, 0.85, crown)
		var half_h := width * 0.5 * lerpf(1.25, 0.55, crown)
		var ring := PackedVector3Array()
		for k in RING:
			var ang := TAU * float(k) / RING
			var noise := 1.0 + (ContentHash.unit(ContentHash.hash4(i, k, 31)) - 0.5) * 0.35
			ring.append(p + across * cos(ang) * half_w * noise + up * sin(ang) * half_h * noise - origin)
		rings.append(ring)
	for i in steps:
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		for k in RING:
			var k1 := (k + 1) % RING
			var pa := r0[k]
			var pb := r0[k1]
			var pc := r1[k1]
			var pd := r1[k]
			var col := _rock_col(pa + origin, rock_l, rock_d, rng)
			var n := (pb - pa).cross(pc - pa)
			var center := (pa + pb + pc + pd) * 0.25
			var mid_ring := (r0[0] + r0[RING / 2]) * 0.5
			if n.dot(center - mid_ring) < 0.0:
				# keep faces pointing out of the span
				var tmp := pb
				pb = pd
				pd = tmp
				n = (pb - pa).cross(pc - pa)
			if n.normalized().y > 0.7:
				col = col.lerp(top_c, 0.7)
			gb.flat_quad(pa, pb, pc, pd, col)
			kit.collide_quad(pa, pb, pc, pd)
	# boulder scree at the feet
	for foot: Vector3 in [a, b]:
		for k in 5:
			var q: Vector3 = foot + across * rng.randf_range(-1.5, 1.5) * width + dir * rng.randf_range(-1.0, 1.0) * width * 0.6
			q.y = WorldData.get_height(q.x, q.z)
			var r := rng.randf_range(0.8, 2.2)
			gb.blob(q - origin, r, 1, _rock_col(q, rock_l, rock_d, rng), rng, 0.3, Vector3(1.0, 0.7, 1.0), Vector3.INF, 0.0, rock_d, Vector2.ZERO, true)
	return {"kit": kit.build(), "origin": origin}


static func _bez(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * u * u + c * 2.0 * u * t + b * t * t


## Sediment strata: horizontal bands by world height + facet variation.
static func _rock_col(p: Vector3, l: Color, d: Color, rng: RandomNumberGenerator) -> Color:
	var band := fposmod(p.y * 0.28, 1.0)
	var k := 0.55 + 0.45 * smoothstep(0.2, 0.8, band) + rng.randf_range(-0.05, 0.05)
	return d.lerp(l, clampf(k, 0.0, 1.0))
