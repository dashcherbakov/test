# scripts/2d/chaser_spawner.gd
# Owns the seeker lifecycle: exactly one point alive at a time. When the circle
# reports a touch, the point dies and a fresh one appears somewhere at random.
#
# Each point gets its OWN Line2D for its path. A single shared line would join
# the dead point's last sample to the next point's spawn and draw a fake corner.
# A point's line fades out after it dies.
class_name ChaserSpawner
extends Node2D

## Minimum gap between "live update" log lines while a slider is being dragged.
const UPDATE_TRACE_INTERVAL_MS: int = 250

@export var point_scene: PackedScene
@export var target: TargetCircle
## Dot parameters, shared with the control panel. Changing this resource updates
## the dot already in flight as well as every later one.
@export var settings: ChaserSettings

@export_group("Spawning")
## Region a point may appear in.
@export var spawn_rect: Rect2 = Rect2(80.0, 80.0, 1760.0, 920.0)
## Never spawn closer to the circle than this, or the point would die instantly.
@export_range(0.0, 900.0, 5.0) var min_spawn_distance: float = 420.0
## Safety net: a point that never resolves is replaced anyway. 0 = disabled.
@export_range(0.0, 60.0, 0.5) var max_lifetime_seconds: float = 15.0

@export_group("Trail")
@export var trail_enabled: bool = true
@export_range(1.0, 12.0, 0.5) var trail_width: float = 2.0
@export var trail_color: Color = Color(1.0, 0.72, 0.25, 0.45)
@export_range(40, 4000, 10) var trail_capacity: int = 1400
@export_range(0.0, 5.0, 0.1) var trail_fade_seconds: float = 1.2

@export_group("Diagnostics")
## Logs each point's spawn, swept angle and death. Useful while tuning the
## mass / thrust / damp trio on chaser_point.tscn.
@export var debug_trace: bool = false
## 0 = reseed from the clock every run, any other value = reproducible chaos.
@export var random_seed: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _current: ChaserPoint = null
var _current_trail: Line2D = null
var _lifetime: float = 0.0
var _swept_angle: float = 0.0
var _last_angle: float = 0.0
var _last_update_trace_ms: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	if target != null:
		target.point_touched.connect(_on_point_touched)
	if settings != null:
		settings.changed.connect(_on_settings_changed)
	_spawn_point()


func _physics_process(delta: float) -> void:
	if _current == null or not is_instance_valid(_current):
		return
	_lifetime += delta
	if _current_trail != null and is_instance_valid(_current_trail):
		_current_trail.add_point(_current.global_position)
		while _current_trail.get_point_count() > trail_capacity:
			_current_trail.remove_point(0)
	if debug_trace:
		_accumulate_swept_angle()
	if max_lifetime_seconds > 0.0 and _lifetime >= max_lifetime_seconds:
		_trace("timeout after %.1fs, path swept %.2f laps" % [_lifetime, _swept_angle / TAU])
		_destroy_current()


## Pure spawn-position math, kept static so it can be unit-tested without a scene.
static func pick_spawn_position(
	rng: RandomNumberGenerator, rect: Rect2, center: Vector2, min_distance: float
) -> Vector2:
	var candidate: Vector2 = Vector2(
		rng.randf_range(rect.position.x, rect.end.x),
		rng.randf_range(rect.position.y, rect.end.y)
	)
	if min_distance <= 0.0:
		return candidate
	# Rejection sample, bounded so a tiny rect can never hang the game.
	var attempts: int = 0
	while attempts < 40:
		attempts += 1
		if candidate.distance_to(center) >= min_distance:
			return candidate
		candidate = Vector2(
			rng.randf_range(rect.position.x, rect.end.x),
			rng.randf_range(rect.position.y, rect.end.y)
		)
	# Constraint unsatisfiable: push the last candidate out instead of spawning
	# straight onto the target.
	var direction: Vector2 = candidate - center
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	return center + direction.normalized() * min_distance


func _on_point_touched(point: Node2D) -> void:
	if point != _current:
		return
	_trace("touched after %.1fs, path swept %.2f laps" % [_lifetime, _swept_angle / TAU])
	_destroy_current()


## The panel writes to the shared settings resource; push it onto the dot that is
## already flying so a slider drag is visible immediately, not next spawn.
func _on_settings_changed() -> void:
	if _current == null or not is_instance_valid(_current):
		return
	_current.apply_settings(settings)
	# Dragging a slider fires this once per pixel of travel, which would bury the
	# log. Report at most a few lines per second.
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_update_trace_ms < UPDATE_TRACE_INTERVAL_MS:
		return
	_last_update_trace_ms = now_ms
	_trace("live update -> mass %.1f, thrust %.0f, ceil %.0f, bleed %.3f, damp %.2f, radius %.0f" % [
		settings.mass, settings.thrust, settings.max_speed,
		settings.speed_bleed_per_second, settings.linear_damp, settings.radius
	])


func _destroy_current() -> void:
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	_current = null
	_fade_trail(_current_trail)
	_current_trail = null
	_lifetime = 0.0
	_swept_angle = 0.0
	# Deferred: never add or remove physics bodies inside a physics callback.
	call_deferred("_spawn_point")


func _spawn_point() -> void:
	if point_scene == null or target == null:
		return
	var point: ChaserPoint = point_scene.instantiate() as ChaserPoint
	if point == null:
		return
	_current_trail = null
	if trail_enabled:
		_current_trail = _create_trail()
		# Added before the point so the point draws on top of its own path.
		add_child(_current_trail)
	add_child(point)
	point.global_position = pick_spawn_position(
		_rng, spawn_rect, target.global_position, min_spawn_distance
	)
	point.setup(target)
	point.apply_settings(settings)
	target.set_threat(point)
	_current = point
	_lifetime = 0.0
	_swept_angle = 0.0
	_last_angle = (point.global_position - target.global_position).angle()
	_trace("spawn at %s (mass %.1f, thrust %.0f, ceil %.0f, bleed %.3f)" % [
		point.global_position, point.mass, point.thrust, point.max_speed,
		point.speed_bleed_per_second
	])


func _create_trail() -> Line2D:
	var line: Line2D = Line2D.new()
	line.width = trail_width
	line.default_color = trail_color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	return line


func _fade_trail(line: Line2D) -> void:
	if line == null or not is_instance_valid(line):
		return
	if trail_fade_seconds <= 0.0:
		line.queue_free()
		return
	var tween: Tween = create_tween()
	tween.tween_property(line, "modulate:a", 0.0, trail_fade_seconds)
	tween.tween_callback(line.queue_free)


func _accumulate_swept_angle() -> void:
	if target == null:
		return
	var offset: Vector2 = _current.global_position - target.global_position
	var angle: float = offset.angle()
	_swept_angle += absf(wrapf(angle - _last_angle, -PI, PI))
	_last_angle = angle


func _trace(message: String) -> void:
	if debug_trace:
		print("[chaser] ", message)
