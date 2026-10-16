class_name EnemyTelegraph
extends RefCounted
## Readable attack telegraphs: a short star glint on the weapon / hand (element
## tinted), an optional ground ring for area attacks, a wind-up sound, and an
## "alert" glyph above enemies that just spotted the player.
##
##   EnemyTelegraph.glint(self, pos, ElementDefs.Element.FIRE, 1.0)
##   var ring := EnemyTelegraph.ring(self, ground_pos, 3.0, element, 0.7)
##   EnemyTelegraph.windup_sound(element, pos, heavy)

const COLORS := {
	ElementDefs.Element.NONE: Color(1.0, 0.93, 0.7),
	ElementDefs.Element.FIRE: Color(1.0, 0.55, 0.18),
	ElementDefs.Element.EARTH: Color(0.72, 0.9, 0.4),
	ElementDefs.Element.WATER: Color(0.55, 0.88, 1.0),
	ElementDefs.Element.AIR: Color(0.92, 0.96, 1.0),
}
## Ground ring colour for enemy area attacks (warm warning red, element inner).
const RING_COLOR := Color(1.0, 0.28, 0.14)

static var _star_tex: Texture2D = null
static var _materials: Dictionary = {}
## Glints shown (tests: every attack must telegraph).
static var glints_shown := 0


static func color_for(element: int) -> Color:
	return COLORS.get(element, COLORS[ElementDefs.Element.NONE])


## A star glint at `pos` (scale ~1 = 0.55 m across), fading over ~0.35 s. With
## `anchor` = [node, local offset] (EnemyVisual.socket_anchor) it rides the weapon.
static func glint(from: Node, pos: Vector3, element: int = ElementDefs.Element.NONE, strength: float = 1.0, anchor: Array = []) -> Node3D:
	glints_shown += 1
	var g := FxLib.take(from, &"enemy_glint", Glint.make) as Glint
	if g == null:
		return null
	g.follow = anchor[0] if anchor.size() == 2 else null
	g.offset = anchor[1] if anchor.size() == 2 else Vector3.ZERO
	g.global_position = pos
	g.start(color_for(element), strength)
	if FxLib.tier() >= 1:
		FxFlash.spawn(from, pos, color_for(element), 1.2 * strength, 0.22, 3.0)
	return g


## Ground warning ring (area attacks), shown for `duration` s.
static func ring(from: Node, pos: Vector3, radius: float, element: int, duration: float) -> FxRing:
	var inner := color_for(element)
	return FxRing.spawn(from, pos, radius, RING_COLOR, maxf(duration, 0.1), {"opacity": 0.75, "width": 0.14, "fill": 0.16, "inner": inner})


static func windup_sound(element: int, pos: Vector3, heavy: bool) -> void:
	match element:
		ElementDefs.Element.FIRE:
			Audio.play_bending(element, &"ignite", pos, -6.0 if not heavy else -2.0)
		ElementDefs.Element.WATER:
			Audio.play_bending(element, &"draw", pos, -8.0 if not heavy else -4.0)
		ElementDefs.Element.EARTH:
			Audio.play_bending(element, &"debris", pos, -8.0 if not heavy else -3.0)
		_:
			Audio.play_sfx(&"whoosh_heavy" if heavy else &"dodge_whoosh", pos, -9.0 if not heavy else -5.0)


static func star_texture() -> Texture2D:
	if _star_tex != null:
		return _star_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			# Four-point star: thin bright cross + soft core.
			var cross := maxf(exp(-absf(u) * 26.0) * (1.0 - absf(v)), exp(-absf(v) * 26.0) * (1.0 - absf(u)))
			var diag := maxf(exp(-absf(u - v) * 30.0), exp(-absf(u + v) * 30.0)) * maxf(0.0, 1.0 - r * 1.4) * 0.45
			var core := exp(-r * r * 22.0)
			var a := clampf(cross + diag + core, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_star_tex = ImageTexture.create_from_image(img)
	return _star_tex


static func star_material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.albedo_texture = star_texture()
	m.albedo_color = Color(c.r * 1.6, c.g * 1.6, c.b * 1.6, 1.0)
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	_materials[key] = m
	return m


## The pooled glint sprite.
class Glint extends Node3D:
	var mesh: MeshInstance3D
	var t := 0.0
	var duration := 0.36
	var size := 0.55
	var follow: Node3D = null
	var offset := Vector3.ZERO

	static func make() -> Glint:
		var g := Glint.new()
		g.name = "Glint"
		g.mesh = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		g.mesh.mesh = q
		g.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(g.mesh)
		return g

	func start(c: Color, strength: float) -> void:
		t = 0.0
		size = 0.55 * clampf(strength, 0.4, 2.0)
		mesh.material_override = EnemyTelegraph.star_material(c)
		visible = true
		_apply(0.0)

	func fx_reset() -> void:
		t = duration
		follow = null

	func _process(delta: float) -> void:
		t += delta
		if follow != null:
			if is_instance_valid(follow) and follow.is_inside_tree():
				global_position = follow.global_transform * offset
			else:
				follow = null
		_apply(t / duration)
		if t >= duration:
			FxLib.release(self)

	func _apply(u: float) -> void:
		# Pops in, twists a little, fades out.
		var grow := clampf(u * 4.0, 0.0, 1.0)
		var fade := 1.0 - clampf((u - 0.45) / 0.55, 0.0, 1.0)
		var s := size * (0.3 + 0.9 * grow) * (0.6 + 0.4 * fade)
		mesh.scale = Vector3(s, s, s)
		mesh.rotation = Vector3(0, 0, u * 0.9)
		mesh.transparency = 1.0 - fade


## "!" alert glyph above an enemy that just spotted the player (rises and fades).
class AlertMark extends Label3D:
	var t := 0.0
	var life := 1.3

	func _init() -> void:
		text = "!"
		font_size = 120
		pixel_size = 0.004
		outline_size = 18
		modulate = Color(1.0, 0.82, 0.25)
		outline_modulate = Color(0.12, 0.05, 0.03)
		billboard = BaseMaterial3D.BILLBOARD_ENABLED
		no_depth_test = true
		fixed_size = false

	func _process(delta: float) -> void:
		t += delta
		position.y += delta * 0.3
		var u := t / life
		modulate.a = 1.0 - clampf((u - 0.6) / 0.4, 0.0, 1.0)
		var s := 1.0 + 0.4 * maxf(0.0, 1.0 - t * 6.0)
		scale = Vector3(s, s, s)
		if t >= life:
			queue_free()
