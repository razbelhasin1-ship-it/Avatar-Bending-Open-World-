class_name MobilePlatform
extends Node
## Phone / tablet / browser lifecycle glue (docs/modules/mobile.md). A self-registering
## node under the tree root (installed by UiInput.ensure, i.e. by every menu and the HUD):
##
## * Android back button / gesture: never quits the app (SceneTree.quit_on_go_back off).
##   In gameplay it opens the pause menu (the `pause` action), in menus it is "Back"
##   (`ui_cancel`), exactly like Esc / B.
## * App sent to the background (or the browser tab hidden): every held action is released
##   (no stuck stick or held Defend) and a running game is paused, so the player returns
##   to the pause menu, not to a fight that went on without them.
##
##   MobilePlatform.ensure(get_tree())

## Emitted after the platform back request was translated (tests).
signal back_requested(action: StringName)

static var _inst: MobilePlatform = null

## Pause gameplay when the app goes to the background (always on phones and in browsers;
## desktop window focus loss does not pause).
var pause_on_background := true


static func ensure(tree: SceneTree) -> MobilePlatform:
	if is_instance_valid(_inst):
		return _inst
	_inst = MobilePlatform.new()
	_inst.name = "MobilePlatform"
	_inst.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(_inst)
	return _inst


func _ready() -> void:
	# The back button is "Back" / "Pause", never "close the app mid-journey".
	get_tree().quit_on_go_back = false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			back_pressed()
		NOTIFICATION_APPLICATION_PAUSED:
			went_to_background()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if PlatformInfo.is_native_mobile() or PlatformInfo.is_web_mobile():
				went_to_background()


## Translates the platform back request into `pause` (gameplay) or `ui_cancel` (menus).
func back_pressed() -> StringName:
	var action := &"ui_cancel"
	if _in_gameplay() and not get_tree().paused:
		action = &"pause"
	_send(action)
	back_requested.emit(action)
	return action


## Releases every held action and pauses a running game.
func went_to_background() -> void:
	for a in InputMap.get_actions():
		if Input.is_action_pressed(a):
			Input.action_release(a)
	if pause_on_background and _in_gameplay() and not get_tree().paused:
		_send(&"pause")


func _in_gameplay() -> bool:
	return get_tree().get_first_node_in_group(&"playable_scene") != null \
			or get_tree().get_first_node_in_group(&"player") != null


static func _send(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		ev.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(ev)
