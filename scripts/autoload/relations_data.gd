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
# --- Rivalidad ---
const GRUDGE_PLAYER_WIN := 15
const GRUDGE_PROUD_EXTRA := 10            # Arrogantes y Ambiciosos encajan peor la derrota
const GRUDGE_PLAYER_LOSS := -10
const GRUDGE_PLAYER_FLED := 10
const GRUDGE_RESPECT_SHIFT := -12         # Leales y Piadosos acaban respetando a quien los vence dos veces
const RIVAL_STAGE_HONOR := [3, 6, 10, 3]  # honor extra por volver a vencer, según la etapa (conocido, rival, némesis, respeto)
const RIVAL_EVENT_DIVISOR := 300.0        # prob. mensual de que un rival tome la iniciativa = rencor / divisor
const RIVAL_EVENT_MAX_CHANCE := 0.25
const RIVAL_NEWS_GRUDGE := 5              # tus victorias alimentan el rencor de tus rivales
const RIVAL_REFUSE_HONOR := [3, 3, 6, 0]  # honor perdido al rechazar un reto, según la etapa
const SPAR_CHANCE := 0.05                 # un rival que te respeta ofrece entrenar

# --- Intimidad y romance ---
# La intimidad (Relationship.affection) crece con el trato; el romance solo es posible entre un hombre y una mujer.
const TALK_BASE := 6                      # + carisma / 3
const TALK_FAIL_BASE := 0.3               # prob. de que la charla salga mal, menos 2% por punto de carisma
const INTIMATE_BASE := 10                 # + carisma / 2
const INTIMATE_MIN_AFFECTION := 40        # antes de ser amigos, un gesto íntimo es una ofensa
const PERSONAL_GIFT_COST := 30           # regalo a una persona (los presentes a un señor cuestan GIFT_COST)
const GIFT_BASE := 12
const DISLIKE_PENALTY := -4
const REJECT_PENALTY := -8                # un gesto íntimo rechazado enfría bastante
const DECAY_GRACE_MONTHS := 2             # meses sin trato antes de que la relación se enfríe
const FRIEND_DECAY := 1
const ROMANCE_DECAY := 3
const ROMANCE_DECAY_LEAL := 5             # la constancia importa más a los Leales
const GRUDGE_EASE := 0.5                  # el buen trato con un rival le quita parte del rencor
const PROPOSAL_MIN_AFFECTION := 80
const PROPOSAL_REJECT_AFFECTION := -6
const WEDDING_COST := 50
const LOVE_MARRIAGE_HONOR := 3
const LOVE_FAMILY_AFFINITY := 10          # el señor del reino de tu cónyuge te mira con mejores ojos

# --- Retos a duelo ---
const CHALLENGE_RANK_GAP := 2             # quien te supera en 2+ rangos rechaza el reto...
const CHALLENGE_FAME_PER_RANK := 20       # ...salvo que tu fama lo justifique (20 por rango de diferencia)
const FEAR_POWER_GAP := 4                 # si le superas en 4+ de combate+defensa puede negarse por miedo
const FEAR_REFUSE_CHANCE := 0.6
const FAME_DUEL_WIN := 3
const FAME_PER_RANK_ABOVE := 3            # vencer a alguien de rango superior da más fama
const FAME_FLED := -2

# --- Séquito y compañeros ---
const RETINUE_SIZE := {
	Character.Role.CAMPESINO: 0, Character.Role.SOLDADO: 1, Character.Role.CABALLERO: 2,
	Character.Role.NOBLEZA_BAJA: 3, Character.Role.NOBLEZA_ALTA: 4, Character.Role.REGENTE: 5,
}
const RETINUE_MIN_AFFECTION := 50
# Lo que exige cada rango para seguirte: [fama mínima, honor mínimo].
const RETINUE_REQUIREMENTS := {
	Character.Role.CAMPESINO: [0, 0], Character.Role.SOLDADO: [0, 20], Character.Role.CABALLERO: [15, 40],
	Character.Role.NOBLEZA_BAJA: [35, 60], Character.Role.NOBLEZA_ALTA: [60, 75], Character.Role.REGENTE: [90, 90],
}
const RETINUE_UPKEEP := 5                 # oro al mes por cada miembro del séquito
const RETINUE_UNPAID_AFFECTION := -10
const RETINUE_LEAVE_AFFECTION := 30       # por debajo de esta intimidad, quien no cobra se marcha
const FACTION_COMPANIONS := 2             # compañeros que presta tu señor si no tienes séquito
const FACTION_MIN_LIEGE_AFFINITY := -20   # con peor relación, tu señor no te presta a nadie

# --- Pueblo ---
const COMMONERS_PER_CASTLE := 4
const COMMONER_ROLES := [Character.Role.CAMPESINO, Character.Role.CAMPESINO, Character.Role.SOLDADO]

const SUITOR_CHANCE := 0.15
const SUITOR_MIN_AFFECTION := 40
const SUITOR_MONTHLY_DECAY := 5
const SUITOR_DUEL_AFFECTION := 20
const ROMANCE_EVENT_CHANCE := 0.12
const SPOUSE_EVENT_CHANCE := 0.12
const SPOUSE_START_AFFECTION := 60

const DUEL_POWER_WINDOW := 3             # cortesanos válidos como rival: combate+defensa a ±3 del jugador

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
var last_victory_month: int = -1     # mes de la última victoria (duelo, torneo, conquista)
var retinue: Array[String] = []       # nombres de quienes forman tu séquito
var requested_tab := ""               # pestaña con la que abrir la pantalla de relaciones ("lugar", "sequito"...)
var retinue_news: Array[String] = []  # avisos del séquito (bajas por falta de paga...) para mostrar en Relaciones

func _ready() -> void:
	GameManager.game_started.connect(func(_character: Character): reset())
	GameManager.turn_advanced.connect(_on_month_passed)

func reset() -> void:
	relations.clear()
	used_portraits.clear()
	kingdom_wars.clear()
	kingdom_alliances.clear()
	spouse_name = ""
	spouse_family = ""
	retinue.clear()
	retinue_news.clear()
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
		var crowned := c.owner_name.begins_with("Rey ") or c.owner_name.begins_with("Reina ")
		var lord_role: int = Character.Role.REGENTE if crowned else Character.Role.NOBLEZA_ALTA
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
		# Campesinos y soldados: gente del lugar con la que también se puede tratar.
		for i in range(COMMONERS_PER_CASTLE):
			var gender := pool.pick_gender()
			var person := _unique_random_character(COMMONER_ROLES[i % COMMONER_ROLES.size()], gender, _take_portrait(pool, gender))
			var r := Relationship.new()
			r.person_name = person.full_name()
			r.kind = Relationship.Kind.PUEBLO
			r.kingdom = c.kingdom
			r.character = person
			relations.append(r)

## Retrato libre (nadie comparte cara) para un personaje nuevo del género dado.
func take_free_portrait(gender: int) -> String:
	return _take_portrait(PortraitPool.new(used_portraits), gender)

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

func commoners(kingdom: int = -1) -> Array[Relationship]:
	var result: Array[Relationship] = []
	for r: Relationship in relations:
		if r.kind == Relationship.Kind.PUEBLO and (kingdom < 0 or r.kingdom == kingdom):
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
	return "Envías presentes a %s. Afinidad %+d (ahora %d).\n%s" % [
		r.person_name, gain, r.affinity, DialogueCatalog.line("lord_gift", r.character, player)]

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
	return "%s acepta la alianza: sus ejércitos no atacarán tus castillos.\n%s" % [
		r.person_name, DialogueCatalog.line("lord_alliance_yes", r.character, GameManager.player_character)]

# --- Reacciones a sucesos del mundo ---

func on_player_conquered(former_owner: String) -> String:
	var r := get_relation(former_owner)
	if r == null:
		return ""
	r.adjust(CONQUEST_AFFINITY)
	var text := "%s no olvidará que le arrebataste su castillo." % former_owner
	text += _check_alliance_break(r)
	var reactions := rival_reactions()
	if not reactions.is_empty():
		text += " " + reactions
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
	# Solo cortesanos de fuerza parecida (combate + defensa a ±DUEL_POWER_WINDOW), mejor si son de tu rango;
	# si no hay ninguno, se genera un rival a tu medida.
	var player_power := player.combat + player.defense
	var fair: Array[Relationship] = []
	for r: Relationship in courtiers():
		if r.character != null and absi(r.character.combat + r.character.defense - player_power) <= DUEL_POWER_WINDOW:
			fair.append(r)
	var same_rank: Array[Relationship] = []
	for r: Relationship in fair:
		if r.character.role == player.role:
			same_rank.append(r)
	var chosen: Relationship = null
	if not same_rank.is_empty():
		chosen = same_rank.pick_random()
	elif not fair.is_empty():
		chosen = fair.pick_random()
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
	if r != null and r.kind in [Relationship.Kind.CORTESANO, Relationship.Kind.PUEBLO]:
		# Un cortesano (o alguien del pueblo) con el que te bates pasa a ser tu rival de duelos.
		r.kind = Relationship.Kind.RIVAL_DUELO
		r.affinity = mini(r.affinity, -10)
	elif r == null:
		r = Relationship.new()
		r.person_name = rival.full_name()
		r.kind = Relationship.Kind.RIVAL_DUELO
		r.character = rival
		r.affinity = -10
		relations.append(r)
	var player: Character = GameManager.player_character
	var stage_before := r.rivalry_stage()
	r.last_duel_month = GameManager.months_elapsed()
	var text := ""
	if fled:
		r.adjust_grudge(GRUDGE_PLAYER_FLED)
		if player != null:
			player.add_fame(FAME_FLED)
		text = "%s se burlará de esta huida." % rival.full_name()
	elif player_won:
		last_victory_month = GameManager.months_elapsed()
		if player != null:
			var fame_gain := FAME_DUEL_WIN + maxi(0, rival.role - player.role) * FAME_PER_RANK_ABOVE
			player.add_fame(fame_gain)
			text = "Fama %+d. " % fame_gain
		r.duels_won_against += 1
		r.adjust(RIVAL_LOSS_AFFINITY)
		var forgiving := rival.personality in [Character.Personality.LEAL, Character.Personality.PIADOSO]
		if forgiving and r.duels_won_against >= 2:
			r.adjust_grudge(GRUDGE_RESPECT_SHIFT)
		else:
			var proud := rival.personality in [Character.Personality.ARROGANTE, Character.Personality.AMBICIOSO]
			r.adjust_grudge(GRUDGE_PLAYER_WIN + (GRUDGE_PROUD_EXTRA if proud else 0))
		if known and player != null:
			var bonus: int = RIVAL_STAGE_HONOR[stage_before]
			player.gain_honor(bonus)
			text += "Vencer de nuevo a tu rival te da +%d de honor extra." % bonus
		else:
			text += "%s jura buscar la revancha." % rival.full_name()
	else:
		r.duels_lost_against += 1
		r.adjust(RIVAL_WIN_AFFINITY)
		r.adjust_grudge(GRUDGE_PLAYER_LOSS)
		text = "%s presume de su victoria sobre ti." % rival.full_name()
	var stage_after := r.rivalry_stage()
	if stage_after != stage_before:
		text += " " + _stage_change_text(r, stage_after)
	if not fled:
		text += _settle_suitor_duel(rival.full_name(), player_won)
	relations_changed.emit()
	return text.strip_edges()

func _stage_change_text(r: Relationship, stage: int) -> String:
	match stage:
		Relationship.RivalryStage.RIVAL:
			return "%s ya no te ve como un simple contrincante: ahora es tu rival." % r.person_name
		Relationship.RivalryStage.NEMESIS:
			return "%s te ha convertido en su obsesión y buscará venganza." % r.person_name
		Relationship.RivalryStage.RESPETO:
			return DialogueCatalog.line("rival_respect", r.character, GameManager.player_character)
	return ""

# Tus victorias llegan a oídos de tus rivales: reaccionan según su carácter y crece su rencor.
func rival_reactions(max_lines: int = 2) -> String:
	last_victory_month = GameManager.months_elapsed()
	var lines: Array[String] = []
	for r: Relationship in duel_rivals():
		var stage := r.rivalry_stage()
		if stage != Relationship.RivalryStage.RIVAL and stage != Relationship.RivalryStage.NEMESIS:
			continue
		r.adjust_grudge(RIVAL_NEWS_GRUDGE)
		if lines.size() < max_lines:
			lines.append(DialogueCatalog.line("rival_news", r.character, GameManager.player_character))
	return " ".join(lines)

# --- Matrimonio político ---

func is_married() -> bool:
	return not spouse_name.is_empty()

func can_propose_marriage(r: Relationship) -> String:
	var player: Character = GameManager.player_character
	if player == null or r == null or r.kind != Relationship.Kind.SENOR:
		return "No disponible."
	if is_married():
		return "Ya estás %s con %s." % [_married_word(player), spouse_name]
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
	var spouse_first: String = names.pick_random()
	spouse_name = "%s %s" % [spouse_first, family_name_of(r.person_name)]
	spouse_family = r.person_name
	r.adjust(MARRIAGE_AFFINITY)
	r.allied = true
	_add_spouse_relation(spouse_first, family_name_of(r.person_name), r.kingdom, _spouse_gender(player))
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
	return "Declaras la guerra a %s. Conquistar sus castillos ya no se considera una agresión, pero sus ejércitos irán a por ti.\n%s" % [
		r.person_name, DialogueCatalog.line("lord_war", r.character, GameManager.player_character)]

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

# --- Vida social: intimidad, romance, matrimonio y cónyuge ---

func spouse_relation() -> Relationship:
	for r: Relationship in relations:
		if r.kind == Relationship.Kind.CONYUGE:
			return r
	return null

## Personas con las que se puede tratar de tú a tú (no los señores, que se tratan por diplomacia).
func sociable(r: Relationship) -> bool:
	return r != null and r.character != null and r.kind in [
		Relationship.Kind.CORTESANO, Relationship.Kind.RIVAL_DUELO, Relationship.Kind.PUEBLO, Relationship.Kind.CONYUGE]

## El romance solo es posible entre un hombre y una mujer.
func romance_possible(r: Relationship) -> bool:
	var player: Character = GameManager.player_character
	return sociable(r) and player != null and r.character.gender != player.gender

# Compatibilidad: quien puede ser cortejado.
func courtable(r: Relationship) -> bool:
	return romance_possible(r) and r.kind != Relationship.Kind.CONYUGE

## Gente de tu zona (tu reino): con ella puedes tratar y a ella puedes retar.
func in_area(r: Relationship) -> bool:
	return r != null and (r.kingdom < 0 or r.kingdom == GameManager.player_kingdom)

func people_in_area() -> Array[Relationship]:
	var result: Array[Relationship] = []
	for r: Relationship in relations:
		if sociable(r) and in_area(r) and r.kind != Relationship.Kind.CONYUGE:
			result.append(r)
	return result

## Personas con quienes tienes algún trato (intimidad, romance o séquito), estén donde estén.
func close_people() -> Array[Relationship]:
	var result: Array[Relationship] = []
	for r: Relationship in relations:
		if sociable(r) and (r.affection >= Relationship.ROMANCE_INTEREST or r.romance or r.person_name in retinue):
			result.append(r)
	return result

func intimacy_label(r: Relationship) -> String:
	var gender: int = r.character.gender if r.character != null else CharacterEnums.Gender.MASCULINO
	if r.kind == Relationship.Kind.CONYUGE:
		return "Tu esposa" if gender == CharacterEnums.Gender.FEMENINO else "Tu esposo"
	var female := gender == CharacterEnums.Gender.FEMENINO
	var fallback: String = ["Desconocido", "Conocido", "Amigo", "Confidente", "Amante" if r.romance else "Íntimo"][intimacy_tier(r.affection)]
	if female:
		fallback = fallback.trim_suffix("o") + "a" if fallback.ends_with("o") else fallback
	return catalog("intimacy_name", [r.affection, r.romance, gender], fallback)

func intimacy_tier(affection: int) -> int:
	return catalog("intimacy_tier", [affection], clampi(affection / 20, 0, 4))

func _like(r: Relationship, kind: String) -> float:
	return catalog("interaction_like", [r.character.personality, kind], 1.0)

var _catalog_methods: Array = []

## Llama a una función del DialogueCatalog si existe (el catálogo crece por partes); si no, devuelve fallback.
func catalog(method: String, args: Array, fallback: Variant) -> Variant:
	if _catalog_methods.is_empty():
		for m in (DialogueCatalog as Script).get_script_method_list():
			_catalog_methods.append(m.name)
	var script: Script = DialogueCatalog
	return script.callv(method, args) if method in _catalog_methods else fallback

func _married_word(player: Character) -> String:
	return "casada" if player.gender == CharacterEnums.Gender.FEMENINO else "casado"

func _spouse_gender(player: Character) -> int:
	return CharacterEnums.Gender.FEMENINO if player.gender == CharacterEnums.Gender.MASCULINO else CharacterEnums.Gender.MASCULINO

func _add_spouse_relation(first_name: String, last_name: String, kingdom: int, gender: int) -> void:
	var pool := PortraitPool.new(used_portraits)
	var spouse := CharacterLoader.make_random_character(Character.Role.NOBLEZA_BAJA, gender, _take_portrait(pool, gender), first_name, last_name)
	var r := Relationship.new()
	r.person_name = spouse.full_name()
	r.kind = Relationship.Kind.CONYUGE
	r.character = spouse
	r.kingdom = kingdom
	r.affinity = SPOUSE_START_AFFECTION
	r.affection = SPOUSE_START_AFFECTION
	r.romance = true
	relations.append(r)

## Motivo por el que no se puede interactuar ("" si se puede). kind: "friendly", "intimate", "gift".
func can_interact(r: Relationship, kind: String) -> String:
	var player: Character = GameManager.player_character
	if player == null or not sociable(r):
		return "No disponible."
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	if r.last_courted_month == GameManager.months_elapsed():
		return "Ya has pasado tiempo con %s este mes." % r.person_name
	match kind:
		"intimate":
			if not romance_possible(r):
				return "Entre vosotros solo cabe la amistad."
			if is_married() and r.kind != Relationship.Kind.CONYUGE:
				return "Ya estás %s con %s." % [_married_word(player), spouse_name]
			if r.affection < INTIMATE_MIN_AFFECTION:
				return "Aún no tenéis la confianza suficiente (intimidad %d de %d)." % [r.affection, INTIMATE_MIN_AFFECTION]
		"gift":
			if player.gold < PERSONAL_GIFT_COST:
				return "Necesitas %d de oro." % PERSONAL_GIFT_COST
	return ""

func interact(r: Relationship, kind: String) -> String:
	var reason := can_interact(r, kind)
	if not reason.is_empty():
		return reason
	var player: Character = GameManager.player_character
	GameManager.consume_action()
	r.last_courted_month = GameManager.months_elapsed()
	var like := _like(r, kind)
	var before := r.affection
	var ctx := {"player": player.full_name(), "rank": player.role_name()}
	# El saludo cambia con la confianza: un desconocido no habla como un amigo.
	var greet_topics := ["greet_stranger", "greet_acquaintance", "greet_friend", "greet_close", "greet_lover"]
	var tier: int = intimacy_tier(r.affection)
	var greet_topic: String = greet_topics[tier]
	if tier == 4 and not r.romance:
		greet_topic = "greet_close"
	if r.kind == Relationship.Kind.PUEBLO and player.role > r.character.role and tier < 2:
		greet_topic = "commoner_greet"
	var lines: Array[String] = []
	var greeting := DialogueCatalog.line(greet_topic, r.character, player, ctx)
	if not greeting.is_empty():
		lines.append(greeting)
	var gain := 0
	var topic := ""
	match kind:
		"friendly":
			var fail_chance: float = clampf(TALK_FAIL_BASE - player.charisma * 0.02, 0.05, TALK_FAIL_BASE)
			if like <= 0.5 or randf() < fail_chance:
				gain = DISLIKE_PENALTY
				topic = "friendly_bad"
			else:
				gain = roundi((TALK_BASE + player.charisma / 3.0) * like)
				topic = "friendly_ok"
		"intimate":
			var chance: float = clampf(0.35 + (r.affection - INTIMATE_MIN_AFFECTION) / 100.0 + player.charisma * 0.02, 0.1, 0.9) * minf(like, 1.2)
			if r.kind == Relationship.Kind.CONYUGE:
				chance = maxf(chance, 0.8)
			if like <= 0.5 or randf() >= chance:
				gain = REJECT_PENALTY
				topic = "intimate_refuse" if not r.romance else "intimate_bad"
			else:
				gain = roundi((INTIMATE_BASE + player.charisma / 2.0) * like)
				topic = "intimate_ok"
				r.romance = true
		"gift":
			player.gold -= PERSONAL_GIFT_COST
			if like <= 0.5:
				gain = DISLIKE_PENALTY
				topic = "gift_dislike"
			else:
				gain = roundi(GIFT_BASE * like)
				topic = "gift_like"
	if gain > 0:
		var bonus: float = SkillEffects.gift_multiplier(player) if kind == "gift" else 1.0 + SkillEffects.fx(player, "social")
		gain = maxi(1, roundi(gain * bonus))
	r.adjust_affection(gain)
	if gain > 0 and r.kind == Relationship.Kind.RIVAL_DUELO:
		r.adjust_grudge(-roundi(gain * GRUDGE_EASE))
	var answer := DialogueCatalog.line(topic, r.character, player, ctx)
	if not answer.is_empty():
		lines.append(answer)
	var quote := " … ".join(lines.map(func(l): return "«%s»" % l))
	var text := "%s: %s\n(Intimidad %+d — %s)" % [r.person_name, quote, r.affection - before, intimacy_label(r)]
	if r.romance and before < PROPOSAL_MIN_AFFECTION and r.affection >= PROPOSAL_MIN_AFFECTION and not is_married():
		text += "\nParece esperar una propuesta."
	relations_changed.emit()
	return text

func can_propose_love(r: Relationship) -> String:
	var player: Character = GameManager.player_character
	if player == null or not courtable(r):
		return "No disponible."
	if is_married():
		return "Ya estás %s con %s." % [_married_word(player), spouse_name]
	if not r.romance:
		return "Antes debe nacer algo más que amistad."
	if r.affection < PROPOSAL_MIN_AFFECTION:
		return "Aún no hay suficiente intimidad (%d de %d)." % [r.affection, PROPOSAL_MIN_AFFECTION]
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	if player.gold < WEDDING_COST:
		return "Necesitas %d de oro para la boda." % WEDDING_COST
	return ""

## Pedir la mano: con intimidad alta acepta; si se precipita, lo rechaza y se enfría un poco.
func propose_love(r: Relationship) -> String:
	var reason := can_propose_love(r)
	if not reason.is_empty():
		return reason
	var player: Character = GameManager.player_character
	GameManager.consume_action()
	var accept_chance: float = clampf(0.5 + (r.affection - PROPOSAL_MIN_AFFECTION) * 0.03 + _like(r, "intimate") * 0.2, 0.4, 0.98)
	if randf() >= accept_chance:
		r.adjust_affection(PROPOSAL_REJECT_AFFECTION)
		relations_changed.emit()
		return "%s: «%s»" % [r.person_name, DialogueCatalog.line("proposal_no", r.character, player, {"player": player.full_name()})]
	player.gold -= WEDDING_COST
	player.gain_honor(LOVE_MARRIAGE_HONOR)
	r.kind = Relationship.Kind.CONYUGE
	r.rival_suitor = ""
	r.adjust_grudge(-100)
	spouse_name = r.person_name
	spouse_family = ""
	var lord_text := ""
	for lord: Relationship in lords():
		if lord.kingdom == r.kingdom:
			lord.adjust(LOVE_FAMILY_AFFINITY)
			lord_text = " %s celebra la unión (afinidad %+d)." % [lord.person_name, LOVE_FAMILY_AFFINITY]
			break
	# Los demás amores se enfrían: ahora estás comprometido.
	for other: Relationship in relations:
		if other != r and other.romance:
			other.romance = false
			other.rival_suitor = ""
	relations_changed.emit()
	return "%s: «%s»\nOs casáis por amor ante toda la corte (honor %+d).%s" % [
		r.person_name, DialogueCatalog.line("proposal_yes", r.character, player, {"player": player.full_name()}),
		LOVE_MARRIAGE_HONOR, lord_text]

# Un duelo contra el pretendiente rival decide a quién prefiere tu amor.
func _settle_suitor_duel(rival_name: String, player_won: bool) -> String:
	for r: Relationship in relations:
		if r.rival_suitor != rival_name:
			continue
		r.rival_suitor = ""
		var gain := SUITOR_DUEL_AFFECTION if player_won else -SUITOR_DUEL_AFFECTION / 2
		# A los piadosos no les gusta que se derrame sangre por ellos.
		if player_won and r.character != null and r.character.personality == Character.Personality.PIADOSO:
			gain = -SUITOR_DUEL_AFFECTION / 2
		r.adjust_affection(gain)
		if player_won:
			return " %s ya no compite por %s (intimidad %+d)." % [rival_name, r.person_name, gain]
		return " %s presume ante %s de su victoria (intimidad %+d)." % [rival_name, r.person_name, gain]
	return ""

# --- Retos a duelo a la gente de tu zona ---

func _power(c: Character) -> int:
	return c.combat + c.defense

## Motivo por el que no puedes retar a alguien ("" si puedes proponerlo; aun así puede rechazarlo).
func can_challenge(r: Relationship) -> String:
	var player: Character = GameManager.player_character
	if player == null or not sociable(r):
		return "No disponible."
	if r.kind == Relationship.Kind.CONYUGE or r.person_name in retinue:
		return "No vas a batirte con los tuyos."
	if not in_area(r):
		return "Solo puedes retar a quien esté en tu zona (tu reino)."
	if not player.can_fight_duels() or player.is_wounded():
		return "No estás en condiciones de batirte."
	if r.character.is_wounded():
		return "%s se recupera de sus heridas." % r.person_name
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	return ""

## Propone un duelo. Devuelve {accepted: bool, text: String, rival: Character}.
## Quien te supera mucho en rango lo rechaza si no tienes fama; quien te teme puede negarse.
func challenge(r: Relationship) -> Dictionary:
	var reason := can_challenge(r)
	if not reason.is_empty():
		return {"accepted": false, "text": reason}
	var player: Character = GameManager.player_character
	GameManager.consume_action()
	var rival := r.character
	var ctx := {"player": player.full_name(), "rank": player.role_name()}
	var rank_gap: int = rival.role - player.role
	if rival.role == Character.Role.CAMPESINO:
		return {"accepted": false, "text": "%s: «%s»\n(Un campesino no se bate en duelo.)" % [
			r.person_name, DialogueCatalog.line("challenge_refuse_fear", rival, player, ctx)]}
	if rank_gap >= CHALLENGE_RANK_GAP and player.fame < CHALLENGE_FAME_PER_RANK * (rank_gap - 1):
		return {"accepted": false, "text": "%s: «%s»\n(Necesitas al menos %d de fama para que alguien de su rango acepte.)" % [
			r.person_name, DialogueCatalog.line("challenge_refuse_rank", rival, player, ctx), CHALLENGE_FAME_PER_RANK * (rank_gap - 1)]}
	var bold: bool = rival.personality in [Character.Personality.ARROGANTE] or Character.Personality.keys().has("VALIENTE") and rival.personality == Character.Personality.get("VALIENTE")
	if _power(player) - _power(rival) >= FEAR_POWER_GAP and not bold and randf() < FEAR_REFUSE_CHANCE:
		player.add_fame(1)
		return {"accepted": false, "text": "%s: «%s»\n(Se niega por miedo. Tu fama crece un poco.)" % [
			r.person_name, DialogueCatalog.line("challenge_refuse_fear", rival, player, ctx)]}
	rival.current_health = rival.max_health
	rival.current_stamina = rival.max_stamina
	rival.current_morale = rival.max_morale
	return {"accepted": true, "rival": rival, "text": "%s: «%s»" % [r.person_name, DialogueCatalog.line("challenge_accept", rival, player, ctx)]}

# --- Séquito y compañeros de facción ---

func max_retinue() -> int:
	var player: Character = GameManager.player_character
	return RETINUE_SIZE.get(player.role, 0) if player != null else 0

func retinue_members() -> Array[Relationship]:
	var result: Array[Relationship] = []
	for person_name in retinue:
		var r := get_relation(person_name)
		if r != null and r.character != null:
			result.append(r)
	return result

func can_invite(r: Relationship) -> String:
	var player: Character = GameManager.player_character
	if player == null or not sociable(r):
		return "No disponible."
	if r.person_name in retinue:
		return "Ya forma parte de tu séquito."
	if retinue.size() >= max_retinue():
		return "Tu séquito está completo (%d de %d para un %s)." % [retinue.size(), max_retinue(), player.role_name()]
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	if r.kind != Relationship.Kind.CONYUGE:
		if r.affection < RETINUE_MIN_AFFECTION:
			return "Necesitas más intimidad (%d de %d)." % [r.affection, RETINUE_MIN_AFFECTION]
		var req: Array = RETINUE_REQUIREMENTS.get(r.character.role, [0, 0])
		if player.fame < req[0] or player.honor < req[1]:
			return "Alguien de su rango solo sigue a quien tiene %d de fama y %d de honor." % [req[0], req[1]]
		if r.kind == Relationship.Kind.RIVAL_DUELO and r.rivalry_stage() in [Relationship.RivalryStage.RIVAL, Relationship.RivalryStage.NEMESIS]:
			return "Te guarda demasiado rencor."
	return ""

func invite_to_retinue(r: Relationship) -> String:
	var reason := can_invite(r)
	if not reason.is_empty():
		return reason
	var player: Character = GameManager.player_character
	GameManager.consume_action()
	retinue.append(r.person_name)
	relations_changed.emit()
	return "%s: «%s»\n%s se une a tu séquito (paga: %d de oro al mes)." % [
		r.person_name, DialogueCatalog.line("retinue_join", r.character, player, {"player": player.full_name()}),
		r.person_name, RETINUE_UPKEEP]

func dismiss_from_retinue(r: Relationship) -> String:
	retinue.erase(r.person_name)
	r.adjust_affection(-5)
	relations_changed.emit()
	return "%s deja tu séquito." % r.person_name

## Quienes pueden luchar en duelo en tu lugar (campeones): miembros del séquito sanos y con armas.
func duel_champions() -> Array[Character]:
	var result: Array[Character] = []
	for r: Relationship in retinue_members():
		var c := r.character
		if c.role != Character.Role.CAMPESINO and not c.is_wounded() and c.current_health > c.max_health * 0.5:
			result.append(c)
	return result

## Compañeros que lideran unidades en tus batallas: tu séquito; si no tienes, tu señor te presta
## gente de tu reino (compañeros de facción, menos leales: pelean con menos moral).
func battle_companions() -> Array[Character]:
	var result: Array[Character] = []
	for r: Relationship in retinue_members():
		if r.character.role != Character.Role.CAMPESINO and not r.character.is_wounded():
			r.character.remove_meta("faction_companion")
			result.append(r.character)
	if not result.is_empty():
		return result
	var liege := get_relation(liege_name)
	if liege != null and liege.affinity < FACTION_MIN_LIEGE_AFFINITY:
		return result
	var candidates: Array[Relationship] = []
	for r: Relationship in courtiers(GameManager.player_kingdom) + commoners(GameManager.player_kingdom):
		if r.character != null and r.character.role != Character.Role.CAMPESINO and not r.character.is_wounded():
			candidates.append(r)
	candidates.sort_custom(func(a: Relationship, b: Relationship) -> bool: return _power(a.character) > _power(b.character))
	for r: Relationship in candidates.slice(0, FACTION_COMPANIONS):
		r.character.set_meta("faction_companion", true)
		result.append(r.character)
	return result

## Frase con la que un compañero se presenta antes de la batalla.
func companion_line(c: Character) -> String:
	var topic := "faction_companion" if c.has_meta("faction_companion") else "retinue_battle"
	return DialogueCatalog.line(topic, c, GameManager.player_character, {"player": GameManager.player_character.full_name()})

# --- Paso del mes: la intimidad se enfría, el séquito cobra, aparecen pretendientes ---

func _on_month_passed(_month: int, _year: int) -> void:
	if not GameManager.is_game_active:
		return
	var now := GameManager.months_elapsed()
	var player: Character = GameManager.player_character
	for r: Relationship in relations:
		if not sociable(r) or r.affection <= 0 or r.kind == Relationship.Kind.CONYUGE:
			continue
		if r.last_courted_month < now - DECAY_GRACE_MONTHS:
			var leal: bool = r.character != null and r.character.personality == Character.Personality.LEAL
			r.adjust_affection(-((ROMANCE_DECAY_LEAL if leal else ROMANCE_DECAY) if r.romance else FRIEND_DECAY))
		if not r.romance:
			continue
		if not r.rival_suitor.is_empty():
			r.adjust_affection(-SUITOR_MONTHLY_DECAY)
		elif r.affection >= SUITOR_MIN_AFFECTION and not is_married() and randf() < SUITOR_CHANCE:
			r.rival_suitor = _pick_suitor_for(r)
	_pay_retinue(player)
	if GameManager.pending_event.is_empty():
		GameManager.pending_event = roll_social_event()
	relations_changed.emit()

func _pay_retinue(player: Character) -> void:
	if player == null:
		return
	for r: Relationship in retinue_members():
		if player.gold >= RETINUE_UPKEEP:
			player.gold -= RETINUE_UPKEEP
			continue
		r.adjust_affection(RETINUE_UNPAID_AFFECTION)
		if r.affection < RETINUE_LEAVE_AFFECTION:
			retinue.erase(r.person_name)
			retinue_news.append("%s abandona tu séquito: no has podido pagarle." % r.person_name)
		else:
			retinue_news.append("%s no ha cobrado este mes y empieza a dudar de ti." % r.person_name)

# Pretendiente rival: si es posible, alguien que ya te guarda rencor.
func _pick_suitor_for(beloved: Relationship) -> String:
	var candidates: Array[Relationship] = []
	for r: Relationship in duel_rivals():
		if r != beloved and r.character != null:
			candidates.append(r)
	if candidates.is_empty():
		for r: Relationship in courtiers():
			if r != beloved and r.character != null:
				candidates.append(r)
	return candidates.pick_random().person_name if not candidates.is_empty() else ""

## Evento del mes protagonizado por un rival, un amor o el cónyuge ({} si no toca ninguno).
## Tiene el mismo formato que EventCatalog, más "speaker" (quien habla), "quote" (su frase)
## y opcionalmente "target" (la relación a la que afectan los efectos) y "duel_with".
func roll_social_event() -> Dictionary:
	var player: Character = GameManager.player_character
	if player == null:
		return {}
	# Un pretendiente rival es lo más urgente.
	for r: Relationship in relations:
		if not r.rival_suitor.is_empty() and r.romance and courtable(r) and randf() < 0.5:
			var suitor := get_relation(r.rival_suitor)
			if suitor != null and suitor.character != null:
				return _suitor_event(r, suitor, player)
	var rivals := duel_rivals()
	rivals.shuffle()
	for r: Relationship in rivals:
		var stage := r.rivalry_stage()
		if stage == Relationship.RivalryStage.RESPETO:
			if randf() < SPAR_CHANCE:
				return _spar_event(r, player)
		elif stage != Relationship.RivalryStage.CONOCIDO and randf() < minf(r.grudge / RIVAL_EVENT_DIVISOR, RIVAL_EVENT_MAX_CHANCE):
			return _rival_event(r, player)
	var loves: Array[Relationship] = []
	for r: Relationship in relations:
		if courtable(r) and r.romance and r.affection >= Relationship.ROMANCE_INTEREST:
			loves.append(r)
	if not loves.is_empty() and not is_married() and randf() < ROMANCE_EVENT_CHANCE:
		return _letter_event(loves.pick_random(), player)
	var spouse := spouse_relation()
	if spouse != null and spouse.character != null and randf() < SPOUSE_EVENT_CHANCE:
		return _spouse_event(spouse, player)
	return {}

func _quote(topic: String, speaker: Character, player: Character) -> String:
	return DialogueCatalog.line(topic, speaker, player, {"player": player.full_name()})

func _rival_event(r: Relationship, player: Character) -> Dictionary:
	var stage := r.rivalry_stage()
	var refuse_honor: int = -RIVAL_REFUSE_HONOR[stage]
	var c := r.character
	var roll := randf()
	if c.personality == Character.Personality.ASTUTO and roll < 0.4:
		return {"id": "rival_robo", "title": "Una bolsa menos", "speaker": r.person_name,
			"quote": _quote("rival_rumor", c, player),
			"text": "Alguien ha vaciado parte de tus arcas durante la noche. Todo apunta a %s." % r.person_name,
			"options": [
				{"label": "Investigar el robo", "chance": 0.5, "chance_stat": "strategy",
					"success": {"effects": {"honor": 3, "grudge": 10}, "result": "Encuentras pruebas: %s queda en evidencia ante la corte." % r.person_name},
					"failure": {"effects": {"gold": -40, "honor": -2}, "result": "No hallas nada y el oro no aparece."}},
				{"label": "Asumir la pérdida", "effects": {"gold": -40}, "result": "Te tragas el orgullo y reforzarás los cerrojos."},
			]}
	if c.personality != Character.Personality.PIADOSO and roll < 0.35:
		return {"id": "rival_rumor", "title": "Rumores en la corte", "speaker": r.person_name,
			"quote": _quote("rival_rumor", c, player),
			"text": "Las malas lenguas trabajan contra ti, y todas llevan a %s." % r.person_name,
			"options": [
				{"label": "Desmentirlo en público", "chance": 0.5, "chance_stat": "charisma",
					"success": {"effects": {"honor": 3, "grudge": 5}, "result": "Tu palabra pesa más que los chismes."},
					"failure": {"effects": {"honor": -4}, "result": "Nadie te cree y el rumor se extiende."}},
				{"label": "Exigir satisfacción con las armas", "requires": {"healthy": true}, "start_duel": true, "effects": {},
					"result": "Retas a %s a un duelo para callar sus mentiras." % r.person_name},
				{"label": "Ignorarlo", "effects": {"honor": -2}, "result": "El rumor se apaga solo… casi del todo."},
			]}
	return {"id": "rival_reto", "title": "Un reto público", "speaker": r.person_name,
		"quote": _quote("rival_challenge", c, player),
		"text": "%s (%s) te desafía ante toda la corte." % [r.person_name, r.rivalry_text().to_lower()],
		"options": [
			{"label": "Aceptar el duelo", "requires": {"healthy": true}, "start_duel": true, "effects": {},
				"result": "Aceptas. La corte se agolpa para ver el combate."},
			{"label": "Rechazar el reto", "effects": {"honor": refuse_honor, "grudge": 5},
				"result": "Rechazas el reto. Unos te llaman prudente; otros, cobarde."},
		]}

func _spar_event(r: Relationship, player: Character) -> Dictionary:
	return {"id": "rival_entreno", "title": "Un viejo rival te ofrece entrenar", "speaker": r.person_name,
		"quote": _quote("duel_open_respect", r.character, player),
		"text": "%s, que ya te respeta, propone unas semanas de práctica juntos." % r.person_name,
		"options": [
			{"label": "Aceptar el entrenamiento", "chance": 0.6, "chance_stat": "combat",
				"success": {"effects": {"combat": 1, "grudge": -5}, "result": "Aprendéis el uno del otro. Tu esgrima mejora."},
				"failure": {"effects": {"grudge": -5}, "result": "Buenas jornadas de práctica, aunque sin grandes avances."}},
			{"label": "Declinar con cortesía", "effects": {}, "result": "Quedáis para otra ocasión."},
		]}

func _letter_event(r: Relationship, player: Character) -> Dictionary:
	return {"id": "carta_amor", "title": "Una carta perfumada", "speaker": r.person_name,
		"quote": _quote("love_letter", r.character, player),
		"text": "%s te ha escrito una carta." % r.person_name,
		"options": [
			{"label": "Responder con ternura", "effects": {"affection": 8}, "result": "Tu respuesta arranca una sonrisa al otro lado."},
			{"label": "Visitarle en persona (20 de oro)", "requires": {"gold": 20}, "effects": {"gold": -20, "affection": 14},
				"result": "Pasáis la tarde juntos. La corte empieza a murmurar."},
			{"label": "Ignorar la carta", "effects": {"affection": -6}, "result": "La carta queda sin respuesta."},
		]}

func _suitor_event(beloved: Relationship, suitor: Relationship, player: Character) -> Dictionary:
	return {"id": "pretendiente", "title": "Un pretendiente rival", "speaker": suitor.person_name,
		"target": beloved.person_name, "duel_with": suitor.person_name,
		"quote": DialogueCatalog.line("suitor_rival", suitor.character, player, {"player": player.full_name()}),
		"text": "%s también corteja a %s, y no piensa ceder." % [suitor.person_name, beloved.person_name],
		"options": [
			{"label": "Retar al pretendiente a duelo", "requires": {"healthy": true}, "start_duel": true, "effects": {},
				"result": "Las espadas decidirán quién merece a %s." % beloved.person_name},
			{"label": "Superarle en regalos (40 de oro)", "requires": {"gold": 40}, "effects": {"gold": -40, "affection": 10, "clear_suitor": 1},
				"result": "Tu generosidad deja en ridículo al otro pretendiente."},
			{"label": "Dejarlo estar", "effects": {"affection": -8}, "result": "Prefieres no competir. Quizá te arrepientas."},
		]}

func _spouse_event(spouse: Relationship, player: Character) -> Dictionary:
	var options: Array
	match spouse.character.personality:
		Character.Personality.AMBICIOSO:
			options = [
				{"label": "Seguir su consejo y apretar a los arrendatarios", "effects": {"gold": 50, "honor": -3, "affection": 5}, "result": "El oro entra; el pueblo murmura."},
				{"label": "Pedirle paciencia", "effects": {"affection": -4}, "result": "Tu cónyuge suspira, nada convencido."},
			]
		Character.Personality.PRUDENTE:
			options = [
				{"label": "Escuchar su plan", "effects": {"strategy": 1, "affection": 3}, "result": "Su consejo resulta sensato. Aprendes algo."},
				{"label": "Hoy no hay tiempo", "effects": {"affection": -3}, "result": "Otra vez será."},
			]
		Character.Personality.ARROGANTE:
			options = [
				{"label": "Organizar un banquete (60 de oro)", "requires": {"gold": 60}, "effects": {"gold": -60, "honor": 4, "affection": 6}, "result": "El banquete es la comidilla del reino."},
				{"label": "Negarse a semejante derroche", "effects": {"affection": -6}, "result": "Tu cónyuge no te habla en tres días."},
			]
		Character.Personality.PIADOSO:
			options = [
				{"label": "Apoyar su caridad (20 de oro)", "requires": {"gold": 20}, "effects": {"gold": -20, "honor": 4, "affection": 4}, "result": "El pueblo bendice a tu familia."},
				{"label": "Agradecérselo de palabra", "effects": {"affection": 1}, "result": "Tu cónyuge sonríe con paciencia."},
			]
		Character.Personality.ASTUTO:
			options = [
				{"label": "Escuchar los rumores", "effects": {"charisma": 1, "affection": 3}, "result": "Sabes ahora quién debe qué a quién en la corte."},
				{"label": "No meterse en intrigas", "effects": {"honor": 1}, "result": "Prefieres mantener las manos limpias."},
			]
		_:
			options = [
				{"label": "Agradecer su apoyo", "effects": {"honor": 2, "affection": 5}, "result": "Os sentís más unidos que nunca."},
				{"label": "Seguir con tus asuntos", "effects": {}, "result": "La vida sigue su curso."},
			]
	return {"id": "conyuge", "title": "Asuntos de familia", "speaker": spouse.person_name,
		"quote": _quote("spouse_month", spouse.character, player),
		"text": "%s quiere hablar contigo." % spouse.person_name, "options": options}

# --- API para otros sistemas (WorldEvents, MissionData) ---

## Un señor muere o abdica: su heredero ocupa su lugar en sus castillos y en la relación con el jugador.
## Devuelve el nombre del heredero.
func replace_lord(old_name: String, heir: Character) -> String:
	var heir_name := heir.full_name()
	for c: Castle in MapData.castles:
		if c.owner_name == old_name:
			c.owner_name = heir_name
	var r := get_relation(old_name)
	if r != null:
		r.person_name = heir_name
		r.character = heir
		r.affinity = int(r.affinity / 2)   # el heredero hereda solo parte de la relación
		r.allied = false
	if liege_name == old_name:
		liege_name = heir_name
	if spouse_family == old_name:
		spouse_family = heir_name
	relations_changed.emit()
	return heir_name

## Tu señor te ofrece en matrimonio político con alguien de su casa (sin dote).
## Devuelve el texto del resultado, o el motivo por el que no es posible.
func arrange_political_marriage(lord_name: String) -> String:
	var player: Character = GameManager.player_character
	var r := get_relation(lord_name)
	if player == null or r == null or r.kind != Relationship.Kind.SENOR:
		return "No disponible."
	if is_married():
		return "Ya estás %s con %s." % [_married_word(player), spouse_name]
	var names: Array = SPOUSE_NAMES_FOR_MALE_PLAYER if player.gender == CharacterEnums.Gender.MASCULINO else SPOUSE_NAMES_FOR_FEMALE_PLAYER
	var spouse_first: String = names.pick_random()
	spouse_name = "%s %s" % [spouse_first, family_name_of(lord_name)]
	spouse_family = lord_name
	r.adjust(MARRIAGE_AFFINITY)
	r.allied = true
	_add_spouse_relation(spouse_first, family_name_of(lord_name), r.kingdom, _spouse_gender(player))
	relations_changed.emit()
	return "Por voluntad de %s te casas con %s. Su casa es ahora la tuya." % [lord_name, spouse_name]

## Estado extra para el guardado (las relaciones en sí van en SaveGame.relations).
func save_state() -> Dictionary:
	return {"retinue": retinue.duplicate(), "last_victory_month": last_victory_month}

func load_state(data: Dictionary) -> void:
	retinue.clear()
	for person_name in data.get("retinue", []):
		retinue.append(str(person_name))
	last_victory_month = int(data.get("last_victory_month", -1))
	retinue_news.clear()
