class_name Hud
extends CanvasLayer
## In-game HUD (scenes/ui/hud.tscn). Add one to the world/tutorial scene and bind the
## player:
##
##   var hud: Hud = preload("res://scenes/ui/hud.tscn").instantiate()
##   add_child(hud)
##   hud.bind_player(player)
##
## Player contract (duck-typed; everything optional except `health`):
##   var health: HealthComponent                       (or func get_health_component())
##   signal resource_changed(resource: StringName, value: float, max_value: float)
##       resources: &"health", &"chi", &"focus" — Events.player_resource_changed works too
##   func get_resource(resource: StringName) -> Vector2   # (value, max) for the initial state
##   func get_ability_slot_info(i: int) -> Dictionary      # i 0..3 techniques, 4 = signature:
##       {id, name, icon (Texture2D or path), element, cooldown_ratio (1 just used .. 0 ready),
##        cooldown_left (s), available (bool), cost (chi)}
##   func get_lock_target() -> Node3D                      # null when not locked
##   func get_companion() -> Node3D                        # optional; may expose `health`,
##       `display_name`, func get_status_text() -> String
## Quest provider (optional, `bind_quest_provider(obj)`):
##   func get_quest_display(quest_id: StringName) -> Dictionary
##       {"title": String, "objectives": [{"text", "done", "count", "target"}], "target": Vector3}
## Everything else is driven by Events: notify, interaction_prompt, region_entered,
## ability_failed / ability_used, hit_landed, player_damaged, target_locked/unlocked,
## quest_* , poi_discovered, player_level_up.
##
## Layout keeps the centre of the screen clear: vitals top-left, compass and lock-on plate
## top-centre, toasts top-right, quest tracker right, companion bottom-left, techniques
## bottom-centre, interaction prompt just above them.

const CENTER_CLEAR := Rect2(0.3, 0.22, 0.4, 0.52)

## Show a title card on every Events.region_entered (default). The world scene turns this
## off and shows first-visit cards itself (RegionDirector); the compass still updates.
var region_titles := true
var player: Node = null
var quest_provider: Object = null
var health: HealthComponent = null
var camera: Camera3D = null

var root: Control
var vitals: HudVitals
var abilities: HudAbilityBar
var compass: HudCompass
var lock_on: HudLockOn
var toasts: HudToasts
var quest: HudQuestTracker
var companion_panel: HudCompanion
var damage_numbers: HudDamageNumbers
var title_card: TitleCard
var prompt_panel: Control
## On-screen touch controls (src/ui/touch, docs/modules/mobile.md). Shows itself when
## Settings.touch_controls_enabled(); its buttons then replace the ability bar and prompt.
var touch: TouchOverlay

var _prompt_label: Label
var _prompt_glyph: PromptGlyph
var _vignette: ColorRect
var _vig_mat: ShaderMaterial
var _hit_flash := 0.0
var _health_ratio := 1.0
var _poi_timer := 0.0
var _resources := {&"health": Vector2(100, 100), &"chi": Vector2(100, 100), &"focus": Vector2(0, 100)}


func _ready() -> void:
	layer = 10
	UiInput.ensure(get_tree())
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	UiTheme.apply_safe_area(root)
	_build()
	_connect_events()
	vitals.set_element(GameState.element)
	vitals.set_level(GameState.level)
	_set_companion_from_state()
	set_region(GameState.region)


func _build() -> void:
	_vignette = ColorRect.new()
	_vignette.name = "Vignette"
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = preload("res://src/ui/shaders/hud_vignette.gdshader")
	_vig_mat.set_shader_parameter(&"noise_tex", preload("res://assets/textures/world/clouds.png"))
	_vignette.material = _vig_mat
	root.add_child(_vignette)
	damage_numbers = HudDamageNumbers.new()
	damage_numbers.name = "DamageNumbers"
	root.add_child(damage_numbers)
	lock_on = HudLockOn.new()
	lock_on.name = "LockOn"
	root.add_child(lock_on)
	vitals = HudVitals.new()
	vitals.name = "Vitals"
	vitals.position = Vector2(40, 34)
	root.add_child(vitals)
	compass = HudCompass.new()
	compass.name = "Compass"
	compass.anchor_left = 0.5
	compass.anchor_right = 0.5
	compass.offset_left = -390
	compass.offset_right = 390
	compass.offset_top = 26
	compass.offset_bottom = 112
	root.add_child(compass)
	toasts = HudToasts.new()
	toasts.name = "Toasts"
	toasts.anchor_left = 1.0
	toasts.anchor_right = 1.0
	toasts.offset_left = -560
	toasts.offset_right = -40
	toasts.offset_top = 36
	toasts.offset_bottom = 420
	root.add_child(toasts)
	quest = HudQuestTracker.new()
	quest.name = "Quest"
	quest.anchor_left = 1.0
	quest.anchor_right = 1.0
	quest.offset_left = -480
	quest.offset_right = -40
	quest.offset_top = 450
	quest.offset_bottom = 700
	root.add_child(quest)
	companion_panel = HudCompanion.new()
	companion_panel.name = "Companion"
	companion_panel.anchor_top = 1.0
	companion_panel.anchor_bottom = 1.0
	companion_panel.offset_left = 40
	companion_panel.offset_right = 400
	companion_panel.offset_top = -128
	companion_panel.offset_bottom = -40
	root.add_child(companion_panel)
	abilities = HudAbilityBar.new()
	abilities.name = "Abilities"
	abilities.anchor_left = 0.5
	abilities.anchor_right = 0.5
	abilities.anchor_top = 1.0
	abilities.anchor_bottom = 1.0
	abilities.offset_left = -330
	abilities.offset_right = 330
	abilities.offset_top = -150
	abilities.offset_bottom = -44
	root.add_child(abilities)
	_build_prompt()
	title_card = TitleCard.new()
	title_card.name = "TitleCard"
	root.add_child(title_card)
	touch = TouchOverlay.new()
	touch.hud = self
	root.add_child(touch)


func _build_prompt() -> void:
	prompt_panel = PanelContainer.new()
	prompt_panel.name = "Prompt"
	var sb := UiFrameStyle.make(Color(UiTheme.INK, 0.8), Color(UiTheme.GOLD, 0.45), 1.0)
	sb.content_margin_left = 18
	sb.content_margin_right = 22
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	prompt_panel.add_theme_stylebox_override(&"panel", sb)
	prompt_panel.anchor_left = 0.5
	prompt_panel.anchor_right = 0.5
	prompt_panel.anchor_top = 1.0
	prompt_panel.anchor_bottom = 1.0
	prompt_panel.offset_left = -220
	prompt_panel.offset_right = 220
	prompt_panel.offset_top = -244
	prompt_panel.offset_bottom = -188
	prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_panel.add_child(h)
	_prompt_glyph = PromptGlyph.for_action(&"interact", 34)
	h.add_child(_prompt_glyph)
	_prompt_label = UiTheme.make_label("", UiTheme.title_font(600, 2), UiTheme.SIZE_SMALL + 1, UiTheme.PARCHMENT)
	_prompt_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_prompt_label)
	prompt_panel.visible = false
	root.add_child(prompt_panel)


func _connect_events() -> void:
	Events.notify.connect(notify)
	Events.interaction_prompt.connect(set_interaction_prompt)
	Events.region_entered.connect(_on_region_entered)
	Events.ability_failed.connect(_on_ability_failed)
	Events.ability_used.connect(_on_ability_used)
	Events.hit_landed.connect(damage_numbers.on_hit_landed)
	# burn ticks (meta "dot") only tint the edges a little; real blows flash fully
	Events.player_damaged.connect(func(_a: float, h: HitInfo) -> void:
		_hit_flash = maxf(_hit_flash, 0.3 if h != null and h.has_meta(&"dot") else 1.0))
	Events.player_resource_changed.connect(set_resource)
	Events.target_locked.connect(func(t: Node3D) -> void: lock_on.set_target(t))
	Events.target_unlocked.connect(func() -> void: lock_on.set_target(null))
	Events.quest_started.connect(_on_quest_changed)
	Events.quest_updated.connect(_on_quest_changed)
	Events.objective_completed.connect(func(q: StringName, _o: StringName) -> void: _on_quest_changed(q))
	Events.quest_completed.connect(_on_quest_completed)
	Events.player_level_up.connect(_on_level_up)
	Events.companion_spawned.connect(func(_c: Node3D) -> void: _set_companion_from_state())
	Events.dialogue_started.connect(func(_n: Node) -> void: set_combat_hud_visible(false))
	Events.dialogue_ended.connect(func(_n: Node) -> void: set_combat_hud_visible(true))


# --- Binding --------------------------------------------------------------------------------

## Binds the HUD to a player (see the contract above).
func bind_player(p: Node) -> void:
	if health and health.changed.is_connected(_on_health_changed):
		health.changed.disconnect(_on_health_changed)
	player = p
	health = null
	if p == null:
		return
	var h: Variant = p.get("health")
	if h is HealthComponent:
		health = h
	elif p.has_method("get_health_component"):
		health = p.call("get_health_component") as HealthComponent
	if health:
		health.changed.connect(_on_health_changed)
		set_resource(&"health", health.health, health.max_health)
	if p.has_signal(&"resource_changed"):
		p.connect(&"resource_changed", set_resource)
	if p.has_method("get_resource"):
		for r: StringName in [&"chi", &"focus"]:
			var v: Variant = p.call("get_resource", r)
			if v is Vector2:
				set_resource(r, (v as Vector2).x, (v as Vector2).y)
	vitals.set_element(GameState.element)
	_poll_player(true)


func bind_quest_provider(provider: Object) -> void:
	quest_provider = provider
	if GameState.tracked_quest != &"":
		_on_quest_changed(GameState.tracked_quest)


## Sets health/chi/focus (also from Events.player_resource_changed).
func set_resource(resource: StringName, value: float, max_value: float) -> void:
	var instant := not _resources.has(resource)
	_resources[resource] = Vector2(value, max_value)
	match resource:
		&"health":
			vitals.set_health(value, max_value, instant)
			_health_ratio = value / maxf(max_value, 0.001)
		&"chi":
			vitals.set_chi(value, max_value, instant)
		&"focus":
			vitals.set_focus(value, max_value)
			abilities.signature.focus_ratio = value / maxf(max_value, 0.001)
			abilities.signature.queue_redraw()


func get_resource(resource: StringName) -> Vector2:
	return _resources.get(resource, Vector2.ZERO)


func _on_health_changed(current: float, maximum: float) -> void:
	set_resource(&"health", current, maximum)


func _poll_player(force: bool = false) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("get_ability_slot_info"):
		for i in 5:
			var d: Variant = player.call("get_ability_slot_info", i)
			abilities.slot(i).set_info(d if d is Dictionary else {})
	if player.has_method("get_locked_signature_info"):
		var lk: Variant = player.call("get_locked_signature_info")
		abilities.signature.set_locked(lk if lk is Dictionary else {})
	if player.has_method("get_lock_target"):
		var t: Variant = player.call("get_lock_target")
		lock_on.set_target(t as Node3D if is_instance_valid(t) else null)
	if player.has_method("get_companion"):
		var c: Variant = player.call("get_companion")
		if c is Node and is_instance_valid(c):
			var ch := HudLockOn.find_health(c)
			var status := "Following"
			if (c as Node).has_method("get_status_text"):
				status = String((c as Node).call("get_status_text"))
			companion_panel.set_status(ch.ratio() if ch else float(GameState.companion.get("health_ratio", 1.0)), status)
	if force:
		pass


func _process(delta: float) -> void:
	camera = get_viewport().get_camera_3d()
	lock_on.camera = camera
	damage_numbers.camera = camera
	_poll_player()
	compass.set_heading_from_camera(camera)
	if player is Node3D and is_instance_valid(player):
		compass.origin = (player as Node3D).global_position
		_poi_timer -= delta
		if _poi_timer <= 0.0:
			_poi_timer = 0.5
			_refresh_compass_markers()
	_hit_flash = maxf(0.0, _hit_flash - delta * 2.5)
	var low := clampf((0.35 - _health_ratio) / 0.3, 0.0, 1.0)
	_vig_mat.set_shader_parameter(&"intensity", low)
	_vig_mat.set_shader_parameter(&"hit_flash", _hit_flash)
	_vignette.visible = low > 0.0 or _hit_flash > 0.0


func _refresh_compass_markers() -> void:
	var list: Array[Dictionary] = []
	for poi: Dictionary in WorldData.get_pois_in_radius(compass.origin, 900.0):
		if list.size() >= 8:
			break
		var known := GameState.discovered_pois.has(String(poi.get("id", "")))
		list.append({"position": poi["position"], "kind": &"discovered" if known else &"poi", "label": String(poi.get("name", ""))})
	var q := quest.data
	if q.has("target") and q["target"] is Vector3:
		list.append({"position": q["target"], "kind": &"quest"})
	if player and player.has_method("get_companion"):
		var c: Variant = player.call("get_companion")
		if c is Node3D and is_instance_valid(c) and compass.origin.distance_to((c as Node3D).global_position) > 25.0:
			list.append({"position": (c as Node3D).global_position, "kind": &"companion"})
	compass.set_markers(list)


# --- Events ---------------------------------------------------------------------------------

## Toast notification (Events.notify).
func notify(text: String, kind: StringName = &"info") -> void:
	toasts.push(text, kind)


## Shows/hides the interaction prompt (Events.interaction_prompt).
func set_interaction_prompt(text: String, show: bool) -> void:
	if touch and touch.active:
		# The touch overlay's contextual button shows the prompt (tap to interact).
		prompt_panel.visible = false
		return
	if show and not text.is_empty():
		_prompt_label.text = text
		if not prompt_panel.visible:
			prompt_panel.visible = true
			UiFx.fade_in(prompt_panel, 0.15)
	else:
		prompt_panel.visible = false


func set_region(region_id: StringName) -> void:
	compass.set_region(TitleCard.region_title(region_id) if region_id != &"" else "")


func _on_region_entered(region_id: StringName) -> void:
	set_region(region_id)
	if region_titles:
		title_card.show_region(region_id)


func _on_ability_failed(ability_id: StringName, reason: StringName) -> void:
	if reason == &"locked":
		# The signature is not learned yet: say what it is and how to get it (at most every 4 s).
		abilities.signature.flash_fail()
		UiFx.sound(UiFx.ERROR)
		var now := Time.get_ticks_msec()
		if now - _locked_hint_ms > 4000:
			_locked_hint_ms = now
			notify(HudAbilitySlot.locked_hint(abilities.signature.locked), &"warning")
		return
	var s := abilities.find_slot(ability_id)
	if s:
		s.flash_fail()
	UiFx.sound(UiFx.ERROR)


var _locked_hint_ms := -100000


## Level-up: the vitals seal updates; the announcement itself belongs to the progression
## LevelUpBanner (group &"level_up_banner", installed in the world). Only where no banner
## exists (dev arenas) the HUD shows one toast - several level-ups at once become one.
func _on_level_up(level: int) -> void:
	vitals.set_level(level)
	if GameState.is_tutorial or not is_inside_tree():
		return
	if get_tree().get_first_node_in_group(&"level_up_banner") != null:
		return
	var first := _level_toast_pending < 0
	_level_toast_pending = maxi(_level_toast_pending, level)
	if first:
		_flush_level_toast.call_deferred()


var _level_toast_pending := -1


func _flush_level_toast() -> void:
	if _level_toast_pending > 0:
		notify("Level %d reached  ·  +1 skill point" % _level_toast_pending, &"unlock")
	_level_toast_pending = -1


func _on_ability_used(ability_id: StringName) -> void:
	var s := abilities.find_slot(ability_id)
	if s:
		s.pulse_used()


func _on_quest_changed(quest_id: StringName) -> void:
	if quest_provider and quest_provider.has_method("get_quest_display"):
		var d: Variant = quest_provider.call("get_quest_display", quest_id)
		if d is Dictionary and not (d as Dictionary).is_empty():
			if GameState.tracked_quest == &"" or GameState.tracked_quest == quest_id:
				quest.show_quest(d)


func _on_quest_completed(quest_id: StringName) -> void:
	if GameState.tracked_quest == quest_id or quest.data.get("id", &"") == quest_id:
		quest.clear_quest()


func _set_companion_from_state() -> void:
	var nm := String(GameState.companion.get("name", ""))
	companion_panel.set_companion(nm, GameState.element)
	companion_panel.set_status(float(GameState.companion.get("health_ratio", 1.0)), "Following")


## Hides combat widgets (dialogue, cinematics); toasts and title cards stay.
func set_combat_hud_visible(on: bool) -> void:
	for c: CanvasItem in [vitals, abilities, compass, quest, companion_panel, lock_on, prompt_panel]:
		var t := create_tween()
		t.tween_property(c, "modulate:a", 1.0 if on else 0.0, 0.25)


## Touch controls on/off (called by TouchOverlay): its buttons replace the ability bar and
## the interaction prompt; toasts move below its top bar, the quest tracker under the
## vitals (the right-thumb cluster owns the lower right) and the companion plate to the
## right when the cluster is mirrored for left-handed play.
func apply_touch_layout(on: bool, left_handed: bool = false) -> void:
	abilities.visible = not on
	if on:
		prompt_panel.visible = false
	toasts.offset_top = 150 if on else 36
	toasts.offset_bottom = 430 if on else 420
	toasts.max_visible = 3 if on else 4
	quest.anchor_left = 0.0 if on else 1.0
	quest.anchor_right = 0.0 if on else 1.0
	quest.offset_left = 40.0 if on else -480.0
	quest.offset_right = 480.0 if on else -40.0
	quest.offset_top = 190.0 if on else 450.0
	quest.offset_bottom = 430.0 if on else 700.0
	var right := on and left_handed
	companion_panel.anchor_left = 1.0 if right else 0.0
	companion_panel.anchor_right = 1.0 if right else 0.0
	companion_panel.offset_left = -400.0 if right else 40.0
	companion_panel.offset_right = -40.0 if right else 400.0


## Screen rect (design px) that HUD widgets must not cover.
func center_clear_rect() -> Rect2:
	var s := root.size
	return Rect2(s * CENTER_CLEAR.position, s * CENTER_CLEAR.size)
