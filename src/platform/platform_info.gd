class_name PlatformInfo
extends RefCounted
## Platform facts for the mobile / web builds (docs/modules/mobile.md). Static helpers so
## any module can ask without an autoload.
##
##   PlatformInfo.is_web()            # HTML5 build (any browser)
##   PlatformInfo.is_web_mobile()     # phone / tablet browser
##   PlatformInfo.can_quit()          # false on Web and iOS (no "exit" there)
##   PlatformInfo.describe()          # one-line summary for logs and the settings panel


static func is_web() -> bool:
	return OS.has_feature("web")


static func is_web_mobile() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios")


static func is_android() -> bool:
	return OS.get_name() == "Android"


static func is_ios() -> bool:
	return OS.get_name() == "iOS"


## Native phone / tablet app (not a browser).
static func is_native_mobile() -> bool:
	return is_android() or is_ios()


## Whether the app may close itself. Browsers cannot close their tab and iOS apps must
## not quit, so EXIT / QUIT options are hidden there.
static func can_quit() -> bool:
	return not is_web() and not is_ios()


## Whether the build can run threads (Web exports ship without thread support so they
## work in every mobile browser without cross-origin isolation headers).
static func has_threads() -> bool:
	return OS.has_feature("threads") or not is_web()


static func renderer_name() -> String:
	match RenderingServer.get_current_rendering_method():
		"forward_plus": return "Forward+"
		"mobile": return "Mobile"
		"gl_compatibility": return "Compatibility"
	return RenderingServer.get_current_rendering_method()


static func describe() -> String:
	var kind := "desktop"
	if is_native_mobile():
		kind = "mobile app"
	elif is_web_mobile():
		kind = "mobile browser"
	elif is_web():
		kind = "browser"
	return "%s (%s) · %s · %s" % [OS.get_name(), kind, renderer_name(), RenderingServer.get_video_adapter_name()]
