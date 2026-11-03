class_name CraftScreen
extends Control

signal begin_pressed
signal back_pressed

var pages: Array = []
var _page := 0
var _slot := 0
var _cards: Array = [[], []]
var _element_buttons: Dictionary = {}
var _form_buttons: Dictionary = {}
var _modifier_buttons: Dictionary = {}

var _preview_name: Label
var _preview_incant: Label
var _preview_stats: Label
var _preview_status: Label
var _preview_panel: PanelContainer
var _mode_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	pages = _copy_pages(Game.player_pages)

	var bg := Backdrop.new()
	bg.accent = UIKit.spell_color(pages[0][0])
	bg.intensity = 0.8
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	var title := UIKit.heading("CRAFT YOUR SPELLBOOK", 38, UIKit.INK)
	titles.add_child(title)
	var sub := UIKit.label("Click a slot, then forge its runes. Short incantations are easier to type under fire.", 15, UIKit.MUTED)
	titles.add_child(sub)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var wand_info := UIKit.bold_label("%s  ·  %s affinity" % [str(SpellData.wand(Game.player_wand)["name"]), str(SpellData.wand(Game.player_wand)["affinity"]).to_upper()], 16, UIKit.GOLD)
	wand_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(wand_info)

	root.add_child(UIKit.vspace(2))

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)

	var pages_box := VBoxContainer.new()
	pages_box.add_theme_constant_override("separation", 10)
	pages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(pages_box)

	pages_box.add_child(_build_page_row(0, "PAGE A", "Quickcast 1–4"))
	pages_box.add_child(_build_page_row(1, "PAGE B", "Tap SHIFT to swap"))
	pages_box.add_child(_build_tips())

	var picker := _build_picker()
	content.add_child(picker)

	root.add_child(_build_footer())
	_select_slot(0, 0)
	_refresh_all()
	if not _cards.is_empty() and not _cards[0].is_empty():
		_cards[0][0].grab_focus()


func _copy_pages(source: Array) -> Array:
	var out: Array = []
	for p in source:
		var row: Array[SpellDef] = []
		for s in p:
			row.append(s.duplicate_spell())
		out.append(row)
	return out


func _build_page_row(page_index: int, page_name: String, hint: String) -> PanelContainer:
	var panel := UIKit.panel(Color(0.07, 0.05, 0.12, 0.8), UIKit.OUTLINE, 12)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var name_label := UIKit.bold_label(page_name, 15, UIKit.ACCENT if page_index == 0 else UIKit.GOLD)
	head.add_child(name_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var hint_label := UIKit.label(hint, 13, UIKit.DIM)
	head.add_child(hint_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	for slot in 4:
		var card := SpellCard.new()
		row.add_child(card)
		card.setup(pages[page_index][slot], slot, false, false)
		card.pressed.connect(func(_c: SpellCard) -> void: _select_slot(page_index, slot))
		_cards[page_index].append(card)
	return panel


func _build_picker() -> PanelContainer:
	var panel := UIKit.panel(Color(0.08, 0.06, 0.14, 0.92), UIKit.ACCENT, 12)
	panel.custom_minimum_size = Vector2(322, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	var title := UIKit.bold_label("RUNE FORGE", 17, UIKit.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_preview_panel = UIKit.panel(Color(0.05, 0.04, 0.09, 0.9), UIKit.OUTLINE, 8)
	box.add_child(_preview_panel)
	var preview := VBoxContainer.new()
	preview.add_theme_constant_override("separation", 0)
	_preview_panel.add_child(preview)
	_preview_name = UIKit.bold_label("", 18, UIKit.INK)
	preview.add_child(_preview_name)
	_preview_incant = UIKit.bold_label("", 15, UIKit.GOLD)
	preview.add_child(_preview_incant)
	_preview_stats = UIKit.label("", 12, UIKit.MUTED)
	preview.add_child(_preview_stats)
	_preview_status = UIKit.label("", 11, UIKit.DIM)
	_preview_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_status.custom_minimum_size = Vector2(272, 0)
	preview.add_child(_preview_status)

	box.add_child(_section_label("ELEMENT"))
	var egrid := GridContainer.new()
	egrid.columns = 3
	egrid.add_theme_constant_override("h_separation", 4)
	egrid.add_theme_constant_override("v_separation", 4)
	box.add_child(egrid)
	for id in SpellData.element_ids():
		var e: Dictionary = SpellData.ELEMENTS[id]
		var b := _rune_button("%s\n%s" % [str(e["name"]), str(e["word"])], e["color"])
		b.tooltip_text = str(e["desc"])
		b.pressed.connect(_apply_element.bind(id))
		egrid.add_child(b)
		_element_buttons[id] = b

	box.add_child(_section_label("FORM"))
	var fgrid := GridContainer.new()
	fgrid.columns = 3
	fgrid.add_theme_constant_override("h_separation", 4)
	fgrid.add_theme_constant_override("v_separation", 4)
	box.add_child(fgrid)
	for id in SpellData.form_ids():
		var f: Dictionary = SpellData.FORMS[id]
		var b := _rune_button("%s\n%s" % [str(f["name"]), str(f["word"])], UIKit.ACCENT)
		b.tooltip_text = "%d damage · %d mana · %.2fs" % [roundi(float(f["damage"])), roundi(float(f["mana"])), float(f["cooldown"])]
		b.pressed.connect(_apply_form.bind(id))
		fgrid.add_child(b)
		_form_buttons[id] = b

	box.add_child(_section_label("MODIFIER"))
	var mgrid := GridContainer.new()
	mgrid.columns = 3
	mgrid.add_theme_constant_override("h_separation", 4)
	mgrid.add_theme_constant_override("v_separation", 4)
	box.add_child(mgrid)
	for id in SpellData.modifier_ids():
		var m: Dictionary = SpellData.MODIFIERS[id]
		var b := _rune_button("%s\n%s" % [str(m["name"]), str(m.get("word", "—"))], UIKit.GOLD)
		b.tooltip_text = str(m["desc"])
		b.pressed.connect(_apply_modifier.bind(id))
		mgrid.add_child(b)
		_modifier_buttons[id] = b

	return panel


func _build_tips() -> PanelContainer:
	var panel := UIKit.panel(Color(0.055, 0.04, 0.095, 0.75), Color(1, 1, 1, 0.05), 12)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	var title := UIKit.bold_label("DUEL NOTES", 13, UIKit.GOLD)
	box.add_child(title)

	var tips := [
		"TYPED OVERCAST: type the gold incantation, hold 1.6s, press ENTER. ×2.4 damage for full mana — direct damage breaks the chant.",
		"FIZZLE: if you only get half the runes right, ENTER still casts at ×0.5 damage. Full mana and cooldown — a consolation, not a plan.",
		"ASSISTED OVERCAST: hold F / RMB / LT for 2.3s instead. ×1.9 damage, no typing; release in the gold window for +15% PERFECT.",
		"TRACK is a modifier: every projectile it touches curves toward the rival. Fire + TRACK makes seeking bolts, even at a bad angle.",
		"The arena element shifts every round and empowers matching spells by 15%. Pages A and B should cover different elements.",
	]
	for tip in tips:
		var line := UIKit.label("·  " + tip, 14, UIKit.MUTED)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(0, 0)
		box.add_child(line)
	return panel


func _section_label(text: String) -> Label:
	var l := UIKit.bold_label(text, 12, UIKit.MUTED)
	l.add_theme_constant_override("outline_size", 0)
	return l


func _rune_button(text: String, accent: Color) -> Button:
	var b := UIKit.button(text, 12, accent)
	b.custom_minimum_size = Vector2(96, 40)
	b.add_theme_font_override("font", UIKit.body_font())
	b.add_theme_color_override("font_color", UIKit.INK)
	b.tooltip_text = ""
	return b


func _build_footer() -> HBoxContainer:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)

	var back := UIKit.ghost_button("BACK", 17)
	back.custom_minimum_size = Vector2(120, 46)
	back.pressed.connect(func() -> void: back_pressed.emit())
	footer.add_child(back)

	var random := UIKit.ghost_button("RANDOMIZE", 17)
	random.custom_minimum_size = Vector2(150, 46)
	random.pressed.connect(_randomize)
	footer.add_child(random)

	var reset := UIKit.ghost_button("RESET", 17)
	reset.custom_minimum_size = Vector2(120, 46)
	reset.pressed.connect(_reset)
	footer.add_child(reset)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	_mode_label = UIKit.label("", 13, UIKit.DIM)
	_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_mode_label)

	var quick := UIKit.button("DUEL NOW", 19, UIKit.GOLD)
	quick.custom_minimum_size = Vector2(170, 50)
	quick.tooltip_text = "Accept this spellbook and start the duel immediately."
	quick.pressed.connect(_duel_now)
	footer.add_child(quick)

	var begin := UIKit.button("BEGIN DUEL", 21)
	begin.custom_minimum_size = Vector2(210, 50)
	begin.pressed.connect(_begin)
	footer.add_child(begin)

	return footer


func _select_slot(page_index: int, slot: int) -> void:
	_page = page_index
	_slot = slot
	for p in 2:
		for s in 4:
			var card: SpellCard = _cards[p][s]
			card.selected = (p == page_index and s == slot)
	_refresh_all()


func _apply_element(id: String) -> void:
	var current: SpellDef = pages[_page][_slot]
	pages[_page][_slot] = SpellDef.new(id, current.form, current.modifier)
	_refresh_all()


func _apply_form(id: String) -> void:
	var current: SpellDef = pages[_page][_slot]
	pages[_page][_slot] = SpellDef.new(current.element, id, current.modifier)
	_refresh_all()


func _apply_modifier(id: String) -> void:
	var current: SpellDef = pages[_page][_slot]
	pages[_page][_slot] = SpellDef.new(current.element, current.form, id)
	_refresh_all()


func _randomize() -> void:
	for p in 2:
		for s in 4:
			pages[p][s] = SpellData.random_spell(Game.player_wand)
	_refresh_all()


func _reset() -> void:
	var fresh := _copy_pages(SpellData.default_pages(Game.player_wand))
	for p in 2:
		for s in 4:
			pages[p][s] = fresh[p][s]
	_refresh_all()


func _refresh_all() -> void:
	for p in 2:
		for s in 4:
			_cards[p][s].setup(pages[p][s], s, false, false)
	var spell: SpellDef = pages[_page][_slot]
	_preview_name.text = spell.display_name()
	_preview_name.add_theme_color_override("font_color", UIKit.spell_color(spell))
	_preview_incant.text = spell.incantation()
	var st := spell.base_stats()
	var over := spell.resolved_stats(SpellData.wand(Game.player_wand), true)
	_preview_stats.text = "%d→%d dmg   %d mana   %.2fs   %s" % [
		roundi(float(st["damage"])), roundi(float(over["damage"])),
		roundi(float(st["mana"])), float(st["cooldown"]), st["kind"]
	]
	_preview_stats.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_preview_status.text = str(st["status"])
	_preview_status.add_theme_color_override("font_color", UIKit.spell_color(spell).darkened(0.15))

	_update_rune_button(_element_buttons, spell.element, spell.element_data()["color"])
	_update_rune_button(_form_buttons, spell.form, UIKit.ACCENT)
	_update_rune_button(_modifier_buttons, spell.modifier, UIKit.GOLD)

	_mode_label.text = "Editing page %s  ·  slot %d" % ["A" if _page == 0 else "B", _slot + 1]


func _update_rune_button(buttons: Dictionary, active_id: String, accent: Color) -> void:
	for id in buttons:
		var b: Button = buttons[id]
		var active: bool = id == active_id
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(accent.r, accent.g, accent.b, 0.22) if active else Color("191229")
		sb.border_color = accent if active else Color(accent.r, accent.g, accent.b, 0.22)
		sb.set_border_width_all(2 if active else 1)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		b.add_theme_stylebox_override("normal", sb)


func _begin() -> void:
	Game.player_pages = _copy_pages(pages)
	begin_pressed.emit()


func _duel_now() -> void:
	Game.player_pages = _copy_pages(pages)
	begin_pressed.emit()
