extends Node
# Autoload — registrar como "Music"
# Música de ambiente (assets/music/, generada con tools/generate_music.py).
# Cambia de pista sola según la escena, con fundido cruzado; si la nueva escena usa la misma
# pista, la música sigue sin cortarse. Las pistas de combate tienen una capa "_tension" que
# suena sincronizada y se sube con set_intensity() cuando la pelea se pone difícil.

const MUSIC_DIR := "res://assets/music/"
const FADE_TIME := 1.6
const SILENT_DB := -60.0

# Pista y ambiente de cada escena. Las escenas que no aparecen conservan lo que suena.
const SCENE_MUSIC := {
	"main_menu": ["menu", ""],
	"new_game": ["menu", ""],
	"character_creation": ["menu", ""],
	"character_summary": ["menu", ""],
	"save_slots": ["menu", ""],
	"fighter_select": ["menu", ""],
	"map": ["map", "amb_wind"],
	"relations": ["map", "amb_wind"],
	"castle_interior": ["castle", "amb_fire"],
	"combat": ["duel", ""],
	"rpg_battle": ["duel", ""],
	"battle": ["battle", "amb_wind"],
}

var current_track := ""
var current_ambience := ""
var intensity := 0.0

var _music: AudioStreamPlayer
var _tension: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _intensity_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().scene_changed.connect(_on_scene_changed)
	_on_scene_changed.call_deferred()

## Cambia a una pista (y su ambiente) con fundido cruzado. "" detiene esa capa.
func play(track: String, ambience: String = "") -> void:
	if track != current_track:
		current_track = track
		intensity = 0.0
		_fade_out(_music)
		_fade_out(_tension)
		_music = _start(track, 0.0)
		_tension = _start(track + "_tension", SILENT_DB, _music != null)
	if ambience != current_ambience:
		current_ambience = ambience
		_fade_out(_ambience)
		_ambience = _start(ambience, 0.0, false, "Ambience")

## 0 = calma, 1 = máxima tensión. Solo tiene efecto en pistas con capa "_tension".
func set_intensity(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if _tension == null or is_equal_approx(value, intensity):
		return
	intensity = value
	if _intensity_tween:
		_intensity_tween.kill()
	_intensity_tween = create_tween()
	_intensity_tween.tween_property(_tension, "volume_db", lerpf(SILENT_DB, 0.0, sqrt(value)), 1.2)

## Baja la música (para que se oiga la fanfarria de victoria o derrota).
func stop(fade: float = FADE_TIME) -> void:
	current_track = ""
	_context_key = ""
	_fade_out(_music, fade)
	_fade_out(_tension, fade)
	_music = null
	_tension = null

func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var key := scene.scene_file_path.get_file().get_basename()
	if MusicCatalog.SCENE_CONTEXT.has(key):
		play_context(_resolve_context(MusicCatalog.SCENE_CONTEXT[key]))
	elif SCENE_MUSIC.has(key):
		play(SCENE_MUSIC[key][0], "")

# --- Música por contexto y cultura (ver MusicCatalog). El ambiente de los lugares lo lleva Ambience. ---
const MusicCatalog = preload("res://scripts/resources/music_catalog.gd")
const ROTATE_SECONDS := 150.0     # pasado este tiempo, otra pieza del mismo contexto (nunca la misma dos veces)
const STING_DB := -2.0

var current_context := ""
var _context_key := ""            # contexto + cultura que suena ahora
var _last_by_context := {}        # contexto -> última pista elegida
var _rotate_timer: Timer
var _sting: AudioStreamPlayer

## Pone la música de un contexto ("map", "castle", "duel"…). culture = -1: la del lugar donde está el jugador.
## Si ya suena ese contexto con esa cultura, no corta nada.
func play_context(context: String, culture: int = -1) -> void:
	if culture < 0 and MusicCatalog.CULTURE_PREFIX.has(context):
		culture = _location_culture()
	var key := "%s:%d" % [context, culture]
	if key == _context_key and not current_track.is_empty():
		return
	_context_key = key
	current_context = context
	var track := MusicCatalog.pick(context, culture, _last_by_context.get(context, current_track), _track_exists)
	if track.is_empty():
		return
	_last_by_context[context] = track
	play(track, "")
	_restart_rotation(context)

## Vuelve a decidir la música de la escena actual (al viajar, al caer preso, al quedar libre…).
func refresh_context() -> void:
	_on_scene_changed()

## Fanfarria de una sola vez por encima de la música (victorias, finales).
func sting(name: String = "") -> void:
	if name.is_empty():
		name = MusicCatalog.STINGS[randi() % MusicCatalog.STINGS.size()]
	var path := MUSIC_DIR + name + ".ogg"
	if not ResourceLoader.exists(path):
		return
	if _sting != null:
		_sting.queue_free()
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = false
	_sting = AudioStreamPlayer.new()
	_sting.stream = stream
	_sting.bus = "SFX"   # va por encima del bus de música, que se aparta
	_sting.volume_db = STING_DB
	add_child(_sting)
	_sting.play()
	_sting.finished.connect(_sting.queue_free)
	duck(stream.get_length() * 0.8)

func _resolve_context(context: String) -> String:
	var capture := get_node_or_null("/root/CaptureData")
	if context in ["map", "castle"] and capture != null and capture.has_method("is_captive") and capture.is_captive():
		return "captivity"
	var travel := get_node_or_null("/root/TravelData")
	if context == "map" and travel != null and GameManager.is_game_active and not travel.is_at_home():
		return "travel"
	return context

func _location_culture() -> int:
	if not GameManager.is_game_active:
		return -1
	var travel := get_node_or_null("/root/TravelData")
	var castle: Castle = travel.current_castle() if travel != null else GameManager.current_castle
	if castle == null:
		castle = GameManager.current_castle
	if castle == null:
		return -1
	return castle.culture if castle.culture >= 0 else MapData.culture_of_kingdom(castle.kingdom)

func _track_exists(track: String) -> bool:
	return ResourceLoader.exists(MUSIC_DIR + track + ".ogg")

func _restart_rotation(context: String) -> void:
	if _rotate_timer == null:
		_rotate_timer = Timer.new()
		_rotate_timer.one_shot = true
		add_child(_rotate_timer)
		_rotate_timer.timeout.connect(_rotate)
	_rotate_timer.stop()
	if not context in MusicCatalog.NO_ROTATION:
		_rotate_timer.start(ROTATE_SECONDS)

func _rotate() -> void:
	if current_context.is_empty() or current_context in MusicCatalog.NO_ROTATION:
		return
	_context_key = ""   # fuerza una pieza nueva del mismo contexto
	play_context(current_context)

func _start(stream_name: String, target_db: float, synced: bool = false, bus: String = "Music") -> AudioStreamPlayer:
	if stream_name.is_empty():
		return null
	var path := MUSIC_DIR + stream_name + ".ogg"
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = SILENT_DB
	add_child(p)
	p.play()
	# La capa de tensión arranca a la vez que la base para que vayan a tempo; solo se oye al subir la intensidad.
	if synced and target_db <= SILENT_DB:
		return p
	create_tween().tween_property(p, "volume_db", target_db, FADE_TIME).set_trans(Tween.TRANS_SINE)
	return p

## Baja la música un momento para que se oiga un aviso (victoria, hazaña, cartel grande) y la repone.
const DUCK_DB := -12.0
const DUCK_IN := 0.08
const DUCK_OUT := 0.6
var _duck_tween: Tween

func duck(hold: float = 1.2, amount_db: float = DUCK_DB) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx < 0:
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	var base := _bus_db_from_settings(idx)
	_duck_tween = create_tween()
	_duck_tween.tween_method(func(db: float): AudioServer.set_bus_volume_db(idx, db), base, base + amount_db, DUCK_IN)
	_duck_tween.tween_interval(hold)
	_duck_tween.tween_method(func(db: float): AudioServer.set_bus_volume_db(idx, db), base + amount_db, base, DUCK_OUT)

func _bus_db_from_settings(idx: int) -> float:
	var v: float = Settings.volumes.get("Music", 1.0)
	return linear_to_db(maxf(v * v, 0.0001)) if v > 0.0 else AudioServer.get_bus_volume_db(idx)

func _fade_out(p: AudioStreamPlayer, fade: float = FADE_TIME) -> void:
	if p == null:
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", SILENT_DB, fade).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(p.queue_free)
