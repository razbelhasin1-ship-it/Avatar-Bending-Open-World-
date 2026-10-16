class_name FxFlash
extends OmniLight3D
## Short-lived pooled point light (fire blasts, impacts, charge glow). Capped:
## at most FxLib.MAX_LIGHTS (fewer on low/mobile effects) exist at once; the
## oldest is recycled. Lights never cast shadows.
##
##   FxFlash.spawn(self, pos, Color(1, 0.6, 0.2), 3.0, 0.25)
##   var l := FxFlash.attach(self, fireball_node, color, 2.0)   # follows, call fade_out()

var t := 0.0
var duration := 0.25
var peak := 2.0
var follow: Node3D = null
var sustained := false


static func spawn(from: Node, pos: Vector3, color: Color, energy: float = 2.5, duration_s: float = 0.25, range_m: float = 6.0) -> FxFlash:
	if FxLib.tier() == 0 and FxLib.alive_count(&"flash") >= 1:
		return null
	FxLib.set_cap(&"flash", FxLib.MAX_LIGHTS)
	var l := FxLib.take(from, &"flash", FxFlash._make) as FxFlash
	l.global_position = pos
	l.light_color = color
	l.peak = energy
	l.light_energy = energy
	l.omni_range = range_m
	l.duration = maxf(duration_s, 0.02)
	l.t = 0.0
	l.follow = null
	l.sustained = false
	return l


## A light that follows `node` until fade_out() (projectiles, charging hands).
static func attach(from: Node, node: Node3D, color: Color, energy: float = 2.0, range_m: float = 5.0) -> FxFlash:
	var l := spawn(from, node.global_position, color, energy, 0.3, range_m)
	if l:
		l.follow = node
		l.sustained = true
	return l


static func _make() -> FxFlash:
	var l := FxFlash.new()
	l.name = "Flash"
	l.shadow_enabled = false
	l.omni_attenuation = 1.6
	l.light_specular = 0.3
	return l


func fade_out(duration_s: float = 0.2) -> void:
	sustained = false
	follow = null
	t = 0.0
	duration = maxf(duration_s, 0.02)
	peak = light_energy


func set_energy(e: float) -> void:
	peak = e
	light_energy = e


func fx_reset() -> void:
	sustained = false
	follow = null
	t = duration


func _process(delta: float) -> void:
	if sustained:
		if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
			global_position = follow.global_position
		else:
			fade_out(0.15)
		return
	t += delta
	var p := clampf(t / duration, 0.0, 1.0)
	light_energy = peak * (1.0 - p) * (1.0 - p)
	if p >= 1.0:
		FxLib.release(self)
