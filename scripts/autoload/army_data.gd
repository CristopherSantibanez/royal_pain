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
	return castle.castle_id == GameManager.home_castle_id or castle.owner_name == player.full_name()

func set_destination(army: Army, destination_castle_id: String) -> bool:
	if not army.is_idle():
		return false
	var origin: Castle = MapData.get_castle_by_id(army.current_castle_id)
	if origin == null:
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

	armies_changed.emit()
	events_changed.emit()

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
	elif is_player_defended(destination):
		_add_event("¡%s asedia %s con %d soldados! Defiéndelo antes de avanzar el turno." % [
			army.owner_name, destination.castle_name, army.size], destination.castle_id)
		battle_pending.emit(army)
	else:
		_auto_resolve_battle(army)

func _auto_resolve_battle(army: Army) -> void:
	var castle: Castle = MapData.get_castle_by_id(army.current_castle_id)
	if castle == null:
		disband_army(army)
		return
	var defending := is_player_defended(castle)
	var r := KingdomAI.auto_resolve(army.size, castle.garrison_size,
		KingdomAI.PLAYER_SIDE_UNPLAYED_FACTOR if defending else 1.0)
	var summary := resolve_battle(army, r.attacker_won, r.attacker_survivors, r.defender_survivors, defending)
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
	var reason := "%s ha caído y no te queda ningún castillo donde refugiarte." % lost.castle_name
	lines.append(reason + " Fin de la partida.")
	GameManager.end_game(reason)

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
	c.kingdom = c.original_kingdom
	c.owner_name = c.original_owner
	_add_event("¡Rebelión en %s! El pueblo se alza y devuelve el castillo a %s (%s)." % [
		c.castle_name, c.original_owner, KingdomEnums.kingdom_name(c.original_kingdom)], c.castle_id)
	armies_changed.emit()
