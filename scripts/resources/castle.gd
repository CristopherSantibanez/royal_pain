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

@export_group("Edificios")
@export var buildings: Dictionary = {}          # id -> nivel (ver BuildingCatalog)
@export var construction_id: String = ""        # obra en curso ("" si ninguna; solo una a la vez)
@export var construction_months_left: int = 0

@export_group("Origen")
@export var original_kingdom: int = -1        # reino al que pertenecía al empezar la partida
@export var original_owner: String = ""       # su señor original (para rebeliones y reconquistas)
@export var culture: int = -1                 # cultura de su gente (NameCatalog.Culture); -1 = partida antigua

# --- Edificios ---
const BuildingCatalog = preload("res://scripts/resources/building_catalog.gd")

func building_level(id: String) -> int:
	return int(buildings.get(id, 0))

## Efecto de un edificio construido aquí (0 si no existe), p. ej. building_value("mercado", "income").
func building_value(id: String, key: String) -> float:
	return BuildingCatalog.value(id, building_level(id), key)

## Bono de defensa de las murallas en asedios de este castillo (0.0, 0.15, 0.30 o 0.45):
## la defensa del castillo se multiplica por (1 + wall_bonus()).
func wall_bonus() -> float:
	return building_value("murallas", "wall_bonus")

## Mejoras de la caballería que sale de este castillo: [fuerza extra (0..0.3), moral extra].
func cavalry_bonus() -> Array:
	return [building_value("establos", "cavalry_power"), int(building_value("establos", "cavalry_morale"))]

func is_building() -> bool:
	return not construction_id.is_empty()

## Comienza una obra (sin comprobar requisitos: ver BuildingCatalog y la pantalla del castillo).
func start_construction(id: String) -> void:
	var next := BuildingCatalog.level_data(id, building_level(id) + 1)
	gold -= int(next.cost)
	construction_id = id
	construction_months_left = int(next.months)

## Avanza un mes la obra en curso. Devuelve el id del edificio terminado ("" si sigue en obras).
func advance_construction() -> String:
	if construction_id.is_empty():
		return ""
	construction_months_left -= 1
	if construction_months_left > 0:
		return ""
	var done := construction_id
	buildings[done] = building_level(done) + 1
	construction_id = ""
	construction_months_left = 0
	return done
