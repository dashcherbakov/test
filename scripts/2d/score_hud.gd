# scripts/2d/score_hud.gd
# The live score, centred along the top of the screen.
#
# It draws two numbers straight off the spawner: the flight in progress - which
# grows in point size as it grows in value - and the running total with the action
# count (selections plus dodges, the things that divide the next award). The
# spawner owns the rules; this only shows them.
class_name ScoreHud
extends Control

@export var spawner: ChaserSpawner
## Point size of the live number as a flight begins.
@export var live_font_size: int = 44
## Point size it grows to, and never past.
@export var max_live_font_size: int = 96
## Live score at which the number has reached its maximum size.
@export var live_score_for_max_size: float = 40.0
@export var detail_font_size: int = 20

const TOP_MARGIN: float = 12.0
const LINE_HEIGHT: float = 1.4
const LIVE_COLOR: Color = Color(1.0, 0.72, 0.25)
const DETAIL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.6)

var _live_label: Label = null
var _detail_label: Label = null
var _current_font_size: int = 0


func _ready() -> void:
	# Anchors are no use under a Node2D parent, so the size is set outright.
	var viewport_size: Vector2 = get_viewport_rect().size
	size = Vector2(viewport_size.x, 0.0)
	position = Vector2(0.0, TOP_MARGIN)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var live_height: float = float(max_live_font_size) * LINE_HEIGHT
	_live_label = _make_label("LiveScore", live_font_size, LIVE_COLOR, Vector2(viewport_size.x, live_height))
	add_child(_live_label)
	_detail_label = _make_label(
		"Detail", detail_font_size, DETAIL_COLOR,
		Vector2(viewport_size.x, float(detail_font_size) * LINE_HEIGHT)
	)
	_detail_label.position = Vector2(0.0, live_height)
	add_child(_detail_label)

	if spawner != null:
		# The round's last award lands in the same frame the tree is paused, and a
		# paused node stops processing - so the total on screen would keep the value
		# it had one award ago. One last refresh on the round's closing signal is
		# what keeps this number in step with the card in front of it.
		spawner.game_over.connect(_on_game_over)
	_refresh()


## Emitted by the spawner when the round's last dot has been banked. Only the
## final refresh is interesting here; the score itself is on the game over card.
func _on_game_over(_final_score: float) -> void:
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _make_label(node_name: String, font_size: int, color: Color, rect_size: Vector2) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = rect_size
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _refresh() -> void:
	if spawner == null:
		return
	var live: float = spawner.get_live_score()
	_live_label.text = str(int(live))

	var growth: float = 0.0
	if live_score_for_max_size > 0.0:
		growth = clampf(live / live_score_for_max_size, 0.0, 1.0)
	var wanted_size: int = int(round(lerpf(float(live_font_size), float(max_live_font_size), growth)))
	# Only touch the theme when the size actually changes: this runs every frame.
	if wanted_size != _current_font_size:
		_current_font_size = wanted_size
		_live_label.add_theme_font_size_override("font_size", wanted_size)

	# Dots sits next to the running total, where the round length is worth looking
	# at: it is the count of dots spawned this round, so it reads 0/max before the
	# first dot and max/max on the last one.
	_detail_label.text = "Total %d      Dots %d/%d      Actions %d" % [
		int(spawner.get_total_score()),
		spawner.get_dots_spawned(),
		spawner.get_max_dots(),
		spawner.get_action_count()
	]
