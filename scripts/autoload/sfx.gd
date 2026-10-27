extends Node
# Autoload — registrar como "Sfx"
# Reproduce los efectos de sonido de assets/sfx/ (generados con tools/generate_sfx.py).
# Para cambiar un sonido basta con reemplazar el .wav del mismo nombre.

const SFX_DIR := "res://assets/sfx/"
const SOUND_NAMES := [
	"clash", "hit", "crit", "whoosh", "guard", "disarm", "push", "click",
	"victory", "defeat", "horn", "arrows", "melee", "rout",
	"shout", "month_turn", "travel_hop", "letter", "achievement", "level_up", "chains", "execution", "story", "plot",
]
const POOL_SIZE := 10
# Variantes <sonido>_v1… (tools/generate_sfx_extra.py): se elige una al azar sin repetir la anterior.
const MAX_VARIANTS := 6
const VOLUME_JITTER_DB := 1.5
# Golpes fuertes que a veces llevan un grito encima.
const SHOUT_ON := ["crit", "push", "melee"]
const SHOUT_CHANCE := 0.35
const SHOUT_DB := -7.0

var _streams := {}
var _variants := {}       # sonido -> Array[AudioStream] (original + variantes)
var _last_variant := {}   # sonido -> índice usado la última vez
var _pool: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sound_name in SOUND_NAMES:
		var path: String = SFX_DIR + sound_name + ".wav"
		if ResourceLoader.exists(path):
			_streams[sound_name] = load(path)
		var list: Array[AudioStream] = []
		if _streams.has(sound_name):
			list.append(_streams[sound_name])
		for v in range(1, MAX_VARIANTS + 1):
			var vpath: String = SFX_DIR + "%s_v%d.wav" % [sound_name, v]
			if ResourceLoader.exists(vpath):
				list.append(load(vpath))
		if list.size() > 1:
			_variants[sound_name] = list
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"   # el volumen lo controla Settings por bus
		add_child(p)
		_pool.append(p)
	# Todos los botones del juego suenan al pulsarse, sin tener que conectarlos uno a uno.
	get_tree().node_added.connect(_on_node_added)

## Reproduce un sonido. pitch_jitter varía levemente el tono para que los golpes repetidos no suenen idénticos.
func play(sound_name: String, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	var stream: AudioStream = _pick(sound_name)
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db + (randf_range(-VOLUME_JITTER_DB, VOLUME_JITTER_DB) if pitch_jitter > 0.0 else 0.0)
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
	if sound_name in SHOUT_ON and randf() < SHOUT_CHANCE:
		play("shout", volume_db + SHOUT_DB, 0.08)

## Una de las variantes del sonido (sin repetir la última), o el sonido tal cual si no tiene.
func _pick(sound_name: String) -> AudioStream:
	var list: Array = _variants.get(sound_name, [])
	if list.is_empty():
		return _streams.get(sound_name)
	var idx := randi() % list.size()
	if idx == _last_variant.get(sound_name, -1):
		idx = (idx + 1) % list.size()
	_last_variant[sound_name] = idx
	return list[idx]

## Cuántas versiones distintas tiene un sonido (1 = sin variantes; 0 = no existe).
func variant_count(sound_name: String) -> int:
	if _variants.has(sound_name):
		return _variants[sound_name].size()
	return 1 if _streams.has(sound_name) else 0

## Aviso sonoro importante: suena por encima de la música, que se aparta un momento.
func stinger(sound_name: String, volume_db: float = 0.0, hold: float = 1.2) -> void:
	Music.duck(hold)
	play(sound_name, volume_db, 0.0)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(play.bind("click", -6.0, 0.04))
