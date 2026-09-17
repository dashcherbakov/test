# scripts/2d/chaser_spawner.gd
# Owns the seeker lifecycle: exactly one point alive at a time. When the circle
# reports a touch, the point dies and a fresh one appears somewhere at random.
#
# Each point gets its OWN Line2D for its path. A single shared line would join
# the dead point's last sample to the next point's spawn and draw a fake corner.
# A point's line fades out after it dies.
#
# A round is settings.max_dots dots long. The counter HUD counts the spawns, and
# the last dot to collide banks its score and ends the game instead of being
# followed by a successor.
class_name ChaserSpawner
extends Node2D

## Emitted once, right after the round's last dot has collided and been banked.
## Carries the score the round finished on, so a listener has nothing to read
## back off the spawner in the same frame.
signal game_over(final_score: float)

## Minimum gap between "live update" log lines while a slider is being dragged.
const UPDATE_TRACE_INTERVAL_MS: int = 250
## Extra pixels around a circle that still count as a click on it.
const CLICK_PADDING: float = 18.0
## Input action that makes the active circle dodge. Mapped to Space in the input
## map; nothing dodges on its own any more, the player picks the moment.
const DASH_ACTION: String = "dash"

@export var point_scene: PackedScene
## The circle the dot starts out chasing. At runtime this always holds the active
## one: clicking another circle swaps it (see set_active_circle).
@export var target: TargetCircle
## Dot parameters, shared with the control panel. Changing this resource updates
## the dot already in flight as well as every later one.
@export var settings: ChaserSettings

@export_group("Spawning")
## Region a point may appear in.
@export var spawn_rect: Rect2 = Rect2(80.0, 80.0, 1760.0, 920.0)
## Never spawn closer to the circle than this, or the point would die instantly.
@export_range(0.0, 900.0, 5.0) var min_spawn_distance: float = 420.0

@export_group("Scoring")
## Points per 100 pixels the dot travels, before the live rate scales it. The
## live score is ground covered, so a long spiralling flight is worth more than a
## short straight one - and the longer it stays alive, the more each of those
## pixels is worth (see the settings' Scoring group).
@export_range(0.0, 20.0, 0.1) var points_per_100_px: float = 1.0

@export_group("Diagnostics")
## Logs each point's spawn, swept angle and death. Useful while tuning the
## mass / thrust / damp trio on chaser_point.tscn.
@export var debug_trace: bool = false
## 0 = reseed from the clock every run, any other value = reproducible chaos.
@export var random_seed: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _circles: Array[TargetCircle] = []
var _dash_action_available: bool = false
var _current: ChaserPoint = null
var _current_trail: Line2D = null
var _lifetime: float = 0.0
var _swept_angle: float = 0.0
var _last_angle: float = 0.0
var _last_update_trace_ms: int = 0
## Scoring for the dot that is flying right now, reset with every spawn.
var _live_score: float = 0.0
## Selections and dodges spent on the dot currently flying. They are what divides
## its score, so the divider is this plus one.
var _action_count: int = 0
var _last_scored_position: Vector2 = Vector2.ZERO
## Score banked from the dots that have already collided.
var _total_score: float = 0.0
## Dots put into play this round. Counted up to get_max_dots(), and the dot that
## takes it there is the last one of the round.
var _dots_spawned: int = 0
## True once the round is decided: no more spawns, no more scoring.
var _game_over: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	if settings == null:
		# Never null from here on: a missing resource just means the defaults,
		# which keeps every settings read below free of null checks.
		settings = ChaserSettings.new()
	_collect_circles()
	# Guarded, so a project without the action only loses the key, not the scene.
	_dash_action_available = InputMap.has_action(DASH_ACTION)
	if target == null and not _circles.is_empty():
		target = _circles[0]
	if target != null:
		set_active_circle(target)
	if settings != null:
		settings.changed.connect(_on_settings_changed)
	_spawn_point()


func _physics_process(delta: float) -> void:
	# Polled rather than read off the event: a focused UI control can swallow a key
	# press, and this way the dash key works whatever has focus.
	if _dash_action_available and Input.is_action_just_pressed(DASH_ACTION):
		_dash_active_circle()
	if _current == null or not is_instance_valid(_current):
		return
	_lifetime += delta
	var position_now: Vector2 = _current.global_position
	# Ground covered, scaled by the rate this flight has earned by staying alive.
	# The rate is built from _lifetime, so every dot starts at the settings'
	# baseline and a collision puts the next one back there.
	_live_score += (
		position_now.distance_to(_last_scored_position)
		* points_per_100_px / 100.0
		* get_rate_multiplier()
	)
	_last_scored_position = position_now
	if _current_trail != null and is_instance_valid(_current_trail):
		_current_trail.add_point(position_now)
		while _current_trail.get_point_count() > _trail_capacity_points():
			_current_trail.remove_point(0)
	if debug_trace:
		_accumulate_swept_angle()


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


## Circles are found by group, so adding a third one to the scene needs no
## rewiring here. Wired once at startup; see _on_point_touched for the rule.
func _collect_circles() -> void:
	_circles.clear()
	for node: Node in get_tree().get_nodes_in_group(TargetCircle.GROUP):
		var circle: TargetCircle = node as TargetCircle
		if circle == null:
			continue
		_circles.append(circle)
		circle.point_touched.connect(_on_point_touched.bind(circle))


## Makes `circle` the one the dot chases: highlights it, hands it the seeker to
## run from, and re-aims the dot already in flight, so a click bends the current
## trajectory instead of only affecting the next dot.
func set_active_circle(circle: TargetCircle) -> void:
	if circle == null or not is_instance_valid(circle):
		return
	var changed: bool = circle != target
	if changed and target != null and is_instance_valid(target):
		target.set_threat(null)
	target = circle
	for other: TargetCircle in _circles:
		other.is_active = other == circle
	circle.set_threat(_current)
	if _current != null and is_instance_valid(_current):
		if changed:
			# Read before the reset, so the log shows how spent the dot was.
			_trace("retarget -> speed ceiling %.0f, reset to %.0f" % [
				_current.get_speed_ceiling(), _current.max_speed
			])
		_current.set_target(circle)
	if changed:
		# A switch is an action, and it hands the circle that just became active a
		# fresh dodge: set_threat() is what restores that budget.
		_action_count += 1
		_trace("selection -> %s (%d action(s), %d dodge(s) on it)" % [
			String(circle.name), _action_count, circle.get_dashes_left()
		])


## Called when the dash key is pressed. The circle answers false when it has no
## dodge left for this seeker, which the trace reports so an ignored press is not
## a mystery.
func _dash_active_circle() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.dash():
		_action_count += 1
		_trace("dash -> %s (%d action(s), %d dodge(s) left on it)" % [
			String(target.name), _action_count, target.get_dashes_left()
		])
	else:
		_trace("dash ignored (that circle is out of dodges until re-selected)")


## Selection is handled here rather than by each circle: one click test in one
## place, with a little padding so a click just outside the ring still lands, and
## nothing can swallow the click the way Area2D physics picking can.
func _unhandled_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	# The event's own position, not the OS cursor: it is already in canvas space
	# and stays correct under a camera or a stretched window.
	var world_point: Vector2 = get_canvas_transform().affine_inverse() * button.position
	var clicked: TargetCircle = _circle_at(world_point)
	var clicked_name: String = "no circle"
	if clicked != null:
		clicked_name = String(clicked.name)
	_trace("click at %s -> %s" % [world_point.round(), clicked_name])
	if clicked != null:
		set_active_circle(clicked)


## Nearest circle within its radius plus CLICK_PADDING, or null for a miss.
func _circle_at(world_point: Vector2) -> TargetCircle:
	var best: TargetCircle = null
	var best_distance: float = INF
	for circle: TargetCircle in _circles:
		var distance: float = circle.global_position.distance_to(world_point)
		if distance <= circle.radius + CLICK_PADDING and distance < best_distance:
			best = circle
			best_distance = distance
	return best


func _on_point_touched(point: Node2D, circle: TargetCircle) -> void:
	# Only the active circle intercepts the dot; it flies over the others.
	if circle != target:
		return
	if point != _current:
		return
	_trace("touched after %.1fs, path swept %.2f laps" % [_lifetime, _swept_angle / TAU])
	_award_score()
	_destroy_current()


## Banks the flight just ended: its score divided by one plus the actions spent on
## it, so a flight that had to be selected or dodged pays less. The divider starts
## at one, so an untouched flight is worth everything it flew.
func _award_score() -> void:
	var divider: int = 1 + _action_count
	var award: float = _live_score / float(divider)
	_total_score += award
	_trace("scored %.1f (%.1f flown / divider %d from %d action(s)) -> total %.1f" % [
		award, _live_score, divider, _action_count, _total_score
	])
	# The divider refreshes with the scoring, so the next dot starts at one again.
	_reset_flight_scoring()


## Clears everything that belongs to a single flight. Called when a flight is
## banked and again when the next dot spawns, so nothing leaks between dots.
func _reset_flight_scoring() -> void:
	_live_score = 0.0
	_action_count = 0


## Distance covered by the dot currently flying, as score points.
func get_live_score() -> float:
	return _live_score


## Score banked from the dots that have already collided.
func get_total_score() -> float:
	return _total_score


## Selections and dodges spent on the dot currently flying. The divider is this
## plus one.
func get_action_count() -> int:
	return _action_count


## The score rate for the dot in flight right now: the settings' baseline plus
## the points each second of its life has bought. A dot straight out of spawn is
## worth exactly `points_per_second`, and a collision puts the next one back
## there, so this is what "the rate resets" reads as.
func get_live_rate() -> float:
	if settings == null:
		return 0.0
	return settings.points_per_second + settings.rate_gain_per_second * _lifetime


## The live rate as a multiple of the rate a dot spawns at. Distance scoring is
## scaled by this, so it is 1.0 at spawn and climbs for as long as the dot stays
## alive: the same ground, counted faster.
func get_rate_multiplier() -> float:
	if settings == null or settings.points_per_second <= 0.0:
		# No baseline to measure against: leave distance scoring unscaled rather
		# than divide by it.
		return 1.0
	return get_live_rate() / settings.points_per_second


## Dots put into play this round, counted up to get_max_dots(). Shown along the
## top of the screen as the dot counter.
func get_dots_spawned() -> int:
	return _dots_spawned


## Dots in a round, from the shared settings. The last one to collide ends it.
func get_max_dots() -> int:
	if settings == null:
		return 0
	return settings.max_dots


## True once the round's last dot has collided. Freezing the playfield is the
## business of whoever shows the game over card, not of this node.
func is_game_over() -> bool:
	return _game_over


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
	if _dots_spawned >= get_max_dots():
		# That was the round's last dot: bank it and stop, rather than follow it
		# with a sixth. Deferred for the same reason as the spawn below, and
		# because the game over card pauses the tree on this signal.
		_finish_game.call_deferred()
		return
	# Deferred: never add or remove physics bodies inside a physics callback.
	call_deferred("_spawn_point")


## Ends the round, once, when the last dot has collided and been banked. The
## handler runs deferred, so it is outside the physics callback that killed the
## dot: nothing here adds or frees bodies, it only reports.
func _finish_game() -> void:
	if _game_over:
		return
	_game_over = true
	_trace("round over: %d dot(s) played, final score %.1f" % [_dots_spawned, _total_score])
	game_over.emit(_total_score)


func _spawn_point() -> void:
	# A finished round never spawns again, however the spawn gets requested.
	if _game_over:
		return
	if point_scene == null or target == null:
		return
	var point: ChaserPoint = point_scene.instantiate() as ChaserPoint
	if point == null:
		return
	_current_trail = null
	if settings.trail_enabled:
		_current_trail = _create_trail()
		# Added before the point so the point draws on top of its own path.
		add_child(_current_trail)
	add_child(point)
	point.global_position = pick_spawn_position(
		_rng, spawn_rect, target.global_position, min_spawn_distance
	)
	point.set_target(target)
	point.apply_settings(settings)
	target.set_threat(point)
	_current = point
	_lifetime = 0.0
	_swept_angle = 0.0
	_dots_spawned += 1
	# Scoring belongs to one dot: the score starts over with every spawn, and so
	# does the rate it is counted at, because _lifetime is what the rate is built
	# from and it has just been zeroed.
	_reset_flight_scoring()
	_last_scored_position = point.global_position
	_last_angle = (point.global_position - target.global_position).angle()
	_trace("spawn at %s (mass %.1f, thrust %.0f, ceil %.0f, bleed %.3f)" % [
		point.global_position, point.mass, point.thrust, point.max_speed,
		point.speed_bleed_per_second
	])


func _create_trail() -> Line2D:
	var line: Line2D = Line2D.new()
	line.width = settings.trail_width
	line.default_color = settings.trail_color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	return line


## Points of path to keep, derived from the settings' length in seconds so the
## panel only has to ask for one thing. The trail is sampled once per physics tick.
func _trail_capacity_points() -> int:
	return maxi(2, int(settings.trail_seconds * Engine.physics_ticks_per_second))


func _fade_trail(line: Line2D) -> void:
	if line == null or not is_instance_valid(line):
		return
	if settings.trail_fade_seconds <= 0.0:
		line.queue_free()
		return
	var tween: Tween = create_tween()
	tween.tween_property(line, "modulate:a", 0.0, settings.trail_fade_seconds)
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
