extends RefCounted
# Edificios del castillo: datos de cada uno por nivel (1..3). Lógica pura.
# Uso: const BuildingCatalog = preload("res://scripts/resources/building_catalog.gd")
#
# Cada nivel: {cost (oro del castillo), months (meses de obra), text (efecto), y sus valores}.
# Los valores son acumulados (el nivel 3 ya incluye lo de los anteriores).

const MAX_LEVEL := 3
const MIN_ROLE_TO_BUILD := Character.Role.NOBLEZA_BAJA   # solo la nobleza ordena obras
const TOP_LEVEL_MIN_ROLE := Character.Role.NOBLEZA_ALTA  # el nivel máximo exige un gran señor (Nobleza Alta, Duque o Regente)

const BUILDINGS := {
	"herreria": {"name": "Herrería", "description": "Forja y armería: mejor equipo en la tienda del castillo y a mejor precio.",
		"levels": [
			{"cost": 150, "months": 2, "shop_tier": 1, "shop_discount": 0.05, "text": "Armería: piezas de un nivel más · precios −5%"},
			{"cost": 280, "months": 3, "shop_tier": 2, "shop_discount": 0.10, "text": "Armería: dos niveles más · precios −10%"},
			{"cost": 450, "months": 4, "shop_tier": 3, "shop_discount": 0.15, "text": "Armería: lo mejor del reino · precios −15%"},
		]},
	"establos": {"name": "Establos", "description": "Caballos de guerra para la caballería que sale de este castillo.",
		"levels": [
			{"cost": 140, "months": 2, "cavalry_power": 0.10, "cavalry_morale": 3, "text": "Caballería +10% de fuerza y +3 de moral"},
			{"cost": 260, "months": 3, "cavalry_power": 0.20, "cavalry_morale": 6, "text": "Caballería +20% de fuerza y +6 de moral"},
			{"cost": 420, "months": 4, "cavalry_power": 0.30, "cavalry_morale": 10, "text": "Caballería +30% de fuerza y +10 de moral"},
		]},
	"murallas": {"name": "Murallas", "description": "Muros y torres más altos: el castillo resiste mejor los asedios.",
		"levels": [
			{"cost": 200, "months": 3, "wall_bonus": 0.15, "text": "Defensa en asedios +15%"},
			{"cost": 350, "months": 4, "wall_bonus": 0.30, "text": "Defensa en asedios +30%"},
			{"cost": 550, "months": 5, "wall_bonus": 0.45, "text": "Defensa en asedios +45%"},
		]},
	"mercado": {"name": "Mercado", "description": "Plaza de comercio: el castillo recauda más cada mes.",
		"levels": [
			{"cost": 120, "months": 2, "income": 12, "text": "Ingresos del castillo +12 de oro al mes"},
			{"cost": 240, "months": 3, "income": 25, "text": "Ingresos del castillo +25 de oro al mes"},
			{"cost": 400, "months": 4, "income": 40, "text": "Ingresos del castillo +40 de oro al mes"},
		]},
	"capilla": {"name": "Capilla", "description": "Un lugar de culto y de cura: honor y salud para quien vive aquí.",
		"levels": [
			{"cost": 100, "months": 2, "heal": 5, "honor": 0, "text": "Curación mensual +5"},
			{"cost": 200, "months": 3, "heal": 10, "honor": 1, "text": "Curación mensual +10 · honor +1 al mes"},
			{"cost": 340, "months": 4, "heal": 15, "honor": 1, "text": "Curación mensual +15 · honor +1 al mes"},
		]},
	"cuartel": {"name": "Cuartel", "description": "Barracones y patio de armas: la guarnición crece más rápido y reclutar sale más barato.",
		"levels": [
			{"cost": 150, "months": 2, "recruits": 1, "recruit_discount": 0.10, "text": "Guarnición +1 al mes · reclutar −10%"},
			{"cost": 280, "months": 3, "recruits": 2, "recruit_discount": 0.20, "text": "Guarnición +2 al mes · reclutar −20%"},
			{"cost": 460, "months": 4, "recruits": 3, "recruit_discount": 0.30, "text": "Guarnición +3 al mes · reclutar −30%"},
		]},
}

const ORDER := ["herreria", "establos", "murallas", "mercado", "capilla", "cuartel"]

## Datos del nivel (1..3) de un edificio, o {} si no existe.
static func level_data(id: String, level: int) -> Dictionary:
	var b: Dictionary = BUILDINGS.get(id, {})
	if b.is_empty() or level < 1 or level > MAX_LEVEL:
		return {}
	return b.levels[level - 1]

## Valor de un efecto con el nivel dado (0 si no está construido o no lo tiene).
static func value(id: String, level: int, key: String) -> float:
	return float(level_data(id, level).get(key, 0.0))

static func building_name(id: String) -> String:
	return BUILDINGS.get(id, {}).get("name", id)
