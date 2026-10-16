extends SceneTree


class Holder extends RefCounted:
	var v := 5

	func bound() -> Callable:
		return add_one

	func add_one(a: int) -> int:
		return a + v

	func lam() -> Callable:
		return func(a: int) -> int: return a + v


func _init() -> void:
	var h := Holder.new()
	var w: WeakRef = weakref(h)
	var b := h.bound()
	h = null
	print("after drop (bound callable held): alive=", w.get_ref() != null, " valid=", b.is_valid())
	b = Callable()
	print("after callable dropped: alive=", w.get_ref() != null)
	var h3 := Holder.new()
	var w3: WeakRef = weakref(h3)
	var l := h3.lam()
	h3 = null
	print("lambda using self keeps alive=", w3.get_ref() != null, " valid=", l.is_valid())
	quit()
