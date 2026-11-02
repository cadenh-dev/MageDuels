class_name WandScreen
extends Control

signal continue_pressed
signal back_pressed

var _cards: Array[WandCard] = []
var _continue: Button
var _selected := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var bg := Backdrop.new()
	bg.accent = Color("b98aff")
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := UIKit.heading("CHOOSE YOUR WAND", 44, UIKit.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var sub := UIKit.label("The wand sets your affinity, your mana, and your rhythm.", 17, UIKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)

	root.add_child(UIKit.vspace(12))

	var card_center := CenterContainer.new()
	card_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card_center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_center.add_child(row)

	for wand_id in SpellData.WAND_ORDER:
		var card := WandCard.new()
		row.add_child(card)
		card.setup(wand_id)
		card.pressed.connect(_on_card_pressed)
		_cards.append(card)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)

	var back := UIKit.ghost_button("BACK", 18)
	back.custom_minimum_size = Vector2(150, 50)
	back.pressed.connect(func() -> void: back_pressed.emit())
	footer.add_child(back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	_continue = UIKit.button("CRAFT SPELLS", 22)
	_continue.custom_minimum_size = Vector2(270, 54)
	_continue.pressed.connect(func() -> void: continue_pressed.emit())
	footer.add_child(_continue)

	_select(Game.player_wand)
	if not _cards.is_empty():
		_cards[0].grab_focus()


func _on_card_pressed(card: WandCard) -> void:
	_select(card.wand_id)


func _select(wand_id: String) -> void:
	_selected = wand_id
	Game.player_wand = wand_id
	for card in _cards:
		card.selected = card.wand_id == wand_id
	_continue.disabled = wand_id == ""
	_continue.text = "CRAFT SPELLS  ·  %s" % str(SpellData.wand(wand_id)["name"]).to_upper()


func selected_wand() -> String:
	return _selected
