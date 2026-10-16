class_name TimeDilation
extends Node
## Global time-scale dips that can never stick: hitstop (Events.hitstop) and
## brief slow motion (Water's perfect dodge). Requests are timed in REAL time
## (Time.get_ticks_usec) by a PROCESS_MODE_ALWAYS node under the tree root, the
## lowest active scale wins, and Engine.time_scale returns to 1.0 as soon as
## none are active (also when the node leaves the tree).
##
##   TimeDilation.request(0.05, 0.08)    # hitstop
##   TimeDilation.request(0.35, 0.5)     # slow motion
##   TimeDilation.clear()

const MAX_DURATION := 1.5
const MIN_SCALE := 0.02

static var _node: TimeDilation = null
## [scale, end_usec]
var _requests: Array = []
var _owns_scale := false


static func _instance(tree: SceneTree = null) -> TimeDilation:
	if _node != null and is_instance_valid(_node):
		return _node
	var t := tree if tree else Engine.get_main_loop() as SceneTree
	if t == null:
		return null
	_node = TimeDilation.new()
	_node.name = "TimeDilation"
	_node.process_mode = Node.PROCESS_MODE_ALWAYS
	t.root.add_child.call_deferred(_node)
	return _node


## Dips Engine.time_scale to `scale` for `real_seconds` of wall-clock time.
static func request(scale: float, real_seconds: float) -> void:
	var n := _instance()
	if n == null:
		return
	var d := clampf(real_seconds, 0.0, MAX_DURATION)
	if d <= 0.0:
		return
	n._requests.append([clampf(scale, MIN_SCALE, 1.0), Time.get_ticks_usec() + int(d * 1000000.0)])
	n._apply()


static func clear() -> void:
	if _node != null and is_instance_valid(_node):
		_node._requests.clear()
		_node._apply()


static func is_active() -> bool:
	return _node != null and is_instance_valid(_node) and not _node._requests.is_empty()


func _process(_delta: float) -> void:
	if not _requests.is_empty() or _owns_scale:
		_apply()


func _apply() -> void:
	var now := Time.get_ticks_usec()
	var s := 1.0
	for i in range(_requests.size() - 1, -1, -1):
		var r: Array = _requests[i]
		if now >= int(r[1]):
			_requests.remove_at(i)
		else:
			s = minf(s, float(r[0]))
	if s < 1.0:
		Engine.time_scale = s
		_owns_scale = true
	elif _owns_scale:
		Engine.time_scale = 1.0
		_owns_scale = false


func _exit_tree() -> void:
	if _owns_scale:
		Engine.time_scale = 1.0
	_owns_scale = false
	_requests.clear()
	if _node == self:
		_node = null
