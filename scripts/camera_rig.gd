extends Node3D
## Slowly orbiting chase camera that frames whoever is still alive.

@onready var camera: Camera3D = $Camera

const BASE_HEIGHT_RATIO := 0.84
## Floor on the pull-in. Framing the shrunken dome as tightly as the full one
## cancels out the shrink on screen -- the rim closing in is the whole back half
## of a round, so the camera holds its ground and lets the platform get smaller.
const MIN_DISTANCE := 21.0
const ORBIT_SPEED := 0.055

var _orbit := 0.6
var _focus := Vector3.ZERO
var _distance := 30.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.2)

## `_distance` is the camera's HORIZONTAL offset; height is that times
## BASE_HEIGHT_RATIO. The binding constraint is the near rim, which sits far
## below the look-at point and drops out of the frustum if the rig gets close.
func frame(points: Array[Vector3], play_radius: float, delta: float) -> void:
	_orbit += delta * ORBIT_SPEED
	GameConfig.camera_yaw = _orbit
	_shake = maxf(_shake - delta * 2.2, 0.0)

	var target_focus := Vector3.ZERO
	var spread := 0.0
	if points.size() > 0:
		for p in points:
			target_focus += p
		target_focus /= float(points.size())
		for p in points:
			spread = maxf(spread, Vector2(p.x - target_focus.x, p.z - target_focus.z).length())
	target_focus.y = 0.0
	# Do not let the camera drift all the way off-centre; keep the dome in frame.
	target_focus = target_focus.limit_length(play_radius * 0.18)

	var wanted := maxf(maxf(play_radius * 1.93, spread * 1.9) + 0.5, MIN_DISTANCE)
	_focus = _focus.lerp(target_focus, 1.0 - pow(0.02, delta))
	_distance = lerpf(_distance, wanted, 1.0 - pow(0.05, delta))

	var offset := Vector3(sin(_orbit), 0.0, cos(_orbit)) * _distance
	offset.y = _distance * BASE_HEIGHT_RATIO
	var eye := _focus + offset

	if _shake > 0.0:
		var jolt := _shake * _shake * 0.55
		eye += Vector3(_rng.randfn(0.0, jolt), _rng.randfn(0.0, jolt * 0.6), _rng.randfn(0.0, jolt))

	camera.global_position = eye
	camera.look_at(_focus + Vector3.UP * 1.0, Vector3.UP)
