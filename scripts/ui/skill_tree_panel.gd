extends Control
# Árbol de habilidades del combate RPG: los tres árboles del personaje (luchador, personalidad, alineamiento),
# cada uno con tres ramas. Aprender un nodo gasta puntos de árbol (SkillTreeCatalog).
# Uso: load("res://scripts/ui/skill_tree_panel.gd").open(nodo, personaje)

const TAB_NAMES := ["Combate", "Personalidad", "Alineación"]
const TIER_MARK := ["", "I", "II", "III", "IV"]
const LEARNED_COLOR := Color("d4af5a")
const LOCKED_ALPHA := 0.45

var character: Character
var _tabs: TabContainer
var _points: Label
var _hint: Label
var _confirm_row: HBoxContainer
var _confirm_label: Label
var _confirm_btn: Button
var _pending := ""
var _focus_id := ""

static func open(host: Node, c: Character) -> Control:
	var panel: Control = load("res://scripts/ui/skill_tree_panel.gd").new()
	panel.character = c
	host.add_child(panel)
	return panel

func _ready() -> void:
	if character == null:
		character = GameManager.player_character
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1060, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := _label("Habilidades de %s · nivel %d" % [character.full_name(), character.level], &"BodyBoldLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_points = _label("", &"BodyBoldLabel")
	_points.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(_points)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 370)
	_tabs.tab_changed.connect(func(_i: int): _focus_first_node())
	box.add_child(_tabs)

	_hint = _label("", &"MutedLabel")
	_hint.custom_minimum_size = Vector2(0, 66)
	box.add_child(_hint)

	_confirm_row = HBoxContainer.new()
	_confirm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_row.add_theme_constant_override("separation", 12)
	_confirm_row.visible = false
	box.add_child(_confirm_row)
	_confirm_label = _label("", &"BodyBoldLabel")
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_confirm_row.add_child(_confirm_label)
	_confirm_btn = Button.new()
	_confirm_btn.text = "Aprender"
	_confirm_btn.custom_minimum_size = Vector2(140, 0)
	_confirm_btn.pressed.connect(confirm_learn)
	_confirm_row.add_child(_confirm_btn)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.theme_type_variation = &"FlatButton"
	cancel.custom_minimum_size = Vector2(140, 0)
	cancel.pressed.connect(cancel_learn)
	_confirm_row.add_child(cancel)

	var close := Button.new()
	close.text = "Cerrar"
	close.theme_type_variation = &"FlatButton"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(180, 0)
	close.pressed.connect(queue_free)
	box.add_child(close)

	_rebuild()
	UiAnim.fade_in(panel, 0.15)
	_focus_first_node()

func _label(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		l.theme_type_variation = variation
	return l

# --- Construcción ---

func _rebuild() -> void:
	var current := _tabs.current_tab
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	var trees := SkillTreeCatalog.trees_for(character)
	for i in trees.size():
		_tabs.add_child(_tree_page(TAB_NAMES[i], trees[i]))
	_tabs.current_tab = clampi(current, 0, _tabs.get_tab_count() - 1)
	_points.text = "Puntos libres: %d" % SkillTreeCatalog.points_free(character)

func _tree_page(tab_name: String, tree_id: String) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 6)
	scroll.add_child(page)
	var t := SkillTreeCatalog.tree(tree_id)
	page.add_child(_label(t.get("name", tree_id), &"BodyBoldLabel"))
	var cols := HBoxContainer.new()
	cols.name = "Ramas"
	cols.add_theme_constant_override("separation", 12)
	page.add_child(cols)
	for br: Dictionary in t.get("branches", []):
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		cols.add_child(col)
		var bl := _label(br.name, &"MutedLabel")
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(bl)
		for id: String in br.nodes:
			col.add_child(_node_button(id))
	return scroll

func _node_button(id: String) -> Button:
	var n := SkillTreeCatalog.node(id)
	var b := Button.new()
	b.set_meta("skill_id", id)
	b.text = "%s · %s" % [TIER_MARK[clampi(int(n.tier), 0, 4)], n.name]
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size = Vector2(0, 34)
	b.clip_text = true
	b.focus_mode = Control.FOCUS_ALL
	if SkillTreeCatalog.knows(character, id):
		b.text = "★ " + b.text
		b.add_theme_color_override("font_color", LEARNED_COLOR)
		b.add_theme_color_override("font_focus_color", LEARNED_COLOR)
		b.add_theme_color_override("font_hover_color", LEARNED_COLOR)
	elif not SkillTreeCatalog.can_learn(character, id):
		b.modulate.a = LOCKED_ALPHA
	b.focus_entered.connect(func(): _show_hint(id))
	b.mouse_entered.connect(func(): _show_hint(id))
	b.pressed.connect(func(): request_learn(id))
	return b

# --- Texto de ayuda ---

func node_state(id: String) -> String:
	if SkillTreeCatalog.knows(character, id):
		return "aprendida"
	return "disponible" if SkillTreeCatalog.can_learn(character, id) else "bloqueada"

func _lock_reason(id: String) -> String:
	var n := SkillTreeCatalog.node(id)
	if SkillTreeCatalog.knows(character, id):
		return "Ya aprendida."
	if character.level < SkillTreeCatalog.required_level(n):
		return "Requiere nivel %d." % SkillTreeCatalog.required_level(n)
	var missing := []
	for r: String in n.req:
		if not SkillTreeCatalog.knows(character, r):
			missing.append(SkillTreeCatalog.node(r).get("name", r))
	if not missing.is_empty():
		return "Requiere %s." % ", ".join(missing)
	if not n.req_any.is_empty() and not n.req_any.any(func(r: String) -> bool: return SkillTreeCatalog.knows(character, r)):
		return "Requiere un básico de la rama."
	if SkillTreeCatalog.points_free(character) < SkillTreeCatalog.cost_for(character, id):
		return "Faltan puntos."
	return ""

func _show_hint(id: String) -> void:
	_focus_id = id
	var n := SkillTreeCatalog.node(id)
	if n.is_empty():
		return
	var parts := []
	if n.kind == "act":
		parts.append("Técnica · %d PT" % int(n.get("pt", 0)))
		if float(n.get("pow", 0.0)) > 0.0:
			var dt := int(n.get("dt", -1))
			parts.append("Daño: " + (RpgStats.DAMAGE_NAMES[dt] if dt >= 0 and dt < RpgStats.DAMAGE_NAMES.size() else "el del arma"))
	else:
		parts.append("Pasiva")
	var cost := SkillTreeCatalog.cost_for(character, id)
	parts.append("Coste: gratis" if cost == 0 else "Coste: %d punto%s" % [cost, "" if cost == 1 else "s"])
	var reqs := []
	for r: String in n.req:
		reqs.append(SkillTreeCatalog.node(r).get("name", r))
	if not n.req_any.is_empty():
		reqs.append("un básico de la rama")
	if not reqs.is_empty():
		parts.append("Requiere: " + ", ".join(reqs))
	parts.append("Nivel %d" % SkillTreeCatalog.required_level(n))
	var state := node_state(id)
	var tail := "Aprendida." if state == "aprendida" else ("Pulsa para aprender." if state == "disponible" else _lock_reason(id))
	_hint.text = "%s — %s\n%s · %s" % [n.name, n.desc, " · ".join(parts), tail]

# --- Aprender ---

func request_learn(id: String) -> void:
	_show_hint(id)
	if not SkillTreeCatalog.can_learn(character, id):
		_confirm_row.visible = false
		_pending = ""
		return
	_pending = id
	var cost := SkillTreeCatalog.cost_for(character, id)
	_confirm_label.text = "¿Aprender «%s» por %s?" % [SkillTreeCatalog.node(id).name, "nada" if cost == 0 else "%d punto%s" % [cost, "" if cost == 1 else "s"]]
	_confirm_row.visible = true
	_focus_later(_confirm_btn)

func confirm_learn() -> bool:
	var id := _pending
	cancel_learn(false)
	if id == "" or not SkillTreeCatalog.learn(character, id):
		return false
	_rebuild()
	_hint.text = "Aprendes «%s»." % SkillTreeCatalog.node(id).name
	_refocus(id)
	return true

func cancel_learn(refocus := true) -> void:
	var id := _pending
	_pending = ""
	_confirm_row.visible = false
	if refocus and id != "":
		_refocus(id)

func _refocus(id: String) -> void:
	for b in _buttons():
		if b.get_meta("skill_id") == id:
			_focus_later(b)
			return

func _buttons() -> Array:
	var out := []
	var page := _tabs.get_current_tab_control()
	if page == null:
		return out
	var stack := [page]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and n.has_meta("skill_id") and not n.is_queued_for_deletion():
			out.append(n)
		stack.append_array(n.get_children())
	out.sort_custom(func(a: Button, b: Button) -> bool: return a.get_index() < b.get_index() if a.get_parent() == b.get_parent() else a.get_parent().get_index() < b.get_parent().get_index())
	return out

func _focus_first_node() -> void:
	var list := _buttons()
	if not list.is_empty():
		_focus_later(list[0])

func _focus_later(c: Control) -> void:
	(func(): if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree(): c.grab_focus()).call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _confirm_row.visible:
			cancel_learn()
		else:
			queue_free()
		return
	var step := 0
	if event is InputEventKey and event.pressed and not event.echo:
		step = -1 if event.keycode == KEY_Q else (1 if event.keycode == KEY_E else 0)
	elif event is InputEventJoypadButton and event.pressed:
		step = -1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else (1 if event.button_index == JOY_BUTTON_RIGHT_SHOULDER else 0)
	if step != 0 and _tabs.get_tab_count() > 0:
		get_viewport().set_input_as_handled()
		_tabs.current_tab = posmod(_tabs.current_tab + step, _tabs.get_tab_count())
