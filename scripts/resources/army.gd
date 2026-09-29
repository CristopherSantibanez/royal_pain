class_name Army
extends Resource

@export var army_id: String = ""
@export var owner_name: String = ""          # texto por ahora, igual que Castle.owner_name
@export var kingdom: KingdomEnums.Kingdom = KingdomEnums.Kingdom.NEUTRAL
@export var size: int = 0

@export var current_castle_id: String = ""    # dónde está parado ahora
@export var destination_castle_id: String = "" # "" si no está en marcha
@export var turns_remaining: int = 0

@export var pending_battle: bool = false       # true si llegó a territorio enemigo y espera resolución

func is_marching() -> bool:
	return destination_castle_id != "" and not pending_battle

func is_idle() -> bool:
	return destination_castle_id == "" and not pending_battle

func status_text() -> String:
	if pending_battle:
		var castle := MapData.get_castle_by_id(current_castle_id)
		var castle_name := castle.castle_name if castle != null else current_castle_id
		return "¡Batalla pendiente en %s!" % castle_name
	if is_marching():
		var dest := MapData.get_castle_by_id(destination_castle_id)
		var dest_name := dest.castle_name if dest != null else destination_castle_id
		return "En marcha a %s (llega en %d turno%s)" % [dest_name, turns_remaining, "" if turns_remaining == 1 else "s"]
	var here := MapData.get_castle_by_id(current_castle_id)
	var here_name := here.castle_name if here != null else current_castle_id
	return "Estacionado en %s" % here_name
