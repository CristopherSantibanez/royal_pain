extends Control
# Combate RPG con vista frontal: enemigos arriba (retratos grandes), tu grupo abajo (caras, PV y PT),
# línea de turnos arriba y menú de órdenes del que actúa. La lógica es RpgBattleManager; el desenlace
# de campaña (honor, experiencia, capturas, muerte, torneo, práctica…) lo aplica FightResults.
#
# Entradas: CombatSetup (duelo de honor 1v1, combate de grupo, torneo, práctica) o, incrustada en una
# batalla campal, player_character + enemy_character + embedded = true (emite embedded_finished).

signal embedded_finished(winner: Character)

const UniqueItems = preload("res://scripts/resources/unique_items.gd")
const LOG_HEIGHT := 58.0
const TURN_DELAY := 0.75
const TIMELINE_N := 8
const ENEMY_MAX := 5
const PARTY_MAX := 4
const ENEMY_CARD_W := 168
const PARTY_CARD_W := 172
const KO_SLOW_MO := 0.5
const SIDE_COLORS := [Color("5b8fd0"), Color("c9584c")]
const CARD_BORDER := Color("4a3a24")
const ACTING_BORDER := Color("f0d48a")
const TARGET_BORDER := Color("ff7a5a")
const ALLY_TARGET_BORDER := Color("8ee08a")
const HP_COLOR := Color("b0392d")
const PT_COLOR := Color("3f78a8")
const TO_DEATH_COLOR := Color("e0503c")
const WEAK_COLOR := Color("ffd25a")
const RESIST_COLOR := Color("9fb4c8")
const TGT_NAMES := {"enemy": "1 enemigo", "enemies": "todos", "random3": "al azar", "ally": "1 aliado",
	"allies": "aliados", "self": "tú", "ko_ally": "caído"}

## Pruebas: la IA juega también por ti y las ventanas previas se saltan; retardo entre turnos.
static var test_auto := false
static var test_delay := -1.0

var player_character: Character
var enemy_character: Character
var side_a: Array = []        # bandos a medida (tutorial, pruebas); vacíos = los de CombatSetup
var side_b: Array = []
var embedded := false
var title_text := ""

var mgr: RpgBattleManager
var results: FightResults
var is_campaign := false
var group := false
var _owner: Character
var _champion: Character
var _practice := false
var _cards := {}              # Fighter -> {root, style, portrait, name, hp, hp_label, pt, pt_label, status, tag}
var _acting = null            # Fighter al que el jugador da órdenes
var _targeting := {}          # {action, targets, idx, dt, fx}
var _last_target = null
var _menu := ""               # "main", "tech", "swap", "abandon", "target"
var _busy := false
var _ended := false
var _pending_next_round := false
var _embedded_winner: Character
var last_result := {}          # resultado completo (choques de las campales)
var _log_text := ""
var _keys := {}               # keycode -> Callable

var background: TextureRect
var screen: MarginContainer
var title_label: Label
var round_label: Label
var timeline_box: HBoxContainer
var btn_back: Button
var enemy_row: HBoxContainer
var party_row: HBoxContainer
var log_label: Label
var log_panel: PanelContainer
var actor_label: Label
var hint_label: Label
var cmd_box: VBoxContainer

func _ready() -> void:
	_build_ui()
	if player_character == null:
		player_character = CombatSetup.player_character if CombatSetup.player_character != null \
			else CharacterLoader.make_test_character("Sir Alaric", Character.Role.CABALLERO)
	if enemy_character == null:
		enemy_character = CombatSetup.enemy_character if CombatSetup.enemy_character != null \
			else CharacterLoader.make_test_character("Bandido Renco", Character.Role.SOLDADO)
	_owner = player_character
	is_campaign = CombatSetup.is_campaign and not embedded
	group = is_campaign and CombatSetup.group_fight and side_a.is_empty()
	_practice = is_campaign and RelationsData.is_practice() and enemy_character.full_name() == RelationsData.practice_partner
	if CombatSetup.duel_to_death and is_campaign and not test_auto:
		await _warn_to_death()
	# Duelo de honor en campaña (no torneo, práctica ni grupo): un campeón del séquito puede batirse por ti.
	if is_campaign and not group and not CombatSetup.is_tournament() and GameManager.is_game_active and not _practice and not test_auto:
		var champions: Array[Character] = RelationsData.duel_champions()
		if not champions.is_empty():
			var chosen: Character = await _ask_champion(champions)
			if chosen != _owner:
				_champion = chosen
				_champion.set_meta("champion", true)
				player_character = chosen
	_begin()

func _exit_tree() -> void:
	Engine.time_scale = 1.0   # por si se sale durante una pausa de impacto

func _delay() -> float:
	return test_delay if test_delay >= 0.0 else TURN_DELAY

# --- Montaje ---

func _begin() -> void:
	var a: Array = side_a.duplicate()
	if a.is_empty():
		if group:
			a = Array(PartyData.active())
			if not player_character in a:
				a.push_front(player_character)
			for r in PartyData.reserve():
				if not r in a:
					a.append(r)
		else:
			a = [player_character]
	var b: Array = side_b.duplicate()
	if b.is_empty():
		b = Array(CombatSetup.enemy_party) if group and not CombatSetup.enemy_party.is_empty() else [enemy_character]
	if not enemy_character in b:
		enemy_character = b[0]
	mgr = RpgBattleManager.new()
	# Bolsa de consumibles del grupo (la del jugador); en práctica se gasta una copia.
	var keeper: Character = _owner if _owner != null else player_character
	var bag: Dictionary = {} if keeper == null else (keeper.consumables.duplicate() if _practice else keeper.consumables)
	var opts := {"to_the_death": CombatSetup.duel_to_death and is_campaign and not _practice, "can_flee": true,
		"bag": bag, "enemy_bag": ConsumableCatalog.enemy_bag()}
	if is_campaign and not _practice:
		opts["loot_hook"] = func(r: Dictionary) -> void: ConsumableCatalog.grant_loot(bag, r)
	mgr.setup(a, b, opts)
	FightResults.apply_start_health(mgr)
	results = FightResults.new(_owner, player_character, enemy_character)
	results.champion = _champion
	results.companions = a.filter(func(c: Character) -> bool: return c != player_character)
	if _practice:
		results.snapshot_practice([player_character, enemy_character])
	mgr.log_line.connect(_log)
	_log("¡Comienza el combate!")
	mgr.battle_ended.connect(_on_battle_ended)
	mgr.fighter_down.connect(_on_fighter_down)
	for f in mgr.fighters:
		var card := _make_card(f, f.side == 1)
		(enemy_row if f.side == 1 else party_row).add_child(card.root)
		_cards[f] = card
	_pick_background()
	_set_title()
	if not embedded:
		Music.play_context("battle" if a.size() + b.size() > 2 else "duel")
	btn_back.disabled = true
	btn_back.text = "Volver a la batalla" if embedded else _return_text()
	btn_back.tooltip_text = "Termina el combate (o abandona) para volver."
	_refresh()
	_advance()

func _return_text() -> String:
	if not is_campaign:
		return "Volver al menú"
	if CombatSetup.return_scene.ends_with("map.tscn"):
		return "Volver al Mapa"
	if CombatSetup.return_scene.ends_with("relations.tscn"):
		return "Volver a Relaciones"
	return "Volver al Castillo"

func _set_title() -> void:
	var t := title_text
	if t.is_empty():
		if embedded:
			t = "Duelo singular"
		elif CombatSetup.is_tournament():
			t = "Torneo · ronda %d de %d" % [CombatSetup.tournament_round, CombatSetup.tournament_opponents.size()]
		elif _practice:
			t = "Práctica · sin heridas"
		elif group:
			t = str(CombatSetup.pending_outcome.get("title", "Combate"))
		else:
			t = "Duelo de honor"
	if mgr.to_the_death:
		t = "☠ " + t + " · a muerte"
		title_label.add_theme_color_override("font_color", TO_DEATH_COLOR)
	title_label.text = t
	title_label.tooltip_text = t

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background = TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.01, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	screen = MarginContainer.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		screen.add_theme_constant_override("margin_" + side, 12)
	for side in ["top", "bottom"]:
		screen.add_theme_constant_override("margin_" + side, 8)
	add_child(screen)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	screen.add_child(root)
	# Barra superior: título, línea de turnos, ronda y volver.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.custom_minimum_size.y = 40
	root.add_child(top)
	title_label = Label.new()
	title_label.theme_type_variation = &"HeaderLabel"
	title_label.custom_minimum_size.x = 160
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(title_label)
	var tl := Label.new()
	tl.text = "Turnos"
	tl.theme_type_variation = &"MutedLabel"
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(tl)
	timeline_box = HBoxContainer.new()
	timeline_box.add_theme_constant_override("separation", 4)
	timeline_box.tooltip_text = "Próximos turnos: el más ágil actúa antes."
	top.add_child(timeline_box)
	round_label = Label.new()
	round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	round_label.custom_minimum_size.x = 64
	round_label.add_theme_font_size_override("font_size", 13)
	top.add_child(round_label)
	btn_back = Button.new()
	btn_back.add_theme_font_size_override("font_size", 13)
	btn_back.pressed.connect(_on_back_pressed)
	top.add_child(btn_back)
	# Enemigos.
	enemy_row = HBoxContainer.new()
	enemy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_row.add_theme_constant_override("separation", 10)
	enemy_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(enemy_row)
	# Registro de alto fijo.
	log_panel = PanelContainer.new()
	root.add_child(log_panel)
	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_font_size_override("font_size", 13)
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_panel.add_child(log_label)
	LogView.wrap(log_label, LOG_HEIGHT)
	# Abajo: tu grupo y el menú de órdenes.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	bottom.custom_minimum_size.y = 206
	root.add_child(bottom)
	party_row = HBoxContainer.new()
	party_row.add_theme_constant_override("separation", 8)
	party_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(party_row)
	var cmd_panel := PanelContainer.new()
	cmd_panel.custom_minimum_size.x = 340
	bottom.add_child(cmd_panel)
	var cmd_col := VBoxContainer.new()
	cmd_col.add_theme_constant_override("separation", 4)
	cmd_panel.add_child(cmd_col)
	actor_label = Label.new()
	actor_label.clip_text = true
	actor_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	actor_label.add_theme_color_override("font_color", ACTING_BORDER)
	cmd_col.add_child(actor_label)
	hint_label = Label.new()
	hint_label.theme_type_variation = &"MutedLabel"
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.max_lines_visible = 2
	hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint_label.custom_minimum_size = Vector2(320, 34)
	cmd_col.add_child(hint_label)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cmd_col.add_child(scroll)
	cmd_box = VBoxContainer.new()
	cmd_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_box.add_theme_constant_override("separation", 3)
	scroll.add_child(cmd_box)

func _bar(parent: Node, color: Color) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.custom_minimum_size.x = 52
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	return [bar, lbl]

func _small_label(parent: Node, size: int = 12) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _make_card(f, enemy: bool) -> Dictionary:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.045, 0.03, 0.85)
	style.border_color = CARD_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(5)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.gui_input.connect(_on_card_input.bind(f))
	panel.mouse_entered.connect(_on_card_hover.bind(f))
	panel.tooltip_text = "%s · Nv %d\nArma: %s · Armadura: %s%s" % [f.c.full_name(), f.c.level,
		RpgStats.DAMAGE_NAMES[int(f.s.weapon)], RpgStats.ARMOR_NAMES[int(f.s.armor)], " + escudo" if f.s.shield else ""]
	var d := {"root": panel, "style": style}
	var tag := Label.new()
	tag.add_theme_font_size_override("font_size", 15)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 5)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.tag = tag
	if enemy:
		panel.custom_minimum_size.x = ENEMY_CARD_W
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(box)
		var tex := TextureRect.new()
		tex.texture = f.c.get_portrait()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED   # figura completa, sin recortar cabeza ni pies
		tex.custom_minimum_size = Vector2(ENEMY_CARD_W - 10, 196)
		tex.clip_contents = true
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tex)
		tex.add_child(tag)
		tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		d.portrait = tex
		d.name = _small_label(box, 13)
		var hp := _bar(box, HP_COLOR)
		d.hp = hp[0]
		d.hp_label = hp[1]
		d.status = _small_label(box, 11)
	else:
		panel.custom_minimum_size.x = PARTY_CARD_W
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(row)
		var face := _upper_body(f.c)
		row.add_child(face)
		face.add_child(tag)
		tag.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		d.portrait = face
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(info)
		d.name = _small_label(info, 13)
		d.name.custom_minimum_size.x = 80
		d.level = _small_label(info, 11)
		var hp := _bar(col, HP_COLOR)
		d.hp = hp[0]
		d.hp_label = hp[1]
		var pt := _bar(col, PT_COLOR)
		d.pt = pt[0]
		d.pt_label = pt[1]
		d.status = _small_label(col, 11)
	return d

const PARTY_PORTRAIT_SIZE := Vector2(84, 84)
const UPPER_BODY_WIDTH := 2.4    # ancho del recorte en «caras» (hombros incluidos)
const UPPER_BODY_HEIGHT := 2.6   # alto: de la coronilla a la cintura
const UPPER_BODY_TOP := 0.15     # margen sobre la cabeza

# Mitad superior del cuerpo (cabeza y torso) para las tarjetas del grupo: se recorta alrededor
# de la cara del retrato (Character.get_face) para que la figura llene el marco.
func _upper_body(c: Character) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = PARTY_PORTRAIT_SIZE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := c.get_portrait()
	if tex == null:
		return rect
	var face := c.get_face() as AtlasTexture
	var region := Rect2(0, 0, tex.get_width(), tex.get_height() * 0.5)
	if face != null and face.region.size.x > 0:
		var side := face.region.size.x
		var w := minf(tex.get_width(), side * UPPER_BODY_WIDTH)
		var h := minf(tex.get_height(), side * UPPER_BODY_HEIGHT)
		var cx := face.region.position.x + side * 0.5
		var x := clampf(cx - w * 0.5, 0.0, tex.get_width() - w)
		var y := clampf(face.region.position.y - side * UPPER_BODY_TOP, 0.0, tex.get_height() - h)
		region = Rect2(x, y, w, h)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = region
	rect.texture = atlas
	return rect

func _pick_background() -> void:
	var path := "res://assets/TurnFight-Trining_Ground.png"
	if is_campaign and not CombatSetup.is_tournament() and GameManager.current_castle != null:
		match GameManager.current_castle.kingdom:
			KingdomEnums.Kingdom.HIELO, KingdomEnums.Kingdom.CUMBRES, KingdomEnums.Kingdom.GRIS:
				path = "res://assets/TurnFight-Snow.png"
			KingdomEnums.Kingdom.DESIERTO, KingdomEnums.Kingdom.AMBAR, KingdomEnums.Kingdom.DORADO:
				path = "res://assets/TurnFight-Desert.png"
			KingdomEnums.Kingdom.AZUL, KingdomEnums.Kingdom.NEUTRAL:
				path = "res://assets/TurnFight-Seaside.png"
			_:
				path = "res://assets/TurnFight-Meadow.png"
	if ResourceLoader.exists(path):
		background.texture = load(path)

# --- Pintar el estado ---

func _status_short(f) -> String:
	var names := []
	for k in f.statuses:
		names.append(RpgBattleManager.STATUS_NAMES.get(k, k))
	return " · ".join(names)

func _shown(side: int, cap: int) -> Array:
	var list: Array = mgr.side_fighters(side)
	var up_active := list.filter(func(f) -> bool: return f.active and f.up())
	var res := list.filter(func(f) -> bool: return not f.active and f.up()) if side == 1 else []
	var fallen := list.filter(func(f) -> bool: return not f.up() and f.participated)
	return (up_active + res + fallen).slice(0, cap)

func _refresh() -> void:
	if mgr == null:
		return
	for side in 2:
		var shown := _shown(side, ENEMY_MAX if side == 1 else PARTY_MAX)
		var row := enemy_row if side == 1 else party_row
		for f in mgr.side_fighters(side):
			_cards[f].root.visible = f in shown
		for i in shown.size():
			row.move_child(_cards[shown[i]].root, i)
	for f in mgr.fighters:
		var d: Dictionary = _cards[f]
		d.name.text = f.c.full_name()
		d.hp.max_value = f.max_hp
		d.hp.value = f.hp
		d.hp_label.text = "%d/%d" % [f.hp, f.max_hp]
		if d.has("pt"):
			d.pt.max_value = maxi(1, f.max_pt)
			d.pt.value = f.pt
			d.pt_label.text = "%d PT" % f.pt
			d.level.text = "Nv %d · %s" % [f.c.level, RpgStats.DAMAGE_NAMES[int(f.s.weapon)]]
		var st := _status_short(f)
		if not f.up():
			st = "Muerto" if f.dead else "Fuera de combate"
		elif f.side == 1 and not f.active:
			st = "En reserva"
		d.status.text = st
		d.status.tooltip_text = st
		d.root.modulate = Color(0.45, 0.45, 0.45) if not f.up() else (Color(0.75, 0.75, 0.75) if not f.active else Color.WHITE)
		var border := CARD_BORDER
		if mgr.current == f:
			border = ACTING_BORDER
		d.style.border_color = border
		if _targeting.is_empty() or not f in _targeting.targets:
			d.tag.text = ""
	if not _targeting.is_empty():
		_mark_targets()
	for ch in timeline_box.get_children():
		ch.queue_free()
	for f in mgr.timeline(TIMELINE_N):
		var icon := FaceIcon.make(f.c, 32, SIDE_COLORS[f.side], false)
		icon.tooltip_text = f.c.full_name()
		timeline_box.add_child(icon)
	round_label.text = "Ronda %d" % mgr.round_num
	_update_music()

func _update_music() -> void:
	if embedded:
		return
	var lowest := 1.0
	for f in mgr.fighters:
		if f.active and f.up():
			lowest = minf(lowest, f.hp_ratio())
	Music.set_intensity(smoothstep(0.75, 0.3, lowest))

func _log(text: String) -> void:
	_log_text = text if _log_text.is_empty() else _log_text + "\n" + text
	_log_text = LogView.cap(_log_text)
	LogView.show(log_label, _log_text)

# --- Turnos ---

func _hp_snapshot() -> Dictionary:
	var out := {}
	for f in mgr.fighters:
		out[f] = f.hp
	return out

func _advance() -> void:
	if _busy:
		return
	_busy = true
	while not mgr.ended:
		var before := _hp_snapshot()
		var f = mgr.next_turn()
		_float_diffs(before, {})
		_refresh()
		if f == null:
			break
		if f.side == 0 and not test_auto:
			_acting = f
			_show_main_menu()
			_busy = false
			return
		_clear_menu()
		actor_label.text = "Turno de %s" % f.c.full_name()
		hint_label.text = ""
		await get_tree().create_timer(_delay()).timeout
		if not is_inside_tree() or mgr.ended:
			break
		_perform(f, mgr.ai_choose(f))
		await get_tree().create_timer(_delay() * 0.5).timeout
		if not is_inside_tree():
			return
	_busy = false

func _perform(f, action: Dictionary) -> void:
	var before := _hp_snapshot()
	var info := mgr.act(f, action)
	if not is_inside_tree():
		return
	_play_fx(info, before)
	_refresh()

func _player_do(action: Dictionary) -> void:
	if _acting == null or mgr.ended or _busy:
		return
	var f = _acting
	_acting = null
	_targeting = {}
	_clear_menu()
	_perform(f, action)
	if mgr.ended:
		return
	_busy = true
	await get_tree().create_timer(_delay() * 0.5).timeout
	_busy = false
	if is_inside_tree():
		_advance()

# --- Menú de órdenes ---

func _clear_menu() -> void:
	_keys.clear()
	for ch in cmd_box.get_children():
		cmd_box.remove_child(ch)
		ch.queue_free()

func _cmd(parent: Node, text: String, key: Key, tip: String, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.disabled = disabled
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	b.focus_entered.connect(func(): hint_label.text = tip)
	b.mouse_entered.connect(func(): hint_label.text = tip)
	parent.add_child(b)
	if key != KEY_NONE and not disabled:
		_keys[key] = cb
	return b

func _show_main_menu() -> void:
	_menu = "main"
	_clear_menu()
	var f = _acting
	actor_label.text = "Turno de %s" % f.c.full_name()
	hint_label.text = "Elige una orden."
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_box.add_child(grid)
	var dt := int(f.s.weapon)
	var first := _cmd(grid, "Atacar (A)", KEY_A, "Golpe con el arma (%s). Recupera PT." % RpgStats.DAMAGE_NAMES[dt],
		func(): _choose_target({"type": "atacar"}, mgr.active_of(1), dt, {}))
	var techs: Array = mgr.techniques_of(f)
	_cmd(grid, "Técnicas (T)", KEY_T, "%d técnicas · %d PT" % [techs.size(), f.pt], _show_techniques, techs.is_empty())
	_cmd(grid, "Defender (D)", KEY_D, "Menos daño hasta tu turno y recuperas PT.", func(): _player_do({"type": "defender"}))
	var no_items: bool = mgr.bags[0].is_empty()
	_cmd(grid, "Objeto (O)", KEY_O, "No llevas objetos." if no_items else "Usa un objeto (gasta el turno).", _show_items, no_items)
	_cmd(grid, "Cambiar (C)", KEY_C, "Entra alguien de la reserva (gasta el turno)." if not mgr.reserve_of(0).is_empty() else "No hay nadie en la reserva.",
		_show_swap, mgr.reserve_of(0).is_empty())
	_cmd(grid, "Abandonar (R)", KEY_R, "Rendirse o retirarse.", _show_abandon)
	first.grab_focus.call_deferred()

func _back_button() -> void:
	var b := _cmd(cmd_box, "◂ Volver", KEY_NONE, "Volver a las órdenes (Esc).", _show_main_menu)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER

func _aff_hint(f, t, dt: int, fx: Dictionary) -> String:
	if t == null or t.side == f.side or dt < 0:   # dt < 0: objeto, sin afinidad
		return ""
	match mgr.affinity_of(f, t, dt, fx):
		RpgStats.Affinity.DEBIL:
			return "Débil"
		RpgStats.Affinity.RESISTE:
			return "Resiste"
	return ""

func _ref_target(f):
	var foes: Array = mgr.active_of(1 - f.side)
	if _last_target != null and _last_target in foes:
		return _last_target
	return foes[0] if not foes.is_empty() else null

func _show_techniques() -> void:
	_menu = "tech"
	_clear_menu()
	var f = _acting
	actor_label.text = "Técnicas · %d PT" % f.pt
	var first: Button = null
	for n: Dictionary in mgr.techniques_of(f):
		var dt := int(n.get("dt", -1))
		if dt < 0:
			dt = int(f.s.weapon)
		var pow := float(n.get("pow", 0.0))
		var fx: Dictionary = n.get("fx", {})
		var tgt: String = n.get("tgt", "enemy")
		var text := "%s · %d PT · %s" % [n.name, int(n.get("pt", 0)), TGT_NAMES.get(tgt, tgt)]
		if pow > 0.0:
			text += " · " + RpgStats.DAMAGE_NAMES[dt]
		var tip: String = n.get("desc", "")
		if pow > 0.0 and tgt in ["enemy", "enemies", "random3"]:
			var ref = _ref_target(f)
			var hint := _aff_hint(f, ref, dt, fx)
			if not hint.is_empty():
				tip += " %s ante %s." % [hint, ref.c.full_name()]
		var ok: bool = f.pt >= int(n.get("pt", 0)) and not mgr.valid_targets(f, n).is_empty()
		var id: String = n.id
		var cb := func():
			if tgt in ["enemy", "ally", "ko_ally"]:
				_choose_target({"type": "tecnica", "node": id}, mgr.valid_targets(f, n), dt, fx)
			else:
				_player_do({"type": "tecnica", "node": id})
		var b := _cmd(cmd_box, text, KEY_NONE, tip, cb, not ok)
		if ok and first == null:
			first = b
	_back_button()
	if first != null:
		first.grab_focus.call_deferred()
	else:
		cmd_box.get_child(cmd_box.get_child_count() - 1).grab_focus.call_deferred()

func _show_swap() -> void:
	_menu = "swap"
	_clear_menu()
	var f = _acting
	actor_label.text = "Cambiar a %s por…" % f.c.first_name
	var first: Button = null
	for r in mgr.reserve_of(0):
		var b := _cmd(cmd_box, "%s · PV %d/%d" % [r.c.full_name(), r.hp, r.max_hp], KEY_NONE, "Entra al combate y %s pasa a la reserva." % f.c.first_name,
			func(): _player_do({"type": "cambiar", "out": f, "reserve": r}))
		if first == null:
			first = b
	_back_button()
	if first != null:
		first.grab_focus.call_deferred()

func _show_items() -> void:
	_menu = "items"
	_clear_menu()
	var f = _acting
	actor_label.text = "Objetos"
	var first: Button = null
	for id in mgr.bags[0].keys():
		var it := ConsumableCatalog.item(id)
		var tgt := str(it.get("tgt", "ally"))
		var text := "%s ×%d · %s" % [it.name, ConsumableCatalog.count(mgr.bags[0], id), TGT_NAMES.get(tgt, tgt)]
		var item_id: String = id
		var cb := func():
			if tgt == "allies":
				_player_do({"type": "objeto", "item": item_id, "target": f})
			else:
				_choose_target({"type": "objeto", "item": item_id}, ConsumableCatalog.targets(mgr, f, item_id), -1, {})
		var b := _cmd(cmd_box, text, KEY_NONE, str(it.desc), cb)
		if first == null:
			first = b
	_back_button()
	if first != null:
		first.grab_focus.call_deferred()

func _show_abandon() -> void:
	_menu = "abandon"
	_clear_menu()
	actor_label.text = "Abandonar"
	var flee := _cmd(cmd_box, "Retirarse", KEY_NONE, "Huir: puede fallar y cuesta honor." if mgr.can_flee else "No hay escapatoria.",
		func(): _player_do({"type": "abandonar", "mode": "retirarse"}), not mgr.can_flee)
	_cmd(cmd_box, "Rendirse", KEY_NONE, "Derrota segura: más honor y un rescate, pero sin caer herido." if not mgr.to_the_death else "En una lucha a muerte no hay rendición.",
		func(): _player_do({"type": "abandonar", "mode": "rendirse"}), mgr.to_the_death)
	_back_button()
	var focus: Control = flee if mgr.can_flee else cmd_box.get_child(cmd_box.get_child_count() - 1)
	focus.grab_focus.call_deferred()

# --- Elegir objetivo (teclado, mando o ratón) ---

func _choose_target(action: Dictionary, targets: Array, dt: int, fx: Dictionary) -> void:
	if targets.is_empty() or _acting == null:
		return
	_menu = "target"
	var idx := targets.find(_last_target)
	_targeting = {"action": action, "targets": targets, "idx": maxi(0, idx), "dt": dt, "fx": fx}
	_clear_menu()
	var b := _cmd(cmd_box, "◂ Volver", KEY_NONE, "Volver a las órdenes (Esc).", _cancel_target)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	get_viewport().gui_release_focus()
	actor_label.text = "Elige objetivo"
	_mark_targets()

func _mark_targets() -> void:
	var targets: Array = _targeting.targets
	var cur = targets[_targeting.idx]
	for t in targets:
		var d: Dictionary = _cards[t]
		var ally: bool = t.side == 0
		d.style.border_color = (ALLY_TARGET_BORDER if ally else TARGET_BORDER) if t == cur else d.style.border_color
		var hint := _aff_hint(_acting, t, _targeting.dt, _targeting.fx) if _acting != null else ""
		d.tag.text = ("▼ " + hint) if t == cur else hint
		d.tag.add_theme_color_override("font_color", WEAK_COLOR if hint == "Débil" else (RESIST_COLOR if hint == "Resiste" else Color.WHITE))
	var h := _aff_hint(_acting, cur, _targeting.dt, _targeting.fx) if _acting != null else ""
	hint_label.text = "%s%s · ←/→ cambia, Aceptar confirma." % [cur.c.full_name(), (": " + h + (" (×1,4)" if h == "Débil" else " (×0,6)")) if not h.is_empty() else ""]

func _cycle_target(step: int) -> void:
	var n: int = _targeting.targets.size()
	_targeting.idx = (int(_targeting.idx) + step + n) % n
	_refresh()

func _confirm_target() -> void:
	var t = _targeting.targets[_targeting.idx]
	var action: Dictionary = _targeting.action.duplicate()
	action["target"] = t
	if t.side == 1:
		_last_target = t
	_targeting = {}
	_player_do(action)

func _cancel_target() -> void:
	_targeting = {}
	_refresh()
	_show_main_menu()

func _on_card_input(event: InputEvent, f) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _targeting.is_empty() and f in _targeting.targets:
			_targeting.idx = _targeting.targets.find(f)
			_confirm_target()

func _on_card_hover(f) -> void:
	if not _targeting.is_empty() and f in _targeting.targets:
		_targeting.idx = _targeting.targets.find(f)
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if _ended or _acting == null:
		return
	if not _targeting.is_empty():
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
			_cycle_target(-1)
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
			_cycle_target(1)
		elif event.is_action_pressed("ui_accept"):
			_confirm_target()
		elif event.is_action_pressed("ui_cancel"):
			_cancel_target()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and _menu != "main":
		_show_main_menu()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and _menu == "main" and _keys.has(key.keycode):
		get_viewport().set_input_as_handled()
		_keys[key.keycode].call()

# --- Sensación de golpe ---

func _center(f) -> Vector2:
	return (_cards[f].portrait as Control).get_global_rect().get_center()

func _float(f, text: String, color: Color, size: int = 28) -> void:
	if _cards[f].root.visible:
		CombatFx.floating_text(self, _center(f), text, color, size)

func _impact(f, tier: int) -> void:
	var p: Control = _cards[f].portrait
	CombatFx.flash(p)
	CombatFx.squash(p, 0.05 + CombatFx.TIER_SHAKE[tier] * 0.005)
	CombatFx.sparks(self, _center(f) - global_position, Color(1.0, 0.85, 0.4), 16 + tier * 16)
	CombatFx.shake(screen, CombatFx.TIER_SHAKE[tier], 0.25)
	CombatFx.hit_stop(get_tree(), CombatFx.TIER_HIT_STOP[tier])

func _play_fx(info: Dictionary, before: Dictionary) -> void:
	var actor = info.actor
	var covered := {}
	if info.type in ["atacar", "tecnica"] and not info.hits.is_empty() and _cards[actor].root.visible:
		CombatFx.lunge(_cards[actor].portrait, Vector2.DOWN if actor.side == 1 else Vector2.UP, 22.0)
	for h: Dictionary in info.hits:
		var t = h.target
		covered[t] = true
		if not h.hit:
			Sfx.play("whoosh")
			_float(t, "Falla", CombatFx.MISS_COLOR, 26)
			continue
		var tier := mini(CombatFx.tier_for(int(h.dmg)) + (2 if h.crit else 0), CombatFx.Tier.BIG)
		if h.crit:
			Sfx.play("crit")
		else:
			Sfx.play("clash", -6.0)
			Sfx.play("hit")
		if _cards[t].root.visible:
			_impact(t, tier)
		var text := "-%d" % int(h.dmg)
		var color := CombatFx.CRIT_COLOR if h.crit else CombatFx.DAMAGE_COLOR
		if h.crit:
			text = "¡Crítico! " + text
		match int(h.aff):
			RpgStats.Affinity.DEBIL:
				text += " ¡Débil!"
				color = WEAK_COLOR
			RpgStats.Affinity.RESISTE:
				text += " Resiste"
		_float(t, text, color, 28 + tier * 6)
	match str(info.type):
		"defender":
			Sfx.play("guard")
			CombatFx.flash(_cards[actor].portrait, Color(0.7, 0.9, 1.6), 0.4)
			_float(actor, "En guardia", CombatFx.INFO_COLOR, 22)
		"cambiar":
			Sfx.play("whoosh", -4.0)
		"abandonar":
			if not mgr.ended:
				Sfx.play("guard", -4.0)
				_float(actor, "¡No lo logra!", CombatFx.MISS_COLOR, 24)
	if info.get("extra", false):
		Sfx.stinger("crit", -8.0, 0.5)
		CombatFx.banner(self, "★ ¡Aprovecha la brecha!", CombatFx.CRIT_COLOR, 28, 0.6, log_panel.get_global_rect())
	_float_diffs(before, covered)

## PV que cambian sin un golpe visible (sangrado, respuestas, curas): número flotante.
func _float_diffs(before: Dictionary, covered: Dictionary) -> void:
	for f in mgr.fighters:
		var d: int = f.hp - int(before.get(f, f.hp))
		if d == 0 or (d < 0 and covered.has(f)):
			continue
		_float(f, ("+%d" % d) if d > 0 else ("-%d" % -d), CombatFx.INFO_COLOR if d > 0 else CombatFx.DAMAGE_COLOR, 24)

func _on_fighter_down(f) -> void:
	_float(f, "Muere" if f.dead else "Cae", CombatFx.MISS_COLOR, 30)

# --- Final ---

func _on_battle_ended(result: Dictionary) -> void:
	_ended = true
	last_result = result
	_acting = null
	_targeting = {}
	_clear_menu()
	FightResults.sync_health(mgr)
	var fled := int(result.get("retreated", -1)) >= 0
	var won := int(result.get("winner", -1)) == 0 and not fled
	actor_label.text = "¡Victoria!" if won else ("Huida" if fled else "Derrota")
	hint_label.text = ""
	var text := ""
	if embedded:
		_embedded_winner = results.finish_embedded(result)
	elif is_campaign and _practice:
		text = results.finish_practice(result)
	elif is_campaign:
		var out: Dictionary = results.finish_campaign(result)
		text = out.text
		if out.next_round:
			_pending_next_round = true
			btn_back.text = "Siguiente ronda (%d/%d)" % [CombatSetup.tournament_round + 1, CombatSetup.tournament_opponents.size()]
		elif out.death_owner:
			btn_back.text = "Volver al Mapa"
		if out.trophy:
			_offer_trophy.call_deferred()
	for l in results.log_lines:
		_log(l)
	if not text.is_empty():
		_log(text)
		hint_label.text = text
		hint_label.tooltip_text = text
	_refresh()
	btn_back.disabled = false
	btn_back.tooltip_text = ""
	btn_back.grab_focus.call_deferred()
	_play_end_sound(won, fled)

func _play_end_sound(won: bool, fled: bool) -> void:
	if fled:
		Sfx.play("whoosh")
		return
	CombatFx.slow_mo(get_tree(), KO_SLOW_MO)
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	Sfx.stinger("victory" if won else "defeat", 0.0, 2.5)
	CombatFx.banner(self, "¡Victoria!" if won else "Derrota", CombatFx.CRIT_COLOR if won else CombatFx.DAMAGE_COLOR, 46, 1.2, log_panel.get_global_rect())

func _on_back_pressed() -> void:
	if not _ended:
		return
	if embedded:
		embedded_finished.emit(_embedded_winner)
		return
	if _pending_next_round:
		CombatSetup.advance_tournament_round()
		get_tree().change_scene_to_file(CombatSetup.RPG_SCENE)
		return
	if is_campaign:
		var scene := CombatSetup.return_scene
		CombatSetup.clear()
		get_tree().change_scene_to_file(scene)
		return
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

# --- Ventanas previas y trofeo ---

func _overlay(alpha: float = 0.65, tint := Color(0, 0, 0)) -> Array:
	var overlay := ColorRect.new()
	overlay.color = Color(tint.r, tint.g, tint.b, alpha)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 70
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return [overlay, box]

func _note(box: Node, text: String) -> void:
	var note := Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(520, 0)
	box.add_child(note)

func _warn_to_death() -> void:
	var o := _overlay(0.75, Color(0.08, 0, 0))
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "☠ A MUERTE contra %s" % enemy_character.full_name()
	title.add_theme_color_override("font_color", TO_DEATH_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	o[1].add_child(title)
	_note(o[1], "Quien caiga, muere. Si caes tú, te sucede tu heredero. Puedes intentar retirarte, a costa de tu honor.")
	var btn := Button.new()
	btn.text = "Desenvainar"
	btn.theme_type_variation = &"PrimaryButton"
	o[1].add_child(btn)
	btn.grab_focus.call_deferred()
	Sfx.play("guard", -4.0)
	await btn.pressed
	o[0].queue_free()

func _ask_champion(champions: Array[Character]) -> Character:
	var o := _overlay()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "¿Quién se bate contra %s?" % enemy_character.full_name()
	o[1].add_child(title)
	_note(o[1], "Un campeón puede luchar por ti: si vence, ganas honor y fama; las heridas son suyas.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	o[1].add_child(row)
	var result := [null]
	var candidates: Array[Character] = [_owner]
	candidates.append_array(champions)
	var preferred: Character = champions[0] if RelationsData.is_designated_champion(champions[0]) else _owner
	for c: Character in candidates:
		var card := VBoxContainer.new()
		card.add_child(FaceIcon.make(c, 110, Color("d4af5a") if c == preferred else FaceIcon.FRAME_COLOR))
		var btn := Button.new()
		btn.text = "Yo mismo" if c == _owner else (c.first_name + (" (campeón)" if c == preferred else ""))
		btn.tooltip_text = "%s · Nv %d · Vida %d/%d" % [c.full_name(), c.level, c.current_health, c.max_health]
		btn.theme_type_variation = &"PrimaryButton" if c == preferred else &""
		btn.pressed.connect(func(): result[0] = c)
		card.add_child(btn)
		row.add_child(card)
		if c == preferred:
			btn.grab_focus.call_deferred()
	while result[0] == null:
		await get_tree().process_frame
	o[0].queue_free()
	return result[0]

## Trofeo: si el vencido lleva una pieza única, el jugador puede reclamarla (cuesta honor y rencor).
func _offer_trophy() -> void:
	var item := UniqueItems.carried_by(enemy_character)
	var taker: Character = _owner if _owner != null else player_character
	if item == null or taker == null or test_auto:
		return
	var o := _overlay()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "%s lleva %s" % [enemy_character.full_name(), item.equipment_name]
	title.add_theme_color_override("font_color", Color("f0c060"))
	o[1].add_child(title)
	_note(o[1], "%s\n\nReclamarla es tu derecho, pero no es de caballeros (−%d de honor) y %s no lo olvidará (+%d de rencor)." % [
		item.description, UniqueItems.TROPHY_HONOR_COST, enemy_character.full_name(), UniqueItems.TROPHY_GRUDGE])
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	o[1].add_child(row)
	var claim := Button.new()
	claim.text = "Reclamar el trofeo"
	claim.theme_type_variation = &"PrimaryButton"
	row.add_child(claim)
	var leave := Button.new()
	leave.text = "Dejarla estar"
	row.add_child(leave)
	claim.pressed.connect(func():
		var text := UniqueItems.claim_trophy(taker, enemy_character)
		CombatSetup.last_result_text = (CombatSetup.last_result_text + " " + text).strip_edges()
		_log(text)
		o[0].queue_free())
	leave.pressed.connect(func(): o[0].queue_free())
	leave.grab_focus.call_deferred()
