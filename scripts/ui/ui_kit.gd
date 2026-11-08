class_name UiKit
extends RefCounted
## Small helpers for the code-built panels. Look and font come from the project theme
## (assets/ui/theme.tres, Phase 8).

const TEXT := Color(0.88, 0.85, 0.76)
const TITLE := Color(0.95, 0.88, 0.6)
const OBJECTIVE := Color(0.62, 0.86, 0.9)  # GDD §12: objective accent = pale cyan


## The pixel font is drawn at 10 px; sizes above 10 become 20 (2x) so it stays crisp.
static func label(text: String, size: int = 10, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 10 if size <= 10 else 20)
	l.add_theme_color_override(&"font_color", color)
	return l


## A big (2x) title in tape yellow (theme type "TitleLabel").
static func title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"TitleLabel"
	return l


static func button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void: AudioManager.play_ui())
	b.pressed.connect(action)
	return b


static func item_list(min_size: Vector2) -> ItemList:
	var l := ItemList.new()
	l.custom_minimum_size = min_size
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.fixed_icon_size = Vector2i(16, 16)
	return l


## A centred panel with a VBox inside; returns the VBox.
static func centered_panel(layer: CanvasLayer, half_size: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -half_size.x
	panel.offset_right = half_size.x
	panel.offset_top = -half_size.y
	panel.offset_bottom = half_size.y
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	panel.add_child(box)
	return box
