extends Node3D
## Slowly orbiting chase camera that frames whoever is still alive.

@onready var camera: Camera3D = $Camera

const BASE_HEIGHT_RATIO := 0.84
## Floor on the pull-in. Framing the shrunken dome as tightly as the full one
## cancels out the shrink on screen -- the rim closing in is the whole back half
## of a round, so the camera holds its ground and lets the platform get smaller.
const MIN_DISTANCE := 21.0
const ORBIT_SPEED := 0.055
## Slack on the horizontal fit: covers the focus drift below, plus the extra
## angle the near half of the dome subtends by being closer than its centre.
const WIDTH_MARGIN := 1.38

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
	# Camera3D holds the vertical FOV, so a viewport narrower than roughly 4:5
	# runs out of horizontal view and slices the dome off at the sides. This is a
	# floor rather than a scale factor: at 4:3 and wider the vertical framing
	# above already asks for more distance, so normal displays are untouched.
	wanted = maxf(wanted, _distance_to_fit_width(play_radius))
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

## Smallest horizontal offset that still fits an arena of `radius` across the
## viewport. `_distance` is the horizontal leg, so the eye is `tilt` times
## further from the focus than that.
func _distance_to_fit_width(radius: float) -> float:
	var view := camera.get_viewport()
	if view == null:
		return 0.0
	var size := view.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return 0.0
	var aspect := size.x / size.y
	var tilt := sqrt(1.0 + BASE_HEIGHT_RATIO * BASE_HEIGHT_RATIO)
	var half_width := tan(deg_to_rad(camera.fov * 0.5)) * aspect * tilt
	return radius * WIDTH_MARGIN / maxf(half_width, 0.001)
