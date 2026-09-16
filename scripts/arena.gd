extends StaticBody3D
class_name Arena
## The dome everyone is fighting on.
##
## Geometry is a cap of a large sphere whose apex sits at the origin, so the
## further out you drift the steeper the slope gets and gravity starts doing the
## work for your opponents. Collision is the whole sphere (smooth, cheap, exact);
## the *visual* cap is rebuilt whenever the play radius shrinks, and each ball
## drops its arena collision mask once it rolls past the rim.

## Radius of the sphere the dome is cut from. Larger = flatter, more forgiving.
const DOME_RADIUS := 48.0
const SEGMENTS := 72
const RINGS := 16
const SKIRT_DROP := 2.4

const COLOR_INNER := Color("2f4f7a")
const COLOR_MID := Color("3d6ea8")
const COLOR_EDGE := Color("e8663f")
const COLOR_SKIRT := Color("14203a")

@onready var _surface: MeshInstance3D = $Surface
@onready var _rim: MeshInstance3D = $Rim
@onready var _pillar: MeshInstance3D = $Pillar

var play_radius := 13.5
var _built_radius := -1.0
var _pulse := 0.0
var _danger := 0.0  ## 0..1, drives how angry the rim looks.

func _ready() -> void:
	var shape := SphereShape3D.new()
	shape.radius = DOME_RADIUS
	$Collision.shape = shape
	$Collision.position = Vector3(0.0, -DOME_RADIUS, 0.0)

	var surf_mat := StandardMaterial3D.new()
	surf_mat.vertex_color_use_as_albedo = true
	surf_mat.roughness = 0.62
	surf_mat.metallic = 0.08
	surf_mat.rim_enabled = true
	surf_mat.rim = 0.45
	_surface.material_override = surf_mat

	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = COLOR_EDGE
	rim_mat.emission_enabled = true
	rim_mat.emission = COLOR_EDGE
	rim_mat.emission_energy_multiplier = 2.0
	_rim.material_override = rim_mat

	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = COLOR_SKIRT.darkened(0.35)
	pillar_mat.roughness = 0.9
	_pillar.material_override = pillar_mat

	rebuild(true)

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
	play_radius = maxf(value, 2.0)
	if absf(play_radius - _built_radius) > 0.03:
		rebuild()

func spawn_transform(index: int, count: int, ball_radius: float) -> Vector3:
	var ring := play_radius * 0.42
	var angle := TAU * float(index) / float(maxi(count, 1)) + PI * 0.25
	var pos := Vector3(cos(angle) * ring, 0.0, sin(angle) * ring)
	pos.y = surface_height(ring) + ball_radius
	return pos

func rebuild(force := false) -> void:
	if not force and absf(play_radius - _built_radius) <= 0.001:
		return
	_built_radius = play_radius

	var mesh := ArrayMesh.new()
	_build_cap(mesh)
	_build_skirt(mesh)
	_surface.mesh = mesh

	var rim_height := surface_height(play_radius)
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(play_radius - 0.28, 0.1)
	torus.outer_radius = play_radius + 0.22
	torus.rings = SEGMENTS
	torus.ring_segments = 8
	_rim.mesh = torus
	_rim.position = Vector3(0.0, rim_height + 0.02, 0.0)

	var pillar := CylinderMesh.new()
	pillar.top_radius = maxf(play_radius * 0.82, 1.0)
	pillar.bottom_radius = maxf(play_radius * 0.34, 0.6)
	pillar.height = 26.0
	pillar.radial_segments = 32
	_pillar.mesh = pillar
	_pillar.position = Vector3(0.0, rim_height - SKIRT_DROP - 13.0, 0.0)

func _cap_color(r: float) -> Color:
	var t: float = clampf(r / maxf(play_radius, 0.001), 0.0, 1.0)
	var c: Color = COLOR_INNER.lerp(COLOR_MID, smoothstep(0.0, 0.8, t))
	c = c.lerp(COLOR_EDGE, smoothstep(0.80, 1.0, t))
	# Concentric banding so you can read distance-to-edge and your own speed.
	if int(floor(r / 1.6)) % 2 == 0:
		c = c.darkened(0.12)
	return c

func _build_cap(mesh: ArrayMesh) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Ring radii, biased outward so the interesting part near the rim is denser.
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in RINGS + 1:
		var t := float(i) / float(RINGS)
		radii.append(play_radius * pow(t, 0.85))

	for i in RINGS:
		var r0 := radii[i]
		var r1 := radii[i + 1]
		for j in SEGMENTS:
			var a0 := TAU * float(j) / float(SEGMENTS)
			var a1 := TAU * float(j + 1) / float(SEGMENTS)
			var inner_a := _cap_vertex(r0, a0)
			var inner_b := _cap_vertex(r0, a1)
			var outer_a := _cap_vertex(r1, a0)
			var outer_b := _cap_vertex(r1, a1)
			# Clockwise from above == front facing in Godot.
			_emit(st, inner_a, r0)
			_emit(st, outer_a, r1)
			_emit(st, inner_b, r0)

			_emit(st, inner_b, r0)
			_emit(st, outer_a, r1)
			_emit(st, outer_b, r1)

	st.commit(mesh)
	mesh.surface_set_name(mesh.get_surface_count() - 1, "cap")

func _build_skirt(mesh: ArrayMesh) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y_top := surface_height(play_radius)
	var y_bot := y_top - SKIRT_DROP
	var r_top := play_radius
	var r_bot := play_radius * 0.9

	for j in SEGMENTS:
		var a0 := TAU * float(j) / float(SEGMENTS)
		var a1 := TAU * float(j + 1) / float(SEGMENTS)
		var t0 := Vector3(cos(a0) * r_top, y_top, sin(a0) * r_top)
		var t1 := Vector3(cos(a1) * r_top, y_top, sin(a1) * r_top)
		var b0 := Vector3(cos(a0) * r_bot, y_bot, sin(a0) * r_bot)
		var b1 := Vector3(cos(a1) * r_bot, y_bot, sin(a1) * r_bot)
		var n0 := Vector3(cos(a0), 0.35, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), 0.35, sin(a1)).normalized()

		_emit_raw(st, t0, n0, COLOR_EDGE.darkened(0.45))
		_emit_raw(st, b0, n0, COLOR_SKIRT)
		_emit_raw(st, t1, n1, COLOR_EDGE.darkened(0.45))

		_emit_raw(st, t1, n1, COLOR_EDGE.darkened(0.45))
		_emit_raw(st, b0, n0, COLOR_SKIRT)
		_emit_raw(st, b1, n1, COLOR_SKIRT)

	st.commit(mesh)
	mesh.surface_set_name(mesh.get_surface_count() - 1, "skirt")

func _cap_vertex(r: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * r, surface_height(r), sin(angle) * r)

func _emit(st: SurfaceTool, v: Vector3, r: float) -> void:
	# The sphere is centred at (0, -DOME_RADIUS, 0), so the normal is trivial.
	_emit_raw(st, v, (v - Vector3(0.0, -DOME_RADIUS, 0.0)).normalized(), _cap_color(r))

func _emit_raw(st: SurfaceTool, v: Vector3, n: Vector3, c: Color) -> void:
	st.set_normal(n)
	st.set_color(c)
	st.add_vertex(v)
