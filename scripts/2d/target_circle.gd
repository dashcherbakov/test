# scripts/2d/target_circle.gd
# The circle the seeker chases. It draws itself, runs from the point once that
# point gets close (a heavy seeker that cannot turn instantly overshoots a late
# sidestep, then spirals inward), and reports the point that touches it.
@tool
class_name TargetCircle
extends Area2D

signal point_touched(point: Node2D)

const FILL_COLOR: Color = Color(0.25, 0.85, 1.0, 0.16)
const RIM_COLOR: Color = Color(0.35, 0.9, 1.0)
const RING_WIDTH: float = 3.0
const DRAW_SEGMENTS: int = 64

## Drawn and detection radius. Kept in sync with the CollisionShape2D.
@export_range(10.0, 200.0, 1.0) var radius: float = 60.0:
	set(value):
		radius = value
		_apply_radius()
		queue_redraw()

@export_group("Evasion")
## Off => the circle stands still and the seeker flies a straight line into it.
@export var evade_enabled: bool = true
## Dash once the seeker is this close. A dash from far away is wasted: the seeker
## has room to re-aim and simply lines up again.
@export_range(0.0, 900.0, 10.0) var evade_trigger_distance: float = 320.0
## Minimum seconds between dashes.
@export_range(0.0, 10.0, 0.1) var evade_cooldown: float = 8.0
## Dashes allowed per seeker. 0 = unlimited. Unlimited dashes keep re-expanding
## the seeker's orbit, so it can circle forever and never close in.
@export_range(0, 10, 1) var max_dashes_per_threat: int = 1
@export_range(0.0, 500.0, 5.0) var dash_distance: float = 240.0
## Box the circle stays inside while dashing.
@export var dash_bounds: Rect2 = Rect2(140.0, 140.0, 1640.0, 800.0)
@export_range(0.05, 2.0, 0.05) var dash_duration: float = 0.3

@export_group("Randomness")
## 0 = reseed from the clock every run, any other value = reproducible chaos.
@export var random_seed: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _threat: Node2D = null
var _cooldown_left: float = 0.0
## -1 means no limit.
var _dashes_left: int = 0
var _tween: Tween = null


func _ready() -> void:
	_apply_radius()
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


## The point this circle runs from. Cached, so the loop never walks the tree.
func set_threat(threat: Node2D) -> void:
	_threat = threat
	# A fresh seeker deserves a fresh dash, otherwise it can arrive while the
	# previous encounter's cooldown is still running and fly straight in.
	_cooldown_left = 0.0
	_dashes_left = max_dashes_per_threat if max_dashes_per_threat > 0 else -1


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if not evade_enabled or _cooldown_left > 0.0 or _dashes_left == 0:
		return
	if _threat == null or not is_instance_valid(_threat):
		return
	if _threat.global_position.distance_to(global_position) > evade_trigger_distance:
		return
	_cooldown_left = evade_cooldown * _rng.randf_range(0.85, 1.25)
	if _dashes_left > 0:
		_dashes_left -= 1
	_dash()


func _apply_radius() -> void:
	var shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.shape is CircleShape2D:
		(shape.shape as CircleShape2D).radius = radius


func _dash() -> void:
	var perpendicular: Vector2 = _perpendicular_to_threat()
	var candidates: Array[Vector2] = [
		_clamp_to_bounds(global_position + perpendicular * dash_distance),
		_clamp_to_bounds(global_position - perpendicular * dash_distance),
	]
	# Take whichever side actually has room. A dash squashed against the edge of
	# the ring travels far too short a distance to fool the seeker, which then
	# just flies straight in - the failure this branch exists to prevent.
	var destination: Vector2 = candidates[0]
	if candidates[1].distance_to(global_position) > destination.distance_to(global_position):
		destination = candidates[1]
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "global_position", destination, dash_duration)


func _clamp_to_bounds(point: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, dash_bounds.position.x, dash_bounds.end.x),
		clampf(point.y, dash_bounds.position.y, dash_bounds.end.y)
	)


## Sidesteps across the seeker's heading. That is the widest possible miss, and
## the seam where the seeker's inertia turns a near hit into a loop around us.
func _perpendicular_to_threat() -> Vector2:
	var heading: Vector2 = Vector2.ZERO
	var body: RigidBody2D = _threat as RigidBody2D
	if body != null:
		heading = body.linear_velocity
	if heading.length() < 1.0:
		return Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
	return heading.normalized().orthogonal()


func _on_body_entered(body: Node2D) -> void:
	if body is ChaserPoint:
		point_touched.emit(body)


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, FILL_COLOR)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, DRAW_SEGMENTS, RIM_COLOR, RING_WIDTH, true)
