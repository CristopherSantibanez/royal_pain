extends RefCounted
# Trabajos a jornal: el sustento de quien no cobra renta ni soldada (no afiliado, campesino,
# soldado sin señor, mercenario sin contrato). Se hacen en el castillo donde estás.

const PER_MONTH := 2               # jornales como máximo al mes
const MARKET_BONUS := 3            # oro extra por nivel del mercado del castillo
const INCIDENT_DAMAGE := 15        # vida que cuesta un mal día de escolta o de guardia

# id, nombre, atributo que cuenta, oro base, oro por punto del atributo, prob. de incidente
const JOBS := [
	{"id": "cargador", "name": "Cargador", "stat": "defense", "base": 6, "per_point": 1.0, "risk": 0.0,
		"desc": "Descargas carros en la plaza. Cuenta tu Defensa."},
	{"id": "jornalero", "name": "Jornalero", "stat": "charisma", "base": 5, "per_point": 1.1, "risk": 0.0,
		"desc": "Ayudas en mercados y talleres. Cuenta tu Carisma."},
	{"id": "guardia", "name": "Guardia de caravana", "stat": "combat", "base": 8, "per_point": 1.4, "risk": 0.15,
		"desc": "Proteges una caravana un día de camino. Cuenta tu Combate; puede haber pelea."},
	{"id": "escolta", "name": "Escolta", "stat": "combat", "base": 10, "per_point": 1.6, "risk": 0.25,
		"desc": "Escoltas a un viajero importante. Mejor pagado, más peligroso."},
]

## ¿Le toca ganarse el pan a jornal? (los que no tienen renta ni soldada).
static func eligible(c: Character, has_liege: bool, has_contract: bool) -> bool:
	if c == null:
		return false
	match c.role:
		Character.Role.INAFILIADO, Character.Role.CAMPESINO:
			return true
		Character.Role.SOLDADO:
			return not has_liege
		Character.Role.MERCENARIO:
			return not has_contract
	return false

static func pay(job: Dictionary, c: Character, castle: Castle) -> int:
	var stat: int = c.get(job.stat)
	var market: int = castle.building_level("mercado") if castle != null else 0
	return int(job.base + job.per_point * stat) + market * MARKET_BONUS
