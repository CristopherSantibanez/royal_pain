extends Node
# Autoload — registrar como "Ambience" (después de Music).
# 1) Ambiente sonoro del lugar en el bus "Ambience" (assets/music/amb_*.ogg), con fundido cruzado:
#    castillo (mercado y forja), camino (viento, cuervos, carreta), costa, torneo, lluvia o nieve en batalla, mazmorra.
# 2) Avisos sonoros del mundo sin tocar a quien los provoca: pasar el mes, viajar, cartas y complots,
#    hazañas, subir de nivel, cautiverio. Escucha señales y el evento pendiente de GameManager.

const AMB_DIR := "res://assets/music/"
const FADE_TIME := 2.0
const SILENT_DB := -60.0
const AMB_DB := 0.0
const POLL_SECONDS := 0.4          # cada cuánto se miran el evento pendiente y el nivel
const CUE_DB := -6.0
const COASTAL_KINGDOMS := [KingdomEnums.Kingdom.AZUL, KingdomEnums.Kingdom.NEUTRAL]
const CAPTIVE_EVENTS := ["cautiverio", "mazmorra"]
const STORY_PREFIX := "story_"     # StoryData.EVENT_PREFIX
const PLOT_PREFIX := "amb_"        # eventos de AmbitionData (complots, propuestas, chantajes)

var current := ""                  # ambiente que suena ("" = ninguno)
var _player: AudioStreamPlayer
var _poll := 0.0
var _last_event_sig := ""
var _last_level := -1
var _was_captive := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().scene_changed.connect(_on_scene_changed)
	_on_scene_changed.call_deferred()
	GameManager.turn_advanced.connect(_on_turn_advanced)
	GameManager.game_started.connect(func(_c): _last_level = -1)
	_connect_optional("TravelData", "location_changed", _on_location_changed)
	_connect_optional("AchievementData", "achievement_unlocked", func(_id): Sfx.stinger("achievement", -2.0, 1.0))
	_connect_optional("AchievementData", "ending_reached", func(_e): Music.sting())
	_connect_optional("CaptureData", "captures_changed", _on_captures_changed)

func _connect_optional(node_name: String, sig: String, cb: Callable) -> void:
	var n := get_node_or_null("/root/" + node_name)
	if n != null and n.has_signal(sig):
		n.connect(sig, cb)

## Ambiente que corresponde a la escena actual (se puede llamar desde fuera tras un cambio, p. ej. el clima).
func refresh() -> void:
	play(_resolve())

func play(amb: String) -> void:
	if amb == current:
		return
	current = amb
	if _player != null:
		var old := _player
		var tw := create_tween()
		tw.tween_property(old, "volume_db", SILENT_DB, FADE_TIME).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(old.queue_free)
		_player = null
	var path := AMB_DIR + amb + ".ogg"
	if amb.is_empty() or not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.bus = "Ambience"
	_player.volume_db = SILENT_DB
	add_child(_player)
	_player.play()
	create_tween().tween_property(_player, "volume_db", AMB_DB, FADE_TIME).set_trans(Tween.TRANS_SINE)

func _on_scene_changed() -> void:
	refresh()

## Qué ambiente pide el lugar: escena + dónde está el jugador + clima de la batalla.
func _resolve() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return current
	var key := scene.scene_file_path.get_file().get_basename()
	match key:
		"map", "relations":
			if _is_captive():
				return "amb_dungeon"
			var castle := _location()
			if castle != null and castle.kingdom in COASTAL_KINGDOMS:
				return "amb_sea"
			var travel := get_node_or_null("/root/TravelData")
			if travel != null and GameManager.is_game_active and not travel.is_at_home():
				return "amb_road"
			return "amb_wind"
		"castle_interior":
			return "amb_dungeon" if _is_captive() else "amb_castle"
		"combat":
			return "amb_crowd" if CombatSetup.is_tournament() else ""
		"battle":
			var b = scene.get("battle")
			var weather: int = b.weather if b != null and "weather" in b else BattleEnums.Weather.DESPEJADO
			match weather:
				BattleEnums.Weather.LLUVIA:
					return "amb_rain"
				BattleEnums.Weather.NIEVE:
					return "amb_snow"
			return "amb_wind"
		"main_menu", "new_game", "character_creation", "character_summary", "save_slots", "fighter_select", "succession":
			return ""
	return current   # otras escenas (glosario, tutorial…): se mantiene lo que suena

func _location() -> Castle:
	if not GameManager.is_game_active:
		return null
	var travel := get_node_or_null("/root/TravelData")
	var c: Castle = travel.current_castle() if travel != null else null
	return c if c != null else GameManager.current_castle

func _is_captive() -> bool:
	var capture := get_node_or_null("/root/CaptureData")
	return capture != null and capture.has_method("is_captive") and capture.is_captive()

# --- Avisos ---

func _on_turn_advanced(_month: int, _year: int) -> void:
	if GameManager.is_game_active:
		Sfx.play("month_turn", CUE_DB, 0.0)

func _on_location_changed(_castle_id: String) -> void:
	Sfx.play("travel_hop", CUE_DB)
	Music.refresh_context()
	refresh()

func _on_captures_changed() -> void:
	var captive := _is_captive()
	if captive and not _was_captive:
		Sfx.stinger("chains", -3.0, 1.0)
	if captive != _was_captive:
		_was_captive = captive
		Music.refresh_context()
		refresh()

func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or not GameManager.is_game_active:
		return
	_poll = POLL_SECONDS
	_check_level()
	_check_event()

func _check_level() -> void:
	var p: Character = GameManager.player_character
	if p == null:
		return
	if _last_level >= 0 and p.level > _last_level:
		Sfx.stinger("level_up", -3.0, 0.8)
	_last_level = p.level

## Un evento nuevo esperando decisión: su sonido según quién lo manda.
func _check_event() -> void:
	var e: Dictionary = GameManager.pending_event
	var sig := "" if e.is_empty() else "%s|%s" % [e.get("id", ""), e.get("title", "")]
	if sig == _last_event_sig:
		return
	_last_event_sig = sig
	if e.is_empty():
		return
	Sfx.play(event_cue(e), CUE_DB, 0.0)

## Sonido de aviso para un evento: historia, complot, cautiverio o una carta cualquiera.
static func event_cue(e: Dictionary) -> String:
	var id := str(e.get("id", ""))
	if id in CAPTIVE_EVENTS:
		return "chains"
	if e.has("_story") or id.begins_with(STORY_PREFIX):
		return "story"
	if e.has("amb_owner") or id.begins_with(PLOT_PREFIX):
		return "plot"
	return "letter"
