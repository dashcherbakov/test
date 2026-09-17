# scripts/2d/dot_params_panel.gd
# Live sliders for every parameter of the chasing dot.
#
# The rows are generated from ChaserSettings' exported floats, so a new export
# there becomes a slider here automatically. Dragging one writes to the shared
# resource and emits its `changed` signal, which the spawner turns into a live
# update on the dot currently in flight.
#
# This is a plain Control in the default canvas, NOT a CanvasLayer. A CanvasLayer
# is drawn through the viewport's stretch transform but its Controls are
# hit-tested in unscaled coordinates, so whenever the window is smaller than the
# project's 1920x1080 base viewport every slider reacts only to clicks placed
# well below where it is drawn. Add a Camera2D later and this panel would need a
# CanvasLayer after all - then set follow_viewport_enabled and retest input.
class_name DotParamsPanel
extends Control

const PANEL_OFFSET: Vector2 = Vector2(18.0, 18.0)
const PANEL_MARGIN: int = 14
const ROW_SEPARATION: int = 8
## Row height. The slider is stretched to this, so the whole row is a hit area
## instead of the thin strip a slider asks for by default.
const ROW_HEIGHT: float = 30.0
const NAME_WIDTH: float = 210.0
const SLIDER_WIDTH: float = 230.0
const VALUE_WIDTH: float = 74.0
const TITLE_FONT_SIZE: int = 20

@export var spawner: ChaserSpawner
## Logs where each click lands, in window and canvas space, and which slider the
## canvas position falls on. Turn on when a click does not hit what it looks like
## it should: if the two disagree, the pointer is being offset by the window size
## or the display scaling, not by this panel.
@export var debug_input_trace: bool = false

var _settings: ChaserSettings = null
var _defaults: ChaserSettings = null
var _sliders: Dictionary[String, HSlider] = {}
var _value_labels: Dictionary[String, Label] = {}


func _ready() -> void:
	# Fill the viewport but let clicks pass through to whatever is behind: only
	# the panel's own controls should consume input.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if spawner == null or spawner.settings == null:
		push_warning("DotParamsPanel: spawner or its settings are missing, no panel built.")
		return
	_settings = spawner.settings
	_defaults = _settings.duplicate() as ChaserSettings
	_build_panel()


func _build_panel() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.position = PANEL_OFFSET
	add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, PANEL_MARGIN)
	panel.add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Rows"
	column.add_theme_constant_override("separation", ROW_SEPARATION)
	margin.add_child(column)

	var title: Label = Label.new()
	title.text = "Dot parameters"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	column.add_child(title)

	var hint: Label = Label.new()
	hint.text = "Applies to the dot in flight and every later one."
	hint.modulate = Color(1.0, 1.0, 1.0, 0.55)
	column.add_child(hint)
	column.add_child(HSeparator.new())

	for info: Dictionary in _settings.get_property_list():
		# One slider per exported float. Anything without a range hint is skipped
		# so a plain float export can never produce a broken control.
		if int(info["type"]) != TYPE_FLOAT:
			continue
		if int(info["hint"]) != PROPERTY_HINT_RANGE:
			continue
		if not (int(info["usage"]) & PROPERTY_USAGE_EDITOR):
			continue
		column.add_child(_build_row(String(info["name"]), String(info["hint_string"])))

	column.add_child(HSeparator.new())
	var reset: Button = Button.new()
	reset.name = "Reset"
	reset.text = "Reset to defaults"
	reset.pressed.connect(_on_reset_pressed)
	column.add_child(reset)


func _build_row(property: String, hint_string: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "row_" + property
	row.add_theme_constant_override("separation", ROW_SEPARATION)
	row.custom_minimum_size.y = ROW_HEIGHT

	var name_label: Label = Label.new()
	name_label.text = property.capitalize()
	name_label.custom_minimum_size.x = NAME_WIDTH
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var bounds: PackedStringArray = hint_string.split(",")
	var slider: HSlider = HSlider.new()
	slider.name = "slider_" + property
	slider.min_value = float(bounds[0])
	slider.max_value = float(bounds[1])
	slider.step = float(bounds[2]) if bounds.size() > 2 else 0.01
	slider.custom_minimum_size.x = SLIDER_WIDTH
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Stretch to the row's height so the drawn track sits on the same line as the
	# labels and the whole row responds, not just the slider's default strip.
	slider.size_flags_vertical = Control.SIZE_FILL
	slider.value = float(_settings.get(property))
	row.add_child(slider)
	_sliders[property] = slider

	var value_label: Label = Label.new()
	value_label.name = "value_" + property
	value_label.custom_minimum_size.x = VALUE_WIDTH
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.text = _format(slider.step, slider.value)
	row.add_child(value_label)
	_value_labels[property] = value_label

	# Connected after the initial value is set, so building the row is silent.
	slider.value_changed.connect(_on_slider_changed.bind(property))
	return row


func _on_slider_changed(value: float, property: String) -> void:
	_settings.set(property, value)
	_settings.emit_changed()
	_refresh_value_text(property, value)


func _on_reset_pressed() -> void:
	for property: String in _sliders.keys():
		var slider: HSlider = _sliders[property]
		var value: float = float(_defaults.get(property))
		slider.set_value_no_signal(value)
		_settings.set(property, value)
		_refresh_value_text(property, value)
	_settings.emit_changed()


func _refresh_value_text(property: String, value: float) -> void:
	var slider: HSlider = _sliders.get(property, null)
	var label: Label = _value_labels.get(property, null)
	if slider == null or label == null:
		return
	label.text = _format(slider.step, value)


func _format(step: float, value: float) -> String:
	if step >= 1.0:
		return "%.0f" % value
	if step >= 0.1:
		return "%.1f" % value
	return "%.3f" % value


func _input(event: InputEvent) -> void:
	if not debug_input_trace:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	var canvas_point: Vector2 = get_viewport().get_final_transform().affine_inverse() * button.position
	print("[panel] click event=", button.position, " -> canvas=", canvas_point.round(),
		" window=", DisplayServer.window_get_size(),
		" canvas_size=", get_viewport().get_visible_rect().size,
		" slider_here=", _slider_name_at(canvas_point))


func _slider_name_at(canvas_point: Vector2) -> String:
	for property: String in _sliders.keys():
		if (_sliders[property] as HSlider).get_global_rect().has_point(canvas_point):
			return property
	return "none"
