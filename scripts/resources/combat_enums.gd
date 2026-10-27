class_name CombatEnums

enum Posture { OFENSIVA, DEFENSIVA, ESGRIMA, MURO, DESESPERADA }
enum ActionType { ATACAR, DEFENDER, ESQUIVAR, CONTRAATACAR, DESARMAR, EMPUJAR, RENDIRSE, RETIRARSE, FINTA }   # las nuevas, siempre al final
enum Status { HERIDO, FATIGADO, DESARMADO, DESMORALIZADO, INSPIRADO }

# Cada postura compromete: cierra las acciones que no le cuadran. Rendirse y Retirarse siempre se pueden.
# La Finta pide soltura: Muro (inmóvil) y Desesperada (sin cabeza para engaños) no la permiten.
const BLOCKED_ACTIONS := {
	Posture.OFENSIVA: [ActionType.DEFENDER, ActionType.ESQUIVAR],
	Posture.DEFENSIVA: [ActionType.EMPUJAR],
	Posture.ESGRIMA: [ActionType.EMPUJAR],
	Posture.MURO: [ActionType.ESQUIVAR, ActionType.DESARMAR, ActionType.FINTA],
	Posture.DESESPERADA: [ActionType.DEFENDER, ActionType.ESQUIVAR, ActionType.DESARMAR, ActionType.CONTRAATACAR, ActionType.FINTA],
}

static func is_blocked(p: int, a: int) -> bool:
	return a in BLOCKED_ACTIONS.get(p, [])

static func allowed_actions(p: int) -> Array:
	var out := []
	for a in ActionType.values():
		if not is_blocked(p, a):
			out.append(a)
	return out

## Motivo para la interfaz ("" si la acción está permitida en esa postura).
static func block_reason(p: int, a: int) -> String:
	if not is_blocked(p, a):
		return ""
	return "En postura %s no puedes %s." % [posture_name(p), action_name(a).to_lower()]

static func posture_name(p: int) -> String:
	match p:
		Posture.OFENSIVA: return "Ofensiva"
		Posture.DEFENSIVA: return "Defensiva"
		Posture.ESGRIMA: return "Esgrima"
		Posture.MURO: return "Muro"
		Posture.DESESPERADA: return "Desesperada"
	return "?"

static func status_name(s: int) -> String:
	match s:
		Status.HERIDO: return "Herido"
		Status.FATIGADO: return "Fatigado"
		Status.DESARMADO: return "Desarmado"
		Status.DESMORALIZADO: return "Desmoralizado"
		Status.INSPIRADO: return "Inspirado"
	return "?"

static func action_name(a: int) -> String:
	match a:
		ActionType.ATACAR: return "Atacar"
		ActionType.DEFENDER: return "Defender"
		ActionType.ESQUIVAR: return "Esquivar"
		ActionType.CONTRAATACAR: return "Contraatacar"
		ActionType.DESARMAR: return "Desarmar"
		ActionType.EMPUJAR: return "Empujar"
		ActionType.RENDIRSE: return "Rendirse"
		ActionType.RETIRARSE: return "Retirarse"
		ActionType.FINTA: return "Finta"
	return "?"
