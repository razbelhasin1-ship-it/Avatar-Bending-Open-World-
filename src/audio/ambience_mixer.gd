class_name AmbienceMixer
extends Node
## Layered ambience beds on the Ambience bus. Each layer (&"base" region bed,
## &"weather", &"night", &"local" ...) holds one looping sound and crossfades
## between two players when its sound changes.

var _resolve: Callable
var _layers: Dictionary = {}   # layer -> {"a": AudioFader, "b": AudioFader, "cur": AudioFader, "name": StringName}


## `resolver(name: StringName) -> AudioStream` (already loop-enabled).
func setup(resolver: Callable) -> void:
	_resolve = resolver
	process_mode = Node.PROCESS_MODE_ALWAYS


## Sets the sound of a layer (&"" fades the layer out).
func set_layer(layer: StringName, sound_name: StringName, volume_db: float = 0.0, fade: float = 2.0) -> void:
	var L: Dictionary = _layer(layer)
	var cur: AudioFader = L["cur"]
	if sound_name == L["name"]:
		cur.base_db = volume_db
		if sound_name != &"":
			cur.fade_to(1.0, fade)
		return
	L["name"] = sound_name
	cur.fade_to(0.0, fade)
	if sound_name == &"":
		return
	var stream: AudioStream = _resolve.call(sound_name) if _resolve.is_valid() else null
	if stream == null:
		return
	var nxt: AudioFader = L["b"] if cur == L["a"] else L["a"]
	nxt.player.stop()
	nxt.key = sound_name
	nxt.player.stream = stream
	nxt.base_db = volume_db
	nxt.gain = 0.0
	nxt.player.volume_db = AudioFader.SILENT_DB
	# Start loops at a random point so repeated visits do not always sound identical.
	var length := stream.get_length()
	nxt.player.play(randf() * length * 0.9 if length > 4.0 else 0.0)
	nxt.fade_to(1.0, fade)
	L["cur"] = nxt


func layer_sound(layer: StringName) -> StringName:
	return _layers[layer]["name"] if _layers.has(layer) else &""


## {layer: sound} for every non-empty layer.
func layers() -> Dictionary:
	var out := {}
	for k: StringName in _layers:
		if _layers[k]["name"] != &"":
			out[k] = _layers[k]["name"]
	return out


func clear(fade: float = 1.5) -> void:
	for k: StringName in _layers.keys():
		set_layer(k, &"", 0.0, fade)


func _layer(layer: StringName) -> Dictionary:
	if not _layers.has(layer):
		var a := AudioFader.new(_make_player())
		var b := AudioFader.new(_make_player())
		_layers[layer] = {"a": a, "b": b, "cur": a, "name": &""}
	return _layers[layer]


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Ambience"
	p.volume_db = AudioFader.SILENT_DB
	add_child(p)
	return p


var _last_usec := 0


func _process(_delta: float) -> void:
	var r := AudioFader.real_delta(_last_usec)
	var delta: float = r[0]
	_last_usec = r[1]
	for k: StringName in _layers:
		var L: Dictionary = _layers[k]
		for f: AudioFader in [L["a"], L["b"]]:
			if not f.player.playing:
				continue
			f.step(delta)
			if f.is_silent():
				f.player.stop()
				f.key = &""
