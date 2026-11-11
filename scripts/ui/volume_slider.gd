extends HBoxContainer

## Master-volume row shared by the title menu and the pause menu.
##
## The slider reads as a percentage because dB is not a useful scale for
## players: 100% is unity, 0% mutes the Master bus. The persisted value is
## still dB, so user://audio.cfg and the Audio autoload stay unchanged.

const FLOOR_DB := -40.0
const MUTE_DB := -80.0

var _slider: HSlider
var _value_label: Label
var _audio: Node


func _init() -> void:
	add_theme_constant_override("separation", 10)

	var name_label := UIKit.label("SOUND", 13, UIKit.MUTED)
	name_label.custom_minimum_size = Vector2(58, 0)
	add_child(name_label)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 100.0
	_slider.step = 1.0
	_slider.custom_minimum_size = Vector2(120, 18)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.focus_mode = Control.FOCUS_ALL
	_slider.tooltip_text = "Master volume"
	_slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_slider.value_changed.connect(_on_value_changed)
	add_child(_slider)

	var track := StyleBoxFlat.new()
	track.bg_color = Color("241c38")
	track.set_corner_radius_all(3)
	track.content_margin_top = 2.0
	track.content_margin_bottom = 2.0
	_slider.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIKit.ACCENT_DARK
	fill.set_corner_radius_all(3)
	_slider.add_theme_stylebox_override("grabber_area", fill)
	var fill_hot := fill.duplicate() as StyleBoxFlat
	fill_hot.bg_color = UIKit.ACCENT
	_slider.add_theme_stylebox_override("grabber_area_highlight", fill_hot)

	_value_label = UIKit.bold_label("", 13, UIKit.MUTED)
	_value_label.custom_minimum_size = Vector2(56, 0)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_value_label)


func _ready() -> void:
	_audio = get_node_or_null("/root/Audio")
	var db := 0.0
	if _audio != null:
		db = float(_audio.get_master_volume_db())
	var percent := _db_to_percent(db)
	_slider.set_value_no_signal(percent)
	_update_label(percent)


func _on_value_changed(percent: float) -> void:
	_update_label(percent)
	if _audio == null:
		return
	var db := MUTE_DB if percent <= 0.0 else clampf(linear_to_db(percent / 100.0), FLOOR_DB, 0.0)
	_audio.set_master_volume_db(db)


func _update_label(percent: float) -> void:
	_value_label.text = "MUTED" if percent <= 0.0 else "%d%%" % roundi(percent)


func _db_to_percent(db: float) -> float:
	# Anything at or below the old -40 dB floor was already inaudible, so
	# treat it as muted instead of showing a 0-ish percentage.
	if db <= FLOOR_DB + 0.01:
		return 0.0
	return clampf(db_to_linear(db) * 100.0, 1.0, 100.0)
