extends Node
# Capturas: tras una batalla (o un duelo hostil) los vencidos con nombre pueden caer prisioneros.
# - Los presos del jugador esperan su decisión (pestaña Prisioneros): reclutar, esclavizar, vender a
#   su facción, liberar o ejecutar.
# - Los presos de la IA se resuelven solos con los meses (rescate, liberación o ejecución); si el preso
#   es de los tuyos (séquito o cónyuge), su captor te pide rescate con un evento.
# - Si el capturado eres tú, tu captor decide según su carácter y lo que piensa de ti: rescate,
#   mazmorra (con intentos de fuga) o ejecución (DynastyData.on_player_executed).
# Los siervos (presos esclavizados) van con tu séquito sin ocupar plaza, dan oro al mes y se pueden vender.

signal captures_changed

# --- Probabilidad de captura según cómo acabó cada jefe ---
const CAPTURE_CHANCE := {"destroyed": 0.45, "routed": 0.25, "standing": 0.15, "withdrew": 0.05, "left": 0.01}
const AUTO_CAPTURE_CHANCE := 0.15      # batallas que se resuelven solas: el señor vencido
const DUEL_CAPTURE_CHANCE := 0.2       # duelo de campaña hostil (eventos, enemigos, rivales)

# --- Tus prisioneros ---
const RECRUIT_BASE := 0.35
const RECRUIT_PER_AFFECTION := 0.005
const RECRUIT_PERSONALITY := {Character.Personality.COBARDE: 0.2, Character.Personality.AMBICIOSO: 0.1,
	Character.Personality.ASTUTO: 0.1, Character.Personality.LEAL: -0.2, Character.Personality.HONORABLE: -0.15,
	Character.Personality.ARROGANTE: -0.1}
const RECRUIT_MIN := 0.05
const RECRUIT_MAX := 0.9
const RECRUIT_AFFECTION := 30          # intimidad mínima con quien acepta servirte
const RECRUIT_FAIL_GRUDGE := 5
const ENSLAVE_HONOR := 10
const ENSLAVE_AFFINITY := 20           # su reino no lo perdona
const ENSLAVE_AFFECTION := 20          # el siervo empieza resentido
const ENSLAVE_GRUDGE := 20
const SERF_DISAPPROVAL := 5            # piadosos y honorables de tu casa lo desaprueban
const SERF_MAX := 4
const SERF_GOLD_BASE := 6              # oro al mes por siervo (+1 por cada 10 de intimidad)
const SERF_GOLD_AFFECTION_DIV := 10
const SERF_ESCAPE_CHANCE := 0.04       # al mes, si te detesta (intimidad < SERF_ESCAPE_AFFECTION)
const SERF_ESCAPE_AFFECTION := 20
const SERF_SELL_BASE := 40
const SERF_SELL_PER_RANK := 20
const SERF_SELL_HONOR := 5
const MANUMIT_HONOR := 3
const MANUMIT_AFFECTION := 15
const EXECUTE_HONOR := 15
const EXECUTE_HONOR_OUTLAW := 3        # ejecutar a un salteador apenas mancha
const EXECUTE_AFFINITY := 30
const EXECUTE_HOUSE_GRUDGE := 40
const FREE_HONOR := 5
const FREE_AFFECTION := 10
const FREE_AFFINITY := 5
const RANSOM_BASE := 50
const RANSOM_PER_RANK := 40
const RANSOM_PER_FAME := 2
const RANSOM_AFFINITY := 2

# --- Presos en manos de la IA ---
const AI_RANSOM_CHANCE := 0.25         # al mes, su gente paga
const AI_EXECUTE_CHANCE := 0.01
const AI_EXECUTE_CRUEL := 0.06
const AI_EXECUTE_WAR := 0.02
const AI_MAX_HOLD := 6                 # meses: después lo sueltan
const REFUSED_EXECUTE_CHANCE := 0.5    # si no pagas por los tuyos, un captor cruel o hostil los ejecuta
const RETURN_UNPAID_AFFECTION := -15   # vuelve, pero no olvida que no pagaste
const RETURN_PAID_AFFECTION := 10

# --- Si te capturan a ti ---
const HATE_AFFINITY := -50
const EXECUTE_IF_HATED := 0.6
const EXECUTE_IF_CRUEL := 0.3
const EXECUTE_IF_WAR := 0.05
const EXECUTE_IF_OUTLAW := 0.15
const RELEASE_MIN_AFFINITY := 20       # un captor honorable o generoso que te aprecia te suelta bajo palabra
const PRISON_MIN_MONTHS := 3
const PRISON_MAX_MONTHS := 6
const PLAYER_RANSOM_BASE := 100
const PLAYER_RANSOM_PER_RANK := 80
const PLAYER_RANSOM_PER_FAME := 3
const GREEDY := [Character.Personality.AMBICIOSO, Character.Personality.ASTUTO]
const GREEDY_RANSOM_CHANCE := 1.0
const RANSOM_CHANCE := 0.7
const PLEA_BASE := 0.15                # suplicar clemencia: +2% por punto de Carisma
const PLEA_PER_CHARISMA := 0.02
const ESCAPE_BASE := 0.12
const ESCAPE_PER_POINT := 0.015        # (Estrategia + Combate − 20)
const ESCAPE_MIN := 0.05
const ESCAPE_MAX := 0.5
const ESCAPE_FAIL_MONTHS := 2
const ESCAPE_FAIL_HEALTH := 20
const CAPTURE_FAME := -3

var prisoners: Array = []          # Dictionary por preso (ver _record)
var serfs: Array[String] = []      # nombres de tus siervos (van con tu séquito)
var captivity: Dictionary = {}     # tu cautiverio: {who, captor, captor_kingdom, captor_personality, captor_castle, stage, decision, ransom, months_left}
var _queue: Array = []             # eventos que esperan un hueco (una decision por mes)

func _ready() -> void:
	GameManager.game_started.connect(func(_c: Character): reset())
	GameManager.turn_advanced.connect(_on_month_passed)
	GameManager.event_option_chosen.connect(_on_option_chosen)

func reset() -> void:
	prisoners.clear()
	serfs.clear()
	captivity = {}
	_queue.clear()
	captures_changed.emit()

# --- Consultas ---

func is_prisoner(person_name: String) -> bool:
	return _find(person_name) != null

func is_serf(person_name: String) -> bool:
	return person_name in serfs

## ¿Eres tú quien está preso ahora mismo?
func is_captive() -> bool:
	var player: Character = GameManager.player_character
	return player != null and not captivity.is_empty() and captivity.get("who", "") == player.full_name()

func captor_name() -> String:
	return str(captivity.get("captor", "")) if is_captive() else ""

## Texto corto para la barra del mapa: «⛓ Preso de X (N meses)».
func captive_text() -> String:
	if not is_captive():
		return ""
	if captivity.get("stage", "") == "prison":
		return "⛓ Preso de %s (%d %s)" % [captivity.captor, int(captivity.months_left), "mes" if int(captivity.months_left) == 1 else "meses"]
	return "⛓ Preso de %s" % captivity.captor

## Presos que tienes tú.
func player_prisoners() -> Array:
	return prisoners.filter(func(p: Dictionary) -> bool: return p.by_player)

## Los tuyos (séquito, cónyuge) en manos de otros.
func held_own_people() -> Array:
	return prisoners.filter(func(p: Dictionary) -> bool: return not p.by_player and (p.was_retinue or p.was_spouse))

func relation_of(p: Dictionary) -> Relationship:
	return RelationsData.get_relation(str(p.name))

func _find(person_name: String) -> Variant:
	for p: Dictionary in prisoners:
		if p.name == person_name:
			return p
	return null

func _player_name() -> String:
	var player: Character = GameManager.player_character
	return player.full_name() if player != null else ""

static func _female(c: Character) -> bool:
	return c != null and c.gender == CharacterEnums.Gender.FEMENINO

static func _g(c: Character, masc: String, fem: String) -> String:
	return fem if _female(c) else masc

# --- Capturas ---

## Tras una batalla táctica: los jefes vencidos pueden caer presos. ctx: {own_share (0..1) parte de tus
## hombres en tu bando (batallas ajenas), retreated (te retiraste a tiempo)}. Devuelve el texto para el cartel.
func after_battle(battle: BattleManager, winner_side: int, ctx: Dictionary = {}) -> String:
	if not GameManager.is_game_active or battle == null:
		return ""
	var player: Character = GameManager.player_character
	var loser_side := battle._other_side(winner_side)
	var player_won := winner_side == battle.player_side
	var lines: Array[String] = []
	var winner_cmd: Character = battle._commander(winner_side)
	if winner_cmd == null or not BattleManager._named(winner_cmd):
		winner_cmd = battle.general_of(winner_side)
	var player_commands := player_won and (battle._commander(battle.player_side) == player or not battle.has_allies())
	var own_share: float = clampf(float(ctx.get("own_share", 1.0)), 0.0, 1.0)
	for entry: Array in battle.capture_fates(loser_side):
		var c: Character = entry[0]
		var fate: String = entry[1]
		if c == null or not c.is_alive():
			continue
		if c == player and bool(ctx.get("retreated", false)):
			fate = "withdrew"
		if randf() >= CAPTURE_CHANCE.get(fate, 0.0):
			continue
		if c == player:
			if DynastyData.needs_succession():
				continue
			lines.append(capture_player(winner_cmd, battle.location_name))
			continue
		var by_player := player_won and (player_commands or randf() < own_share)
		var text := capture(c, winner_cmd, by_player)
		if not text.is_empty():
			lines.append(text)
	return "\n".join(lines)

## Duelo de campaña hostil: el vencido puede caer preso del vencedor. owner: el jugador (aunque luche su campeón).
func after_duel(owner: Character, fighter: Character, foe: Character, winner: Character, hostile: bool) -> String:
	if not hostile or winner == null or not GameManager.is_game_active or randf() >= DUEL_CAPTURE_CHANCE:
		return ""
	var loser := foe if winner == fighter else fighter
	if loser == null or not loser.is_alive():
		return ""
	if winner == fighter:
		return capture(foe, owner, true)
	if loser == owner:
		return capture_player(foe, "")
	return capture(loser, foe, false)   # tu campeón cae en manos del vencedor

## Batalla que se resuelve sola entre señores: el vencido puede caer preso del vencedor.
func after_auto_battle(winner_name: String, loser_name: String) -> void:
	if not GameManager.is_game_active or randf() >= AUTO_CAPTURE_CHANCE:
		return
	var loser: Character = RelationsData.character_of(loser_name)
	var winner: Character = RelationsData.character_of(winner_name)
	if loser == null or winner == null or loser == GameManager.player_character or is_prisoner(loser_name):
		return
	capture(loser, winner, false)

## Captura a "c" (que no eres tú). captor: quien lo retiene (null o el jugador si by_player). Devuelve el texto.
func capture(c: Character, captor: Character, by_player: bool) -> String:
	if c == null or is_prisoner(c.full_name()) or is_serf(c.full_name()):
		return ""
	var r := RelationsData.get_relation(c.full_name())
	var temp := false
	if r == null:
		# Alguien sin ficha en el mundo (un salteador, un rival de evento): se le abre una mientras sea preso.
		r = Relationship.new()
		r.person_name = c.full_name()
		r.kind = Relationship.Kind.CORTESANO
		r.kingdom = -1
		r.character = c
		RelationsData.relations.append(r)
		temp = true
	var p := _record(r, captor, by_player, temp)
	if r.person_name in RelationsData.retinue:
		RelationsData.retinue.erase(r.person_name)
		p.was_retinue = true
	if r.kind == Relationship.Kind.CONYUGE:
		p.was_spouse = true
	if RelationsData.designated_champion == r.person_name:
		RelationsData.designated_champion = ""
	prisoners.append(p)
	var text: String
	if by_player:
		text = "⛓ %s cae en tus manos: es tu %s." % [r.person_name, _g(c, "prisionero", "prisionera")]
		WorldEvents.record("%s, %s tuyo." % [r.person_name, _g(c, "prisionero", "prisionera")], "", true)
	else:
		var who: String = p.captor
		text = "⛓ %s cae %s de %s." % [r.person_name, _g(c, "prisionero", "prisionera"), who]
		if p.was_retinue or p.was_spouse:
			WorldEvents.notify("Uno de los tuyos, preso", text)
		elif r.person_name == RelationsData.liege_name:
			WorldEvents.notify("Tu señor, preso", text)
		WorldEvents.record(text, "", p.was_retinue or p.was_spouse)
	RelationsData.relations_changed.emit()
	captures_changed.emit()
	return text

func _record(r: Relationship, captor: Character, by_player: bool, temp: bool) -> Dictionary:
	return {"name": r.person_name, "by_player": by_player,
		"captor": _player_name() if by_player else (captor.full_name() if captor != null else "unos desconocidos"),
		"captor_kingdom": _kingdom_of_name(captor.full_name()) if captor != null and not by_player else -1,
		"captor_personality": captor.personality if captor != null and not by_player else -1,
		"kingdom": _kingdom_of(r), "since": GameManager.months_elapsed(), "months": 0, "temp": temp,
		"was_retinue": false, "was_spouse": false, "recruit_month": -1, "requested": false, "refused": false}

func _kingdom_of(r: Relationship) -> int:
	if r == null:
		return -1
	if r.kingdom >= 0:
		return r.kingdom
	var castles := RelationsData.castles_of(r.person_name)
	return castles[0].kingdom if not castles.is_empty() else -1

func _kingdom_of_name(person_name: String) -> int:
	return _kingdom_of(RelationsData.get_relation(person_name))

# --- Tus prisioneros: lo que puedes hacer con ellos ---

func is_lord(p: Dictionary) -> bool:
	var r := relation_of(p)
	return r != null and r.kind == Relationship.Kind.SENOR

func recruit_chance(p: Dictionary) -> float:
	var r := relation_of(p)
	if r == null or r.character == null:
		return 0.0
	var chance := RECRUIT_BASE + r.affection * RECRUIT_PER_AFFECTION + float(RECRUIT_PERSONALITY.get(r.character.personality, 0.0))
	if p.temp:
		chance += 0.1   # un salteador sin señor se vende al mejor postor
	return clampf(chance, RECRUIT_MIN, RECRUIT_MAX)

func recruit_blocker(p: Dictionary) -> String:
	if is_lord(p):
		return "Un señor no sirve a nadie."
	if int(p.recruit_month) == GameManager.months_elapsed():
		return "Ya lo intentaste este mes."
	var counts := RelationsData.retinue_counts()
	if not RelationsData._retinue_fits(counts.others + 1, counts.intimates):
		return "No te quedan plazas en el séquito."
	return ""

func recruit(p: Dictionary) -> String:
	var reason := recruit_blocker(p)
	if not reason.is_empty():
		return reason
	var r := relation_of(p)
	p.recruit_month = GameManager.months_elapsed()
	if randf() >= recruit_chance(p):
		r.adjust_grudge(RECRUIT_FAIL_GRUDGE)
		return "%s: «%s»" % [r.person_name, DialogueCatalog.line("prisoner_refuse", r.character, GameManager.player_character)]
	_release_record(p)
	p.temp = false
	r.adjust_affection(maxi(0, RECRUIT_AFFECTION - r.affection))
	RelationsData.retinue.append(r.person_name)
	_changed()
	return "%s: «%s»\n%s se une a tu séquito." % [r.person_name,
		DialogueCatalog.line("prisoner_join", r.character, GameManager.player_character), r.person_name]

func enslave_blocker(p: Dictionary) -> String:
	if is_lord(p):
		return "Un señor no se vende como siervo."
	if serfs.size() >= SERF_MAX:
		return "Ya tienes %d siervos." % SERF_MAX
	return ""

func enslave(p: Dictionary) -> String:
	var reason := enslave_blocker(p)
	if not reason.is_empty():
		return reason
	var player: Character = GameManager.player_character
	var r := relation_of(p)
	_release_record(p)
	p.temp = false
	player.honor = maxi(0, player.honor - ENSLAVE_HONOR)
	_kingdom_affinity(int(p.kingdom), -ENSLAVE_AFFINITY)
	r.affection = maxi(0, r.affection - ENSLAVE_AFFECTION)
	r.adjust_grudge(ENSLAVE_GRUDGE)
	serfs.append(r.person_name)
	RelationsData.retinue.append(r.person_name)
	var disapprove := _court_disapproves()
	_changed()
	var text := "%s pasa a ser tu %s (−%d de honor)." % [r.person_name, _g(r.character, "siervo", "sierva"), ENSLAVE_HONOR]
	if not disapprove.is_empty():
		text += " " + disapprove
	WorldEvents.record(text, "", true)
	return text

func ransom_value(p: Dictionary) -> int:
	var r := relation_of(p)
	if r == null or r.character == null or p.temp:
		return 0
	return RANSOM_BASE + r.character.rank() * RANSOM_PER_RANK + r.character.fame * RANSOM_PER_FAME

func ransom_blocker(p: Dictionary) -> String:
	return "Nadie pagaría por un salteador." if ransom_value(p) <= 0 else ""

## Vendes al preso a su facción: su gente paga el rescate y vuelve con los suyos.
func sell_to_faction(p: Dictionary) -> String:
	var reason := ransom_blocker(p)
	if not reason.is_empty():
		return reason
	var gold := ransom_value(p)
	GameManager.player_character.gold += gold
	_kingdom_affinity(int(p.kingdom), RANSOM_AFFINITY)
	var r := relation_of(p)
	_release_record(p)
	_changed()
	var text := "Su gente paga %d de oro y %s vuelve con los suyos." % [gold, r.person_name if r != null else p.name]
	WorldEvents.record(text, "", true)
	return text

func free_prisoner(p: Dictionary) -> String:
	var player: Character = GameManager.player_character
	var r := relation_of(p)
	player.gain_honor(FREE_HONOR)
	_kingdom_affinity(int(p.kingdom), FREE_AFFINITY)
	var who: String = p.name
	if r != null:
		r.adjust_affection(FREE_AFFECTION)
		r.adjust_grudge(-FREE_AFFECTION)
	_release_record(p)
	if p.temp and r != null:
		RelationsData.relations.erase(r)
	_changed()
	return "Dejas marchar a %s (+%d de honor)." % [who, FREE_HONOR]

func execute(p: Dictionary) -> String:
	var player: Character = GameManager.player_character
	var r := relation_of(p)
	var who: String = p.name
	var outlaw: bool = p.temp
	Sfx.stinger("execution", -2.0, 2.0)
	_release_record(p)
	player.honor = maxi(0, player.honor - (EXECUTE_HONOR_OUTLAW if outlaw else EXECUTE_HONOR))
	if not outlaw:
		_kingdom_affinity(int(p.kingdom), -EXECUTE_AFFINITY)
		_house_grudge(who)
	var cause := "ejecución por orden de %s" % player.full_name()
	if r != null and r.kind == Relationship.Kind.SENOR:
		WorldEvents.kill_lord(r, cause)
	elif r != null and outlaw:
		RelationsData.relations.erase(r)
		WorldEvents.record("%s es %s por orden tuya." % [who, _g(r.character, "ejecutado", "ejecutada")], "", true)
	else:
		RelationsData.on_character_died(who, cause)
	_changed()
	return "%s es %s (−%d de honor)." % [who, _g(r.character if r != null else null, "ejecutado", "ejecutada"),
		EXECUTE_HONOR_OUTLAW if outlaw else EXECUTE_HONOR]

# --- Siervos ---

func serf_gold(r: Relationship) -> int:
	return SERF_GOLD_BASE + (r.affection / SERF_GOLD_AFFECTION_DIV if r != null else 0)

func serf_price(r: Relationship) -> int:
	return SERF_SELL_BASE + (r.character.rank() * SERF_SELL_PER_RANK if r != null and r.character != null else 0)

func sell_serf(person_name: String) -> String:
	var r := RelationsData.get_relation(person_name)
	if r == null or not is_serf(person_name):
		return "No disponible."
	var player: Character = GameManager.player_character
	var price := serf_price(r)
	player.gold += price
	player.honor = maxi(0, player.honor - SERF_SELL_HONOR)
	serfs.erase(person_name)
	RelationsData.retinue.erase(person_name)
	RelationsData.occupations.erase(person_name)
	RelationsData.relations.erase(r)
	_changed()
	var text := "Vendes a %s por %d de oro (−%d de honor)." % [person_name, price, SERF_SELL_HONOR]
	WorldEvents.record(text, "", true)
	return text

func manumit(person_name: String) -> String:
	var r := RelationsData.get_relation(person_name)
	if r == null or not is_serf(person_name):
		return "No disponible."
	serfs.erase(person_name)
	RelationsData.retinue.erase(person_name)
	GameManager.player_character.gain_honor(MANUMIT_HONOR)
	r.adjust_affection(MANUMIT_AFFECTION)
	r.adjust_grudge(-MANUMIT_AFFECTION)
	_changed()
	return "%s: «%s»\nLe devuelves la libertad (+%d de honor)." % [person_name,
		DialogueCatalog.line("serf_freed", r.character, GameManager.player_character), MANUMIT_HONOR]

# --- Si te capturan ---

## Te capturan: tu captor decide (y lo verás como evento). Devuelve el texto para el cartel.
func capture_player(captor: Character, place: String) -> String:
	var player: Character = GameManager.player_character
	if player == null or is_captive():
		return ""
	var captor_name_s := captor.full_name() if captor != null else "unos salteadores"
	var r := RelationsData.get_relation(captor_name_s)
	var outlaw := r == null
	var castles := RelationsData.castles_of(captor_name_s)
	captivity = {"who": player.full_name(), "captor": captor_name_s,
		"captor_kingdom": _kingdom_of(r), "captor_personality": captor.personality if captor != null else -1,
		"captor_castle": castles[0].castle_id if not castles.is_empty() else "", "stage": "captured",
		"decision": _captor_decision(captor, r, outlaw), "ransom": player_ransom(), "months_left": 0, "plea": false}
	player.add_fame(CAPTURE_FAME)
	if not str(captivity.captor_castle).is_empty():
		TravelData.location_id = captivity.captor_castle
		TravelData.location_changed.emit(TravelData.location_id)
	_block_actions()
	var text := "⛓ Caes %s de %s%s." % [_g(player, "prisionero", "prisionera"), captor_name_s, (" en " + place) if not place.is_empty() else ""]
	WorldEvents.record(text, "", true)
	GameManager.pending_event = _captivity_event()
	captures_changed.emit()
	return text

func player_ransom() -> int:
	var player: Character = GameManager.player_character
	return PLAYER_RANSOM_BASE + player.rank() * PLAYER_RANSOM_PER_RANK + player.fame * PLAYER_RANSOM_PER_FAME

## "execute", "ransom", "prison" o "release", según el carácter del captor y lo que piensa de ti.
func _captor_decision(captor: Character, r: Relationship, outlaw: bool) -> String:
	var personality: int = captor.personality if captor != null else -1
	var hated: bool = r != null and (r.affinity <= HATE_AFFINITY or r.rivalry_stage() == Relationship.RivalryStage.NEMESIS)
	var execute_chance := EXECUTE_IF_OUTLAW if outlaw else 0.0
	if hated:
		execute_chance = EXECUTE_IF_HATED
	elif personality == Character.Personality.CRUEL:
		execute_chance = EXECUTE_IF_CRUEL
	elif r != null and r.at_war:
		execute_chance = EXECUTE_IF_WAR
	if randf() < execute_chance:
		return "execute"
	var kind_captor: bool = personality in [Character.Personality.HONORABLE, Character.Personality.GENEROSO]
	if kind_captor and r != null and r.affinity >= RELEASE_MIN_AFFINITY:
		return "release"
	var ransom_chance := GREEDY_RANSOM_CHANCE if personality in GREEDY or outlaw else RANSOM_CHANCE
	return "ransom" if randf() < ransom_chance else "prison"

func _total_gold() -> int:
	var home: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	return GameManager.player_character.gold + (home.gold if home != null else 0)

func _pay(amount: int) -> void:
	var player: Character = GameManager.player_character
	var from_purse := mini(player.gold, amount)
	player.gold -= from_purse
	var home: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	if home != null and amount > from_purse:
		home.gold = maxi(0, home.gold - (amount - from_purse))

func escape_chance() -> float:
	var player: Character = GameManager.player_character
	return clampf(ESCAPE_BASE + (player.strategy + player.combat - 20) * ESCAPE_PER_POINT, ESCAPE_MIN, ESCAPE_MAX)

func plea_chance() -> float:
	return clampf(PLEA_BASE + GameManager.player_character.charisma * PLEA_PER_CHARISMA, 0.05, 0.9)

func _captor_line(topic: String) -> String:
	var r := RelationsData.get_relation(str(captivity.get("captor", "")))
	var speaker: Character = r.character if r != null else null
	if speaker == null:
		speaker = Character.new()
		speaker.personality = int(captivity.get("captor_personality", Character.Personality.CRUEL)) if int(captivity.get("captor_personality", -1)) >= 0 else Character.Personality.CRUEL
	return DialogueCatalog.line(topic, speaker, GameManager.player_character)

func _captivity_event() -> Dictionary:
	var c: String = captivity.captor
	var ransom: int = captivity.ransom
	var pay := {"label": "Pagar el rescate (%d)" % ransom, "requires": {"total_gold": ransom},
		"result": "", "capture_action": "pay_ransom"}
	var e := {"id": "cautiverio", "speaker": c, "title": "Prisionero de %s" % c}
	match captivity.decision:
		"execute":
			e.text = "%s ordena tu ejecución al alba." % c
			e.quote = _captor_line("captor_execute")
			e.options = [{"label": "Suplicar clemencia (%d%%)" % roundi(plea_chance() * 100), "result": "", "capture_action": "plea"},
				{"label": "Afrontar tu destino", "result": "", "capture_action": "accept_death"}]
		"release":
			e.text = "%s te deja marchar bajo palabra." % c
			e.quote = _captor_line("captor_release")
			e.options = [{"label": "Dar tu palabra", "result": "", "capture_action": "released"}]
		"ransom":
			e.text = "%s pide %d de oro por tu libertad." % [c, ransom]
			e.quote = _captor_line("captor_ransom")
			e.options = [pay, {"label": "Negarte", "result": "", "capture_action": "refuse_ransom"}]
		_:
			e.text = "%s te encierra en sus mazmorras." % c
			e.quote = _captor_line("captor_prison")
			e.options = [{"label": "Aceptar tu suerte", "result": "", "capture_action": "to_prison"}]
	return e

func _prison_event() -> Dictionary:
	var c: String = captivity.captor
	var options: Array = [
		{"label": "Intentar la fuga (%d%%)" % roundi(escape_chance() * 100), "result": "", "capture_action": "escape"},
		{"label": "Esperar", "result": "", "capture_action": "wait"}]
	if captivity.decision == "ransom":
		options.insert(1, {"label": "Pagar el rescate (%d)" % captivity.ransom, "requires": {"total_gold": captivity.ransom},
			"result": "", "capture_action": "pay_ransom"})
	return {"id": "mazmorra", "speaker": c, "title": "En las mazmorras",
		"text": "Preso de %s. Quedan %d meses." % [c, int(captivity.months_left)], "options": options}

func _on_option_chosen(event: Dictionary, option: Dictionary) -> void:
	var action: String = option.get("capture_action", "")
	if action.is_empty():
		return
	event["_extra_result"] = _resolve_action(action, option)

func _resolve_action(action: String, option: Dictionary) -> String:
	var player: Character = GameManager.player_character
	match action:
		"pay_ransom":
			_pay(int(captivity.ransom))
			return _release_player("Pagas %d de oro y quedas libre." % int(captivity.ransom), false)
		"released":
			return _release_player("Quedas libre.", false)
		"refuse_ransom", "to_prison":
			_to_prison()
			return "Te encierran: %d meses." % int(captivity.months_left)
		"plea":
			captivity.plea = true
			if randf() < plea_chance():
				captivity.decision = "prison"
				_to_prison()
				return "%s se apiada: mazmorra, %d meses." % [captivity.captor, int(captivity.months_left)]
			return _execute_player()
		"accept_death":
			return _execute_player()
		"escape":
			if randf() < escape_chance():
				return _release_player("¡Te fugas!", true)
			captivity.months_left = int(captivity.months_left) + ESCAPE_FAIL_MONTHS
			player.current_health = maxi(1, player.current_health - ESCAPE_FAIL_HEALTH)
			return "Te atrapan: +%d meses y una paliza." % ESCAPE_FAIL_MONTHS
		"wait":
			return "Pasa otro mes entre rejas."
		"pay_own":
			return pay_for_own(str(option.get("person", "")))
		"refuse_own":
			return refuse_own(str(option.get("person", "")))
	return ""

func _to_prison() -> void:
	captivity.stage = "prison"
	if int(captivity.months_left) <= 0:
		captivity.months_left = randi_range(PRISON_MIN_MONTHS, PRISON_MAX_MONTHS)
	_block_actions()
	captures_changed.emit()

func _release_player(text: String, escaped: bool) -> String:
	var captor := str(captivity.get("captor", ""))
	captivity = {}
	if escaped:
		TravelData.location_id = GameManager.home_castle_id
		TravelData.location_changed.emit(TravelData.location_id)
	WorldEvents.record("Sales del cautiverio de %s." % captor, "", true)
	captures_changed.emit()
	return text

func _execute_player() -> String:
	var captor := str(captivity.get("captor", ""))
	captivity = {}
	captures_changed.emit()
	Sfx.stinger("execution", -2.0, 2.0)
	DynastyData.on_player_executed(captor)
	return "%s ordena tu ejecución." % captor

func _block_actions() -> void:
	GameManager.actions_remaining = 0
	GameManager.actions_changed.emit(0, GameManager.actions_per_turn)

# --- Los tuyos en manos ajenas: el captor pide rescate ---

func own_ransom(p: Dictionary) -> int:
	var r := relation_of(p)
	return RANSOM_BASE + (r.character.rank() * RANSOM_PER_RANK + r.character.fame * RANSOM_PER_FAME if r != null and r.character != null else 0)

func _ransom_request_event(p: Dictionary) -> Dictionary:
	var price := own_ransom(p)
	return {"id": "rescate_de_los_tuyos", "speaker": p.captor, "title": "Rescate", "target": p.name,
		"text": "%s retiene a %s y pide %d de oro." % [p.captor, p.name, price],
		"options": [
			{"label": "Pagar (%d)" % price, "requires": {"total_gold": price}, "result": "", "capture_action": "pay_own", "person": p.name},
			{"label": "Negarte", "result": "", "capture_action": "refuse_own", "person": p.name}]}

func pay_for_own(person_name: String) -> String:
	var p: Variant = _find(person_name)
	if p == null or p.by_player:
		return "Ya no está preso."
	var price := own_ransom(p)
	if _total_gold() < price:
		return "No tienes %d de oro." % price
	_pay(price)
	_return_home(p, RETURN_PAID_AFFECTION)
	return "Pagas %d de oro: %s vuelve contigo." % [price, person_name]

func refuse_own(person_name: String) -> String:
	var p: Variant = _find(person_name)
	if p == null:
		return ""
	p.refused = true
	return "Te niegas a pagar por %s." % person_name

func _return_home(p: Dictionary, affection: int) -> void:
	var r := relation_of(p)
	_release_record(p)
	if r != null:
		r.adjust_affection(affection)
		var counts := RelationsData.retinue_counts()
		var intimate := RelationsData.is_intimate(r)
		if p.was_retinue and RelationsData._retinue_fits(counts.others + (0 if intimate else 1), counts.intimates + (1 if intimate else 0)):
			RelationsData.retinue.append(r.person_name)
	WorldEvents.notify("Vuelve a casa", "%s ha sido %s." % [p.name, _g(r.character if r != null else null, "liberado", "liberada")])
	_changed()

# --- Paso del mes ---

func _on_month_passed(_month: int, _year: int) -> void:
	if not GameManager.is_game_active:
		return
	if not captivity.is_empty() and not is_captive():
		captivity = {}   # el preso era tu antecesor (sucesión): su heredero está libre
	if is_captive():
		if captivity.stage == "prison":
			captivity.months_left = int(captivity.months_left) - 1
			if int(captivity.months_left) <= 0:
				var captor := str(captivity.captor)
				_release_player("", false)
				WorldEvents.notify("Libre", "%s te suelta tras meses de encierro." % captor)
			else:
				GameManager.pending_event = _prison_event()
				_block_actions()
		else:
			GameManager.pending_event = _captivity_event()
			_block_actions()
	_ai_prisoners_month()
	_serfs_month()
	if GameManager.pending_event.is_empty() and not _queue.is_empty():
		GameManager.pending_event = _queue.pop_front()
	captures_changed.emit()

func _ai_prisoners_month() -> void:
	for p: Dictionary in prisoners.duplicate():
		if p.by_player:
			continue
		p.months = int(p.months) + 1
		var cruel: bool = int(p.captor_personality) == Character.Personality.CRUEL
		if (p.was_retinue or p.was_spouse) and not p.requested:
			p.requested = true
			var e := _ransom_request_event(p)
			if GameManager.pending_event.is_empty() and not is_captive():
				GameManager.pending_event = e
			else:
				_queue.append(e)
			continue
		if p.refused:
			if randf() < (REFUSED_EXECUTE_CHANCE if cruel else 0.0):
				_ai_execute(p)
			elif int(p.months) >= AI_MAX_HOLD:
				_return_home(p, RETURN_UNPAID_AFFECTION)
			continue
		if p.was_retinue or p.was_spouse:
			continue   # esperan tu respuesta al rescate
		var at_war := int(p.kingdom) >= 0 and int(p.captor_kingdom) >= 0 \
			and KingdomDiplomacy.at_war(RelationsData.kingdom_wars, int(p.kingdom), int(p.captor_kingdom))
		var execute_chance := (AI_EXECUTE_CRUEL if cruel else AI_EXECUTE_CHANCE) + (AI_EXECUTE_WAR if at_war else 0.0)
		if randf() < execute_chance:
			_ai_execute(p)
		elif randf() < AI_RANSOM_CHANCE or int(p.months) >= AI_MAX_HOLD:
			_ai_release(p)

func _ai_release(p: Dictionary) -> void:
	var r := relation_of(p)
	_release_record(p)
	if p.temp and r != null:
		RelationsData.relations.erase(r)
	WorldEvents.record("%s sale libre tras pagar rescate a %s." % [p.name, p.captor])

func _ai_execute(p: Dictionary) -> void:
	var r := relation_of(p)
	_release_record(p)
	var cause := "ejecución por orden de %s" % p.captor
	if r != null and r.kind == Relationship.Kind.SENOR:
		WorldEvents.kill_lord(r, cause)
		return
	if p.was_retinue or p.was_spouse:
		WorldEvents.notify("Ejecución", "%s ejecuta a %s." % [p.captor, p.name])
	if r != null and p.temp:
		RelationsData.relations.erase(r)
	else:
		RelationsData.on_character_died(str(p.name), cause)

func _serfs_month() -> void:
	var player: Character = GameManager.player_character
	if player == null:
		return
	var earned := 0
	for person_name: String in serfs.duplicate():
		var r := RelationsData.get_relation(person_name)
		if r == null:
			serfs.erase(person_name)
			continue
		if r.affection < SERF_ESCAPE_AFFECTION and randf() < SERF_ESCAPE_CHANCE:
			serfs.erase(person_name)
			RelationsData.retinue.erase(person_name)
			RelationsData.retinue_news.append("%s se ha fugado." % person_name)
			continue
		earned += serf_gold(r)
	if earned > 0:
		player.gold += earned
		RelationsData.retinue_news.append("Tus siervos te rinden %d de oro." % earned)

# --- Utilidades ---

func _release_record(p: Dictionary) -> void:
	prisoners.erase(p)

func _changed() -> void:
	RelationsData.relations_changed.emit()
	captures_changed.emit()

func _kingdom_affinity(kingdom: int, amount: int) -> void:
	if kingdom < 0:
		return
	for r: Relationship in RelationsData.lords():
		if _kingdom_of(r) == kingdom:
			r.adjust(amount)

## Su casa no lo olvida: los señores de su linaje te guardan rencor.
func _house_grudge(person_name: String) -> void:
	var house := RelationsData.family_name_of(person_name)
	for r: Relationship in RelationsData.lords():
		if RelationsData.family_name_of(r.person_name) == house:
			r.adjust(-EXECUTE_AFFINITY)
			r.adjust_grudge(EXECUTE_HOUSE_GRUDGE)

## Los piadosos y honorables de tu casa (séquito y cónyuge) desaprueban la servidumbre.
func _court_disapproves() -> String:
	var names: Array[String] = []
	for r: Relationship in RelationsData.occupation_people():
		if r.character != null and r.character.personality in [Character.Personality.PIADOSO, Character.Personality.HONORABLE] and not is_serf(r.person_name):
			r.adjust_affection(-SERF_DISAPPROVAL)
			names.append(r.character.first_name)
	return "%s lo %s." % [", ".join(names), "desaprueba" if names.size() == 1 else "desaprueban"] if not names.is_empty() else ""

# --- Guardado ---

func save_state() -> Dictionary:
	return {"prisoners": prisoners.duplicate(true), "serfs": serfs.duplicate(), "captivity": captivity.duplicate(true),
		"queue": _queue.duplicate(true)}

func load_state(data: Dictionary) -> void:
	prisoners.clear()
	for p in data.get("prisoners", []):
		if p is Dictionary:
			prisoners.append(_normalize(p))
	serfs.clear()
	for s in data.get("serfs", []):
		serfs.append(str(s))
	captivity = data.get("captivity", {}).duplicate(true)
	_queue = data.get("queue", []).duplicate(true)
	captures_changed.emit()

func _normalize(p: Dictionary) -> Dictionary:
	var out := {"name": "", "by_player": false, "captor": "", "captor_kingdom": -1, "captor_personality": -1, "kingdom": -1,
		"since": 0, "months": 0, "temp": false, "was_retinue": false, "was_spouse": false, "recruit_month": -1,
		"requested": false, "refused": false}
	for k in p:
		out[str(k)] = p[k]
	for k in ["captor_kingdom", "captor_personality", "kingdom", "since", "months", "recruit_month"]:
		out[k] = int(out[k])
	for k in ["by_player", "temp", "was_retinue", "was_spouse", "requested", "refused"]:
		out[k] = bool(out[k])
	out.name = str(out.name)
	out.captor = str(out.captor)
	return out
