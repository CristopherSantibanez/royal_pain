class_name BattleEnums

# Tipos de pelotón (los nuevos, SIEMPRE al final: hay tests y datos que guardan el número).
enum UnitType { INFANTERIA, ARQUEROS, CABALLERIA, PIQUEROS, CABALLERIA_PESADA, BALLESTEROS, INFANTERIA_PESADA, LANCEROS }
# Familias de tropa: cada una tiene una versión básica y otra avanzada (ver FAMILY_TYPES).
enum Family { INFANTERIA, ARQUERIA, CABALLERIA, PIQUEROS }
enum Terrain { LLANO, BOSQUE, COLINA, MURALLA, RIO, VADO, PUENTE, ALDEA }   # los nuevos, siempre al final
enum Order { NINGUNA, MANTENER, CARGAR }      # Replegarse es una acción inmediata, no una orden que dure
enum Formation { LINEA, CUNA, CUADRO }        # formación del pelotón (fase 4B)
enum Weather { DESPEJADO, LLUVIA, NIEBLA, NIEVE }
enum TimeOfDay { DIA, ATARDECER, NOCHE }
enum Side { ATACANTE, DEFENSOR }

const FAMILY_OF := {
	UnitType.INFANTERIA: Family.INFANTERIA, UnitType.INFANTERIA_PESADA: Family.INFANTERIA,
	UnitType.ARQUEROS: Family.ARQUERIA, UnitType.BALLESTEROS: Family.ARQUERIA,
	UnitType.CABALLERIA: Family.CABALLERIA, UnitType.CABALLERIA_PESADA: Family.CABALLERIA,
	UnitType.PIQUEROS: Family.PIQUEROS, UnitType.LANCEROS: Family.PIQUEROS,
}
# [básica, avanzada] de cada familia.
const FAMILY_TYPES := {
	Family.INFANTERIA: [UnitType.INFANTERIA, UnitType.INFANTERIA_PESADA],
	Family.ARQUERIA: [UnitType.ARQUEROS, UnitType.BALLESTEROS],
	Family.CABALLERIA: [UnitType.CABALLERIA, UnitType.CABALLERIA_PESADA],
	Family.PIQUEROS: [UnitType.PIQUEROS, UnitType.LANCEROS],
}
# Círculo de ventajas: cada familia aplasta a la siguiente (caballería > arqueros > infantería > piqueros > caballería).
# Las familias enfrentadas en el círculo (caballería-infantería, arquería-piqueros) luchan sin ventaja.
const BEATS := {
	Family.CABALLERIA: Family.ARQUERIA,
	Family.ARQUERIA: Family.INFANTERIA,
	Family.INFANTERIA: Family.PIQUEROS,
	Family.PIQUEROS: Family.CABALLERIA,
}

# Estadísticas por tipo: fuerza por soldado, casillas de movimiento, alcance y defensa propia.
const UNIT_STATS := {
	UnitType.INFANTERIA:        {"power": 0.30, "move": 2, "range": 1, "defense": 1.0},
	UnitType.ARQUEROS:          {"power": 0.25, "move": 2, "range": 3, "defense": 1.0},
	UnitType.CABALLERIA:        {"power": 0.35, "move": 4, "range": 1, "defense": 1.0},
	UnitType.PIQUEROS:          {"power": 0.28, "move": 2, "range": 1, "defense": 1.05},
	UnitType.CABALLERIA_PESADA: {"power": 0.34, "move": 3, "range": 1, "defense": 1.05},
	UnitType.BALLESTEROS:       {"power": 0.27, "move": 2, "range": 2, "defense": 1.0},
	UnitType.INFANTERIA_PESADA: {"power": 0.32, "move": 2, "range": 1, "defense": 1.08},
	UnitType.LANCEROS:          {"power": 0.31, "move": 2, "range": 1, "defense": 1.25},
}

static func family_of(t: int) -> int:
	return FAMILY_OF.get(t, Family.INFANTERIA)

static func basic_type(f: int) -> int:
	return FAMILY_TYPES[f][0]

static func advanced_type(f: int) -> int:
	return FAMILY_TYPES[f][1]

static func is_advanced(t: int) -> bool:
	return t == advanced_type(family_of(t))

static func is_cavalry(t: int) -> bool:
	return family_of(t) == Family.CABALLERIA

static func is_ranged(t: int) -> bool:
	return family_of(t) == Family.ARQUERIA

static func beats(a_family: int, d_family: int) -> bool:
	return BEATS.get(a_family, -1) == d_family

static func stat(t: int, key: String) -> Variant:
	return UNIT_STATS.get(t, UNIT_STATS[UnitType.INFANTERIA])[key]

static func unit_type_name(t: int) -> String:
	match t:
		UnitType.INFANTERIA: return "Infantería"
		UnitType.ARQUEROS: return "Arqueros"
		UnitType.CABALLERIA: return "Caballería"
		UnitType.PIQUEROS: return "Piqueros"
		UnitType.CABALLERIA_PESADA: return "Caballería pesada"
		UnitType.BALLESTEROS: return "Ballesteros"
		UnitType.INFANTERIA_PESADA: return "Infantería pesada"
		UnitType.LANCEROS: return "Lanceros"
	return "?"

static func family_name(f: int) -> String:
	match f:
		Family.INFANTERIA: return "Infantería"
		Family.ARQUERIA: return "Arquería"
		Family.CABALLERIA: return "Caballería"
		Family.PIQUEROS: return "Piqueros"
	return "?"

## Rasgo propio de cada tipo, para fichas y tooltips.
static func unit_type_trait(t: int) -> String:
	match t:
		UnitType.PIQUEROS: return "Frenan a la caballería."
		UnitType.CABALLERIA_PESADA: return "Carga brutal (+60% al cargar), pero lenta."
		UnitType.BALLESTEROS: return "Atraviesan armaduras, con menos alcance."
		UnitType.INFANTERIA_PESADA: return "Aguanta bien las flechas."
		UnitType.LANCEROS: return "Muro de lanzas: defienden más."
	return ""

## Letra de la familia (los avanzados se distinguen en el tablero con una estrella).
static func unit_type_letter(t: int) -> String:
	match family_of(t):
		Family.INFANTERIA: return "I"
		Family.ARQUERIA: return "A"
		Family.CABALLERIA: return "C"
		Family.PIQUEROS: return "P"
	return "?"

static func terrain_name(t: int) -> String:
	match t:
		Terrain.LLANO: return "Llano"
		Terrain.BOSQUE: return "Bosque"
		Terrain.COLINA: return "Colina"
		Terrain.MURALLA: return "Muralla"
		Terrain.RIO: return "Río"
		Terrain.VADO: return "Vado"
		Terrain.PUENTE: return "Puente"
		Terrain.ALDEA: return "Aldea"
	return "?"

static func formation_name(f: int) -> String:
	match f:
		Formation.CUNA: return "Cuña"
		Formation.CUADRO: return "Cuadro"
	return "Línea"

static func order_name(o: int) -> String:
	match o:
		Order.MANTENER: return "Mantener posición"
		Order.CARGAR: return "Cargar"
	return "Sin orden"

static func weather_name(w: int) -> String:
	match w:
		Weather.LLUVIA: return "Lluvia"
		Weather.NIEBLA: return "Niebla"
		Weather.NIEVE: return "Nieve"
	return "Despejado"

static func time_name(t: int) -> String:
	match t:
		TimeOfDay.ATARDECER: return "Atardecer"
		TimeOfDay.NOCHE: return "Noche"
	return "Día"

static func side_name(s: int) -> String:
	match s:
		Side.ATACANTE: return "Atacante"
		Side.DEFENSOR: return "Defensor"
	return "?"
