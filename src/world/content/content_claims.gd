class_name ContentClaims
extends RefCounted
## Lets another system take over a WorldData feature that a worldcontent provider would otherwise
## build (a bridge, waterfall, cave, POI structure...). Settlement builders that construct their
## own version of, say, the Great Bridge of Omashu call `ContentClaims.claim(&"omashu_great_bridge")`
## before (or after: refresh happens automatically) WorldContent builds it; LandmarkProvider and
## PoiProvider skip claimed ids. Main thread.
##
##   ContentClaims.claim(&"ek_northreach")       # the village builder builds that harbour itself
##   ContentClaims.is_claimed(&"ek_northreach")  # -> true

static var _claims: Dictionary = {}
static var version: int = 0


static func claim(feature_id: StringName, owner: StringName = &"") -> void:
	if _claims.get(feature_id) == owner and _claims.has(feature_id):
		return
	_claims[feature_id] = owner
	version += 1


static func release(feature_id: StringName) -> void:
	if _claims.erase(feature_id):
		version += 1


static func is_claimed(feature_id: StringName) -> bool:
	return _claims.has(feature_id)


static func owner_of(feature_id: StringName) -> StringName:
	return _claims.get(feature_id, &"")


static func clear() -> void:
	if not _claims.is_empty():
		_claims.clear()
		version += 1
