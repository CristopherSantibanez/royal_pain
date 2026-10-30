class_name SkillTreeCatalog
extends RefCounted
# Árboles de habilidades del combate RPG. Cada personaje tiene TRES árboles (trees_for):
#   1. su tipo de luchador (6: técnicas de combate),
#   2. su personalidad (12: actitud y apoyo; los rezos del Piadoso son moral, no magia),
#   3. su alineamiento (6: mando y moral).
# Cada árbol: 3 ramas de 7–8 nodos (22–24 por árbol). En cada rama: dos nodos «básicos» (escalón 1) y el
# resto de escalones 2–4: el 2 pide cualquiera de los básicos; el 3 y el 4, el último nodo del escalón anterior.
# Coste: escalón 1–2 = 1 punto, 3 = 2, 4 = 3. El PRIMER básico de cada rama es gratis (se elige al crear
# el personaje); el segundo básico de la misma rama cuesta 1 punto.
# Puntos: ESCASOS. points_for_level(nivel) = nivel / 3 (1 punto cada 3 niveles; Character lo usa al subir
# de nivel) + fuentes raras con grant_points(c, n, motivo): hazañas, maestros, libros, finales de historia.
# Los puntos extra se guardan en learned_skills como "@pt:<n>:<motivo>" (las entradas con "@" no son nodos).
#
# API: trees_for(c), tree(id), node(id), basic_nodes(tree, rama), all_nodes(), nodes_of_tree(tree),
#      cost_for(c, id), can_learn, learn, auto_learn (PNJ), ensure_kit, available_techniques, passive_fx,
#      points_for_level, points_total/spent/free, grant_points.
#
# Nodo: {id, name, tree (id de árbol), branch, tier, req [todos], req_any [alguno], cost, kind ("act"/"pas"),
#        desc, base?, req_troops?, req_morale? (fase 4: solo en campales; aquí se ignoran)}
#   activas: pt, tgt (enemy, enemies, random3, ally, allies, self, ko_ally), pow (×Fuerza; 0 = sin daño),
#            dt (tipo de daño del arma: Tajo/Estocada/Contundente/Proyectil; -1 = el del arma), hits,
#            st [[estado, probabilidad, turnos]], heal (× PV máx.),
#            fx {crit, acc, pierce, exec, scale_missing, vs_status, per_ally, cover, advance, cleanse, revive,
#                pt_drain, morale (± a los objetivos), self_st [[estado, turnos]], agi (suma Agilidad × v a la
#                Fuerza), estr (suma Estrategia × v), haste (los objetivos actúan antes), pt_give}
#   pasivas: fx {pv_pct, pt_pct, fuerza_pct, defensa, agilidad, punteria, voluntad, crit, crit_mult, evasion,
#                taken, counter, low_hp_dmg, low_hp_taken, guard, lifesteal, pt_regen, status_res, ally_taken,
#                ally_dmg, ally_hit, ally_crit, ally_init, ally_morale, fear, regen, heal_bonus,
#                immune_derribo, last_stand, bleed_bonus, retreat, avenge, dmg_t0..dmg_t3, first_sure,
#                on_hit_bleed, crit_ward, reflect, brecha (acción extra al conectar debilidad o crítico)}
# Estados y su significado: RpgBattleManager (analizado = sus resistencias no cuentan; sereno = recupera vida).

const TREE_BOSS := "boss"           # técnicas propias de enemigos y mini jefes (no se aprenden)
const TIER_LEVEL := [1, 1, 3, 6, 10]   # nivel mínimo por escalón
const TIER_COST := [0, 1, 1, 2, 3]
const LEVELS_PER_POINT := 3
const BONUS_PREFIX := "@pt:"
const AUTO_FIGHTER_WEIGHT := 2.0     # los PNJ prefieren su árbol de luchador...
const AUTO_ACTIVE_WEIGHT := 0.5      # ...y las técnicas activas
const AUTO_TIER_BONUS := 0.3

const T0 := 0   # Tajo
const T1 := 1   # Estocada
const T2 := 2   # Contundente
const T3 := 3   # Proyectil

# Árboles por enum (índice = valor del enum).
const FIGHTER_TREES := ["duelista", "tanque", "estratega", "berserker", "defensor", "asesino"]
const PERSONALITY_TREES := ["p_ambicioso", "p_leal", "p_prudente", "p_arrogante", "p_piadoso", "p_astuto",
	"p_valiente", "p_cruel", "p_generoso", "p_cobarde", "p_romantico", "p_honorable"]
const ALIGNMENT_TREES := ["a_conquistador", "a_pacifista", "a_ambicioso", "a_humilde", "a_diplomatico", "a_tirano"]

# id → [nombre, [[rama, [[id, nombre, datos], ...]], ...]]. Posición en la rama: 0–1 básicos, 2 → escalón 2,
# 3 → escalón 3, 4 → escalón 4; "t" en los datos fija el escalón (los nodos añadidos tras el 5.º lo llevan).
# Datos con "tgt" = activa; sin "tgt" = pasiva. "d" = descripción.
const TREES := {
	# ================= TIPOS DE LUCHADOR =================
	"duelista": ["Duelista", [
		["Esgrima", [
			["due_estocada", "Ataque rápido", {"pt": 4, "tgt": "enemy", "pow": 1.25, "fx": {"acc": 0.05}, "base": true, "d": "Golpe veloz y preciso."}],
			["due_desarme", "Desarme", {"pt": 5, "tgt": "enemy", "pow": 0.6, "st": [["desarmado", 0.65, 2]], "d": "Le quita el arma: pega mucho menos."}],
			["due_guardia", "Guardia de esgrima", {"pt": 6, "tgt": "self", "st": [["guardia_esgrima", 1.0, 2]], "d": "2 turnos: más esquiva y contraataque."}],
			["due_contra", "Contragolpe", {"fx": {"counter": 0.15}, "d": "+15% de contraatacar al recibir un golpe."}],
			["due_maestro", "Maestro de esgrima", {"fx": {"evasion": 0.08, "counter": 0.1}, "d": "+8% de esquiva y +10% de contraataque."}],
			["due_respuesta", "Respuesta", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 1.0, "dt": T1, "fx": {"acc": 0.1, "self_st": [["guardia_esgrima", 1]]}, "d": "Golpea y queda en guardia de esgrima 1 turno."}],
			["due_parada", "Parada perfecta", {"t": 3, "fx": {"evasion": 0.04, "guard": 0.2}, "d": "+4% de esquiva; defender reduce más el daño."}],
			["due_floreo", "Floreo de maestro", {"t": 4, "pt": 14, "tgt": "enemy", "pow": 1.7, "dt": T1, "fx": {"crit": 0.15, "acc": 0.1}, "d": "Estocada final con +15% de crítico y precisión."}]]],
		["Precisión", [
			["due_certero", "Golpe certero", {"fx": {"crit": 0.06}, "d": "+6% de crítico."}],
			["due_esto1", "Maestría: Estocada", {"fx": {"dmg_t1": 0.1}, "d": "+10% de daño de Estocada."}],
			["due_punto", "Punto débil", {"pt": 6, "tgt": "enemy", "pow": 1.0, "fx": {"pierce": 1, "crit": 0.1}, "d": "Ignora la resistencia de la armadura."}],
			["due_brecha", "Aprovechar la brecha", {"fx": {"brecha": 1}, "d": "Al conectar una debilidad o un crítico actúa otra vez (una vez por turno)."}],
			["due_corazon", "Estocada al corazón", {"pt": 12, "tgt": "enemy", "pow": 1.9, "dt": T1, "fx": {"crit": 0.2}, "d": "Golpe muy fuerte con +20% de crítico."}],
			["due_ojo_fino", "Ojo fino", {"t": 2, "fx": {"punteria": 2, "crit": 0.03}, "d": "+2 de Puntería y +3% de crítico."}],
			["due_tendon", "Corte al tendón", {"t": 3, "pt": 8, "tgt": "enemy", "pow": 1.0, "dt": T1, "st": [["desequilibrado", 0.6, 2], ["sangrado", 0.4, 2]], "d": "Desequilibra y puede hacer sangrar."}],
			["due_letal", "Estocada letal", {"t": 4, "fx": {"crit_mult": 0.25, "crit": 0.04}, "d": "Críticos un 25% más fuertes y +4% de crítico."}]]],
		["Elegancia", [
			["due_finta", "Finta", {"pt": 6, "tgt": "enemy", "pow": 0.9, "st": [["desequilibrado", 0.7, 2]], "d": "Engaña y desequilibra (débil a Contundente)."}],
			["due_danza", "Danza de espadas", {"fx": {"agilidad": 2, "evasion": 0.04}, "d": "+2 de Agilidad y +4% de esquiva."}],
			["due_paso", "Paso lateral", {"pt": 5, "tgt": "self", "st": [["oculto", 1.0, 1]], "d": "Esquiva mucho y su próximo golpe busca el crítico."}],
			["due_relampago", "Estocada relámpago", {"pt": 9, "tgt": "enemy", "pow": 1.0, "fx": {"agi": 0.6}, "d": "Suma su Agilidad a la fuerza del golpe."}],
			["due_pies", "Pies ligeros", {"t": 2, "fx": {"agilidad": 1, "evasion": 0.03}, "d": "+1 de Agilidad y +3% de esquiva."}],
			["due_vals", "Vals de acero", {"t": 3, "pt": 9, "tgt": "enemies", "pow": 0.6, "fx": {"agi": 0.3}, "d": "Recorre la fila enemiga sumando su Agilidad."}],
			["due_cisne", "Estocada del cisne", {"t": 4, "pt": 15, "tgt": "enemy", "pow": 1.3, "dt": T1, "st": [["marcado", 0.7, 2]], "fx": {"agi": 0.5, "acc": 0.15}, "d": "Golpe ágil que marca al rival."}]]],
	]],
	"tanque": ["Tanque", [
		["Baluarte", [
			["tan_provocar", "Provocar", {"pt": 5, "tgt": "enemies", "st": [["provocado", 0.85, 2]], "fx": {"self_st": [["fortaleza", 2]]}, "base": true, "d": "Los enemigos le atacan a él; se refuerza 2 turnos."}],
			["tan_piel", "Piel de hierro", {"fx": {"low_hp_taken": -0.2}, "d": "−20% de daño con poca vida."}],
			["tan_robusto", "Robustez", {"fx": {"pv_pct": 0.12}, "d": "+12% de PV."}],
			["tan_inamovible", "Inamovible", {"fx": {"immune_derribo": 1, "status_res": 0.15}, "d": "No lo derriban ni desequilibran."}],
			["tan_coloso", "Coloso", {"fx": {"pv_pct": 0.1, "defensa": 3}, "d": "+10% de PV y +3 de Defensa."}],
			["tan_aguantar", "Aguantar", {"t": 2, "pt": 5, "tgt": "self", "st": [["fortaleza", 1.0, 3]], "d": "Se refuerza 3 turnos."}],
			["tan_mole", "Mole", {"t": 3, "fx": {"defensa": 2, "status_res": 0.1}, "d": "+2 de Defensa y resiste estados."}],
			["tan_titan", "Titán", {"t": 4, "fx": {"last_stand": 1, "pv_pct": 0.08}, "d": "+8% de PV; una vez por combate aguanta con 1 PV."}]]],
		["Escudo", [
			["tan_cubrir", "Cubrir", {"pt": 4, "tgt": "ally", "fx": {"cover": 1}, "d": "Recibe en su lugar los golpes dirigidos a un aliado."}],
			["tan_golpe_escudo", "Golpe de escudo", {"pt": 6, "tgt": "enemy", "pow": 0.8, "dt": T2, "st": [["aturdido", 0.35, 1]], "d": "Puede aturdir."}],
			["tan_guardia", "Guardia férrea", {"fx": {"guard": 0.25}, "d": "Defender reduce aún más el daño."}],
			["tan_muro", "Muro de escudos", {"fx": {"ally_taken": -0.1}, "d": "Mientras esté en pie, su grupo recibe −10% de daño."}],
			["tan_represalia", "Represalia", {"fx": {"counter": 0.2, "reflect": 0.1}, "d": "+20% de responder y devuelve el 10% del daño."}],
			["tan_empujon", "Empujón de escudo", {"t": 2, "pt": 5, "tgt": "enemy", "pow": 0.6, "dt": T2, "st": [["desequilibrado", 0.6, 2]], "d": "Desequilibra al rival."}],
			["tan_tortuga", "Tortuga", {"t": 3, "pt": 10, "tgt": "allies", "st": [["fortaleza", 1.0, 2]], "d": "Todo el grupo tras los escudos 2 turnos."}],
			["tan_egida", "Égida", {"t": 4, "fx": {"ally_taken": -0.06, "guard": 0.15}, "d": "Su grupo recibe −6% de daño; defender protege más."}]]],
		["Aplastar", [
			["tan_mazazo", "Golpe pesado", {"pt": 4, "tgt": "enemy", "pow": 1.3, "base": true, "d": "Golpe con todo el peso del arma."}],
			["tan_cont1", "Maestría: Contundente", {"fx": {"dmg_t2": 0.1}, "d": "+10% de daño Contundente."}],
			["tan_rompe", "Rompearmaduras", {"pt": 7, "tgt": "enemy", "pow": 1.0, "dt": T2, "st": [["desequilibrado", 0.65, 2]], "d": "Desequilibra al rival."}],
			["tan_derribo", "Derribo", {"pt": 9, "tgt": "enemy", "pow": 1.0, "dt": T2, "st": [["derribado", 0.5, 1]], "d": "Puede derribar (débil a todo)."}],
			["tan_terremoto", "Terremoto", {"pt": 14, "tgt": "enemies", "pow": 0.8, "dt": T2, "st": [["desequilibrado", 0.35, 2]], "d": "Golpea a todos y puede desequilibrarlos."}],
			["tan_yunque", "Brazo de yunque", {"t": 2, "fx": {"fuerza_pct": 0.05, "dmg_t2": 0.05}, "d": "+5% de Fuerza y +5% de daño Contundente."}],
			["tan_martillo", "Martillazo", {"t": 3, "pt": 10, "tgt": "enemy", "pow": 1.4, "dt": T2, "st": [["aturdido", 0.4, 1]], "d": "Golpe brutal que puede aturdir."}],
			["tan_demoler", "Demoledor", {"t": 4, "pt": 16, "tgt": "enemy", "pow": 1.5, "dt": T2, "fx": {"pierce": 1, "vs_status": 1.3}, "d": "Atraviesa la armadura; más daño si el rival está tocado."}]]],
	]],
	"estratega": ["Estratega", [
		["Mando", [
			["est_orden", "Orden de ataque", {"pt": 5, "tgt": "ally", "st": [["inspirado", 1.0, 2]], "fx": {"advance": 1}, "base": true, "d": "Un aliado actúa ya, inspirado."}],
			["est_analizar", "Analizar", {"pt": 4, "tgt": "enemy", "st": [["analizado", 1.0, 3], ["marcado", 1.0, 2]], "base": true, "d": "Revela sus debilidades: sus resistencias no cuentan y recibe más daño."}],
			["est_grito", "Grito de guerra", {"pt": 9, "tgt": "allies", "st": [["inspirado", 1.0, 3]], "d": "Todo el grupo inspirado 3 turnos."}],
			["est_lider", "Liderazgo nato", {"fx": {"ally_dmg": 0.06}, "d": "Su grupo hace +6% de daño."}],
			["est_coordinado", "Ataque coordinado", {"pt": 14, "tgt": "enemy", "pow": 0.45, "fx": {"per_ally": 1, "estr": 0.3}, "d": "Daño según los aliados en pie; suma su Estrategia."}],
			["est_relevo", "Relevo táctico", {"t": 2, "pt": 6, "tgt": "ally", "fx": {"haste": 1, "pt_give": 6}, "d": "El aliado actúa antes y recupera 6 PT."}],
			["est_cadena", "Cadena de mando", {"t": 3, "fx": {"ally_hit": 0.03, "ally_init": 0.05}, "d": "Su grupo acierta más y actúa antes."}],
			["est_golpe_mano", "Golpe de mano", {"t": 4, "pt": 16, "tgt": "allies", "st": [["inspirado", 1.0, 2]], "fx": {"morale": 10, "haste": 1}, "d": "Inspira al grupo, +10 de moral y actúan antes."}]]],
		["Táctica", [
			["est_leer", "Leer al enemigo", {"fx": {"punteria": 2, "evasion": 0.04}, "d": "+2 de Puntería y +4% de esquiva."}],
			["est_iniciativa", "Iniciativa", {"fx": {"ally_init": 0.1}, "d": "Su grupo empieza el combate antes."}],
			["est_maniobra", "Maniobra", {"pt": 10, "tgt": "allies", "fx": {"haste": 1}, "d": "Todo el grupo actúa antes."}],
			["est_emboscada", "Emboscada", {"pt": 8, "tgt": "enemy", "pow": 1.1, "fx": {"crit": 0.25, "estr": 0.4}, "d": "Ataque calculado: +25% de crítico, suma su Estrategia."}],
			["est_jaque", "Jaque", {"pt": 12, "tgt": "enemy", "pow": 1.4, "fx": {"vs_status": 1.5}, "d": "×1,5 contra quien sufra un estado."}],
			["est_flanqueo", "Flanqueo", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 0.9, "fx": {"estr": 0.3, "vs_status": 1.3}, "d": "Suma Estrategia; más daño si el rival está tocado."}],
			["est_terreno", "Dominio del terreno", {"t": 3, "fx": {"evasion": 0.04, "ally_dmg": 0.03}, "d": "+4% de esquiva y +3% de daño al grupo."}],
			["est_tenaza", "Tenaza", {"t": 4, "pt": 15, "tgt": "enemies", "pow": 0.7, "st": [["desequilibrado", 0.5, 2]], "fx": {"estr": 0.3}, "d": "Ataque envolvente que desequilibra."}]]],
		["Ingenio", [
			["est_engano", "Engaño", {"pt": 7, "tgt": "enemy", "st": [["aturdido", 0.5, 1]], "d": "Puede aturdir (pierde su turno)."}],
			["est_ojo", "Ojo táctico", {"fx": {"ally_hit": 0.04}, "d": "Su grupo acierta un 4% más."}],
			["est_trampa", "Trampa", {"pt": 10, "tgt": "enemies", "st": [["desequilibrado", 0.4, 2]], "d": "Puede desequilibrar a todos."}],
			["est_contramedida", "Contramedida", {"fx": {"status_res": 0.2, "ally_crit": 0.03}, "d": "Resiste estados; su grupo +3% de crítico."}],
			["est_distraccion", "Distracción", {"t": 2, "pt": 5, "tgt": "enemy", "st": [["cegado", 0.55, 2]], "d": "Le echa polvo a los ojos: puede cegarlo."}],
			["est_reserva", "Planes de reserva", {"t": 3, "fx": {"pt_pct": 0.1, "pt_regen": 1}, "d": "+10% de PT y +1 PT por turno."}],
			["est_jugada", "Jugada maestra", {"t": 4, "pt": 14, "tgt": "enemy", "pow": 1.1, "st": [["analizado", 1.0, 2]], "fx": {"estr": 0.5}, "d": "Golpe calculado que deja al rival analizado."}]]],
	]],
	"berserker": ["Berserker", [
		["Furia", [
			["ber_furia", "Furia", {"pt": 5, "tgt": "self", "st": [["furia", 1.0, 2]], "base": true, "d": "2 turnos: +30% de daño y −30% de Defensa."}],
			["ber_grito", "Grito salvaje", {"pt": 8, "tgt": "enemies", "st": [["debilitado", 0.35, 2]], "d": "Puede debilitar a todos."}],
			["ber_herido", "Furia del herido", {"fx": {"low_hp_dmg": 0.25}, "d": "+25% de daño con poca vida."}],
			["ber_sed", "Sed de sangre", {"fx": {"lifesteal": 0.1}, "d": "Recupera el 10% del daño que hace."}],
			["ber_desenfreno", "Desenfreno", {"pt": 14, "tgt": "random3", "pow": 0.75, "hits": 3, "d": "3 golpes a enemigos al azar."}],
			["ber_rugido", "Rugido", {"t": 2, "pt": 6, "tgt": "enemies", "st": [["debilitado", 0.5, 2]], "fx": {"self_st": [["furia", 2]]}, "d": "Puede debilitar a todos; entra en furia."}],
			["ber_rabia", "Rabia ciega", {"t": 3, "fx": {"low_hp_dmg": 0.15, "crit": 0.03}, "d": "+15% de daño con poca vida y +3% de crítico."}],
			["ber_frenesi", "Frenesí", {"t": 4, "pt": 16, "tgt": "random3", "pow": 0.9, "dt": T0, "fx": {"crit": 0.1}, "d": "Tres golpes a enemigos al azar."}]]],
		["Carnicería", [
			["ber_tajo", "Golpe brutal", {"pt": 4, "tgt": "enemy", "pow": 1.3, "base": true, "d": "Golpe salvaje con su arma."}],
			["ber_tajo1", "Maestría: Tajo", {"fx": {"dmg_t0": 0.1}, "d": "+10% de daño de Tajo."}],
			["ber_barrido", "Barrido", {"pt": 9, "tgt": "enemies", "pow": 0.65, "d": "Golpea a todos los enemigos."}],
			["ber_hachazo", "Hachazo", {"pt": 8, "tgt": "enemy", "pow": 1.8, "fx": {"acc": -0.1}, "d": "Muy fuerte, algo impreciso."}],
			["ber_decapitar", "Decapitar", {"pt": 15, "tgt": "enemy", "pow": 2.4, "d": "El golpe más brutal."}],
			["ber_tajo_bajo", "Tajo bajo", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 1.0, "dt": T0, "st": [["derribado", 0.35, 1]], "d": "Corta las piernas: puede derribar."}],
			["ber_carnicero", "Carnicero", {"t": 3, "fx": {"dmg_t0": 0.08, "crit_mult": 0.1}, "d": "+8% de daño de Tajo y críticos más fuertes."}],
			["ber_torbellino", "Torbellino", {"t": 4, "pt": 16, "tgt": "enemies", "pow": 0.95, "dt": T0, "st": [["sangrado", 0.4, 2]], "d": "Golpea a todos y puede hacerlos sangrar."}]]],
		["Sangre", [
			["ber_herida", "Herida abierta", {"pt": 5, "tgt": "enemy", "pow": 0.9, "st": [["sangrado", 0.7, 3]], "d": "Hace sangrar 3 turnos."}],
			["ber_aliento", "Aliento de bestia", {"fx": {"pt_regen": 1}, "d": "+1 PT por turno."}],
			["ber_incansable", "Incansable", {"fx": {"pv_pct": 0.1}, "d": "+10% de PV."}],
			["ber_fuerza", "Fuerza bruta", {"fx": {"fuerza_pct": 0.08}, "d": "+8% de Fuerza."}],
			["ber_ultimo", "Último aliento", {"fx": {"last_stand": 1}, "d": "Una vez por combate aguanta con 1 PV."}],
			["ber_beber", "Beber sangre", {"t": 2, "fx": {"lifesteal": 0.05}, "d": "Recupera el 5% del daño que hace."}],
			["ber_cicatrices", "Cicatrices", {"t": 3, "fx": {"low_hp_taken": -0.12, "pv_pct": 0.06}, "d": "+6% de PV y −12% de daño con poca vida."}],
			["ber_ira_sangre", "Ira de sangre", {"t": 4, "pt": 14, "tgt": "enemy", "pow": 1.2, "dt": T0, "fx": {"scale_missing": 1}, "d": "Cuanta menos vida tiene, más fuerte pega."}]]],
	]],
	"defensor": ["Defensor", [
		["Protección", [
			["def_cubrir", "Escudar", {"pt": 4, "tgt": "ally", "fx": {"cover": 1}, "base": true, "d": "Recibe los golpes dirigidos a un aliado."}],
			["def_parada", "Parada", {"fx": {"guard": 0.2, "counter": 0.05}, "d": "Mejor guardia y algo de respuesta."}],
			["def_muro", "Muro de escudos", {"fx": {"ally_taken": -0.1}, "d": "Mientras esté en pie, su grupo recibe −10% de daño."}],
			["def_alzado", "Escudos en alto", {"pt": 10, "tgt": "allies", "st": [["fortaleza", 1.0, 2]], "d": "+50% de Defensa al grupo 2 turnos."}],
			["def_bastion", "Bastión", {"fx": {"pv_pct": 0.12, "defensa": 2}, "d": "+12% de PV y +2 de Defensa."}],
			["def_guardia_comun", "Guardia compartida", {"t": 2, "pt": 7, "tgt": "ally", "st": [["fortaleza", 1.0, 2]], "fx": {"self_st": [["fortaleza", 2]]}, "d": "Refuerza a un aliado y a sí mismo 2 turnos."}],
			["def_centinela", "Centinela", {"t": 3, "fx": {"ally_taken": -0.05, "counter": 0.12}, "d": "Su grupo recibe −5% de daño; +12% de contraataque."}],
			["def_inquebrantable", "Inquebrantable", {"t": 4, "fx": {"immune_derribo": 1, "defensa": 3, "status_res": 0.1}, "d": "No lo derriban; +3 de Defensa."}]]],
		["Socorro", [
			["def_vendaje", "Vendaje", {"pt": 6, "tgt": "ally", "heal": 0.3, "base": true, "d": "Cura el 30% de la vida de un aliado."}],
			["def_firme", "Firmeza", {"fx": {"status_res": 0.1, "voluntad": 2}, "d": "+2 de Voluntad, resiste estados."}],
			["def_purificar", "Atender heridas", {"pt": 5, "tgt": "ally", "heal": 0.08, "fx": {"cleanse": 1}, "d": "Quita los estados de un aliado."}],
			["def_plegaria", "Cuidados de campaña", {"pt": 12, "tgt": "allies", "heal": 0.15, "d": "Cura un poco a todo el grupo."}],
			["def_milagro", "Levantar al caído", {"pt": 18, "tgt": "ko_ally", "fx": {"revive": 0.35}, "d": "Levanta a un aliado caído (no en lucha a muerte)."}],
			["def_torniquete", "Torniquete", {"t": 2, "pt": 5, "tgt": "ally", "heal": 0.15, "fx": {"cleanse": 1}, "d": "Cura un poco y quita los estados."}],
			["def_manos", "Manos firmes", {"t": 3, "fx": {"heal_bonus": 0.15, "voluntad": 1}, "d": "Sus curas son un 15% mejores."}],
			["def_campana", "Hospital de campaña", {"t": 4, "pt": 16, "tgt": "allies", "heal": 0.2, "st": [["sereno", 1.0, 2]], "d": "Cura al grupo y lo serena 2 turnos."}]]],
		["Represalia", [
			["def_empellon", "Empellón", {"pt": 5, "tgt": "enemy", "pow": 0.9, "dt": T2, "st": [["desequilibrado", 0.55, 2]], "d": "Puede desequilibrar."}],
			["def_contra", "Contragolpe", {"fx": {"counter": 0.12}, "d": "+12% de responder a los golpes."}],
			["def_castigo", "Castigo", {"pt": 9, "tgt": "enemy", "pow": 1.2, "dt": T2, "st": [["debilitado", 0.5, 3]], "d": "Golpe que puede debilitar."}],
			["def_venganza", "Venganza", {"pt": 8, "tgt": "enemy", "pow": 1.0, "fx": {"scale_missing": 1}, "d": "Más daño cuanta menos vida le quede."}],
			["def_juramento", "Juramento", {"fx": {"avenge": 0.25}, "d": "+25% de daño por cada aliado caído."}],
			["def_escarmiento", "Escarmiento", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 1.25, "dt": T2, "st": [["debilitado", 0.5, 2]], "d": "Puede debilitar al agresor."}],
			["def_puas", "Escudo de púas", {"t": 3, "fx": {"reflect": 0.1, "counter": 0.1}, "d": "Devuelve el 10% del daño; +10% de contraataque."}],
			["def_justicia", "Justicia", {"t": 4, "pt": 14, "tgt": "enemy", "pow": 1.5, "dt": T2, "st": [["aturdido", 0.35, 1]], "fx": {"vs_status": 1.4}, "d": "Más daño si el rival está tocado; puede aturdir."}]]],
	]],
	"asesino": ["Asesino", [
		["Sombras", [
			["ase_punal", "Puñalada", {"pt": 4, "tgt": "enemy", "pow": 1.2, "fx": {"crit": 0.12}, "base": true, "d": "+12% de crítico."}],
			["ase_evasion", "Evasión", {"fx": {"evasion": 0.06}, "d": "+6% de esquiva."}],
			["ase_desaparecer", "Desaparecer", {"pt": 6, "tgt": "self", "st": [["oculto", 1.0, 1]], "d": "Casi no le aciertan y su próximo golpe busca el crítico."}],
			["ase_veloz", "Paso veloz", {"fx": {"agilidad": 3, "evasion": 0.03}, "d": "+3 de Agilidad y +3% de esquiva."}],
			["ase_espalda", "Golpe por la espalda", {"pt": 12, "tgt": "enemy", "pow": 1.5, "fx": {"crit": 0.3, "agi": 0.3}, "d": "+30% de crítico; suma su Agilidad."}],
			["ase_sigilo", "Sigilo", {"t": 2, "fx": {"evasion": 0.04, "agilidad": 1}, "d": "+4% de esquiva y +1 de Agilidad."}],
			["ase_acecho", "Acecho", {"t": 3, "pt": 8, "tgt": "self", "st": [["oculto", 1.0, 2]], "d": "Se oculta 2 turnos."}],
			["ase_sombra", "Golpe sombrío", {"t": 4, "pt": 15, "tgt": "enemy", "pow": 1.5, "dt": T1, "fx": {"crit": 0.25, "acc": 0.1}, "d": "Estocada desde la sombra con +25% de crítico."}]]],
		["Veneno", [
			["ase_hoja", "Hoja envenenada", {"pt": 5, "tgt": "enemy", "pow": 0.8, "st": [["sangrado", 0.8, 3]], "base": true, "d": "Envenena: sangra 3 turnos."}],
			["ase_polvo", "Polvo a los ojos", {"pt": 5, "tgt": "enemy", "st": [["cegado", 0.7, 2]], "d": "Puede cegarlo (falla más)."}],
			["ase_toxinas", "Toxinas", {"fx": {"bleed_bonus": 0.5}, "d": "Su sangrado hace +50% de daño."}],
			["ase_debilitar", "Veneno debilitante", {"pt": 6, "tgt": "enemy", "pow": 0.6, "st": [["debilitado", 0.7, 3]], "d": "Debilita: menos Fuerza y Defensa."}],
			["ase_letal", "Veneno letal", {"pt": 14, "tgt": "enemy", "pow": 1.0, "st": [["sangrado", 1.0, 3], ["aturdido", 0.35, 1]], "d": "Sangrado seguro y puede aturdir."}],
			["ase_aguja", "Aguja", {"t": 2, "pt": 5, "tgt": "enemy", "pow": 0.5, "dt": T1, "st": [["debilitado", 0.6, 2], ["sangrado", 0.5, 2]], "d": "Pinchazo que debilita y hace sangrar."}],
			["ase_ponzona", "Ponzoña lenta", {"t": 3, "fx": {"bleed_bonus": 0.3, "punteria": 1}, "d": "Sus sangrados hacen un 30% más."}],
			["ase_dardos", "Dardos emponzoñados", {"t": 4, "pt": 14, "tgt": "random3", "pow": 0.6, "dt": T3, "st": [["sangrado", 0.7, 3], ["debilitado", 0.4, 2]], "d": "Tres dardos al azar que hacen sangrar."}]]],
		["Letalidad", [
			["ase_ojo", "Ojo certero", {"fx": {"crit": 0.05, "crit_mult": 0.15}, "d": "+5% de crítico, críticos más dañinos."}],
			["ase_disparo", "Disparo", {"pt": 5, "tgt": "enemy", "pow": 1.1, "dt": T3, "d": "Dispara (Proyectil) aunque no lleve arco."}],
			["ase_remate", "Remate", {"pt": 7, "tgt": "enemy", "pow": 1.0, "fx": {"exec": 2.2}, "d": "×2,2 a quien tenga menos del 30% de vida."}],
			["ase_brecha", "Aprovechar la brecha", {"fx": {"brecha": 1}, "d": "Al conectar una debilidad o un crítico actúa otra vez (una vez por turno)."}],
			["ase_ejecucion", "Ejecución", {"pt": 16, "tgt": "enemy", "pow": 2.3, "fx": {"crit": 0.1}, "d": "Golpe letal."}],
			["ase_deguello", "Degüello", {"t": 2, "pt": 7, "tgt": "enemy", "pow": 0.9, "dt": T0, "fx": {"exec": 1.6}, "d": "Mucho más daño a enemigos con poca vida."}],
			["ase_frialdad", "Frialdad", {"t": 3, "fx": {"crit_mult": 0.15, "punteria": 2}, "d": "Críticos un 15% más fuertes y +2 de Puntería."}],
			["ase_sentencia", "Sentencia", {"t": 4, "pt": 16, "tgt": "enemy", "pow": 1.2, "fx": {"vs_status": 1.5, "pierce": 1}, "d": "Atraviesa la armadura; más daño si está tocado."}]]],
	]],
	# ================= PERSONALIDAD =================
	"p_ambicioso": ["Ambicioso", [
		["Ascenso", [
			["pamb_golpe", "Golpe ambicioso", {"pt": 4, "tgt": "enemy", "pow": 1.15, "fx": {"crit": 0.05}, "d": "Golpe con +5% de crítico."}],
			["pamb_afan", "Afán de gloria", {"fx": {"fuerza_pct": 0.04}, "d": "+4% de Fuerza."}],
			["pamb_presa", "Ir a por la presa", {"pt": 7, "tgt": "enemy", "pow": 1.0, "fx": {"exec": 1.8}, "d": "×1,8 a quien tenga menos del 30% de vida."}],
			["pamb_techo", "Sin techo", {"fx": {"crit": 0.04, "crit_mult": 0.15}, "d": "+4% de crítico, críticos más dañinos."}],
			["pamb_gloria", "La gloria es mía", {"pt": 14, "tgt": "enemy", "pow": 2.0, "fx": {"crit": 0.15}, "d": "Golpe decisivo, +15% de crítico."}],
			["pamb_escalar", "Escalar", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 1.05, "fx": {"crit": 0.08, "self_st": [["inspirado", 2]]}, "d": "Golpe con +8% de crítico; se inspira."}],
			["pamb_merito", "Mérito", {"t": 3, "fx": {"crit": 0.04, "fuerza_pct": 0.04}, "d": "+4% de crítico y +4% de Fuerza."}],
			["pamb_cumbre", "Cumbre", {"t": 4, "pt": 16, "tgt": "enemy", "pow": 1.6, "fx": {"crit": 0.15, "exec": 1.5}, "d": "Golpe enorme que remata a los débiles."}]]],
		["Codicia", [
			["pamb_botin", "Botín", {"pt": 3, "tgt": "enemy", "pow": 0.8, "fx": {"pt_drain": 6}, "d": "Golpea y le roba 6 PT."}],
			["pamb_teson", "Tesón", {"fx": {"pt_pct": 0.1}, "d": "+10% de PT."}],
			["pamb_exprimir", "Exprimir", {"fx": {"pt_regen": 1}, "d": "+1 PT por turno."}],
			["pamb_tajada", "Sacar tajada", {"fx": {"lifesteal": 0.06}, "d": "Recupera el 6% del daño que hace."}],
			["pamb_rapina", "Rapiña", {"t": 2, "pt": 5, "tgt": "enemy", "pow": 0.8, "fx": {"pt_drain": 6}, "d": "Le roba 6 PT."}],
			["pamb_avaricia", "Avaricia", {"t": 3, "fx": {"pt_pct": 0.1, "lifesteal": 0.04}, "d": "+10% de PT y recupera el 4% del daño."}],
			["pamb_todo", "Quedarse con todo", {"t": 4, "pt": 14, "tgt": "enemy", "pow": 1.2, "st": [["desarmado", 0.5, 2]], "fx": {"pt_drain": 10}, "d": "Le roba 10 PT y puede desarmarlo."}]]],
		["Ímpetu", [
			["pamb_arrebato", "Arrebato", {"pt": 4, "tgt": "self", "st": [["inspirado", 1.0, 2]], "d": "Se inspira 2 turnos."}],
			["pamb_paso", "Paso firme", {"fx": {"agilidad": 1, "punteria": 1}, "d": "+1 de Agilidad y de Puntería."}],
			["pamb_ofensiva", "Ofensiva", {"fx": {"ally_dmg": 0.03}, "d": "Su grupo hace +3% de daño."}],
			["pamb_mano", "Golpe de mano", {"pt": 8, "tgt": "enemy", "pow": 1.3, "st": [["marcado", 0.6, 2]], "d": "Golpea y puede marcarlo."}],
			["pamb_prisa", "Prisa", {"t": 2, "fx": {"agilidad": 1, "crit": 0.02}, "d": "+1 de Agilidad y +2% de crítico."}],
			["pamb_asalto", "Asalto", {"t": 3, "pt": 9, "tgt": "enemy", "pow": 1.15, "st": [["desequilibrado", 0.5, 2]], "fx": {"acc": 0.1}, "d": "Golpe certero que desequilibra."}],
			["pamb_imparable", "Imparable", {"t": 4, "fx": {"low_hp_dmg": 0.15, "status_res": 0.1}, "d": "+15% de daño con poca vida; resiste estados."}]]],
	]],
	"p_leal": ["Leal", [
		["Escolta", [
			["plea_proteger", "Proteger", {"pt": 4, "tgt": "ally", "fx": {"cover": 1}, "d": "Recibe los golpes dirigidos a un aliado."}],
			["plea_firme", "Junto a los suyos", {"fx": {"ally_taken": -0.03}, "d": "Su grupo recibe −3% de daño."}],
			["plea_escolta", "Escolta", {"fx": {"guard": 0.2, "counter": 0.06}, "d": "Mejor guardia y algo de respuesta."}],
			["plea_muralla", "Muralla viva", {"pt": 9, "tgt": "allies", "st": [["fortaleza", 1.0, 2]], "d": "+50% de Defensa al grupo 2 turnos."}],
			["plea_fin", "Hasta el fin", {"fx": {"last_stand": 1, "pv_pct": 0.05}, "d": "Aguanta una vez con 1 PV; +5% de PV."}],
			["plea_parapeto", "Parapeto", {"t": 2, "pt": 5, "tgt": "ally", "fx": {"cover": 1, "self_st": [["fortaleza", 1]]}, "d": "Cubre a un aliado y se refuerza 1 turno."}],
			["plea_custodio", "Custodio", {"t": 3, "fx": {"ally_taken": -0.05, "defensa": 1}, "d": "Su grupo recibe −5% de daño."}],
			["plea_hasta_final", "Hasta el final", {"t": 4, "fx": {"avenge": 0.1, "guard": 0.15}, "d": "+10% de daño por aliado caído; defender protege más."}]]],
		["Juramento", [
			["plea_caidos", "Por los caídos", {"fx": {"avenge": 0.15}, "d": "+15% de daño por cada aliado caído."}],
			["plea_voto", "Voto", {"fx": {"voluntad": 2, "status_res": 0.05}, "d": "+2 de Voluntad."}],
			["plea_vengar", "Vengar al compañero", {"pt": 7, "tgt": "enemy", "pow": 1.1, "fx": {"scale_missing": 1}, "d": "Más daño cuanta menos vida le quede."}],
			["plea_lealtad", "Lealtad inquebrantable", {"fx": {"status_res": 0.15, "ally_morale": 8}, "d": "Resiste estados; +8 de moral al grupo."}],
			["plea_promesa", "Promesa", {"t": 2, "fx": {"avenge": 0.1}, "d": "+10% de daño por cada aliado caído."}],
			["plea_deuda", "Deuda de sangre", {"t": 3, "pt": 9, "tgt": "enemy", "pow": 1.1, "st": [["marcado", 0.6, 2]], "fx": {"vs_status": 1.3}, "d": "Marca al rival; más daño si está tocado."}],
			["plea_eterno", "Juramento eterno", {"t": 4, "pt": 15, "tgt": "enemy", "pow": 1.5, "fx": {"crit": 0.1, "self_st": [["furia", 2]]}, "d": "Golpe con +10% de crítico; entra en furia."}]]],
		["Camaradería", [
			["plea_animo", "Grito de ánimo", {"pt": 5, "tgt": "ally", "st": [["inspirado", 1.0, 3]], "d": "Inspira a un aliado 3 turnos."}],
			["plea_auxilio", "Primeros auxilios", {"pt": 6, "tgt": "ally", "heal": 0.2, "d": "Cura el 20% de la vida."}],
			["plea_hombro", "Hombro con hombro", {"fx": {"ally_dmg": 0.03, "ally_hit": 0.02}, "d": "Su grupo hace +3% de daño y acierta más."}],
			["plea_relevo", "Relevo", {"pt": 6, "tgt": "ally", "fx": {"advance": 1, "pt_give": 8}, "d": "Un aliado actúa ya y recupera 8 PT."}],
			["plea_hermandad", "Hermandad", {"t": 2, "fx": {"ally_morale": 5, "ally_hit": 0.02}, "d": "+5 de moral y +2% de acierto al grupo."}],
			["plea_codo", "Codo con codo", {"t": 3, "pt": 9, "tgt": "allies", "st": [["inspirado", 1.0, 2]], "d": "Inspira al grupo 2 turnos."}],
			["plea_familia", "Familia", {"t": 4, "pt": 16, "tgt": "allies", "heal": 0.15, "fx": {"morale": 10}, "d": "Cura al grupo y le da +10 de moral."}]]],
	]],
	"p_prudente": ["Prudente", [
		["Cautela", [
			["ppru_defensa", "Guardia prudente", {"pt": 3, "tgt": "self", "st": [["fortaleza", 1.0, 2]], "d": "+50% de Defensa 2 turnos."}],
			["ppru_piel", "Piel curtida", {"fx": {"low_hp_taken": -0.15}, "d": "−15% de daño con poca vida."}],
			["ppru_reserva", "Reserva de fuerzas", {"fx": {"pt_pct": 0.1, "pv_pct": 0.05}, "d": "+10% de PT y +5% de PV."}],
			["ppru_temple", "Temple", {"fx": {"voluntad": 3, "status_res": 0.15}, "d": "+3 de Voluntad y resiste estados."}],
			["ppru_piedra", "Paciencia de piedra", {"fx": {"guard": 0.3, "defensa": 2}, "d": "Defender protege mucho más; +2 de Defensa."}],
			["ppru_paso_atras", "Paso atrás", {"t": 2, "pt": 5, "tgt": "self", "st": [["fortaleza", 1.0, 2]], "d": "Se refuerza 2 turnos."}],
			["ppru_coraza", "Coraza", {"t": 3, "fx": {"defensa": 2, "taken": -0.03}, "d": "+2 de Defensa y −3% de daño recibido."}],
			["ppru_fortin", "Fortín", {"t": 4, "fx": {"ally_taken": -0.05, "status_res": 0.1}, "d": "Su grupo recibe −5% de daño; resiste estados."}]]],
		["Previsión", [
			["ppru_estudiar", "Estudiar al rival", {"pt": 4, "tgt": "enemy", "st": [["analizado", 1.0, 2]], "d": "Sus resistencias no cuentan 2 turnos."}],
			["ppru_reflejos", "Reflejos", {"fx": {"agilidad": 1, "evasion": 0.04}, "d": "+1 de Agilidad y +4% de esquiva."}],
			["ppru_medido", "Golpe medido", {"pt": 6, "tgt": "enemy", "pow": 1.15, "fx": {"acc": 0.15}, "d": "Golpe que casi nunca falla."}],
			["ppru_vigilancia", "Vigilancia", {"fx": {"crit_ward": 1, "evasion": 0.03}, "d": "Anula el primer crítico que recibe; +3% de esquiva."}],
			["ppru_anticipar", "Anticipar", {"t": 2, "fx": {"ally_init": 0.05, "evasion": 0.02}, "d": "Su grupo actúa antes; +2% de esquiva."}],
			["ppru_golpe_medido", "Golpe medido", {"t": 3, "pt": 8, "tgt": "enemy", "pow": 1.05, "fx": {"acc": 0.15, "vs_status": 1.3}, "d": "Muy preciso; más daño si el rival está tocado."}],
			["ppru_plan", "Plan perfecto", {"t": 4, "pt": 14, "tgt": "enemies", "st": [["analizado", 0.8, 2]], "fx": {"morale": -5}, "d": "Analiza a todos y les baja la moral."}]]],
		["Repliegue", [
			["ppru_repliegue", "Saber retirarse", {"fx": {"retreat": 0.2}, "d": "+20% de éxito al retirarse."}],
			["ppru_respiro", "Respiro", {"pt": 6, "tgt": "self", "heal": 0.25, "d": "Se cura el 25%."}],
			["ppru_segundo", "Segundo aliento", {"fx": {"pt_regen": 1}, "d": "+1 PT por turno."}],
			["ppru_calma", "Calma tensa", {"pt": 8, "tgt": "self", "st": [["sereno", 1.0, 3], ["fortaleza", 1.0, 2]], "d": "Se protege y recupera vida 3 turnos."}],
			["ppru_vendar", "Vendarse", {"t": 2, "pt": 5, "tgt": "self", "heal": 0.2, "d": "Se cura el 20% de la vida."}],
			["ppru_aliento", "Aliento", {"t": 3, "fx": {"pt_regen": 1, "regen": 0.02}, "d": "+1 PT y 2% de vida por turno."}],
			["ppru_sobrevivir", "Sobrevivir", {"t": 4, "fx": {"last_stand": 1, "low_hp_taken": -0.1}, "d": "Una vez por combate aguanta con 1 PV."}]]],
	]],
	"p_arrogante": ["Arrogante", [
		["Desprecio", [
			["parr_burla", "Burla", {"pt": 3, "tgt": "enemy", "st": [["provocado", 0.8, 2]], "d": "Le obliga a atacarle."}],
			["parr_soberbia", "Soberbia", {"fx": {"fuerza_pct": 0.07, "taken": 0.04}, "d": "+7% de Fuerza, pero recibe +4% de daño."}],
			["parr_humillar", "Humillar", {"pt": 6, "tgt": "enemy", "pow": 1.0, "fx": {"morale": -15}, "d": "Golpea y le baja 15 de moral."}],
			["parr_desden", "Desdén", {"fx": {"status_res": 0.1, "voluntad": 2}, "d": "+2 de Voluntad, resiste estados."}],
			["parr_aplastar", "Aplastar al débil", {"pt": 12, "tgt": "enemy", "pow": 1.6, "fx": {"vs_status": 1.4}, "d": "×1,4 contra quien sufra un estado."}],
			["parr_escupir", "Escupir", {"t": 2, "pt": 5, "tgt": "enemy", "st": [["provocado", 0.7, 2], ["debilitado", 0.4, 2]], "d": "Lo provoca y puede debilitarlo."}],
			["parr_altivez", "Altivez", {"t": 3, "fx": {"fear": 4, "voluntad": 2}, "d": "El enemigo empieza con −4 de moral; +2 de Voluntad."}],
			["parr_insignificante", "Insignificante", {"t": 4, "pt": 15, "tgt": "enemy", "pow": 1.5, "fx": {"vs_status": 1.4, "morale": -10}, "d": "Golpe humillante: −10 de moral al rival."}]]],
		["Alarde", [
			["parr_floritura", "Floritura", {"pt": 4, "tgt": "enemy", "pow": 1.1, "fx": {"crit": 0.1}, "d": "+10% de crítico."}],
			["parr_pose", "Pose desafiante", {"fx": {"crit": 0.04}, "d": "+4% de crítico."}],
			["parr_lucirse", "Lucirse", {"pt": 7, "tgt": "self", "st": [["inspirado", 1.0, 3], ["fortaleza", 1.0, 1]], "d": "Se inspira 3 turnos y se refuerza."}],
			["parr_estrella", "Estrella del torneo", {"fx": {"crit_mult": 0.25}, "d": "Críticos mucho más dañinos."}],
			["parr_gesto", "Gesto teatral", {"t": 2, "pt": 5, "tgt": "self", "st": [["inspirado", 1.0, 2]], "fx": {"morale": 5}, "d": "Se inspira 2 turnos y gana moral."}],
			["parr_aplauso", "Aplauso", {"t": 3, "fx": {"crit": 0.04, "crit_mult": 0.1}, "d": "+4% de crítico y críticos más fuertes."}],
			["parr_gran_final", "Gran final", {"t": 4, "pt": 16, "tgt": "enemy", "pow": 1.45, "fx": {"crit": 0.2, "acc": 0.1}, "d": "Golpe vistoso con +20% de crítico."}]]],
		["Supremacía", [
			["parr_primero", "Siempre primero", {"fx": {"agilidad": 2}, "d": "+2 de Agilidad."}],
			["parr_imponer", "Imponerse", {"pt": 5, "tgt": "enemy", "pow": 0.9, "st": [["debilitado", 0.5, 2]], "d": "Puede debilitarlo."}],
			["parr_superior", "Superioridad", {"fx": {"first_sure": 1}, "d": "Su primer golpe siempre acierta."}],
			["parr_menosprecio", "Menosprecio", {"fx": {"fear": 8}, "d": "Los enemigos empiezan con −8 de moral."}],
			["parr_nato", "Nacido para mandar", {"t": 2, "fx": {"fuerza_pct": 0.05, "taken": 0.02}, "d": "+5% de Fuerza, pero +2% de daño recibido."}],
			["parr_por_encima", "Por encima", {"t": 3, "pt": 9, "tgt": "enemy", "pow": 1.05, "fx": {"pierce": 1}, "d": "Ignora la armadura del rival."}],
			["parr_intocable", "Intocable", {"t": 4, "fx": {"evasion": 0.05, "status_res": 0.15}, "d": "+5% de esquiva y resiste estados."}]]],
	]],
	"p_piadoso": ["Piadoso", [
		["Plegaria", [
			["ppia_rezo", "Rezo", {"pt": 5, "tgt": "allies", "fx": {"morale": 10}, "d": "Reza con el grupo: +10 de moral."}],
			["ppia_fe", "Fe", {"fx": {"voluntad": 2, "status_res": 0.05}, "d": "+2 de Voluntad."}],
			["ppia_letania", "Letanía", {"pt": 9, "tgt": "allies", "st": [["sereno", 1.0, 2]], "d": "Serena al grupo: recuperan vida 2 turnos."}],
			["ppia_devocion", "Devoción", {"fx": {"ally_morale": 10, "voluntad": 2}, "d": "+10 de moral al grupo al empezar."}],
			["ppia_milagro", "Fe que levanta", {"pt": 18, "tgt": "ko_ally", "fx": {"revive": 0.35}, "d": "Anima a un caído a levantarse (no en lucha a muerte)."}],
			["ppia_salmo", "Salmo", {"t": 2, "pt": 8, "tgt": "allies", "fx": {"cleanse": 1}, "d": "Canto que quita los estados al grupo."}],
			["ppia_vigilia", "Vigilia", {"t": 3, "fx": {"status_res": 0.1, "ally_morale": 5}, "d": "Resiste estados; +5 de moral al grupo."}],
			["ppia_gloria", "Gloria", {"t": 4, "pt": 16, "tgt": "allies", "st": [["inspirado", 1.0, 2], ["sereno", 1.0, 2]], "d": "Inspira y serena al grupo 2 turnos."}]]],
		["Caridad", [
			["ppia_curar", "Curar heridas", {"pt": 6, "tgt": "ally", "heal": 0.25, "d": "Cura el 25% de la vida."}],
			["ppia_manos", "Manos de sanador", {"fx": {"heal_bonus": 0.15}, "d": "Sus curas son un 15% mejores."}],
			["ppia_consuelo", "Consuelo", {"pt": 5, "tgt": "ally", "heal": 0.1, "fx": {"cleanse": 1}, "d": "Quita los estados y cura un poco."}],
			["ppia_hospital", "Hospitalario", {"pt": 12, "tgt": "allies", "heal": 0.15, "d": "Cura un poco a todo el grupo."}],
			["ppia_vendas", "Vendas limpias", {"t": 2, "fx": {"heal_bonus": 0.1, "voluntad": 1}, "d": "Sus curas son un 10% mejores."}],
			["ppia_limosna", "Limosna", {"t": 3, "pt": 6, "tgt": "ally", "fx": {"pt_give": 8}, "d": "Da 8 PT a un aliado."}],
			["ppia_santas", "Manos santas", {"t": 4, "pt": 14, "tgt": "ally", "heal": 0.45, "fx": {"cleanse": 1}, "d": "Cura mucho y quita los estados."}]]],
		["Penitencia", [
			["ppia_ayuno", "Ayuno", {"fx": {"pt_pct": 0.08, "pv_pct": 0.04}, "d": "+8% de PT y +4% de PV."}],
			["ppia_cilicio", "Cilicio", {"fx": {"low_hp_taken": -0.15}, "d": "−15% de daño con poca vida."}],
			["ppia_martir", "Mártir", {"pt": 4, "tgt": "ally", "fx": {"cover": 1, "self_st": [["fortaleza", 2]]}, "d": "Cubre a un aliado y se refuerza."}],
			["ppia_redencion", "Redención", {"fx": {"regen": 0.03}, "d": "Recupera el 3% de la vida cada turno."}],
			["ppia_disciplina", "Disciplina", {"t": 2, "pt": 4, "tgt": "self", "st": [["fortaleza", 1.0, 2]], "fx": {"morale": 5}, "d": "Se refuerza 2 turnos y gana moral."}],
			["ppia_humildad", "Humildad", {"t": 3, "fx": {"taken": -0.04, "voluntad": 2}, "d": "−4% de daño recibido y +2 de Voluntad."}],
			["ppia_cruz", "Cargar la cruz", {"t": 4, "fx": {"ally_taken": -0.04, "regen": 0.02}, "d": "Su grupo recibe −4% de daño; recupera vida."}]]],
	]],
	"p_astuto": ["Astuto", [
		["Trampas", [
			["past_cepo", "Cepo", {"pt": 5, "tgt": "enemy", "st": [["derribado", 0.45, 1]], "d": "Trampa: puede derribarlo."}],
			["past_lazo", "Lazo", {"pt": 4, "tgt": "enemy", "st": [["desequilibrado", 0.6, 2]], "d": "Puede desequilibrarlo."}],
			["past_red", "Red", {"pt": 9, "tgt": "enemies", "st": [["desequilibrado", 0.4, 2]], "d": "Puede desequilibrar a todos."}],
			["past_foso", "Foso oculto", {"pt": 10, "tgt": "enemy", "pow": 0.8, "st": [["derribado", 0.6, 1], ["sangrado", 0.5, 2]], "d": "Puede derribarlo y hacerle sangrar."}],
			["past_emboscada", "Gran emboscada", {"pt": 14, "tgt": "enemies", "pow": 0.7, "st": [["desequilibrado", 0.5, 2]], "fx": {"crit": 0.1}, "d": "Golpea a todos y los desequilibra."}],
			["past_estacas", "Estacas", {"t": 2, "pt": 6, "tgt": "enemies", "pow": 0.4, "dt": T1, "st": [["sangrado", 0.4, 2]], "d": "Estacas ocultas: pueden hacer sangrar."}],
			["past_ingenio", "Ingenio", {"t": 3, "fx": {"punteria": 2, "crit": 0.03}, "d": "+2 de Puntería y +3% de crítico."}],
			["past_avalancha", "Avalancha de rocas", {"t": 4, "pt": 16, "tgt": "enemies", "pow": 0.85, "dt": T2, "st": [["derribado", 0.25, 1]], "d": "Rocas sobre todos: pueden derribar."}]]],
		["Engaños", [
			["past_arena", "Arena a los ojos", {"pt": 5, "tgt": "enemy", "st": [["cegado", 0.7, 2]], "d": "Puede cegarlo."}],
			["past_amago", "Amagar", {"pt": 4, "tgt": "enemy", "pow": 0.8, "fx": {"acc": 0.2}, "st": [["marcado", 0.5, 2]], "d": "Golpe seguro que puede marcarlo."}],
			["past_mentira", "Mentira", {"pt": 6, "tgt": "enemy", "st": [["aturdido", 0.45, 1]], "d": "Puede hacerle perder el turno."}],
			["past_confusion", "Sembrar confusión", {"pt": 10, "tgt": "enemies", "st": [["cegado", 0.4, 2]], "fx": {"morale": -8}, "d": "Puede cegar a todos; −8 de moral."}],
			["past_disfraz", "Disfraz", {"t": 2, "pt": 5, "tgt": "self", "st": [["oculto", 1.0, 1]], "d": "Se oculta 1 turno."}],
			["past_cizana", "Cizaña", {"t": 3, "pt": 9, "tgt": "enemies", "st": [["debilitado", 0.4, 2]], "fx": {"morale": -10}, "d": "Siembra discordia: −10 de moral y puede debilitar."}],
			["past_gran_engano", "Gran engaño", {"t": 4, "pt": 14, "tgt": "enemy", "st": [["aturdido", 0.6, 1], ["analizado", 1.0, 2]], "d": "Lo aturde y lo deja analizado."}]]],
		["Oportunismo", [
			["past_flaco", "Punto flaco", {"fx": {"crit": 0.05}, "d": "+5% de crítico."}],
			["past_ventaja", "Sacar ventaja", {"pt": 6, "tgt": "enemy", "pow": 1.1, "fx": {"vs_status": 1.3}, "d": "×1,3 contra quien sufra un estado."}],
			["past_ojo", "Ojo para el hueco", {"fx": {"punteria": 2, "crit_mult": 0.1}, "d": "+2 de Puntería, críticos más dañinos."}],
			["past_desprevenido", "Pillar desprevenido", {"pt": 9, "tgt": "enemy", "pow": 1.3, "fx": {"pierce": 1, "crit": 0.15}, "d": "Ignora la armadura; +15% de crítico."}],
			["past_carrona", "Carroñero", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 0.9, "fx": {"exec": 1.6}, "d": "Mucho más daño a enemigos con poca vida."}],
			["past_acechar", "Acechar", {"t": 3, "fx": {"crit_mult": 0.1, "crit": 0.03}, "d": "+3% de crítico y críticos más fuertes."}],
			["past_oportuno", "Golpe oportuno", {"t": 4, "pt": 14, "tgt": "enemy", "pow": 1.25, "fx": {"vs_status": 1.5, "crit": 0.1}, "d": "Mucho más daño si el rival está tocado."}]]],
	]],
	"p_valiente": ["Valiente", [
		["Arrojo", [
			["pval_carga", "Carga", {"pt": 5, "tgt": "enemy", "pow": 1.3, "fx": {"acc": -0.05}, "d": "Embestida fuerte."}],
			["pval_arrojo", "Arrojo", {"fx": {"fuerza_pct": 0.04}, "d": "+4% de Fuerza."}],
			["pval_temerario", "Temerario", {"fx": {"low_hp_dmg": 0.2}, "d": "+20% de daño con poca vida."}],
			["pval_primera", "En primera línea", {"pt": 8, "tgt": "enemy", "pow": 1.5, "fx": {"self_st": [["fortaleza", 1]]}, "d": "Golpe fuerte y se refuerza."}],
			["pval_hazana", "Hazaña", {"pt": 14, "tgt": "enemies", "pow": 0.9, "st": [["debilitado", 0.3, 2]], "d": "Golpea a todos y puede debilitarlos."}],
			["pval_embestida", "Embestida", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 1.1, "st": [["desequilibrado", 0.5, 2]], "d": "Carga que puede desequilibrar."}],
			["pval_audaz", "Audaz", {"t": 3, "fx": {"fuerza_pct": 0.05, "ally_morale": 3}, "d": "+5% de Fuerza; +3 de moral al grupo."}],
			["pval_carga_leyenda", "Carga legendaria", {"t": 4, "pt": 16, "tgt": "enemies", "pow": 0.9, "fx": {"morale": -5}, "d": "Golpea a todos y les baja la moral."}]]],
		["Aguante", [
			["pval_aguante", "Aguante", {"fx": {"pv_pct": 0.08}, "d": "+8% de PV."}],
			["pval_tenaz", "Tenacidad", {"fx": {"status_res": 0.1}, "d": "Resiste mejor los estados."}],
			["pval_resistir", "Resistir", {"pt": 5, "tgt": "self", "heal": 0.15, "st": [["fortaleza", 1.0, 2]], "d": "Se cura un poco y se refuerza."}],
			["pval_no_retroceder", "No retroceder", {"fx": {"last_stand": 1}, "d": "Una vez por combate aguanta con 1 PV."}],
			["pval_en_pie", "En pie", {"t": 2, "pt": 5, "tgt": "self", "heal": 0.15, "st": [["fortaleza", 1.0, 1]], "d": "Se cura un poco y se refuerza 1 turno."}],
			["pval_roca", "Roca", {"t": 3, "fx": {"low_hp_taken": -0.12, "status_res": 0.08}, "d": "−12% de daño con poca vida; resiste estados."}],
			["pval_invicto", "Invicto", {"t": 4, "fx": {"regen": 0.03, "status_res": 0.1}, "d": "Recupera el 3% de la vida por turno."}]]],
		["Desafío", [
			["pval_aqui", "¡Aquí estoy!", {"pt": 5, "tgt": "enemies", "st": [["provocado", 0.75, 2]], "d": "Los enemigos le atacan a él."}],
			["pval_valor", "Valor", {"fx": {"voluntad": 3}, "d": "+3 de Voluntad."}],
			["pval_ejemplo", "Dar ejemplo", {"fx": {"ally_morale": 6, "ally_dmg": 0.02}, "d": "+6 de moral y +2% de daño al grupo."}],
			["pval_reto", "Reto", {"pt": 8, "tgt": "enemy", "pow": 1.2, "st": [["provocado", 0.9, 2], ["marcado", 0.9, 2]], "d": "Golpea, lo provoca y lo marca."}],
			["pval_sin_parpadear", "Sin parpadear", {"t": 2, "fx": {"status_res": 0.1, "voluntad": 1}, "d": "Resiste estados; +1 de Voluntad."}],
			["pval_duelo", "Duelo singular", {"t": 3, "pt": 8, "tgt": "enemy", "pow": 1.1, "st": [["provocado", 0.8, 2]], "fx": {"self_st": [["fortaleza", 1]]}, "d": "Lo reta (provocado) y se refuerza."}],
			["pval_campeon", "Campeón", {"t": 4, "pt": 15, "tgt": "enemy", "pow": 1.6, "fx": {"crit": 0.1, "self_st": [["inspirado", 2]]}, "d": "Gran golpe; se inspira 2 turnos."}]]],
	]],
	"p_cruel": ["Cruel", [
		["Tormento", [
			["pcru_herida", "Herida cruel", {"pt": 5, "tgt": "enemy", "pow": 0.9, "st": [["sangrado", 0.75, 3]], "d": "Hace sangrar 3 turnos."}],
			["pcru_sana", "Saña", {"fx": {"bleed_bonus": 0.3}, "d": "Su sangrado hace +30% de daño."}],
			["pcru_retorcer", "Retorcer la hoja", {"pt": 7, "tgt": "enemy", "pow": 1.0, "fx": {"vs_status": 1.4}, "d": "×1,4 contra quien sufra un estado."}],
			["pcru_desgarrar", "Desgarrar", {"fx": {"on_hit_bleed": 1}, "d": "Sus golpes hacen sangrar."}],
			["pcru_carniceria", "Carnicería", {"pt": 14, "tgt": "enemies", "pow": 0.7, "st": [["sangrado", 0.6, 3]], "d": "Golpea a todos y los hace sangrar."}],
			["pcru_mil_cortes", "Mil cortes", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 0.85, "dt": T0, "st": [["sangrado", 0.6, 2]], "d": "Cortes que hacen sangrar."}],
			["pcru_rencor", "Rencor", {"t": 3, "fx": {"bleed_bonus": 0.3, "crit": 0.02}, "d": "Sus sangrados hacen un 30% más."}],
			["pcru_desollar", "Desollar", {"t": 4, "pt": 15, "tgt": "enemy", "pow": 1.2, "dt": T0, "st": [["sangrado", 0.7, 3]], "fx": {"vs_status": 1.4}, "d": "Más daño si está tocado; sangrado largo."}]]],
		["Terror", [
			["pcru_amenaza", "Amenaza", {"pt": 5, "tgt": "enemies", "fx": {"morale": -10}, "d": "−10 de moral a todos los enemigos."}],
			["pcru_mirada", "Mirada fría", {"fx": {"fear": 6}, "d": "Los enemigos empiezan con −6 de moral."}],
			["pcru_escarmiento", "Escarmiento", {"pt": 8, "tgt": "enemy", "pow": 1.2, "fx": {"exec": 1.6, "morale": -8}, "d": "×1,6 al malherido; −8 de moral."}],
			["pcru_espanto", "Espanto", {"pt": 9, "tgt": "enemies", "st": [["debilitado", 0.45, 2]], "fx": {"morale": -8}, "d": "Puede debilitar a todos; −8 de moral."}],
			["pcru_grilletes", "Golpe de cadena", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 0.6, "dt": T2, "st": [["desequilibrado", 0.6, 2]], "d": "Puede desequilibrar."}],
			["pcru_horror", "Horror", {"t": 3, "fx": {"fear": 5}, "d": "El enemigo empieza con −5 de moral."}],
			["pcru_masacre", "Masacre", {"t": 4, "pt": 16, "tgt": "enemies", "pow": 0.75, "st": [["debilitado", 0.4, 2]], "fx": {"morale": -10}, "d": "Golpea a todos: −10 de moral y puede debilitar."}]]],
		["Ensañamiento", [
			["pcru_sin_piedad", "Sin piedad", {"fx": {"crit": 0.04}, "d": "+4% de crítico."}],
			["pcru_pisotear", "Pisotear", {"pt": 5, "tgt": "enemy", "pow": 1.0, "dt": T2, "st": [["derribado", 0.3, 1]], "d": "Puede derribarlo."}],
			["pcru_sangre", "Gusto por la sangre", {"fx": {"lifesteal": 0.06}, "d": "Recupera el 6% del daño que hace."}],
			["pcru_ensanarse", "Ensañarse", {"fx": {"crit_mult": 0.2, "low_hp_dmg": 0.1}, "d": "Críticos más dañinos; +10% de daño herido."}],
			["pcru_rematar", "Rematar al caído", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 0.95, "fx": {"exec": 1.6}, "d": "Mucho más daño a enemigos con poca vida."}],
			["pcru_frio", "Corazón frío", {"t": 3, "fx": {"lifesteal": 0.05, "status_res": 0.05}, "d": "Recupera el 5% del daño que hace."}],
			["pcru_verdugo", "Verdugo", {"t": 4, "pt": 15, "tgt": "enemy", "pow": 1.1, "fx": {"exec": 2.0, "vs_status": 1.2}, "d": "Ejecución: daño enorme a los débiles."}]]],
	]],
	"p_generoso": ["Generoso", [
		["Dar", [
			["pgen_compartir", "Compartir fuerzas", {"pt": 3, "tgt": "ally", "fx": {"pt_give": 10}, "d": "Da 10 PT a un aliado."}],
			["pgen_desprendido", "Desprendido", {"fx": {"pt_regen": 1}, "d": "+1 PT por turno."}],
			["pgen_ceder", "Ceder el turno", {"pt": 5, "tgt": "ally", "st": [["inspirado", 1.0, 1]], "fx": {"advance": 1}, "d": "Un aliado actúa ya."}],
			["pgen_todo", "Darlo todo", {"pt": 10, "tgt": "allies", "fx": {"pt_give": 6}, "d": "Da 6 PT a todo el grupo."}],
			["pgen_corazon", "Gran corazón", {"fx": {"ally_taken": -0.05, "ally_morale": 6}, "d": "Su grupo recibe −5% de daño; +6 de moral."}],
			["pgen_racion", "Ración", {"t": 2, "pt": 4, "tgt": "ally", "heal": 0.05, "fx": {"pt_give": 6}, "d": "Da 6 PT y cura un poco."}],
			["pgen_abundancia", "Abundancia", {"t": 3, "fx": {"pt_pct": 0.1, "heal_bonus": 0.1}, "d": "+10% de PT; sus curas son un 10% mejores."}],
			["pgen_ofrenda", "Ofrenda", {"t": 4, "pt": 14, "tgt": "allies", "fx": {"pt_give": 8}, "d": "Da 8 PT a todo el grupo."}]]],
		["Socorro", [
			["pgen_socorrer", "Socorrer", {"pt": 6, "tgt": "ally", "heal": 0.22, "d": "Cura el 22% de la vida."}],
			["pgen_delante", "Ponerse delante", {"pt": 4, "tgt": "ally", "fx": {"cover": 1}, "d": "Recibe los golpes dirigidos a un aliado."}],
			["pgen_cuidados", "Cuidados", {"fx": {"heal_bonus": 0.15}, "d": "Sus curas son un 15% mejores."}],
			["pgen_rescate", "Rescate", {"pt": 8, "tgt": "ally", "heal": 0.3, "fx": {"cleanse": 1}, "d": "Cura el 30% y quita los estados."}],
			["pgen_brazo", "Brazo amigo", {"t": 2, "pt": 5, "tgt": "ally", "heal": 0.18, "d": "Cura el 18% de la vida."}],
			["pgen_escudo", "Escudo humano", {"t": 3, "fx": {"ally_taken": -0.05}, "d": "Su grupo recibe −5% de daño."}],
			["pgen_salvador", "Salvador", {"t": 4, "pt": 18, "tgt": "ko_ally", "fx": {"revive": 0.3}, "d": "Levanta a un caído (no en lucha a muerte)."}]]],
		["Ánimo", [
			["pgen_animo", "Palabras de ánimo", {"pt": 4, "tgt": "ally", "st": [["inspirado", 1.0, 2]], "d": "Inspira a un aliado 2 turnos."}],
			["pgen_alegria", "Alegría", {"fx": {"voluntad": 2}, "d": "+2 de Voluntad."}],
			["pgen_brindis", "Brindis", {"pt": 8, "tgt": "allies", "st": [["inspirado", 1.0, 1]], "fx": {"morale": 12}, "d": "+12 de moral y un turno inspirados."}],
			["pgen_companero", "Buen compañero", {"fx": {"ally_dmg": 0.03, "ally_hit": 0.02}, "d": "Su grupo hace +3% de daño y acierta más."}],
			["pgen_risa", "Risa contagiosa", {"t": 2, "fx": {"ally_morale": 5}, "d": "+5 de moral al grupo al empezar."}],
			["pgen_fiesta", "Fiesta", {"t": 3, "pt": 9, "tgt": "allies", "st": [["inspirado", 1.0, 2]], "d": "Inspira al grupo 2 turnos."}],
			["pgen_hermanos", "Hermanos de armas", {"t": 4, "fx": {"ally_dmg": 0.04, "ally_hit": 0.03}, "d": "+4% de daño y +3% de acierto al grupo."}]]],
	]],
	"p_cobarde": ["Cobarde", [
		["Huida", [
			["pcob_pies", "Pies ligeros", {"fx": {"retreat": 0.25}, "d": "+25% de éxito al retirarse."}],
			["pcob_esconderse", "Esconderse", {"pt": 4, "tgt": "self", "st": [["oculto", 1.0, 1]], "d": "Casi no le aciertan un turno."}],
			["pcob_liebre", "Nervios de liebre", {"fx": {"agilidad": 3}, "d": "+3 de Agilidad."}],
			["pcob_desaparecer", "Esfumarse", {"pt": 8, "tgt": "self", "st": [["oculto", 1.0, 2]], "d": "Oculto 2 turnos."}],
			["pcob_rata", "Instinto de rata", {"fx": {"evasion": 0.08, "retreat": 0.2}, "d": "+8% de esquiva y huye mejor."}],
			["pcob_polvareda", "Polvareda", {"t": 2, "pt": 5, "tgt": "enemies", "st": [["cegado", 0.4, 1]], "d": "Levanta polvo: puede cegar."}],
			["pcob_retirada", "Retirada", {"t": 3, "fx": {"retreat": 0.15, "evasion": 0.03}, "d": "Huye mejor; +3% de esquiva."}],
			["pcob_escurridizo", "Escurridizo", {"t": 4, "fx": {"evasion": 0.06, "agilidad": 2}, "d": "+6% de esquiva y +2 de Agilidad."}]]],
		["Esquiva", [
			["pcob_agacharse", "Agacharse", {"fx": {"evasion": 0.05}, "d": "+5% de esquiva."}],
			["pcob_suplicar", "Suplicar", {"pt": 5, "tgt": "enemy", "st": [["debilitado", 0.55, 2]], "d": "Implora piedad: puede debilitarle."}],
			["pcob_miedo", "Miedo que salva", {"fx": {"low_hp_taken": -0.2}, "d": "−20% de daño con poca vida."}],
			["pcob_superviviente", "Superviviente", {"fx": {"last_stand": 1}, "d": "Una vez por combate aguanta con 1 PV."}],
			["pcob_tirarse", "Tirarse al suelo", {"t": 2, "pt": 4, "tgt": "self", "st": [["fortaleza", 1.0, 1]], "d": "Se cubre 1 turno."}],
			["pcob_sudor", "Sudor frío", {"t": 3, "fx": {"low_hp_taken": -0.12, "evasion": 0.02}, "d": "−12% de daño con poca vida."}],
			["pcob_vivo", "Seguir vivo", {"t": 4, "fx": {"evasion": 0.04, "regen": 0.02}, "d": "+4% de esquiva y recupera vida."}]]],
		["Golpe bajo", [
			["pcob_espalda", "Por la espalda", {"pt": 5, "tgt": "enemy", "pow": 1.0, "fx": {"crit": 0.15}, "d": "+15% de crítico."}],
			["pcob_piedras", "Tirar piedras", {"pt": 3, "tgt": "enemy", "pow": 0.7, "dt": T3, "d": "Proyectil desde lejos."}],
			["pcob_caido", "Atacar al caído", {"pt": 6, "tgt": "enemy", "pow": 1.0, "fx": {"exec": 1.8}, "d": "×1,8 a quien tenga menos del 30% de vida."}],
			["pcob_pinchazo", "Pinchazo traicionero", {"pt": 8, "tgt": "enemy", "pow": 0.9, "fx": {"agi": 0.4}, "st": [["sangrado", 0.5, 2]], "d": "Suma su Agilidad y puede hacer sangrar."}],
			["pcob_tierra", "Puñado de tierra", {"t": 2, "pt": 4, "tgt": "enemy", "st": [["cegado", 0.6, 2]], "d": "Le tira tierra a los ojos."}],
			["pcob_rodilla", "Golpe a la rodilla", {"t": 3, "pt": 8, "tgt": "enemy", "pow": 0.85, "dt": T2, "st": [["derribado", 0.45, 1]], "d": "Puede derribar."}],
			["pcob_trapera", "Puñalada trapera", {"t": 4, "pt": 14, "tgt": "enemy", "pow": 1.25, "dt": T1, "fx": {"vs_status": 1.5, "crit": 0.15}, "d": "Mucho más daño si el rival está tocado."}]]],
	]],
	"p_romantico": ["Romántico", [
		["Pasión", [
			["prom_impetu", "Ímpetu", {"pt": 4, "tgt": "enemy", "pow": 1.1, "fx": {"agi": 0.2}, "d": "Golpe apasionado; suma algo de Agilidad."}],
			["prom_pasion", "Pasión", {"fx": {"crit": 0.04}, "d": "+4% de crítico."}],
			["prom_dama", "¡Por mi dama!", {"pt": 6, "tgt": "self", "st": [["inspirado", 1.0, 3]], "d": "Se inspira 3 turnos."}],
			["prom_audacia", "Audacia", {"fx": {"crit_mult": 0.15, "agilidad": 1}, "d": "Críticos más dañinos; +1 de Agilidad."}],
			["prom_gesta", "Gesta de leyenda", {"pt": 14, "tgt": "enemy", "pow": 1.9, "fx": {"crit": 0.2}, "d": "Golpe legendario, +20% de crítico."}],
			["prom_arrebato", "Arrebato", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 1.1, "fx": {"self_st": [["inspirado", 2]]}, "d": "Golpe apasionado; se inspira."}],
			["prom_fuego", "Fuego interior", {"t": 3, "fx": {"low_hp_dmg": 0.15, "voluntad": 1}, "d": "+15% de daño con poca vida."}],
			["prom_por_amor", "Por amor", {"t": 4, "pt": 16, "tgt": "enemy", "pow": 1.6, "fx": {"crit": 0.1}, "d": "Golpe enorme con +10% de crítico."}]]],
		["Caballerosidad", [
			["prom_galante", "Gesto galante", {"pt": 4, "tgt": "ally", "fx": {"cover": 1}, "d": "Recibe los golpes dirigidos a un aliado."}],
			["prom_ideal", "Ideal", {"fx": {"voluntad": 2, "status_res": 0.05}, "d": "+2 de Voluntad."}],
			["prom_cancion", "Canción de gesta", {"pt": 8, "tgt": "allies", "st": [["inspirado", 1.0, 1]], "fx": {"morale": 10}, "d": "+10 de moral al grupo e inspira."}],
			["prom_leyenda", "Leyenda viva", {"fx": {"ally_morale": 8}, "d": "+8 de moral al grupo al empezar."}],
			["prom_reverencia", "Reverencia", {"t": 2, "pt": 5, "tgt": "ally", "fx": {"cover": 1, "self_st": [["fortaleza", 1]]}, "d": "Cubre a un aliado y se refuerza."}],
			["prom_honor", "Honor de caballero", {"t": 3, "fx": {"guard": 0.15, "ally_taken": -0.04}, "d": "Su grupo recibe −4% de daño."}],
			["prom_justa", "Justa", {"t": 4, "pt": 15, "tgt": "enemy", "pow": 1.5, "dt": T1, "st": [["derribado", 0.4, 1]], "d": "Lanzazo que puede derribar."}]]],
		["Musa", [
			["prom_inspiracion", "Inspiración", {"fx": {"pt_pct": 0.1}, "d": "+10% de PT."}],
			["prom_versos", "Versos", {"pt": 4, "tgt": "ally", "fx": {"pt_give": 8}, "d": "Da 8 PT a un aliado."}],
			["prom_danza", "Danza", {"fx": {"evasion": 0.05}, "d": "+5% de esquiva."}],
			["prom_entrega", "Entrega", {"pt": 7, "tgt": "ally", "heal": 0.2, "st": [["inspirado", 1.0, 2]], "d": "Cura el 20% e inspira."}],
			["prom_serenata", "Serenata", {"t": 2, "pt": 6, "tgt": "allies", "fx": {"morale": 8}, "d": "+8 de moral al grupo."}],
			["prom_musa", "Inspiración constante", {"t": 3, "fx": {"ally_crit": 0.03, "ally_morale": 4}, "d": "+3% de crítico al grupo."}],
			["prom_balada", "Balada de héroes", {"t": 4, "pt": 16, "tgt": "allies", "st": [["inspirado", 1.0, 3]], "fx": {"haste": 1}, "d": "Inspira al grupo 3 turnos y actúan antes."}]]],
	]],
	"p_honorable": ["Honorable", [
		["Duelo", [
			["phon_saludo", "Saludo de armas", {"pt": 3, "tgt": "enemy", "pow": 1.0, "fx": {"acc": 0.1}, "d": "Golpe limpio y seguro."}],
			["phon_limpio", "Combate limpio", {"fx": {"punteria": 2}, "d": "+2 de Puntería."}],
			["phon_desafio", "Desafío de honor", {"pt": 7, "tgt": "enemy", "pow": 1.2, "st": [["provocado", 0.9, 2]], "d": "Golpea y lo reta."}],
			["phon_maestria", "Maestría del caballero", {"fx": {"counter": 0.1, "crit": 0.03}, "d": "+10% de contraataque y +3% de crítico."}],
			["phon_juicio", "Juicio por combate", {"pt": 14, "tgt": "enemy", "pow": 1.8, "fx": {"pierce": 1}, "d": "Golpe decisivo que ignora la armadura."}],
			["phon_estocada", "Estocada limpia", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 1.15, "fx": {"acc": 0.1}, "d": "Golpe preciso."}],
			["phon_respeto", "Respeto", {"t": 3, "fx": {"counter": 0.1, "crit": 0.03}, "d": "+10% de contraataque y +3% de crítico."}],
			["phon_duelo_final", "Duelo final", {"t": 4, "pt": 16, "tgt": "enemy", "pow": 1.6, "fx": {"pierce": 1}, "d": "Golpe que atraviesa la armadura."}]]],
		["Palabra", [
			["phon_promesa", "Palabra dada", {"fx": {"voluntad": 2}, "d": "+2 de Voluntad."}],
			["phon_firmeza", "Firmeza", {"fx": {"status_res": 0.1}, "d": "Resiste mejor los estados."}],
			["phon_virtud", "Ejemplo de virtud", {"pt": 8, "tgt": "allies", "st": [["inspirado", 1.0, 2]], "d": "Todo el grupo inspirado 2 turnos."}],
			["phon_estandarte", "Estandarte", {"fx": {"ally_taken": -0.04, "ally_morale": 5}, "d": "Su grupo recibe −4% de daño; +5 de moral."}],
			["phon_juramento", "Juramento", {"t": 2, "pt": 5, "tgt": "allies", "fx": {"morale": 8}, "d": "+8 de moral al grupo."}],
			["phon_integro", "Íntegro", {"t": 3, "fx": {"status_res": 0.12, "voluntad": 2}, "d": "Resiste estados; +2 de Voluntad."}],
			["phon_ejemplo", "Ejemplo vivo", {"t": 4, "fx": {"ally_hit": 0.03, "ally_morale": 6}, "d": "+3% de acierto y +6 de moral al grupo."}]]],
		["Escudo del débil", [
			["phon_amparar", "Amparar", {"pt": 4, "tgt": "ally", "fx": {"cover": 1}, "d": "Recibe los golpes dirigidos a un aliado."}],
			["phon_guardia", "Guardia caballeresca", {"fx": {"guard": 0.2}, "d": "Defender reduce más el daño."}],
			["phon_desarmar", "Desarmar sin herir", {"pt": 5, "tgt": "enemy", "pow": 0.5, "st": [["desarmado", 0.7, 2]], "d": "Puede desarmarlo."}],
			["phon_baluarte", "Baluarte de honor", {"pt": 8, "tgt": "ally", "st": [["fortaleza", 1.0, 2]], "fx": {"cover": 1}, "d": "Cubre a un aliado y lo refuerza."}],
			["phon_amparo", "Amparo", {"t": 2, "pt": 4, "tgt": "ally", "fx": {"cover": 1}, "d": "Recibe los golpes dirigidos a un aliado."}],
			["phon_paladin", "Paladín", {"t": 3, "fx": {"ally_taken": -0.05, "defensa": 1}, "d": "Su grupo recibe −5% de daño."}],
			["phon_castigo", "Castigo justo", {"t": 4, "pt": 15, "tgt": "enemy", "pow": 1.3, "st": [["aturdido", 0.3, 1]], "fx": {"vs_status": 1.4}, "d": "Más daño si está tocado; puede aturdir."}]]],
	]],
	# ================= ALINEAMIENTO =================
	"a_conquistador": ["Conquistador", [
		["Vanguardia", [
			["acon_adelante", "¡Adelante!", {"pt": 5, "tgt": "allies", "fx": {"haste": 1}, "d": "Todo el grupo actúa antes."}],
			["acon_ofensiva", "Espíritu ofensivo", {"fx": {"ally_dmg": 0.03}, "d": "Su grupo hace +3% de daño."}],
			["acon_carga", "Carga general", {"pt": 10, "tgt": "allies", "st": [["inspirado", 1.0, 2]], "fx": {"morale": 8}, "req_troops": 20, "d": "Inspira al grupo y +8 de moral."}],
			["acon_impulso", "Impulso", {"fx": {"ally_init": 0.1}, "d": "Su grupo empieza el combate antes."}],
			["acon_marea", "Marea de acero", {"pt": 16, "tgt": "enemies", "pow": 0.8, "fx": {"estr": 0.3}, "req_troops": 50, "d": "Golpea a todos; suma su Estrategia."}],
			["acon_lanzazo", "Lanzazo", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 1.2, "dt": T1, "d": "Estocada de vanguardia."}],
			["acon_avance", "Avance", {"t": 3, "fx": {"ally_init": 0.05, "ally_dmg": 0.03}, "d": "Su grupo actúa antes y pega +3%."}],
			["acon_arrollar", "Arrollar", {"t": 4, "pt": 16, "tgt": "enemies", "pow": 0.95, "st": [["derribado", 0.25, 1]], "d": "Golpea a todos: puede derribar."}]]],
		["Asedio", [
			["acon_brecha", "Abrir brecha", {"pt": 6, "tgt": "enemy", "pow": 1.0, "dt": T2, "fx": {"pierce": 1}, "d": "Golpe Contundente que ignora la armadura."}],
			["acon_ariete", "Ariete", {"fx": {"dmg_t2": 0.08}, "d": "+8% de daño Contundente."}],
			["acon_asedio", "Cerco", {"pt": 8, "tgt": "enemy", "st": [["analizado", 1.0, 3], ["debilitado", 0.5, 2]], "d": "Revela sus debilidades y puede debilitarlo."}],
			["acon_plaza", "Tomar la plaza", {"fx": {"fuerza_pct": 0.06}, "d": "+6% de Fuerza."}],
			["acon_escalas", "Escalas", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 0.95, "fx": {"pierce": 1}, "d": "Ataque que ignora la armadura."}],
			["acon_cerco", "Cerco", {"t": 3, "fx": {"pt_regen": 1, "defensa": 1}, "d": "+1 PT por turno y +1 de Defensa."}],
			["acon_saqueo", "Saqueo", {"t": 4, "pt": 14, "tgt": "enemy", "pow": 1.15, "st": [["desarmado", 0.5, 2]], "fx": {"pt_drain": 10}, "d": "Le roba 10 PT y puede desarmarlo."}]]],
		["Expansión", [
			["acon_reparto", "Reparto del botín", {"fx": {"ally_morale": 6}, "d": "+6 de moral al grupo al empezar."}],
			["acon_marcha", "Marcha forzada", {"fx": {"agilidad": 2}, "d": "+2 de Agilidad."}],
			["acon_ordenes", "Órdenes claras", {"fx": {"ally_hit": 0.03}, "d": "Su grupo acierta un 3% más."}],
			["acon_imperio", "Sueño de imperio", {"pt": 9, "tgt": "allies", "st": [["fortaleza", 1.0, 2]], "fx": {"morale": 6}, "req_morale": 50, "d": "Refuerza al grupo y sube la moral."}],
			["acon_botin", "Botín de guerra", {"t": 2, "fx": {"lifesteal": 0.04}, "d": "Recupera el 4% del daño que hace."}],
			["acon_banderas", "Banderas", {"t": 3, "pt": 9, "tgt": "allies", "st": [["inspirado", 1.0, 1]], "fx": {"morale": 10}, "d": "+10 de moral e inspira al grupo 1 turno."}],
			["acon_dominio", "Dominio", {"t": 4, "fx": {"ally_dmg": 0.04, "fear": 5}, "d": "+4% de daño al grupo; el enemigo empieza con −5 de moral."}]]],
	]],
	"a_pacifista": ["Pacifista", [
		["Calma", [
			["apac_calmar", "Calmar", {"pt": 5, "tgt": "enemy", "st": [["debilitado", 0.6, 2]], "d": "Le aplaca: pega y se protege menos."}],
			["apac_paz", "Paz interior", {"fx": {"voluntad": 3}, "d": "+3 de Voluntad."}],
			["apac_serenar", "Serenar", {"pt": 8, "tgt": "allies", "st": [["sereno", 1.0, 2]], "d": "El grupo recupera vida 2 turnos."}],
			["apac_desarmar", "Desarmar los ánimos", {"pt": 9, "tgt": "enemies", "st": [["desarmado", 0.4, 2]], "d": "Puede desarmar a todos."}],
			["apac_tregua", "Gran tregua", {"pt": 15, "tgt": "enemies", "st": [["aturdido", 0.35, 1]], "fx": {"morale": -10}, "d": "Pueden perder el turno; −10 de moral."}],
			["apac_mediar", "Mediar", {"t": 2, "pt": 5, "tgt": "enemy", "st": [["debilitado", 0.6, 2]], "d": "Le quita las ganas de pelear: puede debilitarlo."}],
			["apac_quietud", "Quietud", {"t": 3, "fx": {"status_res": 0.1, "regen": 0.02}, "d": "Resiste estados y recupera vida."}],
			["apac_armisticio", "Armisticio", {"t": 4, "pt": 15, "tgt": "enemies", "st": [["desarmado", 0.45, 2]], "fx": {"morale": -8}, "d": "Puede desarmar a todos; −8 de moral."}]]],
		["Amparo", [
			["apac_curar", "Curar", {"pt": 6, "tgt": "ally", "heal": 0.25, "d": "Cura el 25% de la vida."}],
			["apac_cuidar", "Cuidar", {"fx": {"heal_bonus": 0.2}, "d": "Sus curas son un 20% mejores."}],
			["apac_aliviar", "Aliviar", {"pt": 5, "tgt": "ally", "heal": 0.1, "fx": {"cleanse": 1}, "d": "Quita los estados y cura un poco."}],
			["apac_refugio", "Refugio", {"fx": {"regen": 0.03, "ally_taken": -0.03}, "d": "Recupera un 3% de vida por turno; grupo −3% de daño."}],
			["apac_panos", "Paños tibios", {"t": 2, "pt": 5, "tgt": "ally", "heal": 0.18, "d": "Cura el 18% de la vida."}],
			["apac_cobijo", "Cobijo", {"t": 3, "pt": 10, "tgt": "allies", "st": [["sereno", 1.0, 2]], "d": "Serena al grupo 2 turnos."}],
			["apac_santuario", "Santuario", {"t": 4, "fx": {"ally_taken": -0.06, "heal_bonus": 0.1}, "d": "Su grupo recibe −6% de daño; curas mejores."}]]],
		["No violencia", [
			["apac_esquivar", "No devolver el golpe", {"fx": {"evasion": 0.05}, "d": "+5% de esquiva."}],
			["apac_parar", "Parar sin herir", {"fx": {"guard": 0.2}, "d": "Defender reduce más el daño."}],
			["apac_contener", "Contener", {"pt": 5, "tgt": "enemy", "pow": 0.5, "dt": T2, "st": [["desequilibrado", 0.6, 2]], "d": "Puede desequilibrarlo."}],
			["apac_dialogo", "Diálogo", {"fx": {"fear": 6}, "d": "Los enemigos empiezan con −6 de moral."}],
			["apac_sujetar", "Sujetar", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 0.3, "dt": T2, "st": [["derribado", 0.4, 1]], "d": "Lo inmoviliza: puede derribarlo."}],
			["apac_sin_rencor", "Sin rencor", {"t": 3, "fx": {"evasion": 0.04, "guard": 0.15}, "d": "+4% de esquiva; defender protege más."}],
			["apac_firmeza", "Firmeza serena", {"t": 4, "fx": {"immune_derribo": 1, "taken": -0.04}, "d": "No lo derriban; −4% de daño recibido."}]]],
	]],
	"a_ambicioso": ["Ambicioso", [
		["Poder", [
			["aamb_mando", "Mando férreo", {"pt": 5, "tgt": "ally", "st": [["inspirado", 1.0, 1]], "fx": {"advance": 1}, "d": "Un aliado actúa ya."}],
			["aamb_autoridad", "Autoridad", {"fx": {"ally_dmg": 0.03}, "d": "Su grupo hace +3% de daño."}],
			["aamb_exigir", "Exigir", {"pt": 8, "tgt": "allies", "st": [["inspirado", 1.0, 2]], "d": "Todo el grupo inspirado 2 turnos."}],
			["aamb_cetro", "Cetro", {"fx": {"ally_crit": 0.03, "ally_morale": 4}, "d": "Su grupo +3% de crítico y +4 de moral."}],
			["aamb_trono", "Ambición sin límites", {"pt": 14, "tgt": "allies", "st": [["inspirado", 1.0, 3]], "fx": {"haste": 1}, "d": "El grupo actúa antes, inspirado 3 turnos."}],
			["aamb_decreto", "Decreto", {"t": 2, "pt": 6, "tgt": "ally", "fx": {"haste": 1, "morale": 5}, "d": "El aliado actúa antes y gana moral."}],
			["aamb_corona", "Corona", {"t": 3, "fx": {"ally_dmg": 0.03, "voluntad": 2}, "d": "+3% de daño al grupo y +2 de Voluntad."}],
			["aamb_voluntad", "Voluntad de hierro", {"t": 4, "pt": 16, "tgt": "allies", "st": [["inspirado", 1.0, 2]], "fx": {"pt_give": 6}, "d": "Inspira al grupo y le da 6 PT."}]]],
		["Intriga", [
			["aamb_espias", "Espías", {"pt": 4, "tgt": "enemy", "st": [["analizado", 1.0, 3]], "d": "Revela sus debilidades 3 turnos."}],
			["aamb_soborno", "Soborno", {"pt": 7, "tgt": "enemy", "st": [["aturdido", 0.5, 1]], "d": "Compra su duda: puede perder el turno."}],
			["aamb_red", "Red de informantes", {"fx": {"ally_hit": 0.03}, "d": "Su grupo acierta un 3% más."}],
			["aamb_punal", "Puñal en la sombra", {"pt": 9, "tgt": "enemy", "pow": 1.2, "fx": {"crit": 0.2, "estr": 0.3}, "d": "+20% de crítico; suma su Estrategia."}],
			["aamb_rumor", "Rumor", {"t": 2, "pt": 5, "tgt": "enemies", "fx": {"morale": -8}, "d": "−8 de moral a los enemigos."}],
			["aamb_copa", "Copa envenenada", {"t": 3, "pt": 9, "tgt": "enemy", "pow": 0.6, "dt": T1, "st": [["debilitado", 0.7, 2], ["sangrado", 0.5, 2]], "d": "Debilita y hace sangrar."}],
			["aamb_traicion", "Traición", {"t": 4, "pt": 15, "tgt": "enemy", "pow": 1.4, "dt": T1, "fx": {"vs_status": 1.4, "crit": 0.1}, "d": "Mucho más daño si el rival está tocado."}]]],
		["Fortuna", [
			["aamb_oro", "Bolsa de oro", {"fx": {"pt_pct": 0.1}, "d": "+10% de PT."}],
			["aamb_suerte", "Suerte", {"fx": {"crit": 0.04}, "d": "+4% de crítico."}],
			["aamb_rentas", "Rentas", {"fx": {"pt_regen": 1}, "d": "+1 PT por turno."}],
			["aamb_inversion", "Inversión", {"pt": 4, "tgt": "ally", "fx": {"pt_give": 10}, "d": "Da 10 PT a un aliado."}],
			["aamb_mercenarios", "Mercenarios", {"t": 2, "fx": {"ally_hit": 0.02, "ally_dmg": 0.02}, "d": "+2% de acierto y daño al grupo."}],
			["aamb_tesoro", "Tesoro", {"t": 3, "fx": {"pt_pct": 0.1, "pv_pct": 0.05}, "d": "+10% de PT y +5% de PV."}],
			["aamb_fortuna", "Golpe de fortuna", {"t": 4, "fx": {"crit": 0.04, "crit_mult": 0.15, "pt_regen": 1}, "d": "+4% de crítico, críticos más fuertes y +1 PT."}]]],
	]],
	"a_humilde": ["Humilde", [
		["Servicio", [
			["ahum_servir", "Servir", {"pt": 4, "tgt": "ally", "fx": {"cover": 1}, "d": "Recibe los golpes dirigidos a un aliado."}],
			["ahum_sencillez", "Sencillez", {"fx": {"pv_pct": 0.06}, "d": "+6% de PV."}],
			["ahum_cargar", "Cargar con el peso", {"fx": {"ally_taken": -0.04}, "d": "Su grupo recibe −4% de daño."}],
			["ahum_sacrificio", "Sacrificio", {"pt": 6, "tgt": "ally", "heal": 0.15, "fx": {"advance": 1}, "d": "Cura un poco a un aliado y le deja actuar ya."}],
			["ahum_ultimo", "El último de todos", {"fx": {"last_stand": 1, "guard": 0.2}, "d": "Aguanta una vez con 1 PV; mejor guardia."}],
			["ahum_mano", "Echar una mano", {"t": 2, "pt": 4, "tgt": "ally", "fx": {"pt_give": 6}, "d": "Da 6 PT a un aliado."}],
			["ahum_abnegado", "Abnegado", {"t": 3, "fx": {"ally_taken": -0.04, "guard": 0.1}, "d": "Su grupo recibe −4% de daño."}],
			["ahum_escudo_pueblo", "Escudo del pueblo", {"t": 4, "pt": 14, "tgt": "allies", "st": [["fortaleza", 1.0, 2]], "d": "Refuerza al grupo 2 turnos."}]]],
		["Sencillez", [
			["ahum_frugal", "Frugalidad", {"fx": {"pt_regen": 1}, "d": "+1 PT por turno."}],
			["ahum_paciencia", "Paciencia", {"fx": {"status_res": 0.1}, "d": "Resiste mejor los estados."}],
			["ahum_remendar", "Remendar", {"pt": 5, "tgt": "ally", "heal": 0.2, "d": "Cura el 20% de la vida."}],
			["ahum_tenacidad", "Tenacidad humilde", {"fx": {"regen": 0.03}, "d": "Recupera el 3% de la vida cada turno."}],
			["ahum_pan", "Pan y agua", {"t": 2, "fx": {"regen": 0.02, "pt_pct": 0.05}, "d": "Recupera vida; +5% de PT."}],
			["ahum_curtido", "Curtido", {"t": 3, "fx": {"pv_pct": 0.08, "status_res": 0.08}, "d": "+8% de PV y resiste estados."}],
			["ahum_constancia", "Constancia", {"t": 4, "fx": {"low_hp_taken": -0.12, "pv_pct": 0.06}, "d": "+6% de PV y −12% de daño con poca vida."}]]],
		["Pueblo", [
			["ahum_azada", "Golpe de azada", {"pt": 3, "tgt": "enemy", "pow": 1.1, "dt": T2, "d": "Golpe Contundente."}],
			["ahum_honda", "Honda", {"pt": 4, "tgt": "enemy", "pow": 1.0, "dt": T3, "d": "Proyectil."}],
			["ahum_juntos", "Juntos", {"fx": {"ally_dmg": 0.02, "ally_morale": 5}, "d": "Su grupo hace +2% de daño; +5 de moral."}],
			["ahum_pueblo", "Fuerza del pueblo", {"pt": 10, "tgt": "enemy", "pow": 0.5, "fx": {"per_ally": 1}, "d": "Daño según los aliados en pie."}],
			["ahum_horca", "Horca", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 1.15, "dt": T1, "d": "Estocada con la horca."}],
			["ahum_mayal", "Mayal", {"t": 3, "pt": 9, "tgt": "enemy", "pow": 1.15, "dt": T2, "st": [["aturdido", 0.35, 1]], "d": "Puede aturdir."}],
			["ahum_levantamiento", "Levantamiento", {"t": 4, "pt": 16, "tgt": "enemies", "pow": 0.85, "st": [["debilitado", 0.3, 2]], "d": "Golpea a todos y puede debilitarlos."}]]],
	]],
	"a_diplomatico": ["Diplomático", [
		["Palabra", [
			["adip_parlamentar", "Parlamentar", {"pt": 5, "tgt": "enemy", "st": [["debilitado", 0.5, 2]], "fx": {"morale": -6}, "d": "Puede debilitarlo; −6 de moral."}],
			["adip_tacto", "Tacto", {"fx": {"voluntad": 2, "status_res": 0.05}, "d": "+2 de Voluntad."}],
			["adip_persuadir", "Persuadir", {"pt": 7, "tgt": "enemy", "st": [["aturdido", 0.45, 1]], "d": "Puede hacerle dudar y perder el turno."}],
			["adip_elocuencia", "Elocuencia", {"fx": {"fear": 5, "ally_morale": 5}, "d": "−5 de moral al enemigo y +5 al grupo."}],
			["adip_rendicion", "Exigir rendición", {"pt": 14, "tgt": "enemies", "st": [["debilitado", 0.5, 2]], "fx": {"morale": -15}, "d": "Puede debilitar a todos; −15 de moral."}],
			["adip_cortesia", "Cortesía", {"t": 2, "pt": 5, "tgt": "enemy", "st": [["desarmado", 0.45, 2]], "d": "Lo convence de bajar el arma."}],
			["adip_oratoria", "Oratoria", {"t": 3, "fx": {"voluntad": 2, "ally_morale": 5}, "d": "+2 de Voluntad; +5 de moral al grupo."}],
			["adip_ultimatum", "Ultimátum", {"t": 4, "pt": 15, "tgt": "enemies", "st": [["debilitado", 0.4, 2]], "fx": {"morale": -12}, "d": "−12 de moral y puede debilitar a todos."}]]],
		["Pacto", [
			["adip_alianza", "Alianza", {"fx": {"ally_hit": 0.02, "ally_crit": 0.02}, "d": "Su grupo acierta más y +2% de crítico."}],
			["adip_coordinar", "Coordinar", {"pt": 5, "tgt": "ally", "fx": {"advance": 1}, "d": "Un aliado actúa ya."}],
			["adip_acuerdo", "Acuerdo de armas", {"pt": 9, "tgt": "allies", "st": [["fortaleza", 1.0, 2]], "d": "+50% de Defensa al grupo 2 turnos."}],
			["adip_concierto", "Concierto", {"fx": {"ally_init": 0.1}, "d": "Su grupo empieza el combate antes."}],
			["adip_consejo", "Consejo", {"t": 2, "pt": 8, "tgt": "allies", "fx": {"pt_give": 5}, "d": "Da 5 PT a todo el grupo."}],
			["adip_frente", "Frente común", {"t": 3, "fx": {"ally_hit": 0.03, "ally_init": 0.05}, "d": "Su grupo acierta más y actúa antes."}],
			["adip_gran_alianza", "Gran alianza", {"t": 4, "pt": 16, "tgt": "allies", "st": [["inspirado", 1.0, 2]], "fx": {"haste": 1}, "d": "Inspira al grupo y actúan antes."}]]],
		["Mediación", [
			["adip_intenciones", "Leer intenciones", {"pt": 4, "tgt": "enemy", "st": [["analizado", 1.0, 3]], "d": "Revela sus debilidades 3 turnos."}],
			["adip_mano", "Mano tendida", {"pt": 5, "tgt": "ally", "heal": 0.12, "fx": {"cleanse": 1}, "d": "Quita los estados y cura un poco."}],
			["adip_paciencia", "Paciencia", {"fx": {"evasion": 0.04, "punteria": 1}, "d": "+4% de esquiva y +1 de Puntería."}],
			["adip_salida", "Salida honrosa", {"fx": {"retreat": 0.3}, "d": "+30% de éxito al retirarse."}],
			["adip_templar", "Templar ánimos", {"t": 2, "pt": 5, "tgt": "ally", "fx": {"cleanse": 1, "morale": 5}, "d": "Quita los estados y da +5 de moral."}],
			["adip_neutral", "Neutralidad", {"t": 3, "fx": {"evasion": 0.03, "taken": -0.03}, "d": "+3% de esquiva y −3% de daño recibido."}],
			["adip_tregua", "Tregua forzada", {"t": 4, "pt": 14, "tgt": "enemy", "st": [["aturdido", 0.6, 1], ["desarmado", 0.5, 2]], "d": "Puede aturdirlo y desarmarlo."}]]],
	]],
	"a_tirano": ["Tirano", [
		["Terror", [
			["atir_intimidar", "Intimidar", {"pt": 6, "tgt": "enemies", "st": [["debilitado", 0.4, 2]], "d": "Puede debilitar a todos."}],
			["atir_temido", "Temido", {"fx": {"fear": 8}, "d": "Los enemigos empiezan con −8 de moral."}],
			["atir_terror", "Terror", {"pt": 9, "tgt": "enemies", "fx": {"morale": -15}, "d": "−15 de moral a todos los enemigos."}],
			["atir_presencia", "Presencia aplastante", {"fx": {"fear": 6, "status_res": 0.1}, "d": "−6 de moral al enemigo; resiste estados."}],
			["atir_reinado", "Reinado de terror", {"pt": 15, "tgt": "enemies", "st": [["aturdido", 0.3, 1]], "fx": {"morale": -15}, "req_morale": 40, "d": "Pueden quedar paralizados; −15 de moral."}],
			["atir_ejemplo", "Ejemplo", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 1.0, "fx": {"morale": -10}, "d": "Golpe que le baja 10 de moral."}],
			["atir_sombra", "Sombra temida", {"t": 3, "fx": {"fear": 5, "voluntad": 1}, "d": "El enemigo empieza con −5 de moral."}],
			["atir_pavor", "Pavor", {"t": 4, "pt": 15, "tgt": "enemies", "st": [["debilitado", 0.5, 2], ["aturdido", 0.2, 1]], "fx": {"morale": -8}, "d": "Debilita, puede aturdir y baja la moral."}]]],
		["Yugo", [
			["atir_latigo", "Látigo", {"pt": 4, "tgt": "ally", "fx": {"advance": 1}, "d": "Obliga a un aliado a actuar ya."}],
			["atir_obediencia", "Obediencia", {"fx": {"ally_dmg": 0.03}, "d": "Su grupo hace +3% de daño."}],
			["atir_disciplina", "Disciplina de hierro", {"fx": {"status_res": 0.1, "ally_hit": 0.02}, "d": "Resiste estados; su grupo acierta más."}],
			["atir_canon", "Carne de cañón", {"pt": 8, "tgt": "allies", "st": [["furia", 1.0, 2]], "d": "Todo el grupo en furia 2 turnos."}],
			["atir_grilletes", "Grilletes", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 0.6, "dt": T2, "st": [["desequilibrado", 0.6, 2]], "d": "Puede desequilibrar."}],
			["atir_capataz", "Capataz", {"t": 3, "fx": {"ally_dmg": 0.03, "ally_init": 0.04}, "d": "Su grupo pega +3% y actúa antes."}],
			["atir_marcha", "Marcha forzada", {"t": 4, "pt": 14, "tgt": "allies", "st": [["furia", 1.0, 2]], "fx": {"haste": 1}, "d": "El grupo actúa antes y entra en furia."}]]],
		["Castigo", [
			["atir_castigo", "Castigo ejemplar", {"pt": 7, "tgt": "enemy", "pow": 1.2, "fx": {"exec": 1.6}, "d": "×1,6 a quien tenga menos del 30% de vida."}],
			["atir_mano", "Mano dura", {"fx": {"fuerza_pct": 0.05}, "d": "+5% de Fuerza."}],
			["atir_aplastar", "Aplastar la rebelión", {"pt": 8, "tgt": "enemy", "pow": 1.1, "dt": T2, "st": [["derribado", 0.35, 1]], "d": "Puede derribarlo."}],
			["atir_cadalso", "Cadalso", {"fx": {"crit_mult": 0.2}, "d": "Críticos más dañinos."}],
			["atir_azote", "Azote", {"t": 2, "pt": 6, "tgt": "enemy", "pow": 0.9, "dt": T0, "st": [["sangrado", 0.5, 2]], "d": "Puede hacer sangrar."}],
			["atir_implacable", "Implacable", {"t": 3, "fx": {"crit": 0.04, "lifesteal": 0.04}, "d": "+4% de crítico; recupera el 4% del daño."}],
			["atir_sentencia", "Sentencia", {"t": 4, "pt": 16, "tgt": "enemy", "pow": 1.3, "fx": {"exec": 2.0}, "d": "Ejecución: daño enorme a los débiles."}]]],
	]],
	# ================= ENEMIGOS Y MINI JEFES (no se aprenden) =================
	"boss": ["Enemigos", [
		["Tropa", [
			["ene_carga", "Carga", {"pt": 8, "tgt": "enemy", "pow": 1.8, "dt": T1, "st": [["derribado", 0.35, 1]], "d": "Carga a caballo: puede derribar."}],
			["ene_virote", "Virote perforante", {"pt": 6, "tgt": "enemy", "pow": 1.4, "dt": T3, "fx": {"pierce": 1}, "d": "Atraviesa cualquier armadura."}],
			["ene_picas", "Muro de picas", {"fx": {"counter": 0.25}, "d": "Castiga a quien se acerca."}]]],
		["Jefes", [
			["jef_saqueo", "Saqueo", {"pt": 8, "tgt": "enemy", "pow": 1.3, "fx": {"pt_drain": 10}, "d": "Golpea y roba PT."}],
			["jef_formacion", "¡Formación!", {"pt": 10, "tgt": "allies", "st": [["fortaleza", 1.0, 2], ["inspirado", 1.0, 2]], "d": "Refuerza e inspira a los suyos."}],
			["jef_campeon", "Lanzada de campeón", {"pt": 10, "tgt": "enemy", "pow": 2.0, "dt": T1, "fx": {"crit": 0.2}, "d": "La lanzada que gana torneos."}],
			["jef_carga_sagrada", "Carga sagrada", {"pt": 14, "tgt": "enemies", "pow": 1.0, "st": [["derribado", 0.3, 1]], "d": "Arrolla a todos."}],
			["jef_turba", "Turba descalza", {"pt": 12, "tgt": "random3", "pow": 0.6, "dt": T2, "hits": 4, "d": "4 golpes al azar."}],
			["jef_vigilia", "Vigilia del guardián", {"pt": 10, "tgt": "self", "heal": 0.2, "st": [["fortaleza", 1.0, 2]], "d": "Se cura y se refuerza."}]]],
	]],
}

# Ids antiguos (árbol común de la primera versión) → nodo actual.
const ALIASES := {
	"com_grito": "plea_animo", "com_auxilios": "plea_auxilio", "com_proteger": "plea_proteger",
	"com_proy1": "ase_disparo", "com_proy2": "ase_disparo", "com_tajo1": "ber_tajo1", "com_esto1": "due_esto1",
	"com_cont1": "tan_cont1", "com_cont2": "tan_rompe", "com_esto2": "due_punto", "com_tajo2": "ber_barrido",
	"com_aguante": "pval_aguante", "com_segundo": "ppru_segundo", "com_reflejos": "ppru_reflejos",
	"com_piel": "ppru_piel", "com_viento": "ppru_respiro", "com_temple": "ppru_temple", "com_voz": "plea_hombro",
	"com_intimidar": "atir_intimidar", "com_estratagema": "pamb_teson", "tan_fuerza": "ber_fuerza",
	"tan_fortaleza": "ppru_defensa", "due_halcon": "past_ojo", "due_leer": "est_leer", "due_reto": "pval_reto",
	"due_gracia": "pamb_presa", "est_retirada": "adip_salida", "est_estandarte": "phon_estandarte",
	"est_arenga": "pgen_brindis", "ber_salvaje": "ber_fuerza", "ber_temple": "ppru_temple", "def_fe": "def_firme",
	"ase_precision": "ase_ojo", "ase_tendones": "past_lazo",
}

# Habilidades de combate y de batalla antiguas → nodo que conceden gratis (no gastan puntos).
const LEGACY_SKILL_NODES := {
	"Desarme Fulminante": "due_desarme", "Mano Rápida": "due_desarme", "Piel de Hierro": "tan_piel",
	"Golpe Certero": "due_certero", "Maestro de Parada": "def_parada", "Danza de Espadas": "due_danza",
	"Fuerza Bruta": "ber_fuerza", "Resistencia": "pval_aguante", "Segundo Aliento": "ppru_segundo",
	"Furia del Herido": "ber_herido", "Contragolpe Letal": "due_contra", "Ojo de Halcón": "past_ojo",
	"Guardia Férrea": "tan_guardia", "Zancadilla": "past_lazo", "Iniciativa": "est_iniciativa",
	"Temple": "ppru_temple", "Rostro de Piedra": "ppru_temple", "Intimidación": "atir_intimidar",
	"Lectura del Rival": "est_leer", "Maestro de Esgrima": "due_guardia", "Muro de Acero": "tan_muro",
	"Furia Desatada": "ber_furia",
	"Grito de Guerra": "est_grito", "Muro de Escudos": "tan_muro", "Ataque Coordinado": "plea_hombro",
	"Lluvia de Flechas": "ase_disparo", "Arqueros de Élite": "ase_disparo", "Escolta del General": "plea_proteger",
	"Leer al Enemigo": "est_leer", "Disciplina de Hierro": "atir_disciplina", "Estandarte Sagrado": "phon_estandarte",
	"Carga Letal": "pval_carga", "Muro de Picas": "due_esto1", "Represalia": "tan_represalia",
}
# Equipo que concede un nodo mientras se lleva puesto.
const EQUIPMENT_NODES := {
	"Estoque de Duelo": "due_guardia", "Manual de Esgrima": "due_guardia", "Hacha de Berserker": "ber_furia",
	"Pavés": "tan_muro", "Escudo de Cometa": "plea_proteger", "Arco Largo": "ase_disparo",
	"Ballesta de Cranequín": "ene_virote", "Lanza": "due_esto1", "Estoque": "due_brecha", "Bolsa de Hierbas": "plea_auxilio",
}
# Piezas únicas (SkillEffects.UNIQUE_*) → efecto pasivo en el RPG.
const UNIQUE_FX := {
	"durandal": {"first_sure": 1}, "sangrado": {"on_hit_bleed": 1, "brecha": 1}, "anticritico": {"crit_ward": 1},
	"reflejo": {"reflect": 0.25}, "firmeza": {"immune_derribo": 1}, "oriflama": {"voluntad": 4},
	"olifante": {"pt_pct": 0.15}, "reliquia": {"status_res": 0.2}, "babieca": {"agilidad": 2},
	"elocuencia": {"voluntad": 2}, "camino_seguro": {"evasion": 0.03}, "sello": {"voluntad": 2},
}

static var _by_id := {}
static var _all: Array = []
static var _trees := {}

static func _build() -> void:
	if not _all.is_empty():
		return
	for tid: String in TREES:
		var def: Array = TREES[tid]
		var tdesc := {"id": tid, "name": def[0], "branches": []}
		for bi in def[1].size():
			var br: Array = def[1][bi]
			var ids := []
			var basics := []
			var tiers := []
			for i in br[1].size():
				var spec: Array = br[1][i]
				var tier: int = 1 if tid == TREE_BOSS else int((spec[2] as Dictionary).get("t", [1, 1, 2, 3, 4][mini(i, 4)]))
				tiers.append(tier)
				if tier == 1:
					basics.append(spec[0])
			for i in br[1].size():
				var spec: Array = br[1][i]
				var tier: int = tiers[i]
				var n: Dictionary = (spec[2] as Dictionary).duplicate(true)
				n.merge({"id": spec[0], "name": spec[1], "tree": tid, "branch": bi, "tier": tier,
					"kind": "act" if n.has("tgt") else "pas", "desc": n.get("d", ""), "cost": TIER_COST[tier]})
				n.erase("d")
				n.erase("t")
				if n.kind == "act":
					n["pow"] = float(n.get("pow", 0.0))
					n["dt"] = int(n.get("dt", -1))
				# Escalón 3+: pide el último nodo anterior (en la lista) del escalón inmediatamente inferior.
				var prev := ""
				for j in i:
					if tiers[j] == tier - 1:
						prev = br[1][j][0]
				n["req"] = [prev] if tier >= 3 and prev != "" else []
				n["req_any"] = basics.duplicate() if tier == 2 else []
				ids.append(spec[0])
				_all.append(n)
				_by_id[spec[0]] = n
			# Se muestran ordenados por escalón (orden estable dentro de cada escalón).
			var shown := []
			for t in range(1, 5):
				for i in ids.size():
					if tiers[i] == t:
						shown.append(ids[i])
			tdesc.branches.append({"name": br[0], "nodes": shown})
		_trees[tid] = tdesc

# --- Árboles ---

static func fighter_tree(ft: int) -> String:
	return FIGHTER_TREES[clampi(ft, 0, FIGHTER_TREES.size() - 1)]

static func personality_tree(p: int) -> String:
	return PERSONALITY_TREES[clampi(p, 0, PERSONALITY_TREES.size() - 1)]

static func alignment_tree(a: int) -> String:
	return ALIGNMENT_TREES[clampi(a, 0, ALIGNMENT_TREES.size() - 1)]

## Los tres árboles del personaje: [luchador, personalidad, alineamiento].
static func trees_for(c: Character) -> Array[String]:
	var out: Array[String] = [fighter_tree(c.fighter_type), personality_tree(c.personality), alignment_tree(c.alignment)]
	return out

## {"id", "name", "branches": [{"name", "nodes": [ids...]}]} (vacío si no existe).
static func tree(tree_id: String) -> Dictionary:
	_build()
	return _trees.get(tree_id, {})

static func tree_ids() -> Array:
	return FIGHTER_TREES + PERSONALITY_TREES + ALIGNMENT_TREES

static func node(id: String) -> Dictionary:
	_build()
	return _by_id.get(ALIASES.get(id, id), {})

static func all_nodes() -> Array:
	_build()
	return _all

static func nodes_of_tree(tree_id: String) -> Array:
	return all_nodes().filter(func(n: Dictionary) -> bool: return n.tree == tree_id)

## Nodos básicos (escalón 1) de una rama: el primero que se aprende en cada rama es gratis.
static func basic_nodes(tree_id: String, branch_idx: int) -> Array:
	var t := tree(tree_id)
	if t.is_empty() or branch_idx < 0 or branch_idx >= t.branches.size():
		return []
	return t.branches[branch_idx].nodes.filter(func(id: String) -> bool: return node(id).tier == 1)

static func required_level(n: Dictionary) -> int:
	return TIER_LEVEL[clampi(int(n.tier), 0, TIER_LEVEL.size() - 1)]

# --- Puntos ---

## Puntos de árbol que da el nivel: 1 cada 3 niveles (nivel 3 → 1, nivel 20 → 6).
static func points_for_level(level: int) -> int:
	return maxi(0, level) / LEVELS_PER_POINT

static func bonus_points(c: Character) -> int:
	var t := 0
	for e: String in c.learned_skills:
		if e.begins_with(BONUS_PREFIX):
			t += int(e.substr(BONUS_PREFIX.length()).get_slice(":", 0))
	return t

## Fuente rara de puntos (hazañas, maestros, libros, finales). Con motivo, solo cuenta una vez.
## Los puntos por nivel NO se conceden aquí: points_total ya suma points_for_level(c.level).
static func grant_points(c: Character, n: int, reason: String = "") -> bool:
	if c == null or n <= 0 or reason.begins_with("nivel"):   # los del nivel ya cuentan solos (points_for_level)
		return false
	if reason != "":
		for e: String in c.learned_skills:
			var body := e.substr(BONUS_PREFIX.length())
			if e.begins_with(BONUS_PREFIX) and body.substr(body.find(":") + 1) == reason:
				return false
	c.learned_skills.append("%s%d:%s" % [BONUS_PREFIX, n, reason])
	return true

static func points_total(c: Character) -> int:
	return points_for_level(c.level) + bonus_points(c)

## Lo gastado: el primer básico aprendido de cada rama es gratis; los «base» de ensure_kit también.
static func points_spent(c: Character) -> int:
	var spent := 0
	var free_used := {}
	for id: String in c.learned_skills:
		if id.begins_with("@"):
			continue
		var n := node(id)
		if n.is_empty() or n.tree == TREE_BOSS:
			continue
		var key := "%s/%d" % [n.tree, n.branch]
		if n.tier == 1 and (not free_used.has(key) or n.get("base", false)):
			free_used[key] = true
			continue
		spent += int(n.cost)
	return spent

static func points_free(c: Character) -> int:
	return points_total(c) - points_spent(c)

static func _learned_basic_in(c: Character, tree_id: String, branch: int) -> bool:
	for id: String in c.learned_skills:
		var n := node(id)
		if not n.is_empty() and n.tree == tree_id and n.branch == branch and n.tier == 1:
			return true
	return false

## Puntos que costaría aprender el nodo ahora (0 = básico gratis de su rama).
static func cost_for(c: Character, id: String) -> int:
	var n := node(id)
	if n.is_empty():
		return 0
	if n.tier == 1 and not _learned_basic_in(c, n.tree, n.branch):
		return 0
	return int(n.cost)

# --- Conocidos ---

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

static func known_ids(c: Character) -> Array:
	var out := []
	for id: String in c.learned_skills:
		if not id.begins_with("@"):
			var real: String = ALIASES.get(id, id)
			if not real in out:
				out.append(real)
	for id in granted(c):
		if not id in out:
			out.append(id)
	return out

static func knows(c: Character, id: String) -> bool:
	return ALIASES.get(id, id) in known_ids(c)

static func can_learn(c: Character, id: String) -> bool:
	var n := node(id)
	if n.is_empty() or n.id != id or knows(c, id):
		return false
	if not n.tree in trees_for(c):
		return false
	if c.level < required_level(n):
		return false
	for r in n.req:
		if not knows(c, r):
			return false
	if not n.req_any.is_empty() and not n.req_any.any(func(r: String) -> bool: return knows(c, r)):
		return false
	return points_free(c) >= cost_for(c, id)

static func learn(c: Character, id: String) -> bool:
	if not can_learn(c, id):
		return false
	c.learned_skills.append(id)
	return true

## Kit mínimo: pasa ids antiguos a los actuales y, en cada árbol sin ningún básico aprendido, aprende sus
## nodos «base» (o el primer básico). Gratis. Los enemigos genéricos solo reciben los de su tipo.
static func ensure_kit(c: Character) -> void:
	for i in c.learned_skills.size():
		if ALIASES.has(c.learned_skills[i]):
			c.learned_skills[i] = ALIASES[c.learned_skills[i]]
	var trees: Array = [fighter_tree(c.fighter_type)] if c.has_meta("enemy_type") else Array(trees_for(c))
	for tid: String in trees:
		var has_basic := false
		for b in 3:
			has_basic = has_basic or _learned_basic_in(c, tid, b)
		if has_basic and not c.has_meta("enemy_type"):
			continue
		var bases := nodes_of_tree(tid).filter(func(n: Dictionary) -> bool: return n.get("base", false))
		if bases.is_empty():
			bases = [node(tree(tid).branches[0].nodes[0])]
		for n: Dictionary in bases:
			if not n.id in c.learned_skills:
				c.learned_skills.append(n.id)

static func _auto_score(c: Character, n: Dictionary) -> float:
	var score: float = AUTO_TIER_BONUS * n.tier
	if n.tree == fighter_tree(c.fighter_type):
		score += AUTO_FIGHTER_WEIGHT
	if n.kind == "act":
		score += AUTO_ACTIVE_WEIGHT
	return score + float(abs(hash(c.first_name + n.id)) % 100) / 1000.0   # desempate estable

## PNJ y séquito: un básico en cada rama de sus tres árboles y luego gastan los puntos (su tipo primero).
static func auto_learn(c: Character) -> void:
	ensure_kit(c)
	for tid: String in trees_for(c):
		for b in 3:
			if _learned_basic_in(c, tid, b):
				continue
			var opts := basic_nodes(tid, b)
			opts.sort_custom(func(x: String, y: String) -> bool: return _auto_score(c, node(x)) > _auto_score(c, node(y)))
			if not opts.is_empty():
				c.learned_skills.append(opts[0])
	while points_free(c) > 0:
		var best := ""
		var best_score := -INF
		for tid: String in trees_for(c):
			for n: Dictionary in nodes_of_tree(tid):
				if not can_learn(c, n.id):
					continue
				var score := _auto_score(c, n)
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
