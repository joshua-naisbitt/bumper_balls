extends Node
## Stages every screen of the real UI and screenshots it, for checking layout
## across form factors and input modes without playing a match to each one.
##
##   xvfb-run godot --path . res://tools/ui_shots.tscn --resolution 1560x720 -- OUT_DIR --phone

@onready var main: Node3D = $Main

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	GameConfig.ai_seed = 3
	await _frames(30)
	await _shot(out, "1-lobby")

	main._start_match()
	while main.state != main.State.PLAYING:
		await _frames(1)
	await _seconds(2.5)
	# Hold the stick up-right so the shot shows it in use, not at rest.
	var touch: Control = main.hud._touch
	if touch.visible:
		var from := Vector2(touch.size.x * 0.16, touch.size.y * 0.74)
		_touch(0, from, true)
		_drag(0, from + Vector2(60, -40))
	await _frames(20)
	await _shot(out, "2-play")
	if touch.visible:
		_touch(0, Vector2.ZERO, false)

	main._set_paused(true)
	await _frames(10)
	await _shot(out, "3-pause")
	main._set_paused(false)

	GameConfig.slots[0]["score"] = GameConfig.points_to_win
	main.hud.refresh_scores()   # the real round-end path does this too
	main._set_state(main.State.MATCH_END)
	main.hud.show_match_result("%s TAKES THE MATCH" % GameConfig.character_of(0)["name"],
		GameConfig.character_of(0)["color"])
	main.hud.show_match_actions()
	await _frames(20)
	await _shot(out, "4-results")
	Sfx.quit_game()

func _shot(dir: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, label])
	print("[ui_shots] ", label)

func _to_window(ui: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * ui

func _touch(index: int, ui_pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _to_window(ui_pos)
	e.pressed = pressed
	Input.parse_input_event(e)

func _drag(index: int, ui_pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = _to_window(ui_pos)
	Input.parse_input_event(e)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout
