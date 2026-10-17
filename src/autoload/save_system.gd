extends Node
## Save/load (autoload "SaveSystem").
##
## Saves are JSON files in user://saves/. Before serializing, every node in
## group &"persist" gets `write_save_state()` called so live objects (player
## position, companion, world objects) push their state into GameState.
## Writes are atomic (temp file + rename) so a crash never corrupts a slot.
## Test runs (`-- --test`) use a separate folder so they never touch real saves.

const SAVE_DIR := "user://saves"
const TEST_SAVE_DIR := "user://saves_test"
const AUTOSAVE_SLOT := 0
const MAX_SLOTS := 4
const GROUP_PERSIST := &"persist"

var autosave_interval := 180.0
## Active save folder (SAVE_DIR, or TEST_SAVE_DIR during automated test runs).
var save_dir: String = SAVE_DIR
var _autosave_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_cmdline_user_args().has("--test"):
		save_dir = TEST_SAVE_DIR
	DirAccess.make_dir_recursive_absolute(save_dir)


func _process(delta: float) -> void:
	if not can_save() or get_tree().paused:
		return
	_autosave_timer += delta
	if _autosave_timer >= autosave_interval:
		_autosave_timer = 0.0
		save_game(AUTOSAVE_SLOT)


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [save_dir, slot]


## Saving is allowed only in a live adventure (not tutorial / menus).
func can_save() -> bool:
	return GameState.has_element() and not GameState.is_tutorial and get_tree().get_nodes_in_group(&"player").size() > 0


func save_game(slot: int = AUTOSAVE_SLOT) -> bool:
	if not GameState.has_element() or GameState.is_tutorial:
		return false
	get_tree().call_group(GROUP_PERSIST, "write_save_state")
	var data := GameState.to_dict()
	data["saved_at"] = Time.get_datetime_string_from_system(false, true)
	data["saved_unix"] = Time.get_unix_time_from_system()
	data["engine"] = Engine.get_version_info().get("string", "")
	var json := JSON.stringify(data, "\t")
	var tmp := slot_path(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SaveSystem: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(json)
	var werr := f.get_error()
	f.close()
	# Only a temp file that reads back complete may replace the slot: a full disk / storage quota
	# (phones, a browser's IndexedDB) used to leave a truncated temp file that then replaced the
	# good save - the journey was lost (wave 4 bug hunt, docs/qa/bughunt_world.md).
	if werr != OK or FileAccess.get_file_as_string(tmp) != json:
		push_warning("SaveSystem: the save did not reach the disk intact (%s); the previous save is kept" % error_string(werr))
		DirAccess.remove_absolute(tmp)
		return false
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return false
	var file := slot_path(slot).get_file()
	# The previous save stays as a backup (read_slot falls back to it if the slot is ever unreadable).
	if dir.file_exists(file):
		DirAccess.copy_absolute(slot_path(slot), slot_path(slot) + ".bak")
	# rename() replaces the old slot atomically where the platform allows it; remove + rename
	# only when it refuses (a crash in between still leaves the .tmp / .bak for read_slot).
	var err := dir.rename(tmp.get_file(), file)
	if err != OK and dir.file_exists(file):
		dir.remove(file)
		err = dir.rename(tmp.get_file(), file)
	if err != OK:
		push_warning("SaveSystem: rename failed (%s)" % error_string(err))
		return false
	_autosave_timer = 0.0
	Events.game_saved.emit(slot)
	return true


## A slot exists (or can be recovered from its temp / backup file, see read_slot).
func has_save(slot: int = AUTOSAVE_SLOT) -> bool:
	var path := slot_path(slot)
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".tmp") or FileAccess.file_exists(path + ".bak")


func has_any_save() -> bool:
	for i in MAX_SLOTS:
		if has_save(i):
			return true
	return false


## Most recently written slot, or -1. Uses the sub-second "saved_unix" stamp
## stored in the save (file mtimes only have 1 s resolution).
func latest_slot() -> int:
	var best := -1
	var best_time := -1.0
	for i in MAX_SLOTS:
		if not has_save(i):
			continue
		var d := read_slot(i)
		if d.is_empty():
			continue
		var t := _num(d.get("saved_unix"), float(FileAccess.get_modified_time(slot_path(i))))
		if t > best_time:
			best_time = t
			best = i
	return best


## The slot's data ({} if missing / unreadable). An unreadable or missing slot file falls back to
## a complete temp file (a crash between writing and renaming) and then to the previous save
## (`.bak`), so one damaged file never costs the whole journey.
func read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	for p: String in [path, path + ".tmp", path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(p)) != OK or not (json.data is Dictionary) \
				or not ElementDefs.is_valid(int(_num((json.data as Dictionary).get("element"), -1))):
			push_warning("SaveSystem: %s is corrupt" % p.get_file())
			continue
		if p != path:
			push_warning("SaveSystem: slot %d recovered from %s" % [slot, p.get_file()])
		return _migrate(json.data)
	return {}


static func _num(v: Variant, fallback: float) -> float:
	return float(v) if (v is int or v is float) else fallback


## Summary for menus: element, level, region, play time, saved_at. Empty if none/invalid.
func get_save_info(slot: int) -> Dictionary:
	var d := read_slot(slot)
	if d.is_empty() or not ElementDefs.is_valid(int(_num(d.get("element"), -1))):
		return {}
	return {
		"slot": slot,
		"element": int(_num(d.get("element"), -1)),
		"level": int(_num(d.get("level"), 1)),
		"region": String(d.get("region")) if d.get("region") is String else "",
		"play_time": _num(d.get("play_time"), 0.0),
		"saved_at": String(d.get("saved_at")) if d.get("saved_at") is String else "",
	}


## Loads a slot into GameState. Returns false if missing/invalid (GameState untouched).
func load_game(slot: int = AUTOSAVE_SLOT) -> bool:
	var d := read_slot(slot)
	if d.is_empty():
		return false
	var backup := GameState.to_dict()
	if not GameState.from_dict(d):
		GameState.from_dict(backup)
		return false
	_autosave_timer = 0.0
	Events.game_loaded.emit(slot)
	return true


func delete_save(slot: int) -> void:
	for p: String in [slot_path(slot), slot_path(slot) + ".tmp", slot_path(slot) + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _migrate(d: Dictionary) -> Dictionary:
	var v := int(_num(d.get("version"), 0))
	if v < 1:
		# Pre-versioned saves: nothing structural changed yet.
		d["version"] = 1
	return d
