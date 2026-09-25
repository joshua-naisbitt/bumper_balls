extends Node
## Keyboard and gamepad regression test: the same flows as touch_test.gd, driven
## by synthetic key and joypad events through the real InputMap.
##
##   xvfb-run godot --path . res://tools/desktop_test.tscn --resolution 1280x720

@onready var main: Node3D = $Main

var _failures := 0
var _checks := 0

func _ready() -> void:
	await _frames(20)
	var hud: CanvasLayer = main.hud
	var D := GameConfig.Driver

	_check(Controls.mode == Controls.Mode.KEYBOARD and not Controls.is_handheld(),
		"desktop starts in keyboard mode")
	_check(is_equal_approx(get_tree().root.content_scale_factor, 1.0), "desktop UI is not scaled")

	# Idle human vs one CPU: a round resolves on its own within a few seconds.
	GameConfig.slots[0]["control"] = D.HUMAN
	GameConfig.slots[1]["control"] = D.CPU
	GameConfig.slots[2]["control"] = D.OFF
	GameConfig.slots[3]["control"] = D.OFF
	GameConfig.points_to_win = 1
	hud.refresh_lobby()

	await _key(KEY_ENTER)
	_check(main.state == main.State.COUNTDOWN, "Enter starts the match")
	_check(not hud._touch.visible, "no touch controls in keyboard mode")

	# --- Esc pauses, focus lands on RESUME, Esc resumes -----------------------
	await _key(KEY_ESCAPE)
	_check(get_tree().paused and hud._pause.visible, "Esc pauses")
	_check(hud._resume_button.has_focus(), "keyboard pause menu focuses RESUME")
	_check(str(hud._pause_hint.text).contains("Esc"), "pause hint uses keyboard wording")
	await _key(KEY_ESCAPE)
	_check(not get_tree().paused, "Esc again resumes (one press, one toggle)")

	while main.state != main.State.PLAYING:
		await _frames(1)

	# --- pad B mid-round used to quit to the lobby; it must do nothing --------
	await _pad(JOY_BUTTON_B)
	_check(main.state == main.State.PLAYING and not get_tree().paused,
		"pad B during play no longer throws the match away")
	_check(Controls.mode == Controls.Mode.GAMEPAD, "a pad press switches to gamepad mode")

	# --- Start pauses; D-pad + A pick RESTART MATCH ---------------------------
	await _pad(JOY_BUTTON_START)
	_check(get_tree().paused, "pad Start pauses")
	_check(str(hud._pause_hint.text).contains("Start"), "pause hint uses gamepad wording")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	var restart: Button = hud._pause_buttons.get_child(1)
	_check(restart.has_focus(), "D-pad moves focus to RESTART MATCH")
	await _pad(JOY_BUTTON_A)
	_check(not get_tree().paused and main.round_number == 1 and main.state == main.State.COUNTDOWN,
		"A on RESTART MATCH restarts from round 1, unpaused")

	# --- match end: choice appears only after the hold ------------------------
	while main.state != main.State.MATCH_END:
		await _frames(1)
	await _frames(5)
	_check(not hud._actions.visible, "results hold: no rematch buttons yet")
	while not hud._actions.visible:
		await _frames(1)
	_check(str(hud._sub.text).contains("Start") and str(hud._sub.text).contains("B"),
		"match-end hint uses gamepad wording")
	await _key(KEY_Q)   # any key flips to keyboard wording
	_check(str(hud._sub.text).contains("Enter"), "match-end hint follows a switch to keyboard")
	await _key(KEY_ESCAPE)
	_check(main.state == main.State.LOBBY, "Esc on the results screen goes to the lobby")

	print("[desktop_test] %d/%d passed" % [_checks - _failures, _checks])
	Sfx.quit_game(1 if _failures > 0 else 0)

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("[desktop_test] %s  %s" % ["PASS" if ok else "FAIL", what])

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await _frames(2)

func _pad(button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await _frames(2)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
