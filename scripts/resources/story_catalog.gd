extends RefCounted
# Historias encadenadas: cadenas de 3–6 pasos con decisiones que se recuerdan (ver StoryData).
# Uso: const StoryCatalog = preload("res://scripts/resources/story_catalog.gd")
#
# Cadena: {id, title, cond: {...}, cast: [...], start, steps: {id: paso}, endings: {id: final}}
#   cond: min_rank / max_rank (Character.rank()), min_fame, min_honor, needs_liege, needs_castle (tienes castillo),
#         needs_war (tu reino en guerra), months [meses posibles], weight.
#   cast: papeles que se resuelven al empezar: lord (señor del lugar), near (castillo vecino),
#         far (castillo lejano de otro reino), enemy (señor enemigo, si hay guerra), npc / npc_f (nombres al azar).
# Paso: {title, text, delay [mín, máx] meses desde el anterior, travel? "near"|"far" (hay que estar allí),
#        deadline? meses para llegar, timeout? final si no llegas, speaker? "lord", options [...]}.
# Opción: formato de EventCatalog (label, requires, effects, chance/success/failure, fight) más
#   if / if_not (marcas de la historia), min_rank / max_rank. El flujo va en effects.story:
#   {set: [marcas], next: "paso"} o {set, end: "final"}. En combates, en win/lose; con azar, en success/failure.
# Final: {title, text, world: {lord_affinity, liege_affinity, kingdom_affinity, kill: "lord"|"enemy",
#        castle_garrison (factor), castle_food, castle_gold, castle_to_player: "near"|"castle",
#        unique: "nombre" o "" (al azar), unique_chance (0–100)}}.
# Textos: {player} {lord} {castle} {near} {far} {npc} {enemy} {kingdom} y marcas de género {a:él|ella}.

const R := Character.Role

const CHAINS := [
	# --- 1. Herejía ---
	{
		"id": "herejia", "title": "Los Pobres de Cristo",
		"cond": {"min_rank": 1, "weight": 1.0},
		"cast": ["lord", "npc"],
		"start": "predica",
		"steps": {
			"predica": {"title": "Un predicador descalzo", "delay": [0, 0],
				"text": "En la plaza de {castle}, {npc} predica que la Iglesia ha olvidado a los pobres. La gente lo escucha en silencio.",
				"options": [
					{"label": "Escucharlo", "effects": {"story": {"set": ["escuchado"], "next": "seguidores"}}, "result": "Sus palabras se te quedan dentro."},
					{"label": "Denunciarlo a {lord}", "effects": {"story": {"set": ["denunciado"], "next": "seguidores"}}, "result": "{lord} toma nota con gesto grave."},
					{"label": "No es asunto tuyo", "effects": {"story": {"end": "olvido"}}, "result": "Sigues tu camino."},
				]},
			"seguidores": {"title": "La herejía crece", "delay": [2, 3], "speaker": "lord",
				"text": "Cientos siguen ya a {npc}. El obispo exige acabar con la herejía, y {lord} te lo encarga a ti.",
				"options": [
					{"label": "Prenderlo (duelo con su guardián)", "requires": {"healthy": true}, "effects": {}, "result": "Sales a buscarlo.",
						"fight": {"type": "duel", "foe": {"name": "Guardián de {npc}", "role": R.SOLDADO, "power": 0, "personality": "PIADOSO"},
							"win": {"effects": {"story": {"end": "hoguera"}}, "result": "Llevas a {npc} encadenado ante el obispo."},
							"lose": {"effects": {"honor": -2, "story": {"end": "reforma"}}, "result": "Caes, y el pueblo protege a su predicador."}}},
					{"label": "Mediar entre ambos", "if": "escuchado", "chance": 0.5, "chance_stat": "charisma",
						"success": {"effects": {"fame": 5, "story": {"end": "reforma"}}, "result": "Logras que el obispo lo escuche."},
						"failure": {"effects": {"honor": -3, "story": {"end": "hoguera"}}, "result": "Nadie cede: el obispo manda prenderlo."}},
					{"label": "Entregarlo tú (ya lo denunciaste)", "if": "denunciado", "effects": {"gold": 40, "story": {"end": "hoguera"}}, "result": "Señalas su escondite."},
					{"label": "Negarte", "effects": {"story": {"end": "negativa"}}, "result": "{lord} no lo olvida."},
				]},
		},
		"endings": {
			"olvido": {"title": "Una voz más", "text": "El predicador se marchó a otra comarca.", "world": {}},
			"hoguera": {"title": "La hoguera", "text": "{npc} ardió en la plaza. El obispo te bendice; el pueblo, no.", "world": {"lord_affinity": 15}},
			"reforma": {"title": "La reforma", "text": "La Iglesia abre sus graneros a los pobres. Tu nombre corre de boca en boca.", "world": {"lord_affinity": -10, "castle_food": 40}},
			"negativa": {"title": "Las manos limpias", "text": "Otros hicieron el trabajo. {lord} te mira con desconfianza.", "world": {"lord_affinity": -15}},
		},
	},
	# --- 2. Pretendiente al trono ---
	{
		"id": "pretendiente", "title": "El hijo perdido del rey",
		"cond": {"min_rank": 2, "needs_liege": true, "weight": 0.8},
		"cast": ["lord", "far", "npc"],
		"start": "llega",
		"steps": {
			"llega": {"title": "Un joven con anillo real", "delay": [0, 0],
				"text": "{npc} dice ser el hijo perdido del viejo rey y muestra un anillo con el sello real. Busca apoyos.",
				"options": [
					{"label": "Apoyarlo en secreto", "effects": {"story": {"set": ["apoyo"], "next": "aliados"}}, "result": "Le das tu palabra."},
					{"label": "Desenmascararlo", "effects": {"story": {"set": ["contra"], "next": "campeon"}}, "result": "Juras demostrar que miente."},
					{"label": "Mantenerte al margen", "effects": {"story": {"end": "margen"}}, "result": "Los grandes juegan sin ti."},
				]},
			"aliados": {"title": "Reunir aliados", "delay": [1, 2], "travel": "far", "deadline": 6, "timeout": "abandonado",
				"text": "En {far} te esperan nobles descontentos. Hacen falta oro y valor para sumarlos a la causa.",
				"options": [
					{"label": "Comprar su apoyo (100)", "requires": {"gold": 100}, "effects": {"gold": -100, "story": {"set": ["aliados"], "next": "choque"}}, "result": "Las bolsas cambian de manos."},
					{"label": "Convencerlos", "chance": 0.45, "chance_stat": "charisma",
						"success": {"effects": {"story": {"set": ["aliados"], "next": "choque"}}, "result": "Brindan por el nuevo rey."},
						"failure": {"effects": {"story": {"next": "choque"}}, "result": "Te escuchan, pero no se mueven."}},
					{"label": "Abandonar la causa", "effects": {"honor": -4, "story": {"end": "abandonado"}}, "result": "Vuelves sobre tus pasos."},
				]},
			"choque": {"title": "Las tropas del rey", "delay": [1, 2],
				"text": "El rey envía soldados a prender al pretendiente. Hay que plantarles cara o huir.",
				"options": [
					{"label": "Combatir (escaramuza)", "requires": {"garrison": 20}, "effects": {}, "result": "Formas a tus hombres.",
						"fight": {"type": "battle", "no_rival": true, "enemy_name": "Las tropas del rey", "enemy_ratio": 1.0, "garrison_share": 0.25,
							"foe": {"name": "Capitán de la guardia real", "role": R.CABALLERO, "power": 1},
							"win": {"effects": {"fame": 10, "story": {"end": "corona"}}, "result": "La guardia real huye."},
							"lose": {"effects": {"honor": -5, "story": {"end": "derrota_pretendiente"}}, "result": "El pretendiente cae preso."}}},
					{"label": "Que luchen tus aliados", "if": "aliados", "chance": 0.55, "chance_stat": "strategy",
						"success": {"effects": {"story": {"end": "corona"}}, "result": "Tus aliados vencen por ti."},
						"failure": {"effects": {"story": {"end": "derrota_pretendiente"}}, "result": "Tus aliados se dispersan."}},
					{"label": "Huir", "effects": {"honor": -6, "story": {"end": "abandonado"}}, "result": "Huyes de noche."},
				]},
			"campeon": {"title": "El campeón del impostor", "delay": [1, 2],
				"text": "Acusado ante la corte, {npc} pide un juicio por combate. Su campeón te espera.",
				"options": [
					{"label": "Batirte", "requires": {"healthy": true}, "effects": {}, "result": "Que Dios decida.",
						"fight": {"type": "duel", "foe": {"name": "Campeón de {npc}", "role": R.CABALLERO, "power": 1, "personality": "ARROGANTE"},
							"win": {"effects": {"fame": 6, "story": {"end": "impostor"}}, "result": "El campeón cae: la mentira queda al descubierto."},
							"lose": {"effects": {"honor": -4, "story": {"end": "duda"}}, "result": "Pierdes, y la corte duda."}}},
					{"label": "Buscar pruebas", "chance": 0.5, "chance_stat": "strategy",
						"success": {"effects": {"story": {"end": "impostor"}}, "result": "Encuentras al orfebre que forjó el anillo."},
						"failure": {"effects": {"story": {"end": "duda"}}, "result": "No hallas nada."}},
				]},
		},
		"endings": {
			"margen": {"title": "Lejos de la corona", "text": "El pretendiente desapareció tan rápido como llegó.", "world": {}},
			"abandonado": {"title": "Promesa rota", "text": "La causa se deshizo sin ti, y los conjurados recuerdan tu deserción.", "world": {"liege_affinity": -5}},
			"corona": {"title": "Corona disputada", "text": "El pretendiente se hace fuerte y te recompensa con tierras. Tu señor te considera un traidor.",
				"world": {"liege_affinity": -40, "castle_to_player": "far", "unique_chance": 25}},
			"derrota_pretendiente": {"title": "Cabeza en una pica", "text": "El pretendiente fue ejecutado. Tu papel no pasó inadvertido.", "world": {"liege_affinity": -25}},
			"impostor": {"title": "El impostor", "text": "{npc} confesó: era hijo de un mozo de cuadra. La corte te aclama.", "world": {"liege_affinity": 20}},
			"duda": {"title": "La sombra de la duda", "text": "Nunca se supo la verdad. {npc} huyó al extranjero.", "world": {}},
		},
	},
	# --- 3. La peste ---
	{
		"id": "peste", "title": "La peste negra",
		"cond": {"weight": 0.9},
		"cast": ["lord", "castle"],
		"start": "llegada",
		"steps": {
			"llegada": {"title": "Fiebres en {castle}", "delay": [0, 0],
				"text": "Unos marineros traen fiebres y bubones a {castle}. Los primeros muertos aparecen en las calles.",
				"options": [
					{"label": "Cerrar las puertas", "effects": {"story": {"set": ["cuarentena"], "next": "estragos"}}, "result": "Nadie entra ni sale."},
					{"label": "Cuidar a los enfermos", "effects": {"story": {"set": ["cuidar"], "next": "estragos"}}, "result": "Te remangas."},
					{"label": "Rezar y esperar", "effects": {"story": {"next": "estragos"}}, "result": "Las campanas no paran de doblar."},
				]},
			"estragos": {"title": "Los estragos", "delay": [1, 2],
				"text": "La peste se ceba con {castle}. Faltan brazos, pan y valor.",
				"options": [
					{"label": "Mantener la cuarentena", "if": "cuarentena", "requires": {"castle_gold": 30}, "effects": {"castle_gold": -30, "story": {"end": "contenida"}}, "result": "Pagas a los guardias para que aguanten."},
					{"label": "Seguir cuidándolos", "if": "cuidar", "chance": 0.6, "chance_stat": "defense",
						"success": {"effects": {"honor": 6, "story": {"end": "contenida"}}, "result": "Sobrevives, y muchos gracias a ti."},
						"failure": {"effects": {"health": -40, "honor": 6, "story": {"end": "estragos"}}, "result": "Caes enfermo; te salvas de milagro."}},
					{"label": "Huir del castillo", "effects": {"honor": -5, "story": {"end": "estragos"}}, "result": "Te alejas mientras arden los muertos."},
					{"label": "Resistir", "effects": {"story": {"end": "estragos"}}, "result": "Esperas a que pase."},
				]},
		},
		"endings": {
			"contenida": {"title": "La peste contenida", "text": "{castle} perdió a muchos, pero menos que sus vecinos.", "world": {"castle_garrison": 0.9, "lord_affinity": 10}},
			"estragos": {"title": "Año de muerte", "text": "Un tercio de {castle} yace en fosas comunes.", "world": {"castle_garrison": 0.7, "castle_food": -40}},
		},
	},
	# --- 4. Hijo bastardo ---
	{
		"id": "bastardo", "title": "Sangre de tu sangre",
		"cond": {"min_rank": 1, "weight": 0.7},
		"cast": ["npc"],
		"start": "llega",
		"steps": {
			"llega": {"title": "Alguien en tu puerta", "delay": [0, 0],
				"text": "Un muchacho, {npc}, llega con una carta de una antigua amante: dice que eres su padre o madre. Tiene tus ojos.",
				"options": [
					{"label": "Reconocerlo", "effects": {"honor": 2, "story": {"set": ["reconocido"], "next": "prueba"}}, "result": "Lo abrazas ante todos."},
					{"label": "Pagarle para que se vaya (40)", "requires": {"gold": 40}, "effects": {"gold": -40, "story": {"end": "pagado"}}, "result": "Toma la bolsa sin mirarte."},
					{"label": "Negarlo", "effects": {"story": {"set": ["negado"], "next": "prueba"}}, "result": "Lo echas a la calle."},
				]},
			"prueba": {"title": "{npc} vuelve", "delay": [2, 3],
				"text": "{npc} ha crecido entre soldados. Ahora te reta, en público, a demostrar quién es quién.",
				"options": [
					{"label": "Aceptar un duelo de práctica", "requires": {"healthy": true}, "effects": {}, "result": "Los dos tomáis espadas romas.",
						"fight": {"type": "duel", "foe": {"name": "{npc}", "role": R.SOLDADO, "power": 0, "personality": "VALIENTE"},
							"win": {"effects": {"fame": 4, "story": {"end": "digno"}}, "result": "Le tiendes la mano: lucha bien."},
							"lose": {"effects": {"fame": 2, "story": {"end": "digno"}}, "result": "Te vence. Sonríes sin querer."}}},
					{"label": "Darle un puesto en tu guardia", "if": "reconocido", "effects": {"story": {"end": "digno"}}, "result": "Le das un escudo con tus colores."},
					{"label": "Pedir perdón", "if": "negado", "chance": 0.5, "chance_stat": "charisma",
						"success": {"effects": {"honor": 3, "story": {"end": "digno"}}, "result": "Tras un largo silencio, asiente."},
						"failure": {"effects": {"story": {"end": "rencor"}}, "result": "Escupe a tus pies y se marcha."}},
					{"label": "Ignorarlo", "effects": {"honor": -3, "story": {"end": "rencor"}}, "result": "Sigue tus pasos con la mirada."},
				]},
		},
		"endings": {
			"pagado": {"title": "Silencio comprado", "text": "Nunca volviste a saber de {npc}.", "world": {}},
			"digno": {"title": "Un hijo digno", "text": "{npc} sirve con tu nombre. Dicen que llegará lejos.", "world": {}},
			"rencor": {"title": "Un rencor de sangre", "text": "{npc} se fue jurando que algún día se cobrará la deuda.", "world": {}},
		},
	},
	# --- 5. Reliquia robada ---
	{
		"id": "reliquia", "title": "La reliquia robada",
		"cond": {"min_rank": 1, "weight": 1.0},
		"cast": ["lord", "near", "npc"],
		"start": "robo",
		"steps": {
			"robo": {"title": "El relicario vacío", "delay": [0, 0], "speaker": "lord",
				"text": "Han robado el relicario de la capilla de {castle}. Un mozo vio al ladrón huir hacia {near}.",
				"options": [
					{"label": "Seguir su rastro", "effects": {"story": {"next": "persecucion"}}, "result": "Ensillas y partes."},
					{"label": "Que lo busquen otros", "effects": {"story": {"end": "perdida"}}, "result": "La capilla se queda sin su santo."},
				]},
			"persecucion": {"title": "El ladrón en {near}", "delay": [1, 1], "travel": "near", "deadline": 4, "timeout": "perdida",
				"text": "En una taberna de {near} das con {npc}, que guarda un bulto envuelto en tela.",
				"options": [
					{"label": "Recuperarla por la fuerza", "requires": {"healthy": true}, "effects": {}, "result": "Desenvainas.",
						"fight": {"type": "duel", "foe": {"name": "{npc}", "role": R.SOLDADO, "power": 0, "personality": "ASTUTO"},
							"win": {"effects": {"story": {"set": ["recuperada"], "next": "destino"}}, "result": "El ladrón suelta el relicario."},
							"lose": {"effects": {"story": {"end": "perdida"}}, "result": "El ladrón escapa con su botín."}}},
					{"label": "Comprársela (60)", "requires": {"gold": 60}, "effects": {"gold": -60, "story": {"set": ["recuperada"], "next": "destino"}}, "result": "Regateas y pagas."},
					{"label": "Dejarlo marchar", "effects": {"story": {"end": "perdida"}}, "result": "El ladrón se pierde entre la gente."},
				]},
			"destino": {"title": "El relicario en tus manos", "delay": [1, 1],
				"text": "Tienes el relicario. Un mercader te ofrece una fortuna por él; los monjes rezan por su vuelta.",
				"options": [
					{"label": "Devolverlo a la capilla", "effects": {"honor": 6, "fame": 4, "story": {"end": "devuelta"}}, "result": "Las campanas repican."},
					{"label": "Venderlo (150)", "effects": {"gold": 150, "honor": -8, "story": {"end": "vendida"}}, "result": "El mercader sonríe."},
					{"label": "Quedártelo", "effects": {"honor": -4, "story": {"end": "guardada"}}, "result": "Lo escondes entre tus cosas."},
				]},
		},
		"endings": {
			"perdida": {"title": "El santo perdido", "text": "La capilla de {castle} nunca recuperó su reliquia.", "world": {"lord_affinity": -5}},
			"devuelta": {"title": "La reliquia vuelve", "text": "Los monjes de {castle} te dedican una misa cada año.", "world": {"lord_affinity": 15}},
			"vendida": {"title": "Oro sagrado", "text": "La reliquia acabó en un palacio lejano. {lord} sospecha de ti.", "world": {"lord_affinity": -10}},
			"guardada": {"title": "El relicario es tuyo", "text": "Dicen que cura a quien lo lleva.", "world": {"unique": "Relicario de Aquisgrán", "unique_chance": 100, "lord_affinity": -10}},
		},
	},
	# --- 6. Revuelta campesina (como señor) ---
	{
		"id": "revuelta_senor", "title": "La revuelta de los descalzos",
		"cond": {"min_rank": 3, "needs_castle": true, "weight": 1.0},
		"cast": ["castle", "npc"],
		"start": "agravios",
		"steps": {
			"agravios": {"title": "Los agravios", "delay": [0, 0],
				"text": "Los campesinos de {castle}, guiados por {npc}, se niegan a pagar el diezmo. Piden pan y justicia.",
				"options": [
					{"label": "Escuchar sus quejas", "effects": {"story": {"set": ["escuchados"], "next": "revuelta"}}, "result": "Recibes a {npc} en tu salón."},
					{"label": "Mandar a la guardia", "effects": {"story": {"set": ["mano_dura"], "next": "revuelta"}}, "result": "La guardia sale a las aldeas."},
				]},
			"revuelta": {"title": "Las horcas en alto", "delay": [1, 2],
				"text": "Arden graneros. {npc} marcha contra {castle} con centenares de campesinos armados con horcas.",
				"options": [
					{"label": "Aplastarlos (escaramuza)", "requires": {"garrison": 20}, "effects": {}, "result": "Tus jinetes cargan.",
						"fight": {"type": "battle", "no_rival": true, "enemy_name": "Los descalzos", "enemy_ratio": 1.2, "garrison_share": 0.3,
							"foe": {"name": "{npc}", "role": R.CAMPESINO, "power": 0},
							"win": {"effects": {"honor": -3, "story": {"end": "aplastada"}}, "result": "La revuelta acaba en sangre."},
							"lose": {"effects": {"honor": -5, "story": {"end": "triunfo_pueblo"}}, "result": "Los campesinos toman los graneros."}}},
					{"label": "Bajar los impuestos", "if": "escuchados", "effects": {"castle_gold": -40, "story": {"end": "pacto"}}, "result": "{npc} acepta tu palabra."},
					{"label": "Negociar", "if_not": "escuchados", "chance": 0.35, "chance_stat": "charisma",
						"success": {"effects": {"castle_gold": -40, "story": {"end": "pacto"}}, "result": "A regañadientes, se retiran."},
						"failure": {"effects": {"story": {"end": "triunfo_pueblo"}}, "result": "No se fían de quien envió a la guardia."}},
				]},
		},
		"endings": {
			"aplastada": {"title": "Paz de cementerio", "text": "Los campos de {castle} callan, pero nadie trabaja con ganas.", "world": {"castle_food": -40, "castle_garrison": 0.95}},
			"pacto": {"title": "El pacto de la era", "text": "Pan para todos y rentas más justas. {castle} prospera.", "world": {"castle_food": 60}},
			"triunfo_pueblo": {"title": "Los descalzos vencen", "text": "Saquearon los graneros y el tesoro de {castle}.", "world": {"castle_food": -80, "castle_gold": -80}},
		},
	},
	# --- 7. Revuelta campesina (desde abajo) ---
	{
		"id": "revuelta_pueblo", "title": "Pan y justicia",
		"cond": {"max_rank": 1, "weight": 1.2},
		"cast": ["lord", "npc"],
		"start": "reunion",
		"steps": {
			"reunion": {"title": "Reunión en el granero", "delay": [0, 0],
				"text": "{npc} reúne a los vecinos: {lord} ha doblado los impuestos en pleno invierno. Te piden que te unas.",
				"options": [
					{"label": "Unirte", "effects": {"story": {"set": ["rebelde"], "next": "levantamiento"}}, "result": "Juras con ellos."},
					{"label": "Avisar a {lord}", "effects": {"story": {"set": ["chivato"], "next": "levantamiento"}}, "result": "Corres al castillo."},
					{"label": "No meterte", "effects": {"story": {"end": "al_margen"}}, "result": "Cierras tu puerta."},
				]},
			"levantamiento": {"title": "El levantamiento", "delay": [1, 2],
				"text": "La noche señalada, las antorchas rodean el castillo. El sargento de {lord} sale al camino.",
				"options": [
					{"label": "Enfrentarte al sargento", "if": "rebelde", "requires": {"healthy": true}, "effects": {}, "result": "Le cortas el paso.",
						"fight": {"type": "duel", "foe": {"name": "Sargento de {lord}", "role": R.SOLDADO, "power": 0},
							"win": {"effects": {"fame": 6, "story": {"end": "jacquerie"}}, "result": "El sargento cae y el pueblo entra."},
							"lose": {"effects": {"health": -20, "story": {"end": "sofocada"}}, "result": "Te reducen a golpes."}}},
					{"label": "Guiar a los vecinos", "if": "rebelde", "chance": 0.4, "chance_stat": "leadership",
						"success": {"effects": {"fame": 5, "story": {"end": "jacquerie"}}, "result": "Tomáis el granero sin sangre."},
						"failure": {"effects": {"story": {"end": "sofocada"}}, "result": "La guardia os dispersa."}},
					{"label": "Cobrar tu recompensa", "if": "chivato", "effects": {"gold": 40, "honor": -4, "story": {"end": "delator"}}, "result": "{lord} te paga en la oscuridad."},
					{"label": "Huir", "effects": {"story": {"end": "sofocada"}}, "result": "Corres al bosque."},
				]},
		},
		"endings": {
			"al_margen": {"title": "Puertas cerradas", "text": "La revuelta fracasó sin ti.", "world": {}},
			"jacquerie": {"title": "La jacquerie", "text": "{lord} rebajó los impuestos para salvar el cuello. Los vecinos cantan tu nombre.", "world": {"lord_affinity": -20, "castle_food": 30}},
			"sofocada": {"title": "Horcas en el camino", "text": "Colgaron a los cabecillas. {npc} entre ellos.", "world": {"lord_affinity": -5}},
			"delator": {"title": "Treinta monedas", "text": "{lord} te debe un favor. Los vecinos ya no te saludan.", "world": {"lord_affinity": 15}},
		},
	},
	# --- 8. Cruzada / peregrinación armada ---
	{
		"id": "cruzada", "title": "La peregrinación armada",
		"cond": {"min_rank": 2, "weight": 0.8},
		"cast": ["lord", "far"],
		"start": "llamada",
		"steps": {
			"llamada": {"title": "La llamada", "delay": [0, 0],
				"text": "Un legado llama a los caballeros a proteger el santuario de {far}, asediado por saqueadores paganos.",
				"options": [
					{"label": "Tomar la cruz", "effects": {"honor": 3, "story": {"next": "camino"}}, "result": "Cosen la cruz a tu capa."},
					{"label": "Enviar oro (60)", "requires": {"gold": 60}, "effects": {"gold": -60, "honor": 2, "story": {"end": "donante"}}, "result": "Tu bolsa irá en tu lugar."},
					{"label": "Rehusar", "effects": {"honor": -2, "story": {"end": "donante"}}, "result": "El legado frunce el ceño."},
				]},
			"camino": {"title": "Ante el santuario", "delay": [1, 2], "travel": "far", "deadline": 6, "timeout": "desertor",
				"text": "Llegas a {far}. Los paganos rodean el santuario; los peregrinos esperan una señal.",
				"options": [
					{"label": "Cargar contra ellos (escaramuza)", "requires": {"garrison": 15}, "effects": {}, "result": "¡Por el santuario!",
						"fight": {"type": "battle", "no_rival": true, "enemy_name": "Los saqueadores paganos", "enemy_ratio": 1.0, "garrison_share": 0.25,
							"foe": {"name": "Caudillo pagano", "role": R.CABALLERO, "power": 1},
							"win": {"effects": {"fame": 12, "honor": 6, "story": {"end": "gloria"}}, "result": "El santuario se salva."},
							"lose": {"effects": {"health": -30, "story": {"end": "martirio"}}, "result": "Caéis entre los peregrinos."}}},
					{"label": "Retar a su caudillo", "requires": {"healthy": true}, "effects": {}, "result": "Avanzas solo hacia sus filas.",
						"fight": {"type": "duel", "foe": {"name": "Caudillo pagano", "role": R.CABALLERO, "power": 1, "personality": "CRUEL"},
							"win": {"effects": {"fame": 15, "story": {"end": "gloria"}}, "result": "Sin su caudillo, los paganos huyen."},
							"lose": {"effects": {"honor": -2, "story": {"end": "martirio"}}, "result": "El caudillo te perdona la vida por burla."}}},
					{"label": "Volver a casa", "effects": {"honor": -6, "story": {"end": "desertor"}}, "result": "Das media vuelta."},
				]},
		},
		"endings": {
			"donante": {"title": "Desde lejos", "text": "Otros partieron a {far}. Tú seguiste con tus asuntos.", "world": {}},
			"gloria": {"title": "Defensor del santuario", "text": "Los juglares cantan tu hazaña en {far}. Los monjes te regalan una reliquia.", "world": {"lord_affinity": 10, "unique_chance": 40}},
			"martirio": {"title": "Sangre en el camino", "text": "El santuario cayó. Volviste con cicatrices y sin gloria.", "world": {}},
			"desertor": {"title": "La cruz abandonada", "text": "Se dice que tomaste la cruz y no llegaste.", "world": {"lord_affinity": -10}},
		},
	},
	# --- 9. Caballero caído en desgracia ---
	{
		"id": "caido", "title": "El caballero caído",
		"cond": {"min_rank": 1, "weight": 1.0},
		"cast": ["lord", "npc"],
		"start": "suplica",
		"steps": {
			"suplica": {"title": "Un caballero sin espuelas", "delay": [0, 0],
				"text": "Sir {npc} perdió sus espuelas acusado de cobardía. Jura que lo traicionó su capitán y te pide ayuda.",
				"options": [
					{"label": "Investigar", "effects": {"story": {"set": ["investiga"], "next": "verdad"}}, "result": "Haces preguntas en las tabernas."},
					{"label": "Creerle sin más", "effects": {"story": {"set": ["fe"], "next": "verdad"}}, "result": "Le das tu palabra."},
					{"label": "Rechazarlo", "effects": {"story": {"end": "olvidado"}}, "result": "Se aleja cojeando."},
				]},
			"verdad": {"title": "La verdad", "delay": [1, 2],
				"text": "El capitán acusador vive en {castle} y no quiere oír hablar del asunto.",
				"options": [
					{"label": "Buscar testigos", "if": "investiga", "chance": 0.55, "chance_stat": "strategy",
						"success": {"effects": {"story": {"end": "rehabilitado"}}, "result": "Un escudero confiesa: el capitán huyó primero."},
						"failure": {"effects": {"story": {"set": ["sin_pruebas"], "next": "juicio"}}, "result": "Nadie se atreve a hablar."}},
					{"label": "Retar al capitán", "requires": {"healthy": true}, "effects": {}, "result": "Le arrojas el guante.",
						"fight": {"type": "duel", "foe": {"name": "El capitán acusador", "role": R.CABALLERO, "power": 1, "personality": "ARROGANTE"},
							"win": {"effects": {"fame": 6, "story": {"end": "rehabilitado"}}, "result": "Vencido, el capitán confiesa."},
							"lose": {"effects": {"honor": -3, "story": {"end": "olvidado"}}, "result": "Pierdes, y con ello la causa."}}},
					{"label": "Dejarlo estar", "effects": {"honor": -2, "story": {"end": "olvidado"}}, "result": "No merece la pena."},
				]},
			"juicio": {"title": "Ante {lord}", "delay": [1, 1], "speaker": "lord",
				"text": "Sin pruebas, solo queda tu palabra ante {lord}.",
				"options": [
					{"label": "Responder por él", "chance": 0.5, "chance_stat": "charisma",
						"success": {"effects": {"story": {"end": "rehabilitado"}}, "result": "{lord} devuelve sus espuelas a Sir {npc}."},
						"failure": {"effects": {"honor": -3, "story": {"end": "olvidado"}}, "result": "{lord} no te cree."}},
					{"label": "Callar", "effects": {"story": {"end": "olvidado"}}, "result": "Sir {npc} baja la cabeza."},
				]},
		},
		"endings": {
			"olvidado": {"title": "Sin espuelas", "text": "Sir {npc} acabó de mercenario en tierras lejanas.", "world": {}},
			"rehabilitado": {"title": "El honor recobrado", "text": "Sir {npc} recupera sus espuelas y jura servirte cuando lo llames.", "world": {"lord_affinity": 5}},
		},
	},
	# --- 10. Torneo amañado ---
	{
		"id": "torneo_amanado", "title": "El torneo amañado",
		"cond": {"min_rank": 1, "max_rank": 4, "months": [4, 5, 6, 7, 8], "weight": 0.9},
		"cast": ["lord", "npc"],
		"start": "oferta",
		"steps": {
			"oferta": {"title": "Una bolsa bajo la mesa", "delay": [0, 0],
				"text": "{npc}, un apostador, te ofrece 120 de oro si pierdes la final del torneo de {castle}.",
				"options": [
					{"label": "Aceptar el trato", "effects": {"gold": 40, "story": {"set": ["trato"], "next": "final"}}, "result": "Te adelanta 40 de oro."},
					{"label": "Rechazarlo", "effects": {"story": {"next": "final"}}, "result": "Se encoge de hombros."},
					{"label": "Denunciarlo a {lord}", "effects": {"honor": 4, "story": {"set": ["denuncia"], "next": "final"}}, "result": "{lord} manda vigilarlo."},
				]},
			"final": {"title": "La final", "delay": [1, 1],
				"text": "Llega la final. {npc} te observa desde la grada.",
				"options": [
					{"label": "Dejarte ganar", "if": "trato", "effects": {"gold": 80, "honor": -8, "story": {"end": "vendido"}}, "result": "Caes del caballo con poca gracia."},
					{"label": "Luchar de verdad", "requires": {"healthy": true}, "effects": {}, "result": "Bajas la visera.",
						"fight": {"type": "duel", "foe": {"name": "Campeón del torneo", "role": R.CABALLERO, "power": 1, "personality": "ARROGANTE"},
							"win": {"effects": {"fame": 8, "gold": 50, "story": {"end": "campeon"}}, "result": "¡Campeón de {castle}!"},
							"lose": {"effects": {"fame": 2, "story": {"end": "limpio"}}, "result": "Pierdes, pero con limpieza."}}},
					{"label": "Retirarte", "effects": {"honor": -2, "story": {"end": "limpio"}}, "result": "Alegas una herida."},
				]},
		},
		"endings": {
			"vendido": {"title": "Oro y vergüenza", "text": "Ganaste una bolsa y perdiste el respeto de quienes lo vieron.", "world": {}},
			"campeon": {"title": "Campeón limpio", "text": "{npc} perdió una fortuna apostando contra ti y no lo olvida.", "world": {"lord_affinity": 5}},
			"limpio": {"title": "Juego limpio", "text": "El torneo terminó sin escándalo.", "world": {}},
		},
	},
	# --- 11. Boda envenenada ---
	{
		"id": "boda", "title": "La boda envenenada",
		"cond": {"min_rank": 2, "weight": 0.8},
		"cast": ["lord", "npc"],
		"start": "invitacion",
		"steps": {
			"invitacion": {"title": "Una boda en {castle}", "delay": [0, 0], "speaker": "lord",
				"text": "{lord} casa a su heredero y te invita. En los pasillos, oyes a {npc} hablar de «acabar con la casa».",
				"options": [
					{"label": "Vigilar a {npc}", "chance": 0.5, "chance_stat": "strategy",
						"success": {"effects": {"story": {"set": ["pruebas"], "next": "banquete"}}, "result": "Lo ves comprar beleño a un boticario."},
						"failure": {"effects": {"story": {"next": "banquete"}}, "result": "Se te escabulle."}},
					{"label": "Contárselo a {lord}", "effects": {"story": {"set": ["avisado"], "next": "banquete"}}, "result": "{lord} se ríe: «Son celos de corte»."},
					{"label": "Disfrutar de la fiesta", "effects": {"story": {"next": "banquete"}}, "result": "El vino es excelente."},
				]},
			"banquete": {"title": "El banquete", "delay": [1, 1],
				"text": "Sirven el vino del brindis. {npc} no deja de mirar la copa de {lord}.",
				"options": [
					{"label": "Desenmascararlo con pruebas", "if": "pruebas", "effects": {"fame": 8, "story": {"end": "salvado"}}, "result": "Muestras el beleño ante todos."},
					{"label": "Tirar la copa de {lord}", "effects": {}, "result": "La copa rueda por el suelo. {npc} desenvaina.",
						"requires": {"healthy": true},
						"fight": {"type": "duel", "foe": {"name": "{npc}", "role": R.CABALLERO, "power": 0, "personality": "ASTUTO"},
							"win": {"effects": {"fame": 6, "story": {"end": "salvado"}}, "result": "Reduces al envenenador."},
							"lose": {"effects": {"health": -20, "story": {"end": "envenenado"}}, "result": "En la confusión, {lord} bebe de otra copa."}}},
					{"label": "Callar", "effects": {"story": {"end": "envenenado"}}, "result": "Brindas en silencio."},
				]},
		},
		"endings": {
			"salvado": {"title": "La copa derramada", "text": "{lord} te debe la vida y lo proclama en su salón.", "world": {"lord_affinity": 30}},
			"envenenado": {"title": "Muerte en el banquete", "text": "{lord} murió al alba, entre convulsiones.", "world": {"kill": "lord"}},
		},
	},
	# --- 12. Mercader endeudado ---
	{
		"id": "mercader", "title": "El mercader endeudado",
		"cond": {"weight": 1.0},
		"cast": ["near", "npc"],
		"start": "prestamo",
		"steps": {
			"prestamo": {"title": "Un préstamo", "delay": [0, 0],
				"text": "{npc}, un mercader de paños, te ruega 80 de oro. Promete devolver 140 tras la feria.",
				"options": [
					{"label": "Prestárselo (80)", "requires": {"gold": 80}, "effects": {"gold": -80, "story": {"set": ["prestado"], "next": "feria"}}, "result": "Firma un pagaré."},
					{"label": "Negarte", "effects": {"story": {"end": "sin_trato"}}, "result": "Se marcha cabizbajo."},
				]},
			"feria": {"title": "Después de la feria", "delay": [2, 3],
				"text": "La feria terminó y {npc} no aparece. Dicen que se esconde en {near}.",
				"options": [
					{"label": "Esperar un poco más", "chance": 0.5,
						"success": {"effects": {"gold": 140, "story": {"end": "pagado"}}, "result": "Al fin llega, con tu dinero y una disculpa."},
						"failure": {"effects": {"story": {"next": "cobro"}}, "result": "No llega nada."}},
					{"label": "Ir a cobrar", "effects": {"story": {"next": "cobro"}}, "result": "Sales hacia {near}."},
					{"label": "Darlo por perdido", "effects": {"story": {"end": "perdido"}}, "result": "Rompes el pagaré."},
				]},
			"cobro": {"title": "Cobrar la deuda", "delay": [1, 1], "travel": "near", "deadline": 4, "timeout": "perdido",
				"text": "Encuentras a {npc} en {near}, rodeado de fardos y matones a sueldo.",
				"options": [
					{"label": "Cobrar por las malas", "requires": {"healthy": true}, "effects": {}, "result": "Apartas a los matones.",
						"fight": {"type": "duel", "foe": {"name": "Matón de {npc}", "role": R.SOLDADO, "power": 0, "personality": "CRUEL"},
							"win": {"effects": {"gold": 160, "story": {"end": "pagado"}}, "result": "{npc} paga hasta la última moneda."},
							"lose": {"effects": {"story": {"end": "perdido"}}, "result": "Te echan a la calle."}}},
					{"label": "Quedarte con su mercancía", "effects": {"gold": 100, "honor": -2, "story": {"end": "pagado"}}, "result": "Te llevas paños por valor de 100."},
					{"label": "Perdonar la deuda", "effects": {"honor": 5, "fame": 3, "story": {"end": "perdonado"}}, "result": "{npc} llora de gratitud."},
				]},
		},
		"endings": {
			"sin_trato": {"title": "Sin trato", "text": "{npc} buscó dinero en otra parte.", "world": {}},
			"pagado": {"title": "Deuda saldada", "text": "La deuda queda saldada.", "world": {}},
			"perdido": {"title": "Oro perdido", "text": "Nunca volviste a ver tu dinero.", "world": {}},
			"perdonado": {"title": "La deuda perdonada", "text": "{npc} cuenta tu generosidad en cada feria.", "world": {}},
		},
	},
	# --- 13. La bestia ---
	{
		"id": "bestia", "title": "La bestia de la comarca",
		"cond": {"months": [10, 11, 12, 1, 2, 3], "weight": 1.0},
		"cast": ["lord", "castle"],
		"start": "rumores",
		"steps": {
			"rumores": {"title": "Ovejas degolladas", "delay": [0, 0],
				"text": "Algo enorme mata el ganado alrededor de {castle}. Los pastores hablan de un lobo del tamaño de un caballo.",
				"options": [
					{"label": "Organizar una batida", "effects": {"story": {"set": ["batida"], "next": "caza"}}, "result": "Reúnes perros y monteros."},
					{"label": "Cazarla tú solo", "effects": {"story": {"next": "caza"}}, "result": "Afilas la lanza."},
					{"label": "Cosa de pastores", "effects": {"story": {"end": "plaga_lobo"}}, "result": "No le das importancia."},
				]},
			"caza": {"title": "La caza", "delay": [1, 2],
				"text": "En la niebla del bosque, unos ojos amarillos te observan.",
				"options": [
					{"label": "Enfrentarte a la bestia", "requires": {"healthy": true}, "effects": {}, "result": "La bestia salta.",
						"fight": {"type": "duel", "foe": {"name": "La Bestia de {castle}", "role": R.CABALLERO, "power": 1, "personality": "CRUEL"},
							"win": {"effects": {"fame": 10, "item": 2, "story": {"end": "bestia_muerta"}}, "result": "La bestia cae. Su piel cubrirá tu salón."},
							"lose": {"effects": {"health": -30, "story": {"end": "plaga_lobo"}}, "result": "Escapas malherido."}}},
					{"label": "Que la acorralen los perros", "if": "batida", "chance": 0.55, "chance_stat": "leadership",
						"success": {"effects": {"fame": 5, "story": {"end": "bestia_muerta"}}, "result": "La jauría la acorrala junto al río."},
						"failure": {"effects": {"story": {"end": "plaga_lobo"}}, "result": "La bestia destroza a los perros y huye."}},
					{"label": "Retirarte", "effects": {"honor": -2, "story": {"end": "plaga_lobo"}}, "result": "Vuelves sin trofeo."},
				]},
		},
		"endings": {
			"bestia_muerta": {"title": "La bestia muerta", "text": "Los pastores de {castle} te agasajan con su mejor queso.", "world": {"lord_affinity": 10, "castle_food": 30}},
			"plaga_lobo": {"title": "Inviernos de miedo", "text": "La bestia sigue en el bosque y el ganado mengua.", "world": {"castle_food": -30}},
		},
	},
]

static func chain(id: String) -> Dictionary:
	for c: Dictionary in CHAINS:
		if c.id == id:
			return c
	return {}
