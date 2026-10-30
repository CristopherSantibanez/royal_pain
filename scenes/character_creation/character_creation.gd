extends Control

@onready var portrait_preview: TextureRect = %PortraitPreview
@onready var btn_choose_portrait: Button = %BtnChoosePortrait

@onready var edit_first_name: LineEdit = %EditFirstName
@onready var edit_last_name: LineEdit = %EditLastName
@onready var btn_male: Button = %BtnMale
@onready var btn_female: Button = %BtnFemale

@onready var opt_personality: OptionButton = %OptPersonality
@onready var opt_alignment: OptionButton = %OptAlignment
@onready var opt_fighter_type: OptionButton = %OptFighterType

@onready var points_remaining_label: Label = %PointsRemainingLabel
@onready var stats_grid: GridContainer = %StatsGrid

@onready var advantages_list: VBoxContainer = %AdvantagesList
@onready var lbl_advantages_count: Label = %LblAdvantagesCount
@onready var disadvantages_list: VBoxContainer = %DisadvantagesList
@onready var lbl_disadvantages_count: Label = %LblDisadvantagesCount

@onready var btn_volver_menu: Button = %BtnVolverMenu
@onready var btn_continuar: Button = %BtnContinuar
@onready var btn_aleatorio: Button = %BtnAleatorio

@onready var portrait_popup: PopupPanel = %PortraitPickerPopup
@onready var portrait_grid: GridContainer = %PortraitGrid
@onready var btn_close_popup: Button = %BtnClosePopup

@onready var pages_tab: TabContainer = %PagesTab

@onready var general_skills_list: VBoxContainer = %GeneralSkillsList
@onready var combat_skills_list: VBoxContainer = %CombatSkillsList
@onready var battle_skills_list: VBoxContainer = %BattleSkillsList
@onready var equipment_list: VBoxContainer = %EquipmentList
@onready var lbl_equipment_count: Label = %LblEquipmentCount

@onready var edit_bio: TextEdit = %EditBio

var character: Character
var allocator: PointAllocator

const STAT_LABELS := {
	"leadership": "Liderazgo",
	"charisma": "Carisma",
	"strategy": "Estrategia",
	"combat": "Combate",
	"defense": "Defensa",
	"agility": "Agilidad",
}

var stat_value_labels: Dictionary = {}

func _ready() -> void:
	(func(): UiAnim.focus_first(self)).call_deferred()   # teclado y mando
	_setup_tabs()

	character = Character.new()
	character.traits_locked = false   # los rasgos solo se eligen aquí
	character.gender = CharacterEnums.Gender.MASCULINO
	btn_male.button_pressed = true

	allocator = PointAllocator.new()
	allocator.points_changed.connect(_refresh_stats_ui)
	allocator.points_reset.connect(_on_points_reset)

	edit_first_name.text_changed.connect(_on_first_name_changed)
	edit_last_name.text_changed.connect(_on_last_name_changed)
	btn_male.pressed.connect(func(): _set_gender(CharacterEnums.Gender.MASCULINO))
	btn_female.pressed.connect(func(): _set_gender(CharacterEnums.Gender.FEMENINO))
	btn_choose_portrait.pressed.connect(_open_portrait_picker)
	btn_close_popup.pressed.connect(func(): portrait_popup.hide())
	btn_volver_menu.pressed.connect(_on_volver_menu_pressed)
	edit_bio.text_changed.connect(_on_bio_changed)
	btn_continuar.pressed.connect(_on_continuar_pressed)
	btn_aleatorio.pressed.connect(_randomize_all)

	_populate_personality_options()
	_populate_alignment_options()
	_populate_fighter_type_options()
	_build_stats_grid()
	_build_traits_lists()
	_build_equipment_list()
	

	opt_personality.item_selected.connect(_on_personality_or_alignment_changed)
	opt_alignment.item_selected.connect(_on_personality_or_alignment_changed)
	opt_fighter_type.item_selected.connect(_on_personality_or_alignment_changed)

	_refresh_portrait_preview()
	_recalculate_points()
	_build_skills_lists()
	_update_continue_button()
	if CreationState.edit_character != null:
		_load_for_edit(CreationState.edit_character)

# --- Editar un personaje guardado (Mis personajes) ---
# Rellena los mismos controles de la interfaz, así se respetan las reglas de creación.

func _load_for_edit(c: Character) -> void:
	var gender := c.gender
	(btn_male if gender == CharacterEnums.Gender.MASCULINO else btn_female).button_pressed = true
	_set_gender(gender)
	edit_first_name.text = c.first_name
	_on_first_name_changed(c.first_name)
	edit_last_name.text = c.last_name
	_on_last_name_changed(c.last_name)
	if c.portrait != null:
		_select_portrait(c.portrait)
	for pair in [[opt_personality, c.personality], [opt_alignment, c.alignment], [opt_fighter_type, c.fighter_type]]:
		var opt: OptionButton = pair[0]
		var idx := opt.get_item_index(int(pair[1]))
		if idx >= 0:
			opt.select(idx)
	_recalculate_points()
	# Las ventajas, desventajas y el equipo ya sumaron sus modificadores: se descuentan.
	var mods := {}
	for item in c.advantages + c.disadvantages + c.equipment:
		for key: String in STAT_LABELS:
			mods[key] = int(mods.get(key, 0)) + int(item.get(key + "_mod"))
	for key: String in STAT_LABELS:
		var target := int(c.get(key)) - int(mods.get(key, 0))
		while allocator.current_value(key) < target and allocator.can_increase(key):
			allocator.increase(key)
	var wanted := {}
	for item in c.advantages + c.disadvantages:
		wanted[item.trait_name] = true
	for list: Container in [advantages_list, disadvantages_list]:
		for cb: CheckBox in list.find_children("*", "CheckBox", true, false):
			if wanted.has(cb.text) and not cb.button_pressed:
				cb.button_pressed = true
	_build_skills_lists()
	for i in _tree_options.size():
		var opt: Dictionary = _tree_options[i]
		for id in opt.ids:
			if id in c.learned_skills:
				_select_basic(i, str(id))
	var names := {}
	for e: Equipment in c.equipment:
		names[e.equipment_name] = true
	for slot: String in _gear_buttons:
		var ob: OptionButton = _gear_buttons[slot]
		for k in ob.item_count:
			if names.has(str(ob.get_item_metadata(k))):
				ob.select(k)
	_apply_gear()
	edit_bio.text = c.biography
	_on_bio_changed()
	character.role = c.role
	_update_continue_button()

func _setup_tabs() -> void:
	pages_tab.set_tab_title(0, "Personaje")
	pages_tab.set_tab_title(1, "Rasgos")
	pages_tab.set_tab_title(2, "Estadísticas e identidad")
	pages_tab.set_tab_title(3, "Habilidades")
	pages_tab.set_tab_title(4, "Equipo")

# --- Identidad ---

func _on_first_name_changed(text: String) -> void:
	character.first_name = text
	_update_continue_button()

func _on_last_name_changed(text: String) -> void:
	character.last_name = text

func _set_gender(gender: int) -> void:
	character.gender = gender
	character.portrait = null
	_refresh_portrait_preview()

func _refresh_portrait_preview() -> void:
	portrait_preview.texture = character.get_portrait()

func _open_portrait_picker() -> void:
	_populate_portrait_grid()
	portrait_popup.popup_centered()

func _populate_portrait_grid() -> void:
	for child in portrait_grid.get_children():
		child.queue_free()

	var paths := PortraitGallery.get_portraits_for_gender(character.gender)

	if paths.is_empty():
		var lbl := Label.new()
		lbl.text = "Aún no hay retratos disponibles para este sexo.\nAgrega imágenes en assets/portraits/characters/."
		portrait_grid.add_child(lbl)
		return

	for path in paths:
		var tex: Texture2D = load(path)
		var btn := TextureButton.new()
		btn.texture_normal = tex
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = Vector2(100, 150)
		btn.pressed.connect(func(): _select_portrait(tex))
		portrait_grid.add_child(btn)

func _select_portrait(tex: Texture2D) -> void:
	character.portrait = tex
	_refresh_portrait_preview()
	portrait_popup.hide()

# --- Personalidad / Alineación / Tipo de Luchador ---

var personality_desc: Label

func _populate_personality_options() -> void:
	opt_personality.clear()
	for p in Character.Personality.values():
		opt_personality.add_item(DialogueCatalog.personality_name(p), p)
	# Descripción de la personalidad elegida, bajo el desplegable.
	if personality_desc == null:
		personality_desc = Label.new()
		personality_desc.theme_type_variation = &"InkLabel"
		personality_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		personality_desc.custom_minimum_size = Vector2(220, 0)
		personality_desc.add_theme_font_size_override("font_size", 14)
		opt_personality.get_parent().add_child(personality_desc)
		opt_personality.item_selected.connect(func(_i): _refresh_personality_desc())
	_refresh_personality_desc()

func _refresh_personality_desc() -> void:
	if personality_desc != null and opt_personality.selected >= 0:
		personality_desc.text = DialogueCatalog.personality_description(opt_personality.get_selected_id())

func _populate_alignment_options() -> void:
	opt_alignment.clear()
	opt_alignment.add_item("Conquistador", CharacterEnums.Alignment.CONQUISTADOR)
	opt_alignment.add_item("Pacifista", CharacterEnums.Alignment.PACIFISTA)
	opt_alignment.add_item("Ambicioso", CharacterEnums.Alignment.AMBICIOSO)
	opt_alignment.add_item("Humilde", CharacterEnums.Alignment.HUMILDE)
	opt_alignment.add_item("Diplomático", CharacterEnums.Alignment.DIPLOMATICO)
	opt_alignment.add_item("Tirano", CharacterEnums.Alignment.TIRANO)

func _populate_fighter_type_options() -> void:
	opt_fighter_type.clear()
	opt_fighter_type.add_item("Duelista", CharacterEnums.FighterType.DUELISTA)
	opt_fighter_type.add_item("Tanque", CharacterEnums.FighterType.TANQUE)
	opt_fighter_type.add_item("Estratega", CharacterEnums.FighterType.ESTRATEGA)
	opt_fighter_type.add_item("Berserker", CharacterEnums.FighterType.BERSERKER)
	opt_fighter_type.add_item("Defensor", CharacterEnums.FighterType.DEFENSOR)
	opt_fighter_type.add_item("Asesino", CharacterEnums.FighterType.ASESINO)

func _on_personality_or_alignment_changed(_index: int) -> void:
	_recalculate_points()
	_build_skills_lists()   # cambian los árboles: se vuelven a elegir las básicas

func _recalculate_points() -> void:
	character.personality = opt_personality.get_selected_id()
	character.alignment = opt_alignment.get_selected_id()
	character.fighter_type = opt_fighter_type.get_selected_id()
	allocator.setup(character.personality, character.alignment, character.fighter_type)

func _on_points_reset() -> void:
	print("Los puntos se reiniciaron por el cambio de personalidad/alineación/tipo de luchador.")

# --- Reparto de Stats ---

func _build_stats_grid() -> void:
	for child in stats_grid.get_children():
		child.queue_free()
	stat_value_labels.clear()

	for stat_key in Character.ATTRIBUTES:
		var name_label := Label.new()
		name_label.text = STAT_LABELS[stat_key]
		name_label.custom_minimum_size = Vector2(100, 0)
		name_label.add_theme_color_override("font_color", Color(0.01, 0.008, 0.002, 1.0)) # dorado suave
		stats_grid.add_child(name_label)

		var btn_minus := Button.new()
		btn_minus.text = "-"
		btn_minus.custom_minimum_size = Vector2(32, 0)
		btn_minus.pressed.connect(func(): _on_stat_button_pressed(stat_key, false))
		stats_grid.add_child(btn_minus)

		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(30, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.add_theme_color_override("font_color", Color.BLACK)
		stats_grid.add_child(value_label)
		stat_value_labels[stat_key] = value_label

		var btn_plus := Button.new()
		btn_plus.text = "+"
		btn_plus.custom_minimum_size = Vector2(32, 0)
		btn_plus.pressed.connect(func(): _on_stat_button_pressed(stat_key, true))
		stats_grid.add_child(btn_plus)

func _on_stat_button_pressed(stat_key: String, increase: bool) -> void:
	if increase:
		allocator.increase(stat_key)
	else:
		allocator.decrease(stat_key)

func _refresh_stats_ui() -> void:
	points_remaining_label.text = "Puntos disponibles: %d / %d" % [allocator.points_remaining(), allocator.total_points]
	for stat_key in stat_value_labels.keys():
		stat_value_labels[stat_key].text = str(allocator.current_value(stat_key))

# --- Ventajas / Desventajas ---

func _build_traits_lists() -> void:
	for child in advantages_list.get_children():
		child.queue_free()
	for child in disadvantages_list.get_children():
		child.queue_free()

	for t: CharacterTrait in GameData.advantages:
		var cb := _make_trait_checkbox(t)
		cb.toggled.connect(func(pressed: bool): _on_advantage_toggled(t, pressed))
		_add_entry(advantages_list, cb, _trait_text(t))

	for t: CharacterTrait in GameData.disadvantages:
		var cb := _make_trait_checkbox(t)
		cb.toggled.connect(func(pressed: bool): _on_disadvantage_toggled(t, pressed))
		_add_entry(disadvantages_list, cb, _trait_text(t))

	_refresh_traits_count()

func _make_trait_checkbox(t: CharacterTrait) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = t.trait_name
	cb.tooltip_text = t.description
	cb.add_theme_color_override("font_color", Color.BLACK)
	return cb

func _trait_text(t: CharacterTrait) -> String:
	var mods := GameData.effect_summary(t.trait_name)
	return t.description + (" (%s)" % mods if not mods.is_empty() else "")

# Cada opción va con su efecto escrito debajo, a la vista (no solo en el tooltip).
func _add_entry(container: Container, cb: CheckBox, description: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(cb)
	var desc := Label.new()
	desc.theme_type_variation = &"InkLabel"
	desc.text = description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(200, 0)
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.24, 0.16, 0.1, 0.85))
	desc.add_theme_constant_override("line_spacing", 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_child(desc)
	box.add_child(margin)
	container.add_child(box)

func _add_header(container: Container, text: String) -> void:
	var header := Label.new()
	header.theme_type_variation = &"InkHeaderLabel"
	header.text = text
	header.add_theme_font_size_override("font_size", 15)
	container.add_child(header)

func _on_advantage_toggled(t: CharacterTrait, pressed: bool) -> void:
	if pressed:
		if character.advantages.size() >= Character.MAX_ADVANTAGES or not character.add_trait(t):
			_uncheck(advantages_list, t.trait_name)
	else:
		character.remove_trait(t)
	_refresh_traits_count()

func _uncheck(list: Container, trait_name: String) -> void:
	for cb: CheckBox in list.find_children("*", "CheckBox", true, false):
		if cb.text == trait_name:
			cb.set_pressed_no_signal(false)

func _on_disadvantage_toggled(t: CharacterTrait, pressed: bool) -> void:
	if pressed:
		character.add_trait(t)
	else:
		character.remove_trait(t)
	_refresh_traits_count()

func _refresh_traits_count() -> void:
	lbl_advantages_count.text = "Elegidas: %d / máximo %d" % [character.advantages.size(), Character.MAX_ADVANTAGES]
	lbl_disadvantages_count.text = "Elegidas: %d / mínimo %d" % [character.disadvantages.size(), Character.MIN_DISADVANTAGES]
	_update_continue_button()

# --- Validación general ---

func _update_continue_button() -> void:
	var result := character.is_creation_valid()
	btn_continuar.disabled = not result.valid
	btn_continuar.tooltip_text = "" if result.valid else "\n".join(result.errors)

func _on_volver_menu_pressed() -> void:
	CreationState.clear_edit()
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

# --- Habilidades: una básica por rama de cada árbol (personalidad, alineación y tipo de luchador) ---

var _tree_options: Array = []      # [{"tree", "branch", "ids"}] en orden: árbol por árbol
var _basic_buttons: Array = []     # OptionButton por rama (mismo índice que _tree_options)

func _build_skills_lists() -> void:
	var lists: Array = [general_skills_list, combat_skills_list, battle_skills_list]
	for list: Container in lists:
		for child in list.get_children():
			child.queue_free()
	character.learned_skills.clear()
	_basic_buttons.clear()
	_tree_options = character.basic_tree_options()
	if _tree_options.is_empty():
		_add_header(general_skills_list, "Árboles no disponibles")
		_update_continue_button()
		return
	var tree_index := -1
	var last_tree := ""
	for i in _tree_options.size():
		var opt: Dictionary = _tree_options[i]
		if opt.tree != last_tree:
			last_tree = opt.tree
			tree_index = mini(tree_index + 1, lists.size() - 1)
			var title := (lists[tree_index] as Node).get_parent().get_parent().get_child(0)
			if title is Label:
				title.text = opt.tree
		var list: Container = lists[tree_index]
		var lbl := Label.new()
		lbl.theme_type_variation = &"InkLabel"
		lbl.text = opt.branch
		list.add_child(lbl)
		var ob := OptionButton.new()
		ob.add_item("—")
		ob.set_item_metadata(0, "")
		for id in opt.ids:
			var n: Dictionary = SkillTreeCatalog.node(str(id))
			ob.add_item(str(n.get("name", id)))
			ob.set_item_metadata(ob.item_count - 1, str(id))
			ob.set_item_tooltip(ob.item_count - 1, str(n.get("desc", "")))
		ob.item_selected.connect(func(k: int): _on_basic_selected(i, str(ob.get_item_metadata(k))))
		list.add_child(ob)
		_basic_buttons.append(ob)
	_update_continue_button()

func _on_basic_selected(index: int, id: String) -> void:
	character.choose_basic(_tree_options[index], id)
	_update_continue_button()

func _select_basic(index: int, id: String) -> void:
	var ob: OptionButton = _basic_buttons[index]
	for k in ob.item_count:
		if str(ob.get_item_metadata(k)) == id:
			ob.select(k)
	_on_basic_selected(index, id)

# --- Equipo inicial: un arma (tipo de daño), un escudo o ninguno, una armadura y un accesorio (+1) ---

var _gear_buttons: Dictionary = {}   # ranura -> OptionButton (metadata: nombre de la pieza)

func _build_equipment_list() -> void:
	for child in equipment_list.get_children():
		child.queue_free()
	_gear_buttons.clear()
	var CC = GameData.ContentCatalog
	var accessories := {}
	for stat: String in CC.CREATION_ACCESSORIES:
		accessories["%s +1" % STAT_LABELS.get(stat, stat)] = CC.CREATION_ACCESSORIES[stat]
	var shields := {"Sin escudo": ""}
	for n: String in CC.CREATION_SHIELDS:
		shields[n] = n
	for row in [["Arma", CC.SLOT_ARMA, CC.CREATION_WEAPONS], ["Escudo", CC.SLOT_ESCUDO, shields],
			["Armadura", CC.SLOT_ARMADURA, CC.CREATION_ARMORS], ["Accesorio", CC.SLOT_ACCESORIO, accessories]]:
		_add_header(equipment_list, row[0])
		var ob := OptionButton.new()
		var choices: Dictionary = row[2]
		for label: String in choices:
			var item_name: String = choices[label]
			ob.add_item(label if item_name.is_empty() or label == item_name else "%s · %s" % [label, item_name])
			ob.set_item_metadata(ob.item_count - 1, item_name)
			var e := _catalog_item(item_name)
			if e != null:
				ob.set_item_tooltip(ob.item_count - 1, e.description)
		ob.item_selected.connect(func(_k: int): _apply_gear())
		equipment_list.add_child(ob)
		_gear_buttons[row[1]] = ob
	(_gear_buttons[CC.SLOT_ARMADURA] as OptionButton).select(1)   # Cuero por defecto
	_apply_gear()

func _catalog_item(item_name: String) -> Equipment:
	for e: Equipment in GameData.equipment_catalog:
		if e.equipment_name == item_name:
			return e
	return null

func _apply_gear() -> void:
	character.equipment.clear()
	for slot: String in _gear_buttons:
		var ob: OptionButton = _gear_buttons[slot]
		var e := _catalog_item(str(ob.get_item_metadata(ob.selected)))
		if e != null:
			character.equipment.append(e)
	_refresh_equipment_count()
	_update_continue_button()

func _refresh_equipment_count() -> void:
	lbl_equipment_count.text = "Un arma, una armadura, un accesorio y, si quieres, un escudo."

func _on_bio_changed() -> void:
	character.biography = edit_bio.text
	
func _on_continuar_pressed() -> void:
	allocator.apply_to_character(character)
	character.apply_trait_and_equipment_modifiers()
	character.traits_locked = true   # desde aquí, los rasgos no cambian
	CreationState.pending_character = character
	get_tree().change_scene_to_file("res://scenes/character_summary/character_summary.tscn")

# --- Personaje aleatorio ---
# Rellena todos los campos usando los mismos controles de la interfaz, así se respetan
# las mismas reglas (puntos, mínimos de rasgos, máximo de equipo) y el jugador puede retocarlo.

const RANDOM_BIOS := [
	"Hijo de una familia humilde, creció entre campos y caminos soñando con algo más.",
	"Sobrevivió a una peste que se llevó a los suyos y juró no volver a ser débil.",
	"Sirvió como escudero de un caballero caído en desgracia, y aprendió de sus errores.",
	"Vendió todo lo que tenía para comprar una espada y un nombre.",
	"Creció en la corte, entre intrigas, y aprendió pronto en quién no confiar.",
	"Peregrinó durante años antes de volver a su tierra con nuevas ambiciones.",
]

func _randomize_all() -> void:
	# Identidad
	var gender: int = [CharacterEnums.Gender.MASCULINO, CharacterEnums.Gender.FEMENINO].pick_random()
	if gender == CharacterEnums.Gender.MASCULINO:
		btn_male.button_pressed = true
	else:
		btn_female.button_pressed = true
	_set_gender(gender)
	edit_first_name.text = CharacterLoader.random_first_name(gender)
	_on_first_name_changed(edit_first_name.text)
	edit_last_name.text = CharacterLoader.random_last_name()
	_on_last_name_changed(edit_last_name.text)
	var portraits := PortraitGallery.get_portraits_for_gender(gender)
	if not portraits.is_empty():
		_select_portrait(load(portraits.pick_random()))

	# Personalidad, alineación y tipo de luchador (reinician el reparto de puntos)
	for opt: OptionButton in [opt_personality, opt_alignment, opt_fighter_type]:
		opt.select(randi() % opt.item_count)
	_recalculate_points()
	var stat_keys := STAT_LABELS.keys()
	while allocator.points_remaining() > 0:
		var possible := stat_keys.filter(func(k): return allocator.can_increase(k))
		if possible.is_empty():
			break
		allocator.increase(possible.pick_random())

	# Rasgos, habilidades y equipo
	_randomize_checkboxes(advantages_list, Character.MAX_ADVANTAGES)
	_randomize_checkboxes(disadvantages_list, Character.MIN_DISADVANTAGES)
	_build_skills_lists()   # el árbol depende de personalidad, alineación y tipo
	for i in _tree_options.size():
		var ids: Array = _tree_options[i].ids
		if not ids.is_empty():
			_select_basic(i, str(ids.pick_random()))
	for ob: OptionButton in _gear_buttons.values():
		ob.select(randi() % ob.item_count)
	_apply_gear()

	edit_bio.text = RANDOM_BIOS.pick_random()
	_on_bio_changed()
	_update_continue_button()

func _randomize_checkboxes(list: Container, count: int) -> void:
	var boxes: Array = []
	for child in list.find_children("*", "CheckBox", true, false):
		if not child.is_queued_for_deletion():
			boxes.append(child)
	# Primero se desmarcan todas (los handlers quitan cada elemento del personaje)...
	for cb: CheckBox in boxes:
		if cb.button_pressed:
			cb.button_pressed = false
	# ...y luego se marcan al azar las necesarias.
	boxes.shuffle()
	for cb: CheckBox in boxes.slice(0, mini(count, boxes.size())):
		cb.button_pressed = true
	_refresh_personality_desc()
