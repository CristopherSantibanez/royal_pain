extends RefCounted
# Experiencia que da cada cosa (ver Character.gain_xp). Uso: const XpRules = preload("res://scripts/resources/xp_rules.gd")

const DUEL_WIN := 40
const DUEL_LOSS := 15
const DUEL_RANK_BONUS := 10        # por cada rango que te supere el rival vencido
const TOURNAMENT_ROUND := 25
const TOURNAMENT_CHAMPION := 80
const BATTLE_WIN := 60
const BATTLE_LOSS := 20
const SKIRMISH_WIN := 35
const MISSION_COMPLETE := 50
const EXPLORATION := 30
const EVENT_FIGHT_WIN := 20        # extra por ganar el combate de un evento
const BATTLE_DUEL_WIN := 30        # duelo singular en mitad de una batalla
const BATTLE_DUEL_LOSS := 10
const TRAINING := 30               # «Entrenar» en el castillo (acción directa)
const TRAINING_PER_MONTH := 2      # sesiones de entrenamiento al mes

# Fuentes de experiencia: el tipo de luchador decide cuánto aprovecha cada una.
const SOURCE_DUEL := "duel"
const SOURCE_BATTLE := "battle"
const SOURCE_TRAINING := "training"
const SOURCE_STUDY := "study"
const SOURCE_MISSION := "mission"
const SOURCE_EXPLORATION := "exploration"
const SOURCE_EVENT := "event"

const SOURCE_NAMES := {
	SOURCE_DUEL: "duelos", SOURCE_BATTLE: "batallas", SOURCE_TRAINING: "entrenamiento",
	SOURCE_STUDY: "estudio", SOURCE_MISSION: "encargos", SOURCE_EXPLORATION: "exploración", SOURCE_EVENT: "sucesos",
}

# Multiplicador por tipo de luchador (CharacterEnums.FighterType) y fuente. Lo que falta vale 1.0.
const FIGHTER_MULTIPLIERS := {
	CharacterEnums.FighterType.DUELISTA: {SOURCE_DUEL: 1.3, SOURCE_BATTLE: 0.85, SOURCE_TRAINING: 1.1, SOURCE_STUDY: 0.9},
	CharacterEnums.FighterType.TANQUE: {SOURCE_BATTLE: 1.1, SOURCE_TRAINING: 1.25, SOURCE_STUDY: 0.85},
	CharacterEnums.FighterType.ESTRATEGA: {SOURCE_DUEL: 0.8, SOURCE_BATTLE: 1.3, SOURCE_TRAINING: 0.9, SOURCE_STUDY: 1.35, SOURCE_MISSION: 1.1},
	CharacterEnums.FighterType.BERSERKER: {SOURCE_DUEL: 1.25, SOURCE_BATTLE: 1.1, SOURCE_TRAINING: 0.85, SOURCE_STUDY: 0.75, SOURCE_EXPLORATION: 1.1},
	CharacterEnums.FighterType.DEFENSOR: {SOURCE_BATTLE: 1.2, SOURCE_TRAINING: 1.15, SOURCE_STUDY: 0.9},
	CharacterEnums.FighterType.ASESINO: {SOURCE_DUEL: 1.2, SOURCE_BATTLE: 0.85, SOURCE_MISSION: 1.2, SOURCE_EXPLORATION: 1.2},
}

static func multiplier(fighter_type: int, source: String) -> float:
	if source.is_empty():
		return 1.0
	return FIGHTER_MULTIPLIERS.get(fighter_type, {}).get(source, 1.0)

## Texto para la interfaz: en qué aprende más y menos este tipo de luchador.
static func affinity_text(fighter_type: int) -> String:
	var best: Array[String] = []
	var worst: Array[String] = []
	for source: String in FIGHTER_MULTIPLIERS.get(fighter_type, {}):
		var m: float = FIGHTER_MULTIPLIERS[fighter_type][source]
		(best if m > 1.0 else worst).append("%s ×%.2f" % [SOURCE_NAMES.get(source, source), m])
	var parts: Array[String] = []
	if not best.is_empty():
		parts.append("aprende más en " + ", ".join(best))
	if not worst.is_empty():
		parts.append("menos en " + ", ".join(worst))
	return "; ".join(parts) + "." if not parts.is_empty() else ""
