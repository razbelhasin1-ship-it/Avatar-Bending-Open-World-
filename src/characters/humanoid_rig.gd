class_name HumanoidRig
extends Node3D
## Procedurally built, procedurally animated humanoid (player, NPCs, enemies,
## trainers). Faces -Z, feet at the origin. See docs/modules/characters.md.
##
##   var rig := HumanoidRig.create({"preset": &"fire_nation", "seed": 7})
##   body.add_child(rig)                 # rig.actor defaults to the parent
##   rig.set_locomotion(body.velocity, body.is_on_floor())   # every frame
##   rig.play_action(&"fire_jab_r")      # -> duration; action_event(&"release")

## Fired at a clip's timed event (e.g. &"release", &"impact", &"plant_r").
signal action_event(clip: StringName, event: StringName)
## Fired when an action clip ends naturally (not when stopped/replaced).
signal action_finished(clip: StringName)
## Fired after build() completes (mesh + skeleton ready).
signal built

const SK = preload("res://src/characters/rig/rig_skeleton_def.gd")
const SOCKETS: PackedStringArray = ["hand_l", "hand_r", "foot_l", "foot_r", "head", "chest", "pelvis", "back", "mouth"]

## Character config (see CharacterOutfits). Built on _ready() if not empty.
@export var config: Dictionary = {}
## Automatic LOD from camera distance and on-screen visibility.
@export var auto_lod := true
## Emit Events.footstep on every foot plant.
@export var emit_footsteps := true
## Emit Events.landed from land().
@export var emit_landed := false
## When true the rig does not update itself; call advance(delta) manually
## (deterministic playback for cutscenes, tests and screenshots).
@export var manual_update := false

## Node reported as the "actor" in Events.footstep / Events.landed. Defaults to
## the parent (the owner body) when it is a Node3D, else this rig.
var actor: Node3D = null
var spec: Dictionary = {}
var skeleton: Skeleton3D = null
var mesh_instance: MeshInstance3D = null
var animator: RigAnimator = null
var def: RigSkeletonDef = null
## Current LOD level (0 full .. 3 dormant).
var lod := 0

var _sockets: Dictionary = {}
var _vel := Vector3.ZERO
var _grounded := true
var _vel_frame := -100
var _last_pos := Vector3.ZERO
var _has_last_pos := false
var _frame := 0
var _on_screen := true
var _notifier: VisibleOnScreenNotifier3D = null
var _unique_mats: Array[ShaderMaterial] = []
var _flash_tween: Tween = null
var _exclude: Array[RID] = []
var _foot_len := 0.26


## Creates a rig and builds it immediately.
static func create(cfg: Dictionary) -> HumanoidRig:
	var r := HumanoidRig.new()
	r.config = cfg
	r.build(cfg)
	return r


func _ready() -> void:
	if skeleton == null and not config.is_empty():
		build(config)
	if actor == null:
		actor = get_parent() as Node3D if get_parent() is Node3D else self
	var co := actor as CollisionObject3D
	if co:
		_exclude = [co.get_rid()]


## (Re)builds the character from a config. Safe to call again to change looks.
func build(cfg: Dictionary) -> void:
	config = cfg
	if skeleton:
		skeleton.queue_free()
		skeleton = null
		_sockets.clear()
		_unique_mats.clear()
	spec = CharacterOutfits.resolve(cfg)
	var res := CharacterMeshBuilder.build(spec)
	def = res["def"]
	skeleton = def.create_skeleton()
	var sc: float = spec.get("scale", 1.0)
	skeleton.scale = Vector3.ONE * sc
	add_child(skeleton)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Body"
	mesh_instance.mesh = res["mesh"]
	skeleton.add_child(mesh_instance)
	# 4.7: the skeleton path defaults to empty, so bind explicitly.
	mesh_instance.skeleton = NodePath("..")
	mesh_instance.skin = skeleton.create_skin_from_rest_transforms()
	mesh_instance.visibility_range_end = 160.0
	mesh_instance.visibility_range_end_margin = 10.0
	mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	_foot_len = float(def.p["foot"]) * float(def.p["height"])
	animator = RigAnimator.new()
	animator.setup(self, def, res["springs"])
	animator.loco.planted.connect(_on_loco_planted)
	animator.ground_query = _ground_at
	animator.set_style(spec.get("style", RigStyles.DEFAULT))
	_make_sockets()
	if _notifier == null:
		_notifier = VisibleOnScreenNotifier3D.new()
		add_child(_notifier)
		_notifier.screen_entered.connect(func() -> void: _on_screen = true)
		_notifier.screen_exited.connect(func() -> void: _on_screen = false)
	_notifier.aabb = AABB(Vector3(-0.8, 0.0, -0.8), Vector3(1.6, float(spec.get("height", 1.8)) + 0.4, 1.6))
	_has_last_pos = false
	if is_inside_tree():
		_prime()
	built.emit()


func _enter_tree() -> void:
	if animator and not _has_last_pos:
		_prime.call_deferred()


func _prime() -> void:
	if not is_inside_tree() or skeleton == null:
		return
	animator.loco.reset(skeleton.global_transform)
	animator.update(0.0, skeleton.global_transform, Vector3.ZERO, true, true, false)
	animator.solver.apply(skeleton)


# --- Locomotion / style -------------------------------------------------------

## Feeds the owner's world velocity and ground state for this frame. If never
## called, velocity is derived from the rig's own movement.
func set_locomotion(world_velocity: Vector3, grounded: bool = true, _delta: float = 0.0) -> void:
	_vel = world_velocity
	_grounded = grounded
	_vel_frame = Engine.get_process_frames()


func set_style(style: StringName) -> void:
	if animator:
		animator.snapshot(0.3)
		animator.set_style(style)


func get_style() -> StringName:
	return animator.style_name if animator else &""


func set_combat_stance(on: bool) -> void:
	if animator:
		animator.combat = on


func is_combat_stance() -> bool:
	return animator != null and animator.combat


# --- Actions ------------------------------------------------------------------

## Plays a clip from AnimLibrary. opts: speed (1.0), blend_in, blend_out, mask
## (&"full", &"upper", &"arms", &"arm_l", &"arm_r", &"legs", &"head"), mirror
## (bool), root_motion (bool -> consume_root_motion()), start (normalized).
## Returns the duration in seconds (0 if the clip does not exist).
func play_action(clip: StringName, opts: Dictionary = {}) -> float:
	var c := AnimLibrary.get_clip(clip)
	if c == null or animator == null:
		push_warning("HumanoidRig: unknown clip '%s'" % clip)
		return 0.0
	return animator.play(c, opts)


func stop_action(blend: float = -1.0) -> void:
	if animator:
		animator.stop(blend)


func is_playing_action() -> bool:
	return animator != null and animator.action != null


func current_action() -> StringName:
	return animator.action.name if animator and animator.action else &""


## Normalized time (0..1) of the current action, -1 if none.
func action_progress() -> float:
	return animator.action_t if animator and animator.action else -1.0


## World-space displacement accumulated by root-motion clips since last call.
func consume_root_motion() -> Vector3:
	return animator.consume_root_motion() if animator else Vector3.ZERO


## Hit reaction. kind: HitInfo.Reaction value or &"flinch", &"stagger",
## &"knockback", &"knockdown", &"launch", &"pull", &"freeze", &"death".
## world_dir: direction the hit pushes this character. Returns the duration of
## the reaction clip (0 for additive flinches).
func play_reaction(kind: Variant, world_dir: Vector3 = Vector3.ZERO, strength: float = 1.0) -> float:
	return RigReactions.play(self, kind, world_dir, strength)


func set_pose_state(state: StringName, blend: float = 0.2) -> void:
	if animator:
		animator.set_pose_state(state, blend)


func get_pose_state() -> StringName:
	return animator.pose_state if animator else &"normal"


## Landing after a jump/fall: plays land_light / land_heavy (style aware) and,
## if emit_landed, emits Events.landed. Returns the clip duration.
func land(impact_speed: float) -> float:
	if animator == null:
		return 0.0
	if animator.pose_state in [&"airborne", &"falling"]:
		animator.set_pose_state(&"normal", 0.08)
	var heavy := absf(impact_speed) > 9.0
	if emit_landed:
		Events.landed.emit(_actor(), global_position, absf(impact_speed), WorldData.get_surface(global_position))
	if animator.pose_state == &"tumbling":
		animator.set_pose_state(&"normal", 0.05)
		return play_action(&"knockdown_land")
	return play_action(&"land_heavy" if heavy else &"land_light", {"speed": 1.0 if heavy else 1.15})


# --- Look-at / face -------------------------------------------------------------

func look_at_point(pos: Vector3, weight: float = 1.0) -> void:
	if animator:
		animator.look_target = pos
		animator.look_weight_target = clampf(weight, 0.0, 1.0)


func clear_look_at() -> void:
	if animator:
		animator.look_weight_target = 0.0


func set_talking(on: bool) -> void:
	if animator:
		animator.talking = on


# --- Sockets ----------------------------------------------------------------------

## Attachment point following an animated bone: hand_l, hand_r (palm center;
## -Z along the fingers, -Y out of the palm), foot_l, foot_r (sole center),
## head (skull center), chest (front of chest), pelvis, back (between the
## shoulder blades), mouth.
func get_socket(socket_name: StringName) -> Node3D:
	return _sockets.get(socket_name, null)


## World direction the palm of `side` (0 left, 1 right) faces.
func get_palm_direction(side: int) -> Vector3:
	var s := get_socket(&"hand_l" if side == 0 else &"hand_r")
	return -s.global_basis.y.normalized() if s else -global_basis.z


func _make_sockets() -> void:
	var h: float = def.p["height"]
	var hl: float = float(def.p["hand"]) * h
	for side in 2:
		var dir := def.arm_dir[side]
		var pn := def.palm_normal[side]
		var bas := Basis.looking_at(dir, -pn)
		_add_socket(&"hand_l" if side == 0 else &"hand_r", SK.HAND[side], Transform3D(bas, dir * hl * 0.42 + pn * hl * 0.06))
		var foot_off := Vector3(0, -def.rest_pos[SK.FOOT[side]].y, -_foot_len * 0.36)
		_add_socket(&"foot_l" if side == 0 else &"foot_r", SK.FOOT[side], Transform3D(Basis.IDENTITY, foot_off))
	_add_socket(&"head", SK.HEAD, Transform3D(Basis.IDENTITY, (def.p["skull_c"] as Vector3) - def.rest_pos[SK.HEAD]))
	_add_socket(&"chest", SK.UPPER_CHEST, Transform3D(Basis.IDENTITY, Vector3(0, -0.02 * h, -float(def.p["chest_d"]) * h)))
	_add_socket(&"pelvis", SK.HIPS, Transform3D.IDENTITY)
	_add_socket(&"back", SK.UPPER_CHEST, Transform3D(Basis.IDENTITY, Vector3(0, -0.01 * h, float(def.p["chest_d"]) * h * 1.2)))
	_add_socket(&"mouth", SK.MOUTH, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.01 * h)))


func _add_socket(socket_name: StringName, bone: int, offset: Transform3D) -> void:
	var ba := BoneAttachment3D.new()
	ba.name = "Bone_%s" % socket_name
	ba.bone_name = def.names[bone]
	skeleton.add_child(ba)
	var s := Node3D.new()
	s.name = String(socket_name)
	s.transform = offset
	ba.add_child(s)
	_sockets[socket_name] = s


# --- Materials / feedback -------------------------------------------------------

func _ensure_unique_materials() -> void:
	if not _unique_mats.is_empty() or mesh_instance == null:
		return
	var m := mesh_instance.mesh
	for i in m.get_surface_count():
		var src := m.surface_get_material(i) as ShaderMaterial
		if src == null:
			continue
		var u := src.duplicate() as ShaderMaterial
		u.next_pass = src.next_pass
		mesh_instance.set_surface_override_material(i, u)
		_unique_mats.append(u)


## White hit flash (tweened). Gives this rig its own material copies.
func flash_hit(color: Color = Color(1, 1, 1), duration: float = 0.18) -> void:
	_ensure_unique_materials()
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	for m in _unique_mats:
		m.set_shader_parameter(&"hit_flash", 1.0)
		if color != Color(1, 1, 1):
			m.set_shader_parameter(&"emission", color)
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash, 1.0, 0.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _set_flash(v: float) -> void:
	for m in _unique_mats:
		m.set_shader_parameter(&"hit_flash", v)
		if v <= 0.0:
			m.set_shader_parameter(&"emission", Color(0, 0, 0))


## Status overlay (soaked, frozen, burned...). amount 0 clears it.
func set_status_tint(color: Color, amount: float) -> void:
	if amount <= 0.0 and _unique_mats.is_empty():
		return
	_ensure_unique_materials()
	for m in _unique_mats:
		m.set_shader_parameter(&"status_color", color)
		m.set_shader_parameter(&"status_amount", clampf(amount, 0.0, 1.0))


# --- IK / LOD -------------------------------------------------------------------

func set_foot_ik(enabled: bool) -> void:
	if animator:
		animator.foot_ik = enabled


## Forces an LOD level (disables auto LOD): 0 full, 1 no secondary motion,
## 2 reduced update rate without IK, 3 dormant (logic only).
func set_lod(level: int) -> void:
	auto_lod = false
	_apply_lod(level)


func _apply_lod(level: int) -> void:
	lod = clampi(level, 0, 3)
	if animator:
		animator.secondary.enabled = lod == 0
		animator.ground_every = 1 if lod == 0 else 3


func _auto_lod() -> int:
	if not _on_screen:
		return 3
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return 0
	var d := cam.global_position.distance_to(global_position)
	var k: float = [0.6, 0.8, 1.0, 1.4][Settings.detail_level()]
	if d < 14.0 * k:
		return 0
	if d < 30.0 * k:
		return 1
	if d < 70.0 * k:
		return 2
	return 3


func _process(delta: float) -> void:
	if not manual_update:
		advance(delta)


## Advances animation by `delta` seconds (called automatically unless manual_update).
func advance(delta: float) -> void:
	if animator == null or skeleton == null:
		return
	_frame += 1
	if auto_lod and _frame % 10 == 0:
		_apply_lod(_auto_lod())
	var xf := skeleton.global_transform
	var vel := _vel
	var grounded := _grounded
	if Engine.get_process_frames() - _vel_frame > 2:
		var pos := global_position
		vel = (pos - _last_pos) / maxf(delta, 0.0001) if _has_last_pos else Vector3.ZERO
		grounded = true
	_last_pos = global_position
	_has_last_pos = true
	var do_solve := true
	match lod:
		1:
			do_solve = true
		2:
			do_solve = _frame % 3 == 0
		3:
			do_solve = _frame % 12 == 0 and _on_screen
	if lod < 2:
		animator.tick_face(delta)
	var solved := animator.update(delta, xf, vel, grounded, do_solve, lod <= 1)
	if solved:
		if lod == 0:
			animator.secondary.process(animator.solver, xf, delta)
		else:
			animator.secondary.process(animator.solver, xf, 0.0)
		animator.solver.apply(skeleton)


func _ground_at(p: Vector3) -> Array:
	if is_inside_tree():
		var space := get_world_3d().direct_space_state
		if space:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 0.7, Layers.SOLID, _exclude)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				return [(hit["position"] as Vector3).y, hit["normal"]]
	var wh := WorldData.get_height(p.x, p.z)
	if absf(wh - global_position.y) < 0.6:
		return [wh, WorldData.get_normal(p.x, p.z)]
	return [global_position.y, Vector3.UP]


func _actor() -> Node3D:
	if actor == null or not is_instance_valid(actor):
		actor = get_parent() as Node3D if get_parent() is Node3D else self
	return actor


func _on_loco_planted(_side: int, world_pos: Vector3, world_yaw: float, weight: float) -> void:
	if not emit_footsteps or not is_inside_tree():
		return
	var g := _ground_at(world_pos)
	var pos := Vector3(world_pos.x, float(g[0]), world_pos.z)
	Events.footstep.emit(_actor(), pos, world_yaw, _foot_len * float(spec.get("scale", 1.0)), weight, WorldData.get_surface(pos))


## Footstep from a clip "plants" entry (stomps, landings, steps inside moves).
func _on_clip_plant(side: int, weight: float) -> void:
	if not emit_footsteps or not is_inside_tree() or animator == null:
		return
	var xf := skeleton.global_transform
	var s := animator.solver
	var foot := SK.FOOT[side]
	var fwd := (s.g_basis[foot] * Vector3(0, 0, -1))
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3(0, 0, -1)
	var center_m := s.g_pos[foot] + fwd * _foot_len * 0.36
	var wp := xf * Vector3(center_m.x, 0.0, center_m.z)
	var g := _ground_at(wp)
	var world_fwd := xf.basis * fwd
	var yaw := atan2(-world_fwd.x, -world_fwd.z)
	Events.footstep.emit(_actor(), Vector3(wp.x, float(g[0]), wp.z), yaw, _foot_len * float(spec.get("scale", 1.0)), weight * float(animator.style.get("weight", 1.0)), WorldData.get_surface(wp))


func _on_action_event(clip: StringName, event: StringName) -> void:
	action_event.emit(clip, event)


func _on_action_finished(clip: StringName) -> void:
	action_finished.emit(clip)


# --- Queries --------------------------------------------------------------------

## Actual standing height in meters (including the seeded scale).
func get_height() -> float:
	return float(spec.get("height", 1.75))


func get_bone_index(bone_name: String) -> int:
	return def.find(bone_name) if def else -1


## World transform of a bone from the last solved pose.
func get_bone_world(bone_name: String) -> Transform3D:
	var i := get_bone_index(bone_name)
	if i < 0 or skeleton == null:
		return global_transform
	return skeleton.global_transform * animator.solver.bone_global(i)
