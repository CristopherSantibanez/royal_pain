class_name Character
extends Resource

## ROLES SOCIALES (los nuevos se añaden SIEMPRE al final: las partidas guardan el número).
## El orden del enum NO es el rango: para comparar rangos usa rank() / Character.rank_of().
enum Role {
	CAMPESINO,
	SOLDADO,
	CABALLERO,
	NOBLEZA_BAJA,
	NOBLEZA_ALTA,
	REGENTE,
	DUQUE,         # entre Nobleza Alta y Regente
	MERCENARIO,    # LEGADO: el camino mercenario ya no existe; se conserva por las partidas guardadas
	CAPITAN,       # LEGADO (ver RoleProgression.migrate_legacy_role)
	CONDOTIERO,    # LEGADO
	INAFILIADO,    # sin tierra ni señor: va donde quiere, vive de jornales y se ofrece en batallas ajenas
}

# Rango social de cada rol (0 = más bajo). Los roles de legado se equiparan a su par de la escalera noble.
const RANK_BY_ROLE := {
	Role.CAMPESINO: 0, Role.SOLDADO: 1, Role.CABALLERO: 2, Role.NOBLEZA_BAJA: 3,
	Role.NOBLEZA_ALTA: 4, Role.DUQUE: 5, Role.REGENTE: 6,
	Role.MERCENARIO: 1, Role.CAPITAN: 2, Role.CONDOTIERO: 3,
	Role.INAFILIADO: 0,
}
# Roles retirados: sólo aparecen en partidas antiguas y se migran al cargar.
const LEGACY_ROLES := [Role.MERCENARIO, Role.CAPITAN, Role.CONDOTIERO]
# Rol de la escalera noble al que equivale cada uno (para eventos y contenidos pensados por rango).
const LADDER_EQUIVALENT := {
	Role.DUQUE: Role.NOBLEZA_ALTA, Role.MERCENARIO: Role.SOLDADO,
	Role.CAPITAN: Role.CABALLERO, Role.CONDOTIERO: Role.NOBLEZA_BAJA,
	Role.INAFILIADO: Role.CAMPESINO,
}

## PERSONALIDADES (las nuevas se añaden SIEMPRE al final: las partidas guardan el número)
enum Personality {
	AMBICIOSO,
	LEAL,
	PRUDENTE,
	ARROGANTE,
	PIADOSO,
	ASTUTO,
	VALIENTE,
	CRUEL,
	GENEROSO,
	COBARDE,
	ROMANTICO,
	HONORABLE,
}

@export_group("Identidad")
@export var first_name: String = "Sin nombre"
@export var last_name: String = ""
@export var gender: CharacterEnums.Gender = CharacterEnums.Gender.MASCULINO
@export var portrait: Texture2D   # retrato específico elegido manualmente, tiene prioridad sobre el selector por sexo/rol
@export var biography: String = ""
@export var role: Role = Role.CAMPESINO
@export var personality: Personality = Personality.LEAL
@export var alignment: CharacterEnums.Alignment = CharacterEnums.Alignment.AMBICIOSO
@export var fighter_type: CharacterEnums.FighterType = CharacterEnums.FighterType.DUELISTA

@export_group("Estadísticas base")
@export_range(1, 20) var leadership: int = 5
@export_range(1, 20) var charisma: int = 5
@export_range(1, 20) var strategy: int = 5
@export_range(1, 20) var combat: int = 5
@export_range(1, 20) var defense: int = 5
## Agilidad: orden de turno y esquiva en el combate RPG. 0 = sin dato (partidas antiguas):
## se deriva de Combate y Estrategia hasta que se le asigne un valor.
@export_range(0, 20) var agility: int = 0:
	get:
		if agility <= 0:
			return clampi(roundi((combat + strategy) / 2.0), 1, 20)
		return agility

## Los seis atributos (clave de propiedad), en el orden en que se muestran.
const ATTRIBUTES := ["leadership", "charisma", "strategy", "combat", "defense", "agility"]

@export_group("Recursos de combate")
@export var max_health: int = 100
@export var current_health: int = 100
@export var max_stamina: int = 100
@export var current_stamina: int = 100
@export var max_morale: int = 100
@export var current_morale: int = 100
@export var honor: int = 50
@export_range(1, 20) var level: int = 1         # nivel de experiencia (ver gain_xp)
@export var xp: int = 0                          # experiencia acumulada hacia el siguiente nivel
@export var unspent_points: int = 0              # puntos de atributo por repartir al subir de nivel
@export var pending_skill_choices: int = 0       # LEGADO: las habilidades ahora se aprenden en los árboles (SkillTreeCatalog)
@export var age: int = 20                        # años; cada enero se cumple uno más (ver DynastyData)
@export_range(0, 100) var fame: int = 0   # reconocimiento: duelos, torneos y hazañas; atrae eventos y seguidores
@export var wound_months: int = 0   # meses que faltan para curar una herida grave (no puede batirse)

@export_group("Progresión Social")
@export var gold: int = 100
@export var duels_won: int = 0
@export var duels_lost: int = 0
@export var rent: int = 0                    # oro que le rinden cada mes las tierras mejoradas
@export var last_training_month: int = -1    # mes (GameManager.months_elapsed) del último entrenamiento
@export var training_sessions_month: int = 0  # sesiones de entrenamiento hechas ese mes (tope: XpRules.TRAINING_PER_MONTH)
@export var last_command_month: int = -1     # último mes en que una batalla ganada le dio Liderazgo

@export_group("Comandancia")
@export var mastery_xp: Dictionary = {}      # familia de tropa (BattleEnums.Family) -> experiencia de mando acumulada
@export var assigned_family: int = -1        # tropa que le asignó el Consejo de guerra (-1: la decide el general)
@export var troop_drill_log: Dictionary = {} # "entrenar"/"estudiar" -> [mes (months_elapsed), veces ese mes]

@export_group("Habilidades")
@export var general_skills: Array[Skill] = []
@export var combat_skills: Array[Skill] = []
@export var battle_skills: Array[Skill] = []
@export var learned_skills: Array[String] = []   # nodos del árbol del combate RPG (SkillTreeCatalog)

@export_group("Ventajas y Desventajas")
@export var advantages: Array[CharacterTrait] = []      # máximo MAX_ADVANTAGES (se eligen al crear)
@export var disadvantages: Array[CharacterTrait] = []   # mínimo MIN_DISADVANTAGES (se eligen al crear)
## Los rasgos se fijan al crear el personaje: durante la partida no se ganan ni se pierden.
@export var traits_locked: bool = true

@export_group("Equipamiento")
@export var equipment: Array[Equipment] = []   # máximo 2, validado en la UI de creación

# --- Nombre completo ---

func full_name() -> String:
	if last_name.is_empty():
		return first_name
	return "%s %s" % [first_name, last_name]

# --- Portrait con fallback: propio > rol+sexo > default ---

func get_portrait() -> Texture2D:
	# 1. Retrato específico elegido por el jugador
	if portrait != null:
		return portrait

	# 2. Placeholder específico por rol + sexo (cuando tengas esos assets)
	var gender_folder := "male" if gender == CharacterEnums.Gender.MASCULINO else "female"
	var role_path := "res://assets/portraits/roles/%s/%s.png" % [gender_folder, _role_file_name()]
	if ResourceLoader.exists(role_path):
		return load(role_path)

	# 3. Placeholder genérico por sexo (lo que acabas de agregar)
	var gender_placeholder := "res://assets/portraits/placeholder_%s.png" % gender_folder
	if ResourceLoader.exists(gender_placeholder):
		return load(gender_placeholder)

	# 4. Último recurso: placeholder totalmente genérico
	var default_path := "res://assets/portraits/placeholder_default.png"
	if ResourceLoader.exists(default_path):
		return load(default_path)

	return null

const FaceRects = preload("res://scripts/resources/face_rects.gd")
const FaceDetector = preload("res://scripts/resources/face_detector.gd")
static var _face_cache := {}   # ruta del retrato -> AtlasTexture con la cara

## Solo la cara del retrato (recorte calculado por tools/build_face_rects.py).
## Se usa en listas, el mapa y la batalla; el retrato completo queda para la ficha.
func get_face() -> Texture2D:
	var tex := get_portrait()
	if tex == null:
		return null
	var path := tex.resource_path
	if _face_cache.has(path):
		return _face_cache[path]
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	var r: Array = FaceRects.RECTS.get(path, [])
	if r.size() != 3:
		r = FaceDetector.face_rect(tex)   # retrato nuevo: se calcula una vez y se guarda
	if r.size() == 3:
		atlas.region = Rect2(r[0], r[1], r[2], r[2])
	else:
		# No se pudo calcular (imagen sin transparencia, por ejemplo): franja superior centrada.
		var side := tex.get_width() * 0.4
		atlas.region = Rect2(tex.get_width() * 0.3, tex.get_height() * 0.03, side, side)
	if not path.is_empty():
		_face_cache[path] = atlas
	return atlas

func _role_file_name() -> String:
	match role:
		Role.DUQUE: return "nobleza_alta"
		Role.MERCENARIO: return "soldado"
		Role.INAFILIADO: return "campesino"
		Role.CAPITAN, Role.CONDOTIERO: return "caballero"
		Role.CAMPESINO: return "campesino"
		Role.SOLDADO: return "soldado"
		Role.CABALLERO: return "caballero"
		Role.NOBLEZA_BAJA: return "nobleza_baja"
		Role.NOBLEZA_ALTA: return "nobleza_alta"
		Role.REGENTE: return "regente"
	return "campesino"

func role_name() -> String:
	return Character.role_name_for(role)

static func role_name_for(r: int) -> String:
	match r:
		Role.CAMPESINO: return "Campesino"
		Role.SOLDADO: return "Soldado"
		Role.CABALLERO: return "Caballero"
		Role.NOBLEZA_BAJA: return "Nobleza Baja"
		Role.NOBLEZA_ALTA: return "Nobleza Alta"
		Role.REGENTE: return "Regente"
		Role.DUQUE: return "Duque"
		Role.MERCENARIO: return "Mercenario"
		Role.CAPITAN: return "Capitán de compañía"
		Role.CONDOTIERO: return "Condotiero"
		Role.INAFILIADO: return "No afiliado"
	return "Desconocido"

## Título con el género del personaje (Duquesa, Campesina...).
static func role_title_for(r: int, gender: int) -> String:
	if gender != CharacterEnums.Gender.FEMENINO:
		return Character.role_name_for(r)
	match r:
		Role.CAMPESINO: return "Campesina"
		Role.DUQUE: return "Duquesa"
		Role.MERCENARIO: return "Mercenaria"
		Role.CAPITAN: return "Capitana de compañía"
		Role.CONDOTIERO: return "Condotiera"
		Role.INAFILIADO: return "No afiliada"
	return Character.role_name_for(r)

func role_title() -> String:
	return Character.role_title_for(role, gender)

static func ladder_role_of(r: int) -> int:
	return LADDER_EQUIVALENT.get(r, r)

func ladder_role() -> int:
	return Character.ladder_role_of(role)

static func rank_of(r: int) -> int:
	return RANK_BY_ROLE.get(r, 0)

func rank() -> int:
	return Character.rank_of(role)

static func is_legacy_role(r: int) -> bool:
	return r in LEGACY_ROLES

# --- Modificadores de traits + equipamiento ---
# Suma los bonos de ventajas, desventajas y equipo por ENCIMA de las stats base
# (las stats base ya deberían incluir personalidad/alineación/tipo + puntos libres repartidos).

func apply_trait_and_equipment_modifiers() -> void:
	var l := 0
	var c := 0
	var s := 0
	var cb := 0
	var d := 0
	var a := 0

	for t: CharacterTrait in advantages:
		l += t.leadership_mod
		c += t.charisma_mod
		s += t.strategy_mod
		cb += t.combat_mod
		d += t.defense_mod
		a += t.agility_mod

	for t: CharacterTrait in disadvantages:
		l += t.leadership_mod
		c += t.charisma_mod
		s += t.strategy_mod
		cb += t.combat_mod
		d += t.defense_mod
		a += t.agility_mod

	for e: Equipment in equipment:
		l += e.leadership_mod
		c += e.charisma_mod
		s += e.strategy_mod
		cb += e.combat_mod
		d += e.defense_mod
		a += e.agility_mod

	leadership = clampi(leadership + l, 1, 20)
	charisma = clampi(charisma + c, 1, 20)
	strategy = clampi(strategy + s, 1, 20)
	combat = clampi(combat + cb, 1, 20)
	defense = clampi(defense + d, 1, 20)
	agility = clampi(agility + a, 1, 20)
	# Ventajas como Robusto o desventajas como Viejas Heridas cambian la vida máxima.
	max_health = maxi(40, 100 + roundi(SkillEffects.fx(self, "max_health")))
	current_health = max_health

## Se equipa una pieza (tienda, botín): sus bonos se suman a los atributos. Si ya había otra en la
## misma ranura, la quita (restando sus bonos) y la devuelve; si no, devuelve null.
func equip(item: Equipment) -> Equipment:
	var replaced: Equipment = null
	for e: Equipment in equipment:
		if e.slot == item.slot:
			replaced = e
			break
	if replaced != null:
		unequip(replaced)
	equipment.append(item)
	_apply_item_mods(item, 1)
	return replaced

func unequip(item: Equipment) -> void:
	if equipment.has(item):
		equipment.erase(item)
		_apply_item_mods(item, -1)

func _apply_item_mods(item: Equipment, sign: int) -> void:
	leadership = clampi(leadership + item.leadership_mod * sign, 1, 20)
	charisma = clampi(charisma + item.charisma_mod * sign, 1, 20)
	strategy = clampi(strategy + item.strategy_mod * sign, 1, 20)
	combat = clampi(combat + item.combat_mod * sign, 1, 20)
	defense = clampi(defense + item.defense_mod * sign, 1, 20)
	agility = clampi(agility + item.agility_mod * sign, 1, 20)
	var old_max := max_health
	max_health = maxi(40, 100 + roundi(SkillEffects.fx(self, "max_health")))
	current_health = clampi(current_health + max_health - old_max, 1, max_health)

# --- Validación de reglas de creación ---

## Reglas: nombre; como mucho MAX_ADVANTAGES ventajas y al menos MIN_DISADVANTAGES desventajas;
## exactamente un arma, una armadura y un accesorio básicos y, opcionalmente, un escudo básico
## (ContentCatalog.CREATION_*); y una habilidad básica por rama de cada uno de sus tres árboles.
func is_creation_valid() -> Dictionary:
	var errors: Array[String] = []
	if first_name.strip_edges().is_empty():
		errors.append("El nombre no puede estar vacío.")
	if advantages.size() > MAX_ADVANTAGES:
		errors.append("Como mucho %d ventajas (tienes %d)." % [MAX_ADVANTAGES, advantages.size()])
	if disadvantages.size() < MIN_DISADVANTAGES:
		errors.append("Al menos %d desventajas (tienes %d)." % [MIN_DISADVANTAGES, disadvantages.size()])
	errors.append_array(creation_equipment_errors())
	errors.append_array(creation_skill_errors())
	return {"valid": errors.is_empty(), "errors": errors}

const MAX_ADVANTAGES := 2
const MIN_DISADVANTAGES := 2
const MAX_EQUIPMENT := 4   # al crear: arma, armadura, accesorio y (opcional) escudo
const CC = preload("res://scripts/resources/content_catalog.gd")

func creation_equipment_errors() -> Array[String]:
	var errors: Array[String] = []
	var allowed := {
		CC.SLOT_ARMA: CC.CREATION_WEAPONS.values(), CC.SLOT_ESCUDO: CC.CREATION_SHIELDS,
		CC.SLOT_ARMADURA: CC.CREATION_ARMORS.values(), CC.SLOT_ACCESORIO: CC.CREATION_ACCESSORIES.values(),
	}
	var count := {}
	for e: Equipment in equipment:
		if e == null:
			continue
		count[e.slot] = int(count.get(e.slot, 0)) + 1
		if not allowed.has(e.slot) or not (e.equipment_name in allowed[e.slot]):
			errors.append("%s no es equipo inicial." % e.equipment_name)
	for slot in [CC.SLOT_ARMA, CC.SLOT_ARMADURA, CC.SLOT_ACCESORIO]:
		if int(count.get(slot, 0)) != 1:
			errors.append("Elige un(a) %s." % slot.to_lower())
	if int(count.get(CC.SLOT_ESCUDO, 0)) > 1:
		errors.append("Solo un escudo.")
	return errors

## Una habilidad básica por rama de cada árbol (personalidad, alineación y tipo de luchador).
func creation_skill_errors() -> Array[String]:
	var errors: Array[String] = []
	var api: Script = load("res://scripts/resources/skill_tree_catalog.gd")
	if not Character.tree_api_ready(api):
		return errors   # árboles aún sin la API nueva: no se exige
	for tree_id in api.call("trees_for", self):
		var tree: Dictionary = api.call("tree", tree_id)
		var branches: Array = tree.get("branches", [])
		for b in branches.size():
			var basics: Array = api.call("basic_nodes", tree_id, b)
			var picked := basics.filter(func(id): return id in learned_skills).size()
			if picked != 1:
				errors.append("%s · %s: elige una habilidad básica." % [tree.get("name", "?"), branches[b].get("name", "?")])
	return errors

## Opciones básicas de sus tres árboles: [{"tree", "branch", "ids"}] (vacío si la API no está lista).
func basic_tree_options() -> Array:
	var out: Array = []
	var api: Script = load("res://scripts/resources/skill_tree_catalog.gd")
	if not Character.tree_api_ready(api):
		return out
	for tree_id in api.call("trees_for", self):
		var tree: Dictionary = api.call("tree", tree_id)
		var branches: Array = tree.get("branches", [])
		for b in branches.size():
			out.append({"tree": str(tree.get("name", "")), "branch": str(branches[b].get("name", "")),
				"ids": api.call("basic_nodes", tree_id, b)})
	return out

## Elige una habilidad básica de una rama (quita la que hubiera elegida en esa misma rama).
func choose_basic(option: Dictionary, id: String) -> void:
	for other in option.ids:
		learned_skills.erase(other)
	if id.is_empty():
		return
	if Character.tree_api_has("learn"):
		load("res://scripts/resources/skill_tree_catalog.gd").call("learn", self, id)
	if not (id in learned_skills):
		learned_skills.append(id)

## Una básica al azar por rama (PNJ y personaje aleatorio).
func pick_random_basics() -> void:
	for opt: Dictionary in basic_tree_options():
		if not (opt.ids as Array).is_empty():
			choose_basic(opt, str((opt.ids as Array).pick_random()))

static func tree_api_ready(api: Script) -> bool:
	if api == null:
		return false
	var names := {}
	for m in api.get_script_method_list():
		names[m.name] = true
	return names.has("trees_for") and names.has("tree") and names.has("basic_nodes")

static func tree_api_has(fn: String) -> bool:
	var api: Script = load("res://scripts/resources/skill_tree_catalog.gd")
	for m in api.get_script_method_list():
		if m.name == fn:
			return true
	return false

# --- Rasgos: fijos tras la creación ---

## Añade un rasgo solo durante la creación (traits_locked = false). Devuelve si se añadió.
func add_trait(t: CharacterTrait) -> bool:
	if traits_locked or t == null:
		return false
	var list: Array[CharacterTrait] = advantages if t.is_advantage else disadvantages
	if t in list:
		return false
	list.append(t)
	return true

func remove_trait(t: CharacterTrait) -> bool:
	if traits_locked or t == null:
		return false
	var list: Array[CharacterTrait] = advantages if t.is_advantage else disadvantages
	if not (t in list):
		return false
	list.erase(t)
	return true

# --- Utilidades ya existentes ---

func is_alive() -> bool:
	return current_health > 0

func take_damage(amount: int) -> void:
	current_health = max(0, current_health - amount)

func can_fight_duels() -> bool:
	return role != Role.CAMPESINO and role != Role.REGENTE

# --- Heridas ---
const SEVERE_WOUND_RATIO := 0.3
const SEVERE_WOUND_MONTHS := 2
const FALLEN_WOUND_MONTHS := 3      # si cayó (vida 0)
const FALLEN_HEALTH_RATIO := 0.1    # con cuánta vida queda quien cae en duelo
const MONTHLY_HEAL := 25

func is_wounded() -> bool:
	return wound_months > 0

# Tras un combate: recupera aliento y ánimo (la vida no) y, si quedó muy maltrecho,
# sufre una herida grave. Devuelve un texto para el jugador ("" si no hay herida).
func after_fight_recovery() -> String:
	current_stamina = max_stamina
	current_morale = max_morale
	var months := 0
	if current_health <= 0:
		current_health = maxi(1, int(max_health * FALLEN_HEALTH_RATIO))
		months = FALLEN_WOUND_MONTHS
	elif current_health < max_health * SEVERE_WOUND_RATIO:
		months = SEVERE_WOUND_MONTHS
	if months > 0:
		months = maxi(1, months - SkillEffects.wound_reduction(self))
	if months > wound_months:
		wound_months = months
	if months > 0:
		return "Quedas gravemente herido (vida %d/%d): no podrás batirte durante %d meses." % [current_health, max_health, wound_months]
	return ""

# Una vez por mes: se recupera vida y avanza la curación de las heridas graves.
func monthly_recovery() -> void:
	current_health = mini(max_health, current_health + maxi(5, MONTHLY_HEAL + SkillEffects.heal_bonus(self)))
	current_stamina = max_stamina
	current_morale = max_morale
	if wound_months > 0:
		wound_months -= 1
		if SkillEffects.has_unique(self, SkillEffects.UNIQUE_RELIC):   # Relicario de Aquisgrán
			wound_months = 0

func health_text() -> String:
	var text := "Vida %d/%d" % [current_health, max_health]
	if is_wounded():
		text += " — herido (%d %s)" % [wound_months, "mes" if wound_months == 1 else "meses"]
	return text

# --- Progresión social ---

# --- Experiencia y niveles ---
const MAX_LEVEL := 20
const XP_BASE := 100            # experiencia para pasar del nivel N al N+1: XP_BASE * N
const POINTS_PER_LEVEL := 2
const SKILL_EVERY_LEVELS := 3
const XpRulesRef = preload("res://scripts/resources/xp_rules.gd")

func xp_to_next() -> int:
	return XP_BASE * level

var last_xp_gained := 0        # experiencia realmente sumada en la última llamada (ya con multiplicador)

## Suma experiencia. Devuelve cuántos niveles se subieron (0 si ninguno).
## source (ver XpRules.SOURCE_*): el tipo de luchador multiplica lo que se aprende de cada fuente.
func gain_xp(amount: int, source: String = "") -> int:
	last_xp_gained = 0
	if amount <= 0 or level >= MAX_LEVEL:
		return 0
	amount = maxi(1, roundi(amount * XpRulesRef.multiplier(fighter_type, source) * (1.0 + SkillEffects.fx(self, "xp_" + source)))) if not source.is_empty() else amount
	last_xp_gained = amount
	xp += amount
	var gained := 0
	while level < MAX_LEVEL and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		gained += 1
		unspent_points += POINTS_PER_LEVEL
	if level >= MAX_LEVEL:
		xp = 0
	return gained

## Puntos que da ese nivel (admite points_for_level por nivel o acumulado).
static func tree_points_at(new_level: int) -> int:
	if not Character.tree_api_has("points_for_level"):
		return 1 if new_level % SKILL_EVERY_LEVELS == 0 else 0
	var api: Script = load("res://scripts/resources/skill_tree_catalog.gd")
	var cumulative: bool = int(api.call("points_for_level", 4)) >= int(api.call("points_for_level", 3))
	if cumulative:
		return maxi(0, int(api.call("points_for_level", new_level)) - int(api.call("points_for_level", new_level - 1)))
	return int(api.call("points_for_level", new_level))

## Suma (o resta) fama: duelos, torneos, batallas y encargos cumplidos. 0..100.
func add_fame(amount: int) -> void:
	if amount > 0:
		amount = roundi(amount * SkillEffects.fame_gain_multiplier(self))
	fame = clampi(fame + amount, 0, 100)

## Suma honor aplicando los efectos de honor ganado (Devoto, Codicioso...). Las pérdidas no se modifican.
func gain_honor(amount: int) -> void:
	if amount > 0:
		amount = roundi(amount * SkillEffects.honor_gain_multiplier(self))
	honor = clampi(honor + amount, 0, 100)

func register_duel_win(honor_gain: int = 10) -> void:
	duels_won += 1
	gain_honor(honor_gain)
	gold += 50

func register_duel_loss() -> void:
	duels_lost += 1
	honor = clamp(honor - 5, 0, 100)

# --- Comandancia: maestría por familia de tropa (1–10) ---
# Cada nivel pide MASTERY_XP_STEP × nivel de experiencia; da más soldados y moral al pelotón que dirige
# y, desde MASTERY_ADVANCED, la versión avanzada de esa tropa.
const MASTERY_MAX := 10
const MASTERY_XP_STEP := 40
const MASTERY_ADVANCED := 5

## Nivel de mando (1..10) en una familia de tropa (BattleEnums.Family).
func mastery(family: int) -> int:
	var xp_left: int = int(mastery_xp.get(str(family), 0))
	var lvl := 1
	while lvl < MASTERY_MAX and xp_left >= MASTERY_XP_STEP * lvl:
		xp_left -= MASTERY_XP_STEP * lvl
		lvl += 1
	return lvl

## Experiencia que falta para el siguiente nivel de mando ([actual, necesaria]).
func mastery_progress(family: int) -> Array:
	var xp_left: int = int(mastery_xp.get(str(family), 0))
	var lvl := 1
	while lvl < MASTERY_MAX and xp_left >= MASTERY_XP_STEP * lvl:
		xp_left -= MASTERY_XP_STEP * lvl
		lvl += 1
	return [xp_left, MASTERY_XP_STEP * lvl] if lvl < MASTERY_MAX else [0, 0]

## Suma experiencia de mando (con los bonus de rasgos y equipo). Devuelve los niveles ganados.
func add_mastery_xp(family: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var before := mastery(family)
	var gain := roundi(amount * maxf(0.0, 1.0 + SkillEffects.fx(self, "mastery_xp")))
	mastery_xp[str(family)] = int(mastery_xp.get(str(family), 0)) + gain
	return mastery(family) - before

## Familia en la que más manda (empate: la primera).
func best_family() -> int:
	var best := 0
	for f in 4:
		if mastery(f) > mastery(best):
			best = f
	return best
