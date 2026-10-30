extends Control

@onready var board: BattleBoard = %Board
@onready var title_label: Label = %TitleLabel
@onready var turn_label: Label = %TurnLabel
@onready var forces_label: Label = %ForcesLabel
@onready var unit_info_label: Label = %UnitInfoLabel
@onready var log_label: Label = %LogLabel
@onready var legend_label: Label = %LegendLabel
@onready var btn_end_turn: Button = %BtnEndTurn
@onready var btn_retreat: Button = %BtnRetreat
@onready var result_overlay: Control = %ResultOverlay
@onready var result_title: Label = %ResultTitle
@onready var result_label: Label = %ResultLabel
@onready var btn_back_to_map: Button = %BtnBackToMap
@onready var forces_bar: ProgressBar = %ForcesBar
@onready var result_panel: PanelContainer = %ResultPanel
@onready var companions_label: Label = %CompanionsLabel

const MAX_LOG_LINES := LogView.MAX_LINES
const LOG_HEIGHT := 150.0  # el registro de batalla tiene alto fijo y se desplaza
# Compañeros que trae el señor enemigo según su rango (cortesanos de su reino).
const ENEMY_COMPANIONS_BY_ROLE := {Character.Role.NOBLEZA_BAJA: 1, Character.Role.NOBLEZA_ALTA: 2, Character.Role.REGENTE: 3,
	Character.Role.DUQUE: 3}
const ENEMY_COMPANION_CHANCE := 0.7
const FACTION_OFFICERS := 2   # cortesanos que van de oficiales en los pelotones enemigos
const DEFENDER_HINT := "Defiendes tras la muralla (+50%)."
const IDLE_HINT := "Elige un pelotón azul."
const XpRules = preload("res://scripts/resources/xp_rules.gd")
const COMPANION_XP_SHARE := 0.5       # experiencia de los compañeros que dirigieron un pelotón
const BATTLE_DEATH_CHANCE := 0.25     # si tu ejército entero cae o huye, puedes caer con él
const BANNER_TIME := 4.0
const ORDER_KEYS := {KEY_H: BattleEnums.Order.MANTENER, KEY_C: BattleEnums.Order.CARGAR}
const WITHDRAW_KEY := KEY_R
const COMMAND_FONT_SIZE := 13

var battle: BattleManager
var army: Army
var castle: Castle
var selected: BattleUnit
var log_lines: Array[String] = []
var player_defending := false   # true si el jugador defiende su castillo de un ejército de la IA

var skirmish: Dictionary = {}   # escaramuza de un evento (sin ejército ni castillo de por medio)
var invited: Dictionary = {}    # batalla ajena: alguien te llamó a filas (ver CombatSetup.invited)
const CHALLENGE_KEY := KEY_D
const COMBAT_SCENE := "res://scenes/rpg_battle/rpg_battle.tscn"
var _challenge_mode := false    # el siguiente clic en un jefe enemigo lo reta a duelo
var _dueling := false           # hay un duelo singular encima del tablero
var _challenge_btn: Button
var _betray_btn: Button
var _betray_armed := false      # la traición pide confirmarla con un segundo clic
var _betrayal_text := ""        # consecuencias ya aplicadas al traicionar (para el cartel final)
var _prompt: Control            # ventana de reto de la IA a uno de tus jefes
var _retreated := false
var _order_buttons := {}        # BattleEnums.Order (o -1 para Replegarse) -> Button
var _ability_buttons: Array = []   # [Button, Character, id]
var _banner: Label
var _council: Control           # consejo antes de la batalla: el general y tu tropa
var _retreat_prompt: Control    # tu general ordenó la retirada
const WarCouncilPanel = preload("res://scripts/ui/war_council_panel.gd")
var _excluded: Array[String] = []    # miembros del séquito que se quedan fuera de esta batalla
var _start_fn: Callable              # arranca la batalla con los compañeros elegidos (se repite si cambias)
var _enemy_list: Array[Character] = []
var _command_box: VBoxContainer
var _ability_node: Control
# Reparto de hombres antes de la batalla (ver CombatSetup.PLATOON_MIN / platoon_max / soldada_cost).
var _allocation := {}                # nombre del jefe (tú o un compañero) -> hombres
var _alloc_hired := false            # true: hombres contratados para esta batalla (se paga soldada)
var _alloc_pool := 0                 # > 0: total de tu propia gente que puedes repartir
var _alloc_default_mine := 0         # tu pelotón por defecto
var _alloc_dirty := false            # cambiaste el reparto: se vuelve a formar al confirmar
var _alloc_rows := {}                # nombre -> Label con el número
var _alloc_cost_label: Label
var _go_btn: Button

func _ready() -> void:
	LogView.wrap(log_label, LOG_HEIGHT)
	skirmish = CombatSetup.skirmish
	invited = CombatSetup.invited
	army = ArmyData.active_battle_army
	if not invited.is_empty():
		skirmish = {}
		army = ArmyData.find_army(str(invited.get("army_id", ""))) if invited.get("kind", "") == "army" else null
		castle = MapData.get_castle_by_id(str(invited.get("castle_id", invited.get("ally_castle_id", ""))))
		if (invited.kind == "army" and (army == null or not army.pending_battle)) or castle == null:
			# El asedio ya se resolvió (o el castillo no existe): no hay batalla a la que unirse.
			CombatSetup.invited = {}
			invited = {}
	if invited.is_empty():
		castle = MapData.get_castle_by_id(army.current_castle_id) if army != null else null
	if invited.is_empty() and skirmish.is_empty() and (army == null or not army.pending_battle or castle == null):
		# Nadie llegó aquí desde una batalla pendiente del mapa; evita un crash.
		var fallback := "res://scenes/map/map.tscn" if GameManager.is_game_active else "res://scenes/main_menu/main_menu.tscn"
		get_tree().change_scene_to_file(fallback)
		return

	result_overlay.visible = false
	btn_end_turn.pressed.connect(_on_end_turn_pressed)
	btn_retreat.pressed.connect(_on_retreat_pressed)
	btn_back_to_map.pressed.connect(_on_back_to_map_pressed)

	player_defending = invited.is_empty() and skirmish.is_empty() and not ArmyData.is_player_army(army)
	if not invited.is_empty():
		pass   # el título lo pone _start_invited
	elif not skirmish.is_empty():
		title_label.text = "%s\n%s contra %s" % [skirmish.title, GameManager.player_character.full_name(), skirmish.enemy_name]
		btn_retreat.text = "Retirarse"
		btn_retreat.tooltip_text = "Abandonas el combate: el evento se da por perdido."
	elif player_defending:
		title_label.text = "Defensa de %s\n%s asedia tu castillo" % [castle.castle_name, army.owner_name]
		btn_retreat.text = "Abandonar Castillo"
		btn_retreat.tooltip_text = "Entregas el castillo al atacante sin seguir luchando."
	else:
		title_label.text = "Batalla por %s\n%s contra %s" % [castle.castle_name, army.owner_name, castle.owner_name]
	legend_label.text = "Bosque +25% · Colina +20% · Aldea +30% · Muralla +50% · Vado −20%"
	legend_label.tooltip_text = "Defensa por terreno. Colina: arqueros +1 alcance. Río: solo por puente o vado.\nI/A/C/P: infantería, arqueros, caballería, piqueros (★ avanzada) · ⚑ general.\nCaballería > arqueros > infantería > piqueros > caballería."
	legend_label.mouse_filter = Control.MOUSE_FILTER_PASS
	legend_label.add_theme_font_size_override("font_size", 12)
	_style_forces_bar()

	battle = BattleManager.new()
	battle.log_message.connect(_on_log_message)
	battle.state_updated.connect(_refresh)
	battle.battle_ended.connect(_on_battle_ended)
	battle.interactive_encounters = true
	battle.auto_resolve_others = Settings.auto_resolve_others
	battle.encounter_pending.connect(func(_e): _play_encounters.call_deferred())
	board.setup(battle)
	# Teclado y mando: el tablero tiene el foco (cursor con flechas o cruceta, Intro o A para actuar).
	board.focus_mode = Control.FOCUS_ALL
	board.grab_focus.call_deferred()
	board.cell_clicked.connect(_on_cell_clicked)
	board.cell_hovered.connect(_on_cell_hovered)
	battle.ability_used.connect(_on_ability_used)
	battle.challenge_offered.connect(_on_challenge_offered)
	battle.challenge_resolved.connect(func(text: String): _show_banner(text))
	battle.retreat_ordered.connect(_on_retreat_ordered)

	var player: Character = GameManager.player_character
	battle.player_leader = player
	if not invited.is_empty():
		_start_invited(player)
		return
	if not skirmish.is_empty():
		# Escaramuza en campo abierto: tu gente (y tu séquito) contra los atacantes del evento.
		battle.player_side = BattleEnums.Side.ATACANTE
		var home: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
		battle.biome = home.kingdom if home != null else -1
		_alloc_hired = false   # tu guarnición: ya cobra, repartirla es gratis
		_alloc_pool = int(skirmish.player_soldiers)
		_start_fn = func(comps: Array[Character]) -> void:
			_use_allocation(comps)
			battle.start_battle(skirmish.player_soldiers, skirmish.enemy_soldiers, false, player, skirmish.foe, "el campo abierto", comps, [])
		var companions := _player_companions()
		_start_fn.call(companions)
		_show_companions(companions, [])
		_after_start()
		return
	# Los señores de la IA comandan con su propia ficha (liderazgo, estrategia y habilidades de batalla).
	var attacker_cmd: Character = RelationsData.character_of(army.owner_name) if player_defending else player
	var defender_cmd: Character = player if player_defending else RelationsData.character_of(castle.owner_name)
	battle.player_side = BattleEnums.Side.DEFENSOR if player_defending else BattleEnums.Side.ATACANTE
	var enemy_cmd: Character = attacker_cmd if player_defending else defender_cmd
	var enemy_kingdom: int = army.kingdom if player_defending else castle.kingdom
	var mine := _player_companions()
	var theirs := _enemy_companions(enemy_cmd, enemy_kingdom)
	battle.biome = castle.kingdom
	if castle.has_method("wall_bonus"):
		battle.wall_bonus = castle.wall_bonus()
		battle.cavalry_bonus = castle.cavalry_bonus()
	_enemy_list = theirs
	_alloc_hired = false   # tu ejército o tu guarnición: ya cobran, repartirlos es gratis
	_alloc_pool = castle.garrison_size if player_defending else army.size
	_start_fn = func(comps: Array[Character]) -> void:
		_use_allocation(comps)
		battle.start_battle(army.size, castle.garrison_size, true, attacker_cmd, defender_cmd, castle.castle_name, comps, theirs)
	_start_fn.call(mine)
	_show_companions(mine, theirs)
	_after_start()

# Batalla ajena: tu pelotón (y tu séquito) junto a las tropas de quien te llamó, que mueve la IA aliada.
func _start_invited(player: Character) -> void:
	var side: int = int(invited.get("side", BattleEnums.Side.ATACANTE))
	battle.player_side = side
	_alloc_default_mine = int(invited.get("player_soldiers", CombatSetup.PERSONAL_LEVY_BY_RANK[0]))
	# Los hombres de una batalla ajena se contratan.
	_alloc_hired = true
	_alloc_pool = 0 if _alloc_hired else _alloc_default_mine
	# A una batalla ajena solo te acompaña tu séquito (tu señor no te presta a nadie para servir a otro).
	var companions: Array[Character] = []
	for c: Character in _player_companions():
		if not c.has_meta("faction_companion"):
			companions.append(c)
	var lord: String = invited.get("lord", "")
	if invited.kind == "army":
		var att_cmd: Character = RelationsData.character_of(army.owner_name)
		var def_cmd: Character = RelationsData.character_of(castle.owner_name)
		var allies: int = army.size if side == BattleEnums.Side.ATACANTE else castle.garrison_size
		battle.ally_soldiers = allies
		invited["ally_soldiers"] = allies
		invited["enemy_soldiers"] = castle.garrison_size if side == BattleEnums.Side.ATACANTE else army.size
		var enemy_cmd: Character = def_cmd if side == BattleEnums.Side.ATACANTE else att_cmd
		var enemy_kingdom: int = castle.kingdom if side == BattleEnums.Side.ATACANTE else army.kingdom
		var theirs := _enemy_companions(enemy_cmd, enemy_kingdom)
		battle.biome = castle.kingdom
		battle.wall_bonus = castle.wall_bonus()
		battle.cavalry_bonus = castle.cavalry_bonus()
		title_label.text = "%s · %s\nCon %s contra %s" % [invited.get("title", "Llamada a filas"), castle.castle_name, lord,
			castle.owner_name if side == BattleEnums.Side.ATACANTE else army.owner_name]
		_enemy_list = theirs
		_start_fn = func(comps: Array[Character]) -> void:
			var mine: int = _use_allocation(comps)
			var att_total: int = army.size + (mine if side == BattleEnums.Side.ATACANTE else 0)
			var def_total: int = castle.garrison_size + (mine if side == BattleEnums.Side.DEFENSOR else 0)
			battle.start_battle(att_total, def_total, true, att_cmd, def_cmd, castle.castle_name, comps, theirs)
		_start_fn.call(companions)
		_show_companions(companions, theirs)
	else:
		var ally_castle := castle
		var enemy_castle: Castle = MapData.get_castle_by_id(str(invited.get("enemy_castle_id", "")))
		var allies := ArmyData.field_battle_soldiers(ally_castle)
		var foes := ArmyData.field_battle_soldiers(enemy_castle)
		battle.ally_soldiers = allies
		invited["ally_soldiers"] = allies
		invited["enemy_soldiers"] = foes
		var ally_cmd: Character = RelationsData.character_of(ally_castle.owner_name)
		var enemy_cmd: Character = RelationsData.character_of(enemy_castle.owner_name) if enemy_castle != null else null
		var theirs := _enemy_companions(enemy_cmd, enemy_castle.kingdom if enemy_castle != null else -1)
		battle.biome = ally_castle.kingdom
		var place := "los campos de %s" % ally_castle.castle_name
		title_label.text = "%s · %s\nCon %s contra %s" % [invited.get("title", "Batalla campal"), place, lord,
			enemy_castle.owner_name if enemy_castle != null else "el enemigo"]
		_enemy_list = theirs
		_start_fn = func(comps: Array[Character]) -> void:
			battle.start_battle(allies + _use_allocation(comps), foes, false, ally_cmd, enemy_cmd, place, comps, theirs)
		_start_fn.call(companions)
		_show_companions(companions, theirs)
	if battle.is_player_general():
		btn_retreat.text = "Ordenar la retirada"
		btn_retreat.tooltip_text = "Eres el general: retiras a todo tu bando y la batalla se da por perdida."
	else:
		btn_retreat.text = "Abandonar el campo"
		btn_retreat.tooltip_text = "Solo el general ordena la retirada: irte por tu cuenta es desertar (−%d de honor). La batalla sigue sin ti." % BattleManager.DESERT_HONOR
	_on_log_message("Mueves tus pelotones (azul). Los aliados (verde) los mueve %s." % lord)
	_after_start()

func _after_start() -> void:
	_build_command_card()
	Sfx.play("horn", 0.0, 0.0)
	var field := "Campo abierto" if battle.map_feature.is_empty() else "El campo: " + battle.map_feature
	_show_banner("%s\n%s" % [battle.conditions_text(), field])
	_refresh()
	if battle.player_unit() != null and not battle.is_over:
		_show_council()

# --- Consejo antes de la batalla: quién es el general y qué tropa llevas (puedes pedir otra) ---

func _modal() -> Array:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 60
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return [overlay, box]

func _text(box: Control, text: String, variation: StringName = &"", width: int = 600) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	if variation != &"":
		l.theme_type_variation = variation
	box.add_child(l)
	return l

func _show_council() -> void:
	_close_council()
	var parts := _modal()
	_council = parts[0]
	var box: VBoxContainer = parts[1]
	var me := battle.player_unit()
	var g := battle.general_of(battle.player_side)
	var player: Character = battle.player_leader
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	if g != null:
		row.add_child(FaceIcon.make(g, 72, BattleBoard.GENERAL_COLOR))
	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(head)
	_text(head, "Consejo antes de la batalla", &"HeaderLabel", 480)
	if battle.is_player_general():
		_text(head, "Eres el general.", &"", 480)
	elif g != null:
		_text(head, "General: %s" % g.full_name(), &"", 480)
	_text(box, "Tu tropa: %s (mando %d en %s). %s" % [BattleEnums.unit_type_name(me.type), player.mastery(me.family()),
		BattleEnums.family_name(me.family()).to_lower(), BattleEnums.unit_type_trait(me.type)], &"BodyBoldLabel")
	var status := _text(box, "Pide otra tropa (una vez):" if not battle.is_player_general() else "Elige tu tropa:")
	status.tooltip_text = "Cuentan tu mando en ella, tu Carisma, tu fama, tu Estrategia y tu relación con el general."
	status.mouse_filter = Control.MOUSE_FILTER_PASS
	var fams := HBoxContainer.new()
	fams.add_theme_constant_override("separation", 8)
	box.add_child(fams)
	var buttons: Array[Button] = []
	for f in 4:
		if f == me.family():
			continue
		var b := Button.new()
		var chance := battle.negotiation_chance(f)
		b.text = "%s (%d%%)" % [BattleEnums.family_name(f), roundi(chance * 100)] if chance < 1.0 else "Llevar %s" % BattleEnums.family_name(f).to_lower()
		b.tooltip_text = "Tu mando en %s: %d%s" % [BattleEnums.family_name(f).to_lower(), player.mastery(f),
			" (llevarías la tropa avanzada: %s)" % BattleEnums.unit_type_name(BattleEnums.advanced_type(f)) if player.mastery(f) >= Character.MASTERY_ADVANCED else ""]
		fams.add_child(b)
		buttons.append(b)
		b.pressed.connect(func():
			var result := battle.negotiate_unit(f)
			status.text = result.text
			for other in buttons:
				other.disabled = true
			_refresh())
	_companion_toggles(box)
	_allocation_rows(box)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(actions)
	if player.rank() >= Character.rank_of(Character.Role.NOBLEZA_BAJA) and battle.is_player_general():
		var council := Button.new()
		council.text = "Consejo de guerra"
		council.tooltip_text = "Asigna la tropa de los personajes de tu facción."
		council.pressed.connect(func(): WarCouncilPanel.open(self, func():
			battle.apply_assignments()
			_refresh()))
		actions.add_child(council)
	var go := Button.new()
	go.text = "¡Al combate!"
	go.theme_type_variation = &"PrimaryButton"
	go.pressed.connect(_confirm_council)
	actions.add_child(go)
	_go_btn = go
	_update_allocation_ui()
	go.grab_focus.call_deferred()

## Miembros de tu séquito que pueden venir (aunque los hayas dejado fuera).
func _available_companions() -> Array[Character]:
	var result: Array[Character] = []
	if RelationsData.has_method("battle_companions"):
		for c in RelationsData.battle_companions():
			if c is Character and not c.has_meta("faction_companion"):
				result.append(c)
	return result

## Casillas para elegir quién te acompaña: cada uno lleva un pelotón que mueves tú.
func _companion_toggles(box: VBoxContainer) -> void:
	var available := _available_companions()
	if available.is_empty():
		return
	var head := _text(box, "Te acompañan", &"BodyBoldLabel")
	head.tooltip_text = "Cada compañero lleva un pelotón que mueves tú."
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.custom_minimum_size = Vector2(600, 0)
	box.add_child(flow)
	for c: Character in available:
		var t := CheckButton.new()
		t.text = c.first_name
		t.icon = c.get_face()
		t.expand_icon = true
		t.add_theme_constant_override("icon_max_width", 24)
		t.tooltip_text = "%s · %s" % [c.full_name(), c.role_title()]
		t.button_pressed = not c.full_name() in _excluded
		var who := c.full_name()
		t.toggled.connect(func(on: bool):
			if on:
				_excluded.erase(who)
			elif not who in _excluded:
				_excluded.append(who)
			_restart_battle.call_deferred())
		flow.add_child(t)

## Vuelve a formar las tropas con los compañeros elegidos (mismo campo y clima; nadie ha movido aún).
func _restart_battle(reopen_council: bool = true) -> void:
	if _start_fn.is_null() or battle == null or battle.is_over or battle.turn > 1:
		return
	battle.reuse_terrain = true
	selected = null
	log_lines.clear()
	var comps := _player_companions()
	_start_fn.call(comps)
	_show_companions(comps, _enemy_list)
	_rebuild_abilities()
	_refresh()
	if reopen_council:
		_show_council()

# --- Reparto de hombres: tu pelotón y el de cada compañero ---

## Jefes de tus pelotones en esta batalla: tú y tus compañeros propios sanos.
func _alloc_leaders(comps: Array[Character]) -> Array[Character]:
	var result: Array[Character] = [battle.player_leader]
	for c: Character in comps:
		if c != null and not c.has_meta("faction_companion") and not c.is_wounded():
			result.append(c)
	return result

## Ajusta el reparto a quienes vienen (los nuevos entran con el mínimo), lo pasa a la batalla y
## devuelve el total de tus hombres.
func _use_allocation(comps: Array[Character]) -> int:
	var leaders := _alloc_leaders(comps)
	var names: Array = leaders.map(func(c: Character) -> String: return c.full_name())
	if _allocation.is_empty():
		_allocation = CombatSetup.default_allocation(leaders[0], leaders.slice(1), _alloc_pool, _alloc_default_mine)
	for who in _allocation.keys():
		if not who in names:
			_allocation.erase(who)
	for c: Character in leaders:
		if not _allocation.has(c.full_name()):
			_allocation[c.full_name()] = CombatSetup.PLATOON_MIN
	if _alloc_pool > 0:   # tu propia gente: no puedes repartir más de la que tienes
		while _alloc_total() > _alloc_pool and _trim_one():
			pass
	battle.own_allocation = _allocation.duplicate()
	return _alloc_total()

func _alloc_total() -> int:
	var n := 0
	for who in _allocation:
		n += int(_allocation[who])
	return n

## Quita hombres al pelotón más numeroso (para no pasar de tu gente). false si ya no se puede.
func _trim_one() -> bool:
	var biggest := ""
	for who in _allocation:
		if biggest == "" or int(_allocation[who]) > int(_allocation[biggest]):
			biggest = who
	if biggest == "" or int(_allocation[biggest]) <= 1:
		return false
	_allocation[biggest] = int(_allocation[biggest]) - 1
	return true

func _alloc_min() -> int:
	if _alloc_pool <= 0:
		return CombatSetup.PLATOON_MIN
	return clampi(_alloc_pool / maxi(1, _allocation.size()), 1, CombatSetup.PLATOON_MIN)

func _alloc_cost() -> int:
	return CombatSetup.soldada_cost(_allocation, battle.player_leader.full_name(), _alloc_hired)

## Suma (o resta) hombres al pelotón de un jefe, dentro del mínimo, su máximo y tu gente.
func change_allocation(who: Character, delta: int) -> void:
	var key := who.full_name()
	if not _allocation.has(key):
		return
	var now := int(_allocation[key])
	var top: int = maxi(_alloc_min(), CombatSetup.platoon_max(who))
	var n := clampi(now + delta, _alloc_min(), top)
	if _alloc_pool > 0:
		n = mini(n, now + maxi(0, _alloc_pool - _alloc_total()))
	if n == now:
		Sfx.play("whoosh", -12.0)
		return
	_allocation[key] = n
	_alloc_dirty = true
	Sfx.play("click", -10.0)
	_update_allocation_ui()

## Una fila por pelotón: retrato, nombre, [−] hombres [+] y el máximo según su Liderazgo.
func _allocation_rows(box: VBoxContainer) -> void:
	_alloc_rows.clear()
	var leaders := _alloc_leaders(_player_companions())
	var head := _text(box, "Hombres por pelotón", &"BodyBoldLabel")
	head.tooltip_text = "Mínimo %d por pelotón; el máximo depende del Liderazgo de quien lo manda." % CombatSetup.PLATOON_MIN
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for c: Character in leaders:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		grid.add_child(row)
		row.add_child(FaceIcon.make(c, 26))
		var name_l := Label.new()
		name_l.text = "Tú" if c == battle.player_leader else c.first_name
		name_l.custom_minimum_size = Vector2(96, 0)
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.tooltip_text = "%s · Liderazgo %d" % [c.full_name(), c.leadership]
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name_l)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(30, 0)
		minus.tooltip_text = "−%d hombres" % CombatSetup.PLATOON_STEP
		minus.pressed.connect(change_allocation.bind(c, -CombatSetup.PLATOON_STEP))
		row.add_child(minus)
		var value := Label.new()
		value.custom_minimum_size = Vector2(34, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(value)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(30, 0)
		plus.tooltip_text = "+%d hombres" % CombatSetup.PLATOON_STEP
		plus.pressed.connect(change_allocation.bind(c, CombatSetup.PLATOON_STEP))
		row.add_child(plus)
		var top := Label.new()
		top.theme_type_variation = &"MutedLabel"
		top.text = "máx %d" % CombatSetup.platoon_max(c)
		row.add_child(top)
		_alloc_rows[c.full_name()] = value
	_alloc_cost_label = _text(box, "", &"MutedLabel")

func _update_allocation_ui() -> void:
	for who in _alloc_rows:
		var l: Label = _alloc_rows[who]
		if is_instance_valid(l):
			l.text = str(int(_allocation.get(who, 0)))
	var gold: int = battle.player_leader.gold
	var cost := _alloc_cost()
	if is_instance_valid(_alloc_cost_label):
		if _alloc_hired:
			_alloc_cost_label.text = "Soldada: %d oro (tienes %d)" % [cost, gold]
			_alloc_cost_label.tooltip_text = "%d de oro por hombre contratado; tus %d allegados no cobran. Si vencéis, %s paga a tu gente." % [
				CombatSetup.SOLDADA_PER_MAN, CombatSetup.PERSONAL_RETAINERS, str(invited.get("lord", "tu anfitrión"))]
		else:
			_alloc_cost_label.text = "Tu gente: %d de %d (ya cobran)" % [_alloc_total(), _alloc_pool]
			_alloc_cost_label.tooltip_text = "Repartir tu propia tropa es gratis. Lo que no asignes lo mandan tus capitanes."
		_alloc_cost_label.mouse_filter = Control.MOUSE_FILTER_PASS
	if is_instance_valid(_go_btn):
		_go_btn.disabled = cost > gold
		_go_btn.tooltip_text = "No te alcanza para la soldada: lleva menos hombres o deja a algún compañero." if cost > gold else ""

## Confirma el consejo: si cambiaste el reparto se vuelven a formar las tropas y se paga la soldada.
func _confirm_council() -> void:
	var cost := _alloc_cost()
	if cost > battle.player_leader.gold:
		return
	if _alloc_dirty:
		_alloc_dirty = false
		_restart_battle(false)
	if cost > 0:
		battle.player_leader.gold -= cost
		_on_log_message("Pagas %d de oro de soldada a tus hombres." % cost)
	_close_council()
	_refresh()

func _close_council() -> void:
	if _council != null:
		_council.queue_free()
		_council = null
		board.grab_focus.call_deferred()

# Tu general ordenó la retirada: ¿te vas con el ejército o te quedas cubriéndola?
func _on_retreat_ordered(general: Character) -> void:
	if _retreat_prompt != null:
		_retreat_prompt.queue_free()
	var parts := _modal()
	_retreat_prompt = parts[0]
	var box: VBoxContainer = parts[1]
	if general != null:
		box.add_child(FaceIcon.make(general, 72, BattleBoard.GENERAL_COLOR))
	_text(box, "%s ordena la retirada" % (general.full_name() if general != null else "Tu general"), &"HeaderLabel")
	_text(box, "Cubrir la huida %d turnos: +%d honor, +%d fama si sobrevives." % [
		BattleManager.COVER_TURNS, BattleManager.COVER_HONOR, BattleManager.COVER_FAME])
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var leave := Button.new()
	leave.text = "Retirarte con el ejército"
	row.add_child(leave)
	var stay := Button.new()
	stay.text = "Cubrir la retirada"
	stay.theme_type_variation = &"PrimaryButton"
	row.add_child(stay)
	leave.pressed.connect(func(): _answer_retreat(false))
	stay.pressed.connect(func(): _answer_retreat(true))
	stay.grab_focus.call_deferred()
	_refresh()

func _answer_retreat(stay: bool) -> void:
	if _retreat_prompt != null:
		_retreat_prompt.queue_free()
		_retreat_prompt = null
	if not stay:
		_retreated = true
	battle.answer_retreat(stay)
	_refresh()

# --- Órdenes y habilidades de mando ---

func _build_command_card() -> void:
	var card := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for spec in [[BattleEnums.Order.MANTENER, "Mantener [H]", "Mantener posición: el pelotón no se mueve, pero recibe un 23% menos de bajas. Dura hasta que la quites."],
			[BattleEnums.Order.CARGAR, "Cargar [C]", "Cargar: su primer golpe cuerpo a cuerpo hace +30%, pero se cansa un 50% más. No vale para arqueros."],
			[-1, "Replegarse [R]", "Replegarse: retrocede hasta 2 casillas hacia tu retaguardia y recupera 10 de moral. Gasta su turno."]]:
		var b := Button.new()
		b.text = spec[1]
		b.tooltip_text = spec[2]
		b.toggle_mode = spec[0] != -1
		_compact(b)
		var order: int = spec[0]
		b.pressed.connect(func(): _give_order(order))
		row.add_child(b)
		_order_buttons[order] = b
	# Retar y traicionar van en la misma fila que las órdenes: la tarjeta cabe bajo el tablero.
	var row2 := row
	_challenge_btn = Button.new()
	_challenge_btn.text = "Retar [D]"
	_challenge_btn.tooltip_text = "Solo en campo abierto: el jefe del pelotón elegido reta a un jefe enemigo a tiro (necesita %d de honor). Quien pierde se retira con su pelotón. Gasta su turno." % BattleManager.CHALLENGE_MIN_HONOR
	_compact(_challenge_btn)
	_challenge_btn.pressed.connect(_on_challenge_pressed)
	row2.add_child(_challenge_btn)
	_betray_btn = Button.new()
	_betray_btn.text = "Traicionar"
	_betray_btn.tooltip_text = "Te pasas al enemigo con tus pelotones y tu séquito. Pierdes %d de honor y %d de fama, y quienes luchan en tu bando no lo olvidarán (afinidad e intimidad %d). Tras la batalla juras lealtad al señor del otro bando." % [
		ArmyData.BETRAYAL_HONOR, ArmyData.BETRAYAL_FAME, ArmyData.BETRAYAL_RELATION]
	_compact(_betray_btn)
	_betray_btn.pressed.connect(_on_betray_pressed)
	row2.add_child(_betray_btn)
	_command_box = box
	_build_abilities(box)
	# Va bajo el tablero (en el panel lateral no cabe): el marco del tablero pasa a una columna.
	var board_frame := board.get_parent().get_parent() as Control
	var main := board_frame.get_parent()
	var column := VBoxContainer.new()
	column.size_flags_horizontal = board_frame.size_flags_horizontal
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(column)
	main.move_child(column, board_frame.get_index())
	board_frame.reparent(column)
	board_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(card)

func _rebuild_abilities() -> void:
	if _command_box == null:
		return
	if _ability_node != null:
		_ability_node.queue_free()
	_ability_buttons.clear()
	_build_abilities(_command_box)

func _build_abilities(box: VBoxContainer) -> void:
	var users := battle.ability_users(battle.player_side, BattleManager.ABILITY_PLAYER)
	if users.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"MutedLabel"
		none.text = "Sin habilidades de mando."
		none.tooltip_text = "Las dan las habilidades de batalla de tu comandante y compañeros."
		none.mouse_filter = Control.MOUSE_FILTER_PASS
		none.add_theme_font_size_override("font_size", COMMAND_FONT_SIZE)
		box.add_child(none)
		_ability_node = none
	else:
		# Una sola fila que se desplaza en horizontal: con más compañeros hay más órdenes, no más alto.
		var scroll := ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		box.add_child(scroll)
		var flow := HBoxContainer.new()
		flow.add_theme_constant_override("separation", 6)
		scroll.add_child(flow)
		_ability_node = scroll
		for c: Character in users:
			for id: String in battle.abilities_of(c):
				var b := Button.new()
				var n := _ability_buttons.size() + 1
				b.text = "%s%s · %s" % ["[%d] " % n if n <= 9 else "", BattleManager.ABILITIES[id].name, c.first_name]
				b.tooltip_text = "%s (%s, una vez por batalla): %s" % [BattleManager.ABILITIES[id].name, c.full_name(), BattleManager.ABILITIES[id].desc]
				b.icon = c.get_face()
				b.expand_icon = true
				b.add_theme_constant_override("icon_max_width", 20)
				_compact(b)
				b.clip_text = false
				b.size_flags_horizontal = Control.SIZE_FILL
				b.pressed.connect(func(): _use_ability(c, id))
				flow.add_child(b)
				_ability_buttons.append([b, c, id])

# Botones pequeños: el panel lateral va justo de espacio.
func _compact(b: Button) -> void:
	b.add_theme_font_size_override("font_size", COMMAND_FONT_SIZE)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := b.get_theme_stylebox(state).duplicate() as StyleBox
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		b.add_theme_stylebox_override(state, sb)

func _give_order(order: int) -> void:
	if selected == null or battle.is_over:
		Sfx.play("whoosh", -10.0)
		_refresh()
		return
	var ok := battle.withdraw(selected) if order == -1 else battle.set_order(selected, order)
	Sfx.play("click" if ok else "whoosh", -6.0 if ok else -10.0)
	_refresh()

func _use_ability(c: Character, id: String) -> void:
	if not battle.use_ability(c, id, battle.player_side):
		Sfx.play("whoosh", -10.0)
	_refresh()

func _on_ability_used(user: Character, ability_id: String, side: int) -> void:
	Sfx.play("horn", -6.0)
	var mine := side == battle.player_side
	_show_banner("%s «%s»\n%s" % ["Tu bando:" if mine else "El enemigo:", BattleManager.ABILITIES[ability_id].name, user.full_name()],
		BattleBoard.PLAYER_COLOR.lightened(0.5) if mine else BattleBoard.ENEMY_COLOR.lightened(0.4))

# Cartel breve sobre el tablero (clima al empezar, habilidades de mando).
const GENERAL_FALL_DELAY := 0.25   # tras el último golpe
const GENERAL_FALL_FONT := 40

# Si la batalla acaba porque cayó un general: cartel grande y cuerno (la música se aparta).
func _announce_general_fall(reason: String) -> void:
	if not (reason.begins_with("Cae ") and "general" in reason):
		return
	await get_tree().create_timer(board.fx_remaining() + GENERAL_FALL_DELAY).timeout
	if not is_inside_tree():
		return
	Sfx.stinger("horn", 0.0, 1.6)
	board.shake(CombatFx.TIER_SHAKE[CombatFx.Tier.BIG])
	CombatFx.banner(self, "¡Cae el general!", Color("f0d48a"), GENERAL_FALL_FONT, 1.0, board.get_global_rect())

func _show_banner(text: String, color: Color = Color("f0d48a")) -> void:
	if _banner == null:
		_banner = Label.new()
		_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_banner.add_theme_font_size_override("font_size", 20)
		_banner.add_theme_constant_override("outline_size", 6)
		_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.z_index = 20
		board.add_child(_banner)
	_banner.size = Vector2(board.custom_minimum_size.x - 40, 0)
	_banner.position = Vector2(20, 12)
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 1.0
	var tw := _banner.create_tween()
	tw.tween_interval(BANNER_TIME)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)

func _refresh_commands() -> void:
	var can_order := selected != null and selected.is_active() and not battle.is_over and battle.is_player_unit(selected)
	for order in _order_buttons:
		var b: Button = _order_buttons[order]
		if order == -1:
			b.disabled = not can_order or not battle.can_withdraw(selected)
		else:
			b.disabled = not can_order or selected.has_acted or (order == BattleEnums.Order.CARGAR and selected.type == BattleEnums.UnitType.ARQUEROS)
			b.set_pressed_no_signal(can_order and selected.order == order)
	if _challenge_btn != null:
		var blocker := _challenge_hint()
		_challenge_btn.disabled = not blocker.is_empty() or _dueling
		_challenge_btn.set_pressed_no_signal(_challenge_mode)
		_challenge_btn.tooltip_text = blocker if not blocker.is_empty() else "Elige al jefe enemigo (resaltado en dorado) al que retar."
	if _betray_btn != null:
		var why := _betrayal_blocker()
		_betray_btn.disabled = not why.is_empty() or _dueling
		_betray_btn.visible = why != NO_FACTION
		if not why.is_empty():
			_betray_armed = false
		_betray_btn.text = "¿Seguro?" if _betray_armed else "Traicionar"
	for entry in _ability_buttons:
		var b: Button = entry[0]
		b.disabled = not battle.can_use_ability(entry[1], entry[2], battle.player_side)
		if battle.ability_used_by(entry[1]):
			b.tooltip_text = "%s ya dio su orden en esta batalla." % entry[1].full_name()

# --- Compañeros ---

# Séquito del jugador (o compañeros de facción prestados por su señor), si el sistema social lo ofrece.
func _player_companions() -> Array[Character]:
	var result: Array[Character] = []
	if RelationsData.has_method("battle_companions"):
		for c in RelationsData.battle_companions():
			if c is Character and not c.full_name() in _excluded:
				result.append(c)
	return result

# El señor enemigo lleva cortesanos de su reino a la batalla, más cuanto más alto es su rango.
func _enemy_companions(enemy_cmd: Character, kingdom: int) -> Array[Character]:
	var result: Array[Character] = []
	var count: int = ENEMY_COMPANIONS_BY_ROLE.get(enemy_cmd.role if enemy_cmd != null else -1, 0)
	var pool := RelationsData.courtiers(kingdom)
	pool.shuffle()
	for r: Relationship in pool:
		if result.size() >= count:
			break
		if r.character != null and not r.character.is_wounded() and randf() < ENEMY_COMPANION_CHANCE:
			result.append(r.character)
	# Otros cortesanos van de oficiales en los pelotones del señor (fase 4).
	var officers: Array[Character] = []
	for r: Relationship in pool:
		if officers.size() >= FACTION_OFFICERS:
			break
		if r.character != null and not r.character in result and not r.character.is_wounded():
			officers.append(r.character)
	battle.faction_officers["enemy"] = officers
	return result

func _show_companions(mine: Array[Character], theirs: Array[Character]) -> void:
	var lines: Array[String] = []
	if not mine.is_empty():
		lines.append("Contigo: " + ", ".join(mine.map(func(c: Character): return c.full_name())))
		var first: Character = mine[0]
		var topic := "faction_companion" if first.has_meta("faction_companion") else "retinue_battle"
		_on_log_message("%s: «%s»" % [first.full_name(), DialogueCatalog.line(topic, first, GameManager.player_character, {"player": GameManager.player_character.full_name()})])
	if not theirs.is_empty():
		lines.append("Con el enemigo: " + ", ".join(theirs.map(func(c: Character): return c.full_name())))
	companions_label.text = "\n".join(lines)
	companions_label.visible = not lines.is_empty()

# --- Interacción con el tablero ---

func _on_cell_clicked(cell: Vector2i) -> void:
	if battle.is_over:
		return
	if _dueling or not battle.pending_challenge.is_empty():
		return
	var clicked := battle.unit_at(cell)
	if clicked != null and not battle.is_visible_to(battle.player_side, clicked):
		clicked = null   # en la niebla o de noche no ves a quien está lejos

	# Modo reto: el clic en un jefe enemigo a tiro lanza el reto; cualquier otro, lo cancela.
	if _challenge_mode:
		_challenge_mode = false
		if selected != null and clicked != null and battle.can_challenge(selected, clicked):
			_issue_challenge(selected, clicked)
			return
		_refresh()
		if clicked == null or battle.is_friendly(clicked):
			return

	# Atacar a un enemigo en alcance con el pelotón seleccionado
	if selected != null and clicked != null and not battle.is_friendly(clicked):
		if battle.can_attack(selected) and clicked in battle.targets_in_range(selected):
			battle.attack(selected, clicked)
			# El ataque puede terminar la batalla y el final ya limpia la selección (selected = null).
			if selected != null and not selected.is_active():
				selected = null
			_refresh()
			return

	# Seleccionar uno de tus pelotones
	if clicked != null and battle.is_player_unit(clicked):
		if clicked != selected:
			Sfx.play("click", -8.0)
		selected = clicked
		_refresh()
		return

	# Mover el pelotón seleccionado a una casilla resaltada
	if selected != null and clicked == null and cell in battle.reachable_cells(selected):
		battle.move_unit(selected, cell)
		_refresh()
		return

	if clicked != null:
		# Enemigo fuera de alcance (o aliado de la IA): solo se muestra su información (y quién lo dirige).
		unit_info_label.text = "%s: %s\nTerreno: %s" % ["Aliado" if battle.is_friendly(clicked) else "Enemigo",
			clicked.describe(), battle.terrain_text(clicked)]
		for pair: Array in battle.visible_intents():
			if pair[0] == clicked:
				unit_info_label.text += "\nParece que va a %s." % pair[1].text
		_show_leader(clicked)
		return

	selected = null
	_refresh()

# Al pasar sobre un enemigo atacable se muestran las bajas esperadas (sin azar) de ambos lados.
func _on_cell_hovered(cell: Vector2i) -> void:
	if battle == null or battle.is_over or selected == null or not selected.is_active() or not battle.can_attack(selected):
		return
	var target := battle.unit_at(cell)
	if target == null or battle.is_friendly(target) or not target in battle.targets_in_range(selected):
		_refresh()
		return
	var p := battle.preview_attack(selected, target)
	var counter_text := "Sin respuesta enemiga" if p.counter == 0 else "Respuesta: ≈%d bajas propias" % p.counter
	unit_info_label.text = "%s → %s\nBajas enemigas esperadas: ≈%d de %d\n%s\nTerreno del objetivo: %s" % [
		BattleEnums.unit_type_name(selected.type), BattleEnums.unit_type_name(target.type),
		p.casualties, target.soldiers, counter_text, battle.terrain_text(target)]

func _on_end_turn_pressed() -> void:
	if _dueling or not battle.pending_challenge.is_empty():
		return
	selected = null
	_challenge_mode = false
	_betray_armed = false
	battle.end_player_turn()
	_refresh()

func _on_retreat_pressed() -> void:
	_retreated = true
	battle.retreat()

# --- UI ---

func _refresh() -> void:
	if battle == null:
		return
	turn_label.text = "Turno %d / %d · %s · %s" % [mini(battle.turn, battle.max_turns), battle.max_turns,
		BattleEnums.weather_name(battle.weather), BattleEnums.time_name(battle.time_of_day)]
	turn_label.tooltip_text = battle.conditions_text()
	var mine := _active_soldiers(battle.player_side)
	var theirs := _active_soldiers(battle._other_side(battle.player_side))
	forces_label.text = "Tus tropas: %d  ·  Enemigos: %d" % [mine, theirs]
	forces_bar.value = mine / float(maxi(1, mine + theirs))
	# La capa de tambores sube a medida que caen soldados de ambos bandos.
	Music.set_intensity(smoothstep(0.0, 0.35, battle.casualty_fraction()) * 0.6 + (0.4 if battle.turn > 1 else 0.0))

	var moves: Array[Vector2i] = []
	var targets: Array[BattleUnit] = []
	if selected != null and selected.is_active() and not battle.is_over:
		moves = battle.reachable_cells(selected)
		if battle.can_attack(selected):
			targets = battle.targets_in_range(selected)
		var status := "Puede moverse y atacar."
		if selected.has_acted:
			status = "Ya actuó este turno."
		elif selected.has_moved:
			status = "Ya se movió; aún puede atacar."
		unit_info_label.text = "%s\nTerreno: %s · Mando %d\n%s" % [
			selected.describe(), battle.terrain_text(selected), battle._unit_mastery(selected), status]
		_show_leader(selected)
	elif not battle.is_over:
		_show_leader(null)
		unit_info_label.text = (DEFENDER_HINT + "\n" if player_defending and battle.turn <= 2 else "") + IDLE_HINT
	board.set_selection(selected, moves, targets)
	board.set_intents(battle.visible_intents())
	var challengeable: Array[BattleUnit] = []
	if _challenge_mode and battle.is_player_unit(selected):
		challengeable = battle.challenge_targets(selected)
	board.set_challenge_targets(challengeable)

	var waiting := _dueling or not battle.pending_challenge.is_empty() or battle.pending_retreat
	btn_end_turn.disabled = battle.is_over or waiting
	btn_retreat.disabled = battle.is_over or waiting
	_refresh_commands()

# Cara y nombre de quien dirige el pelotón elegido (al pulsar la cara se ve su retrato completo).
var _leader_row: HBoxContainer

func _show_leader(unit: BattleUnit) -> void:
	if _leader_row != null:
		_leader_row.queue_free()
		_leader_row = null
	var leader: Character = unit.leader() if unit != null else null
	if leader == null:
		return
	_leader_row = HBoxContainer.new()
	_leader_row.add_theme_constant_override("separation", 10)
	var mine := battle.is_player_unit(unit)
	var frame := BattleBoard.COMPANION_BADGE_COLOR if unit.companion != null else board.unit_color(unit)
	_leader_row.add_child(FaceIcon.make(leader, 52, frame))
	var who := Label.new()
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var post := "Compañero al mando" if unit.companion != null else "Tú" if leader == GameManager.player_character \
		else "Comandante" if leader == battle.attacker_cmd or leader == battle.defender_cmd else "Capitán"
	who.text = "%s\n%s · %s" % [leader.full_name(), post, "tu bando" if mine else "aliado" if battle.is_friendly(unit) else "enemigo"]
	_leader_row.add_child(who)
	unit_info_label.get_parent().add_child(_leader_row)
	unit_info_label.get_parent().move_child(_leader_row, unit_info_label.get_index())

# Barra de fuerzas: tu parte en azul sobre fondo rojo (el enemigo).
func _style_forces_bar() -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = BattleBoard.PLAYER_COLOR
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = BattleBoard.ENEMY_COLOR.darkened(0.25)
	bg.set_corner_radius_all(3)
	forces_bar.add_theme_stylebox_override("fill", fill)
	forces_bar.add_theme_stylebox_override("background", bg)

func _active_soldiers(side: int) -> int:
	var sum := 0
	for u: BattleUnit in battle.active_units(side):
		sum += u.soldiers
	return sum

func _on_log_message(text: String) -> void:
	log_lines.append(text)
	while log_lines.size() > MAX_LOG_LINES:
		log_lines.remove_at(0)
	LogView.show(log_label, "\n".join(log_lines))

func _on_battle_ended(winner_side: int, report: Dictionary) -> void:
	_close_prompt()
	var loot := CampalEncounters.battle_loot(battle, winner_side == battle.player_side and battle.retreating_side != battle.player_side)
	if not loot.is_empty():
		_on_log_message(loot)
		(func(): result_label.text += "\n\n" + loot).call_deferred()
	_challenge_mode = false
	_announce_general_fall(str(report.get("reason", "")))
	if not invited.is_empty():
		_end_invited(winner_side, report)
		return
	if not skirmish.is_empty():
		_end_skirmish(winner_side == battle.player_side, report, winner_side)
		return
	var attacker_won: bool = winner_side == BattleEnums.Side.ATACANTE
	var player_won: bool = winner_side == battle.player_side
	var betrayed := battle.betrayed_side >= 0
	# El resultado se aplica al mundo de inmediato, para que la batalla nunca quede a medias.
	# Si traicionaste, tu gente se va contigo: solo cuentan las tropas que no son tuyas.
	var consequences := ArmyData.resolve_battle(army, attacker_won,
		report.attacker_ai_survivors if betrayed else report.attacker_survivors,
		report.defender_ai_survivors if betrayed else report.defender_survivors, player_defending and not betrayed)
	var social := _social_aftermath(player_won, not betrayed)
	if not social.is_empty():
		consequences += "\n\n" + social
	if not GameManager.is_game_active:
		btn_back_to_map.text = "Volver al Menú"

	result_title.text = "¡Victoria!" if player_won else "Derrota"
	result_title.add_theme_color_override("font_color", Color("f0d48a") if player_won else Color("c9584c"))
	result_label.text = "%s\n\nAtacantes: %d → %d\nDefensores: %d → %d\nTurnos: %d\n\n%s" % [
		report.reason,
		report.attacker_initial, report.attacker_survivors,
		report.defender_initial, report.defender_survivors,
		report.turns, consequences]
	var aftermath := _aftermath(player_won, false)
	if not aftermath.is_empty():
		result_label.text += "\n\n" + aftermath
	if not report.get("wounded_companions", []).is_empty():
		result_label.text += "\n\nHeridos: %s." % ", ".join(report.wounded_companions)
	var caught := _captures(winner_side)
	if not caught.is_empty():
		result_label.text += "\n\n" + caught
	selected = null
	_refresh()
	# El resultado ya está aplicado; el cartel espera a que terminen de verse los últimos golpes.
	await get_tree().create_timer(board.fx_remaining() + 0.3).timeout
	Music.stop(0.8)
	Sfx.play("victory" if player_won else "defeat", 0.0, 0.0)
	result_overlay.visible = true
	btn_back_to_map.grab_focus.call_deferred()
	UiAnim.fade_in(result_panel, 0.3)

# Fin de una escaramuza: las bajas salen de tu guarnición y se aplica el desenlace del evento.
func _end_skirmish(player_won: bool, report: Dictionary, winner_side: int) -> void:
	var losses: int = report.attacker_initial - report.attacker_survivors
	var home: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	if home != null:
		home.garrison_size = maxi(0, home.garrison_size - losses)
	var outcome := CombatSetup.apply_outcome(player_won)
	CombatSetup.skirmish = {}
	var social := _social_aftermath(player_won, true)
	if not social.is_empty():
		outcome += "\n\n" + social
	result_title.text = "¡Victoria!" if player_won else "Derrota"
	result_title.add_theme_color_override("font_color", Color("f0d48a") if player_won else Color("c9584c"))
	result_label.text = "%s\n\nTus hombres: %d → %d (bajas en tu guarnición: %d)\nEnemigos: %d → %d\nTurnos: %d\n\n%s" % [
		report.reason, report.attacker_initial, report.attacker_survivors, losses,
		report.defender_initial, report.defender_survivors, report.turns, outcome]
	var aftermath := _aftermath(player_won, true)
	if not aftermath.is_empty():
		result_label.text += "\n\n" + aftermath
	if not report.get("wounded_companions", []).is_empty():
		result_label.text += "\n\nHeridos: %s." % ", ".join(report.wounded_companions)
	var caught := _captures(winner_side)
	if not caught.is_empty():
		result_label.text += "\n\n" + caught
	selected = null
	_refresh()
	await get_tree().create_timer(board.fx_remaining() + 0.3).timeout
	Music.stop(0.8)
	Sfx.play("victory" if player_won else "defeat", 0.0, 0.0)
	result_overlay.visible = true
	btn_back_to_map.grab_focus.call_deferred()
	UiAnim.fade_in(result_panel, 0.3)

# Fin de una batalla ajena: el asedio (o la batalla campal) se decide por lo que pasó en el tablero;
# tu anfitrión te recompensa y quienes lucharon contigo te aprecian más.
func _end_invited(winner_side: int, report: Dictionary) -> void:
	var player_won: bool = winner_side == battle.player_side
	var betrayed := battle.betrayed_side >= 0
	var lines: Array[String] = []
	if invited.kind == "army":
		if army != null and army.pending_battle and castle != null:
			var defending := ArmyData.is_player_defended(castle) and battle.player_side == BattleEnums.Side.DEFENSOR and not betrayed
			lines.append(ArmyData.resolve_battle(army, winner_side == BattleEnums.Side.ATACANTE,
				report.attacker_ai_survivors, report.defender_ai_survivors, defending))
	else:
		var enemy_castle: Castle = MapData.get_castle_by_id(str(invited.get("enemy_castle_id", "")))
		var ally_lost: int = maxi(0, int(invited.get("ally_soldiers", 0)) - int(report.attacker_ai_survivors))
		var enemy_lost: int = maxi(0, int(invited.get("enemy_soldiers", 0)) - int(report.defender_ai_survivors))
		castle.garrison_size = maxi(1, castle.garrison_size - ally_lost)
		if enemy_castle != null:
			enemy_castle.garrison_size = maxi(1, enemy_castle.garrison_size - enemy_lost)
		lines.append("La batalla campal cuesta %d hombres a %s y %d a %s." % [ally_lost, castle.castle_name, enemy_lost,
			enemy_castle.castle_name if enemy_castle != null else "el enemigo"])
		WorldEvents.record("Batalla campal junto a %s: %s." % [castle.castle_name, report.reason], castle.castle_id)
	if not betrayed:
		lines.append(ArmyData.invitation_reward(str(invited.get("inviter", "")), str(invited.get("lord", "")),
			int(report.get("own_initial", 0)), player_won))
	var lord_is_liege: bool = str(invited.get("lord", "")) == RelationsData.liege_name
	lines.append(_social_aftermath(player_won, lord_is_liege and not betrayed))
	CombatSetup.invited = {}
	if not GameManager.is_game_active:
		btn_back_to_map.text = "Volver al Menú"
	result_title.text = "¡Victoria!" if player_won else "Derrota"
	result_title.add_theme_color_override("font_color", Color("f0d48a") if player_won else Color("c9584c"))
	result_label.text = "%s\n\nTu gente: %d → %d\nAtacantes: %d → %d · Defensores: %d → %d\nTurnos: %d\n\n%s" % [
		report.reason, report.own_initial, report.own_survivors,
		report.attacker_initial, report.attacker_survivors, report.defender_initial, report.defender_survivors,
		report.turns, "\n".join(lines.filter(func(l: String) -> bool: return not l.is_empty()))]
	var aftermath := _aftermath(player_won, false)
	if not aftermath.is_empty():
		result_label.text += "\n\n" + aftermath
	if not report.get("wounded_companions", []).is_empty():
		result_label.text += "\n\nHeridos: %s." % ", ".join(report.wounded_companions)
	var caught := _captures(winner_side)
	if not caught.is_empty():
		result_label.text += "\n\n" + caught
	selected = null
	_refresh()
	await get_tree().create_timer(board.fx_remaining() + 0.3).timeout
	Music.stop(0.8)
	Sfx.play("victory" if player_won else "defeat", 0.0, 0.0)
	result_overlay.visible = true
	btn_back_to_map.grab_focus.call_deferred()
	UiAnim.fade_in(result_panel, 0.3)

# Lazos (quien luchó a tu lado te aprecia más) y, si traicionaste, tu nuevo juramento.
func _social_aftermath(player_won: bool, for_liege: bool) -> String:
	if not GameManager.is_game_active:
		return ""
	var allies: Array[Character] = battle.characters_on_side(battle.player_side)
	for c: Character in battle.companions_of(battle.player_side):
		if not c in allies:
			allies.append(c)
	allies.erase(GameManager.player_character)
	var lines: Array[String] = [ArmyData.battle_bonds(allies, player_won, for_liege)]
	if battle.betrayed_side >= 0:
		lines.append(_betrayal_text)
		var cmd: Character = battle._commander(battle.player_side)
		lines.append(ArmyData.defect_to(cmd.full_name() if cmd != null else ""))
	return "\n".join(lines.filter(func(l: String) -> bool: return not l.is_empty()))

# --- Duelos singulares entre jefes ---

func _challenge_hint() -> String:
	if selected == null or not battle.is_player_unit(selected):
		return "Elige uno de tus pelotones para que su jefe rete a duelo."
	if battle.has_walls:
		return "Solo en campo abierto: en un asedio nadie sale de la muralla a batirse."
	var targets := battle.challenge_targets(selected)
	if targets.is_empty():
		var any_enemy: BattleUnit = null
		for t: BattleUnit in battle.active_units(battle._other_side(battle.player_side)):
			any_enemy = t
			break
		return battle.challenge_blocker(selected, any_enemy) if any_enemy != null else "No hay jefes enemigos a la vista."
	return ""

func _on_challenge_pressed() -> void:
	if not _challenge_hint().is_empty() or _dueling:
		return
	var targets := battle.challenge_targets(selected)
	if targets.size() == 1:
		_issue_challenge(selected, targets[0])
		return
	_challenge_mode = not _challenge_mode
	_refresh()

## Tu jefe reta al de un pelotón enemigo: si acepta, juegas el duelo.
func _issue_challenge(u: BattleUnit, target: BattleUnit) -> void:
	_challenge_mode = false
	if not battle.can_challenge(u, target):
		return
	var mine := u.leader()
	var foe := target.leader()
	_on_log_message("%s reta a duelo singular a %s." % [mine.full_name(), foe.full_name()])
	if not battle.accepts_challenge(mine, foe):
		battle.refuse_challenge(u, target)
		_refresh()
		return
	var winner := await play_duel(mine, foe)
	battle.finish_challenge(u, target, winner == mine)
	if not battle.is_over and not u.is_active():
		selected = null
	_refresh()

## La IA reta a uno de tus jefes: tú decides, y si aceptas lo juegas.
func _on_challenge_offered(challenger: BattleUnit, target: BattleUnit) -> void:
	_close_prompt()
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 60
	add_child(overlay)
	_prompt = overlay
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	row.add_child(FaceIcon.make(challenger.leader(), 84, BattleBoard.ENEMY_COLOR))
	var vs := Label.new()
	vs.theme_type_variation = &"HeaderLabel"
	vs.text = "contra"
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vs)
	row.add_child(FaceIcon.make(target.leader(), 84, BattleBoard.PLAYER_COLOR))
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "%s reta a duelo singular a %s" % [challenger.leader().full_name(), target.leader().full_name()]
	box.add_child(title)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(560, 0)
	note.text = "Quien pierda se retira con su pelotón. Rehusar: −%d moral a tu bando." % BattleManager.CHALLENGE_REFUSE_MORALE
	box.add_child(note)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var accept := Button.new()
	accept.text = "Aceptar el duelo"
	accept.theme_type_variation = &"PrimaryButton"
	buttons.add_child(accept)
	var refuse := Button.new()
	refuse.text = "Rehusar"
	buttons.add_child(refuse)
	accept.pressed.connect(func(): _answer_challenge(true))
	refuse.pressed.connect(func(): _answer_challenge(false))
	accept.grab_focus.call_deferred()
	_refresh()

func _answer_challenge(accepted: bool) -> void:
	if battle.pending_challenge.is_empty():
		return
	_close_prompt()
	if not accepted:
		battle.answer_challenge(false)
		_refresh()
		return
	var challenger: BattleUnit = battle.pending_challenge.challenger
	var target: BattleUnit = battle.pending_challenge.target
	var winner := await play_duel(target.leader(), challenger.leader())
	battle.answer_challenge(true, winner != target.leader())
	_refresh()

func _close_prompt() -> void:
	if _prompt != null:
		_prompt.queue_free()
		_prompt = null

## Juega un duelo singular con el sistema de duelo de verdad, encima del tablero, con "fighter" de tu
## lado (tú o el jefe de tu pelotón). Devuelve el ganador (null si alguien huye: cuenta como derrota tuya).
func play_duel(fighter: Character, foe: Character) -> Character:
	_dueling = true
	_refresh()
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var duel_scene = load(COMBAT_SCENE).instantiate()
	duel_scene.player_character = fighter
	duel_scene.enemy_character = foe
	duel_scene.embedded = true
	layer.add_child(duel_scene)
	var winner: Character = await duel_scene.embedded_finished
	layer.queue_free()
	for c: Character in [fighter, foe]:
		c.after_fight_recovery()
	_dueling = false
	board.grab_focus.call_deferred()
	return winner

# --- Traición ---

const NO_FACTION := "Aquí solo luchas por ti: no hay bando al que traicionar."

func _betrayal_blocker() -> String:
	# Solo traiciona quien lucha por otro: en una batalla ajena o defendiendo el castillo de tu señor.
	var for_someone := not invited.is_empty() or (skirmish.is_empty() and player_defending and castle != null \
		and castle.owner_name != GameManager.player_character.full_name())
	if not for_someone:
		return NO_FACTION
	return battle.betrayal_blocker()

func _on_betray_pressed() -> void:
	if not _betrayal_blocker().is_empty() or _dueling:
		return
	if not _betray_armed:
		_betray_armed = true
		_refresh()
		return
	_betray_armed = false
	selected = null
	var text := battle.betray()
	_betrayal_text = ArmyData.apply_betrayal(battle.betrayed_characters, battle._commander(battle.player_side))
	var new_cmd: Character = battle._commander(battle.player_side)
	var old_cmd: Character = battle._commander(battle.betrayed_side)
	title_label.text = "%s\nTraición: ahora con %s contra %s" % [title_label.text.get_slice("\n", 0),
		new_cmd.full_name() if new_cmd != null else "el enemigo", old_cmd.full_name() if old_cmd != null else "los tuyos"]
	_show_banner(text, BattleBoard.ENEMY_COLOR.lightened(0.4))
	_on_log_message(_betrayal_text)
	_refresh()

## Capturas: los jefes vencidos pueden caer presos (los tuyos, o tú; y los del enemigo, en tus manos).
func _captures(winner_side: int) -> String:
	var own_share := 1.0
	if battle.has_allies():
		own_share = float(battle._own_initial) / maxf(1.0, battle._own_initial + battle.ally_soldiers)
	return CaptureData.after_battle(battle, winner_side, {"own_share": own_share, "retreated": _retreated})

# Experiencia para ti y los compañeros que dirigieron un pelotón; y si tu ejército entero cae o huye
# contigo al mando, puedes caer con él.
func _aftermath(player_won: bool, skirmish_fight: bool) -> String:
	var player: Character = GameManager.player_character
	if player == null or not GameManager.is_game_active:
		return ""
	var lines: Array[String] = []
	if not _retreated and not player_won and battle.active_units(battle.player_side).is_empty() and randf() < BATTLE_DEATH_CHANCE:
		var cause := "en una escaramuza en campo abierto" if skirmish_fight else "en la batalla de %s" % battle.location_name
		if DynastyData.has_method("on_player_died"):
			DynastyData.on_player_died(cause)
		result_title.text = "Has caído"
		return "☠ Tus tropas se deshacen a tu alrededor y caes %s. Tu dinastía buscará un heredero." % cause
	if battle.covering and battle._soldiers_own() > 0:
		player.gain_honor(BattleManager.COVER_HONOR)
		player.add_fame(BattleManager.COVER_FAME)
		lines.append("Cubriste la retirada: +%d de honor y +%d de fama." % [BattleManager.COVER_HONOR, BattleManager.COVER_FAME])
	if battle.deserted:
		player.honor = maxi(0, player.honor - BattleManager.DESERT_HONOR)
		lines.append("Abandonaste el campo sin orden del general: −%d de honor." % BattleManager.DESERT_HONOR)
	for g: Array in battle.mastery_gains:
		if g[0] == player.full_name():
			var prog: Array = player.mastery_progress(g[1])
			lines.append("Mando de %s: nivel %d%s." % [BattleEnums.family_name(g[1]).to_lower(), player.mastery(g[1]),
				" (¡sube!)" if g[2] > 0 else " (%d/%d)" % prog if prog[1] > 0 else ""])
	var amount: int = XpRules.BATTLE_LOSS
	if player_won:
		amount = XpRules.SKIRMISH_WIN + XpRules.EVENT_FIGHT_WIN if skirmish_fight else XpRules.BATTLE_WIN
	lines.append(_xp_line(player, amount, true))
	for c: Character in battle.companions_of(battle.player_side):
		lines.append(_xp_line(c, roundi(amount * COMPANION_XP_SHARE), false))
	return " ".join(lines).strip_edges()

func _xp_line(c: Character, amount: int, is_player: bool) -> String:
	if amount <= 0:
		return ""
	var levels := c.gain_xp(amount, XpRules.SOURCE_BATTLE)
	amount = c.last_xp_gained
	var who := "" if is_player else c.first_name + ": "
	return "%sExperiencia +%d.%s" % [who, amount, " ¡Sube a nivel %d!" % c.level if levels > 0 else ""]

func _on_back_to_map_pressed() -> void:
	if not GameManager.is_game_active:
		GameManager.change_state(GameStateEnums.State.MENU)
		get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
		return
	GameManager.change_state(GameStateEnums.State.MAP)
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")

# T o el botón Y del mando terminan el turno. H/C/R dan órdenes al pelotón elegido; 1–9, habilidades.
func _unhandled_input(event: InputEvent) -> void:
	if battle == null or battle.is_over or _dueling or not battle.pending_challenge.is_empty():
		return
	if event.is_action_pressed("end_turn"):
		get_viewport().set_input_as_handled()
		_on_end_turn_pressed()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		if ORDER_KEYS.has(key):
			_give_order(ORDER_KEYS[key])
		elif key == WITHDRAW_KEY:
			_give_order(-1)
		elif key == CHALLENGE_KEY:
			_on_challenge_pressed()
		elif key >= KEY_1 and key <= KEY_9 and key - KEY_1 < _ability_buttons.size():
			var entry: Array = _ability_buttons[key - KEY_1]
			_use_ability(entry[1], entry[2])
		else:
			return
		get_viewport().set_input_as_handled()

# --- Choques RPG (fase 4) ---

var _encounters_running := false
static var test_auto_encounters := false   # pruebas: los choques se resuelven con «Resolver» sin preguntar

## Juega uno a uno los choques con tu grupo: «Luchar» abre la pantalla RPG; «Resolver», con las mismas reglas.
func _play_encounters() -> void:
	if _encounters_running:
		return
	_encounters_running = true
	while not battle.pending_encounters.is_empty() and not battle.is_over:
		var enc: Dictionary = battle.pending_encounters[0]
		_dueling = true
		_refresh()
		var fight: bool = await _ask_encounter(enc)
		if battle.is_over:
			break
		if fight:
			battle.resolve_encounter(enc, await play_encounter(enc))
		else:
			battle.auto_resolve_pending(enc)
	_dueling = false
	_encounters_running = false
	if selected != null and not selected.is_active():
		selected = null
	_refresh()
	board.grab_focus.call_deferred()

signal _encounter_choice(fight: bool)

func _ask_encounter(enc: Dictionary) -> bool:
	if test_auto_encounters:
		await get_tree().process_frame
		return false
	_close_prompt()
	var fi := CampalEncounters.friendly_index(battle, enc)
	var mine: Array = enc.a if fi == 0 else enc.b
	var foes: Array = enc.b if fi == 0 else enc.a
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 60
	add_child(overlay)
	_prompt = overlay
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	row.add_child(FaceIcon.make(mine[0], 72, BattleBoard.PLAYER_COLOR))
	var vs := Label.new()
	vs.theme_type_variation = &"HeaderLabel"
	vs.text = "contra"
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vs)
	row.add_child(FaceIcon.make(foes[0], 72, BattleBoard.ENEMY_COLOR))
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "¡Choque! %d contra %d" % [mine.size(), foes.size()]
	box.add_child(title)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(520, 0)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var mu: BattleUnit = enc.attacker if fi == 0 else enc.target
	var fu: BattleUnit = enc.target if fi == 0 else enc.attacker
	note.text = "Tus %d soldados contra %d. Perder cuesta bajas y moral; retirarse a tiempo, menos." % [mu.soldiers, fu.soldiers]
	box.add_child(note)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var fight := Button.new()
	fight.text = "Luchar"
	fight.theme_type_variation = &"PrimaryButton"
	buttons.add_child(fight)
	var auto := Button.new()
	auto.text = "Resolver"
	auto.tooltip_text = "Se resuelve solo, con las mismas reglas."
	buttons.add_child(auto)
	fight.pressed.connect(func(): _encounter_choice.emit(true))
	auto.pressed.connect(func(): _encounter_choice.emit(false))
	fight.grab_focus.call_deferred()
	var choice: bool = await _encounter_choice
	_close_prompt()
	return choice

## Juega el choque en la pantalla RPG (tu grupo abajo). Devuelve el resultado con el bando 0 = atacante.
func play_encounter(enc: Dictionary) -> Dictionary:
	var fi := CampalEncounters.friendly_index(battle, enc)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var scene = load(COMBAT_SCENE).instantiate()
	scene.side_a = enc.a if fi == 0 else enc.b
	scene.side_b = enc.b if fi == 0 else enc.a
	scene.player_character = scene.side_a[0]
	scene.enemy_character = scene.side_b[0]
	scene.embedded = true
	# La salud de la batalla (no la del personaje): se pone antes y se restaura al terminar.
	var saved := {}
	for c in enc.a + enc.b:
		if c is Character and not CampalEncounters.is_generic(c) and c.max_health > 0:
			saved[c] = c.current_health
			c.current_health = maxi(1, roundi(c.max_health * float(battle.encounter_hp.get(c, float(c.current_health) / c.max_health))))
	layer.add_child(scene)
	await scene.embedded_finished
	var result: Dictionary = scene.last_result.duplicate()
	layer.queue_free()
	for c: Character in saved:
		c.current_health = saved[c]
	if fi == 1:   # en la pantalla tu grupo es el bando 0: se da la vuelta
		for k in ["winner", "retreated", "surrendered"]:
			var v := int(result.get(k, -1))
			result[k] = 1 - v if v >= 0 else v
	return result
