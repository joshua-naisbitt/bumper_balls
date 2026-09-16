extends RefCounted
class_name AiBrain
## CPU driver for a bumper ball.
##
## The whole behaviour is a tug-of-war between two urges: "get back toward the
## middle" and "go shove someone". How far out the CPU is willing to chase, how
## accurately it aims and how often it dashes all scale with skill.

var skill := 0.7

var _rng := RandomNumberGenerator.new()
var _target_id := 0
var _rethink := 0.0
var _aim_error := Vector2.ZERO
var _aim_retarget := 0.0
var _wander_phase := 0.0
var _dash_requested := false
var _dash_gate := 0.0

func _init(skill_level: float, seed_index: int) -> void:
	skill = clampf(skill_level, 0.0, 1.0)
	_rng.seed = hash("bumper" + str(seed_index)) 
	_wander_phase = _rng.randf() * TAU

func reset() -> void:
	_target_id = 0
	_rethink = 0.0
	_aim_error = Vector2.ZERO
	_dash_requested = false
	_dash_gate = 0.0

func consume_dash() -> bool:
	var v := _dash_requested
	_dash_requested = false
	return v

func steer(me: BumperBall, arena: Arena, delta: float) -> Vector2:
	if arena == null:
		return Vector2.ZERO

	_rethink -= delta
	_aim_retarget -= delta
	_dash_gate -= delta
	_wander_phase += delta * _rng.randf_range(0.6, 1.1)

	var here := Vector2(me.global_position.x, me.global_position.z)
	var my_ratio := here.length() / maxf(arena.play_radius, 0.001)

	# Wobble the aim on a slow timer instead of per-frame, otherwise the error
	# averages out to nothing and the CPU plays perfectly.
	if _aim_retarget <= 0.0:
		var spread := lerpf(0.55, 0.06, skill)
		_aim_error = Vector2(_rng.randfn(0.0, spread), _rng.randfn(0.0, spread))
		_aim_retarget = lerpf(0.5, 0.16, skill)

	var opponents := _living_opponents(me)
	if _rethink <= 0.0:
		_target_id = _pick_target(me, opponents, arena)
		_rethink = lerpf(0.75, 0.22, skill)

	var to_centre := (-here).normalized() if here.length() > 0.01 else Vector2.ZERO
	var attack := Vector2.ZERO
	var target := _find(opponents, _target_id)

	if target:
		var their_pos := Vector2(target.global_position.x, target.global_position.z)
		var their_vel := Vector2(target.linear_velocity.x, target.linear_velocity.z)
		# Lead the target; better CPUs predict further ahead.
		var lead := lerpf(0.0, 0.45, skill)
		var aim := their_pos + their_vel * lead
		var offset := aim - here
		if offset.length() > 0.01:
			attack = offset.normalized()
		# Line the hit up so it pushes them outward rather than across the dome.
		var their_out := their_pos.normalized() if their_pos.length() > 0.01 else attack
		attack = attack.lerp(their_out, lerpf(0.05, 0.4, skill)).normalized()

		_consider_dash(me, target, here, their_pos, my_ratio, arena)
	else:
		attack = to_centre

	# Danger ramps up sharply once past the comfort ring; a cautious CPU has a
	# smaller comfort ring than a bold one.
	var comfort := lerpf(0.50, 0.70, skill)
	var danger: float = clampf(smoothstep(comfort, 1.02, my_ratio), 0.0, 1.0)
	if not me.is_grounded():
		danger = maxf(danger, 0.75)

	var desire := attack.lerp(to_centre, danger)

	# Orbit a little rather than beelining, so CPUs do not clump in the centre.
	var tangent := Vector2(-to_centre.y, to_centre.x) * sin(_wander_phase) * lerpf(0.35, 0.14, skill)
	desire += tangent + _aim_error

	if desire.length() < 0.001:
		return Vector2.ZERO
	return desire.normalized()

func _consider_dash(me: BumperBall, target: BumperBall, here: Vector2, there: Vector2,
		my_ratio: float, arena: Arena) -> void:
	if _dash_gate > 0.0:
		return
	var gap := there - here
	var dist := gap.length()
	if dist > 4.2 or dist < 0.01:
		return

	var dir := gap.normalized()
	var vel := Vector2(me.linear_velocity.x, me.linear_velocity.z)
	var aligned := dir.dot(vel.normalized()) if vel.length() > 0.5 else 1.0
	if aligned < lerpf(0.4, 0.75, skill):
		return

	# Refuse to dash into the void: only commit when the victim is further out
	# than we are, or we are still comfortably inside.
	var their_ratio := there.length() / maxf(arena.play_radius, 0.001)
	if their_ratio < my_ratio and my_ratio > 0.6:
		return

	if _rng.randf() < lerpf(0.15, 0.9, skill):
		_dash_requested = true
	_dash_gate = lerpf(1.4, 0.5, skill)

func _pick_target(me: BumperBall, opponents: Array, arena: Arena) -> int:
	var best_id := 0
	var best_score := -INF
	var here := Vector2(me.global_position.x, me.global_position.z)
	for o in opponents:
		var pos := Vector2(o.global_position.x, o.global_position.z)
		var dist := here.distance_to(pos)
		var ratio := pos.length() / maxf(arena.play_radius, 0.001)
		# Nearby and already teetering is the ideal victim. Heavies are a worse
		# target for a light ball, and a smart CPU knows it.
		var score := ratio * 3.0 - dist * 0.45
		score -= float(o.stats["mass"]) / maxf(me.mass, 0.01) * lerpf(0.0, 0.45, skill)
		score += _rng.randf_range(0.0, lerpf(2.2, 0.3, skill))
		if score > best_score:
			best_score = score
			best_id = o.get_instance_id()
	return best_id

func _living_opponents(me: BumperBall) -> Array:
	var out := []
	var parent := me.get_parent()
	if parent == null:
		return out
	for child in parent.get_children():
		if child is BumperBall and child != me and (child as BumperBall).alive:
			out.append(child)
	return out

func _find(list: Array, id: int) -> BumperBall:
	for o in list:
		if o.get_instance_id() == id:
			return o
	return null
