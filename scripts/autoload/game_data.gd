extends Node
# Autoload — registrar en Project Settings > Autoload como "GameData"
# Los catálogos se construyen a partir de ContentCatalog (datos) — para añadir contenido, edita ese archivo.

const ContentCatalog = preload("res://scripts/resources/content_catalog.gd")
const MAX_EQUIPMENT := 3   # piezas de equipo (una por ranura)

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
	Character.Personality.VALIENTE: {"combat": 2, "leadership": 1},
	Character.Personality.CRUEL: {"combat": 2, "strategy": 1},
	Character.Personality.GENEROSO: {"charisma": 2, "leadership": 1},
	Character.Personality.COBARDE: {"defense": 2, "strategy": 1},
	Character.Personality.ROMANTICO: {"charisma": 2, "combat": 1},
	Character.Personality.HONORABLE: {"defense": 2, "leadership": 1},
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

func _skills_from(data: Array, cat: int) -> Array[Skill]:
	var out: Array[Skill] = []
	for e: Dictionary in data:
		out.append(_make_skill(e.name, e.desc, cat))
	return out

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

func _traits_from(data: Array, is_adv: bool) -> Array[CharacterTrait]:
	var out: Array[CharacterTrait] = []
	for e: Dictionary in data:
		out.append(_make_trait(e.name, e.desc, is_adv, e.get("mods", {})))
	return out

func _make_equipment(e: Dictionary) -> Equipment:
	var item := Equipment.new()
	var mods: Dictionary = e.get("mods", {})
	item.equipment_name = e.name
	item.description = e.desc
	item.slot = e.get("slot", ContentCatalog.SLOT_ACCESORIO)
	item.tier = e.get("tier", 1)
	item.price = e.get("price", 0)
	item.combat_mod = mods.get("combat", 0)
	item.defense_mod = mods.get("defense", 0)
	item.leadership_mod = mods.get("leadership", 0)
	item.charisma_mod = mods.get("charisma", 0)
	item.strategy_mod = mods.get("strategy", 0)
	return item

## Texto breve con lo que hace una entrada del catálogo (para listas y tooltips).
func effect_summary(entry_name: String) -> String:
	for list in [ContentCatalog.GENERAL_SKILLS, ContentCatalog.COMBAT_SKILLS, ContentCatalog.BATTLE_SKILLS,
			ContentCatalog.ADVANTAGES, ContentCatalog.DISADVANTAGES, ContentCatalog.EQUIPMENT]:
		for e: Dictionary in list:
			if e.name == entry_name:
				var parts: Array[String] = []
				var mods: Dictionary = e.get("mods", {})
				for k in mods:
					parts.append("%s %+d" % [STAT_LABELS.get(k, k), mods[k]])
				if e.has("slot"):
					return "%s · %s" % [e.slot, ", ".join(parts)] if not parts.is_empty() else e.slot
				return ", ".join(parts)
	return ""

const STAT_LABELS := {"leadership": "Liderazgo", "charisma": "Carisma", "strategy": "Estrategia", "combat": "Combate", "defense": "Defensa"}

func _ready() -> void:
	general_skills = _skills_from(ContentCatalog.GENERAL_SKILLS, CharacterEnums.SkillCategory.GENERAL)
	combat_skills = _skills_from(ContentCatalog.COMBAT_SKILLS, CharacterEnums.SkillCategory.COMBATE)
	battle_skills = _skills_from(ContentCatalog.BATTLE_SKILLS, CharacterEnums.SkillCategory.BATALLA)
	advantages = _traits_from(ContentCatalog.ADVANTAGES, true)
	disadvantages = _traits_from(ContentCatalog.DISADVANTAGES, false)
	equipment_catalog.clear()
	for e: Dictionary in ContentCatalog.EQUIPMENT:
		equipment_catalog.append(_make_equipment(e))
