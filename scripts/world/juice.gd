class_name Juice
extends RefCounted
## Fun pass: "game feel" helpers — hit-stop, floating text, kill bursts.
## Hit-stop slows the whole game for a few hundredths of a second so hits land with weight.
## It is skipped in headless runs (tests, bots), so measured timings never change.

static var _stop_until_ms: int = 0
static var enabled: bool = true


## Freezes the action for `seconds` (real time). Overlapping calls extend, never stack.
static func hit_stop(tree: SceneTree, seconds: float) -> void:
	if not enabled or tree == null or DisplayServer.get_name() == "headless" or tree.paused:
		return
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	if until <= _stop_until_ms:
		return
	var already: bool = _stop_until_ms > Time.get_ticks_msec()
	_stop_until_ms = until
	if already:
		return
	Engine.time_scale = 0.05
	while Time.get_ticks_msec() < _stop_until_ms:
		await tree.create_timer(0.01, true, false, true).timeout
	Engine.time_scale = 1.0


## A short rising, fading text in the world ("+10", "x3 STREAK!", "+ Canned food").
static func popup(parent: Node, at: Vector2, text: String, color: Color = Color(1, 0.92, 0.6), size: int = 10) -> Label:
	if parent == null or not parent.is_inside_tree():
		return null
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override(&"shadow_offset_x", 1)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(120, 12)
	l.position = at - Vector2(60, 20)
	l.z_index = 50
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	var t: Tween = l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 18.0, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.45)
	t.chain().tween_callback(l.queue_free)
	return l


## A zombie dies: a big blood burst, dark gore bits and a short freeze.
static func kill_burst(parent: Node, at: Vector2, direction: Vector2) -> void:
	Fx.burst(parent, at + Vector2(0, -8), Fx.BLOOD, 18, 90.0, direction, 0.5)
	Fx.burst(parent, at + Vector2(0, -6), Color(0.25, 0.05, 0.05), 8, 60.0, direction, 0.6)
