extends SceneTree
## Loads every .gd and .tscn under res://src, res://scenes and res://tests to
## surface parse errors. Used by tools/check.sh.

var _bad := 0


func _initialize() -> void:
	for root in ["res://src", "res://scenes", "res://tests", "res://tools"]:
		_scan(root)
	if _bad > 0:
		print("CHECK FAILED: %d resources failed to load" % _bad)
	else:
		print("CHECK OK")
	quit(1 if _bad > 0 else 0)


func _scan(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_scan(path.path_join(sub))
	for f in dir.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			var full := path.path_join(f)
			if full == "res://tools/check_scripts.gd":
				continue  # reloading the running script corrupts its bytecode
			var res := ResourceLoader.load(full)
			if res == null:
				print("CHECK FAILED: cannot load ", full)
				_bad += 1
			elif res is GDScript and not (res as GDScript).can_instantiate() and not (res as GDScript).is_abstract():
				print("CHECK FAILED: script has errors ", full)
				_bad += 1
