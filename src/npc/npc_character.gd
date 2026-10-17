class_name NpcCharacter
extends CharacterBody3D
## A townsperson / named character: HumanoidRig body on Layers.NPC (the player cannot walk
## through it), steering movement (whisker rays against walls, separation from people and the
## player), a talk Interactable, floating barks, and for named NPCs a quest marker + name plate.
## Behaviour (routines, reactions) lives in NpcBrain; the NpcDirector spawns and budgets NPCs.
##
## Tiers: `full` (near the player: move_and_slide with gravity, footsteps, talk prompt) or
## light (farther: kinematic stepping with a throttled ground probe, no footsteps).

signal arrived(ok: bool)

const WALK := 1.25
const BRISK := 1.9
const RUN := 4.2
const TURN_RATE := 5.5
const STUCK_TIME := 1.6

var record: Dictionary = {}
var key: StringName = &""
var npc_id: StringName = &""
var role: StringName = &"resident"
var nation: StringName = &"earth"
var director: Node = null
var rig: HumanoidRig = null
var brain: NpcBrain = null
var talk: NpcTalk = null
var marker: NpcMarker = null
var full := true
## Spawn transform (anchor) and the door it goes home to.
var home := Transform3D.IDENTITY
var door := Vector3.ZERO

var _target := Vector3.INF
var _speed := WALK
var _face_yaw := 0.0
var _turning := false
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _probe_t := 0.0
var _ground_y := INF
var _ground_ok := false
var _facing_checked := false
var _avoid := Vector3.ZERO
var _avoid_t := 0.0
var _bark: Label3D = null
var _bark_t := 0.0
var _fade := -1.0
var _speaking := false
var _talk_t := 0.0
var _props: Array[StringName] = []


static func create(rec: Dictionary, p_director: Node = null) -> NpcCharacter:
	var n := NpcCharacter.new()
	n.record = rec
	n.director = p_director
	return n


func _ready() -> void:
	key = record.get("key", &"npc")
	npc_id = record.get("named", &"")
	role = record.get("role", &"resident")
	nation = record.get("nation", &"earth")
	name = "Npc_%s" % String(key).replace("/", "_").left(40)
	add_to_group(&"npc")
	collision_layer = Layers.NPC
	collision_mask = Layers.SOLID
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.6
	safe_margin = 0.02
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	add_child(cs)
	var pos: Vector3 = record.get("pos", global_position)
	var yaw := float(record.get("yaw", 0.0))
	home = Transform3D(Basis(Vector3.UP, yaw), pos)
	door = record.get("home", pos)
	global_transform = home
	_face_yaw = yaw
	_last_pos = pos
	var look: Dictionary = (record.get("look", {}) as Dictionary).duplicate()
	if look.is_empty():
		look = {"preset": &"villager_earth"}
	rig = HumanoidRig.create(look)
	rig.name = "Rig"
	add_child(rig)
	rig.emit_footsteps = full
	talk = NpcTalk.new()
	talk.npc = self
	talk.name = "Talk"
	add_child(talk)
	if npc_id != &"":
		NpcRegistry.register_live(npc_id, self)
		marker = NpcMarker.new()
		marker.npc = self
		marker.position = Vector3(0, rig.get_height() + 0.55, 0)
		add_child(marker)
	_snap_to_ground(true)
	ensure_open_facing()
	brain = NpcBrain.new(self)


func _exit_tree() -> void:
	if npc_id != &"":
		NpcRegistry.unregister_live(npc_id, self)


func display_name() -> String:
	if npc_id != &"":
		return NpcRegistry.display_name(npc_id)
	return NpcBarks.role_title(role, nation, String(record.get("goods", "")))


## Implements the HUD lock target name contract (never lockable, but tests read it).
func get_display_name() -> String:
	return display_name()


func element() -> int:
	return ElementDefs.from_id(nation)


func set_full(on: bool) -> void:
	if full == on:
		return
	full = on
	if rig:
		rig.emit_footsteps = on
	if not on:
		velocity = Vector3.ZERO


# --- movement ----------------------------------------------------------------------------------

func move_to(p: Vector3, speed: float = WALK) -> void:
	_target = p
	_speed = speed
	_stuck_t = 0.0


## Instantly moves the NPC (escort catch-up): drops any move target and snaps to the floor.
func warp(p: Vector3) -> void:
	_target = Vector3.INF
	velocity = Vector3.ZERO
	global_position = p + Vector3(0, 0.3, 0)
	_last_pos = global_position
	_stuck_t = 0.0
	_snap_to_ground(true)


func stop_moving() -> void:
	_target = Vector3.INF
	velocity.x = 0.0
	velocity.z = 0.0


func is_moving() -> bool:
	return _target.is_finite()


func face_yaw(yaw: float) -> void:
	_face_yaw = yaw
	_turning = true


func face_point(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		face_yaw(atan2(-d.x, -d.z))


func _physics_process(delta: float) -> void:
	if _fade >= 0.0:
		_tick_fade(delta)
		return
	_camera_fade()
	if brain:
		brain.tick(delta)
	var desired := Vector3.ZERO
	if _target.is_finite():
		var to := _target - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.35:
			_target = Vector3.INF
			arrived.emit(true)
		else:
			var dir := to / dist
			desired = NpcSteering.steer(self, dir, delta) * _speed * clampf(dist / 0.8, 0.35, 1.0)
			if desired.length_squared() > 0.01:
				_face_yaw = atan2(-desired.x, -desired.z)
				_turning = true
			_stuck_t += delta
			if _stuck_t > STUCK_TIME:
				_stuck_t = 0.0
				if global_position.distance_to(_last_pos) < 0.25 * _speed:
					_target = Vector3.INF
					arrived.emit(false)
				_last_pos = global_position
	if _turning:
		var dy := wrapf(_face_yaw - rotation.y, -PI, PI)
		var step := TURN_RATE * delta
		if absf(dy) <= step:
			rotation.y = _face_yaw
			_turning = false
		else:
			rotation.y += signf(dy) * step
	if full:
		velocity.x = desired.x
		velocity.z = desired.z
		_probe_t -= delta
		if _probe_t <= 0.0:
			_probe_t = 0.5
			_snap_to_ground(false)
		if is_on_floor():
			velocity.y = minf(velocity.y, 0.0)
		elif _ground_ok:
			velocity.y -= 18.0 * delta
		else:
			velocity.y = 0.0
		move_and_slide()
		if global_position.y < _ground_y - 3.0 and _ground_y != INF:
			global_position.y = _ground_y
			velocity.y = 0.0
	else:
		velocity = desired
		global_position += desired * delta
		_probe_t -= delta
		if _probe_t <= 0.0 and desired.length_squared() > 0.01:
			_probe_t = 0.3
			_snap_to_ground(false)
		if _ground_y != INF:
			global_position.y = lerpf(global_position.y, _ground_y, minf(1.0, delta * 10.0))
	if rig:
		rig.set_locomotion(Vector3(velocity.x, 0.0, velocity.z), true, delta)
	_tick_bark(delta)
	if _speaking:
		_talk_t -= delta
		if _talk_t <= 0.0:
			_talk_t = 0.5
			rig.set_talking(true)


## Finds the floor under the NPC (physics ray; WorldData as a last resort far away).
func _snap_to_ground(initial: bool) -> void:
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var p := global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.4, p + Vector3.DOWN * 2.6, Layers.SOLID)
	q.exclude = [get_rid()]
	var r := space.intersect_ray(q)
	if not r.is_empty():
		_ground_y = (r["position"] as Vector3).y
		_ground_ok = true
		if initial:
			global_position.y = _ground_y + 0.02
	else:
		_ground_ok = false
		if _ground_y == INF:
			_ground_y = p.y


## Safety net for named NPCs: one whose facing runs into a wall within 4 m while its back is
## open turns around for good (home and facing) instead of staring at the wall (door-front
## quest-giver anchors face their building; see docs/qa/integration_fixes.md). Interior anchors
## follow the -Z contract at the source now, so crowd NPCs indoors no longer need it. Runs once,
## as soon as there is ground collision under the NPC (the settlement's collision streams in later).
func ensure_open_facing() -> void:
	if _facing_checked or not is_inside_tree():
		return
	if npc_id == &"":
		_facing_checked = true
		return
	if not _ground_ok:
		return
	_facing_checked = true
	var f := home.basis * Vector3.FORWARD
	var ahead := _free_length(f, 6.0)
	if ahead >= 4.0:
		return
	var behind := _free_length(-f, 6.0)
	if behind >= ahead * 1.8 and behind >= 2.5:
		var yaw := wrapf(home.basis.get_euler().y + PI, -PI, PI)
		home = Transform3D(Basis(Vector3.UP, yaw), home.origin)
		rotation.y = yaw
		_face_yaw = yaw


func _free_length(dir: Vector3, max_d: float) -> float:
	var from := global_position + Vector3(0, 1.45, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_d, Layers.SOLID)
	q.exclude = [get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return max_d if r.is_empty() else from.distance_to(r["position"])


# --- presentation -------------------------------------------------------------------------------

func bark(text: String, seconds: float = 2.6) -> void:
	if text.is_empty() or not bool(Settings.get_value("gameplay", "subtitles", true)) or in_conversation():
		return
	if _bark == null:
		_bark = Label3D.new()
		_bark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bark.font = UiTheme.body_font()
		_bark.font_size = 36
		_bark.pixel_size = 0.0038
		_bark.outline_size = 12
		_bark.modulate = Color(1, 0.96, 0.86)
		_bark.outline_modulate = Color(0.08, 0.05, 0.04, 0.9)
		_bark.no_depth_test = false
		_bark.width = 520.0
		_bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# named NPCs: above their marker glyph (the name plate hides while they bark)
		_bark.position = Vector3(0, (rig.get_height() if rig else 1.75) + (1.15 if marker != null else 0.45), 0)
		_bark.visibility_range_end = 30.0
		add_child(_bark)
	_bark.text = text
	_bark.visible = true
	_bark.modulate.a = 1.0
	_bark_t = seconds
	if rig and not _speaking:
		rig.set_talking(true)
		get_tree().create_timer(minf(seconds, 1.6)).timeout.connect(func() -> void:
			if is_instance_valid(rig) and not _speaking:
				rig.set_talking(false))


func _tick_bark(delta: float) -> void:
	if _bark == null or _bark_t <= 0.0:
		return
	_bark_t -= delta
	_bark.modulate.a = clampf(_bark_t / 0.4, 0.0, 1.0)
	if _bark_t <= 0.0:
		_bark.visible = false


func is_barking() -> bool:
	return _bark_t > 0.0


## Mouth flaps while the dialogue shows this NPC's line.
func set_speaking(on: bool) -> void:
	_speaking = on
	if rig:
		rig.set_talking(on)


## Props held for an activity (`hammer`, `broom`, `basket`, `fishing_rod`, `lantern@hand_l`, `staff`).
func hold_props(list: Array) -> void:
	var want: Array[StringName] = []
	for p: Variant in list:
		want.append(StringName(str(p)))
	if want == _props or rig == null:
		return
	for old in _props:
		var parts := String(old).split("@")
		rig.detach_prop(StringName(parts[1]) if parts.size() > 1 else &"hand_r")
	_props.clear()
	for w in want:
		var parts2 := String(w).split("@")
		var prop := StringName(parts2[0])
		if RigProps.is_prop(prop):
			rig.attach_prop(prop, StringName(parts2[1]) if parts2.size() > 1 else (&"back" if prop == &"staff" else &"hand_r"))
			_props.append(w)


## Fades out and frees (went indoors / despawned by the director).
func vanish(t: float = 0.6) -> void:
	if _fade >= 0.0:
		return
	_fade = 0.0
	set_meta(&"fade_time", maxf(0.05, t))
	if talk:
		talk.enabled = false
	collision_layer = 0


func is_vanishing() -> bool:
	return _fade >= 0.0


## Turns see-through while the camera is inside / right behind the NPC (crowded streets, a master
## standing between the camera and the player), like the player's own camera fade.
func _camera_fade() -> void:
	if rig == null or rig.mesh_instance == null:
		return
	var k := 0.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var c := cam.global_position
		var dy := c.y - global_position.y
		if dy > -0.4 and dy < 2.3:
			k = clampf((1.9 - Vector2(c.x - global_position.x, c.z - global_position.z).length()) / 0.8, 0.0, 0.75)
	if absf(rig.mesh_instance.transparency - k) > 0.01:
		rig.mesh_instance.transparency = k


func _tick_fade(delta: float) -> void:
	_fade += delta
	var t := float(get_meta(&"fade_time", 0.6))
	var k := clampf(1.0 - _fade / t, 0.0, 1.0)
	if rig:
		rig.scale = Vector3.ONE * lerpf(0.97, 1.0, k)
		if rig.mesh_instance:
			rig.mesh_instance.transparency = 1.0 - k
	if _fade >= t:
		queue_free()


# --- reactions / conversation (forwarded to the brain) -----------------------------------------

func react_threat(from: Vector3, severity: float) -> void:
	if brain:
		brain.react_threat(from, severity)


func react_bending(from: Vector3, element_id: int) -> void:
	if brain:
		brain.react_bending(from, element_id)


func begin_conversation(with: Node3D) -> void:
	_bark_t = 0.0
	if _bark:
		_bark.visible = false
	if brain:
		brain.begin_conversation(with)


func end_conversation() -> void:
	if brain:
		brain.end_conversation()


func in_conversation() -> bool:
	return brain != null and brain.override == &"converse"


class NpcTalk extends Interactable:
	## The talk prompt of an NPC ("Talk to Master Siku", "Browse the fishmonger's stall").
	var npc: NpcCharacter = null

	func _ready() -> void:
		radius = 2.4
		interact_priority = 1
		animation = &""
		lock_time = 0.2
		focus_offset = Vector3(0, 1.2, 0)
		super._ready()

	func get_interaction_text(_player: Node3D) -> String:
		if npc == null:
			return "Talk"
		if npc.npc_id != &"":
			return "Talk to %s" % npc.display_name()
		if npc.role == &"merchant":
			return "Trade with the %s" % npc.display_name().to_lower()
		return "Talk to the %s" % npc.display_name().to_lower()

	func can_interact(p: Node3D) -> bool:
		if npc == null or not super.can_interact(p) or npc.is_vanishing():
			return false
		return npc.brain != null and npc.brain.can_talk()

	func interact(p: Node3D) -> void:
		super.interact(p)
		if npc.director != null and npc.director.has_method("talk_to"):
			npc.director.call("talk_to", npc)
