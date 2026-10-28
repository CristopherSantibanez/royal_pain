extends RefCounted
# Ocupaciones del mes para tu cónyuge y tu séquito, duelos de práctica y reparto automático
# de puntos al subir de nivel. Lógica pura (la aplica RelationsData al pasar el mes).
#   const OccupationRules = preload("res://scripts/resources/occupation_rules.gd")

const XpRules = preload("res://scripts/resources/xp_rules.gd")

const ADMINISTRAR := "administrar"
const ENTRENAR := "entrenar"
const ESTUDIAR := "estudiar"
const DESCANSAR := "descansar"
const ALL := [ADMINISTRAR, ENTRENAR, ESTUDIAR, DESCANSAR]
const DEFAULT := DESCANSAR

const NAMES := {ADMINISTRAR: "Administrar", ENTRENAR: "Entrenar", ESTUDIAR: "Estudiar", DESCANSAR: "Descansar"}
const DESCRIPTIONS := {
	ADMINISTRAR: "Lleva tus cuentas y tus tratos: rinde oro cada mes según su Carisma y su Estrategia.",
	ENTRENAR: "Se ejercita con las armas: gana experiencia y a veces sube su Combate.",
	ESTUDIAR: "Estudia tratados y mapas: gana experiencia y a veces sube su Estrategia.",
	DESCANSAR: "Reposa: se cura antes de sus heridas. Quien está herido descansa por fuerza.",
}

const ADMIN_BASE_GOLD := 2                 # oro al mes por administrar...
const ADMIN_GOLD_PER_POINT := 0.6          # ...más esto por cada punto de Carisma + Estrategia
const OCCUPATION_XP := 20                  # experiencia al mes por entrenar o estudiar (antes del tipo de luchador)
const STAT_UP_CHANCE := 0.15               # probabilidad al mes de +1 en Combate (entrenar) o Estrategia (estudiar)
const STAT_CAP := 20
const REST_EXTRA_WOUND_MONTHS := 1         # meses de herida que se curan de más al descansar

# Duelo de práctica con un compañero: sin heridas, sin honor en juego, algo de experiencia y de trato.
const PRACTICE_XP_WIN := 15
const PRACTICE_XP_LOSS := 8
const PRACTICE_INTIMACY := 3

# Al subir de nivel, cada tipo de luchador reparte sus puntos en este orden de preferencia.
const AUTO_STAT_ORDER := {
	CharacterEnums.FighterType.DUELISTA: ["combat", "defense", "charisma"],
	CharacterEnums.FighterType.TANQUE: ["defense", "combat", "leadership"],
	CharacterEnums.FighterType.ESTRATEGA: ["strategy", "leadership", "charisma"],
	CharacterEnums.FighterType.BERSERKER: ["combat", "combat", "defense"],
	CharacterEnums.FighterType.DEFENSOR: ["defense", "defense", "leadership"],
	CharacterEnums.FighterType.ASESINO: ["combat", "strategy", "charisma"],
}

static func name_of(id: String) -> String:
	return NAMES.get(id, NAMES[DEFAULT])

static func admin_gold(c: Character) -> int:
	return ADMIN_BASE_GOLD + roundi((c.charisma + c.strategy) * ADMIN_GOLD_PER_POINT)

## Lo que se espera de la ocupación, para la interfaz.
static func preview(c: Character, id: String) -> String:
	match id:
		ADMINISTRAR: return "+%d de oro al mes" % admin_gold(c)
		ENTRENAR: return "+%d exp. al mes (como %s) · a veces +1 Combate" % [
			roundi(OCCUPATION_XP * XpRules.multiplier(c.fighter_type, XpRules.SOURCE_TRAINING)), _fighter(c)]
		ESTUDIAR: return "+%d exp. al mes (como %s) · a veces +1 Estrategia" % [
			roundi(OCCUPATION_XP * XpRules.multiplier(c.fighter_type, XpRules.SOURCE_STUDY)), _fighter(c)]
	return "Cura heridas más deprisa"

## Aplica un mes de ocupación. Devuelve {"text": resumen corto, "gold": oro producido}.
## Quien está herido descansa aunque tenga otra ocupación.
static func apply(c: Character, id: String) -> Dictionary:
	var name := c.first_name
	if c.is_wounded() or id == DESCANSAR:
		var forced := c.is_wounded() and id != DESCANSAR
		c.monthly_recovery()
		if c.wound_months > 0:
			c.wound_months = maxi(0, c.wound_months - REST_EXTRA_WOUND_MONTHS)
		c.current_health = c.max_health if not c.is_wounded() else c.current_health
		var state := "ya está sano" if not c.is_wounded() else "aún herido (%d %s)" % [c.wound_months, "mes" if c.wound_months == 1 else "meses"]
		return {"text": "%s descansa%s: %s" % [name, " por sus heridas" if forced else "", state], "gold": 0}
	c.monthly_recovery()
	match id:
		ADMINISTRAR:
			var gold := admin_gold(c)
			return {"text": "%s administra: +%d de oro" % [name, gold], "gold": gold}
		ENTRENAR:
			return {"text": _learn(c, XpRules.SOURCE_TRAINING, "combat", "Combate"), "gold": 0}
		ESTUDIAR:
			return {"text": _learn(c, XpRules.SOURCE_STUDY, "strategy", "Estrategia"), "gold": 0}
	return {"text": "", "gold": 0}

static func _learn(c: Character, source: String, stat: String, stat_name: String) -> String:
	var levels := c.gain_xp(OCCUPATION_XP, source)
	var text := "%s %s: +%d exp." % [c.first_name, "entrena" if source == XpRules.SOURCE_TRAINING else "estudia", c.last_xp_gained]
	if int(c.get(stat)) < STAT_CAP and randf() < STAT_UP_CHANCE:
		c.set(stat, int(c.get(stat)) + 1)
		text += ", %s +1" % stat_name
	if levels > 0:
		text += ", ¡sube a nivel %d!" % c.level
	return text

## Reparte los puntos de atributo pendientes según el tipo de luchador. Devuelve cuántos repartió.
static func auto_spend_points(c: Character) -> int:
	var order: Array = AUTO_STAT_ORDER.get(c.fighter_type, ["combat", "defense", "strategy"])
	var spent := 0
	var guard := 0
	while c.unspent_points > 0 and guard < 50:
		var stat: String = order[guard % order.size()]
		guard += 1
		if int(c.get(stat)) >= STAT_CAP:
			continue
		c.set(stat, int(c.get(stat)) + 1)
		c.unspent_points -= 1
		spent += 1
	return spent

static func _fighter(c: Character) -> String:
	for key in CharacterEnums.FighterType:
		if CharacterEnums.FighterType[key] == c.fighter_type:
			return str(key).capitalize()
	return "?"
