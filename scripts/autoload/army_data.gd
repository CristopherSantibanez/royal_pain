extends Node
# Autoload — registrar como "ArmyData"

signal armies_changed
signal battle_pending(army: Army)
signal events_changed

# --- Balance de resultados de batalla ---
const VICTORY_HONOR := 10
const DEFEAT_HONOR := 5
const LOOT_FRACTION := 0.3   # parte del oro del castillo conquistado que se lleva el jugador
const FAME_CONQUEST := 8     # fama por conquistar un castillo
const FAME_DEFENSE := 5      # ...por rechazar un asalto a tu castillo
const FAME_DEFEAT := -3      # ...y la que se pierde con una derrota

# --- Asedio: un ejército del jugador que espera ante un castillo enemigo lo desgasta cada mes ---
const SIEGE_ATTRITION := 0.08           # guarnición que pierde el castillo sitiado al mes
const SIEGE_STARVED_ATTRITION := 0.15   # ...si además se quedó sin comida
const SIEGE_UPKEEP_PER_SOLDIERS := 10   # el jugador paga 1 de oro al mes por cada 10 sitiadores
const SIEGE_UNPAID_DESERTION := 0.05    # sin paga, desertan sitiadores
const COMMAND_LEADERSHIP_GAIN := 1      # Liderazgo por batalla ganada al mando (máx. una vez al mes)
const MAX_STAT := 20
const BuildingCatalog = preload("res://scripts/resources/building_catalog.gd")
const InvitationCatalog = preload("res://scripts/resources/invitation_catalog.gd")

# --- Llamadas a filas: te invitan a unirte a un ejército de la IA ---
const INVITE_MIN_AFFINITY := 20         # un señor que te aprecia así te llama...
const INVITE_MIN_INTIMACY := 40         # ...o alguien de su corte con quien tienes esta intimidad...
const INVITE_MIN_FAME := 25             # ...o el señor de la zona donde estás, si tu fama te precede
const INVITE_CHANCE := 0.85             # no todos los que pueden llamarte lo hacen (tu señor, siempre)
const FIELD_INVITE_CHANCE := 0.4        # cada mes, con una guerra en tu zona: batalla campal
const INVITE_WIN_GOLD_PER_SOLDIER := 2  # tu anfitrión paga a tu gente si vencéis
const INVITE_WIN_GOLD_MIN := 20
const INVITE_WIN_FAME := 4
const INVITE_WIN_RELATION := 6
# --- Lazos de batalla: quien lucha a tu lado te aprecia más ---
const BATTLE_BOND_WIN := 5
const BATTLE_BOND_LOSS := 2
const LIEGE_BATTLE_AFFINITY := 3        # tu señor agradece cada victoria por su reino
# --- Traición en plena batalla ---
const BETRAYAL_RELATION := -40          # afinidad e intimidad de quienes la vieron desde el bando traicionado
const BETRAYAL_GRUDGE := 40             # ...y su rencor (pueden volverse rivales)
const BETRAYAL_NEW_SIDE := 10           # el bando al que te pasas te recibe con cierta gratitud
const BETRAYAL_HONOR := 25
const BETRAYAL_FAME := 5

var armies: Array[Army] = []
var _next_id: int = 1

# Ejército cuya batalla se está jugando en la escena de batalla táctica.
var active_battle_army: Army

# Noticias del último turno: [{text, castle_id}]. El mapa muestra las que el jugador puede ver.
var turn_events: Array[Dictionary] = []

func _ready() -> void:
	GameManager.turn_advanced.connect(_on_turn_advanced)
	GameManager.game_started.connect(func(_character: Character): reset())

func reset() -> void:
	armies.clear()
	_next_id = 1
	active_battle_army = null
	turn_events.clear()
	armies_changed.emit()
	events_changed.emit()

func create_army(owner_name: String, kingdom: int, size: int, castle_id: String) -> Army:
	var a := Army.new()
	a.army_id = "army_%d" % _next_id
	_next_id += 1
	a.owner_name = owner_name
	a.kingdom = kingdom
	a.size = size
	a.current_castle_id = castle_id
	armies.append(a)
	armies_changed.emit()
	return a

# Suma tropas del jugador a su ejército parado en ese castillo (o crea uno nuevo si no hay).
func add_player_troops(castle_id: String, kingdom: int, size: int) -> Army:
	var existing := idle_player_army_at(castle_id)
	if existing != null:
		existing.size += size
		armies_changed.emit()
		return existing
	return create_army(GameManager.player_character.full_name(), kingdom, size, castle_id)

func idle_player_army_at(castle_id: String) -> Army:
	for a: Army in armies:
		if a.current_castle_id == castle_id and a.is_idle() and is_player_army(a):
			return a
	return null

func idle_player_armies_at(castle_id: String) -> Array[Army]:
	var result: Array[Army] = []
	for a: Army in armies:
		if a.current_castle_id == castle_id and a.is_idle() and is_player_army(a):
			result.append(a)
	return result

# Reúne en uno todos los ejércitos parados del jugador en un castillo. Devuelve el resultante (o null).
func merge_armies(castle_id: String) -> Army:
	var group := idle_player_armies_at(castle_id)
	if group.is_empty():
		return null
	var main: Army = group[0]
	for i in range(1, group.size()):
		main.size += group[i].size
		armies.erase(group[i])
	armies_changed.emit()
	return main

# Un ejército propio parado en un castillo propio vuelve a la guarnición.
func garrison_army(army: Army) -> bool:
	var castle: Castle = MapData.get_castle_by_id(army.current_castle_id)
	if castle == null or not army.is_idle() or castle.kingdom != army.kingdom:
		return false
	castle.garrison_size += army.size
	disband_army(army)
	return true

func get_armies_at(castle_id: String) -> Array[Army]:
	var result: Array[Army] = []
	for a: Army in armies:
		if a.current_castle_id == castle_id:
			result.append(a)
	return result

func get_player_armies() -> Array[Army]:
	var result: Array[Army] = []
	for a: Army in armies:
		if is_player_army(a):
			result.append(a)
	return result

func is_player_army(army: Army) -> bool:
	var player: Character = GameManager.player_character
	return player != null and army.owner_name == player.full_name()

# Un castillo lo defiende el jugador si es su castillo de origen o uno que conquistó.
func is_player_defended(castle: Castle) -> bool:
	var player: Character = GameManager.player_character
	if castle == null or player == null:
		return false
	# El no afiliado no tiene hogar que defender: solo cuenta lo que sea suyo.
	var home := castle.castle_id == GameManager.home_castle_id and player.role != Character.Role.INAFILIADO
	return home or castle.owner_name == player.full_name()

func set_destination(army: Army, destination_castle_id: String) -> bool:
	if not army.is_idle():
		return false
	var origin: Castle = MapData.get_castle_by_id(army.current_castle_id)
	if origin == null:
		return false
	# Un campesino no lleva ejércitos contra nadie (solo lucha si lo llaman a filas).
	var target_castle: Castle = MapData.get_castle_by_id(destination_castle_id)
	if is_player_army(army) and target_castle != null and target_castle.kingdom != army.kingdom \
			and not CombatSetup.battle_blocker(GameManager.player_character).is_empty():
		return false
	# Habilidades del comandante: Viajero permite marchar a 2 saltos; Paso Invernal evita
	# que el invierno (diciembre a febrero) duplique la duración de la marcha.
	var commander := army_commander(army)
	var hops := SkillEffects.max_march_hops(commander) if is_player_army(army) else 1
	if not destination_castle_id in SkillEffects.march_destinations(origin.castle_id, MapData.castles, hops):
		return false

	army.origin_castle_id = army.current_castle_id
	army.destination_castle_id = destination_castle_id
	army.turns_remaining = SkillEffects.march_turns(GameManager.current_month, commander)

	# Diplomacia: marchar contra un señor sin guerra declarada (o contra un aliado) tiene consecuencias.
	var target: Castle = MapData.get_castle_by_id(destination_castle_id)
	if is_player_army(army) and target != null and target.kingdom != army.kingdom:
		var note: String = RelationsData.on_player_marches_against(target.owner_name)
		if not note.is_empty():
			_add_event(note, target.castle_id)
			events_changed.emit()

	armies_changed.emit()
	return true

# El jugador comanda sus ejércitos; los de la IA los comanda el señor que los movilizó.
func army_commander(army: Army) -> Character:
	if is_player_army(army):
		return GameManager.player_character
	return RelationsData.character_of(army.owner_name)

func disband_army(army: Army) -> void:
	armies.erase(army)
	armies_changed.emit()

func _add_event(text: String, castle_id: String) -> void:
	turn_events.append({"text": text, "castle_id": castle_id})
	WorldEvents.record(text, castle_id)   # la crónica guarda todas las noticias, no solo las del mes

# --- Turno mensual ---

func _on_turn_advanced(_month: int, _year: int) -> void:
	turn_events.clear()

	# 1. Las defensas que el jugador no jugó se resuelven solas; sus asedios desgastan al castillo.
	for a: Army in armies.duplicate():
		if a.pending_battle and not is_player_army(a):
			_auto_resolve_battle(a)
		elif a.pending_battle:
			_siege_month(a)

	# 2. Movimiento (se recorre una copia: las llegadas pueden disolver ejércitos).
	for a: Army in armies.duplicate():
		if a.pending_battle or a.destination_castle_id == "":
			continue
		a.turns_remaining -= 1
		if a.turns_remaining <= 0:
			_resolve_arrival(a)

	# 3. Reclutamiento natural, paga y comida de las guarniciones, rentas del jugador y edicto del Regente.
	KingdomAI.recruit(MapData.castles)
	var own_castles: Array[String] = []
	for c: Castle in MapData.castles:
		if is_player_defended(c):
			own_castles.append(c.castle_id)
	var upkeep_factor := SkillEffects.upkeep_multiplier(GameManager.player_character) if GameManager.player_character != null else 1.0
	for t: Dictionary in KingdomAI.castle_economy(MapData.castles, SkillEffects.is_winter(GameManager.current_month), own_castles, upkeep_factor):
		var c: Castle = t.castle
		_add_event("Por %s, %d soldados abandonan %s." % [t.reason, t.lost, c.castle_name], c.castle_id)
	var player: Character = GameManager.player_character
	if player != null and player.rent > 0:
		player.gold += player.rent
	_buildings_month(own_castles)
	var edict_note := EdictCatalog.apply_monthly(GameManager.active_edict, GameManager.player_character,
		MapData.castles, GameManager.player_kingdom, RelationsData.relations)
	if not edict_note.is_empty():
		_add_event(edict_note, GameManager.home_castle_id)

	# 4. Diplomacia entre reinos y rebeliones; luego los reinos de la IA deciden nuevos ataques.
	if GameManager.is_game_active:
		for news: Dictionary in KingdomDiplomacy.monthly_update(MapData.castles, RelationsData.kingdom_wars,
				RelationsData.kingdom_alliances, GameManager.months_elapsed(), GameManager.player_kingdom):
			_add_event(news.text, news.castle_id)
			# Las declaraciones de guerra se avisan aunque ocurran lejos: cambian el equilibrio del mundo.
			if news.get("kind", "") == "war":
				WorldEvents.notify("Declaración de guerra", news.text)
		_check_rebellions()
		_run_kingdom_ai()
		_maybe_field_invitation()

	armies_changed.emit()
	events_changed.emit()

# Obras en curso de todos los castillos, efectos de la Capilla del castillo del jugador y obras de la IA.
func _buildings_month(own_castles: Array[String]) -> void:
	for c: Castle in MapData.castles:
		var done := c.advance_construction()
		if done.is_empty():
			continue
		var text := "Terminan las obras en %s: %s (nivel %d)." % [c.castle_name, BuildingCatalog.building_name(done), c.building_level(done)]
		if c.castle_id in own_castles:
			_add_event(text, c.castle_id)
			WorldEvents.notify("Obras terminadas", text)
		elif MapVision.get_visible_castle_ids(GameManager.player_character.role if GameManager.player_character != null else 0,
				GameManager.home_castle_id).has(c.castle_id):
			_add_event(text, c.castle_id)
	var player: Character = GameManager.player_character
	var home: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	if player != null and home != null:
		# Los caballeros y soldados también disfrutan de los edificios del castillo de su señor.
		player.current_health = mini(player.max_health, player.current_health + int(home.building_value("capilla", "heal")))
		var honor := int(home.building_value("capilla", "honor"))
		if honor > 0:
			player.gain_honor(honor)
	if GameManager.is_game_active:
		KingdomAI.plan_constructions(MapData.castles, own_castles)

func _run_kingdom_ai() -> void:
	var player_name: String = GameManager.player_character.full_name() if GameManager.player_character != null else ""
	var player_castle_ids: Array[String] = []
	for c: Castle in MapData.castles:
		if is_player_defended(c):
			player_castle_ids.append(c.castle_id)
	# Reinos cuyos señores están en guerra declarada con el jugador (las guerras del jugador viven en sus relaciones).
	var player_war_kingdoms: Array[int] = []
	for r: Relationship in RelationsData.lords():
		if r.at_war:
			for c: Castle in RelationsData.castles_of(r.person_name):
				if not c.kingdom in player_war_kingdoms:
					player_war_kingdoms.append(c.kingdom)
	var plans := KingdomAI.plan_attacks(MapData.castles, armies, GameManager.player_kingdom, GameManager.months_elapsed(), player_name,
		player_castle_ids, RelationsData.allied_kingdoms(), RelationsData.hostile_kingdoms(), RelationsData.kingdom_wars,
		player_war_kingdoms)
	for plan: Dictionary in plans:
		var origin: Castle = MapData.get_castle_by_id(plan.from_id)
		var target: Castle = MapData.get_castle_by_id(plan.to_id)
		if origin == null or target == null or plan.size <= 0:
			continue
		origin.garrison_size -= plan.size
		var army := create_army(origin.owner_name, origin.kingdom, plan.size, origin.castle_id)
		set_destination(army, target.castle_id)
		var warning := ""
		if is_player_defended(target):
			warning = " ¡Va hacia tu castillo!"
			RelationsData.on_attacked_by(origin.owner_name)
		_add_event("%s moviliza %d soldados desde %s hacia %s.%s" % [
			origin.owner_name, plan.size, origin.castle_name, target.castle_name, warning], target.castle_id)

func _resolve_arrival(army: Army) -> void:
	var destination: Castle = MapData.get_castle_by_id(army.destination_castle_id)
	if destination == null:
		# Castillo inválido, cancela la marcha para no dejar el ejército en el limbo.
		army.destination_castle_id = ""
		return

	army.current_castle_id = destination.castle_id
	army.destination_castle_id = ""

	if destination.kingdom == army.kingdom:
		if is_player_army(army):
			# El jugador conserva su ejército (para reunir fuerzas); si ya tenía otro allí, se juntan.
			merge_armies(destination.castle_id)
			return
		# Territorio aliado: el ejército de la IA se disuelve y refuerza la guarnición local.
		destination.garrison_size += army.size
		disband_army(army)
		return

	# Territorio enemigo: queda a la espera de batalla.
	army.pending_battle = true
	if is_player_army(army):
		battle_pending.emit(army)
	elif is_player_defended(destination) and CombatSetup.battle_blocker(GameManager.player_character).is_empty():
		_add_event("¡%s asedia %s con %d soldados! Defiéndelo antes de avanzar el turno." % [
			army.owner_name, destination.castle_name, army.size], destination.castle_id)
		battle_pending.emit(army)
	elif not offer_invitation(army):
		_auto_resolve_battle(army)

const AUTO_MASTERY_PER_LEVEL := 0.03   # +3% de fuerza por nivel de mando (mejor familia) del general

func _command_factor(owner_name: String) -> float:
	var c: Character = RelationsData.character_of(owner_name)
	if c == null:
		return 1.0
	return 1.0 + AUTO_MASTERY_PER_LEVEL * (c.mastery(c.best_family()) - 1)

func _auto_resolve_battle(army: Army) -> void:
	var castle: Castle = MapData.get_castle_by_id(army.current_castle_id)
	if castle == null:
		disband_army(army)
		return
	var defending := is_player_defended(castle)
	# Las murallas del castillo (ver Castle.wall_bonus) refuerzan la defensa.
	# El mando de cada general (su mejor familia de tropa) también pesa al resolverse sola.
	var r := KingdomAI.auto_resolve(army.size, castle.garrison_size,
		(KingdomAI.PLAYER_SIDE_UNPLAYED_FACTOR if defending else 1.0) * (1.0 + castle.wall_bonus()) * _command_factor(castle.owner_name),
		_command_factor(army.owner_name))
	var attacker_name := army.owner_name
	var defender_name := castle.owner_name
	var summary := resolve_battle(army, r.attacker_won, r.attacker_survivors, r.defender_survivors, defending)
	# Entre señores de la IA, el vencido puede caer preso del vencedor (ver CaptureData).
	if not defending:
		CaptureData.after_auto_battle(attacker_name if r.attacker_won else defender_name,
			defender_name if r.attacker_won else attacker_name)
	var prefix := "Sin tu mando, la defensa se libra sola: " if defending else ""
	_add_event(prefix + summary.replace("\n", " "), castle.castle_id)

# --- Resolución de batallas (escena táctica o auto-resolución) ---
# Devuelve un texto de resumen con las consecuencias en el mapa y para el jugador.

func resolve_battle(army: Army, attacker_won: bool, attacker_survivors: int, defender_survivors: int, player_defending: bool = false) -> String:
	var castle: Castle = MapData.get_castle_by_id(army.current_castle_id)
	if army == active_battle_army:
		active_battle_army = null
	if castle == null:
		disband_army(army)
		return "El castillo disputado ya no existe."

	var lines: Array[String] = []
	var player: Character = GameManager.player_character
	var player_attacking := is_player_army(army)

	if attacker_won:
		var old_kingdom: int = castle.kingdom
		var old_owner: String = castle.owner_name
		# Entre reinos de la IA, perder un castillo es casus belli: queda declarada la guerra.
		if not player_attacking and old_kingdom != GameManager.player_kingdom and army.kingdom != GameManager.player_kingdom:
			KingdomDiplomacy.declare_war(RelationsData.kingdom_wars, RelationsData.kingdom_alliances,
				old_kingdom, army.kingdom, GameManager.months_elapsed())
		castle.kingdom = army.kingdom
		castle.owner_name = army.owner_name
		castle.garrison_size = attacker_survivors
		disband_army(army)
		RelationsData.on_castle_taken(castle, old_kingdom, castle.kingdom)
		lines.append("%s cae en manos de %s (antes: %s). Guarnición: %d soldados." % [
			castle.castle_name, KingdomEnums.kingdom_name(castle.kingdom), KingdomEnums.kingdom_name(old_kingdom), attacker_survivors])
		if player_attacking and player != null:
			_grant_command_experience(lines)
			var loot := int(castle.gold * LOOT_FRACTION)
			castle.gold -= loot
			player.gold += loot
			player.honor = clamp(player.honor + VICTORY_HONOR, 0, 100)
			player.add_fame(FAME_CONQUEST)
			lines.append("Ganas %d de honor y %d de fama, y saqueas %d de oro." % [VICTORY_HONOR, FAME_CONQUEST, loot])
			var grudge: String = RelationsData.on_player_conquered(old_owner)
			if not grudge.is_empty():
				lines.append(grudge)
		elif player_defending:
			_apply_player_defeat(lines)
			if castle.castle_id == GameManager.home_castle_id:
				_handle_home_castle_lost(castle, lines)
	else:
		castle.garrison_size = defender_survivors
		lines.append("%s resiste el ataque con %d defensores." % [castle.castle_name, defender_survivors])
		_retreat_army(army, attacker_survivors, lines)
		if player_attacking:
			_apply_player_defeat(lines)
		elif player_defending and player != null:
			player.honor = clamp(player.honor + VICTORY_HONOR, 0, 100)
			player.add_fame(FAME_DEFENSE)
			lines.append("Defendiste tu castillo: ganas %d de honor y %d de fama." % [VICTORY_HONOR, FAME_DEFENSE])
			_grant_command_experience(lines)

	return "\n".join(lines)

# Ganar una batalla al mando enseña a liderar (como mucho una vez al mes).
func _grant_command_experience(lines: Array[String]) -> void:
	var player: Character = GameManager.player_character
	if player == null or player.leadership >= MAX_STAT or player.last_command_month == GameManager.months_elapsed():
		return
	player.last_command_month = GameManager.months_elapsed()
	player.leadership += COMMAND_LEADERSHIP_GAIN
	lines.append("La victoria curte tu mando: Liderazgo %d." % player.leadership)

# Un mes de asedio: el castillo pierde defensores (más si pasa hambre) y el jugador paga a sus sitiadores.
func _siege_month(army: Army) -> void:
	var castle: Castle = MapData.get_castle_by_id(army.current_castle_id)
	if castle == null:
		return
	var rate := SIEGE_STARVED_ATTRITION if castle.food <= 0 else SIEGE_ATTRITION
	var lost := maxi(1, int(castle.garrison_size * rate))
	castle.garrison_size = maxi(1, castle.garrison_size - lost)
	var text := "El asedio de %s se cobra %d defensores (quedan %d)." % [castle.castle_name, lost, castle.garrison_size]
	var player: Character = GameManager.player_character
	var upkeep: int = ceili(army.size / float(SIEGE_UPKEEP_PER_SOLDIERS))
	if player != null and player.gold >= upkeep:
		player.gold -= upkeep
		text += " Pagas %d de oro a tus sitiadores." % upkeep
	else:
		var deserters := maxi(1, int(army.size * SIEGE_UNPAID_DESERTION))
		army.size = maxi(1, army.size - deserters)
		text += " Sin oro para la paga, desertan %d de tus soldados." % deserters
	_add_event(text, castle.castle_id)

func _retreat_army(army: Army, survivors: int, lines: Array[String]) -> void:
	var origin: Castle = MapData.get_castle_by_id(army.origin_castle_id)
	if survivors <= 0 or origin == null:
		disband_army(army)
		lines.append("No quedan tropas que puedan replegarse: el ejército se disuelve.")
		return
	if is_player_army(army):
		army.size = survivors
		army.pending_battle = false
		army.current_castle_id = army.origin_castle_id
		army.destination_castle_id = ""
		armies_changed.emit()
		lines.append("Tu ejército se repliega a %s con %d soldados." % [origin.castle_name, survivors])
	else:
		# La IA no vuelve a dar órdenes a un ejército derrotado: sus restos regresan a la guarnición.
		if origin.kingdom == army.kingdom:
			origin.garrison_size += survivors
		disband_army(army)
		lines.append("Los %d sobrevivientes de %s se repliegan a %s." % [survivors, army.owner_name, origin.castle_name])

func _apply_player_defeat(lines: Array[String]) -> void:
	var player: Character = GameManager.player_character
	if player == null:
		return
	player.honor = clamp(player.honor - DEFEAT_HONOR, 0, 100)
	player.add_fame(FAME_DEFEAT)
	lines.append("Pierdes %d de honor y algo de fama." % DEFEAT_HONOR)
	if RoleProgression.check_dishonor_demotion(player):
		var old_role: int = player.role
		RoleProgression.apply_dishonor_demotion(player)
		GameManager.refresh_actions_for_role_change()
		lines.append("Caes en deshonra y desciendes de %s a %s." % [
			Character.role_name_for(old_role), player.role_name()])

func _handle_home_castle_lost(lost: Castle, lines: Array[String]) -> void:
	var player: Character = GameManager.player_character
	if player == null:
		return
	# Busca refugio en otro castillo conquistado por el jugador.
	for c: Castle in MapData.castles:
		if c != lost and c.owner_name == player.full_name():
			GameManager.home_castle_id = c.castle_id
			GameManager.current_castle = c
			lines.append("Pierdes tu hogar, pero te refugias en %s." % c.castle_name)
			return
	# Sin castillo propio sobrevives sin afiliación (RoleProgression.landless_role).
	var refuge := _landless_refuge(lost)
	if refuge == null:
		var reason := "%s ha caído y no te queda ningún castillo donde refugiarte." % lost.castle_name
		lines.append(reason + " Fin de la partida.")
		GameManager.end_game(reason)
		return
	var old_title := player.role_title()
	player.role = RoleProgression.landless_role(player)
	MissionData.leave_liege()
	GameManager.home_castle_id = refuge.castle_id
	GameManager.current_castle = refuge
	GameManager.refresh_actions_for_role_change()
	lines.append("%s ha caído y no te queda tierra propia. Huyes a %s: ya no eres %s, sino %s." % [
		lost.castle_name, refuge.castle_name, old_title, player.role_title()])

# Castillo donde se refugia quien lo pierde todo: uno de su reino, o el más cercano que no lo odie.
func _landless_refuge(lost: Castle) -> Castle:
	var best: Castle = null
	var best_d := INF
	for c: Castle in MapData.castles:
		if c == lost:
			continue
		var d := c.position_on_map.distance_to(lost.position_on_map) - (10000.0 if c.kingdom == GameManager.player_kingdom else 0.0)
		if d < best_d:
			best_d = d
			best = c
	return best

# --- Rebeliones en castillos conquistados por el jugador ---

func _check_rebellions() -> void:
	var player: Character = GameManager.player_character
	if player == null:
		return
	var tregua := GameManager.active_edict == EdictCatalog.TREGUA
	for c: Castle in MapData.castles:
		if c.owner_name != player.full_name() or c.castle_id == GameManager.home_castle_id:
			continue
		if c.original_kingdom < 0 or c.original_kingdom == c.kingdom:
			continue   # solo se sublevan los castillos arrebatados a otro reino
		if randf() < KingdomDiplomacy.rebellion_chance(player.honor, c.garrison_size, tregua):
			_rebel(c)

func _rebel(c: Castle) -> void:
	var lost := c.garrison_size - int(c.garrison_size * KingdomDiplomacy.REBEL_GARRISON_FACTOR)
	c.garrison_size = maxi(1, c.garrison_size - lost)
	var old_kingdom := c.kingdom
	c.kingdom = c.original_kingdom
	c.owner_name = c.original_owner
	RelationsData.on_castle_taken(c, old_kingdom, c.kingdom)
	_add_event("¡Rebelión en %s! El pueblo se alza y devuelve el castillo a %s (%s)." % [
		c.castle_name, c.original_owner, KingdomEnums.kingdom_name(c.original_kingdom)], c.castle_id)
	armies_changed.emit()

# --- Llamadas a filas (ver InvitationCatalog y CombatSetup.invited) ---

## Una batalla no espera: la llamada a filas ocupa el sitio de un suceso corriente del mes (no de
## otros asuntos, como los de tu familia o tu señor).
func _event_slot_free() -> bool:
	var e: Dictionary = GameManager.pending_event
	if e.is_empty():
		return true
	var id: String = e.get("id", "")
	return EventCatalog.EVENTS.any(func(ev: Dictionary) -> bool: return ev.id == id)

func find_army(army_id: String) -> Army:
	for a: Army in armies:
		if a.army_id == army_id:
			return a
	return null

## Si estás en el castillo asediado, en el de partida o al lado, alguien de un bando puede llamarte a filas.
## Devuelve true si dejó la llamada como evento pendiente (el asedio espera a tu respuesta).
func offer_invitation(army: Army) -> bool:
	var player: Character = GameManager.player_character
	var castle: Castle = MapData.get_castle_by_id(army.current_castle_id)
	if player == null or castle == null or not GameManager.is_game_active or not _event_slot_free():
		return false
	if not _player_near(castle, army.origin_castle_id):
		return false
	var best := {}
	for side: int in [BattleEnums.Side.ATACANTE, BattleEnums.Side.DEFENSOR]:
		var lord: String = army.owner_name if side == BattleEnums.Side.ATACANTE else castle.owner_name
		var lord_kingdom: int = army.kingdom if side == BattleEnums.Side.ATACANTE else castle.kingdom
		var enemy_kingdom: int = castle.kingdom if side == BattleEnums.Side.ATACANTE else army.kingdom
		var pick := _inviter_for(lord, lord_kingdom, enemy_kingdom)
		if not pick.is_empty() and (best.is_empty() or pick.score > best.score):
			pick["side"] = side
			best = pick
	if best.is_empty() or (not best.liege and randf() >= INVITE_CHANCE):
		return false
	GameManager.pending_event = InvitationCatalog.army_event(army, castle, best.side, best.lord, best.inviter, best.liege)
	_add_event("%s te llama a filas: %s está en juego." % [best.inviter, castle.castle_name], castle.castle_id)
	return true

## Quién de ese bando te llamaría (y con cuántas ganas). {} si nadie.
func _inviter_for(lord: String, lord_kingdom: int, enemy_kingdom: int) -> Dictionary:
	var player: Character = GameManager.player_character
	var r := RelationsData.get_relation(lord)
	if r == null or lord == player.full_name() or r.at_war or r.is_hostile():
		return {}
	# Nadie te pide luchar contra tu propio reino (salvo que no tengas afiliación).
	if enemy_kingdom == GameManager.player_kingdom and player.role != Character.Role.INAFILIADO:
		return {}
	var liege := lord == RelationsData.liege_name
	var score := -1.0
	var inviter := lord
	if liege:
		score = 200.0
	elif lord_kingdom == GameManager.player_kingdom:
		score = 100.0 + r.affinity
	elif r.affinity >= INVITE_MIN_AFFINITY or r.affection >= INVITE_MIN_INTIMACY:
		score = 50.0 + r.affinity
	elif lord_kingdom == _zone_kingdom() and (player.fame >= INVITE_MIN_FAME or player.role == Character.Role.INAFILIADO):
		score = 10.0 + player.fame
	# Alguien de su corte que te conoce bien puede hablar por ti.
	for c: Relationship in RelationsData.courtiers(lord_kingdom):
		if c.affection >= INVITE_MIN_INTIMACY and 30.0 + c.affection > score:
			score = 30.0 + c.affection
			inviter = c.person_name
	if score < 0.0:
		return {}
	return {"lord": lord, "inviter": inviter, "score": score, "liege": liege}

func _player_near(castle: Castle, origin_id: String = "") -> bool:
	var travel := get_node_or_null("/root/TravelData")
	var here: String = travel.current_castle_id() if travel != null else GameManager.home_castle_id
	return here == castle.castle_id or here == origin_id or here in castle.connected_castle_ids

func _zone_kingdom() -> int:
	var travel := get_node_or_null("/root/TravelData")
	return travel.zone_kingdom() if travel != null else GameManager.player_kingdom

## Declinas una llamada a filas: el asedio se libra sin ti ahora mismo.
func decline_invitation(army_id: String) -> void:
	var army := find_army(army_id)
	if army != null and army.pending_battle and not is_player_army(army):
		_auto_resolve_battle(army)
		armies_changed.emit()
		events_changed.emit()

# Con una guerra en tu zona, un señor puede llamarte a una batalla campal contra un castillo vecino.
func _maybe_field_invitation() -> void:
	var player: Character = GameManager.player_character
	if player == null or not _event_slot_free() or randf() >= FIELD_INVITE_CHANCE:
		return
	var travel := get_node_or_null("/root/TravelData")
	var here: Castle = travel.current_castle() if travel != null else MapData.get_castle_by_id(GameManager.home_castle_id)
	if here == null:
		return
	var options: Array = []
	for ally: Castle in [here] + here.connected_castle_ids.map(func(id: String): return MapData.get_castle_by_id(id)):
		if ally == null or ally.owner_name == player.full_name():
			continue
		for enemy_id: String in ally.connected_castle_ids:
			var enemy: Castle = MapData.get_castle_by_id(enemy_id)
			if enemy == null or enemy.kingdom == ally.kingdom or not KingdomDiplomacy.at_war(RelationsData.kingdom_wars, ally.kingdom, enemy.kingdom):
				continue
			if enemy.owner_name == player.full_name() or is_player_defended(enemy):
				continue
			var pick := _inviter_for(ally.owner_name, ally.kingdom, enemy.kingdom)
			if not pick.is_empty():
				options.append([pick, ally, enemy])
	if options.is_empty():
		return
	options.sort_custom(func(a: Array, b: Array) -> bool: return a[0].score > b[0].score)
	var best: Array = options[0]
	GameManager.pending_event = InvitationCatalog.field_event(best[1], best[2], best[0].lord, best[0].inviter, best[0].liege)

## El jugador se ofrece voluntario en el castillo donde está: si su reino está en guerra con un vecino,
## su señor lo manda a la batalla campal. Devuelve el evento (o {} si no hay guerra ni señor que lo acepte).
func volunteer_event(here: Castle) -> Dictionary:
	var player: Character = GameManager.player_character
	if player == null or here == null or here.owner_name == player.full_name():
		return {}
	var lord := RelationsData.get_relation(here.owner_name)
	if lord == null or lord.at_war or lord.is_hostile():
		return {}
	for enemy_id: String in here.connected_castle_ids:
		var enemy: Castle = MapData.get_castle_by_id(enemy_id)
		if enemy == null or enemy.kingdom == here.kingdom or not KingdomDiplomacy.at_war(RelationsData.kingdom_wars, here.kingdom, enemy.kingdom):
			continue
		if enemy.owner_name == player.full_name() or is_player_defended(enemy):
			continue
		return InvitationCatalog.field_event(here, enemy, here.owner_name, here.owner_name, false)
	return {}

## Soldados que salen a una batalla campal desde un castillo.
func field_battle_soldiers(castle: Castle) -> int:
	if castle == null:
		return CombatSetup.FIELD_BATTLE_MIN
	return maxi(CombatSetup.FIELD_BATTLE_MIN, roundi(castle.garrison_size * CombatSetup.FIELD_BATTLE_SHARE))

## Recompensa de tu anfitrión al terminar una batalla ajena.
func invitation_reward(inviter_name: String, lord_name: String, player_soldiers: int, won: bool) -> String:
	var player: Character = GameManager.player_character
	if player == null:
		return ""
	var lord := RelationsData.get_relation(lord_name)
	if not won:
		return "%s agradece que acudieras a su llamada." % lord_name
	var gold := maxi(INVITE_WIN_GOLD_MIN, player_soldiers * INVITE_WIN_GOLD_PER_SOLDIER)
	player.gold += gold
	player.add_fame(INVITE_WIN_FAME)
	if lord != null:
		lord.adjust(INVITE_WIN_RELATION)
		lord.adjust_affection(INVITE_WIN_RELATION)
	var inviter := RelationsData.get_relation(inviter_name)
	if inviter != null and inviter != lord:
		inviter.adjust_affection(INVITE_WIN_RELATION)
	return "%s te recompensa: %d de oro para tu gente, fama +%d y su afecto (+%d)." % [lord_name, gold, INVITE_WIN_FAME, INVITE_WIN_RELATION]

## Quienes lucharon a tu lado (compañeros, jefes aliados, tu anfitrión) te aprecian más. Devuelve el texto.
func battle_bonds(allies: Array[Character], won: bool, for_liege: bool) -> String:
	var amount := BATTLE_BOND_WIN if won else BATTLE_BOND_LOSS
	var names: Array[String] = []
	for c: Character in allies:
		var r := RelationsData.get_relation(c.full_name())
		if r == null:
			continue
		r.adjust_affection(amount)
		if r.kind == Relationship.Kind.SENOR:
			r.adjust(amount)
		names.append(r.person_name)
	var liege := RelationsData.get_relation(RelationsData.liege_name)
	if for_liege and won and liege != null:
		liege.adjust(LIEGE_BATTLE_AFFINITY)
	if names.is_empty():
		return ""
	return "Luchar codo con codo os une: %s (intimidad +%d)." % [", ".join(names), amount]

## Consecuencias inmediatas de pasarte al enemigo en plena batalla. Devuelve el texto.
func apply_betrayal(witnesses: Array[Character], new_commander: Character) -> String:
	var player: Character = GameManager.player_character
	if player == null:
		return ""
	var names: Array[String] = []
	for c: Character in witnesses:
		var r := RelationsData.get_relation(c.full_name())
		if r == null:
			continue
		r.adjust(BETRAYAL_RELATION)
		r.adjust_affection(BETRAYAL_RELATION)
		r.adjust_grudge(BETRAYAL_GRUDGE)
		r.allied = false
		names.append(r.person_name)
	if new_commander != null:
		var welcome := RelationsData.get_relation(new_commander.full_name())
		if welcome != null:
			welcome.adjust(BETRAYAL_NEW_SIDE)
			welcome.adjust_affection(BETRAYAL_NEW_SIDE)
	player.honor = clampi(player.honor - BETRAYAL_HONOR, 0, 100)
	player.add_fame(-BETRAYAL_FAME)
	var text := "Traicionas a tu bando: honor −%d, fama −%d." % [BETRAYAL_HONOR, BETRAYAL_FAME]
	if not names.is_empty():
		text += " %s no lo %s." % [", ".join(names), "olvidarán" if names.size() > 1 else "olvidará"]
	RelationsData.relations_changed.emit()
	return text

## Tras la batalla, el traidor jura lealtad al señor del bando al que se pasó (si tiene tierras);
## si nadie lo acoge, vende su espada. Devuelve el texto.
func defect_to(lord_name: String) -> String:
	var player: Character = GameManager.player_character
	if player == null:
		return ""
	var lord := RelationsData.get_relation(lord_name)
	var lands := RelationsData.castles_of(lord_name)
	if lord == null or lands.is_empty() or lord_name == player.full_name():
		var old_title := player.role_title()
		player.role = RoleProgression.landless_role(player)
		MissionData.leave_liege()
		GameManager.refresh_actions_for_role_change()
		return "Nadie te acoge tras la traición: de %s pasas a %s que vende su espada." % [old_title, player.role_title()]
	var castle: Castle = lands[0]
	var old_liege := RelationsData.get_relation(RelationsData.liege_name)
	if old_liege != null and old_liege != lord:
		old_liege.adjust(BETRAYAL_RELATION)
		old_liege.allied = false
	for c: Castle in RelationsData.castles_of(player.full_name()):
		var was := c.kingdom
		c.kingdom = castle.kingdom
		RelationsData.on_castle_taken(c, was, c.kingdom)
	for a: Army in armies:
		if is_player_army(a):
			a.kingdom = castle.kingdom
	for m: Dictionary in MissionData.active.duplicate():
		if not RelationsData.liege_name.is_empty() and str(m.get("giver", "")) == RelationsData.liege_name:
			MissionData.abandon(str(m.uid))
	var old_kingdom := GameManager.player_kingdom
	GameManager.player_kingdom = castle.kingdom
	GameManager.home_castle_id = castle.castle_id
	RelationsData.liege_name = lord_name
	var travel := get_node_or_null("/root/TravelData")
	if travel != null and "last_fealty_month" in travel:
		travel.last_fealty_month = GameManager.months_elapsed()
	var text := "Juras lealtad a %s: %s es tu nuevo hogar." % [lord_name, castle.castle_name]
	var rp: Script = RoleProgression
	if rp.has_method("on_fealty_sworn"):
		var extra = rp.call("on_fealty_sworn", player, castle)
		if extra is String and not extra.is_empty():
			text += " " + extra
	GameManager.refresh_actions_for_role_change()
	WorldEvents.record("%s traiciona a los suyos en plena batalla y pasa de %s a %s." % [player.full_name(),
		KingdomEnums.kingdom_name(old_kingdom) if old_kingdom >= 0 else "ningún reino", KingdomEnums.kingdom_name(castle.kingdom)], castle.castle_id, true)
	RelationsData.relations_changed.emit()
	return text
