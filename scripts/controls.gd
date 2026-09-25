extends Node
## What the player is holding, and what they are looking at.
##
## `mode` is whichever input was used last -- keyboard/mouse, gamepad or touch --
## and flips the moment a different one is touched. The HUD reads it to pick
## hint wording and button glyphs, and to decide whether the on-screen stick is
## up. Following the last input rather than the platform is what makes a
## touchscreen laptop, a tablet with a pad paired to it, or a phone on a desk
## with a keyboard all behave.
##
## `form_factor` is what kind of screen this is, fixed at startup. It sets how
## large the 2D UI is drawn so text stays readable and targets stay tappable on
## a phone held at arm's length.

signal mode_changed(mode: int)

enum Mode { KEYBOARD, GAMEPAD, TOUCH }
enum FormFactor { DESKTOP, TABLET, PHONE }

## 2D UI scale per form factor. The layout is authored for a 720-tall desktop
## view; on a landscape phone that puts the smallest HUD text near 8 pt. 1.35
## lifts it to ~11 pt while still leaving the lobby room to fit.
const UI_SCALE := {
	FormFactor.DESKTOP: 1.0,
	FormFactor.TABLET: 1.1,
	FormFactor.PHONE: 1.35,
}

## Native builds report real DPI; the web reports CSS pixels, which are
## physically larger on a phone than the 96-per-inch they claim to be.
const PHONE_MAX_SHORT_SIDE_INCHES := 3.8
const PHONE_MAX_SHORT_SIDE_CSS_PX := 600.0

## Nothing should sit closer to a physical edge than this, notch or not.
const MIN_EDGE_MARGIN := 20.0

var mode: int = Mode.KEYBOARD
var form_factor: int = FormFactor.DESKTOP
## UI units of screen width the on-screen controls cover, both sides together.
## 0 whenever they are hidden. The camera frames the arena in what is left.
var reserved_width := 0.0

func _ready() -> void:
	# Needs to keep hearing input while the tree is paused, or the first touch
	# on the pause menu would not flip the hints over to touch wording.
	process_mode = Node.PROCESS_MODE_ALWAYS
	form_factor = _detect_form_factor()
	mode = Mode.TOUCH if is_handheld() else Mode.KEYBOARD
	_apply_overrides(OS.get_cmdline_user_args())
	get_tree().root.content_scale_factor = UI_SCALE[form_factor]
	if OS.is_debug_build():
		print("[controls] form=%s mode=%s ui_scale=%.2f %s" % [
			FormFactor.keys()[form_factor], Mode.keys()[mode],
			UI_SCALE[form_factor], _screen_summary()])

func is_handheld() -> bool:
	return form_factor != FormFactor.DESKTOP

func is_touch() -> bool:
	return mode == Mode.TOUCH

func is_gamepad() -> bool:
	return mode == Mode.GAMEPAD

func _input(event: InputEvent) -> void:
	var next := mode
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		next = Mode.TOUCH
	elif event is InputEventKey and event.pressed:
		next = Mode.KEYBOARD
	elif event is InputEventMouseButton and event.pressed:
		# A tap also arrives as an emulated mouse click. Only a real mouse
		# means the player has moved to a desk.
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			next = Mode.KEYBOARD
	elif event is InputEventJoypadButton and event.pressed:
		next = Mode.GAMEPAD
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		next = Mode.GAMEPAD
	if next != mode:
		mode = next
		mode_changed.emit(mode)

## Safe-area insets in UI units: notches, rounded corners, home indicator. On
## desktop the window is not fullscreen and the display's safe area says
## nothing about it, so only the minimum margin applies.
func safe_margins() -> Dictionary:
	var m := {"left": MIN_EDGE_MARGIN, "top": MIN_EDGE_MARGIN,
		"right": MIN_EDGE_MARGIN, "bottom": MIN_EDGE_MARGIN}
	if not is_handheld():
		return m
	var window := get_tree().root
	var px_per_unit := window.get_final_transform().x.x
	if px_per_unit <= 0.0:
		return m
	var win_size := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return m
	m["left"] = maxf(MIN_EDGE_MARGIN, safe.position.x / px_per_unit)
	m["top"] = maxf(MIN_EDGE_MARGIN, safe.position.y / px_per_unit)
	m["right"] = maxf(MIN_EDGE_MARGIN, (win_size.x - safe.end.x) / px_per_unit)
	m["bottom"] = maxf(MIN_EDGE_MARGIN, (win_size.y - safe.end.y) / px_per_unit)
	return m

func _detect_form_factor() -> int:
	var web_handheld := OS.has_feature("web_android") or OS.has_feature("web_ios")
	if not (OS.has_feature("mobile") or web_handheld):
		return FormFactor.DESKTOP
	var size := Vector2(DisplayServer.screen_get_size())
	var short_side := minf(size.x, size.y)
	if web_handheld:
		var css := short_side / maxf(DisplayServer.screen_get_scale(), 1.0)
		return FormFactor.PHONE if css < PHONE_MAX_SHORT_SIDE_CSS_PX else FormFactor.TABLET
	var inches := short_side / float(maxi(DisplayServer.screen_get_dpi(), 1))
	return FormFactor.PHONE if inches < PHONE_MAX_SHORT_SIDE_INCHES else FormFactor.TABLET

## `-- --phone`, `--tablet` or `--touch` fake a handheld on desktop, which is how
## the touch layout is developed and screenshotted without a device.
func _apply_overrides(args: PackedStringArray) -> void:
	if args.has("--phone"):
		form_factor = FormFactor.PHONE
		mode = Mode.TOUCH
	elif args.has("--tablet"):
		form_factor = FormFactor.TABLET
		mode = Mode.TOUCH
	if args.has("--touch"):
		mode = Mode.TOUCH

func _screen_summary() -> String:
	return "screen=%s dpi=%d scale=%.2f window=%s" % [
		str(DisplayServer.screen_get_size()), DisplayServer.screen_get_dpi(),
		DisplayServer.screen_get_scale(), str(DisplayServer.window_get_size())]
