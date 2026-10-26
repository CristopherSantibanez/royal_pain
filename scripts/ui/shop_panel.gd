extends Control
# Armería del castillo: compra y venta de equipo. El surtido cambia cada mes y mejora con tu rango
# (un campesino solo encuentra piezas comunes). El Carisma abarata los precios.
# Uso: const ShopPanel = preload("res://scripts/ui/shop_panel.gd"); ShopPanel.open(nodo)

const STOCK_SIZE := 8
const SELL_FACTOR := 0.4                 # al vender recuperas el 40% del precio
const CHARISMA_DISCOUNT := 0.02          # 2% de rebaja (o recargo) por punto de Carisma sobre (o bajo) 10
const MAX_TIER_BY_ROLE := {
	Character.Role.CAMPESINO: 1, Character.Role.SOLDADO: 1, Character.Role.CABALLERO: 2,
	Character.Role.NOBLEZA_BAJA: 3, Character.Role.NOBLEZA_ALTA: 3, Character.Role.REGENTE: 3,
}

signal purchased

var _stock_list: VBoxContainer
var _owned_list: VBoxContainer
var _gold_label: Label
var _feedback: Label
var _first_button: Button

static func open(host: Node) -> Control:
	var panel: Control = load("res://scripts/ui/shop_panel.gd").new()
	host.add_child(panel)
	return panel

## Precio de compra para el jugador (con su Carisma).
static func buy_price(item: Equipment, buyer: Character) -> int:
	var factor := clampf(1.0 - (buyer.charisma - 10) * CHARISMA_DISCOUNT, 0.8, 1.2)
	return maxi(1, roundi(item.price * factor))

static func sell_price(item: Equipment) -> int:
	return maxi(1, roundi(item.price * SELL_FACTOR))

## Surtido del mes: fijo durante el mes y distinto en cada castillo.
static func monthly_stock(player: Character, castle_id: String) -> Array[Equipment]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [castle_id, GameManager.months_elapsed()])
	var max_tier: int = MAX_TIER_BY_ROLE.get(player.role, 1)
	var pool: Array[Equipment] = []
	for item: Equipment in GameData.equipment_catalog:
		if item.tier <= max_tier and item.price > 0:
			pool.append(item)
	var stock: Array[Equipment] = []
	while not pool.is_empty() and stock.size() < STOCK_SIZE:
		stock.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	stock.sort_custom(func(a: Equipment, b: Equipment) -> bool: return a.slot < b.slot or a.slot == b.slot and a.price < b.price)
	return stock

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 520)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Armería"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_gold_label = Label.new()
	_gold_label.theme_type_variation = &"StatLabel"
	header.add_child(_gold_label)

	var note := Label.new()
	note.theme_type_variation = &"MutedLabel"
	note.text = "El surtido cambia cada mes y mejora con tu rango. Una pieza por ranura: comprar otra de la misma ranura entrega la anterior a cuenta (%d%% de su precio). Tu Carisma regatea el precio." % roundi(SELL_FACTOR * 100)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	_stock_list = _column(columns, "A la venta este mes")
	_owned_list = _column(columns, "Tu equipo")

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_feedback)
	var close := Button.new()
	close.text = "Cerrar"
	close.theme_type_variation = &"PrimaryButton"
	close.pressed.connect(queue_free)
	bottom.add_child(close)
	_rebuild()
	UiAnim.fade_in(panel, 0.15)
	if _first_button != null:
		_first_button.grab_focus.call_deferred()
	else:
		close.grab_focus.call_deferred()

func _column(parent: Node, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var label := Label.new()
	label.theme_type_variation = &"SubheaderLabel"
	label.text = title
	box.add_child(label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list

func _rebuild() -> void:
	var player: Character = GameManager.player_character
	_gold_label.text = "Oro: %d" % player.gold
	_first_button = null
	for list in [_stock_list, _owned_list]:
		for child in list.get_children():
			child.queue_free()
	var castle_id: String = GameManager.current_castle.castle_id if GameManager.current_castle != null else GameManager.home_castle_id
	for item: Equipment in monthly_stock(player, castle_id):
		var owned := player.equipment.any(func(e: Equipment) -> bool: return e.equipment_name == item.equipment_name)
		var price := buy_price(item, player)
		var reason := ""
		if owned:
			reason = "Ya la tienes."
		elif player.gold < price:
			reason = "No te llega el oro."
		elif not _slot_taken(player, item.slot) and player.equipment.size() >= GameData.MAX_EQUIPMENT:
			reason = "Llevas el máximo de %d piezas: vende una antes." % GameData.MAX_EQUIPMENT
		var btn := _row(_stock_list, item, "Comprar (%d)" % price, reason)
		btn.pressed.connect(_buy.bind(item))
		if _first_button == null and not btn.disabled:
			_first_button = btn
	if player.equipment.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"MutedLabel"
		empty.text = "No llevas equipo."
		_owned_list.add_child(empty)
	for item: Equipment in player.equipment.duplicate():
		var btn := _row(_owned_list, item, "Vender (%d)" % sell_price(item), "")
		btn.pressed.connect(_sell.bind(item))

func _slot_taken(player: Character, slot: String) -> bool:
	return player.equipment.any(func(e: Equipment) -> bool: return e.slot == slot)

func _row(list: VBoxContainer, item: Equipment, action: String, disabled_reason: String) -> Button:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	list.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_label := Label.new()
	name_label.theme_type_variation = &"BodyBoldLabel"
	name_label.text = "%s  %s" % [item.equipment_name, "★".repeat(item.tier)]
	text.add_child(name_label)
	var detail := Label.new()
	detail.theme_type_variation = &"MutedLabel"
	detail.add_theme_font_size_override("font_size", 14)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var effects: String = GameData.effect_summary(item.equipment_name)
	detail.text = effects if not effects.is_empty() else "%s · %s" % [item.slot, item.description]
	text.add_child(detail)
	var btn := Button.new()
	btn.text = action
	btn.add_theme_font_size_override("font_size", 13)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.disabled = not disabled_reason.is_empty()
	btn.tooltip_text = disabled_reason
	row.add_child(btn)
	return btn

func _buy(item: Equipment) -> void:
	var player: Character = GameManager.player_character
	var price := buy_price(item, player)
	if player.gold < price:
		return
	player.gold -= price
	var replaced := player.equip(item.duplicate() as Equipment)
	var text := "Compras %s por %d de oro." % [item.equipment_name, price]
	if replaced != null:
		player.gold += sell_price(replaced)
		text += " Entregas %s a cuenta (+%d)." % [replaced.equipment_name, sell_price(replaced)]
	_feedback.text = text
	Sfx.play("clash", -10.0)
	purchased.emit()
	_rebuild()

func _sell(item: Equipment) -> void:
	var player: Character = GameManager.player_character
	player.unequip(item)
	player.gold += sell_price(item)
	_feedback.text = "Vendes %s por %d de oro." % [item.equipment_name, sell_price(item)]
	purchased.emit()
	_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
