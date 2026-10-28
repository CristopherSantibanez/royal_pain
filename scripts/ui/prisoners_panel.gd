extends RefCounted
# Pestaña «Prisioneros» de Relaciones: tus presos (y qué hacer con ellos), tus siervos y los tuyos en
# manos ajenas. Uso: const PrisonersPanel = preload("res://scripts/ui/prisoners_panel.gd")
#   PrisonersPanel.fill(list, func(text: String): ...)   # on_result recibe el texto de lo ocurrido

const FACE_SIZE := 56

static func fill(list: VBoxContainer, on_result: Callable) -> void:
	var mine: Array = CaptureData.player_prisoners()
	var serfs: Array[String] = CaptureData.serfs
	var held: Array = CaptureData.held_own_people()
	if CaptureData.is_captive():
		_note(list, CaptureData.captive_text(), false)
	if mine.is_empty() and serfs.is_empty() and held.is_empty():
		_note(list, "Sin prisioneros.", true)
		return
	if not mine.is_empty():
		_note(list, "Tus prisioneros", false, &"BodyBoldLabel")
		for p: Dictionary in mine:
			_prisoner_row(list, p, on_result)
	if not serfs.is_empty():
		_note(list, "Tus siervos", false, &"BodyBoldLabel")
		for person_name: String in serfs:
			_serf_row(list, person_name, on_result)
	if not held.is_empty():
		_note(list, "Los tuyos, presos", false, &"BodyBoldLabel")
		for p: Dictionary in held:
			_held_row(list, p, on_result)

static func _note(list: VBoxContainer, text: String, muted: bool, variation: StringName = &"") -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.theme_type_variation = variation if variation != &"" else (&"MutedLabel" if muted else &"")
	list.add_child(l)

static func _row(list: VBoxContainer, r: Relationship, title: String, subtitle: String) -> HFlowContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	list.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	if r != null and r.character != null:
		row.add_child(FaceIcon.make(r.character, FACE_SIZE))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var name := Label.new()
	name.theme_type_variation = &"BodyBoldLabel"
	name.text = title
	col.add_child(name)
	var sub := Label.new()
	sub.theme_type_variation = &"MutedLabel"
	sub.text = subtitle
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	col.add_child(buttons)
	return buttons

static func _button(parent: Control, text: String, tooltip: String, blocker: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = blocker if not blocker.is_empty() else tooltip
	b.disabled = not blocker.is_empty()
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b

static func _who(r: Relationship) -> String:
	if r == null or r.character == null:
		return ""
	return "%s · %s" % [r.character.role_title(), DialogueCatalog.personality_name(r.character.personality)]

static func _prisoner_row(list: VBoxContainer, p: Dictionary, on_result: Callable) -> void:
	var r := CaptureData.relation_of(p)
	var months := GameManager.months_elapsed() - int(p.since)
	var sub := "%s · preso hace %d %s" % [_who(r), months, "mes" if months == 1 else "meses"]
	var buttons := _row(list, r, str(p.name), sub)
	_button(buttons, "Reclutar (%d%%)" % roundi(CaptureData.recruit_chance(p) * 100),
		"Te sirve en tu séquito si acepta. Una vez al mes.", CaptureData.recruit_blocker(p),
		func(): on_result.call(CaptureData.recruit(p)))
	_button(buttons, "Esclavizar", "Siervo: oro cada mes, sin plaza. −%d de honor; su reino se ofende." % CaptureData.ENSLAVE_HONOR,
		CaptureData.enslave_blocker(p), func(): on_result.call(CaptureData.enslave(p)))
	_button(buttons, "Vender a los suyos (%d)" % CaptureData.ransom_value(p), "Su gente paga el rescate.",
		CaptureData.ransom_blocker(p), func(): on_result.call(CaptureData.sell_to_faction(p)))
	_button(buttons, "Liberar", "+%d de honor." % CaptureData.FREE_HONOR, "", func(): on_result.call(CaptureData.free_prisoner(p)))
	# Ejecutar pide confirmación: el primer clic arma el botón.
	var exec := _button(buttons, "Ejecutar", "−%d de honor; su casa no lo olvidará." % CaptureData.EXECUTE_HONOR, "", Callable())
	exec.pressed.connect(func():
		if not exec.has_meta("armed"):
			exec.set_meta("armed", true)
			exec.text = "¿Ejecutar? Confirmar"
			return
		on_result.call(CaptureData.execute(p)))

static func _serf_row(list: VBoxContainer, person_name: String, on_result: Callable) -> void:
	var r := RelationsData.get_relation(person_name)
	if r == null:
		return
	var sub := "%s · %s · %d de oro al mes" % [_who(r), RelationsData.intimacy_label(r), CaptureData.serf_gold(r)]
	var buttons := _row(list, r, person_name, sub)
	_button(buttons, "Vender (%d)" % CaptureData.serf_price(r), "−%d de honor." % CaptureData.SERF_SELL_HONOR, "",
		func(): on_result.call(CaptureData.sell_serf(person_name)))
	_button(buttons, "Liberar", "+%d de honor y su gratitud." % CaptureData.MANUMIT_HONOR, "",
		func(): on_result.call(CaptureData.manumit(person_name)))

static func _held_row(list: VBoxContainer, p: Dictionary, on_result: Callable) -> void:
	var r := CaptureData.relation_of(p)
	var buttons := _row(list, r, str(p.name), "Preso de %s" % p.captor)
	var price := CaptureData.own_ransom(p)
	var blocker := "" if CaptureData._total_gold() >= price else "No tienes %d de oro." % price
	_button(buttons, "Pagar rescate (%d)" % price, "Con tu oro y el de tu castillo.", blocker,
		func(): on_result.call(CaptureData.pay_for_own(str(p.name))))
