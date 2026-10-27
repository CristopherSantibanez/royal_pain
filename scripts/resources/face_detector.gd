extends RefCounted
# Recorte automático de la cara en retratos sin entrada en face_rects.gd (p. ej. retratos nuevos).
# Misma heurística que tools/build_face_rects.py: busca la parte de arriba de la figura por la
# transparencia, estima la altura de la cabeza y centra un cuadrado sobre ella. Se calcula la
# primera vez que se muestra la cara y queda guardado en user://, así no se repite.

const CACHE_FILE := "face_rects_auto.json"   # en DataPaths: las pruebas usan su propia carpeta
const ALPHA_MIN := 0.5          # opaco a partir de aquí (igual que ALPHA_MIN = 128 en la herramienta)
const HEAD_RATIO := 0.135       # alto de la cabeza respecto a la figura
const FACE_SCALE := 1.55        # el recorte cubre algo más que la cabeza (pelo y cuello)
const FACE_CENTER := 0.62       # centro vertical del recorte dentro de la cabeza
const MIN_ROW_PIXELS := 6       # píxeles opacos para dar una fila por empezada (en la imagen reducida)
const SAMPLE_SCALE := 4         # se analiza la imagen a 1/4: mucho más rápido y el resultado apenas cambia

static var _cache := {}
static var _loaded := false

## Recorte [x, y, lado] en píxeles del retrato original, o [] si no se puede calcular.
static func face_rect(tex: Texture2D) -> Array:
	if tex == null:
		return []
	var path := tex.resource_path
	_load_cache()
	if not path.is_empty() and _cache.has(path):
		return _cache[path]
	var rect := _compute(tex)
	if not path.is_empty() and rect.size() == 3:
		_cache[path] = rect
		_save_cache()
	return rect

static func _compute(tex: Texture2D) -> Array:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return []
	if img.is_compressed() and img.decompress() != OK:
		return []
	var w := img.get_width()
	var h := img.get_height()
	img.resize(maxi(1, w / SAMPLE_SCALE), maxi(1, h / SAMPLE_SCALE), Image.INTERPOLATE_BILINEAR)
	var sw := img.get_width()
	var sh := img.get_height()
	var rows: Array = []
	for y in sh:
		var xs: PackedInt32Array = []
		for x in sw:
			if img.get_pixel(x, y).a >= ALPHA_MIN:
				xs.append(x)
		rows.append(xs)
	var top := 0
	for y in sh:
		if rows[y].size() >= MIN_ROW_PIXELS:
			top = y
			break
	var bottom := sh - 1
	for y in range(sh - 1, -1, -1):
		if not rows[y].is_empty():
			bottom = y
			break
	var head_h := maxi(10, int((bottom - top) * HEAD_RATIO))
	# Centro horizontal de la cabeza: mediana de los píxeles opacos de su franja.
	var band: PackedInt32Array = []
	for y in range(top + head_h / 4, mini(sh, top + head_h)):
		band.append_array(rows[y])
	band.sort()
	var cx: int = band[band.size() / 2] if not band.is_empty() else sw / 2
	# De vuelta a píxeles del retrato original.
	var side := int(head_h * FACE_SCALE * SAMPLE_SCALE)
	var cy := (top + int(head_h * FACE_CENTER)) * SAMPLE_SCALE
	var x := clampi(cx * SAMPLE_SCALE - side / 2, 0, maxi(0, w - side))
	var y := clampi(cy - side / 2, 0, maxi(0, h - side))
	return [x, y, side]

static func _load_cache() -> void:
	if _loaded:
		return
	_loaded = true
	var file := DataPaths.path(CACHE_FILE)
	if not FileAccess.file_exists(file):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(file))
	if data is Dictionary:
		for k in data:
			var r = data[k]
			if r is Array and r.size() == 3:
				_cache[k] = [int(r[0]), int(r[1]), int(r[2])]

static func _save_cache() -> void:
	var f := FileAccess.open(DataPaths.path(CACHE_FILE), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_cache))
