extends Node
# Autoload — registrar en Project Settings > Autoload como "GameData"

var general_skills: Array[Skill] = []
var combat_skills: Array[Skill] = []
var battle_skills: Array[Skill] = []
var advantages: Array[CharacterTrait] = []
var disadvantages: Array[CharacterTrait] = []
var equipment_catalog: Array[Equipment] = []

# Puntos base que aporta cada elección al pool de estadísticas
const BASE_STAT_VALUE := 5
const FREE_POINTS := 10

const PERSONALITY_STAT_MODS := {
	Character.Personality.AMBICIOSO: {"leadership": 2, "charisma": 1},
	Character.Personality.LEAL: {"defense": 2, "leadership": 1},
	Character.Personality.PRUDENTE: {"strategy": 2, "defense": 1},
	Character.Personality.ARROGANTE: {"combat": 2, "leadership": 1},
	Character.Personality.PIADOSO: {"charisma": 2, "defense": 1},
	Character.Personality.ASTUTO: {"strategy": 2, "charisma": 1},
}

const ALIGNMENT_STAT_MODS := {
	CharacterEnums.Alignment.CONQUISTADOR: {"combat": 2, "leadership": 1},
	CharacterEnums.Alignment.PACIFISTA: {"charisma": 2, "defense": 1},
	CharacterEnums.Alignment.AMBICIOSO: {"leadership": 2, "strategy": 1},
	CharacterEnums.Alignment.HUMILDE: {"defense": 2, "charisma": 1},
	CharacterEnums.Alignment.DIPLOMATICO: {"charisma": 2, "strategy": 1},
	CharacterEnums.Alignment.TIRANO: {"leadership": 2, "combat": 1},
}

const FIGHTER_TYPE_STAT_MODS := {
	CharacterEnums.FighterType.DUELISTA: {"combat": 2, "defense": 1},
	CharacterEnums.FighterType.TANQUE: {"defense": 2, "combat": 1},
	CharacterEnums.FighterType.ESTRATEGA: {"strategy": 2, "leadership": 1},
	CharacterEnums.FighterType.BERSERKER: {"combat": 3},
	CharacterEnums.FighterType.DEFENSOR: {"defense": 3},
	CharacterEnums.FighterType.ASESINO: {"combat": 2, "strategy": 1},
}

func get_base_stats(personality: int, alignment: int, fighter_type: int) -> Dictionary:
	var stats := {
		"leadership": BASE_STAT_VALUE,
		"charisma": BASE_STAT_VALUE,
		"strategy": BASE_STAT_VALUE,
		"combat": BASE_STAT_VALUE,
		"defense": BASE_STAT_VALUE,
	}
	_add_mods(stats, PERSONALITY_STAT_MODS.get(personality, {}))
	_add_mods(stats, ALIGNMENT_STAT_MODS.get(alignment, {}))
	_add_mods(stats, FIGHTER_TYPE_STAT_MODS.get(fighter_type, {}))
	return stats

func _add_mods(stats: Dictionary, mods: Dictionary) -> void:
	for key in mods.keys():
		stats[key] = stats.get(key, 0) + mods[key]
		
func _make_skill(n: String, d: String, cat: int) -> Skill:
	var s := Skill.new()
	s.skill_name = n
	s.description = d
	s.category = cat
	return s

func _load_general_skills() -> void:
	general_skills = [
		_make_skill("Paso Invernal", "Tus ejércitos marchan en 1 turno también en invierno (dic–feb), cuando los demás tardan 2.", CharacterEnums.SkillCategory.GENERAL),
		_make_skill("Reclutador Nato", "La milicia cuesta un tercio menos y suma un 50% más de soldados; movilizas un 10% más de la guarnición.", CharacterEnums.SkillCategory.GENERAL),
		_make_skill("Administrador", "+25% de oro en impuestos, gobierno, impuestos reales y el edicto de impuestos.", CharacterEnums.SkillCategory.GENERAL),
		_make_skill("Viajero", "Tus ejércitos pueden marchar a castillos a 2 saltos de distancia en un solo turno.", CharacterEnums.SkillCategory.GENERAL),
	]

func _load_combat_skills() -> void:
	combat_skills = [
		_make_skill("Desarme Fulminante", "Al desarmar al enemigo, aprovechas para golpearlo de inmediato (turno extra).", CharacterEnums.SkillCategory.COMBATE),
		_make_skill("Piel de Hierro", "Recibes un 30% menos de daño mientras estás herido (vida bajo el 30%).", CharacterEnums.SkillCategory.COMBATE),
		_make_skill("Golpe Certero", "20% de probabilidad de golpe crítico (×1.5 de daño), frente al 5% normal.", CharacterEnums.SkillCategory.COMBATE),
	]

func _load_battle_skills() -> void:
	battle_skills = [
		_make_skill("Grito de Guerra", "Tus pelotones empiezan la batalla con +15 de moral.", CharacterEnums.SkillCategory.BATALLA),
		_make_skill("Táctica Defensiva", "Tus pelotones en colina o muralla reciben un 20% menos de daño.", CharacterEnums.SkillCategory.BATALLA),
		_make_skill("Carga Letal", "Tu caballería causa un 25% más de daño.", CharacterEnums.SkillCategory.BATALLA),
	]

func _make_trait(n: String, d: String, is_adv: bool, mods: Dictionary) -> CharacterTrait:
	var t := CharacterTrait.new()
	t.trait_name = n
	t.description = d
	t.is_advantage = is_adv
	t.leadership_mod = mods.get("leadership", 0)
	t.charisma_mod = mods.get("charisma", 0)
	t.strategy_mod = mods.get("strategy", 0)
	t.combat_mod = mods.get("combat", 0)
	t.defense_mod = mods.get("defense", 0)
	return t

func _load_advantages() -> void:
	advantages = [
		_make_trait("Sangre Noble", "Naciste con ventaja social.", true, {"charisma": 2}),
		_make_trait("Veterano de Guerra", "Años de batalla te curtieron.", true, {"combat": 2}),
		_make_trait("Mente Fría", "Piensas con claridad bajo presión.", true, {"strategy": 2}),
		_make_trait("Presencia Imponente", "Inspiras respeto al instante.", true, {"leadership": 2}),
		_make_trait("Reflejos de Acero", "Reaccionas antes que la mayoría.", true, {"defense": 2}),
	]

func _load_disadvantages() -> void:
	disadvantages = [
		_make_trait("Temperamento Volátil", "Te cuesta controlar la ira.", false, {"charisma": -2}),
		_make_trait("Cuerpo Frágil", "Más vulnerable en combate.", false, {"defense": -2}),
		_make_trait("Ingenuo", "Fácil de engañar en negociaciones.", false, {"strategy": -2}),
		_make_trait("Mal Líder", "Cuesta que tus tropas te sigan con convicción.", false, {"leadership": -2}),
		_make_trait("Torpe en Combate", "Menos preciso al luchar.", false, {"combat": -2}),
	]

func _make_equipment(n: String, d: String, mods: Dictionary) -> Equipment:
	var e := Equipment.new()
	e.equipment_name = n
	e.description = d
	e.combat_mod = mods.get("combat", 0)
	e.defense_mod = mods.get("defense", 0)
	e.leadership_mod = mods.get("leadership", 0)
	e.charisma_mod = mods.get("charisma", 0)
	e.strategy_mod = mods.get("strategy", 0)
	return e

func _load_equipment() -> void:
	equipment_catalog = [
		_make_equipment("Espada Larga", "Arma equilibrada, favorece el ataque.", {"combat": 3}),
		_make_equipment("Armadura Completa", "Protección superior a costa de movilidad.", {"defense": 3}),
		_make_equipment("Sello Familiar", "Un símbolo de linaje que abre puertas.", {"charisma": 2, "leadership": 1}),
		_make_equipment("Mapa Táctico", "Herramienta de planificación militar.", {"strategy": 3}),
		_make_equipment("Capa de Viajero", "Ligera, favorece la agilidad en duelo.", {"defense": 1, "combat": 1}),
	]
	
func _ready() -> void:
	_load_general_skills()
	_load_combat_skills()
	_load_battle_skills()
	_load_advantages()
	_load_disadvantages()
	_load_equipment()
