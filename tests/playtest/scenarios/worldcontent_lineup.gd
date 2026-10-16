extends RefCounted
## Vegetation species lineup: every procedural species at LOD 0/1/2 on a flat lawn, close-ups of
## trees, small props and ground cover, plus a meadow. Pass `--views=a,b` to limit.

const VIEWS := {
	"trees_overview": [Vector3(0, 11, 34), Vector3(0, 5, -10), 62.0],
	"pines": [Vector3(-88, 5, 16), Vector3(-88, 6, 0), 70.0],
	"trees_left": [Vector3(-60, 6, 18), Vector3(-60, 5, 0), 70.0],
	"trees_mid": [Vector3(-6, 6, 18), Vector3(-6, 5, 0), 70.0],
	"trees_right": [Vector3(52, 6, 18), Vector3(52, 5, 0), 70.0],
	"lods": [Vector3(-40, 8, 14), Vector3(-20, 3, -40), 60.0],
	"small": [Vector3(0, 4, 44), Vector3(0, 0.5, 31), 70.0],
	"ground": [Vector3(0, 2.2, 55), Vector3(0, 0.2, 47), 70.0],
	"meadow": [Vector3(3, 1.4, 76), Vector3(0, 0.3, 60), 66.0],
}


func run(p: Playtest) -> void:
	var t0 := Time.get_ticks_msec()
	var scene := await p.load_scene("res://scenes/dev/worldcontent_lineup.tscn")
	p.check(scene != null, "lineup scene loaded")
	if scene == null:
		return
	p.note("meshes built in %.0f ms, scene ready in %d ms" % [VegetationLibrary.build_time_ms, Time.get_ticks_msec() - t0])
	var tris := 0
	for id: StringName in VegetationLibrary.SPECIES:
		var m := VegetationLibrary.get_mesh(id, 0, 0)
		var n := 0
		if m and m.get_surface_count() > 0:
			n = (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		tris += n
		var line := "%s: lod0 %d tris" % [id, n]
		for lod in range(1, VegetationLibrary.lod_count(id)):
			var ml := VegetationLibrary.get_mesh(id, 0, lod)
			if ml and ml.get_surface_count() > 0:
				line += ", lod%d %d" % [lod, (ml.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3]
		p.note(line)
	p.check(tris > 0, "species meshes have geometry")
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--views="):
			only = a.substr(8)
	for v: String in VIEWS:
		if not only.is_empty() and not only.split(",").has(v):
			continue
		var d: Array = VIEWS[v]
		scene.look_from(d[0], d[1], d[2])
		await p.frames(3)
		await p.wait(0.6)
		await p.screenshot("worldcontent_lineup_%s" % v)
