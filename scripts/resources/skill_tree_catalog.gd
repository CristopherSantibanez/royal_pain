class_name SkillTreeCatalog
extends RefCounted
# Árbol de habilidades del combate RPG: un árbol por tipo de luchador (3 ramas, 15 nodos) y 3 ramas
# comunes (Mando y apoyo, Supervivencia, Maestría de arma). 1 punto por nivel; requisitos de nivel
# (por escalón, TIER_LEVEL) y de nodos previos. Los nodos "base" se aprenden gratis.
#
# Nodo: {id, name, tree, branch, tier, req, kind ("act"/"pas"), desc, base?
#   activas: pt, tgt (enemy, enemies, random3, ally, allies, self, ko_ally), pow (×Fuerza; 0 = sin daño),
#            dt (tipo de daño; -1 = el del arma), hits, st [[estado, probabilidad, turnos]], heal (× PV máx.),
#            fx {crit, acc, pierce, exec, scale_missing, vs_status, per_ally, cover, advance, cleanse,
#                revive, pt_drain, morale, self_st [[estado, turnos]]}
#   pasivas: fx {pv_pct, pt_pct, fuerza_pct, defensa, agilidad, punteria, voluntad, crit, crit_mult,
#                evasion, taken, counter, low_hp_dmg, low_hp_taken, guard, lifesteal, pt_regen,
#                status_res, ally_taken, ally_dmg, immune_derribo, last_stand, bleed_bonus, retreat,
#                avenge, dmg_t0..dmg_t3 (por tipo de daño), first_sure, on_hit_bleed, crit_ward, reflect}}
# Efectos de estado y su significado: RpgBattleManager.

const TREE_COMMON := -1
const TREE_BOSS := -2           # técnicas propias de enemigos y mini jefes (no se aprenden)
const POINTS_PER_LEVEL := 1
const TIER_LEVEL := [1, 1, 3, 6, 10, 15]   # nivel mínimo por escalón (índice = escalón)
const AUTO_OWN_TREE_WEIGHT := 3.0          # los PNJ prefieren su propio árbol...
const AUTO_WEAPON_WEIGHT := 2.0            # ...y la maestría de su arma
const AUTO_ACTIVE_WEIGHT := 0.5
const AUTO_TIER_PENALTY := 0.2

const D := CharacterEnums.FighterType
const T0 := 0   # Tajo
const T1 := 1   # Estocada
const T2 := 2   # Contundente
const T3 := 3   # Proyectil

const BRANCHES := {
	D.DUELISTA: ["Esgrima", "Precisión", "Elegancia"],
	D.TANQUE: ["Baluarte", "Escudo", "Aplastar"],
	D.ESTRATEGA: ["Mando", "Táctica", "Ingenio"],
	D.BERSERKER: ["Furia", "Carnicería", "Sangre"],
	D.DEFENSOR: ["Protección", "Sanación", "Represalia"],
	D.ASESINO: ["Sombras", "Veneno", "Letalidad"],
	TREE_COMMON: ["Mando y apoyo", "Supervivencia", "Maestría de arma"],
}

const NODES := [
	# --- DUELISTA ---
	{"id": "due_estocada", "name": "Ataque rápido", "tree": D.DUELISTA, "branch": 0, "tier": 1, "req": [], "kind": "act", "base": true, "pt": 4, "tgt": "enemy", "pow": 1.25, "dt": -1, "fx": {"acc": 0.05}, "desc": "Golpe veloz y preciso con su arma."},
	{"id": "due_guardia", "name": "Guardia de esgrima", "tree": D.DUELISTA, "branch": 0, "tier": 2, "req": ["due_estocada"], "kind": "act", "pt": 6, "tgt": "self", "st": [["guardia_esgrima", 1.0, 2]], "desc": "2 turnos: más esquiva y contraataque."},
	{"id": "due_contra", "name": "Contragolpe", "tree": D.DUELISTA, "branch": 0, "tier": 3, "req": ["due_guardia"], "kind": "pas", "fx": {"counter": 0.15}, "desc": "+15% de contraatacar al recibir un golpe."},
	{"id": "due_finta", "name": "Finta", "tree": D.DUELISTA, "branch": 0, "tier": 3, "req": ["due_estocada"], "kind": "act", "pt": 7, "tgt": "enemy", "pow": 0.9, "dt": -1, "st": [["desequilibrado", 0.7, 2]], "desc": "Engaña y desequilibra (débil a Contundente)."},
	{"id": "due_maestro", "name": "Maestro de esgrima", "tree": D.DUELISTA, "branch": 0, "tier": 5, "req": ["due_contra"], "kind": "pas", "fx": {"evasion": 0.08, "counter": 0.1}, "desc": "+8% de esquiva y +10% de contraataque."},
	{"id": "due_certero", "name": "Golpe certero", "tree": D.DUELISTA, "branch": 1, "tier": 1, "req": [], "kind": "pas", "fx": {"crit": 0.08}, "desc": "+8% de crítico."},
	{"id": "due_punto", "name": "Punto débil", "tree": D.DUELISTA, "branch": 1, "tier": 2, "req": ["due_certero"], "kind": "act", "pt": 6, "tgt": "enemy", "pow": 1.0, "dt": -1, "fx": {"pierce": 1, "crit": 0.1}, "desc": "Ignora la resistencia de la armadura."},
	{"id": "due_halcon", "name": "Ojo de halcón", "tree": D.DUELISTA, "branch": 1, "tier": 3, "req": ["due_certero"], "kind": "pas", "fx": {"crit_mult": 0.25, "punteria": 2}, "desc": "Críticos más dañinos y +2 de Puntería."},
	{"id": "due_corazon", "name": "Estocada al corazón", "tree": D.DUELISTA, "branch": 1, "tier": 4, "req": ["due_punto"], "kind": "act", "pt": 12, "tgt": "enemy", "pow": 1.9, "dt": T1, "fx": {"crit": 0.2}, "desc": "Golpe muy fuerte con +20% de crítico."},
	{"id": "due_gracia", "name": "Golpe de gracia", "tree": D.DUELISTA, "branch": 1, "tier": 5, "req": ["due_corazon"], "kind": "act", "pt": 10, "tgt": "enemy", "pow": 1.2, "dt": -1, "fx": {"exec": 2.0}, "desc": "Doble daño a quien tenga menos del 30% de vida."},
	{"id": "due_desarme", "name": "Desarme", "tree": D.DUELISTA, "branch": 2, "tier": 1, "req": [], "kind": "act", "pt": 5, "tgt": "enemy", "pow": 0.6, "dt": -1, "st": [["desarmado", 0.65, 2]], "desc": "Le quita el arma: pega mucho menos."},
	{"id": "due_danza", "name": "Danza de espadas", "tree": D.DUELISTA, "branch": 2, "tier": 2, "req": ["due_desarme"], "kind": "pas", "fx": {"agilidad": 2, "evasion": 0.05}, "desc": "+2 de Agilidad y +5% de esquiva."},
	{"id": "due_paso", "name": "Paso lateral", "tree": D.DUELISTA, "branch": 2, "tier": 3, "req": ["due_danza"], "kind": "act", "pt": 5, "tgt": "self", "st": [["oculto", 1.0, 1]], "desc": "Esquiva mucho y su próximo golpe busca el crítico."},
	{"id": "due_leer", "name": "Lectura del rival", "tree": D.DUELISTA, "branch": 2, "tier": 4, "req": ["due_danza"], "kind": "pas", "fx": {"punteria": 3, "status_res": 0.1}, "desc": "+3 de Puntería y resiste mejor los estados."},
	{"id": "due_reto", "name": "Reto de honor", "tree": D.DUELISTA, "branch": 2, "tier": 5, "req": ["due_desarme"], "kind": "act", "pt": 8, "tgt": "enemy", "pow": 1.4, "dt": -1, "st": [["provocado", 0.9, 2], ["marcado", 0.9, 2]], "desc": "Golpea, lo provoca y lo marca."},
	# --- TANQUE ---
	{"id": "tan_provocar", "name": "Provocar", "tree": D.TANQUE, "branch": 0, "tier": 1, "req": [], "kind": "act", "base": true, "pt": 5, "tgt": "enemies", "st": [["provocado", 0.85, 2]], "fx": {"self_st": [["fortaleza", 2]]}, "desc": "Los enemigos le atacan a él; se refuerza 2 turnos."},
	{"id": "tan_piel", "name": "Piel de hierro", "tree": D.TANQUE, "branch": 0, "tier": 2, "req": ["tan_provocar"], "kind": "pas", "fx": {"low_hp_taken": -0.3}, "desc": "−30% de daño con poca vida."},
	{"id": "tan_muro", "name": "Muro de escudos", "tree": D.TANQUE, "branch": 0, "tier": 3, "req": ["tan_provocar"], "kind": "pas", "fx": {"ally_taken": -0.1}, "desc": "Mientras esté en pie, su grupo recibe −10% de daño."},
	{"id": "tan_robusto", "name": "Robustez", "tree": D.TANQUE, "branch": 0, "tier": 3, "req": ["tan_piel"], "kind": "pas", "fx": {"pv_pct": 0.15}, "desc": "+15% de PV."},
	{"id": "tan_inamovible", "name": "Inamovible", "tree": D.TANQUE, "branch": 0, "tier": 5, "req": ["tan_robusto"], "kind": "pas", "fx": {"immune_derribo": 1, "status_res": 0.15}, "desc": "No lo derriban ni desequilibran."},
	{"id": "tan_cubrir", "name": "Cubrir", "tree": D.TANQUE, "branch": 1, "tier": 1, "req": [], "kind": "act", "pt": 4, "tgt": "ally", "fx": {"cover": 1}, "desc": "Recibe en su lugar los golpes dirigidos a un aliado."},
	{"id": "tan_golpe_escudo", "name": "Golpe de escudo", "tree": D.TANQUE, "branch": 1, "tier": 2, "req": ["tan_cubrir"], "kind": "act", "pt": 6, "tgt": "enemy", "pow": 0.8, "dt": T2, "st": [["aturdido", 0.35, 1]], "desc": "Puede aturdir."},
	{"id": "tan_guardia", "name": "Guardia férrea", "tree": D.TANQUE, "branch": 1, "tier": 3, "req": ["tan_cubrir"], "kind": "pas", "fx": {"guard": 0.25}, "desc": "Defender reduce aún más el daño."},
	{"id": "tan_represalia", "name": "Represalia", "tree": D.TANQUE, "branch": 1, "tier": 4, "req": ["tan_guardia"], "kind": "pas", "fx": {"counter": 0.2}, "desc": "+20% de responder a los golpes."},
	{"id": "tan_fortaleza", "name": "Fortaleza", "tree": D.TANQUE, "branch": 1, "tier": 4, "req": ["tan_golpe_escudo"], "kind": "act", "pt": 6, "tgt": "self", "st": [["fortaleza", 1.0, 3]], "desc": "+50% de Defensa durante 3 turnos."},
	{"id": "tan_mazazo", "name": "Golpe pesado", "tree": D.TANQUE, "branch": 2, "tier": 1, "req": [], "kind": "act", "base": true, "pt": 4, "tgt": "enemy", "pow": 1.3, "dt": -1, "desc": "Golpe con todo el peso del arma."},
	{"id": "tan_rompe", "name": "Rompearmaduras", "tree": D.TANQUE, "branch": 2, "tier": 2, "req": ["tan_mazazo"], "kind": "act", "pt": 7, "tgt": "enemy", "pow": 1.0, "dt": T2, "st": [["desequilibrado", 0.65, 2]], "desc": "Desequilibra al rival."},
	{"id": "tan_fuerza", "name": "Fuerza bruta", "tree": D.TANQUE, "branch": 2, "tier": 3, "req": ["tan_mazazo"], "kind": "pas", "fx": {"fuerza_pct": 0.1}, "desc": "+10% de Fuerza."},
	{"id": "tan_derribo", "name": "Derribo", "tree": D.TANQUE, "branch": 2, "tier": 3, "req": ["tan_rompe"], "kind": "act", "pt": 9, "tgt": "enemy", "pow": 1.0, "dt": T2, "st": [["derribado", 0.5, 1]], "desc": "Puede derribar (débil a todo)."},
	{"id": "tan_terremoto", "name": "Terremoto", "tree": D.TANQUE, "branch": 2, "tier": 5, "req": ["tan_derribo"], "kind": "act", "pt": 14, "tgt": "enemies", "pow": 0.8, "dt": T2, "st": [["desequilibrado", 0.35, 2]], "desc": "Golpea a todos y puede desequilibrarlos."},
	# --- ESTRATEGA ---
	{"id": "est_orden", "name": "Orden de ataque", "tree": D.ESTRATEGA, "branch": 0, "tier": 1, "req": [], "kind": "act", "base": true, "pt": 5, "tgt": "ally", "st": [["inspirado", 1.0, 2]], "fx": {"advance": 1}, "desc": "Un aliado actúa ya, inspirado."},
	{"id": "est_grito", "name": "Grito de guerra", "tree": D.ESTRATEGA, "branch": 0, "tier": 2, "req": ["est_orden"], "kind": "act", "pt": 9, "tgt": "allies", "st": [["inspirado", 1.0, 3]], "desc": "Todo el grupo inspirado 3 turnos."},
	{"id": "est_lider", "name": "Liderazgo nato", "tree": D.ESTRATEGA, "branch": 0, "tier": 3, "req": ["est_orden"], "kind": "pas", "fx": {"ally_dmg": 0.06}, "desc": "Su grupo hace +6% de daño."},
	{"id": "est_arenga", "name": "Arenga", "tree": D.ESTRATEGA, "branch": 0, "tier": 3, "req": ["est_grito"], "kind": "act", "pt": 10, "tgt": "allies", "heal": 0.12, "fx": {"morale": 15}, "desc": "Cura un poco y sube la moral del grupo."},
	{"id": "est_estandarte", "name": "Estandarte en alto", "tree": D.ESTRATEGA, "branch": 0, "tier": 5, "req": ["est_lider"], "kind": "pas", "fx": {"ally_taken": -0.06, "voluntad": 3}, "desc": "Su grupo recibe −6% de daño."},
	{"id": "est_analizar", "name": "Analizar", "tree": D.ESTRATEGA, "branch": 1, "tier": 1, "req": [], "kind": "act", "base": true, "pt": 4, "tgt": "enemy", "pow": 0.9, "dt": -1, "st": [["marcado", 1.0, 3]], "desc": "Marca al rival: recibe +20% de daño."},
	{"id": "est_leer", "name": "Leer al enemigo", "tree": D.ESTRATEGA, "branch": 1, "tier": 2, "req": ["est_analizar"], "kind": "pas", "fx": {"punteria": 2, "evasion": 0.04}, "desc": "+2 de Puntería y +4% de esquiva."},
	{"id": "est_emboscada", "name": "Emboscada", "tree": D.ESTRATEGA, "branch": 1, "tier": 3, "req": ["est_analizar"], "kind": "act", "pt": 8, "tgt": "enemy", "pow": 1.3, "dt": -1, "fx": {"crit": 0.25}, "desc": "Ataque calculado: +25% de crítico."},
	{"id": "est_retirada", "name": "Retirada ordenada", "tree": D.ESTRATEGA, "branch": 1, "tier": 3, "req": ["est_leer"], "kind": "pas", "fx": {"retreat": 0.3, "agilidad": 1}, "desc": "+30% de éxito al retirarse."},
	{"id": "est_coordinado", "name": "Ataque coordinado", "tree": D.ESTRATEGA, "branch": 1, "tier": 5, "req": ["est_emboscada"], "kind": "act", "pt": 14, "tgt": "enemy", "pow": 0.55, "dt": -1, "fx": {"per_ally": 1}, "desc": "Daño según los aliados en pie."},
	{"id": "est_engano", "name": "Engaño", "tree": D.ESTRATEGA, "branch": 2, "tier": 1, "req": [], "kind": "act", "pt": 7, "tgt": "enemy", "st": [["aturdido", 0.5, 1]], "desc": "Puede aturdir (pierde su turno)."},
	{"id": "est_trampa", "name": "Trampa", "tree": D.ESTRATEGA, "branch": 2, "tier": 2, "req": ["est_engano"], "kind": "act", "pt": 10, "tgt": "enemies", "st": [["desequilibrado", 0.4, 2]], "desc": "Puede desequilibrar a todos."},
	{"id": "est_iniciativa", "name": "Iniciativa", "tree": D.ESTRATEGA, "branch": 2, "tier": 3, "req": ["est_engano"], "kind": "pas", "fx": {"agilidad": 3}, "desc": "+3 de Agilidad."},
	{"id": "est_contramedida", "name": "Contramedida", "tree": D.ESTRATEGA, "branch": 2, "tier": 4, "req": ["est_iniciativa"], "kind": "pas", "fx": {"status_res": 0.2}, "desc": "Resiste mejor los estados."},
	{"id": "est_jaque", "name": "Jaque", "tree": D.ESTRATEGA, "branch": 2, "tier": 5, "req": ["est_trampa"], "kind": "act", "pt": 12, "tgt": "enemy", "pow": 1.4, "dt": -1, "fx": {"vs_status": 1.5}, "desc": "×1,5 contra quien sufra un estado."},
	# --- BERSERKER ---
	{"id": "ber_furia", "name": "Furia", "tree": D.BERSERKER, "branch": 0, "tier": 1, "req": [], "kind": "act", "base": true, "pt": 4, "tgt": "self", "st": [["furia", 1.0, 2]], "desc": "2 turnos: +40% de daño y −30% de Defensa."},
	{"id": "ber_herido", "name": "Furia del herido", "tree": D.BERSERKER, "branch": 0, "tier": 2, "req": ["ber_furia"], "kind": "pas", "fx": {"low_hp_dmg": 0.35}, "desc": "+35% de daño con poca vida."},
	{"id": "ber_grito", "name": "Grito salvaje", "tree": D.BERSERKER, "branch": 0, "tier": 3, "req": ["ber_furia"], "kind": "act", "pt": 8, "tgt": "enemies", "st": [["debilitado", 0.45, 3]], "desc": "Puede debilitar a todos."},
	{"id": "ber_sed", "name": "Sed de sangre", "tree": D.BERSERKER, "branch": 0, "tier": 3, "req": ["ber_herido"], "kind": "pas", "fx": {"lifesteal": 0.12}, "desc": "Recupera el 12% del daño que hace."},
	{"id": "ber_desenfreno", "name": "Desenfreno", "tree": D.BERSERKER, "branch": 0, "tier": 5, "req": ["ber_sed"], "kind": "act", "pt": 14, "tgt": "random3", "pow": 0.75, "dt": -1, "hits": 3, "desc": "3 golpes a enemigos al azar."},
	{"id": "ber_tajo", "name": "Golpe brutal", "tree": D.BERSERKER, "branch": 1, "tier": 1, "req": [], "kind": "act", "base": true, "pt": 4, "tgt": "enemy", "pow": 1.35, "dt": -1, "desc": "Golpe salvaje con su arma."},
	{"id": "ber_barrido", "name": "Barrido", "tree": D.BERSERKER, "branch": 1, "tier": 2, "req": ["ber_tajo"], "kind": "act", "pt": 9, "tgt": "enemies", "pow": 0.65, "dt": -1, "desc": "Golpea a todos los enemigos."},
	{"id": "ber_hachazo", "name": "Hachazo", "tree": D.BERSERKER, "branch": 1, "tier": 3, "req": ["ber_tajo"], "kind": "act", "pt": 8, "tgt": "enemy", "pow": 1.8, "dt": -1, "fx": {"acc": -0.1}, "desc": "Muy fuerte, algo impreciso."},
	{"id": "ber_salvaje", "name": "Golpe salvaje", "tree": D.BERSERKER, "branch": 1, "tier": 4, "req": ["ber_hachazo"], "kind": "pas", "fx": {"crit": 0.05, "fuerza_pct": 0.05}, "desc": "+5% de crítico y de Fuerza."},
	{"id": "ber_decapitar", "name": "Decapitar", "tree": D.BERSERKER, "branch": 1, "tier": 5, "req": ["ber_hachazo"], "kind": "act", "pt": 15, "tgt": "enemy", "pow": 2.4, "dt": -1, "desc": "El golpe más brutal."},
	{"id": "ber_herida", "name": "Herida abierta", "tree": D.BERSERKER, "branch": 2, "tier": 1, "req": [], "kind": "act", "pt": 5, "tgt": "enemy", "pow": 0.9, "dt": -1, "st": [["sangrado", 0.7, 3]], "desc": "Hace sangrar 3 turnos."},
	{"id": "ber_aliento", "name": "Aliento de bestia", "tree": D.BERSERKER, "branch": 2, "tier": 2, "req": ["ber_herida"], "kind": "pas", "fx": {"pt_regen": 2}, "desc": "+2 PT por turno."},
	{"id": "ber_incansable", "name": "Incansable", "tree": D.BERSERKER, "branch": 2, "tier": 3, "req": ["ber_aliento"], "kind": "pas", "fx": {"pv_pct": 0.1}, "desc": "+10% de PV."},
	{"id": "ber_temple", "name": "Sangre fría", "tree": D.BERSERKER, "branch": 2, "tier": 4, "req": ["ber_incansable"], "kind": "pas", "fx": {"voluntad": 3, "status_res": 0.1}, "desc": "+3 de Voluntad."},
	{"id": "ber_ultimo", "name": "Último aliento", "tree": D.BERSERKER, "branch": 2, "tier": 5, "req": ["ber_temple"], "kind": "pas", "fx": {"last_stand": 1}, "desc": "Una vez por combate aguanta con 1 PV."},
	# --- DEFENSOR ---
	{"id": "def_cubrir", "name": "Escudar", "tree": D.DEFENSOR, "branch": 0, "tier": 1, "req": [], "kind": "act", "base": true, "pt": 4, "tgt": "ally", "fx": {"cover": 1}, "desc": "Recibe los golpes dirigidos a un aliado."},
	{"id": "def_muro", "name": "Muro de escudos", "tree": D.DEFENSOR, "branch": 0, "tier": 2, "req": ["def_cubrir"], "kind": "pas", "fx": {"ally_taken": -0.1}, "desc": "Mientras esté en pie, su grupo recibe −10% de daño."},
	{"id": "def_parada", "name": "Parada", "tree": D.DEFENSOR, "branch": 0, "tier": 3, "req": ["def_cubrir"], "kind": "pas", "fx": {"guard": 0.25, "counter": 0.08}, "desc": "Mejor guardia y algo de respuesta."},
	{"id": "def_alzado", "name": "Escudos en alto", "tree": D.DEFENSOR, "branch": 0, "tier": 3, "req": ["def_muro"], "kind": "act", "pt": 10, "tgt": "allies", "st": [["fortaleza", 1.0, 2]], "desc": "+50% de Defensa al grupo 2 turnos."},
	{"id": "def_bastion", "name": "Bastión", "tree": D.DEFENSOR, "branch": 0, "tier": 5, "req": ["def_alzado"], "kind": "pas", "fx": {"pv_pct": 0.12, "defensa": 2}, "desc": "+12% de PV y +2 de Defensa."},
	{"id": "def_vendaje", "name": "Vendaje", "tree": D.DEFENSOR, "branch": 1, "tier": 1, "req": [], "kind": "act", "base": true, "pt": 6, "tgt": "ally", "heal": 0.3, "desc": "Cura el 30% de la vida de un aliado."},
	{"id": "def_plegaria", "name": "Plegaria", "tree": D.DEFENSOR, "branch": 1, "tier": 2, "req": ["def_vendaje"], "kind": "act", "pt": 12, "tgt": "allies", "heal": 0.15, "desc": "Cura un poco a todo el grupo."},
	{"id": "def_purificar", "name": "Purificar", "tree": D.DEFENSOR, "branch": 1, "tier": 3, "req": ["def_vendaje"], "kind": "act", "pt": 5, "tgt": "ally", "heal": 0.08, "fx": {"cleanse": 1}, "desc": "Quita los estados de un aliado."},
	{"id": "def_fe", "name": "Fe inquebrantable", "tree": D.DEFENSOR, "branch": 1, "tier": 4, "req": ["def_purificar"], "kind": "pas", "fx": {"status_res": 0.2, "voluntad": 2}, "desc": "Resiste mejor los estados."},
	{"id": "def_milagro", "name": "Milagro", "tree": D.DEFENSOR, "branch": 1, "tier": 5, "req": ["def_plegaria"], "kind": "act", "pt": 18, "tgt": "ko_ally", "fx": {"revive": 0.35}, "desc": "Levanta a un aliado caído (no en lucha a muerte)."},
	{"id": "def_empellon", "name": "Empellón", "tree": D.DEFENSOR, "branch": 2, "tier": 1, "req": [], "kind": "act", "pt": 5, "tgt": "enemy", "pow": 0.9, "dt": T2, "st": [["desequilibrado", 0.55, 2]], "desc": "Puede desequilibrar."},
	{"id": "def_contra", "name": "Contragolpe", "tree": D.DEFENSOR, "branch": 2, "tier": 2, "req": ["def_empellon"], "kind": "pas", "fx": {"counter": 0.15}, "desc": "+15% de responder a los golpes."},
	{"id": "def_venganza", "name": "Venganza", "tree": D.DEFENSOR, "branch": 2, "tier": 3, "req": ["def_contra"], "kind": "act", "pt": 8, "tgt": "enemy", "pow": 1.0, "dt": -1, "fx": {"scale_missing": 1}, "desc": "Más daño cuanta menos vida le quede."},
	{"id": "def_castigo", "name": "Castigo", "tree": D.DEFENSOR, "branch": 2, "tier": 4, "req": ["def_empellon"], "kind": "act", "pt": 9, "tgt": "enemy", "pow": 1.3, "dt": T2, "st": [["debilitado", 0.5, 3]], "desc": "Golpe que puede debilitar."},
	{"id": "def_juramento", "name": "Juramento", "tree": D.DEFENSOR, "branch": 2, "tier": 5, "req": ["def_venganza"], "kind": "pas", "fx": {"avenge": 0.25}, "desc": "+25% de daño por cada aliado caído."},
	# --- ASESINO ---
	{"id": "ase_punal", "name": "Puñalada", "tree": D.ASESINO, "branch": 0, "tier": 1, "req": [], "kind": "act", "base": true, "pt": 4, "tgt": "enemy", "pow": 1.2, "dt": -1, "fx": {"crit": 0.12}, "desc": "+12% de crítico."},
	{"id": "ase_evasion", "name": "Evasión", "tree": D.ASESINO, "branch": 0, "tier": 2, "req": ["ase_punal"], "kind": "pas", "fx": {"evasion": 0.07}, "desc": "+7% de esquiva."},
	{"id": "ase_veloz", "name": "Paso veloz", "tree": D.ASESINO, "branch": 0, "tier": 3, "req": ["ase_punal"], "kind": "pas", "fx": {"agilidad": 3}, "desc": "+3 de Agilidad."},
	{"id": "ase_desaparecer", "name": "Desaparecer", "tree": D.ASESINO, "branch": 0, "tier": 3, "req": ["ase_evasion"], "kind": "act", "pt": 6, "tgt": "self", "st": [["oculto", 1.0, 1]], "desc": "Casi no le aciertan y su próximo golpe busca el crítico."},
	{"id": "ase_espalda", "name": "Golpe por la espalda", "tree": D.ASESINO, "branch": 0, "tier": 5, "req": ["ase_desaparecer"], "kind": "act", "pt": 12, "tgt": "enemy", "pow": 1.7, "dt": -1, "fx": {"crit": 0.3}, "desc": "+30% de crítico."},
	{"id": "ase_hoja", "name": "Hoja envenenada", "tree": D.ASESINO, "branch": 1, "tier": 1, "req": [], "kind": "act", "base": true, "pt": 5, "tgt": "enemy", "pow": 0.8, "dt": -1, "st": [["sangrado", 0.8, 3]], "desc": "Envenena: sangra 3 turnos."},
	{"id": "ase_toxinas", "name": "Toxinas", "tree": D.ASESINO, "branch": 1, "tier": 2, "req": ["ase_hoja"], "kind": "pas", "fx": {"bleed_bonus": 0.5}, "desc": "Su sangrado hace +50% de daño."},
	{"id": "ase_polvo", "name": "Polvo a los ojos", "tree": D.ASESINO, "branch": 1, "tier": 3, "req": ["ase_hoja"], "kind": "act", "pt": 9, "tgt": "enemies", "st": [["cegado", 0.55, 2]], "desc": "Puede cegar a todos (fallan más)."},
	{"id": "ase_debilitar", "name": "Veneno debilitante", "tree": D.ASESINO, "branch": 1, "tier": 3, "req": ["ase_toxinas"], "kind": "act", "pt": 6, "tgt": "enemy", "pow": 0.6, "dt": -1, "st": [["debilitado", 0.7, 3]], "desc": "Debilita: menos Fuerza y Defensa."},
	{"id": "ase_letal", "name": "Veneno letal", "tree": D.ASESINO, "branch": 1, "tier": 5, "req": ["ase_debilitar"], "kind": "act", "pt": 14, "tgt": "enemy", "pow": 1.0, "dt": -1, "st": [["sangrado", 1.0, 3], ["aturdido", 0.35, 1]], "desc": "Sangrado seguro y puede aturdir."},
	{"id": "ase_ojo", "name": "Ojo certero", "tree": D.ASESINO, "branch": 2, "tier": 1, "req": [], "kind": "pas", "fx": {"crit": 0.06, "crit_mult": 0.2}, "desc": "+6% de crítico, críticos más dañinos."},
	{"id": "ase_remate", "name": "Remate", "tree": D.ASESINO, "branch": 2, "tier": 2, "req": ["ase_ojo"], "kind": "act", "pt": 7, "tgt": "enemy", "pow": 1.0, "dt": -1, "fx": {"exec": 2.2}, "desc": "×2,2 a quien tenga menos del 30% de vida."},
	{"id": "ase_precision", "name": "Precisión mortal", "tree": D.ASESINO, "branch": 2, "tier": 3, "req": ["ase_ojo"], "kind": "pas", "fx": {"crit_mult": 0.3}, "desc": "Críticos aún más dañinos."},
	{"id": "ase_tendones", "name": "Cortar tendones", "tree": D.ASESINO, "branch": 2, "tier": 4, "req": ["ase_remate"], "kind": "act", "pt": 8, "tgt": "enemy", "pow": 0.8, "dt": -1, "st": [["desequilibrado", 0.7, 2]], "desc": "Puede desequilibrar."},
	{"id": "ase_ejecucion", "name": "Ejecución", "tree": D.ASESINO, "branch": 2, "tier": 5, "req": ["ase_remate"], "kind": "act", "pt": 16, "tgt": "enemy", "pow": 2.3, "dt": -1, "fx": {"crit": 0.1}, "desc": "Golpe letal."},
	# --- COMUNES: Mando y apoyo ---
	{"id": "com_grito", "name": "Grito de ánimo", "tree": TREE_COMMON, "branch": 0, "tier": 1, "req": [], "kind": "act", "pt": 5, "tgt": "ally", "st": [["inspirado", 1.0, 3]], "desc": "Inspira a un aliado 3 turnos."},
	{"id": "com_auxilios", "name": "Primeros auxilios", "tree": TREE_COMMON, "branch": 0, "tier": 1, "req": [], "kind": "act", "pt": 6, "tgt": "ally", "heal": 0.2, "desc": "Cura el 20% de la vida."},
	{"id": "com_voz", "name": "Voz de mando", "tree": TREE_COMMON, "branch": 0, "tier": 3, "req": ["com_grito"], "kind": "pas", "fx": {"ally_dmg": 0.04, "voluntad": 2}, "desc": "Su grupo hace +4% de daño."},
	{"id": "com_proteger", "name": "Proteger", "tree": TREE_COMMON, "branch": 0, "tier": 3, "req": ["com_auxilios"], "kind": "act", "pt": 4, "tgt": "ally", "fx": {"cover": 1}, "desc": "Recibe los golpes dirigidos a un aliado."},
	{"id": "com_intimidar", "name": "Intimidar", "tree": TREE_COMMON, "branch": 0, "tier": 4, "req": ["com_voz"], "kind": "act", "pt": 8, "tgt": "enemies", "st": [["debilitado", 0.4, 2]], "desc": "Puede debilitar a todos."},
	{"id": "com_estratagema", "name": "Estratagema", "tree": TREE_COMMON, "branch": 0, "tier": 5, "req": ["com_voz"], "kind": "pas", "fx": {"pt_pct": 0.15}, "desc": "+15% de PT."},
	# Supervivencia
	{"id": "com_aguante", "name": "Aguante", "tree": TREE_COMMON, "branch": 1, "tier": 1, "req": [], "kind": "pas", "fx": {"pv_pct": 0.08}, "desc": "+8% de PV."},
	{"id": "com_segundo", "name": "Segundo aliento", "tree": TREE_COMMON, "branch": 1, "tier": 2, "req": ["com_aguante"], "kind": "pas", "fx": {"pt_regen": 1}, "desc": "+1 PT por turno."},
	{"id": "com_reflejos", "name": "Reflejos", "tree": TREE_COMMON, "branch": 1, "tier": 2, "req": ["com_aguante"], "kind": "pas", "fx": {"agilidad": 1, "evasion": 0.04}, "desc": "+1 de Agilidad y +4% de esquiva."},
	{"id": "com_piel", "name": "Piel curtida", "tree": TREE_COMMON, "branch": 1, "tier": 3, "req": ["com_aguante"], "kind": "pas", "fx": {"low_hp_taken": -0.2}, "desc": "−20% de daño con poca vida."},
	{"id": "com_viento", "name": "Segundo viento", "tree": TREE_COMMON, "branch": 1, "tier": 3, "req": ["com_segundo"], "kind": "act", "pt": 8, "tgt": "self", "heal": 0.3, "desc": "Se cura el 30%."},
	{"id": "com_temple", "name": "Temple", "tree": TREE_COMMON, "branch": 1, "tier": 4, "req": ["com_reflejos"], "kind": "pas", "fx": {"voluntad": 3, "status_res": 0.15}, "desc": "+3 de Voluntad y resiste estados."},
	# Maestría de arma
	{"id": "com_tajo1", "name": "Maestría: Tajo", "tree": TREE_COMMON, "branch": 2, "tier": 1, "req": [], "kind": "pas", "fx": {"dmg_t0": 0.1}, "desc": "+10% de daño de Tajo."},
	{"id": "com_tajo2", "name": "Corte en arco", "tree": TREE_COMMON, "branch": 2, "tier": 3, "req": ["com_tajo1"], "kind": "act", "pt": 10, "tgt": "enemies", "pow": 0.7, "dt": T0, "desc": "Tajo a todos los enemigos."},
	{"id": "com_esto1", "name": "Maestría: Estocada", "tree": TREE_COMMON, "branch": 2, "tier": 1, "req": [], "kind": "pas", "fx": {"dmg_t1": 0.1}, "desc": "+10% de daño de Estocada."},
	{"id": "com_esto2", "name": "Estocada precisa", "tree": TREE_COMMON, "branch": 2, "tier": 3, "req": ["com_esto1"], "kind": "act", "pt": 8, "tgt": "enemy", "pow": 1.4, "dt": T1, "fx": {"pierce": 1}, "desc": "Atraviesa la armadura (no la resiste)."},
	{"id": "com_cont1", "name": "Maestría: Contundente", "tree": TREE_COMMON, "branch": 2, "tier": 1, "req": [], "kind": "pas", "fx": {"dmg_t2": 0.1}, "desc": "+10% de daño Contundente."},
	{"id": "com_cont2", "name": "Golpe aplastante", "tree": TREE_COMMON, "branch": 2, "tier": 3, "req": ["com_cont1"], "kind": "act", "pt": 8, "tgt": "enemy", "pow": 1.1, "dt": T2, "st": [["desequilibrado", 0.5, 2]], "desc": "Puede desequilibrar."},
	{"id": "com_proy1", "name": "Maestría: Proyectil", "tree": TREE_COMMON, "branch": 2, "tier": 1, "req": [], "kind": "pas", "fx": {"dmg_t3": 0.1}, "desc": "+10% de daño de Proyectil."},
	{"id": "com_proy2", "name": "Disparo", "tree": TREE_COMMON, "branch": 2, "tier": 2, "req": ["com_proy1"], "kind": "act", "pt": 5, "tgt": "enemy", "pow": 1.1, "dt": T3, "desc": "Dispara aunque no lleve arco."},
	# --- ENEMIGOS Y MINI JEFES (no se aprenden) ---
	{"id": "ene_carga", "name": "Carga", "tree": TREE_BOSS, "branch": 0, "tier": 1, "req": [], "kind": "act", "pt": 8, "tgt": "enemy", "pow": 1.8, "dt": T1, "st": [["derribado", 0.35, 1]], "desc": "Carga a caballo: puede derribar."},
	{"id": "ene_virote", "name": "Virote perforante", "tree": TREE_BOSS, "branch": 0, "tier": 1, "req": [], "kind": "act", "pt": 6, "tgt": "enemy", "pow": 1.4, "dt": T3, "fx": {"pierce": 1}, "desc": "Atraviesa cualquier armadura."},
	{"id": "ene_picas", "name": "Muro de picas", "tree": TREE_BOSS, "branch": 0, "tier": 1, "req": [], "kind": "pas", "fx": {"counter": 0.25}, "desc": "Castiga a quien se acerca."},
	{"id": "jef_saqueo", "name": "Saqueo", "tree": TREE_BOSS, "branch": 1, "tier": 1, "req": [], "kind": "act", "pt": 8, "tgt": "enemy", "pow": 1.3, "dt": -1, "fx": {"pt_drain": 10}, "desc": "Golpea y roba PT."},
	{"id": "jef_formacion", "name": "¡Formación!", "tree": TREE_BOSS, "branch": 1, "tier": 1, "req": [], "kind": "act", "pt": 10, "tgt": "allies", "st": [["fortaleza", 1.0, 2], ["inspirado", 1.0, 2]], "desc": "Refuerza e inspira a los suyos."},
	{"id": "jef_campeon", "name": "Lanzada de campeón", "tree": TREE_BOSS, "branch": 1, "tier": 1, "req": [], "kind": "act", "pt": 10, "tgt": "enemy", "pow": 2.0, "dt": T1, "fx": {"crit": 0.2}, "desc": "La lanzada que gana torneos."},
	{"id": "jef_carga_sagrada", "name": "Carga sagrada", "tree": TREE_BOSS, "branch": 1, "tier": 1, "req": [], "kind": "act", "pt": 14, "tgt": "enemies", "pow": 1.0, "dt": -1, "st": [["derribado", 0.3, 1]], "desc": "Arrolla a todos."},
	{"id": "jef_turba", "name": "Turba descalza", "tree": TREE_BOSS, "branch": 1, "tier": 1, "req": [], "kind": "act", "pt": 12, "tgt": "random3", "pow": 0.6, "dt": T2, "hits": 4, "desc": "4 golpes al azar."},
	{"id": "jef_vigilia", "name": "Vigilia del guardián", "tree": TREE_BOSS, "branch": 1, "tier": 1, "req": [], "kind": "act", "pt": 10, "tgt": "self", "heal": 0.2, "st": [["fortaleza", 1.0, 2]], "desc": "Se cura y se refuerza."},
]

# Habilidades de combate y de batalla antiguas → nodo que conceden gratis (no gastan puntos).
const LEGACY_SKILL_NODES := {
	"Desarme Fulminante": "due_desarme", "Mano Rápida": "due_desarme", "Piel de Hierro": "tan_piel",
	"Golpe Certero": "due_certero", "Maestro de Parada": "def_parada", "Danza de Espadas": "com_reflejos",
	"Fuerza Bruta": "tan_fuerza", "Resistencia": "com_aguante", "Segundo Aliento": "com_segundo",
	"Furia del Herido": "ber_herido", "Contragolpe Letal": "due_contra", "Ojo de Halcón": "due_halcon",
	"Guardia Férrea": "tan_guardia", "Zancadilla": "com_cont2", "Iniciativa": "est_iniciativa",
	"Temple": "com_temple", "Rostro de Piedra": "com_temple", "Intimidación": "com_intimidar",
	"Lectura del Rival": "est_leer", "Maestro de Esgrima": "due_guardia", "Muro de Acero": "tan_muro",
	"Furia Desatada": "ber_furia",
	"Grito de Guerra": "com_grito", "Muro de Escudos": "tan_muro", "Ataque Coordinado": "com_voz",
	"Lluvia de Flechas": "com_proy1", "Arqueros de Élite": "com_proy2", "Escolta del General": "com_proteger",
	"Leer al Enemigo": "est_leer", "Disciplina de Hierro": "com_temple", "Estandarte Sagrado": "def_fe",
	"Carga Letal": "com_esto2", "Muro de Picas": "com_esto1", "Represalia": "tan_represalia",
}
# Equipo que concede un nodo mientras se lleva puesto.
const EQUIPMENT_NODES := {
	"Estoque de Duelo": "due_guardia", "Manual de Esgrima": "due_guardia", "Hacha de Berserker": "ber_furia",
	"Pavés": "tan_muro", "Escudo de Cometa": "com_proteger", "Arco Largo": "com_proy2",
	"Ballesta de Cranequín": "ene_virote", "Lanza": "com_esto1", "Bolsa de Hierbas": "com_auxilios",
}
# Piezas únicas (SkillEffects.UNIQUE_*) → efecto pasivo en el RPG.
const UNIQUE_FX := {
	"durandal": {"first_sure": 1}, "sangrado": {"on_hit_bleed": 1}, "anticritico": {"crit_ward": 1},
	"reflejo": {"reflect": 0.25}, "firmeza": {"immune_derribo": 1}, "oriflama": {"voluntad": 4},
	"olifante": {"pt_pct": 0.15}, "reliquia": {"status_res": 0.2}, "babieca": {"agilidad": 2},
	"elocuencia": {"voluntad": 2}, "camino_seguro": {"evasion": 0.03}, "sello": {"voluntad": 2},
}

static var _by_id := {}

static func node(id: String) -> Dictionary:
	if _by_id.is_empty():
		for n: Dictionary in NODES:
			_by_id[n.id] = n
	return _by_id.get(id, {})

static func nodes_of_tree(tree: int) -> Array:
	return NODES.filter(func(n: Dictionary) -> bool: return n.tree == tree)

static func required_level(n: Dictionary) -> int:
	return TIER_LEVEL[clampi(int(n.tier), 0, TIER_LEVEL.size() - 1)]

## Nodos concedidos sin gastar puntos: habilidades antiguas y equipo puesto.
static func granted(c: Character) -> Array:
	var out := []
	for list in [c.combat_skills, c.battle_skills]:
		for s: Skill in list:
			if s != null and LEGACY_SKILL_NODES.has(s.skill_name) and not LEGACY_SKILL_NODES[s.skill_name] in out:
				out.append(LEGACY_SKILL_NODES[s.skill_name])
	for e: Equipment in c.equipment:
		if e != null and EQUIPMENT_NODES.has(e.equipment_name) and not EQUIPMENT_NODES[e.equipment_name] in out:
			out.append(EQUIPMENT_NODES[e.equipment_name])
	return out

static func knows(c: Character, id: String) -> bool:
	return id in c.learned_skills or id in granted(c)

static func known_ids(c: Character) -> Array:
	var out: Array = Array(c.learned_skills)
	for id in granted(c):
		if not id in out:
			out.append(id)
	return out

static func points_total(c: Character) -> int:
	return c.level * POINTS_PER_LEVEL

static func points_spent(c: Character) -> int:
	var spent := 0
	for id in c.learned_skills:
		var n := node(id)
		if not n.is_empty() and not n.get("base", false) and n.tree != TREE_BOSS:
			spent += 1
	return spent

static func points_free(c: Character) -> int:
	return points_total(c) - points_spent(c)

static func can_learn(c: Character, id: String) -> bool:
	var n := node(id)
	if n.is_empty() or knows(c, id):
		return false
	if n.tree != TREE_COMMON and n.tree != c.fighter_type:
		return false
	if c.level < required_level(n):
		return false
	for r in n.req:
		if not knows(c, r):
			return false
	return n.get("base", false) or points_free(c) >= 1

static func learn(c: Character, id: String) -> bool:
	if not can_learn(c, id):
		return false
	c.learned_skills.append(id)
	return true

## Kit mínimo: los nodos base del propio árbol (gratis). Para personajes antiguos sin árbol.
static func ensure_kit(c: Character) -> void:
	for n: Dictionary in nodes_of_tree(c.fighter_type):
		if n.get("base", false) and not n.id in c.learned_skills:
			c.learned_skills.append(n.id)

## PNJ y séquito: gastan todos sus puntos según su tipo (propio árbol y maestría de su arma primero).
static func auto_learn(c: Character) -> void:
	ensure_kit(c)
	var weapon_mastery: String = ["com_tajo1", "com_esto1", "com_cont1", "com_proy1"][RpgStats.weapon_type(c)]
	while points_free(c) > 0:
		var best := ""
		var best_score := -INF
		for n: Dictionary in NODES:
			if not can_learn(c, n.id):
				continue
			var score: float = -AUTO_TIER_PENALTY * n.tier
			if n.tree == c.fighter_type:
				score += AUTO_OWN_TREE_WEIGHT
			if n.id == weapon_mastery or weapon_mastery in n.req:
				score += AUTO_WEAPON_WEIGHT
			if n.kind == "act":
				score += AUTO_ACTIVE_WEIGHT
			score += float(abs(hash(c.first_name + n.id)) % 100) / 1000.0   # desempate estable
			if score > best_score:
				best_score = score
				best = n.id
		if best == "":
			break
		c.learned_skills.append(best)

## Técnicas activas que puede usar (aprendidas o concedidas).
static func available_techniques(c: Character) -> Array:
	var out := []
	for id in known_ids(c):
		var n := node(id)
		if not n.is_empty() and n.kind == "act":
			out.append(n)
	return out

## Suma de los efectos pasivos (nodos pasivos conocidos + piezas únicas).
static func passive_fx(c: Character) -> Dictionary:
	var out := {}
	var sources := []
	for id in known_ids(c):
		var n := node(id)
		if not n.is_empty() and n.kind == "pas":
			sources.append(n.get("fx", {}))
	for uid in UNIQUE_FX:
		if SkillEffects.has_unique(c, uid):
			sources.append(UNIQUE_FX[uid])
	for fx: Dictionary in sources:
		for k in fx:
			out[k] = out.get(k, 0.0) + float(fx[k])
	return out
