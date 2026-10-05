class_name RoleProgression

# --- Umbrales de ascenso (ajustables sin tocar el resto del sistema) ---
const SOLDADO_MIN_DUELS_WON := 3
const SOLDADO_MIN_HONOR := 60

const NOBLEZA_BAJA_MIN_HONOR := 75
const NOBLEZA_BAJA_MIN_GOLD := 500

const NOBLEZA_ALTA_MIN_LEADERSHIP := 12
const NOBLEZA_ALTA_MIN_GOLD := 2000

# Sucesión Nobleza Alta -> Regente: honor alto y uno de dos caminos
const REGENTE_MIN_HONOR := 80
const REGENTE_USURP_CASTLES := 4   # castillos de tu reino que debes controlar para usurpar el trono

# Umbral bajo el cual un Caballero+ puede perder su título por deshonor
const DISHONOR_THRESHOLD := 20

static func next_role(role: int) -> int:
	match role:
		Character.Role.CAMPESINO: return Character.Role.SOLDADO
		Character.Role.SOLDADO: return Character.Role.CABALLERO
		Character.Role.CABALLERO: return Character.Role.NOBLEZA_BAJA
		Character.Role.NOBLEZA_BAJA: return Character.Role.NOBLEZA_ALTA
		Character.Role.NOBLEZA_ALTA: return Character.Role.REGENTE
		_: return -1   # Regente es la cima

static func check_ascension(character: Character, succession: Dictionary = {}) -> Dictionary:
	# Devuelve {can_ascend: bool, next_role: int, reason: String}
	# "reason" explica qué falta cuando can_ascend es false, útil para mostrar en UI.
	# "succession" (solo para Regente): {liege_name, married_to_liege: bool, kingdom_castles: int}
	var target := next_role(character.role)
	if target == -1:
		return {"can_ascend": false, "next_role": -1, "reason": "No hay un ascenso disponible desde este rol todavía."}

	match character.role:
		Character.Role.CAMPESINO:
			return {"can_ascend": true, "next_role": target, "reason": ""}

		Character.Role.SOLDADO:
			if character.duels_won < SOLDADO_MIN_DUELS_WON or character.honor < SOLDADO_MIN_HONOR:
				return {"can_ascend": false, "next_role": target, "reason":
					"Necesitas %d+ duelos ganados (tienes %d) y %d+ de honor (tienes %d)." % [
						SOLDADO_MIN_DUELS_WON, character.duels_won, SOLDADO_MIN_HONOR, character.honor]}
			return {"can_ascend": true, "next_role": target, "reason": ""}

		Character.Role.CABALLERO:
			if character.honor < NOBLEZA_BAJA_MIN_HONOR or character.gold < NOBLEZA_BAJA_MIN_GOLD:
				return {"can_ascend": false, "next_role": target, "reason":
					"Necesitas %d+ de honor (tienes %d) y %d+ de oro (tienes %d)." % [
						NOBLEZA_BAJA_MIN_HONOR, character.honor, NOBLEZA_BAJA_MIN_GOLD, character.gold]}
			return {"can_ascend": true, "next_role": target, "reason": ""}

		Character.Role.NOBLEZA_BAJA:
			if character.leadership < NOBLEZA_ALTA_MIN_LEADERSHIP or character.gold < NOBLEZA_ALTA_MIN_GOLD:
				return {"can_ascend": false, "next_role": target, "reason":
					"Necesitas %d+ de liderazgo (tienes %d) y %d+ de oro (tienes %d)." % [
						NOBLEZA_ALTA_MIN_LEADERSHIP, character.leadership, NOBLEZA_ALTA_MIN_GOLD, character.gold]}
			return {"can_ascend": true, "next_role": target, "reason": ""}

		Character.Role.NOBLEZA_ALTA:
			var married: bool = succession.get("married_to_liege", false)
			var castles: int = succession.get("kingdom_castles", 0)
			var liege: String = succession.get("liege_name", "el soberano")
			var missing: Array[String] = []
			if character.honor < REGENTE_MIN_HONOR:
				missing.append("%d+ de honor (tienes %d)" % [REGENTE_MIN_HONOR, character.honor])
			if not (married or castles >= REGENTE_USURP_CASTLES):
				missing.append("casarte con la familia de %s o controlar %d castillos de tu reino (tienes %d)" % [
					liege, REGENTE_USURP_CASTLES, castles])
			if not missing.is_empty():
				return {"can_ascend": false, "next_role": target, "reason": "Necesitas " + " y ".join(missing) + "."}
			return {"can_ascend": true, "next_role": target, "reason": "", "by_marriage": married}

	return {"can_ascend": false, "next_role": -1, "reason": "Ascenso no definido para este rol."}

static func ascend(character: Character, succession: Dictionary = {}) -> bool:
	var result := check_ascension(character, succession)
	if not result.can_ascend:
		return false
	character.role = result.next_role
	return true

# --- Descenso por deshonor (Caballero o superior con honor muy bajo) ---

static func check_dishonor_demotion(character: Character) -> bool:
	if character.role in [Character.Role.CABALLERO, Character.Role.NOBLEZA_BAJA, Character.Role.NOBLEZA_ALTA]:
		return character.honor < DISHONOR_THRESHOLD
	return false

static func apply_dishonor_demotion(character: Character) -> void:
	match character.role:
		Character.Role.CABALLERO: character.role = Character.Role.SOLDADO
		Character.Role.NOBLEZA_BAJA: character.role = Character.Role.CABALLERO
		Character.Role.NOBLEZA_ALTA: character.role = Character.Role.NOBLEZA_BAJA
	character.honor = clamp(character.honor + 15, 0, 100)   # tras la caída, se estabiliza un poco
