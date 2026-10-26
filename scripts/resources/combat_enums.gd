class_name CombatEnums

enum Posture { OFENSIVA, DEFENSIVA, ESGRIMA, MURO, DESESPERADA }
enum ActionType { ATACAR, DEFENDER, ESQUIVAR, CONTRAATACAR, DESARMAR, EMPUJAR, RENDIRSE, RETIRARSE }
enum Status { HERIDO, FATIGADO, DESARMADO, DESMORALIZADO, INSPIRADO }

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
	return "?"
