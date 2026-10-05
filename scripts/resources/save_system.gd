class_name SaveSystem
# Guardado y carga de la partida completa (un único espacio de guardado, con autoguardado mensual).

const SAVE_DIR := "user://saves"
const SAVE_PATH := "user://saves/partida.tres"

static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

static func save_game() -> Error:
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
	s.saved_at = Time.get_datetime_string_from_system(false, true)
	s.summary = "%s (%s) — %s" % [player.full_name(), player.role_name(), GameManager.get_date_string()]
	return ResourceSaver.save(s, SAVE_PATH)

static func read_summary() -> String:
	var s := _read()
	return s.summary if s != null else ""

static func load_game() -> bool:
	var s := _read()
	if s == null or s.player == null or s.castles.is_empty():
		return false

	MapData.castles = s.castles
	ArmyData.armies = s.armies
	ArmyData._next_id = s.next_army_id
	ArmyData.turn_events = s.turn_events
	ArmyData.active_battle_army = null
	GameManager.restore_game(s.player, s.home_castle_id, s.player_kingdom, s.month, s.year,
		s.actions_remaining, s.actions_per_turn)
	GameManager.pending_event = s.pending_event
	GameManager.last_annual_event = s.last_annual_event
	ArmyData.armies_changed.emit()
	ArmyData.events_changed.emit()
	return true

static func _read() -> SaveGame:
	if not has_save():
		return null
	# Sin caché: cada carga crea objetos nuevos, independientes de la partida anterior.
	return ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as SaveGame
