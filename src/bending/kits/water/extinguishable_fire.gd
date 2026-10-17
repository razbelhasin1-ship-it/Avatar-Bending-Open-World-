class_name ExtinguishableFire
extends Node3D
## A fire that water puts out - the reference implementation of the shared
## extinguish hook (WaterEnv): a node in group &"extinguishable" with
## extinguish(by, at) -> bool and `extinguish_radius`. Braziers, campfires,
## torches, burning wreckage (any module) can add one of these, or implement
## the two members themselves.
##
##   var f := ExtinguishableFire.new()
##   f.size = 0.6               # flame size (m)
##   f.relight_time = 20.0      # <= 0: stays out
##   brazier.add_child(f); f.position = Vector3(0, 1.1, 0)
##   f.extinguished.connect(func(by): ...)     # quests, AI reactions
##
## Burning: a flame (FireFx fire-ball sprites + embers), owned by this node.
## Put out: hiss, steam and smoke; relights after relight_time.

signal extinguished(by: Node)
signal relit

@export var size := 0.5
@export var relight_time := 25.0
@export var extinguish_radius := 0.6
## Starts burning.
@export var lit := true

var flame: FireFx.FireBall = null
var _out_t := 0.0


func _ready() -> void:
	add_to_group(WaterEnv.GROUP)
	if lit:
		_light()


func is_burning() -> bool:
	return lit


## WaterEnv hook: put the fire out. Returns true if it was burning.
func extinguish(by: Node = null, _at: Vector3 = Vector3.ZERO) -> bool:
	if not lit:
		return false
	lit = false
	_out_t = 0.0
	_drop_flame()
	var p := global_position
	FxBurst.spawn(self, &"steam", p, {"count": 1.2, "size": 0.8 + size})
	FxBurst.spawn(self, &"smoke", p + Vector3.UP * 0.2, {"count": 0.8, "size": 0.6 + size})
	Audio.play_bending(ElementDefs.Element.FIRE, &"extinguish", p)
	extinguished.emit(by)
	return true


func relight() -> void:
	if lit:
		return
	lit = true
	_light()
	relit.emit()


func _light() -> void:
	if not is_inside_tree():
		return
	# Its own flame (not from the projectile pool, which may recycle pooled balls).
	flame = FireFx.FireBall.make()
	add_child(flame)
	flame.setup(size)
	FireFx.burst(self, global_position, 0.6)


func _drop_flame() -> void:
	if flame != null and is_instance_valid(flame):
		flame.queue_free()
	flame = null


func _process(delta: float) -> void:
	if lit:
		return
	if relight_time > 0.0:
		_out_t += delta
		if _out_t >= relight_time:
			relight()


