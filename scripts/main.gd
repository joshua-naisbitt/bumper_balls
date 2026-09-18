extends Node3D
## Match flow: lobby -> countdown -> round -> scoring -> repeat until someone
## reaches the target score.

const BALL_SCENE := preload("res://scenes/ball.tscn")

const START_RADIUS := 13.5
const MIN_RADIUS := 4.2
const SHRINK_DELAY := 7.0        ## Grace period before the dome starts closing in.
const SHRINK_RATE := 0.40        ## Units per second at the start of the squeeze.
const SHRINK_RAMP := 0.03        ## Added to the rate for every second that passes.

const COUNTDOWN_LENGTH := 3.0
const ROUND_END_HOLD := 2.6
const MATCH_END_HOLD := 1.2      ## Minimum time before input can skip the results.

enum State { LOBBY, COUNTDOWN, PLAYING, ROUND_END, MATCH_END }

@onready var arena: Arena = $Arena
@onready var balls_root: Node3D = $Balls
@onready var camera_rig: Node3D = $CameraRig
@onready var hud: CanvasLayer = $HUD

var state: int = State.LOBBY
var balls: Array[BumperBall] = []
var round_number := 0

var _timer := 0.0
var _round_time := 0.0
var _radius := START_RADIUS
var _last_beep := 99
var _knockout_order: Array[int] = []
var _warned := false
var _match_announced := false
var _demo := false

func _ready() -> void:
	GameConfig.reset_slots()
	arena.set_play_radius(START_RADIUS)
	_enter_lobby()
	_check_demo_mode()

## `godot -- --cpu-demo [--quit-after=SECONDS]` boots straight into an all-CPU
## match. Handy as an attract mode and as a headless smoke test of the loop.
func _check_demo_mode() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--ai-seed="):
			GameConfig.ai_seed = int(arg.split("=")[1])
	if not args.has("--cpu-demo"):
		return
	_demo = true
	for i in GameConfig.MAX_PLAYERS:
		GameConfig.slots[i]["control"] = GameConfig.Driver.CPU
	_start_match()
	for arg in args:
		if arg.begins_with("--quit-after="):
			var seconds := float(arg.split("=")[1])
			get_tree().create_timer(seconds).timeout.connect(func() -> void:
				get_tree().quit())

func _process(delta: float) -> void:
	match state:
		State.LOBBY:
			_lobby_input()
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.PLAYING:
			_tick_round(delta)
		State.ROUND_END, State.MATCH_END:
			_tick_intermission(delta)

	if state != State.LOBBY:
		if Input.is_action_just_pressed("game_back"):
			_enter_lobby()
		elif Input.is_action_just_pressed("game_restart"):
			_start_match()

	_update_camera(delta)

func _update_camera(delta: float) -> void:
	var points: Array[Vector3] = []
	for b in balls:
		if b.alive:
			points.append(b.global_position)
	camera_rig.frame(points, arena.play_radius, delta)

# --- lobby -----------------------------------------------------------------

func _enter_lobby() -> void:
	state = State.LOBBY
	_clear_balls()
	_radius = START_RADIUS
	arena.set_play_radius(_radius)
	arena.set_danger(0.0)
	hud.show_lobby(true)
	hud.set_message("", "")
	hud.set_round("")
	hud.refresh_scores()

func _lobby_input() -> void:
	var dirty := false
	for i in GameConfig.MAX_PLAYERS:
		var p := i + 1
		# One key per slot cycles CPU -> Player -> Empty. Keyboard players have no
		# other way back out: p*_leave is gamepad-only, and game_back is ignored
		# in the lobby, so a claimed slot used to be permanent.
		if Input.is_action_just_pressed("p%d_join" % p):
			GameConfig.slots[i]["control"] = _cycle_driver(i, 1)
			dirty = true
		if Input.is_action_just_pressed("p%d_leave" % p):
			GameConfig.slots[i]["control"] = _cycle_driver(i, -1)
			dirty = true
		if Input.is_action_just_pressed("p%d_left" % p):
			GameConfig.cycle_character(i, -1)
			dirty = true
		if Input.is_action_just_pressed("p%d_right" % p):
			GameConfig.cycle_character(i, 1)
			dirty = true

	if dirty:
		hud.refresh_lobby()
		Sfx.play("beep", -12.0, 1.2)

	if Input.is_action_just_pressed("game_start") and GameConfig.active_count() >= 2:
		_start_match()

## Step a slot through CPU -> Player -> Empty (or backwards), skipping Empty
## when it would leave fewer than two balls in the match.
func _cycle_driver(slot_index: int, step: int) -> int:
	var value: int = GameConfig.slots[slot_index]["control"]
	for _attempt in 3:
		value = wrapi(value + step, 0, 3)
		if value != GameConfig.Driver.OFF or GameConfig.active_count() > 2:
			return value
	return GameConfig.slots[slot_index]["control"]

# --- match / round ---------------------------------------------------------

func _start_match() -> void:
	GameConfig.reset_scores()
	round_number = 0
	hud.show_lobby(false)
	_spawn_balls()
	_start_round()

func _clear_balls() -> void:
	for b in balls:
		# queue_free only takes effect at the end of the frame. Until then these
		# balls still simulate and still emit, and a knockout arriving after the
		# next round has been set up would be recorded against it.
		b.knocked_out.disconnect(_on_ball_knocked_out)
		b.bumped.disconnect(_on_ball_bumped)
		b.set_physics_process(false)
		b.queue_free()
	balls.clear()

func _spawn_balls() -> void:
	_clear_balls()
	for slot_index in GameConfig.active_slots():
		var ball := BALL_SCENE.instantiate() as BumperBall
		balls_root.add_child(ball)
		ball.setup(slot_index, GameConfig.character_of(slot_index),
			GameConfig.is_human(slot_index), arena, GameConfig.ai_skill)
		ball.knocked_out.connect(_on_ball_knocked_out)
		ball.bumped.connect(_on_ball_bumped)
		balls.append(ball)

func _start_round() -> void:
	round_number += 1
	_radius = START_RADIUS
	arena.set_play_radius(_radius)
	arena.set_danger(0.0)
	_round_time = 0.0
	_knockout_order.clear()
	_warned = false
	_match_announced = false

	for i in balls.size():
		balls[i].reset_to(arena.spawn_transform(i, balls.size(), BumperBall.RADIUS))
		balls[i].set_frozen(true)

	state = State.COUNTDOWN
	_timer = COUNTDOWN_LENGTH
	_last_beep = 99
	hud.set_round("ROUND %d   •   FIRST TO %d" % [round_number, GameConfig.points_to_win])
	hud.refresh_scores(_alive_slots())

func _tick_countdown(delta: float) -> void:
	_timer -= delta
	var count := int(ceil(_timer))
	if count < _last_beep and count > 0:
		_last_beep = count
		hud.set_message(str(count), "Knock everyone else off the dome", Color.WHITE)
		hud.pop_message()
		Sfx.play("beep", -6.0)
	if _timer <= 0.0:
		hud.set_message("GO!", "", Color("ffe07a"))
		hud.pop_message()
		Sfx.play("go", -4.0)
		for b in balls:
			b.set_frozen(false)
		state = State.PLAYING
		get_tree().create_timer(0.7).timeout.connect(func() -> void:
			if state == State.PLAYING:
				hud.set_message("", ""))

func _tick_round(delta: float) -> void:
	_round_time += delta

	if _round_time > SHRINK_DELAY:
		if not _warned:
			_warned = true
			hud.set_message("", "The dome is closing in!")
			Sfx.play("warn", -4.0)
			get_tree().create_timer(2.0).timeout.connect(func() -> void:
				if state == State.PLAYING:
					hud.set_message("", ""))
		var elapsed := _round_time - SHRINK_DELAY
		var rate := SHRINK_RATE + elapsed * SHRINK_RAMP
		_radius = maxf(_radius - rate * delta, MIN_RADIUS)
		arena.set_play_radius(_radius)
		arena.set_danger(inverse_lerp(START_RADIUS, MIN_RADIUS, _radius))

	if _alive_balls().size() <= 1:
		_finish_round()

func _finish_round() -> void:
	state = State.ROUND_END
	_timer = ROUND_END_HOLD

	var survivors := _alive_balls()
	var winner_slot := -1
	if survivors.size() == 1:
		winner_slot = survivors[0].slot
	elif _knockout_order.size() > 0:
		# Everyone went over together: the last one to drop takes it.
		winner_slot = _knockout_order[_knockout_order.size() - 1]

	if winner_slot >= 0:
		GameConfig.slots[winner_slot]["score"] += 1
		var character := GameConfig.character_of(winner_slot)
		var who := "PLAYER %d" % (winner_slot + 1) if GameConfig.is_human(winner_slot) else "CPU"
		hud.set_message("%s WINS THE ROUND" % character["name"],
			"%s  •  %d point%s" % [who, GameConfig.slots[winner_slot]["score"],
				"" if GameConfig.slots[winner_slot]["score"] == 1 else "s"],
			character["color"])
		hud.pop_message()
		Sfx.play("round_win", -4.0)
	else:
		hud.set_message("DRAW", "Nobody survived", Color("aab4c8"))

	hud.refresh_scores()
	if _demo:
		print("[demo] round %d  %.1fs  rim %.1f  winner slot %d" % [
			round_number, _round_time, _radius, winner_slot])

	if GameConfig.match_winners().size() > 0:
		state = State.MATCH_END
		_timer = ROUND_END_HOLD

func _tick_intermission(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return

	if state == State.ROUND_END:
		_start_round()
		return

	# Match over: announce exactly once, then hold until someone presses a button.
	# The old guard here compared _timer against the hold length, which stayed
	# true for the whole hold and re-fired the fanfare on every single frame.
	if not _match_announced:
		_match_announced = true
		_announce_match()

	if _timer < -MATCH_END_HOLD and (Input.is_action_just_pressed("game_start") or _demo):
		_start_match()

func _announce_match() -> void:
	var winners := GameConfig.match_winners()
	if winners.is_empty():
		return
	var names := PackedStringArray()
	for w in winners:
		names.append(str(GameConfig.character_of(w)["name"]))
	var color: Color = GameConfig.character_of(winners[0])["color"]
	hud.set_message("%s TAKES THE MATCH" % " & ".join(names),
		"ENTER for a rematch  •  ESC for the lobby", color)
	hud.pop_message()
	Sfx.play("match_win", -2.0)

# --- signals / helpers -----------------------------------------------------

func _on_ball_knocked_out(ball: BumperBall) -> void:
	_knockout_order.append(ball.slot)
	camera_rig.shake(0.35)
	hud.refresh_scores(_alive_slots())

func _on_ball_bumped(strength: float) -> void:
	camera_rig.shake(strength * 0.5)

func _alive_balls() -> Array[BumperBall]:
	var out: Array[BumperBall] = []
	for b in balls:
		if b.alive:
			out.append(b)
	return out

func _alive_slots() -> Array:
	var out := []
	for b in balls:
		if b.alive:
			out.append(b.slot)
	return out

