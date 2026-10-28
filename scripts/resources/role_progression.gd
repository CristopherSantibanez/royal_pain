class_name RoleProgression

# --- Umbrales de ascenso (ajustables sin tocar el resto del sistema) ---
# Campesino (o no afiliado) -> Soldado ("alistarse"): pagar las armas, o demostrar que ya sabes pelear.
const ALISTARSE_GOLD := 150        # antes 60: ya no se asciende nada más empezar
const ALISTARSE_MIN_COMBAT := 12   # antes 9

const SOLDADO_MIN_DUELS_WON := 4   # antes 3
const SOLDADO_MIN_HONOR := 60

const NOBLEZA_BAJA_MIN_HONOR := 75
const NOBLEZA_BAJA_MIN_GOLD := 500

const NOBLEZA_ALTA_MIN_LEADERSHIP := 12
const NOBLEZA_ALTA_MIN_GOLD := 2000

# Nobleza Alta -> Duque: gobernar varios castillos como gran vasallo del rey
const DUQUE_MIN_CASTLES := 2       # castillos de tu reino a tu nombre (el de origen cuenta)
const DUQUE_MIN_HONOR := 70
const DUQUE_MIN_LEADERSHIP := 14

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
		_: return -1   # el no afiliado no asciende aquí: se alista o se asienta en un castillo; Regente es la cima

static func check_ascension(character: Character, succession: Dictionary = {}) -> Dictionary:
	# Devuelve {can_ascend: bool, next_role: int, reason: String}
	# "reason" explica qué falta cuando can_ascend es false, útil para mostrar en UI.
	# "succession" (ver MissionData.progression_context): {liege_name, married_to_liege: bool, kingdom_castles: int}
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
}
# Sin tierras propias, tu señor te expulsa de su servicio y quedas sin afiliación.
const DISGRACE_EXPELLED_ROLES := [Character.Role.SOLDADO, Character.Role.CABALLERO]

static func is_disgraced(character: Character) -> bool:
	return character != null and character.honor <= 0

## Aplica la deshonra: pierdes un rango, fama, y si servías sin tierras tu señor te expulsa.
## Devuelve {text, expelled}. Quien llama se ocupa de olvidar el vasallaje si expelled es true.
static func apply_disgrace(character: Character, has_liege: bool) -> Dictionary:
	var old_title := character.role_title()
	var expelled := has_liege and character.role in DISGRACE_EXPELLED_ROLES
	if expelled:
		character.role = Character.Role.INAFILIADO
	elif DISGRACE_DEMOTION.has(character.role):
		character.role = DISGRACE_DEMOTION[character.role]
	character.honor = DISGRACE_HONOR_RESET
	character.fame = maxi(0, character.fame - DISGRACE_FAME_LOSS)
	var text := "Tu honor ha caído a cero: nadie respeta ya tu palabra."
	if expelled:
		text += " Tu señor te expulsa de su servicio; de %s pasas a ser %s." % [old_title, character.role_title()]
	elif character.role_title() != old_title:
		text += " Pierdes tu dignidad de %s y pasas a ser %s." % [old_title, character.role_title()]
	text += " Fama −%d. Te queda rehacer tu nombre (honor %d)." % [DISGRACE_FAME_LOSS, DISGRACE_HONOR_RESET]
	return {"text": text, "expelled": expelled}

# --- Lealtad jurada (la llama el viaje al jurar lealtad a otro señor) ---
# Quien no tiene afiliación y jura lealtad se asienta; los nobles conservan su rango.
const FEALTY_ROLE := {
	Character.Role.INAFILIADO: Character.Role.CAMPESINO,   # jurar lealtad sin más es asentarse
}

## Motivo por el que no puedes alistarte como soldado ("" si puedes): el mismo requisito que el Campesino.
static func enlist_blocker(character: Character) -> String:
	if character.gold < ALISTARSE_GOLD and character.combat < ALISTARSE_MIN_COMBAT:
		return "Necesitas %d de oro para las armas (tienes %d) o Combate %d (tienes %d)." % [
			ALISTARSE_GOLD, character.gold, ALISTARSE_MIN_COMBAT, character.combat]
	return ""

## Quien se alista sin saber pelear paga sus armas.
static func pay_enlist(character: Character) -> int:
	if character.combat >= ALISTARSE_MIN_COMBAT:
		return 0
	character.gold -= ALISTARSE_GOLD
	return ALISTARSE_GOLD

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

## Pierdes todos tus castillos: si sobrevives, quedas sin afiliación.
static func landless_role(_character: Character) -> int:
	return Character.Role.INAFILIADO

## Partidas antiguas: los roles mercenarios (ya retirados) pasan a la escalera normal.
## Mercenario y Capitán -> No afiliado; Condotiero con castillo propio -> Nobleza Baja, si no -> No afiliado.
static func migrate_legacy_role(character: Character) -> bool:
	if character == null or not Character.is_legacy_role(character.role):
		return false
	var owns_castle := false
	if character.role == Character.Role.CONDOTIERO:
		var tree := Engine.get_main_loop() as SceneTree
		var relations := tree.root.get_node_or_null("RelationsData") if tree != null else null
		owns_castle = relations != null and not relations.castles_of(character.full_name()).is_empty()
	character.role = Character.Role.NOBLEZA_BAJA if owns_castle else Character.Role.INAFILIADO
	return true
