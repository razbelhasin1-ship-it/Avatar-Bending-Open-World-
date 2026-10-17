class_name MapOverlay
extends Control
## Everything drawn on top of the parchment map (MapCanvas): hand-lettered region and sea
## names with the nation's brush seal, ferry routes (dashed, with a boat glyph), places
## (cities always lettered; villages, ports and points of interest once discovered, faint
## dotted "?" marks before), fast-travel badges, quest objectives and quest givers, the
## companion, the player arrow, a pin (e.g. a bending master) and the controller reticle.
## Also answers what can be picked where (MapCanvas.pick).

const INK := Color("2b1d14")
const INK_SOFT := Color(0.17, 0.11, 0.08, 0.55)
const HALO := Color(0.95, 0.91, 0.80, 0.85)
const ROUTE := Color(0.13, 0.30, 0.38, 0.75)
const QUEST := Color("d9a43a")
const GIVER := Color("b23a2c")

var canvas: MapCanvas
## Quest markers (Quests.map_markers()), refreshed by the page.
var quest_markers: Array[Dictionary] = []
## Optional pin: {"position": Vector3, "label": String}
var pin: Dictionary = {}
var player: Node3D = null
var companion: Node3D = null
var show_routes := true

var _t := 0.0
var _pickables: Array[Dictionary] = []
var _pick_frame := -1
## Label requests of this frame: [{rect, prio, text, font, fs, color, pos}] (placed without overlaps).
var _labels: Array[Dictionary] = []
var _obstacles: Array[Rect2] = []
## Cities whose name the region lettering already shows at this zoom.
var _lettered_cities: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()


func _icon(name: String) -> Texture2D:
	return UiTheme.icon(name)


func _zoom_k() -> float:
	return pow(canvas.zoom, 0.32)


## Markers that can be picked, with their screen position (cached per frame).
func pickables() -> Array[Dictionary]:
	var f := Engine.get_process_frames()
	if f == _pick_frame:
		return _pickables
	_pick_frame = f
	_pickables.clear()
	var view := Rect2(Vector2(-40, -40), canvas.size + Vector2(80, 80))
	for p in MapModel.places():
		var known := MapModel.is_known(p)
		if not known and p["kind"] != &"poi" and p["kind"] != &"city":
			continue
		if p["kind"] == &"port" and not known:
			continue
		var s := canvas.world_to_local(p["position"])
		if not view.has_point(s):
			continue
		var e := p.duplicate()
		e["screen"] = s
		e["known"] = known
		_pickables.append(e)
	for m in quest_markers:
		var s2 := canvas.world_to_local(m["position"])
		if view.has_point(s2):
			_pickables.append({"id": m["quest"], "kind": &"quest", "marker": m["kind"], "objective": m.get("objective", &""),
				"name": String(m.get("text", "")), "position": m["position"], "screen": s2, "tracked": bool(m.get("tracked", false))})
	if not pin.is_empty():
		_pickables.append({"id": &"pin", "kind": &"pin", "name": String(pin.get("label", "")), "position": pin["position"],
			"screen": canvas.world_to_local(pin["position"])})
	return _pickables


func _draw() -> void:
	if canvas == null:
		return
	var zk := _zoom_k()
	_labels.clear()
	_obstacles.clear()
	_lettered_cities.clear()
	if show_routes:
		_draw_routes()
	_draw_lettering(zk)
	var items := pickables()
	var hover_id: StringName = canvas.hover.get("id", &"")
	var sel_id: StringName = canvas.selected.get("id", &"")
	# places: unknown marks first, then known, then cities on top
	for pass_i in 3:
		for e in items:
			var kind: StringName = e["kind"]
			if kind == &"quest" or kind == &"pin":
				continue
			var known := bool(e["known"])
			var order := 2 if kind == &"city" else (1 if known else 0)
			if order != pass_i:
				continue
			var hot: bool = e["id"] == hover_id or e["id"] == sel_id
			_draw_place(e, known, hot, zk)
	for e in items:
		if e["kind"] == &"quest":
			var qhot: bool = e["id"] == hover_id and e.get("objective", &"") == canvas.hover.get("objective", &"")
			# quest givers far away clutter the overview: shown from a closer zoom (or hovered)
			if e.get("marker") == &"giver" and canvas.zoom < 1.8 and not qhot:
				continue
			_draw_quest(e, qhot)
	if not pin.is_empty():
		_draw_pin()
	_draw_companion()
	_draw_player()
	_flush_labels()
	if canvas.cursor_mode:
		_draw_reticle()
	_draw_scale_bar()


## Queues a centred label under/over a marker; `prio` 0 = always shown, higher = dropped first
## when it would overlap a label already placed.
func _queue_label(anchor: Vector2, below: float, text: String, font: Font, fs: int, col: Color, prio: int) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := anchor + Vector2(-w * 0.5, below + fs * 0.8)
	_labels.append({"text": text, "font": font, "fs": fs, "color": col, "prio": prio, "pos": base, "w": w,
		"alt": anchor + Vector2(-w * 0.5, -below - fs * 0.35)})


func _flush_labels() -> void:
	_labels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["prio"]) < int(b["prio"]))
	var placed: Array[Rect2] = _obstacles.duplicate()
	for l in _labels:
		var fs := int(l["fs"])
		var w := float(l["w"])
		var chosen := Vector2.INF
		for cand: Vector2 in [l["pos"], l["alt"]]:
			var r := Rect2(cand + Vector2(-4, -fs * 0.85), Vector2(w + 8, fs * 1.15))
			var hit := false
			if int(l["prio"]) > 0:
				for q in placed:
					if q.intersects(r):
						hit = true
						break
			if not hit:
				chosen = cand
				placed.append(r)
				break
		if chosen.is_finite():
			_halo_text(chosen, l["text"], l["font"], fs, l["color"], HALO, 6)


# --- lettering -----------------------------------------------------------------------------------

func _halo_text(pos: Vector2, text: String, font: Font, fs: int, col: Color, halo: Color = HALO, outline: int = 6) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, halo)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_lettering(zk: float) -> void:
	for l: Dictionary in MapModel.LETTERING:
		var kind: StringName = l["kind"]
		var s := canvas.uv_to_local(MapModel.xz_to_uv(l["pos"]))
		var base := float(l["size"])
		var fs := int(clampf(base * 0.62 * zk, 14.0, base * 1.25))
		# geography lettering belongs to the overview: it fades out as you zoom into places
		var a := clampf(1.0 - (canvas.zoom - 1.35) / 1.1, 0.0, 1.0)
		if kind == &"sea":
			a = clampf(1.0 - (canvas.zoom - 2.2) / 1.4, 0.25, 1.0)
		if a <= 0.02:
			continue
		var font: Font
		var col: Color
		if kind == &"sea":
			font = UiTheme.body_font(4)
			col = Color(0.15, 0.32, 0.40, 0.62 * a)
		elif kind == &"wilds":
			font = UiTheme.title_font(600, 6)
			col = Color(INK, 0.6 * a)
		else:
			font = UiTheme.title_font(800, int(fs * 0.32))
			col = Color(INK, 0.86 * a)
		var w := font.get_string_size(l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := s - Vector2(w * 0.5, -fs * 0.35)
		if kind == &"sea":
			draw_string(font, p, l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		else:
			_halo_text(p, l["text"], font, fs, col, Color(HALO, 0.55 * a), 8)
		if a > 0.5:
			_obstacles.append(Rect2(p + Vector2(0, -fs * 0.8), Vector2(w, fs * 1.0)))
			if l.has("city"):
				_lettered_cities[l["city"]] = true
		var glyph := String(l.get("glyph", ""))
		if glyph != "":
			# cinnabar seal stamp with the nation's brush glyph
			var gs := int(fs * 1.25)
			var c := p + Vector2(-gs * 0.85, -fs * 0.38)
			var r := gs * 0.62
			draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), Color(UiTheme.SEAL, 0.82 * a))
			draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0).grow(-3.0), Color(HALO, 0.5 * a), false, 1.5)
			var bf := UiTheme.brush_font()
			var gw := bf.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x
			draw_string(bf, c + Vector2(-gw * 0.5, gs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(HALO, 0.95 * a))


# --- routes --------------------------------------------------------------------------------------

func _draw_routes() -> void:
	for r in MapModel.ferry_routes():
		var pts: PackedVector2Array = r["points"]
		if pts.size() < 2:
			continue
		var sp := PackedVector2Array()
		for q in pts:
			sp.append(canvas.uv_to_local(MapModel.xz_to_uv(q)))
		var w := clampf(2.0 * _zoom_k(), 2.0, 4.0)
		var dash := 10.0 * _zoom_k()
		for i in sp.size() - 1:
			draw_dashed_line(sp[i], sp[i + 1], ROUTE, w, dash, true, true)
		# boat glyph at the middle of the route
		var mid := TravelSystem.polyline_point(pts, TravelSystem.polyline_length(pts) * 0.5)
		var m := canvas.uv_to_local(MapModel.xz_to_uv(mid))
		var ic := _icon("map_port")
		if ic and canvas.zoom > 1.25:
			var s := 18.0 * _zoom_k()
			draw_circle(m, s * 0.75, Color(HALO, 0.9), true, -1.0, true)
			draw_texture_rect(ic, Rect2(m - Vector2(s, s) * 0.5, Vector2(s, s)), false, ROUTE)


# --- places --------------------------------------------------------------------------------------

func _draw_place(e: Dictionary, known: bool, hot: bool, zk: float) -> void:
	var s: Vector2 = e["screen"]
	var kind: StringName = e["kind"]
	var travel := known and MapModel.is_travel_point(e)
	if not known and kind == &"poi":
		var ui := _icon("map_unknown")
		var us := 16.0 * zk * (1.25 if hot else 1.0)
		if ui:
			draw_texture_rect(ui, Rect2(s - Vector2(us, us) * 0.5, Vector2(us, us)), false, Color(INK, 0.38 if not hot else 0.85))
		if hot:
			_queue_label(s, us * 0.5 + 4.0, "Undiscovered", UiTheme.body_font(1), int(15 * zk), Color(INK, 0.85), 0)
		return
	var size := (30.0 if kind == &"city" else 22.0) * zk * (1.2 if hot else 1.0)
	var ic := _icon(String(e.get("icon", "map_landmark")))
	# disc behind the glyph so it reads on any terrain colour
	var disc_col := Color(HALO, 0.92)
	draw_circle(s, size * 0.68, disc_col, true, -1.0, true)
	var ring := Color(INK, 0.75)
	if travel:
		ring = Color(UiTheme.GOLD_DEEP, 0.95)
	if hot:
		ring = UiTheme.SEAL
	draw_arc(s, size * 0.68, 0, TAU, 32, ring, 2.0 if not hot else 3.0, true)
	if ic:
		var col := INK if kind != &"city" else Color("5a1f16")
		if not known:
			col = Color(INK, 0.55)
		draw_texture_rect(ic, Rect2(s - Vector2(size, size) * 0.42, Vector2(size, size) * 0.84), false, col)
	if travel:
		# small gold gate badge: a fast-travel point
		var b := s + Vector2(size * 0.52, -size * 0.52)
		draw_circle(b, 7.0 * zk, UiTheme.GOLD, true, -1.0, true)
		draw_arc(b, 7.0 * zk, 0, TAU, 16, INK, 1.2, true)
	# labels: cities always (unless the region lettering spells the same name), known places
	# when zoomed in, hovered or selected; placed without overlapping (priority order)
	var show := kind == &"city" or hot or (canvas.zoom >= 2.2) or (travel and canvas.zoom >= 1.5)
	if kind == &"city" and _lettered_cities.has(e["id"]) and not hot:
		show = false
	if show:
		var fs := int((21.0 if kind == &"city" else 15.0) * zk)
		var font := UiTheme.title_font(800 if kind == &"city" else 700, 2 if kind == &"city" else 1)
		var prio := 0 if hot else (1 if kind == &"city" else (2 if travel else 3))
		_queue_label(s, size * 0.68 + 2.0, String(e["name"]), font, fs, INK if known else Color(INK, 0.7), prio)


func _draw_quest(e: Dictionary, hot: bool) -> void:
	var s: Vector2 = e["screen"]
	var tracked := bool(e.get("tracked", false))
	var zk := _zoom_k()
	if e.get("marker") == &"giver":
		var gi := _icon("map_giver")
		var gs := 24.0 * zk * (1.2 if hot else 1.0)
		draw_circle(s, gs * 0.55, Color(HALO, 0.9), true, -1.0, true)
		if gi:
			draw_texture_rect(gi, Rect2(s - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false, GIVER)
	else:
		var qs := (30.0 if tracked else 22.0) * zk * (1.2 if hot else 1.0)
		if tracked:
			var k := 0.5 + 0.5 * sin(_t * 3.4)
			draw_arc(s, qs * (0.7 + 0.25 * k), 0, TAU, 40, Color(QUEST, 0.65 * (1.0 - k) + 0.2), 3.0, true)
		var mi := _icon("icon_marker")
		if mi:
			draw_texture_rect(mi, Rect2(s - Vector2(qs, qs) * 0.5 + Vector2(1.5, 2.0), Vector2(qs, qs)), false, Color(0, 0, 0, 0.35))
			draw_texture_rect(mi, Rect2(s - Vector2(qs, qs) * 0.5, Vector2(qs, qs)), false, QUEST if tracked else Color(QUEST, 0.8))
	if hot or (tracked and e.get("marker") != &"giver"):
		_queue_label(s, 16.0 * zk, String(e.get("name", "")), UiTheme.title_font(700, 1), int(15 * zk), Color("4a2a0c"), 0 if hot else 1)


func _draw_pin() -> void:
	var s := canvas.world_to_local(pin["position"])
	var k := 0.5 + 0.5 * sin(_t * 3.0)
	draw_arc(s, 18.0 + 8.0 * k, 0, TAU, 40, Color(UiTheme.SEAL, 0.7 * (1.0 - k) + 0.2), 3.0, true)
	draw_circle(s, 11.0, UiTheme.SEAL, true, -1.0, true)
	draw_circle(s, 4.5, HALO, true, -1.0, true)
	_queue_label(s, 18.0, String(pin.get("label", "")), UiTheme.title_font(700, 1), 17, Color("5a1f16"), 0)


func _draw_companion() -> void:
	if companion == null or not is_instance_valid(companion):
		return
	var s := canvas.world_to_local(companion.global_position)
	var ic := _icon("icon_paw")
	var cs := 22.0 * _zoom_k()
	draw_circle(s, cs * 0.7, Color(HALO, 0.92), true, -1.0, true)
	draw_arc(s, cs * 0.7, 0, TAU, 28, UiTheme.element_color(GameState.element).darkened(0.25), 2.0, true)
	if ic:
		draw_texture_rect(ic, Rect2(s - Vector2(cs, cs) * 0.45, Vector2(cs, cs) * 0.9), false, UiTheme.element_color(GameState.element).darkened(0.3))


func _draw_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	var s := canvas.world_to_local(player.global_position)
	var fwd := -player.global_transform.basis.z
	# map north = -Z = screen up; the arrow glyph points up at angle 0
	var ang := atan2(fwd.x, -fwd.z)
	var k := fmod(_t * 0.7, 1.0)
	var col := UiTheme.element_color(GameState.element) if ElementDefs.is_valid(GameState.element) else UiTheme.SEAL
	draw_arc(s, 14.0 + 26.0 * k, 0, TAU, 40, Color(col, 0.75 * (1.0 - k)), 3.0, true)
	var ic := _icon("map_player")
	var ps := 34.0 * clampf(_zoom_k(), 1.0, 1.4)
	draw_set_transform(s, ang, Vector2.ONE)
	if ic:
		draw_texture_rect(ic, Rect2(-Vector2(ps, ps) * 0.5 + Vector2(2, 3), Vector2(ps, ps)), false, Color(0, 0, 0, 0.4))
		draw_texture_rect(ic, Rect2(-Vector2(ps, ps) * 0.62, Vector2(ps, ps) * 1.24), false, HALO)
		draw_texture_rect(ic, Rect2(-Vector2(ps, ps) * 0.5, Vector2(ps, ps)), false, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_reticle() -> void:
	var c := canvas.cursor_local()
	var col := Color("5a1f16")
	var r := 26.0
	draw_arc(c, r, 0, TAU, 40, Color(col, 0.8), 2.0, true)
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * (r - 6.0), c + d * (r + 10.0), col, 2.5, true)
	draw_circle(c, 3.0, col, true, -1.0, true)


func _draw_scale_bar() -> void:
	var mpp := canvas.metres_per_px()
	var nice := [100.0, 250.0, 500.0, 1000.0, 2000.0]
	var len_m := 1000.0
	for n: float in nice:
		if n / mpp >= 90.0:
			len_m = n
			break
	var px := len_m / mpp
	var o := Vector2(28.0, canvas.size.y - 34.0)
	draw_rect(Rect2(o - Vector2(10, 30), Vector2(px + 20, 42)), Color(HALO, 0.75))
	draw_line(o, o + Vector2(px, 0), INK, 3.0)
	draw_line(o + Vector2(0, -7), o + Vector2(0, 5), INK, 2.0)
	draw_line(o + Vector2(px, -7), o + Vector2(px, 5), INK, 2.0)
	draw_line(o + Vector2(px * 0.5, -4), o + Vector2(px * 0.5, 3), INK, 1.5)
	var t := MapModel.distance_text(len_m)
	draw_string(UiTheme.title_font(700, 1), o + Vector2(0, -12), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)
