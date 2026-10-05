class_name VictoryRules
# Condiciones de victoria y derrota. Lógica pura: no referencia autoloads.
# La meta depende del ROL INICIAL: elegir el rol en Nueva Partida es elegir el camino a la victoria.

# --- Umbrales (ajustables sin tocar la lógica) ---
const CAMPEON_DUELS := 10
const CONQUISTADOR_CASTLES := 2
const SENOR_GUERRA_CASTLES := 3
const HEGEMONIA_CASTLES := 6

static func goal_title(starting_role: int) -> String:
	match starting_role:
		Character.Role.CAMPESINO: return "De la nada"
		Character.Role.SOLDADO: return "Campeón"
		Character.Role.CABALLERO: return "Conquistador"
		Character.Role.NOBLEZA_BAJA: return "Señor de la guerra"
		Character.Role.NOBLEZA_ALTA: return "Hegemonía"
	return "Sin objetivo"

static func goal_description(starting_role: int) -> String:
	match starting_role:
		Character.Role.CAMPESINO:
			return "Asciende desde el campo hasta la Nobleza Baja."
		Character.Role.SOLDADO:
			return "Conviértete en Caballero y gana %d duelos." % CAMPEON_DUELS
		Character.Role.CABALLERO:
			return "Conquista y gobierna %d castillos con tus propios ejércitos." % CONQUISTADOR_CASTLES
		Character.Role.NOBLEZA_BAJA:
			return "Gobierna %d castillos a tu nombre (tu castillo de origen cuenta)." % SENOR_GUERRA_CASTLES
		Character.Role.NOBLEZA_ALTA:
			return "Haz que tu reino controle %d de los 12 castillos." % HEGEMONIA_CASTLES
	return ""

# Devuelve {done: bool, progress: String}
static func evaluate(starting_role: int, character: Character, castles: Array[Castle], player_kingdom: int, home_castle_id: String) -> Dictionary:
	if character == null:
		return {"done": false, "progress": ""}
	match starting_role:
		Character.Role.CAMPESINO:
			return {"done": character.role >= Character.Role.NOBLEZA_BAJA,
				"progress": "Rango actual: %s" % character.role_name()}
		Character.Role.SOLDADO:
			var knight := character.role >= Character.Role.CABALLERO
			return {"done": knight and character.duels_won >= CAMPEON_DUELS,
				"progress": "%s · Duelos ganados %d/%d" % [
					"Caballero ✓" if knight else "Aún no eres Caballero", character.duels_won, CAMPEON_DUELS]}
		Character.Role.CABALLERO:
			var conquered := _owned_castles(character, castles, home_castle_id, false)
			return {"done": conquered >= CONQUISTADOR_CASTLES,
				"progress": "Castillos conquistados %d/%d" % [conquered, CONQUISTADOR_CASTLES]}
		Character.Role.NOBLEZA_BAJA:
			var owned := _owned_castles(character, castles, home_castle_id, true)
			return {"done": owned >= SENOR_GUERRA_CASTLES,
				"progress": "Castillos a tu nombre %d/%d" % [owned, SENOR_GUERRA_CASTLES]}
		Character.Role.NOBLEZA_ALTA:
			var count := 0
			for c: Castle in castles:
				if c.kingdom == player_kingdom:
					count += 1
			return {"done": count >= HEGEMONIA_CASTLES,
				"progress": "Castillos de tu reino %d/%d" % [count, HEGEMONIA_CASTLES]}
	return {"done": false, "progress": ""}

# Derrota por deshonra total. Devuelve el motivo o "" si no hay derrota.
static func check_defeat(character: Character) -> String:
	if character != null and character.honor <= 0:
		return "Tu honor ha caído a cero. Nadie en el reino te reconoce ya: eres desterrado."
	return ""

static func _owned_castles(character: Character, castles: Array[Castle], home_castle_id: String, include_home: bool) -> int:
	var n := 0
	var player_name := character.full_name()
	for c: Castle in castles:
		if c.owner_name == player_name:
			n += 1
		elif include_home and c.castle_id == home_castle_id:
			n += 1
	return n
