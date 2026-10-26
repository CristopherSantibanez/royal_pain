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
	_fade_out(_music, fade)
	_fade_out(_tension, fade)
	_music = null
	_tension = null

func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var key := scene.scene_file_path.get_file().get_basename()
	if SCENE_MUSIC.has(key):
		play(SCENE_MUSIC[key][0], SCENE_MUSIC[key][1])

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

func _fade_out(p: AudioStreamPlayer, fade: float = FADE_TIME) -> void:
	if p == null:
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", SILENT_DB, fade).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(p.queue_free)
