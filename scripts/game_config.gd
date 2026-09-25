extends Node
## Match-wide settings and the roster, shared between the lobby, the arena and the HUD.

const MAX_PLAYERS := 4

## Weight classes are the balance of the game. Mass alone decides who wins a
## collision, so bump_power/knockback_taken stay close to 1.0 and only nudge it --
## letting them track mass as well double-counts weight and the heavies run away
## with every match. Lights pay for their mass with a big mobility edge instead.
const ROSTER := [
	{
		"name": "Pip",
		"dash_cooldown": 0.85,
		"weight": "Feather",
		"color": Color("ff5b5b"),
		"mass": 0.78,
		"accel": 48.0,
		"top_speed": 13.0,
		"bump_power": 0.94,
		"knockback_taken": 1.10,
		"dash_power": 13.5,
	},
	{
		"name": "Nimbus",
		"dash_cooldown": 0.92,
		"weight": "Light",
		"color": Color("4cc6ff"),
		"mass": 0.90,
		"accel": 43.0,
		"top_speed": 12.0,
		"bump_power": 0.97,
		"knockback_taken": 1.05,
		"dash_power": 12.5,
	},
	{
		"name": "Sprout",
		"dash_cooldown": 1.00,
		"weight": "Middle",
		"color": Color("5fe08a"),
		"mass": 1.00,
		"accel": 38.0,
		"top_speed": 11.0,
		"bump_power": 1.00,
		"knockback_taken": 1.00,
		"dash_power": 11.5,
	},
	{
		"name": "Zest",
		"dash_cooldown": 1.06,
		"weight": "Middle",
		"color": Color("ffd24c"),
		"mass": 1.10,
		"accel": 35.0,
		"top_speed": 10.5,
		"bump_power": 1.03,
		"knockback_taken": 0.97,
		"dash_power": 11.0,
	},
	{
		"name": "Mauve",
		"dash_cooldown": 1.18,
		"weight": "Heavy",
		"color": Color("c47bff"),
		"mass": 1.26,
		"accel": 31.0,
		"top_speed": 9.6,
		"bump_power": 1.07,
		"knockback_taken": 0.94,
		"dash_power": 10.2,
	},
	{
		"name": "Rook",
		"dash_cooldown": 1.30,
		"weight": "Boulder",
		"color": Color("ff9c3d"),
		"mass": 1.45,
		"accel": 27.0,
		"top_speed": 8.8,
		"bump_power": 1.10,
		"knockback_taken": 0.92,
		"dash_power": 9.4,
	},
]

enum Driver { OFF, CPU, HUMAN }

## Per-slot lobby state. Index 0..3 maps to p1_*..p4_* input actions.
var slots: Array[Dictionary] = []

## Yaw of the orbiting camera, published so human input can be camera-relative.
## The rig turns slowly during a round; without this, "up" quietly stops meaning
## "away from me" and players fight the camera. CPUs steer in world space and
## ignore it.
var camera_yaw := 0.0

## -1 means seed the CPUs from system entropy. Any other value makes a run
## reproducible, which is what the headless soaks want and a party game does not.
var ai_seed := -1

var points_to_win := 3
var ai_skill := 0.72  ## 0 = harmless, 1 = ruthless.

func _ready() -> void:
	reset_slots()

func reset_slots() -> void:
	slots.clear()
	for i in MAX_PLAYERS:
		slots.append({
			"control": Driver.CPU,
			"character": i % ROSTER.size(),
			"score": 0,
		})
	# Slot 1 starts as a human so a single player can hit Start and go.
	slots[0]["control"] = Driver.HUMAN

func character_of(slot_index: int) -> Dictionary:
	return ROSTER[slots[slot_index]["character"]]

func is_active(slot_index: int) -> bool:
	return slots[slot_index]["control"] != Driver.OFF

func active_slots() -> Array[int]:
	var out: Array[int] = []
	for i in slots.size():
		if is_active(i):
			out.append(i)
	return out

func active_count() -> int:
	return active_slots().size()

func is_human(slot_index: int) -> bool:
	return slots[slot_index]["control"] == Driver.HUMAN

## The slot the on-screen touch controls drive: the first human one, or -1.
func first_human_slot() -> int:
	for i in slots.size():
		if is_human(i):
			return i
	return -1

func human_count() -> int:
	var n := 0
	for s in slots:
		if s["control"] == Driver.HUMAN:
			n += 1
	return n

func cycle_character(slot_index: int, step: int) -> void:
	# Reserve against every slot, not just the active ones: an empty slot keeps
	# its character, so ignoring it here let a slot cycle onto that character and
	# then collide with it the moment the empty slot rejoined.
	var taken := {}
	for i in slots.size():
		if i != slot_index:
			taken[slots[i]["character"]] = true
	var idx: int = slots[slot_index]["character"]
	# Skip past characters another slot already claimed so colours stay unique.
	for _attempt in ROSTER.size():
		idx = wrapi(idx + step, 0, ROSTER.size())
		if not taken.has(idx):
			break
	slots[slot_index]["character"] = idx

func reset_scores() -> void:
	for s in slots:
		s["score"] = 0

func leader_score() -> int:
	var best := 0
	for i in slots.size():
		if is_active(i):
			best = max(best, int(slots[i]["score"]))
	return best

## Slots that have reached the target score. Ties are possible, hence an array.
func match_winners() -> Array[int]:
	var out: Array[int] = []
	for i in slots.size():
		if is_active(i) and slots[i]["score"] >= points_to_win:
			out.append(i)
	return out
