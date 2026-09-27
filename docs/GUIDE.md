# Build Bumper Balls yourself

A step-by-step guide to recreating this project from an empty folder, written so
you come away understanding *why* the code is the way it is, not just what it
does.

**How it works**

- **[Part 1](#part-1--a-playable-prototype)** has you build a small playable
  prototype by hand: the dome, a ball you can steer, two players bumping each
  other, and a round loop — about 350 lines. Every listing in Part 1 was built
  and run in Godot 4.3 exactly as written here, one stage at a time, and loads
  with no editor warnings.
- **[Part 2](#part-2--growing-it-into-the-real-game)** grows the prototype into
  the real game one system at a time. From there the repository is your answer
  key: each chapter explains what the real file does, quotes the parts that
  matter (pulled verbatim from the code), and suggests how to build it yourself
  before you compare.
- **[Part 3](#part-3--lessons-from-the-bugs)** lists the bugs found while
  building this project, each with its cause and fix. A lot of the real
  understanding is in there.

**You will need** Godot **4.3**, the standard build (not .NET). Later 4.x
versions will very likely work, but 4.3 is what everything here was checked
against. Some GDScript helps; Godot concepts are explained as they come up.

**Conventions.** Code you type is shown in full. A ✅ **Checkpoint** tells you
what you should see when you press Play. 💡 **Why** notes explain a decision.
🧪 **Experiment** notes suggest a change to try, with what actually happens.

---

## Part 1 — A playable prototype

### Stage 0 — The project

1. Open Godot → **New Project**. Pick an empty folder and set
   **Renderer: Compatibility**.

   > 💡 **Why Compatibility?** It is the only renderer that runs on the web,
   > and it covers the widest range of phones. It also turned out to be the
   > one this game *looks right* in: rendering with the default Forward+
   > showed the dome washed out to a pale grey (see
   > [Part 3](#part-3--lessons-from-the-bugs)).

2. In the **FileSystem** dock, create two folders: `scripts/` and `scenes/`.
3. Open **Project → Project Settings**, switch on **Advanced Settings** (top
   right), and set:

   | Setting | Value | Why |
   |---|---|---|
   | Physics → 3D → Default Gravity | `22` | Falls read as falls. At Earth's 9.8 the balls drift off the edge like balloons. |
   | Display → Window → Size → Viewport Width / Height | `1280` / `720` | The size the UI is laid out for. |
   | Display → Window → Stretch → Mode | `canvas_items` | The 2D UI scales with the window. |
   | Display → Window → Stretch → Aspect | `expand` | A wider or taller window shows more, rather than adding black bars. |
   | Layer Names → 3D Physics → Layer 1 / Layer 2 | `balls` / `arena` | Only labels, but they make the collision checkboxes readable. |

### Stage 1 — The dome

The whole game rests on one idea: **the platform is the top of a very large
sphere.** At the centre it is flat. Move out and it tilts — at a distance `r`
from the centre the slope is `asin(r / 48)`, from 0° in the middle to about 16°
at the rim. So the further out you are, the harder gravity pulls you further
out. Stop steering and you drift: slowly at first, then faster and faster.

The collision is the **entire sphere**, as a single `SphereShape3D` of radius
48 centred at `(0, −48, 0)` so its top touches `y = 0`. Physics engines handle
spheres exactly and almost for free. What you *see* is only a cap of it, drawn
out to `play_radius`. (If the collision sphere carries on past the rim, how do
balls fall off? Stage 2 answers that.)

**Build the main scene**

1. **Scene → New Scene → 3D Scene.** Rename the root node `Main` and save it as
   `scenes/main.tscn`. When you first press Play, Godot will ask for a main
   scene — choose this one.
2. Add these children of `Main`:
   - **WorldEnvironment** → Environment: *New Environment*. Set Background →
     Mode: *Sky*; Sky: *New Sky*, and its Sky Material: *New
     ProceduralSkyMaterial*; Ambient Light → Source: *Sky*.
   - **DirectionalLight3D**, renamed `Sun` → Position `(0, 20, 0)`, Rotation
     `(-50, 30, 0)`, Shadow → Enabled: on.
   - **Camera3D** → Position `(0, 20, 24)`, Rotation `(-40, 0, 0)`.
   - **StaticBody3D**, renamed `Arena`. Under Collision, tick only **Layer 2**
     (arena) and clear every **Mask** box. Give it two children:
     a **MeshInstance3D** named `Surface`, and a **CollisionShape3D** named
     `Collision`. Leave the collision shape empty — the script creates it (the
     editor shows a warning triangle on it until then; that's expected).
3. Right-click `Arena` → **Attach Script** → `scripts/arena.gd`:

```gdscript
extends StaticBody3D
class_name Arena
## The dome: the top of a very large sphere. The further out you are, the
## steeper it gets, so gravity is always pulling you toward the edge.

const DOME_RADIUS := 48.0   ## Radius of the sphere the dome is cut from.
const RINGS := 16
const SEGMENTS := 64

var play_radius := 13.5     ## How far out the platform reaches.

@onready var _surface: MeshInstance3D = $Surface

func _ready() -> void:
	# Collision is the WHOLE sphere, pushed down so its top sits at y = 0.
	# Smooth, exact, and free -- no mesh collider needed.
	var shape := SphereShape3D.new()
	shape.radius = DOME_RADIUS
	$Collision.shape = shape
	$Collision.position = Vector3(0.0, -DOME_RADIUS, 0.0)

	_surface.mesh = _build_cap()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("3d6ea8")
	_surface.material_override = mat

## Height of the dome's surface at a horizontal distance from the centre.
func surface_height(dist: float) -> float:
	var d := minf(dist, DOME_RADIUS)
	return sqrt(DOME_RADIUS * DOME_RADIUS - d * d) - DOME_RADIUS

## Builds the visible cap: rings of quads from the centre out to play_radius,
## each vertex lifted onto the sphere.
func _build_cap() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RINGS:
		var r0 := play_radius * i / RINGS
		var r1 := play_radius * (i + 1) / RINGS
		for j in SEGMENTS:
			var a0 := TAU * j / SEGMENTS
			var a1 := TAU * (j + 1) / SEGMENTS
			var in_a := _point(r0, a0)
			var in_b := _point(r0, a1)
			var out_a := _point(r1, a0)
			var out_b := _point(r1, a1)
			# Two triangles per quad, wound clockwise seen from above --
			# that is what Godot treats as the front face.
			for v: Vector3 in [in_a, out_a, in_b, in_b, out_a, out_b]:
				st.set_normal((v - Vector3(0.0, -DOME_RADIUS, 0.0)).normalized())
				st.add_vertex(v)
	return st.commit()

func _point(r: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * r, surface_height(r), sin(angle) * r)
```

✅ **Checkpoint.** Press **F5**. You should see a blue disc from above. It looks
flat because it nearly is: the rim is only 1.9 units lower than the centre,
across a platform 27 units wide.

**Understanding it**

- `surface_height` comes straight from the sphere's equation. A sphere of
  radius `R` centred at `(0, −R, 0)` satisfies `x² + (y+R)² + z² = R²`; solve
  for `y` at horizontal distance `r` and you get `√(R² − r²) − R`.
- `_build_cap` walks out in rings and around in segments, making one quad (two
  triangles) per cell and lifting every vertex onto the sphere. Each normal
  points away from the sphere's centre, which is what makes the lighting right.
- The **winding order** matters. Godot treats triangles whose corners run
  clockwise, as seen from the viewer, as front faces, and culls the backs. Get
  the order wrong and the dome is invisible from above.
- `@onready var _surface := $Surface` looks the child up when the node enters
  the scene tree, which is the earliest moment its children exist.

### Stage 2 — A ball you can steer

**Input.** In **Project Settings → Input Map**, add these actions and bind each
one to a key (in the key dialog, keep **Physical Keycode** selected, so WASD
stays WASD on AZERTY and other layouts). The dash actions are used from
Stage 3, but add them now:

| Action | Key | | Action | Key |
|---|---|---|---|---|
| `p1_up` | W | | `p2_up` | Up |
| `p1_down` | S | | `p2_down` | Down |
| `p1_left` | A | | `p2_left` | Left |
| `p1_right` | D | | `p2_right` | Right |
| `p1_dash` | Space | | `p2_dash` | Shift |

**The ball scene.** Scene → New Scene → **Other Node → RigidBody3D**, renamed
`Ball`. Give it:

- a **MeshInstance3D** named `Mesh`: Mesh → *New SphereMesh* with Radius `0.8`,
  Height `1.6`; then that SphereMesh's Material → *New StandardMaterial3D* with
  any Albedo colour (Stage 3 replaces it per character);
- a **CollisionShape3D** named `Collision`: Shape → *New SphereShape3D*,
  Radius `0.8`.

Attach `scripts/ball.gd` to `Ball` and save the scene as `scenes/ball.tscn`:

```gdscript
extends RigidBody3D
class_name BumperBall
## One ball. You steer it by pushing it with a force -- never by setting its
## position or velocity -- so it rolls, slides and bounces for real.

signal knocked_out(ball: BumperBall)

const RADIUS := 0.8
const LAYER_BALLS := 1   ## Physics layer 1 has the value 1...
const LAYER_ARENA := 2   ## ...and layer 2 has the value 2.
const KILL_Y := -9.0

@export var slot := 0    ## 0 reads the p1_* actions, 1 reads p2_*.
@export var arena: Arena

var stats := {"accel": 38.0, "top_speed": 11.0}
var alive := true
var _move_input := Vector2.ZERO
var _off_edge := false

func _ready() -> void:
	linear_damp = 1.1
	angular_damp = 0.8
	continuous_cd = true
	collision_layer = LAYER_BALLS
	collision_mask = LAYER_BALLS | LAYER_ARENA
	var pm := PhysicsMaterial.new()
	pm.friction = 0.78
	pm.bounce = 0.42
	physics_material_override = pm

func _physics_process(_delta: float) -> void:
	if not alive:
		return
	var p := slot + 1
	_move_input = Input.get_vector("p%d_left" % p, "p%d_right" % p, "p%d_up" % p, "p%d_down" % p)
	_drive()
	_check_edge()

func distance_from_centre() -> float:
	return Vector2(global_position.x, global_position.z).length()

func is_grounded() -> bool:
	var surface := arena.surface_height(distance_from_centre()) + RADIUS
	return global_position.y <= surface + 0.3

func _drive() -> void:
	if _move_input.length() < 0.05:
		return
	var dir := Vector3(_move_input.x, 0.0, _move_input.y)
	var strength := minf(dir.length(), 1.0)
	dir = dir.normalized()
	# Throttle only the part of the push that would take us past top speed.
	# Getting knocked faster than that by someone else is never capped.
	var flat_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var throttle := clampf(1.0 - flat_vel.dot(dir) / float(stats["top_speed"]), 0.0, 1.0)
	var grip := 1.0 if is_grounded() else 0.22
	apply_central_force(dir * float(stats["accel"]) * mass * strength * throttle * grip)

func _check_edge() -> void:
	if not _off_edge and distance_from_centre() > arena.play_radius:
		# Past the rim there is nothing to stand on: stop colliding with the
		# dome and let gravity do the rest.
		_off_edge = true
		collision_mask = LAYER_BALLS
	if global_position.y < KILL_Y:
		_die()

func _die() -> void:
	alive = false
	freeze = true
	visible = false
	# A frozen body is still solid. Parked down here it would be an invisible
	# obstacle for everyone else falling past, so switch its collision off.
	collision_layer = 0
	collision_mask = 0
	print("P%d is out!" % (slot + 1))
	knocked_out.emit(self)
```

**Put one in the world.** Drag `ball.tscn` from the FileSystem dock onto `Main`.
Set its Position to `(4, 1, 0)`, and in the Inspector drag the `Arena` node
into the ball's **Arena** field (that is the `@export var arena`).

✅ **Checkpoint.** Press Play. WASD rolls the ball. Now let go and watch: the
ball creeps outward and speeds up as it goes. Measured from where it starts,
4 units out: it is at 4.9 after one second, 6.2 after two, then 7.9, 9.9 and
12.4, and it crosses the rim (13.5) at about five and a half seconds. Hold one direction and you'll
roll straight off the far side — the slope only ever pulls you outward, so
staying on means correcting constantly. That *is* the game.

**Understanding it**

- **Forces, not velocities.** `apply_central_force` pushes the ball and lets
  the physics engine work out the rest, so rolling, sliding and collisions all
  stay physical. The force is multiplied by `mass`, so every character gets
  the same acceleration from its own push — what differs between characters
  (Stage 3) is how they take a hit.
- **The throttle** only reduces *your own push* as you approach top speed.
  Knockback from someone else is never capped, so a good hit always sends a
  ball further than it could ever drive itself.
- **`linear_damp` of 1.1** is rolling resistance. Without it the drift is too
  quick to fight; see the experiment below.
- **Layers and masks.** A body's *layer* says what it is; its *mask* says what
  it collides with. They are bit fields: layer 1 has the value 1, layer 2 the
  value 2, layer 3 the value 4, and so on — hence `LAYER_BALLS | LAYER_ARENA`.
- **Falling off.** Here's the answer to Stage 1's question: the moment a ball
  passes `play_radius`, it takes the arena *out of its own mask*. The sphere is
  still there, but the ball stops colliding with it, so it falls. No
  special-case geometry is needed — and later, when the rim shrinks, the same
  line keeps working.
- **Dying** freezes and hides the ball *and* switches its collision off. A
  frozen body is still solid; left collidable, it would be an invisible
  obstacle parked just below the rim, exactly where everyone else falls past.
  (That was a real bug — see [Part 3](#part-3--lessons-from-the-bugs).)

🧪 **Experiment: why a sphere of radius 48, and why damping?** Change
`DOME_RADIUS` or `linear_damp`, leave the ball alone, and time how long it
lasts. Measured from the same starting point:

| Dome radius | Linear damp | Falls off after |
|---|---|---|
| **48** | **1.1** | **~6.5 s** |
| 34 | 1.1 | ~5 s |
| 48 | 0.16 | ~4.5 s |
| 34 | 0.16 | ~4 s |

The bottom row was the first version of this game. The slope pull grows with
distance, which grows with speed, which grows with the pull — the drift feeds
itself, so a small change in the constants makes a big difference in how long
you can hesitate.

### Stage 3 — Two players, bumps and dashes

**Shared data.** Create `scripts/game_config.gd`:

```gdscript
extends Node
## Shared data. Registered as an autoload called GameConfig, so every script
## can simply write GameConfig.ROSTER.

## Mass decides who wins a collision. The other stats compensate: light balls
## accelerate harder, go faster and dash more often.
const ROSTER := [
	{
		"name": "Pip", "color": Color("ff5b5b"), "mass": 0.78,
		"accel": 48.0, "top_speed": 13.0, "dash_power": 13.5, "dash_cooldown": 0.85,
		"bump_power": 0.94, "knockback_taken": 1.10,
	},
	{
		"name": "Sprout", "color": Color("5fe08a"), "mass": 1.00,
		"accel": 38.0, "top_speed": 11.0, "dash_power": 11.5, "dash_cooldown": 1.00,
		"bump_power": 1.00, "knockback_taken": 1.00,
	},
	{
		"name": "Rook", "color": Color("ff9c3d"), "mass": 1.45,
		"accel": 27.0, "top_speed": 8.8, "dash_power": 9.4, "dash_cooldown": 1.30,
		"bump_power": 1.10, "knockback_taken": 0.92,
	},
]
```

Then register it: **Project Settings → Globals → Autoload** (called just
*Autoload* in some 4.x versions), path `res://scripts/game_config.gd`, name
`GameConfig`, **Add**. An autoload is a node Godot creates before your main
scene and keeps for the whole run, reachable by name from any script.

**The ball, grown up.** Replace `scripts/ball.gd` with this. What's new:
`setup()` replaces the exported fields, it colours itself per character, it can
dash, and it reacts to collisions with other balls.

```gdscript
extends RigidBody3D
class_name BumperBall
## One ball. You steer it by pushing it with a force -- never by setting its
## position or velocity -- so it rolls, slides and bounces for real.

signal knocked_out(ball: BumperBall)

const RADIUS := 0.8
const LAYER_BALLS := 1   ## Physics layer 1 has the value 1...
const LAYER_ARENA := 2   ## ...and layer 2 has the value 2.
const KILL_Y := -9.0

const DASH_WINDOW := 0.3        ## How long after a dash your bumps hit harder.
const DASH_BUMP_BONUS := 1.85
const DASH_AIR_SCALE := 0.45    ## Dashing in mid-air is a weak recovery, not a save.

const BUMP_BASE := 2.4
const BUMP_FROM_APPROACH := 0.72
const BUMP_LIFT := 0.22
const BUMP_REPEAT_LOCK := 0.1

var slot := 0            ## 0 reads the p1_* actions, 1 reads p2_*.
var stats: Dictionary = {}
var arena: Arena
var alive := true
var _move_input := Vector2.ZERO
var _off_edge := false
var _cooldown := 0.0
var _dash_timer := 0.0
var _bump_lock := {}

func setup(slot_index: int, character: Dictionary, arena_node: Arena) -> void:
	slot = slot_index
	stats = character
	arena = arena_node
	mass = character["mass"]
	linear_damp = 1.1
	angular_damp = 0.8
	continuous_cd = true
	collision_layer = LAYER_BALLS
	collision_mask = LAYER_BALLS | LAYER_ARENA
	var pm := PhysicsMaterial.new()
	pm.friction = 0.78
	pm.bounce = 0.42
	physics_material_override = pm

	var mat := StandardMaterial3D.new()
	mat.albedo_color = character["color"]
	$Mesh.material_override = mat

	# Ask the physics engine to tell us who we touch.
	contact_monitor = true
	max_contacts_reported = 8
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_dash_timer = maxf(_dash_timer - delta, 0.0)
	for id in _bump_lock.keys():
		_bump_lock[id] -= delta
		if _bump_lock[id] <= 0.0:
			_bump_lock.erase(id)

	var p := slot + 1
	_move_input = Input.get_vector("p%d_left" % p, "p%d_right" % p, "p%d_up" % p, "p%d_down" % p)
	if Input.is_action_just_pressed("p%d_dash" % p):
		_try_dash()
	_drive()
	_check_edge()

func distance_from_centre() -> float:
	return Vector2(global_position.x, global_position.z).length()

func is_grounded() -> bool:
	var surface := arena.surface_height(distance_from_centre()) + RADIUS
	return global_position.y <= surface + 0.3

func bump_multiplier() -> float:
	var m: float = stats["bump_power"]
	if _dash_timer > 0.0:
		m *= DASH_BUMP_BONUS
	return m

func _drive() -> void:
	if _move_input.length() < 0.05:
		return
	var dir := Vector3(_move_input.x, 0.0, _move_input.y)
	var strength := minf(dir.length(), 1.0)
	dir = dir.normalized()
	# Throttle only the part of the push that would take us past top speed.
	# Getting knocked faster than that by someone else is never capped.
	var flat_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var throttle := clampf(1.0 - flat_vel.dot(dir) / float(stats["top_speed"]), 0.0, 1.0)
	var grip := 1.0 if is_grounded() else 0.22
	apply_central_force(dir * float(stats["accel"]) * mass * strength * throttle * grip)

func _try_dash() -> void:
	if _cooldown > 0.0:
		return
	_cooldown = float(stats["dash_cooldown"])
	_dash_timer = DASH_WINDOW
	var dir := Vector3(_move_input.x, 0.0, _move_input.y)
	if dir.length() < 0.15:
		dir = Vector3(linear_velocity.x, 0.0, linear_velocity.z)   # no input: keep going
	if dir.length() < 0.15:
		dir = -Vector3(global_position.x, 0.0, global_position.z)  # standing still: head inward
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	var power: float = stats["dash_power"] * mass
	if not is_grounded():
		power *= DASH_AIR_SCALE
	apply_central_impulse(dir.normalized() * power)

func _on_body_entered(body: Node) -> void:
	if not alive or not (body is BumperBall):
		return
	var other := body as BumperBall
	var id := other.get_instance_id()
	if _bump_lock.has(id):   # the same contact can report twice in a row
		return
	_bump_lock[id] = BUMP_REPEAT_LOCK

	var away := global_position - other.global_position
	away.y = 0.0
	if away.length() < 0.001:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	away = away.normalized()

	# Only the closing speed counts: glancing rubs barely register, head-on
	# charges hit hard.
	var relative := linear_velocity - other.linear_velocity
	var approach := maxf(-relative.dot(away), 0.0)

	var power := BUMP_BASE + approach * BUMP_FROM_APPROACH
	power *= other.bump_multiplier()
	power *= float(stats["knockback_taken"])
	# The physics engine has ALREADY traded momentum by mass. Scaling by the
	# full mass ratio again double-counts weight; the square root keeps it
	# meaningful without making heavies unbeatable.
	power *= sqrt(other.mass / maxf(mass, 0.01))
	apply_central_impulse((away + Vector3.UP * BUMP_LIFT).normalized() * power * mass)

func _check_edge() -> void:
	if not _off_edge and distance_from_centre() > arena.play_radius:
		# Past the rim there is nothing to stand on: stop colliding with the
		# dome and let gravity do the rest.
		_off_edge = true
		collision_mask = LAYER_BALLS
	if global_position.y < KILL_Y:
		_die()

func _die() -> void:
	alive = false
	freeze = true
	visible = false
	# A frozen body is still solid. Parked down here it would be an invisible
	# obstacle for everyone else falling past, so switch its collision off.
	collision_layer = 0
	collision_mask = 0
	print("P%d is out!" % (slot + 1))
	knocked_out.emit(self)
```

**Spawning.** Delete the ball you placed by hand in `main.tscn`, attach a new
script to `Main`, and save it as `scripts/main.gd`:

```gdscript
extends Node3D
## Spawns the players. The round loop arrives in the next stage.

const BALL_SCENE := preload("res://scenes/ball.tscn")
const PICKS := [0, 2]   ## Player 1 is Pip, player 2 is Rook.

@onready var arena: Arena = $Arena

func _ready() -> void:
	for slot in PICKS.size():
		var ball := BALL_SCENE.instantiate() as BumperBall
		add_child(ball)   # add first: setup() reaches into the ball's children
		ball.setup(slot, GameConfig.ROSTER[PICKS[slot]], arena)
		ball.global_position = Vector3(-4.0 + 8.0 * slot, 1.0, 0.0)
```

✅ **Checkpoint.** Player 1 (Pip, red) uses WASD + Space; player 2 (Rook,
orange) uses the arrow keys + Shift. Drive into each other. A plain collision
nudges; a dash just before impact hits much harder. Tested: Pip dashing into an
idle Rook shoves Rook from 4.5 units out to nearly 11 within two seconds — most
of the way to the rim, where the slope takes over — while Pip rebounds toward
the centre.

**Understanding it**

- **`add_child` before `setup`.** `setup()` reaches into the ball's `Mesh`
  child, and children only exist once the ball is inside the scene tree.
- **`contact_monitor`** has to be on, with `max_contacts_reported` above zero,
  or a `RigidBody3D` never emits `body_entered`.
- **The bump formula**, one step at a time:
  1. `away` — the direction from the other ball to you, flattened.
  2. `approach` — how fast you were closing along that line. Only the closing
     speed counts: a glancing rub barely registers; a head-on charge hits hard.
  3. `power` — a base kick plus the approach speed, scaled by the *other*
     ball's bump power (doubled-ish while it's dashing) and your own
     `knockback_taken`.
  4. The mass term — `sqrt(other.mass / mass)`, which deserves its own note:

  > 💡 **Why the square root?** The physics engine has already traded momentum
  > between the balls according to their masses. The first version of this game
  > multiplied the extra kick by the *full* mass ratio as well — counting weight
  > twice — and in a CPU-only test the lightest character won 1 round in 19.
  > With the square root, weight still matters but no longer decides
  > everything: across the full weight range (Pip to Rook) the same test came
  > out 4 / 7 / 7 / 5. Those numbers are from the full game, which has four
  > players.

- **`_bump_lock`** stops one contact from being counted twice on successive
  physics ticks.
- **Both balls run `_on_body_entered`** for the same collision, and each one
  pushes *itself* away. That keeps the code symmetric: nobody needs to know who
  "started" it.
- **The dash** is an impulse (an instant change of velocity) rather than a
  force. For a moment afterwards your bumps hit harder, and in mid-air it's
  weaker — enough to claw back from the rim now and then, not enough to make
  falling harmless.

### Stage 4 — Rounds and scores

**Two helpers on the ball.** Add these functions to `scripts/ball.gd` (anywhere
inside the class; above `_physics_process` is a good spot):

```gdscript
## Put the ball back on the dome, alive, for a new round.
func reset_to(pos: Vector3) -> void:
	alive = true
	_off_edge = false
	_cooldown = 0.0
	_dash_timer = 0.0
	_bump_lock.clear()
	collision_layer = LAYER_BALLS
	collision_mask = LAYER_BALLS | LAYER_ARENA
	freeze = false
	visible = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = pos

## Hold still for the countdown. The dome has no flat spot, so anything less
```

```gdscript
## Hold still for the countdown. The dome has no flat spot, so anything less
## than a real freeze and everyone quietly rolls away before GO.
func set_frozen(value: bool) -> void:
	set_physics_process(not value)
	freeze = value
	if value:
		_move_input = Vector2.ZERO
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
```

**Spawn points on the arena.** Add this to `scripts/arena.gd`:

```gdscript
## Where player `index` of `count` starts: evenly spaced on a ring part-way out.
func spawn_transform(index: int, count: int, ball_radius: float) -> Vector3:
	var ring := play_radius * 0.42
	var angle := TAU * float(index) / float(maxi(count, 1)) + PI * 0.25
	var pos := Vector3(cos(angle) * ring, 0.0, sin(angle) * ring)
	pos.y = surface_height(ring) + ball_radius
	return pos

## Builds the visible cap: rings of quads from the centre out to play_radius,
```

**A minimal HUD.** In `main.tscn`, add a **CanvasLayer** named `HUD` under
`Main`, with two **Label** children:

- `Message`: Anchors Preset **Full Rect**; Horizontal and Vertical Alignment
  *Center*; Theme Overrides → Font Sizes → Font Size `56`, Constants → Outline
  Size `12`.
- `Scores`: Anchors Preset **Top Wide**; Horizontal Alignment *Center*; Font
  Size `26`, Outline Size `8`.

**The round loop.** Replace `scripts/main.gd`:

```gdscript
extends Node3D
## The round loop: countdown -> play -> someone wins -> next round.

const BALL_SCENE := preload("res://scenes/ball.tscn")
const PICKS := [0, 2]   ## Player 1 is Pip, player 2 is Rook.
const COUNTDOWN_LENGTH := 3.0
const ROUND_END_HOLD := 2.5

enum State { COUNTDOWN, PLAYING, ROUND_END }

@onready var arena: Arena = $Arena
@onready var message: Label = $HUD/Message
@onready var score_label: Label = $HUD/Scores

var state := State.COUNTDOWN
var balls: Array[BumperBall] = []
var scores: Array[int] = []
var _timer := 0.0

func _ready() -> void:
	for slot in PICKS.size():
		var ball := BALL_SCENE.instantiate() as BumperBall
		add_child(ball)   # add first: setup() reaches into the ball's children
		ball.setup(slot, GameConfig.ROSTER[PICKS[slot]], arena)
		balls.append(ball)
		scores.append(0)
	_start_round()

func _start_round() -> void:
	for i in balls.size():
		balls[i].reset_to(arena.spawn_transform(i, balls.size(), BumperBall.RADIUS))
		balls[i].set_frozen(true)
	state = State.COUNTDOWN
	_timer = COUNTDOWN_LENGTH
	_show_scores()

func _process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_timer -= delta
			message.text = str(ceili(_timer))
			if _timer <= 0.0:
				message.text = "GO!"
				for b in balls:
					b.set_frozen(false)
				state = State.PLAYING
				# Clear "GO!" after a moment -- unless the round is already over.
				get_tree().create_timer(0.8).timeout.connect(func() -> void:
					if state == State.PLAYING:
						message.text = "")
		State.PLAYING:
			var alive := balls.filter(func(b: BumperBall) -> bool: return b.alive)
			if alive.size() <= 1:
				_finish_round(alive)
		State.ROUND_END:
			_timer -= delta
			if _timer <= 0.0:
				_start_round()

func _finish_round(survivors: Array) -> void:
	if survivors.size() == 1:
		var winner: BumperBall = survivors[0]
		scores[winner.slot] += 1
		message.text = "%s WINS THE ROUND" % winner.stats["name"]
	else:
		message.text = "DRAW"
	_show_scores()
	state = State.ROUND_END
	_timer = ROUND_END_HOLD

func _show_scores() -> void:
	var parts := PackedStringArray()
	for b in balls:
		parts.append("P%d %s: %d" % [b.slot + 1, b.stats["name"], scores[b.slot]])
	score_label.text = "      ".join(parts)
```

✅ **Checkpoint.** A 3‑2‑1 countdown with both balls pinned in place, **GO!**,
then play until one ball is left: "Pip WINS THE ROUND", the score updates, and
a new round starts.

Now leave both players alone for a round. You'll get **DRAW**, every time. The
two spawn points mirror each other, and how fast you slide down a slope doesn't
depend on mass — gravity pulls a light ball and a heavy ball equally — so both
balls go over the edge on the same physics tick. The real game breaks that tie
by knockout order: whoever dropped *last* wins (see Part 2,
[5. The match flow](#5-the-match-flow)).

**Understanding it**

- **A state machine.** `state` says which phase the round is in, and
  `_process` does different work in each. Every system you add in Part 2 hangs
  off these phases.
- **The countdown freeze is a real `freeze`,** not just "ignore input": the
  dome has no flat spot, so any ball left to physics during the countdown has
  quietly rolled away by GO. The first version of the game shipped exactly
  that bug — every ball fell off during the countdown.
- **`create_timer(0.8).timeout.connect(func ...)`** runs a small anonymous
  function later. It checks `state` first, because by the time it fires the
  round may be over and "GO!" long replaced.
- **`balls.filter(func(b) -> bool: return b.alive)`** — GDScript lambdas
  work like anonymous functions in most languages.

You now have the core game in about 350 lines: a dome that pulls you off,
physical steering, weight-aware collisions, dashes, and rounds.

---

## Part 2 — Growing it into the real game

From here on, the repository is your answer key. Each chapter says what the
system adds, walks through how the real code does it — every excerpt is copied
verbatim from the file named above it — and ends with a way to build it
yourself before you look.

The chapters are in an order where each one builds on the last. The real game
also swaps some of your prototype's structure as it grows (a `Balls` node to
hold the players, `setup()` taking more arguments, a full HUD scene), so when a
chapter changes something you already wrote, compare your file with the repo's
before moving on.

### 1. Map of the real project

```
project.godot          settings, input map (4 players × keyboard + pad), autoloads
export_presets.cfg     Web, Android and iOS export settings
scenes/
  main.tscn            world: environment, lights, Arena, Balls, CameraRig, HUD
  arena.tscn           the dome's nodes (surface, skirt, rim, pillar, collision)
  ball.tscn            one ball (mesh, glow, ground marker, name tag, collision)
  hud.tscn             every 2D screen: scores, messages, lobby, pause, touch
shaders/
  dome.gdshader        shrinks the dome on the GPU
scripts/
  game_config.gd       autoload: roster, the four player slots, scores
  controls.gd          autoload: which input you used last; phone/tablet/desktop
  sfx.gd               autoload: pooled sound effects; the one way to quit
  main.gd              the match: lobby → countdown → rounds → results
  arena.gd             the dome's collision and its shrinking
  ball.gd              one ball: steering, dash, bumps, falling, visuals
  ai_brain.gd          a CPU player's decisions
  camera_rig.gd        the orbiting camera and its framing
  hud.gd               all 2D UI, turning input into requests for main.gd
  touch_controls.gd    on-screen stick, dash and pause button
tools/                 test harnesses, screenshot/video capture, sound generator
audio/                 generated .wav files
docs/                  README images and this guide
```

Three **autoloads** (`GameConfig`, `Controls`, `Sfx`) hold anything that's
global. `main.gd` owns the rules and the state machine; `hud.gd` owns what's on
screen. They talk in one direction each: main *tells* the HUD what to show, and
the HUD *asks* main to do things — it never changes game state itself.

### 2. The real dome — shrinking it on the GPU

**What it adds:** the dome closes in during a round, with an orange danger band
at the edge, concentric bands so you can judge distance, a glowing rim, a skirt
and a pillar underneath.

Your Stage 1 dome builds its mesh in GDScript. The obvious way to shrink it is
to rebuild that mesh as the radius changes — and that's what this game first
did. Measured, each rebuild took **9.7 ms** (21 ms at worst), several times a
second during the squeeze. That's most of a 16.6 ms frame on a desktop, and
dropped frames on a phone.

So the real game builds the mesh **once**, at full size and flat, and lets the
GPU do the rest. The vertex shader folds every vertex outside the current rim
back onto it, then lifts it onto the sphere:

From `shaders/dome.gdshader`:

```glsl
void vertex() {
	float r = length(VERTEX.xz);
	if (r > play_radius && r > 0.0001) {
		VERTEX.xz *= play_radius / r;
		r = play_radius;
	}
	VERTEX.y = sqrt(dome_radius * dome_radius - r * r) - dome_radius;
	NORMAL = normalize(VERTEX - vec3(0.0, -dome_radius, 0.0));
	v_radius = r;
}
```

Vertices that fold onto the rim make zero-area triangles, which the GPU skips.
Colour is worked out per pixel from the same radius, so the danger band follows
the rim exactly:

```glsl
void fragment() {
	float t = clamp(v_radius / max(play_radius, 0.001), 0.0, 1.0);
	vec3 c = mix(color_inner, color_mid, smoothstep(0.0, 0.8, t));
	c = mix(c, color_edge, smoothstep(0.80, 1.0, t));
	// Concentric bands for reading distance to the edge and your own speed. The
	// per-vertex version was interpolated into soft bands; this matches it.
	float band = 0.5 + 0.5 * cos(v_radius / band_width * PI);
	c *= 1.0 - 0.12 * band;
	ALBEDO = c;
	ROUGHNESS = 0.62;
	METALLIC = 0.08;
	RIM = 0.45;
	RIM_TINT = 0.5;
}
```

Changing the radius is now just a handful of property writes — about
**0.35 ms**, cheap enough to do every frame (the old version rebuilt in steps,
and you could see the rim tick inward):

From `scripts/arena.gd`:

```gdscript
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
```

A few details worth noticing in `arena.gd`:

- The **skirt** is modelled once as a ring of radius 1 whose top edge sits at
  `y = 0`, so scaling it by the radius and lifting it to the rim fits it at any
  size.
- The **rim** and **pillar** are `TorusMesh` and `CylinderMesh`. Those
  regenerate in native code when their properties change, so they're cheap.
  Careful with `TorusMesh`: `rings` is the number of segments *around the
  ring*, and `ring_segments` is the tube's cross-section. The first version had
  them swapped, and the glowing rim came out as an octagon.
- `_surface.custom_aabb` is set by hand, because Godot can't know the shader
  moves vertices. Vertices only ever move inward, so the full-size box is
  always safe.

The shrink itself is scheduled in `main.gd`: a grace period, then a slow
squeeze that speeds up the longer the round drags on:

From `scripts/main.gd`:

```gdscript
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
```

🔨 **Build it yourself:** replace `_build_cap` with a *flat* grid, give the
surface a `ShaderMaterial`, and write the vertex function above. Add a
`set_play_radius()` that updates the shader parameter, and call it from your
round loop. Then add the fragment shader and the skirt.

### 3. Making the ball readable

**What it adds:** a floating name tag, a coloured ring on the ground beneath
each ball, a glow when dashing, and a squash on impact.

The interesting part is that the ball is a spinning rigid body, so anything
parented to it spins too. A name tag would orbit the ball, and the ground ring
would tumble. So `_process` places both by hand every frame, in world space:

From `scripts/ball.gd`:

```gdscript
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
	var marker_basis := _basis_from_up(dome_normal)
	_marker.global_transform = Transform3D(marker_basis, global_position + Vector3.UP * (ground_y - global_position.y + 0.04))
	_marker.visible = not _off_edge
	_tag.no_depth_test = not _off_edge

	var pop := 1.0 + _squash * 0.22
	_mesh.scale = Vector3(pop, 1.0 / pop, pop)

	var charge := 1.0 if _cooldown <= 0.0 else 0.0
	var flare: float = maxf(_dash_timer / DASH_WINDOW, _squash * 0.6)
	var color: Color = stats["color"]
	_glow_material.albedo_color = Color(color.r, color.g, color.b, flare * 0.55 + charge * 0.08)
	_base_material.emission_energy_multiplier = 0.12 + flare * 1.4
```

- The tag ignores depth (`no_depth_test`) so you can always find yourself in a
  scrum — except once you're over the edge, when the dome should hide it.
  Leaving that on made labels float over solid dome with no ball beneath them.
- The ball emits two signals when hit: `bumped` once per collision (for sound
  and camera shake) and `hit` on each ball that took an impulse (for vibration
  and rumble, which need to know *whose* ball it was).

🔨 **Build it yourself:** add a `Label3D` and a `TorusMesh` ring to
`ball.tscn`, and position them in `_process` as above. Then try parenting the
label normally and watch it orbit.

### 4. The camera

**What it adds:** a camera that slowly orbits, follows the action a little,
keeps the whole dome in view, and shakes on big hits.

From `scripts/camera_rig.gd`:

```gdscript
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
```

- `_distance` is the camera's **horizontal** distance; its height is
  `_distance × 0.84`, which puts it about 40° above the dome.
- The binding constraint is the **near rim**. It sits well below the point the
  camera looks at, so move in too close and the front of the dome drops out of
  the bottom of the frame. `play_radius × 1.93` comes from working through that
  geometry for a 58° field of view.
- `MIN_DISTANCE` stops the camera following the dome all the way down as it
  shrinks. Without it, the dome stayed the same size *on screen* — at radius 8
  it still filled 98% of its full-size footprint — and the closing rim, the
  whole second half of a round, was invisible.
- `lerp(a, b, 1 − pow(k, delta))` is frame-rate-independent smoothing: it
  closes the same fraction of the gap per second at 30 or 144 frames per
  second.

The width limit handles narrow screens. `Camera3D` keeps its *vertical* field
of view, so a tall, narrow window loses sideways view:

```gdscript
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
	# Only the width the on-screen controls leave uncovered counts.
	var usable := clampf(1.0 - Controls.reserved_width / size.x, 0.3, 1.0)
	var aspect := size.x * usable / size.y
	var tilt := sqrt(1.0 + BASE_HEIGHT_RATIO * BASE_HEIGHT_RATIO)
	var half_width := tan(deg_to_rad(camera.fov * 0.5)) * aspect * tilt
	return radius * WIDTH_MARGIN / maxf(half_width, 0.001)
```

It's a *floor*, not a multiplier. On any normal screen the vertical framing
already asks for more distance, so this changes nothing there.

**Camera-relative steering.** Because the camera orbits, "up on the stick"
must mean "away from the camera", not "toward −Z":

From `scripts/ball.gd`:

```gdscript
	var raw := Input.get_vector(
		"p%d_left" % p, "p%d_right" % p, "p%d_up" % p, "p%d_down" % p)
	# Hold the stick "away from the camera" and go away from the camera, whatever
	# the orbit has done since the round started.
	_move_input = raw.rotated(-GameConfig.camera_yaw)
```

Your prototype's fixed camera got away without this. With a slowly orbiting
camera, world-relative controls drift out of line with the screen partway
through a round.

🔨 **Build it yourself:** make a `CameraRig` node with a `Camera3D` child, move
your camera into it, and call `frame()` from `main._process` with the living
balls' positions. Add the orbit last, and publish its angle through
`GameConfig.camera_yaw`.

### 5. The match flow

**What it adds:** a lobby, matches of first-to-3, knockout order, a results
screen, restarting, and clean teardown.

The real `main.gd` is your Stage 4 loop with more states:
`LOBBY → COUNTDOWN → PLAYING → ROUND_END → (next round | MATCH_END)`. Every
state change goes through one function, which also tells the HUD which screen
it's on:

From `scripts/main.gd`:

```gdscript
## Moves the state machine and tells the HUD which screen it is on.
func _set_state(value: int) -> void:
	state = value
	match value:
		State.LOBBY:
			hud.set_phase(&"lobby")
		State.MATCH_END:
			hud.set_phase(&"match_end")
		_:
			hud.set_phase(&"match")
```

Round results break your prototype's DRAW using **knockout order** — whoever
fell last wins:

```gdscript
func _finish_round() -> void:
	_set_state(State.ROUND_END)
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
		_set_state(State.MATCH_END)
		_timer = ROUND_END_HOLD
```

The results screen shows the winner, waits, and only then offers **Rematch** /
**Lobby**, so a button press left over from the round can't skip past it:

```gdscript
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

	# The rematch / lobby choice only appears once the result has been on screen
	# long enough to read, so a tap or key still in flight from the last round
	# cannot skip straight past it.
	if _timer >= -MATCH_END_HOLD:
		return
	if not _match_actions_shown:
		_match_actions_shown = true
		hud.show_match_actions()
	if Input.is_action_just_pressed("game_start") or _demo:
		_start_match()
	elif Input.is_action_just_pressed("game_back"):
		_enter_lobby()
```

That "announce exactly once" flag is there because of a real bug: an earlier
version tested the timer in a way that stayed true for the whole hold, and
played the victory fanfare **174 times** in 1.2 seconds.

Tearing a match down has one subtlety. `queue_free()` only takes effect at the
end of the frame, so a departing ball can still report a knockout into the
*next* match unless you disconnect it first:

```gdscript
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
```

🔨 **Build it yourself:** extend your `State` enum, add a `_set_state()`, move
the players under a `Balls` node, and record `_knockout_order` from each
ball's `knocked_out` signal. Only record knockouts while the state is
`PLAYING` — the winner often rolls off during the results hold, and that fall
isn't part of the round.

### 6. CPU players

**What it adds:** opponents that attack, defend their position and dash, with
a skill level.

A CPU is a `RefCounted` (a plain object, not a node) owned by its ball. Each
physics tick the ball asks it for a steering direction instead of reading the
keyboard. The whole personality is a **tug-of-war between two urges** — go and
shove someone, or get back toward the middle:

From `scripts/ai_brain.gd`:

```gdscript
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

		_consider_dash(me, here, their_pos, my_ratio, arena)
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
```

- **Danger** is 0 inside a comfort ring and ramps to 1 at the rim. `desire` is
  blended from "attack" toward "home" by exactly that much. Bolder CPUs
  (higher skill) have a larger comfort ring.
- **Aim error** is re-rolled on a slow timer, not every frame. Random error
  added every frame averages out to nothing, and the CPU plays perfectly.
- **The orbit term** stops every CPU beelining for the same spot and clumping.

Target choice favours balls that are close *and* already near the edge:

```gdscript
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
```

Dashing has guards, the most important being "never dash into the void":

```gdscript
func _consider_dash(me: BumperBall, here: Vector2, there: Vector2,
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
```

CPUs draw on system randomness, so no two games play out the same. An early
version seeded every CPU from a fixed number, and every game played out
identically. Tests can still ask for a fixed seed with `--ai-seed=N`:

```gdscript
func _init(skill_level: float, seed_index: int) -> void:
	skill = clampf(skill_level, 0.0, 1.0)
	if GameConfig.ai_seed >= 0:
		_rng.seed = hash("bumper:%d:%d" % [GameConfig.ai_seed, seed_index])
	else:
		_rng.randomize()
	_wander_phase = _rng.randf() * TAU
```

🔨 **Build it yourself:** give your ball a `brain` variable. In `_read_input`,
if there is a brain, take `brain.steer(...)` instead of the keyboard. Start
with only "move toward the nearest opponent" and watch the CPUs chase each
other straight off the edge. Add the danger blend next, then the dash.

### 7. Four players, gamepads and the lobby

**What it adds:** up to four local players, each on keys or a gamepad, CPUs
filling the empty slots, and a lobby to set that up.

**Input.** `project.godot` defines `p1_*` through `p4_*`. Each action has a
keyboard key *and* the matching gamepad's stick, d-pad and buttons — slot N
listens to joypad device N−1. Look at its `[input]` section alongside
**Project Settings → Input Map**. Two things there were learned the hard way:

- Godot 4.3's built-in `ui_accept` has **no gamepad button** — only Enter,
  keypad Enter and Space. So a controller could move through a menu but never
  press anything. The project overrides `ui_accept` to add pad A.
- A pad's **Start** button was once bound to both "join slot" and "start
  match", so pressing it did both at once.

**Slots.** `GameConfig` holds four slots, each `OFF`, `CPU` or `HUMAN`, with a
character and a score:

From `scripts/game_config.gd`:

```gdscript
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
```

```gdscript
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
```

In the lobby, each slot's own dash key cycles it **CPU → Player → Empty**, but
never empties a slot if that would leave fewer than two balls:

From `scripts/main.gd`:

```gdscript
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
```

```gdscript
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
		_lobby_changed()

	if Input.is_action_just_pressed("game_start"):
		_try_start_match()
```

🔨 **Build it yourself:** add the other two players' actions, make
`GameConfig` hold slots rather than a fixed pick list, and spawn one ball per
active slot. Add the lobby state last.

### 8. The HUD

**What it adds:** score chips, announcements, the lobby's player cards, results
buttons and the pause menu — all in one `CanvasLayer`.

The key design rule: **the HUD never changes game state.** A click, a tap or a
menu key becomes a *request* — a signal — and `main.gd` decides what it means.
So each action has exactly one implementation, whether it came from a
keyboard, a pad or a finger:

From `scripts/hud.gd`:

```gdscript
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
```

And on the other side, `main.gd` connects them:

From `scripts/main.gd`:

```gdscript
## Every button and tap in the HUD arrives here as a request. The keyboard and
## gamepad paths below call the same functions, so each action has one
## implementation however it was asked for.
func _connect_hud() -> void:
	hud.start_requested.connect(_try_start_match)
	hud.rematch_requested.connect(func() -> void:
		if state == State.MATCH_END:
			_start_match())
	hud.lobby_requested.connect(_enter_lobby)
	hud.restart_requested.connect(_start_match)
	hud.pause_requested.connect(func() -> void: _set_paused(true))
	hud.resume_requested.connect(func() -> void: _set_paused(false))
	hud.slot_pressed.connect(func(slot: int) -> void:
		if state == State.LOBBY:
			GameConfig.slots[slot]["control"] = _cycle_driver(slot, 1)
			_lobby_changed())
	hud.character_step.connect(func(slot: int, step: int) -> void:
		if state == State.LOBBY:
			GameConfig.cycle_character(slot, step)
			_lobby_changed())
```

Most widgets are built in code, because there are four of each and they change
colour per character. Buttons have a deliberate **focus policy**:

From `scripts/hud.gd`:

```gdscript
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
```

The lobby cards are the buttons for "who plays this slot". A tap arrives as an
emulated mouse click, so one handler covers both:

```gdscript
func _on_card_input(event: InputEvent, slot: int) -> void:
	# A tap arrives here as an emulated left click, so this covers both.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_pressed.emit(slot)
```

On short screens (a phone), the lobby compacts itself and keeps clear of the
notch:

```gdscript
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
```

Two layout bugs to learn from: the cards used to centre their contents, so the
human player's card (one extra line of hints) had its title and colour swatch
out of line with the CPU cards beside it. And `pop_message()` read the label's
size before the container had laid it out, so the first countdown number grew
out of the top-left corner instead of its centre — hence the
`await get_tree().process_frame` at its start.

🔨 **Build it yourself:** replace the prototype's two labels with `hud.tscn`
and `hud.gd` one piece at a time. Start with the score chips, then the
messages, then the lobby. Keep to the rule: the HUD emits requests; `main.gd`
acts on them.

### 9. Sound

**What it adds:** eight sound effects — with no audio files downloaded at all.

`tools/make_sfx.py` *synthesises* every effect with the Python standard
library: sine waves, filtered noise and envelopes, written out as `.wav` files.
Run it and it regenerates `audio/`. For example, the bump:

From `tools/make_sfx.py`:

```python
    # Ball-on-ball thump: a low sine drop with a click of noise on the front.
    n = int(SR * 0.16)
    write("bump", [
        (0.75 * tone(190 - 90 * i / n, i / SR)
         + 0.3 * random.uniform(-1, 1) * (1 - i / n) ** 8) * env(i, n, 0.002, 2.5)
        for i in range(n)
    ])
```

`sfx.gd` is a small pool of `AudioStreamPlayer`s used round-robin, so a burst
of bumps can overlap:

From `scripts/sfx.gd`:

```gdscript
func play(key: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(key):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[key]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
```

It also owns **quitting**. Quitting while a sound was still playing left Godot
reporting leaked objects at exit, because stopping a sound only *marks* it for
release — the audio thread has to let go of it first. So every way out of the
game comes through here:

```gdscript
## Every way out of the game goes through here. Quitting while a sound is still
## playing -- closing the window mid-beep, Android back in the lobby -- left its
## playback with the AudioServer, which Godot reports at exit as leaked objects
## and a resource still in use. stop() only marks a playback for release: the
## audio thread has to fade it out and hand it back before the main thread can
## free it. That is measured in mix buffers, not frames -- a headless run can
## race through several frames before the audio thread wakes once -- so wait on
## the clock. A tenth of a second is a handful of mix buffers, and nobody
## notices it on the way out.
const QUIT_GRACE := 0.1

func quit_game(exit_code := 0) -> void:
	_silence()
	await get_tree().create_timer(QUIT_GRACE, true, false, true).timeout
	get_tree().quit(exit_code)
```

It waits on the **clock**, not on frames. With a three-frame wait the leak
still turned up in 3 runs out of 8; with a tenth of a second it turned up in
none of 12.

### 10. Pausing

**What it adds:** a pause menu (Resume, Restart match, Quit to lobby) from Esc,
P, a pad's Start or the on-screen button.

Pausing sets `get_tree().paused`, which stops every node whose process mode is
the default. The HUD scene is set to **Process Mode: Always**, so it keeps
running — which it has to, to notice the key that *un*pauses.

From `scripts/main.gd`:

```gdscript
func _set_paused(value: bool) -> void:
	if value and not _in_match():
		return
	get_tree().paused = value
	hud.show_pause(value)
```

The same key opens and closes the menu, so exactly **one** place reads it. If
`main.gd` opened the menu and the HUD closed it, both would see the same key
press in the same frame, and the menu would open and shut at once:

From `scripts/hud.gd`:

```gdscript
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
```

Keyboard and pad players navigate the pause menu by focus. A touchscreen
doesn't, and a focus ring on a phone just looks like a stuck highlight:

```gdscript
func _focus_pause() -> void:
	# Pads and keyboards navigate the menu with focus; a touchscreen does not,
	# and a focus ring on a phone just looks like a stuck highlight.
	if _paused and not Controls.is_touch():
		_resume_button.grab_focus()
	elif _pause.get_viewport():
		_pause.get_viewport().gui_release_focus()
```

Before this menu existed, Esc threw the match away on the spot, and pad B did
the same by accident.

### 11. Phones, tablets — and whatever you touched last

**What it adds:** touch controls, a larger UI on handhelds, safe areas,
landscape lock, a portrait prompt on the web, the Android back button,
auto-pause when you switch apps, and vibration.

**One idea runs through all of it:** the UI follows whatever input was used
*last*, rather than guessing from the platform. Press a key and hints name
keys; press a pad button and they name pad buttons; touch the screen and the
on-screen controls appear. That's what makes a touchscreen laptop, a tablet
with a paired pad, or a phone with a keyboard all behave sensibly:

From `scripts/controls.gd`:

```gdscript
func _input(event: InputEvent) -> void:
	var next := mode
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		next = Mode.TOUCH
	elif event is InputEventKey and event.pressed:
		next = Mode.KEYBOARD
	elif event is InputEventMouseButton and event.pressed:
		# A tap also arrives as an emulated mouse click. Only a real mouse
		# means the player has moved to a desk.
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			next = Mode.KEYBOARD
	elif event is InputEventJoypadButton and event.pressed:
		next = Mode.GAMEPAD
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		next = Mode.GAMEPAD
	if next != mode:
		mode = next
		mode_changed.emit(mode)

## Safe-area insets in UI units: notches, rounded corners, home indicator. On
## desktop the window is not fullscreen and the display's safe area says
```

Separately, the **form factor** (desktop, tablet or phone) is decided once at
startup and sets the UI scale. Native builds report the screen's real DPI; the
web reports CSS pixels, so it needs a different threshold:

```gdscript
func _detect_form_factor() -> int:
	var web_handheld := OS.has_feature("web_android") or OS.has_feature("web_ios")
	if not (OS.has_feature("mobile") or web_handheld):
		return FormFactor.DESKTOP
	var size := Vector2(DisplayServer.screen_get_size())
	var short_side := minf(size.x, size.y)
	if web_handheld:
		var css := short_side / maxf(DisplayServer.screen_get_scale(), 1.0)
		return FormFactor.PHONE if css < PHONE_MAX_SHORT_SIDE_CSS_PX else FormFactor.TABLET
	var inches := short_side / float(maxi(DisplayServer.screen_get_dpi(), 1))
	return FormFactor.PHONE if inches < PHONE_MAX_SHORT_SIDE_INCHES else FormFactor.TABLET

## `-- --phone`, `--tablet` or `--touch` fake a handheld on desktop, which is how
```

**Touch controls** read raw touches by finger index rather than using
`Button`s. Godot only turns the *first* finger into an emulated mouse click, so
a Button-based dash would stop working whenever your thumb was already on the
stick:

From `scripts/touch_controls.gd`:

```gdscript
func _touch_down(index: int, pos: Vector2) -> void:
	if _pause_rect().has_point(pos):
		pause_requested.emit()
		return
	if not _has_ball():
		return
	if _dash_index == -1 and pos.distance_to(_dash_center()) <= DASH_RADIUS * 1.25:
		_dash_index = index
		_hold(_action("dash"), 1.0)
	elif _stick_index == -1 and pos.x < size.x * STICK_ZONE and pos.y > TOP_BAND:
		_stick_index = index
		_stick_base = pos
		_stick_knob = pos
		_write_stick(Vector2.ZERO)
	queue_redraw()
```

They don't talk to the ball at all. They press the same `p1_*` actions a
keyboard would, with an analogue strength, so camera-relative steering and
everything else come for free:

```gdscript
## The InputMap's own 0.25 deadzone applies on top, same as for a real stick.
func _write_stick(v: Vector2) -> void:
	_set_strength(_action("right"), maxf(v.x, 0.0))
	_set_strength(_action("left"), maxf(-v.x, 0.0))
	_set_strength(_action("down"), maxf(v.y, 0.0))
	_set_strength(_action("up"), maxf(-v.y, 0.0))
```

```gdscript
## Only releases actions this node pressed. Releasing blindly would cancel a
## key the player is holding on a keyboard at the same moment.
func _let_go(action: String) -> void:
	if _pressed.has(action):
		Input.action_release(action)
		_pressed.erase(action)
```

On a 4:3 tablet, the dome filled the screen's width, and the stick and DASH
sat on top of its edges — under your thumbs, exactly where knock-offs happen.
So the touch controls publish how much width they cover
(`Controls.reserved_width`), and the camera's width limit from chapter 4
subtracts it. On phones, which are wide, that changes nothing.

The rest, briefly (all in the files named):

- **Landscape lock** is a project setting (Display → Window → Handheld →
  Orientation: *Sensor Landscape*). A browser can't lock orientation, so
  `hud.gd` shows "Turn your phone sideways" in portrait and pauses any match.
- **Android's back button** arrives as `NOTIFICATION_WM_GO_BACK_REQUEST`
  (`hud.gd`, `_notification`), with the project setting
  `application/config/quit_on_go_back` turned off so Godot doesn't simply quit.
- **Switching apps** arrives as `NOTIFICATION_APPLICATION_PAUSED` /
  `FOCUS_OUT` and pauses the match on handhelds.
- **Vibration** (`main.gd`, `_rumble`) buzzes the phone for the touch player and
  the matching gamepad for everyone else.
- **Name tags** are 3D, so the 2D UI scale doesn't reach them; `ball.gd`
  multiplies their size by the same factor.

🔨 **Build it yourself:** start with `Controls` and nothing but the mode
switching — print the mode whenever it changes. Then write the stick alone,
drawing it with `_draw()` and pressing actions with `Input.action_press`. Run
the desktop build with `-- --phone` to get the phone layout without a device.

### 12. Exporting

`export_presets.cfg` has three presets. They all leave `tools/` out of the
package, and `docs/` contains a `.gdignore` so its images aren't imported into
the game at all.

- **Web**: *thread support off*. That's what lets the build run from any
  static host (itch.io, GitHub Pages) without special server headers, and in
  mobile browsers.
- **Android / iOS**: install the export templates (Editor → Manage Export
  Templates); for Android also the Android SDK and a keystore, and for iOS a
  Mac with Xcode and your team ID. Change the placeholder package name
  `com.example.bumperballs` before publishing. Texture import for mobile
  (Rendering → Textures → VRAM Compression → Import ETC2 ASTC) is already on.

### 13. Testing the way this project does

Everything in `tools/` exists because a real bug slipped past a less direct
check. The approach: **drive the real game with synthetic input**, and check
what happens.

```sh
# Four CPUs play forever, printing a line per round. The soak test and attract mode.
godot --headless --path . -- --cpu-demo --quit-after=120

# Touch at a phone layout: taps, the stick, two-finger dash, pause, Android back
xvfb-run godot --path . res://tools/touch_test.tscn --resolution 1600x740 -- --phone

# Keyboard and gamepad: pause, menu navigation with d-pad and A, results
xvfb-run godot --path . res://tools/desktop_test.tscn --resolution 1280x720

# Every InputMap action resolves, and each slot's keys move its stick
godot --headless --path . res://tools/capture.tscn -- --input-test
```

(`xvfb-run` provides a virtual display on Linux. On Windows or macOS, drop it.)

The tests inject events with `Input.parse_input_event`, the same path a real
device takes. Touch events are given in *window* pixels while the UI works in
scaled units, so the harness converts:

From `tools/touch_test.gd`:

```gdscript
## Events enter at window coordinates; the UI works in scaled units.
func _to_window(ui: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * ui
```

Three habits worth copying:

- **Make each test fail on purpose once.** Break the thing it checks and
  confirm it goes red. One check in this project passed without its fix too —
  it couldn't fail, so it was deleted.
- **Look at the screenshots.** `tools/ui_shots.tscn` stages every screen at any
  resolution. Several layout bugs in this project had passed every logic test.
- **See the editor's warnings from the command line.** Godot's CLI doesn't
  print GDScript warnings. Copy the project somewhere, set each
  `debug/gdscript/warnings/*` setting to `2` (error) in that copy, and load
  every script: each warning then fails loudly, with file and line.

---

## Part 3 — Lessons from the bugs

Every one of these happened while building this project. Read the symptom
first and try to guess the cause before you read on — that is most of the
value.

### Physics and feel

| Symptom | Cause | Fix |
|---|---|---|
| Balls slid off the dome about two seconds after spawning, nobody touching anything. | The first dome was a tight sphere (radius 34) and the balls barely resisted motion (`linear_damp` 0.16), so the slope won immediately. | A flatter dome (radius 48) and much more damping (1.1). Measured from 4 units out, time to fall: 34/0.16 ≈ 4 s, 48/0.16 ≈ 4.5 s, 34/1.1 ≈ 5 s, 48/1.1 ≈ 6.5 s. Damping mattered more than curvature. |
| Balls rolled off during the 3‑2‑1 countdown. | Zeroing velocity once doesn't stop gravity pulling the ball down the slope next frame. | A real freeze (`freeze = true`) in `set_frozen()`, released on **GO!** |
| The lightest character won 1 match in 19. | Mass was counted twice: once by the physics engine, which already makes heavy balls harder to push, and again in the bump impulse formula. | Scale the bump by the *square root* of the mass ratio. Wins across the roster went to a 4 / 7 / 7 / 5 split. |
| Eliminated balls could still be bumped into. | A ball that fell was hidden, but its collision layer and mask were untouched. | Clear both in `_die()`. |
| The rim ring was an octagon. | `TorusMesh.rings` and `ring_segments` swapped: one is the number of steps *around* the torus, the other around the tube. | Swap them. When a mesh looks faceted, check which count is which. |

### Camera and controls

| Symptom | Cause | Fix |
|---|---|---|
| Players steered the wrong way once the camera had orbited. | Input was world-relative, but the camera keeps turning. | Rotate the stick by the camera's yaw: `raw.rotated(-GameConfig.camera_yaw)`. |
| The dome shrinking was barely visible. | The camera zoomed in as the platform shrank, keeping it the same size on screen (98% of the view at radius 8). | `MIN_DISTANCE`: the camera stops pulling in, so the platform visibly shrinks. |
| On a tall phone screen the dome was cut off at the sides. | `Camera3D` keeps the *vertical* field of view fixed, so narrow screens lose width. A first fix (multiply distance by a constant) was wrong on every other screen shape. | A width-fit *floor*: compute the distance that fits the dome's width and take the larger of that and the normal distance. |
| On tablets the touch controls sat over the arena. | The camera fitted the dome to the full screen width. | `Controls.reserved_width` tells the camera how much width the controls cover. |

### Match flow

| Symptom | Cause | Fix |
|---|---|---|
| The victory fanfare played 174 times in 1.2 seconds. | A time check that stayed true for the whole results hold ran every frame. | An "announced" flag so it fires once. Any "do this when…" in `_process` needs one. |
| Restarting mid-round sometimes counted a knockout in the new match. | `queue_free()` waits until end of frame; the old ball could still emit `knocked_out`. | Disconnect the ball's signals in `_clear_balls()` before freeing it. |
| CPU matches played out identically every time. | The AI's random number generator had a fixed seed. | `randomize()`, with `--ai-seed=N` for reproducible test runs. |

### Lobby and input

| Symptom | Cause | Fix |
|---|---|---|
| Two players could pick the same character. | An empty (OFF) slot's character wasn't counted as taken. | Reserve characters across all slots. |
| A keyboard player couldn't leave their slot. | Only gamepads had a "leave" button. | The dash key cycles the slot CPU → Player → Empty. |
| Pressing Start on a pad both joined and started the match. | Start was bound to `p*_join` *and* to start. | Remove Start from the join actions. |
| Menus couldn't be confirmed with a gamepad. | Godot's default `ui_accept` has no gamepad button. | Override `ui_accept` in Project Settings to include pad A. |
| `game_config.gd` failed to load: "shadows a native class". | An enum named `Control` collided with Godot's built-in `Control` class. | Rename it (`Driver`). Avoid names that match engine classes. |

### UI and mobile

| Symptom | Cause | Fix |
|---|---|---|
| Lobby cards didn't line up. | Cards were vertically centred, and each state (joined / CPU / empty) had a different height. | Top-align them and reserve the tallest state's height. |
| A pop-up message appeared in the wrong place for one frame. | Its size was read before layout ran. | `await get_tree().process_frame` before measuring. |
| A fallen player's name tag stayed visible through the dome as the ball dropped away beneath it. | Tags use `no_depth_test` so they're never hidden behind other balls — which also drew them through the dome's surface. | Turn off `no_depth_test` once the ball is off the edge: `_tag.no_depth_test = not _off_edge`. |
| Name tags were tiny on phones. | `Label3D` sizes are in world units, so UI scaling didn't reach them. | Multiply `pixel_size` by `Controls.UI_SCALE`. |
| Only the first finger worked on the touch controls. | Godot's emulated mouse follows one touch only. | Read raw `InputEventScreenTouch`/`Drag` events and track each finger by its index. |

### Rendering and platform

| Symptom | Cause | Fix |
|---|---|---|
| Run on desktop with Forward+, the dome was washed out to pale grey. | Every screenshot and test had used the Compatibility renderer, which handles tone and lighting differently — the desktop build had never looked like any of them. | Use Compatibility everywhere. The web requires it anyway, so it's the only look worth tuning. |
| Shrinking the dome cost 9.7 ms per frame. | The mesh was rebuilt on the CPU every frame. | A vertex shader folds vertices outside the play radius onto the rim: 0.35 ms. |
| Godot reported leaked objects on quit. | A sound still playing at quit; `stop()` only schedules release, and the audio thread needs a few mix buffers to hand it back. | `Sfx.quit_game()`: silence, then wait 0.1 s *of real time* before quitting. Waiting frames instead still leaked 3 times in 8; the timer 0 in 12. |

### Tooling and tests

These cost time in the test harnesses rather than the game, and they'll cost
you time too:

- **Godot's command line doesn't print GDScript warnings.** Turning them into
  errors in a throwaway copy surfaced an unused parameter, variables shadowing
  `basis`, `ready` and `name`, and a ternary with mismatched types.
- **Output printed just before a process is killed can be lost** — it's still in
  a buffer. Flush, or quit cleanly.
- **Browser touch events via Chrome DevTools**: a `touchEnd` lists the fingers
  that *remain*, not the one that lifted.
- **Software WebGL runs slowly enough to slow game time**, so timing-based web
  tests need a 1× device pixel ratio.
- **A test that can't fail is worse than none.** Break the code on purpose and
  make sure the test notices.

---

## Where to go next

Ideas to build on your own, roughly easiest first:

- **A new character.** Add an entry to `GameConfig.ROSTER` and see how mass,
  size and speed trade off against the others.
- **A "leader" indicator.** `GameConfig.leader_score()` exists but nothing uses
  it yet — show a crown over whoever's winning.
- **Arena hazards.** A bumper in the middle, or a patch of ice (lower damping)
  that appears in later rounds.
- **Smarter CPUs.** Let them use the dash to dodge, not just to attack.
- **Team mode.** Two against two; the knockout-order logic already handles
  "who's left".
