extends StaticBody3D
class_name Arena
## The dome everyone is fighting on.
##
## Geometry is a cap of a large sphere whose apex sits at the origin, so the
## further out you drift the steeper the slope gets and gravity starts doing the
## work for your opponents. Collision is the whole sphere (smooth, cheap, exact),
## and each ball drops its arena collision mask once it rolls past the rim.
##
## Nothing here is rebuilt when the rim closes in. The cap mesh is built once at
## full size and shaders/dome.gdshader folds it down to the live radius; the
## skirt is a unit ring that gets scaled; the rim and pillar are engine
## primitives, which regenerate natively. Shrinking is a handful of property
## writes per frame instead of ~10 ms of GDScript mesh generation.

## Radius of the sphere the dome is cut from. Larger = flatter, more forgiving.
const DOME_RADIUS := 48.0
## Full-size platform. Every round starts here.
const MAX_RADIUS := 13.5
const SEGMENTS := 72
## Evenly spaced now the rim sweeps inward through the whole mesh; when it has
## closed to the minimum there are still ~9 rings left inside it.
const RINGS := 28
const SKIRT_DROP := 2.4

const COLOR_EDGE := Color("e8663f")
const COLOR_SKIRT := Color("14203a")
const DOME_SHADER := preload("res://shaders/dome.gdshader")

@onready var _surface: MeshInstance3D = $Surface
@onready var _skirt: MeshInstance3D = $Skirt
@onready var _rim: MeshInstance3D = $Rim
@onready var _pillar: MeshInstance3D = $Pillar

var play_radius := MAX_RADIUS
var _applied_radius := -1.0
var _pulse := 0.0
var _danger := 0.0  ## 0..1, drives how angry the rim looks.
var _dome_material: ShaderMaterial
var _torus := TorusMesh.new()
var _pillar_mesh := CylinderMesh.new()

func _ready() -> void:
	var shape := SphereShape3D.new()
	shape.radius = DOME_RADIUS
	$Collision.shape = shape
	$Collision.position = Vector3(0.0, -DOME_RADIUS, 0.0)

	_dome_material = ShaderMaterial.new()
	_dome_material.shader = DOME_SHADER
	_dome_material.set_shader_parameter("dome_radius", DOME_RADIUS)
	_surface.mesh = _build_cap()
	_surface.material_override = _dome_material
	# The shader moves vertices inward, never outward, so the full-size bounds
	# are always a safe (if loose) cull box.
	_surface.custom_aabb = AABB(Vector3(-MAX_RADIUS, -SKIRT_DROP - 1.0, -MAX_RADIUS),
		Vector3(MAX_RADIUS * 2.0, SKIRT_DROP + 2.0, MAX_RADIUS * 2.0))

	var skirt_mat := StandardMaterial3D.new()
	skirt_mat.vertex_color_use_as_albedo = true
	skirt_mat.roughness = 0.62
	skirt_mat.metallic = 0.08
	_skirt.mesh = _build_skirt()
	_skirt.material_override = skirt_mat

	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = COLOR_EDGE
	rim_mat.emission_enabled = true
	rim_mat.emission = COLOR_EDGE
	rim_mat.emission_energy_multiplier = 2.0
	_torus.rings = SEGMENTS
	_torus.ring_segments = 8
	_rim.mesh = _torus
	_rim.material_override = rim_mat

	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = COLOR_SKIRT.darkened(0.35)
	pillar_mat.roughness = 0.9
	_pillar_mesh.height = 26.0
	_pillar_mesh.radial_segments = 32
	_pillar.mesh = _pillar_mesh
	_pillar.material_override = pillar_mat

	_apply_radius()

func _process(delta: float) -> void:
	_pulse += delta * lerpf(2.0, 7.5, _danger)
	var mat := _rim.material_override as StandardMaterial3D
	if mat:
		var beat := 0.5 + 0.5 * sin(_pulse)
		mat.emission_energy_multiplier = lerpf(1.2, 4.5, _danger) * (0.55 + 0.45 * beat)

func set_danger(amount: float) -> void:
	_danger = clampf(amount, 0.0, 1.0)

## Height of the dome surface at a given horizontal distance from the centre.
func surface_height(dist: float) -> float:
	var d := minf(dist, DOME_RADIUS)
	return sqrt(DOME_RADIUS * DOME_RADIUS - d * d) - DOME_RADIUS

func set_play_radius(value: float) -> void:
	play_radius = clampf(value, 2.0, MAX_RADIUS)
	# Cheap enough now to follow the rim every frame, so it no longer steps.
	if absf(play_radius - _applied_radius) > 0.002:
		_apply_radius()

func spawn_transform(index: int, count: int, ball_radius: float) -> Vector3:
	var ring := play_radius * 0.42
	var angle := TAU * float(index) / float(maxi(count, 1)) + PI * 0.25
	var pos := Vector3(cos(angle) * ring, 0.0, sin(angle) * ring)
	pos.y = surface_height(ring) + ball_radius
	return pos

func _apply_radius() -> void:
	_applied_radius = play_radius
	var rim_height := surface_height(play_radius)

	_dome_material.set_shader_parameter("play_radius", play_radius)

	# The skirt is modelled at radius 1 with its top edge at y = 0, so a scale
	# and a lift put it exactly under the rim at any size.
	_skirt.scale = Vector3(play_radius, 1.0, play_radius)
	_skirt.position = Vector3(0.0, rim_height, 0.0)

	_torus.inner_radius = maxf(play_radius - 0.28, 0.1)
	_torus.outer_radius = play_radius + 0.22
	_rim.position = Vector3(0.0, rim_height + 0.02, 0.0)

	_pillar_mesh.top_radius = maxf(play_radius * 0.82, 1.0)
	_pillar_mesh.bottom_radius = maxf(play_radius * 0.34, 0.6)
	_pillar.position = Vector3(0.0, rim_height - SKIRT_DROP - 13.0, 0.0)

## Flat full-size grid; the shader supplies the height, normal and colour, so
## only the XZ layout matters here.
func _build_cap() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RINGS:
		var r0 := MAX_RADIUS * float(i) / float(RINGS)
		var r1 := MAX_RADIUS * float(i + 1) / float(RINGS)
		for j in SEGMENTS:
			var a0 := TAU * float(j) / float(SEGMENTS)
			var a1 := TAU * float(j + 1) / float(SEGMENTS)
			var inner_a := _flat(r0, a0)
			var inner_b := _flat(r0, a1)
			var outer_a := _flat(r1, a0)
			var outer_b := _flat(r1, a1)
			# Clockwise from above == front facing in Godot.
			for v in [inner_a, outer_a, inner_b, inner_b, outer_a, outer_b]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	st.index()
	return st.commit()

func _build_skirt() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top_color := COLOR_EDGE.darkened(0.45)
	for j in SEGMENTS:
		var a0 := TAU * float(j) / float(SEGMENTS)
		var a1 := TAU * float(j + 1) / float(SEGMENTS)
		var t0 := Vector3(cos(a0), 0.0, sin(a0))
		var t1 := Vector3(cos(a1), 0.0, sin(a1))
		var b0 := Vector3(cos(a0) * 0.9, -SKIRT_DROP, sin(a0) * 0.9)
		var b1 := Vector3(cos(a1) * 0.9, -SKIRT_DROP, sin(a1) * 0.9)
		var n0 := Vector3(cos(a0), 0.35, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), 0.35, sin(a1)).normalized()
		_emit(st, t0, n0, top_color)
		_emit(st, b0, n0, COLOR_SKIRT)
		_emit(st, t1, n1, top_color)
		_emit(st, t1, n1, top_color)
		_emit(st, b0, n0, COLOR_SKIRT)
		_emit(st, b1, n1, COLOR_SKIRT)
	st.index()
	return st.commit()

func _flat(r: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * r, 0.0, sin(angle) * r)

func _emit(st: SurfaceTool, v: Vector3, n: Vector3, c: Color) -> void:
	st.set_normal(n)
	st.set_color(c)
	st.add_vertex(v)
