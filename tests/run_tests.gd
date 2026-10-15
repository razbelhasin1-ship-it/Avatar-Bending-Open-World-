extends Node
## Automated test runner. Run with tools/test.sh [filter].
## Discovers tests/unit/test_*.gd and tests/integration/test_*.gd.

const DIRS := ["res://tests/unit", "res://tests/integration"]


func _ready() -> void:
	await get_tree().process_frame
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var files: Array[String] = []
	for dir_path: String in DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.begins_with("test_") and f.ends_with(".gd"):
				var full := dir_path.path_join(f)
				if filter.is_empty() or full.contains(filter):
					files.append(full)
	files.sort()
	var total := 0
	var failed := 0
	var all_failures: Array[String] = []
	for path in files:
		var script := load(path) as GDScript
		if script == null:
			all_failures.append("%s: failed to load (parse error?)" % path)
			failed += 1
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if mname.begins_with("test_") and not methods.has(mname):
				methods.append(mname)
		for mname in methods:
			var node: Node = script.new()
			node.name = path.get_file().get_basename()
			add_child(node)
			node.current_test = "%s::%s" % [path.get_file(), mname]
			total += 1
			var before := (node.failures as Array).size()
			await node.before_each()
			var t0 := Time.get_ticks_msec()
			await node.call(mname)
			await node.after_each()
			var dt := Time.get_ticks_msec() - t0
			var errs: Array = node.failures
			if errs.size() > before:
				failed += 1
				print("  FAIL  %s (%d ms)" % [node.current_test, dt])
				for e in errs.slice(before):
					print("        - ", e)
					all_failures.append(e)
			else:
				print("  ok    %s (%d ms)" % [node.current_test, dt])
			get_tree().paused = false
			Engine.time_scale = 1.0
			node.queue_free()
			await get_tree().process_frame
	print("")
	print("TESTS: %d run, %d failed" % [total, failed])
	if failed > 0:
		print("FAILURES:")
		for e in all_failures:
			print("  ", e)
	get_tree().quit(1 if failed > 0 else 0)
