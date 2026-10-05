extends Node
# Autoload — registrar como "RelationsData"
# Relaciones del jugador con los señores de los reinos y con sus rivales de duelo.
# Depende de GameManager y MapData; ningún otro autoload debe ser referenciado aquí
# (ArmyData sí usa RelationsData, así que la dirección inversa crearía un ciclo).

signal relations_changed

# --- Balance (ajustables sin tocar la lógica) ---
const GIFT_COST := 50
const GIFT_BASE_AFFINITY := 8           # + carisma / 2
const CONQUEST_AFFINITY := -40          # al antiguo señor de un castillo que le quitas
const ATTACKED_AFFINITY := -15          # a quien marcha contra tu castillo
const RIVAL_LOSS_AFFINITY := -10        # tu rival te guarda rencor cuando lo vences
const RIVAL_WIN_AFFINITY := 5           # y se calma un poco cuando te vence
const RIVAL_REMATCH_HONOR := 3          # honor extra por vencer a un rival conocido
const REMATCH_CHANCE := 0.5             # al retar a duelo, prob. de enfrentar a un rival conocido
const NO_LORD := "Sin Señor"
const DOWRY_COST := 100
const MARRIAGE_MIN_AFFINITY := 60
const MARRIAGE_AFFINITY := 20
const MARRIAGE_HONOR := 5
const PEACEFUL_SUCCESSION_AFFINITY := 10
const USURPATION_AFFINITY := -50
const WAR_AFFINITY := -30
const PEACE_TRIBUTE := 100
const PEACE_MIN_AFFINITY := -60      # por debajo, el enemigo rechaza cualquier paz
const PEACE_AFFINITY := 15
const BETRAYAL_HONOR := -15
const BETRAYAL_AFFINITY := -50
const BETRAYAL_REPUTATION := -5      # con todos los demás señores
const UNDECLARED_ATTACK_AFFINITY := -15

const SPOUSE_NAMES_FOR_MALE_PLAYER := ["Isabel", "Constanza", "Berenguela", "Elvira", "Mencía", "Blanca"]
const SPOUSE_NAMES_FOR_FEMALE_PLAYER := ["Alfonso", "Fernando", "Enrique", "Ramiro", "Bermudo", "García"]

# --- Población del mundo ---
const COURTIERS_PER_CASTLE := 2
const COURTIER_ROLES := [Character.Role.SOLDADO, Character.Role.CABALLERO, Character.Role.NOBLEZA_BAJA]

var relations: Array[Relationship] = []
var used_portraits: Array[String] = []   # retratos ya asignados: nadie comparte cara

# Diplomacia entre reinos de la IA (ver KingdomDiplomacy): {"a|b": mes_inicio} y {"a|b": true}
var kingdom_wars: Dictionary = {}
var kingdom_alliances: Dictionary = {}

# Soberano del reino del jugador (dueño de su castillo de origen al empezar) y matrimonio.
var liege_name: String = ""
var spouse_name: String = ""
var spouse_family: String = ""      # señor cuya familia se unió a la del jugador

func _ready() -> void:
	GameManager.game_started.connect(func(_character: Character): reset())

func reset() -> void:
	relations.clear()
	used_portraits.clear()
	kingdom_wars.clear()
	kingdom_alliances.clear()
	spouse_name = ""
	spouse_family = ""
	var home: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	liege_name = home.owner_name if home != null else ""
	_populate_world()
	relations_changed.emit()

# Crea la ficha de cada señor y una corte de personajes aleatorios por castillo,
# repartiendo retratos sin repetir y respetando el género.
func _populate_world() -> void:
	var player: Character = GameManager.player_character
	if player != null and player.portrait != null and player.portrait.resource_path != "":
		used_portraits.append(player.portrait.resource_path)
	var pool := PortraitPool.new(used_portraits)

	for c: Castle in MapData.castles:
		if c.owner_name == NO_LORD or get_relation(c.owner_name) != null:
			continue
		var gender := lord_gender(c.owner_name)
		var r := Relationship.new()
		r.person_name = c.owner_name
		r.kind = Relationship.Kind.SENOR
		r.affinity = randi_range(-10, 20)
		r.kingdom = c.kingdom
		var lord_role: int = Character.Role.REGENTE if c.owner_name.begins_with("Rey ") else Character.Role.NOBLEZA_ALTA
		r.character = CharacterLoader.make_random_character(lord_role, gender, _take_portrait(pool, gender), c.owner_name)
		relations.append(r)

	for c: Castle in MapData.castles:
		if c.kingdom == KingdomEnums.Kingdom.NEUTRAL:
			continue
		for i in range(COURTIERS_PER_CASTLE):
			var gender := pool.pick_gender()
			var person := _unique_random_character(COURTIER_ROLES.pick_random(), gender, _take_portrait(pool, gender))
			var r := Relationship.new()
			r.person_name = person.full_name()
			r.kind = Relationship.Kind.CORTESANO
			r.kingdom = c.kingdom
			r.character = person
			relations.append(r)

func _take_portrait(pool: PortraitPool, gender: int) -> String:
	var path := pool.take(gender)
	if path != "":
		used_portraits.append(path)
	return path

func _unique_random_character(role: int, gender: int, portrait_path: String) -> Character:
	var person := CharacterLoader.make_random_character(role, gender, portrait_path)
	var tries := 0
	while get_relation(person.full_name()) != null and tries < 20:
		person.first_name = CharacterLoader.random_first_name(gender)
		person.last_name = CharacterLoader.random_last_name()
		tries += 1
	return person

static func lord_gender(lord_name: String) -> int:
	return CharacterEnums.Gender.FEMENINO if lord_name.begins_with("Lady ") or lord_name.begins_with("Reina ") else CharacterEnums.Gender.MASCULINO

# Ficha de un personaje por nombre (señores, rivales, cortesanos), o null.
func character_of(person_name: String) -> Character:
	var r := get_relation(person_name)
	return r.character if r != null else null

func courtiers(kingdom: int = -1) -> Array[Relationship]:
	var result: Array[Relationship] = []
	for r: Relationship in relations:
		if r.kind == Relationship.Kind.CORTESANO and (kingdom < 0 or r.kingdom == kingdom):
			result.append(r)
	return result

func get_relation(person_name: String) -> Relationship:
	for r: Relationship in relations:
		if r.person_name == person_name:
			return r
	return null

func lords() -> Array[Relationship]:
	var result: Array[Relationship] = []
	for r: Relationship in relations:
		if r.kind == Relationship.Kind.SENOR:
			result.append(r)
	return result

func duel_rivals() -> Array[Relationship]:
	var result: Array[Relationship] = []
	for r: Relationship in relations:
		if r.kind == Relationship.Kind.RIVAL_DUELO and r.character != null:
			result.append(r)
	return result

# Castillos que gobierna un señor (pueden ser varios tras conquistas, o ninguno si los perdió).
func castles_of(person_name: String) -> Array[Castle]:
	var result: Array[Castle] = []
	for c: Castle in MapData.castles:
		if c.owner_name == person_name:
			result.append(c)
	return result

# Reinos cuyos señores son aliados formales / hostiles del jugador (para la IA de reinos).
func allied_kingdoms() -> Array[int]:
	return _kingdoms_where(func(r: Relationship): return r.allied)

func hostile_kingdoms() -> Array[int]:
	return _kingdoms_where(func(r: Relationship): return r.is_hostile())

func _kingdoms_where(predicate: Callable) -> Array[int]:
	var result: Array[int] = []
	for r: Relationship in lords():
		if not predicate.call(r):
			continue
		for c: Castle in castles_of(r.person_name):
			if not c.kingdom in result:
				result.append(c.kingdom)
	return result

# --- Acciones del jugador (cada una gasta 1 acción del turno) ---

func can_send_gift(r: Relationship) -> String:
	var player: Character = GameManager.player_character
	if player == null or r == null or r.kind != Relationship.Kind.SENOR:
		return "No disponible."
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	if player.gold < GIFT_COST:
		return "Necesitas %d de oro." % GIFT_COST
	return ""

func send_gift(r: Relationship) -> String:
	if not can_send_gift(r).is_empty():
		return can_send_gift(r)
	var player: Character = GameManager.player_character
	GameManager.consume_action()
	player.gold -= GIFT_COST
	var gain := GIFT_BASE_AFFINITY + player.charisma / 2
	r.adjust(gain)
	relations_changed.emit()
	return "Envías presentes a %s. Afinidad %+d (ahora %d)." % [r.person_name, gain, r.affinity]

func can_propose_alliance(r: Relationship) -> String:
	var player: Character = GameManager.player_character
	if player == null or r == null or r.kind != Relationship.Kind.SENOR:
		return "No disponible."
	if r.allied:
		return "Ya es tu aliado."
	if player.role < Character.Role.NOBLEZA_BAJA:
		return "Solo la nobleza puede pactar alianzas."
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	if r.affinity < Relationship.ALLIANCE_MIN_AFFINITY:
		return "Necesitas al menos %d de afinidad (tienes %d)." % [Relationship.ALLIANCE_MIN_AFFINITY, r.affinity]
	return ""

func propose_alliance(r: Relationship) -> String:
	if not can_propose_alliance(r).is_empty():
		return can_propose_alliance(r)
	GameManager.consume_action()
	r.allied = true
	relations_changed.emit()
	return "%s acepta la alianza: sus ejércitos no atacarán tus castillos." % r.person_name

# --- Reacciones a sucesos del mundo ---

func on_player_conquered(former_owner: String) -> String:
	var r := get_relation(former_owner)
	if r == null:
		return ""
	r.adjust(CONQUEST_AFFINITY)
	var text := "%s no olvidará que le arrebataste su castillo." % former_owner
	text += _check_alliance_break(r)
	relations_changed.emit()
	return text

func on_attacked_by(lord_name: String) -> void:
	var r := get_relation(lord_name)
	if r == null:
		return
	r.adjust(ATTACKED_AFFINITY)
	_check_alliance_break(r)
	relations_changed.emit()

func _check_alliance_break(r: Relationship) -> String:
	if r.allied and r.affinity < Relationship.ALLIANCE_BREAK_AFFINITY:
		r.allied = false
		return " La alianza con %s se rompe." % r.person_name
	return ""

# --- Rivales de duelo ---

# Devuelve un rival conocido para una revancha, o null para generar uno nuevo.
func pick_rematch_rival() -> Character:
	var rivals := duel_rivals()
	if rivals.is_empty() or randf() >= REMATCH_CHANCE:
		return null
	var rival: Character = rivals.pick_random().character
	rival.current_health = rival.max_health
	rival.current_stamina = rival.max_stamina
	rival.current_morale = rival.max_morale
	return rival

# Rival para un duelo: un conocido buscando revancha, o alguien de la corte con quien aún
# no te has batido (preferentemente de tu rango). Solo si no queda nadie se inventa uno nuevo.
func pick_duel_opponent(player: Character) -> Character:
	var rematch := pick_rematch_rival()
	if rematch != null:
		return rematch
	var candidates := courtiers()
	var same_rank: Array[Relationship] = []
	for r: Relationship in candidates:
		if r.character != null and r.character.role == player.role:
			same_rank.append(r)
	var chosen: Relationship = null
	if not same_rank.is_empty():
		chosen = same_rank.pick_random()
	elif not candidates.is_empty():
		chosen = candidates.pick_random()
	if chosen != null:
		var c := chosen.character
		c.current_health = c.max_health
		c.current_stamina = c.max_stamina
		c.current_morale = c.max_morale
		return c
	var gender := PortraitPool.new(used_portraits).pick_gender()
	return CharacterLoader.make_rival(player, _take_portrait(PortraitPool.new(used_portraits), gender), gender)

# Rivales de un torneo: caballeros de la corte (copias de su ficha, con su nombre y retrato),
# cada ronda algo más fuertes que la anterior. Si la corte no alcanza, se completan con nuevos.
func tournament_opponents(player: Character, rounds: int, stat_step: int) -> Array[Character]:
	var pool_rel := courtiers()
	pool_rel.shuffle()
	var result: Array[Character] = []
	for i in range(rounds):
		var c: Character
		if i < pool_rel.size() and pool_rel[i].character != null:
			c = pool_rel[i].character.duplicate()
		else:
			var gender := PortraitPool.new(used_portraits).pick_gender()
			c = CharacterLoader.make_rival(player, _take_portrait(PortraitPool.new(used_portraits), gender), gender)
		var bonus := (i - 1) * stat_step   # ronda 1 algo más débil, ronda 3 algo más fuerte
		c.combat = clampi(player.combat + bonus + randi_range(-1, 1), 1, 20)
		c.defense = clampi(player.defense + bonus + randi_range(-1, 1), 1, 20)
		c.current_health = c.max_health
		c.current_stamina = c.max_stamina
		c.current_morale = c.max_morale
		result.append(c)
	return result

# Registra el resultado de un duelo de campaña. Devuelve un texto extra para el resumen.
func register_duel(rival: Character, player_won: bool, fled: bool) -> String:
	var r := get_relation(rival.full_name())
	var known := r != null and r.kind == Relationship.Kind.RIVAL_DUELO
	if r != null and r.kind == Relationship.Kind.CORTESANO:
		# Un cortesano con el que te bates pasa a ser tu rival de duelos.
		r.kind = Relationship.Kind.RIVAL_DUELO
		r.affinity = mini(r.affinity, -10)
	elif r == null:
		r = Relationship.new()
		r.person_name = rival.full_name()
		r.kind = Relationship.Kind.RIVAL_DUELO
		r.character = rival
		r.affinity = -10
		relations.append(r)
	var text := ""
	if fled:
		text = "%s se burlará de esta huida." % rival.full_name()
	elif player_won:
		r.duels_won_against += 1
		r.adjust(RIVAL_LOSS_AFFINITY)
		if known and GameManager.player_character != null:
			GameManager.player_character.honor = clampi(GameManager.player_character.honor + RIVAL_REMATCH_HONOR, 0, 100)
			text = "Vencer de nuevo a tu rival te da +%d de honor extra." % RIVAL_REMATCH_HONOR
		else:
			text = "%s jura buscar la revancha." % rival.full_name()
	else:
		r.duels_lost_against += 1
		r.adjust(RIVAL_WIN_AFFINITY)
		text = "%s presume de su victoria sobre ti." % rival.full_name()
	relations_changed.emit()
	return text

# --- Matrimonio político ---

func is_married() -> bool:
	return not spouse_name.is_empty()

func can_propose_marriage(r: Relationship) -> String:
	var player: Character = GameManager.player_character
	if player == null or r == null or r.kind != Relationship.Kind.SENOR:
		return "No disponible."
	if is_married():
		return "Ya estás casado/a con %s." % spouse_name
	if player.role < Character.Role.CABALLERO:
		return "Ninguna casa noble casaría a los suyos con alguien de tu rango."
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	if r.affinity < MARRIAGE_MIN_AFFINITY:
		return "Necesitas al menos %d de afinidad (tienes %d)." % [MARRIAGE_MIN_AFFINITY, r.affinity]
	if player.gold < DOWRY_COST:
		return "Necesitas %d de oro para la dote." % DOWRY_COST
	return ""

func propose_marriage(r: Relationship) -> String:
	var reason := can_propose_marriage(r)
	if not reason.is_empty():
		return reason
	var player: Character = GameManager.player_character
	GameManager.consume_action()
	player.gold -= DOWRY_COST
	player.honor = clampi(player.honor + MARRIAGE_HONOR, 0, 100)
	var names: Array = SPOUSE_NAMES_FOR_MALE_PLAYER if player.gender == CharacterEnums.Gender.MASCULINO else SPOUSE_NAMES_FOR_FEMALE_PLAYER
	spouse_name = "%s %s" % [names.pick_random(), family_name_of(r.person_name)]
	spouse_family = r.person_name
	r.adjust(MARRIAGE_AFFINITY)
	r.allied = true
	relations_changed.emit()
	var text := "Te casas con %s, de la casa de %s. Su familia es ahora tu aliada (honor +%d)." % [
		spouse_name, r.person_name, MARRIAGE_HONOR]
	if r.person_name == liege_name:
		text += " Al emparentar con tu soberano, quedas en la línea de sucesión al trono."
	return text

# "Lord Baram Roca Alta" -> "Roca Alta": se omiten el título y el nombre de pila.
static func family_name_of(lord_name: String) -> String:
	var parts := lord_name.split(" ")
	return " ".join(parts.slice(2)) if parts.size() > 2 else lord_name

# --- Sucesión al trono (Nobleza Alta -> Regente) ---

func succession_context() -> Dictionary:
	var player: Character = GameManager.player_character
	var count := 0
	if player != null:
		for c: Castle in MapData.castles:
			if c.kingdom == GameManager.player_kingdom and (c.owner_name == player.full_name() or c.castle_id == GameManager.home_castle_id):
				count += 1
	return {
		"liege_name": liege_name,
		"married_to_liege": is_married() and spouse_family == liege_name,
		"kingdom_castles": count,
	}

# Aplica las consecuencias de coronarse. Devuelve el texto para el jugador.
func become_regent(by_marriage: bool) -> String:
	var player: Character = GameManager.player_character
	var home: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	if home != null and player != null:
		home.owner_name = player.full_name()
	var liege := get_relation(liege_name)
	var text: String
	if by_marriage:
		text = "Por derecho de matrimonio heredas la corona de %s. La sucesión es pacífica." % liege_name
		if liege != null:
			liege.adjust(PEACEFUL_SUCCESSION_AFFINITY)
	else:
		text = "Con tus castillos y tus tropas, depones a %s y te proclamas Regente." % liege_name
		if liege != null:
			liege.adjust(USURPATION_AFFINITY)
			liege.allied = false
			text += " %s jura venganza." % liege_name
	relations_changed.emit()
	return text

# --- Diplomacia: guerra, paz y traición ---

func can_declare_war(r: Relationship) -> String:
	var player: Character = GameManager.player_character
	if player == null or r == null or r.kind != Relationship.Kind.SENOR:
		return "No disponible."
	if player.role < Character.Role.NOBLEZA_ALTA:
		return "Solo la Nobleza Alta y el Regente pueden declarar la guerra."
	if r.at_war:
		return "Ya estás en guerra con %s." % r.person_name
	if r.allied:
		return "Es tu aliado: rompe la alianza antes (o atácalo y asume la traición)."
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	return ""

func declare_war(r: Relationship) -> String:
	var reason := can_declare_war(r)
	if not reason.is_empty():
		return reason
	GameManager.consume_action()
	r.at_war = true
	r.adjust(WAR_AFFINITY)
	relations_changed.emit()
	return "Declaras la guerra a %s. Conquistar sus castillos ya no se considera una agresión, pero sus ejércitos irán a por ti." % r.person_name

func can_propose_peace(r: Relationship) -> String:
	var player: Character = GameManager.player_character
	if player == null or r == null or not r.at_war:
		return "No estás en guerra con él."
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	if player.gold < PEACE_TRIBUTE:
		return "Necesitas %d de oro de tributo." % PEACE_TRIBUTE
	if r.affinity < PEACE_MIN_AFFINITY:
		return "%s te odia demasiado para negociar (afinidad %d, mínimo %d)." % [r.person_name, r.affinity, PEACE_MIN_AFFINITY]
	return ""

func propose_peace(r: Relationship) -> String:
	var reason := can_propose_peace(r)
	if not reason.is_empty():
		return reason
	GameManager.consume_action()
	GameManager.player_character.gold -= PEACE_TRIBUTE
	r.at_war = false
	r.adjust(PEACE_AFFINITY)
	relations_changed.emit()
	return "Firmas la paz con %s a cambio de %d de oro." % [r.person_name, PEACE_TRIBUTE]

# Se llama cuando el jugador ordena marchar contra un castillo ajeno. Devuelve una noticia ("" si nada).
func on_player_marches_against(owner_name: String) -> String:
	var r := get_relation(owner_name)
	var player: Character = GameManager.player_character
	if r == null or player == null or r.at_war:
		return ""   # contra un enemigo declarado (o sin señor) no hay deshonra
	if r.allied:
		r.allied = false
		r.adjust(BETRAYAL_AFFINITY)
		player.honor = clampi(player.honor + BETRAYAL_HONOR, 0, 100)
		for other: Relationship in lords():
			if other != r:
				other.adjust(BETRAYAL_REPUTATION)
		relations_changed.emit()
		return "¡Traición! Marchas contra tu aliado %s: la alianza se rompe, pierdes %d de honor y los demás señores desconfían de ti." % [
			owner_name, -BETRAYAL_HONOR]
	r.adjust(UNDECLARED_ATTACK_AFFINITY)
	relations_changed.emit()
	return "%s considera tu marcha una agresión sin declaración de guerra." % owner_name
