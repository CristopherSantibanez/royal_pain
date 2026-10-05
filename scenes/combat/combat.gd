extends Control

@export var player_character: Character
@export var enemy_character: Character

@onready var name_player: Label = $ScreenMargin/MainHBox/PlayerColumn/NamePlayer
@onready var portrait_player: TextureRect = $ScreenMargin/MainHBox/PlayerColumn/PortraitPlayer
@onready var health_bar_player: ProgressBar = $ScreenMargin/MainHBox/PlayerColumn/HealthBarPlayer
@onready var stamina_bar_player: ProgressBar = $ScreenMargin/MainHBox/PlayerColumn/StaminaBarPlayer
@onready var morale_bar_player: ProgressBar = $ScreenMargin/MainHBox/PlayerColumn/MoraleBarPlayer
@onready var status_player: Label = $ScreenMargin/MainHBox/PlayerColumn/StatusPlayer
@onready var posture_player: Label = $ScreenMargin/MainHBox/PlayerColumn/PosturePlayer

@onready var btn_volver_menu: Button = $ScreenMargin/MainHBox/CenterColumn/BtnVolverMenu

@onready var name_enemy: Label = $ScreenMargin/MainHBox/EnemyColumn/NameEnemy
@onready var portrait_enemy: TextureRect = $ScreenMargin/MainHBox/EnemyColumn/PortraitEnemy
@onready var health_bar_enemy: ProgressBar = $ScreenMargin/MainHBox/EnemyColumn/HealthBarEnemy
@onready var stamina_bar_enemy: ProgressBar = $ScreenMargin/MainHBox/EnemyColumn/StaminaBarEnemy
@onready var morale_bar_enemy: ProgressBar = $ScreenMargin/MainHBox/EnemyColumn/MoraleBarEnemy
@onready var status_enemy: Label = $ScreenMargin/MainHBox/EnemyColumn/StatusEnemy
@onready var posture_enemy: Label = $ScreenMargin/MainHBox/EnemyColumn/PostureEnemy

@onready var log_label: Label = $ScreenMargin/MainHBox/CenterColumn/LogLabel

@onready var turn_indicator_label: Label = $ScreenMargin/MainHBox/CenterColumn/TurnIndicatorLabel


var duel: DuelManager
var player_turn := true
const ENEMY_TURN_DELAY := 1.2  # segundos de pausa antes de que el enemigo actúe
var current_round_log := ""  # Acumula los mensajes de la ronda actual (jugador + enemigo)

# --- Duelo de campaña ---
var is_campaign := false
var _honor_before := 0
var _gold_before := 0
var _demotion_text := ""

func _ready() -> void:
	if player_character == null:
		player_character = CombatSetup.player_character if CombatSetup.player_character != null \
			else CharacterLoader.make_test_character("Sir Alaric", Character.Role.CABALLERO)
	if enemy_character == null:
		enemy_character = CombatSetup.enemy_character if CombatSetup.enemy_character != null \
			else CharacterLoader.make_test_character("Bandido Renco", Character.Role.SOLDADO)

	duel = DuelManager.new()
	duel.log_message.connect(_on_log_message)
	duel.duel_ended.connect(_on_duel_ended)
	duel.state_updated.connect(_refresh_ui)
	duel.character_demoted.connect(_on_character_demoted)
	duel.start_duel(player_character, enemy_character)

	_connect_buttons()
	_refresh_ui()
	_update_turn_indicator()

	is_campaign = CombatSetup.is_campaign
	if is_campaign:
		_honor_before = player_character.honor
		_gold_before = player_character.gold
		# En campaña no se puede abandonar a mitad: para salir hay que rendirse o retirarse.
		btn_volver_menu.text = "Volver al Castillo"
		btn_volver_menu.disabled = true
		btn_volver_menu.tooltip_text = "Termina el duelo (o ríndete / retírate) para volver."
	# ------------------------------------------------------------------------------------

func _connect_buttons() -> void:
	$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow1/BtnOfensiva.pressed.connect(func(): _player_posture(CombatEnums.Posture.OFENSIVA))
	$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow1/BtnDefensiva.pressed.connect(func(): _player_posture(CombatEnums.Posture.DEFENSIVA))
	$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow1/BtnEsgrima.pressed.connect(func(): _player_posture(CombatEnums.Posture.ESGRIMA))
	$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow2/BtnMuro.pressed.connect(func(): _player_posture(CombatEnums.Posture.MURO))
	$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow2/BtnDesesperada.pressed.connect(func(): _player_posture(CombatEnums.Posture.DESESPERADA))

	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow1/BtnAtacar.pressed.connect(func(): _player_action(CombatEnums.ActionType.ATACAR))
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow1/BtnDefender.pressed.connect(func(): _player_action(CombatEnums.ActionType.DEFENDER))
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow1/BtnEsquivar.pressed.connect(func(): _player_action(CombatEnums.ActionType.ESQUIVAR))
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow1/BtnContraatacar.pressed.connect(func(): _player_action(CombatEnums.ActionType.CONTRAATACAR))
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow2/BtnDesarmar.pressed.connect(func(): _player_action(CombatEnums.ActionType.DESARMAR))
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow2/BtnEmpujar.pressed.connect(func(): _player_action(CombatEnums.ActionType.EMPUJAR))
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow2/BtnRendirse.pressed.connect(func(): _player_action(CombatEnums.ActionType.RENDIRSE))
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow2/BtnRetirarse.pressed.connect(func(): _player_action(CombatEnums.ActionType.RETIRARSE))
	btn_volver_menu.pressed.connect(_on_volver_menu_pressed)
	_set_tooltips()

func _set_tooltips() -> void:
	$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow1/BtnOfensiva.tooltip_text = "Aumenta tu daño de ataque, pero te deja más vulnerable a recibir golpes."
	$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow1/BtnDefensiva.tooltip_text = "Reduce el daño que recibes, a cambio de menor poder ofensivo."
	$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow1/BtnEsgrima.tooltip_text = "Prioriza la evasión y la agilidad sobre la fuerza bruta."
	$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow2/BtnMuro.tooltip_text = "Defensa máxima. Ideal para resistir, pero casi no aporta al ataque."
	$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow2/BtnDesesperada.tooltip_text = "Último recurso: gran daño ofensivo, pero tu defensa cae drásticamente."

	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow1/BtnAtacar.tooltip_text = "Golpea al oponente. Falla si estás desarmado."
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow1/BtnDefender.tooltip_text = "Te pones en guardia, reduciendo el daño del próximo ataque que recibas."
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow1/BtnEsquivar.tooltip_text = "Te preparas para esquivar el próximo ataque, con posibilidad de evitarlo por completo."
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow1/BtnContraatacar.tooltip_text = "Adoptas guardia de contraataque: si el enemigo te ataca, le devuelves parte del daño."
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow2/BtnDesarmar.tooltip_text = "Intentas desarmar al oponente, dejándolo incapaz de atacar por un par de turnos."
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow2/BtnEmpujar.tooltip_text = "Empujas al oponente, reduciendo su resistencia y moral si tienes éxito."
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow2/BtnRendirse.tooltip_text = "Terminas el duelo inmediatamente. El oponente gana."
	$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow2/BtnRetirarse.tooltip_text = "Intentas huir del combate. Puede fallar si el oponente te lo impide."


func _player_posture(p: int) -> void:
	if not player_turn or duel.is_over:
		return
	duel.set_posture(player_character, p)
	_refresh_ui()

func _player_action(action: int) -> void:
	if not player_turn or duel.is_over:
		return
	_start_new_turn_log()
	duel.take_turn(player_character, action)
	_refresh_ui()
	if not duel.is_over:
		_set_buttons_enabled(false)
		_update_turn_indicator()
		await get_tree().create_timer(ENEMY_TURN_DELAY).timeout
		_enemy_turn()

func _enemy_turn() -> void:
	player_turn = false
	if duel.is_over:
		_set_buttons_enabled(false)
		return

	_start_new_turn_log()

	var chosen_posture := CombatEnums.Posture.OFENSIVA
	if CombatEnums.Status.HERIDO in duel.statuses[enemy_character]:
		chosen_posture = CombatEnums.Posture.DEFENSIVA
	duel.set_posture(enemy_character, chosen_posture)

	var action := CombatEnums.ActionType.ATACAR
	if CombatEnums.Status.HERIDO in duel.statuses[enemy_character] and randf() < 0.5:
		action = CombatEnums.ActionType.DEFENDER
	duel.take_turn(enemy_character, action)

	player_turn = true
	_refresh_ui()
	_set_buttons_enabled(true)
	_update_turn_indicator()

func _refresh_ui() -> void:
	name_player.text = player_character.full_name()
	health_bar_player.value = player_character.current_health
	health_bar_player.max_value = player_character.max_health
	stamina_bar_player.value = player_character.current_stamina
	stamina_bar_player.max_value = player_character.max_stamina
	morale_bar_player.value = player_character.current_morale
	morale_bar_player.max_value = player_character.max_morale
	status_player.text = _status_text(duel.statuses.get(player_character, []))
	posture_player.text = "Postura: " + CombatEnums.posture_name(duel.posture.get(player_character, CombatEnums.Posture.DEFENSIVA))
	portrait_player.texture = player_character.get_portrait()


	name_enemy.text = enemy_character.full_name()
	health_bar_enemy.value = enemy_character.current_health
	health_bar_enemy.max_value = enemy_character.max_health
	stamina_bar_enemy.value = enemy_character.current_stamina
	portrait_enemy.texture = enemy_character.get_portrait()
	stamina_bar_enemy.max_value = enemy_character.max_stamina
	morale_bar_enemy.value = enemy_character.current_morale
	morale_bar_enemy.max_value = enemy_character.max_morale
	status_enemy.text = _status_text(duel.statuses.get(enemy_character, []))
	posture_enemy.text = "Postura: " + CombatEnums.posture_name(duel.posture.get(enemy_character, CombatEnums.Posture.DEFENSIVA))

func _status_text(statuses: Array) -> String:
	if statuses.is_empty():
		return "Normal"
	var names := []
	for s in statuses:
		names.append(CombatEnums.Status.keys()[s])
	return ", ".join(names)

var turn_log_buffer: String = ""

func _on_log_message(text: String) -> void:
	if turn_log_buffer.is_empty():
		turn_log_buffer = text
	else:
		turn_log_buffer += "\n" + text
	log_label.text = turn_log_buffer

func _start_new_turn_log() -> void:
	turn_log_buffer = ""

func _on_duel_ended(winner: Character, reason: String) -> void:
	var winner_name := winner.full_name() if winner != null else "Nadie (huida)"
	turn_log_buffer += "\n DUELO TERMINADO Ganador: %s" % winner_name
	log_label.text = turn_log_buffer

	if is_campaign:
		CombatSetup.last_result_text = _campaign_summary(winner)
		btn_volver_menu.disabled = false
		btn_volver_menu.tooltip_text = ""

func _campaign_summary(winner: Character) -> String:
	var outcome: String
	if winner == player_character:
		outcome = "Venciste en duelo a %s." % enemy_character.full_name()
	elif winner == null:
		outcome = "El duelo contra %s terminó con una huida." % enemy_character.full_name()
	else:
		outcome = "%s te derrotó en duelo." % enemy_character.full_name()
	var text := "%s Honor %+d, oro %+d. Duelos: %d ganados / %d perdidos." % [
		outcome, player_character.honor - _honor_before, player_character.gold - _gold_before,
		player_character.duels_won, player_character.duels_lost]
	if not _demotion_text.is_empty():
		text += " " + _demotion_text
	return text

func _on_character_demoted(character: Character, old_role: int, new_role: int) -> void:
	# El mensaje ya queda en el log mediante log_message; en campaña además se
	# guarda para mostrarlo al volver al castillo.
	if is_campaign and character == player_character:
		_demotion_text = "Caes en deshonra: de %s a %s." % [Character.role_name_for(old_role), Character.role_name_for(new_role)]

func _on_volver_menu_pressed() -> void:
	if is_campaign:
		# Aún no hay sistema de heridas: el personaje se recupera por completo tras el duelo.
		player_character.current_health = player_character.max_health
		player_character.current_stamina = player_character.max_stamina
		player_character.current_morale = player_character.max_morale
		var scene := CombatSetup.return_scene
		CombatSetup.clear()
		get_tree().change_scene_to_file(scene)
		return
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _set_buttons_enabled(enabled: bool) -> void:
	var buttons: Array[Button] = [
		$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow1/BtnOfensiva,
		$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow1/BtnDefensiva,
		$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow1/BtnEsgrima,
		$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow2/BtnMuro,
		$ScreenMargin/MainHBox/CenterColumn/PostureBox/PostureRow2/BtnDesesperada,
		$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow1/BtnAtacar,
		$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow1/BtnDefender,
		$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow1/BtnEsquivar,
		$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow1/BtnContraatacar,
		$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow2/BtnDesarmar,
		$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow2/BtnEmpujar,
		$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow2/BtnRendirse,
		$ScreenMargin/MainHBox/CenterColumn/ActionBox/ActionRow2/BtnRetirarse,
	]
	for b in buttons:
		b.disabled = not enabled

func _update_turn_indicator() -> void:
	if duel.is_over:
		return
	if player_turn:
		turn_indicator_label.text = "Tu turno"
	else:
		turn_indicator_label.text = "Turno de %s..." % enemy_character.full_name()
