class_name SaveSystem

# Versión del formato de guardado. Súbela al cambiar qué se guarda y añade la migración en load_game.
#   1: formato original · 2: módulos con estado propio (SaveGame.modules) · 3: archivos JSON (DataCodec)
const SAVE_VERSION := 3
# Autoloads que guardan su propio estado con save_state() -> Dictionary y load_state(d).
# Deben devolver datos planos (números, textos, arrays, diccionarios), nunca objetos.
const MODULES := ["RelationsData", "MissionData", "WorldEvents", "DynastyData", "ExplorationData", "TravelData", "AchievementData", "CaptureData", "StoryData", "AmbitionData", "TravelerData", "SocialEvents", "LoyaltyData", "PartyData"]
# Guardado y carga de la partida completa en ranuras: un autoguardado (cada mes) y varias
# ranuras manuales. Cada ranura es un archivo JSON en <datos>/saves (ver DataCodec y DataPaths).
# Las partidas .tres de versiones anteriores se convierten a JSON la primera vez que se leen.

const AUTO_SLOT := "auto"
const MANUAL_SLOTS: Array[String] = ["1", "2", "3"]

# Pantalla de ranuras: modo ("save" o "load") y escena a la que volver.
static var slots_mode: String = "load"
static var slots_return_scene: String = "res://scenes/main_menu/main_menu.tscn"

static func all_slots() -> Array[String]:
	var result: Array[String] = [AUTO_SLOT]
	result.append_array(MANUAL_SLOTS)
	return result

static func save_dir() -> String:
	return DataPaths.path("saves")

static func slot_path(slot: String) -> String:
	return "%s/%s.json" % [save_dir(), _slot_file(slot)]

static func _slot_file(slot: String) -> String:
	return "autoguardado" if slot == AUTO_SLOT else "ranura_%s" % slot

static func slot_title(slot: String) -> String:
	return "Autoguardado" if slot == AUTO_SLOT else "Ranura %s" % slot

static func has_save(slot: String = AUTO_SLOT) -> bool:
	_migrate_legacy(slot)
	return FileAccess.file_exists(slot_path(slot)) or FileAccess.file_exists(slot_path(slot) + ".bak")

static func has_any_save() -> bool:
	for slot in all_slots():
		if has_save(slot):
			return true
	return false

# La ranura guardada más recientemente (por fecha real), o "" si no hay ninguna.
static func latest_slot() -> String:
	var best := ""
	var best_time := ""
	for slot in all_slots():
		var s := _read(slot)
		if s != null and s.saved_at > best_time:
			best_time = s.saved_at
			best = slot
	return best

# Datos para mostrar una ranura: {exists, summary, saved_at}
static func slot_info(slot: String) -> Dictionary:
	var s := _read(slot)
	if s == null:
		return {"exists": false, "summary": "", "saved_at": ""}
	return {"exists": true, "summary": s.summary, "saved_at": s.saved_at.replace("T", " ")}

static func delete_save(slot: String) -> void:
	if slot == AUTO_SLOT:
		return
	for path in [slot_path(slot), slot_path(slot) + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

static func save_game(slot: String = AUTO_SLOT) -> Error:
	var player: Character = GameManager.player_character
	if not GameManager.is_game_active or player == null:
		return ERR_UNAVAILABLE
	var s := SaveGame.new()
	# Copia sin ruta: así el personaje se guarda dentro del archivo y no como
	# referencia a su ficha original en user://characters (que no tiene el progreso).
	s.player = player.duplicate(false)
	s.home_castle_id = GameManager.home_castle_id
	s.player_kingdom = GameManager.player_kingdom
	s.starting_role = GameManager.starting_role
	s.victory_achieved = GameManager.victory_achieved
	s.active_edict = GameManager.active_edict
	s.last_tournament_year = GameManager.last_tournament_year
	s.month = GameManager.current_month
	s.year = GameManager.current_year
	s.actions_remaining = GameManager.actions_remaining
	s.actions_per_turn = GameManager.actions_per_turn
	s.pending_event = GameManager.pending_event
	s.event_queue = GameManager.event_queue
	s.last_annual_event = GameManager.last_annual_event
	s.castles = MapData.castles
	s.armies = ArmyData.armies
	s.next_army_id = ArmyData._next_id
	s.turn_events = ArmyData.turn_events
	s.relations = RelationsData.relations
	s.used_portraits = RelationsData.used_portraits
	s.kingdom_wars = RelationsData.kingdom_wars
	s.kingdom_alliances = RelationsData.kingdom_alliances
	s.liege_name = RelationsData.liege_name
	s.spouse_name = RelationsData.spouse_name
	s.spouse_family = RelationsData.spouse_family
	s.version = SAVE_VERSION
	for module_name in MODULES:
		var node := _module(module_name)
		if node != null and node.has_method("save_state"):
			s.modules[module_name] = node.save_state()
	s.saved_at = Time.get_datetime_string_from_system(false, true)
	s.summary = "%s (%s) — %s" % [player.full_name(), player.role_name(), GameManager.get_date_string()]
	return DataCodec.write_file(slot_path(slot), s)

static func read_summary(slot: String = AUTO_SLOT) -> String:
	var s := _read(slot)
	return s.summary if s != null else ""

static func load_game(slot: String = AUTO_SLOT) -> bool:
	var s := _read(slot)
	if s == null or s.player == null or s.castles.is_empty():
		return false

	MapData.castles = s.castles
	ArmyData.armies = s.armies
	ArmyData._next_id = s.next_army_id
	ArmyData.turn_events = s.turn_events
	ArmyData.active_battle_army = null
	RelationsData.relations = s.relations
	RelationsData.used_portraits = s.used_portraits
	RelationsData.kingdom_wars = s.kingdom_wars
	RelationsData.kingdom_alliances = s.kingdom_alliances
	RelationsData.liege_name = s.liege_name
	RelationsData.spouse_name = s.spouse_name
	RelationsData.spouse_family = s.spouse_family
	GameManager.restore_game(s.player, s.home_castle_id, s.player_kingdom, s.month, s.year,
		s.actions_remaining, s.actions_per_turn)
	GameManager.pending_event = s.pending_event
	GameManager.event_queue = s.event_queue.duplicate()
	GameManager.last_annual_event = s.last_annual_event
	# Partidas guardadas antes de existir las victorias: se usa el rol actual como meta.
	GameManager.starting_role = s.starting_role if s.starting_role >= 0 else s.player.role
	GameManager.victory_achieved = s.victory_achieved
	GameManager.active_edict = s.active_edict
	GameManager.last_tournament_year = s.last_tournament_year
	if RelationsData.relations.is_empty():
		RelationsData.reset()   # partidas guardadas antes de existir las relaciones
	# Cada módulo restaura su estado; con partidas antiguas recibe {} y usa sus valores iniciales.
	for module_name in MODULES:
		var node := _module(module_name)
		if node != null and node.has_method("load_state"):
			node.load_state(s.modules.get(module_name, {}) if s.version >= 2 else {})
	# Partidas antiguas: la gente de reinos ya caídos se recoloca; los roles mercenarios desaparecen.
	RelationsData.rehome_stranded()
	RoleProgression.migrate_legacy_role(GameManager.player_character)
	if Character.is_legacy_role(GameManager.starting_role):
		GameManager.starting_role = Character.Role.INAFILIADO
	ArmyData.armies_changed.emit()
	ArmyData.events_changed.emit()
	return true

static func _module(module_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(module_name) if tree != null else null

static func _read(slot: String) -> SaveGame:
	if not has_save(slot):
		return null
	# Cada lectura crea objetos nuevos, independientes de la partida anterior.
	return DataCodec.read_file(slot_path(slot)) as SaveGame

# Partidas de versiones anteriores (.tres, propias del jugador): se convierten a JSON una vez y el
# original se renombra a .migrado. partida.tres, de la versión con una sola ranura, pasa a ser el autoguardado.
static func _migrate_legacy(slot: String) -> void:
	if FileAccess.file_exists(slot_path(slot)):
		return
	var legacy := "%s/%s.tres" % [save_dir(), _slot_file(slot)]
	if slot == AUTO_SLOT and not FileAccess.file_exists(legacy):
		legacy = "%s/partida.tres" % save_dir()
	if not FileAccess.file_exists(legacy):
		return
	var old := ResourceLoader.load(legacy, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as SaveGame
	if old != null and DataCodec.write_file(slot_path(slot), old) == OK:
		DirAccess.rename_absolute(legacy, legacy + ".migrado")
