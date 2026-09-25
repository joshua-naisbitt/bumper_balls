extends Node
## Touch regression test. Drives the real game with synthetic ScreenTouch /
## ScreenDrag events -- the same events a phone produces -- and checks the
## results. Runs in a real window so layout has real sizes:
##
##   xvfb-run godot --path . res://tools/touch_test.tscn --resolution 1600x740 -- --phone
##
## Prints one PASS/FAIL line per check and exits non-zero on any failure.

@onready var main: Node3D = $Main

var _failures := 0
var _checks := 0

func _ready() -> void:
	await _frames(20)
	var hud: CanvasLayer = main.hud
	var D := GameConfig.Driver

	_check(Controls.is_touch(), "starts in touch mode on a handheld")
	_check(get_tree().root.content_scale_factor > 1.0, "handheld UI is scaled up (%.2f)" % get_tree().root.content_scale_factor)

	# --- lobby: cards and arrows are tappable --------------------------------
	var card: Control = hud._slot_cards[1]["panel"]
	var before: int = GameConfig.slots[1]["control"]
	await _tap(card.get_global_rect().get_center() + Vector2(0, 60))
	_check(GameConfig.slots[1]["control"] != before, "tapping a card cycles its slot (%d -> %d)" % [before, GameConfig.slots[1]["control"]])
	while GameConfig.slots[1]["control"] != before:
		await _tap(card.get_global_rect().get_center() + Vector2(0, 60))

	var char_before: int = GameConfig.slots[0]["character"]
	var next_arrow: Button = hud._slot_cards[0]["char"].get_parent().get_child(2)
	var slot_before: int = GameConfig.slots[0]["control"]
	await _tap(next_arrow.get_global_rect().get_center())
	_check(GameConfig.slots[0]["character"] != char_before, "› arrow changes character")
	_check(GameConfig.slots[0]["control"] == slot_before, "› arrow does not also cycle the card underneath it")

	# Two still humans and nobody else, so nothing bumps the ball mid-measurement.
	GameConfig.slots[0]["control"] = D.HUMAN
	GameConfig.slots[1]["control"] = D.HUMAN
	GameConfig.slots[2]["control"] = D.OFF
	GameConfig.slots[3]["control"] = D.OFF
	hud.refresh_lobby()
	await _frames(2)

	var start: Button = hud._start_row.get_child(0)
	await _tap(start.get_global_rect().get_center())
	_check(main.state == main.State.COUNTDOWN, "tapping START starts the match")
	_check(hud._touch.visible, "touch controls appear for the match")

	while main.state != main.State.PLAYING:
		await _frames(1)
	await _frames(10)

	# --- stick: push right on screen, ball goes camera-right in the world ----
	var ball: BumperBall = main._ball_for_slot(0)
	var touch: Control = hud._touch
	var from := Vector2(touch.size.x * 0.2, touch.size.y * 0.7)
	var cam_right: Vector3 = main.camera_rig.camera.global_transform.basis.x
	cam_right = Vector3(cam_right.x, 0, cam_right.z).normalized()
	var p0 := ball.global_position
	_touch_event(0, from, true)
	for i in 12:
		_drag_event(0, from + Vector2(8.0 * (i + 1), 0))
		await _frames(1)
	await _seconds(0.8)
	var moved := ball.global_position - p0
	moved.y = 0.0
	var along := moved.dot(cam_right)
	_check(along > 2.0 and along > moved.length() * 0.8,
		"stick right moves the ball camera-right (%.2f of %.2f units along)" % [along, moved.length()])

	# --- multi-touch: dash with a second finger while the stick is held ------
	var dash_at: Vector2 = touch._dash_center()
	_touch_event(1, dash_at, true)
	await _frames(3)
	_touch_event(1, dash_at, false)
	await _frames(2)
	_check(ball.dash_charge() < 1.0, "second finger on DASH dashes while the stick is held")
	_touch_event(0, from, false)
	await _frames(3)
	_check(not Input.is_action_pressed("p1_right"), "lifting the stick finger releases the input")

	# --- pause via the on-screen button, resume via the menu -----------------
	await _tap(touch._pause_rect().get_center())
	_check(get_tree().paused, "pause button pauses the game")
	_check(hud._pause.visible and not touch.visible, "pause menu shows, touch controls hide")
	var frozen_at := ball.global_position
	await _seconds(0.5)
	_check(ball.global_position.distance_to(frozen_at) < 0.001, "physics is frozen while paused")
	await _tap(hud._resume_button.get_global_rect().get_center())
	_check(not get_tree().paused and touch.visible, "RESUME unpauses and brings the controls back")

	# --- Android back button --------------------------------------------------
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(2)
	_check(get_tree().paused, "Android back pauses mid-match")
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(2)
	_check(not get_tree().paused, "Android back again resumes")

	# --- backgrounding the app ------------------------------------------------
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	_check(get_tree().paused, "losing focus on a handheld auto-pauses")

	# --- pause menu -> lobby -----------------------------------------------------
	var quit: Button = hud._pause_buttons.get_child(2)
	await _tap(quit.get_global_rect().get_center())
	_check(main.state == main.State.LOBBY and not get_tree().paused, "QUIT TO LOBBY returns to the lobby unpaused")
	_check(not touch.visible, "touch controls hide in the lobby")

	# --- a keypress flips the UI to keyboard wording ---------------------------
	var key := InputEventKey.new()
	key.physical_keycode = KEY_A
	key.pressed = true
	Input.parse_input_event(key)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await _frames(2)
	_check(Controls.mode == Controls.Mode.KEYBOARD, "a key press switches to keyboard mode")
	_check(str(hud._lobby_hint.text).contains("Enter"), "lobby hints switch to keyboard wording")

	print("[touch_test] %d/%d passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

# --- helpers ------------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("[touch_test] %s  %s" % ["PASS" if ok else "FAIL", what])

## Events enter at window coordinates; the UI works in scaled units.
func _to_window(ui: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * ui

func _touch_event(index: int, ui_pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _to_window(ui_pos)
	e.pressed = pressed
	Input.parse_input_event(e)

func _drag_event(index: int, ui_pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = _to_window(ui_pos)
	Input.parse_input_event(e)

func _tap(ui_pos: Vector2) -> void:
	_touch_event(0, ui_pos, true)
	await _frames(2)
	_touch_event(0, ui_pos, false)
	await _frames(3)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout
