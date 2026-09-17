# scripts/2d/chaser_point.gd
# An inertial seeker: a heavy RigidBody2D that applies a fixed thrust toward its
# target. It cannot turn instantly, so a deviating target makes it overshoot,
# orbit, and spiral inward until contact.
#
# mass, linear_damp, linear_damp_mode, gravity_scale, can_sleep and lock_rotation
# are native RigidBody2D properties and are therefore configured in
# chaser_point.tscn, not redeclared here (a script member would shadow them).
@tool
class_name ChaserPoint
extends RigidBody2D

const FILL_COLOR: Color = Color(1.0, 0.72, 0.25)
const RIM_COLOR: Color = Color(0.32, 0.16, 0.02)
const DRAW_SEGMENTS: int = 32

## Turning authority. Acceleration is thrust / mass, so a lower thrust means
## wider laps: turn radius is roughly speed^2 / acceleration.
@export_range(0.0, 6000.0, 10.0) var thrust: float = 1200.0
## Top speed. Together with the thrust it fixes the tightest loop the seeker can
## fly: loop radius = max_speed^2 / (thrust / mass).
@export_range(0.0, 1200.0, 10.0) var max_speed: float = 500.0
## Fraction of top speed lost per second. The seeker keeps its inertia, but the
## loops it can hold get tighter and tighter - this is what turns "orbits the
## target forever" into "spirals in and hits". 0 = never tightens.
@export_range(0.0, 2.0, 0.005) var speed_bleed_per_second: float = 0.088
## Drawn and collision radius. Kept in sync with the CollisionShape2D.
@export_range(2.0, 64.0, 1.0) var radius: float = 8.0:
	set(value):
		radius = value
		var shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape != null and shape.shape is CircleShape2D:
			(shape.shape as CircleShape2D).radius = radius
		queue_redraw()

var _target: Node2D = null
var _speed_ceiling: float = 0.0


func _ready() -> void:
	# Re-run the setter so the collision shape and the drawing match `radius`.
	radius = radius
	_speed_ceiling = max_speed


## Caches the target reference once, so the physics loop never walks the tree.
func setup(target: Node2D) -> void:
	_target = target


## Stamps a settings resource onto this dot. Called once at spawn and again every
## time the control panel moves a slider, so mid-flight changes are live.
func apply_settings(settings: ChaserSettings) -> void:
	if settings == null:
		return
	mass = settings.mass
	thrust = settings.thrust
	linear_damp = settings.linear_damp
	radius = settings.radius
	speed_bleed_per_second = settings.speed_bleed_per_second
	var top_speed_changed: bool = not is_equal_approx(max_speed, settings.max_speed)
	max_speed = settings.max_speed
	if top_speed_changed:
		# Re-arm the ceiling. Without this, raising the top speed would only show
		# up on the next dot and the slider would look dead on the one flying.
		_speed_ceiling = max_speed


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var to_target: Vector2 = _target.global_position - state.transform.origin
	if to_target != Vector2.ZERO:
		state.apply_central_force(to_target.normalized() * thrust)
	_speed_ceiling = maxf(_speed_ceiling - max_speed * speed_bleed_per_second * state.step, 0.0)
	if state.linear_velocity.length() > _speed_ceiling:
		state.linear_velocity = state.linear_velocity.limit_length(_speed_ceiling)


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, FILL_COLOR)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, DRAW_SEGMENTS, RIM_COLOR, 2.0, true)
