extends CanvasLayer
## Everything 2D: score bar, announcements, the lobby, the match-end choice,
## the pause menu and the on-screen touch controls.
##
## The HUD never changes game state itself. Clicks, taps and the menu-level keys
## become requests (the signals below) and main.gd decides what they mean. All
## wording follows Controls.mode, so a hint always names the thing in your hand:
## a key on a keyboard, a button on a pad, or nothing at all on a touchscreen,
## where the button to press is right there on screen.

signal start_requested
signal rematch_requested
signal lobby_requested
signal restart_requested
signal pause_requested
signal resume_requested
signal slot_pressed(slot: int)
signal character_step(slot: int, step: int)

const KEY_HINTS := ["WASD + Space", "Arrows + Shift", "IJKL + N", "TFGH + B"]
## Below this many UI units of height the lobby drops its tagline and tightens
## up. A landscape phone at 1.35x UI scale has ~533.
const COMPACT_HEIGHT := 600.0
const CARD_WIDTH := 226.0

@onready var _root: Control = $Root
@onready var _top_bar: Control = $Root/TopBar
@onready var _scores: HBoxContainer = $Root/TopBar/Scores
@onready var _round_label: Label = $Root/RoundLabel
@onready var _message: Label = $Root/Centre/Message
@onready var _sub: Label = $Root/Centre/Sub
@onready var _actions: HBoxContainer = $Root/Centre/Actions
@onready var _touch: Control = $Root/Touch
@onready var _lobby: Control = $Root/Lobby
@onready var _title: Label = $Root/Lobby/Panel/Title
@onready var _tagline: Label = $Root/Lobby/Panel/Tagline
@onready var _spacers: Array[Control] = [$Root/Lobby/Panel/Spacer, $Root/Lobby/Panel/Spacer2]
@onready var _lobby_slots: HBoxContainer = $Root/Lobby/Panel/Slots
@onready var _start_row: HBoxContainer = $Root/Lobby/Panel/StartRow
@onready var _lobby_hint: Label = $Root/Lobby/Panel/Hint
@onready var _lobby_hint2: Label = $Root/Lobby/Panel/Hint2
@onready var _pause: Control = $Root/Pause
@onready var _pause_buttons: VBoxContainer = $Root/Pause/Panel/Buttons
@onready var _pause_hint: Label = $Root/Pause/Panel/Hint
@onready var _rotate: Control = $Root/Rotate

var _chips: Array[Dictionary] = []
var _slot_cards: Array[Dictionary] = []
var _phase := &"lobby"   ## &"lobby", &"match" or &"match_end"
var _paused := false
var _compact := false
var _resume_button: Button

func _ready() -> void:
	_build_chips()
	_build_slot_cards()
	_build_buttons()
	set_message("", "")
	_touch.pause_requested.connect(func() -> void: pause_requested.emit())
	Controls.mode_changed.connect(_on_mode_changed)
	_root.resized.connect(_apply_layout)
	_apply_layout()

# --- phase, pause, and the keys that drive menus -----------------------------

## Called by main whenever the match moves between lobby, play and results.
func set_phase(phase: StringName) -> void:
	_phase = phase
	if phase != &"match_end":
		_actions.visible = false
	_update_touch()

## Keeps running while the tree is paused (process_mode = ALWAYS in the scene),
## which is what lets the same key both open and close the pause menu. Doing
## both in one place also means one key press can only ever toggle once.
func _process(_delta: float) -> void:
	if _phase != &"match":
		return
	if Input.is_action_just_pressed("game_pause"):
		if _paused:
			resume_requested.emit()
		else:
			pause_requested.emit()
	elif _paused and Input.is_action_just_pressed("game_back"):
		resume_requested.emit()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Android's back button (quit_on_go_back is off in project settings).
			match _phase:
				&"lobby":
					get_tree().quit()
				&"match_end":
					lobby_requested.emit()
				_:
					if _paused:
						resume_requested.emit()
					else:
						pause_requested.emit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Switching apps or taking a call mid-round should not cost you the
			# round. Desktop players alt-tab on purpose, so only handhelds.
			if _phase == &"match" and not _paused and Controls.is_handheld():
				pause_requested.emit()

func show_pause(value: bool) -> void:
	_paused = value
	_pause.visible = value
	_update_touch()
	_refresh_pause_hint()
	_focus_pause()

func _focus_pause() -> void:
	# Pads and keyboards navigate the menu with focus; a touchscreen does not,
	# and a focus ring on a phone just looks like a stuck highlight.
	if _paused and not Controls.is_touch():
		_resume_button.grab_focus()
	elif _pause.get_viewport():
		_pause.get_viewport().gui_release_focus()

## Which slot the on-screen stick drives, and that slot's ball (null if none).
func set_touch_player(slot: int, ball: BumperBall) -> void:
	_touch.slot = maxi(slot, 0)
	_touch.ball = ball

func _update_touch() -> void:
	_touch.set_active(Controls.is_touch() and _phase == &"match" and not _paused)

func _on_mode_changed(_mode: int) -> void:
	_update_touch()
	_refresh_pause_hint()
	_refresh_match_hint()
	if _lobby.visible:
		refresh_lobby()
	if _paused:
		_focus_pause()

# --- score bar -------------------------------------------------------------

func _build_chips() -> void:
	for child in _scores.get_children():
		child.queue_free()
	_chips.clear()
	for i in GameConfig.MAX_PLAYERS:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.45)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(10)
		style.border_width_bottom = 4
		panel.add_theme_stylebox_override("panel", style)

		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 0)
		panel.add_child(box)

		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 18)
		box.add_child(name_label)

		var score_label := Label.new()
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_label.add_theme_font_size_override("font_size", 34)
		box.add_child(score_label)

		_scores.add_child(panel)
		_chips.append({"panel": panel, "style": style, "name": name_label, "score": score_label})

func refresh_scores(alive_slots: Array = []) -> void:
	for i in _chips.size():
		var chip := _chips[i]
		var active: bool = GameConfig.slots[i]["control"] != GameConfig.Driver.OFF
		chip["panel"].visible = active
		if not active:
			continue
		var character := GameConfig.character_of(i)
		var color: Color = character["color"]
		var who := "P%d" % (i + 1) if GameConfig.is_human(i) else "CPU"
		chip["name"].text = "%s  %s" % [who, character["name"]]
		chip["name"].add_theme_color_override("font_color", color)
		chip["score"].text = str(GameConfig.slots[i]["score"])
		chip["style"].border_color = color
		# Dim anyone already knocked out of the current round.
		var out: bool = alive_slots.size() > 0 and not alive_slots.has(i)
		chip["panel"].modulate = Color(1, 1, 1, 0.35) if out else Color(1, 1, 1, 1)

func set_round(text: String) -> void:
	_round_label.text = text

# --- centre announcements --------------------------------------------------

func set_message(main_text: String, sub_text: String = "", color: Color = Color.WHITE) -> void:
	_message.text = main_text
	_message.add_theme_color_override("font_color", color)
	_sub.text = sub_text
	_message.visible = main_text != ""
	_sub.visible = sub_text != ""

func pop_message() -> void:
	# Small scale punch so the countdown reads as a beat rather than a text swap.
	# The label has just had its text replaced, so wait for the container to lay
	# it out -- reading size first gives (0, 0) and pops from the corner.
	await get_tree().process_frame
	_message.pivot_offset = _message.size * 0.5
	_message.scale = Vector2(1.45, 1.45)
	var tween := create_tween()
	tween.tween_property(_message, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The match is over: name the winner.
func show_match_result(title: String, color: Color) -> void:
	set_message(title, "", color)
	pop_message()

## Then, once it has been on screen a moment, offer the two ways on.
func show_match_actions() -> void:
	_actions.visible = true
	_refresh_match_hint()

func _refresh_match_hint() -> void:
	if not _actions.visible:
		return
	match Controls.mode:
		Controls.Mode.GAMEPAD:
			_sub.text = "Start: rematch  •  B: lobby"
		Controls.Mode.KEYBOARD:
			_sub.text = "Enter: rematch  •  Esc: lobby"
		_:
			_sub.text = ""
	_sub.visible = _sub.text != ""

func _refresh_pause_hint() -> void:
	match Controls.mode:
		Controls.Mode.GAMEPAD:
			_pause_hint.text = "Start or B to resume  •  D-pad and A to choose"
		Controls.Mode.KEYBOARD:
			_pause_hint.text = "Esc to resume  •  R restarts the match"
		_:
			_pause_hint.text = ""
	_pause_hint.visible = _pause_hint.text != ""

# --- buttons -----------------------------------------------------------------

func _build_buttons() -> void:
	# Lobby and results buttons take no focus: in those screens every pad and
	# keyboard slot has its own keys, and a focused button would swallow Space
	# and A (ui_accept) from player 1. The pause menu is the one place a pad
	# player needs to pick between options, so it does navigate by focus.
	var start := _button("START", true, false)
	start.pressed.connect(func() -> void: start_requested.emit())
	_start_row.add_child(start)

	var rematch := _button("REMATCH", true, false)
	rematch.pressed.connect(func() -> void: rematch_requested.emit())
	_actions.add_child(rematch)
	var lobby := _button("LOBBY", false, false)
	lobby.pressed.connect(func() -> void: lobby_requested.emit())
	_actions.add_child(lobby)

	_resume_button = _button("RESUME", true, true)
	_resume_button.pressed.connect(func() -> void: resume_requested.emit())
	var restart := _button("RESTART MATCH", false, true)
	restart.pressed.connect(func() -> void: restart_requested.emit())
	var quit := _button("QUIT TO LOBBY", false, true)
	quit.pressed.connect(func() -> void: lobby_requested.emit())
	for b in [_resume_button, restart, quit]:
		b.custom_minimum_size.x = 320.0
		_pause_buttons.add_child(b)

func _button(text: String, primary: bool, focusable: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL if focusable else Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 64 units tall is ~47 pt on a phone at 1.35x: comfortably above the 44 pt
	# minimum tap target.
	b.custom_minimum_size = Vector2(240.0 if primary else 200.0, 64.0)
	b.add_theme_font_size_override("font_size", 26)
	var accent := Color(1, 0.86, 0.48) if primary else Color(0.62, 0.68, 0.82)
	b.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.1, 0.18, 0.94), accent))
	b.add_theme_stylebox_override("hover", _button_style(Color(0.14, 0.17, 0.28, 0.96), accent))
	b.add_theme_stylebox_override("pressed", _button_style(Color(0.22, 0.26, 0.4, 1.0), accent.lightened(0.3)))
	b.add_theme_stylebox_override("disabled", _button_style(Color(0.06, 0.07, 0.1, 0.8), accent.darkened(0.5)))
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.set_border_width_all(4)
	ring.border_color = Color(1, 1, 1, 0.95)
	ring.set_corner_radius_all(16)
	ring.set_expand_margin_all(5)
	b.add_theme_stylebox_override("focus", ring)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, Color(1, 1, 1))
	return b

func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(3)
	s.set_corner_radius_all(14)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

# --- lobby -----------------------------------------------------------------

func _build_slot_cards() -> void:
	for child in _lobby_slots.get_children():
		child.queue_free()
	_slot_cards.clear()
	for i in GameConfig.MAX_PLAYERS:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(CARD_WIDTH, 250)
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.08, 0.14, 0.9)
		style.set_corner_radius_all(14)
		style.set_content_margin_all(14)
		style.set_border_width_all(3)
		panel.add_theme_stylebox_override("panel", style)
		# The whole card is the button for "who plays this slot". Tapping,
		# clicking and the slot's own dash key all do the same thing.
		panel.gui_input.connect(_on_card_input.bind(i))
		panel.mouse_entered.connect(func() -> void: style.set_border_width_all(5))
		panel.mouse_exited.connect(func() -> void: style.set_border_width_all(3))

		# Top-aligned, not centred: the human card carries an extra line of key
		# hints, and centring pushed its title, swatch and name out of line with
		# the CPU cards sitting next to it.
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		box.alignment = BoxContainer.ALIGNMENT_BEGIN
		box.add_theme_constant_override("separation", 6)
		panel.add_child(box)

		var slot_label := Label.new()
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_label.add_theme_font_size_override("font_size", 26)
		box.add_child(slot_label)

		var swatch := ColorRect.new()
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.custom_minimum_size = Vector2(0, 54)
		box.add_child(swatch)

		# Character name flanked by the arrows that change it, so the thing you
		# are changing sits between the two buttons that change it.
		var name_row := HBoxContainer.new()
		name_row.mouse_filter = Control.MOUSE_FILTER_PASS
		name_row.add_theme_constant_override("separation", 4)
		box.add_child(name_row)
		var prev := _arrow("‹")
		prev.pressed.connect(func() -> void: character_step.emit(i, -1))
		name_row.add_child(prev)
		var char_label := Label.new()
		char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		char_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		char_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		char_label.add_theme_font_size_override("font_size", 24)
		name_row.add_child(char_label)
		var next := _arrow("›")
		next.pressed.connect(func() -> void: character_step.emit(i, 1))
		name_row.add_child(next)

		var weight_label := Label.new()
		weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		weight_label.add_theme_font_size_override("font_size", 16)
		weight_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.9))
		box.add_child(weight_label)

		var state_label := Label.new()
		state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		state_label.add_theme_font_size_override("font_size", 15)
		state_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.82))
		# Reserve room for the tallest variant so the card never resizes as the
		# slot cycles between CPU, player and empty.
		state_label.custom_minimum_size = Vector2(0, 62)
		box.add_child(state_label)

		_lobby_slots.add_child(panel)
		_slot_cards.append({
			"panel": panel, "style": style, "slot": slot_label, "swatch": swatch,
			"char": char_label, "weight": weight_label, "state": state_label,
		})

func _arrow(glyph: String) -> Button:
	var b := Button.new()
	b.text = glyph
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 52 units is ~38 pt on a phone. The arrows sit inside a card that is itself
	# tappable, so a near miss cycles the slot rather than doing nothing; any
	# larger and the character name no longer fits between them.
	b.custom_minimum_size = Vector2(52, 52)
	b.add_theme_font_size_override("font_size", 36)
	b.add_theme_stylebox_override("normal", _button_style(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.18)))
	b.add_theme_stylebox_override("hover", _button_style(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.4)))
	b.add_theme_stylebox_override("pressed", _button_style(Color(1, 1, 1, 0.26), Color(1, 1, 1, 0.7)))
	for s in ["normal", "hover", "pressed"]:
		var box: StyleBoxFlat = b.get_theme_stylebox(s)
		box.content_margin_left = 0
		box.content_margin_right = 0
		box.content_margin_top = 0
		box.content_margin_bottom = 4
		box.set_corner_radius_all(10)
		box.set_border_width_all(2)
	return b

func _on_card_input(event: InputEvent, slot: int) -> void:
	# A tap arrives here as an emulated left click, so this covers both.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_pressed.emit(slot)

func refresh_lobby() -> void:
	var touch_slot := GameConfig.first_human_slot()
	for i in _slot_cards.size():
		var card := _slot_cards[i]
		var control: int = GameConfig.slots[i]["control"]
		var character := GameConfig.character_of(i)
		var color: Color = character["color"]

		card["slot"].text = "SLOT %d" % (i + 1)
		card["slot"].add_theme_color_override("font_color", color)
		card["swatch"].color = color
		card["char"].text = character["name"]
		card["weight"].text = str(character["weight"]).to_upper()
		card["style"].border_color = color
		card["state"].text = _card_state(i, control, touch_slot)
		var ink := Color(0.65, 0.7, 0.82)
		if control == GameConfig.Driver.HUMAN:
			ink = Color(1, 1, 1)
		elif control == GameConfig.Driver.OFF:
			ink = Color(0.45, 0.48, 0.58)
		card["state"].add_theme_color_override("font_color", ink)
		card["panel"].modulate = Color(1, 1, 1, 0.38) if control == GameConfig.Driver.OFF else Color(1, 1, 1, 1)

	var humans := GameConfig.human_count()
	var first := "First to %d wins" % GameConfig.points_to_win
	var who := "%d human player%s" % [humans, "" if humans == 1 else "s"]
	match Controls.mode:
		Controls.Mode.TOUCH:
			_lobby_hint.text = "%s    •    %s" % [first, who]
			_lobby_hint2.text = "Tap a card: CPU → Player → Empty   •   ‹ › change character"
		Controls.Mode.GAMEPAD:
			_lobby_hint.text = "%s    •    Start to begin    •    %s" % [first, who]
			_lobby_hint2.text = "Left / Right: character   •   A: CPU → Player → Empty   •   B steps back"
		_:
			_lobby_hint.text = "%s    •    Enter to start    •    %s" % [first, who]
			_lobby_hint2.text = "Left / Right: character   •   Dash key: CPU → Player → Empty   •   or click a card"

func _card_state(i: int, control: int, touch_slot: int) -> String:
	var n := i + 1
	var key: String = KEY_HINTS[i].split(" + ")[1]
	match Controls.mode:
		Controls.Mode.TOUCH:
			match control:
				GameConfig.Driver.HUMAN:
					if i == touch_slot:
						return "YOU\nOn-screen controls\nTap to sit out"
					return "PLAYER %d\nGamepad %d\nTap to sit out" % [n, n]
				GameConfig.Driver.CPU:
					return "CPU\nTap to change"
				_:
					return "EMPTY\nTap to add a CPU"
		Controls.Mode.GAMEPAD:
			match control:
				GameConfig.Driver.HUMAN:
					return "PLAYER %d\nGamepad %d\nA again to sit out" % [n, n]
				GameConfig.Driver.CPU:
					return "CPU\nA on pad %d to join" % n
				_:
					return "EMPTY\nA on pad %d to fill" % n
		_:
			match control:
				GameConfig.Driver.HUMAN:
					return "PLAYER %d\n%s\n%s again to sit out" % [n, KEY_HINTS[i], key]
				GameConfig.Driver.CPU:
					return "CPU\npress %s to take over" % key
				_:
					return "EMPTY\npress %s to fill" % key

func show_lobby(value: bool) -> void:
	_lobby.visible = value
	# The score bar is all zeroes in the lobby and just crowds the title.
	_top_bar.visible = not value
	if value:
		refresh_lobby()

## Short screens (a phone at 1.35x has ~533 units) lose the tagline and some
## air so the cards, START and hints all still fit without scrolling.
func _apply_layout() -> void:
	_compact = _root.size.y < COMPACT_HEIGHT
	_tagline.visible = not _compact
	_title.add_theme_font_size_override("font_size", 48 if _compact else 76)
	$Root/Lobby/Panel.add_theme_constant_override("separation", 6 if _compact else 10)
	for s in _spacers:
		s.custom_minimum_size.y = 0.0 if _compact else 18.0
	for card in _slot_cards:
		card["panel"].custom_minimum_size = Vector2(CARD_WIDTH, 0 if _compact else 250)
		card["swatch"].custom_minimum_size.y = 30.0 if _compact else 54.0
	# Native builds lock landscape (project settings); a browser cannot, so a
	# phone held upright gets asked to turn -- and a match in progress waits.
	var portrait := Controls.is_handheld() and _root.size.y > _root.size.x
	_rotate.visible = portrait
	if portrait and _phase == &"match" and not _paused:
		pause_requested.emit()
	# Keep menus clear of notches and the home indicator.
	var m := Controls.safe_margins()
	for panel in [$Root/Lobby/Panel, $Root/Pause/Panel]:
		panel.offset_left = m["left"]
		panel.offset_top = m["top"]
		panel.offset_right = -m["right"]
		panel.offset_bottom = -m["bottom"]
