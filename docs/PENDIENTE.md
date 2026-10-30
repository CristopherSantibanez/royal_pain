# Royal Pain — Lo que queda pendiente

Resumen de las fases que faltan del plan de revisión. El detalle completo, con cada decisión, está en `docs/plan_revision.md`. Para retomar, pídele a Claude: **«Lee docs/CONTINUAR.md, docs/PENDIENTE.md y docs/plan_revision.md y empecemos la fase 3»**.

| Fase | Estado |
|---|---|
| 1. Arreglos y retirada de mercenarios | ✅ Hecha |
| 2. Vida social | ✅ Hecha (con algunos repasos abajo) |
| 3. Gestor de grupo y combate RPG | ⏳ Pendiente |
| 4. Batallas campales con profundidad | 🔶 4A hecha (oficiales, choques RPG, traición, botín); falta 4B (IA y formaciones) |

---

## Repasos pequeños de la fase 2
- **Celos:** el evento "Celos" (`soc_celos` en `scripts/resources/social_event_catalog.gd`) se mantiene por ahora; el usuario quiere quitarlo más adelante. Cuando se quite, en `tests/phase2b_test.gd` la comprobación "amante: puede haber celos" pasa a "sin celos".
- **Frecuencia de decisiones:** con todos los sistemas, el 61% de los meses trae alguna decisión (objetivo ≤ 60%). Si se nota pesado, bajar un poco `MONTHLY_EVENT_CHANCE` en `event_catalog.gd` (hoy 0,2).
- **Botín y lealtad:** repartir el botín sube la lealtad (`LoyaltyData.share_loot()`), pero aún ningún combate reparte botín. Se conecta en la fase 3 o 4.
- **Por probar a mano:** el encuentro con un viajero en el juego y las ventanas de exportar e importar de "Mis personajes".

---

## Fase 3 — Gestor de grupo y combate RPG

**Objetivo:** sustituir el duelo actual por un combate de grupo por turnos al estilo JRPG en todo lo que no sea batalla campal: duelos 1 contra 1, torneos, retos, eventos, encuentros, exploración, historias y escaramuzas.

1. **Gestor de grupo:**
   - todo tu séquito con retrato, nivel, vida, técnicas, equipo y lealtad;
   - eliges **4 activos** y el resto queda en reserva;
   - en combate se puede cambiar un activo por uno de la reserva gastando un turno.
2. **Diseño del sistema**, antes de programar:
   - **Estadísticas de combate:** salen de los 5 atributos actuales. Son vida (PV), puntos de técnica (PT), Fuerza, Defensa, Agilidad (turnos y esquiva), Puntería (acierto y crítico) y Voluntad (moral y estados).
   - **Debilidades arma × armadura:** tabla fija con los daños Tajo, Estocada, Contundente y Proyectil contra las armaduras Sin, Cuero, Malla y Placas.
     - Círculo: Tajo > Sin armadura, Estocada > Malla, Contundente > Placas, Proyectil > Cuero; las Placas resisten todo salvo lo Contundente.
     - Débil: ×1,4 de daño. Resiste: ×0,6 de daño. Solo daño: no dan ni quitan turnos.
     - El turno extra solo lo da la pasiva **«Aprovechar la brecha»** (Duelista/Precisión y Asesino, escalón 3), el **Estoque** o la pieza única **Misericordia de Toledo**: al conectar una debilidad o un crítico, una acción más, como mucho una vez por turno.
   - **Las posturas desaparecen:** las útiles pasan a ser técnicas, como "Furia", "Guardia de esgrima" o "Muro de escudos".
   - **Árbol de habilidades:**
     - uno por tipo de luchador, con 3 ramas;
     - 3 ramas comunes: Mando y apoyo, Supervivencia y Maestría de arma;
     - 1 punto por nivel;
     - las habilidades, el equipo y las piezas únicas actuales pasan a ser nodos del árbol.
   - **Equilibrio:** simulaciones de grupo contra grupo, sin un tipo de luchador dominante y con combates de 4 a 8 rondas.
3. **Enemigos genéricos:** catálogo con armadura, daño, rol y técnicas: miliciano, bandido, soldado, infantería pesada, arquero, ballestero, piquero, caballero montado, caballero pesado, explorador, capellán y **mini jefes** (más vida, 2 acciones por ronda y una técnica propia).
   - **Imágenes (las genera el usuario):** PNG de 1024×1536 con fondo transparente en `assets/portraits/enemies/<tipo>/`, una carpeta por tipo y varias imágenes por tipo.
   - **Mientras falten**, se usa la del rol más parecido.
4. **El combate:**
   - **Pantalla:** vista frontal, con los enemigos arriba y sus retratos, tu grupo abajo con sus retratos y barras, y la línea de turnos visible.
   - **Menú:** Atacar, Técnicas, Defender, Objeto, Cambiar y Abandonar.
   - **Se conserva:** duelos a muerte, heridas, capturas, experiencia, trofeos, efectos de golpe y música.
5. **Retirada del duelo antiguo** y tutorial nuevo.

## Fase 4 — Batallas campales con profundidad

**4A hecha** (`scripts/resources/campal_encounters.gd`, prueba `tests/campal_rpg_test.gd`): puntos 1, 2, 5 y botín. Los choques RPG son solo cuerpo a cuerpo; el tiro a distancia sigue con la fórmula del tablero. Los oficiales del grupo se marcan en el Consejo de guerra.

1. **Oficiales:** cada pelotón tiene un jefe y 2 o 3 oficiales, sacados del séquito o de personajes de la facción.
2. **Cada encuentro entre pelotones lanza un combate RPG:** el jefe y sus oficiales contra los del otro pelotón.
   - Las **tropas** dan estadísticas extra según su número, su familia y su moral.
   - Algunas técnicas **piden tropa o moral mínimas**.
   - El resultado se convierte en bajas, pérdida de moral o retirada.
   - Hay un botón **"Resolver"** para resolverlo automáticamente, y una opción para resolver solos los encuentros donde no estás tú ni tu séquito.
3. **IA más lista:** flanquea, protege a su general, concentra ataques, guarda reservas y se repliega para reagruparse. La dificultad será ajustable.
4. **Formaciones y flancos:** las unidades tienen orientación; atacar por el flanco o la espalda da ventaja. Habrá formaciones de Línea, Cuña y Cuadro.
5. **Traición en batalla:** un oficial o pelotón con lealtad muy baja puede pasarse al enemigo, usando `LoyaltyData.is_disloyal()`.
6. **Volver a equilibrar** con simulaciones (`tests/bal_sim.gd`).

## Al cerrar cada fase
- Pasar la prueba de la fase y unas pocas de regresión de `tests/`.
- Generar el `.exe`.
- Hacer commit y push.
- Trabajar en modo ahorro de tokens: agentes nuevos con instrucciones mínimas y una prueba compacta por tarea.
