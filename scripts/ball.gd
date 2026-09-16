extends RigidBody3D
class_name BumperBall
## One bumper ball: a rolling rigid sphere you steer with force, not teleportation.
##
## Knockback deliberately ignores the top-speed limit, so a good hit always sends
## someone further than they could ever drive themselves.

signal knocked_out(ball: BumperBall)
signal bumped(strength: float)

const RADIUS := 0.8
const LAYER_BALLS := 1
const LAYER_ARENA := 2
const KILL_Y := -9.0

const DASH_WINDOW := 0.3          ## How long a dash counts as "charged" for bumps.
const DASH_BUMP_BONUS := 1.85
const DASH_AIR_SCALE := 0.45      ## Dashing off the edge is a weak recovery, not a free save.

const BUMP_BASE := 2.4
const BUMP_FROM_APPROACH := 0.72
const BUMP_LIFT := 0.22
const BUMP_REPEAT_LOCK := 0.1

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _glow: MeshInstance3D = $Glow
@onready var _tag: Label3D = $Tag
@onready var _marker: MeshInstance3D = $Marker

var slot := 0
var stats: Dictionary = {}
var is_human := false
var alive := true
var brain: AiBrain = null

var _arena: Arena = null
var _move_input := Vector2.ZERO
var _dash_timer := 0.0
var _cooldown := 0.0
var _squash := 0.0
var _off_edge := false
var _bump_lock: Dictionary = {}
var _base_material: StandardMaterial3D
var _glow_material: StandardMaterial3D

func setup(slot_index: int, character: Dictionary, human: bool, arena: Arena, ai_skill: float) -> void:
	slot = slot_index
	stats = character
	is_human = human
	_arena = arena
	mass = character["mass"]
	if not human:
		brain = AiBrain.new(ai_skill, slot_index)

	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	linear_damp = 1.1
	angular_damp = 0.8
	collision_layer = LAYER_BALLS
	collision_mask = LAYER_BALLS | LAYER_ARENA

	var pm := PhysicsMaterial.new()
	pm.friction = 0.78
	pm.bounce = 0.42
	physics_material_override = pm

	_apply_look()
	body_entered.connect(_on_body_entered)

func _apply_look() -> void:
	var color: Color = stats["color"]

	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_mesh.mesh = sphere

	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = color
	_base_material.roughness = 0.32
	_base_material.metallic = 0.15
	_base_material.rim_enabled = true
	_base_material.rim = 0.7
	_base_material.emission_enabled = true
	_base_material.emission = color
	_base_material.emission_energy_multiplier = 0.12
	_mesh.material_override = _base_material

	var glow_sphere := SphereMesh.new()
	glow_sphere.radius = RADIUS * 1.22
	glow_sphere.height = RADIUS * 2.44
	glow_sphere.radial_segments = 24
	glow_sphere.rings = 12
	_glow.mesh = glow_sphere

	_glow_material = StandardMaterial3D.new()
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.cull_mode = BaseMaterial3D.CULL_FRONT
	_glow_material.albedo_color = Color(color.r, color.g, color.b, 0.0)
	_glow.material_override = _glow_material

	# Flat ring drawn on the dome under the ball: depth is hard to read otherwise.
	var ring := TorusMesh.new()
	ring.inner_radius = RADIUS * 0.92
	ring.outer_radius = RADIUS * 1.12
	ring.rings = 28
	ring.ring_segments = 6
	_marker.mesh = ring
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = color
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.albedo_color.a = 0.75
	_marker.material_override = marker_mat

	# Keep CPU tags quieter than player tags so you can find yourself in a scrum.
	_tag.text = "%s\n%s" % ["P%d" % (slot + 1) if is_human else "CPU", stats["name"]]
	_tag.modulate = color if is_human else Color(color.r, color.g, color.b, 0.62)
	_tag.outline_modulate = Color(0, 0, 0, 0.85)
	_tag.font_size = 44 if is_human else 32
	_tag.outline_size = 16 if is_human else 10
	_tag.pixel_size = 0.013
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true

func reset_to(pos: Vector3) -> void:
	alive = true
	_off_edge = false
	_dash_timer = 0.0
	_cooldown = 0.0
	_squash = 0.0
	_move_input = Vector2.ZERO
	_bump_lock.clear()
	collision_mask = LAYER_BALLS | LAYER_ARENA
	freeze = false
	visible = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = pos
	if brain:
		brain.reset()

func set_frozen(value: bool) -> void:
	# Countdown hold. A dome has no flat spot, so anything less than a real
	# freeze means everyone has quietly rolled away before GO.
	set_physics_process(not value)
	freeze = value
	if value:
		_move_input = Vector2.ZERO
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

func distance_from_centre() -> float:
	return Vector2(global_position.x, global_position.z).length()

func is_grounded() -> bool:
	if _arena == null:
		return false
	var surface := _arena.surface_height(distance_from_centre()) + RADIUS
	return global_position.y <= surface + 0.3

func bump_multiplier() -> float:
	var m: float = stats["bump_power"]
	if _dash_timer > 0.0:
		m *= DASH_BUMP_BONUS
	return m

func _physics_process(delta: float) -> void:
	if not alive:
		return

	_cooldown = maxf(_cooldown - delta, 0.0)
	_dash_timer = maxf(_dash_timer - delta, 0.0)
	for key in _bump_lock.keys():
		_bump_lock[key] -= delta
		if _bump_lock[key] <= 0.0:
			_bump_lock.erase(key)

	_read_input(delta)
	_drive(delta)
	_check_edge()

func _read_input(delta: float) -> void:
	if brain:
		_move_input = brain.steer(self, _arena, delta)
		if brain.consume_dash():
			_try_dash()
		return

	var p := slot + 1
	_move_input = Input.get_vector(
		"p%d_left" % p, "p%d_right" % p, "p%d_up" % p, "p%d_down" % p)
	if Input.is_action_just_pressed("p%d_dash" % p):
		_try_dash()

func _drive(_delta: float) -> void:
	if _move_input.length() < 0.05:
		return
	var dir := Vector3(_move_input.x, 0.0, _move_input.y)
	var strength := minf(dir.length(), 1.0)
	dir = dir.normalized()

	var flat_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var along := flat_vel.dot(dir)
	# Throttle only the part of the push that would exceed top speed; knockback
	# from a rival is never capped this way.
	var throttle: float = clampf(1.0 - along / float(stats["top_speed"]), 0.0, 1.0)
	var grip := 1.0 if is_grounded() else 0.22
	apply_central_force(dir * float(stats["accel"]) * mass * strength * throttle * grip)

func _try_dash() -> void:
	if _cooldown > 0.0:
		return
	_cooldown = float(stats.get("dash_cooldown", 1.1))
	_dash_timer = DASH_WINDOW

	var dir := Vector3(_move_input.x, 0.0, _move_input.y)
	if dir.length() < 0.15:
		dir = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if dir.length() < 0.15:
		dir = -Vector3(global_position.x, 0.0, global_position.z)
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	dir = dir.normalized()

	var power: float = stats["dash_power"] * mass
	if not is_grounded():
		power *= DASH_AIR_SCALE
	apply_central_impulse(dir * power)
	_squash = 1.0
	Sfx.play("dash", -8.0, randf_range(0.94, 1.06))

func _check_edge() -> void:
	if _arena == null:
		return
	if not _off_edge and distance_from_centre() > _arena.play_radius:
		# Past the rim there is nothing holding you up any more. Other balls can
		# still hit you on the way down, which makes for good panic moments.
		_off_edge = true
		collision_mask = LAYER_BALLS
		Sfx.play("warn", -6.0)
	if global_position.y < KILL_Y:
		_die()

func _die() -> void:
	if not alive:
		return
	alive = false
	freeze = true
	visible = false
	Sfx.play("fall", -3.0, randf_range(0.95, 1.05))
	knocked_out.emit(self)

func _on_body_entered(body: Node) -> void:
	if not alive or not (body is BumperBall):
		return
	var other := body as BumperBall
	var id := other.get_instance_id()
	if _bump_lock.has(id):
		return
	_bump_lock[id] = BUMP_REPEAT_LOCK

	var away := global_position - other.global_position
	away.y = 0.0
	if away.length() < 0.001:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	away = away.normalized()

	# Only the closing part of the relative velocity counts, so glancing rubs
	# barely register while head-on charges hit hard.
	var relative := linear_velocity - other.linear_velocity
	var approach := maxf(-relative.dot(away), 0.0)

	var power := (BUMP_BASE + approach * BUMP_FROM_APPROACH)
	power *= other.bump_multiplier()
	power *= float(stats["knockback_taken"])
	# Square-rooted: the rigid-body solver has already transferred momentum by
	# mass, so applying the full ratio again here makes heavies unbeatable.
	power *= sqrt(other.mass / maxf(mass, 0.01))

	apply_central_impulse((away + Vector3.UP * BUMP_LIFT).normalized() * power * mass)
	_squash = minf(1.0, 0.35 + approach * 0.09)

	# Both balls run this handler, so only one of them needs to make the noise.
	if get_instance_id() < id:
		var loud: float = clampf(approach / 14.0, 0.0, 1.0)
		Sfx.play("bump", lerpf(-14.0, 0.0, loud), randf_range(0.9, 1.12))
		bumped.emit(loud)

func _process(delta: float) -> void:
	if not visible:
		return
	_squash = maxf(_squash - delta * 3.2, 0.0)

	# Counteract the body's spin for the flat overlays, then place them by hand.
	var dome_normal := Vector3.UP
	if _arena:
		dome_normal = (global_position - Vector3(0.0, -Arena.DOME_RADIUS, 0.0)).normalized()

	_tag.global_transform = Transform3D(Basis(), global_position + Vector3.UP * 1.9)

	var ground_y: float = _arena.surface_height(distance_from_centre()) if _arena else 0.0
	var basis := _basis_from_up(dome_normal)
	_marker.global_transform = Transform3D(basis, global_position + Vector3.UP * (ground_y - global_position.y + 0.04))
	_marker.visible = not _off_edge

	var pop := 1.0 + _squash * 0.22
	_mesh.scale = Vector3(pop, 1.0 / pop, pop)

	var charge := 1.0 if _cooldown <= 0.0 else 0.0
	var flare: float = maxf(_dash_timer / DASH_WINDOW, _squash * 0.6)
	var color: Color = stats["color"]
	_glow_material.albedo_color = Color(color.r, color.g, color.b, flare * 0.55 + charge * 0.08)
	_base_material.emission_energy_multiplier = 0.12 + flare * 1.4

func _basis_from_up(up: Vector3) -> Basis:
	var fwd := Vector3.FORWARD
	if absf(up.dot(fwd)) > 0.95:
		fwd = Vector3.RIGHT
	var right := up.cross(fwd).normalized()
	return Basis(right, up, right.cross(up).normalized())
