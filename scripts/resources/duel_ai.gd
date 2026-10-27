class_name DuelAI
extends RefCounted
# Decide postura y acción de un luchador controlado por la IA en un duelo.
# Lógica pura: lee el estado del DuelManager y devuelve {posture, action}.
# Cada personalidad pondera las acciones a su manera, así el estilo de pelea
# coincide con lo que el personaje dice (ver DialogueCatalog).

const A := CombatEnums.ActionType
const P := CombatEnums.Posture

# Multiplicadores por personalidad sobre el peso de cada acción.
const STYLE := {
	Character.Personality.ARROGANTE: {A.ATACAR: 1.4, A.DEFENDER: 0.4, A.CONTRAATACAR: 0.8, A.ESQUIVAR: 0.5, A.DESARMAR: 0.7, A.EMPUJAR: 1.2},
	Character.Personality.PRUDENTE: {A.ATACAR: 0.9, A.DEFENDER: 1.6, A.CONTRAATACAR: 1.8, A.ESQUIVAR: 1.0, A.DESARMAR: 0.8, A.EMPUJAR: 0.8},
	Character.Personality.ASTUTO: {A.ATACAR: 0.9, A.DEFENDER: 0.8, A.CONTRAATACAR: 1.2, A.ESQUIVAR: 1.5, A.DESARMAR: 2.5, A.EMPUJAR: 2.0},
	Character.Personality.LEAL: {A.ATACAR: 1.0, A.DEFENDER: 1.2, A.CONTRAATACAR: 1.3, A.ESQUIVAR: 0.9, A.DESARMAR: 1.0, A.EMPUJAR: 1.0},
	Character.Personality.PIADOSO: {A.ATACAR: 0.9, A.DEFENDER: 1.4, A.CONTRAATACAR: 1.1, A.ESQUIVAR: 1.0, A.DESARMAR: 0.8, A.EMPUJAR: 0.7},
	Character.Personality.AMBICIOSO: {A.ATACAR: 1.3, A.DEFENDER: 0.8, A.CONTRAATACAR: 1.0, A.ESQUIVAR: 0.9, A.DESARMAR: 1.2, A.EMPUJAR: 1.1},
	Character.Personality.VALIENTE: {A.ATACAR: 1.3, A.DEFENDER: 0.6, A.CONTRAATACAR: 1.0, A.ESQUIVAR: 0.5, A.DESARMAR: 0.8, A.EMPUJAR: 1.0},
	Character.Personality.CRUEL: {A.ATACAR: 1.15, A.DEFENDER: 0.8, A.CONTRAATACAR: 0.9, A.ESQUIVAR: 0.7, A.DESARMAR: 1.3, A.EMPUJAR: 1.1},
	Character.Personality.GENEROSO: {A.ATACAR: 1.0, A.DEFENDER: 1.2, A.CONTRAATACAR: 1.1, A.ESQUIVAR: 1.0, A.DESARMAR: 1.3, A.EMPUJAR: 0.8},
	Character.Personality.COBARDE: {A.ATACAR: 0.7, A.DEFENDER: 1.6, A.CONTRAATACAR: 0.9, A.ESQUIVAR: 1.8, A.DESARMAR: 0.6, A.EMPUJAR: 0.6},
	Character.Personality.ROMANTICO: {A.ATACAR: 1.1, A.DEFENDER: 0.6, A.CONTRAATACAR: 1.4, A.ESQUIVAR: 1.4, A.DESARMAR: 1.0, A.EMPUJAR: 0.8},
	Character.Personality.HONORABLE: {A.ATACAR: 1.1, A.DEFENDER: 1.2, A.CONTRAATACAR: 1.5, A.ESQUIVAR: 0.9, A.DESARMAR: 0.4, A.EMPUJAR: 0.2},
}

# Destreza táctica según el rango: cuánto lee al rival y con qué constancia elige lo mejor.
# Los campeones (personajes con el meta "champion") pelean como un rango por encima.
const ROLE_INSIGHT := {
	Character.Role.CAMPESINO: 0.6, Character.Role.SOLDADO: 0.85, Character.Role.CABALLERO: 1.0,
	Character.Role.NOBLEZA_BAJA: 1.15, Character.Role.NOBLEZA_ALTA: 1.3, Character.Role.REGENTE: 1.4,
	Character.Role.DUQUE: 1.35, Character.Role.MERCENARIO: 0.95, Character.Role.CAPITAN: 1.1, Character.Role.CONDOTIERO: 1.2, Character.Role.INAFILIADO: 0.85,
}
const CHAMPION_INSIGHT := 0.25
const READ_INSIGHT := 0.5          # leer al rival (Estrategia) afina un poco sus decisiones
# Las posturas cierran acciones: si la postura preferida deja fuera más de la mitad de lo que
# quiere hacer, cambia a la que mejor encaje (con algo de apego a la suya).
const POSTURE_SWITCH_RATIO := 0.5
const POSTURE_ALT_FACTOR := 0.8

const FEINT_BASE := 0.1          # casi nunca finta a ciegas
const FEINT_VS_COUNTER := 1.3    # el rival espera para parar: la finta es la respuesta
const FEINT_VS_HABIT := 1.4      # el rival suele contraatacar

static func insight(me: Character) -> float:
	var value: float = ROLE_INSIGHT.get(me.role, 1.0)
	if me.has_meta("champion"):
		value += CHAMPION_INSIGHT
	return value

static func choose(d: DuelManager, me: Character, foe: Character) -> Dictionary:
	var personality: int = me.personality
	var my_hp := float(me.current_health) / me.max_health
	var foe_hp := float(foe.current_health) / foe.max_health
	var tired := d.is_fatigued(me)
	var disarmed: bool = CombatEnums.Status.DESARMADO in d.statuses[me]
	var foe_guarding: bool = d.defending[foe] or d.dodging[foe] or d.countering[foe]

	# Rendirse o huir: solo algunos caracteres, y solo cuando la pelea está perdida.
	if my_hp < 0.15 and foe_hp > 0.5:
		if personality == Character.Personality.PRUDENTE and randf() < 0.5:
			return {"posture": P.MURO, "action": A.RENDIRSE}
		if personality == Character.Personality.AMBICIOSO and randf() < 0.3:
			return {"posture": P.DEFENSIVA, "action": A.RETIRARSE}
	if personality == Character.Personality.COBARDE and my_hp < 0.3 and foe_hp > my_hp and randf() < 0.45:
		return {"posture": P.MURO, "action": A.RETIRARSE if randf() < 0.6 else A.RENDIRSE}
	var sharp := insight(me) + READ_INSIGHT * d.read_chance(me, foe)

	var w := {A.ATACAR: 2.0, A.DEFENDER: 0.3, A.ESQUIVAR: 0.2, A.CONTRAATACAR: 0.45, A.DESARMAR: 0.2, A.EMPUJAR: 0.2, A.FINTA: FEINT_BASE}
	# Finta: la respuesta al que espera para parar (el que suele contraatacar lo volverá a hacer).
	if d.countering[foe]:
		w[A.FINTA] += FEINT_VS_COUNTER * sharp
	w[A.FINTA] += _counter_rate(d, foe) * FEINT_VS_HABIT * sharp
	if foe_guarding:
		w[A.EMPUJAR] += 2.0 * sharp       # romper la guardia es la respuesta natural
		w[A.ATACAR] *= 0.5
	# Si el rival no hace más que atacar, conviene esperarlo con una parada (los expertos lo notan antes).
	var foe_aggression := d.attack_rate(foe)
	w[A.CONTRAATACAR] += foe_aggression * foe_aggression * 1.6 * sharp
	w[A.ESQUIVAR] += foe_aggression * 0.3
	if tired:
		w[A.DEFENDER] += 1.5      # recobrar el aliento
		w[A.ATACAR] *= 0.5
		w[A.DESARMAR] = 0.0
		w[A.EMPUJAR] = 0.0
		w[A.FINTA] = 0.0
	if my_hp < 0.35:
		w[A.DEFENDER] += 0.4
		w[A.CONTRAATACAR] += 0.3
	if CombatEnums.Status.DESARMADO in d.statuses[foe]:
		w[A.ATACAR] += 1.0
	# Combos: aprovechar la ventaja propia y no regalarle golpes a la del rival.
	var my_adv: String = d.advantage.get(me, "")
	var foe_adv: String = d.advantage.get(foe, "")
	if my_adv == d.ADV_CONTRA or my_adv == d.ADV_ACECHO or my_adv == d.ADV_ABIERTO:
		w[A.ATACAR] *= 1.0 + 2.0 * sharp
	elif my_adv == d.ADV_DESEQUILIBRIO:
		w[A.DESARMAR] += 1.5 * sharp
	if foe_adv == d.ADV_CONTRA or foe_adv == d.ADV_ACECHO:
		w[A.DEFENDER] += 0.8 * sharp
		w[A.ESQUIVAR] += 0.8 * sharp
		if foe_adv == d.ADV_CONTRA:
			w[A.CONTRAATACAR] *= 0.2   # la contra devastadora no se puede parar
	if d.is_predictable(me):
		w[A.ATACAR] *= 0.6
	if disarmed:
		w[A.ATACAR] = 0.0
		w[A.DESARMAR] = 0.0
		w[A.FINTA] = 0.0
	var style: Dictionary = STYLE.get(personality, {})
	for action in w:
		# Más destreza = elige lo mejor con más constancia (los pesos se acentúan).
		w[action] = pow(w[action] * style.get(action, 1.0), sharp)

	var posture := _coherent_posture(_pick_posture(personality, my_hp, foe_hp, tired), w)
	for action in w.keys():
		if CombatEnums.is_blocked(posture, action):
			w[action] = 0.0
	if _sum(w) <= 0.0:
		return {"posture": P.DEFENSIVA, "action": A.DEFENDER}
	return {"posture": posture, "action": _weighted_pick(w)}

## Proporción de contraataques entre las últimas acciones del rival (0..1).
static func _counter_rate(d: DuelManager, c: Character) -> float:
	var history: Array = d.last_actions.get(c, [])
	if history.is_empty():
		return 0.0
	return float(history.count(A.CONTRAATACAR)) / history.size()

static func _sum(weights: Dictionary) -> float:
	var total := 0.0
	for v in weights.values():
		total += v
	return total

## Peso de lo que quiere hacer que esa postura le deja hacer.
static func _allowed_weight(posture: int, w: Dictionary) -> float:
	var total := 0.0
	for action in w:
		if not CombatEnums.is_blocked(posture, action):
			total += w[action]
	return total

static func _coherent_posture(preferred: int, w: Dictionary) -> int:
	var total := _sum(w)
	if total <= 0.0 or _allowed_weight(preferred, w) >= total * POSTURE_SWITCH_RATIO:
		return preferred
	var best := preferred
	var best_score := _allowed_weight(preferred, w)
	for p in P.values():
		var score := _allowed_weight(p, w) * POSTURE_ALT_FACTOR
		if score > best_score:
			best = p
			best_score = score
	return best

static func _pick_posture(personality: int, my_hp: float, foe_hp: float, tired: bool) -> int:
	if tired:
		return P.DEFENSIVA
	match personality:
		Character.Personality.ARROGANTE:
			return P.DESESPERADA if foe_hp < 0.4 or my_hp < 0.25 else P.OFENSIVA
		Character.Personality.PRUDENTE:
			return P.MURO if my_hp < 0.4 else P.DEFENSIVA
		Character.Personality.ASTUTO:
			return P.ESGRIMA
		Character.Personality.AMBICIOSO:
			if foe_hp < 0.3:
				return P.DESESPERADA
			return P.OFENSIVA if my_hp >= foe_hp else P.DEFENSIVA
		Character.Personality.LEAL, Character.Personality.PIADOSO, Character.Personality.GENEROSO:
			return P.OFENSIVA if foe_hp < 0.35 else P.DEFENSIVA
		Character.Personality.VALIENTE:
			return P.DESESPERADA if my_hp < 0.3 else P.OFENSIVA
		Character.Personality.CRUEL:
			return P.DESESPERADA if foe_hp < 0.25 else (P.DEFENSIVA if my_hp < 0.5 else P.OFENSIVA)
		Character.Personality.COBARDE:
			return P.MURO if my_hp < 0.6 else P.DEFENSIVA
		Character.Personality.ROMANTICO:
			return P.DESESPERADA if my_hp < 0.25 else P.ESGRIMA
		Character.Personality.HONORABLE:
			return P.OFENSIVA if foe_hp < 0.4 else P.DEFENSIVA
	return P.OFENSIVA

static func _weighted_pick(weights: Dictionary) -> int:
	var total := _sum(weights)
	var roll := randf() * total
	for action in weights:
		roll -= weights[action]
		if roll <= 0.0 and weights[action] > 0.0:
			return action
	for action in weights:
		if weights[action] > 0.0:
			return action
	return A.DEFENDER
