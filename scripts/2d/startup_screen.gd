# scripts/2d/startup_screen.gd
# Title card shown before the game runs. It lists the controls and waits for any
# button; the game is paused underneath, so nothing moves until it is dismissed.
#
# The press that starts the game is swallowed, so the same click cannot also
# select a circle or toggle a panel control behind the card.
class_name StartupScreen
extends Control

const TITLE: String = "Point Chaser"
const CONTROLS: Array[String] = [
	"Point and Left click to change circle",
	"Press space to dash circle 1 time",
]
const PROMPT: String = "Press any button to start game"

const BACKDROP: Color = Color(0.04, 0.05, 0.07, 0.97)
const TITLE_COLOR: Color = Color(0.35, 0.9, 1.0)
const BODY_COLOR: Color = Color(1.0, 1.0, 1.0, 0.85)
const PROMPT_COLOR: Color = Color(1.0, 0.72, 0.25)
const TITLE_FONT_SIZE: int = 42
const BODY_FONT_SIZE: int = 22
const PROMPT_FONT_SIZE: int = 26
const LINE_SEPARATION: int = 16

var _started: bool = false


func _ready() -> void:
	# The tree is paused underneath, so this node has to opt in to keep processing
	# its input while paused.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()
	if GameManager.consume_skip_startup():
		# A restart from the game over card goes straight into play: the button
		# the player just pressed was already an answer to "another round?", so
		# making them read the controls again would be one press too many.
		_start()
		return
	GameManager.set_paused(true)


func _input(event: InputEvent) -> void:
	if _started or not _is_start_release(event):
		return
	get_viewport().set_input_as_handled()
	_start()


func _start() -> void:
	_started = true
	visible = false
	set_process_input(false)
	# Belt and braces: the dash action is cleared on the way out, so the press that
	# started the game can never be spent as a dodge once the tree resumes.
	Input.action_release(ChaserSpawner.DASH_ACTION)
	GameManager.set_paused.call_deferred(false)


## Any button starts the game: keyboard, mouse, gamepad or touch.
##
## The RELEASE is what counts. Dismissing on the press would leave that press
## "just pressed" on the frame the tree resumes, and the spawner polls for exactly
## that, so starting with the dash key would spend a dash before the player
## played. By the release, the press is several frames old.
func _is_start_release(event: InputEvent) -> bool:
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
	for line: String in CONTROLS:
		column.add_child(_make_label(line, BODY_FONT_SIZE, BODY_COLOR))
	column.add_child(_make_label(PROMPT, PROMPT_FONT_SIZE, PROMPT_COLOR))


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = color
	return label
