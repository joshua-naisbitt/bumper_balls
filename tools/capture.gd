extends Node
## Demo capture rig. Wraps the real game scene, drives slot 1 with synthetic
## keyboard events (so the actual InputMap -> BumperBall path is exercised, not a
## backdoor), and grabs screenshots on a schedule.
##
##   godot --path . res://tools/capture.tscn -- --drive --shot=/tmp/a.png:8 --quit-after=30
##   godot --headless --path . res://tools/capture.tscn -- --input-test

const KEYS := {
	"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D,
	"dash": KEY_SPACE, "start": KEY_ENTER,
}

const DEADZONE := 0.38      ## Quantise to 8-way, like a real keyboard player.

@onready var main: Node3D = $Main

var _drive := false
var _held := {}
var _started := false
var _dash_gate := 0.0
var _start_delay := 0.0
var _elapsed := 0.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--input-test"):
		await _input_test()
		return
	_drive = args.has("--drive")
	for a in args:
		if a.begins_with("--start-delay="):
			_start_delay = float(a.split("=")[1])
	for a in args:
		if a.begins_with("--shot="):
			var spec := a.split("=", true, 1)[1]
			var cut := spec.rfind(":")
			if cut <= 0:
				push_error("--shot needs PATH:SECONDS, got '%s'" % spec)
				continue
			_queue_shot(spec.substr(0, cut), float(spec.substr(cut + 1)))
		elif a.begins_with("--quit-after="):
			_queue_quit(float(a.split("=")[1]))

func _queue_shot(path: String, at: float) -> void:
	await get_tree().create_timer(at).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[shot] ", path)

func _queue_quit(at: float) -> void:
	await get_tree().create_timer(at).timeout
	Sfx.quit_game()

# --- synthetic input -------------------------------------------------------

func _key(action: String, down: bool) -> void:
	if _held.get(action, false) == down:
		return
	_held[action] = down
	var e := InputEventKey.new()
	e.physical_keycode = KEYS[action]
	e.pressed = down
	Input.parse_input_event(e)

func _tap(action: String) -> void:
	_key(action, true)
	await get_tree().process_frame
	_key(action, false)

func _process(delta: float) -> void:
	if not _drive:
		return
	_dash_gate -= delta
	_elapsed += delta

	# Press Enter on the lobby exactly as a player would, after letting the
	# character-select screen sit on camera for a moment.
	if main.state == main.State.LOBBY and _elapsed >= _start_delay:
		if not _started:
			_started = true
			await _tap("start")
		return
	# Rematch once the match result has been on screen long enough to read.
	if main.state == main.State.MATCH_END and _dash_gate <= 0.0:
		_dash_gate = 6.0
		await _tap("start")
		return

	var me: BumperBall = null
	for b in main.balls:
		if b.is_human and b.alive:
			me = b
			break
	if me == null or main.state != main.State.PLAYING:
		_release_all()
		return

	var here := Vector2(me.global_position.x, me.global_position.z)
	var arena: Arena = main.arena
	var ratio := here.length() / maxf(arena.play_radius, 0.001)
	var to_centre := (-here).normalized() if here.length() > 0.01 else Vector2.ZERO

	var target: BumperBall = null
	var best := INF
	for b in main.balls:
		if b == me or not b.alive:
			continue
		var d := here.distance_to(Vector2(b.global_position.x, b.global_position.z))
		if d < best:
			best = d
			target = b

	var attack := to_centre
	if target:
		var there := Vector2(target.global_position.x, target.global_position.z)
		attack = (there - here).normalized()

	var danger: float = clampf(smoothstep(0.6, 1.0, ratio), 0.0, 1.0)
	var desire := attack.lerp(to_centre, danger)
	if desire.length() < 0.01:
		_release_all()
		return
	desire = desire.normalized()

	# The ball un-rotates human input by the camera yaw, so rotate into that frame.
	var stick := desire.rotated(GameConfig.camera_yaw)
	_key("right", stick.x > DEADZONE)
	_key("left", stick.x < -DEADZONE)
	_key("down", stick.y > DEADZONE)
	_key("up", stick.y < -DEADZONE)

	if target and best < 3.6 and danger < 0.5 and _dash_gate <= 0.0:
		_dash_gate = 1.4
		await _tap("dash")

func _release_all() -> void:
	for k in ["up", "down", "left", "right"]:
		_key(k, false)

# --- headless check that the generated InputMap actually works -------------

func _input_test() -> void:
	var missing := []
	for p in range(1, 5):
		for a in ["up", "down", "left", "right", "dash", "join", "leave"]:
			var action := "p%d_%s" % [p, a]
			if not InputMap.has_action(action):
				missing.append(action)
	for a in ["game_start", "game_restart", "game_back", "game_pause"]:
		if not InputMap.has_action(a):
			missing.append(a)
	print("[input] missing actions: ", str(missing) if missing.size() > 0 else "none")

	# Every slot's keyboard binding, pressed for real through the InputMap.
	var layouts := [
		[KEY_W, KEY_S, KEY_A, KEY_D, KEY_SPACE],
		[KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT],
		[KEY_I, KEY_K, KEY_J, KEY_L, KEY_N],
		[KEY_T, KEY_G, KEY_F, KEY_H, KEY_B],
	]
	for p in range(4):
		var results := []
		for idx in 4:
			var e := InputEventKey.new()
			e.physical_keycode = layouts[p][idx]
			e.pressed = true
			Input.parse_input_event(e)
			await get_tree().process_frame
			results.append(Input.get_vector(
				"p%d_left" % (p + 1), "p%d_right" % (p + 1),
				"p%d_up" % (p + 1), "p%d_down" % (p + 1)))
			e = InputEventKey.new()
			e.physical_keycode = layouts[p][idx]
			e.pressed = false
			Input.parse_input_event(e)
			await get_tree().process_frame
		var dash := InputEventKey.new()
		dash.physical_keycode = layouts[p][4]
		dash.pressed = true
		Input.parse_input_event(dash)
		await get_tree().process_frame
		var dash_ok: bool = Input.is_action_pressed("p%d_dash" % (p + 1))
		dash.pressed = false
		Input.parse_input_event(dash)
		await get_tree().process_frame
		print("[input] P%d up=%s down=%s left=%s right=%s dash=%s" % [
			p + 1, results[0], results[1], results[2], results[3], dash_ok])
	Sfx.quit_game()
