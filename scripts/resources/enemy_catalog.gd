class_name EnemyCatalog
extends RefCounted
# Enemigos genéricos del combate RPG (y de los encuentros de las campales) y plantillas de grupo.
# make_enemy(tipo, nivel, rango) → Character listo para RpgBattleManager (armadura, arma, acciones y
# técnicas fijadas con metadatos de RpgStats y learned_skills).
#
# Retratos: varias imágenes por tipo en assets/portraits/enemies/<tipo>/ (PNG 1024×1536 transparentes).
# Se elige una al azar; dentro de un mismo encuentro (diccionario `used` compartido) no se repite
# imagen mientras queden libres. La lista de cada carpeta se lee una sola vez (caché). Si la carpeta
# falta o está vacía, se usa assets/portraits/roles/<fallback>.png.

const ENEMY_DIR := "res://assets/portraits/enemies/%s/"
const ROLE_FALLBACK := "res://assets/portraits/roles/%s.png"
const ATTR_PER_LEVEL := 0.6          # Combate/Defensa ganados por nivel
const MINOR_ATTR_PER_LEVEL := 0.2    # Estrategia/Liderazgo/Carisma
const ATTR_MIN := 1
const ATTR_MAX := 20
const RANK_NAMES := ["", "veterano", "de élite"]
const RANK_ATTR_BONUS := [0, 2, 4]
const BOSS_ACTIONS := 2
const BOSS_PV_MULT := 2.2
const GENERIC_PV_MULT := 1.2        # los genéricos no tienen árbol: algo más de aguante...
const GENERIC_PV_PER_LEVEL := 0.05  # ...que crece con el nivel (el grupo gana técnicas al subir)
const XP_PER_LEVEL := 6              # experiencia que da cada enemigo por nivel
const BOSS_XP_MULT := 3
const MAX_LEVEL := 20

const A := RpgStats.ArmorClass
const DT := RpgStats.DamageType
const FT := CharacterEnums.FighterType
const P := Character.Personality

# attrs: [combate, defensa, estrategia, liderazgo, carisma] a nivel 1.
const TYPES := {
	"miliciano": {"name": "Miliciano", "armor": A.SIN, "dmg": DT.CONTUNDENTE, "role": "carne de cañón", "type": FT.TANQUE, "attrs": [4, 4, 3, 3, 3], "tech": ["tan_mazazo"], "fallback": "campesino", "pers": P.COBARDE, "family": "infantería"},
	"bandido": {"name": "Bandido", "armor": A.CUERO, "dmg": DT.TAJO, "role": "daño, robo", "type": FT.BERSERKER, "attrs": [6, 4, 4, 3, 3], "tech": ["ber_tajo", "ber_herida"], "fallback": "bandido", "pers": P.CRUEL, "family": ""},
	"soldado": {"name": "Soldado", "armor": A.MALLA, "dmg": DT.TAJO, "role": "equilibrado", "type": FT.DUELISTA, "attrs": [6, 6, 4, 4, 3], "tech": ["due_estocada", "com_tajo1"], "fallback": "soldado", "pers": P.LEAL, "family": "infantería"},
	"infanteria_pesada": {"name": "Infante pesado", "armor": A.PLACAS, "dmg": DT.CONTUNDENTE, "role": "tanque, provocar", "type": FT.TANQUE, "attrs": [5, 8, 3, 4, 3], "tech": ["tan_provocar", "tan_mazazo"], "fallback": "soldado", "pers": P.VALIENTE, "family": "infantería pesada"},
	"arquero": {"name": "Arquero", "armor": A.CUERO, "dmg": DT.PROYECTIL, "role": "daño a distancia", "type": FT.ASESINO, "attrs": [6, 3, 5, 3, 3], "tech": ["com_proy2"], "fallback": "soldado", "pers": P.ASTUTO, "family": "arqueros"},
	"ballestero": {"name": "Ballestero", "armor": A.MALLA, "dmg": DT.PROYECTIL, "role": "daño alto, lento", "type": FT.ESTRATEGA, "attrs": [7, 5, 3, 3, 3], "tech": ["ene_virote"], "fallback": "soldado", "pers": P.PRUDENTE, "family": "ballesteros"},
	"piquero": {"name": "Piquero", "armor": A.MALLA, "dmg": DT.ESTOCADA, "role": "castiga cargas, protege", "type": FT.DEFENSOR, "attrs": [5, 6, 4, 4, 3], "tech": ["ene_picas", "def_cubrir"], "fallback": "soldado", "pers": P.LEAL, "family": "piqueros"},
	"caballero_montado": {"name": "Jinete", "armor": A.MALLA, "dmg": DT.ESTOCADA, "role": "carga inicial, rápido", "type": FT.DUELISTA, "attrs": [7, 5, 5, 5, 4], "tech": ["ene_carga"], "fallback": "caballero", "pers": P.VALIENTE, "family": "caballería"},
	"caballero_pesado": {"name": "Caballero pesado", "armor": A.PLACAS, "dmg": DT.CONTUNDENTE, "role": "muy duro, lento", "type": FT.TANQUE, "attrs": [7, 8, 4, 5, 4], "tech": ["ene_carga", "tan_mazazo"], "fallback": "caballero", "pers": P.ARROGANTE, "family": "caballería pesada"},
	"explorador": {"name": "Explorador", "armor": A.CUERO, "dmg": DT.ESTOCADA, "role": "crítico, veneno", "type": FT.ASESINO, "attrs": [6, 3, 6, 3, 3], "tech": ["ase_punal", "ase_hoja"], "fallback": "bandido", "pers": P.ASTUTO, "family": ""},
	"capellan": {"name": "Capellán", "armor": A.CUERO, "dmg": DT.CONTUNDENTE, "role": "apoyo, cura", "type": FT.DEFENSOR, "attrs": [4, 5, 5, 6, 6], "tech": ["def_vendaje", "com_grito"], "fallback": "campesino", "pers": P.PIADOSO, "family": ""},
	# Mini jefes: más PV, 2 acciones por turno y una técnica propia.
	"capitan_bandido": {"name": "Capitán bandido", "armor": A.CUERO, "dmg": DT.TAJO, "role": "jefe", "type": FT.BERSERKER, "attrs": [8, 6, 5, 6, 4], "tech": ["jef_saqueo", "ber_tajo", "ber_furia"], "fallback": "bandido", "pers": P.CRUEL, "boss": true, "family": ""},
	"sargento_veterano": {"name": "Sargento veterano", "armor": A.MALLA, "dmg": DT.TAJO, "role": "jefe", "type": FT.ESTRATEGA, "attrs": [8, 7, 6, 7, 4], "tech": ["jef_formacion", "due_estocada"], "fallback": "soldado", "pers": P.LEAL, "boss": true, "family": "infantería"},
	"campeon_torneo": {"name": "Campeón de torneo", "armor": A.PLACAS, "dmg": DT.ESTOCADA, "role": "jefe", "type": FT.DUELISTA, "attrs": [9, 7, 5, 5, 6], "tech": ["jef_campeon", "due_estocada", "due_guardia"], "fallback": "caballero", "pers": P.ARROGANTE, "boss": true, "family": "caballería"},
	"caballero_orden": {"name": "Caballero de la orden", "armor": A.PLACAS, "dmg": DT.CONTUNDENTE, "role": "jefe", "type": FT.DEFENSOR, "attrs": [8, 9, 5, 6, 5], "tech": ["jef_carga_sagrada", "def_vendaje", "tan_mazazo"], "fallback": "caballero", "pers": P.HONORABLE, "boss": true, "family": "caballería pesada"},
	"jefe_descalzos": {"name": "Jefe de los descalzos", "armor": A.SIN, "dmg": DT.CONTUNDENTE, "role": "jefe", "type": FT.BERSERKER, "attrs": [8, 6, 4, 8, 5], "tech": ["jef_turba", "ber_furia"], "fallback": "campesino", "pers": P.VALIENTE, "boss": true, "family": ""},
	"guardian_torre": {"name": "Guardián de la torre", "armor": A.PLACAS, "dmg": DT.CONTUNDENTE, "role": "jefe", "type": FT.TANQUE, "attrs": [8, 10, 4, 5, 3], "tech": ["jef_vigilia", "tan_provocar", "tan_mazazo"], "fallback": "caballero", "pers": P.PRUDENTE, "boss": true, "family": ""},
}

# Plantillas de grupo por contexto: [tipos, desfase de nivel].
const TEMPLATES := {
	"camino": [[["bandido", "bandido"], 1], [["bandido", "bandido", "arquero"], 0], [["bandido", "explorador", "bandido", "miliciano"], 0], [["capitan_bandido", "bandido", "bandido"], 0]],
	"exploracion": [[["explorador", "arquero"], 1], [["bandido", "explorador", "arquero"], 0], [["jefe_descalzos", "miliciano", "miliciano", "miliciano"], -1], [["guardian_torre", "soldado"], 0]],
	"historia": [[["soldado", "soldado", "ballestero"], 0], [["sargento_veterano", "soldado", "piquero", "arquero"], 0], [["caballero_orden", "capellan", "infanteria_pesada"], 0]],
	"torneo": [[["caballero_montado"], 2], [["campeon_torneo"], 1], [["caballero_montado", "caballero_pesado"], 0]],
	"escaramuza": [[["soldado", "piquero", "arquero", "miliciano"], 0], [["infanteria_pesada", "ballestero", "soldado"], 0], [["caballero_montado", "caballero_pesado", "soldado", "arquero", "miliciano", "miliciano"], -2]],
}

static var _folder_cache := {}   # tipo -> Array[String] con las rutas de sus retratos

static func is_boss(type_id: String) -> bool:
	return TYPES.get(type_id, {}).get("boss", false)

## Retratos del tipo (leídos una vez). En el juego exportado las imágenes aparecen como .import.
static func portraits_of(type_id: String) -> Array:
	if _folder_cache.has(type_id):
		return _folder_cache[type_id]
	var out := []
	var path := ENEMY_DIR % type_id
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			var img := f.trim_suffix(".import")
			var full := path + img
			if not dir.current_is_dir() and img.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"] \
					and not full in out and ResourceLoader.exists(full):
				out.append(full)
			f = dir.get_next()
		dir.list_dir_end()
	out.sort()
	_folder_cache[type_id] = out
	return out

## Elige un retrato sin repetir dentro del encuentro (`used`: tipo -> rutas ya dadas).
static func pick_portrait(type_id: String, used: Dictionary = {}) -> String:
	var all := portraits_of(type_id)
	if all.is_empty():
		return ROLE_FALLBACK % TYPES.get(type_id, {}).get("fallback", "soldado")
	var taken: Array = used.get(type_id, [])
	var free := all.filter(func(p: String) -> bool: return not p in taken)
	var pick: String = (free if not free.is_empty() else all).pick_random()
	taken.append(pick)
	used[type_id] = taken
	return pick

static func make_enemy(type_id: String, level: int, rank: int = 0, used: Dictionary = {}) -> Character:
	var d: Dictionary = TYPES.get(type_id, TYPES["soldado"])
	var c := Character.new()
	var lv := clampi(level, 1, MAX_LEVEL)
	rank = clampi(rank, 0, RANK_NAMES.size() - 1)
	c.first_name = d.name if RANK_NAMES[rank] == "" else "%s %s" % [d.name, RANK_NAMES[rank]]
	c.last_name = ""
	c.level = lv
	c.fighter_type = d.type
	c.personality = d.pers
	c.role = Character.Role.SOLDADO
	var grow: float = (lv - 1) * ATTR_PER_LEVEL + RANK_ATTR_BONUS[rank]
	var minor: float = (lv - 1) * MINOR_ATTR_PER_LEVEL + RANK_ATTR_BONUS[rank] * 0.5
	c.combat = clampi(roundi(d.attrs[0] + grow), ATTR_MIN, ATTR_MAX)
	c.defense = clampi(roundi(d.attrs[1] + grow), ATTR_MIN, ATTR_MAX)
	c.strategy = clampi(roundi(d.attrs[2] + minor), ATTR_MIN, ATTR_MAX)
	c.leadership = clampi(roundi(d.attrs[3] + minor), ATTR_MIN, ATTR_MAX)
	c.charisma = clampi(roundi(d.attrs[4] + minor), ATTR_MIN, ATTR_MAX)
	c.set_meta(RpgStats.META_ARMOR, d.armor)
	c.set_meta(RpgStats.META_DAMAGE, d.dmg)
	c.set_meta("enemy_type", type_id)
	if d.get("boss", false):
		c.set_meta(RpgStats.META_ACTIONS, BOSS_ACTIONS)
		c.set_meta(RpgStats.META_PV_MULT, BOSS_PV_MULT + GENERIC_PV_PER_LEVEL * lv)
	else:
		c.set_meta(RpgStats.META_PV_MULT, GENERIC_PV_MULT + GENERIC_PV_PER_LEVEL * lv)
	for t in d.tech:
		c.learned_skills.append(t)
	var path := pick_portrait(type_id, used)
	if ResourceLoader.exists(path):
		c.portrait = load(path)
	c.set_meta("portrait_path", path)
	return c

static func xp_value(c: Character) -> int:
	var t: String = c.get_meta("enemy_type", "")
	return c.level * XP_PER_LEVEL * (BOSS_XP_MULT if is_boss(t) else 1)

## Grupo enemigo para un contexto (camino, exploracion, historia, torneo, escaramuza).
## index < 0: plantilla al azar. Los nombres repetidos se distinguen con una letra.
static func make_party(context: String, level: int, index: int = -1) -> Array[Character]:
	var list: Array = TEMPLATES.get(context, TEMPLATES["camino"])
	var tpl: Array = list[index] if index >= 0 and index < list.size() else list.pick_random()
	var used := {}
	var out: Array[Character] = []
	var counts := {}
	for t in tpl[0]:
		var e := make_enemy(t, level + int(tpl[1]), 0, used)
		counts[e.first_name] = counts.get(e.first_name, 0) + 1
		out.append(e)
	var seen := {}
	for e in out:
		if counts[e.first_name] > 1:
			seen[e.first_name] = seen.get(e.first_name, 0) + 1
			e.last_name = char(64 + seen[e.first_name])
	return out
