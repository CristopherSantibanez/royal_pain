class_name ConsumableCatalog
extends RefCounted
# Consumibles del combate RPG (sin magia): vendas, ungüentos, aceite, redes… La bolsa del grupo vive en
# el jugador (Character.consumables: id -> cantidad). Usar uno gasta el turno de quien lo usa.
# Fuentes: tienda del castillo (pestaña Consumibles; el Mercado desbloquea más), botín y sucesos.

const MAX_STACK := 5
const HEAL_SMALL := 0.2          # Venda: fracción de los PV máximos
const HEAL_MEDIUM := 0.4         # Ungüento
const HEAL_HERBS := 0.1          # Hierbas
const PT_RESTORE := 0.5          # Pan y vino: fracción de los PT máximos
const ALE_MORALE := 20           # Cerveza fuerte
const ALE_WILL := 2.0            # Voluntad extra mientras dura
const ALE_HIT := 0.1             # puntería perdida (ebrio)
const ALE_TURNS := 3
const OIL_DMG := 0.12            # Aceite: fracción de los PV máximos del objetivo
const BURN_FRAC := 0.05          # quemadura por turno
const BURN_TURNS := 3
const SHARPEN_DMG := 0.2         # Piedra de afilar: +20 % de daño
const SHARPEN_TURNS := 3
const HOLY_MORALE := 15          # Agua bendita
const SMOKE_EVASION := 0.15      # Bomba de humo: evasión del grupo
const SMOKE_RETREAT := 0.25      # y más fácil retirarse
const SMOKE_TURNS := 2
const NET_CHANCE := 0.85         # Red de caza: probabilidad base de derribar
# IA enemiga: pocos objetos y uso ocasional.
const ENEMY_BAG_CHANCE := 0.4    # probabilidad de que el bando rival lleve objetos
const ENEMY_BAG_MAX := 2         # 1–2 objetos en total
const ENEMY_POOL := ["venda", "unguento", "aceite", "red"]
const AI_ITEM_CHANCE := 0.35
const AI_HEAL_HP := 0.4
const LOOT_CHANCE := 0.5         # tras ganar: probabilidad de encontrar objetos
const LOOT_MAX := 2

# tgt: ally (1 aliado activo), enemy (1 rival), allies (todo el grupo). market: nivel de Mercado necesario.
const ITEMS := {
	"venda": {"name": "Venda", "price": 15, "tgt": "ally", "market": 0, "desc": "Cura un poco (%d%% PV)." % roundi(HEAL_SMALL * 100)},
	"unguento": {"name": "Ungüento", "price": 35, "tgt": "ally", "market": 1, "desc": "Cura (%d%% PV) y corta el Sangrado." % roundi(HEAL_MEDIUM * 100)},
	"pan_vino": {"name": "Pan y vino", "price": 20, "tgt": "ally", "market": 0, "desc": "Recupera la mitad de los PT."},
	"cerveza": {"name": "Cerveza fuerte", "price": 12, "tgt": "ally", "market": 0, "desc": "Moral y Voluntad, pero menos puntería."},
	"aceite": {"name": "Aceite de lámpara", "price": 30, "tgt": "enemy", "market": 1, "desc": "Lo arrojas: daño y Ardiendo."},
	"piedra": {"name": "Piedra de afilar", "price": 25, "tgt": "ally", "market": 0, "desc": "+%d%% de daño unos turnos." % roundi(SHARPEN_DMG * 100)},
	"agua_bendita": {"name": "Agua bendita", "price": 40, "tgt": "ally", "market": 2, "desc": "Quita Aturdido y Provocado; da moral."},
	"humo": {"name": "Bomba de humo", "price": 45, "tgt": "allies", "market": 2, "desc": "El grupo esquiva más y huye mejor."},
	"red": {"name": "Red de caza", "price": 30, "tgt": "enemy", "market": 1, "desc": "Puede derribar al objetivo."},
	"hierbas": {"name": "Hierbas", "price": 18, "tgt": "ally", "market": 0, "desc": "Purgan Debilitado, Cegado y Ardiendo; curan algo."},
}

static func item(id: String) -> Dictionary:
	return ITEMS.get(id, {})

static func item_name(id: String) -> String:
	return str(ITEMS.get(id, {}).get("name", id))

static func count(bag: Dictionary, id: String) -> int:
	return int(bag.get(id, 0))

## Añade n unidades (hasta MAX_STACK). Devuelve cuántas cupieron.
static func add(bag: Dictionary, id: String, n: int = 1) -> int:
	if not ITEMS.has(id):
		return 0
	var room := maxi(0, MAX_STACK - count(bag, id))
	var added := mini(room, n)
	if added > 0:
		bag[id] = count(bag, id) + added
	return added

static func take(bag: Dictionary, id: String) -> bool:
	if count(bag, id) <= 0:
		return false
	bag[id] = count(bag, id) - 1
	if int(bag[id]) <= 0:
		bag.erase(id)
	return true

## Objetos que vende la tienda según el nivel del Mercado del castillo.
static func shop_items(market_level: int) -> Array:
	return ITEMS.keys().filter(func(id: String) -> bool: return int(ITEMS[id].market) <= market_level)

static func summary(bag: Dictionary) -> String:
	var parts := []
	for id in bag:
		parts.append("%s ×%d" % [item_name(id), int(bag[id])])
	return ", ".join(parts)

## Bolsa al azar para el bando rival (vacía la mayoría de las veces).
static func enemy_bag() -> Dictionary:
	var bag := {}
	if randf() < ENEMY_BAG_CHANCE:
		for i in randi_range(1, ENEMY_BAG_MAX):
			add(bag, ENEMY_POOL.pick_random())
	return bag

## Botín tras ganar: añade a la bolsa y deja la lista en result.loot.
static func grant_loot(bag: Dictionary, result: Dictionary) -> void:
	if randf() >= LOOT_CHANCE:
		return
	var loot: Array = result.get("loot", [])
	for i in randi_range(1, LOOT_MAX):
		var id: String = ITEMS.keys().pick_random()
		if add(bag, id) > 0:
			loot.append(id)
	result["loot"] = loot

## Suceso: entrega n objetos al azar. Devuelve el texto.
static func grant_random(bag: Dictionary, n: int) -> String:
	var got := []
	for i in n:
		var id: String = ITEMS.keys().pick_random()
		if add(bag, id) > 0:
			got.append(item_name(id))
	return ("Consigues: " + ", ".join(got)) if not got.is_empty() else ""

# --- En combate ---

static func targets(mgr: RpgBattleManager, f, id: String) -> Array:
	match str(item(id).get("tgt", "ally")):
		"enemy":
			return mgr.active_of(1 - f.side)
		"allies":
			return [f]
	return mgr.active_of(f.side)

## Aplica el objeto action.item sobre action.target. false si no se pudo (no gasta el turno).
static func use(mgr: RpgBattleManager, f, action: Dictionary) -> bool:
	var id := str(action.get("item", ""))
	var bag: Dictionary = mgr.bags[f.side]
	if not ITEMS.has(id) or count(bag, id) <= 0:
		return false
	var t = action.get("target", null)
	var tg := targets(mgr, f, id)
	if t == null or not t in tg:
		t = f if f in tg else (tg[0] if not tg.is_empty() else null)
	if t == null:
		return false
	take(bag, id)
	mgr._log("%s usa %s%s." % [f.name(), item_name(id), (" con %s" % t.name()) if t != f and item(id).tgt != "allies" else ""])
	match id:
		"venda", "unguento", "hierbas":
			var frac: float = {"venda": HEAL_SMALL, "unguento": HEAL_MEDIUM, "hierbas": HEAL_HERBS}[id]
			t.hp = mini(t.max_hp, t.hp + maxi(1, roundi(t.max_hp * frac)))
			if id == "unguento":
				t.statuses.erase("sangrado")
			if id == "hierbas":
				for st in ["debilitado", "cegado", "ardiendo"]:
					t.statuses.erase(st)
		"pan_vino":
			t.pt = mini(t.max_pt, t.pt + maxi(1, roundi(t.max_pt * PT_RESTORE)))
		"cerveza":
			t.morale = mini(100, t.morale + ALE_MORALE)
			if not t.has("ebrio"):
				t.s.voluntad = float(t.s.voluntad) + ALE_WILL
			mgr._add_status(t, "ebrio", ALE_TURNS, null)
		"aceite":
			var dmg := maxi(1, roundi(t.max_hp * OIL_DMG))
			mgr._log("  %s arde (−%d)." % [t.name(), dmg])
			mgr._damage(t, dmg, f)
			if t.up():
				mgr._add_status(t, "ardiendo", BURN_TURNS, null)
		"piedra":
			mgr._add_status(t, "afilado", SHARPEN_TURNS, null)
		"agua_bendita":
			t.statuses.erase("aturdido")
			t.statuses.erase("provocado")
			t.morale = mini(100, t.morale + HOLY_MORALE)
		"humo":
			for o in mgr.active_of(f.side):
				mgr._add_status(o, "humo", SMOKE_TURNS, null)
		"red":
			if mgr._try_status(f, t, "derribado", NET_CHANCE, 1):
				mgr._log("  %s cae enredado." % t.name())
			else:
				mgr._log("  %s esquiva la red." % t.name())
	return true

## IA: a veces usa un objeto de su bolsa ({} si no).
static func ai_pick(mgr: RpgBattleManager, f) -> Dictionary:
	var bag: Dictionary = mgr.bags[f.side]
	if bag.is_empty() or mgr.rng.randf() >= AI_ITEM_CHANCE:
		return {}
	if f.hp_ratio() < AI_HEAL_HP:
		for id in ["unguento", "venda", "hierbas"]:
			if count(bag, id) > 0:
				return {"type": "objeto", "item": id, "target": f}
	var foes := mgr.active_of(1 - f.side)
	if foes.is_empty():
		return {}
	var strongest = foes[0]
	for o in foes:
		if o.hp > strongest.hp:
			strongest = o
	for id in ["red", "aceite"]:
		if count(bag, id) > 0 and not strongest.has("derribado"):
			return {"type": "objeto", "item": id, "target": strongest}
	return {}
