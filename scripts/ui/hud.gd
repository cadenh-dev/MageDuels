class_name DuelHUD
extends CanvasLayer

signal pause_resume
signal pause_quit

var player: Wizard
var enemy: Wizard
var arena: Arena

var _root: Control
var _player_hp: ProgressBar
var _player_mana: ProgressBar
var _enemy_hp: ProgressBar
var _enemy_mana: ProgressBar
var _player_hp_label: Label
var _enemy_hp_label: Label
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
var _toast: Label
var _toast_sub: Label
var _toast_box: VBoxContainer
var _toast_tween: Tween
var _damage_flash: ColorRect
var _flash_tween: Tween
var _pause_root: Control
var _coach: Coach
var _last_page := -1
var _rival_channel: Label


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
		player.chant_changed.connect(func(_w, _a) -> void: _refresh_chant())
		player.chant_interrupted.connect(_on_chant_interrupted)
	if enemy != null:
		enemy.cast_blocked.connect(_on_cast_blocked)
		enemy.chant_interrupted.connect(_on_chant_interrupted)


func _build() -> void:
	_root = Control.new()
	_root.name = "HUDRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_player_panel()
	_build_enemy_panel()
	_build_center_top()
	_build_bottom_bar()
	_build_chant()
	_build_toast()
	_build_flash()
	_build_pause()
	_build_coach()

	_last_page = -1
	_refresh_slots()
	_refresh_chant()


func _build_player_panel() -> void:
	var panel := UIKit.panel(Color(0.07, 0.05, 0.12, 0.86), UIColorBorder(), 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(24, 20)
	panel.custom_minimum_size = Vector2(348, 0)
	_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header)
	var you := UIKit.bold_label("YOU", 16, UIKit.ACCENT)
	header.add_child(you)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	var wand_name := UIKit.label(str(SpellData.wand(Game.player_wand)["name"]), 15, UIKit.MUTED)
	header.add_child(wand_name)

	var hp_wrap := Control.new()
	hp_wrap.custom_minimum_size = Vector2(0, 20)
	hp_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hp_wrap)
	_player_hp = _make_bar(UIKit.HEAL, false)
	hp_wrap.add_child(_player_hp)
	_player_hp_label = UIKit.bold_label("100 / 100", 13, Color(1, 1, 1, 0.9))
	_player_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_player_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_player_hp_label.offset_right = -8
	hp_wrap.add_child(_player_hp_label)
	_hp_style = _player_hp.get_theme_stylebox("fill") as StyleBoxFlat

	var mana_wrap := Control.new()
	mana_wrap.custom_minimum_size = Vector2(0, 9)
	mana_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(mana_wrap)
	_player_mana = _make_bar(UIKit.MANA, false)
	mana_wrap.add_child(_player_mana)
	_mana_style = _player_mana.get_theme_stylebox("fill") as StyleBoxFlat


func _build_enemy_panel() -> void:
	var panel := UIKit.panel(Color(0.07, 0.05, 0.12, 0.86), UIColorBorder(), 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-372, 20)
	panel.custom_minimum_size = Vector2(348, 0)
	_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header)
	var wand_name := UIKit.label(str(SpellData.wand(Game.enemy_wand)["name"]), 15, UIKit.MUTED)
	header.add_child(wand_name)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	var rival := UIKit.bold_label(AIWizard.title_for(Game.enemy_wand), 14, UIKit.DANGER)
	header.add_child(rival)

	var hp_wrap := Control.new()
	hp_wrap.custom_minimum_size = Vector2(0, 20)
	hp_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hp_wrap)
	_enemy_hp = _make_bar(UIKit.DANGER, true)
	hp_wrap.add_child(_enemy_hp)
	_enemy_hp_label = UIKit.bold_label("100 / 100", 13, Color(1, 1, 1, 0.9))
	_enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_enemy_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_enemy_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_enemy_hp_label.offset_left = 8
	hp_wrap.add_child(_enemy_hp_label)
	_hp_style_enemy = _enemy_hp.get_theme_stylebox("fill") as StyleBoxFlat

	var mana_wrap := Control.new()
	mana_wrap.custom_minimum_size = Vector2(0, 9)
	mana_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(mana_wrap)
	_enemy_mana = _make_bar(UIKit.MANA, true)
	mana_wrap.add_child(_enemy_mana)
	_mana_style_enemy = _enemy_mana.get_theme_stylebox("fill") as StyleBoxFlat


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


func _build_center_top() -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-160, 18)
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 5)
	_root.add_child(box)

	_round_label = UIKit.heading("ROUND 1", 22, UIKit.INK)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_round_label)

	_score_label = UIKit.bold_label("0  —  0", 18, UIKit.MUTED)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_score_label)

	_element_panel = UIKit.panel(Color(0.08, 0.06, 0.14, 0.9), Color(0, 0, 0, 0), 8)
	_element_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_element_panel)
	_element_badge = UIKit.bold_label("", 13, UIKit.GOLD)
	_element_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_element_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_element_panel.add_child(_element_badge)


func _build_bottom_bar() -> void:
	_slots_box = HBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 10)
	_slots_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_slots_box.position = Vector2(-312, -112)
	_slots_box.custom_minimum_size = Vector2(624, 0)
	_slots_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_slots_box)

	for i in 4:
		var slot := SpellSlotWidget.new()
		slot.custom_minimum_size = Vector2(146, 92)
		_slots_box.add_child(slot)
		_slots.append(slot)

	_page_label = UIKit.bold_label("PAGE A  ·  SHIFT to swap", 14, UIKit.MUTED)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_page_label.position = Vector2(-200, -134)
	_page_label.custom_minimum_size = Vector2(400, 0)
	_page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_page_label)

	var hint_panel := UIKit.panel(Color(0.03, 0.02, 0.06, 0.7), Color(1, 1, 1, 0.06), 8)
	hint_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint_panel.position = Vector2(20, -44)
	hint_panel.custom_minimum_size = Vector2(0, 0)
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(hint_panel)
	var hint := UIKit.label("WASD · AIM · 1-4 · SPACE · SHIFT", 11, UIKit.MUTED)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_child(hint)

	_rival_channel = UIKit.bold_label("", 13, UIKit.GOLD)
	_rival_channel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_rival_channel.position = Vector2(-220, 140)
	_rival_channel.custom_minimum_size = Vector2(440, 0)
	_rival_channel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rival_channel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rival_channel)


func _build_chant() -> void:
	_chant_panel = UIKit.panel(Color(0.08, 0.06, 0.15, 0.94), UIKit.ACCENT, 12)
	_chant_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_chant_panel.position = Vector2(-290, -262)
	_chant_panel.custom_minimum_size = Vector2(580, 0)
	_chant_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chant_panel.visible = false
	_root.add_child(_chant_panel)

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
	_chant_progress.custom_minimum_size = Vector2(540, 5)
	_chant_progress.min_value = 0.0
	_chant_progress.max_value = 1.0
	_chant_progress.value = 0.0
	_chant_progress.show_percentage = false
	_chant_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.03, 0.02, 0.06, 0.9)
	track.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIKit.GOLD
	fill.set_corner_radius_all(3)
	_chant_progress.add_theme_stylebox_override("background", track)
	_chant_progress.add_theme_stylebox_override("fill", fill)
	box.add_child(_chant_progress)

	var hint := UIKit.label("ENTER unleash  ·  ESC cancel  ·  hold the runes for 0.9s", 12, UIKit.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hint)


func _build_toast() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_box.position = Vector2(-360, 190)
	_toast_box.custom_minimum_size = Vector2(720, 0)
	_toast_box.add_theme_constant_override("separation", 2)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.modulate.a = 0.0
	_root.add_child(_toast_box)

	_toast = UIKit.heading("", 46, UIKit.INK)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_child(_toast)

	_toast_sub = UIKit.label("", 19, UIKit.MUTED)
	_toast_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_child(_toast_sub)


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

	var quit := UIKit.ghost_button("QUIT TO MENU", 18)
	quit.pressed.connect(func() -> void: pause_quit.emit())
	box.add_child(quit)


func set_paused(paused: bool) -> void:
	_pause_root.visible = paused


func _build_coach() -> void:
	if Game.round_index != 0:
		return
	_coach = Coach.new()
	_coach.player = player
	_coach.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_coach.position = Vector2(24, 126)
	_root.add_child(_coach)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_update_bars()
	_update_slots()
	_update_round_info()
	_refresh_chant()
	_update_rival_channel()
	if _coach != null and is_instance_valid(_coach):
		_coach.update(_delta)


func _update_bars() -> void:
	_player_hp.max_value = player.max_hp
	_player_hp.value = player.hp
	_player_mana.max_value = player.max_mana
	_player_mana.value = player.mana
	_player_hp_label.text = "%d / %d" % [ceili(player.hp), ceili(player.max_hp)]

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
		if _hp_style_enemy != null:
			_hp_style_enemy.bg_color = UIKit.DANGER


func _update_slots() -> void:
	if player.page != _last_page:
		_refresh_slots()
	for i in _slots.size():
		var slot := _slots[i]
		var total: float = player.cooldown_max[i] if i < player.cooldown_max.size() else 1.0
		var rem: float = player.cooldowns[i] if i < player.cooldowns.size() else 0.0
		slot.cooldown_ratio = rem / maxf(0.001, total) if rem > 0.0 else 0.0
		slot.cooldown_text = "%.1f" % rem if rem > 0.15 else ""
		slot.selected = (i == player.selected_slot)


func _refresh_slots() -> void:
	if player == null:
		return
	_last_page = player.page
	var spells := player.page_spells()
	for i in _slots.size():
		var spell: SpellDef = spells[i] if i < spells.size() else null
		_slots[i].setup(spell, str(i + 1), i == player.selected_slot)
	_page_label.text = "PAGE %s  ·  SHIFT to swap" % ("A" if player.page == 0 else "B")


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
	_chant_title.text = "CHANTING  ·  %s" % spell.display_name()
	_chant_progress.value = player.chant_progress()
	var fill_style := _chant_progress.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style != null:
		fill_style.bg_color = UIKit.GOLD if player.chant_progress() >= 1.0 else UIKit.ACCENT_DARK
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


func _update_rival_channel() -> void:
	if enemy != null and is_instance_valid(enemy) and enemy.chanting:
		var spell := enemy.current_spell(enemy.chant_slot)
		if spell != null:
			_rival_channel.text = "RIVAL CHANTING  ·  %s  ·  INTERRUPT!" % spell.display_name().to_upper()
		else:
			_rival_channel.text = "RIVAL IS CHANTING…"
	else:
		_rival_channel.text = ""


func _on_chant_interrupted(wiz: Wizard) -> void:
	if wiz == player:
		show_message("CHANT INTERRUPTED", UIKit.DANGER, 0.9)
	else:
		show_message("RIVAL'S CHANT BROKEN", UIKit.GOLD, 0.9)


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


func UIColorBorder() -> Color:
	return UIKit.OUTLINE
