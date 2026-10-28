class_name DataCodec
extends RefCounted
# Convierte partidas y personajes a JSON y de vuelta, sin ejecutar nada del archivo.
#
# Un .tres puede instanciar cualquier script al cargarse: un archivo modificado o compartido
# podría ejecutar código. Aquí solo se reconstruyen los tipos de la lista TYPES, solo se asignan
# sus propiedades guardables, y las texturas solo se aceptan si son imágenes del propio juego.
# Los demás valores (Vector2, enteros...) se conservan con JSON.from_native / to_native.

const TYPES := {
	"Character": preload("res://scripts/resources/character.gd"),
	"Castle": preload("res://scripts/resources/castle.gd"),
	"Army": preload("res://scripts/resources/army.gd"),
	"Relationship": preload("res://scripts/resources/relationship.gd"),
	"Skill": preload("res://scripts/resources/skill.gd"),
	"CharacterTrait": preload("res://scripts/resources/character_trait.gd"),
	"Equipment": preload("res://scripts/resources/equipment.gd"),
	"SaveGame": preload("res://scripts/resources/save_game.gd"),
}
const TEXTURE_PREFIX := "res://assets/"   # única carpeta de la que se aceptan imágenes

# --- Codificar ---

static func encode(value: Variant) -> Variant:
	if value is Texture2D:
		return {"_tex": (value as Texture2D).resource_path}
	if value is Resource:
		return _encode_resource(value)
	if value is Array:
		return (value as Array).map(func(v): return encode(v))
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = encode(value[key])
		return out
	if value is Object:
		return null   # cualquier otro objeto no se guarda
	return value

static func _encode_resource(res: Resource) -> Variant:
	var type_name := _type_of(res)
	if type_name.is_empty():
		return null
	var out := {"_type": type_name}
	for prop in res.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE:
			out[prop.name] = encode(res.get(prop.name))
	return out

static func _type_of(res: Resource) -> String:
	for type_name in TYPES:
		if res.get_script() == TYPES[type_name]:
			return type_name
	return ""

## Texto JSON listo para escribir en disco.
static func to_json(value: Variant) -> String:
	return JSON.stringify(JSON.from_native(encode(value)), "\t")

# --- Decodificar ---

## Lee un texto JSON; devuelve null si está dañado.
static func from_json(text: String) -> Variant:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return null
	return decode(JSON.to_native(parsed))

static func decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("_tex"):
			return _decode_texture(str(value._tex))
		if value.has("_type"):
			return _decode_resource(value)
		var out := {}
		for key in value:
			out[key] = decode(value[key])
		return out
	if value is Array:
		return (value as Array).map(func(v): return decode(v))
	return value

static func _decode_texture(path: String) -> Texture2D:
	if not path.begins_with(TEXTURE_PREFIX) or path.contains("..") or not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	return tex if tex is Texture2D else null

static func _decode_resource(data: Dictionary) -> Resource:
	var script: Script = TYPES.get(str(data._type))
	if script == null:
		return null   # tipo desconocido: se ignora, nunca se instancia
	var res: Resource = script.new()
	var props := {}
	for prop in res.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE:
			props[prop.name] = prop
	for key in data:
		if key == "_type" or not props.has(key):
			continue
		var value: Variant = decode(data[key])
		var current: Variant = res.get(key)
		if current is Array and value is Array:
			# Arrays tipados (Array[Skill]...): se rellenan con los elementos del tipo correcto.
			(current as Array).clear()
			for item in value:
				if item != null:
					(current as Array).append(item)
		elif current is Dictionary and value is Dictionary:
			(current as Dictionary).clear()
			(current as Dictionary).merge(value)
		elif _compatible(props[key], value):
			res.set(key, value)
	return res

static func _compatible(prop: Dictionary, value: Variant) -> bool:
	var expected: int = prop.type
	if expected == TYPE_NIL or value == null and expected == TYPE_OBJECT:
		return true
	if expected == TYPE_FLOAT and value is int:
		return true
	if expected == TYPE_INT and value is float:
		return true
	return typeof(value) == expected

# --- Archivos ---

## Escribe de forma atómica: primero a un .tmp y luego lo cambia por el archivo real,
## guardando la versión anterior como .bak. Un corte a mitad nunca deja una partida rota.
static func write_file(path: String, value: Variant) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json(value))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)

## Lee un archivo; si está dañado prueba con la copia .bak. null si no hay nada válido.
static func read_file(path: String) -> Variant:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var value: Variant = from_json(FileAccess.get_file_as_string(candidate))
		if value != null:
			return value
	return null
