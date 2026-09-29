extends Node
# Autoload — registrar como "ArmyData"

signal armies_changed
signal battle_pending(army: Army)

var armies: Array[Army] = []
var _next_id: int = 1

func _ready() -> void:
	GameManager.turn_advanced.connect(_on_turn_advanced)

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

func get_armies_at(castle_id: String) -> Array[Army]:
	var result: Array[Army] = []
	for a: Army in armies:
		if a.current_castle_id == castle_id:
			result.append(a)
	return result

func get_player_armies() -> Array[Army]:
	var result: Array[Army] = []
	if GameManager.player_character == null:
		return result
	var player_name := GameManager.player_character.full_name()
	for a: Army in armies:
		if a.owner_name == player_name:
			result.append(a)
	return result

func set_destination(army: Army, destination_castle_id: String) -> bool:
	if not army.is_idle():
		return false
	var origin := MapData.get_castle_by_id(army.current_castle_id)
	if origin == null or not origin.connected_castle_ids.has(destination_castle_id):
		return false

	army.destination_castle_id = destination_castle_id
	army.turns_remaining = 1   # por ahora, 1 salto = 1 turno, siempre a castillos directamente conectados
	armies_changed.emit()
	return true

func disband_army(army: Army) -> void:
	armies.erase(army)
	armies_changed.emit()

func _on_turn_advanced(_month: int, _year: int) -> void:
	for a: Army in armies:
		if a.pending_battle:
			continue   # se queda esperando resolución de batalla, no se mueve
		if a.destination_castle_id == "":
			continue

		a.turns_remaining -= 1
		if a.turns_remaining <= 0:
			_resolve_arrival(a)

	armies_changed.emit()

func _resolve_arrival(army: Army) -> void:
	var destination := MapData.get_castle_by_id(army.destination_castle_id)
	if destination == null:
		# Castillo inválido, cancela la marcha para no dejar el ejército en el limbo.
		army.destination_castle_id = ""
		return

	army.current_castle_id = destination.castle_id
	army.destination_castle_id = ""

	if destination.kingdom == army.kingdom:
		# Territorio aliado: el ejército se disuelve y refuerza la guarnición local.
		destination.garrison_size += army.size
		disband_army(army)
	else:
		# Territorio enemigo: queda a la espera de que la batalla táctica lo resuelva.
		army.pending_battle = true
		battle_pending.emit(army)
