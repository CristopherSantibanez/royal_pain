# Royal Pain — cómo continuar el trabajo en otro PC

Este documento resume dónde quedó el trabajo y cómo retomarlo, tanto para ti como para Claude.
**Al empezar en el PC nuevo, pídele a Claude: «Lee docs/CONTINUAR.md y docs/plan_revision.md y retomemos el plan».**

## 1. Preparar el PC nuevo

1. **Clonar el repositorio:**
   `git clone https://github.com/CristopherSantibanez/royal_pain` (ideal en `C:\otros`, la misma ruta que antes; así las rutas de las notas coinciden).
2. **Godot 4.7.2 estable (64 bits):**
   - **Editor:** descárgalo de godotengine.org y usa el `..._console.exe` para las pruebas.
   - **Plantillas de exportación:** son necesarias para generar el `.exe`. En el editor: *Editor → Administrar plantillas de exportación → Descargar e instalar*.
3. **Abrir el proyecto en el editor una vez** para que importe los recursos (crea la carpeta `.godot/`). Tarda unos minutos.
4. **Python 3** (solo para las herramientas de `tools/`):
   `pip install numpy soundfile pillow`.
   - `generate_music_extra.py` y `generate_sfx_extra.py` regeneran música y efectos.
   - `build_face_rects.py` regenera los recortes de cara.
5. **Claude Code** en esa carpeta.

### Opcional: llevar también la conversación con Claude
La conversación y la memoria de Claude están en `C:\Users\<usuario>\.claude\projects\c--otros\` (y el plan en `C:\Users\<usuario>\.claude\plans\`). Para conservarlas, copia esa carpeta al mismo sitio en el PC nuevo; solo funciona si el proyecto queda otra vez en `C:\otros`. Después, dentro de `C:\otros`, `claude --resume` muestra la sesión anterior. Si no la copias, basta con este documento y `docs/plan_revision.md`.

## 2. Estado actual

- **Hecho y subido a git:**
  - todas las rondas anteriores: viaje, roles, dinastía, prisioneros, hazañas, culturas, guerra, audio, sensación de golpe, interfaz con menos texto, No afiliado, Finta y duelo simplificado, retratos nuevos y 130 personajes por mundo;
  - **fase 1** del plan: registros acotados, reinos caídos sin perder personajes, tropa elegida respetada y fuera los mercenarios. Se conserva "Contratar Mercenarios" (tropas a sueldo para nobles).
- **Fase 2, en curso:**
  - **2A, hecha** y probada: varias esposas según rango, concubinas (sus hijos heredan solo sin legítimos adultos), **sin celos** por decisión del usuario, lealtad y traiciones (`LoyaltyData`), acciones y eventos de siervos y prisioneros.
  - **2C, hecha** y probada: viajeros en el mapa con su cara (`TravelerData`), encuentros, gestor «Mis personajes» en el menú.
  - **2B, hecha** y probada: eventos por cercanía, rivalidad, presencia de señores, eventos de facción e historias con efectos duraderos (`SocialEvents`). El evento "Celos" se mantiene por ahora; el usuario quiere quitarlo más adelante.
  - Glosario actualizado con todo lo de la fase 2.
- **Pendiente:** ver **`docs/PENDIENTE.md`**: repasos pequeños de la fase 2, fase 3 (gestor de grupo y combate RPG con árbol de habilidades y enemigos genéricos) y fase 4 (batallas campales). El detalle está en `docs/plan_revision.md`.
- **Imágenes de enemigos** (las genera el usuario): PNG de 1024×1536 con fondo transparente en `assets/portraits/enemies/<tipo>/`. La lista de tipos está en el plan, fase 3.

## 3. Cómo se trabaja (convenciones)

- **Pruebas:** están en `tests/` (scripts `SceneTree`). Se ejecutan así:
  `"<godot>_console.exe" --headless --path . --script tests/<nombre>.gd`
  - Muestran `FALLA` si algo falla.
  - Salir con código 139 después de la última línea es un cierre inesperado conocido de Godot y no importa.
  - Las pruebas visuales (`overflow_all.gd`, `duel_hover_probe.gd`, capturas) se ejecutan **sin** `--headless`.
  - Algunas guardan capturas en una ruta temporal del PC antiguo (constante `OUT`): cámbiala si la necesitas.
- **Lo que nunca hay que hacer:**
  - **Ejecutar el juego sin `--script` para probar:** con `--script`, los guardados van a `user://_pruebas/` y no tocan las partidas reales.
  - **Escribir Python con heredocs de bash:** rompen los `\n`. Hay que crear los `.py` con un editor o con las herramientas Write/Edit y ejecutarlos con `python -I`.
- **Eventos:** se encolan con `GameManager.queue_event(...)`, nunca escribiendo `pending_event`.
- **Ahorro de tokens (preferencia del usuario):**
  - trabajar por fases;
  - delegar en agentes nuevos con instrucciones mínimas, no en copias de la conversación;
  - una prueba compacta por tarea y pocas regresiones;
  - informes cortos.
- **Preferencias del usuario:**
  - preguntar con alternativas antes de decisiones de diseño;
  - interfaz con poco texto (explicaciones en el texto al pasar el ratón, el glosario y el tutorial);
  - textos en español con género correcto.
- **Exportar:** `--export-release "Windows Desktop" builds/windows/RoyalPain.exe` (la configuración está en `export_presets.cfg`; `builds/` no se sube a git).
- **Retratos nuevos:** importarlos con compresión VRAM de alta calidad (`compress/mode=2`, `high_quality=true` en su `.import`) y ejecutar `python tools/build_face_rects.py`. Si no, el juego calcula la cara solo (`face_detector.gd`).
