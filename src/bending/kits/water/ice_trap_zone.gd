class_name IceTrapZone
extends Node3D
## Freezing water on the ground (Ice Trap):
##   IceTrapZone.freeze_at(ctx, p, r, hit, stun, attack_id, ability_id) -> frozen targets
##       FREEZE hit on every target standing within r of p (stun x1.5 if SOAKED),
##       an ice prison around each one's legs, frost on the ground.
##   IceTrapZone.arm(ctx, p, r, hit, stun, ability_id, seconds) -> zone
##       nobody was caught: the frozen patch stays armed and catches the first
##       enemy that steps in (then it is spent), melting after `seconds`.

var ctx: BendingContext
var radius := 1.4
var hit: Dictionary = {}
var stun := 2.0
var ability_id: StringName = &""
var armed_time := 4.0
var caught: Array[Node] = []
var _t := 0.0
var _scan := 0.0
var _mark: MeshInstance3D

static var live: Array[IceTrapZone] = []


static func freeze_at(p_ctx: BendingContext, p: Vector3, r: float, h: Dictionary, base_stun: float, attack_id: int, p_ability: StringName) -> Array[Node]:
	var out: Array[Node] = []
	var gy := p.y
	IceFx.shatter(p_ctx.caster, p + Vector3.UP * 0.25, Vector3.UP, 0.9, gy)
	FxDecal.spawn(p_ctx.caster, p, &"frost", r * 1.2)
	FxRing.spawn(p_ctx.caster, p, r * 1.1, Color(0.85, 0.96, 1.0), 0.35, {"opacity": 0.7, "fill": 0.35})
	for t in BendingHits.targets_in_sphere(p_ctx, p + Vector3.UP * 0.6, r + 0.4):
		if not (t is Node3D) or t is BendingConstruct:
			continue
		var tn := t as Node3D
		var flat := Vector2(tn.global_position.x - p.x, tn.global_position.z - p.z).length()
		if flat > r + 0.35 or tn.global_position.y > gy + 1.6:
			continue
		if _freeze_one(p_ctx, tn, h, base_stun, attack_id, p_ability, p):
			out.append(tn)
	return out


static func _freeze_one(p_ctx: BendingContext, t: Node3D, h: Dictionary, base_stun: float, attack_id: int, p_ability: StringName, p: Vector3) -> bool:
	var hd := h.duplicate()
	var st := WaterStatus.freeze_time(t, base_stun)
	hd["stun"] = st
	hd["reaction"] = HitInfo.Reaction.FREEZE
	var status: Dictionary = (hd.get("status", {}) as Dictionary).duplicate()
	status["frozen"] = st
	hd["status"] = status
	var dir := t.global_position - p_ctx.origin()
	var hit := p_ctx.make_hit(hd, dir, attack_id, p_ability)
	hit.origin = p
	hit.position = t.global_position + Vector3.UP * 0.5
	var res := BendingHits.deliver(p_ctx, t, hit)
	if res == Combat.Result.HIT or res == Combat.Result.KILLED:
		if res == Combat.Result.HIT:
			IcePrisonFx.encase(p_ctx.caster, t, st)
		return true
	return false


static func arm(p_ctx: BendingContext, p: Vector3, r: float, h: Dictionary, base_stun: float, p_ability: StringName, seconds: float) -> IceTrapZone:
	var z := IceTrapZone.new()
	z.name = "IceTrapZone"
	z.ctx = p_ctx
	z.radius = r
	z.hit = h
	z.stun = base_stun
	z.ability_id = p_ability
	z.armed_time = seconds
	FxLib.root(p_ctx.caster).add_child(z)
	z.global_position = p
	z._build()
	live.append(z)
	return z


func _build() -> void:
	# A glassy frozen puddle with a few crystal spikes: readable as "don't step here".
	_mark = MeshInstance3D.new()
	_mark.mesh = WaterMeshes.ice_prison(radius * 0.8, 0.45, randi() % 3)
	_mark.material_override = FxDebris.ice_material()
	_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mark.scale = Vector3(1.0, 0.6, 1.0)
	add_child(_mark)


func _physics_process(delta: float) -> void:
	_t += delta
	if ctx == null or not ctx.is_valid() or _t >= armed_time:
		_melt()
		return
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = 0.1
	var p := global_position
	for t in BendingHits.targets_in_sphere(ctx, p + Vector3.UP * 0.6, radius):
		if not (t is Node3D) or t is BendingConstruct or caught.has(t):
			continue
		var tn := t as Node3D
		if Vector2(tn.global_position.x - p.x, tn.global_position.z - p.z).length() > radius or tn.global_position.y > p.y + 1.2:
			continue
		if _freeze_one(ctx, tn, hit, stun, HitInfo.new_attack_id(), ability_id, p):
			caught.append(tn)
			IceFx.shatter(self, p + Vector3.UP * 0.3, Vector3.UP, 0.7, p.y)
			Audio.play_bending(ElementDefs.Element.WATER, &"freeze", p)
			_melt()
			return


func _melt() -> void:
	if is_queued_for_deletion():
		return
	IceFx.shatter(self, global_position + Vector3.UP * 0.2, Vector3.UP, 0.5, global_position.y)
	live.erase(self)
	queue_free()


func _exit_tree() -> void:
	live.erase(self)
