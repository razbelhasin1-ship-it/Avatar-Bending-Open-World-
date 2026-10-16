class_name PlayerInteraction
extends Node
## Picks the best Interactable in range (distance + facing + priority) at
## 10 Hz, drives Events.interaction_prompt ("[E] Talk to ...") only when the
## choice changes, and triggers it on the interact action (via the player).

var body: Node3D
var current: Interactable = null
var enabled := true
var _timer := 0.0
var _shown_text := ""


func tick(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.1
	var best: Interactable = _pick() if enabled else null
	current = best
	var text := ""
	if best != null:
		text = "[%s] %s" % [InputDefaults.prompt_for(&"interact"), best.get_interaction_text(body)]
	if text != _shown_text:
		_shown_text = text
		Events.interaction_prompt.emit(text, text != "")


func _pick() -> Interactable:
	var o := body.global_position
	var f := -body.global_basis.z
	f.y = 0.0
	f = f.normalized()
	var best: Interactable = null
	var best_score := -INF
	for n in body.get_tree().get_nodes_in_group(&"interactable"):
		var it := n as Interactable
		if it == null or not it.is_inside_tree() or not it.can_interact(body):
			continue
		var p := it.focus_point()
		var to := p - o
		to.y = 0.0
		var d := to.length()
		if d > it.radius + 0.4:
			continue
		var facing := f.dot(to.normalized()) if d > 0.05 else 1.0
		if facing < -0.35 and d > 0.9:
			continue
		var score := float(it.interact_priority) * 10.0 + facing * 1.5 - d
		if score > best_score:
			best_score = score
			best = it
	return best


## Hides the prompt (cinematics, death, mounting).
func hide_prompt() -> void:
	current = null
	if _shown_text != "":
		_shown_text = ""
		Events.interaction_prompt.emit("", false)
