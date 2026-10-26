class_name VictoryRules
# Condiciones de victoria y derrota. Lógica pura: no referencia autoloads.
# La meta depende del ROL INICIAL: elegir el rol en Nueva Partida es elegir el camino a la victoria.

# --- Umbrales (ajustables sin tocar la lógica) ---
# Cada meta combina un logro propio de ese camino con subir al menos un rango, para que
# ningún camino se reduzca a repetir una sola acción.
const CAMPEON_DUELS := 10
const CONQUISTADOR_CASTLES := 1                       # conquistados por ti...
const CONQUISTADOR_RANK := Character.Role.NOBLEZA_BAJA  # ...y ennoblecido
const SENOR_GUERRA_CASTLES := 2                       # a tu nombre (el de origen cuenta)...
const SENOR_GUERRA_RANK := Character.Role.NOBLEZA_ALTA  # ...y en la alta nobleza
const HEGEMONIA_CASTLES := 5                          # castillos de tu reino, o bien ceñir la corona

static func goal_title(starting_role: int) -> String:
	match starting_role:
		Character.Role.CAMPESINO: return "De la nada"
		Character.Role.SOLDADO: return "Campeón"
		Character.Role.CABALLERO: return "Conquistador"
		Character.Role.NOBLEZA_BAJA: return "Señor de la guerra"
		Character.Role.NOBLEZA_ALTA: return "La Corona"
	return "Sin objetivo"

## Duración aproximada de cada meta para un jugador que la persigue (orientativa).
static func goal_estimate(starting_role: int) -> String:
	match starting_role:
		Character.Role.CAMPESINO: return "unos 2 o 3 años de juego"
		Character.Role.SOLDADO: return "unos 2 años"
		Character.Role.CABALLERO: return "entre 1 y 2 años"
		Character.Role.NOBLEZA_BAJA: return "unos 3 años"
		Character.Role.NOBLEZA_ALTA: return "entre 3 y 5 años"
	return "?"

static func goal_description(starting_role: int) -> String:
	match starting_role:
		Character.Role.CAMPESINO:
			return "Asciende desde el campo hasta la Nobleza Baja."
		Character.Role.SOLDADO:
			return "Conviértete en Caballero y gana %d duelos." % CAMPEON_DUELS
		Character.Role.CABALLERO:
			return "Conquista un castillo con tus propios ejércitos y gánate un título de %s." % Character.role_name_for(CONQUISTADOR_RANK)
		Character.Role.NOBLEZA_BAJA:
			return "Gobierna %d castillos a tu nombre (el de origen cuenta) y asciende a %s." % [
				SENOR_GUERRA_CASTLES, Character.role_name_for(SENOR_GUERRA_RANK)]
		Character.Role.NOBLEZA_ALTA:
			return "Ciñe la corona como Regente, o haz que tu reino controle %d de los 12 castillos." % HEGEMONIA_CASTLES
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
			var noble := character.role >= CONQUISTADOR_RANK
			return {"done": conquered >= CONQUISTADOR_CASTLES and noble,
				"progress": "Castillos conquistados %d/%d · %s" % [conquered, CONQUISTADOR_CASTLES,
					_rank_progress(character, CONQUISTADOR_RANK)]}
		Character.Role.NOBLEZA_BAJA:
			var owned := _owned_castles(character, castles, home_castle_id, true)
			var high := character.role >= SENOR_GUERRA_RANK
			return {"done": owned >= SENOR_GUERRA_CASTLES and high,
				"progress": "Castillos a tu nombre %d/%d · %s" % [owned, SENOR_GUERRA_CASTLES,
					_rank_progress(character, SENOR_GUERRA_RANK)]}
		Character.Role.NOBLEZA_ALTA:
			var count := 0
			for c: Castle in castles:
				if c.kingdom == player_kingdom:
					count += 1
			var crowned := character.role >= Character.Role.REGENTE
			return {"done": crowned or count >= HEGEMONIA_CASTLES,
				"progress": "%s · Castillos de tu reino %d/%d" % [
					"Regente ✓" if crowned else "Aún no eres Regente", count, HEGEMONIA_CASTLES]}
	return {"done": false, "progress": ""}

# Derrota por deshonra total. Devuelve el motivo o "" si no hay derrota.
static func check_defeat(character: Character) -> String:
	if character != null and character.honor <= 0:
		return "Tu honor ha caído a cero. Nadie en el reino te reconoce ya: eres desterrado."
	return ""

static func _rank_progress(character: Character, rank: int) -> String:
	if character.role >= rank:
		return "%s ✓" % Character.role_name_for(rank)
	return "Aún no eres %s" % Character.role_name_for(rank)

static func _owned_castles(character: Character, castles: Array[Castle], home_castle_id: String, include_home: bool) -> int:
	var n := 0
	var player_name := character.full_name()
	for c: Castle in castles:
		if c.owner_name == player_name:
			n += 1
		elif include_home and c.castle_id == home_castle_id:
			n += 1
	return n
