extends Control

const CharacterProfile = preload("res://scripts/ui/character_profile.gd")
const ConversationPanel = preload("res://scripts/ui/conversation_panel.gd")
const CompanionPanel = preload("res://scripts/ui/companion_panel.gd")
const PrisonersPanel = preload("res://scripts/ui/prisoners_panel.gd")

@onready var info_label: Label = %InfoLabel
@onready var tabs: TabContainer = %Tabs
@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var feedback_label: Label = %FeedbackLabel
@onready var btn_back: Button = %BtnBack

const AFFINITY_BAR_WIDTH := 150
const FACE_SIZE := 64
# [clave, título]: clave es la que usa RelationsData.requested_tab para abrir una pestaña concreta.
const TAB_KEYS := [["lugar", "Tu zona"], ["afectos", "Afectos"], ["sequito", "Séquito"], ["rivales", "Rivales"], ["senores", "Señores"], ["reinos", "Reinos"], ["presos", "Prisioneros"]]
const RULES_TEXT := "Los señores aliados no atacan tus castillos; los hostiles te prefieren como blanco. Atacar o conquistar a un señor empeora la relación. Las alianzas requieren 40 de afinidad y rango de Nobleza. El matrimonio político (afinidad 60, Caballero o más) une a la familia como aliada; casarte con la familia de tu soberano te pone en la línea de sucesión al trono. Marchar contra un señor sin declararle la guerra lo ofende; marchar contra un aliado es traición."
const AREA_TEXT := "Gente del lugar donde estás (viaja para conocer a la de otros reinos): puedes conversar, hacer regalos, invitar al séquito o retar a duelo. Quien te supera mucho en rango solo acepta un reto si tienes fama; quien te teme puede negarse. El romance solo es posible entre un hombre y una mujer, y nace de la confianza: primero la amistad."
const RETINUE_TEXT := "Tu séquito te acompaña a la batalla (cada miembro lidera una unidad) y puede batirse en duelo en tu lugar como campeón. Para que alguien te siga hacen falta %d de intimidad y la fama y el honor que exige su rango; cada miembro cobra %d de oro al mes. Quien te es íntimo (y tu cónyuge) te sigue sea cual sea tu rol, en %d plazas extra. Con «Gestionar» eliges su ocupación del mes, su equipo, tu campeón y duelos de práctica. Si no tienes séquito, tu señor te presta compañeros de tu reino, menos leales." % [RelationsData.RETINUE_MIN_AFFECTION, RelationsData.RETINUE_UPKEEP, RelationsData.INTIMATE_SLOTS]

const LETTER_TEXT := "Con el señor de la tierra donde estás tratas en persona. A los demás solo puedes escribirles (✉): presentes con mensajero, diplomacia y noticias, con una acción más. Pedir una mano exige ir en persona."

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
		player.full_name(), player.role_title(), player.gold, player.honor, player.fame,
		GameManager.actions_remaining, GameManager.actions_per_turn,
		"tú" if player.role == Character.Role.REGENTE else (RelationsData.liege_name if not RelationsData.liege_name.is_empty() else "ninguno"), _marriage_text(player)]

	for list: VBoxContainer in _lists.values():
		for child in list.get_children():
			child.queue_free()

	var area := RelationsData.people_in_area()
	area.sort_custom(func(a: Relationship, b: Relationship) -> bool: return a.affection > b.affection)
	_add_info(_lists.lugar, _zone_heading() + "Conversa, regala, invita o reta.", AREA_TEXT)
	for r: Relationship in area:
		_add_row(_lists.lugar, r)

	var close := RelationsData.close_people()
	close.sort_custom(func(a: Relationship, b: Relationship) -> bool: return a.affection > b.affection)
	if close.is_empty():
		_add_note(_lists.afectos, "Aún no tienes amistades ni amores.")
	for r: Relationship in close:
		_add_row(_lists.afectos, r)

	var members := RelationsData.retinue_members()
	_add_info(_lists.sequito, "Te acompaña a la batalla y lucha por ti.", RETINUE_TEXT)
	var champ := " · Campeón: %s" % RelationsData.designated_champion if not RelationsData.designated_champion.is_empty() else ""
	_add_note(_lists.sequito, "%s%s" % [RelationsData.retinue_slots_text(), champ], false)
	var spouse_rel := RelationsData.spouse_relation() if RelationsData.is_married() else null
	if spouse_rel != null and spouse_rel.character != null and not spouse_rel.person_name in RelationsData.retinue:
		_add_row(_lists.sequito, spouse_rel)
	for r: Relationship in members:
		_add_row(_lists.sequito, r)
	if members.is_empty():
		var lent := RelationsData.battle_companions()
		var names: Array[String] = []
		for c: Character in lent:
			names.append(c.full_name())
		_add_note(_lists.sequito, "Préstamo de tu señor: %s" % (", ".join(names) if not names.is_empty() else "nadie"), false)

	var rivals := RelationsData.duel_rivals()
	if rivals.is_empty():
		_add_note(_lists.rivales, "Aún no te has batido con nadie.")
	for r: Relationship in rivals:
		_add_row(_lists.rivales, r)

	var rank_block := RelationsData.lord_rank_blocker()
	if not rank_block.is_empty():
		_add_info(_lists.senores, "No puedes dirigirte a un señor.", rank_block)
	else:
		_add_info(_lists.senores, "✉ por carta: +1 acción.", LETTER_TEXT)
	var lords := RelationsData.lords()
	lords.sort_custom(func(a: Relationship, b: Relationship) -> bool:
		return RelationsData.lord_present(a) and not RelationsData.lord_present(b))
	for r: Relationship in lords:
		_add_row(_lists.senores, r)
	_add_info(_lists.senores, "Reglas de diplomacia", RULES_TEXT)

	var lines: Array[String] = []
	for key: String in RelationsData.kingdom_wars.keys():
		lines.append("⚔  %s contra %s (desde hace %d meses)" % [
			_pair_names(key)[0], _pair_names(key)[1], GameManager.months_elapsed() - int(RelationsData.kingdom_wars[key])])
	for key: String in RelationsData.kingdom_alliances.keys():
		lines.append("✦  %s y %s son aliados" % _pair_names(key))
	_add_note(_lists.reinos, "Los reinos están en paz." if lines.is_empty() else "\n".join(lines), false)

	PrisonersPanel.fill(_lists.presos, func(text: String): _show_feedback(text))
	var prisoners_count: int = CaptureData.player_prisoners().size() + CaptureData.serfs.size() + CaptureData.held_own_people().size()
	var counts := [area.size(), close.size(), members.size(), rivals.size(), RelationsData.lords().size(), -1, prisoners_count]
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

## «Estás en X (reino)»: la pestaña Tu zona muestra la gente del lugar donde se encuentra el jugador.
func _zone_heading() -> String:
	var here: Castle = TravelData.current_castle()
	if here == null:
		return ""
	var realm := KingdomEnums.kingdom_name(here.kingdom)
	var heading := ("Estás en %s. " % realm) if here.castle_name == realm else "Estás en %s (%s). " % [here.castle_name, realm]
	if here.kingdom == KingdomEnums.Kingdom.NEUTRAL:
		heading += "Tierra sin señor: apenas hay gente. "
	return heading

## Nota corta con «ⓘ»: la explicación completa va en el tooltip (y en el glosario).
func _add_info(list: VBoxContainer, short: String, full: String) -> void:
	var lbl := Label.new()
	lbl.text = short + "  ⓘ"
	lbl.tooltip_text = full
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.theme_type_variation = &"MutedLabel"
	list.add_child(lbl)

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
	if r.person_name == RelationsData.designated_champion:
		name_lbl.text += "  — tu campeón"
	if RelationsData.has_occupation(r):
		name_lbl.text += "  · %s" % RelationsData.OccupationRules.name_of(RelationsData.occupation_of(r))
	if r.kind == Relationship.Kind.SENOR:
		var extra := RelationsData.letter_extra_actions(r)
		name_lbl.text += "  · en estas tierras" if RelationsData.lord_present(r) else \
			("  · ✉ por carta (+%d %s)" % [extra, "acción" if extra == 1 else "acciones"] if extra > 0 else "  · ✉ por carta (sello imperial)")
	elif not RelationsData.person_present(r):
		name_lbl.text += "  · lejos"
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
	var rank_block := RelationsData.lord_rank_blocker()
	if not rank_block.is_empty():
		var lbl := Label.new()
		lbl.theme_type_variation = &"MutedLabel"
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.text = "No puedes dirigirte a un señor."
		lbl.tooltip_text = rank_block
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		buttons.add_child(lbl)
		return
	var cost := 1 + RelationsData.letter_extra_actions(r)
	var letter := "✉ " if not RelationsData.lord_present(r) else ""
	buttons.add_child(_make_button("%sPresentes (%d oro)" % [letter, RelationsData.gift_cost(r)], RelationsData.can_send_gift(r),
		func(): _show_feedback(RelationsData.send_gift(r)), cost))
	if not RelationsData.lord_present(r):
		buttons.add_child(_make_button("✉ Pedir noticias", RelationsData.can_ask_news(r),
			func(): _show_feedback(RelationsData.ask_news(r)), cost))
	if not r.allied:
		buttons.add_child(_make_button(letter + "Proponer alianza", RelationsData.can_propose_alliance(r),
			func(): _show_feedback(RelationsData.propose_alliance(r)), cost))
	var player_role: int = GameManager.player_character.role
	if r.at_war:
		buttons.add_child(_make_button(letter + "Proponer paz (%d oro)" % RelationsData.PEACE_TRIBUTE, RelationsData.can_propose_peace(r),
			func(): _show_feedback(RelationsData.propose_peace(r)), cost))
	elif Character.rank_of(player_role) >= Character.rank_of(Character.Role.NOBLEZA_ALTA) and not r.allied:
		buttons.add_child(_make_button(letter + "Declarar guerra", RelationsData.can_declare_war(r),
			func(): _show_feedback(RelationsData.declare_war(r)), cost))
	if not RelationsData.is_married():
		buttons.add_child(_make_button("Pedir matrimonio (%d oro)" % RelationsData.DOWRY_COST, RelationsData.can_propose_marriage(r),
			func(): _show_feedback(RelationsData.propose_marriage(r))))

func _social_buttons(buttons: HFlowContainer, r: Relationship) -> void:
	buttons.add_child(_make_button("Conversar", RelationsData.can_interact(r, "friendly"), func(): _on_converse(r)))
	buttons.add_child(_make_button("Regalo (%d oro)" % RelationsData.PERSONAL_GIFT_COST, RelationsData.can_interact(r, "gift"),
		func(): _show_feedback(RelationsData.interact(r, "gift"))))
	if r.kind != Relationship.Kind.CONYUGE and RelationsData.in_area(r) and not r.person_name in RelationsData.retinue:
		buttons.add_child(_make_button("Retar a duelo", RelationsData.can_challenge(r), func(): _on_challenge(r)))
	if RelationsData.has_occupation(r):
		var manage := _make_button("Gestionar", "", func(): _on_manage(r))
		manage.tooltip_text = "Ocupación del mes, equipo, campeón y duelo de práctica (no gasta acciones al abrirlo)."
		manage.theme_type_variation = &"PrimaryButton"
		buttons.add_child(manage)
	if r.person_name in RelationsData.retinue:
		buttons.add_child(_make_button("Despedir del séquito", "", func(): _show_feedback(RelationsData.dismiss_from_retinue(r))))
	elif RelationsData.max_retinue() > 0 or RelationsData.is_intimate(r):
		buttons.add_child(_make_button("Invitar al séquito", RelationsData.can_invite(r),
			func(): _show_feedback(RelationsData.invite_to_retinue(r))))
	if RelationsData.courtable(r) and r.romance and r.affection >= Relationship.ROMANCE_COURTSHIP:
		var propose := _make_button("Pedir la mano (%d oro)" % RelationsData.WEDDING_COST, RelationsData.can_propose_love(r),
			func(): _show_feedback(RelationsData.propose_love(r)))
		propose.theme_type_variation = &"PrimaryButton"
		buttons.add_child(propose)

func _on_manage(r: Relationship) -> void:
	var panel := CompanionPanel.open(self, r)
	panel.finished.connect(func(text: String):
		if not text.is_empty():
			_show_feedback(text)
		else:
			_rebuild())

func _on_converse(r: Relationship) -> void:
	var panel := ConversationPanel.open(self, r)
	panel.finished.connect(func(text: String):
		if not text.is_empty():
			_show_feedback(text))

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

func _make_button(text: String, disabled_reason: String, on_press: Callable, actions: int = 1) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	btn.disabled = not disabled_reason.is_empty()
	btn.tooltip_text = disabled_reason if btn.disabled else (
		"Gasta 1 acción del turno." if actions <= 1 else "Por carta: gasta %d acciones del turno." % actions)
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
		names.append(MapData.place_label(castle))
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
