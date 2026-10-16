class_name FxLib
extends RefCounted
## Shared VFX infrastructure: the per-scene effects root, pooling, budgets
## (Settings.effects_scale()), generated noise textures and statistics.
##
##   var root := FxLib.root(self)                 # Node3D under the current scene
##   var n := FxLib.take(&"dust_burst", _make)    # pooled instance (or a new one)
##   FxLib.release(n)                             # back to the pool (hidden)
##   FxLib.scale()                                # 0.35 (mobile/low) .. 1.4 (ultra)
##
## Every effect in src/fx is short-lived, pooled and capped: there is never an
## unbounded number of particles, lights or meshes alive.

const ROOT_NAME := "FxRoot"
## Max simultaneously alive instances per pool kind (before effects_scale).
const DEFAULT_CAP := 24
## Max short-lived dynamic lights (scaled down on mobile/low).
const MAX_LIGHTS := 4

static var _pools: Dictionary = {}       # kind -> Array[Node3D] (free)
static var _alive: Dictionary = {}       # kind -> Array[Node3D] (in use, oldest first)
static var _caps: Dictionary = {}
static var _root_ref: WeakRef = null
static var _noise: Dictionary = {}
static var _scale_cache := -1.0
static var _scale_frame := -1
## Counters for tests / debugging: kind -> spawned count.
static var stats: Dictionary = {}


## Node3D all effects are parented to (child of the current scene).
static func root(from: Node) -> Node3D:
	if _root_ref != null:
		var r := _root_ref.get_ref() as Node3D
		if r != null and is_instance_valid(r) and r.is_inside_tree():
			return r
	var tree := from.get_tree() if from and from.is_inside_tree() else Engine.get_main_loop() as SceneTree
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	var existing := parent.get_node_or_null(ROOT_NAME) as Node3D
	if existing == null:
		existing = Node3D.new()
		existing.name = ROOT_NAME
		parent.add_child(existing)
		_pools.clear()
		_alive.clear()
	_root_ref = weakref(existing)
	return existing


## Current effects multiplier (cached per frame).
static func scale() -> float:
	var f := Engine.get_process_frames()
	if f != _scale_frame:
		_scale_frame = f
		_scale_cache = Settings.effects_scale()
	return _scale_cache


## Particle amount scaled by the effects setting (min 1).
static func amount(base: int) -> int:
	return maxi(1, int(round(float(base) * scale())))


## Detail tier: 0 low/mobile .. 3 ultra (Settings "effects").
static func tier() -> int:
	return clampi(int(Settings.get_value("graphics", "effects", 2)), 0, 3)


static func set_cap(kind: StringName, cap: int) -> void:
	_caps[kind] = cap


static func cap_of(kind: StringName) -> int:
	return maxi(2, int(round(float(_caps.get(kind, DEFAULT_CAP)) * clampf(scale(), 0.5, 1.4))))


## Takes a pooled instance of `kind` (creating it with `factory` if needed),
## parents it under the effects root and makes it visible. When the kind is
## at its cap, the oldest live instance is recycled.
static func take(from: Node, kind: StringName, factory: Callable) -> Node3D:
	var r := root(from)
	var free_list: Array = _pools.get(kind, [])
	var alive: Array = _alive.get(kind, [])
	_prune(alive)
	var n: Node3D = null
	while not free_list.is_empty() and n == null:
		var c: Variant = free_list.pop_back()
		if c != null and is_instance_valid(c):
			n = c
	if n == null and alive.size() >= cap_of(kind):
		n = alive.pop_front()
		if n.has_method("fx_reset"):
			n.call("fx_reset")
	if n == null:
		n = factory.call()
		n.set_meta(&"fx_kind", kind)
	if n.get_parent() != r:
		if n.get_parent():
			n.get_parent().remove_child(n)
		r.add_child(n)
	n.visible = true
	n.process_mode = Node.PROCESS_MODE_INHERIT
	alive.append(n)
	_pools[kind] = free_list
	_alive[kind] = alive
	stats[kind] = int(stats.get(kind, 0)) + 1
	return n


## Returns an instance to its pool (hidden, processing off).
static func release(n: Node3D) -> void:
	if n == null or not is_instance_valid(n):
		return
	var kind: StringName = n.get_meta(&"fx_kind", &"")
	n.visible = false
	n.process_mode = Node.PROCESS_MODE_DISABLED
	var alive: Array = _alive.get(kind, [])
	alive.erase(n)
	var free_list: Array = _pools.get(kind, [])
	if not free_list.has(n):
		free_list.append(n)
	_pools[kind] = free_list


static func _prune(list: Array) -> void:
	for i in range(list.size() - 1, -1, -1):
		if list[i] == null or not is_instance_valid(list[i]):
			list.remove_at(i)


static func alive_count(kind: StringName) -> int:
	var a: Array = _alive.get(kind, [])
	_prune(a)
	return a.size()


static func total_alive() -> int:
	var n := 0
	for k: StringName in _alive:
		n += alive_count(k)
	return n


static func reset_stats() -> void:
	stats.clear()


static func count(kind: StringName) -> int:
	return int(stats.get(kind, 0))


## Registers a spawn in the stats without pooling (tests read these).
static func note(kind: StringName) -> void:
	stats[kind] = int(stats.get(kind, 0)) + 1


# --- textures ------------------------------------------------------------------------------

## Seamless grayscale noise texture (cached). kind: &"cells" (cellular), &"smooth", &"streaks".
static func noise_texture(kind: StringName = &"smooth", size: int = 128) -> Texture2D:
	var key := "%s_%d" % [kind, size]
	if _noise.has(key):
		return _noise[key]
	var fn := FastNoiseLite.new()
	fn.seed = 1337
	match kind:
		&"cells":
			fn.noise_type = FastNoiseLite.TYPE_CELLULAR
			fn.frequency = 0.06
			fn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		&"streaks":
			fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			fn.frequency = 0.02
			fn.fractal_octaves = 3
		_:
			fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			fn.frequency = 0.035
			fn.fractal_octaves = 4
	var w := size
	var h := size
	if kind == &"streaks":
		h = size / 4
	var img := fn.get_seamless_image(w, h, false, false, 0.15, true)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_noise[key] = tex
	return tex


## Soft round sprite (radial gradient), cached.
static func soft_dot() -> Texture2D:
	if _noise.has("soft_dot"):
		return _noise["soft_dot"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_noise["soft_dot"] = t
	return t


## Element palette used by effects (core, mid, edge).
static func palette(element: int) -> Array[Color]:
	match element:
		ElementDefs.Element.AIR:
			return [Color(0.97, 0.99, 1.0), Color(0.82, 0.92, 0.98), Color(0.6, 0.76, 0.88)]
		ElementDefs.Element.EARTH:
			return [Color(0.62, 0.52, 0.40), Color(0.48, 0.40, 0.31), Color(0.33, 0.28, 0.22)]
		ElementDefs.Element.FIRE:
			return [Color(1.0, 0.95, 0.62), Color(1.0, 0.55, 0.12), Color(0.86, 0.16, 0.05)]
		ElementDefs.Element.WATER:
			return [Color(0.86, 0.97, 1.0), Color(0.32, 0.66, 0.92), Color(0.12, 0.36, 0.72)]
	return [Color(1, 1, 1), Color(0.8, 0.8, 0.8), Color(0.5, 0.5, 0.5)]


## Dust / debris colour for a ground surface.
static func surface_color(surface: StringName) -> Color:
	match surface:
		&"snow": return Color(0.93, 0.96, 1.0)
		&"ice": return Color(0.82, 0.92, 0.98)
		&"sand": return Color(0.86, 0.76, 0.56)
		&"ash": return Color(0.32, 0.29, 0.28)
		&"stone": return Color(0.66, 0.63, 0.58)
		&"dirt": return Color(0.58, 0.46, 0.33)
		&"water": return Color(0.75, 0.88, 0.96)
		&"wood": return Color(0.55, 0.42, 0.3)
	return Color(0.62, 0.56, 0.42)
