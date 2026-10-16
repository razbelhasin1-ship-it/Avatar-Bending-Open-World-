class_name KitCache
extends RefCounted
## Thread-safe cache of archetype builds: a settlement has a few dozen building archetypes
## (variants of homes, towers, stalls...) that hundreds of pieces share. Each archetype is built
## once per LOD (on whichever worker first needs it) and merged into cells with a transform
## (KitMerger). Keys: "<nation>|<arch>|<lod>".

static var _cache: Dictionary = {}
static var _mutex := Mutex.new()
static var builds := 0


static func get_result(key: String) -> KitResult:
	_mutex.lock()
	var r: KitResult = _cache.get(key)
	_mutex.unlock()
	return r


static func put(key: String, res: KitResult) -> void:
	_mutex.lock()
	if not _cache.has(key):
		_cache[key] = res
		builds += 1
	_mutex.unlock()


## Cached result for `key`, or builds it with `make: func() -> KitResult` (outside the lock; two
## workers may race on a key, the first stored result wins and both are identical).
static func fetch(key: String, make: Callable) -> KitResult:
	var r := get_result(key)
	if r != null:
		return r
	r = make.call()
	put(key, r)
	return get_result(key)


static func size() -> int:
	_mutex.lock()
	var n := _cache.size()
	_mutex.unlock()
	return n


static func clear() -> void:
	_mutex.lock()
	_cache.clear()
	builds = 0
	_mutex.unlock()
