extends Node
# Autoload — registrar como "DynastyData"
# Dinastía del jugador: edad, hijos, muertes y sucesión. Guarda su estado en la partida (SaveSystem.MODULES).
#
# Cada enero todos cumplen un año. Casado, puede nacer un hijo; los hijos son adultos a los ADULT_AGE.
# Si el jugador muere (vejez, duelo a muerte, batalla), elige con qué hijo adulto sigue la partida;
# sin hijos adultos, el linaje se extingue y la partida termina.
# Los señores de la IA mueren y heredan en WorldEvents; aquí solo se envejecen.

const SUCCESSION_SCENE := "res://scenes/succession/succession.tscn"

# --- Balance ---
const START_AGE_BY_ROLE := {
	Character.Role.CAMPESINO: 17, Character.Role.SOLDADO: 19, Character.Role.CABALLERO: 23,
	Character.Role.NOBLEZA_BAJA: 27, Character.Role.NOBLEZA_ALTA: 32, Character.Role.REGENTE: 38,
	Character.Role.DUQUE: 35, Character.Role.MERCENARIO: 20, Character.Role.CAPITAN: 26, Character.Role.CONDOTIERO: 30, Character.Role.INAFILIADO: 19,
}
const ADULT_AGE := 16
const OLD_AGE := 55                 # desde esta edad, cada enero puede llegar la muerte
const OLD_AGE_BASE_CHANCE := 0.04
const OLD_AGE_CHANCE_PER_YEAR := 0.03
const BIRTH_CHANCE := 0.35          # por año, con cónyuge en edad de tener hijos
const MAX_FERTILE_AGE := 45
const MAX_CHILDREN := 6
const HEIR_HONOR_MIN := 30
const NAME_REROLLS := 30           # intentos para no repetir el nombre de un hermano

var _children: Array[Character] = []   # hijos del jugador y, tras una sucesión, sus hermanos
var _parent_of := {}                   # nombre del hijo -> nombre de su progenitor jugador
var _natural := {}                     # nombre del hijo -> true si es de una amante (segunda línea)
var _pending_cause := ""             # no vacío: el jugador murió y falta elegir heredero
var _deceased_name := ""
# Opción de Nueva Partida. Si es false, los adultos no envejecen ni mueren de viejos;
# los hijos siguen naciendo y creciendo hasta la mayoría de edad.
var aging_enabled := true

signal family_changed

func _ready() -> void:
	GameManager.game_started.connect(func(_character: Character): reset())
	GameManager.turn_advanced.connect(_on_month_passed)

func reset() -> void:
	_children.clear()
	_parent_of.clear()
	_natural.clear()
	_pending_cause = ""
	_deceased_name = ""
	var player: Character = GameManager.player_character
	if player != null:
		player.age = START_AGE_BY_ROLE.get(player.role, 20)

# --- Consultas ---

func children() -> Array[Character]:
	return _children.duplicate()

## Herederos adultos: los legítimos; los hijos de amantes solo si no hay ningún legítimo adulto.
func adult_children() -> Array[Character]:
	var legit: Array[Character] = []
	var natural: Array[Character] = []
	for c: Character in _children:
		if c.age >= ADULT_AGE:
			(natural if is_natural(c) else legit).append(c)
	return legit if not legit.is_empty() else natural

## Hijo de amante (heredero de segunda línea).
func is_natural(c: Character) -> bool:
	return _natural.has(c.full_name())

## true si es hijo o hija del jugador actual (false: hermano o hermana, de una generación anterior).
func is_own_child(c: Character) -> bool:
	var player: Character = GameManager.player_character
	return player != null and _parent_of.get(c.full_name(), player.full_name()) == player.full_name()

func needs_succession() -> bool:
	return not _pending_cause.is_empty()

func death_cause() -> String:
	return _pending_cause

func deceased_name() -> String:
	return _deceased_name

## Probabilidad de morir de viejo este año a una edad dada.
static func old_age_chance(age: int) -> float:
	if age < OLD_AGE:
		return 0.0
	return minf(1.0, OLD_AGE_BASE_CHANCE + OLD_AGE_CHANCE_PER_YEAR * (age - OLD_AGE))

func _child_word(c: Character) -> String:
	var fem := c.gender == CharacterEnums.Gender.FEMENINO
	if is_own_child(c):
		return "hija" if fem else "hijo"
	return "hermana" if fem else "hermano"

# --- Paso del tiempo ---

func _on_month_passed(month: int, _year: int) -> void:
	if not GameManager.is_game_active or needs_succession() or month != 1:
		return
	_age_everyone()
	_births()
	if not aging_enabled:
		return
	_spouse_old_age()
	var player: Character = GameManager.player_character
	if player != null and randf() < old_age_chance(player.age):
		on_player_died("de vejez, a los %d años" % player.age)

func _age_everyone() -> void:
	var player: Character = GameManager.player_character
	if aging_enabled:
		if player != null:
			player.age += 1
		for r: Relationship in RelationsData.relations:
			if r.character != null:
				r.character.age += 1
	for c: Character in _children:
		c.age += 1
		if c.age == ADULT_AGE:
			CharacterLoader.grow_up(c, RelationsData.take_free_portrait(c.gender))
			_news("%s, tu %s, cumple %d años y ya es %s." % [c.full_name(), _child_word(c), ADULT_AGE,
				"una mujer adulta" if c.gender == CharacterEnums.Gender.FEMENINO else "un hombre adulto"], "Tu familia")
	family_changed.emit()

func _births() -> void:
	var player: Character = GameManager.player_character
	if player == null:
		return
	# Cualquier cónyuge o amante puede dar hijos; los de amantes son herederos de segunda línea.
	var partners: Array[Relationship] = RelationsData.spouse_relations()
	partners.append_array(RelationsData.concubine_relations())
	for partner: Relationship in partners:
		if partner.character == null or partner.character.gender == player.gender or _children.size() >= MAX_CHILDREN:
			continue
		var mother: Character = partner.character if partner.character.gender == CharacterEnums.Gender.FEMENINO else player
		if mother.age >= MAX_FERTILE_AGE or randf() >= BIRTH_CHANCE:
			continue
		_add_child(player, partner, RelationsData.is_concubine(partner.person_name))

func _add_child(player: Character, partner: Relationship, natural: bool) -> Character:
	var child := CharacterLoader.make_child(player, partner.character, house_name(player))
	# La familia se identifica por nombre completo: dos hermanos (o un hijo y su padre) no pueden llamarse igual.
	var taken: Array = _children.map(func(c: Character): return c.full_name()) + [player.full_name()]
	for _attempt in NAME_REROLLS:
		if not child.full_name() in taken:
			break
		child.first_name = CharacterLoader.random_first_name(child.gender)
	_children.append(child)
	_parent_of[child.full_name()] = player.full_name()
	if natural:
		_natural[child.full_name()] = true
	_news("Nace tu %s %s%s. %s y tú lo celebráis." % [_child_word(child), child.first_name,
		" (bastardo)" if natural else "", partner.person_name], "Un nacimiento")
	family_changed.emit()
	return child

func _spouse_old_age() -> void:
	for spouse_rel: Relationship in RelationsData.spouse_relations():
		if spouse_rel.character != null and randf() < old_age_chance(spouse_rel.character.age):
			_news("%s, tu cónyuge, muere de vejez a los %d años." % [spouse_rel.person_name, spouse_rel.character.age], "Luto en la familia")
			_end_marriage(spouse_rel)

# El cónyuge que muere (o enviuda) deja de ser una relación del jugador.
func _end_marriage(spouse_rel: Relationship) -> void:
	RelationsData.relations.erase(spouse_rel)
	RelationsData.retinue.erase(spouse_rel.person_name)
	RelationsData._unregister_spouse(spouse_rel.person_name)
	RelationsData.relations_changed.emit()

const TITLES := ["Sir", "Lady", "Dama", "Don", "Doña", "Lord", "Señor", "Señora"]

## Apellido que llevan los hijos: el del jugador o, si no tiene, el nombre del fundador
## de la casa sin títulos ("Sir Alaric" → "de Alaric").
static func house_name(c: Character) -> String:
	if not c.last_name.is_empty():
		return c.last_name
	var words: Array = Array(c.first_name.split(" ", false)).filter(func(w: String) -> bool: return not w in TITLES)
	return "de " + (" ".join(words) if not words.is_empty() else c.first_name)

func _news(text: String, title: String) -> void:
	WorldEvents.record(text, "", true)
	WorldEvents.notify(title, text)

# --- Muerte y sucesión ---

## El jugador muere. cause: "en un duelo a muerte contra X", "en la batalla de Y", "de vejez"...
## Desde el mapa se pasa enseguida a la pantalla de sucesión; desde un duelo o una batalla,
## el mapa la abre al volver.
func on_player_died(cause: String) -> void:
	var player: Character = GameManager.player_character
	if player == null or needs_succession():
		return
	_pending_cause = cause
	_deceased_name = player.full_name()
	WorldEvents.record("%s muere %s." % [_deceased_name, cause], "", true)
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path.ends_with("map.tscn"):
		get_tree().change_scene_to_file.call_deferred(SUCCESSION_SCENE)

## El jugador, capturado, es ejecutado por orden de captor_name (para el sistema de capturas).
## Igual que cualquier muerte: si hay hijos adultos se elige heredero; si no, el linaje se extingue y
## la partida termina (pantalla de sucesión). executed_where: "en X" opcional, p. ej. "en la plaza de Y".
func on_player_executed(captor_name: String, executed_where: String = "") -> void:
	var player: Character = GameManager.player_character
	var fem := player != null and player.gender == CharacterEnums.Gender.FEMENINO
	var cause := "%s por orden de %s" % ["ejecutada" if fem else "ejecutado", captor_name]
	if not executed_where.is_empty():
		cause += " " + executed_where
	on_player_died(cause)

## El heredero elegido toma el relevo: hereda el oro, parte del honor y la fama, el rango y los
## castillos; el séquito sigue con él. El cónyuge del difunto se retira de la vida de la corte.
func succeed(heir: Character) -> String:
	var old: Character = GameManager.player_character
	if old == null or not heir in _children:
		return ""
	var old_name := old.full_name()
	heir.gold = old.gold
	heir.honor = maxi(HEIR_HONOR_MIN, old.honor / 2)
	heir.fame = old.fame / 2
	heir.role = old.role
	heir.current_health = heir.max_health
	heir.current_stamina = heir.max_stamina
	heir.current_morale = heir.max_morale
	for c: Castle in MapData.castles:
		if c.owner_name == old_name:
			c.owner_name = heir.full_name()
	for a: Army in ArmyData.armies:
		if a.owner_name == old_name:
			a.owner_name = heir.full_name()
	for spouse_rel: Relationship in RelationsData.spouse_relations():
		_end_marriage(spouse_rel)
	RelationsData.concubines.clear()
	_children.erase(heir)
	_parent_of.erase(heir.full_name())
	MissionData.reset()
	GameManager.player_character = heir
	GameManager.refresh_actions_for_role_change()
	_pending_cause = ""
	var text := "%s hereda la casa de %s como %s." % [heir.full_name(), old_name, heir.role_name()]
	WorldEvents.record(text, "", true)
	family_changed.emit()
	ArmyData.armies_changed.emit()
	return text

## Sin hijos adultos que hereden: la partida termina.
func end_lineage() -> String:
	var reason := "Tu linaje se extingue: %s muere %s sin un heredero adulto." % [_deceased_name, _pending_cause]
	_pending_cause = ""
	_children.clear()
	_parent_of.clear()
	GameManager.end_game(reason)
	return reason

# --- Guardado ---

func save_state() -> Dictionary:
	return {
		"children": _children.map(func(c: Character): return DataCodec.encode(c)),
		"parent_of": _parent_of.duplicate(),
		"natural": _natural.duplicate(),
		"pending_cause": _pending_cause,
		"deceased_name": _deceased_name,
		"aging_enabled": aging_enabled,
	}

func load_state(data: Dictionary) -> void:
	_children.clear()
	for entry in data.get("children", []):
		var c := DataCodec.decode(entry) as Character
		if c != null:
			_children.append(c)
	_parent_of = data.get("parent_of", {}).duplicate()
	_natural = data.get("natural", {}).duplicate()
	_pending_cause = str(data.get("pending_cause", ""))
	_deceased_name = str(data.get("deceased_name", ""))
	aging_enabled = bool(data.get("aging_enabled", true))
	# Partidas anteriores a la dinastía: la edad del jugador era la de serie; se ajusta a su rango.
	var player: Character = GameManager.player_character
	if player != null and data.is_empty():
		player.age = START_AGE_BY_ROLE.get(player.role, player.age)
