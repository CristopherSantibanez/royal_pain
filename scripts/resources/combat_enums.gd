class_name CombatEnums

enum Posture { OFENSIVA, DEFENSIVA, ESGRIMA, MURO, DESESPERADA }   # MURO: obsoleta, se trata como DEFENSIVA
enum ActionType { ATACAR, DEFENDER, ESQUIVAR, CONTRAATACAR, DESARMAR, EMPUJAR, RENDIRSE, RETIRARSE, FINTA }   # las nuevas, siempre al final
# DEFENDER es la «Guardia» (reduce el golpe y a veces lo evita); ESQUIVAR quedó obsoleta y se trata como Guardia.

## Posturas y acciones que se muestran (las obsoletas se conservan para partidas y pruebas antiguas).
const POSTURES_SHOWN := [Posture.OFENSIVA, Posture.DEFENSIVA, Posture.ESGRIMA, Posture.DESESPERADA]
const ACTIONS_SHOWN := [ActionType.ATACAR, ActionType.DEFENDER, ActionType.CONTRAATACAR, ActionType.FINTA,
	ActionType.DESARMAR, ActionType.EMPUJAR, ActionType.RENDIRSE, ActionType.RETIRARSE]

static func canon_posture(p: int) -> int:
	return Posture.DEFENSIVA if p == Posture.MURO else p

static func canon_action(a: int) -> int:
	return ActionType.DEFENDER if a == ActionType.ESQUIVAR else a
enum Status { HERIDO, FATIGADO, DESARMADO, DESMORALIZADO, INSPIRADO }

# Cada postura compromete: cierra las acciones que no le cuadran. Rendirse y Retirarse siempre se pueden.
# Desesperada solo deja golpear y empujar (ni guardia ni engaños).
const BLOCKED_ACTIONS := {
	Posture.OFENSIVA: [ActionType.DEFENDER, ActionType.ESQUIVAR],
	Posture.DEFENSIVA: [ActionType.EMPUJAR],
	Posture.ESGRIMA: [ActionType.EMPUJAR],
	Posture.MURO: [ActionType.EMPUJAR],   # obsoleta: igual que Defensiva
	Posture.DESESPERADA: [ActionType.DEFENDER, ActionType.ESQUIVAR, ActionType.DESARMAR, ActionType.CONTRAATACAR, ActionType.FINTA],
}

static func is_blocked(p: int, a: int) -> bool:
	return canon_action(a) in BLOCKED_ACTIONS.get(canon_posture(p), [])

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
		Posture.MURO: return "Defensiva"
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
		ActionType.DEFENDER: return "Guardia"
		ActionType.ESQUIVAR: return "Guardia"
		ActionType.CONTRAATACAR: return "Contraatacar"
		ActionType.DESARMAR: return "Desarmar"
		ActionType.EMPUJAR: return "Empujar"
		ActionType.RENDIRSE: return "Rendirse"
		ActionType.RETIRARSE: return "Retirarse"
		ActionType.FINTA: return "Finta"
	return "?"
