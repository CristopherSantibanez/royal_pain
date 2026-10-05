class_name SaveSystem
# Guardado y carga de la partida completa en ranuras: un autoguardado (cada mes) y varias
# ranuras manuales. Cada ranura es un archivo .tres en user://saves.

const SAVE_DIR := "user://saves"
const AUTO_SLOT := "auto"
const MANUAL_SLOTS: Array[String] = ["1", "2", "3"]
const SAVE_PATH := "user://saves/autoguardado.tres"    # ranura del autoguardado
const LEGACY_SAVE_PATH := "user://saves/partida.tres"  # versión anterior (una sola ranura)

# Pantalla de ranuras: modo ("save" o "load") y escena a la que volver.
static var slots_mode: String = "load"
static var slots_return_scene: String = "res://scenes/main_menu/main_menu.tscn"

static func all_slots() -> Array[String]:
	var result: Array[String] = [AUTO_SLOT]
	result.append_array(MANUAL_SLOTS)
	return result

static func slot_path(slot: String) -> String:
	return SAVE_PATH if slot == AUTO_SLOT else "%s/ranura_%s.tres" % [SAVE_DIR, slot]

static func slot_title(slot: String) -> String:
	return "Autoguardado" if slot == AUTO_SLOT else "Ranura %s" % slot

static func has_save(slot: String = AUTO_SLOT) -> bool:
	_migrate_legacy()
	return FileAccess.file_exists(slot_path(slot))

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
	if slot != AUTO_SLOT and FileAccess.file_exists(slot_path(slot)):
		DirAccess.remove_absolute(slot_path(slot))

static func save_game(slot: String = AUTO_SLOT) -> Error:
	var player: Character = GameManager.player_character
	if not GameManager.is_game_active or player == null:
		return ERR_UNAVAILABLE
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

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
	s.saved_at = Time.get_datetime_string_from_system(false, true)
	s.summary = "%s (%s) — %s" % [player.full_name(), player.role_name(), GameManager.get_date_string()]
	return ResourceSaver.save(s, slot_path(slot))

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
	GameManager.last_annual_event = s.last_annual_event
	# Partidas guardadas antes de existir las victorias: se usa el rol actual como meta.
	GameManager.starting_role = s.starting_role if s.starting_role >= 0 else s.player.role
	GameManager.victory_achieved = s.victory_achieved
	GameManager.active_edict = s.active_edict
	GameManager.last_tournament_year = s.last_tournament_year
	if RelationsData.relations.is_empty():
		RelationsData.reset()   # partidas guardadas antes de existir las relaciones
	ArmyData.armies_changed.emit()
	ArmyData.events_changed.emit()
	return true

static func _read(slot: String) -> SaveGame:
	if not has_save(slot):
		return null
	# Sin caché: cada carga crea objetos nuevos, independientes de la partida anterior.
	return ResourceLoader.load(slot_path(slot), "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as SaveGame

# La versión anterior guardaba todo en partida.tres: pasa a ser el autoguardado.
static func _migrate_legacy() -> void:
	if FileAccess.file_exists(LEGACY_SAVE_PATH) and not FileAccess.file_exists(SAVE_PATH):
		DirAccess.rename_absolute(LEGACY_SAVE_PATH, SAVE_PATH)
