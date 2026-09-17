# scripts/2d/map_bounds.gd
# The playfield the circles live inside.
#
# This node owns the rectangle: it draws it, and the circles read it (they find it
# through the GROUP group) so widening the map is one edit in one place.
#
# Circles only ever move by dashing, and every dash destination goes through
# clamp_point(), so a circle can never come to rest outside this rectangle. The
# dot is deliberately not constrained - its overshoot is the whole point.
@tool
class_name MapBounds
extends Node2D

## Group the circles look for, so they need no hard reference to this node.
const GROUP: String = "map_bounds"
const BORDER_WIDTH: float = 3.0

@export var bounds: Rect2 = Rect2(140.0, 140.0, 1640.0, 800.0):
	set(value):
		bounds = value
		queue_redraw()
@export var border_color: Color = Color(0.4, 0.75, 0.95, 0.55)
@export var fill_color: Color = Color(0.4, 0.75, 0.95, 0.03)


## Keeps a global point inside the playfield, leaving `margin` of room - a circle
## passes its radius, so the circle itself stays in and not just its centre.
func clamp_point(global_point: Vector2, margin: float = 0.0) -> Vector2:
	var local_point: Vector2 = to_local(global_point)
	var clamped: Vector2 = Vector2(
		clampf(local_point.x, bounds.position.x + margin, bounds.end.x - margin),
		clampf(local_point.y, bounds.position.y + margin, bounds.end.y - margin)
	)
	return to_global(clamped)


func _draw() -> void:
	draw_rect(bounds, fill_color, true)
	draw_rect(bounds, border_color, false, BORDER_WIDTH)
