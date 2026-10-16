class_name IceFx
extends RefCounted
## Ice visuals: crystal shards (projectiles), frozen chunks, shatter bursts
## with sparkles and frost marks, water splashes.
##
##   var s := IceFx.shard(self, 0.7)          # pooled shard mesh pointing along -Z; FxLib.release(s)
##   IceFx.shatter(self, pos, dir)
##   IceFx.splash(self, pos, 1.0)


## Ice dagger mesh node (tip along -Z).
static func shard(from: Node, length: float = 0.7, variant: int = -1) -> MeshInstance3D:
	var v := variant if variant >= 0 else randi() % 4
	var m := FxLib.take(from, &"ice_shard_mesh", func() -> Node3D:
		var mi := MeshInstance3D.new()
		mi.name = "IceShard"
		mi.material_override = FxDebris.ice_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi) as MeshInstance3D
	m.mesh = FxMeshes.shard(0.7, 0.085, v)
	m.scale = Vector3.ONE * (length / 0.7)
	return m


## Ice breaking: shards fly, sparkles, frost decal on the ground.
static func shatter(from: Node, pos: Vector3, dir: Vector3 = Vector3.ZERO, size: float = 1.0, ground_y: float = INF) -> void:
	FxDebris.spawn(from, pos, {"kind": &"ice", "count": 5 + int(size * 4.0), "size": 0.5 * size, "up": 3.0, "out": 2.5 + size, "dir": dir * 0.6,
			"ground_y": ground_y if ground_y < INF else pos.y - 1.0, "life": 1.1})
	FxBurst.spawn(from, &"sparkle", pos, {"count": 0.8 + size * 0.6})
	FxBurst.spawn(from, &"snow", pos, {"count": 0.5 * size, "size": 0.6, "color": Color(0.88, 0.96, 1.0)})
	if ground_y < INF:
		FxDecal.spawn(from, Vector3(pos.x, ground_y, pos.z), &"frost", 0.8 * size)


## Water splash (water hits, landings in water, torrents).
static func splash(from: Node, pos: Vector3, size: float = 1.0, dir: Vector3 = Vector3.UP, ground_y: float = INF) -> void:
	FxBurst.spawn(from, &"droplets", pos, {"count": 0.7 + size * 0.6, "speed": 0.8 + size * 0.4, "dir": dir})
	FxBurst.spawn(from, &"spray", pos, {"count": 0.6 + size * 0.5, "size": 0.7 + size * 0.5, "dir": dir})
	if ground_y < INF:
		FxDecal.spawn(from, Vector3(pos.x, ground_y, pos.z), &"wet", 0.7 + size * 0.6)
		if size > 0.8:
			FxRing.spawn(from, Vector3(pos.x, ground_y, pos.z), 1.0 + size, Color(0.75, 0.9, 1.0), 0.45, {"opacity": 0.5, "fill": 0.2})
