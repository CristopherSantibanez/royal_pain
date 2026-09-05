class_name CharacterEnums

enum Gender { MASCULINO, FEMENINO }

enum Alignment { CONQUISTADOR, PACIFISTA, AMBICIOSO, HUMILDE, DIPLOMATICO, TIRANO }

enum FighterType { DUELISTA, TANQUE, ESTRATEGA, BERSERKER, DEFENSOR, ASESINO }

enum SkillCategory { GENERAL, COMBATE, BATALLA }

static func alignment_name(a: int) -> String:
	match a:
		Alignment.CONQUISTADOR: return "Conquistador"
		Alignment.PACIFISTA: return "Pacifista"
		Alignment.AMBICIOSO: return "Ambicioso"
		Alignment.HUMILDE: return "Humilde"
		Alignment.DIPLOMATICO: return "Diplomático"
		Alignment.TIRANO: return "Tirano"
	return "?"

static func fighter_type_name(f: int) -> String:
	match f:
		FighterType.DUELISTA: return "Duelista"
		FighterType.TANQUE: return "Tanque"
		FighterType.ESTRATEGA: return "Estratega"
		FighterType.BERSERKER: return "Berserker"
		FighterType.DEFENSOR: return "Defensor"
		FighterType.ASESINO: return "Asesino"
	return "?"
