# ⚔️ Royal Pain — Reinos de Destino

Estado del proyecto · estrategia 2D histórico-medieval en Godot 4.7

[Visión y pretensiones](#vision) [Arquitectura técnica](#arquitectura) [Lo realizado](#realizado) [Lo pendiente](#pendiente) [Roadmap sugerido](#roadmap)

## Visión y pretensiones generales

"Reinos de Destino" es un juego de estrategia en pixel art ambientado en una Europa medieval sin fantasía (siglos X–XV). No hay niveles ni experiencia: la progresión es puramente **social**. El jugador elige un rol dentro de la jerarquía feudal —de Campesino a Regente— y asciende o desciende según sus decisiones, hazañas y fracasos.

La promesa central: tu historia personal es el juego. Cada decisión puede catapultarte al poder o arruinarte.

El diseño se apoya en tres capas de juego interconectadas, cada una a una escala distinta de conflicto:

- **Mapa geopolítico** — gestión de reinos, movimiento de ejércitos, diplomacia, visión limitada según el rol.
- **Batalla táctica** — resolución de conflictos a escala de pelotones, con terreno y tipos de unidad.
- **Duelo por turnos** — combate personal entre dos personajes, con posturas, honor y consecuencias de carrera.

Pilares de diseño que guían cada decisión técnica tomada hasta ahora:

- **Sin fantasía:** todo históricamente creíble — nada de magia ni criaturas.
- **El rol lo determina casi todo:** visión del mapa, acciones disponibles, participación en combate y caminos de victoria.
- **Movilidad vertical real:** ascender y descender de rango son mecánicas igual de desarrolladas, no solo narrativa.
- **Sistemas con dueño claro:** cada pieza de datos (personaje, castillo, ejército) es un `Resource` de Godot, reutilizable entre las tres interfaces.

## Arquitectura técnica

Patrón consistente en todo el proyecto: **Resource de datos → Manager de lógica pura (señales, sin nodos) → Escena de UI que escucha esas señales**. Así la lógica de combate, duelo o batalla se puede probar y ajustar sin tocar una sola línea de interfaz.

**Autoloads activos:** `GameData` (catálogo de habilidades/ventajas/equipo), `CreationState`, `CombatSetup`, `GameManager` (partida activa, castillo de origen, turno mensual, acciones, eventos, victoria), `MapData` (12 castillos, reinos, conexiones), `ArmyData` (ejércitos, IA de reinos y resolución de batallas), `RelationsData` (relaciones con señores y rivales).

**Regla de dependencias:** los autoloads no pueden referenciarse en ciclo (rompe la compilación). Orden permitido: `RelationsData`/`ArmyData` → `GameManager` → `MapData`. La lógica de reglas vive en clases puras sin autoloads (`KingdomAI`, `EventCatalog`, `VictoryRules`, `BattleManager`, `DuelManager`).

**Managers de lógica pura:** `DuelManager` (duelo) y `BattleManager` (batalla táctica) — ambos `RefCounted` con señales, sin nodos.

**Repositorio:** versionado en Git/GitHub, con historial de commits por entrega.

## Lo realizado

### Flujo de partida

NewGameReinicio del mundo

- Menú principal con **Nueva Partida**: se elige un personaje guardado, el **castillo de origen** y el **rol inicial** (Campesino a Nobleza Alta; Regente queda reservado para la sucesión).
- `GameManager.start_new_game()` reinicia castillos y ejércitos, así una partida nueva no hereda el estado de la anterior; el personaje se carga como copia fresca con vida/resistencia/moral al máximo.
- El mapa usa el **personaje real** (rol y castillo de origen) para la visión limitada y para decidir a qué castillo se puede entrar. Sin partida activa funciona como vista previa ("Ver Mapa").
- "Continuar Partida" en el menú y botón "Menú Principal" en el mapa; desde el resumen de creación se puede pasar directo a Nueva Partida.
- **Guardar / cargar partida** (`SaveSystem` + `SaveGame`): guarda el estado completo — personaje con su progreso, fecha, acciones, castillo de origen y reino, castillos, ejércitos, noticias, relaciones, población, guerras entre reinos, edicto, matrimonio, etc.
  - **Ranuras**: un **autoguardado** (se escribe solo al comenzar cada mes) y **3 ranuras manuales** en `user://saves/`.
  - Pantalla **Partidas guardadas**: desde el mapa para guardar ("Guardar aquí"; sobrescribir pide confirmación) y desde el menú para cargar; las ranuras manuales se pueden borrar (con confirmación). Cada ranura muestra personaje, rango, fecha del juego y fecha real del guardado.
  - En el menú, si no hay partida activa y existe algún guardado, el botón **Continuar** carga el más reciente.
  - El guardado de la versión anterior (`partida.tres`) se convierte solo en el autoguardado.

### Sistema de personajes

Character.gdCreación completaGuardado persistente

- Identidad (nombre, apellido, sexo), retrato con sistema de fallback (propio → por rol/sexo → genérico).
- 5 estadísticas base repartibles: Liderazgo, Carisma, Estrategia, Combate, Defensa.
- Personalidad, Alineación y Tipo de Luchador — cada uno aporta bonos de stats concretos y predefinidos.
- Sistema de puntos: base fija por las 3 elecciones anteriores + 10 puntos libres siempre.
- Ventajas (mín. 3) y Desventajas (mín. 2) obligatorias, con modificadores reales a stats.
- Habilidades en 3 categorías, **todas con efecto mecánico real** (`SkillEffects`):
  - *Generales*: **Administrador** (+25% en impuestos, gobierno, impuestos reales y edicto de impuestos), **Reclutador Nato** (milicia un tercio más barata y +50% de soldados; +10% al movilizar), **Viajero** (marchas a 2 saltos en un turno), **Paso Invernal** (tus ejércitos no se frenan en invierno).
  - *Combate (duelo)*: **Golpe Certero** (20% de golpe crítico ×1.5, frente al 5% base), **Piel de Hierro** (−30% de daño recibido estando herido), **Desarme Fulminante** (golpe inmediato tras desarmar).
  - *Batalla*: **Grito de Guerra**, **Táctica Defensiva**, **Carga Letal** (ver Batalla táctica).
  - Los personajes del mundo también tienen habilidades y las usan (rivales en duelo, señores al mando de sus ejércitos).
- **Invierno** (diciembre a febrero): las marchas tardan 2 turnos salvo con Paso Invernal; el mapa indica "Invierno" junto a la fecha. La partida empieza en enero, así que las primeras marchas son lentas.
- Equipamiento (máx. 2 piezas) con bonos que aplican tanto en combate como en política.
- Biografía opcional. Pantalla de resumen final antes de guardar como `.tres` en `user://characters/`.
- Botón **Aleatorio** en el editor: rellena todo el personaje al azar (sexo, nombre, retrato de su género, personalidad, alineación, tipo, reparto de los 10 puntos, 3 ventajas, 2 desventajas, una habilidad por categoría, equipo y biografía) usando los mismos controles, así se puede retocar después.
- Corregido: los botones Hombre/Mujer estaban en grupos distintos y podían quedar marcados a la vez.

### Combate por turnos (duelo)

DuelManager.gdTurnos reales con pausa

- 5 posturas, 8 acciones (atacar, defender, esquivar, contraatacar, desarmar, empujar, rendirse, retirarse), 5 estados (herido, fatigado, desarmado, desmoralizado, inspirado).
- Postura y acción separadas: elegir postura no gasta turno, la acción sí.
- Turnos alternos con pausa visual real (no simultáneos), indicador de turno, botones bloqueados fuera de tu turno.
- Selector de combatientes: personajes guardados o generados de prueba.
- Resultado del duelo alimenta **honor, oro y contador de victorias/derrotas** del personaje — conecta directo con la progresión social.
- **Duelos en la campaña**: acción "Retar a Duelo" en el castillo (Soldado, Caballero, Nobleza Baja y Alta; gasta 1 acción) contra un rival generado de tu mismo rango y fuerza parecida, con nombre y retrato al azar. El duelo usa tu personaje real: honor, oro, duelos ganados y posible descenso por deshonra se aplican a la partida, y al volver el castillo muestra el resumen. En campaña no se puede abandonar a mitad (solo rendirse o retirarse). Esto hace alcanzable el ascenso Soldado → Caballero jugando.
- Corregido: un golpe que conecta siempre hace al menos 1 de daño (antes, con moral baja podía redondear a 0 y el duelo no terminaba).
- **Heridas**: la vida perdida en un duelo ya no se cura al terminar; se recuperan 25 de vida por mes. Si terminas bajo el 30% de vida quedas **gravemente herido** 2 meses (3 si caes): no puedes retar a duelo ni ir a torneos. El **médico** del castillo (30 de oro, 1 acción) cura 50 y acorta la herida un mes. Algunos eventos de riesgo (bandidos, torneo local) también hieren. La vida y la herida se ven en el castillo.
- **Torneos** (Caballero, Nobleza Baja y Alta; de abril a septiembre, uno por año, 50 de inscripción): 3 duelos seguidos contra caballeros de la corte cada vez más fuertes, con 30 de vida recuperada entre rondas. Cada ronda ganada da +3 de honor; el campeón gana 300 de oro y 15 de honor. Si quedas malherido debes retirarte. Los duelos del torneo cuentan para la victoria "Campeón".

### Mapa geopolítico

12 castillosMapVision.gdTurno mensual

- Imagen única del mundo con 12 castillos clicables (Area2D) y rutas dinámicas entre ellos (grafo de conexiones, no pathfinding automático).
- Cámara con zoom/pan y límites ajustados al tamaño real de la imagen.
- Panel de detalles por castillo: reino, gobernante, guarnición, oro, comida.
- **Visión limitada por rol**: Campesino ve solo su aldea; Soldado, 1 salto; Caballero, 2 saltos; Nobleza Baja, su reino completo; Nobleza Alta, su reino + vecinos; Regente, el mapa entero. Castillos fuera de visión se ven atenuados con datos ocultos.
- **Turno mensual real**: fecha (mes/año), acciones limitadas por turno (fórmula: base según rol + liderazgo/10), botón de avance que resuelve movimiento de ejércitos.

### Progresión social (ascenso y descenso)

RoleProgression.gdAutomático

- Ascenso Campesino → Soldado → Caballero → Nobleza Baja → Nobleza Alta, cada uno con requisitos concretos (duelos ganados, honor, oro, liderazgo).
- Descenso automático por deshonra (honor bajo tras perder duelos repetidamente) para Caballero en adelante.
- Nobleza Alta → Regente por herencia (matrimonio con la casa real) o usurpación (ver "Matrimonios políticos y sucesión").
- Interfaz de castillo con **acciones específicas por rol** (2 por rol: una funcional usando datos reales, otra marcada "Próximamente" donde falta un sistema mayor).

### Ejércitos

ArmyData.gdFuncional

- Movilización de tropas desde la guarnición de un castillo (disponible desde Caballero en adelante, proporcional al rol).
- Movimiento por el grafo de rutas: 1 salto conectado = 1 turno, resuelto automáticamente al avanzar el mes.
- Llegada a territorio aliado refuerza la guarnición; llegada a territorio enemigo marca "batalla pendiente" (círculo rojo en el mapa) y habilita **Iniciar Batalla** en el panel del ejército.
- Marcador visual en el mapa (azul: estacionado, amarillo: en marcha, rojo: batalla pendiente) con línea de ruta mientras marcha.
- Cada ejército recuerda su castillo de origen para poder replegarse tras una derrota.

### Batalla táctica (v1)

BattleManager.gdTablero 12×8Conquista

- Tablero de 12×8 casillas con terreno: **llano**, **bosque** (defensa +25%), **colina** (defensa +20%, arqueros +1 de alcance) y **muralla** del castillo defensor (defensa +50%). Bosque, colina y muralla cuestan más movimiento (la caballería sufre más en bosque y muralla).
- Pelotones generados desde el tamaño del ejército y de la guarnición (≈20 soldados por pelotón, máx. 6 por bando): 50% infantería, 30% arqueros, 20% caballería.
- Ventajas de tipo: caballería > arqueros, infantería > caballería, arqueros > infantería a distancia (y débiles cuerpo a cuerpo). Respuesta automática en cuerpo a cuerpo.
- **Moral y fatiga**: las bajas bajan la moral, bajo 25 el pelotón huye y desmoraliza a sus aliados; moverse y atacar cansa, descansar recupera. El liderazgo y la estrategia del comandante potencian a sus tropas.
- **Habilidades de batalla conectadas**: *Grito de Guerra* (+moral inicial), *Táctica Defensiva* (menos daño en colina/muralla), *Carga Letal* (+25% daño de caballería).
- IA del defensor: espera tras la muralla hasta que el enemigo se acerca (la caballería sale a cazar), elige el objetivo con mayor daño esperado.
- Fin: aniquilación o huida de un bando, retirada voluntaria, o 12 turnos sin tomar el castillo (gana el defensor).
- **Conquista**: si gana el atacante, el castillo cambia de reino y gobernante, la guarnición pasa a ser los sobrevivientes y el jugador gana honor y saquea oro. Si pierde, el castillo conserva a sus defensores sobrevivientes, el ejército se repliega a su origen (o se disuelve) y el jugador pierde honor — con posible descenso por deshonra.

### Reinos con IA

KingdomAI.gdAuto-resoluciónDefensa jugable

- Los 11 reinos que no son del jugador actúan cada mes: todas las guarniciones reclutan (+2/mes, tope 200) y, pasados 3 meses de gracia, un castillo con 60+ soldados puede movilizar un 40% de su guarnición contra el vecino más débil de otro reino (máx. 2 ejércitos de IA a la vez, solo si cree que puede ganar).
- `KingdomAI` es lógica pura (recibe castillos y ejércitos, devuelve decisiones) para evitar ciclos entre autoloads.
- Batallas IA contra IA se **auto-resuelven** con una fórmula (tropas × muralla × azar); los castillos cambian de reino y los restos derrotados vuelven a su guarnición.
- Si atacan **tu** castillo (el de origen o uno que conquistaste): aviso en el mapa y botón **Defender Castillo** — juegas la batalla táctica como defensor, con tus habilidades de batalla. Si avanzas el turno sin defender, la batalla se libra sola.
- Defender con éxito da honor; perder resta honor (con posible deshonra). Si cae tu castillo de origen te refugias en otro castillo tuyo; si no tienes ninguno, **fin de la partida** (primera condición de derrota).
- Mapa: panel **Noticias del reino** con los sucesos del mes que tu rol te permite ver, ejércitos enemigos en púrpura (solo los que están dentro de tu visión) y la visión se recalcula tras las conquistas.
- **Diplomacia entre reinos de la IA** (`KingdomDiplomacy`): cada mes los reinos pueden declararse la guerra (prefieren al vecino más débil, máx. 2 guerras a la vez), firmar la paz (tras 6 meses de guerra) o sellar alianzas. Todo sale en las noticias y se ve en la pantalla de Relaciones. El reino del jugador no entra en esta diplomacia: la suya la decide él.
- **Los ataques entre reinos de la IA requieren guerra** (nunca entre aliados). En guerra la IA ataca más a menudo y se arriesga con menos ventaja. Las tierras sin señor (Isla Neutral) se pueden tomar sin declarar guerra. Perder un castillo ante otro reino es casus belli: queda declarada la guerra.
- **Reconquista**: cada castillo recuerda su reino y señor de origen; un reino prioriza recuperar los castillos que perdió, aunque no haya guerra declarada.
- **Rebeliones**: los castillos que conquistaste pueden sublevarse cada mes y volver a su señor original (3% base; +5% si tu honor es menor a 40; +5% si la guarnición es menor a 30; la Tregua del Rey lo reduce a la mitad). Tu castillo de origen nunca se rebela.
- Balance medido en 20 partidas simuladas de 36 meses: ~5,5 ejércitos de la IA, ~10 guerras y ~1,4 castillos que cambian de manos por partida.

### Eventos mensuales y anuales

EventCatalog.gd14 eventos + 5 anuales

- Cada mes hay un 60% de probabilidad de un **evento con decisión**, elegido según tu **rol** (cada evento declara qué roles lo pueden vivir) y ponderado por tu **personalidad** (un Piadoso encuentra más peregrinos; un Ambicioso, más sobornos).
- 14 eventos históricamente creíbles: recaudador abusivo, bandidos, peregrino enfermo, maestro de armas, soborno, insulto en la taberna, disputa de tierras, incendio del granero, torneo local, vendedor de reliquias, voluntarios, tratado de guerra, buena cosecha, rumores de conspiración.
- Cada opción tiene efectos concretos (oro, honor, stats, oro/comida/guarnición del castillo). Algunas tienen requisitos (se muestran deshabilitadas si no alcanza el oro) y otras son **de riesgo**, con probabilidad que depende de una stat (p. ej. Combate para enfrentar bandidos) y se muestra en el botón.
- Los efectos sobre el honor pueden provocar descenso por deshonra.
- Cada enero, un **evento anual** afecta a todos los castillos: cosecha abundante, mala cosecha, peste, auge comercial o año tranquilo. Aparece en las Noticias del reino.
- En el mapa el evento se muestra en una ventana; hay que decidir antes de avanzar el turno. El evento pendiente se conserva al guardar/cargar.
- Los eventos son datos (`EventCatalog.EVENTS`): agregar uno nuevo es añadir un diccionario, sin tocar lógica.

### Población del mundo

PortraitPool.gdCharacterLoader.make_random_character

- Al iniciar una partida se generan **personajes aleatorios** que pueblan el mundo: una ficha completa para cada uno de los **11 señores** (género según su título: Lord/Rey o Lady) y **2 cortesanos por castillo** (22 en total; Soldado, Caballero o Nobleza Baja).
- Cada personaje recibe un **retrato único**: los retratos se reparten sin repetirse, separados por género (`male/`, `female/`), excluyendo el del jugador. El género de los cortesanos se elige en proporción a los retratos libres de cada género, para no agotar uno antes de tiempo (hoy hay 15 masculinos y 96 femeninos).
- Los personajes tienen stats, rasgos, habilidades y equipo generados con las mismas reglas que la creación del jugador.
- Usos: los **rivales de duelo** salen de la corte (un cortesano con quien te bates pasa a ser tu rival); los **señores comandan sus tropas** en la batalla táctica con su liderazgo, estrategia y habilidades de batalla; la pantalla de Relaciones muestra los retratos y la **corte de tu reino**.
- La población y los retratos usados se guardan con la partida.

### Relaciones

RelationsData.gdPantalla de Relaciones

- Cada partida empieza con una relación (afinidad −100 a 100) con los **11 señores** de los reinos. Se consulta en la pantalla **Relaciones** (botón en el mapa, o "Negociar Alianza Regional" desde el castillo de Nobleza Alta).
- **Enviar presentes** (50 de oro, 1 acción) sube la afinidad según tu Carisma. Con 40+ de afinidad y rango de Nobleza puedes **pactar una alianza** (1 acción).
- Efectos en la IA de reinos: un señor **aliado nunca ataca tus castillos**; un señor **hostil** (afinidad ≤ −20) los prefiere como blanco.
- Las relaciones reaccionan al mundo: quien marcha contra tu castillo pierde afinidad; conquistar el castillo de un señor la hunde (−40) y rompe la alianza si la había.
- **Rivales de duelo recurrentes**: cada rival al que te enfrentas queda registrado (con su ficha), y al retar a duelo hay un 50% de que vuelva uno conocido buscando revancha. Vencer de nuevo a un rival da +3 de honor extra.
- Las relaciones se guardan con la partida.

### Matrimonios políticos y sucesión al trono

RelationsData.gdRoleProgression.gd

- **Matrimonio**: desde Relaciones, con un señor de afinidad 60+ y siendo Caballero o más, puedes pedir la mano de alguien de su casa (dote de 100 de oro, 1 acción). Su familia queda **aliada**, ganas honor y el cónyuge lleva el apellido de la casa. Solo un matrimonio por partida.
- Cada partida registra al **soberano de tu reino** (el señor de tu castillo de origen al empezar).
- **Nobleza Alta → Regente** ya es posible con 80+ de honor y uno de dos caminos:
  - **Herencia**: estar casado con la familia de tu soberano → sucesión pacífica (mejora la relación con el antiguo rey).
  - **Usurpación**: controlar 4 castillos de tu reino (el de origen y los conquistados a tu nombre) → depones al rey, que jura venganza (afinidad −50, rompe alianza).
- Al coronarte pasas a gobernar tu castillo de origen y desbloqueas las acciones de Regente (impuestos reales, ejército real, visión total del mapa).
- Matrimonio, cónyuge y soberano se guardan con la partida.

### Diplomacia y edictos

RelationsData.gdEdictCatalog.gd

- **Declarar guerra** (Nobleza Alta y Regente, 1 acción): el señor pasa a "En guerra", su reino te prefiere como blanco, y marchar contra él **no tiene penalización**.
- **Tratado de paz** (tributo de 100 de oro, 1 acción): el enemigo acepta salvo que su afinidad sea menor a −60.
- **Agresión sin declarar**: marchar contra un señor sin guerra declarada lo ofende (−15 de afinidad).
- **Traición**: marchar contra un aliado rompe la alianza, cuesta 15 de honor y todos los demás señores pierden confianza en ti (−5). Sale en las Noticias del reino.
- **Edictos del Regente** (desde el castillo, 1 acción; uno vigente a la vez, efecto mensual):
  - *Leva*: +5 soldados por mes en cada castillo de tu reino, a costa de comida.
  - *Impuestos Altos*: +40 de oro al mes, −1 de honor.
  - *Tregua del Rey*: +1 de honor y +2 de afinidad con todos los señores cada mes.
- Guerras y edicto vigente se guardan con la partida.

### Victoria y derrota

VictoryRules.gdMeta por rol inicial

- La **meta depende del rol con el que empiezas**: elegir el rol en Nueva Partida es elegir tu camino a la victoria (y no cambia al ascender).

| Rol inicial | Objetivo |
| --- | --- |
| Campesino | *De la nada*: llegar a Nobleza Baja |
| Soldado | *Campeón*: ser Caballero y haber ganado 10 duelos |
| Caballero | *Conquistador*: gobernar 2 castillos conquistados por ti |
| Nobleza Baja | *Señor de la guerra*: 3 castillos a tu nombre (el de origen cuenta) |
| Nobleza Alta | *Hegemonía*: que tu reino controle 6 de los 12 castillos |

- El objetivo y su progreso se ven en el panel de turno del mapa y en Nueva Partida. Al cumplirlo se anuncia la victoria una sola vez y se puede **seguir jugando** o volver al menú.
- **Derrotas**: perder tu último castillo, o que tu honor llegue a 0 (destierro).
- El rol inicial y la victoria se guardan con la partida.

## Lo pendiente

| Sistema | Estado | Notas |
| --- | --- | --- |
| Batalla táctica — mejoras | v1 hecha | Pendiente: batallas de campo abierto sin muralla, asedios de varios turnos de mapa, retratos/arte de unidades. |
| Conquista de castillos | Hecha (v1) | Falta: efectos sobre la lealtad/relaciones del reino conquistado y recuperación por el reino original. |
| Sucesión — ampliación | v1 hecha | Ya hay rebeliones en castillos conquistados. Falta: herederos/descendencia y muerte del personaje. |
| Relaciones — ampliación | v1 hecha | Hechos: afinidad con señores, alianzas, hostilidad, rivales de duelo, matrimonio, población del mundo. Faltan: relaciones entre PNJ, efectos en combate y eventos ligados a relaciones. |
| Eventos — ampliación | v1 hecha | Faltan eventos encadenados, eventos ligados a relaciones entre personajes y efectos del alineamiento. |
| Matrimonios — ampliación | v1 hecha | Falta: hijos, divorcio/viudez, eventos del cónyuge y matrimonios entre NPCs. |
| Diplomacia — ampliación | v1 hecha | La IA ya declara guerras, paces y alianzas entre reinos. Falta: que la IA proponga tratados al jugador y más tipos de tratados/edictos. |
| Condiciones de victoria/derrota — ampliación | v1 hecha | Victoria por rol inicial y dos derrotas implementadas; falta la victoria del Regente (requiere sucesión) y ajustar metas con el documento de diseño original. |
| Arte y sonido final | Pendiente del usuario | Retratos parcialmente integrados; resto de assets, música y SFX no definidos. |

## Roadmap sugerido

1. ~~**Terminar la batalla táctica** y conectarla con el resultado de "batalla pendiente"~~ ✅ v1 hecha.
2. ~~**Conquista de castillos**: cambio de reino/dueño tras una victoria~~ ✅ hecha.
3. ~~**Duelos en la campaña y reinos con IA**~~ ✅ hechos (IA de reinos v1: ataques, auto-resolución, defensa jugable).
4. ~~**Eventos y relaciones**~~ ✅ (v1 de ambos): dan vida al mundo entre turnos.
5. ~~**Diplomacia y matrimonios**~~ ✅ (v1 de ambos).
6. ~~**Sucesión / Regente**~~ ✅ (v1): el ciclo completo de movilidad social Campesino → Regente ya existe.
7. ~~**Condiciones de victoria y guardado de partida completa**~~ ✅ hechos: el juego es jugable de principio a fin.
8. **Pulido**: arte final, sonido, balance general.

Documento generado como resumen de estado — refleja el trabajo hasta el cierre de la última sesión de desarrollo.