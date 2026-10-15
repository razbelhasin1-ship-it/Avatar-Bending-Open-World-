class_name MusicDirector
extends Node
## Music state machine owned by the Audio autoload.
##
## Three layers decide what plays, highest first:
##   override  - cinematics / special moments (set_override)
##   combat    - music_combat while Events.combat_state_changed(true) is active
##   base      - menu / regional exploration track (Audio.play_music)
## Switching layers crossfades; a track that fades out is paused, not stopped,
## so leaving combat resumes the regional theme where it was (for up to
## `resume_window` seconds). Leaving combat waits `combat_exit_delay` seconds so
## short lulls in a fight do not bounce the music.

signal active_track_changed(track: StringName)

const MAX_VOICES := 3

var combat_track: StringName = &"music_combat"
var combat_exit_delay := 4.0
var combat_fade_in := 1.0
var combat_fade_out := 3.0
## Paused tracks resume from their position if re-entered within this many seconds.
var resume_window := 60.0
## Combat restarts from the top unless it is re-entered within this window.
var combat_resume_window := 10.0

var _resolve: Callable
var _faders: Array[AudioFader] = []
var _base: StringName = &""
var _base_db := 0.0
var _base_fade := 2.0
var _override: StringName = &""
var _override_db := 0.0
var _in_combat := false
var _exit_timer := -1.0
var _active: StringName = &""
var _duck_db := 0.0
var _duck_target := 0.0
var _duck_left := 0.0


## `resolver(track: StringName) -> AudioStream` (Audio.get_stream on the music dir).
func setup(resolver: Callable) -> void:
	_resolve = resolver
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.volume_db = AudioFader.SILENT_DB
		add_child(p)
		_faders.append(AudioFader.new(p))


func set_base(track: StringName, fade: float = 2.0, volume_db: float = 0.0) -> void:
	_base = track
	_base_db = volume_db
	_base_fade = fade
	_update(fade)


func base_track() -> StringName:
	return _base


func set_override(track: StringName, fade: float = 1.5, volume_db: float = 0.0) -> void:
	_override = track
	_override_db = volume_db
	_update(fade)


## Combat layering. Entering is immediate; leaving waits combat_exit_delay.
func set_combat(on: bool) -> void:
	if on:
		_exit_timer = -1.0
		if not _in_combat:
			_in_combat = true
			_update(combat_fade_in)
	elif _in_combat and _exit_timer < 0.0:
		_exit_timer = combat_exit_delay


## Forces combat off immediately (returning to menu, death screen...).
func reset_combat() -> void:
	_in_combat = false
	_exit_timer = -1.0
	_update(1.0)


func is_in_combat() -> bool:
	return _in_combat


## The track currently audible (after layering).
func active_track() -> StringName:
	return _active


## Temporarily lowers the music (stingers, dialogue) by `db` for `seconds`.
func duck(db: float, seconds: float) -> void:
	_duck_target = minf(_duck_target, -absf(db))
	_duck_left = maxf(_duck_left, seconds)


## Debug/test view of every music voice.
func voice_states() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in _faders:
		out.append({"track": f.key, "gain": f.gain, "target": f.target, "playing": f.player.playing,
			"paused": f.player.stream_paused, "position": f.player.get_playback_position() if f.player.playing else 0.0})
	return out


func _desired() -> StringName:
	if _override != &"":
		return _override
	if _in_combat and combat_track != &"":
		return combat_track
	return _base


func _desired_db() -> float:
	if _override != &"":
		return _override_db
	if _in_combat:
		return _base_db
	return _base_db


func _update(fade: float) -> void:
	var want := _desired()
	if want == _active:
		var cur := _fader_for(want)
		if cur:
			cur.base_db = _desired_db()
		return
	_active = want
	for f in _faders:
		if f.key != want:
			f.fade_to(0.0, combat_fade_out if f.key == combat_track else fade)
	if want != &"":
		var f := _fader_for(want)
		if f == null:
			f = _claim()
			var stream: AudioStream = _resolve.call(want) if _resolve.is_valid() else null
			if stream == null:
				f.key = &""
				active_track_changed.emit(want)
				return
			f.key = want
			f.player.stream = stream
			f.player.stream_paused = false
			f.gain = 0.0
			f.player.volume_db = AudioFader.SILENT_DB
			f.player.play()
		else:
			var window := combat_resume_window if want == combat_track else resume_window
			if f.player.playing and not f.player.stream_paused:
				pass  # still fading out: simply fade back in from where it is
			elif f.player.stream_paused and f.idle <= window:
				f.player.stream_paused = false
			else:
				f.player.stream_paused = false
				f.player.play()
		f.base_db = _desired_db()
		f.fade_to(1.0, fade)
	active_track_changed.emit(want)


func _fader_for(track: StringName) -> AudioFader:
	if track == &"":
		return null
	for f in _faders:
		if f.key == track:
			return f
	return null


## A free fader, or the one that has been silent the longest.
func _claim() -> AudioFader:
	var best: AudioFader = null
	for f in _faders:
		if f.key == &"" or not f.player.playing:
			return f
		if f.is_silent() and (best == null or f.idle > best.idle):
			best = f
	if best == null:
		best = _faders[0]
		for f in _faders:
			if f.gain < best.gain:
				best = f
	best.player.stop()
	best.key = &""
	return best


func _process(delta: float) -> void:
	if _exit_timer >= 0.0:
		_exit_timer -= delta
		if _exit_timer < 0.0:
			_in_combat = false
			_update(_base_fade)
	if _duck_left > 0.0:
		_duck_left -= delta
		_duck_db = move_toward(_duck_db, _duck_target, 40.0 * delta)
	else:
		_duck_target = 0.0
		_duck_db = move_toward(_duck_db, 0.0, 8.0 * delta)
	for f in _faders:
		if f.key == &"":
			continue
		f.step(delta, _duck_db)
		if f.is_silent() and f.player.playing and not f.player.stream_paused:
			f.player.stream_paused = true
		if f.is_silent() and f.idle > resume_window:
			f.player.stop()
			f.player.stream_paused = false
			f.key = &""
