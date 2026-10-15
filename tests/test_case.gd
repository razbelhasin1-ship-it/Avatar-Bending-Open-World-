class_name TestCase
extends Node
## Base class for automated tests. Put files named test_*.gd in tests/unit or
## tests/integration; every method starting with `test_` runs (may `await`).
## The runner adds the test node to the scene tree, so autoloads and physics work.
##
##   extends TestCase
##   func test_health_dies() -> void:
##       var h := HealthComponent.new(); add_child(h)
##       h.apply_damage(500)
##       expect(h.is_dead(), "should die")

var failures: Array[String] = []
var current_test: String = ""


## Called before/after each test method. Override as needed.
func before_each() -> void:
	pass


func after_each() -> void:
	pass


func expect(cond: bool, msg: String = "expectation failed") -> bool:
	if not cond:
		failures.append("%s: %s" % [current_test, msg])
	return cond


func expect_eq(a: Variant, b: Variant, msg: String = "") -> bool:
	return expect(a == b, "%s expected %s == %s" % [msg, str(a), str(b)])


func expect_near(a: float, b: float, eps: float = 0.001, msg: String = "") -> bool:
	return expect(absf(a - b) <= eps, "%s expected %f ≈ %f (±%f)" % [msg, a, b, eps])


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])


## Waits for `n` physics frames.
func physics_frames(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


func frames(n: int = 1) -> void:
	for i in n:
		await get_tree().process_frame


func seconds(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout
