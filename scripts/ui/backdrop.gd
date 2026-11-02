class_name Backdrop
extends Control

## Procedural arcane backdrop. Draws a slow rune circle, motes, and a vignette.

var accent: Color = UIKit.ACCENT
var intensity: float = 1.0
var _t := 0.0
var _motes: Array[Vector3] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_motes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261101
	for i in 46:
		_motes.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.3, 1.4)))


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var center := Vector2(w * 0.5, h * 0.46)

	draw_rect(Rect2(Vector2.ZERO, size), Color("07050e"))

	# Soft nebula glows
	for i in 4:
		var angle := _t * 0.05 + float(i) * TAU / 4.0
		var p := center + Vector2(cos(angle), sin(angle)) * (w * 0.26)
		var r := w * (0.22 + 0.02 * float(i))
		for layer in 5:
			var alpha := 0.035 * intensity * (1.0 - float(layer) / 5.0)
			draw_circle(p, r * (1.0 - float(layer) * 0.16), Color(accent.r, accent.g, accent.b, alpha))

	# Motes
	for m in _motes:
		var x := fposmod(m.x * w + sin(_t * 0.12 + m.y * 10.0) * 26.0, w)
		var y := fposmod(m.y * h - _t * (5.0 * m.z), h)
		var a := 0.10 + 0.16 * absf(sin(_t * 0.6 + m.x * 20.0))
		draw_circle(Vector2(x, y), 1.2 + m.z * 0.9, Color(0.85, 0.82, 1.0, a))

	# Rune circles
	var base_r := minf(w, h) * 0.43
	draw_arc(center, base_r, 0.0, TAU, 128, Color(accent.r, accent.g, accent.b, 0.22), 1.4, true)
	draw_arc(center, base_r * 0.82, 0.0, TAU, 128, Color(accent.r, accent.g, accent.b, 0.12), 1.0, true)

	# Rotating glyph ring
	var glyph_count := 28
	for i in glyph_count:
		var a := _t * 0.08 + TAU * float(i) / float(glyph_count)
		var dir := Vector2(cos(a), sin(a))
		var p := center + dir * base_r * 0.91
		var tangent := Vector2(-dir.y, dir.x)
		var length := 5.0 + 5.0 * absf(sin(float(i) * 7.13))
		draw_line(p - tangent * length * 0.5, p + tangent * length * 0.5, Color(accent.r, accent.g, accent.b, 0.4), 1.6, true)
		if i % 4 == 0:
			draw_circle(p + dir * 9.0, 1.8, Color(accent.r, accent.g, accent.b, 0.55))

	# Counter-rotating inner ring
	draw_arc(center, base_r * 0.62, -_t * 0.14, -_t * 0.14 + TAU * 0.72, 96, Color(accent.r, accent.g, accent.b, 0.18), 2.0, true)

	# Vignette: stacked edge bands
	for i in 26:
		var inset := float(i) * 4.0
		var alpha := 0.006 * float(i)
		draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0)), Color(0, 0, 0, alpha), false, 5.0)
