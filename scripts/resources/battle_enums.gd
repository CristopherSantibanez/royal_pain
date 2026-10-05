class_name BattleEnums

enum UnitType { INFANTERIA, ARQUEROS, CABALLERIA }
enum Terrain { LLANO, BOSQUE, COLINA, MURALLA }
enum Side { ATACANTE, DEFENSOR }

static func unit_type_name(t: int) -> String:
	match t:
		UnitType.INFANTERIA: return "Infantería"
		UnitType.ARQUEROS: return "Arqueros"
		UnitType.CABALLERIA: return "Caballería"
	return "?"

static func unit_type_letter(t: int) -> String:
	match t:
		UnitType.INFANTERIA: return "I"
		UnitType.ARQUEROS: return "A"
		UnitType.CABALLERIA: return "C"
	return "?"

static func terrain_name(t: int) -> String:
	match t:
		Terrain.LLANO: return "Llano"
		Terrain.BOSQUE: return "Bosque"
		Terrain.COLINA: return "Colina"
		Terrain.MURALLA: return "Muralla"
	return "?"

static func side_name(s: int) -> String:
	match s:
		Side.ATACANTE: return "Atacante"
		Side.DEFENSOR: return "Defensor"
	return "?"
