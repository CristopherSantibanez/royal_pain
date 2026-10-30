class_name RpgStats
extends RefCounted
# Estadísticas del combate RPG, derivadas de los 5 atributos (Liderazgo, Carisma, Estrategia,
# Combate, Defensa) + nivel + equipo + tipo de luchador + pasivas del árbol (SkillTreeCatalog).
# Los atributos ya incluyen los bonos del equipo (Character.apply_trait_and_equipment_modifiers).
#
# Fórmulas (L = nivel - 1; luego se multiplica/suma según el tipo de luchador, TYPE_MODS):
#   PV       = (50 + 3·Defensa + 1·Combate + 6·L) × tipo.pv × (1 + pasivas pv_pct)
#   PT       = (20 + 2·Estrategia + 1·Liderazgo + 2·L) × tipo.pt × (1 + pasivas pt_pct)
#   Fuerza   = (5 + 1,5·Combate + 1·L) × tipo.fuerza × (1 + dmg del equipo/ventajas + fuerza_pct)
#   Defensa  = (3 + 1·Defensa + 0,6·L) × tipo.defensa + armadura (ARMOR_DEF) + escudo (SHIELD_DEF)
#   Agilidad = 6 + 0,4·Combate + 0,4·Estrategia + 0,3·L + armadura (ARMOR_AGI) + tipo.agilidad
#   Puntería = 6 + 0,5·Combate + 0,5·Estrategia + 0,4·L + tipo.punteria
#   Voluntad = 6 + 0,6·Liderazgo + 0,4·Carisma + 0,4·L + tipo.voluntad
# Agilidad: orden de turno (línea de turnos) y esquiva. Puntería: acierto y crítico.
# Voluntad: moral inicial y resistencia a estados.

enum DamageType { TAJO, ESTOCADA, CONTUNDENTE, PROYECTIL }
enum ArmorClass { SIN, CUERO, MALLA, PLACAS }
enum Affinity { NORMAL, DEBIL, RESISTE }

const DAMAGE_NAMES := ["Tajo", "Estocada", "Contundente", "Proyectil"]
const ARMOR_NAMES := ["Sin armadura", "Cuero", "Malla", "Placas"]

# Tabla fija de debilidades (fila: tipo de daño; columna: clase de armadura).
const W := Affinity.DEBIL
const R := Affinity.RESISTE
const N := Affinity.NORMAL
const AFFINITY := [
	[W, N, R, R],   # Tajo
	[N, W, W, R],   # Estocada
	[N, N, N, W],   # Contundente
	[W, N, R, R],   # Proyectil
]
const WEAK_MULT := 1.5
const RESIST_MULT := 0.5

# --- Curvas ---
const PV_BASE := 50.0
const PV_PER_DEFENSE := 3.0
const PV_PER_COMBAT := 1.0
const PV_PER_LEVEL := 6.0
const PT_BASE := 20.0
const PT_PER_STRATEGY := 2.0
const PT_PER_LEADERSHIP := 1.0
const PT_PER_LEVEL := 2.0
const STR_BASE := 5.0
const STR_PER_COMBAT := 1.5
const STR_PER_LEVEL := 1.0
const DEF_BASE := 3.0
const DEF_PER_DEFENSE := 1.0
const DEF_PER_LEVEL := 0.6
const AGI_BASE := 12.0
const AGI_PER_ATTR := 0.4      # Combate y Estrategia
const AGI_PER_LEVEL := 0.3
const AIM_BASE := 10.0
const AIM_PER_ATTR := 0.5      # Combate y Estrategia
const AIM_PER_LEVEL := 0.4
const WILL_BASE := 6.0
const WILL_PER_LEADERSHIP := 0.6
const WILL_PER_CHARISMA := 0.4
const WILL_PER_LEVEL := 0.4

# Armadura: defensa extra y agilidad perdida por el peso.
const ARMOR_DEF := [0, 2, 4, 7]
const ARMOR_AGI := [1, 0, -1, -3]
const SHIELD_DEF_BY_TIER := {1: 1, 2: 2, 3: 3, 4: 3}

# Tipo de luchador: multiplicadores (pv, pt, fuerza, defensa) y sumas (agilidad, punteria, voluntad).
const F := CharacterEnums.FighterType
const TYPE_MODS := {
	F.DUELISTA:  {"pv": 1.0,  "pt": 1.0,  "fuerza": 1.0 , "defensa": 1.0,  "agilidad": 1,  "punteria": 2, "voluntad": 0},
	F.TANQUE:    {"pv": 1.3,  "pt": 0.9,  "fuerza": 0.9,  "defensa": 1.3, "agilidad": -2, "punteria": 0, "voluntad": 2},
	F.ESTRATEGA: {"pv": 1.1,  "pt": 1.35, "fuerza": 1.1,  "defensa": 1.0,  "agilidad": 1,  "punteria": 2, "voluntad": 3},
	F.BERSERKER: {"pv": 1.2,  "pt": 0.9,  "fuerza": 1.35, "defensa": 0.85, "agilidad": 0,  "punteria": 0, "voluntad": 1},
	F.DEFENSOR:  {"pv": 1.15, "pt": 1.15, "fuerza": 0.9,  "defensa": 1.15, "agilidad": -1, "punteria": 0, "voluntad": 3},
	F.ASESINO:   {"pv": 0.85, "pt": 1.0,  "fuerza": 1.1,  "defensa": 0.9,  "agilidad": 2,  "punteria": 3, "voluntad": 0},
}

# Equipo actual → clase de armadura y tipo de daño (por nombre, para las partidas guardadas).
const ARMOR_BY_ITEM := {
	"Gambesón": ArmorClass.CUERO, "Cuero Endurecido": ArmorClass.CUERO,
	"Cota de Malla": ArmorClass.MALLA, "Brigantina": ArmorClass.MALLA, "Loriga de Covadonga": ArmorClass.MALLA,
	"Armadura Completa": ArmorClass.PLACAS,
}
const WEAPON_BY_ITEM := {
	"Espada Corta": DamageType.TAJO, "Espada Larga": DamageType.TAJO, "Mandoble": DamageType.TAJO,
	"Hacha de Guerra": DamageType.TAJO, "Hacha de Berserker": DamageType.TAJO, "Durandal": DamageType.TAJO,
	"Lanza": DamageType.ESTOCADA, "Estoque": DamageType.ESTOCADA, "Estoque de Duelo": DamageType.ESTOCADA,
	"Daga de Misericordia": DamageType.ESTOCADA, "Misericordia de Toledo": DamageType.ESTOCADA,
	"Pica de Fresno": DamageType.ESTOCADA,
	"Maza de Armas": DamageType.CONTUNDENTE,
	"Arco Largo": DamageType.PROYECTIL, "Ballesta de Cranequín": DamageType.PROYECTIL,
}
# Sin pieza de armadura: según el rol social.
const ARMOR_BY_ROLE := {
	Character.Role.CAMPESINO: ArmorClass.SIN, Character.Role.INAFILIADO: ArmorClass.CUERO,
	Character.Role.SOLDADO: ArmorClass.CUERO, Character.Role.MERCENARIO: ArmorClass.CUERO,
	Character.Role.CABALLERO: ArmorClass.MALLA, Character.Role.CAPITAN: ArmorClass.MALLA,
	Character.Role.NOBLEZA_BAJA: ArmorClass.MALLA, Character.Role.CONDOTIERO: ArmorClass.MALLA,
	Character.Role.NOBLEZA_ALTA: ArmorClass.PLACAS, Character.Role.DUQUE: ArmorClass.PLACAS,
	Character.Role.REGENTE: ArmorClass.PLACAS,
}
# Sin arma: según el tipo de luchador.
const WEAPON_BY_TYPE := {
	F.DUELISTA: DamageType.ESTOCADA, F.TANQUE: DamageType.CONTUNDENTE, F.ESTRATEGA: DamageType.TAJO,
	F.BERSERKER: DamageType.TAJO, F.DEFENSOR: DamageType.CONTUNDENTE, F.ASESINO: DamageType.ESTOCADA,
}
# Metadatos que fijan la clase/arma sin equipo (enemigos genéricos).
const META_ARMOR := "rpg_armor"
const META_DAMAGE := "rpg_damage"
const META_ACTIONS := "rpg_actions"     # acciones por turno (mini jefes: 2)
const META_PV_MULT := "rpg_pv_mult"

# Bonos del equipo/ventajas ya existentes (SkillEffects.fx) que el RPG aprovecha.
const LEGACY_FX_CRIT := "crit"
const LEGACY_FX_DMG := "dmg"
const LEGACY_FX_DODGE := "dodge"
const LEGACY_FX_TAKEN := "dmg_taken"
const LEGACY_INITIATIVE_TO_AGI := 10.0   # +0,15 de iniciativa → +1,5 de agilidad

static func armor_class(c: Character) -> int:
	if c.has_meta(META_ARMOR):
		return int(c.get_meta(META_ARMOR))
	for e: Equipment in c.equipment:
		if ARMOR_BY_ITEM.has(e.equipment_name):
			return ARMOR_BY_ITEM[e.equipment_name]
	return ARMOR_BY_ROLE.get(c.role, ArmorClass.CUERO)

static func weapon_type(c: Character) -> int:
	if c.has_meta(META_DAMAGE):
		return int(c.get_meta(META_DAMAGE))
	for e: Equipment in c.equipment:
		if WEAPON_BY_ITEM.has(e.equipment_name):
			return WEAPON_BY_ITEM[e.equipment_name]
	return WEAPON_BY_TYPE.get(c.fighter_type, DamageType.TAJO)

static func shield(c: Character) -> Equipment:
	for e: Equipment in c.equipment:
		if e.slot == "Escudo":
			return e
	return null

## Afinidad de un tipo de daño contra una armadura. Un escudo mejora un paso la defensa ante Proyectil.
static func affinity(dmg: int, armor: int, has_shield: bool = false) -> int:
	var a: int = AFFINITY[dmg][armor]
	if has_shield and dmg == DamageType.PROYECTIL:
		a = Affinity.NORMAL if a == Affinity.DEBIL else Affinity.RESISTE
	return a

static func affinity_mult(a: int) -> float:
	return WEAK_MULT if a == Affinity.DEBIL else (RESIST_MULT if a == Affinity.RESISTE else 1.0)

## Efectos del equipo y de ventajas/desventajas. Las habilidades de combate antiguas NO cuentan aquí:
## se convierten en nodos del árbol (SkillTreeCatalog.LEGACY_SKILL_NODES) para no sumarlas dos veces.
static func _fx(c: Character, key: String) -> float:
	var table := SkillEffects._fx_table()
	var total := 0.0
	for list in [c.advantages, c.disadvantages]:
		for t: CharacterTrait in list:
			if t != null:
				total += table.get(t.trait_name, {}).get(key, 0.0)
	for e: Equipment in c.equipment:
		if e != null:
			total += table.get(e.equipment_name, {}).get(key, 0.0)
	return total

## Todas las estadísticas de combate del personaje (sin estados temporales).
static func compute(c: Character) -> Dictionary:
	var t: Dictionary = TYPE_MODS.get(c.fighter_type, TYPE_MODS[F.DUELISTA])
	var p: Dictionary = SkillTreeCatalog.passive_fx(c)
	var lv := float(c.level - 1)
	var armor := armor_class(c)
	var sh := shield(c)
	var pv: float = (PV_BASE + PV_PER_DEFENSE * c.defense + PV_PER_COMBAT * c.combat + PV_PER_LEVEL * lv) * t.pv
	pv *= (1.0 + p.get("pv_pct", 0.0)) * float(c.get_meta(META_PV_MULT, 1.0))
	var pt: float = (PT_BASE + PT_PER_STRATEGY * c.strategy + PT_PER_LEADERSHIP * c.leadership + PT_PER_LEVEL * lv) * t.pt
	pt *= 1.0 + p.get("pt_pct", 0.0)
	var fuerza: float = (STR_BASE + STR_PER_COMBAT * c.combat + STR_PER_LEVEL * lv) * t.fuerza
	fuerza *= 1.0 + _fx(c, LEGACY_FX_DMG) + p.get("fuerza_pct", 0.0)
	var defensa: float = (DEF_BASE + DEF_PER_DEFENSE * c.defense + DEF_PER_LEVEL * lv) * t.defensa
	defensa += ARMOR_DEF[armor] + (SHIELD_DEF_BY_TIER.get(sh.tier, 1) if sh else 0) + p.get("defensa", 0.0)
	var agi: float = AGI_BASE + AGI_PER_ATTR * (c.combat + c.strategy) + AGI_PER_LEVEL * lv + ARMOR_AGI[armor] + t.agilidad
	agi += p.get("agilidad", 0.0) + _fx(c, "initiative") * LEGACY_INITIATIVE_TO_AGI
	var aim: float = AIM_BASE + AIM_PER_ATTR * (c.combat + c.strategy) + AIM_PER_LEVEL * lv + t.punteria + p.get("punteria", 0.0)
	var will: float = WILL_BASE + WILL_PER_LEADERSHIP * c.leadership + WILL_PER_CHARISMA * c.charisma + WILL_PER_LEVEL * lv
	will += t.voluntad + p.get("voluntad", 0.0)
	return {
		"pv": maxi(1, roundi(pv)), "pt": maxi(0, roundi(pt)),
		"fuerza": maxf(1.0, fuerza), "defensa": maxf(0.0, defensa),
		"agilidad": maxf(1.0, agi), "punteria": aim, "voluntad": will,
		"armor": armor, "weapon": weapon_type(c), "shield": sh != null,
		"crit": _fx(c, LEGACY_FX_CRIT) + p.get("crit", 0.0),
		"crit_mult": _fx(c, "crit_mult") + p.get("crit_mult", 0.0),
		"evasion": _fx(c, LEGACY_FX_DODGE) + p.get("evasion", 0.0),
		"taken": _fx(c, LEGACY_FX_TAKEN) + p.get("taken", 0.0),
		"actions": int(c.get_meta(META_ACTIONS, 1)),
		"fx": p,
	}
