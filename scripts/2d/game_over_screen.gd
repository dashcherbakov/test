# scripts/2d/game_over_screen.gd
# End-of-round card. It sits hidden while the round is played, listening to the
# spawner, and when the round's last dot collides it covers the frozen playfield
# with the score the round finished on and waits for the next round to be asked
# for.
#
# The restart press is swallowed, and a restart skips the title card: the player
# has already answered "another round?", so the controls are not shown again.
class_name GameOverScreen
extends Control

const TITLE: String = "Game Over"
## Singular on purpose - any button finishes a round, not only the mouse.
const PROMPT: String = "Click any button to restart"

const BACKDROP: Color = Color(0.04, 0.05, 0.07, 0.94)
const TITLE_COLOR: Color = Color(1.0, 0.45, 0.4)
const SCORE_COLOR: Color = Color(1.0, 0.72, 0.25)
const PROMPT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.85)
const TITLE_FONT_SIZE: int = 52
const SCORE_FONT_SIZE: int = 76
const PROMPT_FONT_SIZE: int = 24
const LINE_SEPARATION: int = 18

## The spawner whose round this card reports. Wired in point_chaser.tscn.
@export var spawner: ChaserSpawner

var _score_label: Label = null
## Set the moment a restart is asked for, so a second button press during the
## frame the scene reloads cannot start a second reload.
var _restarting: bool = false


func _ready() -> void:
	# Hidden and inert until the round ends. The card must not eat the press that
	# starts the game, and it has nothing to say before then, so its input stays
	# switched off until there is something on screen to dismiss.
	visible = false
	set_process_input(false)
	# The tree is paused when this card appears, so it has to opt in to keep
	# receiving input while paused. The same flag keeps it quiet in play: a
	# WHEN_PAUSED node is not processed while the game is running.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()
	if spawner == null:
		push_warning("GameOverScreen: no spawner, the card can never appear.")
		return
	spawner.game_over.connect(_on_game_over)


func _input(event: InputEvent) -> void:
	if _restarting or not _is_button_release(event):
		return
	get_viewport().set_input_as_handled()
	_restart()


## Shows the score and freezes the playfield under the card: no dot, no scoring,
## nothing moves again until the next round starts.
##
## Truncated, not rounded, so the card agrees digit for digit with the total the
## score HUD has been showing along the top all round.
func _on_game_over(final_score: float) -> void:
	_score_label.text = str(int(final_score))
	visible = true
	set_process_input(true)
	GameManager.set_paused(true)


## Starts a fresh round. The title card is skipped, because the click the player
## just made was already the answer to "another round?".
func _restart() -> void:
	_restarting = true
	set_process_input(false)
	GameManager.restart_scene(true)


## Any button restarts: keyboard, mouse, gamepad or touch.
##
## The RELEASE is what counts, not the press. Dismissing on the press would leave
## that press "just pressed" on the first frame of the new round, where the
## spawner polls exactly that to spend a dash - so starting with the dash key
## would spend the new round's first dodge before the player played. See
## StartupScreen._is_start_release, which answers the same question.
func _is_button_release(event: InputEvent) -> bool:
	var key: InputEventKey = event as InputEventKey
	if key != null:
		return not key.pressed
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		return not button.pressed
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	if pad != null:
		return not pad.pressed
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		return not touch.pressed
	return false


func _build() -> void:
	# Anchors are useless here: for a Control whose parent is a Node2D the
	# anchorable parent rect is empty, so an anchored node collapses to zero size.
	# The viewport size is fixed by the project's canvas stretch, so set it.
	var screen_size: Vector2 = get_viewport_rect().size
	size = screen_size

	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.size = screen_size
	backdrop.color = BACKDROP
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.size = screen_size
	add_child(center)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Lines"
	column.add_theme_constant_override("separation", LINE_SEPARATION)
	center.add_child(column)

	column.add_child(_make_label(TITLE, TITLE_FONT_SIZE, TITLE_COLOR))
	# The score is the one thing worth reading on this card, so it is the biggest
	# thing on it and it is filled in when the round ends.
	_score_label = _make_label("", SCORE_FONT_SIZE, SCORE_COLOR)
	column.add_child(_score_label)
	column.add_child(_make_label(PROMPT, PROMPT_FONT_SIZE, PROMPT_COLOR))


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = color
	return label
