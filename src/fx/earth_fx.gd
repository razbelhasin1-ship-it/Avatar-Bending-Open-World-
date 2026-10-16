class_name EarthFx
extends RefCounted
## Earthbending visuals: solid flat-shaded toon rocks (projectiles, boulders),
## tear-out bursts (debris + dust + crack decal), dust trails and quakes.
##
##   var r := EarthFx.rock(self, 0.45)            # pooled rock mesh node; EarthFx.release_rock(r)
##   EarthFx.tear_out(self, ground_pos, 0.5, surface)
##   EarthFx.impact(self, pos, 0.6, surface)
##   EarthFx.quake(self, ground_pos, 3.0)

const ROCK_COLOR := Color(0.56, 0.47, 0.37)


static func rock_material(color: Color = ROCK_COLOR) -> ShaderMaterial:
	return ToonMaterials.make(color, {"vertex_color": true, "outline_width": 1.2, "rim": 0.25, "outline_color": Color(0.09, 0.07, 0.05)})


## A rock mesh node (diameter ~ 2 * radius). Pooled: give it back with release_rock().
static func rock(from: Node, radius: float, variant: int = -1, color: Color = ROCK_COLOR) -> MeshInstance3D:
	var v := variant if variant >= 0 else randi() % 6
	var m := FxLib.take(from, &"rock_mesh", func() -> Node3D:
		var mi := MeshInstance3D.new()
		mi.name = "Rock"
		return mi) as MeshInstance3D
	m.mesh = FxMeshes.rock(v, 1 if radius > 0.3 else 0)
	m.material_override = rock_material(color)
	m.scale = Vector3.ONE * radius * 2.0
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if radius > 0.35 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


static func release_rock(m: MeshInstance3D) -> void:
	FxLib.release(m)


## Ground tears open where rock is ripped out: debris, dust and a crack.
static func tear_out(from: Node, ground_pos: Vector3, size: float, surface: StringName = &"dirt") -> void:
	var col := FxLib.surface_color(surface)
	FxDebris.spawn(from, ground_pos + Vector3.UP * 0.05, {"count": 4 + int(size * 6.0), "size": 0.08 + size * 0.12, "up": 3.0 + size * 3.0, "out": 1.5 + size * 2.0,
			"ground_y": ground_pos.y, "color": col.darkened(0.15)})
	FxBurst.spawn(from, &"dust", ground_pos, {"color": col, "count": 0.6 + size, "size": 0.6 + size * 0.6, "radius": 0.6 + size})
	FxDecal.spawn(from, ground_pos, &"crack", 0.6 + size * 1.4)


## Rock smashing into something: chunks, dust, ring.
static func impact(from: Node, pos: Vector3, size: float, surface: StringName = &"dirt", ground_y: float = INF) -> void:
	var gy := ground_y if ground_y < INF else pos.y - 0.5
	FxDebris.spawn(from, pos, {"count": 5 + int(size * 6.0), "size": 0.1 + size * 0.14, "up": 3.5 + size * 2.0, "out": 3.0 + size * 2.5, "ground_y": gy})
	FxBurst.spawn(from, &"dust", pos, {"color": FxLib.surface_color(surface), "count": 0.8 + size, "size": 0.7 + size * 0.7, "speed": 1.2 + size * 0.5, "spread": 120.0})
	if size > 0.6:
		FxRing.spawn(from, Vector3(pos.x, gy, pos.z), 1.5 + size * 2.0, FxLib.surface_color(surface), 0.45, {"opacity": 0.55, "fill": 0.3})
		FxDecal.spawn(from, Vector3(pos.x, gy, pos.z), &"crack", 0.8 + size)


## Shockwave over the ground (earth landings, stomps, slides).
static func quake(from: Node, ground_pos: Vector3, radius: float, surface: StringName = &"dirt") -> void:
	var col := FxLib.surface_color(surface)
	FxRing.spawn(from, ground_pos, radius, col.lightened(0.1), 0.55, {"opacity": 0.7, "width": 0.2, "fill": 0.35, "inner": col})
	FxBurst.spawn(from, &"dust_ring", ground_pos, {"color": col, "radius": radius * 0.5, "count": 1.0 + radius * 0.2})
	FxDebris.spawn(from, ground_pos, {"count": 3 + int(radius), "size": 0.12, "up": 3.0, "out": radius * 1.2, "ground_y": ground_pos.y, "color": col.darkened(0.2)})
	FxDecal.spawn(from, ground_pos, &"crack", radius * 0.55)


## Dust kicked up along a slide or a dragged rock.
static func dust_trail(from: Node, ground_pos: Vector3, dir: Vector3, surface: StringName = &"dirt", strength: float = 1.0) -> void:
	FxBurst.spawn(from, &"dust", ground_pos, {"color": FxLib.surface_color(surface), "count": 0.5 * strength, "dir": (Vector3.UP * 0.6 - dir * 0.4), "size": 0.7, "spread": 45.0})
