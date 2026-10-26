extends Node
# Autoload — registrar como "Sfx"
# Reproduce los efectos de sonido de assets/sfx/ (generados con tools/generate_sfx.py).
# Para cambiar un sonido basta con reemplazar el .wav del mismo nombre.

const SFX_DIR := "res://assets/sfx/"
const SOUND_NAMES := [
	"clash", "hit", "crit", "whoosh", "guard", "disarm", "push", "click",
	"victory", "defeat", "horn", "arrows", "melee", "rout",
]
const POOL_SIZE := 10

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sound_name in SOUND_NAMES:
		var path: String = SFX_DIR + sound_name + ".wav"
		if ResourceLoader.exists(path):
			_streams[sound_name] = load(path)
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"   # el volumen lo controla Settings por bus
		add_child(p)
		_pool.append(p)
	# Todos los botones del juego suenan al pulsarse, sin tener que conectarlos uno a uno.
	get_tree().node_added.connect(_on_node_added)

## Reproduce un sonido. pitch_jitter varía levemente el tono para que los golpes repetidos no suenen idénticos.
func play(sound_name: String, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	var stream: AudioStream = _streams.get(sound_name)
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(play.bind("click", -6.0, 0.04))
