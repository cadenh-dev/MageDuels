extends CanvasLayer

## Experimental ASCII post-process. Default OFF; F10 toggles.
## Sits at layer 3, below the HUD (5), so only the 3D world and menus are
## mosaicked. `--ascii` enables it at startup for the existing --shot-* modes.

var enabled := false
var _rect: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS

	_rect = ColorRect.new()
	_rect.name = "AsciiSurface"
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE

	_material = ShaderMaterial.new()
	_material.shader = load("res://scripts/world/ascii_post.gdshader")
	_material.set_shader_parameter("glyphs", load("res://assets/ascii_glyphs.png"))
	_rect.material = _material
	add_child(_rect)
	_rect.visible = false

	if "--ascii" in OS.get_cmdline_user_args():
		set_enabled(true)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and (key.keycode == KEY_F9 or key.keycode == KEY_F10):
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()


func set_enabled(value: bool) -> void:
	enabled = value
	if _rect != null:
		_rect.visible = value
