class_name DraftScreen
extends Control

signal draft_complete

var player_lost := false
var player_loadout: Dictionary = {}
var enemy_loadout: Dictionary = {}
var round_no := 1

var _offer: Array = []
var _cards: Array[BoonCard] = []
var _resolved := false
var _ai_card: Dictionary = {}
var _status: Label


func setup(p_player_lost: bool, p_player_loadout: Dictionary, p_enemy_loadout: Dictionary, p_round: int) -> void:
	player_lost = p_player_lost
	player_loadout = p_player_loadout
	enemy_loadout = p_enemy_loadout
	round_no = p_round


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := Backdrop.new()
	bg.accent = UIKit.GOLD if player_lost else UIKit.DANGER
	bg.intensity = 0.9
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var kicker := UIKit.bold_label("ROUND %d COMPLETE" % round_no, 14, UIKit.GOLD)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(kicker)

	var title := UIKit.heading("CHOOSE A BOON" if player_lost else "RIVAL PICKS FIRST", 52, UIKit.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var subtext := "You lost the round, so you pick first." if player_lost else "The rival lost the round and takes the first card."
	var sub := UIKit.label(subtext, 18, UIKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)

	# The rival picks first when it lost.
	if not player_lost:
		_offer = Game.draw_offer(3, player_loadout)
		if not _offer.is_empty():
			_ai_card = _offer[randi() % _offer.size()]
			_offer.erase(_ai_card)
			Game.apply_card(enemy_loadout, _ai_card)
			Game.enemy_wand = str(enemy_loadout.get("wand_id", Game.enemy_wand))
			Game.enemy_pages = enemy_loadout.get("pages", [])
		var ai_banner := UIKit.bold_label("RIVAL CLAIMS  ·  %s  —  %s" % [str(_ai_card.get("name", "")), str(_ai_card.get("desc", ""))], 16, UIKit.DANGER)
		ai_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ai_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(ai_banner)
	else:
		_offer = Game.draw_offer(3, player_loadout)

	root.add_child(UIKit.vspace(10))

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(row)

	for data in _offer:
		var card := BoonCard.new()
		row.add_child(card)
		card.setup(data)
		card.pressed.connect(_on_card_pressed)
		_cards.append(card)

	_status = UIKit.bold_label("", 18, UIKit.GOLD)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status)

	var foot := UIKit.label("Loser picks first  ·  Boons persist for the rest of the match", 13, UIKit.DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(foot)

	if not _cards.is_empty():
		_cards[0].grab_focus()


func _on_card_pressed(card: BoonCard) -> void:
	if _resolved or card.disabled:
		return
	_resolved = true

	card.chosen = true
	for other in _cards:
		other.disabled = true

	Game.apply_card(player_loadout, card.data)
	Game.player_wand = str(player_loadout.get("wand_id", Game.player_wand))
	Game.player_pages = player_loadout.get("pages", [])

	var rival_text := ""
	if player_lost:
		# Player picked first; the rival takes one of the remaining cards.
		var remaining: Array = []
		for data in _offer:
			if data != card.data:
				remaining.append(data)
		if not remaining.is_empty():
			_ai_card = remaining[randi() % remaining.size()]
			Game.apply_card(enemy_loadout, _ai_card)
			Game.enemy_wand = str(enemy_loadout.get("wand_id", Game.enemy_wand))
			Game.enemy_pages = enemy_loadout.get("pages", [])
			rival_text = "   ·   RIVAL TAKES  %s" % str(_ai_card.get("name", ""))

	_status.text = "YOU TAKE  ·  %s%s" % [str(card.data.get("name", "")), rival_text]
	_status.add_theme_color_override("font_color", UIKit.GOLD)
	await get_tree().create_timer(1.0, false).timeout
	draft_complete.emit()


## Test/controller fast path: take the first available card.
func auto_pick() -> void:
	for card in _cards:
		if not card.disabled:
			_on_card_pressed(card)
			return
