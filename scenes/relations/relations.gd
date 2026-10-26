extends Control

const CharacterProfile = preload("res://scripts/ui/character_profile.gd")

@onready var info_label: Label = %InfoLabel
@onready var tabs: TabContainer = %Tabs
@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var feedback_label: Label = %FeedbackLabel
@onready var btn_back: Button = %BtnBack

const AFFINITY_BAR_WIDTH := 150
const FACE_SIZE := 64
# [clave, título]: clave es la que usa RelationsData.requested_tab para abrir una pestaña concreta.
const TAB_KEYS := [["lugar", "Tu zona"], ["afectos", "Afectos"], ["sequito", "Séquito"], ["rivales", "Rivales"], ["senores", "Señores"], ["reinos", "Reinos"]]
const RULES_TEXT := "Los señores aliados no atacan tus castillos; los hostiles te prefieren como blanco. Atacar o conquistar a un señor empeora la relación. Las alianzas requieren 40 de afinidad y rango de Nobleza. El matrimonio político (afinidad 60, Caballero o más) une a la familia como aliada; casarte con la familia de tu soberano te pone en la línea de sucesión al trono. Marchar contra un señor sin declararle la guerra lo ofende; marchar contra un aliado es traición."
const AREA_TEXT := "Gente de tu reino: puedes conversar, hacer regalos, invitar al séquito o retar a duelo. Quien te supera mucho en rango solo acepta un reto si tienes fama; quien te teme puede negarse. El romance solo es posible entre un hombre y una mujer, y nace de la confianza: primero la amistad."
const RETINUE_TEXT := "Tu séquito te acompaña a la batalla (cada miembro lidera una unidad) y puede batirse en duelo en tu lugar como campeón. Para que alguien te siga hacen falta %d de intimidad y la fama y el honor que exige su rango; cada miembro cobra %d de oro al mes. Si no tienes séquito, tu señor te presta compañeros de tu reino, menos leales." % [RelationsData.RETINUE_MIN_AFFECTION, RelationsData.RETINUE_UPKEEP]

var _lists := {}   # clave de pestaña -> VBoxContainer

func _ready() -> void:
	btn_back.pressed.connect(_on_back_pressed)
	_build_tabs()
	if not GameManager.is_game_active:
		info_label.text = "No hay una partida activa."
		return
	RelationsData.relations_changed.connect(_rebuild)
	_rebuild()
	for i in TAB_KEYS.size():
		if TAB_KEYS[i][0] == RelationsData.requested_tab:
			tabs.current_tab = i
	RelationsData.requested_tab = ""
	# De vuelta de un duelo propuesto aquí: cómo terminó.
	if not CombatSetup.last_result_text.is_empty():
		_show_feedback(CombatSetup.last_result_text, false)
		CombatSetup.last_result_text = ""
	if not RelationsData.retinue_news.is_empty():
		_show_feedback("\n".join(RelationsData.retinue_news), false)
		RelationsData.retinue_news.clear()
	UiAnim.stagger_in(%RootVBox, 0.06)
	# Teclado y mando: izquierda/derecha cambian de pestaña y abajo entra en la lista.
	tabs.get_tab_bar().grab_focus.call_deferred()

func _build_tabs() -> void:
	for entry in TAB_KEYS:
		var scroll := ScrollContainer.new()
		scroll.name = entry[1]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		scroll.add_child(list)
		tabs.add_child(scroll)
		_lists[entry[0]] = list

func _rebuild() -> void:
	var player: Character = GameManager.player_character
	info_label.text = "%s — %s · Oro %d · Honor %d · Fama %d · Acciones %d/%d · Soberano: %s · %s" % [
		player.full_name(), player.role_name(), player.gold, player.honor, player.fame,
		GameManager.actions_remaining, GameManager.actions_per_turn,
		RelationsData.liege_name if player.role != Character.Role.REGENTE else "tú", _marriage_text(player)]

	for list: VBoxContainer in _lists.values():
		for child in list.get_children():
			child.queue_free()

	var area := RelationsData.people_in_area()
	area.sort_custom(func(a: Relationship, b: Relationship) -> bool: return a.affection > b.affection)
	_add_note(_lists.lugar, AREA_TEXT)
	for r: Relationship in area:
		_add_row(_lists.lugar, r)

	var close := RelationsData.close_people()
	close.sort_custom(func(a: Relationship, b: Relationship) -> bool: return a.affection > b.affection)
	if close.is_empty():
		_add_note(_lists.afectos, "Aún no tienes amistades ni amores. Conversa con la gente de tu zona.")
	for r: Relationship in close:
		_add_row(_lists.afectos, r)

	var members := RelationsData.retinue_members()
	_add_note(_lists.sequito, RETINUE_TEXT)
	_add_note(_lists.sequito, "Séquito: %d de %d plazas para un %s." % [members.size(), RelationsData.max_retinue(), player.role_name()], false)
	for r: Relationship in members:
		_add_row(_lists.sequito, r)
	if members.is_empty():
		var lent := RelationsData.battle_companions()
		var names: Array[String] = []
		for c: Character in lent:
			names.append(c.full_name())
		_add_note(_lists.sequito, "Compañeros de facción que te prestaría tu señor: %s." % (", ".join(names) if not names.is_empty() else "ninguno (tu señor no confía en ti)"), false)

	var rivals := RelationsData.duel_rivals()
	if rivals.is_empty():
		_add_note(_lists.rivales, "Aún no te has batido con nadie.")
	for r: Relationship in rivals:
		_add_row(_lists.rivales, r)

	for r: Relationship in RelationsData.lords():
		_add_row(_lists.senores, r)
	_add_note(_lists.senores, RULES_TEXT)

	var lines: Array[String] = []
	for key: String in RelationsData.kingdom_wars.keys():
		lines.append("⚔  %s contra %s (desde hace %d meses)" % [
			_pair_names(key)[0], _pair_names(key)[1], GameManager.months_elapsed() - int(RelationsData.kingdom_wars[key])])
	for key: String in RelationsData.kingdom_alliances.keys():
		lines.append("✦  %s y %s son aliados" % _pair_names(key))
	_add_note(_lists.reinos, "Los reinos están en paz." if lines.is_empty() else "\n".join(lines), false)

	var counts := [area.size(), close.size(), members.size(), rivals.size(), RelationsData.lords().size(), -1]
	for i in TAB_KEYS.size():
		tabs.set_tab_title(i, TAB_KEYS[i][1] + (" (%d)" % counts[i] if counts[i] >= 0 else ""))

func _marriage_text(player: Character) -> String:
	var female := player.gender == CharacterEnums.Gender.FEMENINO
	if not RelationsData.is_married():
		return "Soltera" if female else "Soltero"
	var text := "%s con %s" % ["Casada" if female else "Casado", RelationsData.spouse_name]
	if not RelationsData.spouse_family.is_empty():
		text += " (casa de %s)" % RelationsData.spouse_family
	return text

func _pair_names(key: String) -> Array:
	var parts := key.split("|")
	return [KingdomEnums.kingdom_name(int(parts[0])), KingdomEnums.kingdom_name(int(parts[1]))]

func _add_note(list: VBoxContainer, text: String, muted: bool = true) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if muted:
		lbl.theme_type_variation = &"MutedLabel"
	list.add_child(lbl)

func _add_row(list: VBoxContainer, r: Relationship) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HighlightPanel" if r.person_name in RelationsData.retinue or r.kind == Relationship.Kind.CONYUGE else &"CardPanel"
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	panel.add_child(hbox)

	# La cara abre la ficha completa del personaje (con su retrato entero).
	if r.character != null:
		var face := FaceIcon.make(r.character, FACE_SIZE, FaceIcon.FRAME_COLOR, true, func(): CharacterProfile.open(self, r))
		face.tooltip_text = "Ver ficha de %s" % r.person_name
		face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(face)

	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override("separation", 2)
	var name_lbl := Label.new()
	name_lbl.theme_type_variation = &"BodyBoldLabel"
	name_lbl.text = r.person_name
	if r.person_name == RelationsData.liege_name:
		name_lbl.text += "  — tu soberano"
	if r.person_name == RelationsData.spouse_family:
		name_lbl.text += "  — familia de tu cónyuge"
	if r.person_name in RelationsData.retinue:
		name_lbl.text += "  — tu séquito"
	var detail_lbl := Label.new()
	detail_lbl.theme_type_variation = &"MutedLabel"
	detail_lbl.text = _detail_text(r)
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.add_theme_font_size_override("font_size", 14)
	name_box.add_child(name_lbl)
	name_box.add_child(detail_lbl)
	name_box.add_child(_affinity_row(r) if r.kind == Relationship.Kind.SENOR else _heart_row(r))
	hbox.add_child(name_box)

	# Los botones bajan de línea si no caben, en vez de salirse de la pantalla.
	var buttons := HFlowContainer.new()
	buttons.custom_minimum_size = Vector2(440, 0)
	buttons.alignment = FlowContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	hbox.add_child(buttons)

	if r.kind == Relationship.Kind.SENOR:
		_lord_buttons(buttons, r)
	elif RelationsData.sociable(r):
		_social_buttons(buttons, r)
	list.add_child(panel)

func _lord_buttons(buttons: HFlowContainer, r: Relationship) -> void:
	buttons.add_child(_make_button("Presentes (%d oro)" % RelationsData.GIFT_COST, RelationsData.can_send_gift(r),
		func(): _show_feedback(RelationsData.send_gift(r))))
	if not r.allied:
		buttons.add_child(_make_button("Proponer alianza", RelationsData.can_propose_alliance(r),
			func(): _show_feedback(RelationsData.propose_alliance(r))))
	var player_role: int = GameManager.player_character.role
	if r.at_war:
		buttons.add_child(_make_button("Proponer paz (%d oro)" % RelationsData.PEACE_TRIBUTE, RelationsData.can_propose_peace(r),
			func(): _show_feedback(RelationsData.propose_peace(r))))
	elif player_role >= Character.Role.NOBLEZA_ALTA and not r.allied:
		buttons.add_child(_make_button("Declarar guerra", RelationsData.can_declare_war(r),
			func(): _show_feedback(RelationsData.declare_war(r))))
	if not RelationsData.is_married():
		buttons.add_child(_make_button("Pedir matrimonio (%d oro)" % RelationsData.DOWRY_COST, RelationsData.can_propose_marriage(r),
			func(): _show_feedback(RelationsData.propose_marriage(r))))

func _social_buttons(buttons: HFlowContainer, r: Relationship) -> void:
	buttons.add_child(_make_button("Conversar", RelationsData.can_interact(r, "friendly"),
		func(): _show_feedback(RelationsData.interact(r, "friendly"))))
	buttons.add_child(_make_button("Regalo (%d oro)" % RelationsData.PERSONAL_GIFT_COST, RelationsData.can_interact(r, "gift"),
		func(): _show_feedback(RelationsData.interact(r, "gift"))))
	if RelationsData.romance_possible(r):
		buttons.add_child(_make_button("Gesto íntimo", RelationsData.can_interact(r, "intimate"),
			func(): _show_feedback(RelationsData.interact(r, "intimate"))))
	if r.kind != Relationship.Kind.CONYUGE and RelationsData.in_area(r) and not r.person_name in RelationsData.retinue:
		buttons.add_child(_make_button("Retar a duelo", RelationsData.can_challenge(r), func(): _on_challenge(r)))
	if r.person_name in RelationsData.retinue:
		buttons.add_child(_make_button("Despedir del séquito", "", func(): _show_feedback(RelationsData.dismiss_from_retinue(r))))
	elif RelationsData.max_retinue() > 0:
		buttons.add_child(_make_button("Invitar al séquito", RelationsData.can_invite(r),
			func(): _show_feedback(RelationsData.invite_to_retinue(r))))
	if RelationsData.courtable(r) and r.romance and r.affection >= Relationship.ROMANCE_COURTSHIP:
		var propose := _make_button("Pedir la mano (%d oro)" % RelationsData.WEDDING_COST, RelationsData.can_propose_love(r),
			func(): _show_feedback(RelationsData.propose_love(r)))
		propose.theme_type_variation = &"PrimaryButton"
		buttons.add_child(propose)

func _on_challenge(r: Relationship) -> void:
	var result: Dictionary = RelationsData.challenge(r)
	if not result.get("accepted", false):
		_show_feedback(result.text)
		return
	# Aceptado: al duelo, y al terminar se vuelve a esta pestaña.
	CombatSetup.start_campaign_duel(GameManager.player_character, result.rival)
	CombatSetup.return_scene = "res://scenes/relations/relations.tscn"
	CombatSetup.last_result_text = ""
	RelationsData.requested_tab = TAB_KEYS[tabs.current_tab][0]
	_show_feedback(result.text, false)
	await get_tree().create_timer(1.2).timeout
	get_tree().change_scene_to_file("res://scenes/combat/combat.tscn")

func _affinity_row(r: Relationship) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var bar := ProgressBar.new()
	bar.min_value = -100
	bar.max_value = 100
	bar.value = r.affinity
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(AFFINITY_BAR_WIDTH, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("6b8a2a") if r.affinity >= 0 else Color("a1342a")
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var status_lbl := Label.new()
	status_lbl.text = "%s (%+d)" % [r.status_text(), r.affinity]
	status_lbl.add_theme_font_size_override("font_size", 15)
	row.add_child(status_lbl)
	return row

# Intimidad, romance y rivalidad de un personaje.
func _heart_row(r: Relationship) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.value = r.affection
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(AFFINITY_BAR_WIDTH, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.tooltip_text = "Intimidad %d / 100" % r.affection
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("b0476a") if r.romance else Color("c9a24a")
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var parts: Array[String] = [RelationsData.intimacy_label(r)]
	if r.romance and not r.romance_text().is_empty():
		parts.append("♥ " + r.romance_text())
	if r.kind == Relationship.Kind.RIVAL_DUELO:
		parts.append("⚔ %s (rencor %d)" % [r.rivalry_text(), r.grudge])
	if not r.rival_suitor.is_empty():
		parts.append("Otro pretendiente: %s" % r.rival_suitor)
	var lbl := Label.new()
	lbl.text = "   ·   ".join(parts)
	lbl.add_theme_font_size_override("font_size", 15)
	row.add_child(lbl)
	return row

func _make_button(text: String, disabled_reason: String, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	btn.disabled = not disabled_reason.is_empty()
	btn.tooltip_text = disabled_reason if btn.disabled else "Gasta 1 acción del turno."
	btn.pressed.connect(on_press)
	return btn

func _detail_text(r: Relationship) -> String:
	var c := r.character
	var personality: String = DialogueCatalog.personality_name(c.personality) if c != null else "?"
	match r.kind:
		Relationship.Kind.RIVAL_DUELO:
			return "%s · %s · Duelos: le ganaste %d, te ganó %d" % [c.role_name(), personality, r.duels_won_against, r.duels_lost_against]
		Relationship.Kind.CONYUGE:
			return "Tu cónyuge · %s" % personality
		Relationship.Kind.CORTESANO, Relationship.Kind.PUEBLO:
			return "%s · %s · %s · Combate %d, Defensa %d" % [c.role_name(), personality,
				KingdomEnums.kingdom_name(r.kingdom), c.combat, c.defense]
	var castles := RelationsData.castles_of(r.person_name)
	if castles.is_empty():
		return "Sin tierras: perdió sus castillos"
	var names: Array[String] = []
	for castle: Castle in castles:
		names.append("%s (%s)" % [castle.castle_name, KingdomEnums.kingdom_name(castle.kingdom)])
	return "%s · Gobierna: %s" % [personality, ", ".join(names)]

func _show_feedback(text: String, rebuild: bool = true) -> void:
	feedback_label.text = text
	feedback_panel.visible = not text.is_empty()
	UiAnim.fade_in(feedback_panel, 0.2)
	if rebuild:
		# relations_changed ya reconstruye las filas; las acciones también cambian, así que se refresca el encabezado.
		_rebuild()

func _on_back_pressed() -> void:
	var scene := "res://scenes/map/map.tscn" if GameManager.is_game_active else "res://scenes/main_menu/main_menu.tscn"
	get_tree().change_scene_to_file(scene)
