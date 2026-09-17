# scripts/2d/target_circle.gd
# A circle the seeker can chase. It draws itself, dodges on command - the player
# presses the dash key, and a heavy seeker that cannot turn instantly overshoots
# a late dodge and then spirals inward - and reports the point that touches it.
# Which circle is active, and therefore chased, clickable and dodgeable, is
# decided by the spawner, which owns the input.
@tool
class_name TargetCircle
extends Area2D

## Emitted when the point touches this circle.
signal point_touched(point: Node2D)

const ACTIVE_FILL: Color = Color(0.25, 0.85, 1.0, 0.16)
const ACTIVE_RIM: Color = Color(0.35, 0.9, 1.0)
const ACTIVE_RING_WIDTH: float = 3.0
const IDLE_FILL: Color = Color(0.45, 0.62, 0.72, 0.06)
const IDLE_RIM: Color = Color(0.45, 0.6, 0.7, 0.75)
const IDLE_RING_WIDTH: float = 1.5
const DRAW_SEGMENTS: int = 64

## Circles announce themselves in this group, so the spawner finds however many
## the scene has, and a dashing circle can see its siblings, without anyone
## holding a per-circle reference.
const GROUP: String = "target_circles"
## Dash directions to try, as offsets from the sidestep across the seeker's
## heading. The plain sidestep is first because it is the one that makes a heavy
## seeker overshoot; the rest are fallbacks for when that side is blocked by the
## edge of the field or by the other circle.
const DASH_ANGLE_OFFSETS: Array[float] = [
	0.0, PI, PI / 6.0, -PI / 6.0, PI / 3.0, -PI / 3.0, PI / 2.0, -PI / 2.0,
]
## A candidate counts as unclipped when it travels at least this share of the
## dash. A dash squashed against the bounds is too short to fool the seeker.
const DASH_CLIP_TOLERANCE: float = 0.75

## Drawn and detection radius. Kept in sync with the CollisionShape2D.
@export_range(10.0, 200.0, 1.0) var radius: float = 60.0:
	set(value):
		radius = value
		_apply_radius()
		queue_redraw()

## True while this is the circle the dot chases. Clicking a circle makes it the
## active one; the others are drawn dimmed and do not intercept the dot.
var is_active: bool = false:
	set(value):
		if is_active == value:
			return
		is_active = value
		queue_redraw()

@export_group("Evasion")
## Off => the circle never dodges and the seeker flies straight into it.
@export var evade_enabled: bool = true
## Minimum seconds between dodges. Short enough that a flight can be dodged more
## than once, which is what makes the dash count a real cost in the score.
@export_range(0.0, 10.0, 0.1) var evade_cooldown: float = 1.2
## Dodges allowed per circle. Selecting a circle hands it a fresh dodge, so a
## flight can be dodged once per circle it visits, and re-selecting is the only
## way to buy another one. 0 = unlimited, which lets a seeker circle forever.
@export_range(0, 10, 1) var max_dashes_per_threat: int = 1
## How far from another circle a dash must stay, measured from its centre to the
## whole path the dash travels, so two circles never end up stacked on each other
## (keep this above the two radii added together).
@export_range(0.0, 900.0, 10.0) var min_separation: float = 260.0
@export_range(0.0, 500.0, 5.0) var dash_distance: float = 240.0
@export_range(0.05, 2.0, 0.05) var dash_duration: float = 0.3

@export_group("Randomness")
## 0 = reseed from the clock every run, any other value = reproducible chaos.
@export var random_seed: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The playfield, found through MapBounds.GROUP at startup. Null means no bounds
## node in the scene, in which case dashes are not clamped at all.
var _bounds: MapBounds = null
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
		_bounds = _find_bounds()
		if _bounds == null:
			push_warning(
				"TargetCircle: no MapBounds in group '%s', dashes stay unclamped." % MapBounds.GROUP
			)


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


func _apply_radius() -> void:
	var shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.shape is CircleShape2D:
		(shape.shape as CircleShape2D).radius = radius


## Sidesteps on demand - this is what the spawner calls when the dash key is
## pressed. Returns false when there is nothing left to spend: no dash budget for
## this seeker, or the cooldown has not elapsed yet.
func dash() -> bool:
	if not evade_enabled or _cooldown_left > 0.0 or _dashes_left == 0:
		return false
	_cooldown_left = evade_cooldown * _rng.randf_range(0.85, 1.25)
	if _dashes_left > 0:
		_dashes_left -= 1
	_tween_to(_best_dash_destination(_perpendicular_to_threat()))
	return true


## Dodges still available to this circle. -1 means the budget is unlimited.
func get_dashes_left() -> int:
	return _dashes_left


## Picks where to land: the first direction in DASH_ANGLE_OFFSETS that is neither
## squashed by the bounds nor brushing another circle. Settles for a clipped but
## clear dash, and only if every direction collides does it accept the plain
## sidestep and let the two circles sort themselves out on a later dash.
func _best_dash_destination(perpendicular: Vector2) -> Vector2:
	var shortest_clear: Vector2 = Vector2.ZERO
	var shortest_clear_travel: float = -1.0
	for angle: float in DASH_ANGLE_OFFSETS:
		var candidate: Vector2 = _clamp_to_bounds(
			global_position + perpendicular.rotated(angle) * dash_distance
		)
		if _clearance(candidate) < min_separation:
			continue
		var travel: float = candidate.distance_to(global_position)
		if travel >= dash_distance * DASH_CLIP_TOLERANCE:
			return candidate
		if travel > shortest_clear_travel:
			shortest_clear = candidate
			shortest_clear_travel = travel
	if shortest_clear_travel >= 0.0:
		return shortest_clear
	return _clamp_to_bounds(global_position + perpendicular * dash_distance)


## Smallest distance from another circle's centre to the path this dash travels,
## so the dodge can neither land on a sibling nor sweep straight across one.
func _clearance(destination: Vector2) -> float:
	var smallest: float = INF
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var other: TargetCircle = node as TargetCircle
		if other == null or other == self:
			continue
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(
			other.global_position, global_position, destination
		)
		smallest = minf(smallest, nearest.distance_to(other.global_position))
	return smallest


func _tween_to(destination: Vector2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "global_position", destination, dash_duration)


## The map is the only thing keeping a circle in the playfield, so a dash aims
## inside it and passes the circle's own radius as margin.
func _clamp_to_bounds(point: Vector2) -> Vector2:
	if _bounds == null:
		return point
	return _bounds.clamp_point(point, radius)


func _find_bounds() -> MapBounds:
	var found: Array[Node] = get_tree().get_nodes_in_group(MapBounds.GROUP)
	if found.is_empty():
		return null
	return found[0] as MapBounds


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
	var fill: Color = ACTIVE_FILL if is_active else IDLE_FILL
	var rim: Color = ACTIVE_RIM if is_active else IDLE_RIM
	var width: float = ACTIVE_RING_WIDTH if is_active else IDLE_RING_WIDTH
	draw_circle(Vector2.ZERO, radius, fill)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, DRAW_SEGMENTS, rim, width, true)
