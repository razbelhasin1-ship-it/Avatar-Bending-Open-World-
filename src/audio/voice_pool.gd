class_name VoicePool
extends Node
## Pooled 3D/2D voices with per-category limits and priority stealing.
##
## A request names a category (SoundCatalog.CATEGORIES) and a priority. When
## the category is at its limit, the weakest voice of that category (lowest
## priority, then oldest) is stolen if it is not more important than the new
## sound; otherwise the request is dropped. When the whole pool is busy, the
## weakest non-loop voice anywhere is stolen under the same rule. Loop voices
## (handles from Audio.play_loop) are only ever replaced by other loops.

class Voice:
	## Exactly one of p3 / p2 is set.
	var p3: AudioStreamPlayer3D
	var p2: AudioStreamPlayer
	var sound: StringName = &""
	var category: StringName = &""
	var priority: float = 0.0
	var started_ms: int = 0
	var follow: WeakRef = null
	## Non-zero for looping voices owned by a handle.
	var loop_id: int = 0
	var gain := 1.0
	var target := 1.0
	var rate := 1.0
	var base_db := 0.0
	var stop_when_silent := false

	func is_busy() -> bool:
		if loop_id != 0:
			return true
		return is_playing()

	func is_playing() -> bool:
		return p3.playing if p3 else p2.playing

	func stop() -> void:
		if p3:
			p3.stop()
		else:
			p2.stop()

	func play(stream: AudioStream, from: float = 0.0) -> void:
		if p3:
			p3.stream = stream
			p3.play(from)
		else:
			p2.stream = stream
			p2.play(from)

	func set_volume_db(db: float) -> void:
		if p3:
			p3.volume_db = db
		else:
			p2.volume_db = db

	func set_pitch(pitch: float) -> void:
		if p3:
			p3.pitch_scale = pitch
		else:
			p2.pitch_scale = pitch

	func node() -> Node:
		return p3 if p3 else p2


var voices3d: Array[Voice] = []
var voices2d: Array[Voice] = []
var dropped := 0
var stolen := 0


func setup(count3d: int, count2d: int) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in count3d:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		var v := Voice.new()
		v.p3 = p
		voices3d.append(v)
	for i in count2d:
		var p2 := AudioStreamPlayer.new()
		p2.bus = &"SFX"
		add_child(p2)
		var v2 := Voice.new()
		v2.p2 = p2
		voices2d.append(v2)


## Returns a voice ready to configure + play, or null when the sound loses.
func acquire(positional: bool, sound: StringName, category: StringName, priority: float, is_loop: bool = false) -> Voice:
	var list := voices3d if positional else voices2d
	var limit := int(SoundCatalog.category_info(category)["limit"])
	var same: Array[Voice] = []
	var free_v: Voice = null
	for v in list:
		if v.is_busy():
			if v.category == category:
				same.append(v)
		elif free_v == null:
			free_v = v
	var chosen: Voice = null
	if same.size() >= limit:
		chosen = _weakest(same, is_loop)
		if chosen == null or chosen.priority > priority:
			dropped += 1
			return null
		stolen += 1
	elif free_v != null:
		chosen = free_v
	else:
		var candidates: Array[Voice] = []
		for v in list:
			if v.loop_id == 0 or is_loop:
				candidates.append(v)
		chosen = _weakest(candidates, is_loop)
		if chosen == null or chosen.priority > priority:
			dropped += 1
			return null
		stolen += 1
	_reset(chosen)
	chosen.sound = sound
	chosen.category = category
	chosen.priority = priority
	chosen.started_ms = Time.get_ticks_msec()
	return chosen


func _weakest(list: Array[Voice], allow_loops: bool) -> Voice:
	var best: Voice = null
	for v in list:
		if v.loop_id != 0 and not allow_loops:
			continue
		if best == null or v.priority < best.priority or (is_equal_approx(v.priority, best.priority) and v.started_ms < best.started_ms):
			best = v
	return best


func _reset(v: Voice) -> void:
	if v.is_playing():
		v.stop()
	v.follow = null
	v.loop_id = 0
	v.gain = 1.0
	v.target = 1.0
	v.base_db = 0.0
	v.stop_when_silent = false
	v.sound = &""
	v.category = &""


func release(v: Voice) -> void:
	_reset(v)


func find_loop(loop_id: int) -> Voice:
	if loop_id == 0:
		return null
	for v in voices3d:
		if v.loop_id == loop_id:
			return v
	for v in voices2d:
		if v.loop_id == loop_id:
			return v
	return null


## Number of busy voices, optionally of one category.
func count(category: StringName = &"") -> int:
	var n := 0
	for list: Array[Voice] in [voices3d, voices2d]:
		for v in list:
			if v.is_busy() and (category == &"" or v.category == category):
				n += 1
	return n


## Snapshot of busy voices for debugging and tests.
func snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for list: Array[Voice] in [voices3d, voices2d]:
		for v in list:
			if not v.is_busy():
				continue
			var d := {"sound": v.sound, "category": v.category, "priority": v.priority, "loop": v.loop_id,
				"positional": v.p3 != null}
			if v.p3:
				d["position"] = v.p3.global_position
			out.append(d)
	return out


var _last_usec := 0


func _process(_delta: float) -> void:
	var r := AudioFader.real_delta(_last_usec)
	var delta: float = r[0]
	_last_usec = r[1]
	for list: Array[Voice] in [voices3d, voices2d]:
		for v in list:
			if v.follow != null:
				var n := v.follow.get_ref() as Node3D
				if n != null and is_instance_valid(n) and n.is_inside_tree() and v.p3:
					v.p3.global_position = n.global_position
				else:
					v.follow = null
					if v.loop_id != 0:
						v.target = 0.0
						v.rate = 4.0
						v.stop_when_silent = true
			if v.loop_id != 0:
				v.gain = move_toward(v.gain, v.target, v.rate * delta)
				var amp := sin(v.gain * PI * 0.5)
				v.set_volume_db((linear_to_db(amp) if amp > 0.0001 else -80.0) + v.base_db)
				if v.stop_when_silent and v.gain <= 0.0001:
					_reset(v)
