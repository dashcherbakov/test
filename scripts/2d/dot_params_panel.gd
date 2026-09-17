# scripts/2d/dot_params_panel.gd
# Live sliders for every parameter of the chasing dot.
#
# The rows are generated from ChaserSettings' exported numbers, so a new export
# there becomes a slider here automatically (ints snap to whole numbers). Dragging one writes to the shared
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
const HINT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.55)
const TITLE: String = "Dot parameters"
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
## Properties that are whole numbers in the resource. A slider is a float whatever
## it drives, so these are the rows that have to be rounded on the way in.
var _int_properties: Dictionary[String, bool] = {}
var _header: Button = null
var _body: VBoxContainer = null


func _ready() -> void:
	# Sized outright, not anchored: for a Control whose parent is a Node2D the
	# anchorable parent rect is empty, so anchors would collapse this to zero.
	# Filling the screen only matters for click-through bookkeeping - the panel's
	# own controls carry its real hit areas.
	size = get_viewport_rect().size
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

	# Only the header is always there; everything else lives in the body, so the
	# panel can collapse to a title bar instead of covering the playfield.
	var header: Button = Button.new()
	header.name = "Header"
	header.toggle_mode = true
	header.button_pressed = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Never focusable: a focused button swallows the dash key, so pressing space
	# would expand or collapse this panel instead of dodging.
	header.focus_mode = Control.FOCUS_NONE
	header.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	column.add_child(header)
	_header = header

	var body: VBoxContainer = VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", ROW_SEPARATION)
	column.add_child(body)
	_body = body

	var hint: Label = Label.new()
	hint.text = "Applies to the dot in flight and every later one."
	hint.modulate = HINT_COLOR
	body.add_child(hint)

	var pick_hint: Label = Label.new()
	pick_hint.text = "Left-click a circle to target it. Space makes it dodge."
	pick_hint.modulate = HINT_COLOR
	body.add_child(pick_hint)
	body.add_child(HSeparator.new())

	# The script's own property list, not Resource's: the latter also reports a
	# "Resource" group, which would show up here as a section heading.
	var properties: Array[Dictionary] = []
	var settings_script: GDScript = _settings.get_script() as GDScript
	if settings_script != null:
		properties = settings_script.get_script_property_list()

	for info: Dictionary in properties:
		var usage: int = int(info["usage"])
		if usage & PROPERTY_USAGE_GROUP:
			# Export groups become section headings, so the controls stay sorted
			# the way they are declared in ChaserSettings.
			var section: String = String(info["name"])
			if not section.is_empty():
				body.add_child(_make_section_label(section))
			continue
		# One slider per exported number. Floats and range-hinted ints both build a
		# row; anything without a range hint is skipped, so a bool, a Color or a
		# plain float can never produce a broken control.
		var value_type: int = int(info["type"])
		if value_type != TYPE_FLOAT and value_type != TYPE_INT:
			continue
		if int(info["hint"]) != PROPERTY_HINT_RANGE:
			continue
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue
		body.add_child(_build_row(
			String(info["name"]), String(info["hint_string"]), value_type == TYPE_INT
		))

	body.add_child(HSeparator.new())
	var reset: Button = Button.new()
	reset.name = "Reset"
	reset.text = "Reset to defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_on_reset_pressed)
	body.add_child(reset)

	header.toggled.connect(_on_header_toggled)
	_refresh_header(true)


func _on_header_toggled(expanded: bool) -> void:
	_body.visible = expanded
	_refresh_header(expanded)


## The mark doubles as the state read-out and is deliberately plain ASCII: the
## default theme font is not guaranteed to carry arrow glyphs.
func _refresh_header(expanded: bool) -> void:
	_header.text = ("- " if expanded else "+ ") + TITLE


func _make_section_label(section: String) -> Label:
	var label: Label = Label.new()
	label.text = section
	label.modulate = HINT_COLOR
	label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE - 4)
	return label


func _build_row(property: String, hint_string: String, is_int: bool) -> HBoxContainer:
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
	slider.focus_mode = Control.FOCUS_NONE
	slider.min_value = float(bounds[0])
	slider.max_value = float(bounds[1])
	slider.step = float(bounds[2]) if bounds.size() > 2 else 0.01
	if is_int:
		# A whole-number parameter (the round length) snaps to whole numbers: the
		# slider is still a float under the hood, so the step is what stops a drag
		# from handing the resource 4.7 dots.
		slider.step = 1.0
		_int_properties[property] = true
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
	_write_value(property, value)
	_settings.emit_changed()
	_refresh_value_text(property, value)


func _on_reset_pressed() -> void:
	for property: String in _sliders.keys():
		var slider: HSlider = _sliders[property]
		var value: float = float(_defaults.get(property))
		slider.set_value_no_signal(value)
		_write_value(property, value)
		_refresh_value_text(property, value)
	_settings.emit_changed()


## Writes one slider's value into the shared resource. A slider is a float
## whatever it drives, so an int parameter is rounded into it rather than assigned
## as a float: the resource would reject a count of 4.7.
func _write_value(property: String, value: float) -> void:
	if _int_properties.get(property, false):
		_settings.set(property, roundi(value))
		return
	_settings.set(property, value)


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
