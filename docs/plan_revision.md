# Royal Pain — Plan de la gran revisión (4 fases)

## Contexto
Tras jugar, el usuario detecta que:
- **Mercenarios:** todo lo relacionado sobra.
- **Duelo:** no es divertido. Quiere un combate de grupo por turnos estilo JRPG.
- **Batallas campales:** son fáciles y sin estrategia.
- **Vida social:** es pobre (intimidad, rivalidad, esclavos y prisioneros, señores, compañeros de facción, viajeros, historias con poco impacto).
- **Matrimonio:** falta poder tener varias esposas y concubinas.
- **Gestores:** faltan un gestor de personajes guardados y un gestor de grupo.
- **Errores:** registros largos descuadran la interfaz, desaparecen los personajes de reinos derrotados y la tropa elegida no se respeta.

Decisiones tomadas con el usuario:

| Tema | Decisión |
|---|---|
| Combate RPG | Híbrido FF + SMT: línea de turnos por velocidad y debilidades que suben o bajan el daño (no dan ni quitan turnos). **Vista frontal**: enemigos arriba con su retrato y tu grupo abajo con sus retratos. |
| Alcance del RPG | Todo lo que no es batalla campal: duelos 1v1, torneos, retos, eventos, encuentros, exploración, historias y escaramuzas. |
| Grupo | 4 activos + reserva, cambiables en combate gastando un turno. Gestor de grupo con todo el séquito. |
| Tipos de daño | Solo armas: Tajo, Estocada, Contundente, Proyectil. |
| Técnicas | Árbol amplio por tipo de luchador (3 ramas) + 3 ramas comunes; las habilidades, el equipo y las piezas únicas actuales se convierten en nodos o bonificaciones. |
| Estadísticas | Estadísticas de combate derivadas de los 5 atributos actuales, equilibradas con simulaciones de grupo. |
| Debilidades | Tabla arma × armadura. Las posturas se eliminan; las útiles pasan a ser técnicas activas o pasivas. |
| Campales | IA más lista, formaciones y flancos, y **sistema de oficiales** (cada pelotón tiene un jefe y sus oficiales, p. ej. del séquito). **Cada encuentro entre pelotones lanza un combate RPG** jefe+oficiales contra jefe+oficiales. Las tropas dan estadísticas extra y algunas técnicas piden tropa o moral mínimas. |
| Matrimonio | Esposas según rango (1 hasta Caballero, 2 Nobleza, 3 Duque o Regente) y concubinas aparte (sin alianza ni rango; sus hijos heredan si no hay otros), con celos según personalidad. |
| Mercenarios | Se eliminan. Las partidas guardadas pasan a No afiliado (un Condotiero con castillo pasa a Nobleza Baja). Perder el último castillo deja al jugador No afiliado. |
| Gestor de personajes | Ver, borrar, editar, duplicar, renombrar, importar y exportar. |
| Lealtad | Medidor de lealtad para todo lo que depende del jugador (séquito, cónyuges, siervos, vasallos, guarniciones). Sube y baja por causas claras, con avisos y remedio, y con traiciones en el mundo y en batalla. |
| Orden | Fase 1 arreglos y quitar mercenarios. Fase 2 social. Fase 3 gestor de grupo y combate RPG. Fase 4 campales. |

Cada fase se prueba, se sube a git y genera `.exe` antes de pasar a la siguiente. Se trabaja en modo ahorro: pocas pruebas, compactas y centradas en las reglas clave.

---

## Fase 1 — Arreglos y retirada de mercenarios

1. **Registros que descuadran la interfaz.**
   - Medir primero: ampliar `scratchpad/overflow_all.gd` para llenar los registros con 200 líneas en el duelo/RPG, el registro de la batalla (`scenes/battle/battle.gd`), las noticias del mapa y la crónica (`scripts/ui/chronicle_panel.gd`).
   - Arreglo: cada registro va dentro de un `ScrollContainer` con altura fija, autodesplazamiento al final y un tope de líneas (recortar las más antiguas).

2. **Personajes de reinos derrotados que desaparecen.**
   - Causa: `Relationship.kingdom` se queda con el índice del reino vencido. Como `in_area()` (`relations_data.gd:824`) y `courtiers()`/`commoners()` filtran por reino, nadie vuelve a verlos.
   - Arreglo: un nuevo `RelationsData.on_kingdom_fallen(old_k, victor_k)`, llamado cuando un reino pierde su último castillo, desde la conquista en `army_data.gd` (donde se asigna `castle.kingdom = army.kingdom`) y desde las rebeliones o sucesiones de `world_events.gd`. Qué pasa con cada uno:
     - **Cortesanos y pueblo:** un % pasa al reino vencedor ("reclutados", con noticia) y el resto queda **No afiliado errante** (`kingdom = -1`), material para los viajeros de la fase 2.
     - **Señor vencido:** capturado mediante `CaptureData` o, si huye, No afiliado.
   - Al conquistar un castillo suelto sin que caiga el reino, su gente pasa al vencedor.

3. **La tropa elegida no se respeta.** Investigar el orden de asignación en `battle_manager.gd`:
   - `assigned_family`, negociación (`change_allocation()` / `_confirm_council()` en `battle.gd`) y `_apply_allocation()`.
   - Posible causa: se vuelve a formar el ejército y `_assign_family` reasigna por maestría sin respetar la elección del jugador.

   Prueba: elegir tropa → confirmar → el pelotón del jugador tiene esa familia.

4. **Quitar mercenarios.**
   - **Qué sale:**
     - los roles `MERCENARIO`, `CAPITAN` y `CONDOTIERO` de Nueva Partida (`scenes/new_game/new_game.gd`);
     - contratos (`scripts/ui/contracts_panel.gd`, los tipos "contract" de `mission_catalog.gd`/`mission_data.gd`);
     - compañía, soldada mensual e infamia (`mission_data.gd`), y la línea de compañía en el mapa (`map.gd`, "Tu destino");
     - las acciones del castillo ("Ofrecer tus servicios"…) y las hazañas mercenarias (`achievement_catalog.gd`);
     - las rutas de ascenso (`role_progression.gd`, `victory_rules.gd`) y las entradas del glosario.
   - **Qué se queda:** los valores del enum, porque las partidas guardan números. Se marcan como antiguos y, al cargar, `SaveSystem` / `MissionData.load_state` los convierte en No afiliado (Condotiero con castillo → Nobleza Baja).
   - **Perder el último castillo:** `RoleProgression.landless_role()` / `army_data.gd` devuelven No afiliado.
   - **El trabajo a jornal** sigue sirviendo al No afiliado y al Campesino.

---

## Fase 2 — Vida social

Todo entra por la cola común `GameManager.queue_event()` con ritmo controlado (constantes con nombre) para no saturar: hoy ≈55% de meses con decisión, objetivo ≤ 60%. Los textos se reutilizan con `DialogueCatalog` (marcadores de género, personalidad, intimidad) y los efectos con `EventCatalog.apply_option`.

1. **Eventos por cercanía** (nuevo `scripts/resources/bond_event_catalog.gd` + lógica mensual en `relations_data.gd` o un pequeño autoload `BondData`):
   - Eventos según el nivel de intimidad (Conocido → Íntimo), la clase de relación (cónyuge, concubina, amante, amigo, cortesano, siervo, prisionero) y la personalidad: confidencias, pedir ayuda, regalos espontáneos, celos, disputas, celebraciones y momentos íntimos (Charla íntima ya existe).
   - Cada nivel desbloquea más eventos y más opciones en la conversación.

2. **Rivalidad con más eventos:** ampliar las iniciativas de rival de `relations_data.gd` con humillaciones públicas, sabotaje del cortejo, apuestas, duelos de honor programados, reconciliación y alianza contra un tercero. Más frecuencia según la etapa (Rival/Némesis).

3. **Esclavos y prisioneros** (`capture_data.gd`, `scripts/ui/prisoners_panel.gd`):
   - Nuevas acciones: interrogar (rumores/secretos), asignar trabajo (forja, campo, servicio → oro o mejoras), entrenarlos para el grupo y negociar el rescate con su familia.
   - Eventos propios: intento de fuga, lealtad que crece, petición de libertad, familia que reclama.

4. **Señores con presencia:** cartas y órdenes de tu señor y de señores vecinos (peticiones, convocatorias, quejas, felicitaciones por tus hechos), visitas a tu corte, banquetes, reacción a tus victorias o deshonras, con retrato. Reutilizar `AmbitionData` (los señores ya tienen ambiciones) para que sus planes se noten más.

5. **Eventos de facción** (sentirse ejército): camaradería entre miembros del mismo reino, brindis tras victorias, piques internos, petición de un compañero en apuros, honores del señor al grupo. Alimentados por los "lazos de batalla" que ya existen.

6. **Viajeros en el mapa:** algunos personajes, entre ellos los errantes de la fase 1 y los de `AmbitionData`, viajan entre castillos y se dibujan en el mapa con su cara (reutilizar `scenes/map/player_token.gd` y `FaceIcon`).
   - Si coinciden en tu castillo o tramo: encuentro con su retrato para conversar, reclutar, retar o comerciar.
   - Reutilizar `road_encounter_catalog.gd` y `TravelData`.

7. **Historias con más impacto** (`story_catalog.gd`, `story_data.gd`):
   - Los finales dejan efectos duraderos: títulos o rasgos para el jugador, modificadores de reino durante meses (peste, herejía), personajes que vuelven después y castillos que cambian de manos con noticia en el mapa.
   - Cada final deja una entrada destacada en la crónica y, si toca, desbloquea una hazaña.

8. **Varias esposas y concubinas:**
   - `spouse_name` pasa a ser una lista `spouses` + `concubines` en `RelationsData`, con migración desde el campo único.
   - El tope de esposas lo pone el rango. Las concubinas requieren romance e intimidad.
   - Celos y eventos entre ellas. Los hijos de concubinas son herederos de segunda línea en `DynastyData`.
   - Actualizar boda, viudez, sucesión y el panel de Familia (`level_up_panel.gd`).

9. **Lealtad y traiciones** (nuevo autoload `LoyaltyData` o integrado en `RelationsData`, guardado en `SaveSystem.MODULES`):
   - **Quién tiene lealtad (0–100):** séquito y grupo, cónyuges y concubinas, siervos, vasallos (señores y caballeros bajo tu mando) y la guarnición de cada castillo tuyo (un valor por castillo).
   - **Dónde se ve:** una barra en la ficha, en el gestor de grupo y en el castillo.
   - **Sube con:** paga a tiempo, victorias, regalos, intimidad, honor y reparto del botín.
   - **Baja con:**
     - impagos, derrotas y deshonra;
     - mal trato: esclavizar o ejecutar a los suyos;
     - favoritismo y celos (varias esposas);
     - una ambición propia que choca con la tuya (`AmbitionData`).
   - **Peso según personalidad:** los leales caen despacio, los ambiciosos rápido, los crueles toleran el mal trato y los honorables no toleran la deshonra.
   - **Avisos y remedio:** por debajo de umbrales (constantes con nombre) llegan quejas, eventos de descontento y rumores de tus confidentes. Puedes hablar, pagar, conceder o castigar para recuperarla.
   - **Traición en el mundo** con lealtad baja:
     - deserción con oro;
     - unirse a una conjura contra ti (con `AmbitionData`);
     - venderte al enemigo;
     - un vasallo o una guarnición que entrega o subleva un castillo;
     - envenenamiento (raro);
     - fuga de siervos y prisioneros.
   - **Traición en batalla:**
     - campal: un oficial o un pelotón con lealtad baja puede pasarse al enemigo a mitad de la batalla (reutilizar la lógica de cambio de bando de la traición del jugador en `battle_manager.gd`);
     - RPG: un miembro descontento del grupo puede abandonar el combate.
   - **Ritmo:** traiciones raras y siempre precedidas de avisos. Se prueba en una simulación de 20 años.

10. **Gestor de personajes** (nueva escena desde el menú principal, `scenes/character_manager/`):
   - Lista de los personajes guardados con retrato.
   - Ver la ficha, borrar (con confirmación), editar (abre `character_creation` con el personaje cargado), duplicar, renombrar, y exportar o importar como archivo JSON.
   - Reutilizar `CharacterLoader.save_character` / `get_saved_character_paths`, `DataCodec` y `DataPaths`.

---

## Fase 3 — Gestor de grupo y combate RPG

1. **Gestor de grupo** (`scripts/ui/party_panel.gd`, accesible desde el mapa, el castillo y antes de cada combate):
   - Todo el séquito con retrato, nivel, PV/PT, técnicas, equipo, ocupación, y si va en los **4 activos** o en reserva.
   - Reordenar y cambiar con ratón, teclado o mando.
   - Reutiliza `companion_panel.gd` para el equipo.

2. **Diseño de sistema primero** (documento en el scratchpad antes de programar, revisado con simulaciones):
   - **Estadísticas de combate derivadas** de los 5 atributos actuales (Liderazgo, Carisma, Estrategia, Combate, Defensa) más nivel, equipo y tipo de luchador. Una tabla de fórmulas y curvas por nivel:

     | Estadística | Para qué sirve |
     |---|---|
     | PV | Vida |
     | PT | Puntos de técnica |
     | Fuerza | Daño |
     | Defensa | Reduce el daño recibido |
     | Agilidad | Orden de turno y esquiva |
     | Puntería | Acierto y crítico |
     | Voluntad | Moral y resistencia a estados |

     Los 5 atributos siguen sirviendo para el mapa y la vida social.
   - **Debilidades arma × armadura** en una tabla fija y visible. Clases de defensa: Sin armadura, Cuero, Malla y Placas, según el equipo.

     | | Sin armadura | Cuero | Malla | Placas |
     |---|---|---|---|---|
     | Tajo | Débil | — | — | Resiste |
     | Estocada | — | — | Débil | Resiste |
     | Contundente | — | — | — | Débil |
     | Proyectil | — | Débil | — | Resiste |

     - Un círculo, una debilidad por arma; las Placas resisten todo salvo lo Contundente.
     - Débil: ×1,4 de daño. Resiste: ×0,6 de daño. Solo daño: no dan ni quitan turnos.
     - el turno extra solo lo da la pasiva **«Aprovechar la brecha»** (Duelista/Precisión y Asesino, escalón 3), el **Estoque** o la pieza única **Misericordia de Toledo**: al conectar una debilidad o un crítico, una acción más, como mucho una vez por turno.
     - Algunos estados crean debilidades temporales. Ejemplos: Derribado (débil a todo), Desequilibrado (débil a Contundente).
   - **Las posturas desaparecen** como mecánica aparte. Las que aportan se convierten en técnicas:
     - activas: "Furia" (≈ Desesperada, más daño y menos defensa durante 2 turnos) y "Guardia de esgrima" (≈ Esgrima, más esquiva y contra);
     - pasivas: "Muro de escudos" para Tanque y Defensor.
   - **Árbol de habilidades:**
     - un árbol propio por tipo de luchador, con 3 ramas y unas 15 técnicas y pasivas por tipo;
     - 3 ramas comunes que cualquiera puede aprender: Mando y apoyo, Supervivencia y Maestría de arma (Tajo, Estocada, Contundente, Proyectil);
     - 1 punto por nivel, con requisitos de nivel y de técnicas previas;
     - las habilidades de combate, el equipo y las piezas únicas actuales se convierten en nodos o bonificaciones;
     - los personajes del séquito y los PNJ aprenden solos según su tipo.
   - **Equilibrio de grupo:**
     - roles claros: daño, protección (provocar, cubrir), apoyo (curar, órdenes, subir estadísticas) y control (desarmar, derribar, debilitar);
     - simulaciones de grupo de 4 contra grupos de 2–6 enemigos de distintos niveles (nuevo `scratchpad/rpg_sim.gd`);
     - objetivos: combates de 4–8 rondas, sin un tipo de luchador dominante (cada uno entre el 45% y el 55% de victorias como líder) y con debilidades que importen (acertarlas sube las victorias de forma clara pero no decisiva).
   - La interfaz incluye una pantalla de **árbol de habilidades** (desde el gestor de grupo y al subir de nivel, en vez del panel actual de habilidades).

3. **Enemigos genéricos.** Hacen falta para que el RPG y los encuentros de las campales tengan rivales variados además de los personajes con nombre.
   - **Imágenes:** las genera el usuario. Hoy ya existen algunas en `assets/portraits/roles/` (bandido, soldado, caballero, campesino…).
   - **Dónde y cómo:**
     - formato: igual que los retratos actuales (PNG de 1024×1536 con fondo transparente), así el recorte automático de cara (`face_detector.gd`) funciona sin más;
     - carpeta: una por tipo, `assets/portraits/enemies/<tipo>/`, con varias imágenes por tipo para variar;
     - el juego elige una imagen al azar de la carpeta del tipo, igual que hace `PortraitGallery`;
     - al añadirlas: importarlas con compresión (fase 0 de cada sesión) y regenerar `face_rects.gd`.
   - **Catálogo** (nuevo `scripts/resources/enemy_catalog.gd`), con datos por tipo:
     - clase de armadura (Sin, Cuero, Malla, Placas) → sus debilidades en la tabla;
     - tipo de daño principal (Tajo, Estocada, Contundente, Proyectil);
     - técnicas;
     - estadísticas por nivel y rango;
     - tropa asociada en las campales.
   - **Tipos:**

     | Tipo | Armadura | Daño | Rol | Familia de tropa |
     |---|---|---|---|---|
     | Miliciano / campesino armado | Sin | Contundente | carne de cañón | infantería |
     | Bandido / salteador | Cuero | Tajo | daño, robo | — |
     | Soldado de a pie | Malla | Tajo | equilibrado | infantería |
     | Infantería pesada | Placas | Contundente | tanque, provocar | infantería pesada |
     | Arquero | Cuero | Proyectil | daño a distancia, apunta a débiles | arqueros |
     | Ballestero | Malla | Proyectil (perfora) | daño alto, lento | ballesteros |
     | Piquero / lancero | Malla | Estocada | castiga cargas, protege aliados | piqueros / lanceros |
     | Caballero a caballo | Malla | Estocada (carga) | carga inicial devastadora, rápido | caballería |
     | Caballero pesado a caballo | Placas | Contundente | muy duro, lento | caballería pesada |
     | Explorador / asesino | Cuero | Estocada | crítico, veneno | — |
     | Capellán de campaña | Cuero | Contundente | apoyo, cura, sube la moral | — |
     | **Mini jefes** | variable | variable | más PV, 2 acciones por ronda y una técnica propia | — |

   - **Mini jefes:** capitán de mercenarios bandidos, sargento veterano, campeón de torneo, caballero de la orden, jefe de los descalzos, el guardián de la torre, la bestia de la comarca (si se quiere una bestia).
   - Los grupos enemigos se componen por plantillas según el contexto: encuentro de camino, exploración, historia, torneo o pelotón de una campal.
   - **Sin imagen:** si falta la de un tipo, se usa la de su rol más cercano de `assets/portraits/roles/`. Así se puede probar antes de que estén todas.

4. **Nuevo combate RPG** (escena nueva `scenes/rpg_battle/`, lógica en `scripts/resources/rpg_battle_manager.gd`):
   - **Vista frontal:** enemigos arriba con su retrato grande, tu grupo abajo con sus retratos y barras, línea de turnos arriba.
   - **Recursos:** PV y PT (puntos de técnica), más Moral si sirve.
   - **Turnos:** por velocidad, en una línea visible (estilo FFX).
   - **Debilidades:**
     - tipos de daño Tajo, Estocada, Contundente y Proyectil;
     - armaduras y escudos con debilidades y resistencias;
     - las debilidades solo cambian el daño; el turno extra solo lo da la pasiva **«Aprovechar la brecha»** (Duelista/Precisión y Asesino, escalón 3), el **Estoque** o la pieza única **Misericordia de Toledo**: al conectar una debilidad o un crítico, una acción más, como mucho una vez por turno.
   - **Menú:** Atacar, Técnicas, Defender, Objeto, Cambiar (reserva) y Abandonar (rendirse o retirarse).
   - **Técnicas:** las del árbol de habilidades (punto 2). Datos en un nuevo `scripts/resources/skill_tree_catalog.gd` y efectos en `rpg_battle_manager.gd` / `skill_effects.gd`.
   - **IA:** usa la personalidad (reutilizar la lógica de `duel_ai.gd`) y aprovecha las debilidades.
   - **Lo que se conserva:** muerte a muerte, heridas, capturas (`CaptureData`), experiencia (`XpRules`, con multiplicadores por tipo de luchador), trofeos (piezas únicas) y "sensación de golpe" (`CombatFx`), con música y sonido por contexto.
   - **Puntos de entrada:** `CombatSetup.begin_event_fight`, `start_campaign_duel`, torneos, retos, historias, exploración y encuentros. El duelo de honor 1v1 usa el mismo sistema con un solo personaje por lado.
   - **Retirada del duelo antiguo:** `scenes/combat/` deja de usarse. El tutorial se rehace con lecciones del RPG.

---

## Fase 4 — Batallas campales con profundidad

1. **Oficiales:** cada pelotón tiene un jefe y hasta 2–3 oficiales.
   - Los oficiales salen del séquito (asignables en el gestor de grupo o en el Consejo de guerra) o de PNJ de la facción.
   - Los oficiales aportan sus estadísticas al pelotón.

2. **Cada encuentro entre pelotones = combate RPG:** jefe+oficiales contra jefe+oficiales.
   - Las **tropas dan estadísticas extra** a los personajes de su pelotón según número, familia y moral.
   - Algunas técnicas **piden tropa o moral mínimas** (p. ej. "Carga" requiere caballería y moral ≥ 50).
   - El resultado se traduce en bajas, moral o retirada de los pelotones.
   - Para que la batalla no se eternice: botón **"Resolver"** por encuentro (resolución automática con las mismas reglas) y una opción global en Ajustes para resolver automáticamente los encuentros donde no estás tú ni tu séquito.

3. **IA más lista** (`battle_manager.gd`, la IA del tablero):
   - flanquea;
   - protege a su general;
   - concentra los ataques;
   - guarda reservas;
   - se repliega para reagrupar;
   - nivel de dificultad ajustable.

4. **Formaciones y flancos:**
   - las unidades tienen orientación;
   - atacar por el flanco o la retaguardia da bonificación de daño y moral;
   - formaciones (Línea, Cuña, Cuadro) con fuerzas y debilidades;
   - el círculo de familias de tropa se mantiene.

5. Volver a equilibrar con `scratchpad/bal_sim.gd`.

---

## Archivos críticos (representativos)
- **Fase 1:** `scripts/autoload/relations_data.gd`, `army_data.gd`, `world_events.gd`, `mission_data.gd`, `scripts/resources/role_progression.gd`, `victory_rules.gd`, `achievement_catalog.gd`, `scenes/new_game/new_game.gd`, `scenes/battle/battle.gd`, `battle_manager.gd`, `save_system.gd`.
- **Fase 2:** `relations_data.gd`, `capture_data.gd`, `ambition_data.gd`, `story_data.gd`/`story_catalog.gd`, `dynasty_data.gd`, `dialogue_catalog.gd`, `event_catalog.gd`, `travel_data.gd`, `road_encounter_catalog.gd`, `scenes/map/*`, nuevo `scenes/character_manager/`, `scenes/main_menu/`.
- **Fase 3:** nuevos `scenes/rpg_battle/`, `scripts/resources/rpg_battle_manager.gd`, `scripts/ui/party_panel.gd`; `combat_setup.gd`, `content_catalog.gd`, `skill_effects.gd`, `scenes/tutorial/tutorial.gd`.
- **Fase 4:** `battle_manager.gd`, `battle_unit.gd`, `battle_board.gd`, `battle.gd`, `scripts/ui/war_council_panel.gd`, `settings.gd`.

## Verificación (por fase, modo ahorro)
- **Una prueba compacta por fase** en el scratchpad:
  - `phase1_test.gd`: reino caído → gente reclutada o errante y visible; tropa elegida respetada; partida con mercenario → No afiliado; registros con 200 líneas sin desborde.
  - `social_test.gd`: cada tipo de evento nuevo sale y se aplica; tope de esposas; concubinas y herencia; gestor de personajes (borrar, duplicar, exportar e importar en `user://_pruebas`).
  - Lealtad: sube y baja por cada causa; avisos antes de traicionar; cada tipo de traición se dispara con lealtad baja; ritmo en la simulación de 20 años.
  - `rpg_test.gd`: turnos por velocidad; debilidad → más daño; turno extra solo con «brecha» (una vez por turno); resistencia → menos daño, sin perder turno; técnicas por tipo; cambio de reserva; muerte, captura y XP; todos los puntos de entrada abren el RPG.
  - Fórmulas de estadísticas, tabla arma × armadura y árbol: cada nodo es aprendible y tiene efecto.
  - `rpg_sim.gd`: equilibrio de grupo dentro de los objetivos del punto 2.
  - `campal_test.gd`: oficiales asignados; encuentro → combate RPG o "Resolver"; flancos y formaciones; IA que protege al general.
- **Regresiones clave:** `smoke_game`, `battle2_test`, `captures_test`, `roles_test`, `travel_test`.
- **Sondas con ventana:** `overflow_all.gd` (0 desbordes) y `duel_hover_probe.gd` adaptada al RPG.
- **Cierre de cada fase:** exportar `builds/windows/RoyalPain.exe`, arrancarlo (`--headless --quit-after`) sin errores, commit y push.
- **Siempre:** pruebas solo en `user://_pruebas`; nunca ejecutar el juego sin `--script`.
