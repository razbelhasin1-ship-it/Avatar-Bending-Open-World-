class_name NpcCrowd
extends RefCounted
## Turns settlement anchors (docs/modules/settlements.md) into crowd spawn records: who lives
## where, their role, schedule offset, look, route. Deterministic from the anchor ids and pure
## data, so NpcProvider runs it on WorldContent worker threads.
##
## Record: {key, named (&""), settlement, nation, role, kind, pos, yaw, home, route, loop, look,
##          hash, offset (schedule hours), tags, goods, interior, pair (partner key), wander (m)}

## anchor kind -> [role, chance] (chance scaled by the provider's density).
const KIND_ROLES := {
	&"market_stall": [&"merchant", 0.6],
	&"guard_post": [&"guard", 0.6],
	&"patrol": [&"patrol", 1.0],
	&"worker": [&"worker", 0.65],
	&"fisher": [&"fisher", 0.7],
	&"gardener": [&"gardener", 0.6],
	&"child_play": [&"child", 0.85],
	&"idle": [&"idler", 0.7],
	&"home": [&"resident", 0.3],
	&"student": [&"student", 0.9],
	&"healer": [&"elder", 1.0],
	&"trainer": [&"elder", 1.0],
	&"quest_giver": [&"elder", 0.7],
}

## Kinds a crowd NPC can stand at (the provider indexes only these).
const KINDS: Array[StringName] = [&"market_stall", &"guard_post", &"patrol", &"worker", &"fisher", &"gardener",
	&"child_play", &"idle", &"home", &"student", &"healer", &"trainer", &"quest_giver"]


## Records of `anchors` (all from one cell). `density` scales chances (detail level), `claimed`
## holds anchor ids used by named NPCs (skipped). Small sites (villages) get more residents.
static func records_for(anchors: Array, density: float, claimed: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a: Dictionary in anchors:
		var aid := String(a["id"])
		if claimed.has(aid):
			continue
		var kind: StringName = a["kind"]
		if not KIND_ROLES.has(kind):
			continue
		var h := mix(aid)
		var role: StringName = KIND_ROLES[kind][0]
		var chance := float(KIND_ROLES[kind][1]) * density
		var sid: StringName = a["settlement"]
		var tags: Array = a.get("tags", [])
		if kind == &"home" and (sid == &"arctic_villages" or sid == &"ek_villages" or sid == &"fn_villages"):
			chance *= 1.8
		if kind == &"home" and sid == &"southern_air_temple":
			chance *= 1.6
		if kind == &"quest_giver":
			role = _quest_giver_role(tags)
		if kind == &"idle":
			if tags.has("meditate"):
				role = &"monk"
			elif tags.has("bench") or (h >> 4) % 3 == 0:
				role = &"sitter"
		if kind == &"guard_post" and sid == &"southern_air_temple":
			role = &"monk"
		if kind == &"patrol" and sid == &"southern_air_temple":
			role = &"monk"
		if kind == &"home":
			# each resident of the house (capacity) may be out and about
			var nat := NpcLooks.nation_of(sid)
			var lr: StringName = &"monk" if sid == &"southern_air_temple" else &"resident"
			var right0 := Basis(Vector3.UP, float(a.get("yaw", 0.0))) * Vector3.RIGHT
			for k in clampi(int(a.get("capacity", 2)), 1, 3):
				var rk := "%s_r%d" % [aid, k]
				var hk := mix(rk)
				if float(absi(hk) % 10007) / 10007.0 >= chance:
					continue
				var rr := _record(a, rk, &"resident", lr, nat, hk)
				rr["pos"] = (rr["pos"] as Vector3) + right0 * (float(k) - 1.0) * 1.3
				out.append(rr)
			continue
		if float(absi(h) % 10007) / 10007.0 >= chance:
			continue
		var nation := NpcLooks.nation_of(sid)
		var look_role := role
		if sid == &"southern_air_temple" and role in [&"resident", &"idler", &"sitter", &"worker", &"gardener", &"guard"]:
			look_role = &"monk"
		var base := _record(a, aid, role, look_role, nation, h)
		match role:
			&"child":
				# two kids playing together around the spot
				var right := Basis(Vector3.UP, float(a["yaw"])) * Vector3.RIGHT
				var r1 := base.duplicate(true)
				r1["key"] = StringName(aid + "_a")
				r1["pos"] = (a["position"] as Vector3) + right * 1.4
				var r2 := _record(a, aid + "_b", role, look_role, nation, mix(aid + "_b"))
				r2["key"] = StringName(aid + "_b")
				r2["pos"] = (a["position"] as Vector3) - right * 1.4
				r2["offset"] = r1["offset"]
				out.append(r1)
				out.append(r2)
			&"idler":
				# a pair talking face to face
				var right2 := Basis(Vector3.UP, float(a["yaw"])) * Vector3.RIGHT
				var p1 := base.duplicate(true)
				var p2 := _record(a, aid + "_b", role, look_role, nation, mix(aid + "_b"))
				p1["key"] = StringName(aid + "_a")
				p2["key"] = StringName(aid + "_b")
				p1["pos"] = (a["position"] as Vector3) + right2 * 0.75
				p2["pos"] = (a["position"] as Vector3) - right2 * 0.75
				p1["yaw"] = float(a["yaw"]) + PI * 0.5
				p2["yaw"] = float(a["yaw"]) - PI * 0.5
				p2["offset"] = p1["offset"]
				p1["pair"] = p2["key"]
				p2["pair"] = p1["key"]
				out.append(p1)
				out.append(p2)
			&"merchant":
				out.append(base)
				# a customer browsing beside the stall in market hours (mills about the stall)
				var ck := aid + "_c"
				var hc := mix(ck)
				if kind == &"market_stall" and float(absi(hc) % 10007) / 10007.0 < 0.65 * density:
					var right3 := Basis(Vector3.UP, float(a["yaw"])) * Vector3.RIGHT
					var cust := _record(a, ck, &"shopper", &"monk" if sid == &"southern_air_temple" else &"resident", nation, hc)
					cust["pos"] = (a["position"] as Vector3) + right3 * (2.1 if hc % 2 == 0 else -2.1)
					cust["home"] = cust["pos"]
					cust["goods"] = ""
					out.append(cust)
			_:
				out.append(base)
	return out


## Well-mixed deterministic hash of an id (String.hash() of similar ids is nearly sequential).
static func mix(s: String) -> int:
	return ContentHash.hash4(ContentHash.hash_name(s), 0x51ED)


static func _record(a: Dictionary, aid: String, role: StringName, look_role: StringName, nation: StringName, h: int) -> Dictionary:
	var pos: Vector3 = a["position"]
	var yaw := float(a.get("yaw", 0.0))
	var r := {
		"key": StringName(aid), "named": &"", "settlement": a["settlement"], "nation": nation, "role": role,
		"kind": a["kind"], "pos": pos, "yaw": yaw, "home": pos, "route": PackedVector3Array(), "loop": false,
		"look": NpcLooks.crowd_look(nation, look_role, h), "hash": h, "offset": NpcRoutines.offset_for(h),
		"tags": a.get("tags", []), "goods": String(a.get("goods", "")), "interior": bool(a.get("interior", false)),
		"pair": &"", "wander": 0.0, "district": a.get("district", &""),
	}
	match role:
		&"resident":
			# step off the doorstep into the street
			r["pos"] = pos + Basis(Vector3.UP, yaw) * Vector3(0, 0, -1.6)
			r["wander"] = 6.0
		&"child":
			r["wander"] = 4.5
		&"worker", &"gardener":
			r["wander"] = 2.5
		&"monk":
			r["wander"] = 5.0
		&"elder":
			r["wander"] = 2.0
		&"shopper":
			r["wander"] = 4.0
	if a.has("points"):
		r["route"] = a["points"]
		r["loop"] = bool(a.get("loop", false))
	return r


static func _quest_giver_role(tags: Array) -> StringName:
	for t: Variant in tags:
		match String(t):
			"gatekeeper":
				return &"guard"
			"market", "merchant", "merchant_guild":
				return &"merchant"
			"noticeboard":
				return &"sitter"
			"harbor_master", "mail_clerk":
				return &"worker"
			"chief", "king", "fire_lord", "princess", "earth_king", "noble", "host", "admiral":
				return &"noble"
	return &"elder"
