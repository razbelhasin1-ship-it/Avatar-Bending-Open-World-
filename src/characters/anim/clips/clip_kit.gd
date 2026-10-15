class_name ClipKit
extends RefCounted
## Helpers for authoring clips in code: mirroring L/R, registering pairs and
## a few shared hand/foot positions (RigPose units, see rig_pose.gd).

## Relaxed hanging arm.
const HANG := Vector3(0.1, -0.96, 0.04)
## Fist chambered at the ribs (Shaolin chamber), with ELBOW_BACK.
const CHAMBER := Vector3(0.02, -0.46, -0.12)
const ELBOW_BACK := Vector3(0.15, -0.35, -1.0)
const ELBOW_DOWN := Vector3(0.25, -1.0, 0.0)
const ELBOW_OUT := Vector3(1.0, -0.2, -0.2)
## Straight punch at shoulder height, slightly toward the center line.
const PUNCH := Vector3(-0.12, 0.0, 0.98)
## Guard: fist in front of the face.
const GUARD := Vector3(-0.22, -0.12, 0.42)
const KNEE_FWD := Vector3(0.1, 0.0, 1.0)
const KNEE_OUT := Vector3(0.7, 0.0, 0.8)

const _CENTER := ["hips_rot", "spine", "chest", "neck", "head"]


## Mirrored copy of a clip dictionary (left <-> right).
static func mirror(clip: Dictionary) -> Dictionary:
	var c := clip.duplicate(true)
	var keys: Array = []
	for k: Array in clip.get("keys", []):
		var pose: Dictionary = k[1]
		var out := {}
		for ch: String in pose:
			var val: Variant = pose[ch]
			var name := ch
			if ch.ends_with("_l"):
				name = ch.substr(0, ch.length() - 2) + "_r"
			elif ch.ends_with("_r"):
				name = ch.substr(0, ch.length() - 2) + "_l"
			elif ch == "hips":
				val = Vector3(-(val as Vector3).x, (val as Vector3).y, (val as Vector3).z)
			elif _CENTER.has(ch):
				val = Vector3((val as Vector3).x, -(val as Vector3).y, -(val as Vector3).z)
			out[name] = val
		var nk := [k[0], out]
		if k.size() > 2:
			nk.append(k[2])
		keys.append(nk)
	c["keys"] = keys
	var plants: Array = []
	for pl: Array in clip.get("plants", []):
		var np := pl.duplicate()
		np[1] = "r" if String(pl[1]) in ["l", "left", "0"] else "l"
		plants.append(np)
	c["plants"] = plants
	var root: Array = []
	for r: Array in clip.get("root", []):
		var rv: Vector3 = r[1]
		root.append([r[0], Vector3(-rv.x, rv.y, rv.z)])
	c["root"] = root
	var ev: Variant = clip.get("events", [])
	if ev is Array:
		var evs: Array = []
		for e: Array in ev:
			var en := String(e[1])
			if en.ends_with("_l"):
				en = en.substr(0, en.length() - 2) + "_r"
			elif en.ends_with("_r"):
				en = en.substr(0, en.length() - 2) + "_l"
			evs.append([e[0], StringName(en)])
		c["events"] = evs
	var mask := String(clip.get("mask", "full"))
	if mask.ends_with("_l"):
		c["mask"] = StringName(mask.trim_suffix("_l") + "_r")
	elif mask.ends_with("_r"):
		c["mask"] = StringName(mask.trim_suffix("_r") + "_l")
	return c


static func reg(clip_name: StringName, clip: Dictionary) -> void:
	AnimLibrary.register(clip_name, clip)


## Registers `<stem>_r` from the given right-handed clip and `<stem>_l` mirrored.
static func reg_pair(stem: String, clip_r: Dictionary) -> void:
	AnimLibrary.register(StringName(stem + "_r"), clip_r)
	AnimLibrary.register(StringName(stem + "_l"), mirror(clip_r))


## Same clip registered for several names (aliases / style variants).
static func reg_alias(names: Array, clip: Dictionary) -> void:
	for n: Variant in names:
		AnimLibrary.register(StringName(n), clip)


## Concatenates clip dictionaries into one chain (keys, events, plants and root
## remapped onto the combined timeline). Only explicit keys are kept, so the
## chain flows from hit to hit without returning to the base pose in between.
static func chain(parts: Array, extra: Dictionary = {}) -> Dictionary:
	var total := 0.0
	for p: Dictionary in parts:
		total += float(p.get("length", 1.0))
	var keys: Array = []
	var events: Array = []
	var plants: Array = []
	var root: Array = []
	var off := 0.0
	var root_off := Vector3.ZERO
	var mask := &"upper"
	for p: Dictionary in parts:
		var ln := float(p.get("length", 1.0))
		if StringName(p.get("mask", &"full")) == &"full":
			mask = &"full"
		for k: Array in p.get("keys", []):
			var nk := [(off + float(k[0]) * ln) / total, k[1]]
			if k.size() > 2:
				nk.append(k[2])
			keys.append(nk)
		var ev: Variant = p.get("events", [])
		if ev is Array:
			for e: Array in ev:
				events.append([(off + float(e[0]) * ln) / total, e[1]])
		for pl: Array in p.get("plants", []):
			var np := pl.duplicate()
			np[0] = (off + float(pl[0]) * ln) / total
			plants.append(np)
		var last := Vector3.ZERO
		for r: Array in p.get("root", []):
			root.append([(off + float(r[0]) * ln) / total, root_off + (r[1] as Vector3)])
			last = r[1]
		root_off += last
		off += ln
	var c := {"length": total, "mask": mask, "keys": keys, "events": events, "plants": plants, "root": root}
	for k: String in extra:
		c[k] = extra[k]
	return c
