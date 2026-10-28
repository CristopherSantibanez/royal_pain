extends Node
# Autoload "AchievementData": el libro de hazañas (recompensas, no fin de partida) y los únicos
# finales con victoria: dominar el mundo (tu reino, lo gobiernes tú o tu señor) o unificar los dos
# últimos reinos por matrimonio. Los finales con derrota (morir sin heredero, ser ejecutado sin
# heredero) van por DynastyData.

const AchievementCatalog = preload("res://scripts/resources/achievement_catalog.gd")
const UniqueItems = preload("res://scripts/resources/unique_items.gd")

signal achievement_unlocked(id: String)
signal ending_reached(ending: Dictionary)

const ENDING_CONQUEST := "conquista"
const ENDING_UNIFICATION := "unificacion"
const NEXT_SHOWN := 3          # hazañas más cercanas que se muestran en «Tu destino»

var achieved := {}               # id -> meses transcurridos al cumplirla
var visited_castles: Array[String] = []
var visited_kingdoms: Array[int] = []
var generation := 1              # 1 = el fundador; sube con cada heredero que toma el relevo
var ending_done := ""            # final ya alcanzado (no se repite)
var pending_ending: Dictionary = {}   # final por mostrar en el mapa
var _player_name := ""
var _check_queued := false

func _ready() -> void:
	GameManager.game_started.connect(func(_character: Character): reset())
	GameManager.turn_advanced.connect(func(_m: int, _y: int): queue_check())
	GameManager.event_resolved.connect(func(_t: String): queue_check())
	RelationsData.relations_changed.connect(queue_check)
	MissionData.missions_changed.connect(queue_check)
	ArmyData.armies_changed.connect(queue_check)
	DynastyData.family_changed.connect(queue_check)
	TravelData.location_changed.connect(_on_location_changed)

func reset() -> void:
	achieved.clear()
	visited_castles.clear()
	visited_kingdoms.clear()
	generation = 1
	ending_done = ""
	pending_ending = {}
	var player: Character = GameManager.player_character
	_player_name = player.full_name() if player != null else ""
	_mark_visited(GameManager.home_castle_id)

func _on_location_changed(castle_id: String) -> void:
	_mark_visited(castle_id)
	queue_check()

func _mark_visited(castle_id: String) -> void:
	var castle := MapData.get_castle_by_id(castle_id)
	if castle == null:
		return
	if not castle_id in visited_castles:
		visited_castles.append(castle_id)
	if castle.kingdom != KingdomEnums.Kingdom.NEUTRAL and not int(castle.kingdom) in visited_kingdoms:
		visited_kingdoms.append(int(castle.kingdom))

# --- Comprobación ---

## Las comprobaciones se agrupan al final del frame: muchas señales pueden llegar seguidas.
func queue_check() -> void:
	if _check_queued:
		return
	_check_queued = true
	check_all.call_deferred()

## Revisa hazañas y finales. Devuelve las hazañas cumplidas ahora.
func check_all() -> Array[String]:
	_check_queued = false
	var unlocked: Array[String] = []
	var player: Character = GameManager.player_character
	if not GameManager.is_game_active or player == null or DynastyData.needs_succession():
		return unlocked
	if player.full_name() != _player_name:
		if not _player_name.is_empty():
			generation += 1   # un heredero ha tomado el relevo
		_player_name = player.full_name()
	var ctx := context()
	for a: Dictionary in AchievementCatalog.visible_for(GameManager.starting_role):
		if achieved.has(a.id):
			continue
		if progress_of(a, ctx).done:
			_unlock(a, player)
			unlocked.append(a.id)
	check_endings()
	return unlocked

func _unlock(a: Dictionary, player: Character) -> void:
	achieved[a.id] = GameManager.months_elapsed()
	if a.has("goal_role"):
		GameManager.victory_achieved = true   # compatibilidad con partidas y pantallas antiguas
	var reward: Dictionary = a.get("reward", {})
	var parts: Array[String] = []
	var summary := AchievementCatalog.reward_text(reward)
	if not summary.is_empty():
		parts.append(summary)
	player.gold += int(reward.get("gold", 0))
	if reward.get("fame", 0) > 0:
		player.add_fame(int(reward.fame))
	if reward.get("honor", 0) > 0:
		player.gain_honor(int(reward.honor))
	if reward.get("xp", 0) > 0:
		player.gain_xp(int(reward.xp))
	player.unspent_points += int(reward.get("points", 0))
	if reward.get("unique", false):
		var item_text := UniqueItems.grant(player)
		if not item_text.is_empty():
			parts.append(item_text)
	var text := "Hazaña cumplida: «%s». %s" % [a.title, AchievementCatalog.description_of(a)]
	if not parts.is_empty():
		text += " Recompensa: %s." % ". ".join(parts)
	WorldEvents.record(text, "", true)
	WorldEvents.notify("Hazaña: %s" % a.title, text)
	achievement_unlocked.emit(a.id)

## Datos del jugador y del mundo que miden las hazañas (stat -> valor).
func context() -> Dictionary:
	var player: Character = GameManager.player_character
	if player == null:
		return {}
	var pname := player.full_name()
	var noble := player.rank() >= Character.rank_of(Character.Role.NOBLEZA_BAJA)
	var owned := 0
	var kingdom_castles := 0
	var building_level := 0
	for c: Castle in MapData.castles:
		var mine := c.owner_name == pname
		if mine:
			owned += 1
		if c.kingdom == GameManager.player_kingdom:
			kingdom_castles += 1
		if mine or (noble and c.castle_id == GameManager.home_castle_id):
			for level in c.buildings.values():
				building_level = maxi(building_level, int(level))
	var uniques := 0
	for item: Equipment in player.equipment:
		if item != null and SkillEffects.is_unique_item(item):
			uniques += 1
	return {
		"duels_won": player.duels_won, "level": player.level, "fame": player.fame, "honor": player.honor,
		"gold": player.gold, "rank": player.rank(), "owned_castles": owned, "building_level": building_level,
		"kingdom_share": roundi(100.0 * kingdom_castles / maxf(1.0, MapData.castles.size())),
		"married": 1 if RelationsData.is_married() else 0,
		"children": DynastyData.children().filter(func(c: Character) -> bool: return DynastyData.is_own_child(c)).size(),
		"adult_children": DynastyData.adult_children().size(),
		"generations": generation, "retinue": RelationsData.retinue.size(),
		"missions_done": MissionData.completed_count, "unique_items": uniques,
		"visited_castles": visited_castles.size(), "visited_kingdoms": visited_kingdoms.size(),
	}

## {done, current, target, ratio, text} de una hazaña.
func progress_of(a: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	if ctx.is_empty():
		ctx = context()
	if achieved.has(a.id):
		return {"done": true, "current": 1, "target": 1, "ratio": 1.0, "text": "Cumplida"}
	if a.has("goal_role"):
		var goal := VictoryRules.evaluate(a.goal_role, GameManager.player_character, MapData.castles,
			GameManager.player_kingdom, GameManager.home_castle_id,
			{"visited_kingdoms": visited_kingdoms.size()})
		return {"done": goal.done, "current": 0, "target": 1, "ratio": 0.5, "text": goal.progress}
	var target: int = a.target
	var current: int = int(ctx.get(a.stat, 0))
	var suffix := "%" if a.stat == "kingdom_share" else ""
	return {"done": current >= target, "current": current, "target": target,
		"ratio": clampf(float(current) / maxf(1.0, target), 0.0, 1.0),
		"text": "%d%s / %d%s" % [mini(current, target), suffix, target, suffix]}

func visible() -> Array:
	return AchievementCatalog.visible_for(GameManager.starting_role)

func achieved_count() -> int:
	return visible().filter(func(a: Dictionary) -> bool: return achieved.has(a.id)).size()

## Las hazañas pendientes más cercanas (la de destino del rol va siempre primero).
func next_achievements(count: int = NEXT_SHOWN) -> Array:
	var ctx := context()
	var pending: Array = []
	var goal: Dictionary = {}
	for a: Dictionary in visible():
		if achieved.has(a.id):
			continue
		if a.has("goal_role"):
			goal = a
		else:
			pending.append({"a": a, "ratio": progress_of(a, ctx).ratio})
	pending.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.ratio > y.ratio)
	var out: Array = []
	if not goal.is_empty():
		out.append(goal)
	for p: Dictionary in pending:
		if out.size() >= count:
			break
		out.append(p.a)
	return out

# --- Finales con victoria ---

## Reinos que aún tienen castillos (las tierras sin señor no cuentan).
func kingdoms_standing() -> Array[int]:
	var out: Array[int] = []
	for c: Castle in MapData.castles:
		if c.kingdom != KingdomEnums.Kingdom.NEUTRAL and not int(c.kingdom) in out:
			out.append(int(c.kingdom))
	return out

## Comprueba los dos finales con victoria. Devuelve el final alcanzado ahora ({} si ninguno).
func check_endings() -> Dictionary:
	if not ending_done.is_empty() or not GameManager.is_game_active or GameManager.player_character == null:
		return {}
	var mine := GameManager.player_kingdom
	var standing := kingdoms_standing()
	if not mine in standing:
		return {}
	var ending: Dictionary = {}
	if standing.size() == 1:
		ending = _conquest_ending()
	elif standing.size() == 2:
		var other: int = standing[0] if standing[1] == mine else standing[1]
		if _married_into(other):
			ending = _unification_ending(other)
	if ending.is_empty():
		return {}
	ending_done = ending.id
	pending_ending = ending
	WorldEvents.record(ending.text, "", true)
	ending_reached.emit(ending)
	return ending

## Casado con alguien de la casa del señor de ese reino.
func _married_into(kingdom: int) -> bool:
	if not RelationsData.is_married() or RelationsData.spouse_family.is_empty():
		return false
	var family: Relationship = RelationsData.get_relation(RelationsData.spouse_family)
	if family != null and family.kingdom == kingdom:
		return true
	for c: Castle in MapData.castles:
		if c.kingdom == kingdom and c.owner_name == RelationsData.spouse_family:
			return true
	return false

func _conquest_ending() -> Dictionary:
	var player: Character = GameManager.player_character
	var realm := KingdomEnums.kingdom_name(GameManager.player_kingdom)
	var crowned := player.rank() >= Character.rank_of(Character.Role.REGENTE) or RelationsData.liege_name.is_empty()
	var text: String
	if crowned:
		text = "Todos los castillos del mundo ondean el estandarte de %s. %s reina sobre todas las tierras conocidas." % [realm, player.full_name()]
	else:
		text = "Todos los castillos del mundo ondean el estandarte de %s. Tu señor, %s, reina sobre todas las tierras conocidas, y tu espada ayudó a forjar su imperio." % [
			realm, RelationsData.liege_name]
	return {"id": ENDING_CONQUEST, "title": "El mundo unido por la espada", "text": text, "victory": true}

func _unification_ending(other: int) -> Dictionary:
	var player: Character = GameManager.player_character
	var text := "Solo quedaban dos reinos en pie, %s y %s. Tu matrimonio con %s une sus casas: los dos reinos se funden en uno, y %s pasa a la historia como quien trajo la paz." % [
		KingdomEnums.kingdom_name(GameManager.player_kingdom), KingdomEnums.kingdom_name(other),
		RelationsData.spouse_name, player.full_name()]
	return {"id": ENDING_UNIFICATION, "title": "Dos coronas, una casa", "text": text, "victory": true}

## Resumen para la pantalla final.
func summary() -> Dictionary:
	var player: Character = GameManager.player_character
	return {
		"years": GameManager.months_elapsed() / GameManager.MONTHS_PER_YEAR,
		"months": GameManager.months_elapsed() % GameManager.MONTHS_PER_YEAR,
		"achieved": achieved_count(), "total": visible().size(),
		"house": DynastyData.house_name(player) if player != null else "",
		"generation": generation, "children": DynastyData.children().size(),
		"player": player.full_name() if player != null else "",
		"title": player.role_title() if player != null else "",
	}

# --- Guardado ---

func save_state() -> Dictionary:
	return {"achieved": achieved.duplicate(), "visited_castles": visited_castles.duplicate(),
		"visited_kingdoms": visited_kingdoms.duplicate(), "generation": generation,
		"ending_done": ending_done, "player_name": _player_name}

func load_state(data: Dictionary) -> void:
	achieved.clear()
	for id in data.get("achieved", {}):
		achieved[str(id)] = int(data.achieved[id])
	visited_castles.clear()
	for id in data.get("visited_castles", []):
		visited_castles.append(str(id))
	visited_kingdoms.clear()
	for k in data.get("visited_kingdoms", []):
		visited_kingdoms.append(int(k))
	generation = int(data.get("generation", 1))
	ending_done = str(data.get("ending_done", ""))
	pending_ending = {}
	var player: Character = GameManager.player_character
	_player_name = str(data.get("player_name", player.full_name() if player != null else ""))
	if data.is_empty():
		# Partida anterior al libro de hazañas: la meta ya cumplida cuenta (sin repetir el premio).
		if GameManager.victory_achieved:
			var goal_id: String = AchievementCatalog.ROLE_GOAL_IDS.get(GameManager.starting_role, "")
			if not goal_id.is_empty():
				achieved[goal_id] = GameManager.months_elapsed()
		_mark_visited(GameManager.home_castle_id)
		_mark_visited(TravelData.current_castle_id())
