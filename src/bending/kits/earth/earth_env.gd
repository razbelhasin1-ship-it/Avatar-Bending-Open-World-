class_name EarthEnv
extends RefCounted
## Earth <-> world: where earth can be bent and what it is made of, seismic
## camera shake, the marks earthbending leaves, raised pillars, and the
## practice / feedback bookkeeping shared by the Earth abilities
## (docs/modules/bending_earth.md "Environment").
##
##   var m := EarthEnv.material_at(ctx, point)   # {ok, kind, power, weak, reason, ground, normal, label}
##   if not m["ok"]: return EarthEnv.refuse(ctx, def.id, m)   # &"no_earth" + toast + puff
##   EarthEnv.shake(ctx, center, 0.4, 0.3)       # seismic shake (falls off for other casters)
##   EarthEnv.crater(ctx, ground, 1.4, m["kind"]) # persistent cracked crater (+ rim chunks)
##
## Kinds (EarthPalette ids): stone (x1.1), dirt, grass, ash (x1.05), and the weak
## ones sand (x0.75), snow (x0.85: the earth under the snow), mud (x0.7, shallow
## water). Nothing to bend on ice, wood or deep water.

## Earth material per ground kind: power scales damage and size.
const KINDS := {
	&"stone": {"power": 1.1, "weak": false, "label": "stone"},
	&"dirt": {"power": 1.0, "weak": false, "label": "earth"},
	&"grass": {"power": 1.0, "weak": false, "label": "earth"},
	&"ash": {"power": 1.05, "weak": false, "label": "volcanic rock"},
	&"sand": {"power": 0.75, "weak": true, "label": "Loose sand: weaker earthbending"},
	&"snow": {"power": 0.85, "weak": true, "label": "Frozen ground under the snow: weaker earthbending"},
	&"mud": {"power": 0.7, "weak": true, "label": "Mud: weaker earthbending"},
}
## Why there is nothing to bend (toast text).
const NONE := {
	&"ice": "No earth to bend - only ice here",
	&"wood": "No earth to bend on wood",
	&"deep_water": "No earth to bend in deep water",
}
## Water deeper than this over the ground: nothing to bend; shallower: mud.
const DEEP_WATER := 0.7
const SHALLOW_WATER := 0.06
## A floor this far above the terrain is a structure (stone, or a wooden deck over water).
const STRUCTURE_HEIGHT := 0.8
## Screen-safe cap for any seismic shake (trauma 0..1; the camera squares it and
## applies Settings.camera_shake_scale()).
const MAX_SHAKE := 0.62

static var _toast_t: Dictionary = {}


# --- ground ---------------------------------------------------------------------------------------

## The floor under `p` (terrain, buildings and earth/ice constructs; the caster is
## excluded): {point, normal, collider}. Falls back to WorldData.
static func ground(ctx: BendingContext, p: Vector3, up: float = 2.0, down: float = 6.0) -> Dictionary:
	if ctx != null and ctx.is_valid():
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * up, p + Vector3.DOWN * down, Layers.WORLD | Layers.CONSTRUCT)
		q.exclude = ctx.exclude()
		var r := ctx.space().intersect_ray(q)
		if not r.is_empty():
			return {"point": r["position"], "normal": r["normal"], "collider": r["collider"]}
	return {"point": Vector3(p.x, WorldData.get_height(p.x, p.z), p.z), "normal": WorldData.get_normal(p.x, p.z), "collider": null}


static func ground_y(ctx: BendingContext, p: Vector3) -> float:
	return ((ground(ctx, p)["point"]) as Vector3).y


## Callable(Vector3) -> float for FX that place pieces on the ground.
static func ground_fn(ctx: BendingContext) -> Callable:
	return func(p: Vector3) -> float: return EarthEnv.ground_y(ctx, p)


## What the ground at `p` is made of and whether it can be bent:
## {"ok", "kind" (palette id / &"ice" &"wood" &"deep_water"), "power", "weak",
##  "reason" (&"" or the kind), "label", "ground", "normal", "collider"}.
static func material_at(ctx: BendingContext, p: Vector3) -> Dictionary:
	var g := ground(ctx, p)
	var gp: Vector3 = g["point"]
	var kind := classify(gp, g["collider"])
	return _info(kind, g)


## Ground kind at a ground point (`collider` = what the floor ray hit, or null).
static func classify(gp: Vector3, collider: Variant = null) -> StringName:
	if collider is Object and is_instance_valid(collider):
		var col := collider as Object
		if col.has_meta(&"surface"):
			return _normalize(StringName(col.get_meta(&"surface")))
		if col is BendingConstruct:
			return &"ice" if (col as BendingConstruct).kind == &"ice" else &"stone"
		if col is CollisionObject3D and ((col as CollisionObject3D).collision_layer & Layers.CONSTRUCT) != 0:
			# Other constructs (ice floes ...): ice unless they say otherwise.
			var sc: Script = col.get_script()
			var gname := String(sc.get_global_name()) if sc != null else ""
			return &"stone" if gname.containsn("earth") or gname.containsn("stone") else &"ice"
	var wh := GroundSampler.water_height(gp)
	if wh > -INF:
		var depth := wh - gp.y
		if depth > DEEP_WATER:
			return &"deep_water"
		if depth > SHALLOW_WATER:
			return &"mud"
	var s := _normalize(GroundSampler.surface(gp + Vector3.UP * 0.05))
	# A floor well above the terrain: a structure (stone; a deck or a boat over water).
	if collider != null and WorldData.has_world_data() and GroundSampler.has_zones() == false:
		var terrain := WorldData.get_height(gp.x, gp.z)
		if gp.y - terrain > STRUCTURE_HEIGHT:
			var under_water := WorldData.get_water_height(gp.x, gp.z)
			return &"wood" if under_water > terrain else &"stone"
	return s


static func _normalize(s: StringName) -> StringName:
	match s:
		&"water", &"shallow_water":
			return &"mud"
		&"rock", &"gravel", &"road", &"cobble":
			return &"stone"
		&"", &"earth", &"soil", &"farmland":
			return &"dirt"
	return s


static func _info(kind: StringName, g: Dictionary) -> Dictionary:
	if NONE.has(kind):
		return {"ok": false, "kind": kind, "power": 0.0, "weak": true, "reason": kind, "label": NONE[kind],
				"ground": g["point"], "normal": g["normal"], "collider": g["collider"]}
	var k: Dictionary = KINDS.get(kind, KINDS[&"dirt"])
	var pk := kind if KINDS.has(kind) else &"dirt"
	return {"ok": true, "kind": pk, "power": float(k["power"]), "weak": bool(k["weak"]), "reason": &"", "label": String(k["label"]),
			"ground": g["point"], "normal": g["normal"], "collider": g["collider"]}


## Under the caster's feet.
static func feet(ctx: BendingContext) -> Dictionary:
	return material_at(ctx, ctx.origin() + Vector3.UP * 0.3)


## Standing on something: floor contact, or a floor just below the feet (rig-less
## casters never run move_and_slide, so is_on_floor() alone is not enough).
static func grounded(ctx: BendingContext) -> bool:
	if ctx.body == null or ctx.body.is_on_floor():
		return true
	var o := ctx.origin()
	return o.y - ground_y(ctx, o + Vector3.UP * 0.5) < 0.45 and ctx.body.velocity.y < 1.0


## Nothing to bend: HUD failure (the controller's ability_failed), a toast for the
## player (throttled) and a puff of what is actually there. Returns &"no_earth".
static func refuse(ctx: BendingContext, _ability_id: StringName, info: Dictionary) -> StringName:
	var kind: StringName = info.get("kind", &"ice")
	var p: Vector3 = info.get("ground", ctx.origin())
	if ctx.is_player():
		_toast(String(info.get("label", "No earth to bend")), &"warning")
	if ctx.is_valid():
		match kind:
			&"ice":
				FxBurst.spawn(ctx.caster, &"snow", p, {"count": 0.5, "size": 0.6})
			&"deep_water":
				FxBurst.spawn(ctx.caster, &"spray", p, {"count": 0.6})
			_:
				FxBurst.spawn(ctx.caster, &"dust", p, {"color": FxLib.surface_color(&"wood"), "count": 0.35, "size": 0.5})
	return &"no_earth"


## Weak ground: a one-line hint for the player (throttled per kind).
static func note_weak(ctx: BendingContext, info: Dictionary) -> void:
	if ctx.is_player() and bool(info.get("weak", false)) and bool(info.get("ok", false)):
		_toast(String(info.get("label", "")), &"info", 8.0)


static func _toast(text: String, kind: StringName, every: float = 2.5) -> void:
	if text == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_toast_t.get(text, -999.0)) < every:
		return
	_toast_t[text] = now
	Events.notify.emit(text, kind)


# --- seismic feel ---------------------------------------------------------------------------------

## Camera shake for a seismic event at `center`: full strength for the player's
## own moves, falling off with the player's distance for anyone else's (an enemy
## chief's quake shakes your screen too). Screen-safe (capped).
static func shake(ctx: BendingContext, center: Vector3, strength: float, duration: float, radius: float = 14.0) -> void:
	var s := strength
	if ctx == null or not ctx.is_player():
		var tree := Engine.get_main_loop() as SceneTree
		var pl := tree.get_first_node_in_group(&"player") as Node3D if tree else null
		if pl == null:
			return
		s *= clampf(1.0 - pl.global_position.distance_to(center) / radius, 0.0, 1.0)
	if s > 0.02:
		BendingFeedback.shake(minf(s, MAX_SHAKE), duration)


## Player practice of a technique (skill-tree unlock rules); enemy casts never count.
static func practiced(ctx: BendingContext, id: StringName) -> void:
	if ctx != null and ctx.is_player():
		GameState.add_practice(id)


## Damage / size multiplier of the ground (1.0 when unknown).
static func power(info: Dictionary) -> float:
	return float(info.get("power", 1.0)) if bool(info.get("ok", true)) else 0.0


## Hit dictionary scaled by the ground's power (damage, poise, lift a little).
static func scaled_hit(h: Dictionary, info: Dictionary) -> Dictionary:
	var k := clampf(power(info), 0.5, 1.2)
	var out := h.duplicate()
	out["damage"] = float(h.get("damage", 10.0)) * k
	out["poise"] = float(h.get("poise", 10.0)) * k
	if h.has("lift"):
		out["lift"] = float(h["lift"]) * lerpf(1.0, k, 0.5)
	return out


# --- marks ----------------------------------------------------------------------------------------

## A persistent cracked crater (+ chunks around its rim when big enough).
static func crater(ctx: BendingContext, at: Vector3, radius: float, kind: StringName, normal: Vector3 = Vector3.UP, rim: bool = true) -> void:
	if ctx == null or not ctx.is_valid():
		return
	EarthMarks.crater(ctx.caster, at, radius, kind, normal)
	if rim and radius >= 1.0:
		var n := clampi(int(radius * 4.0 * clampf(FxLib.scale(), 0.5, 1.2)), 4, 12)
		EarthRubble.spawn(ctx.caster, EarthRubble.ring_xforms(at, radius * 0.55, n, ground_fn(ctx), 0.18 + radius * 0.07), kind, &"chunk")


## A persistent fissure between two ground points (+ broken slabs along it).
static func fissure(ctx: BendingContext, a: Vector3, b: Vector3, width: float, kind: StringName, slabs: int = 0) -> void:
	if ctx == null or not ctx.is_valid():
		return
	EarthMarks.fissure(ctx.caster, a, b, width, kind)
	if slabs > 0:
		var n := clampi(int(round(slabs * clampf(FxLib.scale(), 0.5, 1.2))), 2, 16)
		EarthRubble.spawn(ctx.caster, EarthRubble.line_xforms(a, b, n, ground_fn(ctx), 0.32 + width * 0.12, width * 0.45), kind, &"chunk")


# --- rocks and pillars ----------------------------------------------------------------------------

## A pooled rock node (EarthFx.rock) in the colours of `kind`.
static func rock(from: Node, radius: float, kind: StringName) -> MeshInstance3D:
	var m := EarthFx.rock(from, radius)
	m.mesh = EarthMeshes.rock(randi() % 6, 1 if radius > 0.3 else 0, kind)
	m.material_override = EarthMeshes.material()
	return m


## Re-dresses a BendingConstruct with surface-coloured geometry (walls, slabs, pillars).
static func dress(c: BendingConstruct, mesh: Mesh) -> void:
	if c == null or c.mesh_i == null:
		return
	c.mesh_i.mesh = mesh
	var mat := c.mesh_i.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(&"albedo", Color(1, 1, 1))


## Raises a stone column (BendingConstruct, Layers.CONSTRUCT: cover, platform,
## blocks projectiles and line of sight) at a ground point. opts: radius, height,
## hp, lifetime, rise_time, kind.
static func raise_pillar(ctx: BendingContext, ground_pos: Vector3, facing: Vector3, opts: Dictionary = {}) -> BendingConstruct:
	var radius := float(opts.get("radius", 0.75))
	var height := float(opts.get("height", 2.8))
	var kind: StringName = opts.get("kind", &"dirt")
	var c := BendingConstruct.raise(ctx, ground_pos, facing, {"kind": &"earth", "size": Vector3(radius * 1.75, height, radius * 1.75),
			"hp": float(opts.get("hp", 120.0)), "lifetime": float(opts.get("lifetime", 9.0)), "rise_time": float(opts.get("rise_time", 0.16))})
	dress(c, EarthMeshes.pillar(radius, height, randi() % 4, kind))
	c.mesh_i.position = Vector3.ZERO
	c.set_meta(&"earth_pillar", true)
	c.set_meta(&"surface", &"stone")
	return c
