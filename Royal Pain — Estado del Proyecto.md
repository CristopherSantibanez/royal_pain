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

**Autoloads activos:** `GameData` (catálogo de habilidades/ventajas/equipo), `CreationState`, `CombatSetup`, `GameManager` (partida activa, castillo de origen, turno mensual, acciones por turno), `MapData` (12 castillos, reinos, conexiones), `ArmyData` (ejércitos, su movimiento y la resolución de batallas).

**Managers de lógica pura:** `DuelManager` (duelo) y `BattleManager` (batalla táctica) — ambos `RefCounted` con señales, sin nodos.

**Repositorio:** versionado en Git/GitHub, con historial de commits por entrega.

## Lo realizado

### Flujo de partida

NewGameReinicio del mundo

- Menú principal con **Nueva Partida**: se elige un personaje guardado, el **castillo de origen** y el **rol inicial** (Campesino a Nobleza Alta; Regente queda reservado para la sucesión).
- `GameManager.start_new_game()` reinicia castillos y ejércitos, así una partida nueva no hereda el estado de la anterior; el personaje se carga como copia fresca con vida/resistencia/moral al máximo.
- El mapa usa el **personaje real** (rol y castillo de origen) para la visión limitada y para decidir a qué castillo se puede entrar. Sin partida activa funciona como vista previa ("Ver Mapa").
- "Continuar Partida" en el menú y botón "Menú Principal" en el mapa; desde el resumen de creación se puede pasar directo a Nueva Partida.
- **Guardar / cargar partida** (`SaveSystem` + `SaveGame`): guarda en `user://saves/partida.tres` el estado completo — personaje con su progreso, fecha, acciones del mes, castillo de origen y reino, los 12 castillos (dueños, reinos, guarniciones, recursos), ejércitos (en marcha o asediando) y las noticias del mes. Botón "Guardar Partida" en el mapa, **autoguardado** al comenzar cada mes y "Cargar Partida" en el menú principal (muestra el resumen de la partida guardada). Si pierdes, el último autoguardado sigue disponible para reintentar.

### Sistema de personajes

Character.gdCreación completaGuardado persistente

- Identidad (nombre, apellido, sexo), retrato con sistema de fallback (propio → por rol/sexo → genérico).
- 5 estadísticas base repartibles: Liderazgo, Carisma, Estrategia, Combate, Defensa.
- Personalidad, Alineación y Tipo de Luchador — cada uno aporta bonos de stats concretos y predefinidos.
- Sistema de puntos: base fija por las 3 elecciones anteriores + 10 puntos libres siempre.
- Ventajas (mín. 3) y Desventajas (mín. 2) obligatorias, con modificadores reales a stats.
- Habilidades en 3 categorías (general, combate, batalla) — las de **batalla** ya tienen efecto mecánico; las generales y de combate siguen siendo solo datos.
- Equipamiento (máx. 2 piezas) con bonos que aplican tanto en combate como en política.
- Biografía opcional. Pantalla de resumen final antes de guardar como `.tres` en `user://characters/`.

### Combate por turnos (duelo)

DuelManager.gdTurnos reales con pausa

- 5 posturas, 8 acciones (atacar, defender, esquivar, contraatacar, desarmar, empujar, rendirse, retirarse), 5 estados (herido, fatigado, desarmado, desmoralizado, inspirado).
- Postura y acción separadas: elegir postura no gasta turno, la acción sí.
- Turnos alternos con pausa visual real (no simultáneos), indicador de turno, botones bloqueados fuera de tu turno.
- Selector de combatientes: personajes guardados o generados de prueba.
- Resultado del duelo alimenta **honor, oro y contador de victorias/derrotas** del personaje — conecta directo con la progresión social.
- **Duelos en la campaña**: acción "Retar a Duelo" en el castillo (Soldado, Caballero, Nobleza Baja y Alta; gasta 1 acción) contra un rival generado de tu mismo rango y fuerza parecida, con nombre y retrato al azar. El duelo usa tu personaje real: honor, oro, duelos ganados y posible descenso por deshonra se aplican a la partida, y al volver el castillo muestra el resumen. En campaña no se puede abandonar a mitad (solo rendirse o retirarse). Esto hace alcanzable el ascenso Soldado → Caballero jugando.
- Corregido: un golpe que conecta siempre hace al menos 1 de daño (antes, con moral baja podía redondear a 0 y el duelo no terminaba).

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
- Nobleza Alta → Regente queda intencionalmente bloqueado: requiere un sistema de sucesión/rebelión aún no diseñado.
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

### Eventos mensuales y anuales

EventCatalog.gd14 eventos + 5 anuales

- Cada mes hay un 60% de probabilidad de un **evento con decisión**, elegido según tu **rol** (cada evento declara qué roles lo pueden vivir) y ponderado por tu **personalidad** (un Piadoso encuentra más peregrinos; un Ambicioso, más sobornos).
- 14 eventos históricamente creíbles: recaudador abusivo, bandidos, peregrino enfermo, maestro de armas, soborno, insulto en la taberna, disputa de tierras, incendio del granero, torneo local, vendedor de reliquias, voluntarios, tratado de guerra, buena cosecha, rumores de conspiración.
- Cada opción tiene efectos concretos (oro, honor, stats, oro/comida/guarnición del castillo). Algunas tienen requisitos (se muestran deshabilitadas si no alcanza el oro) y otras son **de riesgo**, con probabilidad que depende de una stat (p. ej. Combate para enfrentar bandidos) y se muestra en el botón.
- Los efectos sobre el honor pueden provocar descenso por deshonra.
- Cada enero, un **evento anual** afecta a todos los castillos: cosecha abundante, mala cosecha, peste, auge comercial o año tranquilo. Aparece en las Noticias del reino.
- En el mapa el evento se muestra en una ventana; hay que decidir antes de avanzar el turno. El evento pendiente se conserva al guardar/cargar.
- Los eventos son datos (`EventCatalog.EVENTS`): agregar uno nuevo es añadir un diccionario, sin tocar lógica.

## Lo pendiente

| Sistema | Estado | Notas |
| --- | --- | --- |
| Batalla táctica — mejoras | v1 hecha | Pendiente: ejércitos enemigos controlados por IA (hoy solo el jugador ataca), batallas de campo abierto sin muralla, asedios de varios turnos de mapa, retratos/arte de unidades. |
| Conquista de castillos | Hecha (v1) | Falta: efectos sobre la lealtad/relaciones del reino conquistado y recuperación por el reino original. |
| Sucesión Nobleza Alta → Regente | No iniciado | Requiere diseñar rebelión y/o herencia. |
| Relaciones entre personajes | No iniciado | Alianza, rivalidad, amor, etc. — afectan combate y política según el documento de diseño. |
| Eventos — ampliación | v1 hecha | Faltan eventos encadenados, eventos ligados a relaciones entre personajes y efectos del alineamiento. |
| Matrimonios políticos | No iniciado | Herramienta diplomática central del documento original. |
| Diplomacia (tratados, declarar guerra, edictos) | No iniciado | Marcado como "Próximamente" en las acciones de Nobleza Alta/Regente. |
| Condiciones de victoria/derrota por rol | Parcial | Existe la derrota por perder tu último castillo; faltan las victorias por rol y el resto de derrotas del documento de diseño. |
| Varias ranuras de guardado | Pendiente | Hoy hay un único espacio de guardado (manual + autoguardado mensual). |
| Habilidades con efecto mecánico real | Parcial | Las de batalla ya funcionan; las generales (ej. "Viajero") y de combate (ej. "Desarme Fulminante") siguen sin alterar fórmulas. |
| Heridas y torneos | No iniciado | Tras un duelo de campaña el personaje se recupera por completo; falta un sistema de heridas y la acción "Prepararse para Torneo" del Caballero. |
| Arte y sonido final | Pendiente del usuario | Retratos parcialmente integrados; resto de assets, música y SFX no definidos. |

## Roadmap sugerido

1. ~~**Terminar la batalla táctica** y conectarla con el resultado de "batalla pendiente"~~ ✅ v1 hecha.
2. ~~**Conquista de castillos**: cambio de reino/dueño tras una victoria~~ ✅ hecha.
3. ~~**Duelos en la campaña y reinos con IA**~~ ✅ hechos (IA de reinos v1: ataques, auto-resolución, defensa jugable).
4. **Eventos** ✅ (v1) **y relaciones** (pendiente): dan vida al mundo entre turnos, menos acoplados a otros sistemas técnicos.
5. **Diplomacia y matrimonios**: siguiente capa de profundidad política.
6. **Sucesión / Regente**: cierra el ciclo completo de movilidad social.
7. **Condiciones de victoria** (el guardado de partida completa ✅ ya está hecho): necesarias para que el juego sea "jugable de principio a fin".
8. **Pulido**: arte final, sonido, balance general.

Documento generado como resumen de estado — refleja el trabajo hasta el cierre de la última sesión de desarrollo.