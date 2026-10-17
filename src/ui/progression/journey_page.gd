class_name JourneyPage
extends Control
## Base of the Journey Book pages (Skills, Map, Journal, Inventory, Character).
## The book (JourneyBook) owns pausing, tabs, closing and the hint bar; a page builds its
## own content in `_build()` (called once, lazily, the first time the page is shown) and
## refreshes from the live game state in `on_open()` every time it becomes visible.
##
## Input contract: the book forwards events to `handle_input(event)` before its own tab /
## close shortcuts; a page returns true when it consumed one. `handle_back()` lets a page
## undo a local mode first (e.g. "choose a slot") before Esc / B closes the book.

## Owning book (set before `_build`).
var book: Node = null
## Page id: &"skills", &"map", &"journal", &"inventory", &"character".
var page_id: StringName = &""
var built := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE


## Builds the content once (the book calls this before the first `on_open`).
func ensure_built() -> void:
	if built:
		return
	built = true
	_build()


## Override: create child controls.
func _build() -> void:
	pass


## Override: the page became visible. `args` come from JourneyBook.open(page, args).
func on_open(_args: Dictionary) -> void:
	pass


## Override: the page is being hidden (book closed or another tab).
func on_close() -> void:
	pass


## Override: control focused when the page opens (keyboard / controller navigation).
func initial_focus() -> Control:
	return null


## Override: hint bar entries (InputHintBar format) for this page.
func hints() -> Array:
	return []


## Override: Esc / B pressed. Return true if the page handled it (the book stays open).
func handle_back() -> bool:
	return false


## Override: page shortcuts. Return true when the event was consumed.
func handle_input(_event: InputEvent) -> bool:
	return false


## Override: per-frame update while visible (the book calls it; the tree may be paused).
func page_process(_delta: float) -> void:
	pass


## Helper: the live player (or null in previews / tests).
func player() -> Node3D:
	return get_tree().get_first_node_in_group(&"player") as Node3D if is_inside_tree() else null


## Helper: refreshes the book's hint bar after a mode change.
func refresh_hints() -> void:
	if book != null and book.has_method("refresh_hints"):
		book.call("refresh_hints")
