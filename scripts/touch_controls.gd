extends Control
## On-screen controls for touchscreens: a floating stick on the left, a dash
## button on the right, and a pause button in the top corner.
##
## Touches are read raw, by finger index, rather than through Buttons. Godot
## only turns the *first* finger into an emulated mouse click, so a Button-based
## dash would stop working the moment your thumb was already on the stick.
##
## The stick and dash write straight into the same pN_* input actions the
## keyboard and gamepads use, so BumperBall needs no idea touch exists -- the
## camera-relative steering and everything else come along for free.

signal pause_requested

const STICK_RADIUS := 92.0
const KNOB_RADIUS := 40.0
## Past this the base slides after your thumb instead of pinning it, so the
## stick never feels like it has run out of travel.
const STICK_FOLLOW := 1.3
const DASH_RADIUS := 78.0
const PAUSE_SIZE := 76.0
## Nothing in the stick zone sits above this; the score bar and pause button
## live up there.
const TOP_BAND := 150.0
## Share of the screen width, from the left, that starts a stick.
const STICK_ZONE := 0.5

var slot := 0
var ball: BumperBall = null

var _stick_index := -1
var _stick_base := Vector2.ZERO
var _stick_knob := Vector2.ZERO
var _dash_index := -1
var _pressed := {}      ## Actions this node is holding, so it only ever releases its own.
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = get_theme_default_font()
	visible = false
	resized.connect(func() -> void:
		if visible:
			Controls.reserved_width = _side_bands())

## Show or hide for the current match phase. Hiding lets go of anything held.
func set_active(value: bool) -> void:
	if value == visible:
		return
	visible = value
	Controls.reserved_width = _side_bands() if value else 0.0
	if not value:
		reset()

func reset() -> void:
	_stick_index = -1
	_dash_index = -1
	for action in _pressed.keys():
		Input.action_release(action)
	_pressed.clear()
	queue_redraw()

func _notification(what: int) -> void:
	# A finger lifted while the app was in the background never reports back.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		reset()

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # the dash ring animates with the cooldown

func _input(event: InputEvent) -> void:
	# Deliberately never marks events handled: the Controls autoload needs to
	# see every touch to know touch is the active input.
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag and event.index == _stick_index:
		_drag_stick(event.position)

func _touch_down(index: int, pos: Vector2) -> void:
	if _pause_rect().has_point(pos):
		pause_requested.emit()
		return
	if not _has_ball():
		return
	if _dash_index == -1 and pos.distance_to(_dash_center()) <= DASH_RADIUS * 1.25:
		_dash_index = index
		_hold(_action("dash"), 1.0)
	elif _stick_index == -1 and pos.x < size.x * STICK_ZONE and pos.y > TOP_BAND:
		_stick_index = index
		_stick_base = pos
		_stick_knob = pos
		_write_stick(Vector2.ZERO)
	queue_redraw()

func _touch_up(index: int) -> void:
	if index == _stick_index:
		_stick_index = -1
		_write_stick(Vector2.ZERO)
	elif index == _dash_index:
		_dash_index = -1
		_let_go(_action("dash"))
	queue_redraw()

func _drag_stick(pos: Vector2) -> void:
	var offset := pos - _stick_base
	var reach := STICK_RADIUS * STICK_FOLLOW
	if offset.length() > reach:
		_stick_base = pos - offset.normalized() * reach
		offset = pos - _stick_base
	_stick_knob = _stick_base + offset.limit_length(STICK_RADIUS)
	_write_stick(offset.limit_length(STICK_RADIUS) / STICK_RADIUS)

## The InputMap's own 0.25 deadzone applies on top, same as for a real stick.
func _write_stick(v: Vector2) -> void:
	_set_strength(_action("right"), maxf(v.x, 0.0))
	_set_strength(_action("left"), maxf(-v.x, 0.0))
	_set_strength(_action("down"), maxf(v.y, 0.0))
	_set_strength(_action("up"), maxf(-v.y, 0.0))

func _set_strength(action: String, strength: float) -> void:
	if strength > 0.001:
		_hold(action, strength)
	else:
		_let_go(action)

func _hold(action: String, strength: float) -> void:
	Input.action_press(action, strength)
	_pressed[action] = true

## Only releases actions this node pressed. Releasing blindly would cancel a
## key the player is holding on a keyboard at the same moment.
func _let_go(action: String) -> void:
	if _pressed.has(action):
		Input.action_release(action)
		_pressed.erase(action)

func _action(what: String) -> String:
	return "p%d_%s" % [slot + 1, what]

func _has_ball() -> bool:
	return is_instance_valid(ball) and ball.alive

# --- layout -----------------------------------------------------------------

func _margins() -> Dictionary:
	return Controls.safe_margins()

func _dash_center() -> Vector2:
	var m := _margins()
	return Vector2(size.x - m["right"] - DASH_RADIUS - 28.0,
		size.y - m["bottom"] - DASH_RADIUS - 34.0)

func _stick_rest() -> Vector2:
	var m := _margins()
	return Vector2(m["left"] + STICK_RADIUS + 44.0, size.y - m["bottom"] - STICK_RADIUS - 34.0)

## Width taken from each edge by the stick and the dash button, plus a little
## air, so the camera keeps the arena out from under the player's thumbs.
func _side_bands() -> float:
	if size.x <= 0.0:
		return 0.0
	var left := _stick_rest().x + STICK_RADIUS + 16.0
	var right := size.x - _dash_center().x + DASH_RADIUS + 16.0
	return left + right

func _pause_rect() -> Rect2:
	var m := _margins()
	return Rect2(Vector2(m["left"], m["top"]), Vector2(PAUSE_SIZE, PAUSE_SIZE))

# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	_draw_pause()
	if not _has_ball():
		return
	var color: Color = ball.stats["color"]
	_draw_stick(color)
	_draw_dash(color)

func _draw_pause() -> void:
	var r := _pause_rect()
	draw_rect(r, Color(0, 0, 0, 0.45))
	var bar := Vector2(12.0, PAUSE_SIZE * 0.42)
	var gap := 10.0
	var top := r.position.y + (PAUSE_SIZE - bar.y) * 0.5
	var left := r.position.x + (PAUSE_SIZE - bar.x * 2.0 - gap) * 0.5
	draw_rect(Rect2(Vector2(left, top), bar), Color(1, 1, 1, 0.9))
	draw_rect(Rect2(Vector2(left + bar.x + gap, top), bar), Color(1, 1, 1, 0.9))

func _draw_stick(color: Color) -> void:
	var active := _stick_index != -1
	var base := _stick_base if active else _stick_rest()
	var knob := _stick_knob if active else base
	var alpha := 0.9 if active else 0.35
	draw_circle(base, STICK_RADIUS, Color(0, 0, 0, 0.28 * alpha))
	draw_arc(base, STICK_RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.55 * alpha), 3.0, true)
	draw_circle(knob, KNOB_RADIUS, Color(color.r, color.g, color.b, 0.75 * alpha))
	draw_arc(knob, KNOB_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.8 * alpha), 2.5, true)
	if not active:
		_draw_label(base + Vector2(0.0, STICK_RADIUS + 26.0), "MOVE", 18, Color(1, 1, 1, 0.5))

func _draw_dash(color: Color) -> void:
	var center := _dash_center()
	var charge := ball.dash_charge()
	var charged := charge >= 1.0
	var held := _dash_index != -1
	var radius := DASH_RADIUS * (0.92 if held else 1.0)
	var fill := Color(color.r, color.g, color.b, 0.85 if charged else 0.3)
	if held:
		fill = fill.lightened(0.25)
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 64, Color(1, 1, 1, 0.35), 3.0, true)
	if not charged:
		# Cooldown sweeps clockwise from twelve o'clock.
		draw_arc(center, radius + 7.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 64,
			Color(1, 1, 1, 0.9), 6.0, true)
	_draw_label(center, "DASH", 26, Color(1, 1, 1, 1.0 if charged else 0.55))

func _draw_label(center: Vector2, text: String, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var ascent := _font.get_ascent(font_size)
	var descent := _font.get_descent(font_size)
	var baseline := center + Vector2(-width * 0.5, (ascent - descent) * 0.5)
	draw_string_outline(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6,
		Color(0, 0, 0, 0.6 * color.a))
	draw_string(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
