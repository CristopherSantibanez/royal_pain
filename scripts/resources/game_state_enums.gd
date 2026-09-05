class_name GameStateEnums

enum State { MENU, MAP, BATTLE, DUEL, CHARACTER_CREATION }

static func state_name(s: int) -> String:
	match s:
		State.MENU: return "Menú"
		State.MAP: return "Mapa"
		State.BATTLE: return "Batalla"
		State.DUEL: return "Duelo"
		State.CHARACTER_CREATION: return "Creación de Personaje"
	return "?"
