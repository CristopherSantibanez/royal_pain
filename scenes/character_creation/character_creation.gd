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
}

var stat_value_labels: Dictionary = {}

func _ready() -> void:
	_setup_tabs()

	character = Character.new()
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

	_populate_personality_options()
	_populate_alignment_options()
	_populate_fighter_type_options()
	_build_stats_grid()
	_build_traits_lists()
	_build_skills_lists()
	_build_equipment_list()
	

	opt_personality.item_selected.connect(_on_personality_or_alignment_changed)
	opt_alignment.item_selected.connect(_on_personality_or_alignment_changed)
	opt_fighter_type.item_selected.connect(_on_personality_or_alignment_changed)

	_refresh_portrait_preview()
	_recalculate_points()
	_update_continue_button()

func _setup_tabs() -> void:
	pages_tab.set_tab_title(0, "Personaje")
	pages_tab.set_tab_title(1, "Rasgos")
	pages_tab.set_tab_title(2, "Estadísticas e identidad")
	pages_tab.set_tab_title(3, "Habilidades")
	pages_tab.set_tab_title(4, "Equipamientos")

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

func _populate_personality_options() -> void:
	opt_personality.clear()
	opt_personality.add_item("Ambicioso", Character.Personality.AMBICIOSO)
	opt_personality.add_item("Leal", Character.Personality.LEAL)
	opt_personality.add_item("Prudente", Character.Personality.PRUDENTE)
	opt_personality.add_item("Arrogante", Character.Personality.ARROGANTE)
	opt_personality.add_item("Piadoso", Character.Personality.PIADOSO)
	opt_personality.add_item("Astuto", Character.Personality.ASTUTO)

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

	for stat_key in ["leadership", "charisma", "strategy", "combat", "defense"]:
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

	print("Advantages en GameData: ", GameData.advantages.size())
	print("Disadvantages en GameData: ", GameData.disadvantages.size())

	for t: CharacterTrait in GameData.advantages:
		var cb := _make_trait_checkbox(t)
		cb.toggled.connect(func(pressed: bool): _on_advantage_toggled(t, pressed))
		advantages_list.add_child(cb)

	for t: CharacterTrait in GameData.disadvantages:
		var cb := _make_trait_checkbox(t)
		cb.toggled.connect(func(pressed: bool): _on_disadvantage_toggled(t, pressed))
		disadvantages_list.add_child(cb)

	_refresh_traits_count()

func _make_trait_checkbox(t: CharacterTrait) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = t.trait_name
	cb.tooltip_text = t.description
	cb.add_theme_color_override("font_color", Color.BLACK)
	return cb

func _on_advantage_toggled(t: CharacterTrait, pressed: bool) -> void:
	if pressed:
		if t not in character.advantages:
			character.advantages.append(t)
	else:
		character.advantages.erase(t)
	_refresh_traits_count()

func _on_disadvantage_toggled(t: CharacterTrait, pressed: bool) -> void:
	if pressed:
		if t not in character.disadvantages:
			character.disadvantages.append(t)
	else:
		character.disadvantages.erase(t)
	_refresh_traits_count()

func _refresh_traits_count() -> void:
	lbl_advantages_count.text = "Seleccionadas: %d / mínimo 3" % character.advantages.size()
	lbl_disadvantages_count.text = "Seleccionadas: %d / mínimo 2" % character.disadvantages.size()
	_update_continue_button()

# --- Validación general ---

func _update_continue_button() -> void:
	var result := character.is_creation_valid()
	btn_continuar.disabled = not result.valid
	btn_continuar.tooltip_text = "" if result.valid else "\n".join(result.errors)

func _on_volver_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

# --- Habilidades ---

func _build_skills_lists() -> void:
	_populate_skill_checkboxes(general_skills_list, GameData.general_skills, character.general_skills)
	_populate_skill_checkboxes(combat_skills_list, GameData.combat_skills, character.combat_skills)
	_populate_skill_checkboxes(battle_skills_list, GameData.battle_skills, character.battle_skills)

func _populate_skill_checkboxes(container: VBoxContainer, catalog: Array[Skill], selected: Array[Skill]) -> void:
	for child in container.get_children():
		child.queue_free()

	for s: Skill in catalog:
		var cb := CheckBox.new()
		cb.text = s.skill_name
		cb.tooltip_text = s.description
		cb.add_theme_color_override("font_color", Color.BLACK)
		cb.toggled.connect(func(pressed: bool): _on_skill_toggled(s, selected, pressed))
		container.add_child(cb)

func _on_skill_toggled(s: Skill, selected: Array[Skill], pressed: bool) -> void:
	if pressed:
		if s not in selected:
			selected.append(s)
	else:
		selected.erase(s)
		
# --- Equipamiento ---

var equipment_checkboxes: Dictionary = {}   # Equipment -> CheckBox

func _build_equipment_list() -> void:
	for child in equipment_list.get_children():
		child.queue_free()
	equipment_checkboxes.clear()

	for e: Equipment in GameData.equipment_catalog:
		var cb := CheckBox.new()
		cb.text = _equipment_label(e)
		cb.tooltip_text = e.description
		cb.add_theme_color_override("font_color", Color.BLACK)
		cb.toggled.connect(func(pressed: bool): _on_equipment_toggled(e, cb, pressed))
		equipment_list.add_child(cb)
		equipment_checkboxes[e] = cb

	_refresh_equipment_count()

func _equipment_label(e: Equipment) -> String:
	var bonuses: Array[String] = []
	if e.combat_mod != 0: bonuses.append("Combate %+d" % e.combat_mod)
	if e.defense_mod != 0: bonuses.append("Defensa %+d" % e.defense_mod)
	if e.leadership_mod != 0: bonuses.append("Liderazgo %+d" % e.leadership_mod)
	if e.charisma_mod != 0: bonuses.append("Carisma %+d" % e.charisma_mod)
	if e.strategy_mod != 0: bonuses.append("Estrategia %+d" % e.strategy_mod)
	var bonus_text := ", ".join(bonuses)
	return "%s (%s)" % [e.equipment_name, bonus_text]

func _on_equipment_toggled(e: Equipment, cb: CheckBox, pressed: bool) -> void:
	if pressed:
		if character.equipment.size() >= 2:
			# Ya hay 2 elegidos: revierte visualmente esta casilla sin agregarla.
			cb.set_pressed_no_signal(false)
			return
		character.equipment.append(e)
	else:
		character.equipment.erase(e)

	_refresh_equipment_count()
	_update_equipment_lock_state()

func _refresh_equipment_count() -> void:
	lbl_equipment_count.text = "Equipados: %d / máximo 2" % character.equipment.size()

func _update_equipment_lock_state() -> void:
	var maxed_out := character.equipment.size() >= 2
	for e: Equipment in equipment_checkboxes.keys():
		var cb: CheckBox = equipment_checkboxes[e]
		cb.add_theme_color_override("font_color", Color.BLACK)
		if not cb.button_pressed:
			cb.disabled = maxed_out

func _on_bio_changed() -> void:
	character.biography = edit_bio.text
	
func _on_continuar_pressed() -> void:
	allocator.apply_to_character(character)
	character.apply_trait_and_equipment_modifiers()
	CreationState.pending_character = character
	get_tree().change_scene_to_file("res://scenes/character_summary/character_summary.tscn")
