extends SceneTree
# Teclado en el mapa, armería (compra/venta con bonos) y crónica completa.

func _initialize() -> void:
	_run.call_deferred()

func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	await process_frame

func _run() -> void:
	var GM = root.get_node("GameManager")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	player.gold = 3000
	GM.start_new_game(player, root.get_node("MapData").castles[0].castle_id)

	# --- Crónica: 12 meses de noticias ---
	for m in 12:
		GM.pending_event = {}
		GM.advance_turn()
	var WE = root.get_node("WorldEvents")
	print("Crónica tras 12 meses: %d entradas (mes de la primera: %d/%d)" % [WE.chronicle.size(),
		WE.chronicle[0].m if not WE.chronicle.is_empty() else 0, WE.chronicle[0].y if not WE.chronicle.is_empty() else 0])
	GM.pending_event = {}

	# --- Mapa con teclado ---
	change_scene_to_file("res://scenes/map/map.tscn")
	await create_timer(0.8).timeout
	var map = current_scene
	var focus = root.gui_get_focus_owner()
	print("Foco inicial en el mapa: ", focus.text if focus is Button else focus)
	var closed := 0
	while map.event_overlay.visible and closed < 20:
		await _press("ui_accept")
		closed += 1
	print("Noticias cerradas con Intro/A: ", closed, " · foco ahora: ", root.gui_get_focus_owner().text if root.gui_get_focus_owner() is Button else root.gui_get_focus_owner())
	await _press("map_next_castle")
	focus = root.gui_get_focus_owner()
	print("Tras Tab: ficha abierta=%s, castillo=%s, foco=%s" % [map.castle_details_panel.visible,
		map.selected_castle.castle_name if map.selected_castle else "-", focus.text if focus is Button else focus])
	await _press("ui_cancel")
	print("Tras Esc: ficha abierta=", map.castle_details_panel.visible)
	var cam_before: Vector2 = map.camera.position
	Input.action_press("cam_right")
	await create_timer(0.3).timeout
	Input.action_release("cam_right")
	print("Cámara con D/stick: se movió %.0f px" % (map.camera.position.x - cam_before.x))

	# --- Armería ---
	var Shop = load("res://scripts/ui/shop_panel.gd")
	var stock: Array = Shop.monthly_stock(player, GM.home_castle_id)
	print("Surtido (%d): %s" % [stock.size(), ", ".join(stock.map(func(e): return "%s %s %d" % [e.slot, "★".repeat(e.tier), e.price]))])
	var item = null
	for e in stock:
		if e.combat_mod != 0 or e.defense_mod != 0:
			item = e
			break
	if item == null:
		item = stock[0]
	var before := "C%d D%d oro %d piezas %d" % [player.combat, player.defense, player.gold, player.equipment.size()]
	var shop = Shop.open(map)
	await process_frame
	shop._buy(item)
	var after := "C%d D%d oro %d piezas %d" % [player.combat, player.defense, player.gold, player.equipment.size()]
	print("Compra %s (C%+d D%+d): %s -> %s" % [item.equipment_name, item.combat_mod, item.defense_mod, before, after])
	var bought = null
	for e in player.equipment:
		if e.equipment_name == item.equipment_name:
			bought = e
	shop._sell(bought)
	print("Venta: C%d D%d oro %d piezas %d" % [player.combat, player.defense, player.gold, player.equipment.size()])
	quit()
