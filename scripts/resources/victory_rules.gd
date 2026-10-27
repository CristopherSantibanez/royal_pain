class_name VictoryRules
# Metas de destino de cada rol inicial. Lógica pura: no referencia autoloads.
# Ya no terminan la partida: son las hazañas de «Destino» del libro de hazañas (AchievementCatalog),
# que dan recompensas. La partida solo termina por los finales de AchievementData y DynastyData.

# --- Umbrales (ajustables sin tocar la lógica) ---
# Cada meta combina un logro propio de ese camino con subir al menos un rango, para que
# ningún camino se reduzca a repetir una sola acción.
const CAMPEON_DUELS := 10
const CONQUISTADOR_CASTLES := 1                       # conquistados por ti...
const CONQUISTADOR_RANK := Character.Role.NOBLEZA_BAJA  # ...y ennoblecido
const SENOR_GUERRA_CASTLES := 2                       # a tu nombre (el de origen cuenta)...
const SENOR_GUERRA_RANK := Character.Role.NOBLEZA_ALTA  # ...y en la alta nobleza
const HEGEMONIA_CASTLES := 5                          # castillos de tu reino, o bien ceñir la corona
# Camino mercenario
const ESPADA_CONTRACTS := 5                          # contratos cumplidos...
const ESPADA_RANK := Character.Role.CAPITAN           # ...y tu propia compañía
const COMPANIA_SOLDIERS := 100                       # una gran compañía...
const COMPANIA_RANK := Character.Role.CONDOTIERO      # ...y el rango de condotiero
const SENORIO_CASTLES := 2                           # castillos conquistados a tu nombre, o bien uno y un título

static func goal_title(starting_role: int) -> String:
	match starting_role:
		Character.Role.CAMPESINO: return "De la nada"
		Character.Role.SOLDADO: return "Campeón"
		Character.Role.CABALLERO: return "Conquistador"
		Character.Role.NOBLEZA_BAJA: return "Señor de la guerra"
		Character.Role.NOBLEZA_ALTA: return "La Corona"
		Character.Role.MERCENARIO: return "Espada de alquiler"
		Character.Role.CAPITAN: return "La Compañía Libre"
		Character.Role.CONDOTIERO: return "Un señorío propio"
	return "Sin objetivo"

## Duración aproximada de cada meta para un jugador que la persigue (orientativa).
static func goal_estimate(starting_role: int) -> String:
	match starting_role:
		Character.Role.CAMPESINO: return "unos 2 o 3 años de juego"
		Character.Role.SOLDADO: return "unos 2 años"
		Character.Role.CABALLERO: return "entre 1 y 2 años"
		Character.Role.NOBLEZA_BAJA: return "unos 3 años"
		Character.Role.NOBLEZA_ALTA: return "entre 4 y 6 años"
		Character.Role.MERCENARIO: return "unos 2 años"
		Character.Role.CAPITAN: return "entre 2 y 3 años"
		Character.Role.CONDOTIERO: return "entre 1 y 2 años"
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
			return "Asciende a Duque y ciñe la corona como Regente, o haz que tu reino controle %d de los 12 castillos." % HEGEMONIA_CASTLES
		Character.Role.MERCENARIO:
			return "Cumple %d contratos y levanta tu propia compañía como %s." % [ESPADA_CONTRACTS, Character.role_name_for(ESPADA_RANK)]
		Character.Role.CAPITAN:
			return "Llega a %s con una compañía de %d soldados." % [Character.role_name_for(COMPANIA_RANK), COMPANIA_SOLDIERS]
		Character.Role.CONDOTIERO:
			return "Funda tu señorío: conquista %d castillos a tu nombre, o uno y jura lealtad a un señor que te ennoblezca." % SENORIO_CASTLES
	return ""

# Devuelve {done: bool, progress: String}
## extra: datos que no salen del mapa (MissionData): {contracts_done, company_size}.
static func evaluate(starting_role: int, character: Character, castles: Array[Castle], player_kingdom: int, home_castle_id: String,
		extra: Dictionary = {}) -> Dictionary:
	if character == null:
		return {"done": false, "progress": ""}
	match starting_role:
		Character.Role.CAMPESINO:
			return {"done": character.rank() >= Character.rank_of(Character.Role.NOBLEZA_BAJA),
				"progress": "Rango actual: %s" % character.role_name()}
		Character.Role.SOLDADO:
			var knight := character.rank() >= Character.rank_of(Character.Role.CABALLERO)
			return {"done": knight and character.duels_won >= CAMPEON_DUELS,
				"progress": "%s · Duelos ganados %d/%d" % [
					"Caballero ✓" if knight else "Aún no eres Caballero", character.duels_won, CAMPEON_DUELS]}
		Character.Role.CABALLERO:
			var conquered := _owned_castles(character, castles, home_castle_id, false)
			var noble := character.rank() >= Character.rank_of(CONQUISTADOR_RANK)
			return {"done": conquered >= CONQUISTADOR_CASTLES and noble,
				"progress": "Castillos conquistados %d/%d · %s" % [conquered, CONQUISTADOR_CASTLES,
					_rank_progress(character, CONQUISTADOR_RANK)]}
		Character.Role.NOBLEZA_BAJA:
			var owned := _owned_castles(character, castles, home_castle_id, true)
			var high := character.rank() >= Character.rank_of(SENOR_GUERRA_RANK)
			return {"done": owned >= SENOR_GUERRA_CASTLES and high,
				"progress": "Castillos a tu nombre %d/%d · %s" % [owned, SENOR_GUERRA_CASTLES,
					_rank_progress(character, SENOR_GUERRA_RANK)]}
		Character.Role.NOBLEZA_ALTA:
			var count := 0
			for c: Castle in castles:
				if c.kingdom == player_kingdom:
					count += 1
			var crowned := character.rank() >= Character.rank_of(Character.Role.REGENTE)
			return {"done": crowned or count >= HEGEMONIA_CASTLES,
				"progress": "%s · Castillos de tu reino %d/%d" % [
					"Regente ✓" if crowned else "Aún no eres Regente", count, HEGEMONIA_CASTLES]}
		Character.Role.MERCENARIO:
			var done: int = extra.get("contracts_done", 0)
			var captain := character.rank() >= Character.rank_of(ESPADA_RANK)
			return {"done": captain and done >= ESPADA_CONTRACTS,
				"progress": "Contratos %d/%d · %s" % [done, ESPADA_CONTRACTS, _rank_progress(character, ESPADA_RANK)]}
		Character.Role.CAPITAN:
			var company: int = extra.get("company_size", 0)
			var condottiere := character.role == COMPANIA_RANK or (not character.is_mercenary() and character.rank() >= Character.rank_of(COMPANIA_RANK))
			return {"done": condottiere and company >= COMPANIA_SOLDIERS,
				"progress": "Compañía %d/%d · %s" % [company, COMPANIA_SOLDIERS,
					"%s ✓" % Character.role_name_for(COMPANIA_RANK) if condottiere else "Aún no eres %s" % Character.role_name_for(COMPANIA_RANK)]}
		Character.Role.CONDOTIERO:
			var conquered := _owned_castles(character, castles, home_castle_id, false)
			var titled := not character.is_mercenary() and character.rank() >= Character.rank_of(Character.Role.NOBLEZA_BAJA)
			return {"done": conquered >= SENORIO_CASTLES or (conquered >= 1 and titled),
				"progress": "Castillos conquistados %d/%d · %s" % [conquered, SENORIO_CASTLES,
					"Ennoblecido ✓" if titled else "Sin título (jura lealtad para tenerlo)"]}
	return {"done": false, "progress": ""}

static func _rank_progress(character: Character, rank: int) -> String:
	if character.rank() >= Character.rank_of(rank):
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
