class_name Character
extends Resource

## ROLES SOCIALES
enum Role {
	CAMPESINO,
	SOLDADO,
	CABALLERO,
	NOBLEZA_BAJA,
	NOBLEZA_ALTA,
	REGENTE
}

## PERSONALIDADES
enum Personality {
	AMBICIOSO,
	LEAL,
	PRUDENTE,
	ARROGANTE,
	PIADOSO,
	ASTUTO
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

@export_group("Recursos de combate")
@export var max_health: int = 100
@export var current_health: int = 100
@export var max_stamina: int = 100
@export var current_stamina: int = 100
@export var max_morale: int = 100
@export var current_morale: int = 100
@export var honor: int = 50

@export_group("Progresión Social")
@export var gold: int = 100
@export var duels_won: int = 0
@export var duels_lost: int = 0

@export_group("Habilidades")
@export var general_skills: Array[Skill] = []
@export var combat_skills: Array[Skill] = []
@export var battle_skills: Array[Skill] = []

@export_group("Ventajas y Desventajas")
@export var advantages: Array[CharacterTrait] = []      # mínimo 3, validado en la UI de creación
@export var disadvantages: Array[CharacterTrait] = []   # mínimo 2, validado en la UI de creación

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

func _role_file_name() -> String:
	match role:
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
	return "Desconocido"

# --- Modificadores de traits + equipamiento ---
# Suma los bonos de ventajas, desventajas y equipo por ENCIMA de las stats base
# (las stats base ya deberían incluir personalidad/alineación/tipo + puntos libres repartidos).

func apply_trait_and_equipment_modifiers() -> void:
	var l := 0
	var c := 0
	var s := 0
	var cb := 0
	var d := 0

	for t: CharacterTrait in advantages:
		l += t.leadership_mod
		c += t.charisma_mod
		s += t.strategy_mod
		cb += t.combat_mod
		d += t.defense_mod

	for t: CharacterTrait in disadvantages:
		l += t.leadership_mod
		c += t.charisma_mod
		s += t.strategy_mod
		cb += t.combat_mod
		d += t.defense_mod

	for e: Equipment in equipment:
		l += e.leadership_mod
		c += e.charisma_mod
		s += e.strategy_mod
		cb += e.combat_mod
		d += e.defense_mod

	leadership = max(1, leadership + l)
	charisma = max(1, charisma + c)
	strategy = max(1, strategy + s)
	combat = max(1, combat + cb)
	defense = max(1, defense + d)

# --- Validación de reglas de creación ---

func is_creation_valid() -> Dictionary:
	var errors: Array[String] = []

	if first_name.strip_edges().is_empty():
		errors.append("El nombre no puede estar vacío.")
	if advantages.size() < 3:
		errors.append("Debes elegir al menos 3 ventajas (tienes %d)." % advantages.size())
	if disadvantages.size() < 2:
		errors.append("Debes elegir al menos 2 desventajas (tienes %d)." % disadvantages.size())
	if equipment.size() > 2:
		errors.append("No puedes llevar más de 2 piezas de equipamiento (tienes %d)." % equipment.size())

	return {"valid": errors.is_empty(), "errors": errors}

# --- Utilidades ya existentes ---

func is_alive() -> bool:
	return current_health > 0

func take_damage(amount: int) -> void:
	current_health = max(0, current_health - amount)

func can_fight_duels() -> bool:
	return role != Role.CAMPESINO and role != Role.REGENTE

# --- Progresión social ---

func register_duel_win() -> void:
	duels_won += 1
	honor = clamp(honor + 10, 0, 100)
	gold += 50

func register_duel_loss() -> void:
	duels_lost += 1
	honor = clamp(honor - 5, 0, 100)
