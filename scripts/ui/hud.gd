class_name DuelHUD
extends CanvasLayer

signal pause_resume
signal pause_quit

var player: Wizard
var enemy: Wizard
var arena: Arena

var _root: Control
var _frame: MarginContainer
var _column: VBoxContainer
var _top_row: HBoxContainer
var _bottom: VBoxContainer
var _player_panel: PanelContainer
var _enemy_panel: PanelContainer
var _player_hp: ProgressBar
var _player_mana: ProgressBar
var _enemy_hp: ProgressBar
var _enemy_mana: ProgressBar
var _player_hp_label: Label
var _enemy_hp_label: Label
var _player_shield_label: Label
var _enemy_shield_label: Label
var _hp_style: StyleBoxFlat
var _hp_style_enemy: StyleBoxFlat
var _mana_style: StyleBoxFlat
var _mana_style_enemy: StyleBoxFlat
var _slots: Array[SpellSlotWidget] = []
var _slots_box: HBoxContainer
var _page_label: Label
var _round_label: Label
var _score_label: Label
var _element_badge: Label
var _element_panel: PanelContainer
var _chant_panel: PanelContainer
var _chant_title: Label
var _chant_text: RichTextLabel
var _chant_progress: ProgressBar
var _chant_zone: ColorRect
var _chant_hint: Label
var _chant_mult: Label
var _cast_box: VBoxContainer
var _cast_readout: Label
var _cast_sub: Label
var _cast_tween: Tween
var _toast: Label
var _toast_sub: Label
var _toast_box: VBoxContainer
var _toast_tween: Tween
var _damage_flash: ColorRect
var _flash_tween: Tween
var _pause_root: Control
var _resume_button: Button
var _coach: Coach
var _last_page := -1
var _rival_channel: Label
var _spell_wheel: Control
var _spell_wheel_labels: Array[Label] = []


func setup(p_player: Wizard, p_enemy: Wizard, p_arena: Arena) -> void:
	player = p_player
	enemy = p_enemy
	arena = p_arena


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	connect_wizards()


func connect_wizards() -> void:
	if player != null:
		player.damaged.connect(_on_player_damaged)
		player.cast_blocked.connect(_on_cast_blocked)
		player.cast_fired.connect(_on_cast)
		player.chant_changed.connect(func(_w, _a) -> void: _refresh_chant())
		player.chant_interrupted.connect(_on_chant_interrupted)
	if enemy != null:
		enemy.cast_blocked.connect(_on_cast_blocked)
		enemy.cast_fired.connect(_on_cast)
		enemy.chant_changed.connect(func(_w, _a) -> void: _update_rival_channel())
		enemy.chant_interrupted.connect(_on_chant_interrupted)


func _build() -> void:
	_root = Control.new()
	_root.name = "HUDRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# MarginContainer -> VBoxContainer is the documented way to keep a HUD
	# responsive: the top row and the bottom stack are laid out by containers,
	# and every size is expressed as a minimum or a theme value instead of a
	# magic screen coordinate.
	_frame = MarginContainer.new()
	_frame.name = "HUDFrame"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_theme_constant_override("margin_left", 20)
	_frame.add_theme_constant_override("margin_right", 20)
	_frame.add_theme_constant_override("margin_top", 16)
	_frame.add_theme_constant_override("margin_bottom", 16)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_frame)

	_column = VBoxContainer.new()
	_column.name = "HUDColumn"
	_column.add_theme_constant_override("separation", 0)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_column)

	_build_top_row()

	var middle := Control.new()
	middle.name = "Middle"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(middle)

	_build_bottom_stack()
	_build_toast()
	_build_rival_channel()
	_build_spell_wheel()
	_build_flash()
	_build_pause()
	_build_coach()

	_last_page = -1
	_refresh_slots()
	_refresh_chant()


func _build_top_row() -> void:
	_top_row = HBoxContainer.new()
	_top_row.name = "TopRow"
	_top_row.add_theme_constant_override("separation", 14)
	_top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_top_row)

	_player_panel = _build_side_panel(true)
	_top_row.add_child(_player_panel)

	var center := VBoxContainer.new()
	center.name = "RoundInfo"
	center.add_theme_constant_override("separation", 4)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_row.add_child(center)
	_build_center_top(center)

	_enemy_panel = _build_side_panel(false)
	_top_row.add_child(_enemy_panel)


func _build_side_panel(is_player: bool) -> PanelContainer:
	var panel := UIKit.panel(Color(0.07, 0.05, 0.12, 0.86), UIKit.OUTLINE, 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(348, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.name = "PlayerPanel" if is_player else "EnemyPanel"

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header)
	if is_player:
		header.add_child(UIKit.bold_label("YOU", 16, UIKit.ACCENT))
	else:
		header.add_child(UIKit.label(str(SpellData.wand(Game.enemy_wand)["name"]), 15, UIKit.MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	if is_player:
		header.add_child(UIKit.label(str(SpellData.wand(Game.player_wand)["name"]), 15, UIKit.MUTED))
	else:
		header.add_child(UIKit.bold_label(AIWizard.title_for(Game.enemy_wand), 14, UIKit.DANGER))

	var hp_wrap := Control.new()
	hp_wrap.custom_minimum_size = Vector2(0, 20)
	hp_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hp_wrap)
	var hp_bar := _make_bar(UIKit.HEAL if is_player else UIKit.DANGER, not is_player)
	hp_wrap.add_child(hp_bar)
	var hp_label := UIKit.bold_label("100 / 100", 13, Color(1, 1, 1, 0.9))
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if is_player else HORIZONTAL_ALIGNMENT_LEFT
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if is_player:
		hp_label.offset_right = -8
	else:
		hp_label.offset_left = 8
	hp_wrap.add_child(hp_label)

	var mana_wrap := Control.new()
	mana_wrap.custom_minimum_size = Vector2(0, 9)
	mana_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(mana_wrap)
	var mana_bar := _make_bar(UIKit.MANA, not is_player)
	mana_wrap.add_child(mana_bar)

	var shield := UIKit.bold_label("", 12, Color("8fe7ff"))
	shield.visible = false
	shield.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if is_player else HORIZONTAL_ALIGNMENT_RIGHT
	shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(shield)

	if is_player:
		_player_hp = hp_bar
		_player_mana = mana_bar
		_player_hp_label = hp_label
		_player_shield_label = shield
		_hp_style = hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		_mana_style = mana_bar.get_theme_stylebox("fill") as StyleBoxFlat
	else:
		_enemy_hp = hp_bar
		_enemy_mana = mana_bar
		_enemy_hp_label = hp_label
		_enemy_shield_label = shield
		_hp_style_enemy = hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		_mana_style_enemy = mana_bar.get_theme_stylebox("fill") as StyleBoxFlat
	return panel


func _make_bar(color: Color, reverse: bool) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if reverse:
		bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.02, 0.06, 0.9)
	bg.border_color = Color(1, 1, 1, 0.08)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)

	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)

	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _build_center_top(center: VBoxContainer) -> void:
	_round_label = UIKit.heading("ROUND 1", 22, UIKit.INK)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_round_label)

	_score_label = UIKit.bold_label("0  —  0", 18, UIKit.MUTED)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_score_label)

	_element_panel = UIKit.panel(Color(0.08, 0.06, 0.14, 0.9), Color(0, 0, 0, 0), 8)
	_element_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_element_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(_element_panel)
	_element_badge = UIKit.bold_label("", 13, UIKit.GOLD)
	_element_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_element_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_element_panel.add_child(_element_badge)


func _build_bottom_stack() -> void:
	_bottom = VBoxContainer.new()
	_bottom.name = "BottomStack"
	_bottom.add_theme_constant_override("separation", 4)
	_bottom.size_flags_vertical = Control.SIZE_SHRINK_END
	_bottom.alignment = BoxContainer.ALIGNMENT_END
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_bottom)

	# Cast readout: the newest spell name is always visible, for both duelists.
	var cast_box := VBoxContainer.new()
	cast_box.add_theme_constant_override("separation", 0)
	cast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(cast_box)
	_cast_box = cast_box
	_cast_readout = UIKit.bold_label("", 15, UIKit.INK)
	_cast_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cast_readout.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_cast_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast_box.add_child(_cast_readout)
	_cast_sub = UIKit.label("", 11, UIKit.DIM)
	_cast_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cast_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_cast_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast_box.add_child(_cast_sub)

	_build_chant()

	_page_label = UIKit.bold_label("", 12, UIKit.MUTED)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_page_label)

	_slots_box = HBoxContainer.new()
	_slots_box.name = "SpellSlots"
	_slots_box.add_theme_constant_override("separation", 10)
	_slots_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_slots_box)

	for i in 4:
		var slot := SpellSlotWidget.new()
		slot.custom_minimum_size = Vector2(156, 96)
		_slots_box.add_child(slot)
		_slots.append(slot)


func _build_chant() -> void:
	_chant_panel = UIKit.panel(Color(0.08, 0.06, 0.15, 0.94), UIKit.ACCENT, 12)
	_chant_panel.custom_minimum_size = Vector2(580, 0)
	_chant_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_chant_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chant_panel.visible = false
	_bottom.add_child(_chant_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chant_panel.add_child(box)

	_chant_title = UIKit.bold_label("CHANTING", 14, UIKit.MUTED)
	_chant_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chant_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_chant_title)

	_chant_text = RichTextLabel.new()
	_chant_text.bbcode_enabled = true
	_chant_text.fit_content = true
	_chant_text.scroll_active = false
	_chant_text.custom_minimum_size = Vector2(540, 44)
	_chant_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chant_text.add_theme_font_override("normal_font", UIKit.bold_font())
	_chant_text.add_theme_font_size_override("normal_font_size", 30)
	_chant_text.add_theme_color_override("default_color", UIKit.MUTED)
	box.add_child(_chant_text)

	_chant_progress = ProgressBar.new()
	_chant_progress.custom_minimum_size = Vector2(540, 6)
	_chant_progress.min_value = 0.0
	_chant_progress.max_value = 1.0
	_chant_progress.value = 0.0
	_chant_progress.show_percentage = false
	_chant_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.03, 0.02, 0.06, 0.9)
	track.set_corner_radius_all(3)
	track.content_margin_top = 0
	track.content_margin_bottom = 0
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIKit.GOLD
	fill.set_corner_radius_all(3)
	_chant_progress.add_theme_stylebox_override("background", track)
	_chant_progress.add_theme_stylebox_override("fill", fill)
	box.add_child(_chant_progress)

	# The perfect-release window is drawn as an anchor-driven overlay, so it
	# tracks the bar's real width at any resolution.
	_chant_zone = ColorRect.new()
	_chant_zone.color = Color(1.0, 0.82, 0.4, 0.38)
	_chant_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chant_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chant_zone.offset_left = 0
	_chant_zone.offset_right = 0
	_chant_zone.offset_top = 0
	_chant_zone.offset_bottom = 0
	_chant_zone.visible = false
	_chant_progress.add_child(_chant_zone)

	_chant_mult = UIKit.bold_label("", 12, UIKit.GOLD)
	_chant_mult.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chant_mult.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_chant_mult)

	_chant_hint = UIKit.label("", 11, UIKit.DIM)
	_chant_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chant_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chant_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_chant_hint)


func _build_toast() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.name = "Toast"
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_box.offset_left = -360
	_toast_box.offset_right = 360
	_toast_box.offset_top = 172
	_toast_box.offset_bottom = 292
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.add_theme_constant_override("separation", 2)
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.modulate.a = 0.0
	_root.add_child(_toast_box)

	_toast = UIKit.heading("", 46, UIKit.INK)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_child(_toast)

	_toast_sub = UIKit.label("", 19, UIKit.MUTED)
	_toast_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_child(_toast_sub)


func _build_rival_channel() -> void:
	_rival_channel = UIKit.bold_label("", 13, UIKit.GOLD)
	_rival_channel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_rival_channel.offset_left = -220
	_rival_channel.offset_right = 220
	_rival_channel.offset_top = 126
	_rival_channel.offset_bottom = 146
	_rival_channel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rival_channel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rival_channel.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_rival_channel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rival_channel)


func _build_spell_wheel() -> void:
	_spell_wheel = Control.new()
	_spell_wheel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_spell_wheel.position = Vector2(-170, -125)
	_spell_wheel.custom_minimum_size = Vector2(340, 250)
	_spell_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spell_wheel.visible = false
	_root.add_child(_spell_wheel)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.04, 0.03, 0.08, 0.92), UIKit.GOLD, 16))
	_spell_wheel.add_child(panel)
	var title := UIKit.bold_label("CHOOSE A SPELL  ·  RELEASE LB TO PREPARE", 13, UIKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.position.y = 14
	_spell_wheel.add_child(title)
	var positions := [Vector2(112, 54), Vector2(184, 104), Vector2(112, 154), Vector2(40, 104)]
	for slot in 4:
		var label := UIKit.bold_label("", 14, UIKit.INK)
		label.position = positions[slot]
		label.custom_minimum_size = Vector2(124, 50)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spell_wheel.add_child(label)
		_spell_wheel_labels.append(label)


func set_spell_wheel(active: bool, selected_slot: int = 0) -> void:
	if _spell_wheel == null:
		return
	_spell_wheel.visible = active
	if not active or player == null:
		return
	for slot in 4:
		var spell := player.current_spell(slot)
		if spell == null:
			continue
		var label := _spell_wheel_labels[slot]
		label.text = "%s\n%s" % [spell.display_name().to_upper(), spell.incantation()]
		label.add_theme_color_override("font_color", UIKit.GOLD if slot == selected_slot else UIKit.INK)


func _build_flash() -> void:
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.95, 0.15, 0.25, 0.0)
	_damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_damage_flash)


func _build_pause() -> void:
	_pause_root = Control.new()
	_pause_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_root.visible = false
	_pause_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_pause_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_root.add_child(center)

	var panel := UIKit.panel(Color(0.07, 0.05, 0.12, 0.98), UIKit.ACCENT, 16)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(320, 0)
	panel.add_child(box)

	var title := UIKit.heading("PAUSED", 40, UIKit.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		var vol_label := UIKit.label("MASTER VOLUME", 11, UIKit.MUTED)
		vol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(vol_label)
		var slider := HSlider.new()
		slider.min_value = -30.0
		slider.max_value = 0.0
		slider.step = 1.0
		slider.value = float(audio.get_master_volume_db())
		slider.custom_minimum_size = Vector2(280, 18)
		slider.value_changed.connect(func(v: float) -> void: audio.set_master_volume_db(v))
		box.add_child(slider)

	var resume := UIKit.button("RESUME", 22)
	resume.pressed.connect(func() -> void: pause_resume.emit())
	box.add_child(resume)
	_resume_button = resume

	var quit := UIKit.ghost_button("QUIT TO MENU", 18)
	quit.pressed.connect(func() -> void: pause_quit.emit())
	box.add_child(quit)


func set_paused(paused: bool) -> void:
	_pause_root.visible = paused
	if paused and _resume_button != null:
		_resume_button.grab_focus()
	else:
		var owner := get_viewport().gui_get_focus_owner()
		if owner != null and _pause_root.is_ancestor_of(owner):
			owner.release_focus()


func _build_coach() -> void:
	if Game.round_index != 0:
		return
	_coach = Coach.new()
	_coach.player = player
	_coach.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_coach.position = Vector2(20, 132)
	_root.add_child(_coach)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_update_bars()
	_update_slots()
	_update_round_info()
	_refresh_chant()
	_update_input_hints()
	if _coach != null and is_instance_valid(_coach):
		_coach.update(_delta)


func _update_bars() -> void:
	_player_hp.max_value = player.max_hp
	_player_hp.value = player.hp
	_player_mana.max_value = player.max_mana
	_player_mana.value = player.mana
	_player_hp_label.text = "%d / %d" % [ceili(player.hp), ceili(player.max_hp)]
	_player_shield_label.visible = player.shield_hp > 0.0
	if player.shield_hp > 0.0:
		_player_shield_label.text = "SHIELD  %d" % ceili(player.shield_hp)

	var ratio := player.hp / player.max_hp
	if _hp_style != null:
		if ratio > 0.55:
			_hp_style.bg_color = UIKit.HEAL
		elif ratio > 0.25:
			_hp_style.bg_color = UIKit.GOLD
		else:
			_hp_style.bg_color = UIKit.DANGER

	if enemy != null and is_instance_valid(enemy):
		_enemy_hp.max_value = enemy.max_hp
		_enemy_hp.value = enemy.hp
		_enemy_mana.max_value = enemy.max_mana
		_enemy_mana.value = enemy.mana
		_enemy_hp_label.text = "%d / %d" % [ceili(enemy.hp), ceili(enemy.max_hp)]
		_enemy_shield_label.visible = enemy.shield_hp > 0.0
		if enemy.shield_hp > 0.0:
			_enemy_shield_label.text = "SHIELD  %d" % ceili(enemy.shield_hp)
		if _hp_style_enemy != null:
			_hp_style_enemy.bg_color = UIKit.DANGER


func _update_slots() -> void:
	if player.page != _last_page:
		_refresh_slots()
	for i in _slots.size():
		var sel := i == player.selected_slot
		if _slots[i].selected != sel:
			_slots[i].selected = sel


func _refresh_slots() -> void:
	if player == null:
		return
	_last_page = player.page
	var spells := player.page_spells()
	for i in _slots.size():
		var spell: SpellDef = spells[i] if i < spells.size() else null
		_slots[i].setup(spell, str(i + 1), i == player.selected_slot)


func _update_input_hints() -> void:
	if _page_label == null or player == null:
		return
	var controls := "WASD MOVE  ·  1–4 CAST  ·  SPACE CHANT  ·  F / RMB HOLD  ·  SHIFT PAGE"
	if Game.input_mode == "pad":
		controls = "LS MOVE  ·  RS AIM  ·  ABXY CAST  ·  LT HOLD  ·  RB PAGE"
	if Game.cast_mode == Game.CAST_CHANT:
		controls = "WASD MOVE  ·  1–4 PREPARE  ·  TYPE TO CAST  ·  ESC CANCEL  ·  SHIFT PAGE"
		if Game.input_mode == "pad":
			controls = "LS MOVE  ·  LB WHEEL / RS PICK  ·  RELEASE LB PREPARES  ·  ABXY WORDS  ·  BACK CANCEL / START PAUSE"
	var text := "PAGE %s  ·  %s" % ["A" if player.page == 0 else "B", controls]
	if _page_label.text != text:
		_page_label.text = text


func _update_round_info() -> void:
	_round_label.text = "ROUND %d" % (Game.round_index + 1)
	_score_label.text = "%d  —  %d" % [Game.player_score, Game.enemy_score]
	var e: Dictionary = SpellData.ELEMENTS.get(Game.arena_element, {})
	var color: Color = e.get("color", UIKit.ACCENT)
	_element_badge.text = "%s SURGE  ·  +15%%" % str(e.get("name", "")).to_upper()
	_element_badge.add_theme_color_override("font_color", color)
	var sb := _element_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.border_color = Color(color.r, color.g, color.b, 0.5)


func _refresh_chant() -> void:
	var chanting := player != null and player.chanting
	_chant_panel.visible = chanting
	if not chanting:
		return
	var spell := player.current_spell(player.chant_slot)
	if spell == null:
		return
	var color := UIKit.spell_color(spell)
	_chant_title.add_theme_color_override("font_color", color)
	if player.assisted_chant:
		_chant_title.text = "ASSISTED OVERCAST  ·  %s" % spell.display_name().to_upper()
		_chant_text.text = "[color=#ffd166]%s[/color]" % spell.incantation()
		_chant_hint.text = "HOLD %.1fs  ·  release in the gold window for PERFECT (+%d%%)  ·  auto at %.1fs" % [
			player.chant_time_target(), roundi(SpellDef.PERFECT_DAMAGE_BONUS * 100.0), player.assist_charge_time()
		]
		# Show the real perfect-release window on the bar. The bar's span is
		# CHANT_ASSIST_TIME, so the window is two anchor ratios.
		var span := maxf(0.01, player.chant_time_target())
		var window := player.perfect_window()
		_chant_zone.visible = true
		_chant_zone.anchor_left = clampf(window.x / span, 0.0, 1.0)
		_chant_zone.anchor_right = clampf(window.y / span, 0.0, 1.0)
	else:
		var chant_title := "INCANTATION" if Game.cast_mode == Game.CAST_CHANT else "TYPED OVERCAST"
		_chant_title.text = "%s  ·  %s  ·  %d%%" % [chant_title, spell.display_name().to_upper(), roundi(player.chant_accuracy() * 100.0)]
		if Game.cast_mode != Game.CAST_CHANT:
			_chant_hint.text = "TYPE THE GOLD RUNES  ·  ENTER unleash  ·  ≥50%% = FIZZLE ×0.5  ·  hold %.1fs" % player.typed_charge_time()
		elif player.controller_chant:
			_chant_hint.text = "A/B/X/Y ENTER WORDS IN ORDER  ·  BACK CANCEL  ·  START PAUSE  ·  hold %.1fs" % player.typed_charge_time()
		else:
			_chant_hint.text = "TYPE THE GOLD RUNES  ·  ENTER UNLEASH  ·  ESC CANCEL  ·  ≥50%% = FIZZLE ×0.5  ·  hold %.1fs" % player.typed_charge_time()
		_chant_zone.visible = false
		var target := spell.incantation()
		var typed := player.chant_text.length()
		var count := 0
		var out := ""
		for ch in target:
			if ch == " ":
				out += "  "
				continue
			if count < typed:
				out += "[color=#ffd166]%s[/color]" % ch
			else:
				out += "[color=#5f567d]%s[/color]" % ch
			count += 1
		_chant_text.text = out
	var mult := SpellDef.ASSIST_OVERCAST_MULT if player.assisted_chant else SpellDef.OVERCAST_MULT
	var charge := "READY" if player.chant_progress() >= 1.0 else "CHARGE %.1fs" % maxf(0.0, player.chant_time_target() - player.chant_elapsed)
	_chant_mult.text = "×%.1f DAMAGE  ·  %s  ·  %s" % [mult, "NO TYPING" if player.assisted_chant else "TYPING IS STRONGER", charge]
	_chant_progress.value = player.chant_progress()
	var fill_style := _chant_progress.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style != null:
		fill_style.bg_color = UIKit.GOLD if player.chant_progress() >= 1.0 else UIKit.ACCENT_DARK


func _update_rival_channel() -> void:
	if enemy != null and is_instance_valid(enemy) and enemy.chanting:
		var spell := enemy.current_spell(enemy.chant_slot)
		if spell != null:
			var incantation := spell.incantation()
			var typed := enemy.chant_text.length()
			var shown := ""
			var letter_index := 0
			for ch in incantation:
				if ch == " ":
					shown += " "
				elif letter_index < typed:
					shown += ch
					letter_index += 1
				else:
					shown += "_"
					letter_index += 1
			_rival_channel.text = "RIVAL CHANTING  ·  %s  ·  INTERRUPT!" % shown.to_upper()
		else:
			_rival_channel.text = "RIVAL IS CHANTING…"
	else:
		_rival_channel.text = ""


func _on_chant_interrupted(wiz: Wizard) -> void:
	if wiz == player:
		show_message("CHANT INTERRUPTED", UIKit.DANGER, 0.9)
	else:
		show_message("RIVAL'S CHANT BROKEN", UIKit.GOLD, 0.9)


func _on_cast(wiz: Wizard, spell: SpellDef, stats: Dictionary, _origin: Vector3, _direction: Vector3) -> void:
	announce_cast(spell, stats, wiz == player)
	if wiz == player and bool(stats.get("fizzle", false)):
		show_message("FIZZLED CAST  ·  %d%%" % roundi(float(stats.get("partial_ratio", 0.0)) * 100.0), UIKit.DIM, 0.9)
	elif wiz == player and bool(stats.get("perfect", false)):
		show_message("PERFECT OVERCAST", UIKit.GOLD, 0.8)


## Persistent bottom readout: names every cast as it happens, including the
## rune incantation and the overcast multiplier.
func announce_cast(spell: SpellDef, stats: Dictionary, is_player: bool) -> void:
	if spell == null or _cast_readout == null:
		return
	var color := UIKit.spell_color(spell)
	var overcast := bool(stats.get("overcast", false))
	var fizzle := bool(stats.get("fizzle", false))
	var mult := float(stats.get("overcast_mult", 1.0))
	_cast_readout.text = "%s  ·  %s" % ["YOU" if is_player else "RIVAL", spell.display_name().to_upper()]
	_cast_readout.add_theme_color_override("font_color", color if is_player else color.darkened(0.2))
	var bits: Array[String] = [spell.incantation()]
	if fizzle:
		bits.append("FIZZLE ×%.1f  ·  %d%%" % [float(stats.get("fizzle_mult", Wizard.PARTIAL_CAST_MULT)), roundi(float(stats.get("partial_ratio", 0.0)) * 100.0)])
	if overcast:
		bits.append("×%.1f OVERCAST" % mult)
		if bool(stats.get("perfect", false)):
			bits.append("PERFECT")
	_cast_sub.text = "   ".join(bits)
	_cast_sub.add_theme_color_override("font_color", UIKit.GOLD if overcast else (UIKit.DANGER if fizzle else UIKit.DIM))
	if _cast_tween != null and _cast_tween.is_valid():
		_cast_tween.kill()
	_cast_box.modulate.a = 0.0
	_cast_tween = create_tween()
	_cast_tween.tween_property(_cast_box, "modulate:a", 1.0, 0.10)
	_cast_tween.tween_interval(0.75 if is_player else 0.55)
	_cast_tween.tween_property(_cast_box, "modulate:a", 0.0, 0.3)


func _on_player_damaged(_wiz: Wizard, _amount: float) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_damage_flash.color = Color(0.95, 0.15, 0.25, 0.26)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_damage_flash, "color:a", 0.0, 0.35)


func _on_cast_blocked(wiz: Wizard, reason: String) -> void:
	if wiz == player:
		show_message(reason, UIKit.DANGER, 0.8)


func show_message(text: String, color: Color = UIKit.INK, hold: float = 1.2) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_sub.text = ""
	_play_toast(hold)


func announce(title: String, subtitle: String = "", color: Color = UIKit.INK, hold: float = 1.4) -> void:
	_toast.text = title
	_toast.add_theme_color_override("font_color", color)
	_toast_sub.text = subtitle
	_play_toast(hold)


func _play_toast(hold: float) -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_box.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_box, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(hold)
	_toast_tween.tween_property(_toast_box, "modulate:a", 0.0, 0.35)
