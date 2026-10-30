extends SceneTree
var fails := 0
func check(c: bool, w: String) -> void:
	print(("  ok  " if c else "  FALLA ") + w)
	if not c: fails += 1
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var ST = root.get_node("Settings")
	var host := Control.new()
	root.add_child(host)
	var n := Control.new()
	host.add_child(n)
	n.position = Vector2(100, 100)
	ST.set_shake_level(0)
	CombatFx.shake(n, 20.0, 0.2)
	await create_timer(0.05).timeout
	check(n.position == Vector2(100, 100), "sin sacudida: no se mueve")
	ST.set_shake_level(2)
	CombatFx.shake(n, 20.0, 0.2)
	await create_timer(0.05).timeout
	CombatFx.shake(n, 20.0, 0.2)   # una segunda antes de acabar la primera
	await create_timer(0.5).timeout
	check(n.position == Vector2(100, 100), "dos sacudidas seguidas: vuelve a su sitio (%s)" % n.position)
	ST.set_reduced_effects(true)
	CombatFx.hit_stop(self, 0.1)
	check(Engine.time_scale == 1.0, "efectos reducidos: sin pausa de impacto")
	CombatFx.sparks(host, Vector2.ZERO)
	check(host.get_children().filter(func(c): return c is CPUParticles2D).is_empty(), "efectos reducidos: sin chispas")
	ST.set_reduced_effects(false)
	CombatFx.hit_stop(self, 5.0)   # se recorta a MAX_HIT_STOP
	check(Engine.time_scale < 1.0, "pausa de impacto activa")
	await create_timer(0.2, true, false, true).timeout
	check(Engine.time_scale == 1.0, "la pausa no dura más de %.2fs" % CombatFx.MAX_HIT_STOP)
	check(CombatFx.tier_for(3) == 0 and CombatFx.tier_for(10) == 1 and CombatFx.tier_for(30) == 2, "niveles por daño")
	ST.set_shake_level(2)
	print("FALLAS: ", fails)
	quit(fails)
