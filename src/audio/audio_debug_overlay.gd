class_name AudioDebugOverlay
extends CanvasLayer
## Live audio diagnostics (Audio.show_debug_overlay()): bus peak meters, a
## spectrum of the master bus, voices per category against their limits, the
## sounds currently playing, music layering state, ambience layers and the
## active reverb environment. Everything shown is read back from the engine
## (AudioServer peaks, an AudioEffectSpectrumAnalyzer, the VoicePool), so the
## overlay reflects real playback.

const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"Ambience", &"UI"]
const BANDS := 48
const F_MIN := 30.0
const F_MAX := 16000.0
const WIDTH := 430.0

const INK := Color(0.106, 0.082, 0.071, 0.88)
const PARCHMENT := Color(0.937, 0.89, 0.784)
const GOLD := Color(0.906, 0.71, 0.322)
const DIM := Color(0.937, 0.89, 0.784, 0.45)
const CAT_COLORS := {
	&"step": Color(0.72, 0.62, 0.5), &"body": Color(0.93, 0.88, 0.78), &"impact": Color(0.95, 0.42, 0.25),
	&"bending": Color(0.91, 0.71, 0.32), &"creature": Color(0.5, 0.78, 0.42), &"loop": Color(0.4, 0.78, 0.92),
	&"ambient": Color(0.35, 0.7, 0.62), &"ui": Color(1, 1, 1), &"stinger": Color(0.75, 0.55, 0.95),
}

var _panel: Control
var _font: Font
var _analyzer_bus := -1
var _analyzer: AudioEffectSpectrumAnalyzer
var _spectrum := PackedFloat32Array()
var _peaks: Dictionary = {}
var _recent: Array[Dictionary] = []


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var fp := "res://assets/fonts/Marcellus-Regular.ttf"
	_font = load(fp) as Font if ResourceLoader.exists(fp) else ThemeDB.fallback_font
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	_panel.draw.connect(_on_draw)
	_spectrum.resize(BANDS)
	_spectrum.fill(-90.0)
	_analyzer_bus = AudioServer.get_bus_index(&"Master")
	if _analyzer_bus >= 0:
		_analyzer = AudioEffectSpectrumAnalyzer.new()
		_analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
		_analyzer.buffer_length = 0.5
		AudioServer.add_bus_effect(_analyzer_bus, _analyzer)


func _exit_tree() -> void:
	if _analyzer_bus >= 0 and _analyzer:
		for i in AudioServer.get_bus_effect_count(_analyzer_bus):
			if AudioServer.get_bus_effect(_analyzer_bus, i) == _analyzer:
				AudioServer.remove_bus_effect(_analyzer_bus, i)
				break


## Smoothed spectrum in dB (BANDS log-spaced bands), exposed for tests.
func spectrum_db() -> PackedFloat32Array:
	return _spectrum


func _process(delta: float) -> void:
	for b: StringName in BUSES:
		var idx := AudioServer.get_bus_index(b)
		if idx < 0:
			continue
		var pk := maxf(AudioServer.get_bus_peak_volume_left_db(idx, 0), AudioServer.get_bus_peak_volume_right_db(idx, 0))
		var prev: float = _peaks.get(b, -80.0)
		_peaks[b] = pk if pk > prev else maxf(pk, prev - 30.0 * delta)
	var inst := _analyzer_instance()
	if inst:
		for i in BANDS:
			var f0 := F_MIN * pow(F_MAX / F_MIN, float(i) / BANDS)
			var f1 := F_MIN * pow(F_MAX / F_MIN, float(i + 1) / BANDS)
			var m := inst.get_magnitude_for_frequency_range(f0, f1, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX)
			var d := linear_to_db(maxf(maxf(m.x, m.y), 0.000001))
			_spectrum[i] = d if d > _spectrum[i] else maxf(d, _spectrum[i] - 40.0 * delta)
	var now := Time.get_ticks_msec()
	for v: Dictionary in Audio.active_voices():
		var found := false
		for r in _recent:
			if r["sound"] == v["sound"] and now - int(r["t"]) < 400:
				found = true
				r["t"] = now
				break
		if not found:
			_recent.push_front({"sound": v["sound"], "category": v["category"], "t": now})
	while _recent.size() > 9:
		_recent.pop_back()
	_panel.queue_redraw()


func _analyzer_instance() -> AudioEffectSpectrumAnalyzerInstance:
	if _analyzer_bus < 0 or _analyzer == null:
		return null
	for i in AudioServer.get_bus_effect_count(_analyzer_bus):
		if AudioServer.get_bus_effect(_analyzer_bus, i) == _analyzer:
			return AudioServer.get_bus_effect_instance(_analyzer_bus, i, 0) as AudioEffectSpectrumAnalyzerInstance
	return null


func _text(pos: Vector2, s: String, size: int = 15, color: Color = PARCHMENT) -> void:
	_panel.draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _on_draw() -> void:
	var vp := _panel.get_viewport_rect().size
	var x0 := vp.x - WIDTH - 18.0
	var y := 18.0
	var h := vp.y - 36.0
	_panel.draw_rect(Rect2(x0, y, WIDTH, h), INK)
	_panel.draw_rect(Rect2(x0, y, WIDTH, h), GOLD, false, 1.5)
	var x := x0 + 16.0
	var w := WIDTH - 32.0
	y += 30.0
	_text(Vector2(x, y), "AUDIO", 22, GOLD)
	_text(Vector2(x + 90.0, y), "env: %s" % Audio.current_environment(), 15, PARCHMENT)
	_text(Vector2(x + 230.0, y), "voices %d / %d" % [Audio.voice_count(), Audio.POOL_3D + Audio.POOL_2D], 15, PARCHMENT)
	# Music state
	y += 28.0
	var combat := Audio.is_in_combat()
	_text(Vector2(x, y), "music  %s" % (Audio.active_music() if Audio.active_music() != &"" else "-"), 15, GOLD if combat else PARCHMENT)
	_text(Vector2(x + 270.0, y), "COMBAT" if combat else "explore", 14, Color(0.95, 0.42, 0.25) if combat else DIM)
	for st: Dictionary in Audio.music.voice_states():
		if st["track"] == &"":
			continue
		y += 18.0
		_text(Vector2(x + 10.0, y), String(st["track"]).trim_prefix("music_"), 12, DIM)
		_panel.draw_rect(Rect2(x + 150.0, y - 9.0, (w - 150.0) * float(st["gain"]), 6.0), GOLD if not st["paused"] else DIM)
	# Bus meters
	y += 30.0
	_text(Vector2(x, y), "buses (peak dBFS)", 13, DIM)
	for b: StringName in BUSES:
		y += 20.0
		var db: float = _peaks.get(b, -80.0)
		var t := clampf((db + 60.0) / 60.0, 0.0, 1.0)
		_text(Vector2(x, y), String(b), 13, PARCHMENT)
		_panel.draw_rect(Rect2(x + 90.0, y - 11.0, w - 150.0, 10.0), Color(1, 1, 1, 0.07))
		var col := GOLD if db < -6.0 else Color(0.95, 0.42, 0.25)
		_panel.draw_rect(Rect2(x + 90.0, y - 11.0, (w - 150.0) * t, 10.0), col)
		_text(Vector2(x + w - 52.0, y), "%5.1f" % db if db > -79.0 else "  -inf", 12, DIM)
	# Spectrum
	y += 30.0
	_text(Vector2(x, y), "spectrum (master)", 13, DIM)
	y += 8.0
	var sh := 90.0
	_panel.draw_rect(Rect2(x, y, w, sh), Color(1, 1, 1, 0.05))
	var bw := w / BANDS
	for i in BANDS:
		var t2 := clampf((_spectrum[i] + 80.0) / 70.0, 0.0, 1.0)
		var bh := sh * t2
		var c := GOLD.lerp(Color(0.4, 0.78, 0.92), float(i) / BANDS)
		_panel.draw_rect(Rect2(x + i * bw + 1.0, y + sh - bh, bw - 2.0, bh), c)
	for fl: float in [100.0, 1000.0, 10000.0]:
		var fx := x + w * log(fl / F_MIN) / log(F_MAX / F_MIN)
		_text(Vector2(fx - 10.0, y + sh + 13.0), "%dk" % int(fl / 1000.0) if fl >= 1000.0 else "%d" % int(fl), 10, DIM)
	y += sh + 34.0
	# Categories
	_text(Vector2(x, y), "voices per category", 13, DIM)
	for cat: StringName in SoundCatalog.CATEGORIES:
		y += 18.0
		var n := Audio.voice_count(cat)
		var lim := int(SoundCatalog.CATEGORIES[cat]["limit"])
		var cc: Color = CAT_COLORS.get(cat, PARCHMENT)
		_text(Vector2(x, y), String(cat), 13, cc)
		for k in lim:
			var r := Rect2(x + 90.0 + k * 17.0, y - 10.0, 13.0, 9.0)
			_panel.draw_rect(r, cc if k < n else Color(1, 1, 1, 0.08))
	# Recent sounds
	y += 28.0
	_text(Vector2(x, y), "recent sounds", 13, DIM)
	for r: Dictionary in _recent:
		y += 17.0
		if y > vp.y - 70.0:
			break
		_text(Vector2(x + 10.0, y), String(r["sound"]), 13, CAT_COLORS.get(r["category"], PARCHMENT))
	# Ambience
	var amb := Audio.ambience_layers()
	var parts: Array[String] = []
	for k: StringName in amb:
		parts.append("%s: %s" % [k, String(amb[k]).trim_prefix("amb_")])
	_text(Vector2(x, vp.y - 46.0), "ambience  " + (", ".join(parts) if not parts.is_empty() else "-"), 13, PARCHMENT)
