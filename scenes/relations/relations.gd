extends Control

@onready var info_label: Label = %InfoLabel
@onready var rows: VBoxContainer = %Rows
@onready var feedback_label: Label = %FeedbackLabel
@onready var btn_back: Button = %BtnBack

const AFFINITY_BAR_WIDTH := 160
const PORTRAIT_SIZE := Vector2(48, 64)

func _ready() -> void:
	btn_back.pressed.connect(_on_back_pressed)
	if not GameManager.is_game_active:
		info_label.text = "No hay una partida activa."
		return
	RelationsData.relations_changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	var player: Character = GameManager.player_character
	info_label.text = "%s — %s · Oro %d · Acciones %d/%d\nSoberano de tu reino: %s · %s" % [
		player.full_name(), player.role_name(), player.gold, GameManager.actions_remaining, GameManager.actions_per_turn,
		RelationsData.liege_name if player.role != Character.Role.REGENTE else "tú",
		"Casado/a con %s (casa de %s)" % [RelationsData.spouse_name, RelationsData.spouse_family] if RelationsData.is_married() else "Sin casar"]

	for child in rows.get_children():
		child.queue_free()

	_add_header("Señores de los reinos")
	for r: Relationship in RelationsData.lords():
		_add_row(r)

	var rivals := RelationsData.duel_rivals()
	_add_header("Rivales de duelo")
	if rivals.is_empty():
		var empty := Label.new()
		empty.text = "Aún no te has batido con nadie. Reta a duelo desde tu castillo."
		rows.add_child(empty)
	for r: Relationship in rivals:
		_add_row(r)

	var court := RelationsData.courtiers(GameManager.player_kingdom)
	_add_header("Corte de tu reino")
	if court.is_empty():
		var nobody := Label.new()
		nobody.text = "No quedan cortesanos en tu reino con quienes no te hayas batido."
		rows.add_child(nobody)
	for r: Relationship in court:
		_add_row(r)

	_add_header("Guerras y alianzas entre reinos")
	var lines: Array[String] = []
	for key: String in RelationsData.kingdom_wars.keys():
		lines.append("⚔ %s contra %s (desde hace %d meses)" % [
			_pair_names(key)[0], _pair_names(key)[1], GameManager.months_elapsed() - int(RelationsData.kingdom_wars[key])])
	for key: String in RelationsData.kingdom_alliances.keys():
		lines.append("🤝 %s y %s son aliados" % _pair_names(key))
	var diplo := Label.new()
	diplo.text = "Los reinos están en paz." if lines.is_empty() else "\n".join(lines)
	rows.add_child(diplo)

func _pair_names(key: String) -> Array:
	var parts := key.split("|")
	return [KingdomEnums.kingdom_name(int(parts[0])), KingdomEnums.kingdom_name(int(parts[1]))]

func _add_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.831, 0.686, 0.216))
	rows.add_child(lbl)

func _add_row(r: Relationship) -> void:
	var panel := PanelContainer.new()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	panel.add_child(hbox)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = r.character.get_portrait() if r.character != null else null
	hbox.add_child(portrait)

	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = r.person_name
	if r.person_name == RelationsData.liege_name:
		name_lbl.text += "  — tu soberano"
	if r.person_name == RelationsData.spouse_family:
		name_lbl.text += "  — familia de tu cónyuge"
	var detail_lbl := Label.new()
	detail_lbl.text = _detail_text(r)
	detail_lbl.add_theme_font_size_override("font_size", 12)
	detail_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	name_box.add_child(name_lbl)
	name_box.add_child(detail_lbl)
	hbox.add_child(name_box)

	var status_box := VBoxContainer.new()
	var status_lbl := Label.new()
	status_lbl.text = "%s (%+d)" % [r.status_text(), r.affinity]
	var bar := ProgressBar.new()
	bar.min_value = -100
	bar.max_value = 100
	bar.value = r.affinity
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(AFFINITY_BAR_WIDTH, 10)
	status_box.add_child(status_lbl)
	status_box.add_child(bar)
	hbox.add_child(status_box)

	if r.kind == Relationship.Kind.SENOR:
		var gift_reason := RelationsData.can_send_gift(r)
		hbox.add_child(_make_button("Enviar presentes (%d oro)" % RelationsData.GIFT_COST, gift_reason,
			func(): _show_feedback(RelationsData.send_gift(r))))
		var alliance_reason := RelationsData.can_propose_alliance(r)
		if not r.allied:
			hbox.add_child(_make_button("Proponer alianza", alliance_reason,
				func(): _show_feedback(RelationsData.propose_alliance(r))))
		var player_role: int = GameManager.player_character.role
		if r.at_war:
			hbox.add_child(_make_button("Proponer paz (%d oro)" % RelationsData.PEACE_TRIBUTE, RelationsData.can_propose_peace(r),
				func(): _show_feedback(RelationsData.propose_peace(r))))
		elif player_role >= Character.Role.NOBLEZA_ALTA and not r.allied:
			hbox.add_child(_make_button("Declarar guerra", RelationsData.can_declare_war(r),
				func(): _show_feedback(RelationsData.declare_war(r))))
		if not RelationsData.is_married():
			hbox.add_child(_make_button("Pedir matrimonio (%d oro)" % RelationsData.DOWRY_COST, RelationsData.can_propose_marriage(r),
				func(): _show_feedback(RelationsData.propose_marriage(r))))
	rows.add_child(panel)

func _make_button(text: String, disabled_reason: String, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.disabled = not disabled_reason.is_empty()
	btn.tooltip_text = disabled_reason if btn.disabled else "Gasta 1 acción del turno."
	btn.pressed.connect(on_press)
	return btn

func _detail_text(r: Relationship) -> String:
	if r.kind == Relationship.Kind.RIVAL_DUELO:
		return "Rival de duelos — le ganaste %d, te ganó %d" % [r.duels_won_against, r.duels_lost_against]
	if r.kind == Relationship.Kind.CORTESANO:
		var c := r.character
		return "%s · %s · Combate %d, Defensa %d" % [c.role_name(), Character.Personality.keys()[c.personality].capitalize(), c.combat, c.defense] if c != null else ""
	var castles := RelationsData.castles_of(r.person_name)
	if castles.is_empty():
		return "Sin tierras: perdió sus castillos"
	var names: Array[String] = []
	for c: Castle in castles:
		names.append("%s (%s)" % [c.castle_name, KingdomEnums.kingdom_name(c.kingdom)])
	return "Gobierna: " + ", ".join(names)

func _show_feedback(text: String) -> void:
	feedback_label.text = text
	# relations_changed ya reconstruye las filas; las acciones también cambian, así que se refresca el encabezado.
	_rebuild()

func _on_back_pressed() -> void:
	var scene := "res://scenes/map/map.tscn" if GameManager.is_game_active else "res://scenes/main_menu/main_menu.tscn"
	get_tree().change_scene_to_file(scene)
