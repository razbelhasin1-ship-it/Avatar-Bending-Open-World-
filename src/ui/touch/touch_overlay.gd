class_name TouchOverlay
extends Control
## On-screen touch controls (docs/modules/mobile.md). The HUD creates one as the top child
## of its root; it shows itself while Settings.touch_controls_enabled() (and no controller
## is in use), drives the SAME InputMap actions as keyboard / pad (TouchActions) and camera
## look through Events.look_input, so gameplay never knows touch exists.
##
## * Multi-touch: every finger (touch index) is owned by exactly one widget - the floating
##   stick (left zone), the look pad (anywhere free) or a button - until it lifts. The GUI
##   routes each index to this Control (Viewport touch focus), so menus / dialogue layers
##   above it receive their own taps first.
## * Buttons: Strike, Heavy (hold to charge), Jump, Dodge, Defend (hold), 4 technique slots +
##   Signature (the HUD's own HudAbilitySlot: icons, cooldown sweeps, chi / focus state),
##   top bar (pause, lock-on, call companion, map / journal when such screens exist), the
##   contextual Interact button (Events.interaction_prompt) and, while riding, Ascend /
##   Descend / Dismount.
## * Lock-on: tap = lock, tap again = next target (release when there is no other), hold
##   0.45 s = release; while locked a quick swipe on the look pad switches target
##   (PlayerTargeting flick through Events.look_input).
## * Settings: touch.button_scale, opacity, left_handed, auto_sprint, haptics,
##   camera_sensitivity (applied by the camera).
## * No stuck input: everything is released on pause, dialogue, focus loss, hide, exit.

signal layout_changed

## Hold time (s) on the lock button that releases the lock instead of cycling.
const LOCK_HOLD_RELEASE := 0.45
## Index used for a real mouse when touch controls are forced on at a desktop.
const MOUSE_INDEX := 99
const ICON_DIR := "res://src/ui/touch/icons/"
## Combat buttons and their actions.
const COMBAT := {
	&"strike": &"attack_light", &"heavy": &"attack_heavy", &"jump": &"jump", &"dodge": &"dodge",
	&"defend": &"block", &"tech_0": &"ability_1", &"tech_1": &"ability_2", &"tech_2": &"ability_3",
	&"tech_3": &"ability_4", &"signature": &"ability_special",
}
const ICONS := {
	&"heavy": "touch_heavy", &"jump": "touch_jump", &"dodge": "touch_dodge", &"defend": "touch_defend",
	&"pause": "touch_pause", &"lock": "touch_lock", &"call": "touch_call", &"map": "touch_map",
	&"journal": "touch_journal", &"interact": "touch_interact", &"descend": "touch_descend",
}
## Groups a map / journal screen joins so the top bar offers its button (no fake buttons).
const MAP_GROUP := &"map_screen"
const JOURNAL_GROUP := &"journal_screen"

## Show even when Settings say touch is off (tests, previews).
var force_active := false
## The HUD that owns us (optional: the overlay also works standalone with `player`).
var hud: Node = null
## Player (duck-typed: PlayerCharacter or HudMockPlayer). Defaults to hud.player.
var player: Node = null
var actions := TouchActions.new()
var haptics := TouchHaptics.new()
var stick: TouchStick
var buttons: Dictionary = {}
var layout: Dictionary = {}
## "normal", "mounted", "dead", "cinematic" (what the buttons show).
var mode: StringName = &"normal"
## Contextual prompt text (Events.interaction_prompt, key prefix stripped).
var prompt_text := ""
var active := false

## touch index -> {"kind": &"stick" | &"look" | &"button" | &"none", "id": StringName, "t": float}
var _owners: Dictionary = {}
var _look_index := -1
var _dialogue := false
var _lock_handled := false
var _top_ids: Array = []
var _left_handed := false
var _scale := 1.0
var _opacity := 0.7
var _element := -1
var _last_size := Vector2.ZERO
var _prompt_visible := false
var _safe_t := 0.0
var _last_safe := Vector4(-1, -1, -1, -1)


func _ready() -> void:
	name = "TouchOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	stick = TouchStick.new()
	add_child(stick)
	for id: StringName in COMBAT:
		var b := TouchButton.new(id, COMBAT[id], 56.0, ICON_DIR + ICONS[id] + ".svg" if ICONS.has(id) else "")
		add_child(b)
		buttons[id] = b
		if String(id).begins_with("tech_"):
			b.make_ability_slot(int(String(id).substr(5)))
		elif id == &"signature":
			b.make_ability_slot(4)
	for id: StringName in [&"pause", &"lock", &"call", &"map", &"journal", &"interact", &"descend"]:
		var b := TouchButton.new(id, _action_for(id), 46.0, ICON_DIR + ICONS[id] + ".svg")
		b.flat = id in [&"pause", &"lock", &"call", &"map", &"journal"]
		add_child(b)
		buttons[id] = b
	Events.interaction_prompt.connect(_on_prompt)
	Events.dialogue_started.connect(func(_n: Node) -> void: _dialogue = true)
	Events.dialogue_ended.connect(func(_n: Node) -> void: _dialogue = false)
	Events.pause_changed.connect(func(_p: bool) -> void: release_all())
	Events.touch_controls_changed.connect(func(_on: bool) -> void: _apply_settings())
	Events.settings_applied.connect(_apply_settings)
	Events.ability_failed.connect(_on_ability_failed)
	Events.ability_used.connect(_on_ability_used)
	Events.hit_landed.connect(_on_hit_landed)
	Events.player_damaged.connect(_on_player_damaged)
	Events.mounted.connect(func(_m: Node3D) -> void: release_all())
	Events.dismounted.connect(func(_m: Node3D) -> void: release_all())
	resized.connect(_relayout)
	_apply_settings()
	_set_active(false)


func _exit_tree() -> void:
	release_all()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, \
				NOTIFICATION_APPLICATION_PAUSED:
			release_all()
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree():
				release_all()


# --- Settings / layout ------------------------------------------------------------------------

func _apply_settings() -> void:
	_scale = Settings.touch_button_scale()
	_opacity = Settings.touch_opacity()
	_left_handed = bool(Settings.get_value("touch", "left_handed", false))
	stick.auto_sprint = bool(Settings.get_value("touch", "auto_sprint", true))
	haptics.enabled = bool(Settings.get_value("touch", "haptics", true))
	stick.opacity = _opacity
	for b: TouchButton in buttons.values():
		b.opacity = _opacity
	_relayout()


## Whether the overlay should be on screen at all (setting / forced, no pad in use).
func wants_active() -> bool:
	if not (force_active or Settings.touch_controls_enabled()):
		return false
	return force_active or UiInput.device != &"pad"


func _set_active(on: bool) -> void:
	if on == active and visible == on:
		return
	active = on
	visible = on
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if not on:
		release_all()
	if hud and hud.has_method("apply_touch_layout"):
		hud.call("apply_touch_layout", on, _left_handed)


func _relayout() -> void:
	if stick == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x < 10.0 or rect.size.y < 10.0:
		return
	_last_size = size
	layout = TouchLayout.compute(rect, _scale, _left_handed, _top_ids)
	var bl: Dictionary = layout["buttons"]
	for id: StringName in buttons:
		var b: TouchButton = buttons[id]
		if bl.has(id):
			var spec: Dictionary = bl[id]
			b.set_radius(float(spec["radius"]))
			b.set_center(spec["center"])
	stick.radius = float(layout["stick_radius"])
	stick.rest_center = layout["stick_rest"]
	stick.queue_redraw()
	if hud and hud.has_method("apply_touch_layout") and active:
		hud.call("apply_touch_layout", true, _left_handed)
	queue_redraw()
	layout_changed.emit()


# --- Per-frame state ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = hud.get("player") if hud != null and is_instance_valid(hud) else null
	var want := wants_active() and not _dialogue and _hud_visible()
	if want != active:
		_set_active(want)
	if not active:
		return
	_safe_t -= delta
	if _safe_t <= 0.0:
		_safe_t = 1.0
		_refresh_safe_area()
	if size != _last_size:
		_relayout()
	_update_mode()
	_update_top_bar()
	_poll_player()
	_update_visibility()


## Phones turned 180° (sensor landscape) move the notch to the other side: re-inset the HUD
## root (our parent) whenever the display safe area changes.
func _refresh_safe_area() -> void:
	var m := UiTheme.safe_area_margins(get_viewport())
	if m == _last_safe:
		return
	_last_safe = m
	var root := get_parent() as Control
	if root and m != Vector4.ZERO:
		UiTheme.apply_safe_area(root)


## The HUD hides during loading and cinematics (PlayableScene.set_hud_visible): so do we.
func _hud_visible() -> bool:
	if hud == null or not is_instance_valid(hud):
		return true
	if hud is CanvasLayer and not (hud as CanvasLayer).visible:
		return false
	var p := get_parent() as CanvasItem
	return p == null or p.visible


func _physics_process(delta: float) -> void:
	actions.flush()
	# Lock button held long enough -> release the lock (once per press).
	for idx: int in _owners:
		var o: Dictionary = _owners[idx]
		if o["kind"] == &"button" and o["id"] == &"lock" and not _lock_handled:
			o["t"] = float(o["t"]) + delta
			if float(o["t"]) >= LOCK_HOLD_RELEASE:
				_lock_handled = true
				if _lock_target() != null:
					actions.tap(&"lock_on", &"lock_hold")
					haptics.on_button()


func _update_mode() -> void:
	var m := &"normal"
	if player != null and is_instance_valid(player):
		if player.has_method("is_alive") and not bool(player.call("is_alive")):
			m = &"dead"
		elif player.has_method("get_state"):
			match int(player.call("get_state")):
				PlayerCharacter.State.MOUNTED: m = &"mounted"
				PlayerCharacter.State.CINEMATIC: m = &"cinematic"
	if m != mode:
		mode = m
		release_all()
		_relabel_mode()
		queue_redraw()


func _relabel_mode() -> void:
	var jump: TouchButton = buttons[&"jump"]
	var it: TouchButton = buttons[&"interact"]
	it.action = &"mount" if mode == &"mounted" else &"interact"
	it.icon = UiTheme.texture(ICON_DIR + ("touch_dismount.svg" if mode == &"mounted" else "touch_interact.svg"))
	it.queue_redraw()
	jump.queue_redraw()


func _update_top_bar() -> void:
	var ids: Array = [&"pause"]
	if mode == &"normal":
		ids.append(&"lock")
		if player != null and player.has_method("get_companion") and player.call("get_companion") != null:
			ids.append(&"call")
	if get_tree().get_first_node_in_group(MAP_GROUP) != null:
		ids.append(&"map")
	if get_tree().get_first_node_in_group(JOURNAL_GROUP) != null:
		ids.append(&"journal")
	if ids != _top_ids:
		_top_ids = ids
		_relayout()


func _update_visibility() -> void:
	var combat := mode == &"normal"
	for id: StringName in COMBAT:
		var b: TouchButton = buttons[id]
		var show := combat or (id == &"jump" and mode == &"mounted")
		# Empty technique / signature slots are not buttons (nothing to press yet).
		if b.slot != null and b.slot.is_empty():
			show = false
		_show_button(b, show)
	for id: StringName in [&"pause", &"lock", &"call", &"map", &"journal"]:
		_show_button(buttons[id], _top_ids.has(id))
	_show_button(buttons[&"descend"], mode == &"mounted" and _mount_can_descend())
	var want_interact := (mode == &"normal" and _prompt_visible) or mode == &"mounted"
	_show_button(buttons[&"interact"], want_interact)
	(buttons[&"lock"] as TouchButton).active = _lock_target() != null
	stick.visible = mode == &"normal" or mode == &"mounted"
	if not stick.visible and stick.is_active():
		_end_stick()
	var element := GameState.element
	if element != _element:
		_element = element
		var acc := UiTheme.element_light(element) if ElementDefs.is_valid(element) else UiTheme.GOLD
		stick.accent = acc
		for b: TouchButton in buttons.values():
			b.accent = acc
		(buttons[&"strike"] as TouchButton).icon = UiTheme.emblem(element) if ElementDefs.is_valid(element) else null
		(buttons[&"strike"] as TouchButton).icon_scale = 0.6


func _show_button(b: TouchButton, on: bool) -> void:
	if b.visible == on:
		return
	b.visible = on
	if b.id == &"interact":
		queue_redraw()
	if not on:
		_release_button_owners(b.id)


func _poll_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("get_ability_slot_info"):
		for i in 5:
			var b: TouchButton = buttons[&"signature"] if i == 4 else buttons[StringName("tech_%d" % i)]
			var d: Variant = player.call("get_ability_slot_info", i)
			b.slot.set_info(d if d is Dictionary else {})
	if player.has_method("get_resource"):
		var f: Variant = player.call("get_resource", &"focus")
		if f is Vector2:
			var sig: TouchButton = buttons[&"signature"]
			var ratio := (f as Vector2).x / maxf((f as Vector2).y, 0.001)
			if not is_equal_approx(ratio, sig.slot.focus_ratio):
				sig.slot.focus_ratio = ratio
				sig.slot.queue_redraw()


# --- Touch routing -----------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			touch_down(st.index, st.position)
		else:
			touch_up(st.index)
		accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		touch_move(sd.index, sd.position, sd.relative)
		accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		accept_event()
		# Mouse emulated from touch: the touch events above already did the work.
		if mb.device == InputEvent.DEVICE_ID_EMULATION or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			touch_down(MOUSE_INDEX, mb.position)
		else:
			touch_up(MOUSE_INDEX)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		accept_event()
		if mm.device != InputEvent.DEVICE_ID_EMULATION and _owners.has(MOUSE_INDEX):
			touch_move(MOUSE_INDEX, mm.position, mm.relative)


## A finger touched the overlay at `p` (overlay coordinates).
func touch_down(index: int, p: Vector2) -> void:
	if not active:
		return
	if _owners.has(index):
		touch_up(index)
	var b := button_at(p)
	if b != null:
		_owners[index] = {"kind": &"button", "id": b.id, "t": 0.0}
		_press_button(b)
		return
	var zone: Rect2 = layout.get("stick_zone", Rect2())
	if stick.visible and not stick.is_active() and zone.has_point(p):
		_owners[index] = {"kind": &"stick", "id": &"", "t": 0.0}
		stick.begin(index, p, Rect2(Vector2.ZERO, size))
		_apply_stick()
		return
	if _look_index < 0:
		_owners[index] = {"kind": &"look", "id": &"", "t": 0.0}
		_look_index = index
		return
	_owners[index] = {"kind": &"none", "id": &"", "t": 0.0}


func touch_move(index: int, p: Vector2, relative: Vector2) -> void:
	if not _owners.has(index):
		return
	var o: Dictionary = _owners[index]
	match o["kind"]:
		&"stick":
			stick.move(p)
			_apply_stick()
		&"look":
			if relative != Vector2.ZERO:
				Events.look_input.emit(relative)


func touch_up(index: int) -> void:
	if not _owners.has(index):
		return
	var o: Dictionary = _owners[index]
	_owners.erase(index)
	match o["kind"]:
		&"stick":
			_end_stick()
		&"look":
			_look_index = -1
		&"button":
			var b: TouchButton = buttons.get(o["id"])
			if b != null:
				_release_button(b, index, float(o["t"]))


## The visible button under `p` (nearest centre when hit areas overlap), or null.
func button_at(p: Vector2) -> TouchButton:
	var best: TouchButton = null
	var best_d := INF
	for b: TouchButton in buttons.values():
		if not b.visible or not b.hit(p):
			continue
		var d := b.hit_distance(p) / maxf(b.radius, 1.0)
		if d < best_d:
			best_d = d
			best = b
	return best


func _press_button(b: TouchButton) -> void:
	b.set_pressed(true)
	haptics.on_button()
	match b.id:
		&"lock":
			_lock_handled = false
		&"pause", &"map", &"journal":
			actions.tap(b.action, b.id)
		_:
			actions.press(b.action, b.id)


func _release_button(b: TouchButton, _index: int, held: float) -> void:
	if not _button_still_held(b.id):
		b.set_pressed(false)
	match b.id:
		&"lock":
			if not _lock_handled and held < LOCK_HOLD_RELEASE:
				_lock_tap()
			_lock_handled = false
		&"pause", &"map", &"journal":
			pass
		_:
			if not _button_still_held(b.id):
				actions.release(b.action, b.id)


func _button_still_held(id: StringName) -> bool:
	for o: Dictionary in _owners.values():
		if o["kind"] == &"button" and o["id"] == id:
			return true
	return false


func _release_button_owners(id: StringName) -> void:
	for idx: int in _owners.keys():
		var o: Dictionary = _owners[idx]
		if o["kind"] == &"button" and o["id"] == id:
			_owners.erase(idx)
	var b: TouchButton = buttons.get(id)
	if b:
		b.set_pressed(false)
		if b.action != &"" and actions.is_held(b.action):
			actions.release(b.action, b.id)


func _apply_stick() -> void:
	var v := stick.vector
	actions.set_strength(&"move_right", &"stick", maxf(v.x, 0.0))
	actions.set_strength(&"move_left", &"stick", maxf(-v.x, 0.0))
	actions.set_strength(&"move_back", &"stick", maxf(v.y, 0.0))
	actions.set_strength(&"move_forward", &"stick", maxf(-v.y, 0.0))
	if stick.sprinting:
		actions.press(&"sprint", &"stick")
	else:
		actions.release(&"sprint", &"stick")


func _end_stick() -> void:
	stick.end()
	for a: StringName in [&"move_right", &"move_left", &"move_back", &"move_forward", &"sprint"]:
		actions.release(a, &"stick")
	for idx: int in _owners.keys():
		if (_owners[idx] as Dictionary)["kind"] == &"stick":
			_owners.erase(idx)


## Lets go of everything (fingers, held actions, stick).
func release_all() -> void:
	_owners.clear()
	_look_index = -1
	_lock_handled = false
	if stick:
		stick.end()
	for b: TouchButton in buttons.values():
		b.set_pressed(false)
	actions.release_all()


# --- Lock-on ------------------------------------------------------------------------------------

func _lock_target() -> Node3D:
	if player != null and is_instance_valid(player) and player.has_method("get_lock_target"):
		var t: Variant = player.call("get_lock_target")
		return t as Node3D if t is Node3D and is_instance_valid(t) else null
	return null


## Tap on the lock button: lock when free; when locked switch to the next target, or
## release when there is no other one.
func _lock_tap() -> void:
	var cur := _lock_target()
	if cur == null:
		actions.tap(&"lock_on", &"lock")
		return
	var targeting: Variant = player.get("targeting") if player != null else null
	if targeting is Object and (targeting as Object).has_method("cycle"):
		(targeting as Object).call("cycle", 1.0)
		if _lock_target() == cur:
			(targeting as Object).call("cycle", -1.0)
		if _lock_target() != cur:
			return
	actions.tap(&"lock_on", &"lock")


# --- Mount helpers -------------------------------------------------------------------------------

func _mount_node() -> Node:
	if player == null or not is_instance_valid(player):
		return null
	var m: Variant = player.get("mount_node")
	return m as Node if m is Node and is_instance_valid(m) else null


func _mount_flies() -> bool:
	var m := _mount_node()
	return m != null and m.get("flight") != null


func _mount_can_descend() -> bool:
	var m := _mount_node()
	return m != null and (m.get("flight") != null or m.get("burrow") != null)


# --- Events ----------------------------------------------------------------------------------------

func _on_prompt(text: String, show: bool) -> void:
	_prompt_visible = show and not text.is_empty()
	prompt_text = strip_key_prefix(text) if _prompt_visible else ""
	queue_redraw()


## "[E] Talk to Pakku" -> "Talk to Pakku".
static func strip_key_prefix(text: String) -> String:
	var t := text.strip_edges()
	if t.begins_with("["):
		var close := t.find("]")
		if close >= 0:
			t = t.substr(close + 1).strip_edges()
	return t


func _on_ability_failed(id: StringName, _reason: StringName) -> void:
	if not active:
		return
	for b: TouchButton in buttons.values():
		if b.slot != null and StringName(b.slot.info.get("id", &"")) == id:
			b.slot.flash_fail()
			return


func _on_ability_used(id: StringName) -> void:
	if not active:
		return
	for b: TouchButton in buttons.values():
		if b.slot != null and StringName(b.slot.info.get("id", &"")) == id:
			b.slot.pulse_used()
			return


func _on_hit_landed(hit: HitInfo, target: Node, result: int) -> void:
	if active:
		haptics.on_hit_landed(hit, target, result)


func _on_player_damaged(amount: float, hit: HitInfo) -> void:
	if active:
		haptics.on_player_damaged(amount, hit)


static func _action_for(id: StringName) -> StringName:
	match id:
		&"pause": return &"pause"
		&"lock": return &"lock_on"
		&"call": return &"companion_call"
		&"map": return &"open_map"
		&"journal": return &"open_journal"
		&"interact": return &"interact"
		&"descend": return &"descend"
	return COMBAT.get(id, &"")


# --- Drawing: the contextual prompt plate -------------------------------------------------------------

func _draw() -> void:
	var it: TouchButton = buttons.get(&"interact")
	if it == null or not it.visible:
		return
	var text := "Dismount" if mode == &"mounted" else prompt_text
	if text.is_empty():
		return
	var f := UiTheme.title_font(600, 2)
	var fs := 24
	var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var c := it.get_center()
	var dir := int(layout.get("interact_text_dir", -1))
	var h := 54.0
	var w := ts.x + 46.0
	var x0 := c.x - it.radius - 10.0 - w if dir < 0 else c.x + it.radius + 10.0
	var rect := Rect2(x0, c.y - h * 0.5, w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.INK, 0.82)
	sb.border_color = Color(UiTheme.GOLD, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(h * 0.5))
	sb.anti_aliasing = true
	draw_style_box(sb, rect)
	draw_string(f, Vector2(rect.position.x + 23.0, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.PARCHMENT)
