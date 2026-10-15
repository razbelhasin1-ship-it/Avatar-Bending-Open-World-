extends TestCase
## Characters module tests (WIP).


func test_clip_library_loads() -> void:
	var names := AnimLibrary.clip_names()
	print("clips: ", names.size())
	print(", ".join(PackedStringArray(names)))
	expect(names.size() > 80, "many clips")
