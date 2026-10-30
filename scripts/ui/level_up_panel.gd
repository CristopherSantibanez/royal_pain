extends Control
# Ventana de nivel y familia del jugador.
#   Nivel: experiencia, reparto de puntos de atributo (se aplican al confirmar) y elección de habilidad.
#   Familia: cónyuge e hijos (edad, rasgos heredados; los adultos pueden heredar).
# Uso: const LevelUpPanel = preload("res://scripts/ui/level_up_panel.gd"); LevelUpPanel.open(nodo)

const STATS := Character.ATTRIBUTES
const STAT_MIN := 1
const STAT_MAX := 20
const SKILL_OFFER_SIZE := 3
const XpRulesRef = preload("res://scripts/resources/xp_rules.gd")

var _player: Character
var _added := {}                  # atributo -> puntos añadidos sin confirmar
var _level_box: VBoxContainer
var _family_box: VBoxContainer
var _feedback: Label
var _tabs: TabContainer

static func open(host: Node) -> Control:
	var panel: Control = load("res://scripts/ui/level_up_panel.gd").new()
	host.add_child(panel)
	return panel

func _ready() -> void:
	_player = GameManager.player_character
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
	panel.custom_minimum_size = Vector2(680, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 470)
	box.add_child(_tabs)
	_level_box = _tab_page("Nivel")
	_family_box = _tab_page("Familia")

	_feedback = Label.new()
	_feedback.theme_type_variation = &"BodyBoldLabel"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.visible = false
	box.add_child(_feedback)

	var close := Button.new()
	close.text = "Cerrar"
	close.theme_type_variation = &"FlatButton"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(180, 0)
	close.pressed.connect(queue_free)
	box.add_child(close)

	_rebuild_level()
	_rebuild_family()
	UiAnim.fade_in(panel, 0.15)
	UiAnim.focus_first(_level_box)

func _tab_page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)
	return page

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _label(text: String, variation: StringName = &"", size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l

# --- Nivel ---

func _points_left() -> int:
	var used := 0
	for k in _added:
		used += _added[k]
	return _player.unspent_points - used

func _rebuild_level() -> void:
	_clear(_level_box)
	if _player == null:
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(FaceIcon.make(_player, 64))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_label("%s · Nivel %d" % [_player.full_name(), _player.level], &"SubheaderLabel"))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	if _player.level >= Character.MAX_LEVEL:
		bar.max_value = 1
		bar.value = 1
		info.add_child(bar)
		info.add_child(_label("Has alcanzado el nivel máximo.", &"MutedLabel", 15))
	else:
		bar.max_value = _player.xp_to_next()
		bar.value = _player.xp
		info.add_child(bar)
		info.add_child(_label("Experiencia: %d / %d · %d años" % [_player.xp, _player.xp_to_next(), _player.age], &"MutedLabel", 15))
	var affinity := XpRulesRef.affinity_text(_player.fighter_type)
	if not affinity.is_empty():
		var aff := _label("Como %s: %s" % [CharacterEnums.fighter_type_name(_player.fighter_type), affinity], &"MutedLabel", 14)
		aff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(aff)
	head.add_child(info)
	_level_box.add_child(head)
	_level_box.add_child(HSeparator.new())

	var left := _points_left()
	_level_box.add_child(_label("Puntos por repartir: %d" % left if _player.unspent_points > 0
		else "Sin puntos por repartir.",
		&"BodyBoldLabel" if _player.unspent_points > 0 else &"MutedLabel"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	for stat: String in STATS:
		var name_lbl := _label(GameData.STAT_LABELS[stat])
		name_lbl.custom_minimum_size = Vector2(150, 0)
		grid.add_child(name_lbl)
		var value: int = _player.get(stat) + _added.get(stat, 0)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(40, 0)
		minus.disabled = _added.get(stat, 0) <= 0
		minus.pressed.connect(_change.bind(stat, -1))
		grid.add_child(minus)
		var val := _label(str(value) + (" (+%d)" % _added[stat] if _added.get(stat, 0) > 0 else ""), &"BodyBoldLabel")
		val.custom_minimum_size = Vector2(70, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(val)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(40, 0)
		plus.disabled = left <= 0 or value >= STAT_MAX
		plus.pressed.connect(_change.bind(stat, 1))
		grid.add_child(plus)
	_level_box.add_child(grid)
	if _player.unspent_points > 0:
		var confirm := Button.new()
		confirm.text = "Confirmar reparto"
		confirm.theme_type_variation = &"PrimaryButton"
		confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		confirm.disabled = left == _player.unspent_points
		confirm.pressed.connect(_confirm_points)
		_level_box.add_child(confirm)

	# Habilidades: se aprenden en los árboles (un punto cada SKILL_EVERY_LEVELS niveles).
	_level_box.add_child(HSeparator.new())
	if ResourceLoader.exists(SKILL_TREE_PANEL):
		var trees := Button.new()
		trees.text = "Árbol de habilidades"
		trees.tooltip_text = "Un punto de habilidad cada %d niveles." % Character.SKILL_EVERY_LEVELS
		trees.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		trees.pressed.connect(_open_skill_tree)
		_level_box.add_child(trees)
	else:
		_level_box.add_child(_label("Un punto de habilidad cada %d niveles." % Character.SKILL_EVERY_LEVELS, &"MutedLabel", 15))

const SKILL_TREE_PANEL := "res://scripts/ui/skill_tree_panel.gd"

func _open_skill_tree() -> void:
	var script: Script = load(SKILL_TREE_PANEL)
	if script == null:
		return
	if script.get_script_method_list().any(func(m): return m.name == "open"):
		script.call("open", get_parent())
	else:
		var panel: Node = script.new()
		get_parent().add_child(panel)

func _change(stat: String, delta: int) -> void:
	var now: int = _added.get(stat, 0) + delta
	var value: int = _player.get(stat) + now
	if now < 0 or value < STAT_MIN or value > STAT_MAX or (delta > 0 and _points_left() <= 0):
		return
	_added[stat] = now
	_rebuild_level()
	_refocus_stat(stat, delta)

func _refocus_stat(stat: String, delta: int) -> void:
	# Tras reconstruir, el foco vuelve al mismo botón (para teclado y mando).
	var grid: GridContainer = null
	for c in _level_box.get_children():
		if c is GridContainer:
			grid = c
	if grid == null:
		return
	var idx := STATS.find(stat) * 4 + (3 if delta > 0 else 1)
	var b := grid.get_child(idx) as Button
	if b != null and not b.disabled:
		b.grab_focus()
	else:
		UiAnim.focus_first(grid)

func _confirm_points() -> void:
	var parts: Array[String] = []
	for stat in _added:
		if _added[stat] > 0:
			_player.set(stat, clampi(_player.get(stat) + _added[stat], STAT_MIN, STAT_MAX))
			_player.unspent_points -= _added[stat]
			parts.append("%s +%d" % [GameData.STAT_LABELS[stat], _added[stat]])
	_added.clear()
	_show("Repartes tus puntos: %s." % ", ".join(parts))
	_rebuild_level()
	UiAnim.focus_first(_level_box)

func _owns(c: Character, skill_name: String) -> bool:
	for list in [c.general_skills, c.combat_skills, c.battle_skills]:
		for s: Skill in list:
			if s.skill_name == skill_name:
				return true
	return false

## Tres habilidades que aún no tienes, mezclando categorías. La oferta es fija para cada nivel
## (cerrar y volver a abrir no la cambia).
func _skill_offer() -> Array[Skill]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|%d" % [_player.full_name(), _player.level, _player.pending_skill_choices])
	var pools: Array = []
	for pool in [GameData.general_skills, GameData.combat_skills, GameData.battle_skills]:
		var free: Array = pool.filter(func(s: Skill) -> bool: return not _owns(_player, s.skill_name))
		if not free.is_empty():
			pools.append(free)
	var offer: Array[Skill] = []
	var guard := 0
	while offer.size() < SKILL_OFFER_SIZE and not pools.is_empty() and guard < 50:
		guard += 1
		var pool: Array = pools[rng.randi() % pools.size()]
		var s: Skill = pool[rng.randi() % pool.size()]
		if not s in offer:
			offer.append(s)
		if pools.all(func(p: Array) -> bool: return p.all(func(x: Skill) -> bool: return x in offer)):
			break
	return offer

func _category_name(cat: int) -> String:
	match cat:
		CharacterEnums.SkillCategory.COMBATE: return "Combate"
		CharacterEnums.SkillCategory.BATALLA: return "Batalla"
	return "General"

func _pick_skill(s: Skill) -> void:
	if _player.pending_skill_choices <= 0 or _owns(_player, s.skill_name):
		return
	match s.category:
		CharacterEnums.SkillCategory.COMBATE: _player.combat_skills.append(s)
		CharacterEnums.SkillCategory.BATALLA: _player.battle_skills.append(s)
		_: _player.general_skills.append(s)
	_player.pending_skill_choices -= 1
	_show("Aprendes «%s»." % s.skill_name)
	_rebuild_level()
	UiAnim.focus_first(_level_box)

# --- Familia ---

func _rebuild_family() -> void:
	_clear(_family_box)
	if _player == null:
		return
	var spouses := RelationsData.spouse_relations()
	if not spouses.is_empty():
		_family_box.add_child(_label("Cónyuges (%d/%d)" % [spouses.size(), RelationsData.max_spouses(_player)], &"SubheaderLabel"))
		for spouse: Relationship in spouses:
			_family_box.add_child(_person_row(spouse.character, spouse.person_name,
				"Principal · " + LoyaltyData.bar_text(spouse.person_name) if spouse.person_name == RelationsData.spouse_name else LoyaltyData.bar_text(spouse.person_name)))
		for lover: Relationship in RelationsData.concubine_relations():
			_family_box.add_child(_person_row(lover.character, lover.person_name, "Amante · " + LoyaltyData.bar_text(lover.person_name)))
	else:
		_family_box.add_child(_label("Sin cónyuge." , &"MutedLabel"))
	_family_box.add_child(HSeparator.new())
	var kids := DynastyData.children()
	var own := kids.filter(func(c: Character) -> bool: return DynastyData.is_own_child(c)).size()
	var heading := "Hijos (%d)" % own
	if own < kids.size():
		heading += " · Hermanos (%d)" % (kids.size() - own)
	_family_box.add_child(_label(heading, &"SubheaderLabel"))
	if kids.is_empty():
		_family_box.add_child(_label("Sin descendencia.", &"MutedLabel", 15))
	for c: Character in kids:
		var fem := c.gender == CharacterEnums.Gender.FEMENINO
		var status := ("Adulta · puede heredar" if fem else "Adulto · puede heredar") if c.age >= DynastyData.ADULT_AGE \
			else "Mayor de edad en %d %s" % [DynastyData.ADULT_AGE - c.age, "año" if DynastyData.ADULT_AGE - c.age == 1 else "años"]
		if DynastyData.is_natural(c):
			status = "Bastard%s · %s" % ["a" if fem else "o", status]
		if not DynastyData.is_own_child(c):
			status = ("Tu hermana · " if fem else "Tu hermano · ") + status
		_family_box.add_child(_person_row(c, c.full_name(), status))

func _person_row(c: Character, display_name: String, status: String) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	if c != null:
		row.add_child(FaceIcon.make(c, 52, FaceIcon.FRAME_COLOR, c.portrait != null))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var age_txt := " · %d años" % c.age if c != null else ""
	info.add_child(_label(display_name + age_txt, &"BodyBoldLabel"))
	if c != null:
		var traits: Array[String] = []
		for t: CharacterTrait in c.advantages:
			traits.append(t.trait_name)
		var line := "%s · Liderazgo %d · Carisma %d · Estrategia %d · Combate %d · Defensa %d · Agilidad %d" % [
			_personality(c), c.leadership, c.charisma, c.strategy, c.combat, c.defense, c.agility]
		if not traits.is_empty():
			line += "\nVentajas: " + ", ".join(traits)
		info.add_child(_label(line, &"MutedLabel", 14))
	if not status.is_empty():
		info.add_child(_label(status, &"", 14))
	row.add_child(info)
	return card

## Nombre de la personalidad concordado con el género (Ambicioso → Ambiciosa).
static func _personality(c: Character) -> String:
	var n := DialogueCatalog.personality_name(c.personality)
	if c.gender == CharacterEnums.Gender.FEMENINO and n.ends_with("o"):
		n = n.left(-1) + "a"
	return n

func _show(text: String) -> void:
	_feedback.text = text
	_feedback.visible = not text.is_empty()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
