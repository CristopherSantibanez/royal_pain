class_name Castle
extends Resource

@export var castle_id: String = ""
@export var castle_name: String = ""
@export var kingdom: KingdomEnums.Kingdom = KingdomEnums.Kingdom.NEUTRAL
@export var position_on_map: Vector2 = Vector2.ZERO
@export var connected_castle_ids: Array[String] = []

@export_group("Gobierno y Recursos")
@export var owner_name: String = "Sin Señor"   # placeholder hasta tener sistema de nobleza real
@export var garrison_size: int = 50
@export var gold: int = 200
@export var food: int = 150
