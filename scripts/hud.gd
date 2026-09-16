extends CanvasLayer
## Score bar, centre announcements and the lobby / character select screen.

@onready var _scores: HBoxContainer = $Root/TopBar/Scores
@onready var _round_label: Label = $Root/RoundLabel
@onready var _message: Label = $Root/Centre/Message
@onready var _sub: Label = $Root/Centre/Sub
@onready var _lobby: Control = $Root/Lobby
@onready var _lobby_slots: HBoxContainer = $Root/Lobby/Panel/Slots
@onready var _lobby_hint: Label = $Root/Lobby/Panel/Hint

var _chips: Array[Dictionary] = []
var _slot_cards: Array[Dictionary] = []

const KEY_HINTS := ["WASD + Space", "Arrows + Shift", "IJKL + N", "TFGH + B"]

func _ready() -> void:
	_build_chips()
	_build_slot_cards()
	set_message("", "")

# --- score bar -------------------------------------------------------------

func _build_chips() -> void:
	for child in _scores.get_children():
		child.queue_free()
	_chips.clear()
	for i in GameConfig.MAX_PLAYERS:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.45)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(10)
		style.border_width_bottom = 4
		panel.add_theme_stylebox_override("panel", style)

		var box := VBoxContainer.new()
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
	_message.pivot_offset = _message.size * 0.5
	_message.scale = Vector2(1.45, 1.45)
	var tween := create_tween()
	tween.tween_property(_message, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# --- lobby -----------------------------------------------------------------

func _build_slot_cards() -> void:
	for child in _lobby_slots.get_children():
		child.queue_free()
	_slot_cards.clear()
	for i in GameConfig.MAX_PLAYERS:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(210, 250)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.08, 0.14, 0.9)
		style.set_corner_radius_all(14)
		style.set_content_margin_all(14)
		style.set_border_width_all(3)
		panel.add_theme_stylebox_override("panel", style)

		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 6)
		panel.add_child(box)

		var slot_label := Label.new()
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_label.add_theme_font_size_override("font_size", 26)
		box.add_child(slot_label)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(0, 54)
		box.add_child(swatch)

		var char_label := Label.new()
		char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		char_label.add_theme_font_size_override("font_size", 24)
		box.add_child(char_label)

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
		box.add_child(state_label)

		_lobby_slots.add_child(panel)
		_slot_cards.append({
			"panel": panel, "style": style, "slot": slot_label, "swatch": swatch,
			"char": char_label, "weight": weight_label, "state": state_label,
		})

func refresh_lobby() -> void:
	for i in _slot_cards.size():
		var card := _slot_cards[i]
		var data: Dictionary = GameConfig.slots[i]
		var character := GameConfig.character_of(i)
		var color: Color = character["color"]
		var off: bool = data["control"] == GameConfig.Driver.OFF

		card["slot"].text = "SLOT %d" % (i + 1)
		card["slot"].add_theme_color_override("font_color", color)
		card["swatch"].color = color
		card["char"].text = character["name"]
		card["weight"].text = str(character["weight"]).to_upper()
		card["style"].border_color = color

		match int(data["control"]):
			GameConfig.Driver.HUMAN:
				card["state"].text = "PLAYER %d\n%s" % [i + 1, KEY_HINTS[i]]
				card["state"].add_theme_color_override("font_color", Color(1, 1, 1))
			GameConfig.Driver.CPU:
				card["state"].text = "CPU\npress %s to take over" % KEY_HINTS[i].split(" + ")[1]
				card["state"].add_theme_color_override("font_color", Color(0.65, 0.7, 0.82))
			_:
				card["state"].text = "EMPTY"
				card["state"].add_theme_color_override("font_color", Color(0.45, 0.48, 0.58))

		card["panel"].modulate = Color(1, 1, 1, 0.38) if off else Color(1, 1, 1, 1)

	var humans := GameConfig.human_count()
	_lobby_hint.text = "First to %d wins    •    ENTER to start    •    %d human player%s" % [
		GameConfig.points_to_win, humans, "" if humans == 1 else "s"]

func show_lobby(value: bool) -> void:
	_lobby.visible = value
	# The score bar is all zeroes in the lobby and just crowds the title.
	$Root/TopBar.visible = not value
	if value:
		refresh_lobby()
