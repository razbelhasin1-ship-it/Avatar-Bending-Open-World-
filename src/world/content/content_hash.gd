class_name ContentHash
extends RefCounted
## Deterministic integer hashing for per-cell / per-feature generation (identical on every run,
## platform and thread). GDScript ints are 64-bit and wrap on overflow, so the mixing is exact.

const MASK31 := 0x7fffffff


## Mixes up to four integers into a non-negative 31-bit hash.
static func hash4(a: int, b: int = 0, c: int = 0, d: int = 0) -> int:
	var h := 0x2545F4914F6CDD1D
	h = _mix(h ^ (a * 0x1E3779B97F4A7C15))
	h = _mix(h ^ (b * 0x42B2AE3D27D4EB4F))
	h = _mix(h ^ (c * 0x165667B19E3779F9))
	h = _mix(h ^ (d * 0x27D4EB2F165667C5))
	return h & MASK31


static func _mix(x: int) -> int:
	x = (x ^ (x >> 31)) * 0x7FB5D329728EA185
	x = (x ^ (x >> 27)) * 0x61DADEF4BC2DD44D
	return x ^ (x >> 33)


## Hash of a string/StringName (stable across runs, unlike String.hash() guarantees).
static func hash_name(s: String) -> int:
	var h := 1469598103
	for i in s.length():
		h = ((h ^ s.unicode_at(i)) * 16777619) & 0xffffffff
	return h & MASK31


## Float in [0, 1) from a hash.
static func unit(h: int) -> float:
	return float(h & 0xffffff) / 16777216.0


## Float in [0, 1) for a 2D integer position under a seed.
static func unit2(seed: int, x: int, z: int) -> float:
	return unit(hash4(seed, x, z))


## A seeded RandomNumberGenerator (each cell/feature owns its own: thread-safe and deterministic).
static func rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	r.state = seed * 2 + 1
	return r
