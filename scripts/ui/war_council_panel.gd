extends Control
# Consejo de guerra: la nobleza (desde Nobleza Baja) decide qué tropa lleva cada personaje de su facción
# (su séquito y los caballeros y señores de su reino). Al resto se la asigna el general en cada batalla.
# Uso: const WarCouncilPanel = preload("res://scripts/ui/war_council_panel.gd"); WarCouncilPanel.open(nodo, al_cerrar)

const AUTO_TEXT := "Que decida el general"
const AUTO_ID := 99                      # id del elemento «que decida el general» (los ids 0..3 son las familias)

var on_close: Callable
var _first: Control

static func open(host: Node, closed: Callable = Callable()) -> Control:
	var panel: Control = load("res://scripts/ui/war_council_panel.gd").new()
	panel.on_close = closed
	host.add_child(panel)
	return panel

## Motivo por el que el jugador no puede reunir el Consejo de guerra ("" si puede).
static func block_reason(player: Character) -> String:
	if player == null:
		return "No hay personaje."
	if player.rank() < Character.rank_of(Character.Role.NOBLEZA_BAJA):
		return "Solo la nobleza (desde Nobleza Baja) asigna las tropas de su facción."
	return ""

## Personajes de tu facción: tu séquito y los caballeros y señores de tu reino (y tú).
static func faction_characters() -> Array[Character]:
	var result: Array[Character] = []
	var player: Character = GameManager.player_character
	if player != null:
		result.append(player)
	for r: Relationship in RelationsData.retinue_members():
		if r.character != null and not r.character in result:
			result.append(r.character)
	for r: Relationship in RelationsData.relations:
		var c := r.character
		if c == null or c in result or c.rank() < Character.rank_of(Character.Role.CABALLERO):
			continue
		if r.kind not in [Relationship.Kind.SENOR, Relationship.Kind.CORTESANO]:
			continue
		if _kingdom_of(r) == GameManager.player_kingdom:
			result.append(c)
	return result

static func _kingdom_of(r: Relationship) -> int:
	if r.kingdom >= 0:
		return r.kingdom
	for castle: Castle in MapData.castles:
		if castle.owner_name == r.person_name:
			return castle.kingdom
	return -1

static func mastery_line(c: Character) -> String:
	var parts: Array[String] = []
	for f in 4:
		parts.append("%s %d" % [BattleEnums.family_name(f), c.mastery(f)])
	return " · ".join(parts)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 70
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 500)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	var title := Label.new()
	title.text = "Consejo de guerra"
	title.theme_type_variation = &"HeaderLabel"
	root.add_child(title)
	var note := Label.new()
	note.text = "Asigna la tropa de cada personaje de tu facción. Con mando %d o más en una familia, lleva su versión avanzada. Quien no tenga tropa asignada la recibe del general." % Character.MASTERY_ADVANCED
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.theme_type_variation = &"MutedLabel"
	root.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var reason := block_reason(GameManager.player_character)
	if not reason.is_empty():
		var l := Label.new()
		l.text = reason
		list.add_child(l)
	else:
		for c: Character in faction_characters():
			list.add_child(_row(c))
	var close := Button.new()
	close.text = "Cerrar"
	close.theme_type_variation = &"PrimaryButton"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close)
	root.add_child(close)
	(_first if _first != null else close).grab_focus.call_deferred()

func _row(c: Character) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(FaceIcon.make(c, 44))
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.text = "%s · %s\nMando: %s" % [c.full_name(), c.role_title(), mastery_line(c)]
	row.add_child(info)
	var pick := OptionButton.new()
	pick.add_item(AUTO_TEXT, AUTO_ID)
	for f in 4:
		var advanced := c.mastery(f) >= Character.MASTERY_ADVANCED
		pick.add_item(BattleEnums.unit_type_name(BattleEnums.advanced_type(f) if advanced else BattleEnums.basic_type(f)), f)
	pick.select(pick.get_item_index(c.assigned_family if c.assigned_family >= 0 else AUTO_ID))
	pick.item_selected.connect(func(i: int):
		var id := pick.get_item_id(i)
		c.assigned_family = -1 if id == AUTO_ID else id)
	row.add_child(pick)
	if _first == null:
		_first = pick
	return row

func _close() -> void:
	if on_close.is_valid():
		on_close.call()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
