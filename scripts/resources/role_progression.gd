class_name RoleProgression

# --- Umbrales de ascenso (ajustables sin tocar el resto del sistema) ---
# Campesino -> Soldado ("alistarse"): pagar las armas, o demostrar que ya sabes pelear.
const ALISTARSE_GOLD := 60
const ALISTARSE_MIN_COMBAT := 9

const SOLDADO_MIN_DUELS_WON := 3
const SOLDADO_MIN_HONOR := 60

const NOBLEZA_BAJA_MIN_HONOR := 75
const NOBLEZA_BAJA_MIN_GOLD := 500

const NOBLEZA_ALTA_MIN_LEADERSHIP := 12
const NOBLEZA_ALTA_MIN_GOLD := 2000

# Nobleza Alta -> Duque: gobernar varios castillos como gran vasallo del rey
const DUQUE_MIN_CASTLES := 2       # castillos de tu reino a tu nombre (el de origen cuenta)
const DUQUE_MIN_HONOR := 70
const DUQUE_MIN_LEADERSHIP := 14

# Camino mercenario
const CAPITAN_MIN_CONTRACTS := 2
const CAPITAN_MIN_FAME := 20
const CAPITAN_GOLD := 150          # lo que cuesta levantar tu propia compañía
const CONDOTIERO_MIN_CONTRACTS := 5
const CONDOTIERO_MIN_FAME := 45
const CONDOTIERO_MIN_LEADERSHIP := 10
const CONDOTIERO_MIN_COMPANY := 60

# Sucesión Duque -> Regente: honor alto y uno de dos caminos
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
		Character.Role.NOBLEZA_ALTA: return Character.Role.DUQUE
		Character.Role.DUQUE: return Character.Role.REGENTE
		Character.Role.MERCENARIO: return Character.Role.CAPITAN
		Character.Role.CAPITAN: return Character.Role.CONDOTIERO
		_: return -1   # Regente es la cima; el Condotiero se ennoblece jurando lealtad a un señor

static func check_ascension(character: Character, succession: Dictionary = {}) -> Dictionary:
	# Devuelve {can_ascend: bool, next_role: int, reason: String}
	# "reason" explica qué falta cuando can_ascend es false, útil para mostrar en UI.
	# "succession" (ver MissionData.progression_context): {liege_name, married_to_liege: bool, kingdom_castles: int,
	#   contracts_done, company_size} — los mercenarios usan los dos últimos.
	var target := next_role(character.role)
	if target == -1:
		return {"can_ascend": false, "next_role": -1, "reason": "No hay un ascenso disponible desde este rol todavía."}

	match character.role:
		Character.Role.CAMPESINO:
			if character.gold < ALISTARSE_GOLD and character.combat < ALISTARSE_MIN_COMBAT:
				return {"can_ascend": false, "next_role": target, "reason":
					"Para alistarte necesitas %d de oro para armas (tienes %d) o Combate %d+ (tienes %d)." % [
						ALISTARSE_GOLD, character.gold, ALISTARSE_MIN_COMBAT, character.combat]}
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
			var owned: int = succession.get("kingdom_castles", 0)
			var needs: Array[String] = []
			if owned < DUQUE_MIN_CASTLES:
				needs.append("gobernar %d castillos de tu reino (tienes %d)" % [DUQUE_MIN_CASTLES, owned])
			if character.honor < DUQUE_MIN_HONOR:
				needs.append("%d+ de honor (tienes %d)" % [DUQUE_MIN_HONOR, character.honor])
			if character.leadership < DUQUE_MIN_LEADERSHIP:
				needs.append("%d+ de liderazgo (tienes %d)" % [DUQUE_MIN_LEADERSHIP, character.leadership])
			if not needs.is_empty():
				return {"can_ascend": false, "next_role": target, "reason": "Necesitas " + ", ".join(needs) + "."}
			return {"can_ascend": true, "next_role": target, "reason": ""}

		Character.Role.MERCENARIO:
			var done: int = succession.get("contracts_done", 0)
			if done < CAPITAN_MIN_CONTRACTS or character.fame < CAPITAN_MIN_FAME or character.gold < CAPITAN_GOLD:
				return {"can_ascend": false, "next_role": target, "reason":
					"Necesitas %d contratos cumplidos (tienes %d), %d de fama (tienes %d) y %d de oro para levantar tu compañía (tienes %d)." % [
						CAPITAN_MIN_CONTRACTS, done, CAPITAN_MIN_FAME, character.fame, CAPITAN_GOLD, character.gold]}
			return {"can_ascend": true, "next_role": target, "reason": ""}

		Character.Role.CAPITAN:
			var done: int = succession.get("contracts_done", 0)
			var company: int = succession.get("company_size", 0)
			var needs: Array[String] = []
			if done < CONDOTIERO_MIN_CONTRACTS:
				needs.append("%d contratos cumplidos (tienes %d)" % [CONDOTIERO_MIN_CONTRACTS, done])
			if character.fame < CONDOTIERO_MIN_FAME:
				needs.append("%d de fama (tienes %d)" % [CONDOTIERO_MIN_FAME, character.fame])
			if character.leadership < CONDOTIERO_MIN_LEADERSHIP:
				needs.append("%d de liderazgo (tienes %d)" % [CONDOTIERO_MIN_LEADERSHIP, character.leadership])
			if company < CONDOTIERO_MIN_COMPANY:
				needs.append("una compañía de %d soldados (tienes %d)" % [CONDOTIERO_MIN_COMPANY, company])
			if not needs.is_empty():
				return {"can_ascend": false, "next_role": target, "reason": "Necesitas " + ", ".join(needs) + "."}
			return {"can_ascend": true, "next_role": target, "reason": ""}

		Character.Role.DUQUE:
			var married: bool = succession.get("married_to_liege", false)
			var castles: int = succession.get("kingdom_castles", 0)
			var liege: String = str(succession.get("liege_name", ""))
			if liege.is_empty():
				liege = "el soberano"
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
	# Quien se alista sin saber pelear paga sus propias armas.
	if character.role == Character.Role.CAMPESINO and character.combat < ALISTARSE_MIN_COMBAT:
		character.gold -= ALISTARSE_GOLD
	if character.role == Character.Role.MERCENARIO:
		character.gold -= CAPITAN_GOLD   # quien llama crea la compañía (MissionData.raise_company)
	character.role = result.next_role
	return true

# --- Descenso por deshonor (Caballero o superior con honor muy bajo) ---

static func check_dishonor_demotion(character: Character) -> bool:
	if character.role in [Character.Role.CABALLERO, Character.Role.NOBLEZA_BAJA, Character.Role.NOBLEZA_ALTA, Character.Role.DUQUE]:
		return character.honor < DISHONOR_THRESHOLD
	return false

static func apply_dishonor_demotion(character: Character) -> void:
	match character.role:
		Character.Role.CABALLERO: character.role = Character.Role.SOLDADO
		Character.Role.NOBLEZA_BAJA: character.role = Character.Role.CABALLERO
		Character.Role.NOBLEZA_ALTA: character.role = Character.Role.NOBLEZA_BAJA
		Character.Role.DUQUE: character.role = Character.Role.NOBLEZA_ALTA
	character.honor = clamp(character.honor + 15, 0, 100)   # tras la caída, se estabiliza un poco

# --- Deshonra total (honor 0): ya no termina la partida, pero cuesta caro ---
const DISGRACE_HONOR_RESET := 15     # tras la caída, el honor se rehace desde aquí
const DISGRACE_FAME_LOSS := 10
const DISGRACE_DEMOTION := {
	Character.Role.SOLDADO: Character.Role.CAMPESINO,
	Character.Role.CABALLERO: Character.Role.SOLDADO,
	Character.Role.NOBLEZA_BAJA: Character.Role.CABALLERO,
	Character.Role.NOBLEZA_ALTA: Character.Role.NOBLEZA_BAJA,
	Character.Role.DUQUE: Character.Role.NOBLEZA_ALTA,
	Character.Role.REGENTE: Character.Role.DUQUE,
	Character.Role.CONDOTIERO: Character.Role.CAPITAN,
	Character.Role.CAPITAN: Character.Role.MERCENARIO,
}
# Sin tierras propias, tu señor te expulsa de su servicio y quedas como mercenario.
const DISGRACE_EXPELLED_ROLES := [Character.Role.SOLDADO, Character.Role.CABALLERO]

static func is_disgraced(character: Character) -> bool:
	return character != null and character.honor <= 0

## Aplica la deshonra: pierdes un rango, fama, y si servías sin tierras tu señor te expulsa.
## Devuelve {text, expelled}. Quien llama se ocupa de olvidar el vasallaje si expelled es true.
static func apply_disgrace(character: Character, has_liege: bool) -> Dictionary:
	var old_title := character.role_title()
	var expelled := has_liege and character.role in DISGRACE_EXPELLED_ROLES
	if expelled:
		character.role = Character.Role.MERCENARIO
	elif DISGRACE_DEMOTION.has(character.role):
		character.role = DISGRACE_DEMOTION[character.role]
	character.honor = DISGRACE_HONOR_RESET
	character.fame = maxi(0, character.fame - DISGRACE_FAME_LOSS)
	var text := "Tu honor ha caído a cero: nadie respeta ya tu palabra."
	if expelled:
		text += " Tu señor te expulsa de su servicio; de %s pasas a vender tu espada como %s." % [old_title, character.role_title()]
	elif character.role_title() != old_title:
		text += " Pierdes tu dignidad de %s y pasas a ser %s." % [old_title, character.role_title()]
	text += " Fama −%d. Te queda rehacer tu nombre (honor %d)." % [DISGRACE_FAME_LOSS, DISGRACE_HONOR_RESET]
	return {"text": text, "expelled": expelled}

# --- Lealtad jurada (la llama el viaje al jurar lealtad a otro señor) ---
# Un mercenario que jura lealtad entra en la escalera noble a su altura; los nobles conservan su rango.
const FEALTY_ROLE := {
	Character.Role.MERCENARIO: Character.Role.SOLDADO,
	Character.Role.CAPITAN: Character.Role.CABALLERO,
	Character.Role.CONDOTIERO: Character.Role.NOBLEZA_BAJA,
}

## Devuelve el texto del cambio de rango ("" si no cambia). lord_castle: el castillo del nuevo señor.
static func on_fealty_sworn(character: Character, lord_castle) -> String:
	if character == null or not FEALTY_ROLE.has(character.role):
		return ""
	var old_title := character.role_title()
	character.role = FEALTY_ROLE[character.role]
	var where := ""
	if lord_castle is Castle:
		where = " en %s" % (lord_castle as Castle).castle_name
	return "Dejas de ser %s: juras lealtad%s y pasas a ser %s." % [old_title, where, character.role_title()]

## Pierdes todos tus castillos: si sobrevives, te queda vender tu espada.
static func landless_role(character: Character) -> int:
	if character.is_mercenary():
		return character.role
	return Character.Role.CAPITAN if character.rank() >= Character.rank_of(Character.Role.NOBLEZA_BAJA) else Character.Role.MERCENARIO
