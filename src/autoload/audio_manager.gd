extends Node
## Audio playback (autoload "Audio").
##
## Sound files live in res://assets/audio/sfx/<name>.wav (or .ogg), with optional
## variants <name>_1 .. <name>_6 picked at random. Music lives in
## res://assets/audio/music/<track>.ogg|.wav. Missing sounds are skipped with a
## one-time warning so gameplay never depends on an audio file existing.
##
## Buses: Master > Music, SFX, Ambience, UI, Voice (created by Settings).

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const EXTS := ["wav", "ogg", "mp3"]
const POOL_3D := 40
const POOL_2D := 12

var _cache: Dictionary = {}          # name -> Array[AudioStream]
var _missing: Dictionary = {}
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current: AudioStreamPlayer
var _music_track: StringName = &""
var _ambience: AudioStreamPlayer
var _ambience_name: StringName = &""
var _last_played: Dictionary = {}    # name -> msec, for spam protection


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.ensure_audio_buses()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 6.0
		p.max_distance = 120.0
		add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		p2.bus = &"SFX"
		add_child(p2)
		_pool2d.append(p2)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_music_current = _music_a
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = &"Ambience"
	add_child(_ambience)


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Music"
	add_child(p)
	return p


## Returns a stream for `sound_name` (random variant) or null.
func get_stream(sound_name: StringName, dir: String = SFX_DIR) -> AudioStream:
	var key := dir + String(sound_name)
	if not _cache.has(key):
		var list: Array[AudioStream] = []
		var base := _find(dir + String(sound_name))
		if base:
			list.append(base)
		for i in range(1, 7):
			var v := _find("%s%s_%d" % [dir, sound_name, i])
			if v:
				list.append(v)
		_cache[key] = list
	var arr: Array = _cache[key]
	if arr.is_empty():
		if not _missing.has(key):
			_missing[key] = true
			if OS.is_debug_build():
				print_verbose("Audio: missing sound '%s'" % key)
		return null
	return arr[randi() % arr.size()]


func has_sound(sound_name: StringName) -> bool:
	return get_stream(sound_name) != null


func _find(path_no_ext: String) -> AudioStream:
	for ext: String in EXTS:
		var p := "%s.%s" % [path_no_ext, ext]
		if ResourceLoader.exists(p):
			return load(p) as AudioStream
	return null


## Plays a positional sound. Returns the player (or null if missing/throttled).
func play_sfx(sound_name: StringName, position: Vector3, volume_db: float = 0.0, pitch_variance: float = 0.08, max_distance: float = 120.0) -> AudioStreamPlayer3D:
	var stream := get_stream(sound_name)
	if stream == null or _throttled(sound_name):
		return null
	var p := _free_3d()
	p.stream = stream
	p.global_position = position
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	p.play()
	return p


## Plays a non-positional sound (UI, player-centric stingers).
func play_2d(sound_name: StringName, volume_db: float = 0.0, bus: StringName = &"SFX", pitch_variance: float = 0.0) -> AudioStreamPlayer:
	var stream := get_stream(sound_name)
	if stream == null or _throttled(sound_name):
		return null
	var p := _free_2d()
	p.stream = stream
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	p.play()
	return p


func play_ui(sound_name: StringName, volume_db: float = 0.0) -> void:
	play_2d(sound_name, volume_db, &"UI")


## Crossfades to a music track (looping). Pass &"" to fade out.
func play_music(track: StringName, fade: float = 2.0, volume_db: float = 0.0) -> void:
	if track == _music_track:
		return
	_music_track = track
	var old := _music_current
	var new_player := _music_b if _music_current == _music_a else _music_a
	if old.playing:
		var t := create_tween()
		t.tween_property(old, "volume_db", -60.0, fade)
		t.tween_callback(old.stop)
	if track == &"":
		return
	var stream := get_stream(track, MUSIC_DIR)
	if stream == null:
		return
	_set_loop(stream)
	new_player.stream = stream
	new_player.volume_db = -60.0
	new_player.play()
	create_tween().tween_property(new_player, "volume_db", volume_db, fade)
	_music_current = new_player


func current_music() -> StringName:
	return _music_track


## Loops an ambience bed (wind, city, waves...). Pass &"" to stop.
func set_ambience(ambience_name: StringName, volume_db: float = 0.0, fade: float = 2.0) -> void:
	if ambience_name == _ambience_name:
		return
	_ambience_name = ambience_name
	var t := create_tween()
	t.tween_property(_ambience, "volume_db", -60.0, fade * 0.5)
	if ambience_name == &"":
		t.tween_callback(_ambience.stop)
		return
	var stream := get_stream(ambience_name)
	if stream == null:
		return
	_set_loop(stream)
	t.tween_callback(func() -> void:
		_ambience.stream = stream
		_ambience.play())
	t.tween_property(_ambience, "volume_db", volume_db, fade * 0.5)


func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var w := stream as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


func _throttled(sound_name: StringName) -> bool:
	var now := Time.get_ticks_msec()
	var last: int = _last_played.get(sound_name, -1000)
	if now - last < 25:
		return true
	_last_played[sound_name] = now
	return false


func _free_3d() -> AudioStreamPlayer3D:
	for p in _pool3d:
		if not p.playing:
			return p
	# Steal the oldest (first) player.
	var p0 := _pool3d.pop_front() as AudioStreamPlayer3D
	_pool3d.append(p0)
	p0.stop()
	return p0


func _free_2d() -> AudioStreamPlayer:
	for p in _pool2d:
		if not p.playing:
			return p
	var p0 := _pool2d.pop_front() as AudioStreamPlayer
	_pool2d.append(p0)
	p0.stop()
	return p0
